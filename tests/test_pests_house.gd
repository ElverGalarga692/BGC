extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")


## Entrada en (0,0) + tres habitaciones de 4 puertas formando un bloque 2x2:
##   A(0,-1) C(1,-1)
##   E(0, 0) B(1, 0)
func _square() -> Dictionary:
	var h := PestsHouse.new()
	var a := h.place_custom(Vector2i(0, -1), D.DOOR_ALL)
	var b := h.place_custom(Vector2i(1, 0), D.DOOR_ALL)
	var c := h.place_custom(Vector2i(1, -1), D.DOOR_ALL)
	return {"house": h, "e": 0, "a": a, "b": b, "c": c}


func test_entry() -> void:
	var h := PestsHouse.new()
	assert_eq(h.room_count(), 1)
	assert_eq(h.room_at(Vector2i.ZERO), 0)
	assert_eq(h.room_name(0), "Entrada")
	assert_true(h.is_blocked(Vector2i(0, 1)))
	assert_eq(h.frontier(), [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)] as Array[Vector2i])


func test_can_place() -> void:
	var h := PestsHouse.new()
	assert_eq(h.can_place(Vector2i(0, -1), D.DOOR_ALL), "")
	assert_ne(h.can_place(Vector2i(0, 0), D.DOOR_ALL), "", "ocupada")
	assert_ne(h.can_place(Vector2i(0, 1), D.DOOR_ALL), "", "jardín")
	assert_ne(h.can_place(Vector2i(3, 3), D.DOOR_ALL), "", "no toca la casa")
	# Encima de la entrada sin puerta abajo: la puerta de la entrada daría a una pared.
	assert_ne(h.can_place(Vector2i(0, -1), D.DOOR_LEFT | D.DOOR_RIGHT), "")
	# Debajo-derecha de la entrada (1,1): solo toca el jardín, no una habitación.
	assert_ne(h.can_place(Vector2i(1, 1), D.DOOR_ALL), "")
	h.place_custom(Vector2i(1, 0), D.DOOR_LEFT | D.DOOR_UP)
	# (1,-1): la habitación de abajo tiene puerta arriba, así que hace falta puerta abajo.
	assert_ne(h.can_place(Vector2i(1, -1), D.DOOR_LEFT | D.DOOR_UP), "")
	assert_eq(h.can_place(Vector2i(1, -1), D.DOOR_DOWN), "")
	# (0,-1) toca la entrada (puerta) y nada más: válido con puerta abajo.
	assert_eq(h.can_place(Vector2i(0, -1), D.DOOR_DOWN | D.DOOR_RIGHT), "")


func test_place_standard_rotates() -> void:
	var h := PestsHouse.new()
	# Vestidor: puertas arriba y abajo. Girado 1 vuelta: izquierda y derecha.
	var r := h.place_standard(Vector2i(1, 0), 0, 1)
	assert_eq(h.room_doors[r], D.DOOR_LEFT | D.DOOR_RIGHT)
	assert_eq(h.room_name(r), "Vestidor")
	var n := h.place_nest(Vector2i(-1, 0), D.Species.RED)
	assert_eq(h.nest_of(D.Species.RED), n)
	assert_eq(h.nest_of(D.Species.BLUE), -1)
	assert_eq(h.room_name(n), "Nido rojo")


func test_placements_for() -> void:
	var h := PestsHouse.new()
	# Una loseta de esquina (izquierda+abajo) solo cabe girada para conectar.
	var options := h.placements_for(D.DOOR_LEFT | D.DOOR_DOWN)
	assert_true(options.size() > 0)
	for o in options:
		assert_eq(h.can_place(o["cell"], D.rotate_doors(D.DOOR_LEFT | D.DOOR_DOWN, o["rotation"])), "")
	assert_eq(PestsHouse.distinct_rotations(D.DOOR_ALL), [0] as Array[int])
	assert_eq(PestsHouse.distinct_rotations(D.DOOR_UP | D.DOOR_DOWN), [0, 1] as Array[int])


