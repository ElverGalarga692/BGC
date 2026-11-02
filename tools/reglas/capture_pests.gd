extends RulesCapture
## Capturas del reglamento en PDF de Pests! (ver rules_capture.gd).
## Partida a 4 con elección de exterminadores, de cartas y de losetas, y otra
## partida por equipos para la sección opcional.

const G := preload("res://games/pests/logic/pests_game.gd")


func _init() -> void:
	game_id = "pests"
	player_count = 4
	options = {"quick_species": false, "auto_house": false, "teams": false}


func _new_game() -> GameBase:
	return PestsGame.new()


func _new_ai(pid: int) -> Object:
	return PestsAI.new(pid, PlayerInfo.AILevel.NORMAL, seed_value + pid)


func _screen_scene() -> PackedScene:
	return preload("res://games/pests/pests.tscn")


func _exterminating(g) -> bool:
	return g.phase == G.Phase.EXTERMINATOR and not g.finished


func _shoot_all() -> void:
	# 1. Elección de exterminador y de cartas.
	await load_state(0)
	await shot("01_elegir_exterminador")
	var draft := find(func(g, _n): return g.phase == G.Phase.DRAFT and g.hands[g.turns.current].size() >= 1)
	await load_state(draft)
	await shot("02_elegir_cartas")

	# 2. Construcción de la casa, con una loseta elegida.
	var tiles := find(func(g, _n): return g.phase == G.Phase.PLACE_TILES and g.house.room_count() >= 7 \
		and not g.tile_options(g.turns.current).is_empty())
	await load_state(tiles)
	_screen._select_tile(_screen.game.tile_options(_screen.game.turns.current)[0]["index"])
	await settle(0.6)
	await shot("03_colocar_loseta")
	var nest := find(func(g, _n):
		if g.phase != G.Phase.PLACE_TILES:
			return false
		var pid: int = g.turns.current
		for o in g.tile_options(pid):
			if g.tile_hands[pid][o["index"]]["kind"] == PestsDefs.RoomKind.NEST:
				return true
		return false)
	if nest >= 0:
		await load_state(nest)
		var pid: int = _screen.game.turns.current
		for o in _screen.game.tile_options(pid):
			if _screen.game.tile_hands[pid][o["index"]]["kind"] == PestsDefs.RoomKind.NEST:
				_screen._select_tile(o["index"])
				break
		await settle(0.6)
		await shot("03b_colocar_nido")

	# 3. Casa terminada e infestada: primer turno.
	var first := find(func(g, _n): return g.phase == G.Phase.QUEEN)
	await load_state(first)
	await shot("04_casa_infestada")

	# 4. Después de la reina: turno del exterminador.
	var ext := find(func(g, _n): return _exterminating(g), first)
	await load_state(ext)
	await shot("05_turno_exterminador")

	# 5. Una carta con varios objetivos: ventana de elección.
	var card := find(func(g, _n):
		if not _exterminating(g):
			return false
		var count := {}
		for a in g.get_legal_actions(g.turns.current):
			if a.type == G.PLAY_CARD and PestsDefs.card(a.data["card"])["kind"] == PestsDefs.CardKind.OFFENSIVE:
				count[a.data["card"]] = count.get(a.data["card"], 0) + 1
		return count.values().any(func(c): return c >= 3), ext)
	if card >= 0:
		await load_state(card)
		var g = _screen.game
		var by_card := {}
		for a in g.get_legal_actions(g.turns.current):
			if a.type == G.PLAY_CARD and PestsDefs.card(a.data["card"])["kind"] == PestsDefs.CardKind.OFFENSIVE:
				if not by_card.has(a.data["card"]):
					by_card[a.data["card"]] = [] as Array[GameAction]
				by_card[a.data["card"]].append(a)
		for id in by_card:
			if by_card[id].size() >= 3:
				_screen._choose("Jugar «%s»" % PestsDefs.card(id)["name"], by_card[id])
				break
		await settle(0.5)
		await shot("06_jugar_carta")

	# 6. Trampas: una con plagas y una reina atrapada.
	var trap := find(func(g, _n):
		return _exterminating(g) and g.traps.any(func(t): return t["pests"] >= 2), ext)
	if trap >= 0:
		await load_state(trap)
		await shot("07_trampa_plagas")
	var queen := find(func(g, _n):
		if not _exterminating(g):
			return false
		for pid in g.players.size():
			if g.species(pid) >= 0 and g.is_queen_trapped(g.species(pid)):
				return true
		return false, ext)
	if queen >= 0:
		await load_state(queen)
		await shot("08_reina_atrapada")

	# 7. Nido sellado y cartas delante de un jugador.
	var sealed := find(func(g, _n): return _exterminating(g) and g.sealed.has(true) and not g.effects.is_empty(), ext)
	if sealed < 0:
		sealed = find(func(g, _n): return _exterminating(g) and g.sealed.has(true), ext)
	if sealed >= 0:
		await load_state(sealed)
		await shot("09_nido_sellado")

	# 8. Un jugador eliminado (si ocurre) y el final.
	var out := find(func(g, _n): return g.eliminated.has(true) and not g.finished, ext)
	if out >= 0:
		await load_state(out)
		await shot("10_eliminado")
	var before_end := maxi(ext, _history.size() - 1)
	await load_state(before_end)
	await shot("11_antes_del_final")
	await load_state(_history.size())
	await shot("12_victoria")

	# 9. Partida por equipos (casa y cartas al azar).
	options = {"quick_species": true, "auto_house": true, "teams": true}
	seed_value += 7
	_history = play_full_game()
	var team_ext := find(func(g, _n): return _exterminating(g) and g.turns_taken.min() >= 2)
	await load_state(team_ext)
	await shot("13_equipos")
