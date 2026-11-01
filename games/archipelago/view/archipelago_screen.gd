extends Control
## Pantalla de una partida de Archipiélago (multijugador local por turnos).
##
## Izquierda: jugadores y registro. Centro: tablero. Derecha: acciones del
## jugador en turno. Las decisiones que necesitan más datos (descartes,
## ofertas, cartas de desarrollo...) se piden en ventanas modales.
## La pantalla nunca cambia el estado directamente: crea GameActions y las
## envía a la partida con game.submit().

const G := preload("res://games/archipelago/logic/archipelago_game.gd")
const Pick := ArchBoardView.Pick
const DevCard := ArchDefs.DevCard

const BACKGROUND := Color("163246")
const LEFT_WIDTH := 270.0
const RIGHT_WIDTH := 300.0
const MARGIN := 12.0
const RESOURCE_COLORS := ArchBoardView.RESOURCE_COLORS
const HIGHLIGHT := Color("ffd166")
## Pausa entre jugadas de la IA (normal / rápida), en segundos.
const AI_DELAY := 0.6
const AI_DELAY_FAST := 0.12

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
var _points_label: Label
var _prompt_label: Label
var _error_label: Label
var _dice_label: Label
var _roll_button: Button
var _hand_box: GridContainer
var _build_buttons := {}
var _dev_box: VBoxContainer
var _bank_button: Button
var _players_trade_button: Button
var _end_button: Button
var _banner: Label
var _victory: PanelContainer

var _hand_label: Label
var _ai_fast_toggle: CheckButton
## IA de cada jugador controlado por el ordenador (pid -> ArchAI).
var _ais := {}
## Evita jugadas duplicadas de la IA y jugadas de una partida anterior.
var _ai_pending := false
var _ai_generation := 0
## Jugador cuya mano se muestra: el humano en turno, o el último humano que
## jugó mientras juegan las IAs.
var _viewer := 0

## Ventana modal abierta (null si no hay) y su identificador.
var _dialog: Control
var _dialog_key := ""


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
	_close_dialog()
	game = ArchipelagoGame.new()
	game.setup(App.session_players(), seed)
	game.action_applied.connect(_on_action_applied)
	game.event.connect(_on_game_event)
	game.game_finished.connect(_on_game_finished)
	_board_view.game = game
	_ais.clear()
	_viewer = -1
	for p in game.players:
		if p.is_ai:
			var ai := ArchAI.new(p.id, p.ai_level, seed)
			ai.observe(game)
			_ais[p.id] = ai
		elif _viewer == -1:
			_viewer = p.id
	_viewer = maxi(_viewer, 0)
	_ai_pending = false
	_ai_generation += 1
	_log.clear()
	_log_label.clear()
	_mode = Mode.NONE
	_victory.visible = false
	_add_log("Partida nueva (semilla %d). Colocación inicial." % seed)
	_refresh()
	_layout()
	_show_banner("Turno de %s" % game.current_player().display_name, game.current_player().color)


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
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	return box


func _label(text: String = "", font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String, callback: Callable, font_size: int = 15) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(callback)
	return button


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
	_log_label.add_theme_font_size_override("bold_font_size", 13)
	box.add_child(_log_label)
	_hover_label = _label("", 13)
	_hover_label.modulate = Color(1, 1, 1, 0.7)
	_hover_label.custom_minimum_size = Vector2(0, 36)
	box.add_child(_hover_label)
	_ai_fast_toggle = CheckButton.new()
	_ai_fast_toggle.text = "IA rápida"
	box.add_child(_ai_fast_toggle)
	box.add_child(_button("Volver al menú", App.go_to_menu))


