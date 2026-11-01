class_name ArchBoardView
extends Node2D
## Vista 2D del tablero: dibuja el tablero y las piezas, y detecta qué
## elemento (casilla, vértice o arista) hay bajo el ratón.
##
## Contrato con la pantalla (una futura vista 3D debe cumplir lo mismo):
##   - propiedad `game`: la partida que se dibuja (solo lectura),
##   - set_targets(kind, ids): resalta los sitios donde se puede jugar y
##     limita los clics a ellos (Pick.NONE para quitar),
##   - refresh(): vuelve a dibujar tras un cambio en la partida,
##   - fit(rect): encaja el tablero en un rectángulo de la pantalla,
##   - señales hovered(kind, id) y clicked(kind, id).
## La detección se hace en "unidades de hexágono" con HexGrid, así que una
## vista 3D solo tiene que proyectar el rayo del ratón sobre el plano.

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
const PIECE_OUTLINE := Color("1b1b1b")
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

var game: ArchipelagoGame:
	set(value):
		game = value
		board = game.board if game != null else null
		_hover = [Pick.NONE, -1]
		set_targets(Pick.NONE, [])

var board: ArchBoard

## Radio de cada hexágono en píxeles.
var hex_size := 48.0:
	set(value):
		hex_size = value
		queue_redraw()

var _hover: Array = [Pick.NONE, -1]
var _target_kind: Pick = Pick.NONE
var _target_ids: Array[int] = []
var _time := 0.0


## Tamaño del tablero (con el mar) en unidades de hexágono, para encajarlo.
static func extent() -> Vector2:
	return Vector2(SEA_RADIUS * 2.0, SEA_RADIUS * HexCoords.SQRT3)


func set_targets(kind: Pick, ids: Array) -> void:
	_target_kind = kind if not ids.is_empty() else Pick.NONE
	_target_ids.assign(ids)
	_hover = pick_at(get_local_mouse_position())
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func fit(rect: Rect2) -> void:
	var e := extent()
	hex_size = minf(rect.size.x / e.x, rect.size.y / e.y) * 0.96
	position = rect.get_center()


func _process(delta: float) -> void:
	if _target_kind != Pick.NONE:
		_time += delta
		queue_redraw()


## Qué hay en un punto en coordenadas locales (píxeles). Si hay objetivos
## marcados, solo devuelve uno de ellos.
func pick_at(local_point: Vector2) -> Array:
	if board == null:
		return [Pick.NONE, -1]
	return pick_unit(board, local_point / hex_size, _target_kind, _target_ids)


## Qué hay en el punto `p` (en unidades de hexágono). Si hay objetivos
## marcados, solo devuelve uno de ellos. La comparten la vista 2D y la 3D.
static func pick_unit(p_board: ArchBoard, p: Vector2, target_kind: Pick, target_ids: Array[int]) -> Array:
	var grid := p_board.grid
	if target_kind == Pick.TILE:
		var t := grid.tile_at(p)
		return [Pick.TILE, t] if t in target_ids else [Pick.NONE, -1]
	if target_kind != Pick.NONE:
		var best := -1
		var best_d := 0.5
		for id in target_ids:
			var pos := grid.vertex_positions[id] if target_kind == Pick.VERTEX else grid.edge_midpoint(id)
			var d := pos.distance_to(p)
			if d < best_d:
				best = id
				best_d = d
		return [target_kind, best] if best >= 0 else [Pick.NONE, -1]
	var v := grid.vertex_near(p, VERTEX_PICK_RADIUS)
	if v >= 0:
		return [Pick.VERTEX, v]
	var e := grid.edge_near(p, EDGE_PICK_RADIUS)
	if e >= 0:
		return [Pick.EDGE, e]
	var t := grid.tile_at(p)
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
		if pick[0] != Pick.NONE:
			clicked.emit(pick[0], pick[1])
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if board == null:
		return
	_draw_sea()
	for port in board.ports:
		_draw_port(port)
	for t in board.grid.tile_count():
		_draw_tile(t)
	if game != null:
		for e in game.edge_owner.size():
			if game.edge_owner[e] != -1:
				_draw_road(e, _player_color(game.edge_owner[e]))
		for v in game.vertex_owner.size():
			if game.vertex_owner[v] != -1:
				_draw_building(v, game.vertex_building[v], _player_color(game.vertex_owner[v]))
	_draw_targets()
	if _target_kind == Pick.NONE:
		_draw_highlight(_hover, HOVER_COLOR)
	elif _hover[0] != Pick.NONE:
		_draw_highlight(_hover, SELECT_COLOR)


func _player_color(pid: int) -> Color:
	return game.players[pid].color


func _draw_road(e: int, color: Color) -> void:
	var ev: Array = board.grid.edge_vertices[e]
	var a := board.grid.vertex_positions[ev[0]] * hex_size
	var b := board.grid.vertex_positions[ev[1]] * hex_size
	var shrink := (b - a) * 0.14
	draw_line(a + shrink, b - shrink, PIECE_OUTLINE, hex_size * 0.2, true)
	draw_line(a + shrink, b - shrink, color, hex_size * 0.13, true)


func _draw_building(v: int, building: int, color: Color) -> void:
	var c := board.grid.vertex_positions[v] * hex_size
	var s := hex_size * 0.17
	var shape: PackedVector2Array
	if building == ArchipelagoGame.Building.CITY:
		# Casa con torre a la izquierda.
		shape = PackedVector2Array([
			c + Vector2(-1.5, 1) * s, c + Vector2(1.5, 1) * s, c + Vector2(1.5, -0.3) * s,
			c + Vector2(0.75, -1.0) * s, c + Vector2(0, -0.3) * s, c + Vector2(0, -0.8) * s,
			c + Vector2(-0.75, -1.6) * s, c + Vector2(-1.5, -0.8) * s,
		])
	else:
		shape = PackedVector2Array([
			c + Vector2(-1, 1) * s, c + Vector2(1, 1) * s, c + Vector2(1, -0.2) * s,
			c + Vector2(0, -1.2) * s, c + Vector2(-1, -0.2) * s,
		])
	draw_colored_polygon(shape, color)
	shape.append(shape[0])
	draw_polyline(shape, PIECE_OUTLINE, maxf(1.5, hex_size * 0.04), true)


func _draw_targets() -> void:
	var pulse := 0.65 + 0.35 * sin(_time * 5.0)
	var color := Color(SELECT_COLOR, pulse)
	var backing := Color(0.1, 0.1, 0.1, 0.55)
	for id in _target_ids:
		match _target_kind:
			Pick.VERTEX:
				var c := board.grid.vertex_positions[id] * hex_size
				draw_circle(c, hex_size * 0.14, backing)
				draw_arc(c, hex_size * 0.11, 0, TAU, 24, color, hex_size * 0.05, true)
			Pick.EDGE:
				var ev: Array = board.grid.edge_vertices[id]
				var a := board.grid.vertex_positions[ev[0]] * hex_size
				var b := board.grid.vertex_positions[ev[1]] * hex_size
				var shrink := (b - a) * 0.22
				draw_line(a + shrink, b - shrink, backing, hex_size * 0.14, true)
				draw_line(a + shrink, b - shrink, color, hex_size * 0.07, true)
			Pick.TILE:
				# Borde interior del hexágono, para no tapar el número.
				var corners := HexCoords.corners(board.grid.tile_center(id) * hex_size, hex_size * 0.86)
				corners.append(corners[0])
				draw_polyline(corners, backing, hex_size * 0.1, true)
				draw_polyline(corners, color, hex_size * 0.05, true)


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
