extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")

const FACE_UP := 2


func _game(n: int, quick := true, auto := true, seed_value := 1) -> PestsGame:
	var g := PestsGame.new()
	g.options = {"quick_species": quick, "auto_house": auto}
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i))
	g.setup(ps, seed_value)
	return g


## Bloque 2x2 con 2 jugadores de especies fijas y las manos vacías:
##   A(0,-1) nido sp0   C(1,-1)
##   E(0, 0) entrada    B(1, 0)
## y el nido de sp1 a la izquierda de la entrada. Todo en la reserva.
func _square(sp0: int, sp1: int) -> Dictionary:
	var h := PestsHouse.new()
	var a := h.place_nest(Vector2i(0, -1), sp0)
	var b := h.place_custom(Vector2i(1, 0), D.DOOR_ALL)
	var c := h.place_custom(Vector2i(1, -1), D.DOOR_ALL)
	var n1 := h.place_nest(Vector2i(-1, 0), sp1)
	var g := _game(2)
	g.species_of.assign([sp0, sp1])
	g.house = h
	g.pests.clear()
	for r in h.room_count():
		g.pests.append([0, 0, 0, 0, 0, 0])
	g.traps.clear()
	g.reserve.assign([0, 0, 0, 0, 0, 0])
	g.pool.assign([0, 0, 0, 0, 0, 0])
	g.queen_room.assign([-1, -1, -1, -1, -1, -1])
	g.sealed.assign([false, false, false, false, false, false])
	for pid in 2:
		var sp := g.species_of[pid]
		g.pool[sp] = 20
		g.reserve[sp] = 20
		g.queen_room[sp] = 0
		g.exterminator_room[pid] = 0
		g.hands[pid] = []
		g.turns_taken[pid] = 1
	g.deck.clear()
	g.discard.clear()
	g.effects.clear()
	return {"game": g, "e": 0, "a": a, "b": b, "c": c, "n1": n1}


func _exterminator_turn(g: PestsGame, pid: int) -> void:
	g.turns.current = pid
	g.phase = G.Phase.EXTERMINATOR
	g.free_move = true
	g.action_points = D.ACTION_POINTS
	g.energy_moves = 0


func _queen_turn(g: PestsGame, pid: int) -> void:
	g.turns_taken[pid] = 1
	g._start_turn(pid)


func _put(g: PestsGame, sp: int, room: int, count: int) -> void:
	g.reserve[sp] -= count
	g.pests[room][sp] += count


func _play(g: PestsGame, pid: int, card: String, data: Dictionary = {}) -> String:
	if not card in g.hands[pid]:
		g.hands[pid].append(card)
	var d := data.duplicate()
	d["card"] = card
	return g.submit(GameAction.new(G.PLAY_CARD, pid, d))


func _ok(g: PestsGame, type: StringName, pid: int, data: Dictionary = {}) -> void:
	assert_eq(g.submit(GameAction.new(type, pid, data)), "", "%s debería ser legal" % type)


# --- Reparto y compra -----------------------------------------------------------

func test_quick_deal() -> void:
	for n in range(2, 7):
		var g := _game(n, true, true, n)
		var all := {}
		for pid in n:
			assert_eq(g.hands[pid].size(), 4)
			for c in g.hands[pid]:
				all[c] = true
		for c in g.deck:
			all[c] = true
		assert_eq(g.deck.size(), 24 - 4 * n)
		assert_eq(all.size(), 24, "cada carta está una sola vez")


func test_buy_card() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.deck.assign(["zap", "stuck"])
	_exterminator_turn(g, 0)
	_ok(g, G.BUY_CARD, 0)
	assert_eq(g.hands[0], ["stuck"])
	assert_eq(g.action_points, 0)
	assert_false(g.free_move)
	# Sin mazo se roba del descarte.
	g.deck.clear()
	g.discard.assign(["fertile"])
	_exterminator_turn(g, 0)
	_ok(g, G.BUY_CARD, 0)
	assert_true("fertile" in g.hands[0])
	assert_eq(g.discard.size(), 0)
	_exterminator_turn(g, 0)
	assert_ne(g.submit(GameAction.new(G.BUY_CARD, 0)), "", "no quedan cartas")


func test_played_cards_go_to_discard_at_end_of_turn() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "more_time"), "")
	assert_false("more_time" in g.hands[0])
	assert_eq(g.discard.size(), 0)
	_ok(g, G.END_TURN, 0)
	assert_eq(g.discard, ["more_time"] as Array[String])


