class_name PestsAI
extends RefCounted
## IA de Pests!, con tres niveles:
##
##   Fácil: reglas sencillas, se equivoca a menudo (jugadas al azar) y no usa
##          cartas contra los rivales.
##   Normal: reglas con prioridades (ganar, sellar, no quedarse sin reserva,
##          cartas útiles, exterminar, trampas, moverse hacia lo importante)
##          y ataca al que va ganando.
##   Difícil: planifica el turno completo probando secuencias de jugadas en
##          copias de la partida (PestsGame.clone) y evaluando cómo queda
##          todo al final; exterminar cuenta con la tirada media. Decide con la
##          misma evaluación si le conviene Control mental o Las plagas
##          hibernan.
##
## Misma interfaz que ArchAI: new(pid, nivel, semilla) y choose_action(game).

const AILevel := PlayerInfo.AILevel
const D := preload("res://games/pests/logic/pests_defs.gd")
const G := preload("res://games/pests/logic/pests_game.gd")

const SPECIES_PREFERENCE := [D.Species.GREEN, D.Species.BLUE, D.Species.ORANGE, D.Species.RED,
	D.Species.YELLOW, D.Species.PURPLE]
const CARD_PREFERENCE := ["zap", "bug_bomb", "colony_collapse", "quik_seal", "more_time", "quik_trap",
	"trap_remote", "mating_call", "hibernate", "mind_control", "nesting", "pest_surge", "two_by_two",
	"fertile", "stuck", "angry_queen", "unseal_nest", "trap_breaks", "less_to_infest", "energy_drink",
	"spreading", "sabotage_tools", "royal_persuasion", "dumpster_diver"]
const LOW_RESERVE := 4
const OFFENSIVE_CHANCE := 0.35
const EASY_MISTAKE_CHANCE := 0.3

# --- Evaluación (IA difícil) ---------------------------------------------------
const WIN_VALUE := 10000.0
const SEALED_VALUE := 45.0
## El nido sellado de un rival vale menos: puede volver a sellarlo con 2 PA.
const OPPONENT_SEALED_VALUE := 10.0
const QUEEN_TRAPPED_VALUE := 40.0
const READY_TO_WIN_VALUE := 25.0
const PEST_IN_HOUSE := 3.0
const PEST_IN_TRAP := 0.4
const CARD_VALUE := 2.0
const MAX_VALUED_CARDS := 6
const FREE_TRAP_VALUE := 6.0
const SAFE_RESERVE := 6
const DANGER_FACTOR := 2.0
const POSITION_FACTOR := 0.7
const WIN_PATH_VALUE := 40.0
const WIN_PATH_STEP := 8.0
const LEADER_WEIGHT := 0.35
const OTHERS_WEIGHT := 0.1
## Por equipos: cuánto le importa el progreso de cada compañero.
const TEAM_WEIGHT := 0.8
## Cuánto perjudica cada carta que un jugador tiene delante.
const EFFECT_PENALTY := {"fertile": 7.0, "two_by_two": 7.0, "stuck": 5.0, "angry_queen": 4.0, "royal_persuasion": 4.0}
## Muestras para las jugadas con azar (salvo exterminar, que usa la media).
const SAMPLES := 4
## Tirada media del d6 para planificar (3,5 redondeado hacia abajo).
const EXPECTED_ROLL := 3
## Jugadas como máximo en un plan de turno.
const PLAN_DEPTH := 4
## Ganancia mínima para gastar Control mental o Las plagas hibernan.
const BEFORE_ROLL_GAIN := 3.0

var pid: int
var level: int
var _rng: BGCRng


func _init(p_pid: int, p_level: int = AILevel.NORMAL, p_seed: int = 0) -> void:
	pid = p_pid
	level = p_level if p_level != AILevel.HUMAN else AILevel.NORMAL
	_rng = BGCRng.new(p_seed * 31 + p_pid)


func observe(_game: PestsGame) -> void:
	pass


