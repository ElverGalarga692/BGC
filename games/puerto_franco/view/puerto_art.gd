class_name PuertoArt
extends RefCounted
## Dibujo por código de Puerto Franco (sin imágenes): cartas de edificio,
## reverso, fichas de cargo y casillas del barrio. PuertoCard es el control
## que muestra una carta (pulsable, con estado seleccionado o apagado).

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")

const PAPER := Color("f3ead6")
const INK := Color("2a2320")
const BACK := Color("1d4a5c")
const BACK_LINE := Color("9fc7c9")
const LONJA := Color("c9b48a")

## Letra corta de cada gremio (se ve en las casillas pequeñas).
const GUILD_SHORT := {
	PuertoDefs.Guild.TRADE: "C",
	PuertoDefs.Guild.SEA: "M",
	PuertoDefs.Guild.CRAFT: "O",
	PuertoDefs.Guild.ARTS: "A",
	PuertoDefs.Guild.WONDER: "★",
}

## Texto de cada maravilla.
const WONDER_TEXT := {
	PuertoDefs.Wonder.PLAZA: "+2 por cada edificio vecino",
	PuertoDefs.Wonder.CUSTOMS: "+1 moneda al cobrar monedas",
	PuertoDefs.Wonder.SHIPYARD_ROYAL: "Al cobrar del muelle, roba 1 más",
	PuertoDefs.Wonder.GARDENS: "Cuenta como cualquier gremio en los grupos",
	PuertoDefs.Wonder.LIGHTHOUSE: "+1 punto por cada 2 monedas al final",
}


static func font() -> Font:
	return ThemeDB.fallback_font


static func guild_color(guild: int) -> Color:
	return D.GUILD_COLORS.get(guild, Color.GRAY)


static func card_text(card: int) -> String:
	var wonder := D.wonder_of(card)
	if wonder == PuertoDefs.Wonder.GUILD_HALL:
		return "+1 por cada edificio de %s" % D.GUILD_NAMES[D.BUILDINGS[card]["guild_bonus"]]
	return WONDER_TEXT.get(wonder, "")


static func rounded(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, radius: float, width: float = 2.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(width))
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	ci.draw_style_box(box, rect)


static func text(ci: CanvasItem, pos: Vector2, width: float, value: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_string(font(), pos, value, align, width, size, color)


## Texto en varias líneas, centrado, dentro de `rect`.
static func paragraph(ci: CanvasItem, rect: Rect2, value: String, size: int, color: Color) -> void:
	var lines := font().get_multiline_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size)
	var y := rect.position.y + maxf(0.0, (rect.size.y - lines.y) / 2.0) + size
	ci.draw_multiline_string(font(), Vector2(rect.position.x, y), value, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, -1, color)


## Moneda con un número.
static func coin(ci: CanvasItem, center: Vector2, radius: float, value: int) -> void:
	ci.draw_circle(center, radius, Color("e8b94a"))
	ci.draw_arc(center, radius * 0.82, 0, TAU, 24, Color("a77a1f"), maxf(1.0, radius * 0.12), true)
	var size := int(radius * 1.2)
	text(ci, center + Vector2(-radius, size * 0.36), radius * 2.0, str(value), size, Color("4a3208"))


## Silueta sencilla de un edificio según su gremio (para la carta).
static func building_icon(ci: CanvasItem, rect: Rect2, guild: int, color: Color) -> void:
	var c := rect.get_center()
	var w := rect.size.x
	var h := rect.size.y
	var base := rect.position.y + h
	match guild:
		PuertoDefs.Guild.TRADE:  # tienda con toldo
			ci.draw_rect(Rect2(c.x - w * 0.32, base - h * 0.55, w * 0.64, h * 0.55), color)
			var stripes := 4
			for i in stripes:
				var x := c.x - w * 0.38 + i * w * 0.76 / stripes
				var awning := PackedVector2Array([Vector2(x, base - h * 0.55), Vector2(x + w * 0.76 / stripes, base - h * 0.55), Vector2(x + w * 0.76 / stripes, base - h * 0.42), Vector2(x, base - h * 0.42)])
				ci.draw_colored_polygon(awning, PAPER if i % 2 == 0 else color.lightened(0.35))
			ci.draw_rect(Rect2(c.x - w * 0.08, base - h * 0.3, w * 0.16, h * 0.3), PAPER)
		PuertoDefs.Guild.SEA:  # barca con vela
			var hull := PackedVector2Array([Vector2(c.x - w * 0.4, base - h * 0.25), Vector2(c.x + w * 0.4, base - h * 0.25), Vector2(c.x + w * 0.28, base), Vector2(c.x - w * 0.28, base)])
			ci.draw_colored_polygon(hull, color)
			ci.draw_line(Vector2(c.x, base - h * 0.25), Vector2(c.x, rect.position.y), color.darkened(0.3), maxf(1.0, w * 0.04))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x + w * 0.03, rect.position.y + h * 0.05), Vector2(c.x + w * 0.32, base - h * 0.32), Vector2(c.x + w * 0.03, base - h * 0.32)]), color.lightened(0.45))
		PuertoDefs.Guild.CRAFT:  # taller con chimenea
			ci.draw_rect(Rect2(c.x - w * 0.34, base - h * 0.5, w * 0.68, h * 0.5), color)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.38, base - h * 0.5), Vector2(c.x + w * 0.38, base - h * 0.5), Vector2(c.x, base - h * 0.78)]), color.darkened(0.2))
			ci.draw_rect(Rect2(c.x + w * 0.14, base - h * 0.95, w * 0.12, h * 0.35), color.darkened(0.3))
			ci.draw_circle(Vector2(c.x + w * 0.24, rect.position.y + h * 0.02), w * 0.07, Color(0.6, 0.6, 0.6, 0.7))
		PuertoDefs.Guild.ARTS:  # templete con columnas
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.4, base - h * 0.62), Vector2(c.x + w * 0.4, base - h * 0.62), Vector2(c.x, base - h * 0.92)]), color.darkened(0.15))
			for i in 4:
				var x := c.x - w * 0.3 + i * w * 0.2
				ci.draw_rect(Rect2(x - w * 0.04, base - h * 0.6, w * 0.08, h * 0.5), color)
			ci.draw_rect(Rect2(c.x - w * 0.42, base - h * 0.1, w * 0.84, h * 0.1), color.darkened(0.25))
		_:  # maravilla: torre con estrella
			ci.draw_rect(Rect2(c.x - w * 0.16, base - h * 0.7, w * 0.32, h * 0.7), color)
			ci.draw_rect(Rect2(c.x - w * 0.36, base - h * 0.35, w * 0.72, h * 0.35), color.darkened(0.15))
			star(ci, Vector2(c.x, rect.position.y + h * 0.14), w * 0.16, Color("ffd166"))


