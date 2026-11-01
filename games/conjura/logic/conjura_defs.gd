class_name ConjuraDefs
extends RefCounted
## Constantes de La Conjura: roles, edictos, poderes, reparto por número de
## jugadores y condiciones de victoria.

enum Role { GUARDIA, SOMBRA, USURPADOR }
enum Faction { GUARDIA, SOMBRA }
enum Edict { GUARDIA, SOMBRA, NEUTRAL }
enum Power { ESPIAR, AUGURIO, SUCESION, DESTIERRO, PESQUISA }

const MIN_PLAYERS := 5
const MAX_PLAYERS := 10

## Reparto de roles: jugadores -> [guardias, sombras] (más 1 Usurpador).
const ROLE_TABLE := {
	5: [3, 1], 6: [4, 1], 7: [4, 2], 8: [5, 2], 9: [5, 3], 10: [6, 3],
}
## Con este número de jugadores o menos, el Usurpador conoce a la Sombra.
const USURPER_KNOWS_ALLIES_MAX := 6

## Mazo de edictos.
const DECK := {Edict.GUARDIA: 6, Edict.SOMBRA: 11, Edict.NEUTRAL: 3}
## Con 6 u 8 jugadores la Sombra es proporcionalmente más pequeña: su mazo
## lleva edictos extra de la Sombra (equilibrado con simulaciones).
const EXTRA_SOMBRA := {6: 3, 8: 3}
## Mazo de poderes.
const POWER_DECK := {
	Power.ESPIAR: 3, Power.AUGURIO: 2, Power.SUCESION: 2, Power.DESTIERRO: 2, Power.PESQUISA: 2,
}

## Edictos para ganar.
const GUARDIA_TO_WIN := 5
const SOMBRA_TO_WIN := 6
## Con el descontento al máximo gana la facción con MENOS edictos.
const MAX_DISCONTENT := 4
## Votaciones fallidas seguidas que provocan una crisis.
const MAX_CRISIS := 3
## Desde este número de edictos de la Sombra, si el Usurpador sale elegido
## Consejero, gana la Sombra.
const USURPER_THRESHOLD := 3
## Desde este edicto de la Sombra (incluido), el Consejero recibe un poder.
const POWER_FROM := 2
## Edictos que roba el Regente en cada legislatura.
const HAND_SIZE := 3

const ROLE_NAMES := {
	Role.GUARDIA: "Guardia Real",
	Role.SOMBRA: "Hermandad de la Sombra",
	Role.USURPADOR: "Usurpador",
}
const FACTION_NAMES := {
	Faction.GUARDIA: "Guardia Real",
	Faction.SOMBRA: "Hermandad de la Sombra",
}
const EDICT_NAMES := {
	Edict.GUARDIA: "Edicto de la Guardia",
	Edict.SOMBRA: "Edicto de la Sombra",
	Edict.NEUTRAL: "Edicto neutral",
}
const EDICT_SHORT := {Edict.GUARDIA: "Guardia", Edict.SOMBRA: "Sombra", Edict.NEUTRAL: "Neutral"}
const POWER_NAMES := {
	Power.ESPIAR: "Espiar",
	Power.AUGURIO: "Augurio",
	Power.SUCESION: "Sucesión",
	Power.DESTIERRO: "Destierro",
	Power.PESQUISA: "Pesquisa",
}
const POWER_HELP := {
	Power.ESPIAR: "Mira en secreto la facción de otro jugador.",
	Power.AUGURIO: "Mira en secreto los 3 primeros edictos del mazo.",
	Power.SUCESION: "Elige quién será el próximo Regente.",
	Power.DESTIERRO: "Destierra a otro jugador: queda fuera de la partida.",
	Power.PESQUISA: "Mira en secreto el edicto que descartó el Regente.",
}

const COLOR_GUARDIA := Color("4f8fd6")
const COLOR_SOMBRA := Color("b8404f")
const COLOR_NEUTRAL := Color("c9a96e")


static func faction_of(role: int) -> int:
	return Faction.GUARDIA if role == Role.GUARDIA else Faction.SOMBRA


static func edict_color(edict: int) -> Color:
	match edict:
		Edict.GUARDIA: return COLOR_GUARDIA
		Edict.SOMBRA: return COLOR_SOMBRA
	return COLOR_NEUTRAL


static func faction_color(faction: int) -> Color:
	return COLOR_GUARDIA if faction == Faction.GUARDIA else COLOR_SOMBRA


static func power_needs_target(power: int) -> bool:
	return power in [Power.ESPIAR, Power.SUCESION, Power.DESTIERRO]
