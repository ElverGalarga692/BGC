class_name PestsBoardView
extends Control
## Vista 2D de la casa de Pests!: habitaciones con suelo y mueble propios,
## puertas, plagas, reinas, trampas, sellos y exterminadores, todo dibujado
## por código. Tiene animaciones sencillas (plagas que vuelan de una
## habitación a otra, piezas que se desplazan, textos que flotan, destellos).
##
## Contrato con la pantalla:
##   - propiedad `game` (solo lectura),
##   - set_targets(rooms, cells): resalta habitaciones y casillas vacías,
##   - set_ghost(doors, species): loseta fantasma bajo el ratón al colocar,
##   - refresh(), fit(rect),
##   - animaciones: fly(from, to, color, count), pop(room, color, count),
##     move_piece(from, to, kind, species), float_text(room, text, color),
##     flash(room, color),
##   - señales hovered(cell), cell_clicked(cell).

signal hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const D := preload("res://games/pests/logic/pests_defs.gd")

const NO_CELL := Vector2i(-9999, -9999)
const OUTSIDE := Color("2e3b2c")
const OUTSIDE_DOT := Color("3a4a37")
const WALL := Color("3d2f22")
const DOOR := Color("c08a52")
const LAWN := Color("6fa354")
const TARGET := Color("ffd166")
const TEXT_DARK := Color("2b2b2b")
const OUTLINE := Color("1b1b1b")
const MAX_CELL := 150.0

enum Floor { WOOD, TILES, CARPET }
enum Furniture { NONE, WARDROBE, SOFA, DESK, WASHER, RUG, BOOKCASE, ARCADE, FIREPLACE, PLANT, BATH, PIANO, BOXES, BED, KITCHEN, TOYS }

## Suelo, color del suelo y mueble de cada loseta estándar (mismo orden que
## PestsDefs.STANDARD_TILES).
const TILE_ART := [
	[Floor.WOOD, Color("c79b6a"), Furniture.WARDROBE],
	[Floor.CARPET, Color("b9a07a"), Furniture.SOFA],
	[Floor.WOOD, Color("a87a52"), Furniture.DESK],
	[Floor.TILES, Color("dfe3e6"), Furniture.WASHER],
	[Floor.WOOD, Color("c9a27a"), Furniture.RUG],
	[Floor.WOOD, Color("b88d63"), Furniture.SOFA],
	[Floor.CARPET, Color("8f6d5a"), Furniture.BOOKCASE],
	[Floor.CARPET, Color("6f7fa8"), Furniture.ARCADE],
	[Floor.WOOD, Color("b17f55"), Furniture.FIREPLACE],
	[Floor.WOOD, Color("d1b08a"), Furniture.PLANT],
	[Floor.TILES, Color("cfe4ea"), Furniture.BATH],
	[Floor.CARPET, Color("c78f8f"), Furniture.DESK],
	[Floor.TILES, Color("e6e6e0"), Furniture.PIANO],
	[Floor.WOOD, Color("9c7a55"), Furniture.BOXES],
	[Floor.WOOD, Color("c4976b"), Furniture.BED],
	[Floor.TILES, Color("f0dcc0"), Furniture.KITCHEN],
	[Floor.WOOD, Color("d5ab7c"), Furniture.TOYS],
	[Floor.WOOD, Color("cfa57a"), Furniture.NONE],
]

var game: PestsGame

var _cell := 80.0
var _origin := Vector2.ZERO
var _bounds := Rect2i()
var _target_rooms: Array[int] = []
var _target_cells: Array[Vector2i] = []
var _ghost_doors := -1
var _ghost_species := -1
var _hover := NO_CELL
var _time := 0.0
## Animaciones en curso: {"kind", "from", "to", "color", "species", "t", "delay", "dur", "text"}.
var _anims: Array[Dictionary] = []


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


func cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).get_center()


func room_center(room: int) -> Vector2:
	return cell_center(game.house.room_cell[room])


# --- Animaciones --------------------------------------------------------------

## Plagas que vuelan de una habitación a otra (como mucho 4 dibujadas).
func fly(from_room: int, to_room: int, color: Color, count: int = 1) -> void:
	if not _valid_room(from_room) or not _valid_room(to_room):
		return
	for i in mini(count, 4):
		var jitter := Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15)) * _cell
		_add_anim("fly", room_center(from_room) + jitter, room_center(to_room) + jitter * 0.5, color, i * 0.07, 0.55)


