class_name PuertoDistrictView
extends Control
## Dibuja el barrio de un jugador: 19 casillas hexagonales con la Lonja en
## el centro. Las casillas resaltadas (`targets`) se pueden pulsar.
##
## Contrato con la pantalla: `district` (Array de PuertoDefs.CELLS),
## `targets` (casillas pulsables), `selected` (casilla marcada) y la señal
## `cell_clicked(cell)`.

signal cell_clicked(cell: int)

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")

var district: Array = []
var targets: Array[int] = []
var selected := -1
## Color del jugador (borde del barrio).
var owner_color := Color.WHITE
## Casillas recién construidas (se iluminan un momento).
var flash := {}
var _hover := -1
var _hex := 20.0
var _origin := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(120, 110)


func set_district(p_district: Array, p_targets: Array[int] = [], p_selected: int = -1) -> void:
	district = p_district
	targets = p_targets
	selected = p_selected
	queue_redraw()


func pulse(cell: int) -> void:
	flash[cell] = 1.0
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		flash[cell] = v
		queue_redraw(), 1.0, 0.0, 0.9)
	tween.tween_callback(func() -> void: flash.erase(cell))


func _layout() -> void:
	# El barrio mide 5 hexágonos de ancho (radio 2) y ~4,3 de alto.
	var w := size.x / 9.4
	var h := size.y / 9.4
	_hex = maxf(4.0, minf(w, h))
	_origin = size / 2.0


func cell_center(cell: int) -> Vector2:
	return _origin + HexCoords.to_pixel(D.CELLS[cell], _hex)


func _draw() -> void:
	_layout()
	if district.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(_hex * 0.42, 7, 15))
	var detailed := _hex >= 14.0
	# Suelo: arena dentro y mar alrededor.
	draw_circle(_origin, _hex * 4.6, Color("1d4a5c"))
	draw_arc(_origin, _hex * 4.6, 0, TAU, 64, Color(owner_color, 0.55), 2.0, true)
	draw_circle(_origin, _hex * 4.25, Color("3a3428"))
	# Casillas.
	for cell in district.size():
		var c := cell_center(cell)
		var points := HexCoords.corners(c, _hex * 0.95)
		var content: int = district[cell]
		var fill := Color(1, 1, 1, 0.05)
		if content == D.LONJA:
			fill = PuertoArt.LONJA
		elif content >= 0:
			fill = PuertoArt.guild_color(D.guild_of(content)).darkened(0.45)
		if cell in targets:
			fill = fill.lerp(Color("ffd166"), 0.35) if content != D.EMPTY else Color(1, 0.82, 0.4, 0.22 + (0.2 if cell == _hover else 0.0))
		draw_colored_polygon(points, fill)
	# Grupos: trazos entre vecinos del mismo grupo.
	for g in D.groups(district):
		var color: Color = PuertoArt.guild_color(g["guild"]).lightened(0.2)
		var cells: Array = g["cells"]
		for a in cells:
			for b in D.cell_neighbors(a):
				if b > a and b in cells:
					draw_line(cell_center(a), cell_center(b), Color(color, 0.85), maxf(2.0, _hex * 0.22), true)
	for cell in district.size():
		var c := cell_center(cell)
		var points := HexCoords.corners(c, _hex * 0.95)
		var content: int = district[cell]
		var border := Color(1, 1, 1, 0.16)
		var width := 1.0
		if content >= 0:
			border = PuertoArt.guild_color(D.guild_of(content)).lightened(0.25)
			width = 1.5
		if cell == selected:
			border = Color("ffd166")
			width = 3.0
		elif cell in targets:
			border = Color("ffd166") if cell == _hover else Color(1, 0.82, 0.4, 0.7)
			width = 2.0
		draw_polyline(points + PackedVector2Array([points[0]]), border, width, true)
		if flash.has(cell):
			draw_colored_polygon(points, Color(1, 1, 0.8, 0.6 * flash[cell]))
		if content == D.LONJA:
			if detailed:
				PuertoArt.house(self, Rect2(c + Vector2(-_hex * 0.45, -_hex * 0.05), Vector2(_hex * 0.9, _hex * 0.45)), Color("8a6f45"), Color("5c4528"), 0, 3, true)
				draw_string(font, c + Vector2(-_hex, _hex * 0.75), "Lonja", HORIZONTAL_ALIGNMENT_CENTER, _hex * 2.0, int(font_size * 0.8), PuertoArt.PAPER)
			else:
				draw_circle(c, _hex * 0.3, Color("8a6f45"))
		elif content >= 0:
			var guild := D.guild_of(content)
			var color := PuertoArt.guild_color(guild)
			if detailed:
				var art := Rect2(c - Vector2(_hex * 0.55, _hex * 0.62), Vector2(_hex * 1.1, _hex * 1.05))
				if D.is_wonder(content):
					PuertoArt.wonder_icon(self, art, content)
				else:
					PuertoArt.building_icon(self, art, guild, color, D.cost_of(content))
				PuertoArt.coin(self, c + Vector2(_hex * 0.48, _hex * 0.45), _hex * 0.24, D.cost_of(content))
			else:
				draw_circle(c, _hex * 0.5, color)
				if D.is_wonder(content):
					PuertoArt.star(self, c, _hex * 0.35, Color("ffd166"))


func _cell_at(pos: Vector2) -> int:
	_layout()
	var h := HexCoords.from_pixel(pos - _origin, _hex)
	return D.cell_index(h)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != _hover:
			_hover = cell
			tooltip_text = _tooltip(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if cell >= 0 and cell in targets:
			accept_event()
			cell_clicked.emit(cell)


func _tooltip(cell: int) -> String:
	if cell < 0 or district.is_empty():
		return ""
	var content: int = district[cell]
	if content == D.LONJA:
		return "La Lonja: construye al lado"
	if content < 0:
		return ""
	var extra := PuertoArt.card_text(content)
	return "%s (%s, %d)%s" % [D.card_name(content), D.GUILD_NAMES[D.guild_of(content)], D.cost_of(content), ("\n" + extra) if extra != "" else ""]


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()
