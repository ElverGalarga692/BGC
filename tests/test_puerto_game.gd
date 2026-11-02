extends TestCase

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")
const G := preload("res://games/puerto_franco/logic/puerto_game.gd")


func _game(n: int = 3, seed_value: int = 1) -> PuertoGame:
	var g := PuertoGame.new()
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i))
	g.setup(ps, seed_value)
	return g


func _do(g: PuertoGame, type: StringName, data: Dictionary = {}, pid: int = -1) -> String:
	if pid < 0:
		pid = g.players_to_act()[0]
	return g.submit(GameAction.new(type, pid, data))


## Todos eligen cargo: picks[pid] = [cargo, puja].
func _pick_all(g: PuertoGame, picks: Dictionary) -> void:
	for pid in picks:
		assert_eq(_do(g, G.PICK, {"office": picks[pid][0], "bid": picks[pid][1]}, pid), "", "pick %d" % pid)


## Elige una acción "razonable": construye lo más caro que pueda; si no,
## cobra o termina. Para partidas automáticas en los tests.
func _simple_action(g: PuertoGame, pid: int) -> GameAction:
	var actions := g.get_legal_actions(pid)
	match g.phase:
		G.Phase.PICK:
			var office := (pid * 3 + g.round_number) % D.OFFICE_COUNT
			return GameAction.new(G.PICK, pid, {"office": office, "bid": mini(1, g.coins[pid])})
		G.Phase.REASSIGN:
			return actions[0]
	var best: GameAction = null
	for a in actions:
		if a.type == G.BUILD:
			var card: int = g.hands[pid][a.data["card"]]
			if best == null or D.cost_of(card) > D.cost_of(g.hands[pid][best.data["card"]]):
				best = a
	if best != null:
		return best
	if not g.income_taken:
		var kind := G.Income.COINS if g.hands[pid].size() >= 2 else G.Income.DOCK
		return GameAction.new(G.INCOME, pid, {"kind": kind, "index": 0})
	if not g.ability_used:
		for a in actions:
			if a.type == G.ABILITY and g.turn_office != D.Office.PLANNER:
				return a
	return GameAction.new(G.END_TURN, pid, {})


func _autoplay(g: PuertoGame, max_actions: int = 20000) -> int:
	var count := 0
	while not g.finished and count < max_actions:
		var pid: int = g.players_to_act()[0]
		var action := _simple_action(g, pid)
		var error := g.submit(action)
		assert_eq(error, "", "acción %d %s" % [count, action])
		if error != "":
			return count
		count += 1
	return count


# --- Definiciones -----------------------------------------------------------------

func test_deck_and_cells() -> void:
	assert_eq(D.deck().size(), 65)
	assert_eq(D.deck(5).size(), 77, "con 5 o más, una copia más de los de coste 1 a 3")
	assert_eq(D.CELLS.size(), 19)
	for i in D.CELLS.size():
		assert_eq(HexCoords.distance(D.CELLS[i], Vector2i.ZERO) <= D.DISTRICT_RADIUS, true)
		assert_eq(D.CELLS.find(D.CELLS[i]), i, "casillas repetidas")
	assert_eq(D.cell_neighbors(D.LONJA_CELL).size(), 6)
	assert_eq(D.cell_neighbors(9).size(), 3, "esquina del anillo 2")


func _empty_district() -> Array[int]:
	var d: Array[int] = []
	d.resize(D.CELLS.size())
	d.fill(D.EMPTY)
	d[D.LONJA_CELL] = D.LONJA
	return d


func test_groups_and_score() -> void:
	var d := _empty_district()
	# Tres de Comercio en línea (1, 7 son vecinos; 2 vecino de 1) y una de Mar.
	d[1] = 0   # Puesto de fruta (1)
	d[7] = 1   # Taberna (2)
	d[2] = 2   # Tienda de especias (3)
	d[4] = 5   # Embarcadero (1)
	var groups := D.groups(d)
	assert_eq(groups.size(), 1)
	assert_eq(groups[0]["guild"], D.Guild.TRADE)
	assert_eq(groups[0]["cells"].size(), 3)
	var s := D.score_district(d, 0)
	assert_eq(s["buildings"], 7)
	assert_eq(s["groups"], 3)
	assert_eq(s["total"], 10)


