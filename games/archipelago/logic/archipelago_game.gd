class_name ArchipelagoGame
extends GameBase
## Lógica de una partida de Archipiélago.
##
## Flujo de un turno:
##   SETUP          colocación inicial en serpiente (poblado + camino).
##   ROLL           tirar los dados (antes se puede jugar un Miliciano).
##   DISCARD        tras un 7: quien tenga más de 7 cartas descarta la mitad.
##   ROBBER         mover el bandido y robar una carta a un vecino.
##   MAIN           construir, comprar y jugar cartas de desarrollo,
##                  comerciar con la banca o con otros jugadores, terminar.
##   ROAD_BUILDING  colocar los caminos gratis de la carta Ingenieros.
##   FINISHED       alguien llegó a `victory_points_target` en su turno.
##
## Algunas acciones las hace un jugador que no tiene el turno: los descartes
## y la respuesta a una oferta de intercambio. players_to_act() dice quién
## debe actuar en cada momento.

signal event(kind: StringName, data: Dictionary)

enum Phase { SETUP, ROLL, DISCARD, ROBBER, MAIN, ROAD_BUILDING, FINISHED }
enum Building { NONE, SETTLEMENT, CITY }

const ROLL := &"roll_dice"
const BUILD_ROAD := &"build_road"
const BUILD_SETTLEMENT := &"build_settlement"
const BUILD_CITY := &"build_city"
const TRADE_BANK := &"trade_bank"
const END_TURN := &"end_turn"
const DISCARD := &"discard"                 # {"cards": [5]}
const MOVE_BANDIT := &"move_bandit"         # {"tile": int, "victim": int (-1 = nadie)}
const BUY_DEV := &"buy_dev_card"
const PLAY_DEV := &"play_dev_card"          # {"card": DevCard, "resources": [r, r] | "resource": r}
const OFFER_TRADE := &"offer_trade"         # {"to": pid, "give": [5], "receive": [5]}
const ACCEPT_TRADE := &"accept_trade"
const REJECT_TRADE := &"reject_trade"       # también la usa quien ofrece para cancelar

## Coste de cada compra, indexado por ArchDefs.ResourceType
## (madera, ladrillo, lana, trigo, mineral).
const COSTS := {
	BUILD_ROAD: [1, 1, 0, 0, 0],
	BUILD_SETTLEMENT: [1, 1, 1, 1, 0],
	BUILD_CITY: [0, 0, 0, 2, 3],
	BUY_DEV: [0, 0, 1, 1, 1],
}
## Acciones permitidas en cada fase.
const PHASE_ACTIONS := {
	Phase.SETUP: [BUILD_SETTLEMENT, BUILD_ROAD],
	Phase.ROLL: [ROLL, PLAY_DEV],
	Phase.DISCARD: [DISCARD],
	Phase.ROBBER: [MOVE_BANDIT],
	Phase.MAIN: [BUILD_ROAD, BUILD_SETTLEMENT, BUILD_CITY, TRADE_BANK, BUY_DEV, PLAY_DEV, OFFER_TRADE, END_TURN],
	Phase.ROAD_BUILDING: [BUILD_ROAD],
	Phase.FINISHED: [],
}
## Piezas de cada jugador al empezar.
const PIECES := {"road": 15, "settlement": 5, "city": 4}
const BANK_STOCK := 19
const RESOURCE_COUNT := 5
const DEV_TYPES := 5
const BANK_RATIO := 4
## Con más de estas cartas, un 7 obliga a descartar la mitad.
const DISCARD_LIMIT := 7
const LONGEST_ROAD_MIN := 5
const LARGEST_ARMY_MIN := 3
const AWARD_POINTS := 2
const FREE_ROADS := 2

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

## Mazo de cartas de desarrollo (se roba del final).
var dev_deck: Array[int] = []
## Por jugador: cartas de desarrollo en la mano, por tipo (Array[int] de 5).
var dev_hands: Array = []
## Por jugador: cartas compradas este turno (aún no se pueden jugar).
var dev_new: Array = []
var dev_played_this_turn := false
## Por jugador: Milicianos jugados.
var militia_played: Array[int] = []
## Por jugador: longitud de su camino más largo.
var road_lengths: Array[int] = []
var longest_road_owner := -1
var largest_army_owner := -1

