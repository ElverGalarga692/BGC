extends TestCase
## Fase 3: el 7 y el bandido, cartas de desarrollo, premios y comercio
## entre jugadores.

const DevCard := ArchDefs.DevCard


func _game(player_count: int = 3, seed: int = 42) -> ArchipelagoGame:
	var game := ArchipelagoGame.new()
	var players: Array[PlayerInfo] = []
	for i in player_count:
		players.append(PlayerInfo.new(i))
	game.setup(players, seed)
	while game.phase == ArchipelagoGame.Phase.SETUP:
		game.submit(game.get_legal_actions(game.turns.current)[0])
	return game


## Deja la partida en la fase MAIN del jugador actual sin tirar dados.
func _to_main(game: ArchipelagoGame) -> int:
	game.phase = ArchipelagoGame.Phase.MAIN
	return game.turns.current


func _act(game: ArchipelagoGame, pid: int, type: StringName, data: Dictionary = {}) -> String:
	return game.submit(GameAction.new(type, pid, data))


func _set_hand(game: ArchipelagoGame, pid: int, hand: Array) -> void:
	# Mueve cartas entre la banca y la mano para conservar el total.
	for r in 5:
		game.bank[r] += game.hands[pid][r] - hand[r]
		game.hands[pid][r] = hand[r]


func _give_dev(game: ArchipelagoGame, pid: int, card: int) -> void:
	game.dev_hands[pid][card] += 1


# --- El 7 ------------------------------------------------------------------------

func test_seven_discards_then_robber() -> void:
	var game := _game()
	_set_hand(game, 0, [3, 3, 2, 1, 0])  # 9 cartas -> descarta 4
	_set_hand(game, 1, [2, 2, 2, 1, 0])  # 7 cartas -> no descarta
	_set_hand(game, 2, [4, 4, 0, 0, 0])  # 8 cartas -> descarta 4
	game._start_seven()
	assert_eq(game.phase, ArchipelagoGame.Phase.DISCARD)
	assert_eq(game.players_to_act(), [0, 2] as Array[int])
	assert_eq(game.pending_discards, {0: 4, 2: 4})
	assert_ne(_act(game, 1, ArchipelagoGame.DISCARD, {"cards": [1, 0, 0, 0, 0]}), "", "el 1 no tiene que descartar")
	assert_ne(_act(game, 0, ArchipelagoGame.DISCARD, {"cards": [1, 0, 0, 0, 0]}), "", "número incorrecto")
	assert_ne(_act(game, 0, ArchipelagoGame.DISCARD, {"cards": [0, 0, 0, 0, 4]}), "", "no tiene mineral")
	assert_eq(_act(game, 2, ArchipelagoGame.DISCARD, {"cards": [2, 2, 0, 0, 0]}), "", "se descarta en cualquier orden")
	assert_eq(game.phase, ArchipelagoGame.Phase.DISCARD)
	assert_eq(_act(game, 0, ArchipelagoGame.DISCARD, {"cards": [2, 1, 1, 0, 0]}), "")
	assert_eq(game.hand_size(0), 5)
	assert_eq(game.phase, ArchipelagoGame.Phase.ROBBER)
	assert_eq(game.players_to_act(), [game.turns.current] as Array[int])


func test_seven_without_discards_goes_to_robber() -> void:
	var game := _game()
	game._start_seven()
	assert_eq(game.phase, ArchipelagoGame.Phase.ROBBER)


func test_move_bandit_and_steal() -> void:
	var game := _game()
	var pid := game.turns.current
	game.phase = ArchipelagoGame.Phase.ROBBER
	game._after_robber = ArchipelagoGame.Phase.MAIN
	# Casilla con un edificio rival.
	var tile := -1
	var victim := -1
	for t in game.bandit_tiles():
		var victims := game.bandit_victims(pid, t)
		if not victims.is_empty():
			tile = t
			victim = victims[0]
			break
	assert_ne(tile, -1)
	_set_hand(game, victim, [0, 0, 0, 0, 1])
	var before := game.hand_size(pid)
	assert_ne(_act(game, pid, ArchipelagoGame.MOVE_BANDIT, {"tile": game.board.bandit_tile, "victim": -1}), "", "hay que moverlo")
	assert_ne(_act(game, pid, ArchipelagoGame.MOVE_BANDIT, {"tile": tile, "victim": -1}), "", "hay que elegir víctima")
	assert_ne(_act(game, pid, ArchipelagoGame.MOVE_BANDIT, {"tile": tile, "victim": pid}), "")
	assert_eq(_act(game, pid, ArchipelagoGame.MOVE_BANDIT, {"tile": tile, "victim": victim}), "")
	assert_eq(game.board.bandit_tile, tile)
	assert_eq(game.hand_size(pid), before + 1)
	assert_eq(game.hands[pid][4] >= 1, true)
	assert_eq(game.hand_size(victim), 0)
	assert_eq(game.history.back().data["stolen"], 4)
	assert_eq(game.phase, ArchipelagoGame.Phase.MAIN)