func test_gardens_join_groups_of_any_guild() -> void:
	var d := _empty_district()
	var gardens := -1
	for i in D.BUILDINGS.size():
		if D.wonder_of(i) == D.Wonder.GARDENS:
			gardens = i
	d[1] = gardens
	d[7] = 0   # Comercio, vecino de 1
	d[6] = 5   # Mar, vecino de 1
	var groups := D.groups(d)
	assert_eq(groups.size(), 2, "un grupo de Comercio y otro de Mar")
	assert_eq(D.group_count(d), 2)


func test_wonder_scoring() -> void:
	var d := _empty_district()
	var plaza := -1
	var hall := -1
	var lighthouse := -1
	for i in D.BUILDINGS.size():
		match D.wonder_of(i):
			D.Wonder.PLAZA:
				plaza = i
			D.Wonder.GUILD_HALL:
				if D.BUILDINGS[i]["guild_bonus"] == D.Guild.SEA:
					hall = i
			D.Wonder.LIGHTHOUSE:
				lighthouse = i
	d[1] = plaza
	d[2] = 5      # Mar, vecino de la Plaza
	d[7] = 6      # Mar, vecino de la Plaza (y del 2? no: 7 y 2 no son vecinos)
	d[3] = hall
	d[4] = lighthouse
	var s := D.score_district(d, 7)
	# Plaza: 2 vecinos edificados (2 y 7; la Lonja no cuenta) = 4.
	# Arsenal: 2 de Mar = 2. Faro: 7 monedas = 3.
	assert_eq(s["wonders"], 9)


func test_connectivity() -> void:
	var d := _empty_district()
	d[1] = 0
	d[7] = 0
	assert_true(D.all_linked(d))
	d[1] = D.EMPTY
	assert_false(D.all_linked(d), "la 7 queda suelta")


# --- Preparación ------------------------------------------------------------------

func test_setup() -> void:
	var g := _game(4)
	assert_eq(g.phase, G.Phase.PICK)
	assert_eq(g.dock.size(), D.DOCK_SIZE)
	assert_eq(g.objectives.size(), D.OBJECTIVES_PER_GAME)
	var total := g.deck.size() + g.dock.size()
	for pid in 4:
		assert_eq(g.coins[pid], D.START_COINS)
		assert_eq(g.hands[pid].size(), D.START_HAND)
		assert_eq(g.building_count(pid), 0)
		total += g.hands[pid].size()
	assert_eq(total, D.deck(4).size())
	assert_eq(g.players_to_act().size(), 4, "todos eligen a la vez")


# --- Elección de cargos -----------------------------------------------------------

func test_picks_are_secret_until_everyone_chose() -> void:
	var g := _game(3)
	assert_eq(_do(g, G.PICK, {"office": 2, "bid": 1}, 0), "")
	assert_eq(g.view_for(1)["my_pick"], null)
	assert_eq(g.view_for(0)["my_pick"], {"office": 2, "bid": 1})
	assert_true(g.view_for(1)["picked"].has(0), "se ve que ya ha elegido")
	assert_ne(_do(g, G.PICK, {"office": 3, "bid": 0}, 0), "", "no se elige dos veces")
	assert_eq(g.view_for(-1)["hand"], [])


func test_bids_cannot_exceed_coins() -> void:
	var g := _game(2)
	assert_ne(_do(g, G.PICK, {"office": 0, "bid": D.START_COINS + 1}, 0), "")
	assert_ne(_do(g, G.PICK, {"office": 9, "bid": 0}, 0), "")


