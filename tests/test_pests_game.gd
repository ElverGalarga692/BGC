extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")

# Caras del dado de la reina (índices de PestsDefs.QUEEN_DIE).
const FACE_LEFT := 0    # amarillo
const FACE_RIGHT := 1   # verde
const FACE_UP := 2      # rojo
const FACE_SUMMON := 3  # azul
const FACE_DOWN := 4    # naranja
const FACE_POPULATE := 5  # morado


func _game(n: int, quick := true, auto := true, seed_value := 1) -> PestsGame:
	var g := PestsGame.new()
	g.options = {"quick_species": quick, "auto_house": auto}
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i))
	g.setup(ps, seed_value)
	return g


## Partida de 2 jugadores con especies fijas sobre una casa hecha a mano.
## Todo vuelve a la reserva; reinas y exterminadores en la entrada.
func _custom(h: PestsHouse, sp0: int, sp1: int) -> PestsGame:
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
	for pid in 2:
		var sp := g.species_of[pid]
		g.pool[sp] = 20
		g.reserve[sp] = 20
		g.queen_room[sp] = 0
		g.sealed[sp] = false
		g.exterminator_room[pid] = 0
	return g


## Pone al jugador en su fase de exterminador con el turno recién empezado.
func _exterminator_turn(g: PestsGame, pid: int) -> void:
	g.turns.current = pid
	g.phase = G.Phase.EXTERMINATOR
	g.free_move = true
	g.action_points = D.ACTION_POINTS


func _put(g: PestsGame, sp: int, room: int, count: int) -> void:
	g.reserve[sp] -= count
	g.pests[room][sp] += count


## Bloque 2x2: E(0,0) entrada, A(0,-1) nido de sp0, B(1,0), C(1,-1); y el nido
## de sp1 a la izquierda de la entrada.
func _square(sp0: int, sp1: int) -> Dictionary:
	var h := PestsHouse.new()
	var a := h.place_nest(Vector2i(0, -1), sp0)
	var b := h.place_custom(Vector2i(1, 0), D.DOOR_ALL)
	var c := h.place_custom(Vector2i(1, -1), D.DOOR_ALL)
	var n1 := h.place_nest(Vector2i(-1, 0), sp1)
	return {"game": _custom(h, sp0, sp1), "e": 0, "a": a, "b": b, "c": c, "n1": n1}


func _ok(g: PestsGame, type: StringName, pid: int, data: Dictionary = {}) -> void:
	var error := g.submit(GameAction.new(type, pid, data))
	assert_eq(error, "", "%s debería ser legal" % type)


func _rejected(g: PestsGame, type: StringName, pid: int, data: Dictionary = {}) -> void:
	assert_ne(g.submit(GameAction.new(type, pid, data)), "", "%s debería rechazarse" % type)


# --- Preparación -----------------------------------------------------------------

func test_quick_setup_infests_house() -> void:
	var g := _game(4)
	assert_eq(g.phase, G.Phase.QUEEN)
	assert_eq(g.turns.current, g.start_player)
	assert_eq(g.queen_steps.size(), 2, "el primer turno la reina tira dos veces")
	assert_eq(g.house.room_count(), 1 + 16 + 4)
	for pid in 4:
		var sp := g.species(pid)
		assert_true(sp >= 0)
		assert_eq(g.pests_in_house(sp), 7)
		assert_eq(g.reserve[sp], 22 - 7)
		var nest := g.house.nest_of(sp)
		assert_eq(g.queen_room[sp], nest)
		assert_true(g.pests_in_room(nest, sp) >= 3)
		assert_eq(g.exterminator_room[pid], 0)