## Plagas que aparecen en una habitación.
func pop(room: int, color: Color, count: int = 1) -> void:
	if not _valid_room(room):
		return
	for i in mini(count, 4):
		var offset := Vector2(randf_range(-0.25, 0.25), randf_range(-0.1, 0.3)) * _cell
		_add_anim("pop", room_center(room) + offset, room_center(room) + offset, color, i * 0.08, 0.45)


## Una pieza ("queen" o "exterminator") que se desplaza entre habitaciones.
func move_piece(from_room: int, to_room: int, kind: String, species: int) -> void:
	if not _valid_room(from_room) or not _valid_room(to_room) or from_room == to_room:
		return
	var a := _add_anim(kind, room_center(from_room), room_center(to_room), D.SPECIES_COLORS[species], 0.0, 0.4)
	a["species"] = species


## Texto que sube y se desvanece sobre una habitación (p. ej. "−3").
func float_text(room: int, text: String, color: Color) -> void:
	if not _valid_room(room):
		return
	var a := _add_anim("text", room_center(room), room_center(room) + Vector2(0, -_cell * 0.5), color, 0.0, 1.1)
	a["text"] = text


## Destello de una habitación.
func flash(room: int, color: Color) -> void:
	if not _valid_room(room):
		return
	_add_anim("flash", room_center(room), room_center(room), color, 0.0, 0.6)


func _add_anim(kind: String, from: Vector2, to: Vector2, color: Color, delay: float, dur: float) -> Dictionary:
	var a := {"kind": kind, "from": from, "to": to, "color": color, "species": -1, "t": 0.0, "delay": delay, "dur": dur, "text": ""}
	_anims.append(a)
	return a


func _valid_room(room: int) -> bool:
	return game != null and room >= 0 and room < game.house.room_count()


func _process(delta: float) -> void:
	_time += delta
	for a in _anims:
		a["t"] += delta
	if not _anims.is_empty():
		_anims = _anims.filter(func(a: Dictionary) -> bool: return a["t"] < a["delay"] + a["dur"])
	# Se redibuja cada fotograma: animaciones, pulso de los resaltados y bichos
	# que se mueven. (Nunca desde _draw(): eso encadena redibujados sin fin.)
	if game != null and is_visible_in_tree():
		queue_redraw()


# --- Geometría y entrada -----------------------------------------------------------

func _recompute() -> void:
	if game == null or size.x <= 0:
		return
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


# --- Dibujo ---------------------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	_draw_outside()
	var house := game.house
	_draw_lawn(_cell_rect(PestsHouse.LAWN_CELL))
	for cell in _target_cells:
		var pulse := 0.12 + 0.08 * sin(_time * 4.0)
		var r := _cell_rect(cell).grow(-4)
		draw_rect(r, Color(TARGET, pulse))
		draw_rect(r, TARGET, false, 2.0)
	for room in house.room_count():
		_draw_room(room)
	if _ghost_doors >= 0 and _hover in _target_cells:
		var kind := D.RoomKind.NEST if _ghost_species >= 0 else D.RoomKind.STANDARD
		var ghost := _cell_rect(_hover)
		_draw_floor(ghost, kind, _ghost_species, -1, 0.55)
		_draw_walls(ghost, _ghost_doors, 0.7)
	if game.pests.size() == house.room_count():
		for room in house.room_count():
			_draw_contents(room)
	_draw_anims()


## Exterior: hierba oscura con un punteado regular.
func _draw_outside() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OUTSIDE)
	var step := maxf(18.0, _cell * 0.25)
	var y := fposmod(_origin.y, step)
	var row := 0
	while y < size.y:
		var x := fposmod(_origin.x, step) + (step * 0.5 if row % 2 == 1 else 0.0)
		while x < size.x:
			draw_circle(Vector2(x, y), 1.5, OUTSIDE_DOT)
			x += step
		y += step
		row += 1


