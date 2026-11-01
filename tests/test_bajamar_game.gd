extends TestCase

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")
const G := preload("res://games/bajamar/logic/bajamar_game.gd")


func _game(n: int = 3, seed_value: int = 1) -> BajamarGame:
	var g := BajamarGame.new()
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i))
	g.setup(ps, seed_value)
	return g


## Prepara el mazo para que se roben `cards` en ese orden (el resto debajo).
func _rig(g: BajamarGame, cards: Array) -> void:
	var rest := g.deck.duplicate()
	for c in cards:
		var i := rest.find(c)
		if i >= 0:
			rest.remove_at(i)
	var top := cards.duplicate()
	top.reverse()
	g.deck.assign(rest + top)


func _do(g: BajamarGame, type: StringName, data: Dictionary = {}, pid: int = -1) -> String:
	if pid < 0:
		pid = g.players_to_act()[0] if not g.players_to_act().is_empty() else g.turns.current
	return g.submit(GameAction.new(type, pid, data))


## Juega hasta el final con una estrategia sencilla: roba a ciegas hasta
## tener `stop_at` cartas o un aviso.
func _autoplay(g: BajamarGame, stop_at: int = 4, max_actions: int = 5000) -> void:
	var count := 0
	while not g.finished and count < max_actions:
		var p := g.players_to_act()[0]
		var error := ""
		if not g.pending_gulls.is_empty():
			error = _do(g, G.CHOOSE_TARGET, {"target": g.gull_targets(p)[0]})
		elif g.warnings[p] or g.net(p).size() >= stop_at or g.cards_left() == 0:
			error = _do(g, G.GO_TO_PORT)
		elif not g.market.is_empty() and count % 3 == 0:
			error = _do(g, G.TAKE_MARKET, {"slot": count % g.market.size()})
		else:
			error = _do(g, G.DRAW_BLIND)
		assert_eq(error, "", "acción %d" % count)
		if error != "":
			return
		count += 1


func _total_cards(g: BajamarGame) -> int:
	var total := g.deck.size() + g.discard.size() + g.market.size()
	for p in g.players.size():
		total += g.net(p).size() + (1 if g.warnings[p] else 0) + (1 if g.shields[p] else 0)
	return total


func test_setup() -> void:
	var g := _game(4)
	assert_eq(g.round_number, 1)
	assert_eq(g.turns.current, 0)
	assert_eq(g.market.size(), D.MARKET_SIZE)
	for c in g.market:
		assert_false(D.is_storm(c), "en el mercado no hay tormentas")
	assert_eq(g.at_sea(), [0, 1, 2, 3] as Array[int])
	assert_eq(_total_cards(g), D.deck().size())


func test_same_seed_same_game() -> void:
	var a := _game(3, 42)
	var b := _game(3, 42)
	_autoplay(a)
	_autoplay(b)
	assert_eq(a.scores, b.scores)
	assert_eq(a.round_number, b.round_number)
	assert_eq(a.history.size(), b.history.size())


func test_save_and_replay() -> void:
	var a := _game(3, 7)
	for i in 25:
		if a.finished:
			break
		if not a.pending_gulls.is_empty():
			_do(a, G.CHOOSE_TARGET, {"target": a.gull_targets(a.players_to_act()[0])[0]})
		else:
			_do(a, G.DRAW_BLIND if i % 4 != 3 else G.GO_TO_PORT)
	var data := a.save_data()
	var b := BajamarGame.new()
	b.setup(GameBase.players_from_save(data), int(data["seed"]))
	assert_eq(b.replay(data["history"]), "")
	assert_eq(b.scores, a.scores)
	assert_eq(b.deck, a.deck)
	assert_eq(b.market, a.market)
	assert_eq(b.nets, a.nets)
	assert_eq(b.turns.current, a.turns.current)


func test_only_current_player_acts() -> void:
	var g := _game(3)
	assert_eq(_do(g, G.DRAW_BLIND, {}, 1), "No es tu turno")
	assert_eq(_do(g, G.TAKE_MARKET, {"slot": 5}), "Esa carta del mercado no existe")
	assert_eq(_do(g, &"fly"), "Acción no soportada: fly")
	_rig(g, [D.fish(0, 1)])
	assert_eq(_do(g, G.DRAW_BLIND), "")
	assert_eq(g.turns.current, 1)


