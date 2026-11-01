class_name PestsBoardView
extends Control
## Vista 2D de la casa de Pests!: habitaciones con sus puertas, plagas,
## reinas, trampas, sellos y exterminadores. Detecta clics sobre casillas.
##
## Contrato con la pantalla:
##   - propiedad `game` (solo lectura),
##   - set_targets(rooms, cells): resalta habitaciones y casillas vacías
##     jugables,
##   - set_ghost(doors, species): loseta fantasma bajo el ratón al colocar
##     (doors = -1 para quitarla),
##   - refresh(), fit(rect),
##   - señales hovered(cell), cell_clicked(cell).

signal hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const D := preload("res://games/pests/logic/pests_defs.gd")

const NO_CELL := Vector2i(-9999, -9999)
const FLOOR := Color("e8dcb8")
const FLOOR_ENTRY := Color("c9bfae")
const WALL := Color("4a3b2a")
const DOOR := Color("b07a46")
const LAWN := Color("6fa354")
const TARGET := Color("ffd166")
const TEXT_DARK := Color("2b2b2b")
const OUTLINE := Color("1b1b1b")
const MAX_CELL := 150.0

var game: PestsGame

var _cell := 80.0
var _origin := Vector2.ZERO
var _bounds := Rect2i()
var _target_rooms: Array[int] = []
var _target_cells: Array[Vector2i] = []
var _ghost_doors := -1
var _ghost_species := -1
var _hover := NO_CELL


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func fit(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	_recompute()
	queue_redraw()


func refresh() -> void:
	_recompute()
	queue_redraw()


func set_targets(rooms: Array[int], cells: Array[Vector2i] = []) -> void:
	_target_rooms = rooms
	_target_cells = cells
	queue_redraw()


func set_ghost(doors: int, species: int = -1) -> void:
	_ghost_doors = doors
	_ghost_species = species
	queue_redraw()


## Centro en pantalla (coordenadas locales) de una casilla.
func cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).get_center()


func _recompute() -> void:
	if game == null or size.x <= 0:
		return
	# Mientras se construye la casa, un margen de una casilla para las
	# losetas por colocar.
	_bounds = game.house.bounds()
	if game.phase == PestsGame.Phase.PLACE_TILES:
		_bounds = _bounds.grow(1)
	_cell = minf(MAX_CELL, minf(size.x / _bounds.size.x, size.y / _bounds.size.y))
	var used := Vector2(_bounds.size) * _cell
	_origin = (size - used) / 2.0


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(cell - _bounds.position) * _cell, Vector2.ONE * _cell)


func _cell_at(point: Vector2) -> Vector2i:
	var p := (point - _origin) / _cell
	return Vector2i(floori(p.x), floori(p.y)) + _bounds.position


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != _hover:
			_hover = cell
			hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(_cell_at(event.position))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = NO_CELL
		hovered.emit(NO_CELL)
		queue_redraw()


# --- Dibujo -------------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	var house := game.house
	# Jardín de la entrada.
	var lawn := _cell_rect(PestsHouse.LAWN_CELL).grow(-2)
	draw_rect(lawn, LAWN)
	_text("Jardín", lawn.get_center() + Vector2(0, _cell * 0.05), _cell * 0.14, Color(1, 1, 1, 0.8))
	# Casillas donde se puede colocar.
	for cell in _target_cells:
		var r := _cell_rect(cell).grow(-4)
		draw_rect(r, Color(TARGET, 0.15))
		draw_rect(r, TARGET, false, 2.0)
	for room in house.room_count():
		_draw_room(room)
	if _ghost_doors >= 0 and _hover in _target_cells:
		_draw_tile(_cell_rect(_hover), _ghost_doors, _room_floor(D.RoomKind.NEST if _ghost_species >= 0 else D.RoomKind.STANDARD, _ghost_species), 0.6)
	if game.pests.size() == house.room_count():
		for room in house.room_count():
			_draw_contents(room)


func _room_floor(kind: int, sp: int) -> Color:
	match kind:
		D.RoomKind.ENTRY:
			return FLOOR_ENTRY
		D.RoomKind.NEST:
			return Color(D.SPECIES_COLORS[sp]).lerp(FLOOR, 0.45)
	return FLOOR


func _draw_room(room: int) -> void:
	var house := game.house
	var rect := _cell_rect(house.room_cell[room])
	var kind := house.room_kind[room]
	var sp := house.room_species[room]
	_draw_tile(rect, house.room_doors[room], _room_floor(kind, sp), 1.0)
	var inner := rect.grow(-_cell * 0.08)
	if kind == D.RoomKind.ENTRY:
		var c := rect.get_center()
		var f := _cell * 0.11
		var compass := Color(TEXT_DARK, 0.45)
		_text("U", c + Vector2(0, -_cell * 0.06), f, compass)
		_text("D", c + Vector2(0, _cell * 0.4), f, compass)
		_text("L", c + Vector2(-_cell * 0.36, 0.17 * _cell), f, compass)
		_text("R", c + Vector2(_cell * 0.36, 0.17 * _cell), f, compass)
	elif _cell >= 60:
		_text(house.room_name(room), Vector2(inner.get_center().x, inner.position.y + _cell * 0.1), _cell * 0.11, Color(TEXT_DARK, 0.75), inner.size.x)
	if kind == D.RoomKind.NEST and game.sealed.size() > sp and game.sealed[sp]:
		# Sello: una cruz gruesa sobre el nido.
		var a := inner.grow(-_cell * 0.12)
		draw_line(a.position, a.end, Color(OUTLINE, 0.55), _cell * 0.06)
		draw_line(Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), Color(OUTLINE, 0.55), _cell * 0.06)
		_text("SELLADO", inner.get_center() + Vector2(0, _cell * 0.05), _cell * 0.13, Color("b71c1c"))
	if room in _target_rooms:
		draw_rect(rect.grow(-3), TARGET, false, 4.0)
	if _hover == house.room_cell[room]:
		draw_rect(rect.grow(-2), Color(1, 1, 1, 0.12))


