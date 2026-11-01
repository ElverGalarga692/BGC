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


## Fuente por defecto en negrita.
static func bold_font(strength: float = 0.7) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = strength
	return f


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17

	# Botones normales.
	t.set_stylebox("normal", "Button", box(BUTTON, BORDER, 12, 2, 5))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, ACCENT, 12, 2, 7))
	t.set_stylebox("pressed", "Button", box(BUTTON_PRESSED, ACCENT_DARK, 12, 2, 2))
	t.set_stylebox("disabled", "Button", box(Color(BUTTON, 0.5), Color(BORDER, 0.4), 12, 2, 0))
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
	t.set_stylebox("normal", "CardButton", box(Color("1b3d5e"), BORDER, 16, 2, 8, 14))
	t.set_stylebox("hover", "CardButton", box(Color("23507a"), ACCENT, 16, 3, 12, 14))
	t.set_stylebox("pressed", "CardButton", box(Color("163250"), ACCENT_DARK, 16, 3, 3, 14))
	t.set_stylebox("focus", "CardButton", box(Color.TRANSPARENT, ACCENT, 16, 2, 0, 14))

	# Paneles "de cristal".
	t.set_stylebox("panel", "PanelContainer", box(Color(0.04, 0.1, 0.18, 0.72), Color(1, 1, 1, 0.1), 20, 1, 18, 22))

	# Campos de texto, selectores y casillas.
	t.set_stylebox("normal", "LineEdit", box(Color("10263d"), BORDER, 10, 1, 0, 8))
	t.set_stylebox("focus", "LineEdit", box(Color("10263d"), ACCENT, 10, 2, 0, 8))
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_stylebox("normal", "OptionButton", box(BUTTON, BORDER, 10, 1, 3, 8))
	t.set_stylebox("hover", "OptionButton", box(BUTTON_HOVER, ACCENT, 10, 1, 4, 8))
	t.set_stylebox("pressed", "OptionButton", box(BUTTON_PRESSED, ACCENT_DARK, 10, 1, 1, 8))
	t.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, ACCENT, 10, 1, 0, 8))
	t.set_stylebox("panel", "PopupMenu", box(Color("10263d"), BORDER, 10, 1, 8, 6))
	t.set_stylebox("hover", "PopupMenu", box(BUTTON_HOVER, Color.TRANSPARENT, 6, 0, 0, 4))
	t.set_stylebox("normal", "ColorPickerButton", box(BUTTON, BORDER, 10, 1, 3, 6))
	t.set_stylebox("hover", "ColorPickerButton", box(BUTTON_HOVER, ACCENT, 10, 1, 4, 6))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", ACCENT)
	t.set_stylebox("normal", "CheckButton", box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 12, 1, 0))
	t.set_stylebox("hover", "CheckButton", box(Color(1, 1, 1, 0.09), Color(ACCENT, 0.6), 12, 1, 0))
	t.set_stylebox("pressed", "CheckButton", box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 12, 1, 0))
	t.set_stylebox("hover_pressed", "CheckButton", box(Color(1, 1, 1, 0.09), Color(ACCENT, 0.6), 12, 1, 0))
	t.set_stylebox("focus", "CheckButton", box(Color.TRANSPARENT, Color(ACCENT, 0.5), 12, 1, 0))
	t.set_stylebox("slider", "HSlider", box(Color("10263d"), BORDER, 6, 1, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DARK, Color.TRANSPARENT, 6, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color.TRANSPARENT, 6, 0, 0, 3))
	return t
