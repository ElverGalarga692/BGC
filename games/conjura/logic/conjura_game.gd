class_name ConjuraGame
extends GameBase
## Lógica de La Conjura (roles ocultos y deducción social, 5–10 jugadores).
##
## Ronda: el Regente nomina a un Consejero y todos votan a la vez. Si se
## aprueba, el Regente roba 3 edictos y descarta 1, y el Consejero promulga
## 1 de los 2 restantes. Los edictos de la Sombra (desde el 2.º) dan al
## Consejero a elegir 1 de 2 poderes. Tres votaciones fallidas seguidas
## provocan una crisis: se promulga el primer edicto del mazo.
##
## INFORMACIÓN OCULTA: el estado completo vive aquí (roles, mazo, votos sin
## revelar...). La interfaz y la IA deben usar view_for(seat), que solo
## devuelve lo que ese asiento puede saber. players_to_act() dice quién
## puede actuar ahora (en la votación, varios a la vez).

signal event(kind: StringName, data: Dictionary)

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Faction := ConjuraDefs.Faction
const Edict := ConjuraDefs.Edict
const Power := ConjuraDefs.Power

enum Phase { NOMINATE, VOTE, REGENT_DISCARD, COUNCIL_ENACT, CLAIMS, CHOOSE_POWER, USE_POWER, FINISHED }

const NOMINATE := &"nominate"          # {"target": int}
const VOTE := &"vote"                  # {"yes": bool}
const DISCARD := &"discard"            # {"index": int} (Regente, de sus 3 edictos)
const ENACT := &"enact"                # {"index": int} (Consejero, de sus 2 edictos)
const CHOOSE_POWER := &"choose_power"  # {"index": int} (de las 2 opciones)
const USE_POWER := &"use_power"        # {"target": int} (-1 si el poder no lo necesita)
## Declaración pública tras la legislatura (puede ser mentira):
## {"cards": [edictos]} (3 el Regente, 2 el Consejero) o {"cards": null} para callar.
const CLAIM := &"claim"

const PHASE_NAMES := {
	Phase.NOMINATE: "Nominación",
	Phase.VOTE: "Votación",
	Phase.REGENT_DISCARD: "Legislatura: Regente",
	Phase.COUNCIL_ENACT: "Legislatura: Consejero",
	Phase.CLAIMS: "Declaraciones",
	Phase.CHOOSE_POWER: "Elegir poder",
	Phase.USE_POWER: "Usar poder",
	Phase.FINISHED: "Fin de la partida",
}

var phase := Phase.NOMINATE
var roles: Array[int] = []
var alive: Array[bool] = []

var regent := 0
## Último Regente del orden normal (la Sucesión no lo cambia).
var regent_cursor := 0
## Regente elegido con Sucesión para la próxima ronda (-1 = ninguno).
var special_regent := -1
var nominee := -1
var council := -1
## Último Consejero elegido: no puede repetir en la siguiente nominación.
var last_council := -1

## Votos de la votación en curso (pid -> bool). Secretos hasta el final.
var votes := {}
## Votos de la última votación resuelta (públicos).
var last_votes := {}

var draw_pile: Array[int] = []
var discard_pile: Array[int] = []
## Edictos en mano del Regente o del Consejero (secretos).
var hand: Array[int] = []
## Edicto que descartó el Regente en la legislatura actual (para Pesquisa).
var regent_discarded := -1

var guardia_edicts := 0
var sombra_edicts := 0
var discontent := 0
var crisis := 0

var power_deck: Array[int] = []
var power_options: Array[int] = []
var pending_power := -1

## Lo que sabe cada jugador en secreto: pid -> Array[Dictionary].
var knowledge: Array = []
## Historial público de gobiernos: {regent, nominee, votes, approved, edict}.
var governments: Array[Dictionary] = []

