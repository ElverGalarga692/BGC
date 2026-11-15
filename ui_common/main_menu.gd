extends Control
## Menú principal: elegir juego, configurar los jugadores locales (todos en
## el mismo equipo, por turnos), continuar la partida guardada y ajustes.
##
## Diseño: fondo animado (MenuBackground), tema propio (BGCTheme), barra
## superior fija y, debajo, una zona que se desplaza con la rueda del ratón:
## la cuadrícula de tarjetas de juego o la página elegida (jugadores, sala
## de espera, ajustes).

const MAX_NAME_LENGTH := 16
## Ancho de las páginas de formulario (jugadores, sala de espera, ajustes).
const FORM_WIDTH := 620.0
## Tarjetas de juego: tamaño, separación y columnas como máximo.
const CARD_SIZE := Vector2(352, 252)
const CARD_GAP := 18
const MAX_COLUMNS := 3
const BANNER_HEIGHT := 86.0
## Margen lateral de la pantalla.
const SIDE_MARGIN := 36
## Filas de jugadores visibles sin desplazar (y su altura aproximada).
const MAX_VISIBLE_ROWS := 5
const PLAYER_ROW_HEIGHT := 56.0
const LOBBY_ROW_HEIGHT := 58.0

var _scroll: ScrollContainer
var _pages: VBoxContainer
var _games_box: VBoxContainer
var _cards_box: VBoxContainer
var _cards: Array[Button] = []
var _columns := 0
var _settings_button: Button
var _setup_box: VBoxContainer
var _settings_box: VBoxContainer
var _lobby_box: VBoxContainer
var _local_content: VBoxContainer
var _net_content: VBoxContainer
var _play_button: Button
var _hosts_list: VBoxContainer
var _net_name: LineEdit
var _net_status: Label
var _selected_game: Dictionary = {}
var _player_count := 3
var _count_buttons: Array[Button] = []
var _players_list: VBoxContainer
var _players_scroll: ScrollContainer
var _name_edits: Array[LineEdit] = []
var _color_pickers: Array[ColorPickerButton] = []
var _ai_options: Array[OptionButton] = []


func _ready() -> void:
	theme = BGCTheme.build()
	add_child(MenuBackground.new())

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	layout.add_child(_build_top_bar())

	# Zona central: todo lo que no quepa se desplaza con la rueda del ratón.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	# El margen deja sitio a las sombras y al agrandado de las tarjetas.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_right", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 14)
	center.add_child(margin)
	_pages = VBoxContainer.new()
	margin.add_child(_pages)

	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", 14)
	_games_box.visible = false
	_pages.add_child(_games_box)
	_setup_box = _form_page()
	_settings_box = _form_page()
	_lobby_box = _form_page()
	_build_game_list()
	_build_settings()

	var footer := _label("Multijugador local · Hecho con Godot", 12, BGCTheme.TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.modulate.a = 0.6
	footer.custom_minimum_size.y = 26
	layout.add_child(footer)

	resized.connect(_layout_cards)
	_layout_cards()
	_show_page(_games_box, false)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.disconnected.connect(func(reason: String) -> void:
		Net.stop_discovery()
		_show_notice(reason)
		_show_page(_games_box))
	if App.menu_notice != "":
		_show_notice(App.menu_notice)
		App.menu_notice = ""
	# Entrada: el menú aparece poco a poco.
	layout.modulate.a = 0.0
	create_tween().tween_property(layout, "modulate:a", 1.0, 0.5)


## Esc vuelve a la lista de juegos desde los ajustes o la página de jugadores.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _is_shown(_settings_box) or _is_shown(_setup_box):
		Net.stop_discovery()
		_show_page(_games_box)
		get_viewport().set_input_as_handled()


# --- Piezas de la interfaz -------------------------------------------------------------

## Barra superior fija: emblema y título a la izquierda, ajustes y salir a
## la derecha.
func _build_top_bar() -> Control:
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", SIDE_MARGIN)
	bar.add_theme_constant_override("margin_right", SIDE_MARGIN)
	bar.add_theme_constant_override("margin_top", 16)
	bar.add_theme_constant_override("margin_bottom", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	row.add_child(HexEmblem.new([], 68, 0.12))
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -8)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("BGC", 46, BGCTheme.TEXT)
	title.add_theme_font_override("font", BGCTheme.bold_font(1.1))
	title.add_theme_color_override("font_outline_color", BGCTheme.BG_DEEP)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 3)
	titles.add_child(title)
	var subtitle := _label("BOARD GAME COLLECTION", 13, BGCTheme.ACCENT)
	subtitle.add_theme_font_override("font", BGCTheme.bold_font(0.5))
	titles.add_child(subtitle)
	row.add_child(titles)
	_settings_button = _button("Ajustes", func() -> void:
		Net.stop_discovery()
		_show_page(_games_box if _is_shown(_settings_box) else _settings_box), "", 42)
	var quit := _button("Salir", func() -> void: get_tree().quit(), "GhostButton", 42)
	for b: Button in [_settings_button, quit]:
		b.custom_minimum_size.x = 112
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	return bar


