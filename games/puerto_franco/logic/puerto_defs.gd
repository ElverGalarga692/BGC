class_name PuertoDefs
extends RefCounted
## Constantes de Puerto Franco: gremios, edificios, cargos, objetivos y la
## forma del barrio de cada jugador.
##
## Las cartas de edificio son enteros: el índice del edificio en BUILDINGS
## (así se guardan y se envían por red sin más). Las casillas del barrio
## también son enteros: el índice en CELLS (0 = la Lonja, en el centro).

enum Guild { TRADE, SEA, CRAFT, ARTS, WONDER }

const GUILD_COUNT := 4  # gremios normales (sin contar las maravillas)
const GUILD_NAMES := {
	Guild.TRADE: "Comercio",
	Guild.SEA: "Mar",
	Guild.CRAFT: "Oficios",
	Guild.ARTS: "Artes",
	Guild.WONDER: "Maravilla",
}
const GUILD_COLORS := {
	Guild.TRADE: Color("d9a440"),
	Guild.SEA: Color("3f7fb8"),
	Guild.CRAFT: Color("b8583f"),
	Guild.ARTS: Color("7f5bb0"),
	Guild.WONDER: Color("3f9f7a"),
}

## Efectos de las maravillas (solo hay una de cada).
enum Wonder {
	NONE,
	GUILD_HALL,     # +1 punto por cada edificio del gremio `guild_bonus`
	PLAZA,          # +2 puntos por cada edificio vecino
	CUSTOMS,        # +1 moneda extra cada vez que cobras monedas
	SHIPYARD_ROYAL, # cuando cobras del muelle, robas además 1 carta a ciegas
	GARDENS,        # cuenta como de cualquier gremio para los grupos
	LIGHTHOUSE,     # al final, +1 punto por cada 2 monedas que te queden
}

## Cada edificio: nombre, gremio, coste, copias en el mazo y, si es una
## maravilla, su efecto (y el gremio al que da puntos, si aplica).
const BUILDINGS: Array[Dictionary] = [
	# Comercio
	{"name": "Puesto de fruta", "guild": Guild.TRADE, "cost": 1, "copies": 4},
	{"name": "Taberna", "guild": Guild.TRADE, "cost": 2, "copies": 4},
	{"name": "Tienda de especias", "guild": Guild.TRADE, "cost": 3, "copies": 3},
	{"name": "Casa de cambio", "guild": Guild.TRADE, "cost": 4, "copies": 2},
	{"name": "Banco", "guild": Guild.TRADE, "cost": 5, "copies": 1},
	# Mar
	{"name": "Embarcadero", "guild": Guild.SEA, "cost": 1, "copies": 4},
	{"name": "Almacén de redes", "guild": Guild.SEA, "cost": 2, "copies": 4},
	{"name": "Atarazana", "guild": Guild.SEA, "cost": 3, "copies": 3},
	{"name": "Casa del práctico", "guild": Guild.SEA, "cost": 4, "copies": 2},
	{"name": "Dique seco", "guild": Guild.SEA, "cost": 5, "copies": 1},
	# Oficios
	{"name": "Cordelería", "guild": Guild.CRAFT, "cost": 1, "copies": 4},
	{"name": "Herrería", "guild": Guild.CRAFT, "cost": 2, "copies": 4},
	{"name": "Tejeduría", "guild": Guild.CRAFT, "cost": 3, "copies": 3},
	{"name": "Vidriería", "guild": Guild.CRAFT, "cost": 4, "copies": 2},
	{"name": "Fundición", "guild": Guild.CRAFT, "cost": 5, "copies": 1},
	# Artes
	{"name": "Fuente", "guild": Guild.ARTS, "cost": 1, "copies": 4},
	{"name": "Teatrillo", "guild": Guild.ARTS, "cost": 2, "copies": 4},
	{"name": "Biblioteca", "guild": Guild.ARTS, "cost": 3, "copies": 3},
	{"name": "Academia", "guild": Guild.ARTS, "cost": 4, "copies": 2},
	{"name": "Ópera", "guild": Guild.ARTS, "cost": 5, "copies": 1},
	# Maravillas
	{"name": "Gran Mercado", "guild": Guild.WONDER, "cost": 5, "copies": 1, "wonder": Wonder.GUILD_HALL, "guild_bonus": Guild.TRADE},
	{"name": "Arsenal", "guild": Guild.WONDER, "cost": 5, "copies": 1, "wonder": Wonder.GUILD_HALL, "guild_bonus": Guild.SEA},
	{"name": "Casa de los Gremios", "guild": Guild.WONDER, "cost": 5, "copies": 1, "wonder": Wonder.GUILD_HALL, "guild_bonus": Guild.CRAFT},
	{"name": "Museo", "guild": Guild.WONDER, "cost": 5, "copies": 1, "wonder": Wonder.GUILD_HALL, "guild_bonus": Guild.ARTS},
	{"name": "Plaza Mayor", "guild": Guild.WONDER, "cost": 4, "copies": 1, "wonder": Wonder.PLAZA},
	{"name": "Aduana", "guild": Guild.WONDER, "cost": 6, "copies": 1, "wonder": Wonder.CUSTOMS},
	{"name": "Astillero Real", "guild": Guild.WONDER, "cost": 6, "copies": 1, "wonder": Wonder.SHIPYARD_ROYAL},
	{"name": "Jardines", "guild": Guild.WONDER, "cost": 4, "copies": 1, "wonder": Wonder.GARDENS},
	{"name": "Faro", "guild": Guild.WONDER, "cost": 6, "copies": 1, "wonder": Wonder.LIGHTHOUSE},
]

