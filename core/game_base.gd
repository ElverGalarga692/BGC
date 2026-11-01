class_name GameBase
extends RefCounted
## Clase base de la lógica de cualquier juego de la colección.
##
## La lógica no conoce nodos ni escenas: guarda el estado, valida y aplica
## acciones (GameAction). La interfaz solo dibuja el estado y envía acciones,
## lo que permite reutilizar la lógica para la IA, los tests y el guardado.
##
## Para crear un juego nuevo, hereda de esta clase e implementa:
##   _on_setup(), validate(), _apply() y get_legal_actions().

signal action_applied(action: GameAction)
signal game_finished(winner_ids: Array[int])

var players: Array[PlayerInfo] = []
var rng: BGCRng
var turns: TurnManager
var history: Array[GameAction] = []
var finished := false
var winner_ids: Array[int] = []


## Prepara una partida nueva. Con la misma semilla y las mismas acciones,
## la partida es siempre idéntica.
func setup(p_players: Array[PlayerInfo], p_seed: int) -> void:
	assert(not p_players.is_empty(), "Se necesita al menos un jugador")
	players = p_players
	rng = BGCRng.new(p_seed)
	turns = TurnManager.new(players.size())
	history.clear()
	finished = false
	winner_ids.clear()
	_on_setup()


func current_player() -> PlayerInfo:
	return players[turns.current]


## Valida y aplica una acción. Devuelve "" si se aplicó, o el motivo del
## rechazo en caso contrario.
func submit(action: GameAction) -> String:
	if finished:
		return "La partida ha terminado"
	var error := validate(action)
	if error != "":
		return error
	_apply(action)
	history.append(action)
	action_applied.emit(action)
	return ""


## Marca la partida como terminada.
func finish(p_winner_ids: Array[int]) -> void:
	finished = true
	winner_ids = p_winner_ids
	game_finished.emit(winner_ids)


# --- Métodos a implementar por cada juego ---------------------------------

## Se llama al final de setup(); aquí se crea el estado inicial del juego.
func _on_setup() -> void:
	pass


## Devuelve "" si la acción es legal en el estado actual, o el motivo si no.
func validate(action: GameAction) -> String:
	return "Acción no soportada: %s" % action.type


## Aplica una acción ya validada.
func _apply(_action: GameAction) -> void:
	pass


## Acciones legales para un jugador (útil para la IA y para la interfaz).
func get_legal_actions(_player_id: int) -> Array[GameAction]:
	return []
