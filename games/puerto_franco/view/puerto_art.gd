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
	if value > 0:
		var size := int(radius * 1.2)
		text(ci, center + Vector2(-radius, size * 0.36), radius * 2.0, str(value), size, Color("4a3208"))


## Fachada con tejado y ventanas: `floors` filas de ventanas.
static func house(ci: CanvasItem, rect: Rect2, wall: Color, roof: Color, floors: int, cols: int, pointed: bool = true) -> void:
	ci.draw_rect(rect, wall)
	if pointed:
		var peak := rect.size.y * 0.35
		ci.draw_colored_polygon(PackedVector2Array([rect.position + Vector2(-rect.size.x * 0.08, 0), rect.position + Vector2(rect.size.x * 1.08, 0), rect.position + Vector2(rect.size.x * 0.5, -peak)]), roof)
	else:
		ci.draw_rect(Rect2(rect.position + Vector2(-rect.size.x * 0.06, -rect.size.y * 0.08), Vector2(rect.size.x * 1.12, rect.size.y * 0.08)), roof)
	var win := Color(PAPER, 0.9)
	var rows := maxi(1, floors)
	var cell := Vector2(rect.size.x / (cols * 2 + 1), rect.size.y / (rows * 2 + 1.5))
	for r in rows:
		for c in cols:
			var pos := rect.position + Vector2(cell.x * (c * 2 + 1), cell.y * (r * 2 + 1))
			ci.draw_rect(Rect2(pos, cell), win)


