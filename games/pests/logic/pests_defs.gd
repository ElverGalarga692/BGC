class_name PestsDefs
extends RefCounted
## Constantes de Pests!: especies (colores), habilidades de cada exterminador,
## dado de la reina, costes de las acciones, losetas de la casa y cartas de
## herramientas.
##
## Las decisiones sobre las reglas ambiguas de la edición de prueba v1.2 están
## explicadas en res://games/pests/rules.txt ("Aclaraciones").

# --- Especies ----------------------------------------------------------------

## Cada especie es un color y un jugador (su exterminador, su reina, su nido).
enum Species { YELLOW, GREEN, RED, BLUE, ORANGE, PURPLE }

const SPECIES_COUNT := 6

const SPECIES_NAMES := {
	Species.YELLOW: "Bichos voladores",
	Species.GREEN: "Rastreros escalofriantes",
	Species.RED: "Bestias aladas",
	Species.BLUE: "Alimañas feroces",
	Species.ORANGE: "Huéspedes indeseados",
	Species.PURPLE: "Espectros espeluznantes",
}

const COLOR_NAMES := {
	Species.YELLOW: "Amarillo",
	Species.GREEN: "Verde",
	Species.RED: "Rojo",
	Species.BLUE: "Azul",
	Species.ORANGE: "Naranja",
	Species.PURPLE: "Morado",
}

const SPECIES_COLORS := {
	Species.YELLOW: Color("e9d64a"),
	Species.GREEN: Color("4caf50"),
	Species.RED: Color("e2504c"),
	Species.BLUE: Color("4f6fc4"),
	Species.ORANGE: Color("f0a030"),
	Species.PURPLE: Color("9b5fc0"),
}

# --- Habilidades de los exterminadores --------------------------------------

## Valores por defecto. Cada especie cambia solo lo que dice su carta.
const DEFAULT_ABILITIES := {
	"traps": 1,                    # trampas disponibles
	"trap_capacity": 7,            # plagas que caben en una trampa
	"trap_attracts_adjacent": false,  # la trampa atrae plagas de las habitaciones vecinas
	"trap_destroy_cost": 1,        # PA que paga un rival para destruir tu trampa
	"queen_moves": 1,              # habitaciones que avanza la reina por tirada
	"exterminate_bonus": 0,        # se suma a la tirada del d6 al exterminar
	"populate_distance": 1,        # distancia a la que la reina reparte plagas (P)
	"through_walls": false,        # reina y plagas atraviesan paredes
	"seal_cost": 2,                # PA para sellar el nido propio
	"nest_spawn": 1,               # plagas que salen del nido cada turno
}

const SPECIES_ABILITIES := {
	Species.YELLOW: {"trap_attracts_adjacent": true, "queen_moves": 2},
	Species.GREEN: {"traps": 2},
	Species.RED: {"exterminate_bonus": 1, "populate_distance": 2},
	Species.BLUE: {"trap_capacity": 9},
	Species.ORANGE: {"seal_cost": 1, "nest_spawn": 2},
	Species.PURPLE: {"trap_destroy_cost": 2, "through_walls": true},
}

## Texto de la carta de exterminador (para la interfaz).
const SPECIES_ABILITY_TEXT := {
	Species.YELLOW: "La trampa atrae plagas de las habitaciones vecinas. La reina avanza 2 habitaciones por tirada.",
	Species.GREEN: "Tiene 2 trampas.",
	Species.RED: "+1 a las tiradas para exterminar. Cuando la reina puebla, las plagas aparecen a 2 habitaciones.",
	Species.BLUE: "Su trampa admite 9 plagas.",
	Species.ORANGE: "Sellar su nido cuesta solo 1 punto de acción. Su nido genera 1 plaga más cada turno.",
	Species.PURPLE: "Los rivales gastan 2 puntos de acción para destruir su trampa. La reina y las plagas atraviesan paredes.",
}


## Devuelve el valor de una habilidad para una especie.
static func ability(species: int, key: String) -> Variant:
	var own: Dictionary = SPECIES_ABILITIES.get(species, {})
	return own.get(key, DEFAULT_ABILITIES[key])


# --- Direcciones ---------------------------------------------------------------

## Direcciones absolutas de la casa según la rosa de los vientos de la
## entrada. Van en el sentido de las agujas del reloj.
enum Dir { UP, RIGHT, DOWN, LEFT }

const DIR_VECTORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES := ["Arriba", "Derecha", "Abajo", "Izquierda"]
const DIR_LETTERS := ["U", "R", "D", "L"]

## Orden DLUR: abajo, izquierda, arriba, derecha. Desempata casi todo.
const DLUR: Array[int] = [Dir.DOWN, Dir.LEFT, Dir.UP, Dir.RIGHT]

