extends Control
## Pantalla de una partida de Archipiélago (multijugador local por turnos).
##
## Izquierda: jugadores y registro. Centro: tablero. Derecha: acciones del
## jugador en turno (dados, mano, construir, comerciar, terminar turno).
## La pantalla nunca cambia el estado directamente: crea GameActions y las
## envía a la partida con game.submit().

const G := preload("res://games/archipelago/logic/archipelago_game.gd")
const Pick := ArchBoardView.Pick

const BACKGROUND := Color("163246")
const LEFT_WIDTH := 270.0
const RIGHT_WIDTH := 300.0
const MARGIN := 12.0
const RESOURCE_COLORS := ArchBoardView.RESOURCE_COLORS

## Qué está construyendo el jugador (espera un clic en el tablero).
enum Mode { NONE, ROAD, SETTLEMENT, CITY }

var game: ArchipelagoGame
var _mode := Mode.NONE
var _log: Array[String] = []

var _board_view: ArchBoardView
var _players_box: VBoxContainer
var _log_label: RichTextLabel
var _hover_label: Label
var _turn_label: Label
var _prompt_label: Label
var _error_label: Label
var _dice_label: Label
var _hand_box: GridContainer
var _roll_button: Button
var _build_buttons := {}
var _give_option: OptionButton
var _receive_option: OptionButton
var _trade_button: Button
var _end_button: Button
var _banner: Label
var _victory: PanelContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_board_view = ArchBoardView.new()
	add_child(_board_view)
	_board_view.hovered.connect(_on_hovered)
	_board_view.clicked.connect(_on_board_clicked)

	_build_left_panel()
	_build_right_panel()
	_build_overlays()
	resized.connect(_layout)
	_start(App.session_seed())


func _start(seed: int) -> void:
	game = ArchipelagoGame.new()
	game.setup(App.session_players(), seed)
	game.action_applied.connect(_on_action_applied)
	game.event.connect(_on_game_event)
	game.game_finished.connect(_on_game_finished)
	_board_view.game = game
	_log.clear()
	_mode = Mode.NONE
	_victory.visible = false
	_add_log("Partida nueva (semilla %d). Colocación inicial." % seed)
	_refresh()
	_layout()
	_show_banner()


# --- Construcción de la interfaz -------------------------------------------

func _panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box


func _label(text: String = "", font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_left_panel() -> void:
	var box := _panel(LEFT_WIDTH)
	box.add_child(_label("Archipiélago", 24))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	box.add_child(_players_box)
	box.add_child(HSeparator.new())
	box.add_child(_label("Registro", 14))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_log_label)
	_hover_label = _label("", 13)
	_hover_label.modulate = Color(1, 1, 1, 0.7)
	_hover_label.custom_minimum_size = Vector2(0, 40)
	box.add_child(_hover_label)
	var menu := Button.new()
	menu.text = "Volver al menú"
	menu.pressed.connect(App.go_to_menu)
	box.add_child(menu)