func test_choose_species_counterclockwise() -> void:
	var g := _game(3, false, true, 5)
	assert_eq(g.phase, G.Phase.CHOOSE_SPECIES)
	var s := g.start_player
	assert_eq(g.turns.current, s)
	_rejected(g, G.CHOOSE_SPECIES, (s + 1) % 3, {"species": 0})
	_ok(g, G.CHOOSE_SPECIES, s, {"species": D.Species.PURPLE})
	assert_eq(g.turns.current, posmod(s - 1, 3), "el siguiente es el de la derecha")
	_rejected(g, G.CHOOSE_SPECIES, g.turns.current, {"species": D.Species.PURPLE})
	_ok(g, G.CHOOSE_SPECIES, g.turns.current, {"species": D.Species.RED})
	_ok(g, G.CHOOSE_SPECIES, g.turns.current, {"species": D.Species.BLUE})
	assert_eq(g.species(s), D.Species.PURPLE)
	# Elección de cartas: empieza el último en elegir exterminador (s + 1) y
	# sigue en sentido horario hasta 4 cartas cada uno.
	assert_eq(g.phase, G.Phase.DRAFT)
	assert_eq(g.draft_pool.size(), 24)
	assert_eq(g.turns.current, (s + 1) % 3)
	_rejected(g, G.DRAFT_CARD, g.turns.current, {"card": "nope"})
	_ok(g, G.DRAFT_CARD, g.turns.current, {"card": "zap"})
	assert_eq(g.turns.current, (s + 2) % 3)
	_rejected(g, G.DRAFT_CARD, g.turns.current, {"card": "zap"})
	while g.phase == G.Phase.DRAFT:
		var pid := g.turns.current
		_ok(g, G.DRAFT_CARD, pid, {"card": g.draft_pool[0]})
	for pid in 3:
		assert_eq(g.hands[pid].size(), 4)
	assert_true("zap" in g.hands[(s + 1) % 3])
	assert_eq(g.deck.size(), 24 - 12)
	assert_eq(g.phase, G.Phase.QUEEN)
	assert_eq(g.turns.current, s)


func test_manual_tile_placement() -> void:
	var g := _game(2, true, false, 3)
	assert_eq(g.phase, G.Phase.PLACE_TILES)
	assert_eq(g.tile_hands[0].size(), 8, "7 losetas normales + el nido")
	assert_eq(g.tile_hands[1].size(), 8)
	var pid := g.turns.current
	assert_eq(pid, g.start_player)
	var nest_index := -1
	for i in g.tile_hands[pid].size():
		if g.tile_hands[pid][i]["kind"] == D.RoomKind.NEST:
			nest_index = i
	assert_false(g.nest_allowed(pid))
	_rejected(g, G.PLACE_TILE, pid, {"index": nest_index, "x": 0, "y": -1, "rotation": 0})
	for o in g.tile_options(pid):
		assert_ne(o["index"], nest_index, "el nido no aparece en la 1.ª ronda")
	var placed := 0
	while g.phase == G.Phase.PLACE_TILES and placed < 100:
		var current := g.turns.current
		var options := g.tile_options(current)
		assert_false(options.is_empty())
		_ok(g, G.PLACE_TILE, current, options[options.size() / 2])
		placed += 1
	assert_eq(g.phase, G.Phase.QUEEN)
	assert_eq(g.house.room_count(), placed + 1)
	assert_true(g.house.is_fully_connected())
	assert_true(g.house.nest_of(g.species(0)) >= 0)
	assert_true(g.house.nest_of(g.species(1)) >= 0)
	assert_eq(g.pests_in_house(g.species(0)), 7)


func test_tile_placement_alternates_players() -> void:
	var g := _game(3, true, false, 9)
	var s := g.start_player
	_ok(g, G.PLACE_TILE, s, g.tile_options(s)[0])
	assert_eq(g.turns.current, (s + 1) % 3, "sentido horario")
	_rejected(g, G.PLACE_TILE, s, {"index": 0, "x": 5, "y": 5, "rotation": 0})


# --- La reina ----------------------------------------------------------------------

func test_queen_leaves_house_and_reenters() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.queen_room[sp] = s["a"]
	g.resolve_queen_face(sp, FACE_UP)
	# Sale de A por arriba: la puerta más cercana de otra habitación es la de arriba de C.
	assert_eq(g.queen_room[sp], s["c"])
	assert_eq(g.pests_in_room(s["c"], sp), 1, "suelta 1 plaga donde acaba")
	assert_eq(g.pests_in_room(s["a"], sp), 1, "sale 1 plaga del nido")
	assert_eq(g.reserve[sp], 18)