func test_bandit_victims_need_cards() -> void:
	var game := _game()
	for p in 3:
		_set_hand(game, p, [0, 0, 0, 0, 0])
	for t in game.bandit_tiles():
		assert_true(game.bandit_victims(0, t).is_empty())


# --- Cartas de desarrollo -----------------------------------------------------------

func test_buy_dev_card() -> void:
	var game := _game()
	var pid := _to_main(game)
	_set_hand(game, pid, [0, 0, 1, 1, 1])
	var deck_size := game.dev_deck.size()
	assert_eq(deck_size, 25)
	assert_eq(_act(game, pid, ArchipelagoGame.BUY_DEV), "")
	assert_eq(game.dev_deck.size(), 24)
	assert_eq(game.hand_size(pid), 0)
	assert_eq(game.dev_hand_size(pid), 1)
	var card: int = game.history.back().data["card"]
	assert_eq(game.playable_dev(pid, card), 0, "no se puede jugar el turno en que se compra")
	if card != DevCard.MONUMENT:
		assert_ne(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": card, "resource": 0, "resources": [0, 0]}), "")
	assert_ne(_act(game, pid, ArchipelagoGame.BUY_DEV), "", "sin recursos")
	_act(game, pid, ArchipelagoGame.END_TURN)
	assert_eq(game.playable_dev(pid, card), 1, "el turno siguiente ya se puede jugar")


func test_monument_counts_hidden() -> void:
	var game := _game()
	_give_dev(game, 0, DevCard.MONUMENT)
	assert_eq(game.victory_points(0), 3)
	assert_eq(game.public_victory_points(0), 2)
	_to_main(game)
	assert_ne(_act(game, game.turns.current, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MONUMENT}), "")


func test_one_dev_card_per_turn() -> void:
	var game := _game()
	var pid := _to_main(game)
	_give_dev(game, pid, DevCard.MONOPOLY)
	_give_dev(game, pid, DevCard.MONOPOLY)
	assert_eq(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MONOPOLY, "resource": 0}), "")
	assert_ne(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MONOPOLY, "resource": 1}), "")


func test_militia_before_roll() -> void:
	var game := _game()
	var pid := game.turns.current
	assert_eq(game.phase, ArchipelagoGame.Phase.ROLL)
	_give_dev(game, pid, DevCard.MILITIA)
	_give_dev(game, pid, DevCard.MONOPOLY)
	assert_ne(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MONOPOLY, "resource": 0}), "", "antes de tirar solo Miliciano")
	assert_eq(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MILITIA}), "")
	assert_eq(game.phase, ArchipelagoGame.Phase.ROBBER)
	var move: GameAction = game.get_legal_actions(pid)[0]
	assert_eq(game.submit(move), "")
	assert_eq(game.phase, ArchipelagoGame.Phase.ROLL, "tras el bandido aún hay que tirar")
	assert_eq(game.militia_played[pid], 1)


func test_road_building() -> void:
	var game := _game()
	var pid := _to_main(game)
	_set_hand(game, pid, [0, 0, 0, 0, 0])
	_give_dev(game, pid, DevCard.ROAD_BUILDING)
	assert_eq(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.ROAD_BUILDING}), "")
	assert_eq(game.phase, ArchipelagoGame.Phase.ROAD_BUILDING)
	assert_ne(_act(game, pid, ArchipelagoGame.END_TURN), "", "primero los caminos")
	for i in 2:
		assert_eq(_act(game, pid, ArchipelagoGame.BUILD_ROAD, {"edge": game.legal_road_edges(pid)[0]}), "")
	assert_eq(game.phase, ArchipelagoGame.Phase.MAIN)
	assert_eq(game.pieces[pid]["road"], 11)
	assert_eq(game.hand_size(pid), 0, "gratis")


