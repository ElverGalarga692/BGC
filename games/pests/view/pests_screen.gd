extends Control
## Pantalla de una partida de Pests!
##
## Izquierda: jugadores y registro. Centro: la casa. Derecha: las acciones
## del jugador en turno y su mano de cartas. La pantalla nunca cambia el
## estado directamente: crea GameActions y las envía con _send().

const G := preload("res://games/pests/logic/pests_game.gd")
const D := preload("res://games/pests/logic/pests_defs.gd")

const GAME_ID := "pests"
const BACKGROUND := Color("2b2320")
const LEFT_WIDTH := 290.0
const RIGHT_WIDTH := 320.0
const MARGIN := 12.0
const HIGHLIGHT := Color("ffd166")
const DIM := Color(1, 1, 1, 0.65)
const DEFENSIVE_COLOR := Color("a5d6a7")
const OFFENSIVE_COLOR := Color("ef9a9a")
const AI_DELAY := 0.55
const AI_DELAY_FAST := 0.1
## Opciones si la escena se abre directamente (F6).
const DEFAULT_OPTIONS := {"quick_species": true, "auto_house": true}
const DOOR_ARROWS := ["↑", "→", "↓", "←"]

var game: PestsGame
var _board: PestsBoardView
var _log: Array[String] = []
var _pending_log: Array[String] = []

var _players_box: VBoxContainer
var _log_label: RichTextLabel
var _hover_label: Label
var _turn_label: Label
var _prompt_label: Label
var _error_label: Label
var _status_label: RichTextLabel
var _actions_box: VBoxContainer
var _hand_label: Label
var _hand_box: VBoxContainer
var _end_button: Button
var _banner: Label
var _victory: PanelContainer
var _ai_fast_toggle: CheckButton

## Colocación de losetas: loseta elegida de la mano (-1 = ninguna) y giro.
var _tile_index := -1
var _tile_rotation := 0

var _ais := {}
var _ai_pending := false
var _ai_generation := 0
var _viewer := 0
var _network := false
var _local_seat := -1

var _dialog: Control
var _dialog_key := ""


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_board = PestsBoardView.new()
	add_child(_board)
	_board.hovered.connect(_on_hovered)
	_board.cell_clicked.connect(_on_cell_clicked)
	_build_left_panel()
	_build_right_panel()
	_build_overlays()
	Net.action_received.connect(_on_net_action)
	Net.action_requested.connect(_on_net_request)
	Net.action_rejected.connect(func(message: String) -> void:
		_error_label.text = message
		Sfx.play(&"error"))
	Net.seat_replaced.connect(_on_seat_replaced)
	resized.connect(_layout)
	_start(App.session_seed())


func _start(seed: int) -> void:
	_close_dialog()
	game = PestsGame.new()
	game.options = App.session.get("options", DEFAULT_OPTIONS).duplicate()
	game.setup(App.session_players(4), seed)
	_network = App.session.get("network", false)
	_local_seat = App.session.get("local_seat", -1)
	_create_ais(seed)
	var saved: Array = App.session.get("history", [])
	App.session.erase("history")
	var load_error := game.replay(saved) if not saved.is_empty() else ""
	game.action_applied.connect(_on_action_applied)
	game.event.connect(_on_game_event)
	game.game_finished.connect(_on_game_finished)
	_board.game = game
	_ai_pending = false
	_ai_generation += 1
	_log.clear()
	_pending_log.clear()
	_log_label.clear()
	_tile_index = -1
	_victory.visible = false
	if not saved.is_empty():
		_add_log("Partida guardada cargada (%d jugadas)." % game.history.size())
		if load_error != "":
			_add_log("[color=#ff8a80]No se pudo cargar del todo: %s[/color]" % load_error)
	elif _network:
		_add_log("Partida en red local. Juegas como %s." % game.players[_local_seat].display_name)
	else:
		_add_log("Partida nueva (semilla %d)." % seed)
	_add_log(_phase_intro())
	_layout()
	_refresh()
	_board.refresh()
	_show_banner("Turno de %s" % game.current_player().display_name, _color(game.turns.current))


func _create_ais(seed: int) -> void:
	_ais.clear()
	_viewer = -1
	var autoplay := OS.get_environment("BGC_AUTOPLAY") == "1"
	for p in game.players:
		var runs_here := p.is_ai and (not _network or Net.is_host)
		if runs_here or (autoplay and _is_local(p.id)):
			_ais[p.id] = PestsAI.new(p.id, p.ai_level if p.is_ai else PlayerInfo.AILevel.NORMAL, seed)
		if _viewer == -1 and _is_local(p.id):
			_viewer = p.id
	_viewer = maxi(_viewer, 0)


func _is_local(pid: int) -> bool:
	if game.players[pid].is_ai:
		return false
	return pid == _local_seat if _network else true


