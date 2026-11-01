class_name PestsGame
extends GameBase
## Lógica de una partida de Pests!
##
## Fases:
##   CHOOSE_SPECIES  cada jugador elige exterminador, en sentido antihorario
##                   desde el jugador inicial.
##   DRAFT           se eligen las cartas de herramientas boca arriba, una a
##                   una en sentido horario empezando por el último en elegir
##                   exterminador, hasta tener 4 cada uno.
##   PLACE_TILES     se construye la casa loseta a loseta, en sentido horario
##                   desde el jugador inicial.
##   QUEEN           el jugador activa a su reina (dos veces en su primer
##                   turno). Antes de la primera tirada puede jugar las cartas
##                   "antes de tirar" (Las plagas hibernan, Control mental).
##   EXTERMINATOR    movimiento gratis + 2 puntos de acción; termina con END_TURN.
##   FINISHED
##
## Con la opción "quick_species" (reglas rápidas) los exterminadores y las
## cartas se reparten al azar; con "auto_house" la casa se construye al azar.
##
## El jugador inicial elige exterminador el primero, coloca la primera loseta
## y juega el primer turno (con el orden del reglamento siempre coincide).
##
## Las plagas se guardan por habitación y por especie. Cada especie tiene una
## reserva y un total en juego ("pool"): pool = reserva + en la casa + en
## trampas. Las plagas exterminadas vuelven a la reserva.

signal event(kind: StringName, data: Dictionary)

const D := preload("res://games/pests/logic/pests_defs.gd")

enum Phase { CHOOSE_SPECIES, DRAFT, PLACE_TILES, QUEEN, EXTERMINATOR, FINISHED }

const CHOOSE_SPECIES := &"choose_species"  # {"species": int}
const DRAFT_CARD := &"draft_card"          # {"card": id}
const PLACE_TILE := &"place_tile"          # {"index": int, "x": int, "y": int, "rotation": int}
const ROLL_QUEEN := &"roll_queen"          # activa la reina (tira el dado o usa la acción elegida)
const MOVE := &"move"                      # {"room": int}
const EXTERMINATE := &"exterminate"
const DROP_TRAP := &"drop_trap"            # {"target": "queen" | "pests"} (opcional, por defecto la reina)
const EMPTY_TRAP := &"empty_trap"          # {"trap": id}
const DRAG_TRAP := &"drag_trap"            # {"trap": id, "room": int}
const SEAL_NEST := &"seal_nest"
const DESTROY_TRAP := &"destroy_trap"      # {"trap": id}
const UNSEAL_NEST := &"unseal_nest"
const PLAY_CARD := &"play_card"            # {"card": id, ...objetivos} (ver _card_target_error)
const BUY_CARD := &"buy_card"
const END_TURN := &"end_turn"

const PHASE_ACTIONS := {
	Phase.CHOOSE_SPECIES: [CHOOSE_SPECIES],
	Phase.DRAFT: [DRAFT_CARD],
	Phase.PLACE_TILES: [PLACE_TILE],
	Phase.QUEEN: [ROLL_QUEEN, PLAY_CARD],
	Phase.EXTERMINATOR: [MOVE, EXTERMINATE, DROP_TRAP, EMPTY_TRAP, DRAG_TRAP, SEAL_NEST, DESTROY_TRAP,
		UNSEAL_NEST, PLAY_CARD, BUY_CARD, END_TURN],
	Phase.FINISHED: [],
}

## Acción del exterminador correspondiente a cada tipo (para los costes).
const ACTION_ACTS := {
	MOVE: D.Act.MOVE,
	EXTERMINATE: D.Act.EXTERMINATE,
	DROP_TRAP: D.Act.DROP_TRAP,
	EMPTY_TRAP: D.Act.EMPTY_TRAP,
	DRAG_TRAP: D.Act.DRAG_TRAP,
	SEAL_NEST: D.Act.SEAL_NEST,
	DESTROY_TRAP: D.Act.DESTROY_TRAP,
	UNSEAL_NEST: D.Act.UNSEAL_NEST,
	PLAY_CARD: D.Act.PLAY_CARD,
	BUY_CARD: D.Act.BUY_CARD,
}

## Cartas que se quedan delante del jugador afectado hasta su próximo turno.
const NEXT_TURN_EFFECTS := ["angry_queen", "stuck", "royal_persuasion"]
## Cartas de efecto duradero y su condición de descarte.
const LASTING_EFFECTS := ["fertile", "two_by_two"]

const BUG_BOMB_ALL := 9999
const ZAP_PESTS := 3
const SURGE_PESTS := 5
const LESS_TO_INFEST_PESTS := 5
const SPREADING_PESTS := 4
const MORE_TIME_ACTIONS := 2
const ENERGY_DRINK_MOVES := 4
const MATING_CALL_STEPS := 2

## Opciones de la partida. Se fijan antes de setup() y se guardan con la
## partida.
var options := {"quick_species": false, "auto_house": false}

var phase: Phase = Phase.CHOOSE_SPECIES
var house: PestsHouse
var start_player := 0

## Por jugador: su especie (-1 mientras no ha elegido).
var species_of: Array[int] = []

## Construcción de la casa: por jugador, las losetas que le quedan (en el
## formato de PestsHouseGenerator.tiles_for_game) y cuántas ha colocado.
var tile_hands: Array = []
var tiles_placed: Array[int] = []

## Por habitación: plagas de cada especie (Array[int] de 6).
var pests: Array = []
## Por especie (6): reserva, total en juego, habitación de la reina (-1 si la
## especie no está en juego) y nido sellado.
var reserve: Array[int] = []
var pool: Array[int] = []
var queen_room: Array[int] = []
var sealed: Array[bool] = []

## Por jugador: habitación del exterminador, eliminado, turnos jugados.
var exterminator_room: Array[int] = []
var eliminated: Array[bool] = []
var turns_taken: Array[int] = []

## Trampas en la casa: {"id", "owner", "room", "pests", "queen", "prefer_queen"}.
var traps: Array[Dictionary] = []
var _next_trap_id := 0

## Cartas (por id de PestsDefs.CARDS): por jugador su mano, el mazo (se roba
## del final), el descarte y las cartas boca arriba durante la elección.
var hands: Array = []
var deck: Array[String] = []
var discard: Array[String] = []
var draft_pool: Array[String] = []
## Cartas jugadas este turno: van al descarte al terminar el turno.
var played_this_turn: Array[String] = []
## Cartas delante de un jugador: {"card", "source", "target", "action", "used"}.
var effects: Array[Dictionary] = []