func test_angry_queen_drops_two() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.queen_room[sp] = s["e"]
	g.resolve_queen_face(sp, FACE_DOWN)  # la entrada no tiene puerta abajo
	assert_eq(g.queen_room[sp], s["e"])
	assert_eq(g.pests_in_room(s["e"], sp), 2)
	assert_eq(g.pests_in_room(s["a"], sp), 1)


func test_sealed_nest_spawns_nothing_and_orange_spawns_two() -> void:
	var s := _square(D.Species.ORANGE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.queen_room[D.Species.ORANGE] = s["e"]
	g.resolve_queen_face(D.Species.ORANGE, FACE_UP)  # E -> A
	assert_eq(g.pests_in_room(s["a"], D.Species.ORANGE), 1 + 2, "1 de la reina + 2 del nido naranja")
	g.sealed[D.Species.ORANGE] = true
	g.resolve_queen_face(D.Species.ORANGE, FACE_DOWN)  # A -> E
	assert_eq(g.pests_in_room(s["e"], D.Species.ORANGE), 1)
	assert_eq(g.pests_in_room(s["a"], D.Species.ORANGE), 3, "nido sellado: no sale ninguna")


func test_summon_splits_and_angry_without_pests() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.queen_room[sp] = s["a"]
	_put(g, sp, s["b"], 3)
	g.resolve_queen_face(sp, FACE_SUMMON)
	assert_eq(g.pests_in_room(s["b"], sp), 0)
	assert_eq(g.pests_in_room(s["e"], sp), 2)
	assert_eq(g.pests_in_room(s["c"], sp), 1)
	assert_eq(g.pests_in_room(s["a"], sp), 2, "1 que suelta la reina + 1 del nido")
	# Sin plagas fuera de la habitación de la reina: no puede invocar.
	var s2 := _square(D.Species.BLUE, D.Species.GREEN)
	var g2: PestsGame = s2["game"]
	g2.queen_room[sp] = s2["b"]
	g2.resolve_queen_face(sp, FACE_SUMMON)
	assert_eq(g2.pests_in_room(s2["b"], sp), 2, "enfadada: suelta 2")


func test_populate() -> void:
	var s := _square(D.Species.BLUE, D.Species.RED)
	var g: PestsGame = s["game"]
	g.queen_room[D.Species.BLUE] = s["e"]
	g.resolve_queen_face(D.Species.BLUE, FACE_POPULATE)
	# Vecinos de la entrada en DLUR: izquierda (nido rojo), arriba A, derecha B.
	assert_eq(g.pests_in_room(s["n1"], D.Species.BLUE), 2)
	assert_eq(g.pests_in_room(s["a"], D.Species.BLUE), 1 + 1, "1 al poblar + 1 del nido")
	assert_eq(g.pests_in_room(s["b"], D.Species.BLUE), 1)
	assert_eq(g.pests_in_room(s["e"], D.Species.BLUE), 0, "al poblar no suelta plaga en su habitación")
	# La reina roja puebla a 2 habitaciones: desde el nido rojo, A y B.
	g.queen_room[D.Species.RED] = s["n1"]
	g.resolve_queen_face(D.Species.RED, FACE_POPULATE)
	assert_eq(g.pests_in_room(s["a"], D.Species.RED), 2)
	assert_eq(g.pests_in_room(s["b"], D.Species.RED), 2)


func test_yellow_queen_moves_two_rooms() -> void:
	var h := PestsHouse.new()
	var x := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT | D.DOOR_RIGHT)
	var y := h.place_custom(Vector2i(2, 0), D.DOOR_LEFT)
	h.place_nest(Vector2i(0, -1), D.Species.YELLOW)
	h.place_nest(Vector2i(-1, 0), D.Species.GREEN)
	var g := _custom(h, D.Species.YELLOW, D.Species.GREEN)
	g.resolve_queen_face(D.Species.YELLOW, FACE_RIGHT)
	assert_eq(g.queen_room[D.Species.YELLOW], y)
	# Desde X solo puede avanzar una: cuenta como hecha (no se enfada).
	g.queen_room[D.Species.YELLOW] = x
	g.resolve_queen_face(D.Species.YELLOW, FACE_RIGHT)
	assert_eq(g.queen_room[D.Species.YELLOW], y)
	assert_eq(g.pests_in_room(y, D.Species.YELLOW), 2, "1 por cada tirada, sin enfado")