## Lo que de verdad pasó en cada legislatura (índice de gobierno ->
## {"drawn", "passed"}). Secreto hasta que termina la partida.
var truth := {}

var winner_faction := -1
var win_reason := ""


# --- Preparación ----------------------------------------------------------------

func _on_setup() -> void:
	var n := players.size()
	assert(D.ROLE_TABLE.has(n), "La Conjura es para 5–10 jugadores")
	var counts: Array = D.ROLE_TABLE[n]
	roles.clear()
	for i in counts[0]:
		roles.append(Role.GUARDIA)
	for i in counts[1]:
		roles.append(Role.SOMBRA)
	roles.append(Role.USURPADOR)
	rng.shuffle(roles)
	alive.clear()
	knowledge.clear()
	for i in n:
		alive.append(true)
		knowledge.append([])

	draw_pile.clear()
	for edict in D.DECK:
		for i in D.DECK[edict]:
			draw_pile.append(edict)
	for i in D.EXTRA_SOMBRA.get(n, 0):
		draw_pile.append(Edict.SOMBRA)
	rng.shuffle(draw_pile)
	discard_pile.clear()
	power_deck.clear()
	for power in D.POWER_DECK:
		for i in D.POWER_DECK[power]:
			power_deck.append(power)
	rng.shuffle(power_deck)

	regent = rng.randi_range(0, n - 1)
	regent_cursor = regent
	turns.current = regent
	phase = Phase.NOMINATE


# --- Consultas ------------------------------------------------------------------

func faction_of(pid: int) -> int:
	return D.faction_of(roles[pid])


func alive_ids() -> Array[int]:
	var result: Array[int] = []
	for i in players.size():
		if alive[i]:
			result.append(i)
	return result


## Quién puede actuar ahora.
func players_to_act() -> Array[int]:
	var result: Array[int] = []
	match phase:
		Phase.NOMINATE, Phase.REGENT_DISCARD:
			result.append(regent)
		Phase.VOTE:
			for pid in alive_ids():
				if not votes.has(pid):
					result.append(pid)
		Phase.COUNCIL_ENACT, Phase.CHOOSE_POWER, Phase.USE_POWER:
			result.append(council)
		Phase.CLAIMS:
			var claims: Dictionary = governments[-1]["claims"]
			if not claims.has("regent"):
				result.append(regent)
			if not claims.has("council"):
				result.append(council)
	return result


## Jugadores que el Regente puede nominar.
func eligible_nominees() -> Array[int]:
	var result: Array[int] = []
	for pid in alive_ids():
		if pid != regent and pid != last_council:
			result.append(pid)
	if result.is_empty() and last_council >= 0 and alive[last_council] and last_council != regent:
		result.append(last_council)
	return result


## Objetivos válidos del poder pendiente.
func power_targets() -> Array[int]:
	var result: Array[int] = []
	if pending_power < 0 or not D.power_needs_target(pending_power):
		return result
	for pid in alive_ids():
		if pid != council:
			result.append(pid)
	return result


## Roles que conoce `seat` (pid -> rol). Siempre incluye el suyo.
func known_roles(seat: int) -> Dictionary:
	var result := {}
	if finished:
		for i in players.size():
			result[i] = roles[i]
		return result
	if seat < 0:
		return result
	result[seat] = roles[seat]
	var role := roles[seat]
	var sees_allies := role == Role.SOMBRA or (role == Role.USURPADOR and players.size() <= D.USURPER_KNOWS_ALLIES_MAX)
	if sees_allies:
		for i in players.size():
			if roles[i] == Role.SOMBRA or (role == Role.SOMBRA and roles[i] == Role.USURPADOR):
				result[i] = roles[i]
	return result