## Cargos del consejo, en orden de turno (el número es su índice + 1).
enum Office { HARBOR, SMUGGLER, COLLECTOR, PLANNER, BUILDER, PATRON, MAYOR }

const OFFICE_COUNT := 7
const OFFICE_NAMES := {
	Office.HARBOR: "Capitana de puerto",
	Office.SMUGGLER: "Contrabandista",
	Office.COLLECTOR: "Recaudadora",
	Office.PLANNER: "Urbanista",
	Office.BUILDER: "Maestra de obras",
	Office.PATRON: "Mecenas",
	Office.MAYOR: "Alcaldesa",
}
const OFFICE_TEXT := {
	Office.HARBOR: "Coge gratis 1 carta del muelle. Después se renueva el muelle entero.",
	Office.SMUGGLER: "Coge 1 carta al azar de la mano de otro jugador.",
	Office.COLLECTOR: "Cada jugador con más monedas que tú te paga 1 moneda.",
	Office.PLANNER: "Tus edificios cuestan 2 menos este turno. Puedes trasladar uno de tus edificios.",
	Office.BUILDER: "Puedes construir 2 edificios este turno.",
	Office.PATRON: "Gana 1 moneda por cada grupo de vecinos del mismo gremio de tu barrio (máx. 4).",
	Office.MAYOR: "Al empezar tu turno coges la vara (desempatas y eliges primero), robas 1 carta y ganas 1 moneda.",
}
## Cargos con habilidad que se usa con una acción (el resto es automática).
const ACTIVE_OFFICES := [Office.HARBOR, Office.SMUGGLER, Office.COLLECTOR, Office.PLANNER, Office.PATRON]

## Objetivos públicos (se sacan OBJECTIVES_PER_GAME al azar por partida).
enum Objective { MOST_TRADE, MOST_SEA, MOST_CRAFT, MOST_ARTS, BIGGEST_GROUP, RICHEST, WONDERS }

