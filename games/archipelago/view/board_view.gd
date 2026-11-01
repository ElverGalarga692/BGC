class_name ArchBoardView
extends Node2D
## Dibuja un ArchBoard y detecta qué elemento (casilla, vértice o arista)
## hay bajo el ratón. No modifica el tablero: solo emite señales.

enum Pick { NONE, TILE, VERTEX, EDGE }

signal hovered(kind: Pick, id: int)
signal clicked(kind: Pick, id: int)

const SEA_COLOR := Color("2a6f97")
const SEA_EDGE_COLOR := Color("1d4e6b")
const OUTLINE_COLOR := Color("f4ecd8")
const TOKEN_COLOR := Color("f6edd6")
const TOKEN_TEXT := Color("2b2b2b")
const HOT_TEXT := Color("c0392b")
const HOVER_COLOR := Color(1, 1, 1, 0.85)
const SELECT_COLOR := Color("ffd166")
const RESOURCE_COLORS := {
	ArchDefs.ResourceType.WOOD: Color("2f7a3b"),
	ArchDefs.ResourceType.BRICK: Color("c4623a"),
	ArchDefs.ResourceType.WOOL: Color("9ccc5a"),
	ArchDefs.ResourceType.GRAIN: Color("e8c33f"),
	ArchDefs.ResourceType.ORE: Color("8a8f99"),
}

## Radio del mar alrededor del tablero, en unidades de hexágono.
const SEA_RADIUS := 5.9
## Distancias de detección, en unidades de hexágono.
const VERTEX_PICK_RADIUS := 0.22
const EDGE_PICK_RADIUS := 0.24

var board: ArchBoard:
	set(value):
		board = value
		_hover = [Pick.NONE, -1]
		_selected = [Pick.NONE, -1]
		queue_redraw()

## Radio de cada hexágono en píxeles.
var hex_size := 48.0:
	set(value):
		hex_size = value
		queue_redraw()

var _hover: Array = [Pick.NONE, -1]
var _selected: Array = [Pick.NONE, -1]


## Tamaño del tablero (con el mar) en unidades de hexágono, para encajarlo.
static func extent() -> Vector2:
	return Vector2(SEA_RADIUS * 2.0, SEA_RADIUS * HexCoords.SQRT3)


## Qué hay en un punto en coordenadas locales (píxeles).
func pick_at(local_point: Vector2) -> Array:
	if board == null:
		return [Pick.NONE, -1]
	var p := local_point / hex_size
	var v := board.grid.vertex_near(p, VERTEX_PICK_RADIUS)
	if v >= 0:
		return [Pick.VERTEX, v]
	var e := board.grid.edge_near(p, EDGE_PICK_RADIUS)
	if e >= 0:
		return [Pick.EDGE, e]
	var t := board.grid.tile_at(p)
	if t >= 0:
		return [Pick.TILE, t]
	return [Pick.NONE, -1]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pick := pick_at(get_local_mouse_position())
		if pick != _hover:
			_hover = pick
			hovered.emit(pick[0], pick[1])
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pick := pick_at(get_local_mouse_position())
		_selected = [Pick.NONE, -1] if pick == _selected else pick
		clicked.emit(pick[0], pick[1])
		queue_redraw()


func _draw() -> void:
	if board == null:
		return
	_draw_sea()
	for port in board.ports:
		_draw_port(port)
	for t in board.grid.tile_count():
		_draw_tile(t)
	_draw_highlight(_hover, HOVER_COLOR)
	_draw_highlight(_selected, SELECT_COLOR)


func _draw_sea() -> void:
	var points := PackedVector2Array()
	for i in 6:
		points.append(Vector2.from_angle(deg_to_rad(60.0 * i)) * SEA_RADIUS * hex_size)
	draw_colored_polygon(points, SEA_COLOR)
	points.append(points[0])
	draw_polyline(points, SEA_EDGE_COLOR, hex_size * 0.12, true)


func _draw_tile(t: int) -> void:
	var center := board.grid.tile_center(t) * hex_size
	var corners := HexCoords.corners(center, hex_size)
	draw_colored_polygon(corners, ArchDefs.TERRAIN_COLORS[board.tile_terrain[t]])
	corners.append(corners[0])
	draw_polyline(corners, OUTLINE_COLOR, maxf(2.0, hex_size * 0.05), true)

	var number := board.tile_number[t]
	if number > 0:
		var radius := hex_size * 0.34
		draw_circle(center, radius, TOKEN_COLOR)
		var hot := number in ArchDefs.HOT_NUMBERS
		var color := HOT_TEXT if hot else TOKEN_TEXT
		_draw_text(str(number), center + Vector2(0, -hex_size * 0.04), int(hex_size * 0.36), color)
		var pips := ArchDefs.number_pips(number)
		var dot := hex_size * 0.035
		var spacing := dot * 2.6
		for i in pips:
			var x := (i - (pips - 1) / 2.0) * spacing
			draw_circle(center + Vector2(x, hex_size * 0.2), dot, color)
	if t == board.bandit_tile:
		_draw_bandit(center + Vector2(0, -hex_size * 0.55) if number > 0 else center)


func _draw_bandit(at: Vector2) -> void:
	var s := hex_size * 0.16
	draw_circle(at + Vector2(0, -s * 1.1), s * 0.6, Color("222222"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-s, s), at + Vector2(s, s), at + Vector2(0, -s * 0.8)]), Color("222222"))


func _draw_port(port: Dictionary) -> void:
	var e: int = port["edge"]
	var tile: int = board.grid.edge_tiles[e][0]
	var mid := board.grid.edge_midpoint(e)
	var outward := (mid - board.grid.tile_center(tile)).normalized()
	var pos := (mid + outward * 0.62) * hex_size
	var ev: Array = board.grid.edge_vertices[e]
	for v in ev:
		draw_line(pos, board.grid.vertex_positions[v] * hex_size, Color("d9c7a0"), hex_size * 0.08)
	var type: int = port["type"]
	var fill: Color = TOKEN_COLOR if type == ArchDefs.PORT_GENERIC else RESOURCE_COLORS[type]
	draw_circle(pos, hex_size * 0.27, Color("5b3a1e"))
	draw_circle(pos, hex_size * 0.23, fill)
	var text_color := TOKEN_TEXT if type == ArchDefs.PORT_GENERIC or type == ArchDefs.ResourceType.GRAIN else Color.WHITE
	_draw_text("%d:1" % ArchDefs.port_ratio(type), pos, int(hex_size * 0.2), text_color)


func _draw_highlight(pick: Array, color: Color) -> void:
	var id: int = pick[1]
	match pick[0]:
		Pick.TILE:
			var corners := HexCoords.corners(board.grid.tile_center(id) * hex_size, hex_size * 0.94)
			corners.append(corners[0])
			draw_polyline(corners, color, hex_size * 0.08, true)
		Pick.VERTEX:
			draw_circle(board.grid.vertex_positions[id] * hex_size, hex_size * 0.15, color)
		Pick.EDGE:
			var ev: Array = board.grid.edge_vertices[id]
			var a := board.grid.vertex_positions[ev[0]] * hex_size
			var b := board.grid.vertex_positions[ev[1]] * hex_size
			var shrink := (b - a) * 0.15
			draw_line(a + shrink, b - shrink, color, hex_size * 0.14, true)


## Texto centrado (horizontal y verticalmente) en `center`.
func _draw_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center + Vector2(-size.x / 2.0, font.get_ascent(font_size) - size.y / 2.0)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
