class_name MenuBackground
extends Control
## Fondo animado del menú: degradado de mar profundo con hexágonos de colores
## que flotan despacio en tres capas de profundidad, y viñeta en los bordes.

const LAYERS := [
	# [cantidad, tamaño mínimo, tamaño máximo, velocidad, opacidad]
	[16, 18.0, 34.0, 8.0, 0.10],
	[11, 36.0, 60.0, 14.0, 0.16],
	[6, 70.0, 110.0, 22.0, 0.22],
]

var _hexes: Array = []  # [pos, size, speed, rot, rot_speed, color, alpha, phase]
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 2024
	resized.connect(_spawn)
	_spawn()


func _spawn() -> void:
	_hexes.clear()
	var area := size if size.x > 0 else Vector2(1280, 720)
	for layer in LAYERS:
		for i in layer[0]:
			_hexes.append([
				Vector2(_rng.randf() * area.x, _rng.randf() * area.y),
				_rng.randf_range(layer[1], layer[2]),
				layer[3] * _rng.randf_range(0.7, 1.3),
				_rng.randf() * TAU,
				_rng.randf_range(-0.15, 0.15),
				BGCTheme.PALETTE[_rng.randi() % BGCTheme.PALETTE.size()],
				layer[4],
				_rng.randf() * TAU,
			])


func _process(delta: float) -> void:
	_time += delta
	var drift := Vector2(0.35, -1.0).normalized()
	for h in _hexes:
		h[0] += drift * h[2] * delta
		h[3] += h[4] * delta
		var margin: float = h[1] * 2.0
		if h[0].y < -margin:
			h[0].y = size.y + margin
			h[0].x = _rng.randf() * size.x
		if h[0].x > size.x + margin:
			h[0].x = -margin
	queue_redraw()


func _draw() -> void:
	# Degradado vertical.
	var top := BGCTheme.BG_LIGHT.darkened(0.25)
	var bottom := BGCTheme.BG_DEEP
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	# Resplandor suave detrás del título.
	var glow_center := Vector2(size.x / 2.0, size.y * 0.22)
	for i in 6:
		var r := size.y * (0.16 + i * 0.07)
		draw_circle(glow_center, r, Color(BGCTheme.BG_LIGHT, 0.05))
	# Hexágonos flotantes.
	for h in _hexes:
		var pulse := 0.75 + 0.25 * sin(_time * 0.8 + h[7])
		var color: Color = h[5]
		var points := PackedVector2Array()
		for k in 6:
			points.append(h[0] + Vector2.from_angle(h[3] + k * TAU / 6.0) * h[1])
		draw_colored_polygon(points, Color(color, h[6] * pulse))
		points.append(points[0])
		draw_polyline(points, Color(color.lightened(0.4), h[6] * 1.4 * pulse), 1.5, true)
	# Viñeta.
	var edge := Color(0, 0, 0, 0.45)
	var clear := Color(0, 0, 0, 0)
	var band := size.x * 0.18
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(band, 0), Vector2(band, size.y), Vector2(0, size.y)]),
		PackedColorArray([edge, clear, clear, edge]))
	draw_polygon(PackedVector2Array([Vector2(size.x - band, 0), Vector2(size.x, 0), size, Vector2(size.x - band, size.y)]),
		PackedColorArray([clear, edge, edge, clear]))