## Suelo, paredes y puertas de una loseta.
func _draw_tile(rect: Rect2, doors: int, floor_color: Color, alpha: float) -> void:
	var r := rect.grow(-1.5)
	draw_rect(r, Color(floor_color, alpha))
	var w := maxf(2.0, _cell * 0.05)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for dir in 4:
		# Lado `dir`: de la esquina dir a la siguiente (arriba, derecha, abajo, izquierda).
		var a: Vector2 = corners[dir]
		var b: Vector2 = corners[(dir + 1) % 4]
		var wall := Color(WALL, alpha)
		if doors & D.dir_bit(dir):
			var gap := 0.3
			var m1 := a.lerp(b, 0.5 - gap / 2.0)
			var m2 := a.lerp(b, 0.5 + gap / 2.0)
			draw_line(a, m1, wall, w)
			draw_line(m2, b, wall, w)
			draw_line(m1, m2, Color(DOOR, alpha), w * 0.5)
		else:
			draw_line(a, b, wall, w)


## Plagas, reinas, trampas y exterminadores de una habitación.
func _draw_contents(room: int) -> void:
	var rect := _cell_rect(game.house.room_cell[room]).grow(-_cell * 0.1)
	# Plagas: una ficha por especie con su número, en dos filas abajo.
	var slot := 0
	var radius := _cell * 0.1
	for sp in D.SPECIES_COUNT:
		var n: int = game.pests[room][sp]
		if n <= 0:
			continue
		var col := slot % 3
		var row := slot / 3
		var p := Vector2(rect.position.x + rect.size.x * (0.2 + 0.3 * col), rect.end.y - radius * (1.1 + 2.3 * row))
		draw_circle(p, radius, D.SPECIES_COLORS[sp])
		draw_arc(p, radius, 0, TAU, 20, OUTLINE, 1.2)
		_text(str(n), p + Vector2(0, radius * 0.4), radius * 1.15, TEXT_DARK)
		slot += 1
	# Reinas libres.
	var qx := 0
	for sp in D.SPECIES_COUNT:
		if game.queen_room[sp] != room or game.is_queen_trapped(sp):
			continue
		_draw_queen(Vector2(rect.position.x + _cell * (0.18 + 0.22 * qx), rect.get_center().y - _cell * 0.02), sp, _cell * 0.11)
		qx += 1
	# Trampas: arriba a la derecha.
	var tx := 0
	for t in game.traps_in_room(room):
		var size_t := _cell * 0.2
		var tr := Rect2(Vector2(rect.end.x - size_t * (1.1 + 1.15 * tx), rect.position.y + _cell * 0.1), Vector2.ONE * size_t)
		var color: Color = D.SPECIES_COLORS[game.trap_species(t)]
		draw_rect(tr, Color(color, 0.35))
		draw_rect(tr, color.darkened(0.3), false, 2.0)
		for i in 3:
			var x := tr.position.x + tr.size.x * (0.25 + 0.25 * i)
			draw_line(Vector2(x, tr.position.y), Vector2(x, tr.end.y), color.darkened(0.4), 1.0)
		if t["queen"]:
			_draw_queen(tr.get_center(), game.trap_species(t), size_t * 0.4)
		elif t["pests"] > 0:
			_text(str(t["pests"]), tr.get_center() + Vector2(0, size_t * 0.2), size_t * 0.6, TEXT_DARK)
		tx += 1
	# Exterminadores: en fila, arriba a la izquierda.
	var ex := 0
	for pid in game.players.size():
		if game.eliminated[pid] or game.exterminator_room[pid] != room or game.species(pid) < 0:
			continue
		var c := Vector2(rect.position.x + _cell * (0.08 + 0.12 * ex), rect.position.y + _cell * 0.2)
		_draw_exterminator(c, game.species(pid), Color.WHITE, _cell * 0.06)
		ex += 1


func _draw_queen(c: Vector2, sp: int, s: float) -> void:
	var color: Color = D.SPECIES_COLORS[sp]
	var crown := PackedVector2Array([
		c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.4), c + Vector2(-s * 0.5, s * 0.05),
		c + Vector2(0, -s * 0.8), c + Vector2(s * 0.5, s * 0.05), c + Vector2(s, -s * 0.4), c + Vector2(s, s * 0.6)])
	draw_colored_polygon(crown, color)
	crown.append(crown[0])
	draw_polyline(crown, Color("f2c94c"), maxf(1.5, s * 0.18))


func _draw_exterminator(c: Vector2, sp: int, ring: Color, s: float) -> void:
	var color: Color = D.SPECIES_COLORS[sp]
	var body := PackedVector2Array([c + Vector2(-s, s * 2.2), c + Vector2(-s * 0.8, s * 0.4),
		c + Vector2(s * 0.8, s * 0.4), c + Vector2(s, s * 2.2)])
	draw_colored_polygon(body, color.darkened(0.15))
	draw_circle(c + Vector2(0, -s * 0.4), s * 0.75, color)
	draw_arc(c + Vector2(0, -s * 0.4), s * 0.75, 0, TAU, 16, ring, 2.0)
	body.append(body[0])
	draw_polyline(body, OUTLINE, 1.2)


## Texto centrado en `pos.x`. Con `max_width`, reduce la letra hasta que quepa.
func _text(text: String, pos: Vector2, font_size: float, color: Color, max_width: float = -1.0) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(8, int(font_size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while max_width > 0 and width > max_width and fs > 8:
		fs -= 1
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
