class_name PuertoAI
extends RefCounted
## IA de Puerto Franco. Solo usa game.view_for(pid): no hace trampa (no ve
## las manos de los demás, ni el mazo, ni las elecciones sin revelar).
##
## Cada decisión se valora en "puntos": lo que sube la puntuación del barrio
## (coste, grupos, maravillas), los objetivos públicos y lo que valen las
## monedas y las cartas que quedan para más adelante.
##
##   Fácil: no mira objetivos ni a los rivales; elige cargo con mucho ruido y
##          sin pujar, y a veces se equivoca de jugada.
##   Normal: valora cada cargo para sí misma y puja 1 si un cargo le interesa
##          mucho más que el resto. Planifica el turno (cómo cobrar según lo
##          que podrá construir) y persigue los objetivos públicos.
##   Difícil: además predice qué cargo y qué puja querrá cada rival (con lo
##          público) y puja lo justo para ganar el suyo, o se va a otro si
##          no le compensa. En la última ronda lo gasta todo, pesa más los
##          objetivos, deja sitio para que crezcan sus grupos y la
##          Contrabandista le roba al que va ganando.
##
## Misma interfaz que el resto de IAs: new(pid, nivel, semilla) y
## choose_action(game).

const AILevel := PlayerInfo.AILevel
const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")
const G := preload("res://games/puerto_franco/logic/puerto_game.gd")
const Office := PuertoDefs.Office
const Wonder := PuertoDefs.Wonder
const Objective := PuertoDefs.Objective

# --- Ajustes (equilibrados con torneos entre IAs) ------------------------------
## Valor de una moneda guardada (baja al final: las monedas no puntúan).
const COIN_VALUE := 1.1
const COIN_VALUE_LATE := 0.3
## Valor base de una carta en la mano (más su "extra" esperado).
const CARD_VALUE := 0.6
const CARD_BONUS_WEIGHT := 0.25
## Cartas en la mano a partir de las cuales una más vale la mitad.
const HAND_COMFORT := 4
## Carta a ciegas: lo que vale de media.
const BLIND_CARD_VALUE := 0.9
## Peso de los objetivos públicos (son 4 puntos, pero inciertos).
const OBJECTIVE_WEIGHT := {AILevel.EASY: 0.0, AILevel.NORMAL: 0.5, AILevel.HARD: 1.0}
## Ruido al elegir cargo y probabilidad de jugada al azar (fácil).
const EASY_OFFICE_NOISE := 2.5
const EASY_MISTAKE_CHANCE := 0.1
const NORMAL_OFFICE_NOISE := 0.4
## Normal: margen sobre el segundo cargo para pujar 1.
const BID_MARGIN := 1.5
## Al colocar, extra por cada casilla libre alrededor (sitio para crecer el
## grupo). La difícil lo tiene más en cuenta.
const ROOM_WEIGHT := {AILevel.EASY: 0.03, AILevel.NORMAL: 0.03, AILevel.HARD: 0.12}
## Difícil: puja máxima que se plantea.
const HARD_MAX_BID := 3

var pid: int
var level: int
var _rng: BGCRng
var _view: Dictionary
## Caché de placement() durante una decisión (jugador*1000+carta -> resultado).
var _placement_cache := {}


