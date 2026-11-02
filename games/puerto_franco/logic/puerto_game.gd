class_name PuertoGame
extends GameBase
## Lógica de Puerto Franco (cargos secretos y barrios de hexágonos, 2–6
## jugadores).
##
## Ronda:
##  1. CARGOS: todos eligen a la vez y en secreto un cargo y una puja en
##     monedas. Si varios eligen el mismo, se lo queda la puja más alta (y la
##     paga); los empates los gana quien va antes desde la vara. Los que se
##     quedan sin cargo eligen, por orden desde la vara, entre los vacantes
##     (sin pagar). Los cargos que nadie ocupa acumulan 1 moneda.
##  2. TURNOS: en orden de cargo, cada jugador cobra (2 monedas, 1 carta del
##     muelle o 1 carta a ciegas y 1 moneda), puede usar su cargo y
##     construir 1 edificio en su barrio, vecino de lo que ya tiene.
## Cuando alguien tiene BUILDINGS_TO_END edificios, la partida acaba al
## final de la ronda.
##
## INFORMACIÓN OCULTA: manos, mazo y elecciones de cargo sin revelar viven
## aquí. La interfaz y la IA deben usar view_for(seat).

signal event(kind: StringName, data: Dictionary)

const D := preload("res://games/puerto_franco/logic/puerto_defs.gd")
const Office := PuertoDefs.Office
const Guild := PuertoDefs.Guild
const Wonder := PuertoDefs.Wonder
const Objective := PuertoDefs.Objective

enum Phase { PICK, REASSIGN, TURN, FINISHED }
enum Income { COINS, DOCK, BLIND }

const PICK := &"pick"            # {"office": int, "bid": int} (simultánea)
const REASSIGN := &"reassign"    # {"office": int} (quien perdió la puja)
const INCOME := &"income"        # {"kind": Income, "index": int (muelle)}
const ABILITY := &"ability"      # según el cargo: {"index"}, {"target"}, {"from", "to"} o {}
const BUILD := &"build"          # {"card": índice en la mano, "cell": casilla}
const END_TURN := &"end_turn"

const PHASE_NAMES := {
	Phase.PICK: "Elección de cargos",
	Phase.REASSIGN: "Cargos vacantes",
	Phase.TURN: "Turnos",
	Phase.FINISHED: "Fin de la partida",
}

var phase := Phase.PICK
var round_number := 1

var coins: Array[int] = []
var hands: Array = []          # pid -> Array[int]
var districts: Array = []      # pid -> Array[int] (len CELLS, EMPTY / LONJA / carta)
var deck: Array[int] = []
var discard: Array[int] = []
var dock: Array[int] = []
var objectives: Array[int] = []

## Quien tiene la vara: desempata las pujas y elige primero los vacantes.
var vara := 0
## Elecciones secretas de la ronda: pid -> {"office", "bid"}.
var picks := {}
## Resultado público de la última elección: [{player, office, bid, won}].
var last_reveal: Array[Dictionary] = []
var office_of: Array[int] = []      # pid -> cargo (-1)
var holder: Array[int] = []         # cargo -> pid (-1)
var vacant_coins: Array[int] = []   # cargo -> monedas acumuladas
var reassign_queue: Array[int] = []

# Turno en curso
var turn_office := -1
var income_taken := false
var ability_used := false
var builds_left := 0

var first_finisher := -1
## Desglose de puntos final (pid -> Dictionary), al terminar.
var final_scores: Array[Dictionary] = []


# --- Preparación ----------------------------------------------------------------

func _on_setup() -> void:
	var n := players.size()
	assert(n >= 2 and n <= 6, "Puerto Franco es para 2–6 jugadores")
	deck = D.deck(n)
	rng.shuffle(deck)
	discard.clear()
	coins.clear()
	hands.clear()
	districts.clear()
	office_of.clear()
	for i in n:
		coins.append(D.START_COINS)
		var hand: Array[int] = []
		for k in D.START_HAND:
			hand.append(deck.pop_back())
		hands.append(hand)
		var district: Array[int] = []
		district.resize(D.CELLS.size())
		district.fill(D.EMPTY)
		district[D.LONJA_CELL] = D.LONJA
		districts.append(district)
		office_of.append(-1)
	holder.clear()
	vacant_coins.clear()
	for o in D.OFFICE_COUNT:
		holder.append(-1)
		vacant_coins.append(0)
	dock.clear()
	_refill_dock()
	var all_objectives: Array[int] = []
	for o in D.OBJECTIVE_COUNT:
		all_objectives.append(o)
	rng.shuffle(all_objectives)
	objectives = all_objectives.slice(0, D.OBJECTIVES_PER_GAME)
	objectives.sort()
	vara = rng.randi_range(0, n - 1)
	turns.current = vara
	_begin_round()


