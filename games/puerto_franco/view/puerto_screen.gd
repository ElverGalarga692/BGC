extends Control
## Pantalla de una partida de Puerto Franco.
##
## Izquierda: jugadores (monedas, cartas, edificios, cargo) y registro.
## Centro: el consejo (los 7 cargos), el barrio grande, el muelle y los
## objetivos, los barrios de los rivales y la mano. Derecha: lo que hay que
## hacer ahora y los puntos del barrio que se ve en grande.
##
## INFORMACIÓN OCULTA: la mano de cada uno y su elección de cargo. Si en
## este equipo juegan varias personas, la elección se hace en una ventana
## privada tras una cortina de «Pasa el dispositivo a X», y al empezar el
## turno de cada persona aparece la misma cortina antes de enseñar su mano.
## La pantalla solo lee game.view_for(seat), nunca el estado interno.

const G := preload("res://games/puerto_franco/logic/puerto_game.gd")
const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")
const Phase := PuertoGame.Phase
const Income := PuertoGame.Income
const Office := PuertoDefs.Office
const Card := PuertoArt.PuertoCard

const GAME_ID := "puerto_franco"
const BACKGROUND := Color("13222b")
const LEFT_WIDTH := 270.0
const RIGHT_WIDTH := 320.0
const AI_DELAY := 0.7
const AI_DELAY_FAST := 0.15
const ERROR_COLOR := Color("ff8a80")
const DOCK_WIDTH := 460.0
const HAND_CARD := Vector2(74, 104)
const DOCK_CARD := Vector2(62, 87)
## Nombres cortos para las fichas del consejo.
const OFFICE_SHORT := ["Capitana", "Contraband.", "Recaudad.", "Urbanista", "Obras", "Mecenas", "Alcaldesa"]
const OK_COLOR := Color("8fd694")

var game: PuertoGame
var _ais := {}
var _ai_pending := false
var _ai_generation := 0
var _network := false
var _local_seat := -1
## Cliente: esperando a que el anfitrión confirme nuestra jugada.
var _awaiting_host := false
## Hay varias personas en este equipo: lo privado necesita cortina.
var _hotseat_private := false
## Única persona de este equipo (-1 si hay varias o ninguna).
var _me := -1
## Persona que ya ha pasado la cortina en su turno (enseña su mano).
var _turn_revealed := -1
## Barrio que se ve en grande (-1 = el que toca).
var _focus := -1

## Modo de la interfaz en el turno: "" | "build" | "harbor" | "move_from" | "move_to".
var _mode := ""
var _sel_card := -1
var _move_from := -1
## Elección de cargo en la ventana privada.
var _pick_office := -1
var _pick_bid := 0

var _log: Array[String] = []
var _players_box: VBoxContainer
var _log_label: RichTextLabel
var _ai_fast_toggle: CheckButton
var _council_box: HBoxContainer
var _big_title: Label
var _big_district: PuertoDistrictView
var _dock_box: HFlowContainer
var _deck_label: Label
var _objectives_box: VBoxContainer
var _rivals_box: HBoxContainer
var _hand_title: Label
var _hand_box: HBoxContainer
var _phase_label: Label
var _prompt_label: Label
var _error_label: Label
var _actions_box: VBoxContainer
var _info_box: VBoxContainer
var _banner: Label
var _overlay: Control
var _overlay_box: VBoxContainer
var _overlay_dock: MarginContainer
var _overlay_seat := -1
var _overlay_kind := ""
var _overlay_stage := ""
var _victory: Control
var _banner_queue: Array = []
var _banner_busy := false


func _ready() -> void:
	theme = BGCTheme.build()
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	row.add_child(_build_left_panel())
	row.add_child(_build_center())
	row.add_child(_build_right_panel())
	_build_overlays()

	Net.action_received.connect(_on_net_action)
	Net.action_requested.connect(_on_net_request)
	Net.action_rejected.connect(func(message: String) -> void:
		_awaiting_host = false
		_error_label.text = message
		Sfx.play(&"error")
		_refresh())
	Net.seat_replaced.connect(_on_seat_replaced)
	_start(App.session_seed())


func _start(seed: int) -> void:
	game = PuertoGame.new()
	game.setup(App.session_players(3), seed)
	_network = App.session.get("network", false)
	_local_seat = App.session.get("local_seat", -1)
	_create_ais(seed)
	var saved: Array = App.session.get("history", [])
	App.session.erase("history")
	var load_error := game.replay(saved) if not saved.is_empty() else ""
	game.action_applied.connect(_on_action_applied)
	game.event.connect(_on_game_event)
	game.game_finished.connect(_on_game_finished)
	_ai_pending = false
	_ai_generation += 1
	_log.clear()
	_log_label.clear()
	_victory.visible = false
	_overlay_seat = -1
	_overlay_kind = ""
	_turn_revealed = -1
	_focus = -1
	_reset_mode()
	var humans := _local_humans()
	_hotseat_private = not _network and humans.size() > 1
	_me = humans[0] if humans.size() == 1 else -1
	if not saved.is_empty():
		_add_log("Partida guardada cargada (%d jugadas)." % game.history.size())
		if load_error != "":
			_add_log("[color=#ff8a80]No se pudo cargar del todo: %s[/color]" % load_error)
	else:
		_add_log("Partida nueva con %d jugadores. Objetivos: %s." % [game.players.size(), ", ".join(game.objectives.map(func(o: int) -> String: return D.OBJECTIVE_NAMES[o]))])
		_add_log("La vara empieza en manos de %s." % _player_name(game.vara))
	_refresh()
	_show_banner("Ronda %d: elegid cargo" % game.round_number, BGCTheme.ACCENT)


