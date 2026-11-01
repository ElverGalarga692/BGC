extends TestCase



func _new_game(player_count: int = 3, seed: int = 42) -> ArchipelagoGame:
	var game := ArchipelagoGame.new()
	var players: Array[PlayerInfo] = []
	for i in player_count:
		players.append(PlayerInfo.new(i))
	game.setup(players, seed)
	return game


func _act(game: ArchipelagoGame, type: StringName, data: Dictionary = {}) -> String:
	return game.submit(GameAction.new(type, game.turns.current, data))


## Completa la colocación inicial eligiendo siempre la primera opción legal.
func _finish_setup(game: ArchipelagoGame) -> void:
	while game.phase == ArchipelagoGame.Phase.SETUP:
		var actions := game.get_legal_actions(game.turns.current)
		assert_eq(game.submit(actions[0]), "")


func _total_cards(game: ArchipelagoGame, r: int) -> int:
	var total := game.bank[r]
	for hand in game.hands:
		total += hand[r]
	return total


func test_setup_snake_order() -> void:
	var game := _new_game(3)
	var order: Array[int] = []
	while game.phase == ArchipelagoGame.Phase.SETUP:
		order.append(game.turns.current)
		var actions := game.get_legal_actions(game.turns.current)
		assert_eq(actions[0].type, ArchipelagoGame.BUILD_SETTLEMENT, "primero el poblado")
		assert_eq(game.submit(actions[0]), "")
		actions = game.get_legal_actions(game.turns.current)
		assert_eq(actions[0].type, ArchipelagoGame.BUILD_ROAD, "después el camino")
		assert_eq(game.submit(actions[0]), "")
	assert_eq(order, [0, 1, 2, 2, 1, 0] as Array[int])
	assert_eq(game.phase, ArchipelagoGame.Phase.ROLL)
	assert_eq(game.turns.current, 0, "empieza el primer jugador")
	for p in 3:
		assert_eq(game.victory_points(p), 2)
		assert_eq(game.pieces[p]["settlement"], 3)
		assert_eq(game.pieces[p]["road"], 13)


func test_setup_second_settlement_gives_resources() -> void:
	var game := _new_game(2)
	# Ronda 1: jugadores 0 y 1. No reciben nada.
	for i in 2:
		_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": game.legal_settlement_vertices(game.turns.current)[0]})
		_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": game.legal_road_edges(game.turns.current)[0]})
	assert_eq(game.hand_size(0) + game.hand_size(1), 0)
	# Ronda 2: el jugador 1 coloca su segundo poblado.
	assert_eq(game.turns.current, 1)
	var v := game.legal_settlement_vertices(1)[0]
	var expected := 0
	for t in game.board.grid.vertex_tiles[v]:
		if game.board.tile_resource(t) >= 0:
			expected += 1
	_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": v})
	assert_eq(game.hand_size(1), expected)


