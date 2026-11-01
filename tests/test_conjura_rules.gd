extends TestCase
## Reglas de La Conjura: reparto, nominación, votación, legislatura, crisis,
## poderes y condiciones de victoria.

const G := preload("res://games/conjura/logic/conjura_game.gd")
const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Edict := ConjuraDefs.Edict
const Power := ConjuraDefs.Power


func _game(n: int = 5, seed: int = 42) -> ConjuraGame:
	var players: Array[PlayerInfo] = []
	for i in n:
		players.append(PlayerInfo.new(i, "", PlayerInfo.default_color(i)))
	var game := ConjuraGame.new()
	game.setup(players, seed)
	return game


func _do(game: ConjuraGame, type: StringName, pid: int, data: Dictionary = {}) -> String:
	return game.submit(GameAction.new(type, pid, data))


## Todos los vivos votan lo mismo.
func _vote_all(game: ConjuraGame, yes: bool) -> void:
	for pid in game.alive_ids():
		_do(game, G.VOTE, pid, {"yes": yes})


## Primer jugador que el Regente puede nominar.
func _nominate_any(game: ConjuraGame) -> int:
	var target: int = game.eligible_nominees()[0]
	assert_eq(_do(game, G.NOMINATE, game.regent, {"target": target}), "")
	return target


## Gobierno completo que promulga `edict` (lo pone arriba del mazo).
func _govern(game: ConjuraGame, edict: int) -> void:
	game.draw_pile.push_front(edict)
	game.draw_pile.push_front(edict)
	game.draw_pile.push_front(edict)
	_nominate_any(game)
	_vote_all(game, true)
	assert_eq(_do(game, G.DISCARD, game.regent, {"index": 0}), "")
	assert_eq(_do(game, G.ENACT, game.council, {"index": 0}), "")


## Pone el rol de cada jugador a mano: [rol0, rol1, ...].
func _set_roles(game: ConjuraGame, roles: Array) -> void:
	for i in roles.size():
		game.roles[i] = roles[i]


func test_role_distribution() -> void:
	for n in range(5, 11):
		var game := _game(n, n)
		var counts := {Role.GUARDIA: 0, Role.SOMBRA: 0, Role.USURPADOR: 0}
		for r in game.roles:
			counts[r] += 1
		assert_eq(counts[Role.GUARDIA], D.ROLE_TABLE[n][0], "guardias con %d" % n)
		assert_eq(counts[Role.SOMBRA], D.ROLE_TABLE[n][1], "sombras con %d" % n)
		assert_eq(counts[Role.USURPADOR], 1, "usurpador con %d" % n)
		assert_true(counts[Role.GUARDIA] > counts[Role.SOMBRA] + 1, "la Guardia es mayoría con %d" % n)


func test_decks() -> void:
	var game := _game()
	assert_eq(game.draw_pile.size(), 19)
	assert_eq(game.draw_pile.count(Edict.NEUTRAL), 3)
	assert_eq(game.power_deck.size(), 11)
	assert_eq(game.phase, G.Phase.NOMINATE)


func test_nomination_rules() -> void:
	var game := _game()
	var r := game.regent
	var other := (r + 1) % 5
	assert_ne(_do(game, G.NOMINATE, other, {"target": r}), "", "solo nomina el Regente")
	assert_ne(_do(game, G.NOMINATE, r, {"target": r}), "", "no puede nominarse a sí mismo")
	game.last_council = other
	assert_ne(_do(game, G.NOMINATE, r, {"target": other}), "", "el último Consejero no repite")
	assert_eq(_do(game, G.NOMINATE, r, {"target": (r + 2) % 5}), "")
	assert_eq(game.phase, G.Phase.VOTE)


func test_vote_needs_strict_majority() -> void:
	var game := _game(6)
	_nominate_any(game)
	var ids := game.alive_ids()
	for i in ids.size():
		_do(game, G.VOTE, ids[i], {"yes": i < 3})
	assert_eq(game.phase, G.Phase.NOMINATE, "3 a 3 no aprueba")
	assert_eq(game.crisis, 1)
	assert_eq(game.last_votes.size(), 6)
	assert_false(game.governments[-1]["approved"])


