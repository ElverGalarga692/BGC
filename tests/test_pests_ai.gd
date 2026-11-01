extends TestCase

const G := preload("res://games/pests/logic/pests_game.gd")


## Partidas completas entre IAs: nunca proponen una jugada ilegal y la
## partida termina.
func test_ai_games_finish() -> void:
	var finished := 0
	for n in range(2, 7):
		for s in 2:
			var g := PestsGame.new()
			g.options = {"quick_species": s == 0, "auto_house": s == 0}
			var ps: Array[PlayerInfo] = []
			for i in n:
				ps.append(PlayerInfo.new(i, "", Color.WHITE, PlayerInfo.AILevel.NORMAL))
			g.setup(ps, 1000 + n * 10 + s)
			var ais := []
			for i in n:
				ais.append(PestsAI.new(i, PlayerInfo.AILevel.NORMAL, s))
			var count := 0
			while not g.finished and count < 6000:
				var pid: int = g.players_to_act()[0]
				var action: GameAction = ais[pid].choose_action(g)
				assert_true(action != null, "la IA siempre propone algo")
				if action == null:
					break
				var error := g.submit(action)
				if error != "":
					assert_eq(error, "", "jugada legal de la IA: %s" % action)
					break
				count += 1
			if g.finished:
				finished += 1
	assert_eq(finished, 10, "todas las partidas terminan")