## Dibujo de un edificio según su gremio y su coste (cuanto más caro, más
## grande y con más detalle). Se usa en las cartas y en las casillas.
static func building_icon(ci: CanvasItem, rect: Rect2, guild: int, color: Color, cost: int = 2) -> void:
	var c := rect.get_center()
	var w := rect.size.x
	var h := rect.size.y
	var base := rect.position.y + h
	var k := clampf(0.45 + 0.13 * cost, 0.5, 1.0)  # altura relativa
	var dark := color.darkened(0.3)
	match guild:
		PuertoDefs.Guild.TRADE:  # tienda con toldo; las caras, de varios pisos
			var body := Rect2(c.x - w * 0.34, base - h * 0.62 * k, w * 0.68, h * 0.62 * k)
			house(ci, body, color.lightened(0.15), dark, maxi(0, cost - 2), 2 if cost < 5 else 3, cost < 5)
			var stripes := 4
			var aw_y := base - h * 0.3
			for i in stripes:
				var x := body.position.x - w * 0.04 + i * (body.size.x + w * 0.08) / stripes
				var sw := (body.size.x + w * 0.08) / stripes
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x, aw_y), Vector2(x + sw, aw_y), Vector2(x + sw, aw_y + h * 0.1), Vector2(x, aw_y + h * 0.1)]), PAPER if i % 2 == 0 else Color("c4566b"))
			ci.draw_rect(Rect2(c.x - w * 0.07, base - h * 0.18, w * 0.14, h * 0.18), dark)
			if cost >= 4:
				coin(ci, Vector2(c.x, body.position.y + body.size.y * 0.2), w * 0.08, 0)
		PuertoDefs.Guild.SEA:  # barca; las caras, almacén con grúa o faro de puerto
			if cost >= 3:
				var shed := Rect2(c.x - w * 0.4, base - h * 0.5 * k, w * 0.5, h * 0.5 * k)
				house(ci, shed, color.lightened(0.2), dark, cost - 3, 1)
				ci.draw_line(Vector2(c.x + w * 0.22, base - h * 0.15), Vector2(c.x + w * 0.22, base - h * 0.8 * k), dark, maxf(1.0, w * 0.04))
				ci.draw_line(Vector2(c.x + w * 0.22, base - h * 0.8 * k), Vector2(c.x + w * 0.44, base - h * 0.7 * k), dark, maxf(1.0, w * 0.03))
			var boat_w := w * (0.5 if cost >= 3 else 0.8)
			var bx := c.x + (w * 0.18 if cost >= 3 else 0.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(bx - boat_w / 2, base - h * 0.18), Vector2(bx + boat_w / 2, base - h * 0.18), Vector2(bx + boat_w * 0.35, base), Vector2(bx - boat_w * 0.35, base)]), color)
			if cost == 2:
				for i in 2:
					ci.draw_rect(Rect2(c.x - w * 0.42 + i * w * 0.13, base - h * 0.3, w * 0.11, h * 0.11), Color("8a5a2b"))
			if cost < 3:
				ci.draw_line(Vector2(bx, base - h * 0.18), Vector2(bx, base - h * 0.85), dark, maxf(1.0, w * 0.035))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(bx + w * 0.02, base - h * 0.82), Vector2(bx + w * 0.3, base - h * 0.25), Vector2(bx + w * 0.02, base - h * 0.25)]), color.lightened(0.5))
		PuertoDefs.Guild.CRAFT:  # taller con chimenea humeante
			var body := Rect2(c.x - w * 0.36, base - h * 0.55 * k, w * 0.72, h * 0.55 * k)
			ci.draw_rect(Rect2(c.x + w * 0.14, body.position.y - h * 0.32, w * 0.12, h * 0.4), dark)
			house(ci, body, color.lightened(0.1), dark, maxi(0, cost - 2), 2)
			for i in mini(cost, 3):
				ci.draw_circle(Vector2(c.x + w * (0.2 + 0.06 * i), body.position.y - h * (0.38 + 0.1 * i)), w * (0.05 + 0.02 * i), Color(0.75, 0.75, 0.75, 0.6))
			ci.draw_rect(Rect2(c.x - w * 0.1, base - h * 0.2, w * 0.2, h * 0.2), dark)
		PuertoDefs.Guild.ARTS:  # templete; las caras, con cúpula
			var top := base - h * 0.62 * k
			var columns := 2 + mini(cost, 4)
			for i in columns:
				var x := c.x - w * 0.34 + i * w * 0.68 / (columns - 1)
				ci.draw_rect(Rect2(x - w * 0.035, top, w * 0.07, base - h * 0.1 - top), color.lightened(0.2))
			ci.draw_rect(Rect2(c.x - w * 0.42, base - h * 0.1, w * 0.84, h * 0.1), dark)
			if cost >= 4:
				ci.draw_rect(Rect2(c.x - w * 0.4, top - h * 0.08, w * 0.8, h * 0.08), dark)
				ci.draw_circle(Vector2(c.x, top - h * 0.08), w * 0.22, color)
				ci.draw_rect(Rect2(c.x - w * 0.24, top - h * 0.08, w * 0.48, h * 0.1), dark)
			else:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.42, top), Vector2(c.x + w * 0.42, top), Vector2(c.x, top - h * 0.22)]), dark)
		_:  # maravilla genérica: torre con estrella
			ci.draw_rect(Rect2(c.x - w * 0.36, base - h * 0.35, w * 0.72, h * 0.35), color.darkened(0.15))
			ci.draw_rect(Rect2(c.x - w * 0.16, base - h * 0.78, w * 0.32, h * 0.78), color)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.2, base - h * 0.78), Vector2(c.x + w * 0.2, base - h * 0.78), Vector2(c.x, base - h * 0.95)]), color.darkened(0.25))
			star(ci, Vector2(c.x, rect.position.y + h * 0.08), w * 0.13, Color("ffd166"))