## Página de formulario: una columna dentro de un panel "de cristal".
func _form_page() -> VBoxContainer:
	var glass := PanelContainer.new()
	glass.custom_minimum_size.x = FORM_WIDTH
	glass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glass.visible = false
	_pages.add_child(glass)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	glass.add_child(box)
	return box


## Nodo que se muestra u oculta para una página: la propia lista de juegos
## o el panel que envuelve a un formulario.
func _page_root(page: Control) -> Control:
	return page if page == _games_box else page.get_parent()


func _is_shown(page: Control) -> bool:
	return _page_root(page).visible


func _show_page(page: Control, animate: bool = true) -> void:
	for p: Control in [_games_box, _setup_box, _settings_box, _lobby_box]:
		_page_root(p).visible = p == page
	_scroll.scroll_vertical = 0
	# En la sala de espera no se cambia de página sin salir de la partida.
	_settings_button.visible = page != _lobby_box
	_settings_button.text = "Juegos" if page == _settings_box else "Ajustes"
	if animate:
		var shown := _page_root(page)
		shown.modulate.a = 0.0
		create_tween().tween_property(shown, "modulate:a", 1.0, 0.25)


func _label(text: String, font_size: int = 17, color: Color = BGCTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _section(text: String) -> Label:
	var label := _label(text.to_upper(), 13, BGCTheme.TEXT_DIM)
	label.add_theme_font_override("font", BGCTheme.bold_font(0.4))
	return label


## Título de una página de formulario.
func _page_title(text: String, colors: Array = []) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if not colors.is_empty():
		row.add_child(HexEmblem.new(colors, 44))
	var title := _label(text, 28)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	row.add_child(title)
	return row


## Botón del tema con sonido de clic. `variation`: "", "PrimaryButton" o
## "GhostButton".
func _button(text: String, callback: Callable, variation: String = "", min_height: float = 46.0) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, min_height)
	button.pressed.connect(func() -> void: Sfx.play(&"click"))
	button.pressed.connect(callback)
	return button