func _draw_lawn(rect: Rect2) -> void:
	var r := rect.grow(-2)
	draw_rect(r, LAWN)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var u := _cell / 80.0
	for i in 18:
		var p := r.position + Vector2(rng.randf(), rng.randf()) * r.size
		draw_line(p, p + Vector2(-2, -5) * u, LAWN.darkened(0.25), 1.5)
		draw_line(p, p + Vector2(2, -5) * u, LAWN.darkened(0.25), 1.5)
	for i in 4:
		var p := r.position + Vector2(rng.randf(), rng.randf()) * r.size
		draw_circle(p, _cell * 0.025, Color("f4e04d") if i % 2 == 0 else Color.WHITE)
	# Camino de piedras hasta la puerta.
	for i in 3:
		var c := Vector2(r.get_center().x + (i % 2) * _cell * 0.06 - _cell * 0.03, r.position.y + r.size.y * (0.2 + 0.3 * i))
		draw_circle(c, _cell * 0.07, Color("b7b2a5"))
		draw_arc(c, _cell * 0.07, 0, TAU, 14, Color("8a867b"), 1.0)
	_text("Jardín", r.get_center() + Vector2(_cell * 0.22, _cell * 0.38), _cell * 0.11, Color(1, 1, 1, 0.75))


func _draw_room(room: int) -> void:
	var house := game.house
	var rect := _cell_rect(house.room_cell[room])
	var kind := house.room_kind[room]
	var sp := house.room_species[room]
	_draw_floor(rect, kind, sp, house.room_tile[room], 1.0, room)
	_draw_walls(rect, house.room_doors[room], 1.0)
	var inner := rect.grow(-_cell * 0.08)
	if kind != D.RoomKind.ENTRY and _cell >= 60:
		var label_rect := Rect2(inner.position.x, inner.position.y + _cell * 0.01, inner.size.x, _cell * 0.13)
		draw_rect(label_rect, Color(0, 0, 0, 0.25))
		_text(house.room_name(room), Vector2(inner.get_center().x, inner.position.y + _cell * 0.1), _cell * 0.105, Color(1, 1, 1, 0.92), inner.size.x - 4)
	if kind == D.RoomKind.NEST and game.sealed.size() > sp and game.sealed[sp]:
		_draw_seal(inner)
	if room in _target_rooms:
		var pulse := 0.6 + 0.4 * sin(_time * 5.0)
		draw_rect(rect.grow(-3), Color(TARGET, pulse), false, 4.0)
	if _hover == house.room_cell[room]:
		draw_rect(rect.grow(-2), Color(1, 1, 1, 0.12))


## Suelo de una habitación según su tipo (y el mueble de las estándar).
func _draw_floor(rect: Rect2, kind: int, sp: int, tile: int, alpha: float, room: int = -1) -> void:
	var r := rect.grow(-1.5)
	match kind:
		D.RoomKind.ENTRY:
			_draw_tiles_floor(r, Color("bdb6a8"), alpha, 3)
			_draw_entry_details(r, alpha)
		D.RoomKind.NEST:
			_draw_nest_floor(r, sp, alpha, room)
		_:
			var art: Array = TILE_ART[tile] if tile >= 0 else [Floor.WOOD, Color("cfa57a"), Furniture.NONE]
			match art[0]:
				Floor.WOOD:
					_draw_wood_floor(r, art[1], alpha)
				Floor.TILES:
					_draw_tiles_floor(r, art[1], alpha, 5)
				Floor.CARPET:
					_draw_carpet_floor(r, art[1], alpha)
			_draw_furniture(r, art[2], alpha)


func _draw_wood_floor(r: Rect2, base: Color, alpha: float) -> void:
	draw_rect(r, Color(base, alpha))
	var planks := 6
	var h := r.size.y / planks
	for i in planks:
		var y := r.position.y + h * i
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(base.darkened(0.25), alpha * 0.8), 1.0)
		var joint := r.position.x + r.size.x * (0.3 + 0.37 * (i % 3) / 2.0)
		draw_line(Vector2(joint, y), Vector2(joint, y + h), Color(base.darkened(0.25), alpha * 0.6), 1.0)


func _draw_tiles_floor(r: Rect2, base: Color, alpha: float, n: int) -> void:
	var s := r.size / n
	for i in n:
		for j in n:
			var c := base if (i + j) % 2 == 0 else base.darkened(0.1)
			draw_rect(Rect2(r.position + Vector2(i, j) * s, s), Color(c, alpha))
	for i in n + 1:
		draw_line(r.position + Vector2(s.x * i, 0), r.position + Vector2(s.x * i, r.size.y), Color(base.darkened(0.25), alpha * 0.5), 1.0)
		draw_line(r.position + Vector2(0, s.y * i), r.position + Vector2(r.size.x, s.y * i), Color(base.darkened(0.25), alpha * 0.5), 1.0)


