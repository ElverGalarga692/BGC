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
## Cartas especiales (pueden salir del mazo o cogerse del mercado):
##   Gaviota        quien la recibe elige a otro jugador con peces en la red
##                  (en el mar o en puerto, no con la red rota) y le quita el
##                  último pez que pescó (CHOOSE_TARGET). Si nadie tiene
##                  peces, se descarta sin efecto.
##   Red reforzada  se queda delante del jugador (como mucho una; otra más se
##                  descarta) y le salva de la tormenta que le rompería la
##                  red: las dos cartas se descartan y el aviso sigue.
##   Marea alta     todos los que siguen en el mar roban una carta a ciegas,
##                  empezando por quien la recibió y en orden de turno. Las
##                  tormentas cuentan; otra Marea alta robada así no tiene
##                  efecto. Las gaviotas robadas se resuelven después, en el
##                  mismo orden.
## Mientras haya gaviotas por resolver, solo puede actuar quien la tiene, y
## el turno no pasa hasta que se resuelven todas.
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
const TAKE_MARKET := &"take_market"      # {"slot": int}
const GO_TO_PORT := &"go_to_port"
const CHOOSE_TARGET := &"choose_target"  # Gaviota: {"target": pid}

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
## si tiene una red reforzada, su situación y su puntuación total.
var nets: Array = []
var warnings: Array[bool] = []
var shields: Array[bool] = []
var status: Array[int] = []
var scores: Array[int] = []
## Jugadores con una gaviota por resolver, en orden (la carta ya está en los
## descartes).
var pending_gulls: Array[int] = []
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
	shields.assign(_filled(players.size(), false))
	status.assign(_filled(players.size(), Status.AT_SEA))
	scores.assign(_filled(players.size(), 0))
	pending_gulls.clear()
	last_round.clear()
	_start_round()


# --- Consultas -------------------------------------------------------------------

func players_to_act() -> Array[int]:
	var result: Array[int] = []
	if phase == Phase.FINISHED:
		return result
	result.append(pending_gulls[0] if not pending_gulls.is_empty() else turns.current)
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


## Jugadores a los que `pid` puede quitar un pez con la Gaviota.
func gull_targets(pid: int) -> Array[int]:
	var result: Array[int] = []
	for p in players.size():
		if p != pid and status[p] != Status.BROKEN and not nets[p].is_empty():
			result.append(p)
	return result


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
	if not pending_gulls.is_empty() and action.type != CHOOSE_TARGET:
		return "Primero elige a quién le quita un pez la gaviota"
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
		CHOOSE_TARGET:
			if pending_gulls.is_empty():
				return "No hay ninguna gaviota por resolver"
			if not int(action.data.get("target", -1)) in gull_targets(pid):
				return "La gaviota no puede quitarle un pez a ese jugador"
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
		CHOOSE_TARGET:
			pending_gulls.pop_front()
			var target := int(action.data["target"])
			var fish: int = nets[target].pop_back()
			nets[pid].append(fish)
			event.emit(&"gull", {"player": pid, "target": target, "card": fish})
	_resolve_gulls()
	if pending_gulls.is_empty():
		_advance()


func get_legal_actions(player_id: int) -> Array[GameAction]:
	var result: Array[GameAction] = []
	if not player_id in players_to_act():
		return result
	if not pending_gulls.is_empty():
		for t in gull_targets(player_id):
			result.append(GameAction.new(CHOOSE_TARGET, player_id, {"target": t}))
		return result
	if cards_left() > 0:
		result.append(GameAction.new(DRAW_BLIND, player_id))
	for slot in market.size():
		result.append(GameAction.new(TAKE_MARKET, player_id, {"slot": slot}))
	result.append(GameAction.new(GO_TO_PORT, player_id))
	return result


# --- Internos -------------------------------------------------------------------

## Un jugador recibe una carta. `tide` indica que la roba por una Marea alta.
func _receive(pid: int, card: int, from: String, tide: bool = false) -> void:
	event.emit(&"draw", {"player": pid, "card": card, "from": from})
	if D.is_fish(card):
		nets[pid].append(card)
	elif D.is_storm(card):
		_storm(pid)
	elif card == D.GULL:
		discard.append(card)
		pending_gulls.append(pid)
	elif card == D.SHIELD:
		if shields[pid]:
			discard.append(card)
			event.emit(&"shield_wasted", {"player": pid})
		else:
			shields[pid] = true
			event.emit(&"shield", {"player": pid})
	elif card == D.HIGH_TIDE:
		discard.append(card)
		if tide:
			event.emit(&"tide_wasted", {"player": pid})
		else:
			_high_tide(pid)


func _storm(pid: int) -> void:
	if not warnings[pid]:
		warnings[pid] = true
		event.emit(&"warning", {"player": pid})
		return
	if shields[pid]:
		shields[pid] = false
		discard.append(D.SHIELD)
		discard.append(D.STORM)
		event.emit(&"shield_used", {"player": pid})
		return
	# Segunda tormenta: se rompe la red.
	status[pid] = Status.BROKEN
	discard.append_array(nets[pid])
	discard.append(D.STORM)  # la de aviso
	discard.append(D.STORM)
	nets[pid] = [] as Array[int]
	warnings[pid] = false
	event.emit(&"net_broken", {"player": pid})


## Marea alta: cada jugador que sigue en el mar roba una carta, empezando
## por `pid`.
func _high_tide(pid: int) -> void:
	event.emit(&"tide", {"player": pid})
	var n := players.size()
	for step in n:
		var p := (pid + step) % n
		if status[p] != Status.AT_SEA or cards_left() == 0:
			continue
		_receive(p, _draw(), "tide", true)


## Descarta las gaviotas que ya no pueden quitar nada (sin víctimas, o con la
## red de quien la tiene rota).
func _resolve_gulls() -> void:
	while not pending_gulls.is_empty():
		var p := pending_gulls[0]
		if status[p] != Status.BROKEN and not gull_targets(p).is_empty():
			return
		pending_gulls.pop_front()
		event.emit(&"gull_wasted", {"player": p})


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
		shields[p] = false
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
		if shields[p]:
			discard.append(D.SHIELD)
		nets[p] = [] as Array[int]
		warnings[p] = false
		shields[p] = false
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