const OBJECTIVE_NAMES := {
	Objective.MOST_TRADE: "Plaza de los mercaderes",
	Objective.MOST_SEA: "Muelle animado",
	Objective.MOST_CRAFT: "Calle de los talleres",
	Objective.MOST_ARTS: "Barrio de las artes",
	Objective.BIGGEST_GROUP: "Manzana perfecta",
	Objective.RICHEST: "Arcas llenas",
	Objective.WONDERS: "Ciudad de maravillas",
}
const OBJECTIVE_TEXT := {
	Objective.MOST_TRADE: "Más edificios de Comercio",
	Objective.MOST_SEA: "Más edificios de Mar",
	Objective.MOST_CRAFT: "Más edificios de Oficios",
	Objective.MOST_ARTS: "Más edificios de Artes",
	Objective.BIGGEST_GROUP: "El grupo de vecinos del mismo gremio más grande",
	Objective.RICHEST: "Más monedas al final",
	Objective.WONDERS: "Más maravillas",
}
const OBJECTIVE_COUNT := 7
const OBJECTIVES_PER_GAME := 2
## Puntos de un objetivo (si empatan varios, todos los cobran).
const OBJECTIVE_POINTS := 4

## Barrio: hexágono de radio 2 (19 casillas). La 0 es la Lonja.
const DISTRICT_RADIUS := 2
const CELLS: Array[Vector2i] = [
	Vector2i(0, 0),
	# anillo 1
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	# anillo 2
	Vector2i(2, 0), Vector2i(2, -1), Vector2i(2, -2), Vector2i(1, -2), Vector2i(0, -2), Vector2i(-1, -1),
	Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1),
]
const LONJA_CELL := 0
## Sin edificio (y la Lonja, que no es una carta).
const EMPTY := -1
const LONJA := -2

const START_COINS := 3
const START_HAND := 4
const DOCK_SIZE := 4
const COIN_INCOME := 2
## Edificios (sin contar la Lonja) que cierran la partida al final de la ronda.
const BUILDINGS_TO_END := 9
const FIRST_TO_FINISH_POINTS := 3
## Máximo de monedas que se acumulan sobre un cargo vacante.
const MAX_VACANT_COINS := 3
const PATRON_MAX := 4
const PLANNER_DISCOUNT := 2
const MAYOR_COINS := 1


static func building(card: int) -> Dictionary:
	return BUILDINGS[card]


static func card_name(card: int) -> String:
	if card == LONJA:
		return "Lonja"
	if card < 0 or card >= BUILDINGS.size():
		return "?"
	return BUILDINGS[card]["name"]


static func guild_of(card: int) -> int:
	return BUILDINGS[card]["guild"] if card >= 0 and card < BUILDINGS.size() else -1


static func cost_of(card: int) -> int:
	return BUILDINGS[card]["cost"] if card >= 0 and card < BUILDINGS.size() else 0


static func wonder_of(card: int) -> int:
	return BUILDINGS[card].get("wonder", Wonder.NONE) if card >= 0 and card < BUILDINGS.size() else Wonder.NONE


static func is_wonder(card: int) -> bool:
	return guild_of(card) == Guild.WONDER


## Con tantos jugadores o más se añade una copia de cada edificio normal de
## coste EXTRA_MAX_COST o menos (si no, el mazo se agota a mitad de partida).
const EXTRA_COPIES_FROM := 5
const EXTRA_MAX_COST := 3


## Mazo completo para `player_count` jugadores, sin barajar.
static func deck(player_count: int = 4) -> Array[int]:
	var cards: Array[int] = []
	for i in BUILDINGS.size():
		var copies: int = BUILDINGS[i]["copies"]
		if player_count >= EXTRA_COPIES_FROM and not is_wonder(i) and cost_of(i) <= EXTRA_MAX_COST:
			copies += 1
		for c in copies:
			cards.append(i)
	return cards


static func cell_index(h: Vector2i) -> int:
	return CELLS.find(h)


## Casillas vecinas de `cell` dentro del barrio.
static func cell_neighbors(cell: int) -> Array[int]:
	var result: Array[int] = []
	for h in HexCoords.neighbors(CELLS[cell]):
		var i := CELLS.find(h)
		if i >= 0:
			result.append(i)
	return result


## Casillas libres vecinas de algo construido (o de la Lonja).
static func buildable_cells(district: Array) -> Array[int]:
	var result: Array[int] = []
	for cell in district.size():
		if district[cell] != EMPTY:
			continue
		for n in cell_neighbors(cell):
			if district[n] != EMPTY:
				result.append(cell)
				break
	return result