# --- Consultas ------------------------------------------------------------------

## Orden de iniciativa: desde quien tiene la vara, en el sentido de los asientos.
func initiative_order() -> Array[int]:
	var result: Array[int] = []
	for i in players.size():
		result.append((vara + i) % players.size())
	return result


## Quién puede actuar ahora (en la elección de cargos, varios a la vez).
func players_to_act() -> Array[int]:
	var result: Array[int] = []
	match phase:
		Phase.PICK:
			for pid in initiative_order():
				if not picks.has(pid):
					result.append(pid)
		Phase.REASSIGN:
			result.append(reassign_queue[0])
		Phase.TURN:
			result.append(holder[turn_office])
	return result


func building_count(pid: int) -> int:
	var count := 0
	for c in districts[pid]:
		if c >= 0:
			count += 1
	return count


func vacant_offices() -> Array[int]:
	var result: Array[int] = []
	for o in D.OFFICE_COUNT:
		if holder[o] < 0:
			result.append(o)
	return result


## Coste de construir `card` para el jugador del turno (con la rebaja de la
## Urbanista).
func build_cost(pid: int, card: int) -> int:
	var cost := D.cost_of(card)
	if phase == Phase.TURN and office_of[pid] == Office.PLANNER and holder[turn_office] == pid:
		cost = maxi(0, cost - D.PLANNER_DISCOUNT)
	return cost


## Casillas libres donde `pid` puede construir (vecinas de algo construido).
func buildable_cells(pid: int) -> Array[int]:
	return D.buildable_cells(districts[pid])


func has_wonder(pid: int, wonder: int) -> bool:
	for c in districts[pid]:
		if c >= 0 and D.wonder_of(c) == wonder:
			return true
	return false


## Objetivos de la Contrabandista.
func smuggler_targets(pid: int) -> Array[int]:
	var result: Array[int] = []
	for other in players.size():
		if other != pid and not hands[other].is_empty():
			result.append(other)
	return result


## Traslados válidos de la Urbanista: [[desde, hasta], ...].
func planner_moves(pid: int) -> Array:
	var result: Array = []
	var district: Array = districts[pid]
	for from in district.size():
		if district[from] < 0:
			continue
		for to in district.size():
			if district[to] != D.EMPTY:
				continue
			var moved: Array = district.duplicate()
			moved[to] = moved[from]
			moved[from] = D.EMPTY
			if D.all_linked(moved):
				result.append([from, to])
	return result


## Puntos actuales de un jugador (lo que puntuaría si acabase ahora).
func score_of(pid: int) -> Dictionary:
	var breakdown := D.score_district(districts[pid], coins[pid])
	var obj_points := 0
	var won: Array[int] = []
	for obj in objectives:
		if pid in objective_leaders(obj):
			obj_points += D.OBJECTIVE_POINTS
			won.append(obj)
	breakdown["objectives"] = obj_points
	breakdown["objectives_won"] = won
	breakdown["first"] = D.FIRST_TO_FINISH_POINTS if pid == first_finisher else 0
	breakdown["total"] += obj_points + breakdown["first"]
	return breakdown


## Jugadores que cumplen mejor el objetivo (nadie si el mejor valor es 0).
func objective_leaders(obj: int) -> Array[int]:
	var best := 0
	var result: Array[int] = []
	for pid in players.size():
		var v := D.objective_value(obj, districts[pid], coins[pid])
		if v > best:
			best = v
			result.clear()
			result.append(pid)
		elif v == best and v > 0:
			result.append(pid)
	return result


## Lo que puede saber `seat` (-1 = solo lo público).
func view_for(seat: int) -> Dictionary:
	var picked := {}
	for pid in picks:
		picked[pid] = true
	var hand_sizes: Array[int] = []
	for h in hands:
		hand_sizes.append(h.size())
	var view := {
		"seat": seat,
		"player_count": players.size(),
		"phase": phase,
		"round": round_number,
		"vara": vara,
		"coins": coins.duplicate(),
		"hand_sizes": hand_sizes,
		"districts": districts.duplicate(true),
		"dock": dock.duplicate(),
		"deck_count": deck.size(),
		"discard": discard.duplicate(),
		"objectives": objectives.duplicate(),
		"picked": picked,
		"last_reveal": last_reveal.duplicate(true),
		"office_of": office_of.duplicate(),
		"holder": holder.duplicate(),
		"vacant_coins": vacant_coins.duplicate(),
		"reassign_queue": reassign_queue.duplicate(),
		"turn_office": turn_office,
		"income_taken": income_taken,
		"ability_used": ability_used,
		"builds_left": builds_left,
		"to_act": players_to_act(),
		"first_finisher": first_finisher,
		"hand": [],
		"my_pick": null,
		"finished": finished,
		"final_scores": final_scores.duplicate(true),
	}
	if seat >= 0 and seat < players.size():
		view["hand"] = hands[seat].duplicate()
		if picks.has(seat):
			view["my_pick"] = picks[seat].duplicate()
	return view