func test_draw_fish_goes_to_net() -> void:
	var g := _game(2)
	var c := D.fish(D.Species.HAKE, 5)
	_rig(g, [c])
	_do(g, G.DRAW_BLIND)
	assert_eq(g.net(0), [c] as Array[int])
	assert_eq(g.net_score(0)["total"], 10)


func test_take_market_refills() -> void:
	var g := _game(2)
	var taken: int = g.market[1]
	var refill := D.fish(D.Species.TUNA, 2)
	_rig(g, [refill])
	_do(g, G.TAKE_MARKET, {"slot": 1})
	assert_eq(g.net(0), [taken] as Array[int])
	assert_eq(g.market.size(), D.MARKET_SIZE)
	assert_eq(g.market[D.MARKET_SIZE - 1], refill)


func test_storm_in_market_refill_passes() -> void:
	var g := _game(2)
	var refill := D.fish(D.Species.TUNA, 2)
	_rig(g, [D.STORM, refill])
	var before := g.discard.duplicate()
	var passed := [0]
	g.event.connect(func(kind: StringName, _d: Dictionary) -> void:
		if kind == &"storm_passed":
			passed[0] += 1)
	_do(g, G.TAKE_MARKET, {"slot": 0})
	assert_eq(passed[0], 1)
	assert_eq(g.discard, before + [D.STORM])
	assert_eq(g.market[D.MARKET_SIZE - 1], refill)
	assert_false(D.STORM in g.market)


func test_first_storm_warns_second_breaks() -> void:
	var g := _game(2)
	var f := D.fish(D.Species.SARDINE, 3)
	_rig(g, [f, D.fish(0, 1), D.STORM, D.fish(0, 2), D.STORM])
	var before := g.discard.count(D.STORM)
	_do(g, G.DRAW_BLIND)  # J0: pez
	_do(g, G.DRAW_BLIND)  # J1: pez
	_do(g, G.DRAW_BLIND)  # J0: tormenta (aviso)
	assert_true(g.warnings[0])
	assert_eq(g.status[0], G.Status.AT_SEA)
	assert_eq(g.net(0), [f] as Array[int], "la tormenta no entra en la red")
	_do(g, G.DRAW_BLIND)  # J1: pez
	_do(g, G.DRAW_BLIND)  # J0: segunda tormenta
	assert_eq(g.status[0], G.Status.BROKEN)
	assert_true(g.net(0).is_empty())
	assert_false(g.warnings[0])
	assert_eq(g.discard.count(D.STORM), before + 2)
	assert_true(f in g.discard)
	assert_eq(g.turns.current, 1)
	assert_eq(_total_cards(g), D.deck().size())


func test_turn_skips_players_out_of_the_sea() -> void:
	var g := _game(3)
	_rig(g, [D.fish(0, 1), D.fish(0, 2), D.fish(0, 3)])
	_do(g, G.DRAW_BLIND)       # 0
	_do(g, G.GO_TO_PORT)       # 1 vuelve a puerto
	_do(g, G.DRAW_BLIND)       # 2
	assert_eq(g.turns.current, 0)
	_do(g, G.DRAW_BLIND)       # 0
	assert_eq(g.turns.current, 2, "el 1 ya está en puerto")


func test_round_end_scores_and_rotates_start() -> void:
	var g := _game(2)
	var a := D.fish(D.Species.OCTOPUS, 4)
	var b := D.fish(D.Species.TUNA, 1)
	_rig(g, [a, b])
	_do(g, G.DRAW_BLIND)  # J0: pulpo 4
	_do(g, G.DRAW_BLIND)  # J1: atún 1
	_do(g, G.GO_TO_PORT)  # J0
	assert_eq(g.round_number, 1)
	_do(g, G.GO_TO_PORT)  # J1: termina la ronda
	assert_eq(g.scores, [8, 2] as Array[int])
	assert_eq(g.last_round[0]["total"], 8)
	assert_eq(g.round_number, 2)
	assert_eq(g.turns.current, 1, "la segunda ronda empieza el siguiente jugador")
	assert_eq(g.at_sea(), [0, 1] as Array[int])
	assert_true(g.net(0).is_empty())
	assert_true(a in g.discard and b in g.discard)
	assert_eq(_total_cards(g), D.deck().size())