func test_highest_bid_wins_and_pays() -> void:
	var g := _game(3)
	g.vara = 0
	_pick_all(g, {0: [4, 1], 1: [4, 2], 2: [1, 0]})
	assert_eq(g.holder[4], 1)
	assert_eq(g.coins[1], D.START_COINS - 2)
	assert_eq(g.coins[0], D.START_COINS, "quien pierde no paga")
	assert_eq(g.holder[1], 2)
	assert_eq(g.phase, G.Phase.REASSIGN)
	assert_eq(g.players_to_act(), [0] as Array[int])
	assert_ne(_do(g, G.REASSIGN, {"office": 4}), "", "ocupado")
	assert_eq(_do(g, G.REASSIGN, {"office": 6}), "")
	assert_eq(g.phase, G.Phase.TURN)
	assert_eq(g.turn_office, 1, "empieza el cargo más bajo")
	assert_eq(g.turns.current, 2)


func test_ties_go_to_initiative_order() -> void:
	var g := _game(3)
	g.vara = 2
	_pick_all(g, {0: [3, 1], 1: [3, 1], 2: [5, 0]})
	# Orden desde la vara: 2, 0, 1 → gana el 0.
	assert_eq(g.holder[3], 0)
	assert_eq(g.reassign_queue, [1] as Array[int])


func test_vacant_offices_accumulate_coins() -> void:
	var g := _game(2)
	_pick_all(g, {0: [0, 0], 1: [1, 0]})
	for o in range(2, D.OFFICE_COUNT):
		assert_eq(g.vacant_coins[o], 1)
	# Terminamos la ronda.
	for i in 2:
		assert_eq(_do(g, G.INCOME, {"kind": G.Income.COINS}), "")
		assert_eq(_do(g, G.END_TURN), "")
	assert_eq(g.phase, G.Phase.PICK)
	assert_eq(g.round_number, 2)
	var before := g.coins[0]
	_pick_all(g, {0: [6, 0], 1: [1, 0]})
	assert_eq(g.coins[0], before + 1, "cobra la moneda que había en la Alcaldesa")
	assert_eq(g.vacant_coins[6], 0)
	assert_eq(g.vacant_coins[2], 2)


# --- Turno ------------------------------------------------------------------------

func _to_turn(g: PuertoGame, office0: int, office1: int) -> void:
	_pick_all(g, {0: [office0, 0], 1: [office1, 0]})


func test_must_take_income_before_building_or_ending() -> void:
	var g := _game(2)
	_to_turn(g, 0, 1)
	assert_ne(_do(g, G.END_TURN), "")
	assert_ne(_do(g, G.BUILD, {"card": 0, "cell": 1}), "")
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.COINS}), "")
	assert_eq(g.coins[0], D.START_COINS + D.COIN_INCOME)
	assert_ne(_do(g, G.INCOME, {"kind": G.Income.COINS}), "", "solo una vez")


func test_income_from_dock_and_blind() -> void:
	var g := _game(2)
	_to_turn(g, 2, 3)
	var card: int = g.dock[1]
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.DOCK, "index": 1}), "")
	assert_true(card in g.hands[0])
	assert_eq(g.dock.size(), D.DOCK_SIZE, "el muelle se repone")
	assert_eq(_do(g, G.END_TURN), "")
	var hand: int = g.hands[1].size()
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.BLIND}), "")
	assert_eq(g.hands[1].size(), hand + 1)
	assert_eq(g.coins[1], D.START_COINS + 1)


func test_build_rules() -> void:
	var g := _game(2)
	_to_turn(g, 2, 3)
	g.hands[0] = [0, 4] as Array[int]  # Puesto de fruta (1) y Banco (5)
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.COINS}), "")  # 5 monedas
	assert_ne(_do(g, G.BUILD, {"card": 0, "cell": 7}), "", "no es vecina de nada")
	assert_ne(_do(g, G.BUILD, {"card": 0, "cell": 0}), "", "la Lonja está ocupada")
	assert_eq(_do(g, G.BUILD, {"card": 0, "cell": 1}), "")
	assert_eq(g.coins[0], 4)
	assert_eq(g.districts[0][1], 0)
	assert_ne(_do(g, G.BUILD, {"card": 0, "cell": 7}), "", "solo 1 edificio por turno")