## Tras un 7: jugador -> cartas que debe descartar.
var pending_discards: Dictionary = {}
## Caminos gratis pendientes (carta Ingenieros).
var free_roads := 0
## Oferta pendiente: {"from", "to", "give": [5], "receive": [5]} o {}.
var trade_offer: Dictionary = {}
## Fase a la que se vuelve tras mover el bandido.
var _after_robber: Phase = Phase.MAIN


func _on_setup() -> void:
	board = ArchBoardGenerator.generate(rng)
	var grid := board.grid
	vertex_owner.assign(_filled(grid.vertex_count(), -1))
	vertex_building.assign(_filled(grid.vertex_count(), Building.NONE))
	edge_owner.assign(_filled(grid.edge_count(), -1))
	hands.clear()
	pieces.clear()
	dev_hands.clear()
	dev_new.clear()
	for p in players.size():
		hands.append(_zeros())
		dev_hands.append(_dev_zeros())
		dev_new.append(_dev_zeros())
		pieces.append(PIECES.duplicate())
	bank.assign(_filled(RESOURCE_COUNT, BANK_STOCK))
	dev_deck = ArchDefs.dev_deck()
	rng.shuffle(dev_deck)
	militia_played.assign(_filled(players.size(), 0))
	road_lengths.assign(_filled(players.size(), 0))
	longest_road_owner = -1
	largest_army_owner = -1
	pending_discards.clear()
	free_roads = 0
	trade_offer.clear()
	dev_played_this_turn = false
	last_roll.clear()
	setup_vertex = -1
	phase = Phase.SETUP
	turns.begin_sequence(TurnManager.snake_order(players.size()))


# --- Consultas (las usa la interfaz y la IA) -------------------------------

## Jugadores que deben actuar ahora (normalmente solo el del turno).
func players_to_act() -> Array[int]:
	var result: Array[int] = []
	if phase == Phase.FINISHED:
		return result
	if phase == Phase.DISCARD:
		for pid in pending_discards:
			result.append(pid)
		result.sort()
		return result
	if not trade_offer.is_empty():
		result.append(trade_offer["to"])
		return result
	result.append(turns.current)
	return result


## Puntos totales, incluidos los Monumentos ocultos.
func victory_points(pid: int) -> int:
	return public_victory_points(pid) + dev_hands[pid][ArchDefs.DevCard.MONUMENT]


## Puntos que ven los demás jugadores (sin Monumentos).
func public_victory_points(pid: int) -> int:
	var points := 0
	for v in vertex_owner.size():
		if vertex_owner[v] == pid:
			points += 1 if vertex_building[v] == Building.SETTLEMENT else 2
	if longest_road_owner == pid:
		points += AWARD_POINTS
	if largest_army_owner == pid:
		points += AWARD_POINTS
	return points


func hand_size(pid: int) -> int:
	return _sum(hands[pid])


func dev_hand_size(pid: int) -> int:
	return _sum(dev_hands[pid])


## Cartas de un tipo que el jugador puede jugar (no compradas este turno).
func playable_dev(pid: int, card: int) -> int:
	return dev_hands[pid][card] - dev_new[pid][card]


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


## Jugadores a los que se puede robar poniendo el bandido en `tile`.
func bandit_victims(pid: int, tile: int) -> Array[int]:
	var result: Array[int] = []
	for v in board.grid.tile_vertices[tile]:
		var owner := vertex_owner[v]
		if owner != -1 and owner != pid and not owner in result and hand_size(owner) > 0:
			result.append(owner)
	result.sort()
	return result


## Casillas a las que se puede mover el bandido.
func bandit_tiles() -> Array[int]:
	var result: Array[int] = []
	for t in board.grid.tile_count():
		if t != board.bandit_tile:
			result.append(t)
	return result


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


## "" si el jugador puede construir `type` en algún sitio ahora mismo
## (fase, piezas, recursos y hueco legal).
func build_error(pid: int, type: StringName) -> String:
	if phase != Phase.MAIN or not trade_offer.is_empty():
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