func _draw_carpet_floor(r: Rect2, base: Color, alpha: float) -> void:
	draw_rect(r, Color(base.darkened(0.15), alpha))
	var inner := r.grow(-_cell * 0.07)
	draw_rect(inner, Color(base, alpha))
	draw_rect(inner, Color(base.lightened(0.3), alpha * 0.8), false, 1.5)


func _draw_nest_floor(r: Rect2, sp: int, alpha: float, room: int) -> void:
	var base: Color = Color(D.SPECIES_COLORS[sp]).lerp(Color("5a4a3a"), 0.35)
	draw_rect(r, Color(base, alpha))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + maxi(room, 0) * 17 + sp
	# Manchas.
	for i in 6:
		var p := r.position + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.25, 0.85)) * r.size
		draw_circle(p, _cell * rng.randf_range(0.04, 0.1), Color(base.darkened(0.35), alpha * 0.7))
	# Grietas.
	for i in 3:
		var p := r.position + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.2, 0.9)) * r.size
		var pts := PackedVector2Array([p])
		for k in 3:
			p += Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)) * _cell
			pts.append(p)
		draw_polyline(pts, Color(OUTLINE, alpha * 0.55), 1.2)
	# Agujero del nido.
	var hole := r.get_center() + Vector2(0, _cell * 0.05)
	draw_circle(hole, _cell * 0.12, Color(OUTLINE, alpha * 0.85))
	draw_arc(hole, _cell * 0.12, 0, TAU, 20, Color(base.lightened(0.2), alpha), 2.0)


func _draw_entry_details(r: Rect2, alpha: float) -> void:
	var c := r.get_center()
	# Rosa de los vientos.
	var s := _cell * 0.22
	var star := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.18, -s * 0.18), c + Vector2(s, 0),
		c + Vector2(s * 0.18, s * 0.18), c + Vector2(0, s), c + Vector2(-s * 0.18, s * 0.18), c + Vector2(-s, 0), c + Vector2(-s * 0.18, -s * 0.18)])
	draw_colored_polygon(star, Color("6b5a43", alpha * 0.8))
	var f := _cell * 0.1
	var compass := Color(TEXT_DARK, 0.6 * alpha)
	_text("U", c + Vector2(0, -s - _cell * 0.03), f, compass)
	_text("D", c + Vector2(0, s + _cell * 0.1), f, compass)
	_text("L", c + Vector2(-s - _cell * 0.07, f * 0.35), f, compass)
	_text("R", c + Vector2(s + _cell * 0.07, f * 0.35), f, compass)
	# Felpudo.
	var mat := Rect2(Vector2(c.x - _cell * 0.24, r.end.y - _cell * 0.17), Vector2(_cell * 0.48, _cell * 0.13))
	draw_rect(mat, Color("8c5a2b", alpha))
	_text("WELCOME", mat.get_center() + Vector2(0, _cell * 0.035), _cell * 0.075, Color("f2d9a0", alpha))