func test_builder_builds_two() -> void:
	var g := _game(2)
	_to_turn(g, D.Office.BUILDER, 0)
	_do(g, G.INCOME, {"kind": G.Income.COINS})  # empieza el 1 (Capitana)
	_do(g, G.END_TURN)
	g.hands[0] = [0, 5, 10] as Array[int]
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.COINS}), "")
	assert_eq(_do(g, G.BUILD, {"card": 0, "cell": 1}), "")
	assert_eq(_do(g, G.BUILD, {"card": 0, "cell": 7}), "")
	assert_ne(_do(g, G.BUILD, {"card": 0, "cell": 2}), "")
	assert_eq(g.building_count(0), 2)


func test_planner_discount_and_move() -> void:
	var g := _game(2)
	_to_turn(g, D.Office.PLANNER, D.Office.MAYOR)
	g.hands[0] = [3] as Array[int]  # Casa de cambio (4)
	g.districts[0][1] = 0
	assert_eq(_do(g, G.INCOME, {"kind": G.Income.COINS}), "")
	assert_eq(g.build_cost(0, 3), 2, "coste 4: cuesta 2 menos")
	assert_eq(g.build_cost(0, 2), 3, "coste 3: sin rebaja")
	assert_eq(g.build_cost(0, 0), 1, "coste 1: sin rebaja")
	assert_ne(_do(g, G.ABILITY, {"from": 1, "to": 9}), "", "quedaría suelto")
	assert_eq(_do(g, G.ABILITY, {"from": 1, "to": 4}), "")
	assert_eq(g.districts[0][4], 0)
	assert_eq(g.districts[0][1], D.EMPTY)
	assert_eq(_do(g, G.BUILD, {"card": 0, "cell": 3}), "")
	assert_eq(g.coins[0], D.START_COINS + D.COIN_INCOME - 2)


func test_harbor_takes_and_refreshes_dock() -> void:
	var g := _game(2)
	_to_turn(g, D.Office.HARBOR, D.Office.MAYOR)
	var old := g.dock.duplicate()
	var discarded := g.discard.size()
	assert_eq(_do(g, G.ABILITY, {"index": 2}), "")
	assert_true(old[2] in g.hands[0])
	assert_eq(g.discard.size(), discarded + 3)
	assert_eq(g.dock.size(), D.DOCK_SIZE)
	assert_ne(_do(g, G.ABILITY, {"index": 0}), "", "una vez por turno")


func test_smuggler_takes_a_card() -> void:
	var g := _game(3)
	_pick_all(g, {0: [D.Office.SMUGGLER, 0], 1: [0, 0], 2: [6, 0]})
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	_do(g, G.END_TURN)
	assert_eq(g.turns.current, 0)
	assert_ne(_do(g, G.ABILITY, {"target": 0}), "", "no a sí mismo")
	assert_eq(_do(g, G.ABILITY, {"target": 2}), "")
	assert_eq(g.hands[0].size(), D.START_HAND + 1)
	assert_eq(g.hands[2].size(), D.START_HAND - 1)
	assert_eq(g.coins[0], D.START_COINS, "no paga nada")
	assert_eq(g.coins[2], D.START_COINS)