## Longitud del camino continuo más largo del jugador. Los edificios rivales
## cortan el camino.
func longest_road_length(pid: int) -> int:
	var best := 0
	var starts := {}
	for e in edge_owner.size():
		if edge_owner[e] == pid:
			for v in board.grid.edge_vertices[e]:
				starts[v] = true
	for v in starts:
		best = maxi(best, _road_dfs(pid, v, {}, true))
	return best


func _road_dfs(pid: int, v: int, used: Dictionary, is_start: bool) -> int:
	if not is_start and vertex_owner[v] != -1 and vertex_owner[v] != pid:
		return 0
	var best := 0
	for e in board.grid.vertex_edges[v]:
		if edge_owner[e] != pid or used.has(e):
			continue
		used[e] = true
		var ends: Array = board.grid.edge_vertices[e]
		var other: int = ends[1] if ends[0] == v else ends[0]
		best = maxi(best, 1 + _road_dfs(pid, other, used, false))
		used.erase(e)
	return best


# --- Validación --------------------------------------------------------------

func validate(action: GameAction) -> String:
	var pid := action.player_id
	var type := action.type
	if phase == Phase.FINISHED:
		return "La partida ha terminado"

	# Oferta de intercambio pendiente: solo se puede responder o cancelar.
	if not trade_offer.is_empty():
		if type == REJECT_TRADE and pid in [trade_offer["from"], trade_offer["to"]]:
			return ""
		if type == ACCEPT_TRADE and pid == trade_offer["to"]:
			if not _has_cards(pid, trade_offer["receive"]):
				return "No tienes las cartas que te piden"
			if not _has_cards(trade_offer["from"], trade_offer["give"]):
				return "Quien ofrece ya no tiene esas cartas"
			return ""
		return "Hay una oferta de intercambio pendiente"
	if type in [ACCEPT_TRADE, REJECT_TRADE]:
		return "No hay ninguna oferta pendiente"

	if not pid in players_to_act():
		if phase == Phase.DISCARD:
			return "Esperando a que los demás descarten"
		return "No es tu turno"
	if not type in PHASE_ACTIONS[phase]:
		return _phase_hint()

	match type:
		ROLL:
			return ""
		BUILD_SETTLEMENT:
			var v := int(action.data.get("vertex", -1))
			if v < 0 or v >= vertex_owner.size():
				return "Vértice no válido"
			return _first_error([_purchase_error(pid, type), settlement_spot_error(pid, v)])
		BUILD_ROAD:
			var e := int(action.data.get("edge", -1))
			if e < 0 or e >= edge_owner.size():
				return "Arista no válida"
			return _first_error([_purchase_error(pid, type), road_spot_error(pid, e)])
		BUILD_CITY:
			var v := int(action.data.get("vertex", -1))
			if v < 0 or v >= vertex_owner.size():
				return "Vértice no válido"
			return _first_error([_purchase_error(pid, type), city_spot_error(pid, v)])
		TRADE_BANK:
			var give := int(action.data.get("give", -1))
			var receive := int(action.data.get("receive", -1))
			if not _valid_resource(give) or not _valid_resource(receive):
				return "Recurso no válido"
			if give == receive:
				return "Elige dos recursos distintos"
			if hands[pid][give] < trade_ratio(pid, give):
				return "Necesitas %d de %s" % [trade_ratio(pid, give), ArchDefs.RESOURCE_NAMES[give]]
			if bank[receive] <= 0:
				return "La banca no tiene %s" % ArchDefs.RESOURCE_NAMES[receive]
			return ""
		END_TURN:
			return ""
		DISCARD:
			var cards = action.data.get("cards")
			if not _valid_amounts(cards):
				return "Descarte no válido"
			if _sum(cards) != pending_discards[pid]:
				return "Debes descartar exactamente %d cartas" % pending_discards[pid]
			if not _has_cards(pid, cards):
				return "No tienes esas cartas"
			return ""
		MOVE_BANDIT:
			var t := int(action.data.get("tile", -1))
			if t < 0 or t >= board.grid.tile_count():
				return "Casilla no válida"
			if t == board.bandit_tile:
				return "El bandido debe cambiar de casilla"
			var victim := int(action.data.get("victim", -1))
			var victims := bandit_victims(pid, t)
			if victims.is_empty():
				return "" if victim == -1 else "No hay nadie a quien robar ahí"
			return "" if victim in victims else "Elige a quién robar"
		BUY_DEV:
			if dev_deck.is_empty():
				return "No quedan cartas de desarrollo"
			if not can_afford(pid, COSTS[BUY_DEV]):
				return "No tienes recursos suficientes"
			return ""
		PLAY_DEV:
			return _play_dev_error(pid, action.data)
		OFFER_TRADE:
			var to := int(action.data.get("to", -1))
			if to < 0 or to >= players.size() or to == pid:
				return "Elige con quién comerciar"
			var give = action.data.get("give")
			var receive = action.data.get("receive")
			if not _valid_amounts(give) or not _valid_amounts(receive):
				return "Oferta no válida"
			if _sum(give) == 0 or _sum(receive) == 0:
				return "Hay que dar y recibir al menos una carta"
			for r in RESOURCE_COUNT:
				if give[r] > 0 and receive[r] > 0:
					return "No puedes dar y pedir el mismo recurso"
			if not _has_cards(pid, give):
				return "No tienes las cartas que ofreces"
			return ""
	return "Acción desconocida: %s" % type