func test_neighbors_dlur() -> void:
	var s := _square()
	var h: PestsHouse = s["house"]
	# Desde B(1,0): abajo nada, izquierda E, arriba C, derecha nada.
	assert_eq(h.neighbors(s["b"]), [s["e"], s["c"]] as Array[int])
	# La entrada no tiene puerta abajo (jardín).
	assert_eq(h.neighbors(s["e"]), [s["a"], s["b"]] as Array[int])
	assert_eq(h.distance(s["b"], s["a"]), 2)
	assert_true(h.is_fully_connected())


func test_walls_and_through_walls() -> void:
	var h := PestsHouse.new()
	var x := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT)
	var y := h.place_custom(Vector2i(1, -1), D.DOOR_LEFT)
	assert_eq(h.neighbors(x), [0] as Array[int])
	assert_eq(h.neighbors(x, true), [0, y] as Array[int])
	assert_eq(h.distance(x, y), -1)
	assert_eq(h.distance(x, y, true), 1)
	assert_false(h.is_fully_connected())


func test_summon_split_equal_paths() -> void:
	var s := _square()
	var h: PestsHouse = s["house"]
	# Desde B hasta A hay dos caminos de 2: por E (izquierda) y por C (arriba).
	assert_eq(h.steps_toward(s["b"], s["a"]), [s["e"], s["c"]] as Array[int])
	# 3 plagas: 1 y 1, y la que sobra va por la izquierda (antes que arriba en DLUR).
	assert_eq(h.summon_split(s["b"], 3, s["a"]), {s["e"]: 2, s["c"]: 1})
	assert_eq(h.summon_split(s["b"], 4, s["a"]), {s["e"]: 2, s["c"]: 2})
	assert_eq(h.summon_split(s["b"], 1, s["a"]), {s["e"]: 1})
	# Un solo camino.
	assert_eq(h.summon_split(s["e"], 5, s["a"]), {s["a"]: 5})
	# Ya está con la reina, o no hay plagas.
	assert_eq(h.summon_split(s["a"], 2, s["a"]), {s["a"]: 2})
	assert_eq(h.summon_split(s["b"], 0, s["a"]), {})


func test_summon_split_unreachable() -> void:
	var h := PestsHouse.new()
	var x := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT)
	var y := h.place_custom(Vector2i(1, -1), D.DOOR_LEFT)
	assert_eq(h.summon_split(y, 3, x), {y: 3}, "sin camino se quedan")
	assert_eq(h.summon_split(y, 3, x, true), {x: 3}, "atravesando la pared llegan")


func test_spread_dlur() -> void:
	var s := _square()
	var h: PestsHouse = s["house"]
	# Infestación inicial: 4 plagas alrededor de A. Vecinos de A en DLUR: E (abajo), C (derecha).
	assert_eq(h.spread(s["a"], 4), {s["e"]: 2, s["c"]: 2})
	assert_eq(h.spread(s["a"], 3), {s["e"]: 2, s["c"]: 1})
	# Con 3 vecinos (desde E no: tiene 2). Habitación con 3 vecinos: añade D(-1,0) a la entrada.
	var d := h.place_custom(Vector2i(-1, 0), D.DOOR_RIGHT)
	# Vecinos de E en DLUR: izquierda D, arriba A, derecha B.
	assert_eq(h.spread(s["e"], 4), {d: 2, s["a"]: 1, s["b"]: 1})
	# A 2 habitaciones (reina roja): desde D -> E a 1, A y B a 2.
	assert_eq(h.spread(d, 4, 2), {s["a"]: 2, s["b"]: 2})
	# Sin habitaciones a 2, se usa la distancia 1.
	var h2 := PestsHouse.new()
	var only := h2.place_custom(Vector2i(0, -1), D.DOOR_DOWN)
	assert_eq(h2.spread(0, 4, 2), {only: 4})
	# Sin vecinos: se quedan.
	var h3 := PestsHouse.new()
	assert_eq(h3.spread(0, 4), {0: 4})