func test_harvest() -> void:
	var game := _game()
	var pid := _to_main(game)
	_set_hand(game, pid, [0, 0, 0, 0, 0])
	_give_dev(game, pid, DevCard.HARVEST)
	assert_ne(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.HARVEST, "resources": [0]}), "")
	assert_eq(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.HARVEST, "resources": [4, 4]}), "")
	assert_eq(game.hands[pid], [0, 0, 0, 0, 2] as Array[int])


func test_monopoly() -> void:
	var game := _game()
	var pid := _to_main(game)
	for p in 3:
		_set_hand(game, p, [0, 0, 3, 0, 0] if p != pid else [0, 0, 1, 0, 0])
	_give_dev(game, pid, DevCard.MONOPOLY)
	assert_eq(_act(game, pid, ArchipelagoGame.PLAY_DEV, {"card": DevCard.MONOPOLY, "resource": ArchDefs.ResourceType.WOOL}), "")
	assert_eq(game.hands[pid][2], 7)
	assert_eq(game.history.back().data["taken"], 6)
	for p in 3:
		if p != pid:
			assert_eq(game.hand_size(p), 0)


# --- Premios -------------------------------------------------------------------

func test_largest_army() -> void:
	var game := _game()
	game.militia_played.assign([2, 0, 0])
	game._update_largest_army()
	assert_eq(game.largest_army_owner, -1, "hacen falta 3")
	game.militia_played.assign([3, 0, 0])
	game._update_largest_army()
	assert_eq(game.largest_army_owner, 0)
	assert_eq(game.public_victory_points(0), 4)
	game.militia_played.assign([3, 3, 0])
	game._update_largest_army()
	assert_eq(game.largest_army_owner, 0, "el empate no la quita")
	game.militia_played.assign([3, 4, 0])
	game._update_largest_army()
	assert_eq(game.largest_army_owner, 1)


## Tablero vacío con una línea de caminos del jugador 0 a lo largo de la costa.
func _road_game() -> Array:
	var game := ArchipelagoGame.new()
	var players: Array[PlayerInfo] = [PlayerInfo.new(0), PlayerInfo.new(1)]
	game.setup(players, 1)
	game.phase = ArchipelagoGame.Phase.MAIN
	var coast := game.board.grid.coastal_edges()
	return [game, coast]


func _own(game: ArchipelagoGame, edges: Array, pid: int) -> void:
	for e in edges:
		game.edge_owner[e] = pid


func test_longest_road_length() -> void:
	var r := _road_game()
	var game: ArchipelagoGame = r[0]
	var coast: Array = r[1]
	_own(game, coast.slice(0, 6), 0)
	assert_eq(game.longest_road_length(0), 6)
	# Una rama no suma a la longitud del camino continuo.
	var grid := game.board.grid
	var shared: int = grid.edge_vertices[coast[2]][0] if grid.edge_vertices[coast[2]][0] in grid.edge_vertices[coast[3]] else grid.edge_vertices[coast[2]][1]
	for e in grid.vertex_edges[shared]:
		if game.edge_owner[e] == -1:
			game.edge_owner[e] = 0
	assert_eq(game.longest_road_length(0), 6)
	# Toda la costa es un ciclo de 30.
	_own(game, coast, 0)
	assert_eq(game.longest_road_length(0), 31, "ciclo de 30 más la rama")


func test_longest_road_award_and_break() -> void:
	var r := _road_game()
	var game: ArchipelagoGame = r[0]
	var coast: Array = r[1]
	var grid := game.board.grid
	_own(game, coast.slice(0, 4), 0)
	game._update_longest_road()
	assert_eq(game.longest_road_owner, -1, "hacen falta 5")
	_own(game, coast.slice(0, 7), 0)
	game._update_longest_road()
	assert_eq(game.longest_road_owner, 0)
	assert_eq(game.public_victory_points(0), 2)
	_own(game, coast.slice(10, 17), 1)
	game._update_longest_road()
	assert_eq(game.longest_road_owner, 0, "el empate no lo quita")
	# Un poblado del jugador 1 en mitad del camino del 0 lo corta (3 + 3).
	var a: Array = grid.edge_vertices[coast[2]]
	var b: Array = grid.edge_vertices[coast[3]]
	var middle: int = a[0] if a[0] in b else a[1]
	game.vertex_owner[middle] = 1
	game.vertex_building[middle] = ArchipelagoGame.Building.SETTLEMENT
	game._update_longest_road()
	assert_eq(game.road_lengths[0], 4)
	assert_eq(game.longest_road_owner, 1, "pasa al único con el camino más largo")