## Tarjeta de juego: franja ilustrada con los colores del juego, nombre,
## descripción y, abajo, las reglas y la partida guardada (si la hay).
## Pulsar la tarjeta empieza una partida nueva. Se agranda un poco al pasar
## el ratón o al recibir el foco del teclado.
func _game_card(game: Dictionary) -> Button:
	var card := _button("", _on_game_chosen.bind(game), "CardButton", CARD_SIZE.y)
	card.custom_minimum_size.x = CARD_SIZE.x
	card.pivot_offset = CARD_SIZE / 2.0
	var colors: Array = game.get("colors", BGCTheme.PALETTE)

	var banner := CardBanner.new(colors)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 3
	banner.offset_top = 3
	banner.offset_right = -3
	banner.offset_bottom = BANNER_HEIGHT
	card.add_child(banner)
	var art := HexEmblem.new(colors, 70)
	art.position = Vector2(18, (BANNER_HEIGHT - 70) / 2.0)
	art.size = Vector2(70, 70)
	banner.add_child(art)
	var chip := _chip("%d–%d jugadores" % [game["min_players"], game["max_players"]])
	banner.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)

	var texts := VBoxContainer.new()
	texts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texts.offset_left = 18
	texts.offset_right = -18
	texts.offset_top = BANNER_HEIGHT + 8
	texts.offset_bottom = -14
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(texts)
	var name_label := _label(game["name"], 24)
	name_label.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name_label)
	var desc := _label(game["description"], 13, BGCTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(desc)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(actions)
	if game.has("rules"):
		var rules := _button("Reglas", func() -> void: RulesPanel.open(self, game["rules"]), "GhostButton", 34)
		rules.tooltip_text = "Reglas de %s" % game["name"]
		actions.add_child(rules)
	if App.has_save(game["id"]):
		var resume := _button("▶  Continuar", App.continue_game.bind(game["id"]), "PrimaryButton", 34)
		resume.tooltip_text = "Continuar la partida guardada de %s" % game["name"]
		actions.add_child(resume)
	for b: Button in actions.get_children():
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("focus", BGCTheme.box(Color.TRANSPARENT, BGCTheme.ACCENT, 10, 2, 0, 6))
	var play := _label("Nueva partida  ›" if App.has_save(game["id"]) else "Jugar  ›", 15, BGCTheme.ACCENT)
	play.add_theme_font_override("font", BGCTheme.bold_font(0.5))
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(play)

	var highlight := func(on: bool) -> void:
		card.z_index = 1 if on else 0
		create_tween().tween_property(card, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.12)
		create_tween().tween_property(art, "spin_speed", 0.6 if on else 0.0, 0.2 if on else 0.4)
	card.mouse_entered.connect(highlight.bind(true))
	card.mouse_exited.connect(func() -> void: highlight.call(card.has_focus()))
	card.focus_entered.connect(highlight.bind(true))
	card.focus_exited.connect(highlight.bind(false))
	return card


## Etiqueta pequeña con fondo oscuro (para la franja de las tarjetas).
func _chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", BGCTheme.box(Color(0.03, 0.08, 0.14, 0.72), Color(1, 1, 1, 0.16), 11, 1, 0, 3))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(text, 12, BGCTheme.TEXT)
	label.add_theme_font_override("font", BGCTheme.bold_font(0.4))
	chip.add_child(label)
	return chip


## Franja superior de una tarjeta: fondo con los colores del juego y
## hexágonos tenues de adorno.
class CardBanner extends Control:
	var _colors: Array

	func _init(colors: Array) -> void:
		_colors = colors
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var base: Color = _colors[_colors.size() - 1]
		var style := StyleBoxFlat.new()
		style.bg_color = base.darkened(0.45)
		style.corner_radius_top_left = 13
		style.corner_radius_top_right = 13
		draw_style_box(style, Rect2(Vector2.ZERO, size))
		# Hexágonos de adorno, siempre en el mismo sitio para cada tarjeta.
		var spots := [[0.42, 0.75, 34.0], [0.58, 0.1, 22.0], [0.74, 0.8, 46.0], [0.95, 0.55, 30.0], [0.3, 0.05, 16.0]]
		for i in spots.size():
			var c: Color = _colors[i % _colors.size()]
			var center := Vector2(spots[i][0] * size.x, spots[i][1] * size.y)
			var points := PackedVector2Array()
			for k in 6:
				points.append(center + Vector2.from_angle(0.4 * i + k * TAU / 6.0) * spots[i][2])
			draw_colored_polygon(points, Color(c, 0.3))
			points.append(points[0])
			draw_polyline(points, Color(c.lightened(0.35), 0.45), 1.5, true)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(1, 1, 1, 0.14), 2.0)


# --- Página de juegos ------------------------------------------------------------------

