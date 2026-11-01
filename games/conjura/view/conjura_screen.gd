extends Control
## Pantalla de una partida de La Conjura.
##
## Izquierda: jugadores y registro público. Centro: tablero. Derecha: lo que
## hay que hacer ahora (acciones públicas: nominar, elegir y usar poderes).
##
## INFORMACIÓN OCULTA: todo lo secreto (rol, aliados, edictos en mano, votos,
## resultados de poderes) se enseña en una ventana privada a pantalla
## completa. Si en este equipo juegan varias personas, antes aparece una
## cortina de «Pasa el dispositivo a X» para que solo mire quien debe.
## La pantalla solo lee game.view_for(seat), nunca el estado interno.

const G := preload("res://games/conjura/logic/conjura_game.gd")
const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Faction := ConjuraDefs.Faction
const Edict := ConjuraDefs.Edict
const Power := ConjuraDefs.Power
const Phase := ConjuraGame.Phase

const GAME_ID := "conjura"
const BACKGROUND := Color("1b1724")
const LEFT_WIDTH := 290.0
const RIGHT_WIDTH := 330.0
const AI_DELAY := 0.7
const AI_DELAY_FAST := 0.15
const ERROR_COLOR := Color("ff8a80")
const DOCK_WIDTH := 470.0

var game: ConjuraGame
var _ais := {}
var _ai_pending := false
var _ai_generation := 0
var _network := false
var _local_seat := -1
## Hay varias personas en este equipo: lo privado necesita cortina.
var _hotseat_private := false
## Única persona de este equipo (-1 si hay varias o ninguna): ve su
## información todo el rato en el panel derecho.
var _me := -1

var _log: Array[String] = []
var _players_box: VBoxContainer
var _log_label: RichTextLabel
var _board: ConjuraBoard
var _phase_label: Label
var _prompt_label: Label
var _error_label: Label
var _actions_box: VBoxContainer
var _info_box: VBoxContainer
var _ai_fast_toggle: CheckButton
var _info_button: Button
var _banner: Label

## Ventana privada: cola de cosas que enseñar ({seat, kind}) y estado.
var _private_queue: Array[Dictionary] = []
var _overlay: Control
var _overlay_box: VBoxContainer
var _overlay_dock: MarginContainer
var _overlay_seat := -1
var _overlay_kind := ""
var _overlay_stage := ""
var _victory: Control


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
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_build_left_panel())
	_board = ConjuraBoard.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_board)
	row.add_child(_build_right_panel())
	_build_overlays()

	Net.action_received.connect(_on_net_action)
	Net.action_requested.connect(_on_net_request)
	Net.action_rejected.connect(func(message: String) -> void:
		_error_label.text = message
		Sfx.play(&"error"))
	_start(App.session_seed())


func _start(seed: int) -> void:
	game = ConjuraGame.new()
	game.setup(App.session_players(5), seed)
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
	_private_queue.clear()
	_overlay_seat = -1
	_overlay_kind = ""

	var humans := _local_humans()
	_hotseat_private = not _network and humans.size() > 1
	_me = humans[0] if humans.size() == 1 else -1
	_info_button.visible = _hotseat_private
	_board.player_names.clear()
	_board.player_colors.clear()
	for p in game.players:
		_board.player_names.append(p.display_name)
		_board.player_colors.append(p.color)

	if not saved.is_empty():
		_add_log("Partida guardada cargada (%d jugadas)." % game.history.size())
		if load_error != "":
			_add_log("[color=#ff8a80]No se pudo cargar del todo: %s[/color]" % load_error)
		if _hotseat_private:
			_add_log("Usad «Ver mi información» para recordar vuestro rol.")
	else:
		_add_log("Partida nueva con %d jugadores. Cada uno recibe su rol en secreto." % game.players.size())
		_add_log("Primer Regente: %s." % _player_name(game.regent))
		# Cada persona de este equipo ve su rol al empezar.
		for pid in humans:
			_private_queue.append({"seat": pid, "kind": "info"})
	_refresh()
	_show_banner("Regente: %s" % game.players[game.regent].display_name, game.players[game.regent].color)