func test_card_timing() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "hibernate"), "", "antes de tirar, no en el turno del exterminador")
	_queen_turn(g, 0)
	assert_ne(_play(g, 0, "more_time"), "", "las cartas normales, en el turno del exterminador")
	assert_ne(_play(g, 1, "more_time"), "", "no es su turno")
	assert_ne(_play(g, 0, "stuck", {"player": 0}), "", "una ofensiva no puede ir contra uno mismo")


# --- Defensivas -------------------------------------------------------------------

func test_more_time() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "more_time"), "")
	assert_eq(g.action_points, 3)


func test_hibernate() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.turns_taken[0] = 0  # primer turno: la reina activaría dos veces
	g._start_turn(0)
	assert_eq(g.queen_steps.size(), 2)
	assert_eq(_play(g, 0, "hibernate"), "")
	assert_eq(g.phase, G.Phase.EXTERMINATOR)
	assert_eq(g.reserve[D.Species.BLUE], 20, "ni la reina ni el nido sueltan plagas")
	assert_true(g.free_move, "no gasta el movimiento gratis")
	assert_eq(g.action_points, 2, "no cuesta acción")


func test_before_roll_window_closes_after_first_roll() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.turns_taken[0] = 0
	g._start_turn(0)
	_ok(g, G.ROLL_QUEEN, 0)
	assert_eq(g.phase, G.Phase.QUEEN)
	assert_ne(_play(g, 0, "hibernate"), "")
	assert_ne(_play(g, 0, "mind_control", {"queen_action": 0}), "")


func test_mind_control() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_queen_turn(g, 0)
	assert_ne(_play(g, 0, "mind_control", {"queen_action": 9}), "")
	assert_eq(_play(g, 0, "mind_control", {"queen_action": D.QueenAction.UP}), "")
	_ok(g, G.ROLL_QUEEN, 0)
	assert_eq(g.history[-1].data["chosen"], D.QueenAction.UP)
	assert_eq(g.queen_room[D.Species.BLUE], s["a"])


func test_mating_call() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["c"], 4)
	g.exterminator_room[0] = s["n1"]  # C está a 3 pasos: C -> A/B -> E -> nido verde
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "mating_call"), "")
	assert_eq(g.pests_in_room(s["e"], D.Species.BLUE), 4, "avanzan dos habitaciones")


func test_colony_collapse() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["b"], 5)
	_put(g, D.Species.BLUE, s["c"], 2)
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "colony_collapse", {"room": s["c"]}), "", "no es la más infestada")
	assert_eq(_play(g, 0, "colony_collapse", {"room": s["b"]}), "")
	assert_eq(g.pests_in_room(s["b"], D.Species.BLUE), 2, "quita la mitad redondeando hacia arriba")


func test_bug_bomb_and_zap() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["e"], 6)
	_put(g, D.Species.GREEN, s["e"], 6)
	_put(g, D.Species.BLUE, s["c"], 5)
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "bug_bomb"), "")
	assert_eq(g.pests_in_room(s["e"], D.Species.BLUE), 0)
	assert_eq(g.pests_in_room(s["e"], D.Species.GREEN), 6, "solo las de su color")
	assert_eq(_play(g, 0, "zap", {"room": s["c"]}), "")
	assert_eq(g.pests_in_room(s["c"], D.Species.BLUE), 2)
	assert_eq(g.reserve[D.Species.BLUE], 20 - 2)


func test_energy_drink() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["c"], 1)
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "energy_drink"), "")
	assert_eq(g.action_points, 0)
	assert_eq(g.energy_moves, 4)
	_ok(g, G.MOVE, 0, {"room": s["b"]})
	_ok(g, G.MOVE, 0, {"room": s["c"]})
	assert_ne(g.submit(GameAction.new(G.EXTERMINATE, 0)), "", "solo puede moverse")
	_ok(g, G.MOVE, 0, {"room": s["a"]})
	_ok(g, G.MOVE, 0, {"room": s["e"]})
	assert_ne(g.submit(GameAction.new(G.MOVE, 0, {"room": s["b"]})), "", "solo 4")