# --- Validación -------------------------------------------------------------------

func validate(action: GameAction) -> String:
	var pid := action.player_id
	if pid < 0 or pid >= players.size():
		return "Jugador desconocido"
	if not pid in players_to_act():
		return "No te toca"
	match action.type:
		PICK:
			if phase != Phase.PICK:
				return "Ahora no se eligen cargos"
			var office := int(action.data.get("office", -1))
			if office < 0 or office >= D.OFFICE_COUNT:
				return "Cargo no válido"
			var bid := int(action.data.get("bid", -1))
			if bid < 0 or bid > coins[pid]:
				return "Puja no válida"
		REASSIGN:
			if phase != Phase.REASSIGN:
				return "Ahora no se eligen vacantes"
			var office := int(action.data.get("office", -1))
			if not office in vacant_offices():
				return "Ese cargo no está vacante"
		INCOME:
			if phase != Phase.TURN:
				return "Ahora no se cobra"
			if income_taken:
				return "Ya has cobrado este turno"
			match int(action.data.get("kind", -1)):
				Income.COINS:
					pass
				Income.DOCK:
					var index := int(action.data.get("index", -1))
					if index < 0 or index >= dock.size():
						return "Carta del muelle no válida"
				Income.BLIND:
					if deck.is_empty() and discard.is_empty():
						return "No quedan cartas"
				_:
					return "Forma de cobrar no válida"
		ABILITY:
			if phase != Phase.TURN:
				return "Ahora no se usan cargos"
			if ability_used:
				return "Ya has usado tu cargo"
			return _validate_ability(pid, action.data)
		BUILD:
			if phase != Phase.TURN:
				return "Ahora no se construye"
			if not income_taken:
				return "Primero tienes que cobrar"
			if builds_left <= 0:
				return "No puedes construir más este turno"
			var index := int(action.data.get("card", -1))
			if index < 0 or index >= hands[pid].size():
				return "Carta no válida"
			if not int(action.data.get("cell", -1)) in buildable_cells(pid):
				return "No se puede construir en esa casilla"
			if build_cost(pid, hands[pid][index]) > coins[pid]:
				return "No tienes monedas suficientes"
		END_TURN:
			if phase != Phase.TURN:
				return "Ahora no hay turnos"
			if not income_taken:
				return "Primero tienes que cobrar"
		_:
			return "Acción no soportada: %s" % action.type
	return ""


func _validate_ability(pid: int, data: Dictionary) -> String:
	match turn_office:
		Office.HARBOR:
			var index := int(data.get("index", -1))
			if index < 0 or index >= dock.size():
				return "Carta del muelle no válida"
		Office.SMUGGLER:
			if not int(data.get("target", -1)) in smuggler_targets(pid):
				return "Ese jugador no tiene cartas"
		Office.COLLECTOR, Office.PATRON:
			pass
		Office.PLANNER:
			var move := [int(data.get("from", -1)), int(data.get("to", -1))]
			if not move in planner_moves(pid):
				return "Traslado no válido"
		_:
			return "Este cargo no tiene habilidad que usar"
	return ""