func _build_right_panel() -> void:
	var box := _panel(RIGHT_WIDTH)
	var header := HBoxContainer.new()
	_turn_label = _label("", 22)
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_turn_label.clip_text = true
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_turn_label)
	_points_label = _label("", 15)
	_points_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(_points_label)
	box.add_child(header)
	_prompt_label = _label("", 14)
	_prompt_label.custom_minimum_size = Vector2(0, 40)
	box.add_child(_prompt_label)
	_error_label = _label("", 13)
	_error_label.add_theme_color_override("font_color", Color("ff8a80"))
	box.add_child(_error_label)

	var dice_row := HBoxContainer.new()
	_roll_button = _button("Tirar dados", func() -> void: _submit(G.ROLL))
	_roll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_row.add_child(_roll_button)
	_dice_label = _label("", 20)
	_dice_label.custom_minimum_size = Vector2(120, 0)
	_dice_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_row.add_child(_dice_label)
	box.add_child(dice_row)

	_hand_label = _label("", 13)
	box.add_child(_hand_label)
	_hand_box = GridContainer.new()
	_hand_box.columns = 5
	_hand_box.add_theme_constant_override("h_separation", 4)
	box.add_child(_hand_box)

	box.add_child(_label("Construir", 13))
	var build_grid := GridContainer.new()
	build_grid.columns = 2
	build_grid.add_theme_constant_override("h_separation", 6)
	build_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(build_grid)
	for entry in [[Mode.ROAD, G.BUILD_ROAD, "Camino"], [Mode.SETTLEMENT, G.BUILD_SETTLEMENT, "Poblado"], [Mode.CITY, G.BUILD_CITY, "Ciudad"]]:
		var button := _build_button("%s\n%s" % [entry[2], _cost_text(G.COSTS[entry[1]])], _on_build_pressed.bind(entry[0]))
		button.toggle_mode = true
		build_grid.add_child(button)
		_build_buttons[entry[0]] = button
	var buy := _build_button("Carta desarrollo\n%s" % _cost_text(G.COSTS[G.BUY_DEV]), func() -> void: _submit(G.BUY_DEV))
	build_grid.add_child(buy)
	_build_buttons["dev"] = buy

	box.add_child(_label("Cartas de desarrollo", 13))
	_dev_box = VBoxContainer.new()
	_dev_box.add_theme_constant_override("separation", 4)
	box.add_child(_dev_box)

	box.add_child(_label("Comerciar", 13))
	var trade_row := HBoxContainer.new()
	_bank_button = _button("Con la banca", _open_bank_dialog)
	_bank_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_row.add_child(_bank_button)
	_players_trade_button = _button("Con jugadores", _open_offer_dialog)
	_players_trade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_row.add_child(_players_trade_button)
	box.add_child(trade_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_end_button = _button("Terminar turno", func() -> void: _submit(G.END_TURN), 16)
	_end_button.custom_minimum_size = Vector2(0, 40)
	box.add_child(_end_button)


func _build_button(text: String, callback: Callable) -> Button:
	var button := _button(text, callback, 13)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 46)
	button.clip_text = true
	return button


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
	var details := _label("", 15)
	details.name = "Details"
	details.autowrap_mode = TextServer.AUTOWRAP_OFF
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(details)
	box.add_child(_button("Nueva partida (mismos jugadores)", func() -> void: _start(BGCRng.random_seed())))
	box.add_child(_button("Volver al menú", App.go_to_menu))


func _board_rect() -> Rect2:
	var x0 := LEFT_WIDTH + MARGIN * 2
	return Rect2(x0, MARGIN, maxf(100.0, size.x - x0 - RIGHT_WIDTH - MARGIN * 2), size.y - MARGIN * 2)


func _layout() -> void:
	if _board_view == null:
		return
	var left: Control = _players_box.get_parent().get_parent().get_parent()
	var right: Control = _turn_label.get_parent().get_parent().get_parent().get_parent()
	left.position = Vector2(MARGIN, MARGIN)
	left.size = Vector2(LEFT_WIDTH, size.y - MARGIN * 2)
	right.position = Vector2(size.x - RIGHT_WIDTH - MARGIN, MARGIN)
	right.size = Vector2(RIGHT_WIDTH, size.y - MARGIN * 2)
	var board_rect := _board_rect()
	_board_view.fit(board_rect)
	_banner.position = board_rect.position
	_banner.size = board_rect.size
	_victory.reset_size()
	_victory.position = board_rect.get_center() - _victory.size / 2.0


# --- Estado -> interfaz -------------------------------------------------------