func _build_right_panel() -> void:
	var box := _panel(RIGHT_WIDTH)
	_turn_label = _label("", 22)
	box.add_child(_turn_label)
	_prompt_label = _label("", 15)
	_prompt_label.custom_minimum_size = Vector2(0, 44)
	box.add_child(_prompt_label)
	_error_label = _label("", 13)
	_error_label.add_theme_color_override("font_color", Color("ff8a80"))
	box.add_child(_error_label)

	var dice_row := HBoxContainer.new()
	_roll_button = Button.new()
	_roll_button.text = "Tirar dados"
	_roll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll_button.pressed.connect(func() -> void: _submit(G.ROLL))
	dice_row.add_child(_roll_button)
	_dice_label = _label("", 20)
	_dice_label.custom_minimum_size = Vector2(120, 0)
	_dice_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_row.add_child(_dice_label)
	box.add_child(dice_row)

	box.add_child(HSeparator.new())
	box.add_child(_label("Tu mano", 14))
	_hand_box = GridContainer.new()
	_hand_box.columns = 5
	_hand_box.add_theme_constant_override("h_separation", 4)
	box.add_child(_hand_box)

	box.add_child(HSeparator.new())
	box.add_child(_label("Construir", 14))
	for entry in [[Mode.ROAD, G.BUILD_ROAD, "Camino"], [Mode.SETTLEMENT, G.BUILD_SETTLEMENT, "Poblado"], [Mode.CITY, G.BUILD_CITY, "Ciudad"]]:
		var button := Button.new()
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s" % [entry[2], _cost_text(G.COSTS[entry[1]])]
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_build_pressed.bind(entry[0]))
		box.add_child(button)
		_build_buttons[entry[0]] = button

	box.add_child(HSeparator.new())
	box.add_child(_label("Comerciar con la banca", 14))
	var trade_row := HBoxContainer.new()
	_give_option = OptionButton.new()
	_give_option.fit_to_longest_item = false
	_give_option.clip_text = true
	_give_option.custom_minimum_size = Vector2(120, 0)
	_give_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_give_option.item_selected.connect(func(_i: int) -> void: _refresh())
	trade_row.add_child(_give_option)
	trade_row.add_child(_label("→"))
	_receive_option = OptionButton.new()
	_receive_option.fit_to_longest_item = false
	_receive_option.clip_text = true
	_receive_option.custom_minimum_size = Vector2(110, 0)
	_receive_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in G.RESOURCE_COUNT:
		_receive_option.add_item(ArchDefs.RESOURCE_NAMES[r], r)
	_receive_option.select(ArchDefs.ResourceType.BRICK)
	_receive_option.item_selected.connect(func(_i: int) -> void: _refresh())
	trade_row.add_child(_receive_option)
	box.add_child(trade_row)
	_trade_button = Button.new()
	_trade_button.clip_text = true
	_trade_button.pressed.connect(_on_trade_pressed)
	box.add_child(_trade_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_end_button = Button.new()
	_end_button.text = "Terminar turno"
	_end_button.custom_minimum_size = Vector2(0, 40)
	_end_button.pressed.connect(func() -> void: _submit(G.END_TURN))
	box.add_child(_end_button)


func _build_overlays() -> void:
	_banner = _label("", 40)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	add_child(_banner)

	_victory = PanelContainer.new()
	_victory.custom_minimum_size = Vector2(420, 0)
	_victory.visible = false
	add_child(_victory)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_victory.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := _label("", 36)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var again := Button.new()
	again.text = "Nueva partida (mismos jugadores)"
	again.pressed.connect(func() -> void: _start(BGCRng.random_seed()))
	box.add_child(again)
	var menu := Button.new()
	menu.text = "Volver al menú"
	menu.pressed.connect(App.go_to_menu)
	box.add_child(menu)


func _layout() -> void:
	if _board_view == null:
		return
	var left: Control = _players_box.get_parent().get_parent().get_parent()
	var right: Control = _turn_label.get_parent().get_parent().get_parent()
	left.position = Vector2(MARGIN, MARGIN)
	left.size = Vector2(LEFT_WIDTH, size.y - MARGIN * 2)
	right.position = Vector2(size.x - RIGHT_WIDTH - MARGIN, MARGIN)
	right.size = Vector2(RIGHT_WIDTH, size.y - MARGIN * 2)
	var x0 := LEFT_WIDTH + MARGIN * 2
	var board_rect := Rect2(x0, MARGIN, maxf(100.0, size.x - x0 - RIGHT_WIDTH - MARGIN * 2), size.y - MARGIN * 2)
	_board_view.fit(board_rect)
	_banner.position = board_rect.position
	_banner.size = board_rect.size
	_victory.reset_size()
	_victory.position = board_rect.get_center() - _victory.size / 2.0


# --- Estado -> interfaz -------------------------------------------------------

func _refresh() -> void:
	var pid := game.turns.current
	var player := game.players[pid]
	var main := game.phase == G.Phase.MAIN

	# Jugadores
	for child in _players_box.get_children():
		child.queue_free()
	for p in game.players:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = p.color
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _label(p.display_name, 15)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if p.id == pid and not game.finished:
			name_label.text = "▶ " + name_label.text
			name_label.add_theme_color_override("font_color", Color("ffd166"))
		row.add_child(name_label)
		var stats := _label("%d PV · %d cartas" % [game.victory_points(p.id), game.hand_size(p.id)], 13)
		stats.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(stats)
		_players_box.add_child(row)

	_turn_label.text = player.display_name
	_turn_label.add_theme_color_override("font_color", player.color.lightened(0.2))
	_prompt_label.text = _prompt_text()

	# Dados
	_roll_button.disabled = game.phase != G.Phase.ROLL
	_dice_label.text = "" if game.last_roll.is_empty() else "%d + %d = %d" % [game.last_roll[0], game.last_roll[1], game.last_roll[0] + game.last_roll[1]]

	# Mano
	for child in _hand_box.get_children():
		child.queue_free()
	for r in G.RESOURCE_COUNT:
		_hand_box.add_child(_resource_card(r, game.hands[pid][r]))

	# Construir
	for mode in _build_buttons:
		var button: Button = _build_buttons[mode]
		var error := game.build_error(pid, _mode_action(mode))
		button.disabled = error != ""
		button.tooltip_text = error
		button.set_pressed_no_signal(_mode == mode)

	# Comercio
	var give_selected := maxi(0, _give_option.selected)
	_give_option.clear()
	for r in G.RESOURCE_COUNT:
		_give_option.add_item("%s %d:1" % [ArchDefs.RESOURCE_NAMES[r], game.trade_ratio(pid, r)], r)
	_give_option.select(give_selected)
	var give := _give_option.get_selected_id()
	var receive := _receive_option.get_selected_id()
	_trade_button.text = "Dar %d %s por 1 %s" % [game.trade_ratio(pid, give), ArchDefs.RESOURCE_NAMES[give], ArchDefs.RESOURCE_NAMES[receive]]
	_trade_button.disabled = game.validate(GameAction.new(G.TRADE_BANK, pid, {"give": give, "receive": receive})) != ""
	_give_option.disabled = not main
	_receive_option.disabled = not main

	_end_button.disabled = not main
	_update_targets()


func _prompt_text() -> String:
	match game.phase:
		G.Phase.SETUP:
			var placed: int = G.PIECES["settlement"] - game.pieces[game.turns.current]["settlement"]
			var round_text := "%d.ª" % (placed + 1 if game.setup_vertex == -1 else placed)
			if game.setup_vertex == -1:
				return "Colocación inicial (%s ronda): elige dónde poner un poblado." % round_text
			return "Colocación inicial (%s ronda): pon un camino junto a tu poblado." % round_text
		G.Phase.ROLL:
			return "Tira los dados."
		G.Phase.MAIN:
			match _mode:
				Mode.ROAD: return "Elige dónde construir el camino. Clic derecho para cancelar."
				Mode.SETTLEMENT: return "Elige dónde construir el poblado. Clic derecho para cancelar."
				Mode.CITY: return "Elige qué poblado mejorar. Clic derecho para cancelar."
			return "Construye, comercia o termina tu turno."
	return "Fin de la partida."


func _update_targets() -> void:
	var pid := game.turns.current
	if game.phase == G.Phase.SETUP:
		if game.setup_vertex == -1:
			_board_view.set_targets(Pick.VERTEX, game.legal_settlement_vertices(pid))
		else:
			_board_view.set_targets(Pick.EDGE, game.legal_road_edges(pid))
		return
	match _mode:
		Mode.ROAD: _board_view.set_targets(Pick.EDGE, game.legal_road_edges(pid))
		Mode.SETTLEMENT: _board_view.set_targets(Pick.VERTEX, game.legal_settlement_vertices(pid))
		Mode.CITY: _board_view.set_targets(Pick.VERTEX, game.legal_city_vertices(pid))
		_: _board_view.set_targets(Pick.NONE, [])


func _resource_card(r: int, count: int) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = RESOURCE_COLORS[r]
	style.set_corner_radius_all(6)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(50, 0)
	card.tooltip_text = ArchDefs.RESOURCE_NAMES[r]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var dark_text := r == ArchDefs.ResourceType.GRAIN or r == ArchDefs.ResourceType.WOOL
	for text in [str(count), ArchDefs.RESOURCE_NAMES[r].substr(0, 4)]:
		var label := _label(text, 20 if text == str(count) else 11)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("1b1b1b") if dark_text else Color.WHITE)
		box.add_child(label)
	card.modulate.a = 1.0 if count > 0 else 0.45
	return card


