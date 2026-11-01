extends TestCase

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")
const G := preload("res://games/bajamar/logic/bajamar_game.gd")
const AILevel := PlayerInfo.AILevel


func _game(levels: Array, seed_value: int = 1) -> BajamarGame:
	var g := BajamarGame.new()
	var ps: Array[PlayerInfo] = []
	for i in levels.size():
		ps.append(PlayerInfo.new(i, "", Color.WHITE, levels[i]))
	g.setup(ps, seed_value)
	return g


## Juega con IAs hasta el final. Devuelve false si una IA propone algo ilegal
## o la partida no termina.
func _play_out(g: BajamarGame, seed_value: int, max_actions: int = 5000) -> bool:
	var ais := []
	for p in g.players:
		ais.append(BajamarAI.new(p.id, p.ai_level, seed_value))
	var count := 0
	while not g.finished and count < max_actions:
		var pid: int = g.players_to_act()[0]
		var action: GameAction = ais[pid].choose_action(g)
		if action == null:
			assert_true(false, "la IA siempre propone algo")
			return false
		var error := g.submit(action)
		if error != "":
			assert_eq(error, "", "jugada legal de la IA (%s): %s" % [PlayerInfo.AI_LEVEL_NAMES[g.players[pid].ai_level], action])
			return false
		count += 1
	return g.finished


func test_easy_and_normal_finish_games() -> void:
	for n in range(2, 7):
		var levels := []
		for i in n:
			levels.append(AILevel.EASY if i % 2 == 0 else AILevel.NORMAL)
		var g := _game(levels, 10 + n)
		assert_true(_play_out(g, n), "%d jugadores" % n)


func test_hard_finishes_a_game() -> void:
	var g := _game([AILevel.HARD, AILevel.NORMAL, AILevel.EASY], 5)
	assert_true(_play_out(g, 5))


func test_card_counting_matches_deck() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 3)
	# Unas cuantas jugadas para que haya cartas en redes y descartes.
	_play_some(g, 12)
	var ai := BajamarAI.new(g.players_to_act()[0], AILevel.NORMAL, 0)
	ai._count_cards(g)
	var real := {}
	for c in g.deck:
		real[c] = real.get(c, 0) + 1
	assert_eq(ai._pool, real, "lo deducido de la mesa es exactamente el mazo")
	assert_eq(ai._pool_size, g.deck.size())


func test_normal_stops_with_a_big_net() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 2)
	g.nets[0] = _big_net()
	var action := BajamarAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_ne(action.type, G.DRAW_BLIND, "con tanto en la red no arriesga")


func test_normal_draws_with_empty_net() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 2)
	var action := BajamarAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_eq(action.type, G.DRAW_BLIND)


func test_hard_risks_when_stopping_cannot_win() -> void:
	var g := _game([AILevel.HARD, AILevel.HARD], 2)
	g.nets[0] = _big_net()
	var mine: int = g.net_score(0)["total"]
	# J1 ya está en puerto con la partida ganada si J0 se planta.
	g.nets[1] = [D.fish(4, 6)] as Array[int]
	g.status[1] = G.Status.IN_PORT
	# J1 acaba con 145 + 8 = 153; plantándose, J0 empataría a 153 (y en el
	# mercado no hay nada que le ayude).
	g.market.assign([D.SHIELD, D.SHIELD, D.SHIELD])
	g.scores.assign([153 - mine, 145])
	var action := BajamarAI.new(0, AILevel.HARD).choose_action(g)
	assert_eq(action.type, G.DRAW_BLIND, "plantarse no gana: tiene que arriesgar")
	var normal := BajamarAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_ne(normal.type, G.DRAW_BLIND, "la normal no mira el marcador y se planta")


func test_hard_secures_the_win() -> void:
	var g := _game([AILevel.HARD, AILevel.HARD], 2)
	g.nets[0] = _big_net()
	var mine: int = g.net_score(0)["total"]
	g.nets[1] = [D.fish(4, 6)] as Array[int]
	g.status[1] = G.Status.IN_PORT
	g.scores.assign([155 - mine, 145])
	var action := BajamarAI.new(0, AILevel.HARD).choose_action(g)
	assert_ne(action.type, G.DRAW_BLIND, "plantándose ya gana")


func test_gull_picks_the_most_valuable_fish() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL], 2)
	g.nets[0] = [D.fish(0, 3), D.fish(0, 4)] as Array[int]
	g.nets[1] = [D.fish(1, 1)] as Array[int]
	g.nets[2] = [D.fish(0, 5)] as Array[int]  # sardina 5: suma y alarga la escalera
	g.pending_gulls.assign([0])
	var action := BajamarAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_eq(action.type, G.CHOOSE_TARGET)
	assert_eq(action.data["target"], 2)


func test_normal_beats_easy() -> void:
	# Torneo pequeño y determinista: la normal en una plaza que va rotando.
	var normal_wins := 0.0
	var games := 24
	for i in games:
		var levels := [AILevel.EASY, AILevel.EASY, AILevel.EASY]
		levels[i % 3] = AILevel.NORMAL
		var g := _game(levels, 100 + i)
		assert_true(_play_out(g, i))
		if i % 3 in g.winner_ids:
			normal_wins += 1.0 / g.winner_ids.size()
	print("    IA normal contra 2 fáciles: %.1f de %d victorias" % [normal_wins, games])
	assert_true(normal_wins > games / 3.0 + 2, "gana bastante más que su parte")


func _play_some(g: BajamarGame, actions: int) -> void:
	var ais := [BajamarAI.new(0, AILevel.NORMAL, 1), BajamarAI.new(1, AILevel.NORMAL, 1)]
	for i in actions:
		if g.finished:
			return
		g.submit(ais[g.players_to_act()[0]].choose_action(g))


## Red de unos 74 puntos: las seis sardinas y las seis caballas.
func _big_net() -> Array[int]:
	var net: Array[int] = []
	for s in 2:
		for v in range(1, 7):
			net.append(D.fish(s, v))
	return net


func test_registered_in_menu() -> void:
	var entry := GameRegistry.find("bajamar")
	assert_false(entry.is_empty(), "Bajamar está en el registro")
	assert_true(ResourceLoader.exists(entry["scene"]), "existe la escena")
	assert_true(FileAccess.file_exists(entry["rules"]), "existe el reglamento")
	assert_eq(entry["min_players"], 2)
	assert_eq(entry["max_players"], 6)
