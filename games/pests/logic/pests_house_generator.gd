class_name PestsHouseGenerator
extends RefCounted
## Construye casas al azar (determinista con la semilla). Sirve para la
## partida rápida, para la IA cuando le toca colocar losetas y para los tests.

const D := preload("res://games/pests/logic/pests_defs.gd")

## Intentos completos antes de rendirse (en la práctica basta el primero).
const MAX_ATTEMPTS := 50


## Losetas en juego para una partida: las estándar que no se devuelven a la
## caja y los nidos de las especies en juego. Cada loseta es un Dictionary
## {"kind": RoomKind, "tile": índice estándar o -1, "species": especie o -1}.
static func tiles_for_game(species: Array[int], rng: BGCRng) -> Array[Dictionary]:
	var standard: Array = range(D.STANDARD_TILES.size())
	rng.shuffle(standard)
	var removed: int = D.TILES_REMOVED[species.size()]
	var result: Array[Dictionary] = []
	for i in range(removed, standard.size()):
		result.append({"kind": D.RoomKind.STANDARD, "tile": standard[i], "species": -1})
	for s in species:
		result.append({"kind": D.RoomKind.NEST, "tile": -1, "species": s})
	return result


## Puertas sin girar de una loseta de tiles_for_game().
static func tile_doors(tile: Dictionary) -> int:
	if tile["kind"] == D.RoomKind.NEST:
		return D.NEST_DOORS
	return D.STANDARD_TILES[tile["tile"]]["doors"]


## Coloca una loseta en la casa (sin validar).
static func place_tile(house: PestsHouse, tile: Dictionary, cell: Vector2i, rotation: int) -> int:
	if tile["kind"] == D.RoomKind.NEST:
		return house.place_nest(cell, tile["species"], rotation)
	return house.place_standard(cell, tile["tile"], rotation)


## Casa con todas las losetas colocadas al azar en un orden aleatorio.
## Devuelve null si no lo consigue (no debería pasar con las losetas reales).
static func generate(tiles: Array[Dictionary], rng: BGCRng) -> PestsHouse:
	for attempt in MAX_ATTEMPTS:
		var order := tiles.duplicate()
		rng.shuffle(order)
		var house := _try_build(order, rng)
		if house != null:
			return house
	return null


static func _try_build(order: Array, rng: BGCRng) -> PestsHouse:
	var house := PestsHouse.new()
	var pending: Array = order.duplicate()
	while not pending.is_empty():
		# Coloca la primera loseta pendiente que quepa en algún sitio.
		var placed := false
		for i in pending.size():
			var tile: Dictionary = pending[i]
			var options := house.placements_for(tile_doors(tile))
			if options.is_empty():
				continue
			var choice: Dictionary = rng.pick(options)
			place_tile(house, tile, choice["cell"], choice["rotation"])
			pending.remove_at(i)
			placed = true
			break
		if not placed:
			return null
	return house