func choose_action(game: PestsGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	match game.phase:
		G.Phase.CHOOSE_SPECIES:
			if level == AILevel.EASY:
				return _rng.pick(legal)
			for sp in SPECIES_PREFERENCE:
				var a := _find(legal, G.CHOOSE_SPECIES, {"species": sp})
				if a != null:
					return a
		G.Phase.DRAFT:
			if level == AILevel.EASY:
				return _rng.pick(legal)
			for card_id in CARD_PREFERENCE:
				var a := _find(legal, G.DRAFT_CARD, {"card": card_id})
				if a != null:
					return a
		G.Phase.PLACE_TILES:
			return _place_tile(game, legal)
		G.Phase.QUEEN:
			if level == AILevel.HARD:
				return _hard_queen(game, legal)
			return _queen_phase(game, legal)
		G.Phase.EXTERMINATOR:
			match level:
				AILevel.EASY:
					if _rng.randf() < EASY_MISTAKE_CHANCE:
						var careless := legal.filter(func(a: GameAction) -> bool:
							return a.type != G.END_TURN and not _is_offensive(a))
						if not careless.is_empty():
							return careless[_rng.randi_range(0, careless.size() - 1)]
					return _rule_based(game, legal, false)
				AILevel.HARD:
					return _hard_exterminator(game, legal)
			return _rule_based(game, legal, true)
	return legal[0]


# --- Construcción de la casa ------------------------------------------------------

## Fácil: al azar. Normal y difícil: el nido propio cerca de la entrada (su
## exterminador empieza allí) y las demás losetas donde toquen más
## habitaciones (casa compacta, caminos cortos).
func _place_tile(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	if level == AILevel.EASY:
		return _rng.pick(legal)
	var best: Array[GameAction] = []
	var best_score := -INF
	for a in legal:
		var cell := Vector2i(a.data["x"], a.data["y"])
		var tile: Dictionary = game.tile_hands[pid][a.data["index"]]
		var score := 0.0
		if tile["kind"] == D.RoomKind.NEST:
			score = 100.0 - (absi(cell.x) + absi(cell.y)) * 5.0
		else:
			for dir in 4:
				if game.house.room_at(cell + D.DIR_VECTORS[dir]) >= 0:
					score += 1.0
			score -= (absi(cell.x) + absi(cell.y)) * 0.1
		if score > best_score + 0.001:
			best_score = score
			best = [a]
		elif absf(score - best_score) <= 0.001:
			best.append(a)
	return _rng.pick(best)


# --- Reglas (fácil y normal) ------------------------------------------------------

func _queen_phase(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var sp := game.species(pid)
	if level != AILevel.EASY and game.reserve[sp] <= LOW_RESERVE:
		var hibernate := _find(legal, G.PLAY_CARD, {"card": "hibernate"})
		if hibernate != null:
			return hibernate
	return _find(legal, G.ROLL_QUEEN)


func _rule_based(game: PestsGame, legal: Array[GameAction], use_offensive: bool) -> GameAction:
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
	var exterminate := _best_exterminate(game, legal)
	if exterminate != null:
		return exterminate
	# 6. Una trampa de sobra para las plagas, si hay muchas aquí.
	if game.traps_available(pid) >= 2 and game.pests_in_room(here, sp) >= 3:
		var trap := _find(legal, G.DROP_TRAP, {"target": "pests"})
		if trap != null:
			return trap
	# 7. Fastidiar al que va ganando.
	if use_offensive and _rng.randf() < OFFENSIVE_CHANCE:
		var offensive := _offensive_card(game, legal)
		if offensive != null:
			return offensive
	# 8. Moverse hacia lo más interesante.
	var move := _best_move(game, legal)
	if move != null:
		return move
	return _find(legal, G.END_TURN)


## Exterminar las plagas propias o, por equipos, las del compañero que más
## tenga en la habitación (nunca las de un rival).
func _best_exterminate(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var here: int = game.exterminator_room[pid]
	var best: GameAction = null
	var best_count := 0
	for a in _all(legal, G.EXTERMINATE):
		var sp := int(a.data.get("species", game.species(pid)))
		var owner := game.player_of(sp)
		if owner < 0 or not game.same_team(pid, owner):
			continue
		var count := game.pests_in_room(here, sp) + (100 if sp == game.species(pid) else 0)
		if count > best_count:
			best_count = count
			best = a
	return best


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


## Carta ofensiva contra el rival que va mejor.
func _offensive_card(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var leader := _leader(game)
	var options: Array[GameAction] = []
	for a in _all(legal, G.PLAY_CARD):
		if _is_offensive(a) and a.data["card"] != "dumpster_diver" and int(a.data.get("player", -1)) == leader:
			options.append(a)
	return _rng.pick(options) if not options.is_empty() else null


func _leader(game: PestsGame) -> int:
	var best := -1
	var best_value := -INF
	for o in game.opponents(pid):
		var v := _progress(game, o)
		if v > best_value:
			best_value = v
			best = o
	return best


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


## Interés de una habitación para el exterminador (por equipos cuentan
## también las plagas de los compañeros, que puede exterminar).
func _room_value(game: PestsGame, sp: int, room: int) -> float:
	var value := float(game.pests_in_room(room, sp))
	for mate in game.teammates(pid):
		value += 0.8 * game.pests_in_room(room, game.species(mate))
	if game.queen_room[sp] == room and not game.is_queen_trapped(sp) and game.traps_available(pid) > 0:
		value += 4.0
	if game.house.nest_of(sp) == room and not game.sealed[sp]:
		value += 5.0
	var queen := game.queen_trap(sp)
	if not queen.is_empty() and queen["room"] == room and game.can_empty_queen_trap(pid):
		value += 30.0
	return value


# --- Evaluación y búsqueda (difícil) ---------------------------------------------

## Valor de una situación para esta IA: su progreso y su posición menos el
## progreso de los rivales (sobre todo del que va mejor).
func evaluate(game: PestsGame) -> float:
	if game.finished:
		return WIN_VALUE if pid in game.winner_ids else -WIN_VALUE
	if game.eliminated[pid]:
		return -WIN_VALUE
	var value := _progress(game, pid) + _position(game)
	for mate in game.teammates(pid):
		value += TEAM_WEIGHT * _progress(game, mate)
	var leader := -INF
	var others := 0.0
	for o in game.opponents(pid):
		var p := _progress(game, o)
		leader = maxf(leader, p)
		others += p
	if leader > -INF:
		value -= LEADER_WEIGHT * leader + OTHERS_WEIGHT * (others - leader)
	return value


## Lo cerca que está un jugador de ganar (y de no perder).
func _progress(game: PestsGame, p: int) -> float:
	if game.eliminated[p]:
		return -200.0
	var sp := game.species(p)
	var value := 0.0
	var queen_trapped := game.is_queen_trapped(sp)
	var in_house := game.pests_in_house(sp)
	var trapped := game.pests_in_traps(sp)
	if game.sealed[sp]:
		value += SEALED_VALUE if p == pid else OPPONENT_SEALED_VALUE
	if queen_trapped:
		value += QUEEN_TRAPPED_VALUE
	else:
		value += FREE_TRAP_VALUE * game.traps_available(p)
	if game.sealed[sp] and queen_trapped and in_house == 0:
		value += READY_TO_WIN_VALUE
	value -= PEST_IN_HOUSE * in_house
	value += PEST_IN_TRAP * trapped
	var reserve := game.reserve[sp]
	if reserve < SAFE_RESERVE:
		var danger := pow(SAFE_RESERVE - reserve, 2) * DANGER_FACTOR
		value -= danger * (0.25 if trapped > 0 else 1.0)
	value += CARD_VALUE * mini(game.hands[p].size(), MAX_VALUED_CARDS)
	for e in game.effects_on(p):
		value -= EFFECT_PENALTY.get(e["card"], 3.0)
	return value


## Lo bien situado que está el exterminador de esta IA.
func _position(game: PestsGame) -> float:
	var sp := game.species(pid)
	var here: int = game.exterminator_room[pid]
	var dist := game.house.distances(here)
	var best := 0.0
	for r in dist:
		best = maxf(best, _room_value(game, sp, r) / (1.0 + float(dist[r])))
	var value := POSITION_FACTOR * best
	var queen := game.queen_trap(sp)
	if not queen.is_empty() and game.can_empty_queen_trap(pid):
		value += WIN_PATH_VALUE - WIN_PATH_STEP * float(dist.get(queen["room"], 5))
	return value


## Planifica el turno completo: prueba secuencias de jugadas (hasta agotar
## el movimiento gratis y los puntos de acción, con un máximo de PLAN_DEPTH)
## y hace la primera jugada de la mejor. Se vuelve a planificar tras cada
## jugada, así que los dados reales corrigen el plan.
func _hard_exterminator(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var budget := mini(PLAN_DEPTH, (1 if game.free_move else 0) + game.action_points + game.energy_moves)
	var best: GameAction = _find(legal, G.END_TURN)
	var best_value := evaluate(game)
	for a in legal:
		if a.type == G.END_TURN:
			continue
		var v := _root_value(game, a, budget - 1)
		if v > best_value + 0.01:
			best_value = v
			best = a
	return best if best != null else legal[0]


## Valor de empezar el turno con `a` (con su mejor continuación).
func _root_value(game: PestsGame, a: GameAction, depth: int) -> float:
	var samples := SAMPLES if _is_random(a) and a.type != G.EXTERMINATE else 1
	var total := 0.0
	for s in samples:
		var c := _apply_planned(game, a, _rng.randi_range(0, 1 << 30))
		if c == null:
			return -INF
		_simulate_future(c, a)
		total += _plan(c, depth)
	return total / samples


## Mejor valor alcanzable desde `c` con `depth` jugadas más (o parando aquí).
func _plan(c: PestsGame, depth: int) -> float:
	var best := evaluate(c)
	if depth <= 0 or c.finished or c.phase != G.Phase.EXTERMINATOR:
		return best
	for a in c.get_legal_actions(pid):
		if not _worth_planning(a):
			continue
		var next := _apply_planned(c, a, -1)
		if next != null:
			best = maxf(best, _plan(next, depth - 1))
	return best


## Jugadas que se consideran en mitad de un plan (las de la raíz son todas).
static func _worth_planning(a: GameAction) -> bool:
	match a.type:
		G.MOVE, G.EXTERMINATE, G.DROP_TRAP, G.EMPTY_TRAP, G.SEAL_NEST, G.DRAG_TRAP:
			return true
		G.PLAY_CARD:
			return a.data["card"] in ["zap", "bug_bomb", "colony_collapse", "quik_seal", "quik_trap", "trap_remote", "more_time"]
	return false


## Copia de la partida con la jugada hecha. Exterminar usa el resultado
## esperado del dado (sin azar) para que el plan sea estable.
func _apply_planned(game: PestsGame, a: GameAction, seed_value: int) -> PestsGame:
	var c := game.clone(seed_value)
	if a.type == G.EXTERMINATE:
		if c.validate(a) != "":
			return null
		c._pay(pid, a.type, a.data)
		c.exterminate(pid, EXPECTED_ROLL + int(c.ability(pid, "exterminate_bonus")), int(a.data.get("species", -1)))
		return c
	if c.submit(a) != "":
		return null
	return c


## Cartas cuyo efecto llega más tarde: se simula una vez para valorarlas.
func _simulate_future(c: PestsGame, a: GameAction) -> void:
	if a.type != G.PLAY_CARD or a.data["card"] != "royal_persuasion":
		return
	var target := int(a.data["player"])
	c.resolve_queen_choice(c.species(target), int(a.data["queen_action"]))


func _is_random(a: GameAction) -> bool:
	if a.type == G.EXTERMINATE:
		return true
	if a.type == G.PLAY_CARD:
		return a.data["card"] == "sabotage_tools" or a.data.get("use", "") == "sabotage_tools"
	return false


## Antes de tirar: compara lo que se espera de la tirada con elegir la acción
## (Control mental) o saltársela (Las plagas hibernan).
func _hard_queen(game: PestsGame, legal: Array[GameAction]) -> GameAction:
	var roll := _find(legal, G.ROLL_QUEEN)
	var mind := _all(legal, G.PLAY_CARD).filter(func(a: GameAction) -> bool: return a.data["card"] == "mind_control")
	var hibernate := _find(legal, G.PLAY_CARD, {"card": "hibernate"})
	if mind.is_empty() and hibernate == null:
		return roll
	var sp := game.species(pid)
	var step: Dictionary = game.queen_steps[0]
	var expected := 0.0
	if step["action"] >= 0:
		var c := game.clone()
		c.resolve_queen_choice(sp, step["action"], step["repeat"])
		expected = evaluate(c)
	else:
		for face in D.QUEEN_DIE.size():
			var c := game.clone()
			c.resolve_queen_face(sp, face, step["repeat"])
			expected += evaluate(c) / D.QUEEN_DIE.size()
	if hibernate != null:
		var gain := (evaluate(game) - expected) * game.queen_steps.size()
		if gain > BEFORE_ROLL_GAIN * 2:
			return hibernate
	var best_mind: GameAction = null
	var best_value := expected + BEFORE_ROLL_GAIN
	for a in mind:
		var c := game.clone()
		c.resolve_queen_choice(sp, int(a.data["queen_action"]), step["repeat"])
		var v := evaluate(c)
		if v > best_value:
			best_value = v
			best_mind = a
	return best_mind if best_mind != null else roll


# --- Utilidades -----------------------------------------------------------------------

static func _is_offensive(a: GameAction) -> bool:
	return a.type == G.PLAY_CARD and D.card(a.data["card"])["kind"] == D.CardKind.OFFENSIVE


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
