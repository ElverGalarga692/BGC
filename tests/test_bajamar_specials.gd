extends TestCase

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")
const G := preload("res://games/bajamar/logic/bajamar_game.gd")


func _game(n: int = 3, seed_value: int = 1) -> BajamarGame:
	var g := BajamarGame.new()
	var ps: Array[PlayerInfo] = []
	for i in n:
		ps.append(PlayerInfo.new(i))
	g.setup(ps, seed_value)
	return g


## Prepara el mazo para que se roben `cards` en ese orden (el resto debajo).
## Si una carta está en el mercado, se cambia allí por un pez del mazo, para
## no duplicarla.
func _rig(g: BajamarGame, cards: Array) -> void:
	var rest := g.deck.duplicate()
	for c in cards:
		var i := rest.find(c)
		if i >= 0:
			rest.remove_at(i)
			continue
		var slot := g.market.find(c)
		if slot >= 0:
			for k in rest.size():
				if D.is_fish(rest[k]) and not rest[k] in cards:
					g.market[slot] = rest[k]
					rest.remove_at(k)
					break
	var top := cards.duplicate()
	top.reverse()
	g.deck.assign(rest + top)


func _do(g: BajamarGame, type: StringName, data: Dictionary = {}, pid: int = -1) -> String:
	if pid < 0:
		pid = g.players_to_act()[0] if not g.players_to_act().is_empty() else g.turns.current
	return g.submit(GameAction.new(type, pid, data))


func _total_cards(g: BajamarGame) -> int:
	var total := g.deck.size() + g.discard.size() + g.market.size()
	for p in g.players.size():
		total += g.net(p).size() + (1 if g.shields[p] else 0)
	return total


func _events(g: BajamarGame) -> Array:
	var log := []
	g.event.connect(func(kind: StringName, _d: Dictionary) -> void: log.append(kind))
	return log


# --- Gaviota ----------------------------------------------------------------------

func test_gull_steals_last_fish() -> void:
	var g := _game(3)
	var a := D.fish(0, 2)
	var b := D.fish(1, 5)
	_rig(g, [D.fish(2, 1), a, b, D.GULL])
	_do(g, G.DRAW_BLIND)  # J0: pez
	_do(g, G.DRAW_BLIND)  # J1: a
	_do(g, G.DRAW_BLIND)  # J2: b
	_do(g, G.DRAW_BLIND)  # J0: gaviota
	assert_eq(g.pending_gulls, [0] as Array[int])
	assert_eq(g.players_to_act(), [0] as Array[int])
	assert_eq(g.turns.current, 0, "el turno no pasa hasta resolverla")
	assert_eq(g.gull_targets(0), [1, 2] as Array[int])
	assert_eq(_do(g, G.DRAW_BLIND), "Primero elige a quién le quita un pez la gaviota")
	assert_eq(_do(g, G.CHOOSE_TARGET, {"target": 0}), "La gaviota no puede quitarle un pez a ese jugador")
	var legal := g.get_legal_actions(0)
	assert_eq(legal.size(), 2)
	assert_eq(_do(g, G.CHOOSE_TARGET, {"target": 2}), "")
	assert_true(g.net(2).is_empty())
	assert_eq(g.net(0), [D.fish(2, 1), b] as Array[int])
	assert_true(g.pending_gulls.is_empty())
	assert_eq(g.turns.current, 1)
	assert_true(D.GULL in g.discard)
	assert_eq(_total_cards(g), D.deck().size())


