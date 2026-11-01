extends TestCase


func _board(seed: int) -> ArchBoard:
	return ArchBoardGenerator.generate(BGCRng.new(seed))


func test_terrain_distribution() -> void:
	var board := _board(1)
	var counts := {}
	for terrain in board.tile_terrain:
		counts[terrain] = counts.get(terrain, 0) + 1
	assert_eq(counts, ArchDefs.TERRAIN_COUNTS)


func test_numbers() -> void:
	for seed in 30:
		var board := _board(seed)
		var numbers: Array = []
		for t in board.grid.tile_count():
			if board.tile_terrain[t] == ArchDefs.Terrain.DESERT:
				assert_eq(board.tile_number[t], 0, "el desierto no tiene número")
				assert_eq(board.bandit_tile, t, "el bandido empieza en el desierto")
			else:
				numbers.append(board.tile_number[t])
		numbers.sort()
		assert_eq(numbers, ArchDefs.NUMBER_TOKENS)


func test_hot_numbers_never_adjacent() -> void:
	for seed in 100:
		assert_true(ArchBoardGenerator.numbers_are_valid(_board(seed)), "semilla %d" % seed)


func test_ports() -> void:
	for seed in 30:
		var board := _board(seed)
		assert_eq(board.ports.size(), 9)
		var used_vertices := {}
		var types: Array = []
		for port in board.ports:
			assert_true(board.grid.is_coastal_edge(port["edge"]), "los puertos están en la costa")
			types.append(port["type"])
			for v in board.grid.edge_vertices[port["edge"]]:
				assert_false(used_vertices.has(v), "dos puertos comparten vértice (semilla %d)" % seed)
				used_vertices[v] = true
		types.sort()
		var expected: Array = ArchDefs.PORT_TYPES.duplicate()
		expected.sort()
		assert_eq(types, expected)


func test_vertex_port_lookup() -> void:
	var board := _board(3)
	var port: Dictionary = board.ports[0]
	var v: int = board.grid.edge_vertices[port["edge"]][0]
	assert_eq(board.vertex_port(v), port)


func test_same_seed_same_board() -> void:
	assert_eq(_board(42).to_dict(), _board(42).to_dict())
	assert_ne(_board(42).to_dict(), _board(43).to_dict())


func test_game_setup_creates_board() -> void:
	var game := ArchipelagoGame.new()
	var players: Array[PlayerInfo] = [PlayerInfo.new(0), PlayerInfo.new(1), PlayerInfo.new(2)]
	game.setup(players, 42)
	assert_eq(game.board.grid.tile_count(), 19)
	assert_eq(game.board.to_dict(), _board(42).to_dict(), "el juego usa la semilla de la partida")


func test_pips() -> void:
	assert_eq(ArchDefs.number_pips(6), 5)
	assert_eq(ArchDefs.number_pips(2), 1)
	assert_eq(ArchDefs.number_pips(7), 6)
