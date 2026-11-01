extends TestCase

const AILevel := PlayerInfo.AILevel


func _game(levels: Array, seed: int) -> ArchipelagoGame:
	var players: Array[PlayerInfo] = []
	for i in levels.size():
		players.append(PlayerInfo.new(i, "", PlayerInfo.default_color(i), levels[i]))
	var game := ArchipelagoGame.new()
	game.setup(players, seed)
	return game


func _ais(game: ArchipelagoGame, seed: int) -> Array[ArchAI]:
	var ais: Array[ArchAI] = []
	for p in game.players:
		ais.append(ArchAI.new(p.id, p.ai_level, seed))
	return ais


## Juega una partida entre IAs. Devuelve el número de acciones, o -1 si
## alguna IA propuso una acción ilegal.
func _play(game: ArchipelagoGame, ais: Array[ArchAI], max_steps: int = 5000) -> int:
	var steps := 0
	while not game.finished and steps < max_steps:
		var actor: int = game.players_to_act()[0]
		var action := ais[actor].choose_action(game)
		if action == null:
			assert_true(false, "la IA no devolvió acción (fase %d)" % game.phase)
			return -1
		var error := game.submit(action)
		if error != "":
			assert_eq(error, "", "acción ilegal de la IA: %s" % action)
			return -1
		steps += 1
	return steps


func test_normal_ai_games_finish() -> void:
	for seed in [11, 12, 13, 14]:
		var game := _game([AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL], seed)
		var steps := _play(game, _ais(game, seed))
		assert_true(game.finished, "semilla %d: termina (%d acciones, ronda %d)" % [seed, steps, game.turns.round_number])
		assert_true(game.turns.round_number < 120, "semilla %d: no se eterniza (ronda %d)" % [seed, game.turns.round_number])


func test_easy_ai_games_finish() -> void:
	for seed in [21, 22]:
		var game := _game([AILevel.EASY, AILevel.EASY, AILevel.EASY], seed)
		_play(game, _ais(game, seed), 20000)
		assert_true(game.finished, "semilla %d" % seed)


## La IA normal debe ganar con claridad a tres IAs fáciles (al azar ganaría
## una de cada cuatro).
func test_normal_beats_easy() -> void:
	var wins := 0
	var games := 12
	for seed in games:
		var levels := [AILevel.EASY, AILevel.EASY, AILevel.EASY, AILevel.EASY]
		var normal_seat := seed % 4
		levels[normal_seat] = AILevel.NORMAL
		var game := _game(levels, 100 + seed)
		_play(game, _ais(game, seed), 20000)
		if game.finished and game.winner_ids[0] == normal_seat:
			wins += 1
	print("    IA normal contra 3 fáciles: %d de %d victorias" % [wins, games])
	assert_true(wins >= games * 0.6, "la IA normal gana %d de %d" % [wins, games])


func test_setup_picks_best_spot() -> void:
	var game := _game([AILevel.NORMAL, AILevel.HUMAN], 5)
	var ai := ArchAI.new(0, AILevel.NORMAL, 5)
	var action := ai.choose_action(game)
	assert_eq(action.type, ArchipelagoGame.BUILD_SETTLEMENT)
	var weights := ai._weights(game)
	var chosen := ai.vertex_score(game, action.data["vertex"], weights)
	for v in game.legal_settlement_vertices(0):
		assert_true(ai.vertex_score(game, v, weights) <= chosen + 0.02)


func test_ai_not_its_turn() -> void:
	var game := _game([AILevel.NORMAL, AILevel.NORMAL], 5)
	assert_eq(ArchAI.new(1, AILevel.NORMAL).choose_action(game), null)


func _main_game() -> ArchipelagoGame:
	var game := _game([AILevel.HUMAN, AILevel.NORMAL, AILevel.HUMAN], 9)
	while game.phase == ArchipelagoGame.Phase.SETUP:
		game.submit(game.get_legal_actions(game.turns.current)[0])
	game.phase = ArchipelagoGame.Phase.MAIN
	return game


func _set_hand(game: ArchipelagoGame, p: int, hand: Array) -> void:
	for r in 5:
		game.bank[r] += game.hands[p][r] - hand[r]
		game.hands[p][r] = hand[r]