func _create_ais(seed: int) -> void:
	_ais.clear()
	var autoplay := OS.get_environment("BGC_AUTOPLAY") == "1"
	for p in game.players:
		var runs_here := p.is_ai and (not _network or Net.is_host)
		var local_human := not p.is_ai and (not _network or p.id == _local_seat)
		if runs_here or (autoplay and local_human):
			_ais[p.id] = PuertoAI.new(p.id, p.ai_level if p.is_ai else PlayerInfo.AILevel.NORMAL, seed)


func _local_humans() -> Array[int]:
	var result: Array[int] = []
	for p in game.players:
		if _is_local(p.id):
			result.append(p.id)
	return result


func _is_local(pid: int) -> bool:
	if game.players[pid].is_ai or _ais.has(pid):
		return false
	return pid == _local_seat if _network else true


## Primera persona de este equipo que debe actuar ahora (o -1).
func _local_actor() -> int:
	if game.finished:
		return -1
	for pid in game.players_to_act():
		if _is_local(pid):
			return pid
	return -1


## Jugador del turno (o -1 fuera de los turnos).
func _turn_player(view: Dictionary) -> int:
	if view["phase"] != Phase.TURN or view["turn_office"] < 0:
		return -1
	return view["holder"][view["turn_office"]]


## Mano que se puede enseñar en la pantalla principal (-1 = ninguna).
func _hand_seat() -> int:
	if _me >= 0:
		return _me
	if _hotseat_private:
		var actor := _local_actor()
		if actor >= 0 and game.phase == Phase.TURN and _turn_revealed == actor:
			return actor
	return -1


# --- Construcción de la interfaz ---------------------------------------------------

func _panel(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", BGCTheme.box(Color(0.04, 0.1, 0.13, 0.85), Color(1, 1, 1, 0.1), 16, 1, 8, 12))
	return panel


func _label(text: String = "", font_size: int = 16, color: Color = BGCTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _tag(text: String, font_size: int = 14, color: Color = BGCTheme.TEXT) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _button(text: String, callback: Callable, font_size: int = 15, variation: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", font_size)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void: Sfx.play(&"click"))
	button.pressed.connect(callback)
	return button


func _build_left_panel() -> Control:
	var panel := _panel(LEFT_WIDTH)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := _label("Puerto Franco", 26, BGCTheme.ACCENT)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	box.add_child(_players_box)
	box.add_child(HSeparator.new())
	box.add_child(_label("Registro", 13, BGCTheme.TEXT_DIM))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	_log_label.add_theme_font_size_override("bold_font_size", 13)
	box.add_child(_log_label)
	var row := HBoxContainer.new()
	var rules := _button("Reglas", func() -> void: RulesPanel.open(self, GameRegistry.find(GAME_ID)["rules"]), 14, "GhostButton")
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rules)
	var menu := _button("Menú", App.go_to_menu, 14, "GhostButton")
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)
	box.add_child(row)
	_ai_fast_toggle = CheckButton.new()
	_ai_fast_toggle.text = "IA rápida"
	_ai_fast_toggle.add_theme_font_size_override("font_size", 14)
	_ai_fast_toggle.button_pressed = App.get_setting("ai_fast", false)
	_ai_fast_toggle.toggled.connect(func(on: bool) -> void: App.set_setting("ai_fast", on))
	box.add_child(_ai_fast_toggle)
	return panel


func _build_center() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_council_box = HBoxContainer.new()
	_council_box.add_theme_constant_override("separation", 5)
	box.add_child(_council_box)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	box.add_child(middle)
	var district_box := VBoxContainer.new()
	district_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(district_box)
	_big_title = _label("", 17, BGCTheme.ACCENT)
	_big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	district_box.add_child(_big_title)
	_big_district = PuertoDistrictView.new()
	_big_district.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_big_district.cell_clicked.connect(_on_cell_clicked)
	district_box.add_child(_big_district)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size = Vector2(DOCK_CARD.x * 2 + 22, 0)
	middle.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	side_scroll.add_child(side)
	side.add_child(_label("Muelle", 14, BGCTheme.TEXT_DIM))
	_dock_box = HFlowContainer.new()
	_dock_box.add_theme_constant_override("h_separation", 6)
	_dock_box.add_theme_constant_override("v_separation", 6)
	side.add_child(_dock_box)
	_deck_label = _label("", 13, BGCTheme.TEXT_DIM)
	side.add_child(_deck_label)
	side.add_child(HSeparator.new())
	side.add_child(_label("Objetivos (4 puntos)", 14, BGCTheme.TEXT_DIM))
	_objectives_box = VBoxContainer.new()
	side.add_child(_objectives_box)

	_rivals_box = HBoxContainer.new()
	_rivals_box.add_theme_constant_override("separation", 8)
	_rivals_box.custom_minimum_size = Vector2(0, 104)
	box.add_child(_rivals_box)
	_hand_title = _label("", 14, BGCTheme.TEXT_DIM)
	box.add_child(_hand_title)
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 6)
	_hand_box.custom_minimum_size = Vector2(0, HAND_CARD.y + 10)
	box.add_child(_hand_box)
	return box


func _build_right_panel() -> Control:
	var panel := _panel(RIGHT_WIDTH)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_phase_label = _label("", 22, BGCTheme.ACCENT)
	box.add_child(_phase_label)
	_prompt_label = _label("", 15)
	box.add_child(_prompt_label)
	_error_label = _label("", 13, ERROR_COLOR)
	box.add_child(_error_label)
	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	box.add_child(_actions_box)
	box.add_child(HSeparator.new())
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 4)
	box.add_child(_info_box)
	return panel