## Aviso arriba de la lista de juegos (p. ej. una desconexión).
func _show_notice(text: String) -> void:
	var old := _games_box.get_node_or_null("Notice")
	if old != null:
		_games_box.remove_child(old)
		old.queue_free()
	var notice := PanelContainer.new()
	notice.name = "Notice"
	notice.add_theme_stylebox_override("panel", BGCTheme.box(Color(BGCTheme.ACCENT_DARK, 0.16), Color(BGCTheme.ACCENT, 0.6), 12, 1, 0, 10))
	var label := _label("⚠  " + text, 15, BGCTheme.ACCENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_child(label)
	_games_box.add_child(notice)
	_games_box.move_child(notice, 0)


func _build_game_list() -> void:
	var games := GameRegistry.all_games()
	var heading := HBoxContainer.new()
	var section := _section("Elige un juego")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(section)
	heading.add_child(_label("%d juegos · humanos e IA" % games.size(), 13, BGCTheme.TEXT_DIM))
	_games_box.add_child(heading)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", CARD_GAP)
	_games_box.add_child(_cards_box)
	for game in games:
		_cards.append(_game_card(game))


## Reparte las tarjetas en filas según el ancho de la ventana (de 1 a
## MAX_COLUMNS columnas); la última fila queda centrada.
func _layout_cards() -> void:
	var available := size.x - 2.0 * SIDE_MARGIN
	var columns := clampi(int((available + CARD_GAP) / (CARD_SIZE.x + CARD_GAP)), 1, MAX_COLUMNS)
	if columns == _columns:
		return
	_columns = columns
	for card in _cards:
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
	for row in _cards_box.get_children():
		_cards_box.remove_child(row)
		row.queue_free()
	var row: HBoxContainer
	for i in _cards.size():
		if i % columns == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", CARD_GAP)
			_cards_box.add_child(row)
		row.add_child(_cards[i])
	_games_box.custom_minimum_size.x = columns * CARD_SIZE.x + (columns - 1) * CARD_GAP


# --- Página de jugadores ---------------------------------------------------------------

func _on_game_chosen(game: Dictionary) -> void:
	_selected_game = game
	for child in _setup_box.get_children():
		_setup_box.remove_child(child)
		child.queue_free()

	_setup_box.add_child(_page_title(game["name"], game.get("colors", BGCTheme.PALETTE)))

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	modes.visible = game.get("network", true)
	var mode_group := ButtonGroup.new()
	for entry in [["En este equipo", false], ["En red local", true]]:
		var mb := _button(entry[0], _set_network_mode.bind(entry[1]), "", 42)
		mb.toggle_mode = true
		mb.button_group = mode_group
		mb.button_pressed = not entry[1]
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(mb)
	_setup_box.add_child(modes)
	_build_game_options(game)

	_local_content = VBoxContainer.new()
	_local_content.add_theme_constant_override("separation", 12)
	_setup_box.add_child(_local_content)
	_net_content = VBoxContainer.new()
	_net_content.add_theme_constant_override("separation", 10)
	_net_content.visible = false
	_setup_box.add_child(_net_content)
	_build_network_content()

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 8)
	var count_label := _section("Jugadores")
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_label)
	_count_buttons.clear()
	var group := ButtonGroup.new()
	_player_count = clampi(_player_count, game["min_players"], game["max_players"])
	for n in range(game["min_players"], game["max_players"] + 1):
		var b := _button(str(n), _set_player_count.bind(n), "", 40)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 52
		b.button_pressed = n == _player_count
		count_row.add_child(b)
		_count_buttons.append(b)
	_local_content.add_child(count_row)

	# Con muchos jugadores, la lista se desplaza para que quepa en pantalla.
	_players_scroll = ScrollContainer.new()
	_players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_local_content.add_child(_players_scroll)
	_players_list = VBoxContainer.new()
	_players_list.add_theme_constant_override("separation", 8)
	_players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_scroll.add_child(_players_list)
	_name_edits.clear()
	_color_pickers.clear()
	_ai_options.clear()
	_rebuild_player_rows()

	_local_content.add_child(_label("Todos jugáis en este equipo por turnos. Las IA juegan solas.", 13, BGCTheme.TEXT_DIM))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var back := _button("Volver", func() -> void:
		Net.stop_discovery()
		_show_page(_games_box), "GhostButton", 50)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	var play := _button("Jugar", _on_play, "PrimaryButton", 50)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.size_flags_stretch_ratio = 2.0
	buttons.add_child(play)
	_play_button = play
	_setup_box.add_child(buttons)
	_show_page(_setup_box)


