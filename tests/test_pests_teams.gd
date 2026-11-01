extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")


func _game(n: int, teams: bool, seed_value: int = 3, level: int = PlayerInfo.AILevel.HUMAN) -> PestsGame:
	var g := PestsGame.new()
	g.options = {"quick_species": true, "auto_house": true, "teams": teams}
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i, "", Color.WHITE, level))
	g.setup(ps, seed_value)
	return g


## 4 jugadores por equipos (0 y 2 contra 1 y 3) en una casa pequeña:
##   A(0,-1) nido sp0   C(1,-1) nido sp2
##   E(0, 0) entrada    B(1, 0) nido sp1
## y el nido de sp3 a la izquierda de la entrada. Todo en la reserva.
func _teams_board() -> Dictionary:
	var sps := [D.Species.BLUE, D.Species.GREEN, D.Species.RED, D.Species.ORANGE]
	var h := PestsHouse.new()
	var a := h.place_nest(Vector2i(0, -1), sps[0])
	var b := h.place_nest(Vector2i(1, 0), sps[1])
	var c := h.place_nest(Vector2i(1, -1), sps[2])
	var d := h.place_nest(Vector2i(-1, 0), sps[3])
	var g := _game(4, true)
	g.species_of.assign(sps)
	g.house = h
	g.pests.clear()
	for r in h.room_count():
		g.pests.append([0, 0, 0, 0, 0, 0])
	g.traps.clear()
	g.effects.clear()
	g.reserve.assign([0, 0, 0, 0, 0, 0])
	g.pool.assign([0, 0, 0, 0, 0, 0])
	g.queen_room.assign([-1, -1, -1, -1, -1, -1])
	g.sealed.assign([false, false, false, false, false, false])
	for pid in 4:
		var sp: int = sps[pid]
		g.pool[sp] = 20
		g.reserve[sp] = 20
		g.queen_room[sp] = h.nest_of(sp)
		g.exterminator_room[pid] = 0
		g.hands[pid] = []
		g.turns_taken[pid] = 1
	g.turns.current = 0
	g.phase = G.Phase.EXTERMINATOR
	g.free_move = true
	g.action_points = D.ACTION_POINTS
	return {"game": g, "sps": sps, "e": 0, "a": a, "b": b, "c": c, "d": d}


func _put(g: PestsGame, sp: int, room: int, count: int) -> void:
	g.reserve[sp] -= count
	g.pests[room][sp] += count


func _ok(g: PestsGame, type: StringName, pid: int, data: Dictionary = {}) -> void:
	assert_eq(g.submit(GameAction.new(type, pid, data)), "", "%s debería ser legal" % type)


func _rejected(g: PestsGame, type: StringName, pid: int, data: Dictionary = {}) -> void:
	assert_ne(g.submit(GameAction.new(type, pid, data)), "", "%s debería rechazarse" % type)


func test_team_assignment() -> void:
	var g := _game(4, true)
	assert_true(g.teams_enabled())
	assert_eq(g.team_of, [0, 1, 0, 1] as Array[int])
	assert_eq(g.teammates(0), [2] as Array[int])
	assert_eq(g.opponents(0), [1, 3] as Array[int])
	var six := _game(6, true)
	assert_eq(six.teammates(1), [3, 5] as Array[int])
	# Con 3 o 5 jugadores no hay equipos.
	var three := _game(3, true)
	assert_false(three.teams_enabled())
	assert_eq(three.opponents(0), [1, 2] as Array[int])


func test_exterminate_any_color_only_in_teams() -> void:
	var t := _teams_board()
	var g: PestsGame = t["game"]
	var red: int = t["sps"][2]
	_put(g, red, t["e"], 5)
	_ok(g, G.EXTERMINATE, 0, {"species": red})
	assert_true(g.pests_in_room(t["e"], red) < 5, "extermina las del compañero")
	assert_eq(g.reserve[red], 20 - g.pests_in_room(t["e"], red), "vuelven a su reserva")
	# Sin equipos no se puede.
	var solo := _game(2, false)
	solo.phase = G.Phase.EXTERMINATOR
	solo.action_points = 2
	var pid := solo.turns.current
	var other_sp := solo.species(1 - pid)
	solo.pests[solo.exterminator_room[pid]][other_sp] += 3
	assert_ne(solo.validate(GameAction.new(G.EXTERMINATE, pid, {"species": other_sp})), "")


