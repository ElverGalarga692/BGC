class_name BajamarDefs
extends RefCounted
## Constantes de Bajamar: cartas, mazo y puntuación de una red.
##
## Las cartas son enteros (así se guardan y se envían por red sin más):
##   pez       especie * 10 + valor   (especie 0..4, valor 1..6 → 1..46)
##   tormenta  STORM
## Las cartas especiales (Gaviota, Red reforzada, Marea alta) llegan en la
## fase 2 y usarán los números a partir de SPECIAL_BASE.

enum Species { SARDINE, MACKEREL, OCTOPUS, HAKE, TUNA }

const SPECIES_COUNT := 5
const SPECIES_NAMES := {
	Species.SARDINE: "Sardina",
	Species.MACKEREL: "Caballa",
	Species.OCTOPUS: "Pulpo",
	Species.HAKE: "Merluza",
	Species.TUNA: "Atún",
}
const SPECIES_COLORS := {
	Species.SARDINE: Color("9fb8c8"),
	Species.MACKEREL: Color("3f8f8a"),
	Species.OCTOPUS: Color("c4566b"),
	Species.HAKE: Color("d9c48c"),
	Species.TUNA: Color("3f5fa8"),
}

const MIN_VALUE := 1
const MAX_VALUE := 6
## Copias de cada pez (especie y valor) en el mazo.
const FISH_COPIES := 2
const STORM_COUNT := 8

const STORM := 100
const SPECIAL_BASE := 101

## Cartas boca arriba en el mercado.
const MARKET_SIZE := 3
## Puntos para ganar la partida (se comprueba al final de cada ronda).
const TARGET_SCORE := 150
## Escaleras: valores distintos seguidos. Desde RUN_MIN cartas puntúan
## RUN_POINTS por cada carta a partir de la tercera (1-2-3 = 5, 1-2-3-4 = 10).
const RUN_MIN := 3
const RUN_POINTS := 5


static func fish(species: int, value: int) -> int:
	assert(species >= 0 and species < SPECIES_COUNT)
	assert(value >= MIN_VALUE and value <= MAX_VALUE)
	return species * 10 + value


static func is_fish(card: int) -> bool:
	if card < 1 or card >= STORM:
		return false
	var v := card % 10
	return card / 10 < SPECIES_COUNT and v >= MIN_VALUE and v <= MAX_VALUE


static func is_storm(card: int) -> bool:
	return card == STORM


static func species_of(card: int) -> int:
	return card / 10 if is_fish(card) else -1


static func value_of(card: int) -> int:
	return card % 10 if is_fish(card) else 0


static func card_name(card: int) -> String:
	if is_storm(card):
		return "Tormenta"
	if is_fish(card):
		return "%s %d" % [SPECIES_NAMES[species_of(card)], value_of(card)]
	return "Carta %d" % card


## Mazo completo, sin barajar.
static func deck() -> Array[int]:
	var cards: Array[int] = []
	for s in SPECIES_COUNT:
		for v in range(MIN_VALUE, MAX_VALUE + 1):
			for c in FISH_COPIES:
				cards.append(fish(s, v))
	for i in STORM_COUNT:
		cards.append(STORM)
	return cards


## Puntuación de una red que vuelve a puerto. Devuelve el desglose:
##   base           suma de los valores de los peces
##   best_species   especie que vale doble (-1 si no hay peces)
##   species_bonus  puntos extra por esa especie (la suma de sus valores)
##   runs           escaleras que puntúan, cada una [desde, hasta]
##   run_bonus      puntos de las escaleras
##   total
##
## Vale doble la especie con más cartas; si empatan, la que más suma y, si
## siguen empatadas, la primera en el orden de Species.
static func score(net: Array) -> Dictionary:
	var base := 0
	var counts: Array[int] = []
	var sums: Array[int] = []
	counts.resize(SPECIES_COUNT)
	sums.resize(SPECIES_COUNT)
	var present := {}
	for card in net:
		if not is_fish(card):
			continue
		var s := species_of(card)
		var v := value_of(card)
		base += v
		counts[s] += 1
		sums[s] += v
		present[v] = true
	var best := -1
	for s in SPECIES_COUNT:
		if counts[s] == 0:
			continue
		if best == -1 or counts[s] > counts[best] or (counts[s] == counts[best] and sums[s] > sums[best]):
			best = s
	var species_bonus := sums[best] if best >= 0 else 0
	var runs: Array = []
	var run_bonus := 0
	var v := MIN_VALUE
	while v <= MAX_VALUE:
		if not present.has(v):
			v += 1
			continue
		var start := v
		while present.has(v + 1):
			v += 1
		var length := v - start + 1
		if length >= RUN_MIN:
			runs.append([start, v])
			run_bonus += RUN_POINTS * (length - RUN_MIN + 1)
		v += 1
	return {
		"base": base,
		"best_species": best,
		"species_bonus": species_bonus,
		"runs": runs,
		"run_bonus": run_bonus,
		"total": base + species_bonus + run_bonus,
	}