## Dibujo propio de cada maravilla.
static func wonder_icon(ci: CanvasItem, rect: Rect2, card: int) -> void:
	var c := rect.get_center()
	var w := rect.size.x
	var h := rect.size.y
	var base := rect.position.y + h
	var green := guild_color(PuertoDefs.Guild.WONDER)
	var dark := green.darkened(0.35)
	var gold := Color("ffd166")
	match D.wonder_of(card):
		PuertoDefs.Wonder.GUILD_HALL:
			var bonus: int = D.BUILDINGS[card]["guild_bonus"]
			var col := guild_color(bonus)
			# Edificio grande del gremio con un estandarte verde.
			building_icon(ci, Rect2(rect.position + Vector2(w * 0.05, h * 0.1), Vector2(w * 0.9, h * 0.9)), bonus, col, 5)
			ci.draw_line(Vector2(rect.position.x + w * 0.1, base), Vector2(rect.position.x + w * 0.1, rect.position.y), dark, maxf(1.0, w * 0.03))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(rect.position.x + w * 0.1, rect.position.y), Vector2(rect.position.x + w * 0.32, rect.position.y + h * 0.1), Vector2(rect.position.x + w * 0.1, rect.position.y + h * 0.2)]), green)
		PuertoDefs.Wonder.PLAZA:  # plaza con fuente y casas alrededor
			ci.draw_rect(Rect2(c.x - w * 0.45, base - h * 0.2, w * 0.9, h * 0.2), Color("c9b48a"))
			house(ci, Rect2(c.x - w * 0.45, base - h * 0.62, w * 0.25, h * 0.42), green.lightened(0.2), dark, 2, 1)
			house(ci, Rect2(c.x + w * 0.2, base - h * 0.62, w * 0.25, h * 0.42), green.lightened(0.2), dark, 2, 1)
			ci.draw_rect(Rect2(c.x - w * 0.14, base - h * 0.3, w * 0.28, h * 0.12), dark)
			ci.draw_line(Vector2(c.x, base - h * 0.3), Vector2(c.x, base - h * 0.55), Color("9fd0e8"), maxf(1.0, w * 0.04))
			ci.draw_arc(Vector2(c.x - w * 0.08, base - h * 0.55), w * 0.08, PI, TAU, 8, Color("9fd0e8"), maxf(1.0, w * 0.025))
			ci.draw_arc(Vector2(c.x + w * 0.08, base - h * 0.55), w * 0.08, PI, TAU, 8, Color("9fd0e8"), maxf(1.0, w * 0.025))
		PuertoDefs.Wonder.CUSTOMS:  # aduana: edificio con balanza
			house(ci, Rect2(c.x - w * 0.38, base - h * 0.55, w * 0.76, h * 0.55), green.lightened(0.15), dark, 2, 3, false)
			var top := Vector2(c.x, rect.position.y + h * 0.1)
			ci.draw_line(top, top + Vector2(0, h * 0.28), gold, maxf(1.0, w * 0.03))
			ci.draw_line(top + Vector2(-w * 0.25, h * 0.05), top + Vector2(w * 0.25, h * 0.05), gold, maxf(1.0, w * 0.03))
			coin(ci, top + Vector2(-w * 0.25, h * 0.16), w * 0.07, 0)
			coin(ci, top + Vector2(w * 0.25, h * 0.16), w * 0.07, 0)
		PuertoDefs.Wonder.SHIPYARD_ROYAL:  # gran barco en grada con grúa
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.45, base - h * 0.3), Vector2(c.x + w * 0.45, base - h * 0.3), Vector2(c.x + w * 0.3, base - h * 0.05), Vector2(c.x - w * 0.3, base - h * 0.05)]), Color("8a5a2b"))
			for i in 3:
				var x := c.x - w * 0.22 + i * w * 0.22
				ci.draw_line(Vector2(x, base - h * 0.3), Vector2(x, rect.position.y + h * (0.15 + 0.08 * (i % 2))), dark, maxf(1.0, w * 0.03))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x + w * 0.01, rect.position.y + h * 0.2), Vector2(x + w * 0.16, base - h * 0.4), Vector2(x + w * 0.01, base - h * 0.4)]), PAPER.darkened(0.08))
			ci.draw_rect(Rect2(c.x - w * 0.48, base - h * 0.05, w * 0.96, h * 0.05), dark)
			star(ci, Vector2(c.x - w * 0.22, rect.position.y + h * 0.08), w * 0.08, gold)
		PuertoDefs.Wonder.GARDENS:  # árboles y setos
			ci.draw_rect(Rect2(c.x - w * 0.45, base - h * 0.12, w * 0.9, h * 0.12), Color("5a8f3e"))
			for i in 3:
				var x := c.x - w * 0.3 + i * w * 0.3
				var r := w * (0.16 if i == 1 else 0.12)
				ci.draw_rect(Rect2(x - w * 0.025, base - h * 0.4, w * 0.05, h * 0.3), Color("6b4a2b"))
				ci.draw_circle(Vector2(x, base - h * (0.55 if i == 1 else 0.45)), r, Color("4f9a4a"))
				ci.draw_circle(Vector2(x + r * 0.3, base - h * (0.6 if i == 1 else 0.5)), r * 0.6, Color("6fbf5a"))
			for i in 4:
				ci.draw_circle(Vector2(c.x - w * 0.36 + i * w * 0.24, base - h * 0.14), w * 0.035, Color("e07aa8"))
		PuertoDefs.Wonder.LIGHTHOUSE:  # faro con haz de luz
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x, rect.position.y + h * 0.12), Vector2(c.x + w * 0.5, rect.position.y), Vector2(c.x + w * 0.5, rect.position.y + h * 0.28)]), Color(1, 0.9, 0.5, 0.45))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x, rect.position.y + h * 0.12), Vector2(c.x - w * 0.5, rect.position.y), Vector2(c.x - w * 0.5, rect.position.y + h * 0.28)]), Color(1, 0.9, 0.5, 0.45))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.18, base), Vector2(c.x + w * 0.18, base), Vector2(c.x + w * 0.1, rect.position.y + h * 0.22), Vector2(c.x - w * 0.1, rect.position.y + h * 0.22)]), PAPER.darkened(0.05))
			for i in 3:
				var y := base - h * (0.2 + i * 0.22)
				ci.draw_rect(Rect2(c.x - w * (0.17 - i * 0.025), y, w * (0.34 - i * 0.05), h * 0.07), Color("b8404f"))
			ci.draw_rect(Rect2(c.x - w * 0.12, rect.position.y + h * 0.06, w * 0.24, h * 0.14), gold)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.14, rect.position.y + h * 0.06), Vector2(c.x + w * 0.14, rect.position.y + h * 0.06), Vector2(c.x, rect.position.y - h * 0.04)]), dark)
		_:
			building_icon(ci, rect, PuertoDefs.Guild.WONDER, green, 5)