func test_queen_step_moves_and_blocks() -> void:
	var s := _square()
	var h: PestsHouse = s["house"]
	assert_eq(h.queen_step(s["e"], D.Dir.UP), {"result": PestsHouse.Step.MOVED, "room": s["a"]})
	# La entrada no tiene puerta abajo: pared.
	assert_eq(h.queen_step(s["e"], D.Dir.DOWN), {"result": PestsHouse.Step.BLOCKED, "room": s["e"]})
	var h2 := PestsHouse.new()
	var x := h2.place_custom(Vector2i(1, 0), D.DOOR_LEFT)
	var y := h2.place_custom(Vector2i(1, -1), D.DOOR_DOWN | D.DOOR_LEFT)
	# Pared entre X e Y (Y tiene puerta abajo pero X no arriba: casa inválida a propósito).
	assert_eq(h2.queen_step(x, D.Dir.UP)["result"], PestsHouse.Step.BLOCKED)
	assert_eq(h2.queen_step(x, D.Dir.UP, true), {"result": PestsHouse.Step.MOVED, "room": y})


func test_reentry_nearest_door_clockwise() -> void:
	# Entrada + A encima, con 4 puertas. La reina sale de A por arriba.
	var h := PestsHouse.new()
	var a := h.place_custom(Vector2i(0, -1), D.DOOR_ALL)
	# Las puertas izquierda/derecha de A son las más cercanas (distancia 1)...
	# pero llevan a A, que es de donde sale. Las de la entrada (izq. y der.)
	# están a 3 casillas en ambos sentidos: gana el sentido del reloj (derecha).
	var r := h.queen_step(a, D.Dir.UP)
	assert_eq(r, {"result": PestsHouse.Step.REENTERED, "room": 0})
	# Si sale por la izquierda de A, la puerta izquierda de la entrada está a 1.
	assert_eq(h.reentry(a, Vector2i(-1, -1)), 0)


func test_reentry_prefers_shorter_path() -> void:
	# Fila: D(-1,0) E(0,0) B(1,0), y A encima de E. La reina sale de A por arriba.
	var h := PestsHouse.new()
	var a := h.place_custom(Vector2i(0, -1), D.DOOR_UP | D.DOOR_DOWN)
	var b := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT | D.DOOR_UP)
	var d := h.place_custom(Vector2i(-1, 0), D.DOOR_RIGHT | D.DOOR_LEFT)
	# Arriba de B, en (1,-1): está a 1 de (0,-2) en diagonal = 2 pasos.
	# La puerta izquierda de D, en (-2,0): 4 pasos. Gana B.
	assert_eq(h.queen_step(a, D.Dir.UP), {"result": PestsHouse.Step.REENTERED, "room": b})
	assert_ne(d, b)


func test_reentry_counterclockwise_tie_breaker() -> void:
	# Igual que el primero pero saliendo por abajo de una habitación de abajo:
	# así se comprueba que el sentido del reloj depende de la posición.
	var h := PestsHouse.new()
	var a := h.place_custom(Vector2i(-1, 0), D.DOOR_RIGHT | D.DOOR_DOWN | D.DOOR_UP)
	# Sale de A por abajo a (-1,1). Puertas a otra habitación: arriba de la entrada (0,-1)
	# y derecha de la entrada (1,0). A (1,0): (-1,1)->(0,1)jardín->(1,1)->(1,0) = 3.
	# A (0,-1): (-1,1)... rodeando A por la izquierda: (-2,1),(-2,0),(-2,-1),(-1,-1),(0,-1) = 5.
	assert_eq(h.queen_step(a, D.Dir.DOWN), {"result": PestsHouse.Step.REENTERED, "room": 0})
	# Desde (-1,-1) (arriba de A): (0,-1) está a 1 -> la entrada por su puerta de arriba.
	assert_eq(h.reentry(a, Vector2i(-1, -1)), 0)


func test_courtyard() -> void:
	# Anillo de 8 habitaciones alrededor de un patio en (0,-2); la entrada debajo.
	var h := PestsHouse.new()
	var south := h.place_custom(Vector2i(0, -1), D.DOOR_DOWN | D.DOOR_UP)
	var ring := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(1, -2),
		Vector2i(-1, -3), Vector2i(0, -3), Vector2i(1, -3)]
	var rooms := {}
	for c in ring:
		rooms[c] = h.place_custom(c, 0)
	assert_eq(h.queen_step(south, D.Dir.UP), {"result": PestsHouse.Step.COURTYARD, "room": south})
	# Quien atraviesa paredes sí puede entrar por otra pared del patio.
	var through := h.queen_step(south, D.Dir.UP, true)
	assert_eq(through["result"], PestsHouse.Step.REENTERED)
	assert_ne(through["room"], south)
	# Con una puerta hacia el patio en la habitación de la derecha, entra por ahí.
	var h2 := PestsHouse.new()
	var s2 := h2.place_custom(Vector2i(0, -1), D.DOOR_DOWN | D.DOOR_UP)
	var east := -1
	for c in ring:
		var doors := D.DOOR_LEFT if c == Vector2i(1, -2) else 0
		var r := h2.place_custom(c, doors)
		if c == Vector2i(1, -2):
			east = r
	assert_eq(h2.queen_step(s2, D.Dir.UP), {"result": PestsHouse.Step.REENTERED, "room": east})


