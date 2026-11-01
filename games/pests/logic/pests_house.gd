class_name PestsHouse
extends RefCounted
## La casa de Pests!: una cuadrícula de habitaciones cuadradas unidas por
## puertas. Son datos puros, sin nodos.
##
## Cada habitación ocupa una casilla (Vector2i, con y hacia abajo) y se
## identifica por su índice. La entrada es siempre la habitación 0, en (0, 0);
## su jardín ocupa la casilla de debajo y no admite losetas.
##
## Aquí está todo lo que depende de la forma de la casa: validar la colocación
## de losetas, vecinos, distancias, hacia dónde avanzan las plagas al ser
## invocadas, el reparto en orden DLUR y adónde va la reina cuando sale de la
## casa.

const D := preload("res://games/pests/logic/pests_defs.gd")

## Resultado de intentar mover la reina en una dirección.
enum Step {
	MOVED,      # entró en la habitación de al lado
	BLOCKED,    # pared: no puede moverse (la reina se enfada)
	REENTERED,  # salió de la casa y volvió a entrar por otra habitación
	COURTYARD,  # salió a un patio interior sin otra entrada: vuelve a su habitación
}

const ENTRY_CELL := Vector2i(0, 0)
const LAWN_CELL := Vector2i(0, 1)

var room_cell: Array[Vector2i] = []
## Puertas ya giradas (máscara de PestsDefs.DOOR_*).
var room_doors: Array[int] = []
var room_kind: Array[int] = []
## Especie del nido (-1 si no es un nido).
var room_species: Array[int] = []
## Índice en PestsDefs.STANDARD_TILES (-1 para la entrada y los nidos).
var room_tile: Array[int] = []
## Cuartos de vuelta aplicados a la loseta (para dibujarla).
var room_rotation: Array[int] = []

var _cell_room: Dictionary = {}
var _blocked: Dictionary = {}


func _init() -> void:
	_blocked[LAWN_CELL] = true
	_add_room(ENTRY_CELL, D.ENTRY_DOORS, D.RoomKind.ENTRY, -1, -1, 0)


# --- Consultas básicas ------------------------------------------------------------

func room_count() -> int:
	return room_cell.size()


## Habitación en esa casilla, o -1.
func room_at(cell: Vector2i) -> int:
	return _cell_room.get(cell, -1)