func _play_dev_error(pid: int, data: Dictionary) -> String:
	var card := int(data.get("card", -1))
	if card < 0 or card >= DEV_TYPES:
		return "Carta no válida"
	if card == ArchDefs.DevCard.MONUMENT:
		return "Los Monumentos no se juegan: ya cuentan como punto"
	if dev_played_this_turn:
		return "Solo puedes jugar una carta de desarrollo por turno"
	if dev_hands[pid][card] <= 0:
		return "No tienes esa carta"
	if playable_dev(pid, card) <= 0:
		return "No puedes jugar una carta el mismo turno que la compras"
	if phase == Phase.ROLL and card != ArchDefs.DevCard.MILITIA:
		return "Antes de tirar solo se puede jugar un Miliciano"
	match card:
		ArchDefs.DevCard.ROAD_BUILDING:
			if pieces[pid]["road"] <= 0 or legal_road_edges(pid).is_empty():
				return "No puedes construir más caminos"
		ArchDefs.DevCard.HARVEST:
			var res = data.get("resources")
			if not res is Array or res.size() != 2 or not _valid_resource(res[0]) or not _valid_resource(res[1]):
				return "Elige dos recursos"
			var wanted := _zeros()
			for r in res:
				wanted[r] += 1
			for r in RESOURCE_COUNT:
				if wanted[r] > bank[r]:
					return "La banca no tiene suficiente %s" % ArchDefs.RESOURCE_NAMES[r]
		ArchDefs.DevCard.MONOPOLY:
			if not _valid_resource(int(data.get("resource", -1))):
				return "Elige un recurso"
	return ""


## En la colocación inicial y con Ingenieros los caminos son gratis; si no,
## hay que tener la pieza y pagar.
func _purchase_error(pid: int, type: StringName) -> String:
	if pieces[pid][_piece_name(type)] <= 0:
		return "No te quedan piezas"
	if phase == Phase.SETUP or phase == Phase.ROAD_BUILDING:
		return ""
	if not can_afford(pid, COSTS[type]):
		return "No tienes recursos suficientes"
	return ""


func _phase_hint() -> String:
	match phase:
		Phase.SETUP: return "Primero termina la colocación inicial"
		Phase.ROLL: return "Primero tira los dados"
		Phase.DISCARD: return "Esperando a que se descarten cartas"
		Phase.ROBBER: return "Primero mueve el bandido"
		Phase.ROAD_BUILDING: return "Coloca primero tus caminos gratis"
	return "Ahora no puedes hacer eso"


