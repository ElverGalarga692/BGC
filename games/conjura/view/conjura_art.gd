class_name ConjuraArt
extends RefCounted
## Ilustraciones de La Conjura dibujadas por código (sin imágenes): cartas
## de edicto, cartas de rol y emblemas. Se usan en el tablero, en la
## ventana privada y en la pantalla final.

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Edict := ConjuraDefs.Edict
const Role := ConjuraDefs.Role

const PARCHMENT := Color("efe2c4")
const INK := Color("2b2118")
const GOLD := Color("e3b34c")

enum Emblem { SHIELD, CRESCENT, SCALES, CROWN, DAGGER }


static func _font() -> Font:
	return ThemeDB.fallback_font


static func _rounded(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, radius: float, width: float = 2.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(width))
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	ci.draw_style_box(box, rect)


static func edict_emblem(edict: int) -> int:
	match edict:
		Edict.GUARDIA: return Emblem.SHIELD
		Edict.SOMBRA: return Emblem.CRESCENT
	return Emblem.SCALES


## Carta de edicto: marco del color de la facción, pergamino y emblema.
static func draw_edict(ci: CanvasItem, rect: Rect2, edict: int, show_label: bool = true, glow: float = 0.0) -> void:
	var color := D.edict_color(edict)
	var radius := rect.size.x * 0.1
	if glow > 0.0:
		_rounded(ci, rect.grow(6.0 * glow), Color(1, 1, 1, 0.45 * glow), Color.TRANSPARENT, radius + 4, 0)
	_rounded(ci, rect, color.darkened(0.35), color.lightened(0.25), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.09)
	_rounded(ci, inner, PARCHMENT, color.darkened(0.1), radius * 0.6, 1)
	var label_h := rect.size.y * 0.2 if show_label else 0.0
	var art := Rect2(inner.position, Vector2(inner.size.x, inner.size.y - label_h))
	draw_emblem(ci, art.get_center(), minf(art.size.x, art.size.y) * 0.32, edict_emblem(edict), color.darkened(0.15), PARCHMENT)
	if show_label:
		var text: String = D.EDICT_SHORT[edict].to_upper()
		_fit_text(ci, Rect2(inner.position.x, inner.end.y - label_h * 0.32, inner.size.x, 0), text, int(clampf(rect.size.x * 0.15, 9, 20)), color.darkened(0.45))


## Texto centrado en la línea base `line.position.y`, encogido hasta caber
## en `line.size.x`.
static func _fit_text(ci: CanvasItem, line: Rect2, text: String, max_size: int, color: Color) -> void:
	var font_size := max_size
	while font_size > 6 and _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > line.size.x - 4:
		font_size -= 1
	ci.draw_string(_font(), line.position, text, HORIZONTAL_ALIGNMENT_CENTER, line.size.x, font_size, color)


## Reverso de una carta (para las votaciones).
static func draw_back(ci: CanvasItem, rect: Rect2) -> void:
	var radius := rect.size.x * 0.1
	_rounded(ci, rect, Color("3a2d4a"), GOLD.darkened(0.2), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.12)
	_rounded(ci, inner, Color("2a2036"), Color(GOLD, 0.5), radius * 0.6, 1)
	draw_emblem(ci, inner.get_center(), inner.size.x * 0.28, Emblem.CROWN, Color(GOLD, 0.7), Color("2a2036"))


## Carta de rol.
static func draw_role(ci: CanvasItem, rect: Rect2, role: int) -> void:
	var color := D.faction_color(D.faction_of(role))
	var radius := rect.size.x * 0.08
	_rounded(ci, rect, color.darkened(0.45), GOLD if role == Role.USURPADOR else color.lightened(0.3), radius, 3)
	var inner := rect.grow(-rect.size.x * 0.08)
	_rounded(ci, inner, color.darkened(0.15), Color(1, 1, 1, 0.25), radius * 0.6, 1)
	var c := inner.get_center() - Vector2(0, inner.size.y * 0.08)
	var r := inner.size.x * 0.3
	match role:
		Role.GUARDIA:
			draw_emblem(ci, c, r, Emblem.SHIELD, PARCHMENT, color.darkened(0.15))
		Role.SOMBRA:
			draw_emblem(ci, c, r, Emblem.CRESCENT, PARCHMENT, color.darkened(0.15))
			draw_emblem(ci, c + Vector2(r * 0.35, r * 0.15), r * 0.75, Emblem.DAGGER, GOLD, color.darkened(0.15))
		_:
			draw_emblem(ci, c + Vector2(0, r * 0.25), r * 0.95, Emblem.CRESCENT, PARCHMENT, color.darkened(0.15))
			draw_emblem(ci, c - Vector2(0, r * 0.55), r * 0.8, Emblem.CROWN, GOLD, color.darkened(0.15))
	var name: String = {Role.GUARDIA: "GUARDIA", Role.SOMBRA: "SOMBRA", Role.USURPADOR: "USURPADOR"}[role]
	_fit_text(ci, Rect2(inner.position.x, inner.end.y - inner.size.y * 0.08, inner.size.x, 0), name, int(clampf(rect.size.x * 0.13, 9, 22)), PARCHMENT)