func test_quik_trap() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["b"], 5)
	g.exterminator_room[0] = s["b"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "quik_trap"), "")
	assert_eq(g.traps.size(), 0, "la trampa se suelta y se vacía")
	assert_eq(g.pests_in_room(s["b"], D.Species.BLUE), 0)
	assert_eq(g.reserve[D.Species.BLUE], 20)
	assert_eq(g.traps_available(0), 1)


func test_quik_trap_keeps_queen_if_it_cannot_win() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.queen_room[D.Species.BLUE] = s["b"]
	_put(g, D.Species.BLUE, s["c"], 1)
	g.exterminator_room[0] = s["b"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "quik_trap"), "")
	assert_true(g.is_queen_trapped(D.Species.BLUE), "atrapa a la reina pero no puede vaciarla aún")
	assert_false(g.finished)


func test_quik_seal_any_nest() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.exterminator_room[0] = s["n1"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "quik_seal"), "")
	assert_true(g.sealed[D.Species.GREEN])
	g.exterminator_room[0] = s["b"]
	assert_ne(_play(g, 0, "quik_seal"), "", "no está en un nido")


func test_trap_remote() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.traps.append({"id": 5, "owner": 0, "room": s["c"], "pests": 3, "queen": false, "prefer_queen": true})
	g.reserve[D.Species.BLUE] -= 3
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "trap_remote", {"trap": 5}), "")
	assert_eq(g.traps.size(), 0)
	assert_eq(g.reserve[D.Species.BLUE], 20)


func test_nesting() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.queen_room[D.Species.BLUE] = s["b"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "nesting"), "")
	assert_eq(g.queen_room[D.Species.BLUE], s["a"])
	assert_ne(_play(g, 0, "nesting"), "", "ya está en su nido")


# --- Ofensivas ---------------------------------------------------------------------

func test_unseal_and_trap_breaks() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.sealed[D.Species.GREEN] = true
	g.traps.append({"id": 8, "owner": 1, "room": s["c"], "pests": 4, "queen": false, "prefer_queen": true})
	g.reserve[D.Species.GREEN] -= 4
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "unseal_nest", {"player": 1}), "")
	assert_false(g.sealed[D.Species.GREEN])
	assert_eq(_play(g, 0, "trap_breaks", {"player": 1, "trap": 8}), "")
	assert_eq(g.traps.size(), 0)
	assert_eq(g.pests_in_room(s["c"], D.Species.GREEN), 4)


func test_pest_surge_ignores_seal() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.sealed[D.Species.GREEN] = true
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "pest_surge", {"player": 1}), "")
	assert_eq(g.pests_in_room(s["n1"], D.Species.GREEN), 5)


func test_less_to_infest() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "less_to_infest", {"player": 1}), "")
	assert_eq(g.reserve[D.Species.GREEN], 15)
	assert_eq(g.pool[D.Species.GREEN], 15)


func test_sabotage_tools() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "sabotage_tools", {"player": 1}), "", "sin cartas no se puede")
	g.hands[1] = ["zap", "stuck"]
	assert_eq(_play(g, 0, "sabotage_tools", {"player": 1}), "")
	assert_eq(g.hands[1].size(), 1)
	assert_eq(g.discard.size(), 1)
	assert_true(g.discard[0] in ["zap", "stuck"])


func test_spreading() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.GREEN, s["b"], 1)
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "spreading", {"player": 1, "room": s["c"]}), "", "en C no hay plagas verdes")
	assert_eq(_play(g, 0, "spreading", {"player": 1, "room": s["b"]}), "")
	# Vecinos de B en DLUR: E (izquierda) y C (arriba).
	assert_eq(g.pests_in_room(s["e"], D.Species.GREEN), 2)
	assert_eq(g.pests_in_room(s["c"], D.Species.GREEN), 2)


func test_stuck() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "stuck", {"player": 1}), "")
	assert_false("stuck" in g.discard, "se queda delante del jugador")
	assert_true(g.has_effect(1, "stuck"))
	_ok(g, G.END_TURN, 0)
	_ok(g, G.ROLL_QUEEN, 1)
	assert_eq(g.phase, G.Phase.EXTERMINATOR)
	assert_false(g.free_move)
	assert_eq(g.action_points, 1)
	_ok(g, G.END_TURN, 1)
	assert_false(g.has_effect(1, "stuck"))
	assert_true("stuck" in g.discard)
	# El turno siguiente vuelve a ser normal.
	_ok(g, G.ROLL_QUEEN, 0)
	_ok(g, G.END_TURN, 0)
	_ok(g, G.ROLL_QUEEN, 1)
	assert_eq(g.action_points, 2)