func test_card_exchange_with_teammate() -> void:
	var t := _teams_board()
	var g: PestsGame = t["game"]
	g.hands[0] = ["zap"]
	g.hands[2] = ["stuck", "fertile"]
	_ok(g, G.GIVE_CARD, 0, {"to": 2, "card": "zap"})
	_ok(g, G.TAKE_CARD, 0, {"from": 2, "card": "fertile"})
	assert_eq(g.hands[0], ["fertile"])
	assert_true("zap" in g.hands[2])
	assert_true(g.free_move, "intercambiar no gasta el movimiento gratis")
	assert_eq(g.action_points, 2, "ni puntos de acción")
	_rejected(g, G.GIVE_CARD, 0, {"to": 1, "card": "fertile"})  # rival
	g.exterminator_room[2] = t["a"]
	_rejected(g, G.GIVE_CARD, 0, {"to": 2, "card": "fertile"})  # otra habitación
	var solo := _game(4, false)
	solo.phase = G.Phase.EXTERMINATOR
	assert_ne(solo.validate(GameAction.new(G.GIVE_CARD, solo.turns.current, {"to": (solo.turns.current + 2) % 4, "card": "x"})), "")


func test_no_attacks_on_teammates() -> void:
	var t := _teams_board()
	var g: PestsGame = t["game"]
	var red: int = t["sps"][2]
	g.sealed[red] = true
	g.exterminator_room[0] = t["c"]  # nido del compañero (rojo)
	_rejected(g, G.UNSEAL_NEST, 0)
	g.traps.append({"id": 1, "owner": 2, "room": t["c"], "pests": 2, "queen": false, "prefer_queen": true})
	_rejected(g, G.DESTROY_TRAP, 0, {"trap": 1})
	g.hands[0] = ["stuck"]
	_rejected(g, G.PLAY_CARD, 0, {"card": "stuck", "player": 2})
	_ok(g, G.PLAY_CARD, 0, {"card": "stuck", "player": 1})


func test_team_victory_needs_the_whole_team() -> void:
	var t := _teams_board()
	var g: PestsGame = t["game"]
	var blue: int = t["sps"][0]
	var red: int = t["sps"][2]
	g.sealed[blue] = true
	g.traps.append({"id": 1, "owner": 0, "room": t["e"], "pests": 0, "queen": true, "prefer_queen": true})
	assert_false(g.can_empty_queen_trap(0), "falta el compañero")
	g.sealed[red] = true
	assert_false(g.can_empty_queen_trap(0), "la reina roja sigue libre")
	g.traps.append({"id": 2, "owner": 2, "room": t["c"], "pests": 0, "queen": true, "prefer_queen": true})
	_put(g, red, t["b"], 1)
	assert_false(g.can_empty_queen_trap(0), "quedan plagas rojas")
	g.pests[t["b"]][red] = 0
	g.reserve[red] = 20
	assert_true(g.can_empty_queen_trap(0))
	_ok(g, G.EMPTY_TRAP, 0, {"trap": 1})
	assert_true(g.finished)
	assert_eq(g.winner_ids, [0, 2] as Array[int])


func test_team_elimination() -> void:
	var t := _teams_board()
	var g: PestsGame = t["game"]
	var red: int = t["sps"][2]
	# Le toca al rojo (jugador 2) y tiene todas sus plagas en la casa.
	_put(g, red, t["b"], 20)
	g.turns.current = 2
	_ok(g, G.END_TURN, 2)
	assert_true(g.eliminated[2])
	assert_true(g.eliminated[0], "cae todo su equipo")
	assert_true(g.finished)
	assert_eq(g.winner_ids, [1, 3] as Array[int])


func test_ai_team_games_finish() -> void:
	for n in [4, 6]:
		for level in [PlayerInfo.AILevel.EASY, PlayerInfo.AILevel.NORMAL, PlayerInfo.AILevel.HARD]:
			var g := _game(n, true, 300 + n * 7 + level, level)
			var ais := []
			for i in n:
				ais.append(PestsAI.new(i, level, n))
			var count := 0
			while not g.finished and count < 6000:
				var pid: int = g.players_to_act()[0]
				var action: GameAction = ais[pid].choose_action(g)
				var error := g.submit(action)
				if error != "":
					assert_eq(error, "", "jugada legal por equipos: %s" % action)
					break
				count += 1
			assert_true(g.finished, "%d jugadores, nivel %d" % [n, level])
			if g.finished:
				var team: int = g.team_of[g.winner_ids[0]]
				for w in g.winner_ids:
					assert_eq(g.team_of[w], team, "ganan los de un mismo equipo")
