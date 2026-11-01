extends Control
## Pantalla de una partida de Bajamar.
##
## Izquierda: marcador, registro y opciones. Centro: la mesa (mazo con el
## riesgo de tormenta, mercado y descartes) y la barca de cada jugador con su
## red. Derecha: lo que puede hacer el jugador en turno, con los puntos que
## le daría cada opción.
##
## En Bajamar todo es público salvo el orden del mazo, así que no hace falta
## esconder nada aunque jueguen varias personas en el mismo equipo.
##
## Atajos: R robar a ciegas, P volver a puerto, 1-3 coger del mercado.

const G := preload("res://games/bajamar/logic/bajamar_game.gd")
const D := preload("res://games/bajamar/logic/bajamar_defs.gd")
const Card := BajamarArt.BajamarCard
const Status := BajamarGame.Status

const GAME_ID := "bajamar"
const BACKGROUND := Color("0b1e33")
const LEFT_WIDTH := 270.0
const RIGHT_WIDTH := 320.0
const AI_DELAY := 0.75
const AI_DELAY_FAST := 0.15
## Sin personas en este equipo, el resumen de la ronda se cierra solo.
const SUMMARY_AUTO_CLOSE := 3.5
const ERROR_COLOR := Color("ff8a80")
const BIG_CARD := Vector2(70, 98)
const NET_CARD := Vector2(46, 64)

var game: BajamarGame
var _ais := {}
var _ai_pending := false
var _ai_generation := 0
var _network := false
var _local_seat := -1
## Cliente: esperando a que el anfitrión confirme nuestra jugada.
var _awaiting_host := false

var _log: Array[String] = []
var _players_box: VBoxContainer
var _log_label: RichTextLabel
var _ai_fast_toggle: CheckButton
var _deck_card: Card
var _deck_label: Label
var _risk_label: Label
var _market_box: HBoxContainer
var _discard_slot: Control
var _discard_label: Label
var _boats: GridContainer
var _round_label: Label
var _prompt_label: Label
var _error_label: Label
var _actions_box: VBoxContainer
var _info_box: VBoxContainer
var _banner: Label
var _summary: Control
var _victory: Control

## Rótulos pendientes de mostrar uno tras otro: [texto, color].
var _banner_queue: Array = []
var _banner_busy := false
## Animaciones pendientes para el siguiente redibujado.
var _fresh_net: Dictionary = {}       # pid -> número de cartas nuevas al final de su red
var _broken_flash: Dictionary = {}    # pid -> true
var _last_market: Array[int] = []
## Resultados de la última ronda terminada (para el resumen).
var _round_results: Array = []
var _round_shown := 0


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
	resized.connect(_layout)
	_start(App.session_seed())


func _start(seed: int) -> void:
	game = BajamarGame.new()
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
	_summary.visible = false
	_victory.visible = false
	_fresh_net.clear()
	_broken_flash.clear()
	_last_market = game.market.duplicate()
	_round_shown = game.round_number
	if not saved.is_empty():
		_add_log("Partida guardada cargada (%d jugadas)." % game.history.size())
		if load_error != "":
			_add_log("[color=#ff8a80]No se pudo cargar del todo: %s[/color]" % load_error)
	elif _network:
		_add_log("Partida en red local. Juegas como %s." % _player_name(_local_seat))
	else:
		_add_log("Partida nueva con %d jugadores. Gana quien tenga más puntos cuando alguien llegue a %d." % [game.players.size(), game.target_score])
	_refresh()
	_layout()
	_show_banner("Ronda %d" % game.round_number, BGCTheme.ACCENT)


## IAs que maneja este equipo (todas en local; en red, solo el anfitrión). Con
## BGC_AUTOPLAY=1, las personas de este equipo también juegan solas.
func _create_ais(seed: int) -> void:
	_ais.clear()
	var autoplay := OS.get_environment("BGC_AUTOPLAY") == "1"
	for p in game.players:
		var runs_here := p.is_ai and (not _network or Net.is_host)
		var local_human := not p.is_ai and (not _network or p.id == _local_seat)
		if runs_here or (autoplay and local_human):
			_ais[p.id] = BajamarAI.new(p.id, p.ai_level if p.is_ai else PlayerInfo.AILevel.NORMAL, seed)


