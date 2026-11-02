class_name PuertoPickReveal
extends Control
## Revelación de la elección de cargos: una ficha por jugador que se da la
## vuelta y enseña el cargo y la puja; quien pierde la puja queda tachado.
## Desaparece sola (o con un clic).

signal closed

const TILE := Vector2(96, 120)
const STAGGER := 0.16
const STAY := 1.5

var _tiles: Array[Control] = []
var _title: Label
var _row: HFlowContainer
var _generation := 0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(700, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_title)
	_row = HFlowContainer.new()
	_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("h_separation", 12)
	_row.add_theme_constant_override("v_separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_row)


## entries: [{"name", "color", "office", "bid", "won"}], en orden de cargo.
## `speed` < 1 la acelera (IA rápida).
func reveal(entries: Array, speed: float = 1.0) -> void:
	_generation += 1
	var generation := _generation
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_title.text = "Se revelan los cargos…"
	_title.add_theme_color_override("font_color", Color.WHITE)
	for e in entries:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tile := _OfficeTile.new(e)
		tile.custom_minimum_size = TILE
		tile.pivot_offset = TILE / 2.0
		cell.add_child(tile)
		var label := Label.new()
		label.text = e["name"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(TILE.x, 0)
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(e["color"]).lightened(0.3))
		cell.add_child(label)
		_row.add_child(cell)
		_tiles.append(tile)
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	var stagger := STAGGER * speed
	for i in _tiles.size():
		var tile: Control = _tiles[i]
		var flip := create_tween()
		flip.tween_interval(0.2 + i * stagger)
		flip.tween_property(tile, "scale:x", 0.0, 0.09)
		flip.tween_callback(func() -> void:
			tile.set("face_up", true)
			tile.queue_redraw()
			Sfx.play(&"click", 1.2 if tile.get("won") else 0.75))
		flip.tween_property(tile, "scale:x", 1.0, 0.09)
	var done := 0.2 + _tiles.size() * stagger + 0.2
	get_tree().create_timer(done).timeout.connect(func() -> void:
		if generation != _generation:
			return
		var lost := 0
		for e in entries:
			if not e["won"]:
				lost += 1
		_title.text = "Cargos repartidos" if lost == 0 else "%d sin cargo: eligen vacante" % lost
		_title.add_theme_color_override("font_color", Color("ffd166"))
		Sfx.play(&"reveal"))
	get_tree().create_timer(done + STAY * speed).timeout.connect(_close.bind(generation))


func _close(generation: int) -> void:
	if generation != _generation or not visible:
		return
	_generation += 1
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close(_generation)
		accept_event()


class _OfficeTile extends Control:
	var entry: Dictionary
	var won := true
	var face_up := false

	func _init(p_entry: Dictionary) -> void:
		entry = p_entry
		won = p_entry["won"]
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if not face_up:
			PuertoArt.draw_back(self, rect)
			return
		var color: Color = entry["color"]
		PuertoArt.rounded(self, rect, Color("172b36"), color.lightened(0.2), 9, 3)
		var office: int = entry["office"]
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(8, 22), str(office + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd166"))
		PuertoArt.office_emblem(self, Vector2(size.x / 2, size.y * 0.4), size.x * 0.2, office, PuertoArt.PAPER)
		PuertoArt.paragraph(self, Rect2(4, size.y * 0.6, size.x - 8, size.y * 0.24), PuertoDefs.OFFICE_NAMES[office], 12, PuertoArt.PAPER)
		var bid: int = entry["bid"]
		PuertoArt.coin(self, Vector2(size.x - 16, 16), 11, bid)
		if bid == 0:
			draw_string(font, Vector2(size.x - 27, 21), "0", HORIZONTAL_ALIGNMENT_CENTER, 22, 13, Color("4a3208"))
		if not won:
			draw_rect(rect, Color(0, 0, 0, 0.5))
			draw_line(Vector2(10, 10), size - Vector2(10, 10), Color("ff8a80"), 4.0, true)
			draw_line(Vector2(size.x - 10, 10), Vector2(10, size.y - 10), Color("ff8a80"), 4.0, true)
			draw_string(font, Vector2(0, size.y - 8), "pierde", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color("ff8a80"))