func _build_overlays() -> void:
	_banner = _label("", 40)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_overlay = _modal(Color(0.02, 0.05, 0.07, 0.97))
	_overlay_box = _overlay.get_meta("box")
	_overlay_dock = MarginContainer.new()
	_overlay_dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_overlay_dock.offset_left = -DOCK_WIDTH - 12
	for side in ["right", "top", "bottom"]:
		_overlay_dock.add_theme_constant_override("margin_" + side, 12)
	_overlay.add_child(_overlay_dock)
	_victory = _modal(Color(0, 0, 0, 0.75))


func _modal(shade: Color) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	var bg := ColorRect.new()
	bg.color = shade
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", BGCTheme.box(Color("172b36"), Color(1, 1, 1, 0.15), 18, 1, 18, 22))
	center.add_child(panel)
	root.set_meta("center", center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.set_meta("box", box)
	return root


# --- Estado -> interfaz ----------------------------------------------------------

func _refresh() -> void:
	var pub := game.view_for(-1)
	var turn_player := _turn_player(pub)
	if _turn_revealed >= 0 and _turn_revealed != turn_player:
		_turn_revealed = -1
	if _local_actor() < 0 or game.phase != Phase.TURN:
		_reset_mode()
	_refresh_players(pub)
	_refresh_council(pub)
	_refresh_board(pub)
	_refresh_hand()
	_refresh_actions(pub)
	_refresh_info(pub)
	_update_overlay()
	_schedule_ai()


func _reset_mode() -> void:
	_mode = ""
	_sel_card = -1
	_move_from = -1


func _refresh_players(pub: Dictionary) -> void:
	_clear(_players_box)
	for p in game.players:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = p.color
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _tag(p.display_name + (" (IA)" if p.is_ai else ""), 14)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if p.id == pub["vara"]:
			row.add_child(_tag("vara", 12, BGCTheme.ACCENT))
		if pub["phase"] == Phase.PICK:
			row.add_child(_tag("✔" if pub["picked"].has(p.id) else "…", 13, BGCTheme.TEXT_DIM))
		col.add_child(row)
		var office: int = pub["office_of"][p.id]
		var details := "%s · %s · %d/%d edificios" % [_plural(pub["coins"][p.id], "moneda"), _plural(pub["hand_sizes"][p.id], "carta"), _count(pub["districts"][p.id]), D.BUILDINGS_TO_END]
		var detail_label := _tag(details, 12, BGCTheme.TEXT_DIM)
		col.add_child(detail_label)
		if office >= 0:
			var turn := _turn_player(pub) == p.id
			col.add_child(_tag("%d. %s%s" % [office + 1, D.OFFICE_NAMES[office], "  ◀ turno" if turn else ""], 12, BGCTheme.ACCENT if turn else Color("9fc7c9")))
		_players_box.add_child(col)


static func _plural(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]


static func _count(district: Array) -> int:
	var n := 0
	for c in district:
		if c >= 0:
			n += 1
	return n


func _refresh_council(pub: Dictionary) -> void:
	_clear(_council_box)
	for o in D.OFFICE_COUNT:
		var holder: int = pub["holder"][o]
		var current: bool = pub["phase"] == Phase.TURN and pub["turn_office"] == o
		var color := game.players[holder].color if holder >= 0 else Color(1, 1, 1, 0.25)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(60, 0)
		var fill := Color(color, 0.22) if holder >= 0 else Color(0, 0, 0, 0.25)
		panel.add_theme_stylebox_override("panel", BGCTheme.box(fill, Color("ffd166") if current else Color(color, 0.6), 10, 3 if current else 1, 0, 6))
		panel.tooltip_text = D.OFFICE_TEXT[o]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		panel.add_child(col)
		var title := _tag("%d. %s" % [o + 1, OFFICE_SHORT[o]], 12, BGCTheme.TEXT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.clip_text = true
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(title)
		var who := game.players[holder].display_name if holder >= 0 else "vacante"
		var sub := _tag(who, 12, color.lightened(0.3) if holder >= 0 else BGCTheme.TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.clip_text = true
		col.add_child(sub)
		if pub["vacant_coins"][o] > 0:
			var coins := _tag("+%d moneda%s" % [pub["vacant_coins"][o], "s" if pub["vacant_coins"][o] > 1 else ""], 11, Color("e8b94a"))
			coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(coins)
		_council_box.add_child(panel)


func _focus_seat(pub: Dictionary) -> int:
	if _focus >= 0:
		return _focus
	var turn := _turn_player(pub)
	if turn >= 0:
		return turn
	if _me >= 0:
		return _me
	var actor := _local_actor()
	return actor if actor >= 0 else pub["vara"]


func _refresh_board(pub: Dictionary) -> void:
	var seat := _focus_seat(pub)
	var p := game.players[seat]
	var score: Dictionary = game.score_of(seat)
	_big_title.text = "Barrio de %s · %d puntos ahora" % [p.display_name, score["total"]]
	_big_title.add_theme_color_override("font_color", p.color.lightened(0.3))
	_big_district.owner_color = p.color
	var targets: Array[int] = []
	var selected := -1
	var actor := _local_actor()
	if actor == seat and game.phase == Phase.TURN:
		match _mode:
			"build":
				targets = game.buildable_cells(actor)
			"move_from":
				for move in game.planner_moves(actor):
					if not int(move[0]) in targets:
						targets.append(int(move[0]))
			"move_to":
				selected = _move_from
				for move in game.planner_moves(actor):
					if int(move[0]) == _move_from:
						targets.append(int(move[1]))
	_big_district.set_district(pub["districts"][seat], targets, selected)

	_clear(_dock_box)
	var dock_clickable := actor >= 0 and game.phase == Phase.TURN and _hand_seat() == actor and (_mode == "harbor" or not game.income_taken)
	for i in pub["dock"].size():
		var card := Card.new(pub["dock"][i], DOCK_CARD)
		card.clickable = dock_clickable
		card.pressed.connect(_on_dock_pressed.bind(i))
		_dock_box.add_child(card)
	_deck_label.text = "Mazo: %d cartas · descartes: %d" % [pub["deck_count"], pub["discard"].size()]

	_clear(_objectives_box)
	for obj in pub["objectives"]:
		var leaders := game.objective_leaders(obj)
		var who := "nadie" if leaders.is_empty() else ", ".join(leaders.map(func(pid: int) -> String: return game.players[pid].display_name))
		_objectives_box.add_child(_label("%s: %s.\nVa ganando: %s" % [D.OBJECTIVE_NAMES[obj], D.OBJECTIVE_TEXT[obj], who], 12))

	_clear(_rivals_box)
	for other in game.players:
		if other.id == seat:
			continue
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		var name_btn := _button("%s · %d pts" % [other.display_name, game.score_of(other.id)["total"]], func() -> void:
			_focus = other.id
			_refresh(), 12, "GhostButton")
		name_btn.add_theme_color_override("font_color", other.color.lightened(0.3))
		name_btn.tooltip_text = "Ver su barrio en grande"
		cell.add_child(name_btn)
		var view := PuertoDistrictView.new()
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view.custom_minimum_size = Vector2(90, 76)
		view.owner_color = other.color
		view.set_district(pub["districts"][other.id])
		cell.add_child(view)
		_rivals_box.add_child(cell)
	if _focus >= 0:
		var back := _button("Volver", func() -> void:
			_focus = -1
			_refresh(), 12, "GhostButton")
		_rivals_box.add_child(back)


func _refresh_hand() -> void:
	_clear(_hand_box)
	var seat := _hand_seat()
	if seat < 0:
		var actor := _local_actor()
		if _hotseat_private and actor >= 0 and game.phase == Phase.TURN:
			_hand_title.text = "Mano de %s: oculta hasta que pase la cortina." % game.players[actor].display_name
		else:
			_hand_title.text = "Las manos son secretas." if _local_humans().size() > 0 else "Solo juegan IAs."
		return
	var view := game.view_for(seat)
	var hand: Array = view["hand"]
	var my_turn := _local_actor() == seat and game.phase == Phase.TURN
	var can_build: bool = my_turn and view["income_taken"] and view["builds_left"] > 0
	_hand_title.text = "Mano de %s (%d cartas)%s" % [game.players[seat].display_name, hand.size(), " · pulsa una carta para construirla" if can_build else ""]
	for i in hand.size():
		var card := Card.new(hand[i], HAND_CARD)
		var affordable: bool = game.build_cost(seat, hand[i]) <= view["coins"][seat]
		card.clickable = can_build and affordable
		card.dimmed = can_build and not affordable
		card.selected = _mode == "build" and _sel_card == i
		card.pressed.connect(_on_hand_pressed.bind(i))
		_hand_box.add_child(card)


func _refresh_actions(pub: Dictionary) -> void:
	_clear(_actions_box)
	var phase: int = pub["phase"]
	_phase_label.text = "Ronda %d · %s" % [pub["round"], G.PHASE_NAMES[phase]]
	if game.finished:
		_prompt_label.text = "La partida ha terminado."
		_actions_box.add_child(_button("Ver resultados", func() -> void: _victory.visible = true, 15, "PrimaryButton"))
		return
	var actor := _local_actor()
	match phase:
		Phase.PICK:
			_prompt_label.text = "Cada uno elige en secreto un cargo y cuánto puja por él. Han elegido %d de %d." % [pub["picked"].size(), game.players.size()]
			if actor >= 0 and _hotseat_private:
				_actions_box.add_child(_label("Elección secreta de %s: pasadle el dispositivo." % game.players[actor].display_name, 14, BGCTheme.ACCENT))
		Phase.REASSIGN:
			var who: int = pub["reassign_queue"][0]
			_prompt_label.text = "%s perdió la puja y elige un cargo vacante (gratis)." % game.players[who].display_name
			_add_reveal(pub)
			if actor >= 0:
				for o in game.vacant_offices():
					var extra := " (+%d monedas)" % pub["vacant_coins"][o] if pub["vacant_coins"][o] > 0 else ""
					var b := _button("%d. %s%s\n%s" % [o + 1, D.OFFICE_NAMES[o], extra, D.OFFICE_TEXT[o]], func() -> void: _submit(G.REASSIGN, {"office": o}, actor), 13)
					b.alignment = HORIZONTAL_ALIGNMENT_LEFT
					_actions_box.add_child(b)
		Phase.TURN:
			var turn := _turn_player(pub)
			var office: int = pub["turn_office"]
			_prompt_label.text = "Turno de %s (%d. %s)." % [game.players[turn].display_name, office + 1, D.OFFICE_NAMES[office]]
			if actor < 0:
				_add_reveal(pub)
			elif _hand_seat() != actor:
				_actions_box.add_child(_label("Turno de %s: pasadle el dispositivo." % game.players[actor].display_name, 14, BGCTheme.ACCENT))
			else:
				_turn_actions(actor, pub)


## Quién eligió qué en la última elección (público).
func _add_reveal(pub: Dictionary) -> void:
	if pub["last_reveal"].is_empty():
		return
	var lines: Array[String] = []
	for r in pub["last_reveal"]:
		lines.append("%s → %s (puja %d)%s" % [game.players[r["player"]].display_name, D.OFFICE_NAMES[r["office"]], r["bid"], "" if r["won"] else " ✗"])
	_actions_box.add_child(_label("Elecciones de esta ronda:\n" + "\n".join(lines), 12, BGCTheme.TEXT_DIM))


func _turn_actions(actor: int, pub: Dictionary) -> void:
	var office: int = pub["turn_office"]
	var coins: int = pub["coins"][actor]
	_actions_box.add_child(_label(D.OFFICE_TEXT[office], 13, Color("9fc7c9")))
	# 1. Cobrar.
	if not pub["income_taken"]:
		_actions_box.add_child(_label("Cobra (obligatorio antes de construir):", 14, BGCTheme.ACCENT))
		var amount := D.COIN_INCOME + (1 if game.has_wonder(actor, PuertoDefs.Wonder.CUSTOMS) else 0)
		_actions_box.add_child(_button("Cobrar %d monedas" % amount, func() -> void: _submit(G.INCOME, {"kind": Income.COINS}, actor), 15, "PrimaryButton"))
		if pub["deck_count"] > 0 or not pub["discard"].is_empty():
			_actions_box.add_child(_button("Robar 1 carta a ciegas y 1 moneda", func() -> void: _submit(G.INCOME, {"kind": Income.BLIND}, actor), 14))
		if not pub["dock"].is_empty():
			_actions_box.add_child(_label("…o pulsa una carta del muelle para quedártela.", 13, BGCTheme.TEXT_DIM))
	# 2. El cargo.
	if not pub["ability_used"]:
		match office:
			Office.HARBOR:
				if not pub["dock"].is_empty():
					if _mode == "harbor":
						_actions_box.add_child(_label("Pulsa la carta del muelle que quieres (gratis).", 14, BGCTheme.ACCENT))
						_actions_box.add_child(_button("Cancelar", _cancel_mode, 13, "GhostButton"))
					else:
						_actions_box.add_child(_button("Capitana: coger 1 carta del muelle gratis", func() -> void:
							_mode = "harbor"
							_refresh(), 14))
			Office.SMUGGLER:
				for t in game.smuggler_targets(actor):
					_actions_box.add_child(_button("Contrabandista: quitar 1 carta a %s (%d)" % [game.players[t].display_name, pub["hand_sizes"][t]], func() -> void: _submit(G.ABILITY, {"target": t}, actor), 14))
			Office.COLLECTOR:
				var payers := 0
				for other in game.players.size():
					if other != actor and pub["coins"][other] > coins:
						payers += 1
				var hint := " (mejor antes de cobrar)" if not pub["income_taken"] else ""
				_actions_box.add_child(_button("Recaudadora: cobrar %d moneda%s%s" % [payers, "" if payers == 1 else "s", hint], func() -> void: _submit(G.ABILITY, {}, actor), 14))
			Office.PATRON:
				var amount := mini(D.group_count(pub["districts"][actor]), D.PATRON_MAX)
				_actions_box.add_child(_button("Mecenas: cobrar %d moneda%s" % [amount, "" if amount == 1 else "s"], func() -> void: _submit(G.ABILITY, {}, actor), 14))
			Office.PLANNER:
				if not game.planner_moves(actor).is_empty():
					if _mode == "move_from":
						_actions_box.add_child(_label("Pulsa el edificio que quieres trasladar.", 14, BGCTheme.ACCENT))
						_actions_box.add_child(_button("Cancelar", _cancel_mode, 13, "GhostButton"))
					elif _mode == "move_to":
						_actions_box.add_child(_label("Pulsa la casilla de destino.", 14, BGCTheme.ACCENT))
						_actions_box.add_child(_button("Cancelar", _cancel_mode, 13, "GhostButton"))
					else:
						_actions_box.add_child(_button("Urbanista: trasladar un edificio", func() -> void:
							_mode = "move_from"
							_refresh(), 14))
	# 3. Construir.
	if pub["income_taken"]:
		if pub["builds_left"] > 0:
			if _mode == "build":
				var card: int = game.view_for(actor)["hand"][_sel_card]
				_actions_box.add_child(_label("Construir %s por %d: pulsa una casilla resaltada de tu barrio." % [D.card_name(card), game.build_cost(actor, card)], 14, BGCTheme.ACCENT))
				_actions_box.add_child(_button("Cancelar", _cancel_mode, 13, "GhostButton"))
			else:
				var more := " (te quedan %d)" % pub["builds_left"] if pub["builds_left"] > 1 else ""
				_actions_box.add_child(_label("Puedes construir: pulsa una carta de tu mano%s." % more, 13, BGCTheme.TEXT_DIM))
		_actions_box.add_child(_button("Terminar el turno", func() -> void: _submit(G.END_TURN, {}, actor), 15, "PrimaryButton"))


func _cancel_mode() -> void:
	_reset_mode()
	_refresh()


## Puntos del barrio que se ve en grande.
func _refresh_info(pub: Dictionary) -> void:
	_clear(_info_box)
	var seat := _focus_seat(pub)
	var s: Dictionary = game.score_of(seat)
	_info_box.add_child(_label("Puntos de %s si acabase ahora" % game.players[seat].display_name, 14, BGCTheme.TEXT_DIM))
	var lines := [
		"Edificios (coste): %d" % s["buildings"],
		"Grupos de vecinos: %d" % s["groups"],
		"Maravillas: %d" % s["wonders"],
		"Objetivos: %d" % s["objectives"],
	]
	if s["first"] > 0:
		lines.append("Completó el barrio primero: %d" % s["first"])
	lines.append("Total: %d" % s["total"])
	_info_box.add_child(_label("\n".join(lines), 13))
	var groups := D.groups(pub["districts"][seat])
	if not groups.is_empty():
		var parts: Array[String] = []
		for g in groups:
			parts.append("%s (%d)" % [D.GUILD_NAMES[g["guild"]], g["cells"].size()])
		_info_box.add_child(_label("Grupos: " + ", ".join(parts), 12, BGCTheme.TEXT_DIM))


# --- Clics ----------------------------------------------------------------------------

func _on_hand_pressed(index: int) -> void:
	var actor := _local_actor()
	if actor < 0 or _hand_seat() != actor:
		return
	if _mode == "build" and _sel_card == index:
		_reset_mode()
	else:
		_mode = "build"
		_sel_card = index
		_move_from = -1
	Sfx.play(&"card")
	_refresh()


func _on_dock_pressed(index: int) -> void:
	var actor := _local_actor()
	if actor < 0:
		return
	if _mode == "harbor":
		_submit(G.ABILITY, {"index": index}, actor)
	elif not game.income_taken:
		_submit(G.INCOME, {"kind": Income.DOCK, "index": index}, actor)


func _on_cell_clicked(cell: int) -> void:
	var actor := _local_actor()
	if actor < 0:
		return
	match _mode:
		"build":
			var index := _sel_card
			_reset_mode()
			_submit(G.BUILD, {"card": index, "cell": cell}, actor)
		"move_from":
			_mode = "move_to"
			_move_from = cell
			_refresh()
		"move_to":
			var from := _move_from
			_reset_mode()
			_submit(G.ABILITY, {"from": from, "to": cell}, actor)


# --- Ventana privada -----------------------------------------------------------------

## Qué enseñar en la ventana privada: la elección secreta de cargo, o la
## cortina antes del turno de una persona (si hay varias en este equipo).
func _update_overlay() -> void:
	if game.finished:
		_overlay.visible = false
		return
	var want := {}
	var actor := _local_actor()
	if actor >= 0:
		if game.phase == Phase.PICK:
			want = {"seat": actor, "kind": "pick"}
		elif game.phase == Phase.TURN and _hotseat_private and _turn_revealed != actor:
			want = {"seat": actor, "kind": "turn"}
	if want.is_empty():
		_overlay.visible = false
		_overlay_seat = -1
		_overlay_kind = ""
		return
	if want["seat"] != _overlay_seat or want["kind"] != _overlay_kind:
		_overlay_seat = want["seat"]
		_overlay_kind = want["kind"]
		_overlay_stage = "pass" if _hotseat_private else "show"
		_pick_office = -1
		_pick_bid = 0
	_overlay.visible = true
	_render_overlay()


func _render_overlay() -> void:
	_clear(_overlay_box)
	_place_overlay(_overlay_stage != "show")
	var seat := _overlay_seat
	var p := game.players[seat]
	if _overlay_stage == "pass":
		var title := _label("Pasa el dispositivo a", 20, BGCTheme.TEXT_DIM)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_box.add_child(title)
		var name_label := _label(p.display_name, 40, p.color.lightened(0.3))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", BGCTheme.bold_font(0.8))
		_overlay_box.add_child(name_label)
		var why := "elegir su cargo en secreto" if _overlay_kind == "pick" else "jugar su turno con su mano a la vista"
		var hint := _label("Es para %s. Los demás, no miréis la pantalla." % why, 15, BGCTheme.TEXT_DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_box.add_child(hint)
		_overlay_box.add_child(_button("Soy %s: mostrar" % p.display_name, func() -> void:
			if _overlay_kind == "turn":
				_turn_revealed = seat
				_overlay_kind = ""
				_overlay_seat = -1
				_refresh()
			else:
				_overlay_stage = "show"
				_render_overlay(), 18, "PrimaryButton"))
		return
	if _overlay_kind == "pick":
		_fill_pick(seat)


## Elección secreta de cargo y puja.
func _fill_pick(seat: int) -> void:
	var view := game.view_for(seat)
	var p := game.players[seat]
	var header := _label("Solo para %s · %d monedas" % [p.display_name, view["coins"][seat]], 15, p.color.lightened(0.3))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(header)
	_overlay_box.add_child(_label("Elige un cargo. Si alguien más lo elige, se lo queda la puja más alta (y la paga); si empatáis, quien va antes desde la vara (%s)." % game.players[view["vara"]].display_name, 13, BGCTheme.TEXT_DIM))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	for o in D.OFFICE_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var extra := "\n+%d monedas" % view["vacant_coins"][o] if view["vacant_coins"][o] > 0 else ""
		var b := _button("%d. %s%s" % [o + 1, D.OFFICE_NAMES[o], extra], func() -> void:
			_pick_office = o
			_render_overlay(), 13, "PrimaryButton" if _pick_office == o else "")
		b.custom_minimum_size = Vector2(150, 0)
		row.add_child(b)
		var text := _label(D.OFFICE_TEXT[o], 12, BGCTheme.TEXT if _pick_office == o else BGCTheme.TEXT_DIM)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(text)
		list.add_child(row)
	_overlay_box.add_child(list)
	var bid_row := HBoxContainer.new()
	bid_row.add_theme_constant_override("separation", 8)
	bid_row.add_child(_tag("Puja:", 15))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = view["coins"][seat]
	spin.value = _pick_bid
	spin.value_changed.connect(func(v: float) -> void: _pick_bid = int(v))
	bid_row.add_child(spin)
	bid_row.add_child(_tag("monedas (solo paga quien gana el cargo)", 13, BGCTheme.TEXT_DIM))
	_overlay_box.add_child(bid_row)
	var hand: Array = view["hand"]
	if not hand.is_empty():
		_overlay_box.add_child(_label("Tu mano:", 13, BGCTheme.TEXT_DIM))
		var cards := HFlowContainer.new()
		cards.add_theme_constant_override("h_separation", 4)
		cards.add_theme_constant_override("v_separation", 4)
		for c in hand:
			cards.add_child(Card.new(c, Vector2(56, 78)))
		_overlay_box.add_child(cards)
	var confirm := _button("Confirmar" if _pick_office >= 0 else "Elige un cargo", func() -> void:
		if _pick_office >= 0:
			_submit(G.PICK, {"office": _pick_office, "bid": _pick_bid}, seat), 17, "PrimaryButton")
	confirm.disabled = _pick_office < 0
	_overlay_box.add_child(confirm)
	if _error_label.text != "":
		_overlay_box.add_child(_label(_error_label.text, 14, ERROR_COLOR))


## Cortina opaca y centrada, o ventana acoplada a la derecha.
func _place_overlay(centered: bool) -> void:
	var panel: Control = _overlay_box.get_parent()
	var center: Control = _overlay.get_meta("center")
	var target: Control = center if centered else _overlay_dock
	if panel.get_parent() != target:
		panel.reparent(target, false)
	panel.custom_minimum_size = Vector2(560, 0) if centered else Vector2.ZERO
	var bg: ColorRect = _overlay.get_child(0)
	bg.color.a = 0.97 if centered else 0.45


# --- IA ---------------------------------------------------------------------------

func _schedule_ai() -> void:
	if game.finished or _ai_pending or _awaiting_host or not is_inside_tree() or _ai_actor() == -1:
		return
	_ai_pending = true
	var delay := AI_DELAY_FAST if _ai_fast_toggle.button_pressed else AI_DELAY
	if game.phase == Phase.PICK:
		delay *= 0.4
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
		push_warning("La IA de %s no encontró jugada" % game.players[actor].display_name)
		return
	var error := _send(action)
	if error != "":
		push_warning("Jugada ilegal de la IA: %s (%s)" % [action, error])


func _ai_actor() -> int:
	for pid in game.players_to_act():
		if _ais.has(pid):
			return pid
	return -1


# --- Interfaz -> acciones -----------------------------------------------------------

func _submit(type: StringName, data: Dictionary, pid: int) -> void:
	if _awaiting_host:
		return
	var error := _send(GameAction.new(type, pid, data))
	_error_label.text = error
	if error != "":
		Sfx.play(&"error")
		_refresh()


func _send(action: GameAction) -> String:
	if _network and not Net.is_host:
		if not game.players[action.player_id].is_ai and action.player_id != _local_seat:
			return "No puedes actuar por otro jugador"
		var error := game.validate(action)
		if error == "":
			Net.request_action(action.to_dict())
			if not game.players[action.player_id].is_ai:
				_awaiting_host = true
		return error
	return game.submit(action)


func _on_net_request(data: Dictionary, peer_id: int) -> void:
	if not _network:
		return
	var error := game.submit(GameAction.from_dict(data))
	if error != "":
		Net.reject(peer_id, error)


func _on_seat_replaced(seat: int) -> void:
	if not _network or game == null:
		return
	game.players[seat].ai_level = PlayerInfo.AILevel.NORMAL
	if Net.is_host:
		_ais[seat] = PuertoAI.new(seat, PlayerInfo.AILevel.NORMAL, game.rng.seed_value)
	_add_log("[color=#ffd166]%s se ha desconectado: ahora juega una IA.[/color]" % game.players[seat].display_name)
	_refresh()


func _on_net_action(data: Dictionary) -> void:
	if not _network or Net.is_host:
		return
	if int(data.get("player", -1)) == _local_seat:
		_awaiting_host = false
	var error := game.submit(GameAction.from_dict(data))
	if error != "":
		_add_log("[color=#ff8a80]Desincronización con el anfitrión: %s[/color]" % error)


# --- Eventos de la partida -------------------------------------------------------------

func _on_action_applied(action: GameAction) -> void:
	if _network and Net.is_host:
		Net.broadcast_action(action.to_dict())
	if not _network:
		if game.finished:
			App.delete_save(GAME_ID)
		else:
			App.save_game(GAME_ID, game.save_data())
	_error_label.text = ""
	_refresh()


func _on_game_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"picked":
			Sfx.play(&"click")
		&"picks_revealed":
			_add_log("[b]Se revelan los cargos:[/b]")
			for r in data["reveal"]:
				var result := "se lo queda" if r["won"] else "[color=#ff8a80]pierde[/color]"
				var paid := " y paga %d" % r["bid"] if r["won"] and r["bid"] > 0 else ""
				_add_log("  %s quería %s (puja %d): %s%s." % [_player_name(r["player"]), D.OFFICE_NAMES[r["office"]], r["bid"], result, paid])
			Sfx.play(&"seal")
		&"reassigned":
			_add_log("%s se queda %s (vacante)." % [_player_name(data["player"]), D.OFFICE_NAMES[data["office"]]])
		&"vacant_coins":
			_add_log("%s recoge %d moneda%s acumuladas en %s." % [_player_name(data["player"]), data["coins"], "s" if data["coins"] > 1 else "", D.OFFICE_NAMES[data["office"]]])
			Sfx.play(&"resource")
		&"turn":
			var pid: int = data["player"]
			_focus = -1
			_show_banner("%d. %s: %s" % [data["office"] + 1, D.OFFICE_NAMES[data["office"]], game.players[pid].display_name], game.players[pid].color)
			Sfx.play(&"turn")
		&"mayor":
			_add_log("%s coge la vara, roba 1 carta y gana %d moneda." % [_player_name(data["player"]), data["coins"]])
		&"income":
			var pid: int = data["player"]
			match int(data["kind"]):
				Income.COINS:
					_add_log("%s cobra %d monedas." % [_player_name(pid), data["coins"]])
					Sfx.play(&"resource")
				Income.DOCK:
					_add_log("%s coge %s del muelle%s." % [_player_name(pid), _card_name(data["card"]), " (y roba otra con el Astillero Real)" if data["extra"] else ""])
					Sfx.play(&"card")
				Income.BLIND:
					_add_log("%s roba a ciegas y cobra 1 moneda." % _player_name(pid))
					Sfx.play(&"card")
		&"harbor":
			_add_log("%s (Capitana) coge %s del muelle y lo renueva." % [_player_name(data["player"]), _card_name(data["card"])])
			Sfx.play(&"card")
		&"smuggled":
			_add_log("%s (Contrabandista) le quita una carta a %s." % [_player_name(data["player"]), _player_name(data["target"])])
			Sfx.play(&"robber")
		&"collected":
			var names: Array = data["payers"].map(func(pid: int) -> String: return game.players[pid].display_name)
			_add_log("%s (Recaudadora) cobra 1 moneda de: %s." % [_player_name(data["player"]), ", ".join(names) if not names.is_empty() else "nadie"])
			Sfx.play(&"trade")
		&"moved":
			_add_log("%s (Urbanista) traslada un edificio." % _player_name(data["player"]))
			Sfx.play(&"build")
		&"patron":
			_add_log("%s (Mecenas) cobra %d monedas." % [_player_name(data["player"]), data["coins"]])
			Sfx.play(&"resource")
		&"built":
			var pid: int = data["player"]
			_add_log("%s construye %s por %d." % [_player_name(pid), _card_name(data["card"]), data["cost"]])
			Sfx.play(&"build")
			if _focus_seat(game.view_for(-1)) == pid:
				_big_district.pulse(data["cell"])
		&"district_complete":
			var pid: int = data["player"]
			_add_log("[b]%s completa su barrio: la partida acaba al final de esta ronda.[/b]" % _player_name(pid))
			_show_banner("¡%s completa su barrio!" % game.players[pid].display_name, game.players[pid].color)
			Sfx.play(&"gong")
		&"reshuffle":
			_add_log("Se barajan los descartes: el mazo vuelve a tener %d cartas." % data["count"])
		&"new_round":
			if data["round"] > 1:
				_add_log("[b]Ronda %d.[/b]" % data["round"])
				_show_banner("Ronda %d: elegid cargo" % data["round"], BGCTheme.ACCENT)


func _on_game_finished(_winner_ids: Array[int]) -> void:
	_show_victory.call_deferred()


func _show_victory() -> void:
	_overlay.visible = false
	Sfx.play(&"win")
	var winners: Array[int] = game.winner_ids
	var names: Array = winners.map(func(pid: int) -> String: return game.players[pid].display_name)
	_add_log("[b]Fin de la partida. Gana %s.[/b]" % " y ".join(names))
	var box: VBoxContainer = _victory.get_meta("box")
	_clear(box)
	var color := game.players[winners[0]].color if winners.size() == 1 else BGCTheme.ACCENT
	var title := _label("¡Gana %s!" % " y ".join(names), 32, color.lightened(0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for h in ["Jugador", "Edificios", "Grupos", "Maravillas", "Objetivos", "Primero", "Total"]:
		grid.add_child(_tag(h, 13, BGCTheme.TEXT_DIM))
	var order: Array = range(game.players.size())
	order.sort_custom(func(a: int, b: int) -> bool: return game.final_scores[a]["total"] > game.final_scores[b]["total"])
	for pid in order:
		var s: Dictionary = game.final_scores[pid]
		grid.add_child(_tag(game.players[pid].display_name, 14, game.players[pid].color.lightened(0.3)))
		for key in ["buildings", "groups", "wonders", "objectives", "first", "total"]:
			grid.add_child(_tag(str(s[key]), 14 if key != "total" else 16, BGCTheme.ACCENT if key == "total" else BGCTheme.TEXT))
	box.add_child(grid)
	box.add_child(_label("Si hay empate a puntos, gana quien tenga más monedas.", 12, BGCTheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if not _network:
		var again := _button("Nueva partida", func() -> void: _start(BGCRng.random_seed()), 16, "PrimaryButton")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(again)
	var close := _button("Ver los barrios", func() -> void: _victory.visible = false, 16)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(close)
	var menu := _button("Menú", App.go_to_menu, 16, "GhostButton")
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)
	box.add_child(row)
	_victory.visible = true
	_refresh()


# --- Utilidades ---------------------------------------------------------------------

func _show_banner(text: String, color: Color) -> void:
	_banner_queue.append([text, color])
	if not _banner_busy:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_busy = false
		return
	_banner_busy = true
	var item: Array = _banner_queue.pop_front()
	_banner.text = item[0]
	_banner.add_theme_color_override("font_color", Color(item[1]).lightened(0.3))
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2.ONE * 0.85
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_next_banner)


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
	return "[color=#%s]%s[/color]" % [p.color.lightened(0.25).to_html(false), p.display_name]


func _card_name(card: int) -> String:
	return "[color=#%s]%s[/color]" % [PuertoArt.guild_color(D.guild_of(card)).lightened(0.3).to_html(false), D.card_name(card)]