## Máscaras de puertas: un bit por dirección.
const DOOR_UP := 1
const DOOR_RIGHT := 2
const DOOR_DOWN := 4
const DOOR_LEFT := 8
const DOOR_ALL := 15


static func dir_bit(dir: int) -> int:
	return 1 << dir


static func opposite(dir: int) -> int:
	return (dir + 2) % 4


## Gira una máscara de puertas `quarter_turns` cuartos de vuelta en el sentido
## de las agujas del reloj.
static func rotate_doors(mask: int, quarter_turns: int) -> int:
	var r := posmod(quarter_turns, 4)
	var result := 0
	for d in 4:
		if mask & dir_bit(d):
			result |= dir_bit((d + r) % 4)
	return result


static func door_count(mask: int) -> int:
	var n := 0
	for d in 4:
		if mask & dir_bit(d):
			n += 1
	return n


# --- Dado de la reina ----------------------------------------------------------

enum QueenAction { UP, DOWN, LEFT, RIGHT, SUMMON, POPULATE }

const QUEEN_ACTION_NAMES := {
	QueenAction.UP: "Arriba",
	QueenAction.DOWN: "Abajo",
	QueenAction.LEFT: "Izquierda",
	QueenAction.RIGHT: "Derecha",
	QueenAction.SUMMON: "Invocar",
	QueenAction.POPULATE: "Poblar",
}

## Las 6 caras del dado: cada una tiene una acción y un color. Si sale el
## color de una reina atrapada, se escapa. La letra de cada cara coincide con
## la que aparece en la carta de exterminador de ese color.
const QUEEN_DIE := [
	{"letter": "L", "action": QueenAction.LEFT, "species": Species.YELLOW},
	{"letter": "R", "action": QueenAction.RIGHT, "species": Species.GREEN},
	{"letter": "U", "action": QueenAction.UP, "species": Species.RED},
	{"letter": "S", "action": QueenAction.SUMMON, "species": Species.BLUE},
	{"letter": "D", "action": QueenAction.DOWN, "species": Species.ORANGE},
	{"letter": "P", "action": QueenAction.POPULATE, "species": Species.PURPLE},
]

## Dirección de movimiento de cada acción (-1 si no es un movimiento).
static func queen_action_dir(action: int) -> int:
	match action:
		QueenAction.UP:
			return Dir.UP
		QueenAction.DOWN:
			return Dir.DOWN
		QueenAction.LEFT:
			return Dir.LEFT
		QueenAction.RIGHT:
			return Dir.RIGHT
	return -1


## Plagas que suelta la reina tras actuar, y cuántas suelta si no puede.
const QUEEN_DROP := 1
const QUEEN_ANGRY_DROP := 2
## Plagas que reparte al poblar (P).
const POPULATE_COUNT := 4

# --- Acciones del exterminador -------------------------------------------------

const ACTION_POINTS := 2
const FREE_MOVES := 1

enum Act {
	MOVE,
	EXTERMINATE,
	DROP_TRAP,
	EMPTY_TRAP,
	DRAG_TRAP,
	SEAL_NEST,
	DESTROY_TRAP,
	UNSEAL_NEST,
	PLAY_CARD,
	BUY_CARD,
}

const ACT_NAMES := {
	Act.MOVE: "Moverse",
	Act.EXTERMINATE: "Exterminar",
	Act.DROP_TRAP: "Soltar trampa",
	Act.EMPTY_TRAP: "Vaciar trampa",
	Act.DRAG_TRAP: "Arrastrar trampa",
	Act.SEAL_NEST: "Sellar nido",
	Act.DESTROY_TRAP: "Destruir trampa rival",
	Act.UNSEAL_NEST: "Desellar nido rival",
	Act.PLAY_CARD: "Jugar carta",
	Act.BUY_CARD: "Comprar carta",
}

## Coste base en puntos de acción. SEAL_NEST y DESTROY_TRAP pueden cambiar
## según la especie (ver act_cost).
const ACT_COSTS := {
	Act.MOVE: 1,
	Act.EXTERMINATE: 1,
	Act.DROP_TRAP: 1,
	Act.EMPTY_TRAP: 1,
	Act.DRAG_TRAP: 2,
	Act.SEAL_NEST: 2,
	Act.DESTROY_TRAP: 1,
	Act.UNSEAL_NEST: 2,
	Act.PLAY_CARD: 1,
	Act.BUY_CARD: 2,
}


