class_name ConjuraVoteReveal
extends Control
## Revelación de una votación: una carta por jugador que se da la vuelta y
## muestra SÍ o NO, y después el resultado. Desaparece sola (o con un clic).

signal closed

const CARD := Vector2(64, 88)
const FLIP_STAGGER := 0.09
const STAY := 1.6

var _cards: Array[Control] = []
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
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(640, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_title)
	_row = HFlowContainer.new()
	_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("h_separation", 12)
	_row.add_theme_constant_override("v_separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_row)


## entries: [{"name", "color", "yes"}].
func reveal(entries: Array, approved: bool, yes: int, no: int) -> void:
	_generation += 1
	var generation := _generation
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	_title.text = "Votación…"
	_title.add_theme_color_override("font_color", Color.WHITE)
	for e in entries:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := _VoteCard.new(bool(e["yes"]))
		card.custom_minimum_size = CARD
		card.pivot_offset = CARD / 2.0
		cell.add_child(card)
		var label := Label.new()
		label.text = e["name"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(CARD.x + 16, 0)
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(e["color"]).lightened(0.3))
		cell.add_child(label)
		_row.add_child(cell)
		_cards.append(card)
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	for i in _cards.size():
		var card: Control = _cards[i]
		var flip := create_tween()
		flip.tween_interval(0.25 + i * FLIP_STAGGER)
		flip.tween_property(card, "scale:x", 0.0, 0.1)
		flip.tween_callback(func() -> void:
			card.set("face_up", true)
			card.queue_redraw()
			Sfx.play(&"click", 1.3 if card.get("yes") else 0.8))
		flip.tween_property(card, "scale:x", 1.0, 0.1)
	var done := 0.25 + _cards.size() * FLIP_STAGGER + 0.25
	get_tree().create_timer(done).timeout.connect(func() -> void:
		if generation != _generation:
			return
		_title.text = ("¡Aprobado!  %d a %d" if approved else "Rechazado  %d a %d") % [yes, no]
		_title.add_theme_color_override("font_color", Color("8fd694") if approved else Color("ff8a80"))
		Sfx.play(&"approve" if approved else &"reject"))
	get_tree().create_timer(done + STAY).timeout.connect(_close.bind(generation))


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


class _VoteCard extends Control:
	var yes := false
	var face_up := false

	func _init(p_yes: bool) -> void:
		yes = p_yes
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if not face_up:
			ConjuraArt.draw_back(self, rect)
			return
		var color := Color("3f9a4f") if yes else Color("b8404f")
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.border_color = Color.WHITE
		box.set_border_width_all(2)
		box.set_corner_radius_all(7)
		draw_style_box(box, rect)
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.62), "SÍ" if yes else "NO", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color.WHITE)
