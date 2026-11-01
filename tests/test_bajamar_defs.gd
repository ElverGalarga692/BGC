extends TestCase

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")


func test_card_encoding() -> void:
	for s in D.SPECIES_COUNT:
		for v in range(D.MIN_VALUE, D.MAX_VALUE + 1):
			var c := D.fish(s, v)
			assert_true(D.is_fish(c))
			assert_false(D.is_storm(c))
			assert_eq(D.species_of(c), s)
			assert_eq(D.value_of(c), v)
	assert_true(D.is_storm(D.STORM))
	assert_false(D.is_fish(D.STORM))
	assert_false(D.is_fish(0))
	assert_false(D.is_fish(7))  # especie 0, valor 7: no existe
	assert_eq(D.card_name(D.fish(D.Species.OCTOPUS, 4)), "Pulpo 4")
	for c in [D.GULL, D.SHIELD, D.HIGH_TIDE]:
		assert_true(D.is_special(c))
		assert_false(D.is_fish(c))
	assert_eq(D.card_name(D.GULL), "Gaviota")


func test_specials_do_not_score() -> void:
	assert_eq(D.score([D.GULL, D.SHIELD, D.fish(0, 2)])["total"], 4)


func test_deck_composition() -> void:
	var deck := D.deck()
	assert_eq(deck.size(), D.SPECIES_COUNT * 6 * D.FISH_COPIES + D.STORM_COUNT + 8)
	assert_eq(deck.count(D.GULL), 3)
	assert_eq(deck.count(D.SHIELD), 3)
	assert_eq(deck.count(D.HIGH_TIDE), 2)
	assert_eq(deck.count(D.STORM), D.STORM_COUNT)
	assert_eq(deck.count(D.fish(D.Species.TUNA, 6)), D.FISH_COPIES)


func test_score_empty_net() -> void:
	var s := D.score([])
	assert_eq(s["total"], 0)
	assert_eq(s["best_species"], -1)


func test_score_bonus_for_most_common_species() -> void:
	# Dos sardinas (2 + 5) y un atún 6: la sardina da +2 por carta.
	var net := [D.fish(D.Species.SARDINE, 2), D.fish(D.Species.SARDINE, 5), D.fish(D.Species.TUNA, 6)]
	var s := D.score(net)
	assert_eq(s["base"], 13)
	assert_eq(s["best_species"], D.Species.SARDINE)
	assert_eq(s["species_bonus"], 2 * D.SPECIES_BONUS_PER_CARD)
	assert_eq(s["run_bonus"], 0, "5 y 6 son solo dos seguidos")
	assert_eq(s["total"], 13 + 2 * D.SPECIES_BONUS_PER_CARD)


func test_score_species_tie_breaks_by_sum_then_order() -> void:
	var net := [D.fish(D.Species.SARDINE, 1), D.fish(D.Species.HAKE, 4)]
	assert_eq(D.score(net)["best_species"], D.Species.HAKE, "empate en cartas: gana la que más suma")
	net = [D.fish(D.Species.TUNA, 3), D.fish(D.Species.MACKEREL, 3)]
	assert_eq(D.score(net)["best_species"], D.Species.MACKEREL, "empate total: la primera en el orden")


func test_score_runs() -> void:
	# 1-2-3 de especies distintas (+5); un 3 repetido no cuenta dos veces.
	var net := [D.fish(0, 1), D.fish(1, 2), D.fish(2, 3), D.fish(3, 3)]
	var s := D.score(net)
	assert_eq(s["runs"], [[1, 3]])
	assert_eq(s["run_bonus"], 5)
	# 2-3-4-5 (+10).
	net = [D.fish(0, 5), D.fish(1, 3), D.fish(2, 4), D.fish(3, 2)]
	assert_eq(D.score(net)["run_bonus"], 10)
	# Escalera completa 1..6 (+20).
	net = []
	for v in range(1, 7):
		net.append(D.fish(v % D.SPECIES_COUNT, v))
	s = D.score(net)
	assert_eq(s["runs"], [[1, 6]])
	assert_eq(s["run_bonus"], 20)


func test_score_full_example() -> void:
	# Pulpo 1, 2, 4 + Atún 3 → suma 10, tres pulpos +6, escalera 1-4 +10.
	var net := [D.fish(2, 1), D.fish(2, 2), D.fish(2, 4), D.fish(4, 3)]
	var s := D.score(net)
	assert_eq(s["base"], 10)
	assert_eq(s["species_bonus"], 6)
	assert_eq(s["run_bonus"], 10)
	assert_eq(s["total"], 26)