func _local_actor() -> int:
	if game.finished:
		return -1
	for pid in game.players_to_act():
		if _is_local(pid) and not _ais.has(pid):
			return pid
	return -1


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
	box.add_child(_label("Pests!", 24))
	var players_scroll := ScrollContainer.new()
	players_scroll.custom_minimum_size = Vector2(0, 250)
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(players_scroll)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll.add_child(_players_box)
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
	_hover_label.modulate = DIM
	_hover_label.custom_minimum_size = Vector2(0, 52)
	box.add_child(_hover_label)
	box.add_child(_button("Reglas", func() -> void: RulesPanel.open(self, GameRegistry.find(GAME_ID)["rules"])))
	_ai_fast_toggle = CheckButton.new()
	_ai_fast_toggle.text = "IA rápida"
	_ai_fast_toggle.button_pressed = App.get_setting("ai_fast", false)
	_ai_fast_toggle.toggled.connect(func(on: bool) -> void: App.set_setting("ai_fast", on))
	box.add_child(_ai_fast_toggle)
	box.add_child(_button("Volver al menú", App.go_to_menu))


func _build_right_panel() -> void:
	var box := _panel(RIGHT_WIDTH)
	_turn_label = _label("", 22)
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_turn_label.clip_text = true
	box.add_child(_turn_label)
	_prompt_label = _label("", 14)
	box.add_child(_prompt_label)
	_error_label = _label("", 13)
	_error_label.add_theme_color_override("font_color", Color("ff8a80"))
	box.add_child(_error_label)
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.add_theme_font_size_override("normal_font_size", 14)
	_status_label.add_theme_font_size_override("bold_font_size", 14)
	box.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 5)
	inner.add_child(_actions_box)
	inner.add_child(HSeparator.new())
	_hand_label = _label("", 13)
	inner.add_child(_hand_label)
	_hand_box = VBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 4)
	inner.add_child(_hand_box)
	_end_button = _button("Terminar turno", func() -> void: _submit(G.END_TURN), 16)
	_end_button.custom_minimum_size = Vector2(0, 40)
	box.add_child(_end_button)