func test_cannot_vote_twice() -> void:
	var game := _game()
	_nominate_any(game)
	assert_eq(_do(game, G.VOTE, 0, {"yes": true}), "")
	assert_ne(_do(game, G.VOTE, 0, {"yes": false}), "")


func test_regent_rotates_after_failed_vote() -> void:
	var game := _game()
	var first := game.regent
	_nominate_any(game)
	_vote_all(game, false)
	assert_eq(game.regent, (first + 1) % 5)


func test_legislation_flow() -> void:
	var game := _game()
	game.draw_pile.push_front(Edict.NEUTRAL)
	game.draw_pile.push_front(Edict.GUARDIA)
	game.draw_pile.push_front(Edict.SOMBRA)
	var regent := game.regent
	var target := _nominate_any(game)
	_vote_all(game, true)
	assert_eq(game.phase, G.Phase.REGENT_DISCARD)
	assert_eq(game.council, target)
	assert_eq(game.hand, [Edict.SOMBRA, Edict.GUARDIA, Edict.NEUTRAL] as Array[int])
	assert_ne(_do(game, G.DISCARD, target, {"index": 0}), "", "el Consejero no descarta")
	assert_eq(_do(game, G.DISCARD, regent, {"index": 0}), "")
	assert_eq(game.phase, G.Phase.COUNCIL_ENACT)
	assert_eq(game.hand.size(), 2)
	assert_eq(_do(game, G.ENACT, target, {"index": 0}), "")
	assert_eq(game.guardia_edicts, 1)
	assert_eq(game.discard_pile.size(), 2)
	assert_eq(game.last_council, target)
	assert_eq(game.phase, G.Phase.NOMINATE)
	assert_eq(game.draw_pile.size() + game.discard_pile.size() + game.guardia_edicts, 22, "19 + los 3 añadidos")


func test_neutral_raises_discontent() -> void:
	var game := _game()
	_govern(game, Edict.NEUTRAL)
	assert_eq(game.discontent, 1)
	assert_eq(game.guardia_edicts + game.sombra_edicts, 0)


func test_crisis_enacts_top_card() -> void:
	var game := _game()
	game.last_council = 3
	game.draw_pile.push_front(Edict.GUARDIA)
	for i in 3:
		_nominate_any(game)
		_vote_all(game, false)
	assert_eq(game.crisis, 0)
	assert_eq(game.guardia_edicts, 1)
	assert_eq(game.discontent, 1, "la crisis sube el descontento")
	assert_eq(game.last_council, -1, "la crisis borra el límite de mandatos")
	assert_true(game.governments[-1]["crisis"])


func test_crisis_never_grants_powers() -> void:
	var game := _game()
	game.sombra_edicts = 3
	game.draw_pile.push_front(Edict.SOMBRA)
	for i in 3:
		_nominate_any(game)
		_vote_all(game, false)
	assert_eq(game.sombra_edicts, 4)
	assert_eq(game.phase, G.Phase.NOMINATE)


func test_approval_resets_crisis() -> void:
	var game := _game()
	_nominate_any(game)
	_vote_all(game, false)
	assert_eq(game.crisis, 1)
	_govern(game, Edict.GUARDIA)
	assert_eq(game.crisis, 0)


func test_reshuffle_when_deck_is_short() -> void:
	var game := _game()
	game.discard_pile.append_array(game.draw_pile.slice(2))
	game.draw_pile = game.draw_pile.slice(0, 2)
	_nominate_any(game)
	_vote_all(game, true)
	assert_eq(game.hand.size(), 3)
	assert_eq(game.draw_pile.size() + game.hand.size(), 19)
	assert_eq(game.discard_pile.size(), 0)


