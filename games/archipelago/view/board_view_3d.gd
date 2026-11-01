class_name ArchBoardView3D
extends SubViewportContainer
## Vista 3D del tablero. Cumple el mismo contrato que ArchBoardView (2D):
## propiedad `game`, set_targets(), refresh(), fit() y las señales
## hovered/clicked. Todo se genera por código (sin modelos externos).
##
## Coordenadas: un punto (x, y) en unidades de hexágono del tablero 2D es
## (x, altura, y) en 3D, así que la cámara por defecto (desde +Z) ve el
## tablero igual que la vista 2D.
##
## Controles: rueda = zoom; botón central o Q/E = girar la cámara.

const Pick := ArchBoardView.Pick

signal hovered(kind: Pick, id: int)
signal clicked(kind: Pick, id: int)

## Altura de las fichas de terreno (su cara superior está en y = TILE_TOP).
const TILE_TOP := 0.22
const TILE_RADIUS := 0.965
const SEA_RADIUS := ArchBoardView.SEA_RADIUS
const BACKGROUND := Color("163246")
const SEA_COLOR := Color("1d5a80")
const SEA_RIM_COLOR := Color("7a5a3a")
const TOKEN_COLOR := Color("f3e6c4")
const TOKEN_TEXT := Color("2b2b2b")
const HOT_TEXT := Color("c0392b")
const SELECT_COLOR := Color("ffc933")
const DROP_HEIGHT := 1.6

var game: ArchipelagoGame:
	set(value):
		game = value
		board = game.board if game != null else null
		_build_board()

var board: ArchBoard

var _viewport: SubViewport
var _camera: Camera3D
var _board_root: Node3D
var _pieces_root: Node3D
var _markers_root: Node3D
var _hover_marker: Node3D
var _bandit: Node3D
var _bandit_tile := -1

var _hover: Array = [Pick.NONE, -1]
var _target_kind: Pick = Pick.NONE
var _target_ids: Array[int] = []
## Piezas en el tablero: clave ("v12", "e30") -> [nodo, tipo].
var _pieces := {}
var _animate := false
var _time := 0.0
var _yaw := 0.0
var _zoom := 1.0
var _dragging := false

var _materials := {}
var _marker_material: StandardMaterial3D
var _hover_material: StandardMaterial3D
var _hex_mesh: ArrayMesh


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d8e8")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.72
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	_viewport.add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 36.0
	_viewport.add_child(_camera)

	_board_root = Node3D.new()
	_pieces_root = Node3D.new()
	_markers_root = Node3D.new()
	for node in [_board_root, _pieces_root, _markers_root]:
		_viewport.add_child(node)

	_marker_material = _unshaded(SELECT_COLOR, 0.8)
	_marker_material.no_depth_test = true
	_marker_material.render_priority = 1
	_hover_material = _unshaded(Color.WHITE, 0.95)
	_hover_material.no_depth_test = true
	_hover_material.render_priority = 2
	_hex_mesh = _make_hex_prism(TILE_RADIUS, TILE_TOP)
	_update_camera()


# --- Contrato con la pantalla -------------------------------------------------------

func set_targets(kind: Pick, ids: Array) -> void:
	_target_kind = kind if not ids.is_empty() else Pick.NONE
	_target_ids.assign(ids)
	_clear(_markers_root)
	_hover_marker = null
	for id in _target_ids:
		_markers_root.add_child(_make_marker(_target_kind, id, _marker_material))
	_set_hover(_pick_at_screen(get_local_mouse_position()) if is_inside_tree() else [Pick.NONE, -1])


func refresh() -> void:
	if board == null:
		return
	_sync_pieces()
	_sync_bandit()


