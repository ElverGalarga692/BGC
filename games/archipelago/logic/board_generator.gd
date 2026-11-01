class_name ArchBoardGenerator
extends RefCounted
## Genera tableros aleatorios (pero reproducibles con la semilla) de
## Archipiélago, cumpliendo las reglas de equilibrio:
##   - el desierto no lleva ficha numérica,
##   - los números "calientes" (6 y 8) nunca quedan en casillas vecinas,
##   - los puertos se reparten de forma uniforme por la costa, sin que dos
##     puertos compartan vértice.

const MAX_ATTEMPTS := 2000


static func generate(rng: BGCRng) -> ArchBoard:
	var board := ArchBoard.new()
	_place_terrains(board, rng)
	_place_numbers(board, rng)
	_place_ports(board, rng)
	return board


static func _place_terrains(board: ArchBoard, rng: BGCRng) -> void:
	var pool := ArchDefs.terrain_pool()
	assert(pool.size() == board.grid.tile_count(), "El reparto de terrenos no coincide con el tablero")
	rng.shuffle(pool)
	for t in pool.size():
		board.tile_terrain[t] = pool[t]
		if pool[t] == ArchDefs.Terrain.DESERT:
			board.bandit_tile = t


static func _place_numbers(board: ArchBoard, rng: BGCRng) -> void:
	var slots: Array[int] = []
	for t in board.grid.tile_count():
		board.tile_number[t] = 0
		if board.tile_terrain[t] != ArchDefs.Terrain.DESERT:
			slots.append(t)
	var tokens: Array = ArchDefs.NUMBER_TOKENS.duplicate()
	assert(tokens.size() == slots.size(), "El número de fichas no coincide con el tablero")

	for attempt in MAX_ATTEMPTS:
		rng.shuffle(tokens)
		for i in slots.size():
			board.tile_number[slots[i]] = tokens[i]
		if numbers_are_valid(board):
			return
	push_warning("No se encontró un reparto de números válido en %d intentos" % MAX_ATTEMPTS)


## true si ningún par de casillas vecinas tiene ambas un número caliente.
static func numbers_are_valid(board: ArchBoard) -> bool:
	for t in board.grid.tile_count():
		if not board.tile_number[t] in ArchDefs.HOT_NUMBERS:
			continue
		for n in board.grid.tile_neighbors(t):
			if board.tile_number[n] in ArchDefs.HOT_NUMBERS:
				return false
	return true


static func _place_ports(board: ArchBoard, rng: BGCRng) -> void:
	var coast := board.grid.coastal_edges()
	var types: Array = ArchDefs.PORT_TYPES.duplicate()
	rng.shuffle(types)
	var offset := rng.randi_range(0, coast.size() - 1)
	board.ports.clear()
	for i in types.size():
		var index := offset + roundi(float(i) * coast.size() / types.size())
		board.ports.append({"edge": coast[index % coast.size()], "type": types[i]})