## Casillas con las opciones del juego (si tiene). Se recuerdan entre
## partidas y en red se usan las del anfitrión.
func _build_game_options(game: Dictionary) -> void:
	var options: Array = game.get("options", [])
	if options.is_empty():
		return
	_setup_box.add_child(_section("Opciones"))
	var checks := VBoxContainer.new()
	checks.add_theme_constant_override("separation", 0)
	_setup_box.add_child(checks)
	var current := App.game_options(game["id"])
	for option in options:
		var check := CheckBox.new()
		check.text = option["label"]
		check.button_pressed = current.get(option["key"], option["default"])
		check.toggled.connect(func(on: bool) -> void: App.set_game_option(game["id"], option["key"], on))
		check.pressed.connect(func() -> void: Sfx.play(&"click"))
		checks.add_child(check)


func _set_player_count(n: int) -> void:
	_player_count = n
	_rebuild_player_rows()


## Ajusta las filas de jugadores al número elegido, conservando lo escrito.
func _rebuild_player_rows() -> void:
	while _name_edits.size() < _player_count:
		var i := _name_edits.size()
		var row_panel := PanelContainer.new()
		var style := BGCTheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 12, 1, 0, 4)
		row_panel.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)
		var picker := ColorPickerButton.new()
		picker.color = PlayerInfo.default_color(i)
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(44, 38)
		row.add_child(picker)
		var edit := LineEdit.new()
		edit.placeholder_text = "Jugador %d" % (i + 1)
		edit.max_length = MAX_NAME_LENGTH
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		var ai := OptionButton.new()
		for level in PlayerInfo.AI_LEVEL_NAMES:
			ai.add_item(PlayerInfo.AI_LEVEL_NAMES[level], level)
		# Por defecto: el primer jugador es humano y el resto, IA normal.
		ai.select(PlayerInfo.AILevel.HUMAN if i == 0 else PlayerInfo.AILevel.NORMAL)
		ai.custom_minimum_size = Vector2(140, 0)
		row.add_child(ai)
		_players_list.add_child(row_panel)
		_name_edits.append(edit)
		_color_pickers.append(picker)
		_ai_options.append(ai)
		row_panel.modulate.a = 0.0
		create_tween().tween_property(row_panel, "modulate:a", 1.0, 0.2)
	while _name_edits.size() > _player_count:
		_name_edits.pop_back()
		_color_pickers.pop_back()
		_ai_options.pop_back()
		var row := _players_list.get_child(_players_list.get_child_count() - 1)
		_players_list.remove_child(row)
		row.queue_free()
	_players_scroll.custom_minimum_size.y = minf(_player_count, MAX_VISIBLE_ROWS) * PLAYER_ROW_HEIGHT - 8.0


func _on_play() -> void:
	var players: Array[PlayerInfo] = []
	for i in _name_edits.size():
		var level := _ai_options[i].get_selected_id()
		var player_name := _name_edits[i].text.strip_edges()
		if player_name == "" and level != PlayerInfo.AILevel.HUMAN:
			player_name = "IA %d" % (i + 1)
		players.append(PlayerInfo.new(i, player_name, _color_pickers[i].color, level))
	App.start_game(_selected_game["id"], players)


# --- Red local ---------------------------------------------------------------------------

func _set_network_mode(on: bool) -> void:
	_local_content.visible = not on
	_net_content.visible = on
	_play_button.visible = not on
	if on:
		Net.start_discovery()
		_refresh_hosts()
	else:
		Net.stop_discovery()


