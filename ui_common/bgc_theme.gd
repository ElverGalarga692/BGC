class_name BGCTheme
extends RefCounted
## Tema visual de los menús de BGC: botones redondeados con sombra, campos
## de texto, paneles "de cristal" y fuentes en negrita.

const BG_DEEP := Color("0b1e33")
const BG_MID := Color("143a5c")
const BG_LIGHT := Color("1f5f86")
const ACCENT := Color("ffd166")
const ACCENT_DARK := Color("e0a43a")
const TEXT := Color("f4f1e8")
const TEXT_DIM := Color("b9c6d3")
const BUTTON := Color("22476b")
const BUTTON_HOVER := Color("2d5a85")
const BUTTON_PRESSED := Color("1a3955")
const BORDER := Color("3f6f99")

## Colores de los terrenos, para decoraciones.
const PALETTE := [
	Color("2f7a3b"), Color("c4623a"), Color("9ccc5a"),
	Color("e8c33f"), Color("8a8f99"), Color("e3cf98"),
]


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 12, border_width: int = 0, shadow: int = 0, margin: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, shadow * 0.5)
	s.content_margin_left = margin + 4
	s.content_margin_right = margin + 4
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	s.anti_aliasing = true
	return s


## Pieza de una barra de desplazamiento (8 px de grosor).
static func _bar(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	s.set_content_margin_all(4)
	s.anti_aliasing = true
	return s


## Icono de casilla (22 px): un recuadro con borde claro y, si está
## marcada, relleno del color de acento con una marca oscura.
static func _check_icon(checked: bool) -> ImageTexture:
	const N := 22
	var image := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var mark := [Vector2(5.5, 11.5), Vector2(9.5, 15.5), Vector2(16.5, 6.5)]
	for y in N:
		for x in N:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distancia al borde de un cuadrado redondeado (radio 5).
			var q := (p - Vector2(N, N) / 2.0).abs() - Vector2(N / 2.0 - 6.0, N / 2.0 - 6.0)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 5.0
			var color := Color(ACCENT if checked else BORDER, clampf(-d, 0.0, 1.0))
			if d < -2.0:
				color = ACCENT_DARK if checked else Color("10263d")
			if checked:
				var m := minf(
					Geometry2D.get_closest_point_to_segment(p, mark[0], mark[1]).distance_to(p),
					Geometry2D.get_closest_point_to_segment(p, mark[1], mark[2]).distance_to(p))
				color = color.lerp(Color("2a1d05"), clampf(2.0 - m, 0.0, 1.0))
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## Fuente por defecto en negrita.
static func bold_font(strength: float = 0.7) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = strength
	return f


## `button`, `border` y `field` cambian el tono de botones y campos para
## los juegos con otra paleta (p. ej. los marrones de Pests!).
static func build(button: Color = BUTTON, border: Color = BORDER, field: Color = Color("10263d")) -> Theme:
	var button_hover := button.lightened(0.12)
	var button_pressed := button.darkened(0.2)
	var t := Theme.new()
	t.default_font_size = 17

	# Botones normales.
	t.set_stylebox("normal", "Button", box(button, border, 12, 2, 5))
	t.set_stylebox("hover", "Button", box(button_hover, ACCENT, 12, 2, 7))
	t.set_stylebox("pressed", "Button", box(button_pressed, ACCENT_DARK, 12, 2, 2))
	t.set_stylebox("disabled", "Button", box(Color(button, 0.5), Color(border, 0.4), 12, 2, 0))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, ACCENT, 12, 2, 0))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_font("font", "Button", bold_font(0.5))

	# Botón principal (variación "PrimaryButton").
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(ACCENT_DARK, ACCENT, 12, 2, 6))
	t.set_stylebox("hover", "PrimaryButton", box(ACCENT, Color.WHITE, 12, 2, 8))
	t.set_stylebox("pressed", "PrimaryButton", box(Color("c98d2a"), ACCENT, 12, 2, 2))
	t.set_color("font_color", "PrimaryButton", Color("2a1d05"))
	t.set_color("font_hover_color", "PrimaryButton", Color("1a1203"))
	t.set_color("font_pressed_color", "PrimaryButton", Color("2a1d05"))

	# Botón secundario discreto (variación "GhostButton").
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.18), 12, 1, 0))
	t.set_stylebox("hover", "GhostButton", box(Color(1, 1, 1, 0.1), ACCENT, 12, 1, 0))
	t.set_stylebox("pressed", "GhostButton", box(Color(0, 0, 0, 0.2), ACCENT_DARK, 12, 1, 0))
	t.set_color("font_color", "GhostButton", TEXT_DIM)

	# Tarjetas de juego (variación "CardButton").
	t.set_type_variation("CardButton", "Button")
	t.set_stylebox("normal", "CardButton", box(Color("1b3d5e"), border, 16, 2, 8, 14))
	t.set_stylebox("hover", "CardButton", box(Color("23507a"), ACCENT, 16, 3, 12, 14))
	t.set_stylebox("pressed", "CardButton", box(Color("163250"), ACCENT_DARK, 16, 3, 3, 14))
	t.set_stylebox("focus", "CardButton", box(Color.TRANSPARENT, ACCENT, 16, 2, 0, 14))

	# Paneles "de cristal".
	t.set_stylebox("panel", "PanelContainer", box(Color(0.04, 0.1, 0.18, 0.72), Color(1, 1, 1, 0.1), 20, 1, 18, 22))

	# Campos de texto, selectores y casillas.
	t.set_stylebox("normal", "LineEdit", box(field, border, 10, 1, 0, 8))
	t.set_stylebox("focus", "LineEdit", box(field, ACCENT, 10, 2, 0, 8))
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_stylebox("normal", "OptionButton", box(button, border, 10, 1, 3, 8))
	t.set_stylebox("hover", "OptionButton", box(button_hover, ACCENT, 10, 1, 4, 8))
	t.set_stylebox("pressed", "OptionButton", box(button_pressed, ACCENT_DARK, 10, 1, 1, 8))
	t.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, ACCENT, 10, 1, 0, 8))
	t.set_stylebox("panel", "PopupMenu", box(field, border, 10, 1, 8, 6))
	t.set_stylebox("hover", "PopupMenu", box(button_hover, Color.TRANSPARENT, 6, 0, 0, 4))
	t.set_stylebox("normal", "ColorPickerButton", box(button, border, 10, 1, 3, 6))
	t.set_stylebox("hover", "ColorPickerButton", box(button_hover, ACCENT, 10, 1, 4, 6))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", ACCENT)
	t.set_stylebox("normal", "CheckButton", box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 12, 1, 0))
	t.set_stylebox("hover", "CheckButton", box(Color(1, 1, 1, 0.09), Color(ACCENT, 0.6), 12, 1, 0))
	t.set_stylebox("pressed", "CheckButton", box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 12, 1, 0))
	t.set_stylebox("hover_pressed", "CheckButton", box(Color(1, 1, 1, 0.09), Color(ACCENT, 0.6), 12, 1, 0))
	t.set_stylebox("focus", "CheckButton", box(Color.TRANSPARENT, Color(ACCENT, 0.5), 12, 1, 0))
	# Casillas de opciones: sin caja de botón, solo se ilumina al pasar.
	for state in ["normal", "pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 10, 0, 0, 3))
	for state in ["hover", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", box(Color(1, 1, 1, 0.07), Color.TRANSPARENT, 10, 0, 0, 3))
	t.set_stylebox("focus", "CheckBox", box(Color.TRANSPARENT, Color(ACCENT, 0.5), 10, 1, 0, 3))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_constant("h_separation", "CheckBox", 10)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)

	# Barras de desplazamiento finas.
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _bar(Color(1, 1, 1, 0.05)))
		t.set_stylebox("scroll_focus", bar, _bar(Color(1, 1, 1, 0.05)))
		t.set_stylebox("grabber", bar, _bar(Color(border, 0.8)))
		t.set_stylebox("grabber_highlight", bar, _bar(ACCENT_DARK))
		t.set_stylebox("grabber_pressed", bar, _bar(ACCENT))

	t.set_stylebox("slider", "HSlider", box(field, border, 6, 1, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DARK, Color.TRANSPARENT, 6, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color.TRANSPARENT, 6, 0, 0, 3))
	return t
