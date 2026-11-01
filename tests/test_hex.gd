extends TestCase


func test_distance() -> void:
	assert_eq(HexCoords.distance(Vector2i.ZERO, Vector2i(2, -1)), 2)
	assert_eq(HexCoords.distance(Vector2i(1, 1), Vector2i(-1, -1)), 4)


func test_ring_and_spiral_sizes() -> void:
	assert_eq(HexCoords.ring(0).size(), 1)
	assert_eq(HexCoords.ring(1).size(), 6)
	assert_eq(HexCoords.ring(2).size(), 12)
	assert_eq(HexCoords.spiral(2).size(), 19)
	for h in HexCoords.ring(2):
		assert_eq(HexCoords.distance(Vector2i.ZERO, h), 2)


func test_pixel_roundtrip() -> void:
	for h in HexCoords.spiral(3):
		assert_eq(HexCoords.from_pixel(HexCoords.to_pixel(h, 40.0), 40.0), h)
		# Un punto cerca del centro sigue dentro del mismo hexágono.
		var p := HexCoords.to_pixel(h, 40.0) + Vector2(15, -10)
		assert_eq(HexCoords.from_pixel(p, 40.0), h)


func test_standard_grid_counts() -> void:
	var grid := HexGrid.hexagonal(2)
	assert_eq(grid.tile_count(), 19)
	assert_eq(grid.vertex_count(), 54)
	assert_eq(grid.edge_count(), 72)
	assert_eq(grid.coastal_edges().size(), 30)


func test_grid_topology_is_consistent() -> void:
	var grid := HexGrid.hexagonal(2)
	for t in grid.tile_count():
		assert_eq(grid.tile_vertices[t].size(), 6)
		assert_eq(grid.tile_edges[t].size(), 6)
		for i in 6:
			var e: int = grid.tile_edges[t][i]
			var a: int = grid.tile_vertices[t][i]
			var b: int = grid.tile_vertices[t][(i + 1) % 6]
			assert_eq(grid.edge_between(a, b), e)
	for v in grid.vertex_count():
		var n: int = grid.vertex_tiles[v].size()
		assert_true(n >= 1 and n <= 3)
		assert_true(grid.vertex_edges[v].size() in [2, 3])
		assert_eq(grid.vertex_edges[v].size(), grid.vertex_neighbors[v].size())
		for w in grid.vertex_neighbors[v]:
			assert_true(v in grid.vertex_neighbors[w], "vecindad simétrica")
	for e in grid.edge_count():
		assert_true(grid.edge_tiles[e].size() in [1, 2])
		var ev: Array = grid.edge_vertices[e]
		assert_true(absf(grid.vertex_positions[ev[0]].distance_to(grid.vertex_positions[ev[1]]) - 1.0) < 0.001, "las aristas miden 1")


func test_tile_neighbors() -> void:
	var grid := HexGrid.hexagonal(2)
	var center := grid.tile_at(Vector2.ZERO)
	assert_eq(grid.tile_neighbors(center).size(), 6)
	var corner := grid.tile_index[Vector2i(2, 0)] as int
	assert_eq(grid.tile_neighbors(corner).size(), 3)


func test_picking() -> void:
	var grid := HexGrid.hexagonal(2)
	assert_eq(grid.vertex_near(grid.vertex_positions[10] + Vector2(0.05, 0.05), 0.3), 10)
	assert_eq(grid.vertex_near(Vector2(20, 20), 0.3), -1)
	assert_eq(grid.edge_near(grid.edge_midpoint(33), 0.3), 33)
	assert_eq(grid.tile_at(Vector2(100, 100)), -1)
