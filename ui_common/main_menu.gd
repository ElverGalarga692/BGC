extends Control
## Menú principal: elegir juego, configurar los jugadores locales (todos en
## el mismo equipo, por turnos), continuar la partida guardada y ajustes.
##
## Diseño: fondo animado (MenuBackground), tema propio (BGCTheme), tarjetas
## de juego con ilustración y páginas que aparecen con una transición.

const MAX_NAME_LENGTH := 16
const COLUMN_WIDTH := 580.0
## Filas de jugadores visibles sin desplazar (y su altura aproximada).
const MAX_VISIBLE_ROWS := 5
const PLAYER_ROW_HEIGHT := 54.0
const LOBBY_ROW_HEIGHT := 58.0

var _pages: Control
var _games_box: VBoxContainer
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

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	column.add_child(_build_header())

	var glass := PanelContainer.new()
	column.add_child(glass)
	_pages = VBoxContainer.new()
	glass.add_child(_pages)
	_games_box = _page()
	_setup_box = _page()
	_settings_box = _page()
	_lobby_box = _page()
	_build_game_list()
	_build_settings()

	var footer := _label("Multijugador local · Hecho con Godot", 12, BGCTheme.TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.modulate.a = 0.6
	column.add_child(footer)

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
	# Entrada: la columna aparece desde abajo.
	column.modulate.a = 0.0
	var intro := create_tween().set_parallel()
	intro.tween_property(column, "modulate:a", 1.0, 0.6)
	column.position.y += 30
	intro.tween_property(column, "position:y", column.position.y - 30, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Piezas de la interfaz -------------------------------------------------------------

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 22)
	header.add_child(HexEmblem.new([], 116, 0.12))
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -6)
	var title := _label("BGC", 92, BGCTheme.TEXT)
	title.add_theme_font_override("font", BGCTheme.bold_font(1.1))
	title.add_theme_color_override("font_outline_color", Color("0b1e33"))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 6)
	titles.add_child(title)
	var subtitle := _label("BOARD GAME COLLECTION", 19, BGCTheme.ACCENT)
	subtitle.add_theme_font_override("font", BGCTheme.bold_font(0.5))
	titles.add_child(subtitle)
	header.add_child(titles)
	return header


func _page() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.visible = false
	_pages.add_child(box)
	return box


func _show_page(page: Control, animate: bool = true) -> void:
	for p in [_games_box, _setup_box, _settings_box, _lobby_box]:
		p.visible = p == page
	if animate:
		page.modulate.a = 0.0
		create_tween().tween_property(page, "modulate:a", 1.0, 0.25)


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


## Tarjeta de juego: ilustración, nombre, descripción y número de jugadores.
## Se agranda un poco al pasar el ratón.
func _game_card(game: Dictionary) -> Button:
	var card := _button("", _on_game_chosen.bind(game), "CardButton", 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var art := HexEmblem.new(game.get("colors", []), 84)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _label(game["name"], 26)
	name_label.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	texts.add_child(name_label)
	var desc := _label(game["description"], 14, BGCTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(desc)
	var players := _label("%d–%d jugadores  ·  humanos e IA" % [game["min_players"], game["max_players"]], 13, BGCTheme.ACCENT)
	texts.add_child(players)
	for child in texts.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var arrow := _label("›", 40, BGCTheme.ACCENT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)
	card.mouse_entered.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2.ONE * 1.025, 0.12)
		create_tween().tween_property(art, "spin_speed", 0.6, 0.2))
	card.mouse_exited.connect(func() -> void:
		create_tween().tween_property(card, "scale", Vector2.ONE, 0.12)
		create_tween().tween_property(art, "spin_speed", 0.0, 0.4))
	return card


# --- Página de juegos ------------------------------------------------------------------

## Aviso arriba de la lista de juegos (p. ej. una desconexión).
func _show_notice(text: String) -> void:
	var old := _games_box.get_node_or_null("Notice")
	if old != null:
		old.queue_free()
	var notice := _label("⚠  " + text, 15, BGCTheme.ACCENT)
	notice.name = "Notice"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_games_box.add_child(notice)
	_games_box.move_child(notice, 0)


func _build_game_list() -> void:
	_games_box.add_child(_section("Elige un juego"))
	for game in GameRegistry.all_games():
		if App.has_save(game["id"]):
			_games_box.add_child(_button("▶  Continuar partida de %s" % game["name"], App.continue_game.bind(game["id"]), "PrimaryButton", 50))
		_games_box.add_child(_game_card(game))
		if game.has("rules"):
			var rules := _button("Reglas de %s" % game["name"], func() -> void: RulesPanel.open(self, game["rules"]), "GhostButton", 36)
			_games_box.add_child(rules)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var settings := _button("Ajustes", func() -> void: _show_page(_settings_box))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(settings)
	var quit := _button("Salir", func() -> void: get_tree().quit(), "GhostButton")
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(quit)
	_games_box.add_child(HSeparator.new())
	_games_box.add_child(bottom)


# --- Página de jugadores ---------------------------------------------------------------

func _on_game_chosen(game: Dictionary) -> void:
	_selected_game = game
	for child in _setup_box.get_children():
		_setup_box.remove_child(child)
		child.queue_free()

	var title := _label(game["name"], 28)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	_setup_box.add_child(title)

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


func _set_player_count(n: int) -> void:
	_player_count = n
	_rebuild_player_rows()


## Ajusta las filas de jugadores al número elegido, conservando lo escrito.
func _rebuild_player_rows() -> void:
	while _name_edits.size() < _player_count:
		var i := _name_edits.size()
		var row_panel := PanelContainer.new()
		var style := BGCTheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 12, 1, 0, 6)
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
	_players_scroll.custom_minimum_size.y = minf(_player_count, MAX_VISIBLE_ROWS) * PLAYER_ROW_HEIGHT


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
	var title := _label("Sala de espera", 28)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	_lobby_box.add_child(title)
	if Net.is_host:
		var ips := Net.local_addresses()
		var where := ", ".join(ips) if not ips.is_empty() else "desconocida"
		_lobby_box.add_child(_label("Los demás pueden encontrar la partida en la lista o unirse con tu IP: %s" % where, 14, BGCTheme.TEXT_DIM))
	var lobby_game := GameRegistry.find(Net.game_id)
	_lobby_box.add_child(_label(lobby_game.get("name", ""), 18, BGCTheme.ACCENT))
	_lobby_box.add_child(_section("Jugadores (%d/%d)" % [Net.seats.size(), Net.max_players()]))
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
	if Net.is_host and Net.seats.size() < Net.max_players():
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
	if not _lobby_box.visible:
		_show_page(_lobby_box)


# --- Página de ajustes -----------------------------------------------------------------

## Ajustes que se guardan entre sesiones.
func _build_settings() -> void:
	var title := _label("Ajustes", 28)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	_settings_box.add_child(title)

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
