class_name ArchAI
extends RefCounted
## Jugador controlado por el ordenador para Archipiélago.
##
## Cada llamada a choose_action() devuelve UNA acción legal para el jugador
## (o null si no le toca). La IA solo usa información pública más su propia
## mano: no mira las cartas de los demás.
##
## Niveles:
##   EASY    elige al azar entre las acciones legales, prefiriendo construir.
##   NORMAL  heurísticas: valora las esquinas por probabilidad y variedad de
##           recursos, persigue un objetivo de construcción, comercia hacia
##           él, ataca al líder con el bandido y evalúa las ofertas.
##   HARD    como NORMAL, y además: cuenta las cartas de los rivales
##           (ArchCardTracker) para elegir Monopolio y socios de comercio,
##           valora el potencial de expansión de cada esquina, prioriza
##           trigo, mineral y cartas de desarrollo, juega los Milicianos en
##           cuanto puede, no gasta lo que reserva para su objetivo, castiga
##           más al líder y se lanza a por los últimos puntos al final.
##           Ajustada con torneos: gana ~43 % de las partidas contra tres
##           IAs normales (25 % sería el empate).
##
## Para el nivel HARD hay que llamar a observe(game) al crear la IA.

const AILevel := PlayerInfo.AILevel
const G := preload("res://games/archipelago/logic/archipelago_game.gd")
const DevCard := ArchDefs.DevCard

## Valor base de cada recurso (madera, ladrillo, lana, trigo, mineral).
const BASE_WEIGHT := [1.0, 1.0, 0.85, 1.0, 1.0]
## La IA difícil valora más el trigo y el mineral (ciudades y cartas).
const HARD_WEIGHT := [1.0, 1.0, 0.8, 1.15, 1.15]
## Cuánto pesa el potencial de expansión al elegir esquina (IA difícil).
const EXPANSION_WEIGHT := 0.3
## Preferencia por ciudades y por cartas de desarrollo al elegir objetivo
## (menos = más preferencia), para la IA normal y la difícil.
const CITY_BIAS := -0.5
const HARD_CITY_BIAS := -0.5
const DEV_BIAS := 1.5
const HARD_DEV_BIAS := 0.3

var pid: int
var level: int
var _rng: BGCRng
## Turno en el que la IA ya hizo una oferta a otro jugador.
var _offered_turn := ""
## Contador de cartas (solo nivel HARD).
var tracker: ArchCardTracker
var _hard: bool:
	get:
		return level == AILevel.HARD


func _init(p_pid: int, p_level: int = AILevel.NORMAL, p_seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng = BGCRng.new(p_seed * 7919 + p_pid)


## Empieza a observar la partida (necesario para contar cartas).
func observe(game: ArchipelagoGame) -> void:
	if _hard and tracker == null:
		tracker = ArchCardTracker.new()
		tracker.observe(game, pid)


func choose_action(game: ArchipelagoGame) -> GameAction:
	if game.finished or not pid in game.players_to_act():
		return null
	var action := _choose_easy(game) if level == AILevel.EASY else _choose_normal(game)
	if action == null or game.validate(action) != "":
		# Red de seguridad: nunca bloquear la partida.
		var legal := game.get_legal_actions(pid)
		action = legal.back() if not legal.is_empty() else null
	return action


# --- Nivel fácil ----------------------------------------------------------------

func _choose_easy(game: ArchipelagoGame) -> GameAction:
	var actions := game.get_legal_actions(pid)
	if actions.is_empty():
		return null
	if game.phase == G.Phase.ROLL:
		return GameAction.new(G.ROLL, pid)
	if game.phase != G.Phase.MAIN or not game.trade_offer.is_empty():
		return _rng.pick(actions)
	var builds := actions.filter(func(a: GameAction) -> bool:
		return a.type in [G.BUILD_CITY, G.BUILD_SETTLEMENT, G.BUILD_ROAD, G.BUY_DEV, G.PLAY_DEV])
	if not builds.is_empty() and _rng.randf() < 0.8:
		return _rng.pick(builds)
	var trades := actions.filter(func(a: GameAction) -> bool: return a.type == G.TRADE_BANK)
	if not trades.is_empty() and _rng.randf() < 0.3:
		return _rng.pick(trades)
	return GameAction.new(G.END_TURN, pid)


# --- Nivel normal ---------------------------------------------------------------

func _choose_normal(game: ArchipelagoGame) -> GameAction:
	if not game.trade_offer.is_empty():
		return _respond_to_offer(game)
	match game.phase:
		G.Phase.SETUP:
			if game.setup_vertex == -1:
				return GameAction.new(G.BUILD_SETTLEMENT, pid, {"vertex": _best_vertex(game, game.legal_settlement_vertices(pid))})
			return GameAction.new(G.BUILD_ROAD, pid, {"edge": _best_road(game)[0]})
		G.Phase.ROLL:
			if _wants_militia(game, true):
				return GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.MILITIA})
			return GameAction.new(G.ROLL, pid)
		G.Phase.DISCARD:
			return GameAction.new(G.DISCARD, pid, {"cards": _discard(game)})
		G.Phase.ROBBER:
			return _move_bandit(game)
		G.Phase.ROAD_BUILDING:
			return GameAction.new(G.BUILD_ROAD, pid, {"edge": _best_road(game)[0]})
		G.Phase.MAIN:
			return _main_turn(game)
	return null


