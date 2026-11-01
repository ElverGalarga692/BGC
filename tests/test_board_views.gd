extends TestCase
## Vistas del tablero (2D y 3D): ambas cumplen el mismo contrato.

const Pick := ArchBoardView.Pick


func _game() -> ArchipelagoGame:
	var game := ArchipelagoGame.new()
	var players: Array[PlayerInfo] = [PlayerInfo.new(0), PlayerInfo.new(1), PlayerInfo.new(2)]
	game.setup(players, 8)
	while game.phase == ArchipelagoGame.Phase.SETUP:
		game.submit(game.get_legal_actions(game.turns.current)[0])
	return game


func test_pick_unit_shared() -> void:
	var game := _game()
	var grid := game.board.grid
	var none: Array[int] = []
	assert_eq(ArchBoardView.pick_unit(game.board, grid.vertex_positions[5], Pick.NONE, none), [Pick.VERTEX, 5])
	assert_eq(ArchBoardView.pick_unit(game.board, grid.edge_midpoint(9), Pick.NONE, none), [Pick.EDGE, 9])
	assert_eq(ArchBoardView.pick_unit(game.board, grid.tile_center(3), Pick.NONE, none), [Pick.TILE, 3])
	assert_eq(ArchBoardView.pick_unit(game.board, Vector2(40, 40), Pick.NONE, none), [Pick.NONE, -1])
	# Con objetivos, solo se pueden elegir ellos.
	var targets: Array[int] = [12]
	assert_eq(ArchBoardView.pick_unit(game.board, grid.vertex_positions[12] + Vector2(0.2, 0), Pick.VERTEX, targets), [Pick.VERTEX, 12])
	assert_eq(ArchBoardView.pick_unit(game.board, grid.vertex_positions[5], Pick.VERTEX, targets)[0], Pick.NONE)


func _view_contract(view: Object) -> void:
	for method in ["set_targets", "refresh", "fit"]:
		assert_true(view.has_method(method), "la vista tiene %s()" % method)
	for sig in ["hovered", "clicked"]:
		assert_true(view.has_signal(sig), "la vista tiene la señal %s" % sig)
	assert_true("game" in view, "la vista tiene la propiedad game")


func test_both_views_share_contract() -> void:
	var v2 := ArchBoardView.new()
	var v3 := ArchBoardView3D.new()
	_view_contract(v2)
	_view_contract(v3)
	v2.free()
	v3.free()


func test_3d_view_builds_pieces() -> void:
	var game := _game()
	var view := ArchBoardView3D.new()
	view.game = game
	var buildings := 0
	var roads := 0
	for v in game.vertex_owner.size():
		buildings += 1 if game.vertex_owner[v] != -1 else 0
	for e in game.edge_owner.size():
		roads += 1 if game.edge_owner[e] != -1 else 0
	assert_eq(view._pieces.size(), buildings + roads)
	assert_eq(view._board_root.get_child_count(), 1 + 19 + 9, "mar + 19 fichas + 9 puertos")
	# Mejorar a ciudad sustituye la pieza.
	var pid := game.turns.current
	game.phase = ArchipelagoGame.Phase.MAIN
	game.hands[pid].assign([0, 0, 0, 2, 3])
	var v := game.legal_city_vertices(pid)[0]
	assert_eq(game.submit(GameAction.new(ArchipelagoGame.BUILD_CITY, pid, {"vertex": v})), "")
	view.refresh()
	assert_eq(view._pieces["v%d" % v][1], ArchipelagoGame.Building.CITY)
	assert_eq(view._pieces.size(), buildings + roads)
	view.free()


func test_3d_view_markers() -> void:
	var game := _game()
	var view := ArchBoardView3D.new()
	view.game = game
	var tiles := game.bandit_tiles()
	view.set_targets(Pick.TILE, tiles)
	assert_eq(view._markers_root.get_child_count(), tiles.size())
	view.set_targets(Pick.NONE, [])
	view._markers_root.get_children().map(func(n: Node) -> void: pass)
	assert_eq(view._target_kind, Pick.NONE)
	view.free()