func _cost_text(cost: Array) -> String:
	var parts: Array[String] = []
	for r in cost.size():
		if cost[r] > 0:
			var name: String = ArchDefs.RESOURCE_NAMES[r]
			parts.append(name if cost[r] == 1 else "%d %s" % [cost[r], name])
	return ", ".join(parts)


# --- Interfaz -> acciones -------------------------------------------------------

func _submit(type: StringName, data: Dictionary = {}) -> void:
	var error := game.submit(GameAction.new(type, game.turns.current, data))
	_error_label.text = error


func _on_build_pressed(mode: Mode) -> void:
	_mode = Mode.NONE if _mode == mode else mode
	_error_label.text = ""
	_refresh()


func _on_board_clicked(kind: ArchBoardView.Pick, id: int) -> void:
	if game.phase == G.Phase.SETUP:
		if kind == Pick.VERTEX:
			_submit(G.BUILD_SETTLEMENT, {"vertex": id})
		elif kind == Pick.EDGE:
			_submit(G.BUILD_ROAD, {"edge": id})
		return
	match _mode:
		Mode.ROAD: _submit(G.BUILD_ROAD, {"edge": id})
		Mode.SETTLEMENT: _submit(G.BUILD_SETTLEMENT, {"vertex": id})
		Mode.CITY: _submit(G.BUILD_CITY, {"vertex": id})


func _on_trade_pressed() -> void:
	_submit(G.TRADE_BANK, {"give": _give_option.get_selected_id(), "receive": _receive_option.get_selected_id()})


func _unhandled_input(event: InputEvent) -> void:
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	if cancel and _mode != Mode.NONE:
		_mode = Mode.NONE
		_refresh()
		get_viewport().set_input_as_handled()