func _refresh() -> void:
	var pid := game.turns.current
	var player := game.players[pid]
	var human_turn := not player.is_ai
	var main := game.phase == G.Phase.MAIN and game.trade_offer.is_empty() and human_turn
	if human_turn or _ais.size() == game.players.size():
		_viewer = pid
	var viewer := game.players[_viewer]

	_refresh_players()

	_turn_label.text = player.display_name + (" (IA)" if player.is_ai else "")
	_turn_label.add_theme_color_override("font_color", player.color.lightened(0.2))
	var hidden: int = game.dev_hands[_viewer][DevCard.MONUMENT]
	_points_label.text = "%d PV" % game.victory_points(_viewer) + (" (%d ocultos)" % hidden if hidden > 0 else "")
	if _viewer != pid:
		_points_label.text = "%s: %s" % [viewer.display_name, _points_label.text]
	_points_label.tooltip_text = "Puntos de %s" % viewer.display_name
	_prompt_label.text = _prompt_text()

	_roll_button.disabled = not human_turn or game.validate(GameAction.new(G.ROLL, pid)) != ""
	_dice_label.text = "" if game.last_roll.is_empty() else "%d + %d = %d" % [game.last_roll[0], game.last_roll[1], game.last_roll[0] + game.last_roll[1]]

	_hand_label.text = "Mano de %s" % viewer.display_name
	_clear(_hand_box)
	for r in G.RESOURCE_COUNT:
		_hand_box.add_child(_resource_card(r, game.hands[_viewer][r]))

	for mode in [Mode.ROAD, Mode.SETTLEMENT, Mode.CITY]:
		var button: Button = _build_buttons[mode]
		var error := game.build_error(pid, _mode_action(mode)) if human_turn else "Es el turno de la IA"
		button.disabled = error != ""
		button.tooltip_text = error
		button.set_pressed_no_signal(_mode == mode)
	var buy_error := game.validate(GameAction.new(G.BUY_DEV, pid)) if main else "Ahora no se puede comprar"
	_build_buttons["dev"].disabled = buy_error != ""
	_build_buttons["dev"].tooltip_text = buy_error if buy_error != "" else "Quedan %d cartas en el mazo" % game.dev_deck.size()

	_refresh_dev_cards(_viewer, human_turn)

	_bank_button.disabled = not main
	_players_trade_button.disabled = not main
	_end_button.disabled = not main
	_update_targets()
	_update_state_dialog()
	_schedule_ai()


func _refresh_players() -> void:
	_clear(_players_box)
	for p in game.players:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = p.color
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _label(p.display_name + (" (IA)" if p.is_ai else ""), 15)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if p.id == game.turns.current and not game.finished:
			name_label.text = "▶ " + name_label.text
			name_label.add_theme_color_override("font_color", HIGHLIGHT)
		row.add_child(name_label)
		var points := _label("%d PV" % game.public_victory_points(p.id), 15)
		points.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(points)
		column.add_child(row)

		var details := "   %d cartas · %d desarrollo · %d milic. · camino %d" % [
			game.hand_size(p.id), game.dev_hand_size(p.id), game.militia_played[p.id], game.road_lengths[p.id]]
		var info := _label(details, 11)
		info.autowrap_mode = TextServer.AUTOWRAP_OFF
		info.modulate = Color(1, 1, 1, 0.7)
		column.add_child(info)
		var awards: Array[String] = []
		if game.longest_road_owner == p.id:
			awards.append("★ Camino más largo")
		if game.largest_army_owner == p.id:
			awards.append("★ Mayor milicia")
		if not awards.is_empty():
			var award := _label("   " + "   ".join(awards), 12)
			award.add_theme_color_override("font_color", HIGHLIGHT)
			column.add_child(award)
		_players_box.add_child(column)


func _refresh_dev_cards(pid: int, can_play: bool) -> void:
	_clear(_dev_box)
	var any := false
	for card in ArchDefs.DEV_NAMES:
		var count: int = game.dev_hands[pid][card]
		if count == 0:
			continue
		any = true
		var new_count: int = game.dev_new[pid][card]
		var text := "%s ×%d" % [ArchDefs.DEV_NAMES[card], count]
		if new_count > 0 and card != DevCard.MONUMENT:
			text += " (%d nueva%s)" % [new_count, "s" if new_count > 1 else ""]
		if card == DevCard.MONUMENT:
			var label := _label(text + "  · +%d PV" % count, 13)
			label.tooltip_text = ArchDefs.DEV_DESCRIPTIONS[card]
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			_dev_box.add_child(label)
			continue
		var button := _button("Jugar " + text, _on_play_dev.bind(card), 13)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var error := game.validate(GameAction.new(G.PLAY_DEV, pid, _dev_probe_data(card)))
		button.disabled = error != "" or not can_play
		button.tooltip_text = ArchDefs.DEV_DESCRIPTIONS[card] + ("\n" + error if error != "" else "")
		_dev_box.add_child(button)
	if not any:
		var none := _label("Ninguna", 13)
		none.modulate = Color(1, 1, 1, 0.5)
		_dev_box.add_child(none)


## Datos de ejemplo para saber si una carta se puede jugar ahora.
func _dev_probe_data(card: int) -> Dictionary:
	var data := {"card": card}
	if card == DevCard.MONOPOLY:
		data["resource"] = 0
	elif card == DevCard.HARVEST:
		var best := game.bank.find(game.bank.max())
		data["resources"] = [best, best]
	return data