## Lo que puede saber `seat` (-1 = solo lo público). La interfaz y la IA
## usan SOLO esto, nunca el estado interno.
func view_for(seat: int) -> Dictionary:
	var voted := {}
	for pid in votes:
		voted[pid] = true
	var view := {
		"seat": seat,
		"player_count": players.size(),
		"phase": phase,
		"regent": regent,
		"nominee": nominee,
		"council": council,
		"last_council": last_council,
		"alive": alive.duplicate(),
		"guardia_edicts": guardia_edicts,
		"sombra_edicts": sombra_edicts,
		"discontent": discontent,
		"crisis": crisis,
		"deck_count": draw_pile.size(),
		"discard_count": discard_pile.size(),
		"voted": voted,
		"last_votes": last_votes.duplicate(),
		"power_options": power_options.duplicate(),
		"pending_power": pending_power,
		"governments": governments.duplicate(true),
		"to_act": players_to_act(),
		"eligible": eligible_nominees() if phase == Phase.NOMINATE else [],
		"power_targets": power_targets(),
		"known_roles": known_roles(seat),
		"knowledge": [],
		"hand": [],
		"my_vote": null,
		"finished": finished,
		"winner_faction": winner_faction,
		"win_reason": win_reason,
	}
	if finished:
		view["truth"] = truth.duplicate(true)
	if seat >= 0 and seat < players.size():
		view["knowledge"] = knowledge[seat].duplicate(true)
		if votes.has(seat):
			view["my_vote"] = votes[seat]
		var holds := (phase == Phase.REGENT_DISCARD and seat == regent) or (phase == Phase.COUNCIL_ENACT and seat == council)
		if holds:
			view["hand"] = hand.duplicate()
	return view


# --- Validación -------------------------------------------------------------------

func validate(action: GameAction) -> String:
	var pid := action.player_id
	if pid < 0 or pid >= players.size():
		return "Jugador desconocido"
	if not alive[pid]:
		return "Los desterrados no pueden actuar"
	match action.type:
		NOMINATE:
			if phase != Phase.NOMINATE:
				return "Ahora no se nomina"
			if pid != regent:
				return "Solo el Regente nomina"
			var target := int(action.data.get("target", -1))
			if not target in eligible_nominees():
				return "Ese jugador no puede ser Consejero"
		VOTE:
			if phase != Phase.VOTE:
				return "Ahora no se vota"
			if votes.has(pid):
				return "Ya has votado"
			if not action.data.get("yes") is bool:
				return "Voto no válido"
		DISCARD:
			if phase != Phase.REGENT_DISCARD:
				return "Ahora no se descarta"
			if pid != regent:
				return "Solo el Regente descarta"
			var index := int(action.data.get("index", -1))
			if index < 0 or index >= hand.size():
				return "Edicto no válido"
		ENACT:
			if phase != Phase.COUNCIL_ENACT:
				return "Ahora no se promulga"
			if pid != council:
				return "Solo el Consejero promulga"
			var index := int(action.data.get("index", -1))
			if index < 0 or index >= hand.size():
				return "Edicto no válido"
		CHOOSE_POWER:
			if phase != Phase.CHOOSE_POWER:
				return "Ahora no se elige poder"
			if pid != council:
				return "Solo el Consejero elige el poder"
			var index := int(action.data.get("index", -1))
			if index < 0 or index >= power_options.size():
				return "Poder no válido"
		USE_POWER:
			if phase != Phase.USE_POWER:
				return "No hay ningún poder que usar"
			if pid != council:
				return "Solo el Consejero usa el poder"
			var target := int(action.data.get("target", -1))
			if D.power_needs_target(pending_power):
				if not target in power_targets():
					return "Objetivo no válido"
			elif target != -1:
				return "Este poder no necesita objetivo"
		CLAIM:
			if phase != Phase.CLAIMS:
				return "Ahora no se declara"
			if not pid in players_to_act():
				return "No te toca declarar"
			var cards = action.data.get("cards")
			if cards == null:
				return ""
			if not cards is Array or cards.size() != (D.HAND_SIZE if pid == regent else D.HAND_SIZE - 1):
				return "Declaración no válida"
			for c in cards:
				if not (c is int or c is float) or int(c) < 0 or int(c) > Edict.NEUTRAL:
					return "Declaración no válida"
		_:
			return "Acción no soportada: %s" % action.type
	return ""