func test_trapped_queen_escapes_only_with_her_color() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.queen_room[sp] = s["b"]
	g.traps.append({"id": 50, "owner": 0, "room": s["b"], "pests": 0, "queen": true, "prefer_queen": true})
	g.resolve_queen_face(sp, FACE_UP)
	assert_true(g.is_queen_trapped(sp))
	assert_eq(g.queen_room[sp], s["b"])
	assert_eq(g.pests_in_room(s["b"], sp), 0, "atrapada no suelta plagas")
	assert_eq(g.pests_in_room(s["a"], sp), 1, "el nido sigue generando")
	g.resolve_queen_face(sp, FACE_SUMMON)  # cara azul
	assert_false(g.is_queen_trapped(sp))
	assert_eq(g.traps.size(), 0, "la trampa vuelve al jugador")
	assert_eq(g.queen_room[sp], s["b"])
	assert_eq(g.pests_in_room(s["b"], sp), 1)


func test_queen_walks_into_trap() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.queen_room[sp] = s["e"]
	g.traps.append({"id": 7, "owner": 0, "room": s["b"], "pests": 0, "queen": false, "prefer_queen": true})
	g.resolve_queen_face(sp, FACE_RIGHT)
	assert_true(g.is_queen_trapped(sp))
	assert_eq(g.find_trap(7)["pests"], 0, "una trampa con la reina no admite plagas")
	assert_eq(g.pests_in_room(s["b"], sp), 1, "la plaga que suelta queda libre")


# --- El exterminador -------------------------------------------------------------

func test_free_move_and_action_points() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	_rejected(g, G.MOVE, 0, {"room": s["c"]})  # no es vecina de la entrada
	_ok(g, G.MOVE, 0, {"room": s["b"]})
	assert_false(g.free_move)
	assert_eq(g.action_points, 2, "el movimiento gratis no gasta puntos")
	_ok(g, G.MOVE, 0, {"room": s["c"]})
	_ok(g, G.MOVE, 0, {"room": s["a"]})
	assert_eq(g.action_points, 0)
	_rejected(g, G.MOVE, 0, {"room": s["e"]})
	_ok(g, G.END_TURN, 0)
	assert_eq(g.turns.current, 1)
	assert_eq(g.phase, G.Phase.QUEEN)


func test_other_action_first_forfeits_free_move() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["e"], 2)
	_exterminator_turn(g, 0)
	_ok(g, G.EXTERMINATE, 0)
	assert_false(g.free_move)
	assert_eq(g.action_points, 1)
	assert_eq(g.pests_in_room(s["e"], D.Species.BLUE), maxi(0, 2 - g.last_roll))
	assert_eq(g.reserve[D.Species.BLUE], 20 - g.pests_in_room(s["e"], D.Species.BLUE), "vuelven a la reserva")
	_rejected(g, G.EXTERMINATE, 1)


func test_exterminate_bonus_and_own_color_only() -> void:
	var s := _square(D.Species.RED, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.RED, s["e"], 10)
	_put(g, D.Species.GREEN, s["e"], 10)
	_exterminator_turn(g, 0)
	var removed := g.exterminate(0, 3)
	assert_eq(removed, 3)
	assert_eq(g.pests_in_room(s["e"], D.Species.GREEN), 10, "solo las de su color")
	_ok(g, G.EXTERMINATE, 0)
	assert_eq(g.history[-1].data["removed"], g.last_roll + 1, "+1 del rojo")