func _create_ais(seed: int) -> void:
	_ais.clear()
	var autoplay := OS.get_environment("BGC_AUTOPLAY") == "1"
	for p in game.players:
		var runs_here := p.is_ai and (not _network or Net.is_host)
		if runs_here or (autoplay and not p.is_ai):
			_ais[p.id] = ConjuraAI.new(p.id, p.ai_level if p.is_ai else PlayerInfo.AILevel.NORMAL, seed)


## Personas (no IA) que juegan en este equipo.
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


static func _is_private_phase(phase: int) -> bool:
	return phase in [Phase.VOTE, Phase.REGENT_DISCARD, Phase.COUNCIL_ENACT]


# --- Construcción de la interfaz ---------------------------------------------------

func _panel(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", BGCTheme.box(Color(0.07, 0.05, 0.1, 0.8), Color(1, 1, 1, 0.1), 16, 1, 8, 12))
	return panel


func _label(text: String = "", font_size: int = 16, color: Color = BGCTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Etiqueta de una sola línea (para filas y rejillas).
func _tag(text: String, font_size: int = 14, color: Color = BGCTheme.TEXT) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _button(text: String, callback: Callable, font_size: int = 15, variation: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(func() -> void: Sfx.play(&"click"))
	button.pressed.connect(callback)
	return button


func _build_left_panel() -> Control:
	var panel := _panel(LEFT_WIDTH)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := _label("La Conjura", 26, BGCTheme.ACCENT)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 3)
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
	_info_button = _button("Ver mi información", _open_info_picker, 14)
	box.add_child(_info_button)
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
	_info_box.add_theme_constant_override("separation", 6)
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

	_overlay = _modal(Color(0.03, 0.02, 0.05, 0.97))
	_overlay_box = _overlay.get_meta("box")
	# Al mostrar lo privado, la ventana se acopla a la derecha para que el
	# tablero y el registro (públicos) sigan a la vista.
	_overlay_dock = MarginContainer.new()
	_overlay_dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_overlay_dock.offset_left = -DOCK_WIDTH - 12
	for side in ["right", "top", "bottom"]:
		_overlay_dock.add_theme_constant_override("margin_" + side, 12)
	_overlay.add_child(_overlay_dock)
	_victory = _modal(Color(0, 0, 0, 0.75))


## Capa a pantalla completa con un panel centrado (su VBox en meta "box").
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
	panel.add_theme_stylebox_override("panel", BGCTheme.box(Color("221b2e"), Color(1, 1, 1, 0.15), 18, 1, 18, 24))
	center.add_child(panel)
	root.set_meta("center", center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	root.set_meta("box", box)
	return root


# --- Estado -> interfaz ----------------------------------------------------------

func _refresh() -> void:
	var pub := game.view_for(-1)
	_board.refresh(pub)
	_refresh_players(pub)
	_refresh_actions(pub)
	_refresh_info()
	_update_overlay()
	_schedule_ai()


func _refresh_players(pub: Dictionary) -> void:
	_clear(_players_box)
	var known: Dictionary = game.view_for(_me)["known_roles"] if _me >= 0 else {}
	if game.finished:
		known = pub["known_roles"]
	var phase: int = pub["phase"]
	for p in game.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = p.color
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var dead: bool = not pub["alive"][p.id]
		var name_label := _label(p.display_name + (" (IA)" if p.is_ai else ""), 14, Color(BGCTheme.TEXT, 0.4) if dead else BGCTheme.TEXT)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var tags: Array[String] = []
		if dead:
			tags.append("Desterrado")
		if p.id == pub["regent"] and not dead:
			tags.append("Regente")
		if p.id == pub["nominee"]:
			tags.append("Nominado")
		if p.id == pub["council"] and phase in [Phase.REGENT_DISCARD, Phase.COUNCIL_ENACT, Phase.CHOOSE_POWER, Phase.USE_POWER]:
			tags.append("Consejero")
		if phase != Phase.VOTE and p.id == pub["last_council"] and p.id != pub["council"]:
			tags.append("ex-Consejero")
		var tag_label := _label(" · ".join(tags), 12, BGCTheme.ACCENT)
		tag_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(tag_label)
		if phase == Phase.VOTE and pub["alive"][p.id]:
			row.add_child(_tag("✔" if pub["voted"].has(p.id) else "…", 13, BGCTheme.TEXT_DIM))
		elif pub["last_votes"].has(p.id):
			var yes: bool = pub["last_votes"][p.id]
			row.add_child(_tag("Sí" if yes else "No", 13, Color("8fd694") if yes else ERROR_COLOR))
		if known.has(p.id) and (p.id != _me or game.finished):
			var role: int = known[p.id]
			var role_label := _label(_role_short(role), 12, D.faction_color(D.faction_of(role)).lightened(0.3))
			role_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(role_label)
		_players_box.add_child(row)


func _refresh_actions(pub: Dictionary) -> void:
	_clear(_actions_box)
	var phase: int = pub["phase"]
	_phase_label.text = G.PHASE_NAMES[phase]
	if game.finished:
		_prompt_label.text = game.win_reason
		return
	var actor := _local_actor()
	var regent := _player_name_plain(pub["regent"])
	var council := _player_name_plain(pub["council"])
	match phase:
		Phase.NOMINATE:
			if actor >= 0:
				_prompt_label.text = "%s, eres Regente: nomina a un Consejero." % regent
				for t in pub["eligible"]:
					_actions_box.add_child(_player_button(t, func() -> void: _submit(G.NOMINATE, {"target": t}, actor)))
				if pub["last_council"] >= 0 and pub["alive"][pub["last_council"]]:
					_actions_box.add_child(_label("%s fue el último Consejero y no puede repetir." % _player_name_plain(pub["last_council"]), 12, BGCTheme.TEXT_DIM))
			else:
				_prompt_label.text = "%s (Regente) está eligiendo Consejero." % regent
		Phase.VOTE:
			var total: int = game.alive_ids().size()
			_prompt_label.text = "Gobierno propuesto: %s (Regente) y %s (Consejero).\nHan votado %d de %d." % [regent, _player_name_plain(pub["nominee"]), pub["voted"].size(), total]
			if pub["crisis"] == D.MAX_CRISIS - 1:
				_actions_box.add_child(_label("¡Si falla esta votación habrá crisis!", 14, Color("e07a3c")))
			_private_hint(actor)
		Phase.REGENT_DISCARD:
			_prompt_label.text = "%s (Regente) ha robado 3 edictos y descarta uno en secreto." % regent
			_private_hint(actor)
		Phase.COUNCIL_ENACT:
			_prompt_label.text = "%s (Consejero) elige en secreto qué edicto promulgar." % council
			_private_hint(actor)
		Phase.CHOOSE_POWER:
			_prompt_label.text = "Edicto de la Sombra: %s (Consejero) elige un poder." % council
			for i in pub["power_options"].size():
				var power: int = pub["power_options"][i]
				if actor >= 0:
					var b := _button("%s\n%s" % [D.POWER_NAMES[power], D.POWER_HELP[power]], func() -> void: _submit(G.CHOOSE_POWER, {"index": i}, actor), 14)
					b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					b.alignment = HORIZONTAL_ALIGNMENT_LEFT
					_actions_box.add_child(b)
				else:
					_actions_box.add_child(_label("• %s: %s" % [D.POWER_NAMES[power], D.POWER_HELP[power]], 14))
		Phase.USE_POWER:
			var power: int = pub["pending_power"]
			_prompt_label.text = "%s usa %s: %s" % [council, D.POWER_NAMES[power], D.POWER_HELP[power]]
			if actor >= 0:
				if D.power_needs_target(power):
					for t in pub["power_targets"]:
						_actions_box.add_child(_player_button(t, func() -> void: _submit(G.USE_POWER, {"target": t}, actor)))
				else:
					_actions_box.add_child(_button("Usar %s" % D.POWER_NAMES[power], func() -> void: _submit(G.USE_POWER, {"target": -1}, actor), 15, "PrimaryButton"))


## En una fase secreta: explica dónde se decide.
func _private_hint(actor: int) -> void:
	if actor < 0:
		return
	if _hotseat_private:
		_actions_box.add_child(_label("Turno secreto de %s: pasadle el dispositivo." % _player_name_plain(actor), 14, BGCTheme.ACCENT))


func _player_button(pid: int, callback: Callable) -> Button:
	var b := _button(game.players[pid].display_name, callback, 15)
	b.add_theme_color_override("font_color", game.players[pid].color.lightened(0.35))
	return b


## Panel derecho, abajo: la información de la única persona del equipo.
func _refresh_info() -> void:
	_clear(_info_box)
	if _me < 0:
		if _hotseat_private:
			_info_box.add_child(_label("Varias personas juegan en este equipo: la información secreta solo aparece en la ventana privada.", 13, BGCTheme.TEXT_DIM))
		return
	_fill_identity(_info_box, _me, 15)
	_fill_knowledge(_info_box, _me)


# --- Ventana privada -----------------------------------------------------------------

## Decide qué enseñar en la ventana privada: primero la cola (roles al
## empezar, resultados de poderes) y luego la jugada secreta pendiente.
func _update_overlay() -> void:
	if _overlay_kind == "picker":
		return  # el selector de «Ver mi información» sigue abierto
	if game.finished:
		_overlay.visible = false
		return
	var want := {}
	if not _private_queue.is_empty():
		want = _private_queue[0]
	else:
		var actor := _local_actor()
		if actor >= 0 and _is_private_phase(game.phase):
			want = {"seat": actor, "kind": "action"}
	if want.is_empty():
		_overlay.visible = false
		_overlay_seat = -1
		_overlay_kind = ""
		return
	var key_changed: bool = want["seat"] != _overlay_seat or want["kind"] != _overlay_kind
	if key_changed:
		_overlay_seat = want["seat"]
		_overlay_kind = want["kind"]
		_overlay_stage = "pass" if _hotseat_private else "show"
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
		var why := {"info": "para ver su rol en secreto", "result": "para ver el resultado de su poder", "action": _action_reason()}
		var hint := _label("Es %s. Los demás, no miréis la pantalla." % why[_overlay_kind], 15, BGCTheme.TEXT_DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_box.add_child(hint)
		_overlay_box.add_child(_button("Soy %s: mostrar" % p.display_name, func() -> void:
			_overlay_stage = "show"
			_render_overlay(), 18, "PrimaryButton"))
		return

	var header := _label("Solo para %s" % p.display_name, 15, p.color.lightened(0.3))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(header)
	match _overlay_kind:
		"info":
			_fill_identity(_overlay_box, seat, 18)
			_fill_knowledge(_overlay_box, seat)
			_overlay_box.add_child(_button("Ocultar", _pop_private, 16, "PrimaryButton"))
		"result":
			var knowledge: Array = game.view_for(seat)["knowledge"]
			var big := _label(_describe_knowledge(knowledge[-1]) if not knowledge.is_empty() else "Sin resultado.", 22)
			big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_overlay_box.add_child(big)
			_overlay_box.add_child(_button("Ocultar", _pop_private, 16, "PrimaryButton"))
		"action":
			_fill_private_action(_overlay_box, seat)


func _action_reason() -> String:
	match game.phase:
		Phase.VOTE: return "su turno de votar"
		Phase.REGENT_DISCARD: return "su turno de descartar como Regente"
		Phase.COUNCIL_ENACT: return "su turno de promulgar como Consejero"
	return "su turno"


func _pop_private() -> void:
	if not _private_queue.is_empty():
		_private_queue.pop_front()
	_refresh()


## Jugada secreta: votar, descartar o promulgar.
func _fill_private_action(box: VBoxContainer, seat: int) -> void:
	var view := game.view_for(seat)
	_fill_identity(box, seat, 14)
	match game.phase:
		Phase.VOTE:
			var text := _label("Gobierno propuesto:\n%s (Regente)  y  %s (Consejero)" % [_player_name_plain(view["regent"]), _player_name_plain(view["nominee"])], 20)
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(text)
			if view["crisis"] == D.MAX_CRISIS - 1:
				box.add_child(_label("Si se rechaza, habrá crisis: se promulgará el primer edicto del mazo y subirá el descontento.", 14, Color("e07a3c")))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			for entry in [["Aprobar", true], ["Rechazar", false]]:
				var b := _button(entry[0], func() -> void: _submit(G.VOTE, {"yes": entry[1]}, seat), 20, "PrimaryButton" if entry[1] else "")
				b.custom_minimum_size = Vector2(0, 60)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(b)
			box.add_child(row)
		Phase.REGENT_DISCARD:
			box.add_child(_label("Has robado estos 3 edictos. Descarta uno; %s (Consejero) recibirá los otros dos." % _player_name_plain(view["council"]), 16))
			box.add_child(_card_row(view["hand"], func(i: int) -> void: _submit(G.DISCARD, {"index": i}, seat), "Descartar"))
		Phase.COUNCIL_ENACT:
			box.add_child(_label("%s (Regente) te ha pasado estos 2 edictos. Promulga uno; el otro se descarta." % _player_name_plain(view["regent"]), 16))
			box.add_child(_card_row(view["hand"], func(i: int) -> void: _submit(G.ENACT, {"index": i}, seat), "Promulgar"))
	var err := _label("", 14, ERROR_COLOR)
	err.text = _error_label.text
	box.add_child(err)


func _card_row(cards: Array, on_pick: Callable, verb: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for i in cards.size():
		var edict: int = cards[i]
		var color := D.edict_color(edict)
		var b := Button.new()
		b.text = "%s\n\n%s" % [D.EDICT_SHORT[edict], verb]
		b.custom_minimum_size = Vector2(130, 170)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", BGCTheme.box(color.darkened(0.15), color.lightened(0.4), 12, 3, 6))
		b.add_theme_stylebox_override("hover", BGCTheme.box(color, Color.WHITE, 12, 3, 9))
		b.add_theme_stylebox_override("pressed", BGCTheme.box(color.darkened(0.3), Color.WHITE, 12, 3, 2))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(func() -> void:
			Sfx.play(&"card")
			on_pick.call(i))
		row.add_child(b)
	return row


## Rol y aliados conocidos de `seat`.
func _fill_identity(box: VBoxContainer, seat: int, font_size: int) -> void:
	var view := game.view_for(seat)
	var known: Dictionary = view["known_roles"]
	var role: int = known[seat]
	var color := D.faction_color(D.faction_of(role))
	var role_panel := PanelContainer.new()
	role_panel.add_theme_stylebox_override("panel", BGCTheme.box(Color(color, 0.25), color, 12, 2, 0, 10))
	var role_box := VBoxContainer.new()
	role_panel.add_child(role_box)
	role_box.add_child(_label("Tu rol", font_size - 3, BGCTheme.TEXT_DIM))
	var name_label := _label(D.ROLE_NAMES[role], font_size + 8, color.lightened(0.4))
	name_label.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	role_box.add_child(name_label)
	role_box.add_child(_label(_role_goal(role), font_size - 2))
	box.add_child(role_panel)
	var allies: Array[String] = []
	for pid in known:
		if pid != seat:
			allies.append("%s (%s)" % [game.players[pid].display_name, D.ROLE_NAMES[known[pid]]])
	if not allies.is_empty():
		box.add_child(_label("Tus aliados: " + ", ".join(allies), font_size - 1, D.COLOR_SOMBRA.lightened(0.4)))
	elif role == Role.USURPADOR:
		box.add_child(_label("No sabes quiénes son tus aliados, pero ellos sí saben quién eres.", font_size - 1, BGCTheme.TEXT_DIM))


func _role_goal(role: int) -> String:
	match role:
		Role.GUARDIA:
			return "Promulga 5 edictos de la Guardia o destierra al Usurpador. No sabes quién es quién: desconfía."
		Role.SOMBRA:
			return "Promulga 6 edictos de la Sombra o haz que elijan Consejero al Usurpador cuando haya 3 o más. Protege al Usurpador."
	return "Eres el líder secreto de la Sombra. Gana si os eligen a ti como Consejero con 3 o más edictos de la Sombra, o con 6. Que no te destierren."


func _fill_knowledge(box: VBoxContainer, seat: int) -> void:
	var knowledge: Array = game.view_for(seat)["knowledge"]
	if knowledge.is_empty():
		return
	box.add_child(_label("Lo que sabes", 13, BGCTheme.TEXT_DIM))
	for k in knowledge:
		box.add_child(_label("• " + _describe_knowledge(k), 13))


func _describe_knowledge(k: Dictionary) -> String:
	match String(k["kind"]):
		"faction":
			return "%s es de la %s." % [_player_name_plain(k["target"]), D.FACTION_NAMES[k["faction"]]]
		"top":
			return "Augurio: los próximos edictos son %s." % _cards_text(k["cards"])
		"discarded":
			return "Pesquisa: %s (Regente) descartó un %s." % [_player_name_plain(k["regent"]), D.EDICT_NAMES[k["card"]]]
		"drawn":
			return "Como Regente (con %s) robaste: %s." % [_player_name_plain(k["council"]), _cards_text(k["cards"])]
		"received":
			return "Como Consejero (de %s) recibiste: %s." % [_player_name_plain(k["regent"]), _cards_text(k["cards"])]
	return str(k)


func _cards_text(cards: Array) -> String:
	var names: Array[String] = []
	for c in cards:
		names.append(D.EDICT_SHORT[c])
	return ", ".join(names)


## Botón «Ver mi información» (varias personas): elegir quién quiere mirar.
func _open_info_picker() -> void:
	_clear(_overlay_box)
	_place_overlay(true)
	_overlay.visible = true
	_overlay_seat = -1
	_overlay_kind = "picker"
	var title := _label("¿Quién quiere ver su información?", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for pid in _local_humans():
		var b := _player_button(pid, func() -> void:
			_private_queue.push_front({"seat": pid, "kind": "info"})
			_overlay_kind = ""
			_refresh())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	_overlay_box.add_child(grid)
	_overlay_box.add_child(_button("Cancelar", func() -> void:
		_overlay_kind = ""
		_refresh(), 15, "GhostButton"))


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
	if game.finished or _ai_pending or not is_inside_tree() or _ai_actor() == -1:
		return
	_ai_pending = true
	var delay := AI_DELAY_FAST if _ai_fast_toggle.button_pressed else AI_DELAY
	if game.phase == Phase.VOTE:
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
		return error
	return game.submit(action)


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


# --- Eventos de la partida -------------------------------------------------------------

func _on_action_applied(action: GameAction) -> void:
	if _network and Net.is_host:
		Net.broadcast_action(action.to_dict())
	if action.type == G.VOTE:
		Sfx.play(&"click")
	if not _network:
		if game.finished:
			App.delete_save(GAME_ID)
		else:
			App.save_game(GAME_ID, game.save_data())
	_error_label.text = ""
	_refresh()


func _on_game_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"nominated":
			_add_log("%s (Regente) nomina a %s como Consejero." % [_player_name(data["regent"]), _player_name(data["nominee"])])
		&"vote_result":
			var yes_names: Array[String] = []
			var no_names: Array[String] = []
			for pid in data["votes"]:
				(yes_names if data["votes"][pid] else no_names).append(game.players[pid].display_name)
			var result := "[color=#8fd694]APROBADO[/color]" if data["approved"] else "[color=#ff8a80]RECHAZADO[/color]"
			_add_log("Votación: %s (%d a %d). Sí: %s. No: %s." % [result, yes_names.size(), no_names.size(), _join(yes_names), _join(no_names)])
			Sfx.play(&"trade" if data["approved"] else &"error")
		&"crisis":
			_add_log("[b][color=#e07a3c]¡Crisis![/color][/b] Tres votaciones fallidas: se promulga el primer edicto del mazo y sube el descontento.")
			Sfx.play(&"robber")
		&"enacted":
			var edict: int = data["edict"]
			var color := D.edict_color(edict).lightened(0.3).to_html(false)
			_add_log("[b]Se promulga un [color=#%s]%s[/color].[/b]" % [color, D.EDICT_NAMES[edict]])
			_board.pulse(edict)
			Sfx.play(&"card")
			if edict == Edict.NEUTRAL:
				_add_log("El descontento sube.")
		&"power_offer":
			var options: Array = data["options"]
			_add_log("%s puede elegir poder: %s o %s." % [_player_name(data["council"]), D.POWER_NAMES[options[0]], D.POWER_NAMES[options[1]]])
		&"power_chosen":
			_add_log("%s elige [b]%s[/b]." % [_player_name(data["council"]), D.POWER_NAMES[data["power"]]])
		&"power_used":
			var power: int = data["power"]
			var council: int = data["council"]
			match power:
				Power.ESPIAR:
					_add_log("%s espía la facción de %s." % [_player_name(council), _player_name(data["target"])])
				Power.AUGURIO:
					_add_log("%s mira los 3 primeros edictos del mazo." % _player_name(council))
				Power.PESQUISA:
					_add_log("%s mira el edicto que descartó el Regente." % _player_name(council))
				Power.SUCESION:
					_add_log("%s nombra próximo Regente a %s." % [_player_name(council), _player_name(data["target"])])
			if power in [Power.ESPIAR, Power.AUGURIO, Power.PESQUISA] and _is_local(council):
				_private_queue.append({"seat": council, "kind": "result"})
		&"banished":
			_add_log("[b]%s queda desterrado.[/b]" % _player_name(data["target"]))
			Sfx.play(&"robber")
		&"reshuffle":
			_add_log("Se baraja el descarte: el mazo vuelve a tener %d edictos." % data["count"])
		&"new_round":
			var regent: int = data["regent"]
			_show_banner("Regente: %s" % game.players[regent].display_name, game.players[regent].color)
			Sfx.play(&"turn")


func _on_game_finished(_winner_ids: Array[int]) -> void:
	_show_victory.call_deferred()


func _show_victory() -> void:
	_overlay.visible = false
	_private_queue.clear()
	Sfx.play(&"win")
	var faction := game.winner_faction
	var color := D.faction_color(faction)
	_add_log("[b]Fin: gana la %s.[/b] %s" % [D.FACTION_NAMES[faction], game.win_reason])
	var box: VBoxContainer = _victory.get_meta("box")
	_clear(box)
	var title := _label("¡Gana la %s!" % D.FACTION_NAMES[faction], 32, color.lightened(0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	var reason := _label(game.win_reason, 16)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(reason)
	box.add_child(_label("Roles", 14, BGCTheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	var roles: Dictionary = game.view_for(-1)["known_roles"]
	for p in game.players:
		grid.add_child(_tag(p.display_name, 16, p.color.lightened(0.3)))
		var role: int = roles[p.id]
		grid.add_child(_tag(D.ROLE_NAMES[role], 16, D.faction_color(D.faction_of(role)).lightened(0.35)))
	box.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if not _network:
		var again := _button("Nueva partida", func() -> void: _start(BGCRng.random_seed()), 16, "PrimaryButton")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(again)
	var close := _button("Ver el tablero", func() -> void: _victory.visible = false, 16)
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
	_banner.text = text
	_banner.add_theme_color_override("font_color", color.lightened(0.3))
	var tween := create_tween()
	_banner.modulate.a = 1.0
	tween.tween_interval(0.8)
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
	var p := game.players[pid]
	return "[color=#%s]%s[/color]" % [p.color.lightened(0.25).to_html(false), p.display_name]


func _player_name_plain(pid: int) -> String:
	return game.players[pid].display_name if pid >= 0 and pid < game.players.size() else "—"


func _join(names: Array[String]) -> String:
	return ", ".join(names) if not names.is_empty() else "nadie"


func _role_short(role: int) -> String:
	match role:
		Role.GUARDIA: return "Guardia"
		Role.SOMBRA: return "Sombra"
	return "Usurpador"