# --- Aplicación --------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	var data := action.data
	match action.type:
		ROLL:
			last_roll = rng.roll_dice(2)
			data["dice"] = last_roll.duplicate()
			var total := last_roll[0] + last_roll[1]
			if total == 7:
				_start_seven()
			else:
				_produce(total)
				phase = Phase.MAIN
		BUILD_SETTLEMENT:
			var v: int = data["vertex"]
			vertex_owner[v] = pid
			vertex_building[v] = Building.SETTLEMENT
			pieces[pid]["settlement"] -= 1
			data["paid"] = phase != Phase.SETUP
			if phase == Phase.SETUP:
				setup_vertex = v
				if PIECES["settlement"] - pieces[pid]["settlement"] == 2:
					_give_setup_resources(pid, v)
			else:
				_pay(pid, COSTS[BUILD_SETTLEMENT])
				_update_longest_road()  # puede cortar el camino de un rival
		BUILD_ROAD:
			var e: int = data["edge"]
			edge_owner[e] = pid
			pieces[pid]["road"] -= 1
			data["paid"] = phase == Phase.MAIN
			match phase:
				Phase.SETUP:
					setup_vertex = -1
					turns.next()
					if not turns.in_sequence():
						phase = Phase.ROLL
				Phase.ROAD_BUILDING:
					free_roads -= 1
					if free_roads <= 0 or pieces[pid]["road"] <= 0 or legal_road_edges(pid).is_empty():
						free_roads = 0
						phase = Phase.MAIN
				_:
					_pay(pid, COSTS[BUILD_ROAD])
			if phase != Phase.SETUP:
				_update_longest_road()
		BUILD_CITY:
			var v: int = data["vertex"]
			vertex_building[v] = Building.CITY
			pieces[pid]["city"] -= 1
			pieces[pid]["settlement"] += 1
			_pay(pid, COSTS[BUILD_CITY])
		TRADE_BANK:
			var give: int = data["give"]
			var receive: int = data["receive"]
			var ratio := trade_ratio(pid, give)
			data["ratio"] = ratio
			hands[pid][give] -= ratio
			bank[give] += ratio
			hands[pid][receive] += 1
			bank[receive] -= 1
		END_TURN:
			dev_new[pid] = _dev_zeros()
			dev_played_this_turn = false
			turns.next()
			phase = Phase.ROLL
		DISCARD:
			var cards: Array = data["cards"]
			for r in RESOURCE_COUNT:
				hands[pid][r] -= cards[r]
				bank[r] += cards[r]
			pending_discards.erase(pid)
			if pending_discards.is_empty():
				phase = Phase.ROBBER
		MOVE_BANDIT:
			board.bandit_tile = data["tile"]
			var victim := int(data.get("victim", -1))
			data["stolen"] = -1
			if victim >= 0:
				var cards: Array[int] = []
				for r in RESOURCE_COUNT:
					for i in hands[victim][r]:
						cards.append(r)
				var r: int = rng.pick(cards)
				hands[victim][r] -= 1
				hands[pid][r] += 1
				data["stolen"] = r
			phase = _after_robber
		BUY_DEV:
			var card: int = dev_deck.pop_back()
			data["card"] = card
			dev_hands[pid][card] += 1
			dev_new[pid][card] += 1
			_pay(pid, COSTS[BUY_DEV])
		PLAY_DEV:
			_apply_dev(pid, data)
		OFFER_TRADE:
			trade_offer = {"from": pid, "to": int(data["to"]), "give": data["give"].duplicate(), "receive": data["receive"].duplicate()}
		ACCEPT_TRADE:
			var from: int = trade_offer["from"]
			for r in RESOURCE_COUNT:
				var give: int = trade_offer["give"][r]
				var receive: int = trade_offer["receive"][r]
				hands[from][r] += receive - give
				hands[pid][r] += give - receive
			data["offer"] = trade_offer.duplicate(true)
			trade_offer = {}
		REJECT_TRADE:
			data["offer"] = trade_offer.duplicate(true)
			trade_offer = {}
	if phase != Phase.SETUP and phase != Phase.FINISHED:
		_check_victory(turns.current)


func _apply_dev(pid: int, data: Dictionary) -> void:
	var card: int = data["card"]
	dev_hands[pid][card] -= 1
	dev_played_this_turn = true
	match card:
		ArchDefs.DevCard.MILITIA:
			militia_played[pid] += 1
			_update_largest_army()
			_after_robber = phase
			phase = Phase.ROBBER
		ArchDefs.DevCard.ROAD_BUILDING:
			free_roads = mini(FREE_ROADS, pieces[pid]["road"])
			phase = Phase.ROAD_BUILDING
		ArchDefs.DevCard.HARVEST:
			for r in data["resources"]:
				bank[r] -= 1
				hands[pid][r] += 1
		ArchDefs.DevCard.MONOPOLY:
			var r: int = data["resource"]
			var taken := 0
			for other in players.size():
				if other != pid:
					taken += hands[other][r]
					hands[other][r] = 0
			hands[pid][r] += taken
			data["taken"] = taken