func test_drop_trap_captures_up_to_capacity() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["b"], 12)
	_put(g, D.Species.GREEN, s["b"], 4)
	g.exterminator_room[0] = s["b"]
	_exterminator_turn(g, 0)
	_ok(g, G.DROP_TRAP, 0)
	assert_eq(g.traps.size(), 1)
	assert_eq(g.traps[0]["pests"], 9, "la trampa azul admite 9")
	assert_eq(g.pests_in_room(s["b"], D.Species.BLUE), 3)
	assert_eq(g.pests_in_room(s["b"], D.Species.GREEN), 4, "solo atrapa su color")
	_rejected(g, G.DROP_TRAP, 0)  # no le quedan trampas
	assert_eq(g.pests_in_traps(D.Species.BLUE), 9)


func test_green_has_two_traps_and_cannot_trap_in_nest() -> void:
	var s := _square(D.Species.GREEN, D.Species.BLUE)
	var g: PestsGame = s["game"]
	g.exterminator_room[0] = s["a"]
	_exterminator_turn(g, 0)
	_rejected(g, G.DROP_TRAP, 0)  # A es su nido
	_ok(g, G.MOVE, 0, {"room": s["e"]})
	_ok(g, G.DROP_TRAP, 0)
	_ok(g, G.DROP_TRAP, 0)
	assert_eq(g.traps_available(0), 0)


func test_trap_choice_between_queen_and_pests() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.queen_room[D.Species.BLUE] = s["b"]
	_put(g, D.Species.BLUE, s["b"], 2)
	g.exterminator_room[0] = s["b"]
	_exterminator_turn(g, 0)
	_ok(g, G.DROP_TRAP, 0, {"target": "queen"})
	assert_true(g.is_queen_trapped(D.Species.BLUE))
	assert_eq(g.pests_in_room(s["b"], D.Species.BLUE), 2)
	var s2 := _square(D.Species.BLUE, D.Species.GREEN)
	var g2: PestsGame = s2["game"]
	g2.queen_room[D.Species.BLUE] = s2["b"]
	_put(g2, D.Species.BLUE, s2["b"], 2)
	g2.exterminator_room[0] = s2["b"]
	_exterminator_turn(g2, 0)
	_ok(g2, G.DROP_TRAP, 0, {"target": "pests"})
	assert_false(g2.is_queen_trapped(D.Species.BLUE))
	assert_eq(g2.traps[0]["pests"], 2)


func test_yellow_trap_attracts_adjacent() -> void:
	var s := _square(D.Species.YELLOW, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.YELLOW, s["e"], 2)
	_put(g, D.Species.YELLOW, s["c"], 3)
	_put(g, D.Species.YELLOW, s["b"], 1)
	g.exterminator_room[0] = s["b"]
	_exterminator_turn(g, 0)
	_ok(g, G.DROP_TRAP, 0, {"target": "pests"})
	assert_eq(g.traps[0]["pests"], 6)
	assert_eq(g.pests_in_house(D.Species.YELLOW), 0)


func test_empty_trap_and_win() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.BLUE
	g.traps.append({"id": 1, "owner": 0, "room": s["e"], "pests": 4, "queen": false, "prefer_queen": true})
	g.reserve[sp] -= 4
	_exterminator_turn(g, 0)
	_ok(g, G.EMPTY_TRAP, 0, {"trap": 1})
	assert_eq(g.reserve[sp], 20, "las plagas vuelven a la reserva")
	assert_eq(g.traps.size(), 0)
	# Trampa con la reina: hace falta nido sellado y ninguna plaga en la casa.
	g.traps.append({"id": 2, "owner": 0, "room": s["e"], "pests": 0, "queen": true, "prefer_queen": true})
	_put(g, sp, s["c"], 1)
	_rejected(g, G.EMPTY_TRAP, 0, {"trap": 2})
	g.sealed[sp] = true
	_rejected(g, G.EMPTY_TRAP, 0, {"trap": 2})
	g.pests[s["c"]][sp] = 0
	_ok(g, G.EMPTY_TRAP, 0, {"trap": 2})
	assert_true(g.finished)
	assert_eq(g.winner_ids, [0] as Array[int])
	assert_eq(g.phase, G.Phase.FINISHED)


