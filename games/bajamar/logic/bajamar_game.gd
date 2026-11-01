class_name BajamarGame
extends GameBase
## Lógica de una partida de Bajamar.
##
## La partida se juega en rondas. En cada ronda todos salen a pescar y, por
## turnos, cada jugador que sigue en el mar hace una de estas tres cosas:
##   DRAW_BLIND    robar la carta de arriba del mazo (a ciegas);
##   TAKE_MARKET   coger una de las cartas boca arriba del mercado;
##   GO_TO_PORT    volver a puerto: guarda su red y deja de jugar la ronda.
##
## La primera tormenta que recibe un jugador es un aviso (se queda delante
## de él). Con la segunda se le rompe la red: pierde lo pescado y no puntúa
## la ronda. En el mercado nunca hay tormentas: si al reponerlo sale una,
## pasa de largo (va a los descartes, a la vista de todos) y se repone otra
## vez.
##
## La ronda termina cuando ya nadie está en el mar. Cada red que volvió a
## puerto puntúa (BajamarDefs.score). Si alguien llega a TARGET_SCORE, gana
## quien más puntos tenga (puede haber empate); si no, empieza otra ronda con
## el siguiente jugador. El mercado se conserva entre rondas.
##
## Cuando el mazo se acaba, se barajan los descartes y forman un mazo nuevo.
##
## Todo es público salvo el orden del mazo, así que no hace falta filtrar el
## estado por jugador.

signal event(kind: StringName, data: Dictionary)

const D := preload("res://games/bajamar/logic/bajamar_defs.gd")

enum Phase { FISHING, FINISHED }
## Situación de cada jugador durante la ronda.
enum Status { AT_SEA, IN_PORT, BROKEN }

const DRAW_BLIND := &"draw_blind"
const TAKE_MARKET := &"take_market"  # {"slot": int}
const GO_TO_PORT := &"go_to_port"

const ACTIONS := [DRAW_BLIND, TAKE_MARKET, GO_TO_PORT]

var phase: Phase = Phase.FISHING
## Puntos para ganar. Se puede cambiar antes de jugar (tests, opciones).
var target_score := D.TARGET_SCORE
var start_player := 0
var round_number := 0

## Mazo (se roba del final) y descartes.
var deck: Array[int] = []
var discard: Array[int] = []
## Cartas boca arriba del mercado (hasta MARKET_SIZE).
var market: Array[int] = []

## Por jugador: cartas de su red esta ronda, si tiene una tormenta de aviso,
## su situación y su puntuación total.
var nets: Array = []
var warnings: Array[bool] = []
var status: Array[int] = []
var scores: Array[int] = []
## Puntos de la última ronda terminada, por jugador (desglose de
## BajamarDefs.score, o {"total": 0, "broken": true}).
var last_round: Array = []


func _on_setup() -> void:
	phase = Phase.FISHING
	start_player = 0
	round_number = 0
	deck = D.deck()
	rng.shuffle(deck)
	discard.clear()
	market.clear()
	nets.clear()
	for p in players.size():
		nets.append([] as Array[int])
	warnings.assign(_filled(players.size(), false))
	status.assign(_filled(players.size(), Status.AT_SEA))
	scores.assign(_filled(players.size(), 0))
	last_round.clear()
	_start_round()


# --- Consultas -------------------------------------------------------------------

func players_to_act() -> Array[int]:
	var result: Array[int] = []
	if phase != Phase.FINISHED:
		result.append(turns.current)
	return result


func at_sea() -> Array[int]:
	var result: Array[int] = []
	for p in players.size():
		if status[p] == Status.AT_SEA:
			result.append(p)
	return result


func net(pid: int) -> Array[int]:
	return nets[pid]


## Puntos que se llevaría ahora mismo si volviera a puerto.
func net_score(pid: int) -> Dictionary:
	return D.score(nets[pid])


## Cartas que se pueden robar a ciegas (mazo más descartes por barajar).
func cards_left() -> int:
	return deck.size() + discard.size()


## Tormentas que quedan en el mazo. Se deduce de lo que está a la vista (los
## avisos y los descartes), así que cualquier jugador puede calcularlo.
func storms_in_deck() -> int:
	var seen := discard.count(D.STORM)
	for p in players.size():
		if warnings[p]:
			seen += 1
	return D.STORM_COUNT - seen


## Probabilidad de que robar a ciegas dé una tormenta (si el mazo está vacío,
## se robaría de los descartes barajados).
func storm_chance() -> float:
	if not deck.is_empty():
		return float(storms_in_deck()) / deck.size()
	if discard.is_empty():
		return 0.0
	return float(discard.count(D.STORM)) / discard.size()


