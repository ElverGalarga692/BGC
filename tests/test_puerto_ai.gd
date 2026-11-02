extends TestCase

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")
const G := preload("res://games/puerto_franco/logic/puerto_game.gd")
const AILevel := PlayerInfo.AILevel


func _game(levels: Array, seed_value: int = 1) -> PuertoGame:
	var g := PuertoGame.new()
	var ps: Array[PlayerInfo] = []
	for i in levels.size():
		ps.append(PlayerInfo.new(i, "", Color.WHITE, levels[i]))
	g.setup(ps, seed_value)
	return g


## Juega con IAs hasta el final. Devuelve false si una IA propone algo ilegal
## o la partida no termina.
func _play_out(g: PuertoGame, seed_value: int, max_actions: int = 20000) -> bool:
	var ais := []
	for p in g.players:
		ais.append(PuertoAI.new(p.id, p.ai_level, seed_value))
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


func _do(g: PuertoGame, type: StringName, data: Dictionary = {}, pid: int = -1) -> String:
	if pid < 0:
		pid = g.players_to_act()[0]
	return g.submit(GameAction.new(type, pid, data))


func _first_of(wonder: int) -> int:
	for i in D.BUILDINGS.size():
		if D.wonder_of(i) == wonder:
			return i
	return -1


func test_all_levels_finish_games() -> void:
	for n in range(2, 7):
		var levels := []
		for i in n:
			levels.append([AILevel.EASY, AILevel.NORMAL, AILevel.HARD][i % 3])
		var g := _game(levels, 20 + n)
		assert_true(_play_out(g, n), "%d jugadores" % n)


func test_ai_ignores_hidden_information() -> void:
	# Lo que decide la IA no puede depender de las manos de los demás, del
	# orden del mazo ni de lo que han elegido en secreto.
	var g := _game([AILevel.HARD, AILevel.HARD, AILevel.HARD], 4)
	assert_eq(_do(g, G.PICK, {"office": 3, "bid": 2}, 1), "")
	var before := PuertoAI.new(0, AILevel.HARD, 9).choose_action(g)
	# Mismo número de cartas (eso sí es público), pero otras.
	g.hands[1].assign([D.BUILDINGS.size() - 1, D.BUILDINGS.size() - 2, D.BUILDINGS.size() - 3, 4])
	g.hands[2].assign([0, 0, 0, 0])
	g.deck.reverse()
	g.picks[1] = {"office": 0, "bid": 0}
	var after := PuertoAI.new(0, AILevel.HARD, 9).choose_action(g)
	assert_eq(after.to_dict(), before.to_dict())


func test_takes_income_before_building_and_builds() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 3)
	assert_eq(_do(g, G.PICK, {"office": D.Office.BUILDER, "bid": 0}, 0), "")
	assert_eq(_do(g, G.PICK, {"office": D.Office.MAYOR, "bid": 0}, 1), "")
	g.hands[0].assign([1, 1])  # dos Tabernas (2), que hacen grupo con el Puesto
	g.districts[0][1] = 0
	g.coins[0] = 6
	var ai := PuertoAI.new(0, AILevel.NORMAL)
	var first := ai.choose_action(g)
	assert_eq(first.type, G.INCOME)
	assert_eq(g.submit(first), "")
	var built := 0
	while g.turns.current == 0 and g.phase == G.Phase.TURN:
		var a := ai.choose_action(g)
		if a.type == G.BUILD:
			built += 1
		assert_eq(g.submit(a), "")
	assert_eq(built, 2, "con la Maestra de obras construye las dos")


func test_harbor_takes_the_best_dock_card() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 3)
	# Muelle: tres de coste 1 y el Gran Mercado (5, da puntos por Comercio),
	# con un barrio de Comercio.
	var market := -1
	for i in D.BUILDINGS.size():
		if D.wonder_of(i) == D.Wonder.GUILD_HALL and D.BUILDINGS[i]["guild_bonus"] == D.Guild.TRADE:
			market = i
	g.dock.assign([10, 15, market, 5])
	g.districts[0][1] = 0
	g.districts[0][2] = 1
	g.districts[0][3] = 2
	_do(g, G.PICK, {"office": D.Office.HARBOR, "bid": 0}, 0)
	_do(g, G.PICK, {"office": D.Office.MAYOR, "bid": 0}, 1)
	var a := PuertoAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_eq(a.type, G.ABILITY, "usa la Capitana antes de cobrar")
	assert_eq(a.data["index"], 2)