## Coste de una acción para el exterminador `actor`. Para destruir una trampa,
## `trap_owner` es la especie dueña de esa trampa.
static func act_cost(act: int, actor: int, trap_owner: int = -1) -> int:
	match act:
		Act.SEAL_NEST:
			return ability(actor, "seal_cost")
		Act.DESTROY_TRAP:
			return ability(trap_owner, "trap_destroy_cost") if trap_owner >= 0 else ACT_COSTS[act]
	return ACT_COSTS[act]


# --- Preparación ---------------------------------------------------------------

const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
const PESTS_PER_SPECIES := 24
const CARDS_PER_HAND := 4
const INITIAL_NEST_PESTS := 3
const INITIAL_ADJACENT_PESTS := 4
## Ronda de colocación de losetas a partir de la cual se puede poner el nido.
const NEST_MIN_ROUND := 3

## Losetas estándar y plagas por especie que se devuelven a la caja.
const TILES_REMOVED := {2: 4, 3: 3, 4: 2, 5: 1, 6: 0}
const PESTS_REMOVED := {2: 4, 3: 3, 4: 2, 5: 1, 6: 0}


static func pests_in_play(player_count: int) -> int:
	return PESTS_PER_SPECIES - PESTS_REMOVED[player_count]


# --- Losetas -------------------------------------------------------------------

enum RoomKind { ENTRY, STANDARD, NEST }

## Puertas de la entrada (no gira): la rosa de los vientos marca "arriba".
## Abajo está el jardín, que ocupa la casilla de debajo y no admite losetas.
const ENTRY_DOORS := DOOR_UP | DOOR_LEFT | DOOR_RIGHT

## Puertas de los nidos: tienen puerta en los 4 lados.
const NEST_DOORS := DOOR_ALL