func _build_network_content() -> void:
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label := _section("Tu nombre")
	name_label.custom_minimum_size = Vector2(110, 0)
	name_row.add_child(name_label)
	_net_name = LineEdit.new()
	_net_name.text = App.get_setting("net_name", "")
	_net_name.placeholder_text = "Jugador"
	_net_name.max_length = MAX_NAME_LENGTH
	_net_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_net_name)
	_net_content.add_child(name_row)

	_net_content.add_child(_button("Crear partida", _on_host, "PrimaryButton", 48))

	_net_content.add_child(_section("O únete a una partida de la red"))
	_hosts_list = VBoxContainer.new()
	_hosts_list.add_theme_constant_override("separation", 6)
	_net_content.add_child(_hosts_list)

	var manual := HBoxContainer.new()
	manual.add_theme_constant_override("separation", 8)
	var ip := LineEdit.new()
	ip.placeholder_text = "IP del anfitrión (p. ej. 192.168.1.20)"
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual.add_child(ip)
	var join := _button("Unirse", func() -> void: _on_join(ip.text.strip_edges()), "", 40)
	join.custom_minimum_size.x = 100
	manual.add_child(join)
	_net_content.add_child(manual)
	_net_status = _label("", 14, BGCTheme.ACCENT)
	_net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_content.add_child(_net_status)
	_net_content.add_child(_label("Todos los equipos deben estar en la misma red (wifi o cable).", 13, BGCTheme.TEXT_DIM))


func _player_name() -> String:
	var n := _net_name.text.strip_edges()
	if n == "":
		n = "Jugador"
	App.set_setting("net_name", n)
	return n


func _refresh_hosts() -> void:
	if _hosts_list == null:
		return
	for child in _hosts_list.get_children():
		_hosts_list.remove_child(child)
		child.queue_free()
	if Net.hosts.is_empty():
		_hosts_list.add_child(_label("Buscando partidas en la red…", 14, BGCTheme.TEXT_DIM))
		return
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		var full: bool = h["players"] >= h["max"]
		var game_name: String = GameRegistry.find(String(h.get("game", ""))).get("name", "?")
		var b := _button("%s: partida de %s   (%d/%d)   %s" % [game_name, h["name"], h["players"], h["max"], ip], _on_join.bind(ip), "", 42)
		b.disabled = full
		_hosts_list.add_child(b)


func _on_host() -> void:
	var error := Net.host_game(_player_name(), _selected_game["id"])
	if error != "":
		_net_status.text = error
		return
	Net.stop_discovery()
	_show_page(_lobby_box)


func _on_join(address: String) -> void:
	if address == "":
		_net_status.text = "Escribe la IP del anfitrión o elige una partida de la lista."
		return
	var error := Net.join_game(address, _player_name())
	if error != "":
		_net_status.text = error
		return
	_net_status.text = "Conectando con %s…" % address
	Net.stop_discovery()


