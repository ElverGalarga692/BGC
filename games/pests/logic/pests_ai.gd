class_name PestsAI
extends RefCounted
## IA de Pests! (versión inicial, voraz: mira solo la jugada siguiente).
##
## Prioridades en su turno de exterminador: ganar si puede, sellar el nido,
## no quedarse sin reserva, usar las cartas útiles, exterminar donde está,
## poner trampas, y si no, moverse hacia la habitación más interesante
## (sus plagas, su reina libre, su nido abierto).
## Misma interfaz que ArchAI: new(pid, nivel, semilla) y choose_action(game).

const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")

## Orden en que prefiere los exterminadores.
const SPECIES_PREFERENCE := [D.Species.GREEN, D.Species.BLUE, D.Species.ORANGE, D.Species.RED,
	D.Species.YELLOW, D.Species.PURPLE]
## Orden en que prefiere las cartas al elegirlas.
const CARD_PREFERENCE := ["zap", "bug_bomb", "colony_collapse", "quik_seal", "more_time", "quik_trap",
	"trap_remote", "mating_call", "hibernate", "mind_control", "nesting", "pest_surge", "two_by_two",
	"fertile", "stuck", "angry_queen", "unseal_nest", "trap_breaks", "less_to_infest", "energy_drink",
	"spreading", "sabotage_tools", "royal_persuasion", "dumpster_diver"]
## Con esta reserva o menos, empieza a preocuparse por la eliminación.
const LOW_RESERVE := 4
const OFFENSIVE_CHANCE := 0.35

var pid: int
var level: int
var _rng: BGCRng


func _init(p_pid: int, p_level: int = PlayerInfo.AILevel.NORMAL, p_seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng = BGCRng.new(p_seed * 31 + p_pid)


func observe(_game: PestsGame) -> void:
	pass


func choose_action(game: PestsGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	match game.phase:
		G.Phase.CHOOSE_SPECIES:
			for sp in SPECIES_PREFERENCE:
				var a := _find(legal, G.CHOOSE_SPECIES, {"species": sp})
				if a != null:
					return a
		G.Phase.DRAFT:
			for card_id in CARD_PREFERENCE:
				var a := _find(legal, G.DRAFT_CARD, {"card": card_id})
				if a != null:
					return a
		G.Phase.PLACE_TILES:
			return _rng.pick(legal)
		G.Phase.QUEEN:
			return _queen_phase(game, legal)
		G.Phase.EXTERMINATOR:
			return _exterminator_phase(game, legal)
	return legal[0]


func _queen_phase(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var sp := game.species(pid)
	if game.reserve[sp] <= LOW_RESERVE:
		var hibernate := _find(legal, G.PLAY_CARD, {"card": "hibernate"})
		if hibernate != null:
			return hibernate
	return _find(legal, G.ROLL_QUEEN)


func _exterminator_phase(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var sp := game.species(pid)
	var here: int = game.exterminator_room[pid]
	# 1. Ganar.
	for a in _all(legal, G.EMPTY_TRAP):
		if game.find_trap(a.data["trap"])["queen"]:
			return a
	for a in _all(legal, G.PLAY_CARD):
		if a.data["card"] == "trap_remote" and game.find_trap(a.data["trap"])["queen"]:
			return a
	# 2. Sellar el nido.
	var seal := _find(legal, G.SEAL_NEST)
	if seal != null:
		return seal
	var quik_seal := _find(legal, G.PLAY_CARD, {"card": "quik_seal"})
	if quik_seal != null and game.house.room_species[here] == sp:
		return quik_seal
	# 3. Reserva baja: vaciar trampas con plagas recupera reserva.
	if game.reserve[sp] <= LOW_RESERVE:
		for a in _all(legal, G.EMPTY_TRAP):
			if game.find_trap(a.data["trap"])["pests"] > 0:
				return a
	# 4. Cartas que exterminan.
	var card := _useful_card(game, legal)
	if card != null:
		return card
	# 5. Atrapar a la reina si está aquí; si no, exterminar.
	if game.queen_room[sp] == here and not game.is_queen_trapped(sp):
		var trap := _find(legal, G.DROP_TRAP, {"target": "queen"})
		if trap != null:
			return trap
	var exterminate := _find(legal, G.EXTERMINATE)
	if exterminate != null:
		return exterminate
	# 6. Una trampa de sobra para las plagas, si hay muchas aquí.
	if game.traps_available(pid) >= 2 and game.pests_in_room(here, sp) >= 3:
		var trap := _find(legal, G.DROP_TRAP, {"target": "pests"})
		if trap != null:
			return trap
	# 7. Fastidiar a un rival.
	if _rng.randf() < OFFENSIVE_CHANCE:
		var offensive := _offensive_card(game, legal)
		if offensive != null:
			return offensive
	# 8. Moverse hacia lo más interesante.
	var move := _best_move(game, legal)
	if move != null:
		return move
	return _find(legal, G.END_TURN)


func _useful_card(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var sp := game.species(pid)
	var here: int = game.exterminator_room[pid]
	for a in _all(legal, G.PLAY_CARD):
		match a.data["card"]:
			"bug_bomb":
				if game.pests_in_room(here, sp) >= 4:
					return a
			"zap":
				if game.pests_in_room(a.data["room"], sp) >= 3:
					return a
			"colony_collapse":
				if game.pests_in_room(a.data["room"], sp) >= 4:
					return a
	return null


func _offensive_card(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var options: Array[GameAction] = []
	for a in _all(legal, G.PLAY_CARD):
		var card := D.card(a.data["card"])
		if card["kind"] == D.CardKind.OFFENSIVE and a.data["card"] != "dumpster_diver":
			options.append(a)
	return _rng.pick(options) if not options.is_empty() else null


## Movimiento hacia la habitación con más valor (por distancia).
func _best_move(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var moves := _all(legal, G.MOVE)
	if moves.is_empty():
		return null
	var sp := game.species(pid)
	var here: int = game.exterminator_room[pid]
	var dist := game.house.distances(here)
	var best_room := -1
	var best_value := 0.0
	for r in dist:
		var value: float = _room_value(game, sp, r) / (1.0 + float(dist[r]))
		if r != here and value > best_value:
			best_value = value
			best_room = r
	if best_room < 0:
		return null
	var steps := game.house.steps_toward(here, best_room)
	for a in moves:
		if a.data["room"] in steps:
			return a
	return null


func _room_value(game: PestsGame, sp: int, room: int) -> float:
	var value := float(game.pests_in_room(room, sp))
	if game.queen_room[sp] == room and not game.is_queen_trapped(sp) and game.traps_available(pid) > 0:
		value += 4.0
	if game.house.nest_of(sp) == room and not game.sealed[sp]:
		value += 5.0
	var queen := game.queen_trap(sp)
	if not queen.is_empty() and queen["room"] == room and game.can_empty_queen_trap(pid):
		value += 30.0
	return value


static func _find(legal: Array[GameAction], type: StringName, data: Dictionary = {}) -> GameAction:
	for a in legal:
		if a.type != type:
			continue
		var ok := true
		for k in data:
			if a.data.get(k) != data[k]:
				ok = false
				break
		if ok:
			return a
	return null


static func _all(legal: Array[GameAction], type: StringName) -> Array[GameAction]:
	var result: Array[GameAction] = []
	for a in legal:
		if a.type == type:
			result.append(a)
	return result