func _main_turn(game: ArchipelagoGame) -> GameAction:
	var goal := _pick_goal(game)
	var cost: Array = G.COSTS.get(goal, [0, 0, 0, 0, 0])

	# 1. Cartas de desarrollo.
	if _wants_militia(game, false):
		return GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.MILITIA})
	var road := _best_road(game)
	if _can_play(game, DevCard.ROAD_BUILDING) and road[0] >= 0 and road[1] > 0.0:
		return GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.ROAD_BUILDING})
	var missing := _missing(game, cost)
	if _can_play(game, DevCard.HARVEST) and goal != &"":
		var wanted := _harvest_choice(game, missing)
		var action := GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.HARVEST, "resources": wanted})
		if _sum(missing) in [1, 2] and game.validate(action) == "":
			return action
	if _can_play(game, DevCard.MONOPOLY):
		if tracker != null:
			var best_r := 0
			for r in 5:
				if tracker.others_have(r) > tracker.others_have(best_r):
					best_r = r
			if tracker.others_have(best_r) >= 3.0:
				return GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.MONOPOLY, "resource": best_r})
		elif _sum(missing) >= 2 and game.turns.round_number >= 4:
			return GameAction.new(G.PLAY_DEV, pid, {"card": DevCard.MONOPOLY, "resource": _most_missing(missing)})

	# 2. Construir.
	if game.build_error(pid, G.BUILD_CITY) == "":
		return GameAction.new(G.BUILD_CITY, pid, {"vertex": _best_city(game)})
	if game.build_error(pid, G.BUILD_SETTLEMENT) == "":
		return GameAction.new(G.BUILD_SETTLEMENT, pid, {"vertex": _best_vertex(game, game.legal_settlement_vertices(pid))})
	var road_ok := goal == G.BUILD_ROAD or (_racing_for_road(game) and (not _hard or _spare(game, cost, G.COSTS[G.BUILD_ROAD])))
	if game.build_error(pid, G.BUILD_ROAD) == "" and road[0] >= 0 and road_ok:
		return GameAction.new(G.BUILD_ROAD, pid, {"edge": road[0]})
	var dev_ok := goal == G.BUY_DEV or game.hand_size(pid) > G.DISCARD_LIMIT
	if _hard:
		var endgame := game.victory_points(pid) >= game.victory_points_target - 2
		dev_ok = goal == G.BUY_DEV or endgame or (game.hand_size(pid) > G.DISCARD_LIMIT and _spare(game, cost, G.COSTS[G.BUY_DEV]))
	if game.validate(GameAction.new(G.BUY_DEV, pid)) == "" and dev_ok:
		return GameAction.new(G.BUY_DEV, pid)

	# 3. Comerciar hacia el objetivo.
	if goal != &"":
		var trade := _bank_trade(game, cost)
		if trade != null:
			return trade
		var offer := _player_offer(game, cost)
		if offer != null:
			return offer

	# 4. Con muchas cartas, gasta en lo que se pueda antes de arriesgarse a un 7.
	if game.hand_size(pid) > G.DISCARD_LIMIT and game.build_error(pid, G.BUILD_ROAD) == "" and road[0] >= 0:
		return GameAction.new(G.BUILD_ROAD, pid, {"edge": road[0]})
	return GameAction.new(G.END_TURN, pid)


## true si, tras reservar `reserved` para el objetivo, aún se puede pagar
## `cost`.
func _spare(game: ArchipelagoGame, reserved: Array, cost: Array) -> bool:
	for r in 5:
		if game.hands[pid][r] - reserved[r] < cost[r]:
			return false
	return true