func _prompt_text() -> String:
	var pid := game.turns.current
	if not game.finished:
		var actor: int = game.players_to_act()[0]
		if game.players[actor].is_ai:
			return "%s (IA) está pensando…" % game.players[actor].display_name
	if not game.trade_offer.is_empty():
		return "Esperando respuesta a la oferta…"
	match game.phase:
		G.Phase.SETUP:
			var placed: int = G.PIECES["settlement"] - game.pieces[pid]["settlement"]
			var round_text := "%d.ª" % (placed + 1 if game.setup_vertex == -1 else placed)
			if game.setup_vertex == -1:
				return "Colocación inicial (%s ronda): elige dónde poner un poblado." % round_text
			return "Colocación inicial (%s ronda): pon un camino junto a tu poblado." % round_text
		G.Phase.ROLL:
			return "Tira los dados (o juega antes un Miliciano)."
		G.Phase.DISCARD:
			return "Ha salido un 7: hay jugadores que deben descartar."
		G.Phase.ROBBER:
			return "Mueve el bandido: elige una casilla."
		G.Phase.ROAD_BUILDING:
			return "Ingenieros: coloca %d camino%s gratis." % [game.free_roads, "s" if game.free_roads > 1 else ""]
		G.Phase.MAIN:
			match _mode:
				Mode.ROAD: return "Elige dónde construir el camino. Clic derecho para cancelar."
				Mode.SETTLEMENT: return "Elige dónde construir el poblado. Clic derecho para cancelar."
				Mode.CITY: return "Elige qué poblado mejorar. Clic derecho para cancelar."
			return "Construye, comercia o termina tu turno."
	return "Fin de la partida."


func _update_targets() -> void:
	var pid := game.turns.current
	if _dialog != null or not game.trade_offer.is_empty() or game.current_player().is_ai:
		_board_view.set_targets(Pick.NONE, [])
		return
	match game.phase:
		G.Phase.SETUP:
			if game.setup_vertex == -1:
				_board_view.set_targets(Pick.VERTEX, game.legal_settlement_vertices(pid))
			else:
				_board_view.set_targets(Pick.EDGE, game.legal_road_edges(pid))
			return
		G.Phase.ROBBER:
			_board_view.set_targets(Pick.TILE, game.bandit_tiles())
			return
		G.Phase.ROAD_BUILDING:
			_board_view.set_targets(Pick.EDGE, game.legal_road_edges(pid))
			return
	match _mode:
		Mode.ROAD: _board_view.set_targets(Pick.EDGE, game.legal_road_edges(pid))
		Mode.SETTLEMENT: _board_view.set_targets(Pick.VERTEX, game.legal_settlement_vertices(pid))
		Mode.CITY: _board_view.set_targets(Pick.VERTEX, game.legal_city_vertices(pid))
		_: _board_view.set_targets(Pick.NONE, [])


