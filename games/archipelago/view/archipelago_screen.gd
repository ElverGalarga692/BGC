extends Control
## Pantalla de una partida de Archipiélago: el tablero y el HUD.
##
## Fase 1: muestra el tablero generado, permite generar otro y muestra qué
## elemento hay bajo el ratón (base para la colocación de la fase 2).

const BACKGROUND := Color("163246")
const HUD_WIDTH := 300.0

var game: ArchipelagoGame
var _board_view: ArchBoardView
var _info_label: Label
var _seed_label: Label
var _players_box: VBoxContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_board_view = ArchBoardView.new()
	add_child(_board_view)
	_board_view.hovered.connect(_on_hovered)

	_build_hud()
	resized.connect(_layout)

	_start(App.session_seed())


func _start(seed: int) -> void:
	game = ArchipelagoGame.new()
	game.setup(App.session_players(), seed)
	_board_view.board = game.board
	_seed_label.text = "Semilla: %d" % seed
	_info_label.text = "Pasa el ratón por el tablero."
	_refresh_players()
	_layout()


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(HUD_WIDTH, 0)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Archipiélago"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	_players_box = VBoxContainer.new()
	box.add_child(_players_box)

	box.add_child(HSeparator.new())
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(HUD_WIDTH - 24, 72)
	box.add_child(_info_label)
	box.add_child(HSeparator.new())

	_seed_label = Label.new()
	_seed_label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_seed_label)

	var new_board := Button.new()
	new_board.text = "Nuevo tablero"
	new_board.pressed.connect(func() -> void: _start(BGCRng.random_seed()))
	box.add_child(new_board)

	var menu := Button.new()
	menu.text = "Volver al menú"
	menu.pressed.connect(App.go_to_menu)
	box.add_child(menu)


func _refresh_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	for player in game.players:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = player.color
		swatch.custom_minimum_size = Vector2(18, 18)
		row.add_child(swatch)
		var name_label := Label.new()
		name_label.text = player.display_name
		if player.id == game.turns.current:
			name_label.text += "  ◀ turno"
		row.add_child(name_label)
		_players_box.add_child(row)


## Centra el tablero en el espacio a la derecha del HUD y lo escala.
func _layout() -> void:
	if _board_view == null:
		return
	var left := HUD_WIDTH + 32.0
	var area := Rect2(left, 0, maxf(100.0, size.x - left), size.y)
	var extent := ArchBoardView.extent()
	_board_view.hex_size = minf(area.size.x / extent.x, area.size.y / extent.y) * 0.96
	_board_view.position = area.get_center()


func _on_hovered(kind: ArchBoardView.Pick, id: int) -> void:
	var board := game.board
	match kind:
		ArchBoardView.Pick.TILE:
			_info_label.text = "Casilla %d\n%s" % [id, _tile_text(id)]
		ArchBoardView.Pick.VERTEX:
			var parts: Array[String] = []
			for t in board.grid.vertex_tiles[id]:
				parts.append(_tile_text(t))
			var text := "Vértice %d\nToca: %s" % [id, ", ".join(parts)]
			var port = board.vertex_port(id)
			if port != null:
				text += "\nPuerto %s" % ArchDefs.port_label(port["type"])
			_info_label.text = text
		ArchBoardView.Pick.EDGE:
			var text := "Arista %d" % id
			text += " (costa)" if board.grid.is_coastal_edge(id) else ""
			var port = board.edge_port(id)
			if port != null:
				text += "\nPuerto %s" % ArchDefs.port_label(port["type"])
			_info_label.text = text
		_:
			_info_label.text = ""


func _tile_text(t: int) -> String:
	var board := game.board
	var text: String = ArchDefs.TERRAIN_NAMES[board.tile_terrain[t]]
	if board.tile_number[t] > 0:
		text += " (%d)" % board.tile_number[t]
	return text
