extends Node
## Autoload "App": navegación entre pantallas y datos de la sesión actual
## (qué juego se juega, con qué jugadores y qué semilla).

const MAIN_MENU := "res://main.tscn"
const SETTINGS_PATH := "user://settings.cfg"

## Configuración de la partida en curso:
## {"game_id": String, "players": Array[PlayerInfo], "seed": int}
var session: Dictionary = {}
## Aviso pendiente de mostrar en el menú principal.
var menu_notice := ""


var _settings := ConfigFile.new()


func _ready() -> void:
	_settings.load(SETTINGS_PATH)  # si no existe, se usan los valores por defecto
	if get_setting("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Ajustes del usuario que se guardan entre sesiones (p. ej. vista 2D/3D).
func get_setting(key: String, default: Variant) -> Variant:
	return _settings.get_value("general", key, default)


func set_setting(key: String, value: Variant) -> void:
	_settings.set_value("general", key, value)
	_settings.save(SETTINGS_PATH)


# --- Partidas guardadas -------------------------------------------------------

func _save_path(game_id: String) -> String:
	return "user://saves/%s.save" % game_id


func save_game(game_id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var file := FileAccess.open(_save_path(game_id), FileAccess.WRITE)
	if file != null:
		file.store_var(data)


func has_save(game_id: String) -> bool:
	return FileAccess.file_exists(_save_path(game_id))


func load_save(game_id: String) -> Dictionary:
	var file := FileAccess.open(_save_path(game_id), FileAccess.READ)
	if file == null:
		return {}
	var data = file.get_var()
	return data if data is Dictionary else {}


func delete_save(game_id: String) -> void:
	if has_save(game_id):
		DirAccess.remove_absolute(_save_path(game_id))


# --- Opciones de cada juego -------------------------------------------------------

## Opciones elegidas para un juego (las de GameRegistry con sus valores por
## defecto, cambiadas por lo que el jugador eligió en el menú).
func game_options(game_id: String) -> Dictionary:
	var result := {}
	for option in GameRegistry.find(game_id).get("options", []):
		result[option["key"]] = option["default"]
	var saved: Dictionary = get_setting("options_" + game_id, {})
	for key in saved:
		if result.has(key):
			result[key] = saved[key]
	return result


func set_game_option(game_id: String, key: String, value: Variant) -> void:
	var saved: Dictionary = get_setting("options_" + game_id, {}).duplicate()
	saved[key] = value
	set_setting("options_" + game_id, saved)


## Continúa la partida guardada de un juego.
func continue_game(game_id: String) -> void:
	var data := load_save(game_id)
	if data.is_empty():
		return
	var game := GameRegistry.find(game_id)
	session = {
		"game_id": game_id,
		"players": GameBase.players_from_save(data),
		"seed": int(data["seed"]),
		"history": data.get("history", []),
		"options": data.get("options", game_options(game_id)),
	}
	get_tree().change_scene_to_file(game["scene"])


func start_game(game_id: String, players: Array[PlayerInfo], seed: int = -1) -> void:
	var game := GameRegistry.find(game_id)
	assert(not game.is_empty(), "Juego desconocido: %s" % game_id)
	session = {
		"game_id": game_id,
		"players": players,
		"seed": BGCRng.random_seed() if seed < 0 else seed,
		"options": game_options(game_id),
	}
	get_tree().change_scene_to_file(game["scene"])


## Vuelve al menú. Si se indica `notice`, el menú lo muestra (p. ej. "el
## anfitrión ha cerrado la partida"). Sale de la partida en red si la hay.
func go_to_menu(notice: String = "") -> void:
	session = {}
	menu_notice = notice
	var net := get_node_or_null("/root/Net")
	if net != null and net.active:
		net.leave()
	get_tree().change_scene_to_file(MAIN_MENU)


## Partida en red: `local_seat` es la plaza del jugador de este equipo.
func start_network_game(game_id: String, players: Array[PlayerInfo], seed: int, local_seat: int, options: Dictionary = {}) -> void:
	var game := GameRegistry.find(game_id)
	session = {
		"game_id": game_id,
		"players": players,
		"seed": seed,
		"network": true,
		"local_seat": local_seat,
		"options": options if not options.is_empty() else game_options(game_id),
	}
	get_tree().change_scene_to_file(game["scene"])


## Jugadores de la sesión, o unos por defecto si se abre la escena del juego
## directamente desde el editor (F6).
func session_players(default_count: int = 3) -> Array[PlayerInfo]:
	if session.has("players"):
		return session["players"]
	var players: Array[PlayerInfo] = []
	for i in default_count:
		players.append(PlayerInfo.new(i, "", PlayerInfo.default_color(i)))
	return players


func session_seed() -> int:
	return session.get("seed", BGCRng.random_seed())