# --- Partida -> interfaz --------------------------------------------------------

func _on_action_applied(action: GameAction) -> void:
	var name := _player_name(action.player_id)
	match action.type:
		G.ROLL:
			var dice: Array = action.data["dice"]
			_add_log("%s tira %d + %d = [b]%d[/b]." % [name, dice[0], dice[1], dice[0] + dice[1]])
		G.BUILD_ROAD:
			_add_log("%s construye un camino." % name)
		G.BUILD_SETTLEMENT:
			_add_log("%s construye un poblado." % name)
		G.BUILD_CITY:
			_add_log("%s mejora un poblado a ciudad." % name)
		G.TRADE_BANK:
			_add_log("%s cambia %d %s por 1 %s." % [name, action.data["ratio"], ArchDefs.RESOURCE_NAMES[action.data["give"]], ArchDefs.RESOURCE_NAMES[action.data["receive"]]])
	var turn_changed := game.turns.current != action.player_id
	if action.type != G.TRADE_BANK:
		_mode = Mode.NONE
	if game.phase == G.Phase.ROLL and action.type == G.BUILD_ROAD:
		_add_log("Termina la colocación inicial. ¡Empieza la partida!")
	_refresh()
	_board_view.refresh()
	if turn_changed and not game.finished:
		_show_banner()


func _on_game_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"production":
			var any := false
			for p in data["gains"].size():
				var text := ArchipelagoGame.format_resources(data["gains"][p])
				if text != "":
					any = true
					_add_log("  %s recibe %s." % [_player_name(p), text])
			for r in data["shortages"]:
				_add_log("  La banca no tiene bastante %s: nadie lo recibe." % ArchDefs.RESOURCE_NAMES[r])
			if not any and data["shortages"].is_empty():
				_add_log("  Nadie produce.")
		&"setup_resources":
			var text := ArchipelagoGame.format_resources(data["gains"])
			if text != "":
				_add_log("  %s recibe %s." % [_player_name(data["player"]), text])
		&"seven":
			_add_log("  ¡Un 7! (El bandido llegará en la fase 3.)")


func _on_game_finished(winner_ids: Array[int]) -> void:
	# Se emite dentro de la acción ganadora: se muestra después de registrarla.
	_show_victory.call_deferred(winner_ids)


func _show_victory(winner_ids: Array[int]) -> void:
	var winner := game.players[winner_ids[0]]
	_add_log("[b]¡%s gana con %d puntos![/b]" % [winner.display_name, game.victory_points(winner.id)])
	var title: Label = _victory.find_child("Title", true, false)
	title.text = "¡%s gana!" % winner.display_name
	title.add_theme_color_override("font_color", winner.color.lightened(0.2))
	_victory.visible = true
	_layout()


func _on_hovered(kind: ArchBoardView.Pick, id: int) -> void:
	var board := game.board
	match kind:
		Pick.TILE:
			_hover_label.text = _tile_text(id)
		Pick.VERTEX:
			var parts: Array[String] = []
			for t in board.grid.vertex_tiles[id]:
				parts.append(_tile_text(t))
			var text := "Esquina: %s" % ", ".join(parts)
			var port = board.vertex_port(id)
			if port != null:
				text += ". Puerto %s" % ArchDefs.port_label(port["type"])
			_hover_label.text = text
		Pick.EDGE:
			var port = board.edge_port(id)
			_hover_label.text = "Lado" + (". Puerto %s" % ArchDefs.port_label(port["type"]) if port != null else "")
		_:
			_hover_label.text = ""


# --- Utilidades -------------------------------------------------------------------

func _show_banner() -> void:
	var player := game.current_player()
	_banner.text = "Turno de %s" % player.display_name
	_banner.add_theme_color_override("font_color", player.color.lightened(0.3))
	var tween := create_tween()
	_banner.modulate.a = 1.0
	tween.tween_interval(0.9)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _add_log(line: String) -> void:
	_log.append(line)
	if _log.size() > 200:
		_log.pop_front()
	_log_label.text = "\n".join(_log)


func _player_name(pid: int) -> String:
	var p := game.players[pid]
	return "[color=#%s]%s[/color]" % [p.color.lightened(0.2).to_html(false), p.display_name]


func _tile_text(t: int) -> String:
	var board := game.board
	var text: String = ArchDefs.TERRAIN_NAMES[board.tile_terrain[t]]
	if board.tile_number[t] > 0:
		text += " (%d)" % board.tile_number[t]
	return text


static func _mode_action(mode: Mode) -> StringName:
	match mode:
		Mode.ROAD: return G.BUILD_ROAD
		Mode.SETTLEMENT: return G.BUILD_SETTLEMENT
	return G.BUILD_CITY