func _draw_furniture(r: Rect2, kind: int, alpha: float) -> void:
	var u := _cell / 100.0
	var c := r.get_center() + Vector2(0, -6 * u)
	var line := Color(OUTLINE, alpha * 0.7)
	match kind:
		Furniture.WARDROBE, Furniture.BOOKCASE:
			var shelf := Rect2(Vector2(r.position.x + 12 * u, r.position.y + 16 * u), Vector2(r.size.x - 24 * u, 13 * u))
			draw_rect(shelf, Color("6d4c35", alpha))
			var colors := [Color("c0392b"), Color("2980b9"), Color("27ae60"), Color("f1c40f"), Color("8e44ad")]
			var n := 9 if kind == Furniture.BOOKCASE else 4
			for i in n:
				var w := (shelf.size.x - 4 * u) / n
				var book := Rect2(shelf.position + Vector2(2 * u + w * i, 2 * u), Vector2(w - 1.5 * u, shelf.size.y - 4 * u))
				var book_color: Color = colors[i % colors.size()] if kind == Furniture.BOOKCASE else Color("8a6447")
				draw_rect(book, Color(book_color, alpha))
			draw_rect(shelf, line, false, 1.0)
		Furniture.SOFA:
			var body := Rect2(c + Vector2(-26, -4) * u, Vector2(52, 18) * u)
			draw_rect(body, Color("7d5ba6", alpha))
			draw_rect(Rect2(body.position + Vector2(0, -8 * u), Vector2(body.size.x, 9 * u)), Color("6a4a92", alpha))
			draw_rect(Rect2(body.position + Vector2(-5 * u, -8 * u), Vector2(6 * u, 26 * u)), Color("5c3f80", alpha))
			draw_rect(Rect2(body.end + Vector2(-1 * u, -26 * u), Vector2(6 * u, 26 * u)), Color("5c3f80", alpha))
		Furniture.DESK:
			var desk := Rect2(c + Vector2(-22, -10) * u, Vector2(44, 16) * u)
			draw_rect(desk, Color("8b5e3c", alpha))
			draw_rect(desk, line, false, 1.0)
			draw_rect(Rect2(desk.position + Vector2(6, 3) * u, Vector2(12, 8) * u), Color("dfe6e9", alpha))
			draw_circle(c + Vector2(0, 14) * u, 6 * u, Color("444444", alpha))
		Furniture.WASHER:
			for i in 2:
				var box := Rect2(c + Vector2(-24 + 26 * i, -12) * u, Vector2(22, 22) * u)
				draw_rect(box, Color("f5f6fa", alpha))
				draw_rect(box, line, false, 1.0)
				draw_circle(box.get_center(), 7 * u, Color("74b9ff", alpha))
				draw_arc(box.get_center(), 7 * u, 0, TAU, 16, line, 1.0)
		Furniture.RUG:
			_draw_ellipse(c, Vector2(26, 14) * u, Color("c0392b", alpha))
			_draw_ellipse(c, Vector2(19, 9) * u, Color("f39c12", alpha))
			_draw_ellipse(c, Vector2(11, 5) * u, Color("c0392b", alpha))
		Furniture.ARCADE:
			for i in 2:
				var cab := Rect2(c + Vector2(-24 + 28 * i, -14) * u, Vector2(20, 24) * u)
				draw_rect(cab, Color("2d3436", alpha))
				draw_rect(Rect2(cab.position + Vector2(3, 3) * u, Vector2(14, 9) * u), Color("00cec9", alpha))
				draw_circle(cab.position + Vector2(6, 17) * u, 2.5 * u, Color("d63031", alpha))
		Furniture.FIREPLACE:
			var fp := Rect2(Vector2(c.x - 22 * u, r.position.y + 16 * u), Vector2(44, 20) * u)
			draw_rect(fp, Color("a0522d", alpha))
			for i in 3:
				draw_line(fp.position + Vector2(0, 6 * u * (i + 1)), fp.position + Vector2(fp.size.x, 6 * u * (i + 1)), Color("7a3d22", alpha), 1.0)
			var mouth := Rect2(fp.position + Vector2(12, 6) * u, Vector2(20, 14) * u)
			draw_rect(mouth, Color("2d1b12", alpha))
			var flame := 1.0 + 0.15 * sin(_time * 9.0)
			draw_colored_polygon(PackedVector2Array([mouth.get_center() + Vector2(-6, 6) * u, mouth.get_center() + Vector2(0, -8 * flame) * u, mouth.get_center() + Vector2(6, 6) * u]), Color("f39c12", alpha))
		Furniture.PLANT:
			for k in 2:
				var pc := c + Vector2(-24 + 48 * k, -8) * u
				draw_circle(pc + Vector2(0, 6) * u, 6 * u, Color("a0522d", alpha))
				draw_circle(pc + Vector2(-4, -2) * u, 7 * u, Color("27ae60", alpha))
				draw_circle(pc + Vector2(4, -3) * u, 7 * u, Color("2ecc71", alpha))
		Furniture.BATH:
			var tub := Rect2(c + Vector2(-26, -12) * u, Vector2(52, 22) * u)
			draw_rect(tub, Color("f5f6fa", alpha))
			draw_rect(tub.grow(-4 * u), Color("74b9ff", alpha))
			draw_rect(tub, line, false, 1.0)
		Furniture.PIANO:
			var piano := Rect2(c + Vector2(-24, -14) * u, Vector2(48, 22) * u)
			draw_rect(piano, Color("1e1e1e", alpha))
			var keys := Rect2(piano.position + Vector2(0, piano.size.y - 7 * u), Vector2(piano.size.x, 7 * u))
			draw_rect(keys, Color("f5f5f5", alpha))
			for i in 8:
				draw_line(keys.position + Vector2(keys.size.x * i / 8.0, 0), keys.position + Vector2(keys.size.x * i / 8.0, keys.size.y), Color("1e1e1e", alpha), 1.0)
		Furniture.BOXES:
			for p in [Vector2(-26, -14), Vector2(-4, -14), Vector2(-15, -2)]:
				var box := Rect2(c + p * u, Vector2(20, 16) * u)
				draw_rect(box, Color("c49a6c", alpha))
				draw_line(box.position + Vector2(box.size.x / 2, 0), box.position + Vector2(box.size.x / 2, box.size.y), Color("8e6b45", alpha), 2.0)
				draw_rect(box, line, false, 1.0)
		Furniture.BED:
			var bed := Rect2(c + Vector2(-16, -20) * u, Vector2(32, 34) * u)
			draw_rect(bed, Color("dfe6e9", alpha))
			draw_rect(Rect2(bed.position + Vector2(0, 11 * u), Vector2(bed.size.x, bed.size.y - 11 * u)), Color("6c5ce7", alpha))
			draw_rect(Rect2(bed.position + Vector2(5, 3) * u, Vector2(22, 6) * u), Color("ffffff", alpha))
			draw_rect(bed, line, false, 1.0)
		Furniture.KITCHEN:
			var counter := Rect2(Vector2(r.position.x + 12 * u, r.position.y + 16 * u), Vector2(r.size.x - 24 * u, 12 * u))
			draw_rect(counter, Color("b2bec3", alpha))
			for i in 2:
				draw_circle(counter.position + Vector2(14 * u + 12 * u * i, 6 * u), 4 * u, Color("2d3436", alpha))
			draw_circle(c + Vector2(0, 10) * u, 10 * u, Color("a47148", alpha))
			for k in 4:
				draw_circle(c + Vector2(0, 10) * u + Vector2.from_angle(k * TAU / 4.0) * 14 * u, 3.5 * u, Color("7a5230", alpha))
		Furniture.TOYS:
			draw_circle(c + Vector2(-16, -4) * u, 7 * u, Color("e17055", alpha))
			draw_line(c + Vector2(-23, -4) * u, c + Vector2(-9, -4) * u, Color(1, 1, 1, alpha), 1.5)
			draw_rect(Rect2(c + Vector2(2, -10) * u, Vector2(10, 10) * u), Color("0984e3", alpha))
			draw_rect(Rect2(c + Vector2(13, -2) * u, Vector2(10, 10) * u), Color("fdcb6e", alpha))
			draw_rect(Rect2(c + Vector2(6, 4) * u, Vector2(10, 10) * u), Color("00b894", alpha))