## Emblema centrado en `c` con radio aproximado `r`. `bg` es el color del
## fondo (para recortar la luna).
static func draw_emblem(ci: CanvasItem, c: Vector2, r: float, emblem: int, color: Color, bg: Color) -> void:
	match emblem:
		Emblem.SHIELD:
			var pts := PackedVector2Array([
				c + Vector2(-r, -r * 0.95), c + Vector2(r, -r * 0.95), c + Vector2(r, 0.1 * r),
				c + Vector2(r * 0.55, r * 0.75), c + Vector2(0, r * 1.1), c + Vector2(-r * 0.55, r * 0.75), c + Vector2(-r, 0.1 * r),
			])
			ci.draw_colored_polygon(pts, color)
			# Cruz del escudo.
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.8), bg, maxf(2.0, r * 0.16))
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.2), c + Vector2(r * 0.7, -r * 0.2), bg, maxf(2.0, r * 0.16))
		Emblem.CRESCENT:
			ci.draw_circle(c, r, color)
			ci.draw_circle(c + Vector2(r * 0.42, -r * 0.22), r * 0.84, bg)
		Emblem.SCALES:
			var w := maxf(1.5, r * 0.1)
			ci.draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.85), color, w)
			ci.draw_line(c + Vector2(-r, -r * 0.6), c + Vector2(r, -r * 0.6), color, w)
			ci.draw_line(c + Vector2(-r * 0.5, r * 0.85), c + Vector2(r * 0.5, r * 0.85), color, w)
			for side in [-1.0, 1.0]:
				var top := c + Vector2(side * r * 0.85, -r * 0.6)
				ci.draw_line(top, top + Vector2(-r * 0.3, r * 0.6), color, w * 0.6)
				ci.draw_line(top, top + Vector2(r * 0.3, r * 0.6), color, w * 0.6)
				ci.draw_arc(top + Vector2(0, r * 0.6), r * 0.32, 0, PI, 12, color, w)
		Emblem.CROWN:
			var pts := PackedVector2Array([
				c + Vector2(-r, r * 0.55), c + Vector2(-r, -r * 0.45), c + Vector2(-r * 0.5, r * 0.05),
				c + Vector2(0, -r * 0.7), c + Vector2(r * 0.5, r * 0.05), c + Vector2(r, -r * 0.45), c + Vector2(r, r * 0.55),
			])
			ci.draw_colored_polygon(pts, color)
			for x in [-1.0, 0.0, 1.0]:
				var y := -0.7 if x == 0.0 else -0.45
				ci.draw_circle(c + Vector2(x * r, y * r - r * 0.12), r * 0.13, color)
		Emblem.DAGGER:
			var blade := PackedVector2Array([c + Vector2(-r * 0.12, -r * 0.2), c + Vector2(r * 0.12, -r * 0.2), c + Vector2(0, -r * 1.1)])
			ci.draw_colored_polygon(blade, color)
			ci.draw_line(c + Vector2(-r * 0.35, -r * 0.2), c + Vector2(r * 0.35, -r * 0.2), color, maxf(2.0, r * 0.12))
			ci.draw_line(c + Vector2(0, -r * 0.2), c + Vector2(0, r * 0.3), color.darkened(0.3), maxf(2.0, r * 0.15))


## Control con una carta de edicto dibujada (botón si se le da `on_pick`).
class EdictCard extends Button:
	var edict := 0
	var caption := ""

	func _init(p_edict: int, p_caption: String = "", card_size: Vector2 = Vector2(120, 168)) -> void:
		edict = p_edict
		caption = p_caption
		flat = true
		custom_minimum_size = card_size + Vector2(0, 26 if p_caption != "" else 0)
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := is_hovered() and not disabled
		var lift := -6.0 if hover else 0.0
		var card := Rect2(Vector2(0, 6 + lift), Vector2(size.x, size.y - 6 - (26 if caption != "" else 0)))
		ConjuraArt.draw_edict(self, card, edict, true, 0.8 if hover else 0.0)
		if caption != "":
			draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color.WHITE if hover else Color(1, 1, 1, 0.75))


## Control con una carta de rol dibujada.
class RoleCard extends Control:
	var role := 0

	func _init(p_role: int, card_size: Vector2 = Vector2(96, 134)) -> void:
		role = p_role
		custom_minimum_size = card_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		ConjuraArt.draw_role(self, Rect2(Vector2.ZERO, size), role)