## Turno en curso. queen_steps son las activaciones de la reina que quedan:
## {"action": acción elegida o -1 para tirar, "repeat": veces que la hace}.
var queen_steps: Array[Dictionary] = []
var queen_steps_done := 0
var free_move := false
var action_points := 0
## Movimientos gratis de la Bebida energética.
var energy_moves := 0
## Última cara del dado de la reina (-1 si aún no ha salido ninguna) y última
## tirada del d6.
var last_queen_face := -1
var last_roll := 0


func _on_setup() -> void:
	var n := players.size()
	assert(n >= D.MIN_PLAYERS and n <= D.MAX_PLAYERS, "Pests! es para 2 a 6 jugadores")
	house = PestsHouse.new()
	species_of.assign(_filled(n, -1))
	exterminator_room.assign(_filled(n, 0))
	eliminated.assign(_filled(n, false))
	turns_taken.assign(_filled(n, 0))
	tiles_placed.assign(_filled(n, 0))
	tile_hands.clear()
	reserve.assign(_filled(D.SPECIES_COUNT, 0))
	pool.assign(_filled(D.SPECIES_COUNT, 0))
	queen_room.assign(_filled(D.SPECIES_COUNT, -1))
	sealed.assign(_filled(D.SPECIES_COUNT, false))
	pests.clear()
	traps.clear()
	_next_trap_id = 0
	hands.clear()
	for i in n:
		hands.append([])
	deck.clear()
	discard.clear()
	draft_pool.clear()
	played_this_turn.clear()
	effects.clear()
	queen_steps.clear()
	queen_steps_done = 0
	free_move = false
	action_points = 0
	energy_moves = 0
	last_queen_face = -1
	last_roll = 0
	# Se tira el d6 para ver quién empieza.
	start_player = rng.randi_range(0, n - 1)
	turns.start_player = start_player
	turns.current = start_player
	if options.get("quick_species", false):
		var all: Array = range(D.SPECIES_COUNT)
		rng.shuffle(all)
		for i in n:
			species_of[(start_player + i) % n] = all[i]
		_deal_cards()
		_begin_house()
	else:
		phase = Phase.CHOOSE_SPECIES
		var order: Array[int] = []
		for i in n:
			order.append(posmod(start_player - i, n))
		turns.begin_sequence(order, start_player)


# --- Guardar y cargar -----------------------------------------------------------

func save_data() -> Dictionary:
	var data := super.save_data()
	data["options"] = options.duplicate()
	return data


static func options_from_save(data: Dictionary) -> Dictionary:
	return data.get("options", {}).duplicate()


# --- Consultas -----------------------------------------------------------------

func players_to_act() -> Array[int]:
	var result: Array[int] = []
	if phase != Phase.FINISHED:
		result.append(turns.current)
	return result


func species(pid: int) -> int:
	return species_of[pid]


## Jugador que lleva una especie (-1 si nadie).
func player_of(sp: int) -> int:
	return species_of.find(sp)


func active_players() -> Array[int]:
	var result: Array[int] = []
	for pid in players.size():
		if not eliminated[pid]:
			result.append(pid)
	return result


## Rivales que siguen en la partida.
func opponents(pid: int) -> Array[int]:
	var result: Array[int] = []
	for other in active_players():
		if other != pid:
			result.append(other)
	return result


func available_species() -> Array[int]:
	var result: Array[int] = []
	for sp in D.SPECIES_COUNT:
		if not sp in species_of:
			result.append(sp)
	return result


func ability(pid: int, key: String) -> Variant:
	return D.ability(species_of[pid], key)


func pests_in_room(room: int, sp: int) -> int:
	return pests[room][sp]


func total_pests_in_room(room: int) -> int:
	var total := 0
	for sp in D.SPECIES_COUNT:
		total += pests[room][sp]
	return total


func pests_in_house(sp: int) -> int:
	var total := 0
	for r in pests.size():
		total += pests[r][sp]
	return total


func pests_in_traps(sp: int) -> int:
	var total := 0
	for t in traps:
		if trap_species(t) == sp:
			total += t["pests"]
	return total


## Habitaciones con más plagas de una especie (vacío si no hay ninguna).
func most_infested_rooms(sp: int) -> Array[int]:
	var best := 0
	var result: Array[int] = []
	for r in pests.size():
		var c: int = pests[r][sp]
		if c > best:
			best = c
			result = [r]
		elif c == best and c > 0:
			result.append(r)
	return result


func trap_species(trap: Dictionary) -> int:
	return species_of[trap["owner"]]


func trap_capacity(trap: Dictionary) -> int:
	return D.ability(trap_species(trap), "trap_capacity")


func find_trap(id: int) -> Dictionary:
	for t in traps:
		if t["id"] == id:
			return t
	return {}