func test_first_sombra_edict_has_no_power() -> void:
	var game := _game()
	_govern(game, Edict.SOMBRA)
	assert_eq(game.sombra_edicts, 1)
	assert_eq(game.phase, G.Phase.NOMINATE)


func test_second_sombra_edict_offers_two_powers() -> void:
	var game := _game()
	game.sombra_edicts = 1
	_govern(game, Edict.SOMBRA)
	assert_eq(game.phase, G.Phase.CHOOSE_POWER)
	assert_eq(game.power_options.size(), 2)
	assert_ne(game.power_options[0], game.power_options[1], "dos poderes distintos")
	assert_eq(game.power_deck.size(), 9)
	var council := game.council
	assert_ne(_do(game, G.CHOOSE_POWER, game.regent, {"index": 0}), "", "elige el Consejero, no el Regente")
	assert_eq(_do(game, G.CHOOSE_POWER, council, {"index": 1}), "")
	assert_eq(game.phase, G.Phase.USE_POWER)
	assert_eq(game.power_deck.size(), 10, "el poder no elegido vuelve al mazo")


func _force_power(game: ConjuraGame, power: int) -> int:
	game.sombra_edicts = 1
	game.power_deck.push_front(Power.PESQUISA)
	game.power_deck.push_front(power)
	_govern(game, Edict.SOMBRA)
	var council := game.council
	assert_eq(_do(game, G.CHOOSE_POWER, council, {"index": 0}), "")
	return council


func test_power_spy() -> void:
	var game := _game()
	_set_roles(game, [Role.GUARDIA, Role.GUARDIA, Role.SOMBRA, Role.GUARDIA, Role.USURPADOR])
	var council := _force_power(game, Power.ESPIAR)
	assert_ne(_do(game, G.USE_POWER, council, {"target": council}), "", "no puede espiarse a sí mismo")
	var target := 4 if council != 4 else 2
	assert_eq(_do(game, G.USE_POWER, council, {"target": target}), "")
	var k: Dictionary = game.knowledge[council][-1]
	assert_eq(k["kind"], "faction")
	assert_eq(k["faction"], ConjuraDefs.Faction.SOMBRA, "el Usurpador aparece como Sombra")
	assert_eq(game.phase, G.Phase.NOMINATE)


func test_power_augury_and_inquiry() -> void:
	var game := _game()
	var council := _force_power(game, Power.AUGURIO)
	assert_ne(_do(game, G.USE_POWER, council, {"target": 1}), "", "el Augurio no lleva objetivo")
	assert_eq(_do(game, G.USE_POWER, council, {"target": -1}), "")
	assert_eq(game.knowledge[council][-1]["kind"], "top")
	assert_eq(game.knowledge[council][-1]["cards"], game.draw_pile.slice(0, 3))

	var game2 := _game()
	var council2 := _force_power(game2, Power.PESQUISA)
	assert_eq(_do(game2, G.USE_POWER, council2, {"target": -1}), "")
	assert_eq(game2.knowledge[council2][-1]["card"], Edict.SOMBRA)


func test_power_succession() -> void:
	var game := _game()
	var regent := game.regent
	var council := _force_power(game, Power.SUCESION)
	var chosen := (regent + 3) % 5
	if chosen == council:
		chosen = (regent + 4) % 5
	assert_eq(_do(game, G.USE_POWER, council, {"target": chosen}), "")
	assert_eq(game.regent, chosen)
	# Después, el orden normal sigue desde el Regente anterior.
	_nominate_any(game)
	_vote_all(game, false)
	assert_eq(game.regent, (regent + 1) % 5)


func test_power_banish() -> void:
	var game := _game()
	_set_roles(game, [Role.GUARDIA, Role.GUARDIA, Role.GUARDIA, Role.SOMBRA, Role.USURPADOR])
	var council := _force_power(game, Power.DESTIERRO)
	var target := 0 if council != 0 else 1
	assert_eq(_do(game, G.USE_POWER, council, {"target": target}), "")
	assert_false(game.alive[target])
	assert_false(game.finished)
	assert_ne(_do(game, G.VOTE, target, {"yes": true}), "", "los desterrados no votan")
	assert_false(target in game.eligible_nominees())
	assert_eq(game.alive_ids().size(), 4)


