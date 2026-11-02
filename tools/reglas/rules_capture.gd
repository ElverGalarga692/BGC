class_name RulesCapture
extends Node
## Base de los scripts que sacan las capturas de los reglamentos en PDF.
##
## Juega una partida entera entre IAs (solo la lógica), guarda sus jugadas y
## después abre la pantalla real del juego en distintos momentos de esa
## partida para fotografiarla. Cada juego hereda de esta clase y define
## _new_game(), _new_ai(), _screen_scene() y _shoot_all().
##
## Uso (necesita pantalla; en un servidor, Xvfb):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . \
##       --rendering-driver opengl3 res://tools/reglas/capture_<juego>.tscn -- <carpeta>

const NAMES := ["Ana", "Bruno", "Carla", "David", "Elena", "Fran"]

var seed_value := 20261102
var player_count := 3
var options := {}
var game_id := ""

var _out := "user://capturas"
var _history: Array = []
var _screen: Control


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1600, 900)
	_history = play_full_game()
	await _shoot_all()
	get_tree().quit()


# --- A definir en cada juego ---------------------------------------------------

func _new_game() -> GameBase:
	return null


func _new_ai(_pid: int) -> Object:
	return null


func _screen_scene() -> PackedScene:
	return null


func _shoot_all() -> void:
	pass


# --- Partida -------------------------------------------------------------------

func players() -> Array[PlayerInfo]:
	var result: Array[PlayerInfo] = []
	for i in player_count:
		result.append(PlayerInfo.new(i, NAMES[i], PlayerInfo.default_color(i)))
	return result


func fresh_game() -> GameBase:
	var game := _new_game()
	if "options" in game and not options.is_empty():
		game.options = options.duplicate()
	game.setup(players(), seed_value)
	return game


## Partida completa entre IAs; devuelve sus jugadas como diccionarios.
func play_full_game() -> Array:
	var game := fresh_game()
	var ais := {}
	for p in game.players:
		ais[p.id] = _new_ai(p.id)
		if ais[p.id].has_method("observe"):
			ais[p.id].observe(game)
	var guard := 0
	while not game.finished and guard < 20000:
		guard += 1
		var actor: int = game.players_to_act()[0]
		var action: GameAction = ais[actor].choose_action(game)
		if action == null or game.submit(action) != "":
			push_error("La IA se ha atascado")
			break
	print("Partida de %d jugadas; gana %s" % [game.history.size(), game.winner_ids])
	return game.history.map(func(a: GameAction) -> Dictionary: return a.to_dict())


## Primer número de jugadas n >= from tras el que se cumple `test(game, n)`
## (-1 si no ocurre nunca).
func find(test: Callable, from: int = 0) -> int:
	var game := fresh_game()
	for n in range(0, _history.size() + 1):
		if n > 0:
			game.submit(GameAction.from_dict(_history[n - 1]))
		if n >= from and test.call(game, n):
			return n
	return -1


## Tipo de la jugada número n (la última aplicada al llegar a n jugadas).
func action_type(n: int) -> StringName:
	return StringName(_history[n - 1]["type"]) if n > 0 else &""


# --- Pantalla ------------------------------------------------------------------

## Abre la pantalla del juego con las primeras `n` jugadas. Las últimas
## `live` se juegan con la pantalla ya abierta, para que salgan en el registro.
func load_state(n: int, live: int = 6, settings := {}) -> void:
	if _screen != null:
		_screen.queue_free()
		await get_tree().process_frame
	for key in settings:
		App.set_setting(key, settings[key])
	App.session = {
		"game_id": game_id,
		"players": players(),
		"seed": seed_value,
		"history": _history.slice(0, n - mini(live, n)),
		"options": options.duplicate(),
	}
	_screen = _screen_scene().instantiate()
	add_child(_screen)
	await get_tree().process_frame
	_screen._log.clear()
	_screen._log_label.clear()
	for i in range(n - mini(live, n), n):
		_screen.game.submit(GameAction.from_dict(_history[i]))
	# El ratón, fuera del tablero (si no, sale la información de la casilla).
	get_viewport().warp_mouse(Vector2(4, 896))
	await settle(2.6)


func settle(seconds: float = 1.8) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Captura: ", path)
