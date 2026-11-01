class_name ArchipelagoGame
extends GameBase
## Lógica de una partida de Archipiélago.
##
## Fase 2 (reglas básicas):
##   - Colocación inicial en orden serpiente: cada jugador coloca un poblado
##     y un camino que salga de él; con el segundo poblado recibe un recurso
##     de cada casilla que toca.
##   - Turno: tirar los dados (producción), y luego construir caminos,
##     poblados y ciudades, comerciar con la banca (4:1 o mejor con puertos)
##     y terminar el turno.
##   - Gana quien llega a `victory_points_target` puntos en su turno.
## Pendiente (fase 3): el 7 y el bandido, cartas de desarrollo, camino más
## largo, ejército más grande y comercio entre jugadores.

signal event(kind: StringName, data: Dictionary)

enum Phase { SETUP, ROLL, MAIN, FINISHED }
enum Building { NONE, SETTLEMENT, CITY }

const ROLL := &"roll_dice"
const BUILD_ROAD := &"build_road"
const BUILD_SETTLEMENT := &"build_settlement"
const BUILD_CITY := &"build_city"
const TRADE_BANK := &"trade_bank"
const END_TURN := &"end_turn"

## Coste de cada construcción, indexado por ArchDefs.ResourceType
## (madera, ladrillo, lana, trigo, mineral).
const COSTS := {
	BUILD_ROAD: [1, 1, 0, 0, 0],
	BUILD_SETTLEMENT: [1, 1, 1, 1, 0],
	BUILD_CITY: [0, 0, 0, 2, 3],
}
## Piezas de cada jugador al empezar.
const PIECES := {"road": 15, "settlement": 5, "city": 4}
## Cartas de cada recurso en la banca.
const BANK_STOCK := 19
const RESOURCE_COUNT := 5
const BANK_RATIO := 4

var board: ArchBoard
var phase: Phase = Phase.SETUP
var victory_points_target := 10

## Por vértice: jugador propietario (-1 = libre) y tipo de edificio.
var vertex_owner: Array[int] = []
var vertex_building: Array[int] = []
## Por arista: jugador propietario del camino (-1 = libre).
var edge_owner: Array[int] = []
## Por jugador: cartas de cada recurso (Array[int] de 5).
var hands: Array = []
## Cartas de cada recurso que quedan en la banca.
var bank: Array[int] = []
## Por jugador: piezas que le quedan {"road", "settlement", "city"}.
var pieces: Array[Dictionary] = []
## Última tirada de dados ([] si aún no se ha tirado).
var last_roll: Array[int] = []
## Durante la colocación: poblado recién colocado que espera su camino.
var setup_vertex := -1


func _on_setup() -> void:
	board = ArchBoardGenerator.generate(rng)
	var grid := board.grid
	vertex_owner.assign(_filled(grid.vertex_count(), -1))
	vertex_building.assign(_filled(grid.vertex_count(), Building.NONE))
	edge_owner.assign(_filled(grid.edge_count(), -1))
	hands.clear()
	pieces.clear()
	for p in players.size():
		var hand: Array[int] = []
		hand.assign(_filled(RESOURCE_COUNT, 0))
		hands.append(hand)
		pieces.append(PIECES.duplicate())
	bank.assign(_filled(RESOURCE_COUNT, BANK_STOCK))
	last_roll.clear()
	setup_vertex = -1
	phase = Phase.SETUP
	turns.begin_sequence(TurnManager.snake_order(players.size()))


# --- Consultas (las usa la interfaz y la IA) -------------------------------

func victory_points(pid: int) -> int:
	var points := 0
	for v in vertex_owner.size():
		if vertex_owner[v] == pid:
			points += 1 if vertex_building[v] == Building.SETTLEMENT else 2
	return points


func hand_size(pid: int) -> int:
	var total := 0
	for n in hands[pid]:
		total += n
	return total


func can_afford(pid: int, cost: Array) -> bool:
	for r in RESOURCE_COUNT:
		if hands[pid][r] < cost[r]:
			return false
	return true


