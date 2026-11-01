class_name BGCRng
extends RefCounted
## Generador aleatorio con semilla. Todo el azar de un juego (dados, barajar,
## generar tableros) debe pasar por aquí para que las partidas sean
## reproducibles (depuración, repeticiones, guardado).

var seed_value: int
var _rng := RandomNumberGenerator.new()


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


## Devuelve una semilla aleatoria nueva (no determinista).
static func random_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


## Tira un dado de `sides` caras.
func roll(sides: int = 6) -> int:
	return _rng.randi_range(1, sides)


## Tira `count` dados y devuelve cada resultado.
func roll_dice(count: int, sides: int = 6) -> Array[int]:
	var result: Array[int] = []
	for i in count:
		result.append(roll(sides))
	return result


## Baraja `array` en el sitio (Fisher-Yates), de forma determinista.
func shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


## Elige un elemento al azar (null si el array está vacío).
func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[_rng.randi_range(0, array.size() - 1)]


## Estado interno, para guardar/cargar partidas a mitad.
func get_state() -> int:
	return _rng.state


func set_state(state: int) -> void:
	_rng.state = state