## Emblema de un cargo (para las fichas y la revelación).
static func office_emblem(ci: CanvasItem, center: Vector2, r: float, office: int, color: Color) -> void:
	var lw := maxf(1.5, r * 0.14)
	match office:
		PuertoDefs.Office.HARBOR:  # ancla
			ci.draw_line(center + Vector2(0, -r * 0.8), center + Vector2(0, r * 0.7), color, lw)
			ci.draw_arc(center + Vector2(0, r * 0.1), r * 0.6, 0.15 * PI, 0.85 * PI, 16, color, lw)
			ci.draw_line(center + Vector2(-r * 0.35, -r * 0.45), center + Vector2(r * 0.35, -r * 0.45), color, lw)
			ci.draw_arc(center + Vector2(0, -r * 0.85), r * 0.15, 0, TAU, 12, color, lw * 0.7)
		PuertoDefs.Office.SMUGGLER:  # antifaz
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.9, -r * 0.25), center + Vector2(r * 0.9, -r * 0.25), center + Vector2(r * 0.7, r * 0.3), center + Vector2(0, r * 0.1), center + Vector2(-r * 0.7, r * 0.3)]), color)
			ci.draw_circle(center + Vector2(-r * 0.4, 0), r * 0.15, Color(0, 0, 0, 0.7))
			ci.draw_circle(center + Vector2(r * 0.4, 0), r * 0.15, Color(0, 0, 0, 0.7))
		PuertoDefs.Office.COLLECTOR:  # pila de monedas
			for i in 3:
				var y := center.y + r * 0.5 - i * r * 0.35
				ci.draw_rect(Rect2(center.x - r * 0.55, y - r * 0.15, r * 1.1, r * 0.28), color)
				ci.draw_rect(Rect2(center.x - r * 0.55, y - r * 0.15, r * 1.1, r * 0.28), color.darkened(0.4), false, lw * 0.5)
		PuertoDefs.Office.PLANNER:  # compás
			ci.draw_line(center + Vector2(0, -r * 0.8), center + Vector2(-r * 0.55, r * 0.8), color, lw)
			ci.draw_line(center + Vector2(0, -r * 0.8), center + Vector2(r * 0.55, r * 0.8), color, lw)
			ci.draw_arc(center + Vector2(0, -r * 0.8), r * 1.1, 0.38 * PI, 0.62 * PI, 12, color, lw * 0.6)
			ci.draw_circle(center + Vector2(0, -r * 0.8), r * 0.15, color)
		PuertoDefs.Office.BUILDER:  # martillo
			ci.draw_line(center + Vector2(-r * 0.6, r * 0.75), center + Vector2(r * 0.3, -r * 0.3), color, lw * 1.2)
			var head := PackedVector2Array([center + Vector2(-r * 0.05, -r * 0.75), center + Vector2(r * 0.85, r * 0.15), center + Vector2(r * 0.6, r * 0.4), center + Vector2(-r * 0.3, -r * 0.5)])
			ci.draw_colored_polygon(head, color)
		PuertoDefs.Office.PATRON:  # corona de laurel
			ci.draw_arc(center, r * 0.7, 0.6 * PI, 1.9 * PI, 20, color, lw)
			for i in 6:
				var a := 0.7 * PI + i * 0.2 * PI
				ci.draw_circle(center + Vector2(cos(a), sin(a)) * r * 0.7, r * 0.16, color)
			star(ci, center, r * 0.3, color)
		PuertoDefs.Office.MAYOR:  # vara con corona
			ci.draw_line(center + Vector2(0, -r * 0.4), center + Vector2(0, r * 0.9), color, lw)
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.5, -r * 0.4), center + Vector2(-r * 0.5, -r * 0.9), center + Vector2(-r * 0.2, -r * 0.6), center + Vector2(0, -r * 0.95), center + Vector2(r * 0.2, -r * 0.6), center + Vector2(r * 0.5, -r * 0.9), center + Vector2(r * 0.5, -r * 0.4)]), color)


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
	if D.is_wonder(card):
		wonder_icon(ci, art, card)
	else:
		building_icon(ci, art, guild, color, D.cost_of(card))
	# Nombre
	var effect := card_text(card)
	var name_size := title if D.card_name(card).length() <= 14 else int(title * 0.85)
	var name_h := 0.18 if effect != "" else 0.3
	var name_rect := Rect2(inner.position + Vector2(2, inner.size.y * 0.6), Vector2(inner.size.x - 4, inner.size.y * name_h))
	if effect != "" and D.card_name(card).length() > 14:
		name_rect.size.y = inner.size.y * 0.12
		name_size = int(title * 0.78)
	paragraph(ci, name_rect, D.card_name(card), name_size, INK)
	if effect != "":
		var top := name_rect.end.y + 1
		var effect_rect := Rect2(Vector2(inner.position.x + 3, top), Vector2(inner.size.x - 6, inner.end.y - top - 2))
		var effect_size := int(title * (0.72 if effect.length() <= 30 else 0.62))
		paragraph(ci, effect_rect, effect, effect_size, INK.lightened(0.25))


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