func _is_local(pid: int) -> bool:
	if pid < 0 or game.players[pid].is_ai or _ais.has(pid):
		return false
	return pid == _local_seat if _network else true


## Persona de este equipo que debe actuar ahora (o -1).
func _local_actor() -> int:
	if game.finished or _summary.visible:
		return -1
	for pid in game.players_to_act():
		if _is_local(pid):
			return pid
	return -1


func _has_local_humans() -> bool:
	for p in game.players:
		if _is_local(p.id):
			return true
	return false


# --- Construcción de la interfaz ---------------------------------------------------

func _panel(width: float, fill: Color = Color(0.03, 0.09, 0.16, 0.85)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", BGCTheme.box(fill, Color(1, 1, 1, 0.1), 16, 1, 8, 12))
	return panel


func _label(text: String = "", font_size: int = 16, color: Color = BGCTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Etiqueta de una sola línea (para filas).
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
	var title := _label("Bajamar", 28, BGCTheme.ACCENT)
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	box.add_child(_label("Meta: %d puntos" % D.TARGET_SCORE, 13, BGCTheme.TEXT_DIM))
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
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)

	var table := _panel(0, Color(0.06, 0.2, 0.32, 0.9))
	column.add_child(table)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	table.add_child(row)

	var deck_box := _column_box()
	deck_box.add_child(_tag("Mazo", 13, BGCTheme.TEXT_DIM))
	_deck_card = Card.new(-1, BIG_CARD)
	_deck_card.pressed.connect(func() -> void: _act(G.DRAW_BLIND))
	deck_box.add_child(_deck_card)
	_deck_label = _tag("", 13)
	deck_box.add_child(_deck_label)
	_risk_label = _tag("", 13, BGCTheme.ACCENT)
	deck_box.add_child(_risk_label)
	row.add_child(deck_box)

	var market_col := _column_box()
	market_col.add_child(_tag("Mercado · coger una = volver a puerto con ella", 13, BGCTheme.TEXT_DIM))
	_market_box = HBoxContainer.new()
	_market_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_market_box.add_theme_constant_override("separation", 10)
	_market_box.custom_minimum_size = Vector2(0, BIG_CARD.y + 6)
	market_col.add_child(_market_box)
	row.add_child(market_col)

	var discard_box := _column_box()
	discard_box.add_child(_tag("Descartes", 13, BGCTheme.TEXT_DIM))
	_discard_slot = CenterContainer.new()
	_discard_slot.custom_minimum_size = BIG_CARD
	discard_box.add_child(_discard_slot)
	_discard_label = _tag("", 13)
	discard_box.add_child(_discard_label)
	row.add_child(discard_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_boats = GridContainer.new()
	_boats.columns = 2
	_boats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boats.add_theme_constant_override("h_separation", 10)
	_boats.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_boats)
	return column


func _column_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
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
	_round_label = _label("", 22, BGCTheme.ACCENT)
	box.add_child(_round_label)
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
	_summary = _modal(Color(0, 0, 0, 0.6))
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
	panel.add_theme_stylebox_override("panel", BGCTheme.box(Color("102a44"), Color(1, 1, 1, 0.15), 18, 1, 18, 24))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.set_meta("box", box)
	return root


func _layout() -> void:
	if _boats == null:
		return
	var center_width := size.x - LEFT_WIDTH - RIGHT_WIDTH - 48
	_boats.columns = 2 if center_width >= 600 else 1


# --- Estado -> interfaz ----------------------------------------------------------

func _refresh() -> void:
	_refresh_players()
	_refresh_table()
	_refresh_boats()
	_refresh_actions()
	_fresh_net.clear()
	_broken_flash.clear()
	_schedule_ai()


func _status_text(pid: int) -> String:
	match game.status[pid]:
		Status.IN_PORT:
			return "en puerto"
		Status.BROKEN:
			return "red rota"
	return "en el mar"


func _status_color(pid: int) -> Color:
	match game.status[pid]:
		Status.IN_PORT:
			return Color("8fd694")
		Status.BROKEN:
			return ERROR_COLOR
	return Color("9fd0e8")


func _refresh_players() -> void:
	_clear(_players_box)
	var order := range(game.players.size())
	order.sort_custom(func(a: int, b: int) -> bool: return game.scores[a] > game.scores[b])
	for pid in order:
		var p := game.players[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var marker := _tag("▶" if pid in game.players_to_act() and not game.finished else " ", 13, p.color.lightened(0.3))
		marker.custom_minimum_size.x = 14
		row.add_child(marker)
		var name_box := VBoxContainer.new()
		name_box.add_theme_constant_override("separation", 0)
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := _tag(p.display_name + (" (IA)" if p.is_ai else ""), 15, p.color.lightened(0.3))
		name.clip_text = true
		name_box.add_child(name)
		var detail := _status_text(pid)
		if game.status[pid] != Status.BROKEN and not game.finished:
			detail += " · red %d" % int(game.net_score(pid)["total"])
		name_box.add_child(_tag(detail, 12, _status_color(pid)))
		row.add_child(name_box)
		row.add_child(_tag(str(game.scores[pid]), 20, BGCTheme.TEXT))
		_players_box.add_child(row)


func _refresh_table() -> void:
	_deck_label.text = _plural(game.deck.size(), "carta", "cartas")
	_deck_card.visible = game.cards_left() > 0
	_risk_label.text = "Tormenta: %d %%" % roundi(game.storm_chance() * 100.0)
	var actor := _local_actor()
	_deck_card.clickable = actor >= 0 and game.pending_gulls.is_empty() and game.cards_left() > 0
	# Mercado: las cartas nuevas se voltean al aparecer.
	_clear(_market_box)
	var previous := _last_market.duplicate()
	for slot in game.market.size():
		var c: int = game.market[slot]
		var view := Card.new(c, BIG_CARD)
		view.tooltip_text = "%s: cógela y vuelve a puerto (%s)" % [D.card_name(c), _market_effect_text(game.turns.current, c)]
		view.clickable = actor >= 0 and game.pending_gulls.is_empty()
		view.pressed.connect(func() -> void: _act(G.TAKE_MARKET, {"slot": slot}))
		_market_box.add_child(view)
		var i := previous.find(c)
		if i >= 0:
			previous.remove_at(i)
		else:
			view.flip_in(0.1 * slot)
	_last_market = game.market.duplicate()
	_clear(_discard_slot)
	if game.discard.is_empty():
		var empty := Panel.new()
		empty.custom_minimum_size = BIG_CARD
		empty.add_theme_stylebox_override("panel", BGCTheme.box(Color(0, 0, 0, 0.15), Color(1, 1, 1, 0.15), 8, 1))
		_discard_slot.add_child(empty)
	else:
		_discard_slot.add_child(Card.new(game.discard[-1], BIG_CARD))
	var storms := game.discard.count(D.STORM)
	_discard_label.text = "%s · %s" % [_plural(game.discard.size(), "carta", "cartas"), _plural(storms, "tormenta", "tormentas")]


func _refresh_boats() -> void:
	_clear(_boats)
	for pid in game.players.size():
		_boats.add_child(_boat(pid))


## Barca de un jugador: nombre, situación, puntos de la red y sus cartas.
func _boat(pid: int) -> Control:
	var p := game.players[pid]
	var acting := pid in game.players_to_act() and not game.finished
	var fill := Color(0.04, 0.12, 0.2, 0.9) if game.status[pid] == Status.AT_SEA else Color(0.03, 0.08, 0.13, 0.8)
	var border := p.color if acting else Color(1, 1, 1, 0.1)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", BGCTheme.box(fill, border, 12, 3 if acting else 1, 4, 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var name := _tag(p.display_name, 16, p.color.lightened(0.3))
	name.add_theme_font_override("font", BGCTheme.bold_font(0.6))
	head.add_child(name)
	head.add_child(_tag(_status_text(pid), 13, _status_color(pid)))
	if game.shields[pid]:
		head.add_child(_tag("· red reforzada", 13, Color("d8c39a")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if game.status[pid] != Status.BROKEN:
		head.add_child(_tag("%d pts" % int(game.net_score(pid)["total"]), 16, BGCTheme.ACCENT))
	elif game.salvaged[pid] > 0:
		head.add_child(_tag("salva %d" % game.salvaged[pid], 16, BGCTheme.ACCENT))
	box.add_child(head)
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 4)
	cards.add_theme_constant_override("v_separation", 4)
	cards.custom_minimum_size = Vector2(0, NET_CARD.y)
	var net := game.net(pid)
	var fresh: int = _fresh_net.get(pid, 0)
	for i in net.size():
		var view := Card.new(net[i], NET_CARD)
		view.tooltip_text = D.card_name(net[i])
		cards.add_child(view)
		if i >= net.size() - fresh:
			view.flip_in(0.05 * (i - (net.size() - fresh)))
	if net.is_empty():
		var empty := _tag("Red rota" if game.status[pid] == Status.BROKEN else "Red vacía", 13, BGCTheme.TEXT_DIM)
		cards.add_child(empty)
	box.add_child(cards)
	if _broken_flash.has(pid):
		panel.modulate = Color(1.6, 0.6, 0.6)
		var tween := panel.create_tween()
		tween.tween_property(panel, "modulate", Color.WHITE, 0.9)
	return panel


func _refresh_actions() -> void:
	_clear(_actions_box)
	_clear(_info_box)
	_round_label.text = "Ronda %d" % game.round_number
	if game.finished:
		_prompt_label.text = "La partida ha terminado."
		_actions_box.add_child(_button("Ver el resultado", func() -> void: _victory.visible = true, 15))
		return
	var actor: int = game.players_to_act()[0]
	var local := _local_actor()
	if not game.pending_gulls.is_empty():
		_prompt_label.text = "La gaviota de %s: ¿a quién le quita el último pez?" % _player_name_plain(actor)
		if local >= 0:
			for t in game.gull_targets(local):
				var fish: int = game.net(t)[-1]
				var gain: int = D.score(game.net(local) + [fish])["total"] - int(game.net_score(local)["total"])
				_actions_box.add_child(_button("%s: %s (+%d para ti)" % [game.players[t].display_name, D.card_name(fish), gain],
					_act.bind(G.CHOOSE_TARGET, {"target": t}), 15))
	elif local >= 0:
		_prompt_label.text = "Turno de %s." % game.players[local].display_name
		var draw := _button("Robar a ciegas  ·  riesgo de tormenta %d %%  [R]" % roundi(game.storm_chance() * 100.0), _act.bind(G.DRAW_BLIND), 15, "PrimaryButton")
		draw.disabled = game.cards_left() == 0 or _awaiting_host
		_actions_box.add_child(draw)
		for slot in game.market.size():
			var c: int = game.market[slot]
			var take := _button("Coger %s y volver  ·  %s  [%d]" % [D.card_name(c), _market_effect_text(local, c), slot + 1], _act.bind(G.TAKE_MARKET, {"slot": slot}), 14)
			take.disabled = _awaiting_host
			_actions_box.add_child(take)
		var port := _button("Volver a puerto  ·  %d puntos  [P]" % int(game.net_score(local)["total"]), _act.bind(G.GO_TO_PORT), 15)
		port.disabled = _awaiting_host
		_actions_box.add_child(port)
	else:
		var who := game.players[actor]
		_prompt_label.text = ("Juega %s (IA)..." if who.is_ai or _ais.has(actor) else "Esperando a %s...") % who.display_name
	_fill_info(local if local >= 0 else actor)


## Lo que daría coger `card` del mercado y volver a puerto.
func _market_effect_text(pid: int, card: int) -> String:
	var now := int(game.net_score(pid)["total"])
	if D.is_fish(card):
		var after: int = D.score(game.net(pid) + [card])["total"]
		return "%d puntos (+%d)" % [after, after - now]
	match card:
		D.GULL: return "%d puntos y una gaviota" % now
		D.HIGH_TIDE: return "%d puntos; los demás roban" % now
	return "%d puntos" % now


## Desglose de la red del jugador en turno y cómo está el mazo.
func _fill_info(pid: int) -> void:
	var s := game.net_score(pid)
	_info_box.add_child(_label("Red de %s" % game.players[pid].display_name, 14, BGCTheme.TEXT_DIM))
	if game.net(pid).is_empty():
		_info_box.add_child(_label("Todavía vacía.", 14))
	else:
		var lines: Array[String] = ["Suma de los peces: %d" % s["base"]]
		if s["best_species"] >= 0:
			lines.append("%s (la que más tienes): +%d" % [D.SPECIES_NAMES[s["best_species"]], s["species_bonus"]])
		for run in s["runs"]:
			lines.append("Escalera %d-%d: +%d" % [run[0], run[1], D.RUN_POINTS * (run[1] - run[0] + 1 - D.RUN_MIN + 1)])
		lines.append("Total: %d" % s["total"])
		_info_box.add_child(_label("\n".join(lines), 14))
	if game.shields[pid]:
		_info_box.add_child(_label("Red reforzada: si se rompe, salvas la mitad.", 13, Color("d8c39a")))
	_info_box.add_child(_label("Quedan %d tormentas en %d cartas del mazo." % [game.storms_in_deck(), game.deck.size()], 13, BGCTheme.TEXT_DIM))


# --- IA ---------------------------------------------------------------------------

func _schedule_ai() -> void:
	if game.finished or _ai_pending or not is_inside_tree() or _ai_actor() == -1:
		return
	_ai_pending = true
	var delay := AI_DELAY_FAST if _ai_fast_toggle.button_pressed else AI_DELAY
	get_tree().create_timer(delay).timeout.connect(_run_ai.bind(_ai_generation))


func _run_ai(generation: int) -> void:
	if generation != _ai_generation:
		return
	_ai_pending = false
	if game.finished:
		return
	if _summary.visible:
		return  # sigue al cerrar el resumen de la ronda
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

## Jugada de la persona de este equipo que tiene el turno.
func _act(type: StringName, data: Dictionary = {}) -> void:
	var pid := _local_actor()
	if pid < 0 or _awaiting_host:
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


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _summary.visible and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		_close_summary()
		return
	if _local_actor() < 0 or not game.pending_gulls.is_empty():
		return
	match event.keycode:
		KEY_R: _act(G.DRAW_BLIND)
		KEY_P: _act(G.GO_TO_PORT)
		KEY_1, KEY_2, KEY_3:
			var slot: int = event.keycode - KEY_1
			if slot < game.market.size():
				_act(G.TAKE_MARKET, {"slot": slot})


func _on_net_request(data: Dictionary, peer_id: int) -> void:
	if not _network:
		return
	var error := game.submit(GameAction.from_dict(data))
	if error != "":
		Net.reject(peer_id, error)


## Un jugador se ha desconectado: pasa a jugar una IA (en el anfitrión).
func _on_seat_replaced(seat: int) -> void:
	if not _network or game == null:
		return
	game.players[seat].ai_level = PlayerInfo.AILevel.NORMAL
	if Net.is_host:
		_ais[seat] = BajamarAI.new(seat, PlayerInfo.AILevel.NORMAL, game.rng.seed_value)
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
	var pid: int = data.get("player", -1)
	match kind:
		&"draw":
			var card: int = data["card"]
			match data["from"]:
				"deck": _add_log("%s roba: %s." % [_player_name(pid), _card_bbcode(card)])
				"market": _add_log("%s coge del mercado %s." % [_player_name(pid), _card_bbcode(card)])
				"tide": _add_log("   Con la marea, %s roba: %s." % [_player_name(pid), _card_bbcode(card)])
			if D.is_fish(card):
				_fresh_net[pid] = _fresh_net.get(pid, 0) + 1
				Sfx.play(&"card")
		&"net_broken":
			var salvaged: int = data["salvaged"]
			var extra := " La red reforzada salva %d puntos." % salvaged if salvaged > 0 else ""
			_add_log("[color=#ff8a80][b]¡Tormenta! Se rompe la red de %s.[/b][/color]%s" % [game.players[pid].display_name, extra])
			_broken_flash[pid] = true
			Sfx.play(&"robber")
			_show_banner("¡Tormenta! Red rota: %s" % game.players[pid].display_name, ERROR_COLOR)
		&"storm_passed":
			_add_log("[color=#9fb8c8]Una tormenta pasa de largo por el mercado.[/color]")
		&"shield":
			_add_log("%s tiene ahora una red reforzada." % _player_name(pid))
			Sfx.play(&"approve")
		&"shield_wasted":
			_add_log("%s ya tenía red reforzada: la nueva se descarta." % _player_name(pid))
		&"gull":
			var target: int = data["target"]
			_add_log("La gaviota de %s le quita %s a %s." % [_player_name(pid), _card_bbcode(data["card"]), _player_name(target)])
			_fresh_net[pid] = _fresh_net.get(pid, 0) + 1
			Sfx.play(&"trade")
			_show_banner("¡Gaviota! %s → %s" % [game.players[target].display_name, game.players[pid].display_name], Color("e9eef2"))
		&"gull_wasted":
			_add_log("La gaviota de %s no encuentra nada que robar." % _player_name(pid))
		&"tide":
			_add_log("[b]¡Marea alta![/b] Todos los que siguen en el mar roban una carta.")
			Sfx.play(&"resource")
			_show_banner("¡Marea alta!", Color("9fd0e8"))
		&"tide_wasted":
			_add_log("   Otra Marea alta: esta no tiene efecto.")
		&"port":
			_add_log("%s vuelve a puerto con %d puntos." % [_player_name(pid), int(data["score"]["total"])])
			Sfx.play(&"build")
		&"reshuffle":
			_add_log("Se acaba el mazo: se barajan los descartes (%d cartas)." % data["cards"])
		&"round_end":
			_round_results = data["results"]
			_round_shown = data["round"]
			_after_round_end.call_deferred()
		&"round_start":
			pass


## Al terminar una ronda: resumen, o la pantalla final si ya hay ganador.
func _after_round_end() -> void:
	if game.finished:
		return  # _on_game_finished se encarga
	_show_summary()


func _show_summary() -> void:
	var box: VBoxContainer = _summary.get_meta("box")
	_clear(box)
	var title := _label("Fin de la ronda %d" % _round_shown, 28, BGCTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	box.add_child(_results_grid(_round_results))
	var button := _button("Siguiente ronda  [Intro]", _close_summary, 16, "PrimaryButton")
	box.add_child(button)
	_summary.visible = true
	Sfx.play(&"turn")
	if not _has_local_humans():
		var wait := 1.2 if _ai_fast_toggle.button_pressed else SUMMARY_AUTO_CLOSE
		var generation := _ai_generation
		get_tree().create_timer(wait).timeout.connect(func() -> void:
			if generation == _ai_generation and _summary.visible:
				_close_summary())
	_refresh()


func _close_summary() -> void:
	if not _summary.visible:
		return
	_summary.visible = false
	_show_banner("Ronda %d" % game.round_number, BGCTheme.ACCENT)
	_refresh()


## Tabla de resultados de una ronda: jugador, lo que ganó y su total.
func _results_grid(results: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["Jugador", "Esta ronda", "Total"]:
		grid.add_child(_tag(h, 13, BGCTheme.TEXT_DIM))
	var order := range(game.players.size())
	order.sort_custom(func(a: int, b: int) -> bool: return game.scores[a] > game.scores[b])
	for pid in order:
		var r: Dictionary = results[pid] if pid < results.size() else {"total": 0}
		grid.add_child(_tag(game.players[pid].display_name, 16, game.players[pid].color.lightened(0.3)))
		var text := "+%d" % r["total"]
		var color := BGCTheme.TEXT
		if r.get("broken", false):
			text = "red rota" + (" (salva %d)" % r["total"] if r["total"] > 0 else "")
			color = ERROR_COLOR
		elif r.has("base") and r["base"] > 0:
			var parts: Array[String] = ["%d" % r["base"]]
			if r["species_bonus"] > 0:
				parts.append("especie %d" % r["species_bonus"])
			if r["run_bonus"] > 0:
				parts.append("escalera %d" % r["run_bonus"])
			text += "   (" + " + ".join(parts) + ")"
		grid.add_child(_tag(text, 15, color))
		grid.add_child(_tag(str(game.scores[pid]), 18, BGCTheme.ACCENT))
	return grid


func _on_game_finished(_winner_ids: Array[int]) -> void:
	_show_victory.call_deferred()


func _show_victory() -> void:
	_summary.visible = false
	Sfx.play(&"win")
	var winners := game.winner_ids
	var names: Array[String] = []
	for w in winners:
		names.append(game.players[w].display_name)
	var heading := "¡Gana %s!" % names[0] if winners.size() == 1 else "Empate: %s" % " y ".join(names)
	_add_log("[b]Fin de la partida tras %d rondas. %s[/b]" % [game.round_number, heading])
	var box: VBoxContainer = _victory.get_meta("box")
	_clear(box)
	var color: Color = game.players[winners[0]].color.lightened(0.3)
	var title := _label(heading, 32, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BGCTheme.bold_font(0.8))
	box.add_child(title)
	var sub := _label("%d rondas · última ronda:" % game.round_number, 15, BGCTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_results_grid(_round_results))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if not _network:
		var again := _button("Nueva partida", func() -> void: _start(BGCRng.random_seed()), 16, "PrimaryButton")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(again)
	var close := _button("Ver la mesa", func() -> void: _victory.visible = false, 16)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(close)
	var menu := _button("Menú", App.go_to_menu, 16, "GhostButton")
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)
	box.add_child(row)
	_victory.visible = true
	_refresh()


# --- Utilidades ---------------------------------------------------------------------

## Rótulo grande sobre la mesa. Si ya hay uno, espera su turno; uno nuevo
## sustituye a los que aún esperaban (así nunca se quedan atrasados).
func _show_banner(text: String, color: Color) -> void:
	_banner_queue = [[text, color]]
	if not _banner_busy:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_busy = false
		return
	_banner_busy = true
	var item: Array = _banner_queue.pop_front()
	_banner.text = item[0]
	_banner.add_theme_color_override("font_color", Color(item[1]).lightened(0.2))
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


func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _card_bbcode(card: int) -> String:
	if D.is_fish(card):
		var color: Color = D.SPECIES_COLORS[D.species_of(card)]
		return "[color=#%s]%s[/color]" % [color.lightened(0.3).to_html(false), D.card_name(card)]
	if D.is_storm(card):
		return "[color=#ff8a80][b]Tormenta[/b][/color]"
	return "[b]%s[/b]" % D.card_name(card)


func _player_name(pid: int) -> String:
	var p := game.players[pid]
	return "[color=#%s]%s[/color]" % [p.color.lightened(0.25).to_html(false), p.display_name]


func _player_name_plain(pid: int) -> String:
	return game.players[pid].display_name if pid >= 0 and pid < game.players.size() else "—"