func fit(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	_update_camera()


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.65 + 0.35 * (0.5 + 0.5 * sin(_time * 5.0))
	_marker_material.albedo_color.a = pulse


# --- Cámara y entrada ------------------------------------------------------------------

func _update_camera() -> void:
	if _camera == null:
		return
	var aspect := size.x / maxf(1.0, size.y)
	var distance := 15.5 * maxf(1.0, 1.12 / maxf(aspect, 0.1)) * _zoom
	var pitch := deg_to_rad(57.0)
	var offset := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * distance
	_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_yaw -= event.relative.x * 0.008
			_update_camera()
		_set_hover(_pick_at_screen(event.position))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var pick := _pick_at_screen(event.position)
				if pick[0] != Pick.NONE:
					clicked.emit(pick[0], pick[1])
					accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = maxf(0.55, _zoom - 0.07)
				_update_camera()
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = minf(1.4, _zoom + 0.07)
				_update_camera()
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_dragging = true
				accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_yaw -= deg_to_rad(15)
			_update_camera()
		elif event.keycode == KEY_E:
			_yaw += deg_to_rad(15)
			_update_camera()


## Proyecta el ratón sobre el plano de las fichas y reutiliza la detección
## de la vista 2D.
func _pick_at_screen(screen_pos: Vector2) -> Array:
	if board == null or _camera == null or not _camera.is_inside_tree():
		return [Pick.NONE, -1]
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return [Pick.NONE, -1]
	var t := (TILE_TOP - from.y) / dir.y
	if t < 0.0:
		return [Pick.NONE, -1]
	var hit := from + dir * t
	return ArchBoardView.pick_unit(board, Vector2(hit.x, hit.z), _target_kind, _target_ids)


func _set_hover(pick: Array) -> void:
	if pick == _hover:
		return
	_hover = pick
	if _hover_marker != null:
		_hover_marker.queue_free()
		_hover_marker = null
	if pick[0] != Pick.NONE and (_target_kind != Pick.NONE or pick[0] != Pick.TILE):
		_hover_marker = _make_marker(pick[0], pick[1], _hover_material)
		_markers_root.add_child(_hover_marker)
	hovered.emit(pick[0], pick[1])


# --- Construcción del tablero -------------------------------------------------------------

func _build_board() -> void:
	_clear(_board_root)
	_clear(_pieces_root)
	_clear(_markers_root)
	_pieces.clear()
	_bandit = null
	_bandit_tile = -1
	_hover_marker = null
	if board == null:
		return
	_board_root.add_child(_make_sea())
	for t in board.grid.tile_count():
		_board_root.add_child(_make_tile(t))
	for port in board.ports:
		_board_root.add_child(_make_port(port))
	_animate = false
	refresh()
	_animate = true


func _make_sea() -> Node3D:
	var root := Node3D.new()
	var rim := MeshInstance3D.new()
	rim.mesh = _make_flat_hexagon(SEA_RADIUS + 0.35, 0.0)
	rim.material_override = _material(SEA_RIM_COLOR)
	rim.position.y = -0.06
	root.add_child(rim)
	var sea := MeshInstance3D.new()
	sea.mesh = _make_flat_hexagon(SEA_RADIUS, 0.0)
	var water := _material(SEA_COLOR)
	water.roughness = 0.25
	water.metallic_specular = 0.8
	sea.material_override = water
	sea.position.y = -0.02
	root.add_child(sea)
	return root


func _make_tile(t: int) -> Node3D:
	var center := board.grid.tile_center(t)
	var tile := Node3D.new()
	tile.position = Vector3(center.x, 0, center.y)
	var prism := MeshInstance3D.new()
	prism.mesh = _hex_mesh
	# Algo más oscuros que en 2D: la luz 3D los aclara.
	prism.material_override = _material(ArchDefs.TERRAIN_COLORS[board.tile_terrain[t]].darkened(0.15))
	tile.add_child(prism)
	_add_decoration(tile, t)
	var number := board.tile_number[t]
	if number > 0:
		tile.add_child(_make_token(number))
	return tile


## Pequeños adornos según el terreno, colocados alrededor de la ficha
## numérica.
func _add_decoration(tile: Node3D, t: int) -> void:
	var spots := [Vector2(-0.5, -0.3), Vector2(0.5, -0.3), Vector2(-0.45, 0.4), Vector2(0.45, 0.4), Vector2(0, -0.62)]
	var rng := RandomNumberGenerator.new()
	rng.seed = t * 977 + 13
	match board.tile_terrain[t]:
		ArchDefs.Terrain.FOREST:
			for p in spots:
				var h := rng.randf_range(0.28, 0.4)
				_add_mesh(tile, _cylinder(0.025, 0.025, 0.08), Color("5b3a1e"), Vector3(p.x, TILE_TOP + 0.04, p.y))
				_add_mesh(tile, _cylinder(0.0, 0.12, h), Color("1f5e2b").lightened(rng.randf_range(0.0, 0.15)), Vector3(p.x, TILE_TOP + 0.08 + h / 2.0, p.y))
		ArchDefs.Terrain.MOUNTAINS:
			for i in 3:
				var p: Vector2 = spots[i] * 1.05
				var h := rng.randf_range(0.35, 0.5)
				_add_mesh(tile, _cylinder(0.0, 0.2, h, 5), Color("6f747d"), Vector3(p.x, TILE_TOP + h / 2.0, p.y))
				_add_mesh(tile, _cylinder(0.0, 0.07, h * 0.3, 5), Color("f2f2f2"), Vector3(p.x, TILE_TOP + h * 0.85, p.y))
		ArchDefs.Terrain.HILLS:
			for i in 4:
				var p: Vector2 = spots[i]
				var hill := SphereMesh.new()
				hill.radius = 0.2
				hill.height = 0.18
				_add_mesh(tile, hill, Color("a8502f"), Vector3(p.x, TILE_TOP, p.y))
		ArchDefs.Terrain.PASTURE:
			for i in 4:
				var p: Vector2 = spots[i]
				var sheep := BoxMesh.new()
				sheep.size = Vector3(0.14, 0.09, 0.09)
				_add_mesh(tile, sheep, Color("f5f5f0"), Vector3(p.x, TILE_TOP + 0.06, p.y))
				var head := BoxMesh.new()
				head.size = Vector3(0.05, 0.05, 0.05)
				_add_mesh(tile, head, Color("2b2b2b"), Vector3(p.x + 0.09, TILE_TOP + 0.09, p.y))
		ArchDefs.Terrain.FIELDS:
			for p in spots:
				_add_mesh(tile, _cylinder(0.03, 0.09, 0.14, 8), Color("d9a520"), Vector3(p.x, TILE_TOP + 0.07, p.y))
		ArchDefs.Terrain.DESERT:
			for i in 2:
				var p: Vector2 = spots[i + 2]
				_add_mesh(tile, _cylinder(0.04, 0.04, 0.26, 8), Color("4f8a3c"), Vector3(p.x, TILE_TOP + 0.13, p.y))
				var dune := SphereMesh.new()
				dune.radius = 0.22
				dune.height = 0.12
				_add_mesh(tile, dune, Color("d8c48a"), Vector3(-p.x, TILE_TOP, -p.y * 0.4))


func _make_token(number: int) -> Node3D:
	var token := Node3D.new()
	token.position.y = TILE_TOP
	_add_mesh(token, _cylinder(0.3, 0.3, 0.04, 24), TOKEN_COLOR, Vector3(0, 0.02, 0))
	var hot := number in ArchDefs.HOT_NUMBERS
	var color := HOT_TEXT if hot else TOKEN_TEXT
	var label := _flat_label(str(number), 44, color)
	label.position = Vector3(0, 0.045, -0.04)
	token.add_child(label)
	var pips := ArchDefs.number_pips(number)
	for i in pips:
		var dot := SphereMesh.new()
		dot.radius = 0.022
		dot.height = 0.02
		_add_mesh(token, dot, color, Vector3((i - (pips - 1) / 2.0) * 0.06, 0.042, 0.15))
	return token


func _make_port(port: Dictionary) -> Node3D:
	var e: int = port["edge"]
	var tile: int = board.grid.edge_tiles[e][0]
	var mid := board.grid.edge_midpoint(e)
	var outward := (mid - board.grid.tile_center(tile)).normalized()
	var pos := mid + outward * 0.62
	var root := Node3D.new()
	for v in board.grid.edge_vertices[e]:
		var corner: Vector2 = board.grid.vertex_positions[v]
		var plank := BoxMesh.new()
		var length := pos.distance_to(corner)
		plank.size = Vector3(length, 0.04, 0.07)
		var inst := _add_mesh(root, plank, Color("9c7a4e"), Vector3((pos.x + corner.x) / 2.0, 0.04, (pos.y + corner.y) / 2.0))
		inst.rotation.y = atan2(-(corner.y - pos.y), corner.x - pos.x)
	var type: int = port["type"]
	var fill: Color = TOKEN_COLOR if type == ArchDefs.PORT_GENERIC else ArchBoardView.RESOURCE_COLORS[type]
	_add_mesh(root, _cylinder(0.24, 0.26, 0.1, 20), Color("5b3a1e"), Vector3(pos.x, 0.05, pos.y))
	_add_mesh(root, _cylinder(0.2, 0.2, 0.02, 20), fill, Vector3(pos.x, 0.11, pos.y))
	var dark := type == ArchDefs.PORT_GENERIC or type == ArchDefs.ResourceType.GRAIN or type == ArchDefs.ResourceType.WOOL
	var label := _flat_label("%d:1" % ArchDefs.port_ratio(type), 30, TOKEN_TEXT if dark else Color.WHITE)
	label.position = Vector3(pos.x, 0.125, pos.y)
	root.add_child(label)
	return root


# --- Piezas ---------------------------------------------------------------------------------

func _sync_pieces() -> void:
	var wanted := {}
	for e in game.edge_owner.size():
		if game.edge_owner[e] != -1:
			wanted["e%d" % e] = [e, -1, game.edge_owner[e]]
	for v in game.vertex_owner.size():
		if game.vertex_owner[v] != -1:
			wanted["v%d" % v] = [v, game.vertex_building[v], game.vertex_owner[v]]
	for key in _pieces.keys():
		if not wanted.has(key) or _pieces[key][1] != wanted[key][1]:
			_pieces[key][0].queue_free()
			_pieces.erase(key)
	for key in wanted:
		if _pieces.has(key):
			continue
		var info: Array = wanted[key]
		var color := game.players[info[2]].color
		var node := _make_road(info[0], color) if info[1] == -1 else _make_building(info[0], info[1], color)
		_pieces_root.add_child(node)
		_pieces[key] = [node, info[1]]
		if _animate:
			_drop_in(node)


func _drop_in(node: Node3D) -> void:
	var target := node.position
	node.position.y += DROP_HEIGHT
	var tween := create_tween()
	tween.tween_property(node, "position", target, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _make_road(e: int, color: Color) -> Node3D:
	var ev: Array = board.grid.edge_vertices[e]
	var a: Vector2 = board.grid.vertex_positions[ev[0]]
	var b: Vector2 = board.grid.vertex_positions[ev[1]]
	var mid := (a + b) / 2.0
	var box := BoxMesh.new()
	box.size = Vector3(0.64, 0.12, 0.16)
	var road := MeshInstance3D.new()
	road.mesh = box
	road.material_override = _material(color)
	road.position = Vector3(mid.x, TILE_TOP + 0.06, mid.y)
	road.rotation.y = atan2(-(b.y - a.y), b.x - a.x)
	return road


func _make_building(v: int, building: int, color: Color) -> Node3D:
	var p: Vector2 = board.grid.vertex_positions[v]
	var root := Node3D.new()
	root.position = Vector3(p.x, TILE_TOP, p.y)
	root.scale = Vector3.ONE * 1.45
	var roof_color := color.darkened(0.25)
	if building == ArchipelagoGame.Building.CITY:
		_add_box(root, Vector3(0.36, 0.17, 0.22), color, Vector3(0.04, 0.085, 0))
		_add_box(root, Vector3(0.15, 0.36, 0.22), color, Vector3(-0.1, 0.18, 0))
		_add_roof(root, Vector3(0.17, 0.12, 0.24), roof_color, Vector3(-0.1, 0.42, 0))
		_add_roof(root, Vector3(0.23, 0.11, 0.24), roof_color, Vector3(0.12, 0.225, 0))
	else:
		_add_box(root, Vector3(0.2, 0.15, 0.2), color, Vector3(0, 0.075, 0))
		_add_roof(root, Vector3(0.23, 0.13, 0.22), roof_color, Vector3(0, 0.215, 0))
	return root


func _sync_bandit() -> void:
	if _bandit == null:
		_bandit = Node3D.new()
		var body := CapsuleMesh.new()
		body.radius = 0.1
		body.height = 0.36
		_add_mesh(_bandit, body, Color("232323"), Vector3(0, 0.18, 0))
		var head := SphereMesh.new()
		head.radius = 0.085
		head.height = 0.17
		_add_mesh(_bandit, head, Color("232323"), Vector3(0, 0.42, 0))
		_pieces_root.add_child(_bandit)
	if board.bandit_tile == _bandit_tile:
		return
	var center := board.grid.tile_center(board.bandit_tile)
	var offset := Vector2(0.0, -0.5) if board.tile_number[board.bandit_tile] > 0 else Vector2.ZERO
	var target := Vector3(center.x + offset.x, TILE_TOP, center.y + offset.y)
	if _animate and _bandit_tile != -1:
		var tween := create_tween()
		var lift := (_bandit.position + target) / 2.0 + Vector3(0, 1.0, 0)
		tween.tween_property(_bandit, "position", lift, 0.25).set_ease(Tween.EASE_OUT)
		tween.tween_property(_bandit, "position", target, 0.25).set_ease(Tween.EASE_IN)
	else:
		_bandit.position = target
	_bandit_tile = board.bandit_tile


# --- Marcadores -----------------------------------------------------------------------------

func _make_marker(kind: Pick, id: int, material: Material) -> Node3D:
	var inst := MeshInstance3D.new()
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		Pick.VERTEX:
			var ring := TorusMesh.new()
			ring.inner_radius = 0.1
			ring.outer_radius = 0.17
			inst.mesh = ring
			var p: Vector2 = board.grid.vertex_positions[id]
			inst.position = Vector3(p.x, TILE_TOP + 0.04, p.y)
		Pick.EDGE:
			var bar := BoxMesh.new()
			bar.size = Vector3(0.5, 0.05, 0.12)
			inst.mesh = bar
			var ev: Array = board.grid.edge_vertices[id]
			var a: Vector2 = board.grid.vertex_positions[ev[0]]
			var b: Vector2 = board.grid.vertex_positions[ev[1]]
			var mid := (a + b) / 2.0
			inst.position = Vector3(mid.x, TILE_TOP + 0.03, mid.y)
			inst.rotation.y = atan2(-(b.y - a.y), b.x - a.x)
		Pick.TILE:
			var ring := TorusMesh.new()
			ring.inner_radius = 0.8
			ring.outer_radius = 0.87
			ring.rings = 6
			ring.ring_segments = 4
			inst.mesh = ring
			var c := board.grid.tile_center(id)
			inst.position = Vector3(c.x, TILE_TOP + 0.02, c.y)
			inst.rotation.y = 0.0  # TorusMesh de 6 lados ya coincide con los hexágonos "pointy-top"
	return inst


# --- Utilidades de mallas y materiales -----------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		_materials[key] = m
	return _materials[key]


func _unshaded(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, alpha)
	m.no_depth_test = false
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _material(color)
	inst.position = pos
	parent.add_child(inst)
	return inst


func _add_box(parent: Node3D, box_size: Vector3, color: Color, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = box_size
	_add_mesh(parent, box, color, pos)


func _add_roof(parent: Node3D, roof_size: Vector3, color: Color, pos: Vector3) -> void:
	var roof := PrismMesh.new()
	roof.size = roof_size
	_add_mesh(parent, roof, color, pos)


func _cylinder(top: float, bottom: float, height: float, segments: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


## Etiqueta tumbada sobre el tablero, legible desde la cámara por defecto.
func _flat_label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0055
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.rotation_degrees.x = -90
	return label


## Prisma hexagonal "pointy-top" con caras planas, de y = 0 a y = height.
func _make_hex_prism(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var corners := HexCoords.corners(Vector2.ZERO, radius)
	var top := Vector3(0, height, 0)
	for i in 6:
		var a := corners[i]
		var b := corners[(i + 1) % 6]
		var a_top := Vector3(a.x, height, a.y)
		var b_top := Vector3(b.x, height, b.y)
		var a_low := Vector3(a.x, 0, a.y)
		var b_low := Vector3(b.x, 0, b.y)
		# Cara superior. Godot considera cara frontal la de vértices en
		# sentido horario vistos desde fuera.
		st.add_vertex(top)
		st.add_vertex(a_top)
		st.add_vertex(b_top)
		# Lateral.
		st.add_vertex(a_top)
		st.add_vertex(b_low)
		st.add_vertex(b_top)
		st.add_vertex(a_top)
		st.add_vertex(a_low)
		st.add_vertex(b_low)
	st.generate_normals()
	return st.commit()


## Hexágono plano "flat-top" (como el mar del tablero 2D).
func _make_flat_hexagon(radius: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in 6:
		var a := Vector2.from_angle(deg_to_rad(60.0 * i)) * radius
		var b := Vector2.from_angle(deg_to_rad(60.0 * (i + 1))) * radius
		st.add_vertex(Vector3(0, y, 0))
		st.add_vertex(Vector3(a.x, y, a.y))
		st.add_vertex(Vector3(b.x, y, b.y))
	return st.commit()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
