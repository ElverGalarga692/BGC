class_name DiceView
extends Control
## Dos (o más) dados dibujados con sus puntos, con animación de tirada.
## roll(valores) los hace girar un momento y emite `finished` al pararse.

signal finished

const FACE := Color("f7f1e3")
const PIP := Color("2b2b2b")
const BORDER := Color("1b1b1b")
const ROLL_TIME := 0.6
const PIP_LAYOUT := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}

var values: Array[int] = []
var _shown: Array[int] = []
var _angles: Array[float] = []
var _rolling := 0.0
var _flip_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(100, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


## Muestra unos valores sin animación ([] = sin dados).
func show_values(p_values: Array) -> void:
	values.assign(p_values)
	_shown.assign(p_values)
	_angles.assign(p_values.map(func(_v: int) -> float: return 0.0))
	_rolling = 0.0
	queue_redraw()


## Anima una tirada que termina en `p_values`.
func roll(p_values: Array) -> void:
	values.assign(p_values)
	_shown.assign(p_values.map(func(_v: int) -> int: return _rng.randi_range(1, 6)))
	_angles.assign(p_values.map(func(_v: int) -> float: return _rng.randf_range(-0.5, 0.5)))
	_rolling = ROLL_TIME
	_flip_timer = 0.0
	queue_redraw()


func is_rolling() -> bool:
	return _rolling > 0.0


func _process(delta: float) -> void:
	if _rolling <= 0.0:
		return
	_rolling -= delta
	_flip_timer -= delta
	if _rolling <= 0.0:
		_shown.assign(values)
		_angles.assign(values.map(func(_v: int) -> float: return 0.0))
		queue_redraw()
		finished.emit()
		return
	if _flip_timer <= 0.0:
		_flip_timer = 0.06
		for i in _shown.size():
			_shown[i] = _rng.randi_range(1, 6)
			_angles[i] = _rng.randf_range(-0.6, 0.6) * (_rolling / ROLL_TIME)
		queue_redraw()


func _draw() -> void:
	var n := _shown.size()
	if n == 0:
		return
	var side := minf(size.y - 4.0, (size.x - 8.0 * (n - 1)) / n)
	var total := side * n + 8.0 * (n - 1)
	var x0 := (size.x - total) / 2.0
	for i in n:
		var center := Vector2(x0 + side / 2.0 + i * (side + 8.0), size.y / 2.0)
		if _rolling > 0.0:
			center.y -= absf(sin(_rolling * 25.0 + i)) * 4.0
		draw_set_transform(center, _angles[i])
		var rect := Rect2(Vector2(-side, -side) / 2.0, Vector2(side, side))
		draw_rect(rect.grow(1.5), BORDER)
		draw_rect(rect, FACE)
		for p in PIP_LAYOUT[_shown[i]]:
			draw_circle(p * side * 0.27, side * 0.09, PIP)
	draw_set_transform(Vector2.ZERO)
