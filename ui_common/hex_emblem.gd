class_name HexEmblem
extends Control
## Ilustración de hexágonos (un hexágono central y un anillo de 6), con
## colores a elegir. Se usa como emblema del título y como ilustración de
## las tarjetas de juego. Puede girar despacio.

var colors: Array = BGCTheme.PALETTE
var spin_speed := 0.0
var outline := Color(1, 1, 1, 0.85)
var _angle := 0.0


func _init(p_colors: Array = [], p_size: float = 80.0, p_spin: float = 0.0) -> void:
	if not p_colors.is_empty():
		colors = p_colors
	custom_minimum_size = Vector2(p_size, p_size)
	spin_speed = p_spin
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if spin_speed != 0.0:
		_angle += spin_speed * delta
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var r := minf(size.x, size.y) / 6.2
	var spacing := r * 1.78
	_hex(center, r, colors[0])
	for i in 6:
		var a := _angle + i * TAU / 6.0
		_hex(center + Vector2.from_angle(a) * spacing, r, colors[(i + 1) % colors.size()])


func _hex(center: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for k in 6:
		points.append(center + Vector2.from_angle(_angle + PI / 6.0 + k * TAU / 6.0) * r)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, outline, maxf(1.5, r * 0.09), true)