func test_through_walls_exit() -> void:
	var h := PestsHouse.new()
	var x := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT)
	# X no tiene puerta arriba: la reina normal choca.
	assert_eq(h.queen_step(x, D.Dir.UP)["result"], PestsHouse.Step.BLOCKED)
	# La morada sale por la pared a (1,-1) y entra por la pared más cercana de
	# otra habitación: la entrada, desde (0,-1).
	assert_eq(h.queen_step(x, D.Dir.UP, true), {"result": PestsHouse.Step.REENTERED, "room": 0})


func test_bounds() -> void:
	var h := PestsHouse.new()
	assert_eq(h.bounds(), Rect2i(0, 0, 1, 2))
	h.place_custom(Vector2i(-2, -1), 0)
	assert_eq(h.bounds(), Rect2i(-2, -1, 3, 3))


func test_generator_builds_valid_houses() -> void:
	for players in range(D.MIN_PLAYERS, D.MAX_PLAYERS + 1):
		for s_i in 8:
			var rng := BGCRng.new(s_i * 31 + players)
			var species: Array[int] = []
			for s in players:
				species.append(s)
			var tiles := PestsHouseGenerator.tiles_for_game(species, rng)
			assert_eq(tiles.size(), 18 - D.TILES_REMOVED[players] + players)
			var house := PestsHouseGenerator.generate(tiles, rng)
			assert_true(house != null, "casa generada (%d jugadores, semilla %d)" % [players, s_i])
			if house == null:
				continue
			assert_eq(house.room_count(), tiles.size() + 1)
			assert_true(house.is_fully_connected(), "todas las habitaciones conectadas")
			for s in species:
				assert_true(house.nest_of(s) >= 0)
			_assert_doors_consistent(house)


func test_generator_is_deterministic() -> void:
	var species: Array[int] = [0, 1, 2, 3]
	var a := PestsHouseGenerator.generate(PestsHouseGenerator.tiles_for_game(species, BGCRng.new(7)), BGCRng.new(7))
	var b := PestsHouseGenerator.generate(PestsHouseGenerator.tiles_for_game(species, BGCRng.new(7)), BGCRng.new(7))
	assert_eq(a.room_cell, b.room_cell)
	assert_eq(a.room_doors, b.room_doors)


func _assert_doors_consistent(house: PestsHouse) -> void:
	for r in house.room_count():
		for dir in 4:
			var other := house.room_at(house.room_cell[r] + D.DIR_VECTORS[dir])
			if other >= 0:
				assert_eq(house.has_door(r, dir), house.has_door(other, D.opposite(dir)),
					"puertas alineadas entre %d y %d" % [r, other])
		assert_false(house.room_cell[r] == PestsHouse.LAWN_CELL)


func test_reentry_clockwise_picks_right_side() -> void:
	# L(-1,0) E(0,0) R(1,0) y A encima de E. L y R solo tienen puerta exterior
	# hacia fuera (izquierda y derecha). Saliendo de A por arriba, las dos
	# están a 4 casillas: en el sentido del reloj se llega antes a la derecha.
	var h := PestsHouse.new()
	var a := h.place_custom(Vector2i(0, -1), D.DOOR_UP | D.DOOR_DOWN)
	var l := h.place_custom(Vector2i(-1, 0), D.DOOR_LEFT | D.DOOR_RIGHT)
	var r := h.place_custom(Vector2i(1, 0), D.DOOR_LEFT | D.DOOR_RIGHT)
	assert_eq(h.queen_step(a, D.Dir.UP), {"result": PestsHouse.Step.REENTERED, "room": r})
	assert_ne(l, r)