## Elige qué construir a continuación: lo que esté más cerca de poder
## pagarse, con preferencia por ciudades y poblados.
func _pick_goal(game: ArchipelagoGame) -> StringName:
	var options := {}
	var settlement_spots := not game.legal_settlement_vertices(pid).is_empty()
	if game.pieces[pid]["settlement"] > 0 and settlement_spots:
		options[G.BUILD_SETTLEMENT] = 0.0
	if game.pieces[pid]["city"] > 0 and not game.legal_city_vertices(pid).is_empty():
		options[G.BUILD_CITY] = HARD_CITY_BIAS if _hard else CITY_BIAS
	if not settlement_spots and game.pieces[pid]["settlement"] > 0 and game.pieces[pid]["road"] > 0 and _best_road(game)[0] >= 0:
		options[G.BUILD_ROAD] = 0.5
	if not game.dev_deck.is_empty():
		options[G.BUY_DEV] = HARD_DEV_BIAS if _hard else DEV_BIAS
	var best := &""
	var best_score := INF
	for goal in options:
		var score: float = _sum(_missing(game, G.COSTS[goal])) + options[goal]
		if score < best_score:
			best = goal
			best_score = score
	return best


# --- Valoración del tablero -------------------------------------------------------

## Probabilidad (en "puntos" de 2d6) de cada recurso para este jugador.
func _production(game: ArchipelagoGame) -> Array[float]:
	var prod: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for v in game.vertex_owner.size():
		if game.vertex_owner[v] != pid:
			continue
		var mult := 1.0 if game.vertex_building[v] == G.Building.SETTLEMENT else 2.0
		for t in game.board.grid.vertex_tiles[v]:
			var r := game.board.tile_resource(t)
			if r >= 0:
				prod[r] += ArchDefs.number_pips(game.board.tile_number[t]) * mult
	return prod


## Peso de cada recurso: los que el jugador apenas produce valen más.
func _weights(game: ArchipelagoGame) -> Array[float]:
	var prod := _production(game)
	var w: Array[float] = []
	var base: Array = HARD_WEIGHT if _hard else BASE_WEIGHT
	for r in 5:
		w.append(base[r] * (1.0 + 0.8 / (1.0 + prod[r])))
	return w


func vertex_score(game: ArchipelagoGame, v: int, weights: Array[float]) -> float:
	var board := game.board
	var score := 0.0
	var kinds := {}
	for t in board.grid.vertex_tiles[v]:
		var r := board.tile_resource(t)
		if r < 0:
			continue
		var pips := float(ArchDefs.number_pips(board.tile_number[t]))
		if t == board.bandit_tile:
			pips *= 0.5
		score += pips * weights[r]
		kinds[r] = true
	score += kinds.size() * 1.2
	var port = board.vertex_port(v)
	if port != null:
		if port["type"] == ArchDefs.PORT_GENERIC:
			score += 1.0
		else:
			score += 0.5 + _production(game)[port["type"]] * 0.25
	return score


func _best_vertex(game: ArchipelagoGame, candidates: Array[int]) -> int:
	var weights := _weights(game)
	var best := -1
	var best_score := -INF
	for v in candidates:
		var s := vertex_score(game, v, weights) + _rng.randf() * 0.01
		if _hard and game.vertex_owner[v] == -1:
			s += EXPANSION_WEIGHT * _expansion(game, v, weights)
		if s > best_score:
			best = v
			best_score = s
	return best


## La ciudad que más produce.
func _best_city(game: ArchipelagoGame) -> int:
	return _best_vertex(game, game.legal_city_vertices(pid))


## Mejor sitio libre para un poblado a dos caminos de `v` (potencial de
## expansión).
func _expansion(game: ArchipelagoGame, v: int, weights: Array[float]) -> float:
	var grid := game.board.grid
	var best := 0.0
	for n in grid.vertex_neighbors[v]:
		for u in grid.vertex_neighbors[n]:
			if u != v and _spot_free(game, u):
				best = maxf(best, vertex_score(game, u, weights))
	return best


func _spot_free(game: ArchipelagoGame, v: int) -> bool:
	if game.vertex_owner[v] != -1:
		return false
	for n in game.board.grid.vertex_neighbors[v]:
		if game.vertex_owner[n] != -1:
			return false
	return true