func get_legal_actions(pid: int) -> Array[GameAction]:
	var result: Array[GameAction] = []
	if finished or not pid in players_to_act():
		return result
	match phase:
		Phase.PICK:
			for o in D.OFFICE_COUNT:
				for bid in coins[pid] + 1:
					result.append(GameAction.new(PICK, pid, {"office": o, "bid": bid}))
		Phase.REASSIGN:
			for o in vacant_offices():
				result.append(GameAction.new(REASSIGN, pid, {"office": o}))
		Phase.TURN:
			if not income_taken:
				result.append(GameAction.new(INCOME, pid, {"kind": Income.COINS}))
				for i in dock.size():
					result.append(GameAction.new(INCOME, pid, {"kind": Income.DOCK, "index": i}))
				if not (deck.is_empty() and discard.is_empty()):
					result.append(GameAction.new(INCOME, pid, {"kind": Income.BLIND}))
			if not ability_used:
				match turn_office:
					Office.HARBOR:
						for i in dock.size():
							result.append(GameAction.new(ABILITY, pid, {"index": i}))
					Office.SMUGGLER:
						for t in smuggler_targets(pid):
							result.append(GameAction.new(ABILITY, pid, {"target": t}))
					Office.COLLECTOR, Office.PATRON:
						result.append(GameAction.new(ABILITY, pid, {}))
					Office.PLANNER:
						for move in planner_moves(pid):
							result.append(GameAction.new(ABILITY, pid, {"from": move[0], "to": move[1]}))
			if income_taken:
				if builds_left > 0:
					var cells := buildable_cells(pid)
					for i in hands[pid].size():
						if build_cost(pid, hands[pid][i]) > coins[pid]:
							continue
						for cell in cells:
							result.append(GameAction.new(BUILD, pid, {"card": i, "cell": cell}))
				result.append(GameAction.new(END_TURN, pid, {}))
	return result


# --- Aplicar acciones ---------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	match action.type:
		PICK:
			picks[pid] = {"office": int(action.data["office"]), "bid": int(action.data["bid"])}
			event.emit(&"picked", {"player": pid})
			if picks.size() == players.size():
				_resolve_picks()
		REASSIGN:
			var office := int(action.data["office"])
			_assign(pid, office)
			reassign_queue.pop_front()
			event.emit(&"reassigned", {"player": pid, "office": office})
			if reassign_queue.is_empty():
				_start_turns()
			else:
				turns.current = reassign_queue[0]
		INCOME:
			_income(pid, action.data)
		ABILITY:
			ability_used = true
			_ability(pid, action.data)
		BUILD:
			var index := int(action.data["card"])
			var cell := int(action.data["cell"])
			var card: int = hands[pid][index]
			var cost := build_cost(pid, card)
			coins[pid] -= cost
			hands[pid].remove_at(index)
			districts[pid][cell] = card
			builds_left -= 1
			event.emit(&"built", {"player": pid, "card": card, "cell": cell, "cost": cost})
			if first_finisher < 0 and building_count(pid) >= D.BUILDINGS_TO_END:
				first_finisher = pid
				event.emit(&"district_complete", {"player": pid})
		END_TURN:
			_next_turn()


func _begin_round() -> void:
	phase = Phase.PICK
	picks.clear()
	reassign_queue.clear()
	turn_office = -1
	for pid in players.size():
		office_of[pid] = -1
	for o in D.OFFICE_COUNT:
		holder[o] = -1
	turns.current = vara
	event.emit(&"new_round", {"round": round_number, "vara": vara})


## Todos han elegido: se revelan las elecciones y se resuelven las pujas.
func _resolve_picks() -> void:
	last_reveal.clear()
	var losers: Array[int] = []
	var order := initiative_order()
	for o in D.OFFICE_COUNT:
		var winner := -1
		for pid in order:
			if picks[pid]["office"] != o:
				continue
			if winner < 0 or picks[pid]["bid"] > picks[winner]["bid"]:
				winner = pid
		if winner < 0:
			continue
		var bid: int = picks[winner]["bid"]
		coins[winner] -= bid
		_assign(winner, o)
		for pid in order:
			if picks[pid]["office"] == o:
				last_reveal.append({"player": pid, "office": o, "bid": picks[pid]["bid"], "won": pid == winner})
				if pid != winner:
					losers.append(pid)
	# Los que pierden eligen vacante por orden de iniciativa.
	for pid in order:
		if pid in losers:
			reassign_queue.append(pid)
	picks.clear()
	event.emit(&"picks_revealed", {"reveal": last_reveal.duplicate(true)})
	if reassign_queue.is_empty():
		_start_turns()
	else:
		phase = Phase.REASSIGN
		turns.current = reassign_queue[0]


func _assign(pid: int, office: int) -> void:
	office_of[pid] = office
	holder[office] = pid


## Cobran las monedas acumuladas los cargos ocupados y suben los vacantes.
func _start_turns() -> void:
	for o in D.OFFICE_COUNT:
		if holder[o] >= 0:
			if vacant_coins[o] > 0:
				coins[holder[o]] += vacant_coins[o]
				event.emit(&"vacant_coins", {"player": holder[o], "office": o, "coins": vacant_coins[o]})
			vacant_coins[o] = 0
		else:
			vacant_coins[o] = mini(vacant_coins[o] + 1, D.MAX_VACANT_COINS)
	phase = Phase.TURN
	turn_office = -1
	_next_turn()