func test_guardia_wins_with_five_edicts() -> void:
	var game := _game()
	game.guardia_edicts = 4
	_govern(game, Edict.GUARDIA)
	assert_true(game.finished)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.GUARDIA)
	for pid in game.winner_ids:
		assert_eq(game.roles[pid], Role.GUARDIA)


func test_sombra_wins_with_six_edicts() -> void:
	var game := _game()
	game.sombra_edicts = 5
	_govern(game, Edict.SOMBRA)
	assert_true(game.finished)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.SOMBRA)
	assert_eq(game.winner_ids.size(), 2)


func test_usurper_elected_council_wins() -> void:
	var game := _game()
	var r := game.regent
	var target := (r + 1) % 5
	game.roles[target] = Role.USURPADOR
	game.sombra_edicts = 3
	_do(game, G.NOMINATE, r, {"target": target})
	_vote_all(game, true)
	assert_true(game.finished)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.SOMBRA)


func test_usurper_elected_early_is_not_a_win() -> void:
	var game := _game()
	var r := game.regent
	var target := (r + 1) % 5
	game.roles[target] = Role.USURPADOR
	game.sombra_edicts = 2
	_do(game, G.NOMINATE, r, {"target": target})
	_vote_all(game, true)
	assert_false(game.finished)


func test_banishing_usurper_wins_for_guardia() -> void:
	var game := _game()
	var council := _force_power(game, Power.DESTIERRO)
	_set_roles(game, [Role.GUARDIA, Role.GUARDIA, Role.GUARDIA, Role.SOMBRA, Role.GUARDIA])
	var target := (council + 1) % 5
	game.roles[target] = Role.USURPADOR
	assert_eq(_do(game, G.USE_POWER, council, {"target": target}), "")
	assert_true(game.finished)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.GUARDIA)


func test_discontent_win_goes_to_fewer_edicts() -> void:
	var game := _game()
	game.discontent = 3
	game.guardia_edicts = 1
	game.sombra_edicts = 3
	_govern(game, Edict.NEUTRAL)
	assert_true(game.finished)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.GUARDIA)

	var game2 := _game()
	game2.discontent = 3
	game2.guardia_edicts = 3
	game2.sombra_edicts = 1
	_govern(game2, Edict.NEUTRAL)
	assert_eq(game2.winner_faction, ConjuraDefs.Faction.SOMBRA)


func test_discontent_tie_goes_to_guardia() -> void:
	var game := _game()
	game.discontent = 3
	game.guardia_edicts = 2
	game.sombra_edicts = 2
	_govern(game, Edict.NEUTRAL)
	assert_eq(game.winner_faction, ConjuraDefs.Faction.GUARDIA)


func test_finished_game_rejects_actions() -> void:
	var game := _game()
	game.guardia_edicts = 4
	_govern(game, Edict.GUARDIA)
	assert_ne(_do(game, G.NOMINATE, game.regent, {"target": 0}), "")


func test_save_and_replay_is_identical() -> void:
	var game := _game(7, 99)
	for i in 30:
		if game.finished:
			break
		var pid: int = game.players_to_act()[0]
		var legal := game.get_legal_actions(pid)
		assert_eq(game.submit(legal[i % legal.size()]), "")
	var data := game.save_data()
	var copy := ConjuraGame.new()
	copy.setup(GameBase.players_from_save(data), int(data["seed"]))
	assert_eq(copy.replay(data["history"]), "")
	assert_eq(copy.roles, game.roles)
	assert_eq(copy.draw_pile, game.draw_pile)
	assert_eq(copy.phase, game.phase)
	assert_eq(copy.governments, game.governments)
	assert_eq(copy.knowledge, game.knowledge)