func traps_in_room(room: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in traps:
		if t["room"] == room:
			result.append(t)
	return result


func traps_in_house(pid: int) -> int:
	var n := 0
	for t in traps:
		if t["owner"] == pid:
			n += 1
	return n


func traps_available(pid: int) -> int:
	return int(ability(pid, "traps")) - traps_in_house(pid)


## Trampa que tiene atrapada a la reina de una especie ({} si está libre).
func queen_trap(sp: int) -> Dictionary:
	for t in traps:
		if t["queen"] and trap_species(t) == sp:
			return t
	return {}


func is_queen_trapped(sp: int) -> bool:
	return not queen_trap(sp).is_empty()


func nest_room(pid: int) -> int:
	return house.nest_of(species_of[pid])


## ¿Puede el jugador vaciar la trampa con su reina (y ganar)?
func can_empty_queen_trap(pid: int) -> bool:
	var sp := species_of[pid]
	return sealed[sp] and pests_in_house(sp) == 0


func hand(pid: int) -> Array:
	return hands[pid]


## Cartas delante de un jugador.
func effects_on(pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in effects:
		if e["target"] == pid:
			result.append(e)
	return result


func has_effect(pid: int, card_id: String) -> bool:
	for e in effects:
		if e["target"] == pid and e["card"] == card_id:
			return true
	return false


## ¿Se pueden jugar ahora las cartas "antes de tirar"?
func before_roll_window() -> bool:
	return phase == Phase.QUEEN and queen_steps_done == 0


## Coste en PA de una acción del exterminador.
func action_cost(pid: int, type: StringName, data: Dictionary = {}) -> int:
	if type == MOVE:
		return 0 if (energy_moves > 0 or free_move) else 1
	if type == PLAY_CARD:
		var card := D.card(String(data.get("card", "")))
		if not card.is_empty() and card["timing"] == D.CardTiming.BEFORE_ROLL:
			return 0
	if type == END_TURN or not ACTION_ACTS.has(type):
		return 0
	var owner_species := -1
	if type == DESTROY_TRAP:
		var t := find_trap(int(data.get("trap", -1)))
		if not t.is_empty():
			owner_species = trap_species(t)
	return D.act_cost(ACTION_ACTS[type], species_of[pid], owner_species)


## ¿Se puede colocar ya el nido? Desde la 3.ª ronda, o antes si ya no le quedan
## losetas normales.
func nest_allowed(pid: int) -> bool:
	if tiles_placed[pid] >= D.NEST_MIN_ROUND - 1:
		return true
	for tile in tile_hands[pid]:
		if tile["kind"] != D.RoomKind.NEST:
			return false
	return true


## Colocaciones legales de losetas para el jugador:
## [{"index", "x", "y", "rotation"}].
func tile_options(pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if phase != Phase.PLACE_TILES or pid != turns.current:
		return result
	var tiles: Array = tile_hands[pid]
	for i in tiles.size():
		var tile: Dictionary = tiles[i]
		var is_nest: bool = tile["kind"] == D.RoomKind.NEST
		if is_nest and not nest_allowed(pid):
			continue
		var options_for := house.placements_for(PestsHouseGenerator.tile_doors(tile))
		for o in options_for:
			result.append({"index": i, "x": o["cell"].x, "y": o["cell"].y, "rotation": o["rotation"]})
		if is_nest and options_for.is_empty():
			# Último recurso: el nido se adapta a las puertas de alrededor.
			for cell in house.frontier():
				if house.fitted_nest_doors(cell) != 0:
					result.append({"index": i, "x": cell.x, "y": cell.y, "rotation": 0})
	return result


# --- Validación -----------------------------------------------------------------

func validate(action: GameAction) -> String:
	var pid := action.player_id
	var type := action.type
	var data := action.data
	if phase == Phase.FINISHED:
		return "La partida ha terminado"
	if pid < 0 or pid >= players.size():
		return "Jugador no válido"
	if not pid in players_to_act():
		return "No es tu turno"
	if not type in PHASE_ACTIONS[phase]:
		return _phase_hint()
	if phase == Phase.EXTERMINATOR and type != END_TURN:
		if energy_moves > 0 and type != MOVE:
			return "Con la Bebida energética solo puedes moverte"
		var cost := action_cost(pid, type, data)
		if cost > action_points:
			return "No te quedan puntos de acción suficientes (necesitas %d)" % cost
	var sp := species_of[pid]
	var here := exterminator_room[pid]
	match type:
		CHOOSE_SPECIES:
			var s := int(data.get("species", -1))
			if s < 0 or s >= D.SPECIES_COUNT:
				return "Exterminador no válido"
			if s in species_of:
				return "Ese exterminador ya está elegido"
			return ""
		DRAFT_CARD:
			if not String(data.get("card", "")) in draft_pool:
				return "Esa carta no está disponible"
			return ""
		PLACE_TILE:
			var wanted := {"index": int(data.get("index", -1)), "x": int(data.get("x", 0)),
				"y": int(data.get("y", 0)), "rotation": posmod(int(data.get("rotation", 0)), 4)}
			var index: int = wanted["index"]
			if index < 0 or index >= tile_hands[pid].size():
				return "Loseta no válida"
			if tile_hands[pid][index]["kind"] == D.RoomKind.NEST and not nest_allowed(pid):
				return "El nido no se puede colocar hasta la ronda %d" % D.NEST_MIN_ROUND
			for o in tile_options(pid):
				if o == wanted:
					return ""
			var doors := D.rotate_doors(PestsHouseGenerator.tile_doors(tile_hands[pid][index]), wanted["rotation"])
			var reason := house.can_place(Vector2i(wanted["x"], wanted["y"]), doors)
			return reason if reason != "" else "No se puede colocar ahí"
		ROLL_QUEEN, END_TURN:
			return ""
		MOVE:
			var room := int(data.get("room", -1))
			if not room in house.neighbors(here):
				return "Solo puedes moverte a una habitación conectada por una puerta"
			return ""
		EXTERMINATE:
			if pests[here][sp] <= 0:
				return "No hay plagas de tu color en esta habitación"
			return ""
		DROP_TRAP:
			if traps_available(pid) <= 0:
				return "No te quedan trampas"
			if here == house.nest_of(sp):
				return "No puedes soltar una trampa en tu nido"
			if not String(data.get("target", "queen")) in ["queen", "pests"]:
				return "Objetivo de la trampa no válido"
			return ""
		EMPTY_TRAP:
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["owner"] != pid:
				return "Esa trampa no es tuya"
			if t["room"] != here:
				return "La trampa no está en tu habitación"
			return _queen_trap_error(pid, t)
		DRAG_TRAP:
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["room"] != here:
				return "No hay esa trampa en tu habitación"
			if not int(data.get("room", -1)) in house.neighbors(here):
				return "Solo puedes arrastrarla a una habitación conectada por una puerta"
			return ""
		SEAL_NEST:
			if here != house.nest_of(sp):
				return "Tienes que estar en tu nido"
			if sealed[sp]:
				return "Tu nido ya está sellado"
			return ""
		DESTROY_TRAP:
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["room"] != here:
				return "No hay esa trampa en tu habitación"
			if t["owner"] == pid:
				return "No puedes destruir tu propia trampa"
			return ""
		UNSEAL_NEST:
			var nest_species := house.room_species[here]
			if nest_species < 0 or nest_species == sp or player_of(nest_species) < 0:
				return "Tienes que estar en el nido de un rival"
			if not sealed[nest_species]:
				return "Ese nido no está sellado"
			return ""
		BUY_CARD:
			if deck.is_empty() and discard.is_empty():
				return "No quedan cartas"
			return ""
		PLAY_CARD:
			return _play_card_error(pid, data)
	return "Acción desconocida"


func _queen_trap_error(pid: int, t: Dictionary) -> String:
	if t["queen"] and not can_empty_queen_trap(pid):
		return "Para vaciar la trampa con tu reina necesitas el nido sellado y ninguna plaga tuya en la casa"
	return ""


func _play_card_error(pid: int, data: Dictionary) -> String:
	var card_id := String(data.get("card", ""))
	var card := D.card(card_id)
	if card.is_empty() or not card_id in hands[pid]:
		return "No tienes esa carta"
	if card["timing"] == D.CardTiming.BEFORE_ROLL:
		if not before_roll_window():
			return "Esta carta se juega antes de tirar el dado de tu reina"
	elif phase != Phase.EXTERMINATOR:
		return "Esta carta se juega en tu turno de exterminador"
	return _card_target_error(pid, card_id, data)


## Comprueba los objetivos de una carta. Datos según la carta:
##   mind_control, royal_persuasion: "queen_action"
##   colony_collapse, zap: "room"
##   trap_remote: "trap" (propia); trap_breaks: "trap" (rival)
##   cartas ofensivas: "player"; spreading además "room"
##   dumpster_diver: "use" (carta ofensiva del descarte) y sus objetivos
func _card_target_error(pid: int, card_id: String, data: Dictionary) -> String:
	var sp := species_of[pid]
	var here := exterminator_room[pid]
	var card := D.card(card_id)
	if card["kind"] == D.CardKind.OFFENSIVE and card_id != "dumpster_diver":
		var target := int(data.get("player", -1))
		if not target in opponents(pid):
			return "Elige a un rival"
	var target_pid := int(data.get("player", -1))
	var target_sp := species_of[target_pid] if target_pid >= 0 and target_pid < players.size() else -1
	match card_id:
		"more_time", "energy_drink", "mating_call", "hibernate":
			return ""
		"mind_control":
			if not _valid_queen_action(data):
				return "Elige la acción de la reina"
			for step in queen_steps:
				if step["action"] < 0:
					return ""
			return "La acción de tu reina ya está decidida"
		"bug_bomb":
			return "" if pests[here][sp] > 0 else "No hay plagas de tu color en tu habitación"
		"colony_collapse":
			var room := int(data.get("room", -1))
			return "" if room in most_infested_rooms(sp) else "Elige la habitación con más plagas de tu color"
		"zap":
			var room := int(data.get("room", -1))
			if room < 0 or room >= pests.size():
				return "Elige una habitación"
			return "" if pests[room][sp] > 0 else "No hay plagas de tu color en esa habitación"
		"quik_trap":
			if traps_available(pid) <= 0:
				return "No te quedan trampas"
			if here == house.nest_of(sp):
				return "No puedes soltar una trampa en tu nido"
			return ""
		"quik_seal":
			var nest_species := house.room_species[here]
			if nest_species < 0 or player_of(nest_species) < 0 or eliminated[player_of(nest_species)]:
				return "Tienes que estar en un nido"
			return "Ese nido ya está sellado" if sealed[nest_species] else ""
		"trap_remote":
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["owner"] != pid:
				return "Elige una de tus trampas"
			return _queen_trap_error(pid, t)
		"nesting":
			if is_queen_trapped(sp):
				return "Tu reina está atrapada"
			return "Tu reina ya está en su nido" if queen_room[sp] == house.nest_of(sp) else ""
		"unseal_nest":
			return "" if sealed[target_sp] else "Ese nido no está sellado"
		"trap_breaks":
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["owner"] != target_pid:
				return "Elige una trampa de ese jugador"
			return ""
		"pest_surge", "angry_queen", "stuck", "less_to_infest":
			return ""
		"royal_persuasion":
			return "" if _valid_queen_action(data) else "Elige la acción de su reina"
		"sabotage_tools":
			return "" if not hands[target_pid].is_empty() else "Ese jugador no tiene cartas"
		"spreading":
			var room := int(data.get("room", -1))
			if room < 0 or room >= pests.size() or pests[room][target_sp] <= 0:
				return "Elige una habitación con plagas de ese jugador"
			return ""
		"two_by_two":
			return "" if not sealed[target_sp] else "Su nido está sellado"
		"fertile":
			return "" if not is_queen_trapped(target_sp) else "Su reina está atrapada"
		"dumpster_diver":
			var used := String(data.get("use", ""))
			var used_card := D.card(used)
			if not used in discard or used_card.is_empty() or used_card["kind"] != D.CardKind.OFFENSIVE or used == "dumpster_diver":
				return "Elige una carta ofensiva del descarte"
			return _card_target_error(pid, used, data)
	return "Carta desconocida"


static func _valid_queen_action(data: Dictionary) -> bool:
	var a := int(data.get("queen_action", -1))
	return a >= 0 and a < D.QueenAction.size()


func _phase_hint() -> String:
	match phase:
		Phase.CHOOSE_SPECIES:
			return "Ahora toca elegir exterminador"
		Phase.DRAFT:
			return "Ahora toca elegir una carta"
		Phase.PLACE_TILES:
			return "Ahora toca colocar una loseta"
		Phase.QUEEN:
			return "Primero activa a tu reina"
	return "Ahora no puedes hacer eso"


# --- Aplicación -------------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	var data := action.data
	var type := action.type
	if phase == Phase.EXTERMINATOR and type != END_TURN:
		_pay(pid, type, data)
	match type:
		CHOOSE_SPECIES:
			species_of[pid] = int(data["species"])
			event.emit(&"species_chosen", {"player": pid, "species": species_of[pid]})
			turns.next()
			if not turns.in_sequence():
				_begin_draft()
		DRAFT_CARD:
			var card_id := String(data["card"])
			draft_pool.erase(card_id)
			hands[pid].append(card_id)
			event.emit(&"card_drafted", {"player": pid, "card": card_id})
			turns.next()
			if not turns.in_sequence():
				deck.assign(draft_pool)
				draft_pool.clear()
				rng.shuffle(deck)
				_begin_house()
		PLACE_TILE:
			_apply_place_tile(pid, data)
		ROLL_QUEEN:
			_activate_queen(pid, data)
		MOVE:
			exterminator_room[pid] = int(data["room"])
			event.emit(&"exterminator_moved", {"player": pid, "room": exterminator_room[pid]})
		EXTERMINATE:
			last_roll = rng.roll(6)
			data["roll"] = last_roll
			data["removed"] = exterminate(pid, last_roll + int(ability(pid, "exterminate_bonus")))
		DROP_TRAP:
			data["trap"] = _drop_trap(pid, String(data.get("target", "queen")) == "queen")
		EMPTY_TRAP:
			_empty_trap(pid, find_trap(int(data["trap"])))
		DRAG_TRAP:
			var t := find_trap(int(data["trap"]))
			var room := int(data["room"])
			t["room"] = room
			exterminator_room[pid] = room
			event.emit(&"trap_dragged", {"player": pid, "trap": t["id"], "room": room})
			_resolve_traps()
		SEAL_NEST:
			_seal(species_of[pid], pid)
		DESTROY_TRAP:
			var t := find_trap(int(data["trap"]))
			_release_trap(t)
			event.emit(&"trap_destroyed", {"player": pid, "owner": t["owner"], "room": t["room"]})
			_resolve_traps()
		UNSEAL_NEST:
			var nest_species := house.room_species[exterminator_room[pid]]
			sealed[nest_species] = false
			event.emit(&"nest_unsealed", {"player": pid, "species": nest_species})
		BUY_CARD:
			var card_id: String
			if not deck.is_empty():
				card_id = deck.pop_back()
			else:
				var i := rng.randi_range(0, discard.size() - 1)
				card_id = discard[i]
				discard.remove_at(i)
			hands[pid].append(card_id)
			event.emit(&"card_bought", {"player": pid})
		PLAY_CARD:
			var card_id := String(data["card"])
			hands[pid].erase(card_id)
			event.emit(&"card_played", {"player": pid, "card": card_id, "data": data.duplicate()})
			_apply_card(pid, card_id, data)
		END_TURN:
			_end_turn(pid)


## Paga el coste de una acción del exterminador.
func _pay(pid: int, type: StringName, data: Dictionary) -> void:
	if type == MOVE:
		if energy_moves > 0:
			energy_moves -= 1
		elif free_move:
			free_move = false
		else:
			action_points -= 1
		return
	action_points -= action_cost(pid, type, data)
	free_move = false


func _apply_place_tile(pid: int, data: Dictionary) -> void:
	var index := int(data["index"])
	var tile: Dictionary = tile_hands[pid][index]
	var cell := Vector2i(int(data["x"]), int(data["y"]))
	var rotation := posmod(int(data.get("rotation", 0)), 4)
	var room: int
	if tile["kind"] == D.RoomKind.NEST and house.can_place(cell, D.rotate_doors(D.NEST_DOORS, rotation)) != "":
		room = house.place_fitted_nest(cell, tile["species"])
	else:
		room = PestsHouseGenerator.place_tile(house, tile, cell, rotation)
	tile_hands[pid].remove_at(index)
	tiles_placed[pid] += 1
	event.emit(&"tile_placed", {"player": pid, "room": room})
	turns.current = (pid + 1) % players.size()
	_prepare_tile_turn()


# --- Cartas: reparto -------------------------------------------------------------

## Reglas rápidas: se barajan las 24 cartas y se reparten 4 a cada jugador.
func _deal_cards() -> void:
	deck.clear()
	for c in D.CARDS:
		deck.append(c["id"])
	rng.shuffle(deck)
	for round_i in D.CARDS_PER_HAND:
		for i in players.size():
			hands[(start_player + i) % players.size()].append(deck.pop_back())


## Elección de cartas: empieza el último en elegir exterminador y se sigue en
## sentido horario hasta que todos tienen 4.
func _begin_draft() -> void:
	phase = Phase.DRAFT
	draft_pool.clear()
	for c in D.CARDS:
		draft_pool.append(c["id"])
	var n := players.size()
	var first := (start_player + 1) % n
	var order: Array[int] = []
	for i in n * D.CARDS_PER_HAND:
		order.append((first + i) % n)
	turns.begin_sequence(order, start_player)


# --- Cartas: efectos -------------------------------------------------------------

func _apply_card(pid: int, card_id: String, data: Dictionary) -> void:
	var sp := species_of[pid]
	var here := exterminator_room[pid]
	var target := int(data.get("player", -1))
	var target_sp := species_of[target] if target >= 0 else -1
	if card_id in NEXT_TURN_EFFECTS or card_id in LASTING_EFFECTS:
		effects.append({"card": card_id, "source": pid, "target": target,
			"action": int(data.get("queen_action", -1)), "used": false})
		return
	if card_id != "dumpster_diver":
		played_this_turn.append(card_id)
	match card_id:
		"more_time":
			action_points += MORE_TIME_ACTIONS
		"hibernate":
			queen_steps.clear()
			event.emit(&"queen_hibernates", {"species": sp})
			_begin_exterminator(pid)
		"mind_control":
			for step in queen_steps:
				if step["action"] < 0:
					step["action"] = int(data["queen_action"])
					break
		"mating_call":
			summon(sp, here, MATING_CALL_STEPS)
		"colony_collapse":
			var room := int(data["room"])
			_remove_pests(pid, room, ceili(pests[room][sp] / 2.0))
		"bug_bomb":
			_remove_pests(pid, here, BUG_BOMB_ALL)
		"energy_drink":
			action_points = 0
			free_move = false
			energy_moves = ENERGY_DRINK_MOVES
		"quik_trap":
			var trap_id := _drop_trap(pid, pests[here][sp] == 0)
			var t := find_trap(trap_id)
			if not t.is_empty() and _queen_trap_error(pid, t) == "":
				_empty_trap(pid, t)
		"quik_seal":
			_seal(house.room_species[here], pid)
		"trap_remote":
			_empty_trap(pid, find_trap(int(data["trap"])))
		"nesting":
			queen_room[sp] = house.nest_of(sp)
			event.emit(&"queen_moved", {"species": sp, "room": queen_room[sp], "reentered": false})
			_resolve_traps()
		"zap":
			_remove_pests(pid, int(data["room"]), ZAP_PESTS)
		"unseal_nest":
			sealed[target_sp] = false
			event.emit(&"nest_unsealed", {"player": pid, "species": target_sp})
		"trap_breaks":
			var t := find_trap(int(data["trap"]))
			_release_trap(t)
			event.emit(&"trap_destroyed", {"player": pid, "owner": t["owner"], "room": t["room"]})
			_resolve_traps()
		"pest_surge":
			var nest := house.nest_of(target_sp)
			var added := _add_pests(target_sp, nest, SURGE_PESTS)
			event.emit(&"nest_spawned", {"species": target_sp, "room": nest, "count": added})
			_resolve_traps()
		"sabotage_tools":
			var i := rng.randi_range(0, hands[target].size() - 1)
			var lost: String = hands[target][i]
			hands[target].remove_at(i)
			discard.append(lost)
			data["discarded"] = lost
			event.emit(&"card_discarded", {"player": target, "card": lost})
		"less_to_infest":
			var n := mini(LESS_TO_INFEST_PESTS, reserve[target_sp])
			reserve[target_sp] -= n
			pool[target_sp] -= n
			event.emit(&"pests_removed", {"species": target_sp, "count": n})
		"spreading":
			var spread := house.spread(int(data["room"]), SPREADING_PESTS)
			var placed := {}
			for r in spread:
				placed[r] = _add_pests(target_sp, r, spread[r])
			event.emit(&"pests_spread", {"species": target_sp, "rooms": placed})
			_resolve_traps()
		"dumpster_diver":
			played_this_turn.append(card_id)
			var used := String(data["use"])
			discard.erase(used)
			event.emit(&"card_played", {"player": pid, "card": used, "data": data.duplicate()})
			_apply_card(pid, used, data)


## Quita plagas propias de una habitación (vuelven a la reserva).
func _remove_pests(pid: int, room: int, count: int) -> int:
	var sp := species_of[pid]
	var removed := mini(count, pests[room][sp])
	pests[room][sp] -= removed
	reserve[sp] += removed
	event.emit(&"pests_exterminated", {"player": pid, "room": room, "count": removed})
	return removed


func _discard_effect(e: Dictionary) -> void:
	effects.erase(e)
	discard.append(e["card"])
	event.emit(&"effect_ended", {"card": e["card"], "player": e["target"]})


## Descarta las cartas `card_id` que tiene delante el jugador.
func _discard_effects(target: int, card_id: String) -> void:
	for e in effects.duplicate():
		if e["target"] == target and e["card"] == card_id:
			_discard_effect(e)


# --- Construcción de la casa ------------------------------------------------------

func _begin_house() -> void:
	var active: Array[int] = []
	for pid in players.size():
		active.append(species_of[pid])
	var tiles := PestsHouseGenerator.tiles_for_game(active, rng)
	if options.get("auto_house", false):
		var generated := PestsHouseGenerator.generate(tiles, rng)
		assert(generated != null, "No se pudo generar la casa")
		house = generated
		_infest()
		return
	phase = Phase.PLACE_TILES
	tile_hands.clear()
	for pid in players.size():
		tile_hands.append([])
	var n := players.size()
	var dealt := 0
	for tile in tiles:
		if tile["kind"] == D.RoomKind.NEST:
			tile_hands[player_of(tile["species"])].append(tile)
		else:
			tile_hands[(start_player + dealt) % n].append(tile)
			dealt += 1
	turns.current = start_player
	_prepare_tile_turn()


## Busca al siguiente jugador que pueda colocar una loseta. Si un jugador no
## puede colocar ninguna de sus losetas normales, las devuelve a la caja.
## Cuando ya no quedan losetas, infesta la casa y empieza la partida.
func _prepare_tile_turn() -> void:
	var n := players.size()
	var checked := 0
	while checked < n * 2:
		var pid := turns.current
		if not tile_hands[pid].is_empty():
			if not tile_options(pid).is_empty():
				return
			# No puede colocar nada: devuelve a la caja sus losetas normales
			# (así el nido queda permitido y siempre tiene un hueco adaptado).
			var discarded := 0
			for i in range(tile_hands[pid].size() - 1, -1, -1):
				if tile_hands[pid][i]["kind"] != D.RoomKind.NEST:
					tile_hands[pid].remove_at(i)
					discarded += 1
			event.emit(&"tiles_discarded", {"player": pid, "count": discarded})
			if not tile_hands[pid].is_empty() and not tile_options(pid).is_empty():
				return
			tile_hands[pid].clear()
		turns.current = (pid + 1) % n
		checked += 1
		if _all_tiles_placed():
			break
	_infest()


func _all_tiles_placed() -> bool:
	for tiles in tile_hands:
		if not tiles.is_empty():
			return false
	return true


## Infestación inicial y comienzo del primer turno.
func _infest() -> void:
	pests.clear()
	for r in house.room_count():
		pests.append(_filled(D.SPECIES_COUNT, 0))
	var in_play := D.pests_in_play(players.size())
	for pid in players.size():
		var sp := species_of[pid]
		pool[sp] = in_play
		reserve[sp] = in_play
		exterminator_room[pid] = 0
		var nest := house.nest_of(sp)
		queen_room[sp] = nest
		_add_pests(sp, nest, D.INITIAL_NEST_PESTS)
		var spread := house.spread(nest, D.INITIAL_ADJACENT_PESTS)
		for r in spread:
			_add_pests(sp, r, spread[r])
	event.emit(&"house_infested", {})
	_start_turn(start_player)


# --- Turnos ---------------------------------------------------------------------

func _start_turn(pid: int) -> void:
	turns.current = pid
	phase = Phase.QUEEN
	free_move = false
	action_points = 0
	energy_moves = 0
	queen_steps_done = 0
	queen_steps.clear()
	for i in (2 if turns_taken[pid] == 0 else 1):
		queen_steps.append({"action": -1, "repeat": 1})
	for e in effects_on(pid):
		match e["card"]:
			"royal_persuasion":
				queen_steps[0]["action"] = e["action"]
				e["used"] = true
			"angry_queen":
				queen_steps[0]["repeat"] = 2
				e["used"] = true
	event.emit(&"turn_started", {"player": pid})


func _activate_queen(pid: int, data: Dictionary) -> void:
	var sp := species_of[pid]
	var step: Dictionary = queen_steps.pop_front()
	queen_steps_done += 1
	if step["action"] >= 0:
		data["chosen"] = step["action"]
		resolve_queen_choice(sp, step["action"], step["repeat"])
	else:
		var face := rng.randi_range(0, D.QUEEN_DIE.size() - 1)
		data["face"] = face
		resolve_queen_face(sp, face, step["repeat"])
	if queen_steps.is_empty():
		_begin_exterminator(pid)


func _begin_exterminator(pid: int) -> void:
	phase = Phase.EXTERMINATOR
	free_move = true
	action_points = D.ACTION_POINTS
	energy_moves = 0
	for e in effects_on(pid):
		if e["card"] == "stuck":
			free_move = false
			action_points = 1
			e["used"] = true


func _end_turn(pid: int) -> void:
	turns_taken[pid] += 1
	free_move = false
	action_points = 0
	energy_moves = 0
	discard.append_array(played_this_turn)
	played_this_turn.clear()
	for e in effects_on(pid):
		if e["used"]:
			_discard_effect(e)
	if _check_elimination(pid):
		var alive := active_players()
		if alive.size() <= 1:
			phase = Phase.FINISHED
			finish(alive)
			return
	var n := players.size()
	var next := (pid + 1) % n
	while eliminated[next]:
		next = (next + 1) % n
	if _wrapped(pid, next):
		turns.round_number += 1
	_start_turn(next)


## ¿Pasa el turno por el jugador inicial al ir de `from` a `to`?
func _wrapped(from: int, to: int) -> bool:
	var n := players.size()
	var i := (from + 1) % n
	while true:
		if i == start_player:
			return true
		if i == to:
			return false
		i = (i + 1) % n
	return false


## Si al final de su turno todas las plagas disponibles del jugador están en
## la casa, queda eliminado: sus piezas salen del tablero y sus cartas van al
## descarte.
func _check_elimination(pid: int) -> bool:
	var sp := species_of[pid]
	if reserve[sp] > 0 or pests_in_traps(sp) > 0 or pests_in_house(sp) == 0:
		return false
	eliminated[pid] = true
	for r in pests.size():
		pests[r][sp] = 0
	for i in range(traps.size() - 1, -1, -1):
		if traps[i]["owner"] == pid:
			traps.remove_at(i)
	queen_room[sp] = -1
	sealed[sp] = false
	for card_id in hands[pid]:
		discard.append(card_id)
	hands[pid].clear()
	for e in effects_on(pid):
		_discard_effect(e)
	event.emit(&"player_eliminated", {"player": pid, "species": sp})
	return true


# --- La reina ---------------------------------------------------------------------

## Resuelve una tirada del dado de la reina de la especie `sp`.
func resolve_queen_face(sp: int, face: int, repeat: int = 1) -> void:
	last_queen_face = face
	var f: Dictionary = D.QUEEN_DIE[face]
	event.emit(&"queen_rolled", {"species": sp, "face": face, "action": f["action"]})
	_resolve_queen(sp, f["action"], f["species"], repeat)


## Resuelve una acción elegida (Control mental, Persuasión real). Sin tirada
## no sale ningún color, así que una reina atrapada no escapa.
func resolve_queen_choice(sp: int, action: int, repeat: int = 1) -> void:
	event.emit(&"queen_chosen", {"species": sp, "action": action})
	_resolve_queen(sp, action, -1, repeat)


## Acción de la reina (`repeat` veces, por la Reina furiosa), plagas que
## suelta y plagas que salen del nido (una sola vez).
func _resolve_queen(sp: int, action: int, color: int, repeat: int) -> void:
	var trap := queen_trap(sp)
	if not trap.is_empty():
		if color == sp:
			traps.erase(trap)
			event.emit(&"queen_escaped", {"species": sp, "room": queen_room[sp]})
			_queen_drop(sp, D.QUEEN_DROP)
		_nest_spawn(sp)
		_resolve_traps()
		return
	for i in repeat:
		if is_queen_trapped(sp):
			break
		var performed := true
		match action:
			D.QueenAction.SUMMON:
				performed = summon(sp, queen_room[sp], 1)
				_queen_drop(sp, D.QUEEN_DROP if performed else D.QUEEN_ANGRY_DROP)
			D.QueenAction.POPULATE:
				var spread := house.spread(queen_room[sp], D.POPULATE_COUNT,
					int(D.ability(sp, "populate_distance")), _through_walls(sp))
				var placed := {}
				for r in spread:
					placed[r] = _add_pests(sp, r, spread[r])
				event.emit(&"queen_populated", {"species": sp, "rooms": placed})
			_:
				performed = _queen_move(sp, D.queen_action_dir(action))
				_queen_drop(sp, D.QUEEN_DROP if performed else D.QUEEN_ANGRY_DROP)
		if not performed:
			event.emit(&"queen_angry", {"species": sp})
		_resolve_traps()
	_nest_spawn(sp)
	_resolve_traps()


## Mueve la reina. Devuelve false si no pudo moverse (pared o patio).
func _queen_move(sp: int, dir: int) -> bool:
	var tw := _through_walls(sp)
	var moved := false
	for i in int(D.ability(sp, "queen_moves")):
		var step := house.queen_step(queen_room[sp], dir, tw)
		match step["result"]:
			PestsHouse.Step.BLOCKED:
				break
			PestsHouse.Step.COURTYARD:
				event.emit(&"queen_courtyard", {"species": sp, "room": queen_room[sp]})
				return false
			_:
				queen_room[sp] = step["room"]
				moved = true
				var reentered: bool = step["result"] == PestsHouse.Step.REENTERED
				event.emit(&"queen_moved", {"species": sp, "room": queen_room[sp], "reentered": reentered})
				_resolve_traps()
				if reentered or is_queen_trapped(sp):
					break
	return moved


## Todas las plagas de `sp` avanzan `steps` habitaciones hacia `target`.
## Devuelve true si alguna se movió.
func summon(sp: int, target: int, steps: int) -> bool:
	var tw := _through_walls(sp)
	var moved_any := false
	for s in steps:
		var next_counts: Array = _filled(pests.size(), 0)
		var moves: Array = []
		for r in pests.size():
			var c: int = pests[r][sp]
			if c == 0:
				continue
			var split := house.summon_split(r, c, target, tw)
			for dest in split:
				next_counts[dest] += split[dest]
				if dest != r:
					moved_any = true
					moves.append({"from": r, "to": dest, "count": split[dest]})
		for r in pests.size():
			pests[r][sp] = next_counts[r]
		if not moves.is_empty():
			event.emit(&"pests_summoned", {"species": sp, "moves": moves})
		_resolve_traps()
	return moved_any


func _queen_drop(sp: int, count: int) -> void:
	var extra := 1 if has_effect(player_of(sp), "fertile") else 0
	var added := _add_pests(sp, queen_room[sp], count + extra)
	event.emit(&"queen_dropped", {"species": sp, "room": queen_room[sp], "count": added})


func _nest_spawn(sp: int) -> void:
	if sealed[sp]:
		return
	var nest := house.nest_of(sp)
	var extra := 1 if has_effect(player_of(sp), "two_by_two") else 0
	var added := _add_pests(sp, nest, int(D.ability(sp, "nest_spawn")) + extra)
	event.emit(&"nest_spawned", {"species": sp, "room": nest, "count": added})


func _seal(sp: int, by: int) -> void:
	sealed[sp] = true
	event.emit(&"nest_sealed", {"player": by, "species": sp})
	_discard_effects(player_of(sp), "two_by_two")


# --- Plagas y trampas -------------------------------------------------------------

## Pasa hasta `count` plagas de la reserva a una habitación. Devuelve cuántas.
func _add_pests(sp: int, room: int, count: int) -> int:
	var n := mini(count, reserve[sp])
	if n <= 0:
		return 0
	reserve[sp] -= n
	pests[room][sp] += n
	return n


## Quita hasta `count` plagas propias de la habitación del exterminador y las
## devuelve a la reserva. Devuelve cuántas quitó.
func exterminate(pid: int, count: int) -> int:
	return _remove_pests(pid, exterminator_room[pid], count)


func _through_walls(sp: int) -> bool:
	return D.ability(sp, "through_walls")


func _drop_trap(pid: int, prefer_queen: bool) -> int:
	var trap := {"id": _next_trap_id, "owner": pid, "room": exterminator_room[pid],
		"pests": 0, "queen": false, "prefer_queen": prefer_queen}
	_next_trap_id += 1
	traps.append(trap)
	event.emit(&"trap_dropped", {"player": pid, "trap": trap["id"], "room": trap["room"]})
	_resolve_traps()
	return trap["id"]


## Vacía una trampa propia. Si tenía a la reina, el jugador gana.
func _empty_trap(pid: int, t: Dictionary) -> void:
	traps.erase(t)
	if t["queen"]:
		event.emit(&"queen_trap_emptied", {"player": pid})
		phase = Phase.FINISHED
		var winners: Array[int] = [pid]
		finish(winners)
		return
	reserve[species_of[pid]] += t["pests"]
	event.emit(&"trap_emptied", {"player": pid, "pests": t["pests"]})


## Las trampas atrapan lo que haya de su color: la reina (si la trampa está
## vacía) o plagas hasta llenarse. La trampa amarilla también atrae las plagas
## de las habitaciones vecinas.
func _resolve_traps() -> void:
	for t in traps:
		if t["queen"]:
			continue
		var sp := trap_species(t)
		var room: int = t["room"]
		var queen_here: bool = queen_room[sp] == room and not is_queen_trapped(sp)
		if t["pests"] == 0 and queen_here and (t["prefer_queen"] or pests[room][sp] == 0):
			t["queen"] = true
			event.emit(&"queen_trapped", {"species": sp, "trap": t["id"], "room": room})
			_discard_effects(t["owner"], "fertile")
			continue
		var space := trap_capacity(t) - int(t["pests"])
		if space <= 0:
			continue
		var sources: Array[int] = [room]
		if D.ability(sp, "trap_attracts_adjacent"):
			sources.append_array(house.neighbors(room))
		var caught := 0
		for r in sources:
			var n := mini(space - caught, pests[r][sp])
			pests[r][sp] -= n
			caught += n
		if caught > 0:
			t["pests"] += caught
			event.emit(&"pests_trapped", {"species": sp, "trap": t["id"], "room": room, "count": caught})


## Devuelve una trampa a su dueño y deja libre su contenido en la habitación.
func _release_trap(t: Dictionary) -> void:
	var sp := trap_species(t)
	pests[t["room"]][sp] += t["pests"]
	traps.erase(t)


# --- Acciones legales ---------------------------------------------------------------

func get_legal_actions(pid: int) -> Array[GameAction]:
	var candidates: Array[GameAction] = []
	if finished or not pid in players_to_act():
		return candidates
	match phase:
		Phase.CHOOSE_SPECIES:
			for sp in available_species():
				candidates.append(GameAction.new(CHOOSE_SPECIES, pid, {"species": sp}))
		Phase.DRAFT:
			for card_id in draft_pool:
				candidates.append(GameAction.new(DRAFT_CARD, pid, {"card": card_id}))
		Phase.PLACE_TILES:
			for o in tile_options(pid):
				candidates.append(GameAction.new(PLACE_TILE, pid, o.duplicate()))
		Phase.QUEEN:
			candidates.append(GameAction.new(ROLL_QUEEN, pid))
			_card_candidates(pid, candidates)
		Phase.EXTERMINATOR:
			var here := exterminator_room[pid]
			for r in house.neighbors(here):
				candidates.append(GameAction.new(MOVE, pid, {"room": r}))
			candidates.append(GameAction.new(EXTERMINATE, pid))
			candidates.append(GameAction.new(DROP_TRAP, pid, {"target": "queen"}))
			var sp := species_of[pid]
			if queen_room[sp] == here and pests[here][sp] > 0:
				candidates.append(GameAction.new(DROP_TRAP, pid, {"target": "pests"}))
			for t in traps_in_room(here):
				candidates.append(GameAction.new(EMPTY_TRAP, pid, {"trap": t["id"]}))
				candidates.append(GameAction.new(DESTROY_TRAP, pid, {"trap": t["id"]}))
				for r in house.neighbors(here):
					candidates.append(GameAction.new(DRAG_TRAP, pid, {"trap": t["id"], "room": r}))
			candidates.append(GameAction.new(SEAL_NEST, pid))
			candidates.append(GameAction.new(UNSEAL_NEST, pid))
			candidates.append(GameAction.new(BUY_CARD, pid))
			_card_candidates(pid, candidates)
			candidates.append(GameAction.new(END_TURN, pid))
	var result: Array[GameAction] = []
	for a in candidates:
		if validate(a) == "":
			result.append(a)
	return result


func _card_candidates(pid: int, out: Array[GameAction]) -> void:
	var seen := {}
	for card_id in hands[pid]:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		for targets in card_targets(pid, card_id):
			var data: Dictionary = targets.duplicate()
			data["card"] = card_id
			out.append(GameAction.new(PLAY_CARD, pid, data))


## Posibles objetivos de una carta (sin validar): lista de diccionarios de
## datos para PLAY_CARD (sin la clave "card").
func card_targets(pid: int, card_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match card_id:
		"mind_control":
			for a in D.QueenAction.size():
				result.append({"queen_action": a})
		"colony_collapse":
			for r in most_infested_rooms(species_of[pid]):
				result.append({"room": r})
		"zap":
			for r in pests.size():
				if pests[r][species_of[pid]] > 0:
					result.append({"room": r})
		"trap_remote":
			for t in traps:
				if t["owner"] == pid:
					result.append({"trap": t["id"]})
		"trap_breaks":
			for t in traps:
				if t["owner"] != pid:
					result.append({"player": t["owner"], "trap": t["id"]})
		"royal_persuasion":
			for other in opponents(pid):
				for a in D.QueenAction.size():
					result.append({"player": other, "queen_action": a})
		"spreading":
			for other in opponents(pid):
				for r in pests.size():
					if pests[r][species_of[other]] > 0:
						result.append({"player": other, "room": r})
		"dumpster_diver":
			var seen := {}
			for used in discard:
				if seen.has(used) or used == "dumpster_diver" or D.card(used)["kind"] != D.CardKind.OFFENSIVE:
					continue
				seen[used] = true
				for t in card_targets(pid, used):
					var data: Dictionary = t.duplicate()
					data["use"] = used
					result.append(data)
		_:
			if D.card(card_id)["kind"] == D.CardKind.OFFENSIVE:
				for other in opponents(pid):
					result.append({"player": other})
			else:
				result.append({})
	return result


# --- Utilidades ---------------------------------------------------------------------

static func _filled(count: int, value: Variant) -> Array:
	var result := []
	result.resize(count)
	result.fill(value)
	return result
