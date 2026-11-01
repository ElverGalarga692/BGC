extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")
const AILevel := PlayerInfo.AILevel


func _game(n: int, quick: bool, auto: bool, seed_value: int, levels: Array) -> PestsGame:
	var g := PestsGame.new()
	g.options = {"quick_species": quick, "auto_house": auto}
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i, "", Color.WHITE, levels[i % levels.size()]))
	g.setup(ps, seed_value)
	return g


## Juega con IAs hasta el final. Devuelve false si una IA propone algo ilegal
## o la partida no termina.
func _play_out(g: PestsGame, seed_value: int, max_actions: int = 6000) -> bool:
	var ais := []
	for p in g.players:
		ais.append(PestsAI.new(p.id, p.ai_level, seed_value))
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


## Bloque 2x2 de 2 jugadores con especies fijas (ver test_pests_cards.gd).
func _square(sp0: int, sp1: int) -> Dictionary:
	var h := PestsHouse.new()
	var a := h.place_nest(Vector2i(0, -1), sp0)
	var b := h.place_custom(Vector2i(1, 0), D.DOOR_ALL)
	var c := h.place_custom(Vector2i(1, -1), D.DOOR_ALL)
	var n1 := h.place_nest(Vector2i(-1, 0), sp1)
	var g := _game(2, true, true, 1, [AILevel.HARD])
	g.species_of.assign([sp0, sp1])
	g.house = h
	g.pests.clear()
	for r in h.room_count():
		g.pests.append([0, 0, 0, 0, 0, 0])
	g.traps.clear()
	g.reserve.assign([0, 0, 0, 0, 0, 0])
	g.pool.assign([0, 0, 0, 0, 0, 0])
	g.queen_room.assign([-1, -1, -1, -1, -1, -1])
	g.sealed.assign([false, false, false, false, false, false])
	for pid in 2:
		var sp := g.species_of[pid]
		g.pool[sp] = 20
		g.reserve[sp] = 20
		g.queen_room[sp] = n1 if pid == 1 else c
		g.exterminator_room[pid] = 0
		g.hands[pid] = []
		g.turns_taken[pid] = 1
	g.effects.clear()
	g.turns.current = 0
	g.phase = G.Phase.EXTERMINATOR
	g.free_move = true
	g.action_points = D.ACTION_POINTS
	return {"game": g, "e": 0, "a": a, "b": b, "c": c, "n1": n1}


func test_every_level_finishes_games() -> void:
	var finished := 0
	var total := 0
	for level in [AILevel.EASY, AILevel.NORMAL, AILevel.HARD]:
		for n in [2, 4, 6]:
			var g := _game(n, n != 4, n != 6, 700 + level * 10 + n, [level])
			total += 1
			if _play_out(g, level):
				finished += 1
	assert_eq(finished, total, "todas las partidas terminan")


func test_mixed_levels_with_full_rules() -> void:
	var g := _game(3, false, false, 77, [AILevel.HARD, AILevel.NORMAL, AILevel.EASY])
	assert_true(_play_out(g, 3), "con elección de cartas y casa a mano")


func test_clone_is_independent_and_reproducible() -> void:
	var g := _game(3, true, true, 12, [AILevel.NORMAL])
	var copy := g.clone()
	var pid := g.turns.current
	assert_eq(copy.submit(GameAction.new(G.ROLL_QUEEN, pid)), "")
	assert_eq(g.phase, G.Phase.QUEEN, "la original no cambia")
	assert_eq(g.history.size(), 0)
	# Con el mismo estado del azar, la misma jugada da el mismo resultado.
	assert_eq(g.submit(GameAction.new(G.ROLL_QUEEN, pid)), "")
	assert_eq(copy.pests, g.pests)
	assert_eq(copy.queen_room, g.queen_room)
	assert_eq(copy.last_queen_face, g.last_queen_face)
	# Cambiar la copia no toca la original.
	copy.pests[0][0] += 50
	copy.hands[0].append("zap")
	assert_ne(copy.pests[0][0], g.pests[0][0])
	assert_ne(copy.hands[0].size(), g.hands[0].size())


func test_hard_takes_the_win() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.sealed[D.Species.BLUE] = true
	g.traps.append({"id": 3, "owner": 0, "room": s["b"], "pests": 0, "queen": true, "prefer_queen": true})
	g.queen_room[D.Species.BLUE] = s["b"]
	assert_true(_play_turn(g, PestsAI.new(0, AILevel.HARD, 1)))
	assert_true(g.finished)
	assert_eq(g.winner_ids, [0] as Array[int])


func test_hard_seals_its_nest_this_turn() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	_put(g, D.Species.BLUE, s["a"], 3)
	_play_turn(g, PestsAI.new(0, AILevel.HARD, 1))
	assert_true(g.sealed[D.Species.BLUE], "va a su nido (al lado) y lo sella")


func test_hard_exterminates_nearby_pests() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	g.sealed[D.Species.BLUE] = true
	# Su reina está en su nido (no se puede soltar trampa allí): lo mejor es
	# exterminar.
	g.queen_room[D.Species.BLUE] = s["a"]
	_put(g, D.Species.BLUE, s["b"], 8)
	_play_turn(g, PestsAI.new(0, AILevel.HARD, 1))
	assert_true(g.pests_in_room(s["b"], D.Species.BLUE) < 8, "se mueve a B y extermina")


func test_hard_uses_mind_control_when_it_helps() -> void:
	var s := _square(D.Species.BLUE, D.Species.GREEN)
	var g: PestsGame = s["game"]
	# Reina azul en B y una trampa azul vacía en C, justo encima: con Control
	# mental la manda arriba, a la trampa.
	g.queen_room[D.Species.BLUE] = s["b"]
	g.traps.append({"id": 1, "owner": 0, "room": s["c"], "pests": 0, "queen": false, "prefer_queen": true})
	g.hands[0] = ["mind_control"]
	g._start_turn(0)
	var action := PestsAI.new(0, AILevel.HARD, 1).choose_action(g)
	assert_eq(action.type, G.PLAY_CARD)
	assert_eq(action.data.get("queen_action"), D.QueenAction.UP)


func test_normal_attacks_the_leader() -> void:
	var g := _game(3, true, true, 5, [AILevel.NORMAL])
	var ai := PestsAI.new(0, AILevel.NORMAL, 1)
	var other := 1
	var leader := 2
	g.sealed[g.species(leader)] = true
	assert_eq(ai._leader(g), leader)
	assert_ne(ai._leader(g), other)


## Juega el turno de exterminador del jugador 0 con esa IA. Devuelve true si
## la partida ha terminado.
func _play_turn(g: PestsGame, ai: PestsAI) -> bool:
	var guard := 0
	while not g.finished and g.turns.current == 0 and g.phase == G.Phase.EXTERMINATOR and guard < 20:
		var action := ai.choose_action(g)
		assert_eq(g.submit(action), "")
		guard += 1
	return g.finished


func _put(g: PestsGame, sp: int, room: int, count: int) -> void:
	g.reserve[sp] -= count
	g.pests[room][sp] += count