func test_ai_accepts_good_offer_and_rejects_bad() -> void:
	var game := _main_game()
	var ai := ArchAI.new(1, AILevel.NORMAL)
	_set_hand(game, 0, [3, 3, 0, 0, 0])
	_set_hand(game, 1, [0, 0, 4, 0, 0])
	# 2 cartas por 1 lana que le sobra: acepta.
	game.submit(GameAction.new(ArchipelagoGame.OFFER_TRADE, 0, {"to": 1, "give": [1, 1, 0, 0, 0], "receive": [0, 0, 1, 0, 0]}))
	assert_eq(ai.choose_action(game).type, ArchipelagoGame.ACCEPT_TRADE)
	game.submit(GameAction.new(ArchipelagoGame.REJECT_TRADE, 0))
	# Pedirle 3 lanas por 1 madera: rechaza.
	game.submit(GameAction.new(ArchipelagoGame.OFFER_TRADE, 0, {"to": 1, "give": [1, 0, 0, 0, 0], "receive": [0, 0, 3, 0, 0]}))
	assert_eq(ai.choose_action(game).type, ArchipelagoGame.REJECT_TRADE)


func test_ai_rejects_offers_from_leader() -> void:
	var game := _main_game()
	var ai := ArchAI.new(1, AILevel.NORMAL)
	game.victory_points_target = 4
	_set_hand(game, 0, [3, 3, 0, 0, 0])
	_set_hand(game, 1, [0, 0, 4, 0, 0])
	game.submit(GameAction.new(ArchipelagoGame.OFFER_TRADE, 0, {"to": 1, "give": [2, 2, 0, 0, 0], "receive": [0, 0, 1, 0, 0]}))
	assert_eq(ai.choose_action(game).type, ArchipelagoGame.REJECT_TRADE)


func test_ai_builds_city_when_it_can() -> void:
	var game := _main_game()
	game.turns.current = 1
	_set_hand(game, 1, [0, 0, 0, 2, 3])
	var action := ArchAI.new(1, AILevel.NORMAL).choose_action(game)
	assert_eq(action.type, ArchipelagoGame.BUILD_CITY)


func test_ai_discard_keeps_goal_cards() -> void:
	var game := _main_game()
	_set_hand(game, 1, [0, 0, 6, 1, 2])  # 9 cartas, objetivo: ciudad
	game._start_seven()
	var action := ArchAI.new(1, AILevel.NORMAL).choose_action(game)
	assert_eq(action.type, ArchipelagoGame.DISCARD)
	assert_eq(action.data["cards"], [0, 0, 4, 0, 0] as Array[int], "descarta la lana que sobra")


func _ais_observing(game: ArchipelagoGame, seed: int) -> Array[ArchAI]:
	var ais := _ais(game, seed)
	for ai in ais:
		ai.observe(game)
	return ais


func test_hard_ai_games_finish() -> void:
	for seed in [31, 32]:
		var game := _game([AILevel.HARD, AILevel.HARD, AILevel.HARD, AILevel.HARD], seed)
		_play(game, _ais_observing(game, seed))
		assert_true(game.finished, "semilla %d" % seed)


## La IA difícil debe ganar a tres IAs normales bastante más de una de cada
## cuatro partidas (lo esperado si fueran iguales).
func test_hard_beats_normal() -> void:
	var wins := 0
	var games := 48
	for seed in games:
		var levels := [AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL]
		var hard_seat := seed % 4
		levels[hard_seat] = AILevel.HARD
		var game := _game(levels, 300 + seed)
		_play(game, _ais_observing(game, seed), 20000)
		if game.finished and game.winner_ids[0] == hard_seat:
			wins += 1
	print("    IA difícil contra 3 normales: %d de %d victorias" % [wins, games])
	assert_true(wins >= games * 0.33, "la IA difícil gana %d de %d" % [wins, games])


## Sin sietes, el contador de cartas acierta exactamente las manos rivales.
func test_card_tracker_exact_without_steals() -> void:
	var game := _game([AILevel.HARD, AILevel.NORMAL, AILevel.NORMAL], 77)
	var tracker := ArchCardTracker.new()
	tracker.observe(game, 0)
	var ais := _ais(game, 77)
	var steps := 0
	while not game.finished and steps < 400:
		var actor: int = game.players_to_act()[0]
		var action := ais[actor].choose_action(game)
		game.submit(action)
		steps += 1
		if game.history.filter(func(a: GameAction) -> bool: return a.type == ArchipelagoGame.MOVE_BANDIT and a.data.get("victim", -1) >= 0 and a.player_id != 0 and a.data["victim"] != 0).size() > 0:
			break
		for p in [1, 2]:
			var est := tracker.estimate(p)
			for r in 5:
				if absf(est[r] - game.hands[p][r]) > 0.001:
					assert_eq(est[r], float(game.hands[p][r]), "jugador %d, recurso %d, paso %d (%s)" % [p, r, steps, action])
					return
