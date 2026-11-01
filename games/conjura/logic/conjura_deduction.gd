class_name ConjuraDeduction
extends RefCounted
## Deducción de La Conjura: probabilidad de que cada jugador sea de la Sombra
## (Sombra o Usurpador), vista desde un asiento.
##
## Método: se enumeran TODOS los repartos posibles de traidores (con 10
## jugadores y 4 traidores son solo 210) que respetan lo que se sabe seguro
## (tu rol, tus aliados, lo espiado). Cada reparto se pondera por lo
## verosímiles que son los hechos observados si fuera el verdadero:
##   - qué edicto promulgó cada gobierno (un gobierno honrado rara vez
##     promulga Sombra);
##   - declaraciones que no cuadran (alguien miente: es de la Sombra);
##   - lo que sabe solo este asiento (qué pasó como Regente, qué recibió
##     como Consejero, Augurio y Pesquisa);
##   - votos a favor de gobiernos que promulgaron Sombra (señal débil).
## La probabilidad de cada jugador es la suma de los pesos de los repartos
## en los que es traidor.
##
## Solo usa una vista de ConjuraGame.view_for(): con view_for(-1) da la
## opinión «pública» (lo que puede pensar cualquiera de la mesa).

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const G := preload("res://games/conjura/logic/conjura_game.gd")
const Edict := ConjuraDefs.Edict
const Faction := ConjuraDefs.Faction

## Casi imposible (no 0, para que un dato contradictorio no anule todo).
const NEVER := 0.002
## Verosimilitud del edicto según quién es traidor en el gobierno.
## Índice: 0 = los dos honrados, 1 = solo el Consejero traidor,
## 2 = solo el Regente traidor, 3 = los dos traidores.
const EDICT_LIKELIHOOD := {
	Edict.SOMBRA: [0.25, 0.75, 0.6, 0.9],
	Edict.GUARDIA: [0.75, 0.35, 0.45, 0.15],
	Edict.NEUTRAL: [1.0, 1.0, 1.0, 1.0],
}
## Factor por cada voto a favor de un gobierno que promulgó Sombra (traidor
## frente a honrado).
const VOTE_RATIO_SOMBRA := 1.15
const VOTE_RATIO_GUARDIA := 0.92

## Máscaras de repartos posibles: "n,k" -> Array[int].
static var _masks := {}


## Probabilidad de que cada jugador sea de la Sombra. Para quien mira, la
## suya es 0 o 1.
static func evil_probabilities(view: Dictionary) -> Array[float]:
	var n: int = view["player_count"]
	var k: int = D.ROLE_TABLE[n][1] + 1
	var must_in := 0
	var must_out := 0
	var known: Dictionary = view["known_roles"]
	for pid in known:
		if D.faction_of(known[pid]) == Faction.SOMBRA:
			must_in |= 1 << int(pid)
		else:
			must_out |= 1 << int(pid)
	var knowledge: Array = view["knowledge"]
	for kn in knowledge:
		if kn["kind"] == "faction":
			if kn["faction"] == Faction.SOMBRA:
				must_in |= 1 << int(kn["target"])
			else:
				must_out |= 1 << int(kn["target"])

	# Factores de cada gobierno: [regente, consejero, tabla de 4].
	var tables: Array = []
	var ratio: Array[float] = []
	ratio.resize(n)
	ratio.fill(1.0)
	var governments: Array = view["governments"]
	for i in governments.size():
		var gov: Dictionary = governments[i]
		if not gov["approved"] or gov["crisis"] or int(gov["edict"]) < 0:
			continue
		tables.append([int(gov["regent"]), int(gov["nominee"]), _gov_table(gov, i, view)])
		var votes: Dictionary = gov["votes"]
		for pid in votes:
			if votes[pid]:
				match int(gov["edict"]):
					Edict.SOMBRA: ratio[int(pid)] *= VOTE_RATIO_SOMBRA
					Edict.GUARDIA: ratio[int(pid)] *= VOTE_RATIO_GUARDIA

	var probs: Array[float] = []
	probs.resize(n)
	probs.fill(0.0)
	var total := 0.0
	for mask in _all_masks(n, k):
		if mask & must_in != must_in or mask & must_out != 0:
			continue
		var w := 1.0
		for t in tables:
			var r: int = (mask >> t[0]) & 1
			var c: int = (mask >> t[1]) & 1
			w *= t[2][r * 2 + c]
		for pid in n:
			if mask & (1 << pid):
				w *= ratio[pid]
		if w <= 0.0:
			continue
		total += w
		for pid in n:
			if mask & (1 << pid):
				probs[pid] += w
	if total <= 0.0:
		# Datos imposibles (no debería pasar): sin opinión.
		probs.fill(float(k) / n)
		return probs
	for pid in n:
		probs[pid] /= total
	return probs