func _resource_card(r: int, count: int, compact: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = RESOURCE_COLORS[r]
	style.set_corner_radius_all(6)
	style.content_margin_top = 2 if compact else 4
	style.content_margin_bottom = 2 if compact else 4
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
			var short: String = ArchDefs.RESOURCE_NAMES[r].substr(0, 3)
			parts.append(short if cost[r] == 1 else "%d %s" % [cost[r], short])
	return ", ".join(parts)


# --- Ventanas modales -------------------------------------------------------------

## Abre una ventana modal sobre el tablero y devuelve su contenedor.
func _open_dialog(key: String, title: String, title_color: Color = Color.WHITE) -> VBoxContainer:
	_close_dialog()
	_dialog_key = key
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var rect := _board_rect()
	shade.position = rect.position
	shade.size = rect.size
	add_child(shade)
	_dialog = shade

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(420, rect.size.x - 20), 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title_label := _label(title, 22)
	title_label.add_theme_color_override("font_color", title_color)
	box.add_child(title_label)
	_board_view.set_targets(Pick.NONE, [])
	return box


func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	_dialog_key = ""


func _cancel_dialog() -> void:
	_close_dialog()
	_refresh()


## Las ventanas que dependen del estado de la partida (descartes y ofertas)
## se abren y cierran solas.
func _update_state_dialog() -> void:
	var actor: int = game.players_to_act()[0] if not game.finished else -1
	if actor >= 0 and game.players[actor].is_ai:
		if _dialog_key.begins_with("state:"):
			_close_dialog()
		return
	if game.phase == G.Phase.DISCARD:
		var pid: int = game.players_to_act()[0]
		if not _dialog_key.begins_with("state:discard:%d:" % pid):
			_open_discard_dialog(pid, "state:discard:%d:%d" % [pid, game.history.size()])
	elif not game.trade_offer.is_empty():
		if not _dialog_key.begins_with("state:trade"):
			_open_trade_response_dialog("state:trade:%d" % game.history.size())
	elif _dialog_key.begins_with("state:"):
		_close_dialog()
		_update_targets()


func _amount_rows(box: VBoxContainer, maxima: Array, on_change: Callable) -> Array[SpinBox]:
	var spins: Array[SpinBox] = []
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for r in G.RESOURCE_COUNT:
		var swatch := ColorRect.new()
		swatch.color = RESOURCE_COLORS[r]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(swatch)
		var limited: bool = maxima[r] < 99
		var name_label := _label("%s (%d)" % [ArchDefs.RESOURCE_NAMES[r], maxima[r]] if limited else ArchDefs.RESOURCE_NAMES[r], 15)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = mini(maxima[r], G.BANK_STOCK)
		spin.editable = maxima[r] > 0
		spin.value_changed.connect(func(_v: float) -> void: on_change.call())
		grid.add_child(spin)
		spins.append(spin)
	return spins


func _values(spins: Array[SpinBox]) -> Array[int]:
	var result: Array[int] = []
	for spin in spins:
		result.append(int(spin.value))
	return result


func _open_discard_dialog(pid: int, key: String) -> void:
	var player := game.players[pid]
	var needed: int = game.pending_discards[pid]
	var box := _open_dialog(key, "%s: descarta %d cartas" % [player.display_name, needed], player.color.lightened(0.3))
	box.add_child(_label("Ha salido un 7 y tienes más de %d cartas. Elige cuáles devuelves a la banca." % G.DISCARD_LIMIT, 14))
	var confirm := Button.new()
	var counter := _label("", 14)
	var spins: Array[SpinBox] = []
	var update := func() -> void:
		var total := 0
		for spin in spins:
			total += int(spin.value)
		counter.text = "Seleccionadas: %d de %d" % [total, needed]
		confirm.disabled = total != needed
	spins.assign(_amount_rows(box, game.hands[pid], update))
	box.add_child(counter)
	confirm.text = "Descartar"
	confirm.pressed.connect(func() -> void: _submit(G.DISCARD, {"cards": _values(spins)}, pid))
	box.add_child(confirm)
	update.call()


func _open_trade_response_dialog(key: String) -> void:
	var offer := game.trade_offer
	var from := game.players[offer["from"]]
	var to := game.players[offer["to"]]
	var box := _open_dialog(key, "Oferta para %s" % to.display_name, to.color.lightened(0.3))
	box.add_child(_label("%s te da: %s" % [from.display_name, ArchipelagoGame.format_resources(offer["give"])], 16))
	box.add_child(_label("A cambio te pide: %s" % ArchipelagoGame.format_resources(offer["receive"]), 16))
	box.add_child(_label("Tu mano:", 13))
	var hand := GridContainer.new()
	hand.columns = 5
	for r in G.RESOURCE_COUNT:
		hand.add_child(_resource_card(r, game.hands[to.id][r], true))
	box.add_child(hand)
	var row := HBoxContainer.new()
	var accept := _button("Aceptar", func() -> void: _submit(G.ACCEPT_TRADE, {}, to.id))
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var error := game.validate(GameAction.new(G.ACCEPT_TRADE, to.id))
	accept.disabled = error != ""
	accept.tooltip_text = error
	row.add_child(accept)
	var reject := _button("Rechazar", func() -> void: _submit(G.REJECT_TRADE, {}, to.id))
	reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reject)
	box.add_child(row)
	box.add_child(_button("%s retira la oferta" % from.display_name, func() -> void: _submit(G.REJECT_TRADE, {}, from.id), 13))


func _open_victim_dialog(tile: int, victims: Array[int]) -> void:
	var box := _open_dialog("ui:victim", "¿A quién robas?")
	for victim in victims:
		var p := game.players[victim]
		var button := _button("%s (%d cartas)" % [p.display_name, game.hand_size(victim)], func() -> void:
			_submit(G.MOVE_BANDIT, {"tile": tile, "victim": victim}))
		button.add_theme_color_override("font_color", p.color.lightened(0.3))
		box.add_child(button)
	box.add_child(_button("Cancelar", _cancel_dialog, 13))


