extends TestCase
## La Conjura: view_for(seat) nunca filtra información secreta, y la IA
## básica termina partidas completas sin jugadas ilegales.

const G := preload("res://games/conjura/logic/conjura_game.gd")
const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Edict := ConjuraDefs.Edict


func _game(n: int = 5, seed: int = 7, ai_level: int = PlayerInfo.AILevel.HUMAN) -> ConjuraGame:
	var players: Array[PlayerInfo] = []
	for i in n:
		players.append(PlayerInfo.new(i, "", PlayerInfo.default_color(i), ai_level))
	var game := ConjuraGame.new()
	game.setup(players, seed)
	return game


func _sombra_ids(game: ConjuraGame) -> Array[int]:
	var result: Array[int] = []
	for i in game.players.size():
		if game.roles[i] != Role.GUARDIA:
			result.append(i)
	return result


func test_guardia_only_knows_itself() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 3)
		for seat in n:
			if game.roles[seat] != Role.GUARDIA:
				continue
			var known: Dictionary = game.view_for(seat)["known_roles"]
			assert_eq(known.size(), 1, "un guardia con %d jugadores" % n)
			assert_eq(known[seat], Role.GUARDIA)


func test_sombra_knows_all_allies() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 5)
		var allies := _sombra_ids(game)
		for seat in n:
			if game.roles[seat] != Role.SOMBRA:
				continue
			var known: Dictionary = game.view_for(seat)["known_roles"]
			assert_eq(known.size(), allies.size(), "sombra con %d jugadores" % n)
			for a in allies:
				assert_eq(known.get(a, -1), game.roles[a])


func test_usurper_knows_allies_only_in_small_games() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 11)
		var seat := game.roles.find(Role.USURPADOR)
		var known: Dictionary = game.view_for(seat)["known_roles"]
		var expected := _sombra_ids(game).size() if n <= D.USURPER_KNOWS_ALLIES_MAX else 1
		assert_eq(known.size(), expected, "usurpador con %d jugadores" % n)


func test_public_view_has_no_secrets() -> void:
	var game := _game()
	var view := game.view_for(-1)
	assert_true(view["known_roles"].is_empty())
	assert_true(view["hand"].is_empty())
	assert_true(view["knowledge"].is_empty())
	assert_false(view.has("roles"))
	assert_false(view.has("draw_pile"))


func test_votes_hidden_until_resolved() -> void:
	var game := _game()
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	game.submit(GameAction.new(G.VOTE, 0, {"yes": false}))
	game.submit(GameAction.new(G.VOTE, 1, {"yes": true}))
	for seat in 5:
		var view := game.view_for(seat)
		assert_eq(view["voted"].size(), 2, "se sabe quién ha votado")
		for v in view["voted"].values():
			assert_eq(v, true, "pero no qué ha votado")
		if seat == 0:
			assert_eq(view["my_vote"], false)
		elif seat == 1:
			assert_eq(view["my_vote"], true)
		else:
			assert_eq(view["my_vote"], null)
		assert_true(view["last_votes"].is_empty())
	for pid in range(2, 5):
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	assert_eq(game.view_for(-1)["last_votes"].size(), 5, "al resolverse, los votos son públicos")


func test_hand_only_visible_to_holder() -> void:
	var game := _game()
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	for pid in 5:
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	for seat in 5:
		var hand: Array = game.view_for(seat)["hand"]
		assert_eq(hand.size(), 3 if seat == game.regent else 0, "Regente: asiento %d" % seat)
	game.submit(GameAction.new(G.DISCARD, game.regent, {"index": 0}))
	for seat in 5:
		var hand: Array = game.view_for(seat)["hand"]
		assert_eq(hand.size(), 2 if seat == game.council else 0, "Consejero: asiento %d" % seat)


func test_knowledge_is_private() -> void:
	var game := _game()
	game.knowledge[2].append({"kind": "faction", "target": 0, "faction": 0})
	for seat in 5:
		assert_eq(game.view_for(seat)["knowledge"].size(), 1 if seat == 2 else 0)


func test_view_is_a_copy() -> void:
	var game := _game()
	var view := game.view_for(0)
	view["alive"][1] = false
	view["known_roles"][3] = Role.USURPADOR
	assert_true(game.alive[1], "modificar la vista no cambia la partida")
	assert_false(game.view_for(0)["known_roles"].has(3) and game.roles[3] != Role.USURPADOR and game.roles[0] == Role.GUARDIA)


func test_finished_game_reveals_everything() -> void:
	var game := _game()
	game.guardia_edicts = 4
	for i in 3:
		game.draw_pile.push_front(Edict.GUARDIA)
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	for pid in 5:
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	game.submit(GameAction.new(G.DISCARD, game.regent, {"index": 0}))
	game.submit(GameAction.new(G.ENACT, game.council, {"index": 0}))
	assert_true(game.finished)
	assert_eq(game.view_for(-1)["known_roles"].size(), 5)
	var truth: Dictionary = game.view_for(-1)["truth"]
	assert_eq(truth[0]["drawn"], [Edict.GUARDIA, Edict.GUARDIA, Edict.GUARDIA] as Array[int], "al final se sabe qué se robó")
	assert_eq(truth[0]["passed"].size(), 2)