## Sala de espera: quién está en la mesa; el anfitrión añade IAs y empieza.
func _on_lobby_changed() -> void:
	if not Net.active:
		return
	for child in _lobby_box.get_children():
		_lobby_box.remove_child(child)
		child.queue_free()
	_lobby_box.add_child(_page_title("Sala de espera"))
	if Net.is_host:
		var ips := Net.local_addresses()
		var where := ", ".join(ips) if not ips.is_empty() else "desconocida"
		_lobby_box.add_child(_label("Los demás pueden encontrar la partida en la lista o unirse con tu IP: %s" % where, 14, BGCTheme.TEXT_DIM))
	var lobby_game := GameRegistry.find(Net.game_id)
	_lobby_box.add_child(_label(lobby_game.get("name", ""), 18, BGCTheme.ACCENT))
	_lobby_box.add_child(_section("Jugadores (%d/%d)" % [Net.seats.size(), Net.max_players]))
	# Con muchos jugadores, la lista se desplaza para que quepa en pantalla.
	var seats_scroll := ScrollContainer.new()
	seats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	seats_scroll.custom_minimum_size.y = minf(Net.seats.size(), MAX_VISIBLE_ROWS) * LOBBY_ROW_HEIGHT
	_lobby_box.add_child(seats_scroll)
	var seats_box := VBoxContainer.new()
	seats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_box.add_theme_constant_override("separation", 6)
	seats_scroll.add_child(seats_box)
	for i in Net.seats.size():
		var seat: Dictionary = Net.seats[i]
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", BGCTheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 12, 1, 0, 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = PlayerInfo.default_color(i)
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _label(seat["name"], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var tags: Array[String] = []
		if seat["peer"] == 1:
			tags.append("Anfitrión")
		if seat["peer"] == Net.my_id():
			tags.append("Tú")
		if seat["ai"] != PlayerInfo.AILevel.HUMAN:
			tags.append(PlayerInfo.AI_LEVEL_NAMES[seat["ai"]])
		row.add_child(_label(" · ".join(tags), 14, BGCTheme.ACCENT))
		if Net.is_host and i > 0:
			var remove := _button("Quitar", Net.remove_seat.bind(i), "GhostButton", 32)
			row.add_child(remove)
		seats_box.add_child(row_panel)
	if Net.is_host and Net.seats.size() < Net.max_players:
		var add_row := HBoxContainer.new()
		add_row.add_theme_constant_override("separation", 8)
		var level := OptionButton.new()
		for l in [PlayerInfo.AILevel.EASY, PlayerInfo.AILevel.NORMAL, PlayerInfo.AILevel.HARD]:
			level.add_item(PlayerInfo.AI_LEVEL_NAMES[l], l)
		level.select(1)
		level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_row.add_child(level)
		var add := _button("Añadir IA", func() -> void: Net.add_ai(level.get_selected_id()), "", 40)
		add_row.add_child(add)
		_lobby_box.add_child(add_row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var leave := _button("Salir", func() -> void:
		Net.leave()
		_show_page(_games_box), "GhostButton", 50)
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(leave)
	if Net.is_host:
		var start := _button("Empezar partida", Net.start_game, "PrimaryButton", 50)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.size_flags_stretch_ratio = 2.0
		start.disabled = Net.seats.size() < Net.min_players()
		start.tooltip_text = "Hacen falta al menos %d jugadores (añade IAs si faltan)" % Net.min_players() if start.disabled else ""
		buttons.add_child(start)
	else:
		var waiting := _label("Esperando a que el anfitrión empiece…", 15, BGCTheme.TEXT_DIM)
		waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(waiting)
	_lobby_box.add_child(buttons)
	if not _is_shown(_lobby_box):
		_show_page(_lobby_box)


# --- Página de ajustes -----------------------------------------------------------------

## Ajustes que se guardan entre sesiones.
func _build_settings() -> void:
	_settings_box.add_child(_page_title("Ajustes"))

	var volume_row := HBoxContainer.new()
	var volume_label := _label("Volumen")
	volume_label.custom_minimum_size = Vector2(170, 0)
	volume_row.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = App.get_setting("volume", 0.8)
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume.value_changed.connect(func(v: float) -> void:
		App.set_setting("volume", v)
		Sfx.set_volume(v))
	volume.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(&"resource"))
	volume_row.add_child(volume)
	_settings_box.add_child(volume_row)

	var options := [
		["fullscreen", "Pantalla completa", false],
		["board_3d", "Tablero en 3D", true],
		["ai_fast", "IA rápida", false],
	]
	for option in options:
		var check := CheckButton.new()
		check.text = option[1]
		check.button_pressed = App.get_setting(option[0], option[2])
		var key: String = option[0]
		check.toggled.connect(func(on: bool) -> void:
			Sfx.play(&"click")
			App.set_setting(key, on)
			if key == "fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
		_settings_box.add_child(check)

	_settings_box.add_child(_button("Volver", func() -> void: _show_page(_games_box), "GhostButton", 48))