func _open_bank_dialog() -> void:
	var pid := game.turns.current
	var box := _open_dialog("ui:bank", "Comerciar con la banca")
	box.add_child(_label("Das varias cartas de un recurso por una de otro. Los puertos mejoran el cambio.", 13))
	var give := OptionButton.new()
	var receive := OptionButton.new()
	var best := 0
	for r in G.RESOURCE_COUNT:
		give.add_item("%s (%d:1, tienes %d)" % [ArchDefs.RESOURCE_NAMES[r], game.trade_ratio(pid, r), game.hands[pid][r]], r)
		receive.add_item(ArchDefs.RESOURCE_NAMES[r], r)
		if game.hands[pid][r] - game.trade_ratio(pid, r) > game.hands[pid][best] - game.trade_ratio(pid, best):
			best = r
	give.select(best)
	receive.select((best + 1) % G.RESOURCE_COUNT)
	box.add_child(_label("Das:", 14))
	box.add_child(give)
	box.add_child(_label("Recibes:", 14))
	box.add_child(receive)
	var confirm := Button.new()
	var update := func() -> void:
		var g := give.get_selected_id()
		var r := receive.get_selected_id()
		confirm.text = "Dar %d %s por 1 %s" % [game.trade_ratio(pid, g), ArchDefs.RESOURCE_NAMES[g], ArchDefs.RESOURCE_NAMES[r]]
		var error := game.validate(GameAction.new(G.TRADE_BANK, pid, {"give": g, "receive": r}))
		confirm.disabled = error != ""
		confirm.tooltip_text = error
	give.item_selected.connect(func(_i: int) -> void: update.call())
	receive.item_selected.connect(func(_i: int) -> void: update.call())
	confirm.pressed.connect(func() -> void:
		_submit(G.TRADE_BANK, {"give": give.get_selected_id(), "receive": receive.get_selected_id()}))
	box.add_child(confirm)
	box.add_child(_button("Cerrar", _cancel_dialog, 13))
	update.call()


func _open_offer_dialog() -> void:
	var pid := game.turns.current
	var box := _open_dialog("ui:offer", "Proponer un intercambio")
	var partner := OptionButton.new()
	for p in game.players:
		if p.id != pid:
			partner.add_item("%s (%d cartas)" % [p.display_name, game.hand_size(p.id)], p.id)
	box.add_child(partner)
	var confirm := Button.new()
	var give_spins: Array[SpinBox] = []
	var receive_spins: Array[SpinBox] = []
	var update := func() -> void:
		var data := {"to": partner.get_selected_id(), "give": _values(give_spins), "receive": _values(receive_spins)}
		var error := game.validate(GameAction.new(G.OFFER_TRADE, pid, data))
		confirm.disabled = error != ""
		confirm.tooltip_text = error
	box.add_child(_label("Das:", 14))
	give_spins.assign(_amount_rows(box, game.hands[pid], update))
	box.add_child(_label("Pides:", 14))
	receive_spins.assign(_amount_rows(box, [99, 99, 99, 99, 99], update))
	partner.item_selected.connect(func(_i: int) -> void: update.call())
	confirm.text = "Proponer"
	confirm.pressed.connect(func() -> void:
		_submit(G.OFFER_TRADE, {"to": partner.get_selected_id(), "give": _values(give_spins), "receive": _values(receive_spins)}))
	box.add_child(confirm)
	box.add_child(_button("Cancelar", _cancel_dialog, 13))
	update.call()


func _open_harvest_dialog() -> void:
	var box := _open_dialog("ui:harvest", ArchDefs.DEV_NAMES[DevCard.HARVEST])
	box.add_child(_label("Elige 2 recursos de la banca (pueden ser iguales).", 14))
	var options: Array[OptionButton] = []
	for i in 2:
		var option := OptionButton.new()
		for r in G.RESOURCE_COUNT:
			option.add_item("%s (banca: %d)" % [ArchDefs.RESOURCE_NAMES[r], game.bank[r]], r)
		box.add_child(option)
		options.append(option)
	box.add_child(_button("Tomar", func() -> void:
		_submit(G.PLAY_DEV, {"card": DevCard.HARVEST, "resources": [options[0].get_selected_id(), options[1].get_selected_id()]})))
	box.add_child(_button("Cancelar", _cancel_dialog, 13))


func _open_monopoly_dialog() -> void:
	var box := _open_dialog("ui:monopoly", ArchDefs.DEV_NAMES[DevCard.MONOPOLY])
	box.add_child(_label("Elige un recurso: los demás jugadores te darán todas sus cartas de ese recurso.", 14))
	for r in G.RESOURCE_COUNT:
		box.add_child(_button(ArchDefs.RESOURCE_NAMES[r], func() -> void:
			_submit(G.PLAY_DEV, {"card": DevCard.MONOPOLY, "resource": r})))
	box.add_child(_button("Cancelar", _cancel_dialog, 13))


# --- IA ---------------------------------------------------------------------------