func _start_seven() -> void:
	pending_discards.clear()
	for p in players.size():
		var n := hand_size(p)
		if n > DISCARD_LIMIT:
			@warning_ignore("integer_division")
			pending_discards[p] = n / 2
	_after_robber = Phase.MAIN
	phase = Phase.DISCARD if not pending_discards.is_empty() else Phase.ROBBER
	event.emit(&"seven", {"player": turns.current, "discards": pending_discards.duplicate()})


## Reparte los recursos de una tirada. Si la banca no tiene bastante de un
## recurso para todos, nadie recibe ese recurso.
func _produce(number: int) -> void:
	var gains: Array = []
	for p in players.size():
		gains.append(_zeros())
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
	var gains := _zeros()
	for t in board.grid.vertex_tiles[v]:
		var resource := board.tile_resource(t)
		if resource >= 0 and bank[resource] > 0:
			gains[resource] += 1
			bank[resource] -= 1
			hands[pid][resource] += 1
	event.emit(&"setup_resources", {"player": pid, "gains": gains, "vertex": v})


## Recalcula el Camino más largo. Quien lo tiene lo conserva en caso de
## empate; si lo pierde y hay empate entre los demás, no es de nadie.
func _update_longest_road() -> void:
	for p in players.size():
		road_lengths[p] = longest_road_length(p)
	var previous := longest_road_owner
	var best: int = road_lengths.max()
	var holder := longest_road_owner
	if holder != -1 and road_lengths[holder] >= LONGEST_ROAD_MIN and road_lengths[holder] == best:
		return
	longest_road_owner = -1
	if best >= LONGEST_ROAD_MIN and road_lengths.count(best) == 1:
		longest_road_owner = road_lengths.find(best)
	if longest_road_owner != previous:
		event.emit(&"longest_road", {"player": longest_road_owner, "previous": previous, "length": best})


## La Mayor milicia es de quien tenga al menos 3 Milicianos y más que
## quien la tenía.
func _update_largest_army() -> void:
	var previous := largest_army_owner
	for p in players.size():
		var count := militia_played[p]
		if count < LARGEST_ARMY_MIN:
			continue
		if largest_army_owner == -1 or count > militia_played[largest_army_owner]:
			largest_army_owner = p
	if largest_army_owner != previous:
		event.emit(&"largest_army", {"player": largest_army_owner, "previous": previous, "count": militia_played[largest_army_owner]})


func _pay(pid: int, cost: Array) -> void:
	for r in RESOURCE_COUNT:
		hands[pid][r] -= cost[r]
		bank[r] += cost[r]


func _check_victory(pid: int) -> void:
	if victory_points(pid) >= victory_points_target:
		phase = Phase.FINISHED
		trade_offer = {}
		var winners: Array[int] = [pid]
		finish(winners)


# --- Acciones legales ---------------------------------------------------------

