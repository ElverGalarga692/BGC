class_name BajamarArt
extends RefCounted
## Cartas de Bajamar dibujadas por código (sin imágenes): peces de cada
## especie, tormenta, cartas especiales y reverso. BajamarCard es el control
## que las muestra, con animación de volteo.

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")

const PAPER := Color("f3ead6")
const INK := Color("1d2b3a")
const SEA := Color("143a5c")
const SEA_DARK := Color("0b2338")
const FOAM := Color("cfe6f2")
const STORM_BG := Color("2c3140")
const BOLT := Color("ffd166")


static func _font() -> Font:
	return ThemeDB.fallback_font


static func _rounded(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, radius: float, width: float = 2.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(width))
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	ci.draw_style_box(box, rect)


static func _text(ci: CanvasItem, pos: Vector2, width: float, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_string(_font(), pos, text, align, width, font_size, color)


## Dibuja una carta cualquiera en `rect`.
static func draw_card(ci: CanvasItem, rect: Rect2, card: int) -> void:
	if D.is_fish(card):
		draw_fish_card(ci, rect, D.species_of(card), D.value_of(card))
	elif D.is_storm(card):
		draw_storm(ci, rect)
	elif card == D.GULL:
		_special(ci, rect, Color("e9eef2"), Color("5a6b7a"), "GAVIOTA", _draw_gull)
	elif card == D.SHIELD:
		_special(ci, rect, Color("d8c39a"), Color("6b5330"), "RED", _draw_shield)
	elif card == D.HIGH_TIDE:
		_special(ci, rect, Color("9fd0e8"), Color("1f5f86"), "MAREA", _draw_tide)
	else:
		draw_back(ci, rect)


static func draw_fish_card(ci: CanvasItem, rect: Rect2, species: int, value: int) -> void:
	var color: Color = D.SPECIES_COLORS[species]
	var radius := rect.size.x * 0.12
	_rounded(ci, rect, color.darkened(0.25), color.lightened(0.35), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.07)
	_rounded(ci, inner, PAPER, color.darkened(0.1), radius * 0.6, 1)
	var small := int(clampf(rect.size.x * 0.24, 9, 22))
	_text(ci, inner.position + Vector2(inner.size.x * 0.08, small + 1), inner.size.x, str(value), small, color.darkened(0.45), HORIZONTAL_ALIGNMENT_LEFT)
	var fish_rect := Rect2(inner.position + Vector2(inner.size.x * 0.1, inner.size.y * 0.32), Vector2(inner.size.x * 0.8, inner.size.y * 0.36))
	draw_fish(ci, fish_rect, species, color)
	if rect.size.x >= 52:
		var name_size := int(clampf(rect.size.x * 0.15, 8, 13))
		_text(ci, Vector2(inner.position.x, inner.end.y - inner.size.y * 0.07), inner.size.x, D.SPECIES_NAMES[species], name_size, color.darkened(0.5))
	else:
		# Valor repetido abajo a la derecha, como en las cartas de verdad.
		_text(ci, Vector2(inner.position.x, inner.end.y - 3), inner.size.x * 0.92, str(value), small - 2, color.darkened(0.45), HORIZONTAL_ALIGNMENT_RIGHT)


## Silueta sencilla de cada especie dentro de `r`.
static func draw_fish(ci: CanvasItem, r: Rect2, species: int, color: Color) -> void:
	var c := r.get_center()
	var body := color
	var dark := color.darkened(0.45)
	match species:
		D.Species.OCTOPUS:
			var head_r := r.size.y * 0.42
			var head := c + Vector2(0, -r.size.y * 0.12)
			for i in 6:
				var x := lerpf(r.position.x + r.size.x * 0.2, r.end.x - r.size.x * 0.2, i / 5.0)
				var pts := PackedVector2Array([Vector2(x, head.y), Vector2(x + r.size.x * 0.05 * (1 if i % 2 == 0 else -1), r.end.y), Vector2(x + r.size.x * 0.06, head.y)])
				ci.draw_colored_polygon(pts, body.darkened(0.15))
			ci.draw_circle(head, head_r, body)
			ci.draw_circle(head + Vector2(-head_r * 0.35, -head_r * 0.1), head_r * 0.14, PAPER)
			ci.draw_circle(head + Vector2(head_r * 0.35, -head_r * 0.1), head_r * 0.14, PAPER)
			ci.draw_circle(head + Vector2(-head_r * 0.35, -head_r * 0.05), head_r * 0.07, dark)
			ci.draw_circle(head + Vector2(head_r * 0.35, -head_r * 0.05), head_r * 0.07, dark)
			return
	# Peces: cuerpo ovalado más o menos alargado y cola.
	var length: float = {D.Species.SARDINE: 0.78, D.Species.MACKEREL: 0.86, D.Species.HAKE: 0.9, D.Species.TUNA: 0.8}[species]
	var height: float = {D.Species.SARDINE: 0.42, D.Species.MACKEREL: 0.5, D.Species.HAKE: 0.55, D.Species.TUNA: 0.8}[species]
	var half := Vector2(r.size.x * length * 0.42, r.size.y * height * 0.5)
	var center := c + Vector2(-r.size.x * 0.06, 0)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * half.x, sin(a) * half.y))
	var tail_x := center.x + half.x * 0.85
	var tail := PackedVector2Array([Vector2(tail_x, center.y), Vector2(r.end.x, center.y - half.y * 1.1), Vector2(r.end.x - r.size.x * 0.04, center.y), Vector2(r.end.x, center.y + half.y * 1.1)])
	ci.draw_colored_polygon(tail, body.darkened(0.15))
	ci.draw_colored_polygon(pts, body)
	if species == D.Species.MACKEREL:
		for i in 3:
			var x := center.x - half.x * 0.3 + i * half.x * 0.35
			ci.draw_line(Vector2(x, center.y - half.y * 0.8), Vector2(x + half.x * 0.15, center.y - half.y * 0.1), dark, 1.5)
	if species == D.Species.TUNA:
		ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-half.x * 0.1, -half.y * 0.9), center + Vector2(half.x * 0.3, -half.y * 1.5), center + Vector2(half.x * 0.35, -half.y * 0.7)]), body.darkened(0.2))
	var eye := center + Vector2(-half.x * 0.6, -half.y * 0.15)
	ci.draw_circle(eye, maxf(1.5, half.y * 0.18), PAPER)
	ci.draw_circle(eye, maxf(0.8, half.y * 0.09), dark)