## Mejor camino que construir: [arista, valor]. El valor mide lo bueno que
## es el sitio para un poblado al que acerca (0 si no acerca a ninguno).
func _best_road(game: ArchipelagoGame) -> Array:
	var grid := game.board.grid
	var weights := _weights(game)
	var best := -1
	var best_value := -INF
	for e in game.legal_road_edges(pid):
		var value := 0.0
		for f in grid.edge_vertices[e]:
			if game.vertex_owner[f] == pid:
				continue
			if _spot_free(game, f):
				value = maxf(value, vertex_score(game, f, weights))
			for u in grid.vertex_neighbors[f]:
				if _spot_free(game, u):
					value = maxf(value, vertex_score(game, u, weights) - 2.0)
		value += _rng.randf() * 0.01
		if value > best_value:
			best = e
			best_value = value
	return [best, maxf(best_value, 0.0)]


## true si merece la pena alargar caminos para el Camino más largo.
func _racing_for_road(game: ArchipelagoGame) -> bool:
	if game.longest_road_owner == pid:
		return false
	var mine := game.road_lengths[pid]
	var target := G.LONGEST_ROAD_MIN if game.longest_road_owner == -1 else game.road_lengths[game.longest_road_owner] + 1
	return target - mine <= 2


# --- Cartas de desarrollo -----------------------------------------------------------

func _can_play(game: ArchipelagoGame, card: int) -> bool:
	var data := {"card": card, "resource": 0, "resources": [0, 0]}
	if card == DevCard.HARVEST:
		var best := game.bank.find(game.bank.max())
		data["resources"] = [best, best]
	return game.validate(GameAction.new(G.PLAY_DEV, pid, data)) == ""


func _wants_militia(game: ArchipelagoGame, before_roll: bool) -> bool:
	if not _can_play(game, DevCard.MILITIA):
		return false
	var blocked := false
	for v in game.board.grid.tile_vertices[game.board.bandit_tile]:
		if game.vertex_owner[v] == pid and game.board.tile_number[game.board.bandit_tile] > 0:
			blocked = true
	if blocked:
		return true
	if before_roll:
		return false
	if _hard:
		return true  # la IA difícil presiona con el bandido y la Mayor milicia
	var next := game.militia_played[pid] + 1
	var holder := game.largest_army_owner
	if holder == pid:
		return false
	return next >= G.LARGEST_ARMY_MIN and (holder == -1 or next > game.militia_played[holder])


func _harvest_choice(game: ArchipelagoGame, missing: Array[int]) -> Array:
	var wanted: Array = []
	for r in 5:
		for i in missing[r]:
			if wanted.size() < 2:
				wanted.append(r)
	var weights := _weights(game)
	while wanted.size() < 2:
		wanted.append(weights.find(weights.max()))
	return wanted


# --- Bandido y descartes ------------------------------------------------------------

func _move_bandit(game: ArchipelagoGame) -> GameAction:
	var board := game.board
	var best_tile := -1
	var best_score := -INF
	for t in game.bandit_tiles():
		var pips := float(ArchDefs.number_pips(board.tile_number[t]))
		var score := 0.0
		for v in board.grid.tile_vertices[t]:
			var owner := game.vertex_owner[v]
			if owner == -1:
				continue
			var mult := 1.0 if game.vertex_building[v] == G.Building.SETTLEMENT else 2.0
			if owner == pid:
				score -= pips * mult * 2.0
			else:
				score += pips * mult * (1.0 + game.public_victory_points(owner) / (2.5 if _hard else 4.0))
		if game.bandit_victims(pid, t).is_empty():
			score -= 1.0
		score += _rng.randf() * 0.01
		if score > best_score:
			best_tile = t
			best_score = score
	var victims := game.bandit_victims(pid, best_tile)
	var victim := -1
	for p in victims:
		if victim == -1 or _threat(game, p) > _threat(game, victim):
			victim = p
	return GameAction.new(G.MOVE_BANDIT, pid, {"tile": best_tile, "victim": victim})


func _threat(game: ArchipelagoGame, p: int) -> float:
	return game.public_victory_points(p) * 10.0 + game.hand_size(p)


## Descarta lo que menos falta hace para el objetivo actual.
func _discard(game: ArchipelagoGame) -> Array[int]:
	var needed: int = game.pending_discards[pid]
	var goal := _pick_goal(game)
	var cost: Array = G.COSTS.get(goal, [0, 0, 0, 0, 0])
	var hand: Array[int] = game.hands[pid].duplicate()
	var weights := _weights(game)
	var cards: Array[int] = [0, 0, 0, 0, 0]
	for i in needed:
		var worst := -1
		var worst_value := INF
		for r in 5:
			if hand[r] == 0:
				continue
			# Las cartas que sobran respecto al objetivo valen poco.
			var value := weights[r] * (3.0 if hand[r] <= cost[r] else 1.0) - hand[r] * 0.1
			if value < worst_value:
				worst = r
				worst_value = value
		hand[worst] -= 1
		cards[worst] += 1
	return cards