## Si le toca a una IA, programa su siguiente jugada tras una pausa.
func _schedule_ai() -> void:
	if game.finished or _ai_pending or not is_inside_tree():
		return
	var actor: int = game.players_to_act()[0]
	if not _ais.has(actor):
		return
	_ai_pending = true
	var delay := AI_DELAY_FAST if _ai_fast_toggle.button_pressed else AI_DELAY
	if game.phase == G.Phase.SETUP:
		delay *= 0.6
	get_tree().create_timer(delay).timeout.connect(_run_ai.bind(_ai_generation))


func _run_ai(generation: int) -> void:
	if generation != _ai_generation:
		return  # pertenece a una partida anterior
	_ai_pending = false
	if game.finished:
		return
	var actor: int = game.players_to_act()[0]
	if not _ais.has(actor):
		return
	var action: GameAction = _ais[actor].choose_action(game)
	if action == null:
		push_warning("La IA de %s no encontró ninguna acción" % game.players[actor].display_name)
		return
	var error := game.submit(action)
	if error != "":
		push_warning("Acción ilegal de la IA: %s (%s)" % [action, error])


# --- Interfaz -> acciones -------------------------------------------------------

## Envía una acción (por defecto, del jugador en turno) y muestra el error si
## se rechaza.
func _submit(type: StringName, data: Dictionary = {}, pid: int = -1) -> void:
	var actor := game.turns.current if pid < 0 else pid
	var error := game.submit(GameAction.new(type, actor, data))
	_error_label.text = error


func _on_build_pressed(mode: Mode) -> void:
	_mode = Mode.NONE if _mode == mode else mode
	_error_label.text = ""
	_refresh()


func _on_play_dev(card: int) -> void:
	_error_label.text = ""
	match card:
		DevCard.HARVEST: _open_harvest_dialog()
		DevCard.MONOPOLY: _open_monopoly_dialog()
		_: _submit(G.PLAY_DEV, {"card": card})


func _on_board_clicked(kind: ArchBoardView.Pick, id: int) -> void:
	match game.phase:
		G.Phase.SETUP:
			if kind == Pick.VERTEX:
				_submit(G.BUILD_SETTLEMENT, {"vertex": id})
			elif kind == Pick.EDGE:
				_submit(G.BUILD_ROAD, {"edge": id})
			return
		G.Phase.ROBBER:
			var victims := game.bandit_victims(game.turns.current, id)
			if victims.size() > 1:
				_open_victim_dialog(id, victims)
			else:
				_submit(G.MOVE_BANDIT, {"tile": id, "victim": victims[0] if victims.size() == 1 else -1})
			return
		G.Phase.ROAD_BUILDING:
			_submit(G.BUILD_ROAD, {"edge": id})
			return
	match _mode:
		Mode.ROAD: _submit(G.BUILD_ROAD, {"edge": id})
		Mode.SETTLEMENT: _submit(G.BUILD_SETTLEMENT, {"vertex": id})
		Mode.CITY: _submit(G.BUILD_CITY, {"vertex": id})


func _unhandled_input(event: InputEvent) -> void:
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	if cancel and _mode != Mode.NONE:
		_mode = Mode.NONE
		_refresh()
		get_viewport().set_input_as_handled()


# --- Partida -> interfaz --------------------------------------------------------