func test_gull_can_rob_player_in_port() -> void:
	var g := _game(2)
	var a := D.fish(3, 6)
	var b := D.fish(4, 4)
	_rig(g, [a, b, D.GULL])
	_do(g, G.DRAW_BLIND)  # J0: a
	_do(g, G.DRAW_BLIND)  # J1: b
	_do(g, G.GO_TO_PORT)  # J0 vuelve a puerto con a
	_do(g, G.DRAW_BLIND)  # J1: gaviota
	assert_eq(g.gull_targets(1), [0] as Array[int])
	_do(g, G.CHOOSE_TARGET, {"target": 0})
	assert_eq(g.net(1), [b, a] as Array[int])
	_do(g, G.GO_TO_PORT)  # J1: termina la ronda
	assert_eq(g.last_round[0]["total"], 0)
	assert_eq(g.last_round[1]["total"], D.score([b, a])["total"])


func test_gull_without_targets_is_wasted() -> void:
	var g := _game(2)
	_rig(g, [D.GULL])
	var log := _events(g)
	_do(g, G.DRAW_BLIND)
	assert_true(&"gull_wasted" in log)
	assert_true(g.pending_gulls.is_empty())
	assert_eq(g.turns.current, 1)


func test_gull_from_market() -> void:
	var g := _game(2)
	var a := D.fish(0, 4)
	_rig(g, [a])
	_do(g, G.DRAW_BLIND)  # J0: pez
	g.market[0] = D.GULL
	_do(g, G.TAKE_MARKET, {"slot": 0})  # J1: gaviota y a puerto
	assert_eq(g.status[1], G.Status.IN_PORT)
	assert_eq(g.players_to_act(), [1] as Array[int], "resuelve la gaviota aunque ya esté en puerto")
	_do(g, G.CHOOSE_TARGET, {"target": 0})
	assert_eq(g.net(1), [a] as Array[int])
	assert_eq(g.market.size(), D.MARKET_SIZE)
	assert_eq(g.turns.current, 0)


# --- Red reforzada ------------------------------------------------------------------

func test_shield_salvages_half_when_net_breaks() -> void:
	var g := _game(2)
	var fish := [D.fish(1, 3), D.fish(1, 4)]  # 7 + 2 caballas × 2 = 11
	_rig(g, [D.SHIELD, D.fish(0, 1), fish[0], D.fish(0, 2), fish[1], D.STORM])
	_do(g, G.DRAW_BLIND)  # J0: red reforzada
	assert_true(g.shields[0])
	for i in 4:
		_do(g, G.DRAW_BLIND)
	_do(g, G.GO_TO_PORT)  # J1
	assert_eq(g.net_score(0)["total"], 11)
	var log := []
	g.event.connect(func(kind: StringName, d: Dictionary) -> void:
		if kind == &"net_broken":
			log.append(d["salvaged"]))
	_do(g, G.DRAW_BLIND)  # J0: tormenta → se rompe, salva la mitad
	assert_eq(log, [5])
	assert_eq(g.last_round[0]["total"], 5)
	assert_true(g.last_round[0]["broken"])
	assert_eq(g.scores[0], 5)


func test_shield_from_market_is_useless() -> void:
	var g := _game(2)
	g.market[0] = D.SHIELD
	_do(g, G.TAKE_MARKET, {"slot": 0})
	assert_eq(g.status[0], G.Status.IN_PORT)
	assert_true(g.shields[0], "la tiene, pero ya está en puerto")


func test_second_shield_is_discarded() -> void:
	var g := _game(2)
	_rig(g, [D.SHIELD, D.fish(0, 1), D.SHIELD])
	var before := g.discard.count(D.SHIELD)
	_do(g, G.DRAW_BLIND)
	_do(g, G.DRAW_BLIND)
	_do(g, G.DRAW_BLIND)
	assert_true(g.shields[0])
	assert_eq(g.discard.count(D.SHIELD), before + 1)


func test_shield_discarded_at_round_end() -> void:
	var g := _game(2)
	_rig(g, [D.SHIELD])
	_do(g, G.DRAW_BLIND)
	_do(g, G.GO_TO_PORT)
	_do(g, G.GO_TO_PORT)
	assert_false(g.shields[0])
	assert_eq(g.last_round[0]["total"], 0)
	assert_eq(_total_cards(g), D.deck().size())