## Todas las declaraciones posibles de `size` edictos (ordenadas).
static func claim_options(size: int) -> Array:
	var result: Array = []
	for g in range(size, -1, -1):
		for s in range(size - g, -1, -1):
			var cards: Array[int] = []
			for i in g:
				cards.append(Edict.GUARDIA)
			for i in s:
				cards.append(Edict.SOMBRA)
			for i in size - g - s:
				cards.append(Edict.NEUTRAL)
			result.append(cards)
	return result


func get_legal_actions(pid: int) -> Array[GameAction]:
	var result: Array[GameAction] = []
	if finished or not pid in players_to_act():
		return result
	match phase:
		Phase.NOMINATE:
			for t in eligible_nominees():
				result.append(GameAction.new(NOMINATE, pid, {"target": t}))
		Phase.VOTE:
			result.append(GameAction.new(VOTE, pid, {"yes": true}))
			result.append(GameAction.new(VOTE, pid, {"yes": false}))
		Phase.REGENT_DISCARD:
			for i in hand.size():
				result.append(GameAction.new(DISCARD, pid, {"index": i}))
		Phase.COUNCIL_ENACT:
			for i in hand.size():
				result.append(GameAction.new(ENACT, pid, {"index": i}))
		Phase.CHOOSE_POWER:
			for i in power_options.size():
				result.append(GameAction.new(CHOOSE_POWER, pid, {"index": i}))
		Phase.CLAIMS:
			var size := D.HAND_SIZE if pid == regent else D.HAND_SIZE - 1
			for cards in claim_options(size):
				result.append(GameAction.new(CLAIM, pid, {"cards": cards}))
			result.append(GameAction.new(CLAIM, pid, {"cards": null}))
		Phase.USE_POWER:
			if D.power_needs_target(pending_power):
				for t in power_targets():
					result.append(GameAction.new(USE_POWER, pid, {"target": t}))
			else:
				result.append(GameAction.new(USE_POWER, pid, {"target": -1}))
	return result


# --- Aplicar acciones ---------------------------------------------------------------

func _apply(action: GameAction) -> void:
	var pid := action.player_id
	match action.type:
		NOMINATE:
			nominee = int(action.data["target"])
			votes.clear()
			phase = Phase.VOTE
			event.emit(&"nominated", {"regent": regent, "nominee": nominee})
		VOTE:
			votes[pid] = bool(action.data["yes"])
			if votes.size() == alive_ids().size():
				_resolve_vote()
		DISCARD:
			var index := int(action.data["index"])
			regent_discarded = hand[index]
			discard_pile.append(hand[index])
			hand.remove_at(index)
			knowledge[council].append({"kind": "received", "cards": hand.duplicate(), "regent": regent, "round": governments.size() - 1})
			knowledge[regent][-1]["passed"] = hand.duplicate()
			truth[governments.size() - 1]["passed"] = hand.duplicate()
			phase = Phase.COUNCIL_ENACT
			event.emit(&"regent_discarded", {"regent": regent})
		ENACT:
			var index := int(action.data["index"])
			var edict := hand[index]
			hand.remove_at(index)
			discard_pile.append_array(hand)
			hand.clear()
			governments[-1]["edict"] = edict
			_enact(edict, false)
		CHOOSE_POWER:
			var index := int(action.data["index"])
			pending_power = power_options[index]
			# El poder no elegido vuelve al fondo del mazo; el elegido se gasta.
			power_deck.append(power_options[1 - index])
			power_options.clear()
			phase = Phase.USE_POWER
			event.emit(&"power_chosen", {"council": council, "power": pending_power})
		USE_POWER:
			_use_power(int(action.data.get("target", -1)))
		CLAIM:
			var cards = action.data.get("cards")
			var claim = null
			if cards != null:
				var sorted_cards: Array[int] = []
				for c in cards:
					sorted_cards.append(int(c))
				sorted_cards.sort()
				claim = sorted_cards
			var claims: Dictionary = governments[-1]["claims"]
			claims["regent" if pid == regent else "council"] = claim
			event.emit(&"claimed", {"player": pid, "as_regent": pid == regent, "cards": claim})
			if claims.size() == 2:
				event.emit(&"claims_done", {"consistent": claims_consistent(governments[-1])})
				_after_claims()