## Las 18 losetas estándar, con sus puertas tal como están impresas
## (sin girar).
const STANDARD_TILES := [
	{"name": "Vestidor", "doors": DOOR_UP | DOOR_DOWN},
	{"name": "Salón", "doors": DOOR_UP | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Despacho", "doors": DOOR_LEFT | DOOR_DOWN},
	{"name": "Lavadero", "doors": DOOR_UP | DOOR_RIGHT},
	{"name": "Recibidor", "doors": DOOR_LEFT | DOOR_RIGHT},
	{"name": "Sala de estar", "doors": DOOR_LEFT | DOOR_RIGHT},
	{"name": "Biblioteca", "doors": DOOR_UP | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Sala de juegos", "doors": DOOR_UP | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Sala de la chimenea", "doors": DOOR_UP | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Galería", "doors": DOOR_LEFT | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Baño", "doors": DOOR_LEFT | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Estudio", "doors": DOOR_LEFT | DOOR_RIGHT | DOOR_DOWN},
	{"name": "Sala de música", "doors": DOOR_ALL},
	{"name": "Almacén", "doors": DOOR_LEFT | DOOR_DOWN},
	{"name": "Dormitorio juvenil", "doors": DOOR_UP | DOOR_LEFT | DOOR_RIGHT},
	{"name": "Cocina", "doors": DOOR_ALL},
	{"name": "Cuarto de juguetes", "doors": DOOR_ALL},
	{"name": "Cuarto vacío", "doors": DOOR_ALL},
]

const ENTRY_NAME := "Entrada"


static func nest_name(species: int) -> String:
	return "Nido %s" % String(COLOR_NAMES[species]).to_lower()


# --- Cartas de herramientas ---------------------------------------------------

enum CardKind { DEFENSIVE, OFFENSIVE }

## Cuándo se puede jugar una carta.
enum CardTiming {
	ACTION,       # durante tu turno de exterminador; cuesta 1 PA
	BEFORE_ROLL,  # antes de tirar el dado de tu reina; gratis y no gasta el movimiento gratis
}

## Qué hay que elegir al jugarla.
enum CardTarget {
	NONE,
	PLAYER,           # otro jugador
	PLAYER_OPEN_NEST, # otro jugador con el nido abierto
	PLAYER_SEALED,    # otro jugador con el nido sellado
	PLAYER_FREE_QUEEN,# otro jugador cuya reina no está atrapada
	PLAYER_WITH_CARDS,# otro jugador con cartas en la mano
	NEST,             # cualquier nido (el suyo incluido)
	ROOM,             # cualquier habitación
	TRAP,             # una trampa rival en la casa
	DISCARD_OFFENSIVE,# una carta ofensiva del descarte
}

## Las 24 cartas (12 defensivas y 12 ofensivas), una copia de cada una.
## "persistent": se queda delante del jugador afectado hasta cumplir su
## condición.
const CARDS := [
	# Defensivas
	{"id": "more_time", "name": "Más tiempo", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Juega dos acciones extra este turno."},
	{"id": "hibernate", "name": "Las plagas hibernan", "kind": CardKind.DEFENSIVE, "timing": CardTiming.BEFORE_ROLL, "target": CardTarget.NONE, "persistent": false,
		"text": "Tu reina no tira el dado ni salen plagas nuevas del nido este turno. No cuesta acción."},
	{"id": "mating_call", "name": "Llamada de apareamiento", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Atrae todas las plagas de tu color dos habitaciones hacia ti."},
	{"id": "colony_collapse", "name": "Colapso de la colonia", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.ROOM, "persistent": false,
		"text": "Extermina la mitad (redondeando hacia arriba) de las plagas de tu color en la habitación más infestada."},
	{"id": "bug_bomb", "name": "Bomba insecticida", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Elimina todas las plagas de tu color en tu habitación."},
	{"id": "energy_drink", "name": "Bebida energética", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Como tu única acción, además de jugar esta carta, muévete hasta 4 habitaciones este turno."},
	{"id": "quik_trap", "name": "Trampa exprés", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Suelta y vacía inmediatamente una trampa en tu habitación."},
	{"id": "quik_seal", "name": "Sellado exprés", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Sella inmediatamente el nido de tu habitación."},
	{"id": "trap_remote", "name": "Trampa a distancia", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Vacía tu trampa aunque esté en otra habitación."},
	{"id": "nesting", "name": "De vuelta al nido", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NONE, "persistent": false,
		"text": "Devuelve tu reina (si no está atrapada) a su nido."},
	{"id": "zap", "name": "¡Zas!", "kind": CardKind.DEFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.ROOM, "persistent": false,
		"text": "Extermina hasta 3 plagas en cualquier habitación."},
	{"id": "mind_control", "name": "Control mental", "kind": CardKind.DEFENSIVE, "timing": CardTiming.BEFORE_ROLL, "target": CardTarget.NONE, "persistent": false,
		"text": "En vez de tirar el dado, elige la acción de tu reina. No cuesta acción."},
	# Ofensivas
	{"id": "unseal_nest", "name": "Desellar nido", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER_SEALED, "persistent": false,
		"text": "Quita el sello del nido de otro jugador."},
	{"id": "trap_breaks", "name": "Trampa rota", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.TRAP, "persistent": false,
		"text": "Devuelve una trampa a su jugador. Su contenido queda libre en la habitación donde estaba."},
	{"id": "pest_surge", "name": "Oleada de plagas", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.NEST, "persistent": false,
		"text": "Salen 5 plagas inmediatamente del nido elegido, aunque esté sellado."},
	{"id": "angry_queen", "name": "Reina furiosa", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER, "persistent": true,
		"text": "En su próximo turno, la reina de ese jugador realiza su acción completa dos veces."},
	{"id": "stuck", "name": "¡Atascado!", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER, "persistent": true,
		"text": "En su próximo turno, ese jugador pierde el movimiento gratis y solo tiene 1 acción."},
	{"id": "sabotage_tools", "name": "Herramientas saboteadas", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER_WITH_CARDS, "persistent": false,
		"text": "Descarta al azar una carta de otro jugador."},
	{"id": "less_to_infest", "name": "Menos que infestar", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER, "persistent": false,
		"text": "Quita 5 plagas de la reserva de otro jugador y devuélvelas a la caja."},
	{"id": "royal_persuasion", "name": "Persuasión real", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER, "persistent": true,
		"text": "En su próximo turno, tú eliges la acción de la reina de ese jugador."},
	{"id": "dumpster_diver", "name": "Buscador de basura", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.DISCARD_OFFENSIVE, "persistent": false,
		"text": "Toma una carta ofensiva del descarte y úsala inmediatamente."},
	{"id": "spreading", "name": "¡Se extienden!", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER, "persistent": false,
		"text": "Coloca 4 plagas de la reserva de otro jugador en habitaciones conectadas a una que ya tenga plagas de ese tipo (orden DLUR)."},
	{"id": "two_by_two", "name": "De dos en dos", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER_OPEN_NEST, "persistent": true,
		"text": "Hasta que selle su nido, sale 1 plaga más del nido de ese jugador cada turno."},
	{"id": "fertile", "name": "Fértil", "kind": CardKind.OFFENSIVE, "timing": CardTiming.ACTION, "target": CardTarget.PLAYER_FREE_QUEEN, "persistent": true,
		"text": "Hasta que sea atrapada, la reina de ese jugador suelta 1 plaga más cada turno."},
]


## Índice de una carta por su id (-1 si no existe).
static func card_index(card_id: String) -> int:
	for i in CARDS.size():
		if CARDS[i]["id"] == card_id:
			return i
	return -1


static func card(card_id: String) -> Dictionary:
	var i := card_index(card_id)
	return CARDS[i] if i >= 0 else {}