## Cuántas cartas de `resource` pide la banca por una (4, 3 o 2 con puertos).
func trade_ratio(pid: int, resource: int) -> int:
	var ratio := BANK_RATIO
	for v in vertex_owner.size():
		if vertex_owner[v] != pid:
			continue
		var port = board.vertex_port(v)
		if port == null:
			continue
		if port["type"] == ArchDefs.PORT_GENERIC:
			ratio = mini(ratio, 3)
		elif port["type"] == resource:
			ratio = mini(ratio, 2)
	return ratio


## "" si el jugador puede poner un poblado en `v` (sin contar el coste).
func settlement_spot_error(pid: int, v: int) -> String:
	if vertex_owner[v] != -1:
		return "Ese vértice ya está ocupado"
	for n in board.grid.vertex_neighbors[v]:
		if vertex_owner[n] != -1:
			return "Demasiado cerca de otro edificio"
	if phase == Phase.SETUP:
		return "" if setup_vertex == -1 else "Ahora toca colocar un camino"
	for e in board.grid.vertex_edges[v]:
		if edge_owner[e] == pid:
			return ""
	return "El poblado debe tocar uno de tus caminos"


## "" si el jugador puede poner un camino en `e` (sin contar el coste).
func road_spot_error(pid: int, e: int) -> String:
	if edge_owner[e] != -1:
		return "Ya hay un camino ahí"
	var ends: Array = board.grid.edge_vertices[e]
	if phase == Phase.SETUP:
		if setup_vertex == -1:
			return "Primero coloca un poblado"
		if not setup_vertex in ends:
			return "El camino debe salir del poblado que acabas de colocar"
		return ""
	for v in ends:
		if vertex_owner[v] == pid:
			return ""
		if vertex_owner[v] != -1:
			continue  # un edificio rival corta la conexión por ese extremo
		for other in board.grid.vertex_edges[v]:
			if other != e and edge_owner[other] == pid:
				return ""
	return "El camino debe conectar con tus caminos o edificios"


func city_spot_error(pid: int, v: int) -> String:
	if vertex_owner[v] != pid or vertex_building[v] != Building.SETTLEMENT:
		return "Solo puedes mejorar tus propios poblados"
	return ""


func legal_settlement_vertices(pid: int) -> Array[int]:
	var result: Array[int] = []
	for v in vertex_owner.size():
		if settlement_spot_error(pid, v) == "":
			result.append(v)
	return result


func legal_road_edges(pid: int) -> Array[int]:
	var result: Array[int] = []
	for e in edge_owner.size():
		if road_spot_error(pid, e) == "":
			result.append(e)
	return result


func legal_city_vertices(pid: int) -> Array[int]:
	var result: Array[int] = []
	for v in vertex_owner.size():
		if city_spot_error(pid, v) == "":
			result.append(v)
	return result


## "" si el jugador actual puede construir `type` en algún sitio ahora mismo
## (fase, piezas, recursos y hueco legal).
func build_error(pid: int, type: StringName) -> String:
	if phase != Phase.MAIN:
		return "Ahora no se puede construir"
	var piece := _piece_name(type)
	if pieces[pid][piece] <= 0:
		return "No te quedan piezas"
	if not can_afford(pid, COSTS[type]):
		return "No tienes recursos suficientes"
	var spots: Array[int]
	match type:
		BUILD_ROAD: spots = legal_road_edges(pid)
		BUILD_SETTLEMENT: spots = legal_settlement_vertices(pid)
		BUILD_CITY: spots = legal_city_vertices(pid)
	return "" if not spots.is_empty() else "No hay ningún sitio válido"


# --- Validación --------------------------------------------------------------

