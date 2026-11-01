class_name RulesPanel
extends Control
## Ventana con las reglas de un juego (texto BBCode en un archivo).
## Uso: RulesPanel.open(self, "res://games/<id>/rules.txt")

const BACKGROUND := Color(0, 0, 0, 0.6)


static func open(parent: Node, path: String) -> RulesPanel:
	var panel := RulesPanel.new()
	panel._build(path)
	parent.add_child(panel)
	return panel


func _build(path: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = BACKGROUND
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 600)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	var file := FileAccess.open(path, FileAccess.READ)
	text.text = file.get_as_text() if file != null else "No se encontraron las reglas."
	box.add_child(text)
	var close := Button.new()
	close.text = "Cerrar"
	close.pressed.connect(queue_free)
	box.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