func is_blocked(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func has_door(room: int, dir: int) -> bool:
	return (room_doors[room] & D.dir_bit(dir)) != 0


## Nido de una especie, o -1 si no está en la casa.
func nest_of(species: int) -> int:
	for r in room_count():
		if room_species[r] == species:
			return r
	return -1


func room_name(room: int) -> String:
	match room_kind[room]:
		D.RoomKind.ENTRY:
			return D.ENTRY_NAME
		D.RoomKind.NEST:
			return D.nest_name(room_species[room])
	return D.STANDARD_TILES[room_tile[room]]["name"]


## Rectángulo que ocupa la casa (incluido el jardín).
func bounds() -> Rect2i:
	var lo := LAWN_CELL
	var hi := LAWN_CELL
	for c in room_cell:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


# --- Colocación de losetas ------------------------------------------------------------

## Comprueba si se puede poner una loseta con esas puertas (ya giradas) en
## `cell`. Devuelve "" si se puede, o el motivo.
##
## Reglas: la casilla está libre, toca alguna habitación, todas las puertas
## que dan a una habitación coinciden con una puerta suya (y al revés) y al
## menos una puerta la conecta con la casa. Las puertas al exterior están
## permitidas.
func can_place(cell: Vector2i, doors: int) -> String:
	if room_at(cell) >= 0:
		return "Ya hay una habitación ahí"
	if is_blocked(cell):
		return "Ahí está el jardín de la entrada"
	var touches := false
	var connected := false
	for dir in 4:
		var other := room_at(cell + D.DIR_VECTORS[dir])
		if other < 0:
			continue
		touches = true
		var mine := (doors & D.dir_bit(dir)) != 0
		var theirs := has_door(other, D.opposite(dir))
		if mine != theirs:
			return "Las puertas no coinciden con la habitación de al lado"
		if mine:
			connected = true
	if not touches:
		return "Tiene que tocar una habitación de la casa"
	if not connected:
		return "Tiene que conectarse a la casa por una puerta"
	return ""


## Casillas libres junto a la casa, ordenadas (para la interfaz y la IA).
func frontier() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	for c in room_cell:
		for dir in D.DLUR:
			var n: Vector2i = c + D.DIR_VECTORS[dir]
			if room_at(n) < 0 and not is_blocked(n) and not seen.has(n):
				seen[n] = true
				result.append(n)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


## Todas las colocaciones válidas de una loseta con esas puertas (sin girar):
## una lista de {"cell": Vector2i, "rotation": int}. Las rotaciones que dan
## las mismas puertas se cuentan una sola vez.
func placements_for(base_doors: int) -> Array[Dictionary]:
	var rotations := distinct_rotations(base_doors)
	var result: Array[Dictionary] = []
	for cell in frontier():
		for r in rotations:
			if can_place(cell, D.rotate_doors(base_doors, r)) == "":
				result.append({"cell": cell, "rotation": r})
	return result


## Rotaciones (0..3) que producen máscaras distintas.
static func distinct_rotations(base_doors: int) -> Array[int]:
	var seen: Dictionary = {}
	var result: Array[int] = []
	for r in 4:
		var m := D.rotate_doors(base_doors, r)
		if not seen.has(m):
			seen[m] = true
			result.append(r)
	return result


## Coloca una loseta estándar. No valida: llama antes a can_place().
func place_standard(cell: Vector2i, tile: int, rotation: int) -> int:
	var doors := D.rotate_doors(D.STANDARD_TILES[tile]["doors"], rotation)
	return _add_room(cell, doors, D.RoomKind.STANDARD, -1, tile, rotation)


## Coloca un nido. No valida: llama antes a can_place().
func place_nest(cell: Vector2i, species: int, rotation: int = 0) -> int:
	var doors := D.rotate_doors(D.NEST_DOORS, rotation)
	return _add_room(cell, doors, D.RoomKind.NEST, species, -1, rotation)


## Puertas que tendría un nido "adaptado" en `cell`: puerta hacia cada casilla
## vacía y hacia cada habitación que tenga puerta hacia ella. Es el último
## recurso cuando un nido no cabe en ningún sitio con las reglas normales.
## Devuelve 0 si ni así se conectaría con la casa.
func fitted_nest_doors(cell: Vector2i) -> int:
	if room_at(cell) >= 0 or is_blocked(cell):
		return 0
	var doors := 0
	var connected := false
	for dir in 4:
		var other := room_at(cell + D.DIR_VECTORS[dir])
		if other < 0:
			doors |= D.dir_bit(dir)
		elif has_door(other, D.opposite(dir)):
			doors |= D.dir_bit(dir)
			connected = true
	return doors if connected else 0


## Coloca un nido con las puertas de fitted_nest_doors().
func place_fitted_nest(cell: Vector2i, species: int) -> int:
	var doors := fitted_nest_doors(cell)
	assert(doors != 0, "El nido no se puede conectar ahí")
	return _add_room(cell, doors, D.RoomKind.NEST, species, -1, 0)


## Coloca una habitación con puertas arbitrarias, sin validar (para tests y
## herramientas).
func place_custom(cell: Vector2i, doors: int) -> int:
	return _add_room(cell, doors, D.RoomKind.STANDARD, -1, -1, 0)


func _add_room(cell: Vector2i, doors: int, kind: int, species: int, tile: int, rotation: int) -> int:
	assert(room_at(cell) < 0 and not is_blocked(cell), "Casilla ocupada")
	var index := room_cell.size()
	room_cell.append(cell)
	room_doors.append(doors)
	room_kind.append(kind)
	room_species.append(species)
	room_tile.append(tile)
	room_rotation.append(rotation)
	_cell_room[cell] = index
	return index


# --- Vecinos y distancias ----------------------------------------------------------

## Habitación vecina en una dirección (-1 si no hay o si hay pared y no se
## atraviesan paredes).
func neighbor(room: int, dir: int, through_walls: bool = false) -> int:
	var other := room_at(room_cell[room] + D.DIR_VECTORS[dir])
	if other < 0:
		return -1
	if through_walls or has_door(room, dir):
		return other
	return -1


## Habitaciones vecinas en orden DLUR.
func neighbors(room: int, through_walls: bool = false) -> Array[int]:
	var result: Array[int] = []
	for dir in D.DLUR:
		var other := neighbor(room, dir, through_walls)
		if other >= 0:
			result.append(other)
	return result


## Distancia (en habitaciones) desde `from` a cada habitación alcanzable.
## La búsqueda expande los vecinos en orden DLUR, así que las claves quedan
## en un orden determinista.
func distances(from: int, through_walls: bool = false) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[int] = [from]
	var i := 0
	while i < queue.size():
		var r := queue[i]
		i += 1
		for n in neighbors(r, through_walls):
			if not dist.has(n):
				dist[n] = dist[r] + 1
				queue.append(n)
	return dist


## Distancia entre dos habitaciones (-1 si no están conectadas).
func distance(a: int, b: int, through_walls: bool = false) -> int:
	return distances(a, through_walls).get(b, -1)


## Habitaciones a exactamente `d` pasos, en orden de búsqueda DLUR.
func rooms_at_distance(room: int, d: int, through_walls: bool = false) -> Array[int]:
	var result: Array[int] = []
	var dist := distances(room, through_walls)
	for r in dist:
		if dist[r] == d:
			result.append(r)
	return result


## ¿Están todas las habitaciones conectadas a la entrada?
func is_fully_connected() -> bool:
	return distances(0).size() == room_count()


## Siguientes habitaciones en algún camino más corto de `from` a `target`,
## en orden DLUR. Vacío si ya está allí o no hay camino.
func steps_toward(from: int, target: int, through_walls: bool = false) -> Array[int]:
	var result: Array[int] = []
	if from == target:
		return result
	var dist := distances(target, through_walls)
	if not dist.has(from):
		return result
	for n in neighbors(from, through_walls):
		if dist.get(n, -1) == dist[from] - 1:
			result.append(n)
	return result


# --- Movimiento de plagas ---------------------------------------------------------------

## Reparte `count` plagas que están en `from` y avanzan una habitación hacia
## `target` (invocación de la reina). Si hay varios caminos igual de cortos,
## se reparten a partes iguales y las que sobran van en orden DLUR.
## Devuelve un Dictionary habitación -> plagas (las que no pueden avanzar se
## quedan en `from`).
func summon_split(from: int, count: int, target: int, through_walls: bool = false) -> Dictionary:
	var steps := steps_toward(from, target, through_walls)
	if steps.is_empty() or count <= 0:
		return {from: count} if count > 0 else {}
	return _split_evenly(count, steps)


## Reparte `count` plagas entre las habitaciones a `d` pasos de `room`, una a
## una en orden DLUR (dando la vuelta si hay menos habitaciones que plagas).
## Si no hay habitaciones a esa distancia se prueba más cerca y, en último
## caso, se quedan en `room`.
func spread(room: int, count: int, d: int = 1, through_walls: bool = false) -> Dictionary:
	var targets: Array[int] = []
	var k := d
	while targets.is_empty() and k >= 1:
		targets = rooms_at_distance(room, k, through_walls)
		k -= 1
	if targets.is_empty():
		return {room: count} if count > 0 else {}
	var result := {}
	for i in count:
		var r: int = targets[i % targets.size()]
		result[r] = result.get(r, 0) + 1
	return result


func _split_evenly(count: int, rooms: Array[int]) -> Dictionary:
	var result := {}
	var base := count / rooms.size()
	var extra := count % rooms.size()
	for i in rooms.size():
		var n := base + (1 if i < extra else 0)
		if n > 0:
			result[rooms[i]] = n
	return result


# --- Movimiento de la reina -----------------------------------------------------------------

## Intenta mover una habitación en `dir` desde `room`. Devuelve
## {"result": Step, "room": habitación final}.
##
## Si sale por una puerta exterior (o por una pared exterior, si atraviesa
## paredes), vuelve a entrar por la entrada más cercana a otra habitación
## recorriendo el exterior de la casa (ver reentry()).
func queen_step(room: int, dir: int, through_walls: bool = false) -> Dictionary:
	var cell: Vector2i = room_cell[room] + D.DIR_VECTORS[dir]
	var other := room_at(cell)
	if other >= 0:
		if through_walls or has_door(room, dir):
			return {"result": Step.MOVED, "room": other}
		return {"result": Step.BLOCKED, "room": room}
	if not (through_walls or has_door(room, dir)):
		return {"result": Step.BLOCKED, "room": room}
	var back := reentry(room, cell, through_walls)
	if back < 0:
		return {"result": Step.COURTYARD, "room": room}
	return {"result": Step.REENTERED, "room": back}


## Habitación por la que vuelve a entrar quien sale de `from_room` a la
## casilla vacía `exit_cell`, o -1 si está en un patio cerrado sin otra
## entrada.
##
## Se recorre el exterior casilla a casilla (las casillas vacías alrededor de
## la casa cuentan como si fueran habitaciones) hasta la primera casilla
## desde la que una puerta lleva a otra habitación. Quien atraviesa paredes
## puede entrar por cualquier pared. Si hay empate, gana la que se alcanza
## antes girando en el sentido de las agujas del reloj alrededor de la casa;
## si sigue habiendo empate, el orden DLUR.
func reentry(from_room: int, exit_cell: Vector2i, through_walls: bool = false) -> int:
	var area := bounds().grow(1)
	var dist := {exit_cell: 0}
	var queue: Array[Vector2i] = [exit_cell]
	var best_dist := -1
	var candidates: Array[Dictionary] = []
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		var dc: int = dist[c]
		if best_dist >= 0 and dc > best_dist:
			break
		for dir in D.DLUR:
			var n: Vector2i = c + D.DIR_VECTORS[dir]
			var r := room_at(n)
			if r >= 0:
				if r != from_room and (through_walls or has_door(r, D.opposite(dir))):
					best_dist = dc
					candidates.append({"cell": c, "room": r, "dlur": D.DLUR.find(dir)})
			elif area.has_point(n) and not dist.has(n):
				dist[n] = dc + 1
				queue.append(n)
	if candidates.is_empty():
		return -1
	var center := _center()
	var start_angle := (Vector2(exit_cell) - center).angle()
	var best: Dictionary = {}
	var best_key := Vector2.INF
	for cand in candidates:
		var delta := 0.0
		if cand["cell"] != exit_cell:
			delta = fposmod((Vector2(cand["cell"]) - center).angle() - start_angle, TAU)
		# Con la y hacia abajo, un ángulo creciente gira en el sentido del reloj.
		var key := Vector2(snappedf(delta, 0.0001), cand["dlur"])
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = cand
	return best["room"]


func _center() -> Vector2:
	var sum := Vector2.ZERO
	for c in room_cell:
		sum += Vector2(c)
	return sum / room_cell.size()
