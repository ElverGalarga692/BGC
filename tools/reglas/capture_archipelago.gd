extends Node
## Saca las capturas del reglamento en PDF de Archipiélago.
##
## Juega una partida entera con tres IAs (solo la lógica), guarda sus jugadas
## y después carga la pantalla real del juego en distintos momentos de esa
## partida para fotografiarla. Necesita una pantalla (o Xvfb):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . \
##       res://tools/reglas/capture_archipelago.tscn -- <carpeta_salida>

const G := preload("res://games/archipelago/logic/archipelago_game.gd")
const SCREEN := preload("res://games/archipelago/archipelago.tscn")
const SEED := 20261102
const NAMES := ["Ana", "Bruno", "Carla"]

var _out := "user://capturas"
var _history: Array = []
var _screen: Control


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1600, 900)
	_history = _play_full_game()
	await _shoot_all()
	get_tree().quit()


func _players() -> Array[PlayerInfo]:
	var players: Array[PlayerInfo] = []
	for i in NAMES.size():
		players.append(PlayerInfo.new(i, NAMES[i], PlayerInfo.default_color(i)))
	return players


## Partida completa entre IAs normales; devuelve sus jugadas como diccionarios.
func _play_full_game() -> Array:
	var game := ArchipelagoGame.new()
	game.setup(_players(), SEED)
	var ais := {}
	for p in game.players:
		ais[p.id] = ArchAI.new(p.id, PlayerInfo.AILevel.NORMAL, SEED + p.id)
		ais[p.id].observe(game)
	var guard := 0
	while not game.finished and guard < 5000:
		guard += 1
		var actor: int = game.players_to_act()[0]
		var action: GameAction = ais[actor].choose_action(game)
		if action == null or game.submit(action) != "":
			push_error("La IA se ha atascado")
			break
	print("Partida de %d jugadas; gana %s" % [game.history.size(), game.winner_ids])
	return game.history.map(func(a: GameAction) -> Dictionary: return a.to_dict())


## Estado de la partida tras las primeras `n` jugadas.
func _state_at(n: int) -> ArchipelagoGame:
	var game := ArchipelagoGame.new()
	game.setup(_players(), SEED)
	game.replay(_history.slice(0, n))
	return game


## Primer índice >= from en el que se cumple `test(game, n)`.
func _find(test: Callable, from: int = 0) -> int:
	var game := ArchipelagoGame.new()
	game.setup(_players(), SEED)
	for n in range(0, _history.size() + 1):
		if n > 0:
			game.submit(GameAction.from_dict(_history[n - 1]))
		if n >= from and test.call(game, n):
			return n
	return -1


## Carga la pantalla del juego con las primeras `n` jugadas. Las últimas
## `live` se juegan ya con la pantalla abierta, para que salgan en el registro.
func _load(n: int, view_3d: bool = true, live: int = 6) -> void:
	if _screen != null:
		_screen.queue_free()
		await get_tree().process_frame
	App.set_setting("board_3d", view_3d)
	App.session = {
		"game_id": "archipelago",
		"players": _players(),
		"seed": SEED,
		"history": _history.slice(0, n - mini(live, n)),
		"options": {},
	}
	_screen = SCREEN.instantiate()
	add_child(_screen)
	await get_tree().process_frame
	_screen._log.clear()
	_screen._log_label.clear()
	for i in range(n - mini(live, n), n):
		_screen.game.submit(GameAction.from_dict(_history[i]))
	# El ratón, fuera del tablero (si no, sale el nombre de la casilla).
	get_viewport().warp_mouse(Vector2(4, 896))
	await _settle(2.6)


func _settle(seconds: float = 1.8) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Captura: ", path)


func _last_type(game: ArchipelagoGame) -> StringName:
	return game.history.back().type if not game.history.is_empty() else &""


func _shoot_all() -> void:
	# 1. Tablero vacío al empezar la colocación inicial.
	await _load(0)
	await _shot("01_tablero")
	await _load(0, false)
	await _shot("01b_tablero_2d")

	# 2. Colocación inicial: camino junto al primer poblado.
	await _load(1)
	await _shot("02_colocacion_camino")

	# 3. Fin de la colocación: primer turno, hay que tirar los dados.
	var first_roll := _find(func(g, _n): return g.phase == G.Phase.ROLL)
	await _load(first_roll)
	await _shot("03_primer_turno")

	# 4. Turno en marcha con recursos: modo «construir poblado» (o camino).
	var build := _find(func(g, _n):
		return g.phase == G.Phase.MAIN and g.trade_offer.is_empty() \
			and g.build_error(g.turns.current, G.BUILD_SETTLEMENT) == "" \
			and not g.legal_settlement_vertices(g.turns.current).is_empty(), first_roll)
	if build >= 0:
		await _load(build)
		_screen._on_build_pressed(_screen.Mode.SETTLEMENT)
		await _settle(0.6)
		await _shot("04_construir_poblado")

	# 5. Descartes tras un 7.
	var discard := _find(func(g, _n): return g.phase == G.Phase.DISCARD, first_roll)
	if discard >= 0:
		await _load(discard)
		await _shot("05_descartar")

	# 6. Mover el bandido.
	var robber := _find(func(g, _n): return g.phase == G.Phase.ROBBER, first_roll)
	if robber >= 0:
		await _load(robber)
		await _shot("06_bandido")

	# 7. Comercio con la banca (mejor si el jugador tiene un puerto).
	var bank := _find(func(g, n):
		if g.phase != G.Phase.MAIN or not g.trade_offer.is_empty():
			return false
		var pid: int = g.turns.current
		for r in G.RESOURCE_COUNT:
			if g.trade_ratio(pid, r) < 4 and g.hands[pid][r] >= g.trade_ratio(pid, r):
				return true
		return false, first_roll)
	if bank < 0:
		bank = _find(func(g, _n): return g.phase == G.Phase.MAIN and g.hand_size(g.turns.current) >= 4, first_roll)
	await _load(bank)
	_screen._open_bank_dialog()
	await _settle(0.4)
	await _shot("07_comercio_banca")

	# 8. Proponer un intercambio a otro jugador.
	_screen._cancel_dialog()
	_screen._open_offer_dialog()
	await _settle(0.4)
	await _shot("08_proponer_intercambio")

	# 9. Oferta recibida (si las IAs llegaron a ofrecer algo).
	var offer := _find(func(g, _n): return not g.trade_offer.is_empty(), first_roll)
	if offer >= 0:
		await _load(offer)
		await _shot("09_oferta_recibida")

	# 10. Cartas de desarrollo en la mano del jugador en turno.
	var dev := _find(func(g, _n):
		var pid: int = g.turns.current
		return g.phase == G.Phase.MAIN and g.trade_offer.is_empty() and g.dev_hand_size(pid) >= 2, first_roll)
	if dev >= 0:
		await _load(dev)
		await _shot("10_cartas_desarrollo")

	# 11. Partida avanzada (premios repartidos), en 3D y en 2D.
	var late := _find(func(g, _n):
		return g.phase == G.Phase.ROLL and g.longest_road_owner >= 0 and g.largest_army_owner >= 0, first_roll)
	if late < 0:
		late = _find(func(g, _n): return g.phase == G.Phase.ROLL and g.longest_road_owner >= 0, first_roll)
	if late < 0:
		late = _history.size() - 1
	await _load(late)
	await _shot("11_partida_avanzada")
	await _load(late, false)
	await _shot("12_vista_2d")

	# 13. Final de la partida.
	await _load(_history.size())
	await _shot("13_victoria")
	App.set_setting("board_3d", true)