func _on_action_applied(action: GameAction) -> void:
	var name := _player_name(action.player_id)
	var data := action.data
	match action.type:
		G.ROLL:
			var dice: Array = data["dice"]
			_add_log("%s tira %d + %d = [b]%d[/b]." % [name, dice[0], dice[1], dice[0] + dice[1]])
		G.BUILD_ROAD:
			_add_log("%s construye un camino." % name)
		G.BUILD_SETTLEMENT:
			_add_log("%s construye un poblado." % name)
		G.BUILD_CITY:
			_add_log("%s mejora un poblado a ciudad." % name)
		G.TRADE_BANK:
			_add_log("%s cambia %d %s por 1 %s con la banca." % [name, data["ratio"], ArchDefs.RESOURCE_NAMES[data["give"]], ArchDefs.RESOURCE_NAMES[data["receive"]]])
		G.DISCARD:
			_add_log("  %s descarta %s." % [name, ArchipelagoGame.format_resources(data["cards"])])
		G.MOVE_BANDIT:
			var victim := int(data.get("victim", -1))
			if victim >= 0:
				_add_log("%s mueve el bandido y roba una carta a %s." % [name, _player_name(victim)])
			else:
				_add_log("%s mueve el bandido." % name)
		G.BUY_DEV:
			_add_log("%s compra una carta de desarrollo." % name)
		G.PLAY_DEV:
			var card: int = data["card"]
			var text := "%s juega [b]%s[/b]" % [name, ArchDefs.DEV_NAMES[card]]
			match card:
				DevCard.HARVEST:
					var amounts := [0, 0, 0, 0, 0]
					for r in data["resources"]:
						amounts[r] += 1
					text += " y toma %s" % ArchipelagoGame.format_resources(amounts)
				DevCard.MONOPOLY:
					text += " (%s) y se lleva %d cartas" % [ArchDefs.RESOURCE_NAMES[data["resource"]], data["taken"]]
			_add_log(text + ".")
		G.OFFER_TRADE:
			_add_log("%s ofrece a %s: %s por %s." % [name, _player_name(data["to"]), ArchipelagoGame.format_resources(data["give"]), ArchipelagoGame.format_resources(data["receive"])])
		G.ACCEPT_TRADE:
			_add_log("  %s acepta el intercambio." % name)
		G.REJECT_TRADE:
			var offer: Dictionary = data["offer"]
			_add_log("  %s %s la oferta." % [name, "retira" if action.player_id == offer["from"] else "rechaza"])

	if not action.type in [G.TRADE_BANK, G.OFFER_TRADE, G.REJECT_TRADE, G.ACCEPT_TRADE]:
		_mode = Mode.NONE
	if _dialog_key.begins_with("ui:"):
		_close_dialog()
	if game.phase == G.Phase.ROLL and action.type == G.BUILD_ROAD and game.history.size() == game.players.size() * 4:
		_add_log("Termina la colocación inicial. ¡Empieza la partida!")
	_refresh()
	_board_view.refresh()
	if game.turns.current != action.player_id and action.type in [G.END_TURN, G.BUILD_ROAD] and not game.finished:
		var p := game.current_player()
		_show_banner("Turno de %s" % p.display_name, p.color)


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
			_add_log("  ¡Un 7! El bandido se mueve.")
			_show_banner("¡7!", Color("ff8a80"))
		&"longest_road":
			if data["player"] >= 0:
				_add_log("[b]%s consigue el Camino más largo (%d).[/b]" % [_player_name(data["player"]), data["length"]])
			else:
				_add_log("Nadie tiene ya el Camino más largo.")
		&"largest_army":
			_add_log("[b]%s consigue la Mayor milicia (%d).[/b]" % [_player_name(data["player"]), data["count"]])


func _on_game_finished(winner_ids: Array[int]) -> void:
	# Se emite dentro de la acción ganadora: se muestra después de registrarla.
	_show_victory.call_deferred(winner_ids)


func _show_victory(winner_ids: Array[int]) -> void:
	_close_dialog()
	var winner := game.players[winner_ids[0]]
	_add_log("[b]¡%s gana con %d puntos![/b]" % [winner.display_name, game.victory_points(winner.id)])
	var title: Label = _victory.find_child("Title", true, false)
	title.text = "¡%s gana!" % winner.display_name
	title.add_theme_color_override("font_color", winner.color.lightened(0.2))
	var lines: Array[String] = []
	for p in game.players:
		lines.append("%s: %d puntos" % [p.display_name, game.victory_points(p.id)])
	var details: Label = _victory.find_child("Details", true, false)
	details.text = "\n".join(lines)
	_victory.visible = true
	_refresh()
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

func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color.lightened(0.3))
	var tween := create_tween()
	_banner.modulate.a = 1.0
	tween.tween_interval(0.9)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


## Vacía un contenedor al momento (queue_free solo borra al final del
## fotograma y, si se refresca dos veces seguidas, saldrían duplicados).
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_log(line: String) -> void:
	_log.append(line)
	if _log.size() > 300:
		_log = _log.slice(-200)
		_log_label.text = "\n".join(_log)
	elif _log.size() == 1:
		_log_label.text = line
	else:
		_log_label.append_text("\n" + line)


func _player_name(pid: int) -> String:
	var p := game.players[pid]
	return "[color=#%s]%s[/color]" % [p.color.lightened(0.2).to_html(false), p.display_name]


func _tile_text(t: int) -> String:
	var board := game.board
	var text: String = ArchDefs.TERRAIN_NAMES[board.tile_terrain[t]]
	if board.tile_number[t] > 0:
		text += " (%d)" % board.tile_number[t]
	if t == board.bandit_tile:
		text += " · bandido"
	return text


static func _mode_action(mode: Mode) -> StringName:
	match mode:
		Mode.ROAD: return G.BUILD_ROAD
		Mode.SETTLEMENT: return G.BUILD_SETTLEMENT
	return G.BUILD_CITY