func test_collector_is_used_before_taking_coins() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL], 3)
	g.coins.assign([1, 4, 4])
	_do(g, G.PICK, {"office": D.Office.COLLECTOR, "bid": 0}, 0)
	_do(g, G.PICK, {"office": D.Office.HARBOR, "bid": 0}, 1)
	_do(g, G.PICK, {"office": D.Office.MAYOR, "bid": 0}, 2)
	_do(g, G.INCOME, {"kind": G.Income.COINS})  # Capitana (jugador 1)
	_do(g, G.END_TURN)
	var a := PuertoAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_eq(a.type, G.ABILITY)


func test_planner_moves_to_join_a_group() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL], 3)
	# Dos de Comercio separados: 1 y 4 (lados opuestos de la Lonja).
	g.districts[0][1] = 0
	g.districts[0][4] = 1
	g.hands[0].clear()
	_do(g, G.PICK, {"office": D.Office.PLANNER, "bid": 0}, 0)
	_do(g, G.PICK, {"office": D.Office.MAYOR, "bid": 0}, 1)
	var ai := PuertoAI.new(0, AILevel.NORMAL)
	assert_eq(g.submit(ai.choose_action(g)), "")  # cobra
	var a := ai.choose_action(g)
	assert_eq(a.type, G.ABILITY, "traslada para formar un grupo")
	assert_eq(g.submit(a), "")
	assert_eq(D.group_count(g.districts[0]), 1)


func test_normal_wants_the_office_that_pays_most() -> void:
	var g := _game([AILevel.NORMAL, AILevel.NORMAL, AILevel.NORMAL], 3)
	# Tres grupos en el barrio: el Mecenas da 3 monedas.
	var d: Array = g.districts[0]
	d[1] = 0
	d[7] = 0
	d[3] = 5
	d[11] = 5
	d[5] = 10
	d[15] = 10
	var a := PuertoAI.new(0, AILevel.NORMAL).choose_action(g)
	assert_eq(a.type, G.PICK)
	assert_eq(a.data["office"], D.Office.PATRON)


func test_hard_spends_everything_in_the_final_round() -> void:
	var g := _game([AILevel.HARD, AILevel.HARD], 3)
	g.first_finisher = 1
	var ai := PuertoAI.new(0, AILevel.HARD)
	ai._view = g.view_for(0)
	assert_true(ai.final_round())
	assert_eq(ai.coin_value(), 0.0, "las monedas ya no sirven")
	assert_eq(ai.card_keep_value(0, 1), 0.0, "ni las cartas")
	var normal := PuertoAI.new(0, AILevel.NORMAL)
	normal._view = g.view_for(0)
	assert_true(normal.coin_value() > 0.0, "la normal no lo mira")


func test_hard_avoids_a_contest_it_would_lose() -> void:
	# Los dos tienen un barrio que da 3 monedas con el Mecenas, pero el
	# jugador 1 tiene la vara: la difícil no se pelea por él si lo va a
	# perder.
	var g := _game([AILevel.HARD, AILevel.NORMAL], 3)
	for d in [g.districts[0], g.districts[1]]:
		for pair in [[1, 7, 0], [3, 11, 5], [5, 15, 10]]:
			d[pair[0]] = pair[2]
			d[pair[1]] = pair[2]
	g.vara = 1
	# Sin monedas no puede superar ni una puja de 0 (el empate es del 1).
	g.coins.assign([0, 9])
	var ai := PuertoAI.new(0, AILevel.HARD)
	ai._view = g.view_for(0)
	var guess := ai.predict_pick(1)
	assert_eq(guess["office"], D.Office.PATRON)
	var a := ai.choose_action(g)
	assert_ne(a.data["office"], D.Office.PATRON, "lo perdería: la vara es del 1")


func test_normal_beats_easy() -> void:
	# Torneo pequeño y determinista: la normal en una plaza que va rotando.
	var normal_wins := 0.0
	var games := 18
	for i in games:
		var levels := [AILevel.EASY, AILevel.EASY, AILevel.EASY]
		levels[i % 3] = AILevel.NORMAL
		var g := _game(levels, 200 + i)
		assert_true(_play_out(g, i))
		if i % 3 in g.winner_ids:
			normal_wins += 1.0 / g.winner_ids.size()
	print("    Puerto Franco, IA normal contra 2 fáciles: %.1f de %d victorias" % [normal_wins, games])
	assert_true(normal_wins > games / 3.0 + 2, "gana bastante más que su parte")
