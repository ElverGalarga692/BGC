extends TestCase

const D := preload("res://games/pests/logic/pests_defs.gd")


func test_tiles() -> void:
	assert_eq(D.STANDARD_TILES.size(), 18)
	for t in D.STANDARD_TILES:
		var n := D.door_count(t["doors"])
		assert_true(n >= 2 and n <= 4, "%s tiene %d puertas" % [t["name"], n])
	assert_eq(D.door_count(D.ENTRY_DOORS), 3)
	assert_eq(D.ENTRY_DOORS & D.DOOR_DOWN, 0, "la entrada no tiene puerta al jardín")
	# Con 6 jugadores: 18 estándar + 6 nidos + entrada = 25 losetas.
	assert_eq(D.STANDARD_TILES.size() - D.TILES_REMOVED[6] + 6 + 1, 25)


func test_rotate_doors() -> void:
	assert_eq(D.rotate_doors(D.DOOR_UP, 1), D.DOOR_RIGHT)
	assert_eq(D.rotate_doors(D.DOOR_UP | D.DOOR_RIGHT, 1), D.DOOR_RIGHT | D.DOOR_DOWN)
	assert_eq(D.rotate_doors(D.DOOR_LEFT, 1), D.DOOR_UP)
	assert_eq(D.rotate_doors(D.DOOR_UP | D.DOOR_DOWN, 2), D.DOOR_UP | D.DOOR_DOWN)
	assert_eq(D.rotate_doors(D.DOOR_RIGHT, -1), D.DOOR_UP)
	for t in D.STANDARD_TILES:
		assert_eq(D.rotate_doors(t["doors"], 4), t["doors"])


func test_dlur_order() -> void:
	assert_eq(D.DLUR, [D.Dir.DOWN, D.Dir.LEFT, D.Dir.UP, D.Dir.RIGHT] as Array[int])
	for dir in 4:
		assert_eq(D.DIR_VECTORS[dir] + D.DIR_VECTORS[D.opposite(dir)], Vector2i.ZERO)


func test_queen_die() -> void:
	assert_eq(D.QUEEN_DIE.size(), 6)
	var species := {}
	var actions := {}
	for face in D.QUEEN_DIE:
		species[face["species"]] = true
		actions[face["action"]] = true
	assert_eq(species.size(), 6, "cada cara tiene un color distinto")
	assert_eq(actions.size(), 6, "cada cara tiene una acción distinta")
	assert_eq(D.queen_action_dir(D.QueenAction.UP), D.Dir.UP)
	assert_eq(D.queen_action_dir(D.QueenAction.SUMMON), -1)


func test_abilities() -> void:
	assert_eq(D.ability(D.Species.GREEN, "traps"), 2)
	assert_eq(D.ability(D.Species.BLUE, "traps"), 1)
	assert_eq(D.ability(D.Species.BLUE, "trap_capacity"), 9)
	assert_eq(D.ability(D.Species.YELLOW, "queen_moves"), 2)
	assert_eq(D.ability(D.Species.RED, "populate_distance"), 2)
	assert_eq(D.ability(D.Species.PURPLE, "through_walls"), true)
	assert_eq(D.ability(D.Species.ORANGE, "nest_spawn"), 2)
	assert_eq(D.act_cost(D.Act.SEAL_NEST, D.Species.ORANGE), 1)
	assert_eq(D.act_cost(D.Act.SEAL_NEST, D.Species.RED), 2)
	assert_eq(D.act_cost(D.Act.DESTROY_TRAP, D.Species.RED, D.Species.PURPLE), 2)
	assert_eq(D.act_cost(D.Act.DESTROY_TRAP, D.Species.PURPLE, D.Species.RED), 1)
	for s in D.SPECIES_COUNT:
		assert_true(D.SPECIES_ABILITY_TEXT.has(s))
		assert_true(D.SPECIES_NAMES.has(s))


func test_cards() -> void:
	assert_eq(D.CARDS.size(), 24)
	var ids := {}
	var defensive := 0
	for c in D.CARDS:
		ids[c["id"]] = true
		if c["kind"] == D.CardKind.DEFENSIVE:
			defensive += 1
	assert_eq(ids.size(), 24, "ids únicos")
	assert_eq(defensive, 12)
	assert_eq(D.card("hibernate")["timing"], D.CardTiming.BEFORE_ROLL)
	assert_eq(D.card("mind_control")["timing"], D.CardTiming.BEFORE_ROLL)
	assert_eq(D.card_index("nope"), -1)


func test_setup_tables() -> void:
	for n in range(D.MIN_PLAYERS, D.MAX_PLAYERS + 1):
		assert_true(D.TILES_REMOVED.has(n))
		assert_eq(D.pests_in_play(n), 24 - D.PESTS_REMOVED[n])
	assert_eq(D.pests_in_play(2), 20)