func test_longest_road_tie_after_break_goes_to_nobody() -> void:
	var r := _road_game()
	var game: ArchipelagoGame = r[0]
	var coast: Array = r[1]
	game.longest_road_owner = 0
	_own(game, coast.slice(10, 15), 1)  # 5
	_own(game, coast.slice(20, 24), 0)  # 4
	game._update_longest_road()
	assert_eq(game.longest_road_owner, 1)
	game.longest_road_owner = 0
	_own(game, coast.slice(20, 25), 0)  # 5 y 5, pero el 0 lo tenía
	game._update_longest_road()
	assert_eq(game.longest_road_owner, 0)


# --- Comercio entre jugadores ---------------------------------------------------

func test_player_trade_accept() -> void:
	var game := _game()
	var pid := _to_main(game)
	var other := (pid + 1) % 3
	_set_hand(game, pid, [2, 0, 0, 0, 0])
	_set_hand(game, other, [0, 0, 0, 0, 1])
	var offer := {"to": other, "give": [2, 0, 0, 0, 0], "receive": [0, 0, 0, 0, 1]}
	assert_eq(_act(game, pid, ArchipelagoGame.OFFER_TRADE, offer), "")
	assert_eq(game.players_to_act(), [other] as Array[int])
	assert_ne(_act(game, pid, ArchipelagoGame.END_TURN), "", "hay una oferta pendiente")
	assert_eq(_act(game, other, ArchipelagoGame.ACCEPT_TRADE), "")
	assert_eq(game.hands[pid], [0, 0, 0, 0, 1] as Array[int])
	assert_eq(game.hands[other], [2, 0, 0, 0, 0] as Array[int])
	assert_true(game.trade_offer.is_empty())
	assert_eq(game.players_to_act(), [pid] as Array[int])


func test_player_trade_reject_and_validation() -> void:
	var game := _game()
	var pid := _to_main(game)
	var other := (pid + 1) % 3
	_set_hand(game, pid, [1, 0, 0, 0, 0])
	_set_hand(game, other, [0, 0, 0, 0, 0])
	assert_ne(_act(game, pid, ArchipelagoGame.OFFER_TRADE, {"to": pid, "give": [1, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0]}), "")
	assert_ne(_act(game, pid, ArchipelagoGame.OFFER_TRADE, {"to": other, "give": [2, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0]}), "", "no tiene 2")
	assert_ne(_act(game, pid, ArchipelagoGame.OFFER_TRADE, {"to": other, "give": [1, 0, 0, 0, 0], "receive": [0, 0, 0, 0, 0]}), "", "regalo")
	assert_eq(_act(game, pid, ArchipelagoGame.OFFER_TRADE, {"to": other, "give": [1, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0]}), "")
	assert_ne(_act(game, other, ArchipelagoGame.ACCEPT_TRADE), "", "no tiene ladrillo")
	assert_eq(_act(game, other, ArchipelagoGame.REJECT_TRADE), "")
	assert_eq(game.hands[pid], [1, 0, 0, 0, 0] as Array[int])
	# Quien ofrece también puede cancelar.
	_act(game, pid, ArchipelagoGame.OFFER_TRADE, {"to": other, "give": [1, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0]})
	assert_eq(_act(game, pid, ArchipelagoGame.REJECT_TRADE), "")
	assert_true(game.trade_offer.is_empty())


func test_victory_by_monument_on_own_turn() -> void:
	var game := _game()
	var pid := _to_main(game)
	game.victory_points_target = 3
	_set_hand(game, pid, [0, 0, 1, 1, 1])
	# Fuerza que la próxima carta sea un Monumento.
	game.dev_deck.append(DevCard.MONUMENT)
	assert_eq(_act(game, pid, ArchipelagoGame.BUY_DEV), "")
	assert_true(game.finished)
	assert_eq(game.winner_ids, [pid] as Array[int])