func test_setup_rejects_other_actions() -> void:
	var game := _new_game()
	assert_ne(_act(game, ArchipelagoGame.ROLL), "")
	assert_ne(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": 0}), "", "el camino va después del poblado")
	assert_ne(game.submit(GameAction.new(ArchipelagoGame.BUILD_SETTLEMENT, 1, {"vertex": 0})), "", "no es su turno")


func test_distance_rule() -> void:
	var game := _new_game()
	assert_eq(_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": 0}), "")
	assert_eq(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": game.board.grid.vertex_edges[0][0]}), "")
	var neighbor: int = game.board.grid.vertex_neighbors[0][0]
	assert_ne(_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": neighbor}), "")
	assert_ne(_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": 0}), "")


func test_setup_road_must_touch_new_settlement() -> void:
	var game := _new_game()
	_act(game, ArchipelagoGame.BUILD_SETTLEMENT, {"vertex": 0})
	var far := -1
	for e in game.board.grid.edge_count():
		if not 0 in game.board.grid.edge_vertices[e]:
			far = e
			break
	assert_ne(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": far}), "")


func test_roll_and_turn_flow() -> void:
	var game := _new_game()
	_finish_setup(game)
	assert_ne(_act(game, ArchipelagoGame.END_TURN), "", "hay que tirar antes de terminar")
	assert_ne(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": 0}), "", "hay que tirar antes de construir")
	assert_eq(_act(game, ArchipelagoGame.ROLL), "")
	assert_eq(game.last_roll.size(), 2)
	assert_eq(game.history.back().data["dice"], game.last_roll, "la tirada queda en el historial")
	assert_ne(_act(game, ArchipelagoGame.ROLL), "", "solo se tira una vez")
	assert_eq(_act(game, ArchipelagoGame.END_TURN), "")
	assert_eq(game.turns.current, 1)
	assert_eq(game.phase, ArchipelagoGame.Phase.ROLL)


func test_production() -> void:
	var game := _new_game(2, 7)
	_finish_setup(game)
	# Busca una casilla con número de un jugador y fuerza esa producción.
	var hands_before: Array = game.hands.duplicate(true)
	var number := 0
	var expected: Array = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	for v in game.vertex_owner.size():
		if game.vertex_owner[v] != -1 and number == 0:
			for t in game.board.grid.vertex_tiles[v]:
				if game.board.tile_number[t] > 0 and t != game.board.bandit_tile:
					number = game.board.tile_number[t]
					break
	assert_ne(number, 0)
	for t in game.board.tiles_with_number(number):
		if t == game.board.bandit_tile:
			continue
		for v in game.board.grid.tile_vertices[t]:
			if game.vertex_owner[v] != -1:
				expected[game.vertex_owner[v]][game.board.tile_resource(t)] += 1
	game._produce(number)
	for p in 2:
		for r in 5:
			assert_eq(game.hands[p][r], hands_before[p][r] + expected[p][r])


func test_bandit_blocks_production() -> void:
	var game := _new_game(2, 7)
	_finish_setup(game)
	var t := -1
	for v in game.vertex_owner.size():
		if game.vertex_owner[v] != -1:
			for tile in game.board.grid.vertex_tiles[v]:
				if game.board.tile_number[tile] > 0:
					t = tile
	game.board.bandit_tile = t
	var number := game.board.tile_number[t]
	var before := game.hand_size(0) + game.hand_size(1)
	var others := 0
	for tile in game.board.tiles_with_number(number):
		if tile != t:
			for v in game.board.grid.tile_vertices[tile]:
				if game.vertex_owner[v] != -1:
					others += 1
	game._produce(number)
	assert_eq(game.hand_size(0) + game.hand_size(1), before + others)


func test_build_road_costs_and_connectivity() -> void:
	var game := _new_game()
	_finish_setup(game)
	_act(game, ArchipelagoGame.ROLL)
	var pid := game.turns.current
	game.hands[pid] = [0, 0, 0, 0, 0] as Array[int]
	var edges := game.legal_road_edges(pid)
	assert_false(edges.is_empty())
	assert_ne(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": edges[0]}), "", "sin recursos")
	game.hands[pid] = [1, 1, 0, 0, 0] as Array[int]
	game.bank[0] -= 1
	game.bank[1] -= 1
	assert_eq(_act(game, ArchipelagoGame.BUILD_ROAD, {"edge": edges[0]}), "")
	assert_eq(game.hands[pid], [0, 0, 0, 0, 0] as Array[int])
	assert_eq(game.edge_owner[edges[0]], pid)
	for e in game.legal_road_edges(pid):
		assert_eq(game.road_spot_error(pid, e), "")


func test_road_blocked_by_rival_settlement() -> void:
	var game := _new_game(2)
	_finish_setup(game)
	game.phase = ArchipelagoGame.Phase.MAIN
	var grid := game.board.grid
	# Camino del jugador 0 que llega a un vértice libre `v`; un rival ocupa `v`.
	var road := -1
	var v := -1
	for e in grid.edge_count():
		if game.edge_owner[e] == 0:
			for end in grid.edge_vertices[e]:
				if game.vertex_owner[end] == -1:
					road = e
					v = end
	assert_ne(v, -1)
	var beyond := -1
	for e in grid.vertex_edges[v]:
		if e != road and game.edge_owner[e] == -1:
			var other: int = grid.edge_vertices[e][0] if grid.edge_vertices[e][1] == v else grid.edge_vertices[e][1]
			if game.vertex_owner[other] != 0:
				beyond = e
	assert_ne(beyond, -1)
	assert_eq(game.road_spot_error(0, beyond), "", "antes se puede seguir el camino")
	game.vertex_owner[v] = 1
	game.vertex_building[v] = ArchipelagoGame.Building.SETTLEMENT
	assert_ne(game.road_spot_error(0, beyond), "", "el poblado rival corta el camino")


func test_settlement_needs_road() -> void:
	var game := _new_game()
	_finish_setup(game)
	_act(game, ArchipelagoGame.ROLL)
	var pid := game.turns.current
	game.hands[pid] = [5, 5, 5, 5, 5] as Array[int]
	for v in game.vertex_owner.size():
		if game.settlement_spot_error(pid, v) == "":
			var touches := false
			for e in game.board.grid.vertex_edges[v]:
				touches = touches or game.edge_owner[e] == pid
			assert_true(touches)


func test_city_upgrade() -> void:
	var game := _new_game()
	_finish_setup(game)
	_act(game, ArchipelagoGame.ROLL)
	var pid := game.turns.current
	game.hands[pid] = [0, 0, 0, 2, 3] as Array[int]
	var v := game.legal_city_vertices(pid)[0]
	assert_eq(_act(game, ArchipelagoGame.BUILD_CITY, {"vertex": v}), "")
	assert_eq(game.vertex_building[v], ArchipelagoGame.Building.CITY)
	assert_eq(game.victory_points(pid), 3)
	assert_eq(game.pieces[pid]["city"], 3)
	assert_eq(game.pieces[pid]["settlement"], 4, "el poblado vuelve a la reserva")
	assert_ne(_act(game, ArchipelagoGame.BUILD_CITY, {"vertex": v}), "", "ya es ciudad")


func test_bank_trade() -> void:
	var game := _new_game()
	_finish_setup(game)
	_act(game, ArchipelagoGame.ROLL)
	var pid := game.turns.current
	game.hands[pid] = [4, 0, 0, 0, 0] as Array[int]
	var ratio := game.trade_ratio(pid, 0)
	assert_true(ratio in [2, 3, 4])
	assert_ne(_act(game, ArchipelagoGame.TRADE_BANK, {"give": 0, "receive": 0}), "")
	var ore_before: int = game.hands[pid][4]
	assert_eq(_act(game, ArchipelagoGame.TRADE_BANK, {"give": 0, "receive": 4}), "")
	assert_eq(game.hands[pid][0], 4 - ratio)
	assert_eq(game.hands[pid][4], ore_before + 1)


func test_port_ratios() -> void:
	var game := _new_game()
	var port: Dictionary = {}
	for p in game.board.ports:
		if p["type"] != ArchDefs.PORT_GENERIC:
			port = p
			break
	var v: int = game.board.grid.edge_vertices[port["edge"]][0]
	game.vertex_owner[v] = 0
	game.vertex_building[v] = ArchipelagoGame.Building.SETTLEMENT
	assert_eq(game.trade_ratio(0, port["type"]), 2)
	assert_eq(game.trade_ratio(1, port["type"]), 4)


func test_victory() -> void:
	var game := _new_game()
	_finish_setup(game)
	_act(game, ArchipelagoGame.ROLL)
	var pid := game.turns.current
	game.victory_points_target = 3
	game.hands[pid] = [0, 0, 0, 2, 3] as Array[int]
	var winners: Array = []
	game.game_finished.connect(func(ids: Array[int]) -> void: winners.assign(ids))
	_act(game, ArchipelagoGame.BUILD_CITY, {"vertex": game.legal_city_vertices(pid)[0]})
	assert_true(game.finished)
	assert_eq(game.phase, ArchipelagoGame.Phase.FINISHED)
	assert_eq(winners, [pid])
	assert_ne(_act(game, ArchipelagoGame.END_TURN), "", "la partida ha terminado")


## Jugadores aleatorios juegan partidas completas: nunca debe haber errores,
## las cartas se conservan y alguien termina ganando.
func test_random_playouts() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var game := _new_game(4, seed)
		var chooser := BGCRng.new(seed * 31)
		var steps := 0
		var sevens := [0]  # array: las lambdas capturan las variables por valor
		var devs_played := 0
		game.event.connect(func(kind: StringName, _d: Dictionary) -> void:
			if kind == &"seven":
				sevens[0] += 1)
		while not game.finished and steps < 20000:
			var actor: int = game.players_to_act()[0]
			var actions := game.get_legal_actions(actor)
			assert_false(actions.is_empty(), "siempre hay alguna acción legal (fase %d)" % game.phase)
			if actions.is_empty():
				return
			var preferred := actions.filter(func(a: GameAction) -> bool:
				return a.type in [ArchipelagoGame.BUILD_CITY, ArchipelagoGame.BUILD_SETTLEMENT, ArchipelagoGame.BUILD_ROAD, ArchipelagoGame.PLAY_DEV, ArchipelagoGame.BUY_DEV])
			var trades := actions.filter(func(a: GameAction) -> bool: return a.type == ArchipelagoGame.TRADE_BANK)
			var action: GameAction
			if not preferred.is_empty() and game.phase != ArchipelagoGame.Phase.ROLL:
				action = chooser.pick(preferred)
			elif not trades.is_empty() and chooser.randf() < 0.5:
				action = chooser.pick(trades)
			elif game.phase == ArchipelagoGame.Phase.ROLL:
				action = actions[0]
			else:
				action = chooser.pick(actions)
			if action.type == ArchipelagoGame.PLAY_DEV:
				devs_played += 1
			var error := game.submit(action)
			if error != "":
				assert_eq(error, "", "acción legal rechazada: %s" % action)
				return
			steps += 1
			_check_invariants(game)
		assert_true(game.finished, "semilla %d: la partida termina (%d pasos)" % [seed, steps])
		assert_true(game.victory_points(game.winner_ids[0]) >= 10)
		assert_true(sevens[0] > 0, "han salido sietes")
		assert_true(devs_played > 0, "se han jugado cartas de desarrollo")


func _check_invariants(game: ArchipelagoGame) -> void:
	for r in 5:
		var total := _total_cards(game, r)
		if total != ArchipelagoGame.BANK_STOCK:
			assert_eq(total, ArchipelagoGame.BANK_STOCK, "se conservan las cartas de %s" % ArchDefs.RESOURCE_NAMES[r])
	for p in game.players.size():
		for r in 5:
			if game.hands[p][r] < 0:
				assert_true(false, "mano negativa")
	var devs := game.dev_deck.size()
	for p in game.players.size():
		devs += game.dev_hand_size(p) + game.militia_played[p]
	# Las cartas jugadas que no son Milicianos se descartan; nunca hay más
	# cartas de las que tiene el mazo.
	assert_true(devs <= 25)