# --- Marea alta ---------------------------------------------------------------------

func test_high_tide_everyone_at_sea_draws() -> void:
	var g := _game(4)
	var a := D.fish(0, 1)
	var b := D.fish(1, 2)
	var c := D.fish(2, 3)
	_rig(g, [D.fish(4, 6), D.HIGH_TIDE, a, b, c])
	_do(g, G.DRAW_BLIND)  # J0: pez
	_do(g, G.GO_TO_PORT)  # J1 en puerto: no roba con la marea
	_do(g, G.DRAW_BLIND)  # J2: Marea alta → roban J2, J3 y J0
	assert_eq(g.net(2), [a] as Array[int])
	assert_eq(g.net(3), [b] as Array[int])
	assert_eq(g.net(0), [D.fish(4, 6), c] as Array[int])
	assert_true(g.net(1).is_empty())
	assert_eq(g.turns.current, 3)
	assert_eq(_total_cards(g), D.deck().size())


func test_high_tide_storm_can_break_others() -> void:
	var g := _game(2)
	_rig(g, [D.fish(0, 1), D.HIGH_TIDE, D.fish(0, 3), D.STORM])
	_do(g, G.DRAW_BLIND)  # J0: pez
	_do(g, G.DRAW_BLIND)  # J1: marea → J1 pez, J0 tormenta (se rompe)
	assert_eq(g.status[0], G.Status.BROKEN)
	assert_eq(g.status[1], G.Status.AT_SEA)
	assert_eq(g.turns.current, 1, "J0 ya no está en el mar")


func test_high_tide_from_market_skips_taker() -> void:
	var g := _game(3)
	var a := D.fish(0, 1)
	var b := D.fish(1, 2)
	_rig(g, [a, b])
	g.market[0] = D.HIGH_TIDE
	_do(g, G.TAKE_MARKET, {"slot": 0})  # J0 a puerto; roban J1 y J2
	assert_true(g.net(0).is_empty())
	assert_eq(g.net(1), [a] as Array[int])
	assert_eq(g.net(2), [b] as Array[int])
	assert_eq(g.turns.current, 1)


func test_high_tide_chain_is_wasted_and_gulls_resolve_after() -> void:
	var g := _game(3)
	var a := D.fish(0, 5)
	_rig(g, [a, D.HIGH_TIDE, D.HIGH_TIDE, D.GULL, D.fish(1, 1)])
	_do(g, G.DRAW_BLIND)  # J0: pez a
	var log := _events(g)
	_do(g, G.DRAW_BLIND)  # J1: marea → J1 otra marea (sin efecto), J2 gaviota, J0 pez
	assert_true(&"tide_wasted" in log)
	assert_eq(g.players_to_act(), [2] as Array[int])
	assert_eq(g.gull_targets(2), [0] as Array[int])
	_do(g, G.CHOOSE_TARGET, {"target": 0})
	assert_eq(g.net(2), [D.fish(1, 1)] as Array[int], "le quita el último pez de J0")
	assert_eq(g.net(0), [a] as Array[int])
	assert_eq(g.turns.current, 2, "después sigue el turno normal")
	assert_eq(_total_cards(g), D.deck().size())


func test_gull_wasted_when_only_target_breaks_in_tide() -> void:
	var g := _game(2)
	_rig(g, [D.fish(0, 1), D.HIGH_TIDE, D.GULL, D.STORM])
	_do(g, G.DRAW_BLIND)  # J0: pez
	var log := _events(g)
	_do(g, G.DRAW_BLIND)  # J1: marea → J1 gaviota, J0 tormenta (se rompe)
	assert_eq(g.status[0], G.Status.BROKEN)
	assert_true(&"gull_wasted" in log, "la única víctima posible ya no tiene red")
	assert_true(g.pending_gulls.is_empty())
	assert_eq(g.turns.current, 1)
	assert_eq(_total_cards(g), D.deck().size())