func _resolve_vote() -> void:
	var yes := 0
	for pid in votes:
		if votes[pid]:
			yes += 1
	var approved := yes * 2 > votes.size()
	last_votes = votes.duplicate()
	votes.clear()
	governments.append({"regent": regent, "nominee": nominee, "votes": last_votes.duplicate(), "approved": approved, "edict": -1, "crisis": false, "claims": {}})
	event.emit(&"vote_result", {"approved": approved, "votes": last_votes.duplicate(), "yes": yes})
	if not approved:
		nominee = -1
		crisis += 1
		if crisis >= D.MAX_CRISIS:
			_crisis()
		if not finished:
			_next_round()
		return
	council = nominee
	nominee = -1
	crisis = 0
	last_council = council
	if roles[council] == Role.USURPADOR and sombra_edicts >= D.USURPER_THRESHOLD:
		_win(Faction.SOMBRA, "El Usurpador ha sido elegido Consejero con %d edictos de la Sombra." % sombra_edicts)
		return
	_ensure_cards(D.HAND_SIZE)
	hand.clear()
	for i in D.HAND_SIZE:
		hand.append(draw_pile.pop_front())
	regent_discarded = -1
	knowledge[regent].append({"kind": "drawn", "cards": hand.duplicate(), "council": council, "round": governments.size() - 1})
	truth[governments.size() - 1] = {"drawn": hand.duplicate()}
	phase = Phase.REGENT_DISCARD


## Tres votaciones fallidas: se promulga el primer edicto del mazo, sin
## poderes, sube el descontento y se olvida el límite de mandatos.
func _crisis() -> void:
	crisis = 0
	last_council = -1
	_ensure_cards(1)
	var edict: int = draw_pile.pop_front()
	discontent += 1
	governments[-1]["crisis"] = true
	governments[-1]["edict"] = edict
	event.emit(&"crisis", {"edict": edict})
	_enact(edict, true)


func _enact(edict: int, from_crisis: bool) -> void:
	match edict:
		Edict.GUARDIA:
			guardia_edicts += 1
		Edict.SOMBRA:
			sombra_edicts += 1
		Edict.NEUTRAL:
			discontent += 1
	event.emit(&"enacted", {"edict": edict, "crisis": from_crisis})
	if guardia_edicts >= D.GUARDIA_TO_WIN:
		_win(Faction.GUARDIA, "La Guardia ha promulgado %d edictos." % guardia_edicts)
		return
	if sombra_edicts >= D.SOMBRA_TO_WIN:
		_win(Faction.SOMBRA, "La Sombra ha promulgado %d edictos." % sombra_edicts)
		return
	if discontent >= D.MAX_DISCONTENT:
		discontent = D.MAX_DISCONTENT
		var faction := Faction.SOMBRA if sombra_edicts < guardia_edicts else Faction.GUARDIA
		_win(faction, "El pueblo se ha rebelado: gana la facción con menos edictos (Guardia %d, Sombra %d)." % [guardia_edicts, sombra_edicts])
		return
	if from_crisis:
		return  # _resolve_vote pasa a la siguiente ronda
	# Tras promulgar, Regente y Consejero declaran lo que vieron.
	phase = Phase.CLAIMS