## true si todo lo construido está unido a la Lonja por vecinos.
static func all_linked(district: Array) -> bool:
	var seen := {LONJA_CELL: true}
	var stack: Array[int] = [LONJA_CELL]
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		for n in cell_neighbors(cell):
			if district[n] != EMPTY and not seen.has(n):
				seen[n] = true
				stack.append(n)
	for cell in district.size():
		if district[cell] != EMPTY and not seen.has(cell):
			return false
	return true


## true si la casilla cuenta para los grupos del gremio `guild` (los
## Jardines cuentan como de cualquier gremio).
static func counts_as(card: int, guild: int) -> bool:
	if card < 0:
		return false
	return guild_of(card) == guild or wonder_of(card) == Wonder.GARDENS


## Grupos de vecinos del mismo gremio con 2 o más edificios:
## [{"guild", "cells"}]. Unos Jardines pueden estar en grupos de varios gremios.
static func groups(district: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for guild in GUILD_COUNT:
		var seen := {}
		for start in district.size():
			if seen.has(start) or not counts_as(district[start], guild):
				continue
			var cells: Array[int] = []
			var stack: Array[int] = [start]
			seen[start] = true
			var has_real := false
			while not stack.is_empty():
				var cell: int = stack.pop_back()
				cells.append(cell)
				if guild_of(district[cell]) == guild:
					has_real = true
				for n in cell_neighbors(cell):
					if not seen.has(n) and counts_as(district[n], guild):
						seen[n] = true
						stack.append(n)
			# Un grupo solo de Jardines no es de ningún gremio.
			if cells.size() >= 2 and has_real:
				cells.sort()
				result.append({"guild": guild, "cells": cells})
	return result


static func group_count(district: Array) -> int:
	return groups(district).size()


static func guild_count(district: Array, guild: int) -> int:
	var count := 0
	for c in district:
		if c >= 0 and guild_of(c) == guild:
			count += 1
	return count


static func biggest_group(district: Array) -> int:
	var best := 0
	for g in groups(district):
		best = maxi(best, g["cells"].size())
	return best


## Valor de un jugador para un objetivo (más es mejor).
static func objective_value(obj: int, district: Array, coins: int) -> int:
	match obj:
		Objective.MOST_TRADE:
			return guild_count(district, Guild.TRADE)
		Objective.MOST_SEA:
			return guild_count(district, Guild.SEA)
		Objective.MOST_CRAFT:
			return guild_count(district, Guild.CRAFT)
		Objective.MOST_ARTS:
			return guild_count(district, Guild.ARTS)
		Objective.BIGGEST_GROUP:
			return biggest_group(district)
		Objective.RICHEST:
			return coins
		Objective.WONDERS:
			return guild_count(district, Guild.WONDER)
	return 0


## Puntos del barrio (sin objetivos ni el extra por terminar primero):
##   buildings  suma de los costes
##   groups     cada grupo de vecinos del mismo gremio da 1 punto por edificio
##   wonders    puntos de las maravillas
##   total
static func score_district(district: Array, coins: int) -> Dictionary:
	var buildings := 0
	for c in district:
		if c >= 0:
			buildings += cost_of(c)
	var group_points := 0
	for g in groups(district):
		group_points += g["cells"].size()
	var wonder_points := 0
	for cell in district.size():
		var c: int = district[cell]
		if c < 0:
			continue
		match wonder_of(c):
			Wonder.GUILD_HALL:
				wonder_points += guild_count(district, BUILDINGS[c]["guild_bonus"])
			Wonder.PLAZA:
				for n in cell_neighbors(cell):
					if district[n] >= 0:
						wonder_points += 2
			Wonder.LIGHTHOUSE:
				@warning_ignore("integer_division")
				wonder_points += coins / 2
	return {
		"buildings": buildings,
		"groups": group_points,
		"wonders": wonder_points,
		"total": buildings + group_points + wonder_points,
	}
