class_name ArchDefs
extends RefCounted
## Constantes de Archipiélago: terrenos, recursos, números y puertos.

enum Terrain { DESERT, FOREST, HILLS, PASTURE, FIELDS, MOUNTAINS }
enum ResourceType { WOOD, BRICK, WOOL, GRAIN, ORE }

## Recurso que produce cada terreno (-1 = ninguno).
const TERRAIN_RESOURCE := {
	Terrain.DESERT: -1,
	Terrain.FOREST: ResourceType.WOOD,
	Terrain.HILLS: ResourceType.BRICK,
	Terrain.PASTURE: ResourceType.WOOL,
	Terrain.FIELDS: ResourceType.GRAIN,
	Terrain.MOUNTAINS: ResourceType.ORE,
}

const TERRAIN_NAMES := {
	Terrain.DESERT: "Desierto",
	Terrain.FOREST: "Bosque",
	Terrain.HILLS: "Colinas",
	Terrain.PASTURE: "Pastos",
	Terrain.FIELDS: "Campos",
	Terrain.MOUNTAINS: "Montañas",
}

const RESOURCE_NAMES := {
	ResourceType.WOOD: "Madera",
	ResourceType.BRICK: "Ladrillo",
	ResourceType.WOOL: "Lana",
	ResourceType.GRAIN: "Trigo",
	ResourceType.ORE: "Mineral",
}

const TERRAIN_COLORS := {
	Terrain.DESERT: Color("e3cf98"),
	Terrain.FOREST: Color("2f7a3b"),
	Terrain.HILLS: Color("c4623a"),
	Terrain.PASTURE: Color("9ccc5a"),
	Terrain.FIELDS: Color("e8c33f"),
	Terrain.MOUNTAINS: Color("8a8f99"),
}

## Casillas de cada terreno en el tablero estándar de 19 casillas.
const TERRAIN_COUNTS := {
	Terrain.DESERT: 1,
	Terrain.FOREST: 4,
	Terrain.HILLS: 3,
	Terrain.PASTURE: 4,
	Terrain.FIELDS: 4,
	Terrain.MOUNTAINS: 3,
}

## Fichas numéricas (una por casilla que no sea desierto).
const NUMBER_TOKENS := [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

## Números que no pueden quedar en casillas vecinas.
const HOT_NUMBERS := [6, 8]

## Valor de puerto para el comercio genérico 3:1.
const PORT_GENERIC := -1

## Puertos: 4 genéricos (3:1) y uno 2:1 por recurso.
const PORT_TYPES := [
	PORT_GENERIC, PORT_GENERIC, PORT_GENERIC, PORT_GENERIC,
	ResourceType.WOOD, ResourceType.BRICK, ResourceType.WOOL, ResourceType.GRAIN, ResourceType.ORE,
]

const BOARD_RADIUS := 2

## Cartas de desarrollo.
enum DevCard { MILITIA, MONUMENT, ROAD_BUILDING, HARVEST, MONOPOLY }

const DEV_NAMES := {
	DevCard.MILITIA: "Miliciano",
	DevCard.MONUMENT: "Monumento",
	DevCard.ROAD_BUILDING: "Ingenieros",
	DevCard.HARVEST: "Cosecha abundante",
	DevCard.MONOPOLY: "Monopolio",
}

const DEV_DESCRIPTIONS := {
	DevCard.MILITIA: "Mueve el bandido y roba una carta. Cuenta para la Mayor milicia.",
	DevCard.MONUMENT: "1 punto de victoria (oculto para los demás).",
	DevCard.ROAD_BUILDING: "Construye 2 caminos gratis.",
	DevCard.HARVEST: "Toma 2 recursos cualesquiera de la banca.",
	DevCard.MONOPOLY: "Elige un recurso: todos los jugadores te dan todas sus cartas de ese recurso.",
}

## Cartas de cada tipo en el mazo.
const DEV_DECK := {
	DevCard.MILITIA: 14,
	DevCard.MONUMENT: 5,
	DevCard.ROAD_BUILDING: 2,
	DevCard.HARVEST: 2,
	DevCard.MONOPOLY: 2,
}


## Lista de terrenos (sin barajar) para el tablero estándar.
static func terrain_pool() -> Array[int]:
	var pool: Array[int] = []
	for terrain in TERRAIN_COUNTS:
		for i in TERRAIN_COUNTS[terrain]:
			pool.append(terrain)
	return pool


## Mazo de cartas de desarrollo (sin barajar).
static func dev_deck() -> Array[int]:
	var deck: Array[int] = []
	for card in DEV_DECK:
		for i in DEV_DECK[card]:
			deck.append(card)
	return deck


## Número de combinaciones de 2d6 que suman `n` (los "puntos" de la ficha).
static func number_pips(n: int) -> int:
	if n < 2 or n > 12:
		return 0
	return 6 - absi(7 - n)


static func port_ratio(port_type: int) -> int:
	return 3 if port_type == PORT_GENERIC else 2


static func port_label(port_type: int) -> String:
	if port_type == PORT_GENERIC:
		return "3:1"
	return "2:1 %s" % RESOURCE_NAMES[port_type]