func _init(p_pid: int, p_level: int = AILevel.NORMAL, p_seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng = BGCRng.new(p_seed * 31 + p_pid * 7919 + 23)


func choose_action(game: PuertoGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	_view = game.view_for(pid)
	_placement_cache.clear()
	if level == AILevel.EASY and _view["phase"] == G.Phase.TURN and _rng.randf() < EASY_MISTAKE_CHANCE:
		return legal[_rng.randi_range(0, legal.size() - 1)]
	match _view["phase"]:
		G.Phase.PICK:
			return _pick()
		G.Phase.REASSIGN:
			var best: GameAction = legal[0]
			var best_value := -INF
			for a in legal:
				var v := office_value(int(a.data["office"]), pid)
				if v > best_value:
					best_value = v
					best = a
			return best
		G.Phase.TURN:
			return _turn(legal)
	return legal[0]


# --- Valoraciones ----------------------------------------------------------------

func _district(p: int) -> Array:
	return _view["districts"][p]


func _coins(p: int) -> int:
	return _view["coins"][p]


func _building_count(p: int) -> int:
	var count := 0
	for c in _district(p):
		if c >= 0:
			count += 1
	return count


## Rondas que quedan, más o menos (se construye ~1 edificio por ronda).
func rounds_left() -> int:
	var most := 0
	for p in _view["player_count"]:
		most = maxi(most, _building_count(p))
	return maxi(1, D.BUILDINGS_TO_END - most)


func coin_value() -> float:
	if level == AILevel.HARD and final_round():
		return 0.0
	return COIN_VALUE if rounds_left() > 2 else COIN_VALUE_LATE


## Difícil: true si esta ronda es seguro la última (alguien ya completó su
## barrio). Entonces ni monedas ni cartas valen nada: hay que construir.
func final_round() -> bool:
	return _view["first_finisher"] >= 0


## Difícil: true si alguien puede completar el barrio esta ronda.
func final_round_likely() -> bool:
	for p in _view["player_count"]:
		if _building_count(p) >= D.BUILDINGS_TO_END - 1:
			return true
	return false


## Mejor sitio para `card` en el barrio de `p`: {"cell", "gain"}. La
## ganancia son los puntos que suma (sin restar el coste en monedas).
func placement(card: int, p: int = -1, district: Array = []) -> Dictionary:
	if p < 0:
		p = pid
	var key := -1
	if district.is_empty():
		district = _district(p)
		key = p * 1000 + card
		if _placement_cache.has(key):
			return _placement_cache[key]
	var before: int = D.score_district(district, _coins(p))["total"]
	var best := {"cell": -1, "gain": -INF}
	for cell in D.buildable_cells(district):
		var after := district.duplicate()
		after[cell] = card
		var gain := float(D.score_district(after, _coins(p))["total"] - before)
		gain += _objective_gain(p, district, after)
		gain += _wonder_future(card, cell, after)
		# Desempate: dejar sitio alrededor para futuros grupos.
		for n in D.cell_neighbors(cell):
			if after[n] == D.EMPTY:
				gain += ROOM_WEIGHT[level] if not D.is_wonder(card) else 0.03
		if gain > best["gain"]:
			best = {"cell": cell, "gain": gain}
	if key >= 0:
		_placement_cache[key] = best
	return best


## Valor esperado de lo que aportan las maravillas en las rondas que quedan.
func _wonder_future(card: int, cell: int, district: Array) -> float:
	var r := float(rounds_left())
	match D.wonder_of(card):
		Wonder.CUSTOMS:
			return 0.5 * r
		Wonder.SHIPYARD_ROYAL:
			return 0.4 * r
		Wonder.GUILD_HALL:
			return 0.3 * r
		Wonder.PLAZA:
			var free := 0
			for n in D.cell_neighbors(cell):
				if district[n] == D.EMPTY:
					free += 1
			return 0.6 * minf(free, r)
		Wonder.LIGHTHOUSE:
			return 0.3 * r
	return 0.0


## Cuánto acerca un cambio de barrio a ganar los objetivos públicos.
func _objective_gain(p: int, before: Array, after: Array) -> float:
	var weight: float = OBJECTIVE_WEIGHT[level]
	if weight == 0.0:
		return 0.0
	var gain := 0.0
	for obj in _view["objectives"]:
		if obj == Objective.RICHEST:
			continue
		var rival := 0
		for other in _view["player_count"]:
			if other != p:
				rival = maxi(rival, D.objective_value(obj, _district(other), _coins(other)))
		var v0 := D.objective_value(obj, before, _coins(p))
		var v1 := D.objective_value(obj, after, _coins(p))
		gain += (_share(v1, rival) - _share(v0, rival)) * D.OBJECTIVE_POINTS * weight
	return gain


static func _share(mine: int, rival: int) -> float:
	if mine <= 0 or mine < rival:
		return 0.0
	return 1.0 if mine > rival else 0.5


## Valor de una carta para guardarla en la mano.
func card_keep_value(card: int, hand_size: int, p: int = -1) -> float:
	var extra := maxf(0.0, placement(card, p)["gain"] - D.cost_of(card))
	var v := CARD_VALUE + CARD_BONUS_WEIGHT * extra
	if level == AILevel.HARD and final_round():
		return 0.0
	if rounds_left() <= 1:
		v *= 0.2
	return v * (0.5 if hand_size >= HAND_COMFORT else 1.0)


## Mejor construcción posible con esta mano y estas monedas:
## {"index", "cell", "value"} (value = puntos − monedas gastadas).
func best_build(hand: Array, coins: int, discount: int = 0) -> Dictionary:
	var best := {"index": -1, "cell": -1, "value": 0.0}
	var cv := coin_value()
	for i in hand.size():
		var cost := maxi(0, D.cost_of(hand[i]) - discount)
		if cost > coins:
			continue
		var place := placement(hand[i])
		if place["cell"] < 0:
			continue
		var value: float = place["gain"] - cost * cv
		if best["index"] < 0 or value > best["value"]:
			best = {"index": i, "cell": place["cell"], "value": value}
	return best


## Valor de una situación tras cobrar: lo mejor que se puede construir y lo
## que vale lo que sobra.
func _plan_value(hand: Array, coins: int, extra_cards: float, builds: int, discount: int) -> float:
	var total := 0.0
	var h := hand.duplicate()
	var c := coins
	for i in builds:
		var b := best_build(h, c, discount)
		if b["index"] < 0:
			break
		total += b["value"]
		c -= maxi(0, D.cost_of(h[b["index"]]) - discount)
		h.remove_at(b["index"])
	total += c * coin_value()
	for card in h:
		total += card_keep_value(card, h.size())
	total += extra_cards * BLIND_CARD_VALUE
	return total


## Lo que vale un cargo este turno para `p` (en puntos).
func office_value(o: int, p: int) -> float:
	var cv := coin_value()
	var v: float = _view["vacant_coins"][o] * cv
	var mine := p == pid
	var hand: Array = _view["hand"] if mine else []
	var coins := _coins(p)
	match o:
		Office.HARBOR:
			var best := 1.2 if not _view["dock"].is_empty() else 0.0
			for card in _view["dock"]:
				best = maxf(best, card_keep_value(card, hand.size() if mine else _view["hand_sizes"][p], p) + 0.6)
			v += best
		Office.SMUGGLER:
			var targets := 0
			for other in _view["player_count"]:
				if other != p and _view["hand_sizes"][other] > 0:
					targets += 1
			if targets > 0:
				v += BLIND_CARD_VALUE + 0.3
				if level == AILevel.HARD:
					v += 0.3
		Office.COLLECTOR:
			# Se cobra después de cobrar el turno: quien coge monedas antes
			# de usar el cargo cobra de menos gente, así que se usa antes.
			for other in _view["player_count"]:
				if other != p and _coins(other) > coins:
					v += cv + 0.3
		Office.PLANNER:
			v += 0.5
			if mine:
				var b := best_build(hand, coins + D.COIN_INCOME, D.PLANNER_DISCOUNT)
				if b["index"] >= 0:
					v += cv * mini(D.PLANNER_DISCOUNT, D.cost_of(hand[b["index"]]))
				v += maxf(0.0, _best_move(p)["gain"])
			else:
				# Un rival: casi siempre construirá con la rebaja.
				v += cv * D.PLANNER_DISCOUNT if coins + D.COIN_INCOME >= 2 else 0.0
				v += maxf(0.0, _best_move(p)["gain"])
		Office.BUILDER:
			if mine:
				var with_two := _plan_value(hand, coins + D.COIN_INCOME, 0, 2, 0)
				var with_one := _plan_value(hand, coins + D.COIN_INCOME, 0, 1, 0)
				v += maxf(0.0, with_two - with_one) + 0.4
				if level == AILevel.HARD and final_round_likely():
					v += 1.5
			else:
				v += 1.6 if coins + D.COIN_INCOME >= 4 and _view["hand_sizes"][p] >= 2 else 0.3
		Office.PATRON:
			v += mini(D.group_count(_district(p)), D.PATRON_MAX) * cv
		Office.MAYOR:
			v += BLIND_CARD_VALUE + 0.4 + D.MAYOR_COINS * cv
	return v


## Mejor traslado de la Urbanista para `p`: {"from", "to", "gain"}.
func _best_move(p: int) -> Dictionary:
	var district := _district(p)
	var before: int = D.score_district(district, _coins(p))["total"]
	var best := {"from": -1, "to": -1, "gain": 0.0}
	for from in district.size():
		if district[from] < 0:
			continue
		for to in district.size():
			if district[to] != D.EMPTY:
				continue
			var moved := district.duplicate()
			moved[to] = moved[from]
			moved[from] = D.EMPTY
			if not D.all_linked(moved):
				continue
			var gain := float(D.score_district(moved, _coins(p))["total"] - before)
			gain += _objective_gain(p, district, moved)
			if gain > best["gain"]:
				best = {"from": from, "to": to, "gain": gain}
	return best


# --- Elección de cargo -------------------------------------------------------------

func _pick() -> GameAction:
	var values: Array[float] = []
	for o in D.OFFICE_COUNT:
		values.append(office_value(o, pid))
	if level == AILevel.HARD:
		return _hard_pick(values)
	var noise := EASY_OFFICE_NOISE if level == AILevel.EASY else NORMAL_OFFICE_NOISE
	var order := _ranked(values, noise)
	var best: int = order[0]
	var bid := 0
	if level == AILevel.NORMAL and _coins(pid) >= 2 and values[best] - values[order[1]] >= BID_MARGIN:
		bid = 1
	return GameAction.new(G.PICK, pid, {"office": best, "bid": bid})


func _ranked(values: Array[float], noise: float) -> Array[int]:
	var noisy: Array[float] = []
	for v in values:
		noisy.append(v + (_rng.randf() * 2.0 - 1.0) * noise)
	var order: Array[int] = []
	for o in values.size():
		order.append(o)
	order.sort_custom(func(a: int, b: int) -> bool: return noisy[a] > noisy[b])
	return order


## Qué cargo y qué puja espera de un rival (como lo haría una IA normal).
func predict_pick(p: int) -> Dictionary:
	var values: Array[float] = []
	for o in D.OFFICE_COUNT:
		values.append(office_value(o, p))
	var order := _ranked(values, 0.0)
	var bid := 1 if _coins(p) >= 2 and values[order[0]] - values[order[1]] >= BID_MARGIN else 0
	return {"office": order[0], "bid": bid}


## Difícil: elige el par (cargo, puja) con más valor esperado, sabiendo qué
## querrán los demás. Si pierde, se queda un vacante: se estima con el
## mejor cargo que nadie más quiere.
func _hard_pick(values: Array[float]) -> GameAction:
	var initiative: Array[int] = []
	for i in _view["player_count"]:
		initiative.append((_view["vara"] + i) % _view["player_count"])
	var rivals := {}  # cargo -> [{pid, bid}]
	for p in _view["player_count"]:
		if p == pid:
			continue
		var guess := predict_pick(p)
		if not rivals.has(guess["office"]):
			rivals[guess["office"]] = []
		rivals[guess["office"]].append({"pid": p, "bid": guess["bid"]})
	var fallback := 0.0
	for o in D.OFFICE_COUNT:
		if not rivals.has(o):
			fallback = maxf(fallback, values[o])
	fallback *= 0.9  # quien pierde elige vacante, pero no siempre el primero
	var cv := coin_value()
	var best := {"office": 0, "bid": 0}
	var best_ev := -INF
	for o in D.OFFICE_COUNT:
		for bid in mini(HARD_MAX_BID, _coins(pid)) + 1:
			var wins := true
			for r in rivals.get(o, []):
				var their: int = r["bid"]
				if their > bid or (their == bid and initiative.find(r["pid"]) < initiative.find(pid)):
					wins = false
			var ev := values[o] - bid * cv if wins else fallback
			ev += (_rng.randf() - 0.5) * 0.1
			if ev > best_ev:
				best_ev = ev
				best = {"office": o, "bid": bid}
	return GameAction.new(G.PICK, pid, best)


# --- Turno --------------------------------------------------------------------------

func _turn(legal: Array[GameAction]) -> GameAction:
	var office: int = _view["turn_office"]
	var hand: Array = _view["hand"]
	var coins := _coins(pid)
	# 1. Cargos que conviene usar antes de cobrar.
	if not _view["ability_used"]:
		match office:
			Office.HARBOR when not _view["dock"].is_empty():
				var best_i := 0
				var best_v := -INF
				for i in _view["dock"].size():
					var v := card_keep_value(_view["dock"][i], hand.size())
					if v > best_v:
						best_v = v
						best_i = i
				return GameAction.new(G.ABILITY, pid, {"index": best_i})
			Office.SMUGGLER:
				var target := _smuggler_target()
				if target >= 0:
					return GameAction.new(G.ABILITY, pid, {"target": target})
			Office.COLLECTOR, Office.PATRON:
				return GameAction.new(G.ABILITY, pid, {})
	# 2. Cobrar según lo que se podrá construir después.
	if not _view["income_taken"]:
		return _income(hand, coins, office)
	# 3. La Urbanista traslada si mejora el barrio.
	if office == Office.PLANNER and not _view["ability_used"]:
		var move := _best_move(pid)
		if move["from"] >= 0 and move["gain"] >= 1.0:
			return GameAction.new(G.ABILITY, pid, {"from": move["from"], "to": move["to"]})
	# 4. Construir lo mejor que se pueda.
	if _view["builds_left"] > 0:
		var discount := D.PLANNER_DISCOUNT if office == Office.PLANNER else 0
		var b := best_build(hand, coins, discount)
		if b["index"] >= 0 and b["value"] > -0.2:
			return GameAction.new(G.BUILD, pid, {"card": b["index"], "cell": b["cell"]})
	return GameAction.new(G.END_TURN, pid, {})


func _income(hand: Array, coins: int, office: int) -> GameAction:
	var builds: int = _view["builds_left"]
	var discount := D.PLANNER_DISCOUNT if office == Office.PLANNER else 0
	var customs := false
	var shipyard := false
	for c in _district(pid):
		if c >= 0 and D.wonder_of(c) == Wonder.CUSTOMS:
			customs = true
		if c >= 0 and D.wonder_of(c) == Wonder.SHIPYARD_ROYAL:
			shipyard = true
	var best := GameAction.new(G.INCOME, pid, {"kind": G.Income.COINS})
	var best_v := _plan_value(hand, coins + D.COIN_INCOME + (1 if customs else 0), 0, builds, discount)
	for i in _view["dock"].size():
		var h := hand.duplicate()
		h.append(_view["dock"][i])
		var v := _plan_value(h, coins, 1.0 if shipyard else 0.0, builds, discount)
		if v > best_v:
			best_v = v
			best = GameAction.new(G.INCOME, pid, {"kind": G.Income.DOCK, "index": i})
	if _view["deck_count"] > 0 or not _view["discard"].is_empty():
		var v := _plan_value(hand, coins + 1, 1.0, builds, discount)
		if v > best_v:
			best = GameAction.new(G.INCOME, pid, {"kind": G.Income.BLIND})
	return best


## A quién le quita una carta la Contrabandista: a quien más tiene (la
## difícil, al que va ganando de entre los que tienen al menos 2).
func _smuggler_target() -> int:
	var best := -1
	var best_v := -INF
	for other in _view["player_count"]:
		if other == pid or _view["hand_sizes"][other] == 0:
			continue
		var v := float(_view["hand_sizes"][other])
		if level == AILevel.HARD and _view["hand_sizes"][other] >= 2:
			v += D.score_district(_district(other), _coins(other))["total"] * 0.2
		if v > best_v:
			best_v = v
			best = other
	return best