static func star(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	ci.draw_colored_polygon(points, color)


## Carta de edificio completa en `rect`.
static func draw_card(ci: CanvasItem, rect: Rect2, card: int) -> void:
	if card < 0:
		draw_back(ci, rect)
		return
	var guild := D.guild_of(card)
	var color := guild_color(guild)
	var radius := rect.size.x * 0.1
	rounded(ci, rect, color.darkened(0.2), color.lightened(0.3), radius, 2)
	var inner := rect.grow(-rect.size.x * 0.06)
	rounded(ci, inner, PAPER, color.darkened(0.1), radius * 0.6, 1)
	var title := int(clampf(rect.size.x * 0.12, 8, 16))
	# Coste
	var coin_r := rect.size.x * 0.13
	coin(ci, inner.position + Vector2(coin_r + 2, coin_r + 2), coin_r, D.cost_of(card))
	# Gremio
	text(ci, inner.position + Vector2(0, title + 3), inner.size.x - 5, D.GUILD_NAMES[guild], int(title * 0.8), color.darkened(0.35), HORIZONTAL_ALIGNMENT_RIGHT)
	# Dibujo
	var art := Rect2(inner.position + Vector2(inner.size.x * 0.2, inner.size.y * 0.22), Vector2(inner.size.x * 0.6, inner.size.y * 0.36))
	building_icon(ci, art, guild, color)
	# Nombre
	var name_rect := Rect2(inner.position + Vector2(2, inner.size.y * 0.6), Vector2(inner.size.x - 4, inner.size.y * 0.18))
	paragraph(ci, name_rect, D.card_name(card), title, INK)
	var effect := card_text(card)
	if effect != "":
		var effect_rect := Rect2(inner.position + Vector2(3, inner.size.y * 0.78), Vector2(inner.size.x - 6, inner.size.y * 0.21))
		paragraph(ci, effect_rect, effect, int(title * 0.72), INK.lightened(0.25))


static func draw_back(ci: CanvasItem, rect: Rect2) -> void:
	var radius := rect.size.x * 0.1
	rounded(ci, rect, BACK, BACK_LINE, radius, 2)
	var c := rect.get_center()
	var r := rect.size.x * 0.28
	ci.draw_polyline(HexCoords.corners(c, r) + PackedVector2Array([HexCoords.corner(c, r, 0)]), BACK_LINE, 2.0, true)
	ci.draw_polyline(HexCoords.corners(c, r * 0.55) + PackedVector2Array([HexCoords.corner(c, r * 0.55, 0)]), BACK_LINE, 1.5, true)


## Una carta como control: se puede pulsar, seleccionar y apagar.
class PuertoCard:
	extends Control

	signal pressed

	var card := -1
	var selected := false
	var dimmed := false
	var clickable := false
	var _hover := false

	func _init(p_card: int = -1, p_size: Vector2 = Vector2(92, 128)) -> void:
		card = p_card
		custom_minimum_size = p_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())
		if card >= 0:
			tooltip_text = "%s (%s, cuesta %d)%s" % [D.card_name(card), D.GUILD_NAMES[D.guild_of(card)], D.cost_of(card), ("\n" + PuertoArt.card_text(card)) if PuertoArt.card_text(card) != "" else ""]

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if selected:
			rect.position.y -= 8
		PuertoArt.draw_card(self, rect, card)
		if selected:
			PuertoArt.rounded(self, rect.grow(2), Color.TRANSPARENT, Color("ffd166"), size.x * 0.1, 3)
		elif _hover and clickable:
			PuertoArt.rounded(self, rect.grow(1), Color.TRANSPARENT, Color(1, 1, 1, 0.8), size.x * 0.1, 2)
		if dimmed:
			PuertoArt.rounded(self, rect, Color(0, 0, 0, 0.45), Color.TRANSPARENT, size.x * 0.1, 0)

	func _gui_input(event: InputEvent) -> void:
		if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()
