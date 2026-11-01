class_name PestsGame
extends GameBase
## Lógica de una partida de Pests! (sin cartas de herramientas todavía).
##
## Fases:
##   CHOOSE_SPECIES  cada jugador elige exterminador, en sentido antihorario
##                   desde el jugador inicial (se salta con "quick_species").
##   PLACE_TILES     se construye la casa loseta a loseta, en sentido horario
##                   desde el jugador inicial (se salta con "auto_house").
##   QUEEN           el jugador tira el dado de su reina (dos veces en su
##                   primer turno).
##   EXTERMINATOR    movimiento gratis + 2 puntos de acción; termina con END_TURN.
##   FINISHED
##
## El jugador inicial elige exterminador el primero, coloca la primera loseta
## y juega el primer turno (con el orden del reglamento siempre coincide).
##
## Las plagas se guardan por habitación y por especie. Cada especie tiene una
## reserva y un total en juego ("pool"): pool = reserva + en la casa + en
## trampas. Las plagas exterminadas vuelven a la reserva.

signal event(kind: StringName, data: Dictionary)

const D := preload("res://games/pests/logic/pests_defs.gd")

enum Phase { CHOOSE_SPECIES, PLACE_TILES, QUEEN, EXTERMINATOR, FINISHED }

const CHOOSE_SPECIES := &"choose_species"  # {"species": int}
const PLACE_TILE := &"place_tile"          # {"index": int, "x": int, "y": int, "rotation": int}
const ROLL_QUEEN := &"roll_queen"
const MOVE := &"move"                      # {"room": int}
const EXTERMINATE := &"exterminate"
const DROP_TRAP := &"drop_trap"            # {"target": "queen" | "pests"} (opcional, por defecto la reina)
const EMPTY_TRAP := &"empty_trap"          # {"trap": id}
const DRAG_TRAP := &"drag_trap"            # {"trap": id, "room": int}
const SEAL_NEST := &"seal_nest"
const DESTROY_TRAP := &"destroy_trap"      # {"trap": id}
const UNSEAL_NEST := &"unseal_nest"
const END_TURN := &"end_turn"

const PHASE_ACTIONS := {
	Phase.CHOOSE_SPECIES: [CHOOSE_SPECIES],
	Phase.PLACE_TILES: [PLACE_TILE],
	Phase.QUEEN: [ROLL_QUEEN],
	Phase.EXTERMINATOR: [MOVE, EXTERMINATE, DROP_TRAP, EMPTY_TRAP, DRAG_TRAP, SEAL_NEST, DESTROY_TRAP, UNSEAL_NEST, END_TURN],
	Phase.FINISHED: [],
}

## Coste en PA de cada acción del exterminador (MOVE y las que dependen de la
## especie se calculan en action_cost()).
const ACTION_ACTS := {
	MOVE: D.Act.MOVE,
	EXTERMINATE: D.Act.EXTERMINATE,
	DROP_TRAP: D.Act.DROP_TRAP,
	EMPTY_TRAP: D.Act.EMPTY_TRAP,
	DRAG_TRAP: D.Act.DRAG_TRAP,
	SEAL_NEST: D.Act.SEAL_NEST,
	DESTROY_TRAP: D.Act.DESTROY_TRAP,
	UNSEAL_NEST: D.Act.UNSEAL_NEST,
}

## Opciones de la partida. Se fijan antes de setup() y se guardan con la
## partida.
##   quick_species: reparte los exterminadores al azar.
##   auto_house: construye la casa al azar.
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

## Turno en curso.
var queen_rolls_left := 0
var free_move := false
var action_points := 0
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
	queen_rolls_left = 0
	free_move = false
	action_points = 0
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