func validate(action: GameAction) -> String:
	if action.player_id != turns.current:
		return "No es tu turno"
	var pid := action.player_id
	if phase == Phase.SETUP and not action.type in [BUILD_SETTLEMENT, BUILD_ROAD]:
		return "Primero termina la colocación inicial"
	match action.type:
		ROLL:
			return "" if phase == Phase.ROLL else "Ahora no se pueden tirar los dados"
		BUILD_SETTLEMENT:
			var v := int(action.data.get("vertex", -1))
			if v < 0 or v >= vertex_owner.size():
				return "Vértice no válido"
			return _first_error([_main_build_error(pid, action.type), settlement_spot_error(pid, v)])
		BUILD_ROAD:
			var e := int(action.data.get("edge", -1))
			if e < 0 or e >= edge_owner.size():
				return "Arista no válida"
			return _first_error([_main_build_error(pid, action.type), road_spot_error(pid, e)])
		BUILD_CITY:
			var v := int(action.data.get("vertex", -1))
			if v < 0 or v >= vertex_owner.size():
				return "Vértice no válido"
			return _first_error([_main_build_error(pid, action.type), city_spot_error(pid, v)])
		TRADE_BANK:
			if phase != Phase.MAIN:
				return "Primero tira los dados"
			var give := int(action.data.get("give", -1))
			var receive := int(action.data.get("receive", -1))
			if give < 0 or give >= RESOURCE_COUNT or receive < 0 or receive >= RESOURCE_COUNT:
				return "Recurso no válido"
			if give == receive:
				return "Elige dos recursos distintos"
			if hands[pid][give] < trade_ratio(pid, give):
				return "Necesitas %d de %s" % [trade_ratio(pid, give), ArchDefs.RESOURCE_NAMES[give]]
			if bank[receive] <= 0:
				return "La banca no tiene %s" % ArchDefs.RESOURCE_NAMES[receive]
			return ""
		END_TURN:
			return "" if phase == Phase.MAIN else "Primero tira los dados"
	return "Acción desconocida: %s" % action.type


## En la colocación inicial construir es gratis; en el turno normal hay que
## haber tirado, tener la pieza y pagar.
func _main_build_error(pid: int, type: StringName) -> String:
	if phase == Phase.SETUP:
		if type == BUILD_CITY:
			return "Primero termina la colocación inicial"
		return ""
	if phase != Phase.MAIN:
		return "Primero tira los dados"
	if pieces[pid][_piece_name(type)] <= 0:
		return "No te quedan piezas"
	if not can_afford(pid, COSTS[type]):
		return "No tienes recursos suficientes"
	return ""


# --- Aplicación --------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	match action.type:
		ROLL:
			last_roll = rng.roll_dice(2)
			action.data["dice"] = last_roll.duplicate()
			var total := last_roll[0] + last_roll[1]
			if total == 7:
				event.emit(&"seven", {"player": pid})
			else:
				_produce(total)
			phase = Phase.MAIN
		BUILD_SETTLEMENT:
			var v: int = action.data["vertex"]
			vertex_owner[v] = pid
			vertex_building[v] = Building.SETTLEMENT
			pieces[pid]["settlement"] -= 1
			if phase == Phase.SETUP:
				setup_vertex = v
				if _settlement_count(pid) == 2:
					_give_setup_resources(pid, v)
			else:
				_pay(pid, COSTS[BUILD_SETTLEMENT])
				_check_victory(pid)
		BUILD_ROAD:
			var e: int = action.data["edge"]
			edge_owner[e] = pid
			pieces[pid]["road"] -= 1
			if phase == Phase.SETUP:
				setup_vertex = -1
				turns.next()
				if not turns.in_sequence():
					phase = Phase.ROLL
			else:
				_pay(pid, COSTS[BUILD_ROAD])
		BUILD_CITY:
			var v: int = action.data["vertex"]
			vertex_building[v] = Building.CITY
			pieces[pid]["city"] -= 1
			pieces[pid]["settlement"] += 1
			_pay(pid, COSTS[BUILD_CITY])
			_check_victory(pid)
		TRADE_BANK:
			var give: int = action.data["give"]
			var receive: int = action.data["receive"]
			var ratio := trade_ratio(pid, give)
			action.data["ratio"] = ratio
			hands[pid][give] -= ratio
			bank[give] += ratio
			hands[pid][receive] += 1
			bank[receive] -= 1
		END_TURN:
			turns.next()
			phase = Phase.ROLL