func test_destroy_trap_frees_contents_and_purple_costs_two() -> void:
	var s := _square(D.Species.PURPLE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	var sp := D.Species.PURPLE
	g.traps.append({"id": 3, "owner": 0, "room": s["e"], "pests": 5, "queen": false, "prefer_queen": true})
	g.reserve[sp] -= 5
	_exterminator_turn(g, 1)
	assert_eq(g.action_cost(1, G.DESTROY_TRAP, {"trap": 3}), 2)
	_rejected(g, G.DESTROY_TRAP, 0, {"trap": 3})  # no es su turno
	_ok(g, G.DESTROY_TRAP, 1, {"trap": 3})
	assert_eq(g.action_points, 0)
	assert_eq(g.pests_in_room(s["e"], sp), 5)
	assert_eq(g.traps.size(), 0)
	# No se puede destruir la propia.
	g.traps.append({"id": 4, "owner": 1, "room": s["e"], "pests": 0, "queen": false, "prefer_queen": true})
	_exterminator_turn(g, 1)
	_rejected(g, G.DESTROY_TRAP, 1, {"trap": 4})


func test_drag_trap() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.GREEN, s["b"], 3)
	g.traps.append({"id": 9, "owner": 1, "room": s["e"], "pests": 0, "queen": false, "prefer_queen": false})
	_exterminator_turn(g, 0)
	_ok(g, G.DRAG_TRAP, 0, {"trap": 9, "room": s["b"]})
	assert_eq(g.exterminator_room[0], s["b"])
	assert_eq(g.find_trap(9)["room"], s["b"])
	assert_eq(g.find_trap(9)["pests"], 3, "atrapa lo que hay al llegar")
	assert_eq(g.action_points, 0)
	assert_false(g.free_move)


func test_seal_and_unseal() -> void:
	var s := _square(D.Species.ORANGE, D.Species.BLUE)
	var g: PestsGame = s["game"]
	_exterminator_turn(g, 0)
	_rejected(g, G.SEAL_NEST, 0)  # no está en su nido
	_ok(g, G.MOVE, 0, {"room": s["a"]})
	_ok(g, G.SEAL_NEST, 0)
	assert_true(g.sealed[D.Species.ORANGE])
	assert_eq(g.action_points, 1, "el naranja sella con 1 punto")
	_rejected(g, G.SEAL_NEST, 0)
	_ok(g, G.END_TURN, 0)
	g.phase = G.Phase.EXTERMINATOR
	g.free_move = true
	g.action_points = 2
	g.exterminator_room[1] = s["e"]
	_ok(g, G.MOVE, 1, {"room": s["a"]})
	_ok(g, G.UNSEAL_NEST, 1)
	assert_false(g.sealed[D.Species.ORANGE])
	_rejected(g, G.UNSEAL_NEST, 1)


func test_elimination_ends_two_player_game() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["b"], 20)
	_exterminator_turn(g, 0)
	_ok(g, G.END_TURN, 0)
	assert_true(g.eliminated[0])
	assert_true(g.finished)
	assert_eq(g.winner_ids, [1] as Array[int])


func test_elimination_needs_no_trapped_pests() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["b"], 19)
	g.reserve[D.Species.BLUE] -= 1
	g.traps.append({"id": 1, "owner": 0, "room": s["c"], "pests": 1, "queen": false, "prefer_queen": true})
	_exterminator_turn(g, 0)
	_ok(g, G.END_TURN, 0)
	assert_false(g.eliminated[0], "una plaga en una trampa no está en la casa")