func _after_claims() -> void:
	var edict: int = governments[-1]["edict"]
	if edict == Edict.SOMBRA and sombra_edicts >= D.POWER_FROM:
		power_options.clear()
		power_options.append(power_deck.pop_front())
		# La segunda opción es el primer poder distinto del mazo.
		var second := 0
		while second < power_deck.size() - 1 and power_deck[second] == power_options[0]:
			second += 1
		power_options.append(power_deck.pop_at(second))
		phase = Phase.CHOOSE_POWER
		event.emit(&"power_offer", {"council": council, "options": power_options.duplicate()})
		return
	_next_round()


func _use_power(target: int) -> void:
	var power := pending_power
	pending_power = -1
	match power:
		Power.ESPIAR:
			knowledge[council].append({"kind": "faction", "target": target, "faction": faction_of(target)})
		Power.AUGURIO:
			_ensure_cards(D.HAND_SIZE)
			knowledge[council].append({"kind": "top", "cards": draw_pile.slice(0, D.HAND_SIZE), "round": governments.size()})
		Power.SUCESION:
			special_regent = target
		Power.DESTIERRO:
			alive[target] = false
		Power.PESQUISA:
			knowledge[council].append({"kind": "discarded", "card": regent_discarded, "regent": regent, "round": governments.size() - 1})
	event.emit(&"power_used", {"council": council, "power": power, "target": target})
	if power == Power.DESTIERRO:
		event.emit(&"banished", {"target": target})
		if roles[target] == Role.USURPADOR:
			_win(Faction.GUARDIA, "El Usurpador ha sido desterrado.")
			return
	_next_round()


## Si quedan menos de `count` edictos, se baraja el descarte en el mazo.
func _ensure_cards(count: int) -> void:
	if draw_pile.size() >= count:
		return
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	rng.shuffle(draw_pile)
	event.emit(&"reshuffle", {"count": draw_pile.size()})


func _next_round() -> void:
	council = -1
	nominee = -1
	power_options.clear()
	if special_regent >= 0 and alive[special_regent]:
		regent = special_regent
	else:
		regent_cursor = _next_alive(regent_cursor)
		regent = regent_cursor
	special_regent = -1
	turns.current = regent
	phase = Phase.NOMINATE
	event.emit(&"new_round", {"regent": regent})


func _next_alive(from: int) -> int:
	var n := players.size()
	for step in range(1, n + 1):
		var pid := (from + step) % n
		if alive[pid]:
			return pid
	return from


func _win(faction: int, reason: String) -> void:
	phase = Phase.FINISHED
	winner_faction = faction
	win_reason = reason
	var winners: Array[int] = []
	for i in players.size():
		if faction_of(i) == faction:
			winners.append(i)
	finish(winners)


## Declaraciones de un gobierno que no pueden ser todas ciertas:
## "council" (el Consejero no declara el edicto promulgado), "regent" (el
## Regente tampoco lo tenía) o "pair" (lo que dice uno no cuadra con el otro).
## Devuelve [] si todo es coherente.
static func claim_conflicts(gov: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var claims: Dictionary = gov.get("claims", {})
	var edict: int = gov.get("edict", -1)
	var rc = claims.get("regent")
	var cc = claims.get("council")
	if cc != null and not edict in cc:
		result.append("council")
	if rc != null and not edict in rc:
		result.append("regent")
	if rc != null and cc != null and not can_pass(rc, cc):
		result.append("pair")
	return result


static func claims_consistent(gov: Dictionary) -> bool:
	return claim_conflicts(gov).is_empty()


## true si quitando un edicto de `drawn` (3) quedan exactamente `passed` (2).
static func can_pass(drawn: Array, passed: Array) -> bool:
	for i in drawn.size():
		var rest := drawn.duplicate()
		rest.remove_at(i)
		rest.sort()
		var p := passed.duplicate()
		p.sort()
		if rest == p:
			return true
	return false
