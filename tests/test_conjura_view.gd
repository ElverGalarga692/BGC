extends TestCase
## La Conjura: view_for(seat) nunca filtra información secreta, y la IA
## básica termina partidas completas sin jugadas ilegales.

const G := preload("res://games/conjura/logic/conjura_game.gd")
const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Edict := ConjuraDefs.Edict


func _game(n: int = 5, seed: int = 7, ai_level: int = PlayerInfo.AILevel.HUMAN) -> ConjuraGame:
	var players: Array[PlayerInfo] = []
	for i in n:
		players.append(PlayerInfo.new(i, "", PlayerInfo.default_color(i), ai_level))
	var game := ConjuraGame.new()
	game.setup(players, seed)
	return game


func _sombra_ids(game: ConjuraGame) -> Array[int]:
	var result: Array[int] = []
	for i in game.players.size():
		if game.roles[i] != Role.GUARDIA:
			result.append(i)
	return result


func test_guardia_only_knows_itself() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 3)
		for seat in n:
			if game.roles[seat] != Role.GUARDIA:
				continue
			var known: Dictionary = game.view_for(seat)["known_roles"]
			assert_eq(known.size(), 1, "un guardia con %d jugadores" % n)
			assert_eq(known[seat], Role.GUARDIA)


func test_sombra_knows_all_allies() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 5)
		var allies := _sombra_ids(game)
		for seat in n:
			if game.roles[seat] != Role.SOMBRA:
				continue
			var known: Dictionary = game.view_for(seat)["known_roles"]
			assert_eq(known.size(), allies.size(), "sombra con %d jugadores" % n)
			for a in allies:
				assert_eq(known.get(a, -1), game.roles[a])


func test_usurper_knows_allies_only_in_small_games() -> void:
	for n in range(5, 11):
		var game := _game(n, n * 11)
		var seat := game.roles.find(Role.USURPADOR)
		var known: Dictionary = game.view_for(seat)["known_roles"]
		var expected := _sombra_ids(game).size() if n <= D.USURPER_KNOWS_ALLIES_MAX else 1
		assert_eq(known.size(), expected, "usurpador con %d jugadores" % n)


func test_public_view_has_no_secrets() -> void:
	var game := _game()
	var view := game.view_for(-1)
	assert_true(view["known_roles"].is_empty())
	assert_true(view["hand"].is_empty())
	assert_true(view["knowledge"].is_empty())
	assert_false(view.has("roles"))
	assert_false(view.has("draw_pile"))


func test_votes_hidden_until_resolved() -> void:
	var game := _game()
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	game.submit(GameAction.new(G.VOTE, 0, {"yes": false}))
	game.submit(GameAction.new(G.VOTE, 1, {"yes": true}))
	for seat in 5:
		var view := game.view_for(seat)
		assert_eq(view["voted"].size(), 2, "se sabe quién ha votado")
		for v in view["voted"].values():
			assert_eq(v, true, "pero no qué ha votado")
		if seat == 0:
			assert_eq(view["my_vote"], false)
		elif seat == 1:
			assert_eq(view["my_vote"], true)
		else:
			assert_eq(view["my_vote"], null)
		assert_true(view["last_votes"].is_empty())
	for pid in range(2, 5):
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	assert_eq(game.view_for(-1)["last_votes"].size(), 5, "al resolverse, los votos son públicos")


func test_hand_only_visible_to_holder() -> void:
	var game := _game()
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	for pid in 5:
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	for seat in 5:
		var hand: Array = game.view_for(seat)["hand"]
		assert_eq(hand.size(), 3 if seat == game.regent else 0, "Regente: asiento %d" % seat)
	game.submit(GameAction.new(G.DISCARD, game.regent, {"index": 0}))
	for seat in 5:
		var hand: Array = game.view_for(seat)["hand"]
		assert_eq(hand.size(), 2 if seat == game.council else 0, "Consejero: asiento %d" % seat)


func test_knowledge_is_private() -> void:
	var game := _game()
	game.knowledge[2].append({"kind": "faction", "target": 0, "faction": 0})
	for seat in 5:
		assert_eq(game.view_for(seat)["knowledge"].size(), 1 if seat == 2 else 0)


func test_view_is_a_copy() -> void:
	var game := _game()
	var view := game.view_for(0)
	view["alive"][1] = false
	view["known_roles"][3] = Role.USURPADOR
	assert_true(game.alive[1], "modificar la vista no cambia la partida")
	assert_false(game.view_for(0)["known_roles"].has(3) and game.roles[3] != Role.USURPADOR and game.roles[0] == Role.GUARDIA)


func test_finished_game_reveals_everything() -> void:
	var game := _game()
	game.guardia_edicts = 4
	for i in 3:
		game.draw_pile.push_front(Edict.GUARDIA)
	game.submit(GameAction.new(G.NOMINATE, game.regent, {"target": game.eligible_nominees()[0]}))
	for pid in 5:
		game.submit(GameAction.new(G.VOTE, pid, {"yes": true}))
	game.submit(GameAction.new(G.DISCARD, game.regent, {"index": 0}))
	game.submit(GameAction.new(G.ENACT, game.council, {"index": 0}))
	assert_true(game.finished)
	assert_eq(game.view_for(-1)["known_roles"].size(), 5)


func test_ai_games_finish() -> void:
	var wins := {0: 0, 1: 0}
	for g in 60:
		var n := 5 + g % 6
		var game := _game(n, 1000 + g, PlayerInfo.AILevel.NORMAL)
		var ais := {}
		for pid in n:
			ais[pid] = ConjuraAI.new(pid, [PlayerInfo.AILevel.EASY, PlayerInfo.AILevel.NORMAL, PlayerInfo.AILevel.HARD][pid % 3], g)
		var steps := 0
		while not game.finished and steps < 2000:
			var pid: int = game.players_to_act()[0]
			var action: GameAction = ais[pid].choose_action(game)
			assert_true(action != null, "la IA siempre tiene jugada")
			if action == null:
				return
			var error := game.submit(action)
			assert_eq(error, "", "jugada legal de la IA")
			if error != "":
				return
			steps += 1
		assert_true(game.finished, "la partida %d termina" % g)
		wins[game.winner_faction] += 1
	assert_true(wins[0] > 0 and wins[1] > 0, "ganan las dos facciones alguna vez: %s" % wins)