func _draw_ellipse(c: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(c + Vector2(cos(i * TAU / 24.0) * radii.x, sin(i * TAU / 24.0) * radii.y))
	draw_colored_polygon(pts, color)


## Paredes y puertas de una loseta.
func _draw_walls(rect: Rect2, doors: int, alpha: float) -> void:
	var r := rect.grow(-1.5)
	var w := maxf(3.0, _cell * 0.06)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for dir in 4:
		var a: Vector2 = corners[dir]
		var b: Vector2 = corners[(dir + 1) % 4]
		var wall := Color(WALL, alpha)
		if doors & D.dir_bit(dir):
			var m1 := a.lerp(b, 0.34)
			var m2 := a.lerp(b, 0.66)
			draw_line(a, m1, wall, w)
			draw_line(m2, b, wall, w)
			# Marco y hoja de la puerta.
			draw_line(m1, m2, Color(DOOR, alpha), w * 0.45)
			draw_circle(m1, w * 0.45, Color(WALL, alpha))
			draw_circle(m2, w * 0.45, Color(WALL, alpha))
		else:
			draw_line(a, b, wall, w)


func _draw_seal(inner: Rect2) -> void:
	var c := inner.get_center() + Vector2(0, _cell * 0.05)
	var radius := _cell * 0.26
	draw_circle(c, radius, Color("b71c1c", 0.8))
	draw_arc(c, radius, 0, TAU, 28, Color("ffcdd2"), 2.0)
	draw_arc(c, radius * 0.82, 0, TAU, 28, Color("ffcdd2", 0.6), 1.0)
	_text("SELLADO", c + Vector2(0, _cell * 0.035), _cell * 0.09, Color.WHITE, radius * 1.8)


## Plagas, reinas, trampas y exterminadores de una habitación.
func _draw_contents(room: int) -> void:
	var rect := _cell_rect(game.house.room_cell[room]).grow(-_cell * 0.1)
	# Plagas: un bicho por especie con su número, en dos filas abajo.
	var slot := 0
	var s := _cell * 0.075
	for sp in D.SPECIES_COUNT:
		var n: int = game.pests[room][sp]
		if n <= 0:
			continue
		var col := slot % 3
		var row := slot / 3
		var p := Vector2(rect.position.x + rect.size.x * (0.17 + 0.32 * col), rect.end.y - s * (1.4 + 2.9 * row))
		var wiggle := sin(_time * 6.0 + room * 1.7 + sp) * 0.12
		_draw_bug(p, D.SPECIES_COLORS[sp], s, wiggle)
		_draw_count(p + Vector2(s * 1.25, s * 0.5), n)
		slot += 1
	# Reinas libres.
	var qx := 0
	for sp in D.SPECIES_COUNT:
		if game.queen_room[sp] != room or game.is_queen_trapped(sp):
			continue
		_draw_queen(Vector2(rect.position.x + _cell * (0.2 + 0.24 * qx), rect.get_center().y + _cell * 0.02), sp, _cell * 0.1)
		qx += 1
	# Trampas: arriba a la derecha.
	var tx := 0
	for t in game.traps_in_room(room):
		_draw_trap(Vector2(rect.end.x - _cell * (0.13 + 0.24 * tx), rect.position.y + _cell * 0.27), t, _cell * 0.2)
		tx += 1
	# Exterminadores: en fila, arriba a la izquierda.
	var ex := 0
	for pid in game.players.size():
		if game.eliminated[pid] or game.exterminator_room[pid] != room or game.species(pid) < 0:
			continue
		var c := Vector2(rect.position.x + _cell * (0.08 + 0.12 * ex), rect.position.y + _cell * 0.27)
		_draw_exterminator(c, game.species(pid), _cell * 0.055)
		ex += 1


func _draw_bug(c: Vector2, color: Color, s: float, wiggle: float = 0.0) -> void:
	draw_set_transform(c, wiggle, Vector2.ONE)
	var leg := Color(OUTLINE, color.a)
	for k in 3:
		var y := (k - 1) * s * 0.45
		draw_line(Vector2(-s * 0.3, y), Vector2(-s * 1.0, y + s * 0.25 * (k - 1)), leg, maxf(1.0, s * 0.12))
		draw_line(Vector2(s * 0.3, y), Vector2(s * 1.0, y + s * 0.25 * (k - 1)), leg, maxf(1.0, s * 0.12))
	_draw_ellipse(Vector2(0, s * 0.15), Vector2(s * 0.62, s * 0.8), color)
	draw_circle(Vector2(0, -s * 0.75), s * 0.38, color.darkened(0.3))
	draw_line(Vector2(-s * 0.15, -s * 1.05), Vector2(-s * 0.45, -s * 1.45), leg, 1.0)
	draw_line(Vector2(s * 0.15, -s * 1.05), Vector2(s * 0.45, -s * 1.45), leg, 1.0)
	draw_line(Vector2(0, -s * 0.4), Vector2(0, s * 0.9), Color(OUTLINE, 0.5 * color.a), 1.0)
	draw_set_transform(Vector2.ZERO)


func _draw_count(p: Vector2, n: int) -> void:
	var fs := maxi(9, int(_cell * 0.11))
	var font := ThemeDB.fallback_font
	var text := str(n)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pill := Rect2(p - Vector2(2, fs * 0.85), Vector2(w + 6, fs + 2))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.set_corner_radius_all(int(fs * 0.5))
	draw_style_box(style, pill)
	draw_string(font, p + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_queen(c: Vector2, sp: int, s: float) -> void:
	var color: Color = D.SPECIES_COLORS[sp]
	_draw_bug(c + Vector2(0, s * 0.4), color, s * 0.9)
	var top := c + Vector2(0, -s * 0.75)
	var crown := PackedVector2Array([
		top + Vector2(-s * 0.7, s * 0.35), top + Vector2(-s * 0.7, -s * 0.3), top + Vector2(-s * 0.35, 0),
		top + Vector2(0, -s * 0.5), top + Vector2(s * 0.35, 0), top + Vector2(s * 0.7, -s * 0.3), top + Vector2(s * 0.7, s * 0.35)])
	draw_colored_polygon(crown, Color("f2c94c"))
	crown.append(crown[0])
	draw_polyline(crown, Color("8a6d1d"), maxf(1.0, s * 0.1))


func _draw_trap(c: Vector2, t: Dictionary, s: float) -> void:
	var color: Color = D.SPECIES_COLORS[game.trap_species(t)]
	var box := Rect2(c - Vector2.ONE * s / 2.0, Vector2.ONE * s)
	draw_rect(box, Color(color.darkened(0.5), 0.55))
	if t["queen"]:
		_draw_queen(c + Vector2(0, s * 0.05), game.trap_species(t), s * 0.32)
	elif t["pests"] > 0:
		_draw_bug(c + Vector2(-s * 0.15, s * 0.1), color, s * 0.18)
	for i in 4:
		var x := box.position.x + box.size.x * (0.12 + 0.25 * i)
		draw_line(Vector2(x, box.position.y), Vector2(x, box.end.y), Color("d0d0d0"), 1.2)
	draw_rect(Rect2(box.position - Vector2(0, s * 0.12), Vector2(s, s * 0.14)), color)
	draw_rect(box, OUTLINE, false, 1.5)
	if not t["queen"] and t["pests"] > 0:
		_draw_count(c + Vector2(s * 0.05, s * 0.4), t["pests"])


func _draw_exterminator(c: Vector2, sp: int, s: float) -> void:
	var color: Color = D.SPECIES_COLORS[sp]
	# Mochila con el pulverizador.
	draw_rect(Rect2(c + Vector2(-s * 1.15, s * 0.5), Vector2(s * 0.55, s * 1.2)), Color("7f8c8d"))
	var body := PackedVector2Array([c + Vector2(-s * 0.9, s * 2.2), c + Vector2(-s * 0.75, s * 0.4),
		c + Vector2(s * 0.75, s * 0.4), c + Vector2(s * 0.9, s * 2.2)])
	draw_colored_polygon(body, color.darkened(0.1))
	body.append(body[0])
	draw_polyline(body, OUTLINE, 1.2)
	draw_circle(c + Vector2(0, -s * 0.35), s * 0.72, Color("f5d6b4"))
	# Máscara.
	draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.45), Vector2(s * 1.1, s * 0.45)), Color("2d3436"))
	draw_arc(c + Vector2(0, -s * 0.35), s * 0.72, 0, TAU, 16, OUTLINE, 1.2)
	draw_line(c + Vector2(s * 0.75, s * 1.0), c + Vector2(s * 1.6, s * 0.6), Color("2d3436"), maxf(1.5, s * 0.25))


