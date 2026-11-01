extends TestCase


func test_rng_is_deterministic() -> void:
	var a := BGCRng.new(1234)
	var b := BGCRng.new(1234)
	for i in 50:
		assert_eq(a.roll(), b.roll())


func test_rng_roll_in_range() -> void:
	var rng := BGCRng.new(7)
	for i in 500:
		var r := rng.roll(6)
		assert_true(r >= 1 and r <= 6, "tirada %d" % r)


func test_rng_shuffle_keeps_elements() -> void:
	var rng := BGCRng.new(99)
	var arr := [1, 2, 3, 4, 5, 6, 7, 8]
	rng.shuffle(arr)
	var sorted := arr.duplicate()
	sorted.sort()
	assert_eq(sorted, [1, 2, 3, 4, 5, 6, 7, 8])


func test_rng_state_roundtrip() -> void:
	var rng := BGCRng.new(5)
	rng.roll()
	var state := rng.get_state()
	var expected := rng.roll_dice(5)
	rng.set_state(state)
	assert_eq(rng.roll_dice(5), expected)


func test_turn_manager_normal_order() -> void:
	var tm := TurnManager.new(3)
	assert_eq(tm.current, 0)
	assert_eq(tm.next(), 1)
	assert_eq(tm.next(), 2)
	assert_eq(tm.round_number, 1)
	assert_eq(tm.next(), 0)
	assert_eq(tm.round_number, 2)


func test_snake_order() -> void:
	assert_eq(TurnManager.snake_order(3), [0, 1, 2, 2, 1, 0] as Array[int])
	assert_eq(TurnManager.snake_order(4, 2), [2, 3, 0, 1, 1, 0, 3, 2] as Array[int])


func test_turn_manager_sequence_then_normal() -> void:
	var tm := TurnManager.new(3)
	tm.begin_sequence(TurnManager.snake_order(3))
	var seen: Array[int] = [tm.current]
	assert_true(tm.in_sequence())
	for i in 5:
		seen.append(tm.next())
	assert_eq(seen, [0, 1, 2, 2, 1, 0] as Array[int])
	assert_eq(tm.next(), 0, "tras la serpiente empieza el jugador inicial")
	assert_false(tm.in_sequence())
	assert_eq(tm.round_number, 1)
	assert_eq(tm.next(), 1)


func test_action_roundtrip() -> void:
	var action := GameAction.new(&"build_road", 2, {"edge": 17})
	var copy := GameAction.from_dict(action.to_dict())
	assert_eq(copy.type, &"build_road")
	assert_eq(copy.player_id, 2)
	assert_eq(copy.data, {"edge": 17})


func test_player_roundtrip() -> void:
	var p := PlayerInfo.new(1, "Ana", Color("3f72d6"))
	var copy := PlayerInfo.from_dict(p.to_dict())
	assert_eq(copy.display_name, "Ana")
	assert_eq(copy.color.to_html(false), p.color.to_html(false))


func test_game_base_rejects_unknown_actions() -> void:
	var game := GameBase.new()
	var players: Array[PlayerInfo] = [PlayerInfo.new(0), PlayerInfo.new(1)]
	game.setup(players, 1)
	assert_ne(game.submit(GameAction.new(&"nada", 0)), "")
	assert_true(game.history.is_empty())


func test_registry_has_archipelago() -> void:
	var game := GameRegistry.find("archipelago")
	assert_false(game.is_empty())
	assert_true(ResourceLoader.exists(game["scene"]), "la escena del juego existe")
