extends TestCase
## Puerto Franco: el juego está registrado en el menú y la vista
## del barrio convierte bien entre casillas y píxeles.

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")


func test_registered_in_the_menu() -> void:
	var entry := GameRegistry.find("puerto_franco")
	assert_false(entry.is_empty())
	assert_eq(entry["min_players"], 2)
	assert_eq(entry["max_players"], 6)
	assert_true(ResourceLoader.exists(entry["scene"]))
	assert_true(FileAccess.file_exists(entry["rules"]))


func test_district_view_picks_the_right_cell() -> void:
	var view := PuertoDistrictView.new()
	view.size = Vector2(400, 360)
	var district: Array[int] = []
	district.resize(D.CELLS.size())
	district.fill(D.EMPTY)
	district[D.LONJA_CELL] = D.LONJA
	view.set_district(district)
	for cell in D.CELLS.size():
		view._layout()
		assert_eq(view._cell_at(view.cell_center(cell)), cell, "casilla %d" % cell)
	assert_eq(view._cell_at(Vector2(2, 2)), -1, "fuera del barrio")
	view.free()


func test_cards_have_names_and_effects() -> void:
	for card in D.BUILDINGS.size():
		assert_ne(D.card_name(card), "")
		if D.is_wonder(card):
			assert_ne(PuertoArt.card_text(card), "", "la maravilla %s explica su efecto" % D.card_name(card))