func test_truth_hidden_during_game() -> void:
	var game := _game()
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	for pid in 5:
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	for seat in range(-1, 5):
		assert_false(game.view_for(seat).has("truth"), "la verdad no se ve durante la partida (asiento %d)" % seat)


func test_ai_games_finish() -> void:
	for g in 30:
		var n := 5 + g % 6
		var game := _game(n, 1000 + g, PlayerInfo.AILevel.NORMAL)
		var ais := {}
		for pid in n:
			ais[pid] = ConjuraAI.new(pid, [PlayerInfo.AILevel.EASY, PlayerInfo.AILevel.NORMAL, PlayerInfo.AILevel.HARD][pid % 3], g)
		var steps := 0
		while not game.finished and steps < 2000:
			var pid: int = game.players_to_act()[0]
			var action: GameAction = ais[pid].choose_action(game)
			assert_true(action != null, "la IA siempre tiene jugada")
			if action == null:
				return
			var error := game.submit(action)
			assert_eq(error, "", "jugada legal de la IA")
			if error != "":
				return
			steps += 1
		assert_true(game.finished, "la partida %d termina" % g)


## Equilibrio: entre IAs normales, cada facción gana entre el 35 % y el 65 %.
func test_ai_balance() -> void:
	var games := 240
	var guardia := 0
	for g in games:
		var n := 5 + g % 6
		var game := _game(n, 5000 + g, PlayerInfo.AILevel.NORMAL)
		var ais := {}
		for pid in n:
			ais[pid] = ConjuraAI.new(pid, PlayerInfo.AILevel.NORMAL, g)
		while not game.finished:
			var pid: int = game.players_to_act()[0]
			if game.submit(ais[pid].choose_action(game)) != "":
				_fail("jugada ilegal de la IA")
				return
		if game.winner_faction == ConjuraDefs.Faction.GUARDIA:
			guardia += 1
	var rate := 100.0 * guardia / games
	assert_true(rate >= 35.0 and rate <= 65.0, "la Guardia gana el %.0f %% (se espera 35–65 %%)" % rate)


## La Guardia difícil deduce: el Usurpador no debería ganar casi siempre por
## Consejero, y la Guardia sospecha más de los traidores que de los honrados.
func test_deduction_points_at_traitors() -> void:
	var traitor_sum := 0.0
	var honest_sum := 0.0
	var traitor_count := 0
	var honest_count := 0
	for g in 40:
		var n := 5 + g % 6
		var game := _game(n, 7000 + g, PlayerInfo.AILevel.NORMAL)
		var ais := {}
		for pid in n:
			ais[pid] = ConjuraAI.new(pid, PlayerInfo.AILevel.HARD, g)
		var steps := 0
		while not game.finished and steps < 40:
			var pid: int = game.players_to_act()[0]
			game.submit(ais[pid].choose_action(game))
			steps += 1
		var probs := ConjuraDeduction.evil_probabilities(game.view_for(-1))
		for pid in n:
			if game.roles[pid] == Role.GUARDIA:
				honest_sum += probs[pid]
				honest_count += 1
			else:
				traitor_sum += probs[pid]
				traitor_count += 1
	var traitor_avg := traitor_sum / traitor_count
	var honest_avg := honest_sum / honest_count
	assert_true(traitor_avg > honest_avg + 0.05, "sospecha media: traidores %.2f, honrados %.2f" % [traitor_avg, honest_avg])


func test_deduction_respects_hard_facts() -> void:
	var game := _game(7, 3)
	var seat := game.roles.find(Role.GUARDIA)
	var target := (seat + 1) % 7
	game.knowledge[seat].append({"kind": "faction", "target": target, "faction": D.faction_of(game.roles[target])})
	var probs := ConjuraDeduction.evil_probabilities(game.view_for(seat))
	assert_eq(probs[seat], 0.0, "un guardia sabe que él no es traidor")
	assert_eq(probs[target], 1.0 if game.roles[target] != Role.GUARDIA else 0.0, "lo espiado es seguro")
	var total := 0.0
	for p in probs:
		total += p
	assert_true(absf(total - (D.ROLE_TABLE[7][1] + 1)) < 0.001, "las probabilidades suman el número de traidores")


func test_deduction_catches_lying_council() -> void:
	# Fui Regente, pasé dos de la Guardia y salió Sombra: el Consejero miente.
	var game := _game(7, 11)
	var seat := game.roles.find(Role.GUARDIA)
	var view := game.view_for(seat)
	var council := (seat + 1) % 7
	view["governments"] = [{"regent": seat, "nominee": council, "votes": {}, "approved": true, "edict": Edict.SOMBRA, "crisis": false, "claims": {"regent": [0, 0, 1], "council": [1, 1]}}]
	view["knowledge"] = [{"kind": "drawn", "cards": [0, 0, 1], "passed": [0, 0], "council": council, "round": 0}]
	var probs := ConjuraDeduction.evil_probabilities(view)
	assert_true(probs[council] > 0.99, "el Consejero es traidor (%.3f)" % probs[council])
