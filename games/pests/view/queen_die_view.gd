class_name QueenDieView
extends Control
## El dado de la reina: un dado de colores con las letras U, D, L, R, S, P.
## roll(cara) lo hace girar un momento antes de mostrar la cara; show_face()
## la muestra sin animación (-1 = sin tirar).

signal finished

const D := preload("res://games/pests/logic/pests_defs.gd")
const ROLL_TIME := 0.7
const FLIP_TIME := 0.07

var face := -1
var _shown := -1
var _rolling := 0.0
var _flip := 0.0
var _angle := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func show_face(p_face: int) -> void:
	face = p_face
	_shown = p_face
	_rolling = 0.0
	_angle = 0.0
	queue_redraw()


func roll(p_face: int) -> void:
	face = p_face
	_rolling = ROLL_TIME
	_flip = 0.0
	queue_redraw()


func is_rolling() -> bool:
	return _rolling > 0.0


func _process(delta: float) -> void:
	if _rolling <= 0.0:
		return
	_rolling -= delta
	_flip -= delta
	if _flip <= 0.0:
		_flip = FLIP_TIME
		_shown = _rng.randi_range(0, D.QUEEN_DIE.size() - 1)
		_angle = _rng.randf_range(-0.35, 0.35)
	if _rolling <= 0.0:
		_shown = face
		_angle = 0.0
		finished.emit()
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	draw_set_transform(c, _angle, Vector2.ONE)
	var rect := Rect2(-Vector2.ONE * s * 0.45, Vector2.ONE * s * 0.9)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(s * 0.16))
	style.border_color = Color("1b1b1b")
	style.set_border_width_all(2)
	if _shown < 0:
		style.bg_color = Color(1, 1, 1, 0.08)
		draw_style_box(style, rect)
		draw_set_transform(Vector2.ZERO)
		return
	var f: Dictionary = D.QUEEN_DIE[_shown]
	style.bg_color = D.SPECIES_COLORS[f["species"]]
	draw_style_box(style, rect)
	var font := ThemeDB.fallback_font
	var fs := int(s * 0.55)
	var text: String = f["letter"]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color("1b1b1b"))
	draw_string(font, Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