## Acciones legales para un jugador. No incluye ofertas de intercambio (hay
## infinitas): la IA las construirá por su cuenta. En los descartes devuelve
## una sola propuesta razonable (descartar de lo que más se tiene).
func get_legal_actions(pid: int) -> Array[GameAction]:
	var candidates: Array[GameAction] = []
	if finished or not pid in players_to_act():
		return candidates
	if not trade_offer.is_empty():
		candidates.append(GameAction.new(ACCEPT_TRADE, pid))
		candidates.append(GameAction.new(REJECT_TRADE, pid))
		return _only_valid(candidates)
	match phase:
		Phase.SETUP:
			if setup_vertex == -1:
				for v in legal_settlement_vertices(pid):
					candidates.append(GameAction.new(BUILD_SETTLEMENT, pid, {"vertex": v}))
			else:
				for e in legal_road_edges(pid):
					candidates.append(GameAction.new(BUILD_ROAD, pid, {"edge": e}))
		Phase.ROLL:
			candidates.append(GameAction.new(ROLL, pid))
			candidates.append(GameAction.new(PLAY_DEV, pid, {"card": ArchDefs.DevCard.MILITIA}))
		Phase.DISCARD:
			candidates.append(GameAction.new(DISCARD, pid, {"cards": suggested_discard(pid)}))
		Phase.ROBBER:
			for t in bandit_tiles():
				var victims := bandit_victims(pid, t)
				if victims.is_empty():
					candidates.append(GameAction.new(MOVE_BANDIT, pid, {"tile": t, "victim": -1}))
				for victim in victims:
					candidates.append(GameAction.new(MOVE_BANDIT, pid, {"tile": t, "victim": victim}))
		Phase.ROAD_BUILDING:
			for e in legal_road_edges(pid):
				candidates.append(GameAction.new(BUILD_ROAD, pid, {"edge": e}))
		Phase.MAIN:
			if build_error(pid, BUILD_CITY) == "":
				for v in legal_city_vertices(pid):
					candidates.append(GameAction.new(BUILD_CITY, pid, {"vertex": v}))
			if build_error(pid, BUILD_SETTLEMENT) == "":
				for v in legal_settlement_vertices(pid):
					candidates.append(GameAction.new(BUILD_SETTLEMENT, pid, {"vertex": v}))
			if build_error(pid, BUILD_ROAD) == "":
				for e in legal_road_edges(pid):
					candidates.append(GameAction.new(BUILD_ROAD, pid, {"edge": e}))
			candidates.append(GameAction.new(BUY_DEV, pid))
			for card in [ArchDefs.DevCard.MILITIA, ArchDefs.DevCard.ROAD_BUILDING]:
				candidates.append(GameAction.new(PLAY_DEV, pid, {"card": card}))
			for r in RESOURCE_COUNT:
				candidates.append(GameAction.new(PLAY_DEV, pid, {"card": ArchDefs.DevCard.MONOPOLY, "resource": r}))
				for r2 in range(r, RESOURCE_COUNT):
					candidates.append(GameAction.new(PLAY_DEV, pid, {"card": ArchDefs.DevCard.HARVEST, "resources": [r, r2]}))
			for give in RESOURCE_COUNT:
				for receive in RESOURCE_COUNT:
					candidates.append(GameAction.new(TRADE_BANK, pid, {"give": give, "receive": receive}))
			candidates.append(GameAction.new(END_TURN, pid))
	return _only_valid(candidates)


## Descarte sencillo: quita una a una cartas del recurso del que más tiene.
func suggested_discard(pid: int) -> Array[int]:
	var cards := _zeros()
	var hand: Array[int] = hands[pid].duplicate()
	for i in pending_discards.get(pid, 0):
		var r := hand.find(hand.max())
		hand[r] -= 1
		cards[r] += 1
	return cards


func _only_valid(candidates: Array[GameAction]) -> Array[GameAction]:
	var result: Array[GameAction] = []
	for a in candidates:
		if validate(a) == "":
			result.append(a)
	return result


# --- Utilidades ----------------------------------------------------------------

static func format_resources(amounts: Array) -> String:
	var parts: Array[String] = []
	for r in amounts.size():
		if amounts[r] > 0:
			parts.append("%d %s" % [amounts[r], ArchDefs.RESOURCE_NAMES[r]])
	return ", ".join(parts)


func _has_cards(pid: int, amounts: Array) -> bool:
	for r in RESOURCE_COUNT:
		if hands[pid][r] < amounts[r]:
			return false
	return true


static func _valid_resource(r: Variant) -> bool:
	return (r is int or r is float) and int(r) >= 0 and int(r) < RESOURCE_COUNT


static func _valid_amounts(amounts: Variant) -> bool:
	if not amounts is Array or amounts.size() != RESOURCE_COUNT:
		return false
	for n in amounts:
		if not (n is int or n is float) or n < 0:
			return false
	return true


static func _sum(values: Array) -> int:
	var total := 0
	for n in values:
		total += n
	return total


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


static func _zeros() -> Array[int]:
	var a: Array[int] = []
	a.assign(_filled(RESOURCE_COUNT, 0))
	return a


static func _dev_zeros() -> Array[int]:
	var a: Array[int] = []
	a.assign(_filled(DEV_TYPES, 0))
	return a


static func _filled(count: int, value: Variant) -> Array:
	var a := []
	a.resize(count)
	a.fill(value)
	return a