func _draw_anims() -> void:
	for a in _anims:
		var t: float = (a["t"] - a["delay"]) / a["dur"]
		if t < 0.0:
			continue
		t = clampf(t, 0.0, 1.0)
		var color: Color = a["color"]
		var e := t * t * (3.0 - 2.0 * t)
		match a["kind"]:
			"fly":
				var p: Vector2 = a["from"].lerp(a["to"], e) + Vector2(0, -sin(t * PI) * _cell * 0.25)
				_draw_bug(p, color, _cell * 0.06, sin(_time * 20.0) * 0.3)
			"pop":
				var scale := sin(t * PI) * 1.2
				if scale > 0.05:
					_draw_bug(a["from"] - Vector2(0, t * _cell * 0.15), Color(color, 1.0 - t * 0.5), _cell * 0.06 * scale)
			"queen", "exterminator":
				var p: Vector2 = a["from"].lerp(a["to"], e)
				draw_circle(p, _cell * 0.16 * (1.0 - t * 0.3), Color(color, 0.35 * (1.0 - t)))
				if a["kind"] == "queen":
					_draw_queen(p, a["species"], _cell * 0.1)
				else:
					_draw_exterminator(p, a["species"], _cell * 0.055)
			"text":
				var p: Vector2 = a["from"].lerp(a["to"], t)
				var fs := int(_cell * 0.22)
				var font := ThemeDB.fallback_font
				var w := font.get_string_size(a["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var c := Color(color, 1.0 - t * t)
				draw_string_outline(font, p - Vector2(w / 2.0, 0), a["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, c.a))
				draw_string(font, p - Vector2(w / 2.0, 0), a["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
			"flash":
				var r := Rect2(a["from"] - Vector2.ONE * _cell / 2.0, Vector2.ONE * _cell).grow(-2)
				draw_rect(r, Color(color, 0.45 * (1.0 - t)))
				draw_rect(r.grow(t * _cell * 0.1), Color(color, 1.0 - t), false, 3.0)


## Texto centrado en `pos.x`. Con `max_width`, reduce la letra hasta que quepa.
func _text(text: String, pos: Vector2, font_size: float, color: Color, max_width: float = -1.0) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(8, int(font_size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while max_width > 0 and width > max_width and fs > 8:
		fs -= 1
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