## Coste en PA de una acción del exterminador.
func action_cost(pid: int, type: StringName, data: Dictionary = {}) -> int:
	if type == MOVE:
		return 0 if free_move else 1
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
	var hand: Array = tile_hands[pid]
	for i in hand.size():
		var tile: Dictionary = hand[i]
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
		var cost := action_cost(pid, type, data)
		if cost > action_points:
			return "No te quedan puntos de acción suficientes (necesitas %d)" % cost
	var sp := species_of[pid]
	var here := exterminator_room[pid] if pid < exterminator_room.size() else -1
	match type:
		CHOOSE_SPECIES:
			var s := int(data.get("species", -1))
			if s < 0 or s >= D.SPECIES_COUNT:
				return "Exterminador no válido"
			if s in species_of:
				return "Ese exterminador ya está elegido"
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
			var target := String(data.get("target", "queen"))
			if not target in ["queen", "pests"]:
				return "Objetivo de la trampa no válido"
			return ""
		EMPTY_TRAP:
			var t := find_trap(int(data.get("trap", -1)))
			if t.is_empty() or t["owner"] != pid:
				return "Esa trampa no es tuya"
			if t["room"] != here:
				return "La trampa no está en tu habitación"
			if t["queen"] and not can_empty_queen_trap(pid):
				return "Para vaciar la trampa con tu reina necesitas el nido sellado y ninguna plaga tuya en la casa"
			return ""
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
	return "Acción desconocida"


## ¿Puede el jugador vaciar la trampa con su reina (y ganar)?
func can_empty_queen_trap(pid: int) -> bool:
	var sp := species_of[pid]
	return sealed[sp] and pests_in_house(sp) == 0


func _phase_hint() -> String:
	match phase:
		Phase.CHOOSE_SPECIES:
			return "Ahora toca elegir exterminador"
		Phase.PLACE_TILES:
			return "Ahora toca colocar una loseta"
		Phase.QUEEN:
			return "Primero tira el dado de la reina"
	return "Ahora no puedes hacer eso"


# --- Aplicación -------------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	var data := action.data
	var type := action.type
	if phase == Phase.EXTERMINATOR and type != END_TURN:
		var cost := action_cost(pid, type, data)
		if type == MOVE and free_move:
			free_move = false
		else:
			action_points -= cost
			free_move = false
	match type:
		CHOOSE_SPECIES:
			species_of[pid] = int(data["species"])
			event.emit(&"species_chosen", {"player": pid, "species": species_of[pid]})
			turns.next()
			if not turns.in_sequence():
				_begin_house()
		PLACE_TILE:
			_apply_place_tile(pid, data)
		ROLL_QUEEN:
			var face := rng.randi_range(0, D.QUEEN_DIE.size() - 1)
			data["face"] = face
			resolve_queen_face(species_of[pid], face)
			queen_rolls_left -= 1
			if queen_rolls_left <= 0:
				phase = Phase.EXTERMINATOR
				free_move = true
				action_points = D.ACTION_POINTS
		MOVE:
			exterminator_room[pid] = int(data["room"])
			event.emit(&"exterminator_moved", {"player": pid, "room": exterminator_room[pid]})
		EXTERMINATE:
			last_roll = rng.roll(6)
			data["roll"] = last_roll
			data["removed"] = exterminate(pid, last_roll + int(ability(pid, "exterminate_bonus")))
		DROP_TRAP:
			var trap := {"id": _next_trap_id, "owner": pid, "room": exterminator_room[pid],
				"pests": 0, "queen": false, "prefer_queen": String(data.get("target", "queen")) == "queen"}
			_next_trap_id += 1
			traps.append(trap)
			data["trap"] = trap["id"]
			event.emit(&"trap_dropped", {"player": pid, "trap": trap["id"], "room": trap["room"]})
			_resolve_traps()
		EMPTY_TRAP:
			var t := find_trap(int(data["trap"]))
			if t["queen"]:
				traps.erase(t)
				event.emit(&"queen_trap_emptied", {"player": pid})
				phase = Phase.FINISHED
				var winners: Array[int] = [pid]
				finish(winners)
				return
			reserve[species_of[pid]] += t["pests"]
			traps.erase(t)
			event.emit(&"trap_emptied", {"player": pid, "pests": t["pests"]})
		DRAG_TRAP:
			var t := find_trap(int(data["trap"]))
			var room := int(data["room"])
			t["room"] = room
			exterminator_room[pid] = room
			event.emit(&"trap_dragged", {"player": pid, "trap": t["id"], "room": room})
			_resolve_traps()
		SEAL_NEST:
			sealed[species_of[pid]] = true
			event.emit(&"nest_sealed", {"player": pid, "species": species_of[pid]})
		DESTROY_TRAP:
			var t := find_trap(int(data["trap"]))
			_release_trap(t)
			event.emit(&"trap_destroyed", {"player": pid, "owner": t["owner"], "room": t["room"]})
			_resolve_traps()
		UNSEAL_NEST:
			var nest_species := house.room_species[exterminator_room[pid]]
			sealed[nest_species] = false
			event.emit(&"nest_unsealed", {"player": pid, "species": nest_species})
		END_TURN:
			_end_turn(pid)


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
	for hand in tile_hands:
		if not hand.is_empty():
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
	queen_rolls_left = 2 if turns_taken[pid] == 0 else 1
	free_move = false
	action_points = 0
	event.emit(&"turn_started", {"player": pid})