func test_elimination_skips_player_in_bigger_game() -> void:
	var g := _game(3, true, true, 4)
	var loser := g.start_player
	var sp := g.species(loser)
	# Todas sus plagas a la casa.
	g.pests[0][sp] += g.reserve[sp]
	g.reserve[sp] = 0
	_exterminator_turn(g, loser)
	_ok(g, G.END_TURN, loser)
	assert_true(g.eliminated[loser])
	assert_false(g.finished)
	assert_eq(g.pests_in_house(sp), 0, "sus plagas salen de la casa")
	assert_eq(g.queen_room[sp], -1)
	var next := g.turns.current
	assert_ne(next, loser)
	_exterminator_turn(g, next)
	_ok(g, G.END_TURN, next)
	assert_ne(g.turns.current, loser, "se salta al eliminado")


# --- Turnos completos, partidas al azar y guardado ----------------------------------

func test_first_turn_rolls_twice_then_once() -> void:
	var g := _game(2, true, true, 11)
	var p := g.turns.current
	_ok(g, G.ROLL_QUEEN, p)
	assert_eq(g.phase, G.Phase.QUEEN)
	_ok(g, G.ROLL_QUEEN, p)
	assert_eq(g.phase, G.Phase.EXTERMINATOR)
	assert_true(g.free_move)
	assert_eq(g.action_points, 2)
	_rejected(g, G.ROLL_QUEEN, p)
	_ok(g, G.END_TURN, p)
	var q := g.turns.current
	assert_ne(q, p)
	assert_eq(g.queen_steps.size(), 2, "el primer turno del segundo jugador también es doble")
	_ok(g, G.ROLL_QUEEN, q)
	_ok(g, G.ROLL_QUEEN, q)
	_ok(g, G.END_TURN, q)
	assert_eq(g.queen_steps.size(), 1)
	assert_eq(g.turns.round_number, 2)


func _play_random(g: PestsGame, rng: BGCRng, max_actions: int) -> int:
	var count := 0
	while not g.finished and count < max_actions:
		var pid: int = g.players_to_act()[0]
		var legal := g.get_legal_actions(pid)
		assert_false(legal.is_empty(), "siempre hay alguna acción legal")
		if legal.is_empty():
			return count
		# Termina el turno con menos frecuencia para que pasen cosas.
		var action: GameAction = rng.pick(legal)
		if action.type == G.END_TURN and legal.size() > 1 and rng.randf() < 0.7:
			action = rng.pick(legal)
		assert_eq(g.submit(action), "", "la acción legal se acepta")
		_check_conservation(g)
		count += 1
	return count


func _check_conservation(g: PestsGame) -> void:
	var cards := g.deck.size() + g.discard.size() + g.draft_pool.size() + g.played_this_turn.size() + g.effects.size()
	for h in g.hands:
		cards += h.size()
	if cards != 24 and g.phase != G.Phase.CHOOSE_SPECIES:
		assert_eq(cards, 24, "se conservan las cartas")
	if g.phase in [G.Phase.CHOOSE_SPECIES, G.Phase.DRAFT, G.Phase.PLACE_TILES]:
		return
	for pid in g.players.size():
		if g.eliminated[pid]:
			continue
		var sp := g.species(pid)
		var total := g.reserve[sp] + g.pests_in_house(sp) + g.pests_in_traps(sp)
		if total != g.pool[sp]:
			assert_eq(total, g.pool[sp], "se conservan las plagas de %s" % D.COLOR_NAMES[sp])
			return
		if g.reserve[sp] < 0:
			_fail("reserva negativa")


func test_random_games_respect_invariants() -> void:
	for n in range(2, 7):
		var g := _game(n, false, n % 2 == 0, 100 + n)
		_play_random(g, BGCRng.new(n), 1500)


func test_save_and_replay() -> void:
	var g := _game(3, false, false, 42)
	_play_random(g, BGCRng.new(1), 400)
	var data := g.save_data()
	var copy := PestsGame.new()
	copy.options = PestsGame.options_from_save(data)
	copy.setup(GameBase.players_from_save(data), data["seed"])
	assert_eq(copy.replay(data["history"]), "")
	assert_eq(copy.pests, g.pests)
	assert_eq(copy.house.room_cell, g.house.room_cell)
	assert_eq(copy.queen_room, g.queen_room)
	assert_eq(copy.turns.current, g.turns.current)
