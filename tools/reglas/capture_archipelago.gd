extends RulesCapture
## Capturas del reglamento en PDF de Archipiélago (ver rules_capture.gd).

const G := preload("res://games/archipelago/logic/archipelago_game.gd")


func _init() -> void:
	game_id = "archipelago"
	player_count = 3


func _new_game() -> GameBase:
	return ArchipelagoGame.new()


func _new_ai(pid: int) -> Object:
	return ArchAI.new(pid, PlayerInfo.AILevel.NORMAL, seed_value + pid)


func _screen_scene() -> PackedScene:
	return preload("res://games/archipelago/archipelago.tscn")


func _load(n: int, view_3d: bool = true) -> void:
	await load_state(n, 6, {"board_3d": view_3d})


func _shoot_all() -> void:
	# 1. Tablero vacío al empezar la colocación inicial (en 3D y en 2D).
	await _load(0)
	await shot("01_tablero")
	await _load(0, false)
	await shot("01b_tablero_2d")

	# 2. Colocación inicial: camino junto al primer poblado.
	await _load(1)
	await shot("02_colocacion_camino")

	# 3. Fin de la colocación: primer turno, hay que tirar los dados.
	var first_roll := find(func(g, _n): return g.phase == G.Phase.ROLL)
	await _load(first_roll)
	await shot("03_primer_turno")

	# 4. Turno en marcha con recursos: modo «construir poblado».
	var build := find(func(g, _n):
		return g.phase == G.Phase.MAIN and g.trade_offer.is_empty() \
			and g.build_error(g.turns.current, G.BUILD_SETTLEMENT) == "" \
			and not g.legal_settlement_vertices(g.turns.current).is_empty(), first_roll)
	if build >= 0:
		await _load(build)
		_screen._on_build_pressed(_screen.Mode.SETTLEMENT)
		await settle(0.6)
		await shot("04_construir_poblado")

	# 5. Descartes tras un 7.
	var discard := find(func(g, _n): return g.phase == G.Phase.DISCARD, first_roll)
	if discard >= 0:
		await _load(discard)
		await shot("05_descartar")

	# 6. Mover el bandido.
	var robber := find(func(g, _n): return g.phase == G.Phase.ROBBER, first_roll)
	if robber >= 0:
		await _load(robber)
		await shot("06_bandido")

	# 7. Comercio con la banca (mejor si el jugador tiene un puerto).
	var bank := find(func(g, _n):
		if g.phase != G.Phase.MAIN or not g.trade_offer.is_empty():
			return false
		var pid: int = g.turns.current
		for r in G.RESOURCE_COUNT:
			if g.trade_ratio(pid, r) < 4 and g.hands[pid][r] >= g.trade_ratio(pid, r):
				return true
		return false, first_roll)
	if bank < 0:
		bank = find(func(g, _n): return g.phase == G.Phase.MAIN and g.hand_size(g.turns.current) >= 4, first_roll)
	await _load(bank)
	_screen._open_bank_dialog()
	await settle(0.4)
	await shot("07_comercio_banca")

	# 8. Proponer un intercambio a otro jugador.
	_screen._cancel_dialog()
	_screen._open_offer_dialog()
	await settle(0.4)
	await shot("08_proponer_intercambio")

	# 9. Oferta recibida.
	var offer := find(func(g, _n): return not g.trade_offer.is_empty(), first_roll)
	if offer >= 0:
		await _load(offer)
		await shot("09_oferta_recibida")

	# 10. Cartas de desarrollo en la mano del jugador en turno.
	var dev := find(func(g, _n):
		var pid: int = g.turns.current
		return g.phase == G.Phase.MAIN and g.trade_offer.is_empty() and g.dev_hand_size(pid) >= 2, first_roll)
	if dev >= 0:
		await _load(dev)
		await shot("10_cartas_desarrollo")

	# 11. Partida avanzada (premios repartidos), en 3D y en 2D.
	var late := find(func(g, _n):
		return g.phase == G.Phase.ROLL and g.longest_road_owner >= 0 and g.largest_army_owner >= 0, first_roll)
	if late < 0:
		late = find(func(g, _n): return g.phase == G.Phase.ROLL and g.longest_road_owner >= 0, first_roll)
	if late < 0:
		late = _history.size() - 1
	await _load(late)
	await shot("11_partida_avanzada")
	await _load(late, false)
	await shot("12_vista_2d")

	# 13. Final de la partida.
	await _load(_history.size())
	await shot("13_victoria")
	App.set_setting("board_3d", true)