## Probabilidad de que en el gobierno (regente, consejero) haya algún traidor.
static func government_risk(probs: Array[float], regent: int, council: int) -> float:
	return 1.0 - (1.0 - probs[regent]) * (1.0 - probs[council])


static func _all_masks(n: int, k: int) -> Array:
	var key := "%d,%d" % [n, k]
	if _masks.has(key):
		return _masks[key]
	var result: Array = []
	for mask in 1 << n:
		var bits := 0
		var m := mask
		while m:
			bits += m & 1
			m >>= 1
		if bits == k:
			result.append(mask)
	_masks[key] = result
	return result


## Verosimilitud de lo ocurrido en un gobierno según quién es traidor.
static func _gov_table(gov: Dictionary, index: int, view: Dictionary) -> Array[float]:
	var edict: int = gov["edict"]
	var t: Array[float] = []
	t.assign(EDICT_LIKELIHOOD[edict])
	# Declaraciones públicas que no cuadran.
	for conflict in G.claim_conflicts(gov):
		match conflict:
			"council": _council_lies(t)
			"regent": _regent_lies(t)
			"pair":
				t[0] *= NEVER * 10.0  # al menos uno miente
	var claims: Dictionary = gov.get("claims", {})
	var rc = claims.get("regent")
	var cc = claims.get("council")
	# Lo que solo sabe este asiento.
	var received: Array = []
	for kn in view["knowledge"]:
		if int(kn.get("round", -2)) != index:
			continue
		match String(kn["kind"]):
			"drawn":
				# Fui Regente: sé qué pasé al Consejero.
				var passed: Array = kn.get("passed", [])
				if passed.is_empty():
					continue
				var sorted_passed := passed.duplicate()
				sorted_passed.sort()
				if cc != null and cc != sorted_passed:
					_council_lies(t)
				if edict == Edict.SOMBRA and Edict.GUARDIA in passed:
					# Eligió Sombra teniendo Guardia.
					t[0] *= 0.08
					t[2] *= 0.08
			"received":
				# Fui Consejero: sé qué me pasó el Regente.
				received = kn["cards"]
				if rc != null and not G.can_pass(rc, received):
					_regent_lies(t)
				if received.count(Edict.SOMBRA) == 2:
					# Un Regente honrado solo pasa dos de la Sombra si robó tres.
					t[0] *= 0.3
					t[1] *= 0.3
	for kn in view["knowledge"]:
		if int(kn.get("round", -2)) != index:
			continue
		if kn["kind"] == "discarded" and not received.is_empty():
			# Pesquisa: con lo recibido, sé exactamente qué robó el Regente.
			var drawn: Array = received.duplicate()
			drawn.append(int(kn["card"]))
			drawn.sort()
			if rc != null and rc != drawn:
				_regent_lies(t)
			if int(kn["card"]) == Edict.GUARDIA and Edict.SOMBRA in received:
				_regent_lies(t)  # descartó Guardia quedándose Sombra
	# Augurio: sé qué iba a robar el siguiente Regente.
	for kn in view["knowledge"]:
		if kn["kind"] != "top" or _first_legislation_after(view["governments"], int(kn["round"])) != index:
			continue
		var top: Array = kn["cards"].duplicate()
		top.sort()
		if rc != null and rc != top:
			_regent_lies(t)
		if edict == Edict.SOMBRA and Edict.GUARDIA in top:
			t[0] *= 0.08  # había Guardia y salió Sombra: alguien lo eligió
	return t


static func _council_lies(t: Array[float]) -> void:
	t[0] *= NEVER
	t[2] *= NEVER


static func _regent_lies(t: Array[float]) -> void:
	t[0] *= NEVER
	t[1] *= NEVER


## Índice del primer gobierno desde `from` que robó del mazo (o -1 si antes
## hubo una crisis, que se lleva el primer edicto).
static func _first_legislation_after(governments: Array, from: int) -> int:
	for i in range(from, governments.size()):
		var gov: Dictionary = governments[i]
		if gov["crisis"]:
			return -1
		if gov["approved"]:
			return i
	return -1