static func draw_storm(ci: CanvasItem, rect: Rect2) -> void:
	var radius := rect.size.x * 0.12
	_rounded(ci, rect, STORM_BG, Color("6c7a91"), radius, 2)
	var c := rect.get_center()
	var w := rect.size.x
	# Nube.
	for p in [Vector2(-0.18, -0.12), Vector2(0.05, -0.2), Vector2(0.22, -0.1), Vector2(0.0, -0.06)]:
		ci.draw_circle(c + Vector2(p.x * w, p.y * w), w * 0.17, Color("8e9bb0"))
	# Rayo.
	var bolt := PackedVector2Array([
		c + Vector2(0.02, -0.02) * w, c + Vector2(-0.12, 0.28) * w, c + Vector2(0.0, 0.25) * w,
		c + Vector2(-0.08, 0.5) * w, c + Vector2(0.14, 0.16) * w, c + Vector2(0.02, 0.19) * w, c + Vector2(0.1, -0.02) * w])
	ci.draw_colored_polygon(bolt, BOLT)
	if rect.size.x >= 52:
		_text(ci, Vector2(rect.position.x, rect.end.y - rect.size.y * 0.07), rect.size.x, "TORMENTA", int(clampf(rect.size.x * 0.13, 8, 12)), FOAM)


static func _special(ci: CanvasItem, rect: Rect2, fill: Color, ink: Color, label: String, art: Callable) -> void:
	var radius := rect.size.x * 0.12
	_rounded(ci, rect, ink.darkened(0.2), ink.lightened(0.3), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.07)
	_rounded(ci, inner, fill, ink, radius * 0.6, 1)
	var art_rect := Rect2(inner.position + inner.size * Vector2(0.12, 0.14), inner.size * Vector2(0.76, 0.56))
	art.call(ci, art_rect, ink)
	if rect.size.x >= 52:
		_text(ci, Vector2(inner.position.x, inner.end.y - inner.size.y * 0.08), inner.size.x, label, int(clampf(rect.size.x * 0.14, 8, 12)), ink)
	else:
		ci.draw_circle(inner.position + Vector2(inner.size.x * 0.18, inner.size.y * 0.12), maxf(2.0, inner.size.x * 0.07), ink)


