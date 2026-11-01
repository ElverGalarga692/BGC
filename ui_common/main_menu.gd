extends Control
## Menú principal: elegir juego y configurar los jugadores locales
## (hot-seat: todos juegan en el mismo equipo por turnos).

const BACKGROUND := Color("1f3b57")
const MAX_NAME_LENGTH := 16

var _games_box: VBoxContainer
var _setup_box: VBoxContainer
var _settings_box: VBoxContainer
var _selected_game: Dictionary = {}
var _count_spin: SpinBox
var _players_list: VBoxContainer
var _name_edits: Array[LineEdit] = []
var _color_pickers: Array[ColorPickerButton] = []
var _ai_options: Array[OptionButton] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "BGC"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Board Game Collection"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.modulate = Color(1, 1, 1, 0.75)
	column.add_child(subtitle)

	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", 10)
	column.add_child(_games_box)
	_build_game_list()

	_setup_box = VBoxContainer.new()
	_setup_box.add_theme_constant_override("separation", 10)
	_setup_box.visible = false
	column.add_child(_setup_box)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 12)
	_settings_box.visible = false
	column.add_child(_settings_box)
	_build_settings()

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var settings := Button.new()
	settings.text = "Ajustes"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func() -> void:
		_games_box.visible = false
		_settings_box.visible = true)
	bottom.add_child(settings)
	var quit := Button.new()
	quit.text = "Salir"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void: get_tree().quit())
	bottom.add_child(quit)
	_games_box.add_child(bottom)


func _build_game_list() -> void:
	var header := Label.new()
	header.text = "Elige un juego"
	header.add_theme_font_size_override("font_size", 20)
	_games_box.add_child(header)
	for game in GameRegistry.all_games():
		if App.has_save(game["id"]):
			var resume := Button.new()
			resume.text = "Continuar partida de %s" % game["name"]
			resume.custom_minimum_size = Vector2(0, 44)
			resume.pressed.connect(App.continue_game.bind(game["id"]))
			_games_box.add_child(resume)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var button := Button.new()
		button.text = "%s\n%s" % [game["name"], game["description"]]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_game_chosen.bind(game))
		row.add_child(button)
		if game.has("rules"):
			var rules := Button.new()
			rules.text = "Reglas"
			rules.custom_minimum_size = Vector2(90, 0)
			rules.pressed.connect(func() -> void: RulesPanel.open(self, game["rules"]))
			row.add_child(rules)
		_games_box.add_child(row)


## Ajustes que se guardan entre sesiones.
func _build_settings() -> void:
	var header := Label.new()
	header.text = "Ajustes"
	header.add_theme_font_size_override("font_size", 20)
	_settings_box.add_child(header)

	var volume_row := HBoxContainer.new()
	var volume_label := Label.new()
	volume_label.text = "Volumen"
	volume_label.custom_minimum_size = Vector2(160, 0)
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
			App.set_setting(key, on)
			if key == "fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
		_settings_box.add_child(check)

	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func() -> void:
		_settings_box.visible = false
		_games_box.visible = true)
	_settings_box.add_child(back)


func _on_game_chosen(game: Dictionary) -> void:
	_selected_game = game
	_games_box.visible = false
	_setup_box.visible = true
	for child in _setup_box.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "%s · Jugadores locales" % game["name"]
	header.add_theme_font_size_override("font_size", 20)
	_setup_box.add_child(header)

	var count_row := HBoxContainer.new()
	var count_label := Label.new()
	count_label.text = "Número de jugadores"
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_label)
	_count_spin = SpinBox.new()
	_count_spin.min_value = game["min_players"]
	_count_spin.max_value = game["max_players"]
	_count_spin.value = clampi(3, game["min_players"], game["max_players"])
	_count_spin.value_changed.connect(func(_v: float) -> void: _rebuild_player_rows())
	count_row.add_child(_count_spin)
	_setup_box.add_child(count_row)

	_players_list = VBoxContainer.new()
	_setup_box.add_child(_players_list)
	_name_edits.clear()
	_color_pickers.clear()
	_ai_options.clear()
	_rebuild_player_rows()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "Volver"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_back)
	buttons.add_child(back)
	var play := Button.new()
	play.text = "Jugar"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(_on_play)
	buttons.add_child(play)
	_setup_box.add_child(buttons)


## Ajusta las filas de jugadores al número elegido, conservando lo escrito.
func _rebuild_player_rows() -> void:
	var count := int(_count_spin.value)
	while _name_edits.size() < count:
		var i := _name_edits.size()
		var row := HBoxContainer.new()
		var picker := ColorPickerButton.new()
		picker.color = PlayerInfo.default_color(i)
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(40, 0)
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
		ai.custom_minimum_size = Vector2(130, 0)
		row.add_child(ai)
		_players_list.add_child(row)
		_name_edits.append(edit)
		_color_pickers.append(picker)
		_ai_options.append(ai)
	while _name_edits.size() > count:
		_name_edits.pop_back()
		_color_pickers.pop_back()
		_ai_options.pop_back()
		var row := _players_list.get_child(_players_list.get_child_count() - 1)
		_players_list.remove_child(row)
		row.queue_free()


func _on_back() -> void:
	_setup_box.visible = false
	_games_box.visible = true


func _on_play() -> void:
	var players: Array[PlayerInfo] = []
	for i in _name_edits.size():
		var level := _ai_options[i].get_selected_id()
		var player_name := _name_edits[i].text.strip_edges()
		if player_name == "" and level != PlayerInfo.AILevel.HUMAN:
			player_name = "IA %d" % (i + 1)
		players.append(PlayerInfo.new(i, player_name, _color_pickers[i].color, level))
	App.start_game(_selected_game["id"], players)