func _action_button(text: String, callback: Callable, enabled: bool, tooltip: String = "") -> Button:
	var b := _button(text, callback, 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	_actions_box.add_child(b)
	return b


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
	var title := _label("", 34)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var details := _label("", 15)
	details.name = "Details"
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(details)
	var again := _button("Nueva partida (mismos jugadores)", func() -> void: _start(BGCRng.random_seed()))
	again.name = "Again"
	box.add_child(again)
	box.add_child(_button("Volver al menú", App.go_to_menu))


func _board_rect() -> Rect2:
	var x0 := LEFT_WIDTH + MARGIN * 2
	return Rect2(x0, MARGIN, maxf(100.0, size.x - x0 - RIGHT_WIDTH - MARGIN * 2), size.y - MARGIN * 2)


func _layout() -> void:
	var left: Control = _players_box.get_parent().get_parent().get_parent().get_parent()
	var right: Control = _turn_label.get_parent().get_parent().get_parent()
	left.position = Vector2(MARGIN, MARGIN)
	left.size = Vector2(LEFT_WIDTH, size.y - MARGIN * 2)
	right.position = Vector2(size.x - RIGHT_WIDTH - MARGIN, MARGIN)
	right.size = Vector2(RIGHT_WIDTH, size.y - MARGIN * 2)
	var rect := _board_rect()
	_board.fit(rect)
	_banner.position = rect.position
	_banner.size = rect.size
	_victory.reset_size()
	_victory.position = rect.get_center() - _victory.size / 2.0


# --- Estado -> interfaz -------------------------------------------------------

func _refresh() -> void:
	var pid := game.turns.current
	var player := game.players[pid]
	var actor := _local_actor()
	if not _network and (actor >= 0 or _ais.size() == game.players.size()):
		_viewer = pid
	if _tile_index >= 0 and (game.phase != G.Phase.PLACE_TILES or actor < 0 or _tile_index >= game.tile_hands[pid].size()):
		_tile_index = -1
	_refresh_players()
	var sp := game.species(pid)
	_turn_label.text = player.display_name + (" (IA)" if player.is_ai else (" (tú)" if _network and pid == _local_seat else ""))
	_turn_label.add_theme_color_override("font_color", _color(pid))
	_prompt_label.text = _prompt_text(actor)
	_status_label.text = _status_text()
	_clear(_actions_box)
	if actor >= 0:
		match game.phase:
			G.Phase.CHOOSE_SPECIES:
				_build_species_choice(actor)
			G.Phase.DRAFT:
				_build_draft(actor)
			G.Phase.PLACE_TILES:
				_build_tile_hand(actor)
			G.Phase.QUEEN:
				_build_queen_actions(actor)
			G.Phase.EXTERMINATOR:
				_build_exterminator_actions(actor)
	_refresh_hand(actor)
	_end_button.disabled = actor < 0 or game.phase != G.Phase.EXTERMINATOR
	_end_button.visible = game.phase in [G.Phase.QUEEN, G.Phase.EXTERMINATOR, G.Phase.FINISHED]
	_update_targets(actor)
	_schedule_ai()


func _refresh_players() -> void:
	_clear(_players_box)
	for p in game.players:
		var pid := p.id
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.07 if pid == game.turns.current else 0.03)
		style.border_color = HIGHLIGHT if pid == game.turns.current and not game.finished else Color(1, 1, 1, 0.1)
		style.set_border_width_all(2 if pid == game.turns.current else 1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		panel.add_child(box)
		var name := _label(p.display_name + (" (IA)" if p.is_ai else ""), 15)
		name.add_theme_color_override("font_color", _color(pid))
		box.add_child(name)
		var sp := game.species(pid)
		if sp >= 0:
			var species_label := _label("%s — %s" % [D.COLOR_NAMES[sp], D.SPECIES_NAMES[sp]], 12)
			species_label.add_theme_color_override("font_color", Color(D.SPECIES_COLORS[sp]).lightened(0.15))
			species_label.tooltip_text = D.SPECIES_ABILITY_TEXT[sp]
			species_label.mouse_filter = Control.MOUSE_FILTER_PASS
			box.add_child(species_label)
		if game.eliminated[pid]:
			box.add_child(_label("Eliminado", 12))
		elif game.phase in [G.Phase.QUEEN, G.Phase.EXTERMINATOR, G.Phase.FINISHED] and sp >= 0:
			var stats := _label("Reserva %d · Casa %d · Trampas %d" % [game.reserve[sp], game.pests_in_house(sp), game.pests_in_traps(sp)], 12)
			stats.modulate = DIM
			box.add_child(stats)
			var flags: Array[String] = []
			flags.append("nido sellado" if game.sealed[sp] else "nido abierto")
			flags.append("reina atrapada" if game.is_queen_trapped(sp) else "reina libre")
			flags.append("%d cartas" % game.hands[pid].size())
			var flags_label := _label(" · ".join(flags), 12)
			flags_label.modulate = DIM
			box.add_child(flags_label)
			var effects: Array[String] = []
			for e in game.effects_on(pid):
				effects.append(D.card(e["card"])["name"])
			if not effects.is_empty():
				var effects_label := _label("Delante: " + ", ".join(effects), 12)
				effects_label.add_theme_color_override("font_color", Color("ffab91"))
				box.add_child(effects_label)
		elif game.phase != G.Phase.CHOOSE_SPECIES:
			var cards := _label("%d cartas" % game.hands[pid].size(), 12)
			cards.modulate = DIM
			box.add_child(cards)
		_players_box.add_child(panel)


func _status_text() -> String:
	var parts: Array[String] = []
	if game.last_queen_face >= 0:
		var face: Dictionary = D.QUEEN_DIE[game.last_queen_face]
		parts.append("Dado de la reina: [b][color=#%s]%s[/color][/b] (%s)" % [Color(D.SPECIES_COLORS[face["species"]]).to_html(false), face["letter"], D.QUEEN_ACTION_NAMES[face["action"]]])
	if game.last_roll > 0:
		parts.append("d6: [b]%d[/b]" % game.last_roll)
	if game.phase == G.Phase.EXTERMINATOR:
		var line := "Movimiento gratis: [b]%s[/b] · Puntos de acción: [b]%d[/b]" % ["sí" if game.free_move else "no", game.action_points]
		if game.energy_moves > 0:
			line += " · Bebida: [b]%d[/b] movimientos" % game.energy_moves
		parts.append(line)
	elif game.phase == G.Phase.QUEEN:
		parts.append("Activaciones de la reina pendientes: [b]%d[/b]" % game.queen_steps.size())
	return "\n".join(parts)


func _prompt_text(actor: int) -> String:
	var name := game.current_player().display_name
	if game.finished:
		return "La partida ha terminado."
	if actor < 0:
		return "Esperando a %s…" % name
	match game.phase:
		G.Phase.CHOOSE_SPECIES:
			return "Elige tu exterminador."
		G.Phase.DRAFT:
			return "Elige una carta de herramientas (tendrás 4)."
		G.Phase.PLACE_TILES:
			if _tile_index < 0:
				return "Elige una loseta de tu mano."
			return "Haz clic en una casilla resaltada. R o «Girar» para girarla."
		G.Phase.QUEEN:
			return "Activa a tu reina. Antes de la primera tirada puedes jugar «Las plagas hibernan» o «Control mental»."
		G.Phase.EXTERMINATOR:
			return "Haz clic en una habitación resaltada para moverte, o elige una acción."
	return ""


func _phase_intro() -> String:
	match game.phase:
		G.Phase.CHOOSE_SPECIES:
			return "Cada jugador elige exterminador."
		G.Phase.DRAFT:
			return "Elección de cartas de herramientas."
		G.Phase.PLACE_TILES:
			return "Construcción de la casa."
	return "La casa está infestada. ¡A exterminar!"


# --- Paneles de cada fase --------------------------------------------------------

func _build_species_choice(pid: int) -> void:
	for sp in game.available_species():
		var b := _action_button("%s — %s" % [D.COLOR_NAMES[sp], D.SPECIES_NAMES[sp]], _submit.bind(G.CHOOSE_SPECIES, {"species": sp}, pid), true, D.SPECIES_ABILITY_TEXT[sp])
		b.add_theme_color_override("font_color", Color(D.SPECIES_COLORS[sp]).lightened(0.2))
		var info := _label(D.SPECIES_ABILITY_TEXT[sp], 12)
		info.modulate = DIM
		_actions_box.add_child(info)


func _build_draft(pid: int) -> void:
	for kind in [D.CardKind.DEFENSIVE, D.CardKind.OFFENSIVE]:
		_actions_box.add_child(_label("Defensivas" if kind == D.CardKind.DEFENSIVE else "Ofensivas", 13))
		for card_id in game.draft_pool:
			var card := D.card(card_id)
			if card["kind"] != kind:
				continue
			_action_button(card["name"], _submit.bind(G.DRAFT_CARD, {"card": card_id}, pid), true, card["text"])


func _build_tile_hand(pid: int) -> void:
	var tiles: Array = game.tile_hands[pid]
	var options := game.tile_options(pid)
	for i in tiles.size():
		var tile: Dictionary = tiles[i]
		var available := false
		for o in options:
			if o["index"] == i:
				available = true
				break
		var name := D.nest_name(tile["species"]) if tile["kind"] == D.RoomKind.NEST else String(D.STANDARD_TILES[tile["tile"]]["name"])
		var b := _action_button("%s  %s" % [name, _door_glyphs(PestsHouseGenerator.tile_doors(tile), _tile_rotation if i == _tile_index else 0)],
			_select_tile.bind(i), available,
			"" if available else ("El nido se coloca desde la ronda %d" % D.NEST_MIN_ROUND if tile["kind"] == D.RoomKind.NEST and not game.nest_allowed(pid) else "No cabe en ningún sitio"))
		b.toggle_mode = true
		b.set_pressed_no_signal(i == _tile_index)
	var rotate := _action_button("Girar loseta (R)", _rotate_tile, _tile_index >= 0)
	rotate.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_queen_actions(pid: int) -> void:
	var step: Dictionary = game.queen_steps[0] if not game.queen_steps.is_empty() else {}
	var text := "Tirar el dado de la reina"
	if not step.is_empty() and step["action"] >= 0:
		text = "Activar reina: %s (elegida)" % D.QUEEN_ACTION_NAMES[step["action"]]
	if not step.is_empty() and step["repeat"] > 1:
		text += " ×%d" % step["repeat"]
	var b := _action_button(text, _submit.bind(G.ROLL_QUEEN, {}, pid), true)
	b.custom_minimum_size = Vector2(0, 40)


func _build_exterminator_actions(pid: int) -> void:
	var legal := game.get_legal_actions(pid)
	var entries := [
		[G.EXTERMINATE, "Exterminar (tirar d6)"],
		[G.DROP_TRAP, "Soltar trampa"],
		[G.EMPTY_TRAP, "Vaciar trampa"],
		[G.DRAG_TRAP, "Arrastrar trampa"],
		[G.SEAL_NEST, "Sellar tu nido"],
		[G.DESTROY_TRAP, "Destruir trampa rival"],
		[G.UNSEAL_NEST, "Desellar nido rival"],
		[G.BUY_CARD, "Comprar carta"],
	]
	for entry in entries:
		var type: StringName = entry[0]
		var actions := _of_type(legal, type)
		var cost := game.action_cost(pid, type, actions[0].data if not actions.is_empty() else {})
		var label := "%s · %d PA" % [entry[1], cost]
		var reason := ""
		if actions.is_empty():
			reason = game.validate(GameAction.new(type, pid, _probe_data(pid, type)))
		_action_button(label, _choose.bind(String(entry[1]), actions), not actions.is_empty(), reason)


## Datos de ejemplo para preguntar por qué una acción no está disponible.
func _probe_data(pid: int, type: StringName) -> Dictionary:
	var here: int = game.exterminator_room[pid]
	var traps := game.traps_in_room(here)
	match type:
		G.EMPTY_TRAP, G.DESTROY_TRAP:
			return {"trap": traps[0]["id"]} if not traps.is_empty() else {"trap": -1}
		G.DRAG_TRAP:
			var rooms := game.house.neighbors(here)
			return {"trap": traps[0]["id"] if not traps.is_empty() else -1, "room": rooms[0] if not rooms.is_empty() else -1}
	return {}


func _refresh_hand(actor: int) -> void:
	_clear(_hand_box)
	var viewer := game.players[_viewer]
	var cards: Array = game.hands[_viewer]
	_hand_label.text = "Cartas de %s (%d) · mazo %d · descarte %d" % [viewer.display_name, cards.size(), game.deck.size(), game.discard.size()]
	var legal: Array[GameAction] = []
	if actor >= 0 and actor == _viewer:
		legal = game.get_legal_actions(actor)
	for card_id in cards:
		var card := D.card(card_id)
		var plays: Array[GameAction] = []
		for a in legal:
			if a.type == G.PLAY_CARD and a.data["card"] == card_id:
				plays.append(a)
		var timing := " (antes de tirar)" if card["timing"] == D.CardTiming.BEFORE_ROLL else ""
		var defensive: bool = card["kind"] == D.CardKind.DEFENSIVE
		var b := _button(card["name"] + timing, _choose.bind("Jugar «%s»" % card["name"], plays), 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", DEFENSIVE_COLOR if defensive else OFFENSIVE_COLOR)
		b.tooltip_text = ("Defensiva. " if defensive else "Ofensiva. ") + card["text"]
		b.disabled = plays.is_empty()
		b.clip_text = true
		_hand_box.add_child(b)


func _update_targets(actor: int) -> void:
	var rooms: Array[int] = []
	var cells: Array[Vector2i] = []
	_board.set_ghost(-1)
	if actor >= 0 and game.phase == G.Phase.PLACE_TILES and _tile_index >= 0:
		for o in game.tile_options(actor):
			if _matches_rotation(actor, o):
				var cell := Vector2i(o["x"], o["y"])
				if not cell in cells:
					cells.append(cell)
		var tile: Dictionary = game.tile_hands[actor][_tile_index]
		_board.set_ghost(D.rotate_doors(PestsHouseGenerator.tile_doors(tile), _tile_rotation), tile["species"])
	elif actor >= 0 and game.phase == G.Phase.EXTERMINATOR:
		for a in game.get_legal_actions(actor):
			if a.type == G.MOVE:
				rooms.append(a.data["room"])
	_board.set_targets(rooms, cells)


## ¿La colocación `o` es la loseta elegida con el giro actual? Se comparan
## las puertas, porque tile_options solo da un giro de cada forma distinta.
func _matches_rotation(actor: int, o: Dictionary) -> bool:
	if o["index"] != _tile_index:
		return false
	var doors := PestsHouseGenerator.tile_doors(game.tile_hands[actor][_tile_index])
	return D.rotate_doors(doors, o["rotation"]) == D.rotate_doors(doors, _tile_rotation)


func _door_glyphs(doors: int, rotation: int) -> String:
	var rotated := D.rotate_doors(doors, rotation)
	var text := ""
	for dir in 4:
		if rotated & D.dir_bit(dir):
			text += DOOR_ARROWS[dir]
	return text


# --- Ventanas de elección ----------------------------------------------------------

## Envía la acción si solo hay una; si hay varias, pregunta cuál.
func _choose(title: String, actions: Array[GameAction]) -> void:
	if actions.is_empty():
		return
	if actions.size() == 1:
		_send_reporting(actions[0])
		return
	var box := _open_dialog("ui:choose", title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(420, 44 * actions.size()))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for a in actions:
		var b := _button(_describe(a), func() -> void:
			_close_dialog()
			_send_reporting(a), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	box.add_child(_button("Cancelar", _cancel_dialog))


func _open_dialog(key: String, title: String) -> VBoxContainer:
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
	panel.custom_minimum_size = Vector2(minf(440, rect.size.x - 20), 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_label(title, 20))
	return box


func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	_dialog_key = ""


func _cancel_dialog() -> void:
	_close_dialog()
	_refresh()


## Texto de una acción para las ventanas de elección.
func _describe(a: GameAction) -> String:
	var data := a.data
	var parts: Array[String] = []
	if a.type == G.PLAY_CARD and data.has("use"):
		parts.append("Usar «%s»" % D.card(data["use"])["name"])
	if data.has("trap"):
		var t := game.find_trap(int(data["trap"]))
		if not t.is_empty():
			parts.append(_trap_text(t))
	if data.has("player"):
		parts.append("contra %s" % game.players[int(data["player"])].display_name)
	if data.has("room"):
		var r := int(data["room"])
		var text := "→ %s" % game.house.room_name(r) if a.type == G.DRAG_TRAP else "en %s" % game.house.room_name(r)
		parts.append(text)
	if data.has("queen_action"):
		parts.append("reina: %s" % D.QUEEN_ACTION_NAMES[int(data["queen_action"])])
	if data.has("target"):
		parts.append("atrapar a la reina" if data["target"] == "queen" else "atrapar plagas")
	if parts.is_empty():
		return String(a.type)
	return " · ".join(parts)


func _trap_text(t: Dictionary) -> String:
	var sp := game.trap_species(t)
	var content := "con la reina" if t["queen"] else "%d plagas" % t["pests"]
	return "Trampa %s (%s) en %s" % [String(D.COLOR_NAMES[sp]).to_lower(), content, game.house.room_name(t["room"])]


# --- IA ----------------------------------------------------------------------------

func _schedule_ai() -> void:
	if game.finished or _ai_pending or not is_inside_tree():
		return
	if _ai_actor() == -1:
		return
	_ai_pending = true
	var delay := AI_DELAY_FAST if _ai_fast_toggle.button_pressed else AI_DELAY
	if game.phase in [G.Phase.DRAFT, G.Phase.PLACE_TILES, G.Phase.CHOOSE_SPECIES]:
		delay *= 0.5
	get_tree().create_timer(delay).timeout.connect(_run_ai.bind(_ai_generation))


func _run_ai(generation: int) -> void:
	if generation != _ai_generation:
		return
	_ai_pending = false
	if game.finished:
		return
	var actor := _ai_actor()
	if actor == -1:
		return
	var action: GameAction = _ais[actor].choose_action(game)
	if action == null:
		push_warning("La IA de %s no encontró ninguna acción" % game.players[actor].display_name)
		return
	var error := _send(action)
	if error != "":
		push_warning("Acción ilegal de la IA: %s (%s)" % [action, error])


func _ai_actor() -> int:
	for pid in game.players_to_act():
		if _ais.has(pid):
			return pid
	return -1


# --- Interfaz -> acciones -------------------------------------------------------

func _submit(type: StringName, data: Dictionary = {}, pid: int = -1) -> void:
	var actor := game.turns.current if pid < 0 else pid
	_send_reporting(GameAction.new(type, actor, data))


func _send_reporting(action: GameAction) -> void:
	var error := _send(action)
	_error_label.text = error
	if error != "":
		Sfx.play(&"error")


func _send(action: GameAction) -> String:
	if _network and not Net.is_host:
		if not game.players[action.player_id].is_ai and action.player_id != _local_seat:
			return "No puedes actuar por otro jugador"
		var error := game.validate(action)
		if error == "":
			Net.request_action(action.to_dict())
		return error
	return game.submit(action)


func _select_tile(index: int) -> void:
	if _tile_index == index:
		_tile_index = -1
	else:
		_tile_index = index
		_tile_rotation = 0
		# Empieza por un giro que tenga algún hueco.
		var actor := _local_actor()
		if actor >= 0:
			for o in game.tile_options(actor):
				if o["index"] == index:
					_tile_rotation = o["rotation"]
					break
	_refresh()


func _rotate_tile() -> void:
	if _tile_index < 0:
		return
	_tile_rotation = (_tile_rotation + 1) % 4
	_refresh()


func _on_cell_clicked(cell: Vector2i) -> void:
	var actor := _local_actor()
	if actor < 0 or _dialog != null:
		return
	if game.phase == G.Phase.PLACE_TILES and _tile_index >= 0:
		for o in game.tile_options(actor):
			if o["x"] == cell.x and o["y"] == cell.y and _matches_rotation(actor, o):
				_submit(G.PLACE_TILE, o.duplicate(), actor)
				return
		_error_label.text = "La loseta no cabe ahí con ese giro"
		Sfx.play(&"error")
		return
	if game.phase == G.Phase.EXTERMINATOR:
		var room := game.house.room_at(cell)
		if room >= 0 and room != game.exterminator_room[actor]:
			_submit(G.MOVE, {"room": room}, actor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rotate_tile()
		elif event.keycode == KEY_ESCAPE:
			if _dialog != null:
				_cancel_dialog()
			elif _tile_index >= 0:
				_tile_index = -1
				_refresh()


func _on_hovered(cell: Vector2i) -> void:
	var room := game.house.room_at(cell)
	if room < 0:
		_hover_label.text = ""
		return
	var parts: Array[String] = [game.house.room_name(room)]
	if game.pests.size() == game.house.room_count():
		var counts: Array[String] = []
		for sp in D.SPECIES_COUNT:
			if game.pests[room][sp] > 0:
				counts.append("%d %s" % [game.pests[room][sp], String(D.COLOR_NAMES[sp]).to_lower()])
		if not counts.is_empty():
			parts.append("Plagas: " + ", ".join(counts))
		for sp in D.SPECIES_COUNT:
			if game.queen_room[sp] == room and not game.is_queen_trapped(sp):
				parts.append("Reina %s" % String(D.COLOR_NAMES[sp]).to_lower())
		for t in game.traps_in_room(room):
			parts.append(_trap_text(t))
	_hover_label.text = "\n".join(parts)


# --- Red local ---------------------------------------------------------------------

func _on_net_request(data: Dictionary, peer_id: int) -> void:
	if not _network:
		return
	var error := game.submit(GameAction.from_dict(data))
	if error != "":
		Net.reject(peer_id, error)


func _on_net_action(data: Dictionary) -> void:
	if not _network or Net.is_host:
		return
	var error := game.submit(GameAction.from_dict(data))
	if error != "":
		_add_log("[color=#ff8a80]Desincronización con el anfitrión: %s[/color]" % error)


func _on_seat_replaced(seat: int) -> void:
	if not _network or game == null:
		return
	game.players[seat].ai_level = PlayerInfo.AILevel.NORMAL
	if Net.is_host:
		_ais[seat] = PestsAI.new(seat, PlayerInfo.AILevel.NORMAL, game.rng.seed_value)
	_add_log("[color=#ffd166]%s se ha desconectado: ahora juega una IA.[/color]" % game.players[seat].display_name)
	_refresh()


# --- Registro y efectos -------------------------------------------------------------

func _on_action_applied(action: GameAction) -> void:
	var name := _player_name(action.player_id)
	var data := action.data
	var line := ""
	match action.type:
		G.ROLL_QUEEN:
			Sfx.play(&"dice")
		G.MOVE:
			Sfx.play(&"build", 1.3)
		G.EXTERMINATE:
			line = "%s tira el d6: [b]%d[/b] y extermina %d." % [name, data["roll"], data["removed"]]
			Sfx.play(&"dice")
		G.DROP_TRAP, G.DRAG_TRAP, G.EMPTY_TRAP, G.DESTROY_TRAP:
			Sfx.play(&"build", 0.8)
		G.BUY_CARD, G.DRAFT_CARD, G.PLAY_CARD:
			Sfx.play(&"card")
		G.PLACE_TILE:
			Sfx.play(&"build")
		G.END_TURN:
			pass
	if line != "":
		_add_log(line)
	for pending in _pending_log:
		_add_log(pending)
	_pending_log.clear()
	if _dialog_key.begins_with("ui:"):
		_close_dialog()
	_refresh()
	_board.refresh()
	if _network:
		Net.broadcast_action(action.to_dict())
	elif game.finished:
		App.delete_save(GAME_ID)
	else:
		App.save_game(GAME_ID, game.save_data())
	if game.turns.current != action.player_id and not game.finished:
		var p := game.current_player()
		_show_banner("Turno de %s" % p.display_name, _color(p.id))
		if _is_local(p.id):
			Sfx.play(&"turn")


func _on_game_event(kind: StringName, data: Dictionary) -> void:
	var text := _event_text(kind, data)
	if text != "":
		_pending_log.append(text)


func _event_text(kind: StringName, data: Dictionary) -> String:
	match kind:
		&"species_chosen":
			return "%s elige %s (%s)." % [_player_name(data["player"]), _species_text(data["species"]), D.SPECIES_NAMES[data["species"]]]
		&"card_drafted":
			return "%s elige «%s»." % [_player_name(data["player"]), D.card(data["card"])["name"]]
		&"tile_placed":
			return "%s coloca %s." % [_player_name(data["player"]), game.house.room_name(data["room"])]
		&"tiles_discarded":
			return "  %s no puede colocar sus losetas y devuelve %d a la caja." % [_player_name(data["player"]), data["count"]]
		&"house_infested":
			return "[b]La casa está infestada. ¡A exterminar![/b]"
		&"turn_started":
			return "[b]Turno de %s[/b]" % _player_name(data["player"])
		&"queen_rolled":
			var face: Dictionary = D.QUEEN_DIE[data["face"]]
			return "  Reina de %s: sale [b]%s[/b] (%s)." % [_species_text(data["species"]), face["letter"], D.QUEEN_ACTION_NAMES[face["action"]]]
		&"queen_chosen":
			return "  Reina de %s: acción elegida, %s." % [_species_text(data["species"]), D.QUEEN_ACTION_NAMES[data["action"]]]
		&"queen_moved":
			return "  La reina de %s %s a %s." % [_species_text(data["species"]), "sale de la casa y vuelve a entrar por" if data["reentered"] else "va", game.house.room_name(data["room"])]
		&"queen_courtyard":
			return "  La reina de %s sale a un patio sin salida y vuelve." % _species_text(data["species"])
		&"queen_angry":
			return "  ¡La reina de %s no puede actuar y se enfada!" % _species_text(data["species"])
		&"queen_populated":
			return "  La reina de %s puebla las habitaciones de alrededor." % _species_text(data["species"])
		&"pests_summoned":
			return "  Las plagas de %s acuden a su reina." % _species_text(data["species"])
		&"queen_dropped":
			return "  La reina suelta %d plaga%s." % [data["count"], "" if data["count"] == 1 else "s"] if data["count"] > 0 else ""
		&"nest_spawned":
			return "  Salen %d plaga%s del nido de %s." % [data["count"], "" if data["count"] == 1 else "s", _species_text(data["species"])] if data["count"] > 0 else ""
		&"queen_escaped":
			return "  ¡La reina de %s escapa de la trampa!" % _species_text(data["species"])
		&"queen_trapped":
			return "  [b]¡La reina de %s cae en una trampa![/b]" % _species_text(data["species"])
		&"pests_trapped":
			return "  La trampa de %s atrapa %d plagas." % [_species_text(data["species"]), data["count"]]
		&"pests_exterminated":
			return "" if data["count"] == 0 else "  %s elimina %d plagas en %s." % [_player_name(data["player"]), data["count"], game.house.room_name(data["room"])]
		&"trap_dropped":
			return "%s suelta una trampa en %s." % [_player_name(data["player"]), game.house.room_name(data["room"])]
		&"trap_dragged":
			return "%s arrastra una trampa a %s." % [_player_name(data["player"]), game.house.room_name(data["room"])]
		&"trap_emptied":
			return "%s vacía su trampa (%d plagas vuelven a su reserva)." % [_player_name(data["player"]), data["pests"]]
		&"trap_destroyed":
			return "%s destruye la trampa de %s." % [_player_name(data["player"]), _player_name(data["owner"])]
		&"queen_trap_emptied":
			return "[b]%s vacía la trampa con su reina.[/b]" % _player_name(data["player"])
		&"nest_sealed":
			return "%s sella el nido de %s." % [_player_name(data["player"]), _species_text(data["species"])]
		&"nest_unsealed":
			return "%s quita el sello del nido de %s." % [_player_name(data["player"]), _species_text(data["species"])]
		&"card_bought":
			return "%s compra una carta." % _player_name(data["player"])
		&"card_played":
			var text := "%s juega [b]%s[/b]" % [_player_name(data["player"]), D.card(data["card"])["name"]]
			var target := int(data["data"].get("player", -1))
			if target >= 0 and data["card"] != "dumpster_diver":
				text += " contra %s" % _player_name(target)
			return text + "."
		&"card_discarded":
			return "  %s pierde «%s»." % [_player_name(data["player"]), D.card(data["card"])["name"]]
		&"effect_ended":
			return "  Se descarta «%s» de %s." % [D.card(data["card"])["name"], _player_name(data["player"])]
		&"queen_hibernates":
			return "  Las plagas de %s hibernan este turno." % _species_text(data["species"])
		&"pests_removed":
			return "  %d plagas de %s vuelven a la caja." % [data["count"], _species_text(data["species"])]
		&"pests_spread":
			return "  Las plagas de %s se extienden." % _species_text(data["species"])
		&"player_eliminated":
			Sfx.play(&"robber")
			return "[b]%s queda eliminado: la casa está infestada de %s.[/b]" % [_player_name(data["player"]), _species_text(data["species"])]
	return ""


func _on_game_finished(winner_ids: Array[int]) -> void:
	_show_victory.call_deferred(winner_ids)


func _show_victory(winner_ids: Array[int]) -> void:
	_close_dialog()
	Sfx.play(&"win")
	var winner := game.players[winner_ids[0]] if not winner_ids.is_empty() else null
	var title: Label = _victory.find_child("Title", true, false)
	var details: Label = _victory.find_child("Details", true, false)
	if winner != null:
		var sp := game.species(winner.id)
		_add_log("[b]¡%s gana y cobra el trabajo![/b]" % winner.display_name)
		title.text = "¡%s gana!" % winner.display_name
		title.add_theme_color_override("font_color", _color(winner.id))
		details.text = ("Ha limpiado la casa de %s." % String(D.SPECIES_NAMES[sp]).to_lower()) if game.is_queen_trapped(sp) or game.sealed[sp] else "Es el último exterminador en pie."
	else:
		title.text = "Fin de la partida"
		details.text = ""
	_victory.find_child("Again", true, false).visible = not _network
	_victory.visible = true
	_refresh()
	_layout()


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color.lightened(0.3))
	var tween := create_tween()
	_banner.modulate.a = 1.0
	tween.tween_interval(0.9)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


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
	return "[color=#%s]%s[/color]" % [_color(pid).to_html(false), game.players[pid].display_name]


## Color con el que se muestra un jugador: el de su especie en cuanto la
## elige (así coincide con sus piezas), y si no, el suyo.
func _color(pid: int) -> Color:
	var sp := game.species(pid)
	var base: Color = D.SPECIES_COLORS[sp] if sp >= 0 else game.players[pid].color
	return base.lightened(0.2)


## Nombre de una especie como equipo ("Morado"), en su color.
func _species_text(sp: int) -> String:
	return "[color=#%s]%s[/color]" % [Color(D.SPECIES_COLORS[sp]).lightened(0.15).to_html(false), D.COLOR_NAMES[sp]]


static func _of_type(actions: Array[GameAction], type: StringName) -> Array[GameAction]:
	var result: Array[GameAction] = []
	for a in actions:
		if a.type == type:
			result.append(a)
	return result