func test_collector_and_patron() -> void:
	var g := _game(3)
	g.districts[0][1] = 0
	g.districts[0][7] = 1  # grupo de Comercio
	g.districts[0][2] = 5
	g.districts[0][3] = 6  # grupo de Mar (2 y 3 son vecinos)
	g.coins.assign([5, 2, 2])
	_pick_all(g, {0: [D.Office.PATRON, 0], 1: [D.Office.COLLECTOR, 0], 2: [6, 0]})
	assert_eq(g.turns.current, 1)
	# Usa el cargo antes de cobrar: paga quien tiene más monedas que ella.
	assert_eq(_do(g, G.ABILITY), "")
	assert_eq(g.coins, [4, 3, 2] as Array[int], "solo paga el 0 (el 2 tiene las mismas)")
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	_do(g, G.END_TURN)
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	assert_eq(_do(g, G.ABILITY), "")
	assert_eq(g.coins[0], 4 + D.COIN_INCOME + 2, "2 grupos")


func test_mayor_takes_the_vara_and_draws() -> void:
	var g := _game(2)
	g.vara = 0
	_to_turn(g, 0, D.Office.MAYOR)
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	var hand: int = g.hands[1].size()
	_do(g, G.END_TURN)
	assert_eq(g.vara, 1)
	assert_eq(g.hands[1].size(), hand + 1)
	assert_eq(g.coins[1], D.START_COINS + D.MAYOR_COINS)
	assert_ne(_do(g, G.ABILITY), "", "la Alcaldesa no tiene acción")


func test_customs_gives_extra_coin() -> void:
	var g := _game(2)
	for i in D.BUILDINGS.size():
		if D.wonder_of(i) == D.Wonder.CUSTOMS:
			g.districts[0][1] = i
	_to_turn(g, 0, 1)
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	assert_eq(g.coins[0], D.START_COINS + D.COIN_INCOME + 1)


# --- Final ------------------------------------------------------------------------

func test_game_ends_after_the_round_when_a_district_is_complete() -> void:
	var g := _game(2)
	var cells := [1, 2, 3, 4, 5, 6, 7, 8]
	for i in cells.size():
		g.districts[0][cells[i]] = 0
	g.hands[0] = [0] as Array[int]
	_to_turn(g, 0, 1)
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	assert_eq(_do(g, G.BUILD, {"card": 0, "cell": 9}), "")
	assert_eq(g.first_finisher, 0)
	assert_false(g.finished, "se acaba la ronda")
	_do(g, G.END_TURN)
	_do(g, G.INCOME, {"kind": G.Income.COINS})
	_do(g, G.END_TURN)
	assert_true(g.finished)
	assert_eq(g.final_scores.size(), 2)
	assert_eq(g.final_scores[0]["first"], D.FIRST_TO_FINISH_POINTS)
	# 9 Puestos de fruta en un grupo: 9 + 9 + 3 por terminar (+ objetivos).
	assert_true(g.final_scores[0]["total"] >= 21)
	assert_eq(g.winner_ids, [0] as Array[int])


func test_full_games_finish_and_replay() -> void:
	for n in range(2, 7):
		var g := _game(n, 100 + n)
		var count := _autoplay(g)
		assert_true(g.finished, "%d jugadores: la partida termina (%d acciones)" % [n, count])
		# Se conservan todas las cartas.
		var total := g.deck.size() + g.discard.size() + g.dock.size()
		for pid in n:
			total += g.hands[pid].size() + g.building_count(pid)
		assert_eq(total, D.deck(n).size(), "%d jugadores: no se pierden cartas" % n)
		var copy := PuertoGame.new()
		copy.setup(GameBase.players_from_save(g.save_data()), g.rng.seed_value)
		assert_eq(copy.replay(g.save_data()["history"]), "")
		assert_eq(copy.coins, g.coins, "repetición idéntica")
		assert_eq(copy.districts, g.districts)
		assert_eq(copy.winner_ids, g.winner_ids)


func test_legal_actions_are_valid() -> void:
	var g := _game(4, 7)
	var steps := 0
	while not g.finished and steps < 300:
		var pid: int = g.players_to_act()[0]
		var actions := g.get_legal_actions(pid)
		assert_false(actions.is_empty(), "siempre hay algo que hacer")
		for a in actions:
			assert_eq(g.validate(a), "", str(a))
		g.submit(_simple_action(g, pid))
		steps += 1