func test_broken_net_scores_zero() -> void:
	var g := _game(2)
	_rig(g, [D.fish(0, 6), D.STORM, D.STORM])
	_do(g, G.DRAW_BLIND)  # J0: pez
	_do(g, G.DRAW_BLIND)  # J1: aviso
	_do(g, G.GO_TO_PORT)  # J0
	_do(g, G.DRAW_BLIND)  # J1: se rompe y acaba la ronda
	assert_eq(g.scores, [12, 0] as Array[int])
	assert_true(g.last_round[1].get("broken", false))


func test_warning_storm_discarded_at_round_end() -> void:
	var g := _game(2)
	_rig(g, [D.STORM])
	var before := g.discard.count(D.STORM)
	_do(g, G.DRAW_BLIND)  # J0: aviso
	_do(g, G.GO_TO_PORT)
	_do(g, G.GO_TO_PORT)
	assert_false(g.warnings[0])
	assert_eq(g.discard.count(D.STORM), before + 1)
	assert_eq(g.storms_in_deck(), D.STORM_COUNT - g.discard.count(D.STORM))


func test_reshuffle_when_deck_runs_out() -> void:
	var g := _game(2)
	g.discard.assign([D.fish(0, 1), D.fish(0, 2), D.fish(0, 3), D.fish(0, 4), D.fish(0, 5)])
	g.deck.assign([D.fish(1, 1)])
	_do(g, G.DRAW_BLIND)  # roba la última
	assert_true(g.deck.is_empty())
	_do(g, G.DRAW_BLIND)  # baraja los descartes
	assert_eq(g.deck.size(), 4)
	assert_true(g.discard.is_empty())


func test_no_blind_draw_without_cards() -> void:
	var g := _game(2)
	g.deck.clear()
	g.discard.clear()
	assert_eq(_do(g, G.DRAW_BLIND), "No quedan cartas en el mazo")
	var types := g.get_legal_actions(0).map(func(a: GameAction) -> StringName: return a.type)
	assert_false(G.DRAW_BLIND in types)
	assert_true(G.GO_TO_PORT in types)
	assert_eq(g.get_legal_actions(1), [] as Array[GameAction], "no es su turno")


func test_storm_chance() -> void:
	var g := _game(2)
	assert_eq(g.storms_in_deck() + g.discard.count(D.STORM), D.STORM_COUNT)
	var expected := float(g.storms_in_deck()) / g.deck.size()
	assert_true(absf(g.storm_chance() - expected) < 0.0001)
	# Con el mazo vacío se robaría de los descartes barajados.
	g.deck.clear()
	g.discard.assign([D.STORM, D.fish(0, 1), D.fish(0, 2), D.fish(0, 3)])
	assert_true(absf(g.storm_chance() - 0.25) < 0.0001)


func test_game_ends_at_target_with_ties() -> void:
	var g := _game(2)
	g.target_score = 10
	g.scores.assign([5, 5])
	_rig(g, [D.fish(0, 3), D.fish(1, 3)])
	_do(g, G.DRAW_BLIND)
	_do(g, G.DRAW_BLIND)
	_do(g, G.GO_TO_PORT)
	_do(g, G.GO_TO_PORT)
	assert_true(g.finished)
	assert_eq(g.phase, G.Phase.FINISHED)
	assert_eq(g.winner_ids, [0, 1] as Array[int], "empate a 11")
	assert_eq(_do(g, G.DRAW_BLIND), "La partida ha terminado")


func test_full_games_finish_and_keep_cards() -> void:
	for n in range(2, 7):
		for seed_value in [3, 11]:
			var g := _game(n, seed_value)
			_autoplay(g)
			assert_true(g.finished, "%d jugadores, semilla %d" % [n, seed_value])
			assert_true(g.scores.max() >= D.TARGET_SCORE)
			assert_eq(_total_cards(g), D.deck().size(), "no se pierden cartas")