## Reparte los recursos de una tirada. Si la banca no tiene bastante de un
## recurso para todos, nadie recibe ese recurso.
func _produce(number: int) -> void:
	var gains: Array = []
	for p in players.size():
		var g: Array[int] = []
		g.assign(_filled(RESOURCE_COUNT, 0))
		gains.append(g)
	for t in board.tiles_with_number(number):
		if t == board.bandit_tile:
			continue
		var resource := board.tile_resource(t)
		for v in board.grid.tile_vertices[t]:
			var owner := vertex_owner[v]
			if owner != -1:
				gains[owner][resource] += 1 if vertex_building[v] == Building.SETTLEMENT else 2
	var shortages: Array[int] = []
	for r in RESOURCE_COUNT:
		var demand := 0
		for p in players.size():
			demand += gains[p][r]
		if demand > bank[r]:
			shortages.append(r)
			for p in players.size():
				gains[p][r] = 0
		else:
			bank[r] -= demand
			for p in players.size():
				hands[p][r] += gains[p][r]
	event.emit(&"production", {"number": number, "gains": gains, "shortages": shortages})


func _give_setup_resources(pid: int, v: int) -> void:
	var gains: Array[int] = []
	gains.assign(_filled(RESOURCE_COUNT, 0))
	for t in board.grid.vertex_tiles[v]:
		var resource := board.tile_resource(t)
		if resource >= 0 and bank[resource] > 0:
			gains[resource] += 1
			bank[resource] -= 1
			hands[pid][resource] += 1
	event.emit(&"setup_resources", {"player": pid, "gains": gains})


func _pay(pid: int, cost: Array) -> void:
	for r in RESOURCE_COUNT:
		hands[pid][r] -= cost[r]
		bank[r] += cost[r]


func _check_victory(pid: int) -> void:
	if victory_points(pid) >= victory_points_target:
		phase = Phase.FINISHED
		var winners: Array[int] = [pid]
		finish(winners)


func _settlement_count(pid: int) -> int:
	var count := 0
	for v in vertex_owner.size():
		if vertex_owner[v] == pid:
			count += 1
	return count


# --- Acciones legales ---------------------------------------------------------

func get_legal_actions(pid: int) -> Array[GameAction]:
	var result: Array[GameAction] = []
	if finished or pid != turns.current:
		return result
	match phase:
		Phase.SETUP:
			if setup_vertex == -1:
				for v in legal_settlement_vertices(pid):
					result.append(GameAction.new(BUILD_SETTLEMENT, pid, {"vertex": v}))
			else:
				for e in legal_road_edges(pid):
					result.append(GameAction.new(BUILD_ROAD, pid, {"edge": e}))
		Phase.ROLL:
			result.append(GameAction.new(ROLL, pid))
		Phase.MAIN:
			if build_error(pid, BUILD_CITY) == "":
				for v in legal_city_vertices(pid):
					result.append(GameAction.new(BUILD_CITY, pid, {"vertex": v}))
			if build_error(pid, BUILD_SETTLEMENT) == "":
				for v in legal_settlement_vertices(pid):
					result.append(GameAction.new(BUILD_SETTLEMENT, pid, {"vertex": v}))
			if build_error(pid, BUILD_ROAD) == "":
				for e in legal_road_edges(pid):
					result.append(GameAction.new(BUILD_ROAD, pid, {"edge": e}))
			for give in RESOURCE_COUNT:
				if hands[pid][give] < trade_ratio(pid, give):
					continue
				for receive in RESOURCE_COUNT:
					if receive != give and bank[receive] > 0:
						result.append(GameAction.new(TRADE_BANK, pid, {"give": give, "receive": receive}))
			result.append(GameAction.new(END_TURN, pid))
	return result


# --- Utilidades ----------------------------------------------------------------

static func format_resources(amounts: Array) -> String:
	var parts: Array[String] = []
	for r in amounts.size():
		if amounts[r] > 0:
			parts.append("%d %s" % [amounts[r], ArchDefs.RESOURCE_NAMES[r]])
	return ", ".join(parts)


static func _piece_name(type: StringName) -> String:
	match type:
		BUILD_ROAD: return "road"
		BUILD_SETTLEMENT: return "settlement"
		_: return "city"


static func _first_error(errors: Array) -> String:
	for e in errors:
		if e != "":
			return e
	return ""


static func _filled(count: int, value: Variant) -> Array:
	var a := []
	a.resize(count)
	a.fill(value)
	return a