# --- Comercio ------------------------------------------------------------------------

func _missing(game: ArchipelagoGame, cost: Array) -> Array[int]:
	var result: Array[int] = []
	for r in 5:
		result.append(maxi(0, cost[r] - game.hands[pid][r]))
	return result


func _most_missing(missing: Array[int]) -> int:
	return missing.find(missing.max())


## Cambio con la banca que acerca al objetivo usando cartas que sobran.
func _bank_trade(game: ArchipelagoGame, cost: Array) -> GameAction:
	var missing := _missing(game, cost)
	if _sum(missing) == 0:
		return null
	for give in 5:
		var surplus: int = game.hands[pid][give] - cost[give]
		if surplus < game.trade_ratio(pid, give):
			continue
		for receive in 5:
			if missing[receive] > 0:
				var action := GameAction.new(G.TRADE_BANK, pid, {"give": give, "receive": receive})
				if game.validate(action) == "":
					return action
	return null


## Oferta 1 por 1 a otro jugador (como mucho una por turno), evitando
## ayudar a quien está cerca de ganar.
func _player_offer(game: ArchipelagoGame, cost: Array) -> GameAction:
	var turn_key := "%d:%d" % [game.turns.round_number, game.turns.current]
	if _offered_turn == turn_key:
		return null
	_offered_turn = turn_key
	# Solo cuando le falta una carta, y no siempre, para no agobiar a los
	# humanos con ofertas.
	var missing := _missing(game, cost)
	if _hard:
		if _sum(missing) == 0 or _sum(missing) > 2:
			return null
	elif _sum(missing) != 1 or _rng.randf() < 0.5:
		return null
	var give := -1
	for r in 5:
		if game.hands[pid][r] - cost[r] > 0 and (give == -1 or game.hands[pid][r] > game.hands[pid][give]):
			give = r
	if give == -1:
		return null
	var partners: Array[int] = []
	for p in game.players.size():
		if p != pid and game.hand_size(p) > 0 and game.public_victory_points(p) < game.victory_points_target - 2:
			partners.append(p)
	if partners.is_empty():
		return null
	var wanted := _most_missing(missing)
	var partner: int = _rng.pick(partners)
	if tracker != null:
		# Ofrece a quien probablemente tenga la carta que necesita.
		partner = -1
		for p in partners:
			if tracker.estimate(p)[wanted] >= 0.6 and (partner == -1 or tracker.estimate(p)[wanted] > tracker.estimate(partner)[wanted]):
				partner = p
		if partner == -1:
			return null
	var give_cards: Array[int] = [0, 0, 0, 0, 0]
	var receive_cards: Array[int] = [0, 0, 0, 0, 0]
	give_cards[give] = 1
	receive_cards[wanted] = 1
	return GameAction.new(G.OFFER_TRADE, pid, {"to": partner, "give": give_cards, "receive": receive_cards})


## Acepta si sale ganando según lo que necesita y quien ofrece no está a
## punto de ganar.
func _respond_to_offer(game: ArchipelagoGame) -> GameAction:
	var offer := game.trade_offer
	if offer["to"] != pid:
		return null
	var accept := GameAction.new(G.ACCEPT_TRADE, pid)
	var reject := GameAction.new(G.REJECT_TRADE, pid)
	if game.validate(accept) != "":
		return reject
	if game.public_victory_points(offer["from"]) >= game.victory_points_target - (3 if _hard else 2):
		return reject
	var goal := _pick_goal(game)
	var cost: Array = G.COSTS.get(goal, [0, 0, 0, 0, 0])
	var missing := _missing(game, cost)
	var weights := _weights(game)
	var gained := 0.0
	var lost := 0.0
	for r in 5:
		gained += offer["give"][r] * weights[r] * (1.6 if missing[r] > 0 else 1.0)
		var keep_needed: bool = game.hands[pid][r] - offer["receive"][r] < cost[r]
		lost += offer["receive"][r] * weights[r] * (1.6 if keep_needed else 1.0)
	return accept if gained > lost * 1.05 else reject


static func _sum(values: Array) -> int:
	var total := 0
	for n in values:
		total += n
	return total
