extends Node
## Autoload "App": navegación entre pantallas y datos de la sesión actual
## (qué juego se juega, con qué jugadores y qué semilla).

const MAIN_MENU := "res://main.tscn"
const SETTINGS_PATH := "user://settings.cfg"

## Configuración de la partida en curso:
## {"game_id": String, "players": Array[PlayerInfo], "seed": int}
var session: Dictionary = {}


var _settings := ConfigFile.new()


func _ready() -> void:
	_settings.load(SETTINGS_PATH)  # si no existe, se usan los valores por defecto


## Ajustes del usuario que se guardan entre sesiones (p. ej. vista 2D/3D).
func get_setting(key: String, default: Variant) -> Variant:
	return _settings.get_value("general", key, default)


func set_setting(key: String, value: Variant) -> void:
	_settings.set_value("general", key, value)
	_settings.save(SETTINGS_PATH)


func start_game(game_id: String, players: Array[PlayerInfo], seed: int = -1) -> void:
	var game := GameRegistry.find(game_id)
	assert(not game.is_empty(), "Juego desconocido: %s" % game_id)
	session = {
		"game_id": game_id,
		"players": players,
		"seed": BGCRng.random_seed() if seed < 0 else seed,
	}
	get_tree().change_scene_to_file(game["scene"])


func go_to_menu() -> void:
	session = {}
	get_tree().change_scene_to_file(MAIN_MENU)


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