func test_angry_queen() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "angry_queen", {"player": 1}), "")
	_ok(g, G.END_TURN, 0)
	assert_eq(g.queen_steps[0]["repeat"], 2)
	# Reina verde en la entrada: arriba dos veces = E -> A -> fuera y vuelta.
	g.resolve_queen_choice(D.Species.GREEN, D.QueenAction.DOWN, 2)
	assert_eq(g.pests_in_room(s["e"], D.Species.GREEN), 4, "enfadada dos veces: 2 + 2")
	assert_eq(g.pests_in_room(s["n1"], D.Species.GREEN), 1, "el nido solo una vez")


func test_royal_persuasion() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "royal_persuasion", {"player": 1}), "", "hay que elegir la acción")
	assert_eq(_play(g, 0, "royal_persuasion", {"player": 1, "queen_action": D.QueenAction.RIGHT}), "")
	_ok(g, G.END_TURN, 0)
	_ok(g, G.ROLL_QUEEN, 1)
	assert_eq(g.history[-1].data["chosen"], D.QueenAction.RIGHT)
	assert_eq(g.queen_room[D.Species.GREEN], s["b"])
	_ok(g, G.END_TURN, 1)
	assert_false(g.has_effect(1, "royal_persuasion"))


func test_two_by_two_until_sealed() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "two_by_two", {"player": 1}), "")
	g.queen_room[D.Species.GREEN] = s["e"]
	g.resolve_queen_choice(D.Species.GREEN, D.QueenAction.DOWN)  # pared: se queda en E
	assert_eq(g.pests_in_room(s["n1"], D.Species.GREEN), 2, "1 + 1 de De dos en dos")
	g._seal(D.Species.GREEN, 1)
	assert_false(g.has_effect(1, "two_by_two"))
	assert_true("two_by_two" in g.discard)
	g.sealed[D.Species.GREEN] = true
	assert_ne(_play(g, 0, "two_by_two", {"player": 1}), "", "con el nido sellado no se puede")


func test_fertile_until_trapped() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	assert_eq(_play(g, 0, "fertile", {"player": 1}), "")
	g.queen_room[D.Species.GREEN] = s["e"]
	g.sealed[D.Species.GREEN] = true
	g.resolve_queen_choice(D.Species.GREEN, D.QueenAction.DOWN)  # pared abajo de la entrada: enfadada
	assert_eq(g.pests_in_room(s["e"], D.Species.GREEN), 3, "2 por enfado + 1 por Fértil")
	g.traps.append({"id": 1, "owner": 1, "room": s["b"], "pests": 0, "queen": false, "prefer_queen": true})
	g.resolve_queen_choice(D.Species.GREEN, D.QueenAction.RIGHT)  # E -> B, cae en la trampa
	assert_true(g.is_queen_trapped(D.Species.GREEN))
	assert_false(g.has_effect(1, "fertile"))


func test_dumpster_diver() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.discard.assign(["pest_surge", "zap"])
	_exterminator_turn(g, 0)
	assert_ne(_play(g, 0, "dumpster_diver", {"use": "zap", "room": 0}), "", "solo ofensivas")
	assert_ne(_play(g, 0, "dumpster_diver", {"use": "pest_surge", "player": 0}), "", "contra un rival")
	assert_eq(_play(g, 0, "dumpster_diver", {"use": "pest_surge", "player": 1}), "")
	assert_eq(g.pests_in_room(s["n1"], D.Species.GREEN), 5)
	assert_false("pest_surge" in g.discard)
	_ok(g, G.END_TURN, 0)
	assert_true("pest_surge" in g.discard)
	assert_true("dumpster_diver" in g.discard)


func test_legal_actions_include_cards() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.hands[0] = ["zap", "stuck", "mind_control"]
	_put(g, D.Species.BLUE, s["c"], 1)
	_exterminator_turn(g, 0)
	var cards := {}
	for a in g.get_legal_actions(0):
		if a.type == G.PLAY_CARD:
			cards[a.data["card"]] = true
	assert_true(cards.has("zap"))
	assert_true(cards.has("stuck"))
	assert_false(cards.has("mind_control"), "antes de tirar no vale en este momento")