func _next_turn() -> void:
	var o := turn_office + 1
	while o < D.OFFICE_COUNT and holder[o] < 0:
		o += 1
	if o >= D.OFFICE_COUNT:
		_end_round()
		return
	turn_office = o
	var pid := holder[o]
	turns.current = pid
	income_taken = false
	ability_used = not o in D.ACTIVE_OFFICES
	builds_left = 2 if o == Office.BUILDER else 1
	event.emit(&"turn", {"player": pid, "office": o})
	if o == Office.MAYOR:
		vara = pid
		var card := _draw()
		if card >= 0:
			hands[pid].append(card)
		coins[pid] += D.MAYOR_COINS
		event.emit(&"mayor", {"player": pid, "drew": card >= 0, "coins": D.MAYOR_COINS})


func _income(pid: int, data: Dictionary) -> void:
	income_taken = true
	match int(data["kind"]):
		Income.COINS:
			var amount := D.COIN_INCOME + (1 if has_wonder(pid, Wonder.CUSTOMS) else 0)
			coins[pid] += amount
			event.emit(&"income", {"player": pid, "kind": Income.COINS, "coins": amount})
		Income.DOCK:
			var card: int = dock[int(data["index"])]
			dock.remove_at(int(data["index"]))
			hands[pid].append(card)
			var extra := -1
			if has_wonder(pid, Wonder.SHIPYARD_ROYAL):
				extra = _draw()
				if extra >= 0:
					hands[pid].append(extra)
			_refill_dock()
			event.emit(&"income", {"player": pid, "kind": Income.DOCK, "card": card, "extra": extra >= 0})
		Income.BLIND:
			var card := _draw()
			if card >= 0:
				hands[pid].append(card)
			coins[pid] += 1
			event.emit(&"income", {"player": pid, "kind": Income.BLIND, "coins": 1})


func _ability(pid: int, data: Dictionary) -> void:
	match turn_office:
		Office.HARBOR:
			var card: int = dock[int(data["index"])]
			dock.remove_at(int(data["index"]))
			hands[pid].append(card)
			discard.append_array(dock)
			dock.clear()
			_refill_dock()
			event.emit(&"harbor", {"player": pid, "card": card})
		Office.SMUGGLER:
			var target := int(data["target"])
			var index := rng.randi_range(0, hands[target].size() - 1)
			var card: int = hands[target][index]
			hands[target].remove_at(index)
			hands[pid].append(card)
			event.emit(&"smuggled", {"player": pid, "target": target})
		Office.COLLECTOR:
			var mine := coins[pid]
			var payers: Array[int] = []
			for other in players.size():
				if other != pid and coins[other] > mine:
					coins[other] -= 1
					coins[pid] += 1
					payers.append(other)
			event.emit(&"collected", {"player": pid, "payers": payers})
		Office.PLANNER:
			var from := int(data["from"])
			var to := int(data["to"])
			districts[pid][to] = districts[pid][from]
			districts[pid][from] = D.EMPTY
			event.emit(&"moved", {"player": pid, "from": from, "to": to})
		Office.PATRON:
			var amount := mini(D.group_count(districts[pid]), D.PATRON_MAX)
			coins[pid] += amount
			event.emit(&"patron", {"player": pid, "coins": amount})


func _end_round() -> void:
	for pid in players.size():
		if building_count(pid) >= D.BUILDINGS_TO_END:
			_finish_game()
			return
	round_number += 1
	_begin_round()


func _finish_game() -> void:
	phase = Phase.FINISHED
	turn_office = -1
	final_scores.clear()
	var best := -1
	var best_coins := -1
	var winners: Array[int] = []
	for pid in players.size():
		var s := score_of(pid)
		final_scores.append(s)
		var total: int = s["total"]
		if total > best or (total == best and coins[pid] > best_coins):
			best = total
			best_coins = coins[pid]
			winners.clear()
			winners.append(pid)
		elif total == best and coins[pid] == best_coins:
			winners.append(pid)
	event.emit(&"game_over", {"scores": final_scores.duplicate(true), "winners": winners.duplicate()})
	finish(winners)


## Roba la carta de arriba del mazo (barajando los descartes si se acaba).
## Devuelve -1 si no quedan cartas.
func _draw() -> int:
	if deck.is_empty():
		if discard.is_empty():
			return -1
		deck.append_array(discard)
		discard.clear()
		rng.shuffle(deck)
		event.emit(&"reshuffle", {"count": deck.size()})
	return deck.pop_back()


func _refill_dock() -> void:
	while dock.size() < D.DOCK_SIZE:
		var card := _draw()
		if card < 0:
			return
		dock.append(card)