func _end_turn(pid: int) -> void:
	turns_taken[pid] += 1
	free_move = false
	action_points = 0
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


func _wrapped(from: int, to: int) -> bool:
	# ¿Pasa el turno por el jugador inicial al ir de `from` a `to`?
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
## la casa, queda eliminado y sus piezas salen del tablero.
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
	event.emit(&"player_eliminated", {"player": pid, "species": sp})
	return true


# --- La reina ---------------------------------------------------------------------

## Resuelve una cara del dado de la reina de la especie `sp`: acción, plagas
## que suelta y plagas que salen del nido.
func resolve_queen_face(sp: int, face: int) -> void:
	last_queen_face = face
	var f: Dictionary = D.QUEEN_DIE[face]
	var action: int = f["action"]
	event.emit(&"queen_rolled", {"species": sp, "face": face, "action": action})
	var trap := queen_trap(sp)
	if not trap.is_empty():
		if f["species"] == sp:
			traps.erase(trap)
			event.emit(&"queen_escaped", {"species": sp, "room": queen_room[sp]})
			_queen_drop(sp, D.QUEEN_DROP)
		_nest_spawn(sp)
		_resolve_traps()
		return
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
	var added := _add_pests(sp, queen_room[sp], count)
	event.emit(&"queen_dropped", {"species": sp, "room": queen_room[sp], "count": added})


func _nest_spawn(sp: int) -> void:
	if sealed[sp]:
		return
	var nest := house.nest_of(sp)
	var added := _add_pests(sp, nest, int(D.ability(sp, "nest_spawn")))
	event.emit(&"nest_spawned", {"species": sp, "room": nest, "count": added})


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
	var sp := species_of[pid]
	var room := exterminator_room[pid]
	var removed := mini(count, pests[room][sp])
	pests[room][sp] -= removed
	reserve[sp] += removed
	event.emit(&"pests_exterminated", {"player": pid, "room": room, "count": removed})
	return removed


func _through_walls(sp: int) -> bool:
	return D.ability(sp, "through_walls")


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
		Phase.PLACE_TILES:
			for o in tile_options(pid):
				candidates.append(GameAction.new(PLACE_TILE, pid, o.duplicate()))
		Phase.QUEEN:
			candidates.append(GameAction.new(ROLL_QUEEN, pid))
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
			candidates.append(GameAction.new(END_TURN, pid))
	var result: Array[GameAction] = []
	for a in candidates:
		if validate(a) == "":
			result.append(a)
	return result


# --- Utilidades ---------------------------------------------------------------------

static func _filled(count: int, value: Variant) -> Array:
	var result := []
	result.resize(count)
	result.fill(value)
	return result