static func _draw_gull(ci: CanvasItem, r: Rect2, ink: Color) -> void:
	var c := r.get_center()
	var w := r.size.x * 0.5
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		var x := lerpf(-w, w, t)
		var y := -absf(sin(t * PI * 2.0)) * w * 0.35 + absf(x) * 0.15
		pts.append(c + Vector2(x, y))
	ci.draw_polyline(pts, ink, maxf(2.0, r.size.x * 0.06), true)
	ci.draw_circle(c + Vector2(0, w * 0.05), maxf(2.0, r.size.x * 0.06), ink)


static func _draw_shield(ci: CanvasItem, r: Rect2, ink: Color) -> void:
	# Red: rombos.
	var step := r.size.x / 4.0
	var width := maxf(1.2, r.size.x * 0.03)
	for i in 5:
		var x := r.position.x + i * step
		ci.draw_line(Vector2(x, r.position.y), Vector2(x + r.size.y * 0.5, r.end.y), ink, width, true)
		ci.draw_line(Vector2(x, r.position.y), Vector2(x - r.size.y * 0.5, r.end.y), ink, width, true)
	ci.draw_rect(r, ink, false, width * 1.5)


static func _draw_tide(ci: CanvasItem, r: Rect2, ink: Color) -> void:
	for row in 3:
		var pts := PackedVector2Array()
		var y0 := r.position.y + r.size.y * (0.25 + row * 0.27)
		for i in 17:
			var t := i / 16.0
			pts.append(Vector2(r.position.x + t * r.size.x, y0 + sin(t * TAU * 1.5 + row) * r.size.y * 0.09))
		ci.draw_polyline(pts, ink, maxf(1.5, r.size.x * 0.05), true)


## Reverso: mar con olas y el nombre del juego.
static func draw_back(ci: CanvasItem, rect: Rect2) -> void:
	var radius := rect.size.x * 0.12
	_rounded(ci, rect, SEA_DARK, Color("3f6f99"), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.09)
	_rounded(ci, inner, SEA, Color(FOAM, 0.35), radius * 0.6, 1)
	for row in 4:
		var pts := PackedVector2Array()
		var y0 := inner.position.y + inner.size.y * (0.2 + row * 0.2)
		for i in 13:
			var t := i / 12.0
			pts.append(Vector2(inner.position.x + t * inner.size.x, y0 + sin(t * TAU * 1.5 + row * 1.3) * inner.size.y * 0.035))
		ci.draw_polyline(pts, Color(FOAM, 0.35), maxf(1.0, rect.size.x * 0.025), true)


## Una carta en pantalla. `card` = -1 es el reverso. Puede ser pulsable
## (resalta al pasar el ratón) y animarse al aparecer (volteo).
class BajamarCard extends Control:
	signal pressed

	var card := -1
	var clickable := false:
		set(value):
			clickable = value
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW
			queue_redraw()
	var dimmed := false
	var _hover := false
	## 0..1: cuánto se ve la cara (para el volteo, que encoge en horizontal).
	var _flip := 1.0

	func _init(p_card: int = -1, p_size: Vector2 = Vector2(64, 90)) -> void:
		card = p_card
		custom_minimum_size = p_size
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())

	## Animación al aparecer: se voltea desde el reverso.
	func flip_in(delay: float = 0.0) -> void:
		_flip = -1.0
		var tween := create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_method(func(v: float) -> void:
			_flip = v
			queue_redraw(), -1.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)

	func _gui_input(event: InputEvent) -> void:
		if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if clickable and _hover:
			rect.position.y -= 4
			BajamarArt._rounded(self, rect.grow(3), Color(BajamarArt.BOLT, 0.55), Color.TRANSPARENT, size.x * 0.14, 0)
		var w := absf(_flip)
		var face := Rect2(rect.position + Vector2(rect.size.x * (1.0 - w) * 0.5, 0), Vector2(maxf(1.0, rect.size.x * w), rect.size.y))
		if _flip < 0.0:
			# Primera mitad del volteo: reverso, sin encoger el dibujo interior.
			draw_set_transform(face.position, 0, Vector2(w, 1))
			BajamarArt.draw_back(self, Rect2(Vector2.ZERO, rect.size))
		else:
			draw_set_transform(face.position, 0, Vector2(maxf(w, 0.01), 1))
			BajamarArt.draw_card(self, Rect2(Vector2.ZERO, rect.size), card)
		draw_set_transform(Vector2.ZERO)
		if dimmed:
			BajamarArt._rounded(self, rect, Color(0, 0, 0, 0.45), Color.TRANSPARENT, size.x * 0.12, 0)
