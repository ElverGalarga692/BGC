class_name TurnManager
extends RefCounted
## Gestiona de quién es el turno. Soporta el orden normal (0, 1, 2, ...) y
## secuencias especiales, como el orden "serpiente" de la colocación inicial
## (0, 1, 2, 2, 1, 0).

var player_count: int
var start_player: int
var current: int
## Número de ronda en el orden normal (empieza en 1).
var round_number: int = 1

var _sequence: Array[int] = []
var _sequence_index: int = -1
var _resume_at: int = 0


func _init(p_player_count: int = 2, p_start_player: int = 0) -> void:
	assert(p_player_count > 0)
	player_count = p_player_count
	start_player = p_start_player
	current = p_start_player


## Orden serpiente: ida y vuelta empezando por `start`.
static func snake_order(count: int, start: int = 0) -> Array[int]:
	var forward: Array[int] = []
	for i in count:
		forward.append((start + i) % count)
	var order: Array[int] = forward.duplicate()
	forward.reverse()
	order.append_array(forward)
	return order


## Inicia una secuencia especial de turnos. Al terminarla, el turno pasa a
## `resume_at` (por defecto, el jugador inicial) y se reanuda el orden normal
## desde la ronda 1.
func begin_sequence(order: Array[int], resume_at: int = -1) -> void:
	assert(not order.is_empty())
	_sequence = order.duplicate()
	_sequence_index = 0
	_resume_at = start_player if resume_at < 0 else resume_at
	current = _sequence[0]


func in_sequence() -> bool:
	return _sequence_index >= 0


## Avanza al siguiente jugador y lo devuelve.
func next() -> int:
	if in_sequence():
		_sequence_index += 1
		if _sequence_index < _sequence.size():
			current = _sequence[_sequence_index]
		else:
			_sequence_index = -1
			_sequence.clear()
			current = _resume_at
			round_number = 1
		return current
	current = (current + 1) % player_count
	if current == start_player:
		round_number += 1
	return current