# --- Validar y aplicar ----------------------------------------------------------

func validate(action: GameAction) -> String:
	var pid := action.player_id
	if phase == Phase.FINISHED:
		return "La partida ha terminado"
	if pid < 0 or pid >= players.size():
		return "Jugador no válido"
	if not pid in players_to_act():
		return "No es tu turno"
	match action.type:
		DRAW_BLIND:
			if cards_left() == 0:
				return "No quedan cartas en el mazo"
			return ""
		TAKE_MARKET:
			var slot := int(action.data.get("slot", -1))
			if slot < 0 or slot >= market.size():
				return "Esa carta del mercado no existe"
			return ""
		GO_TO_PORT:
			return ""
	return "Acción no soportada: %s" % action.type


func _apply(action: GameAction) -> void:
	var pid := action.player_id
	match action.type:
		DRAW_BLIND:
			_receive(pid, _draw(), "deck")
		TAKE_MARKET:
			var slot := int(action.data["slot"])
			var card: int = market[slot]
			market.remove_at(slot)
			_receive(pid, card, "market")
			_refill_market()
		GO_TO_PORT:
			status[pid] = Status.IN_PORT
			event.emit(&"port", {"player": pid, "score": net_score(pid)})
	_advance()


func get_legal_actions(player_id: int) -> Array[GameAction]:
	var result: Array[GameAction] = []
	if not player_id in players_to_act():
		return result
	if cards_left() > 0:
		result.append(GameAction.new(DRAW_BLIND, player_id))
	for slot in market.size():
		result.append(GameAction.new(TAKE_MARKET, player_id, {"slot": slot}))
	result.append(GameAction.new(GO_TO_PORT, player_id))
	return result


# --- Internos -------------------------------------------------------------------

## Un jugador recibe una carta en su red (o una tormenta).
func _receive(pid: int, card: int, from: String) -> void:
	event.emit(&"draw", {"player": pid, "card": card, "from": from})
	if not D.is_storm(card):
		nets[pid].append(card)
		return
	if not warnings[pid]:
		warnings[pid] = true
		event.emit(&"warning", {"player": pid})
		return
	# Segunda tormenta: se rompe la red.
	status[pid] = Status.BROKEN
	discard.append_array(nets[pid])
	discard.append(D.STORM)  # la de aviso
	discard.append(card)
	nets[pid] = [] as Array[int]
	warnings[pid] = false
	event.emit(&"net_broken", {"player": pid})


## Roba la carta de arriba del mazo; si está vacío, baraja los descartes.
## Solo se llama si cards_left() > 0.
func _draw() -> int:
	if deck.is_empty():
		deck = discard.duplicate()
		discard.clear()
		rng.shuffle(deck)
		event.emit(&"reshuffle", {"cards": deck.size()})
	return deck.pop_back()


## Repone el mercado. Las tormentas que salen pasan de largo.
func _refill_market() -> void:
	while market.size() < D.MARKET_SIZE and cards_left() > 0:
		var card := _draw()
		if D.is_storm(card):
			discard.append(card)
			event.emit(&"storm_passed", {})
		else:
			market.append(card)


## Pasa el turno al siguiente jugador que sigue en el mar o cierra la ronda.
func _advance() -> void:
	var n := players.size()
	for step in range(1, n + 1):
		var p := (turns.current + step) % n
		if status[p] == Status.AT_SEA:
			turns.current = p
			return
	_end_round()


func _start_round() -> void:
	round_number += 1
	var n := players.size()
	for p in n:
		nets[p] = [] as Array[int]
		warnings[p] = false
		status[p] = Status.AT_SEA
	_refill_market()
	turns.current = (start_player + round_number - 1) % n
	event.emit(&"round_start", {"round": round_number, "first": turns.current})


func _end_round() -> void:
	last_round.clear()
	for p in players.size():
		var result: Dictionary
		if status[p] == Status.IN_PORT:
			result = D.score(nets[p])
		else:
			result = {"total": 0, "broken": true}
		scores[p] += int(result["total"])
		last_round.append(result)
		discard.append_array(nets[p])
		if warnings[p]:
			discard.append(D.STORM)
		nets[p] = [] as Array[int]
		warnings[p] = false
	event.emit(&"round_end", {"round": round_number, "results": last_round.duplicate(true)})
	var best: int = scores.max()
	if best >= target_score:
		var winners: Array[int] = []
		for p in players.size():
			if scores[p] == best:
				winners.append(p)
		phase = Phase.FINISHED
		finish(winners)
		return
	_start_round()


func _filled(count: int, value: Variant) -> Array:
	var a := []
	a.resize(count)
	a.fill(value)
	return a
