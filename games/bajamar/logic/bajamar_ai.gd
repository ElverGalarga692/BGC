class_name BajamarAI
extends RefCounted
## IA de Bajamar, con tres niveles:
##
##   Fácil: no cuenta cartas. Pesca hasta llevar bastantes puntos y entonces
##          se lleva la mejor carta del mercado si le suma algo. A veces se
##          equivoca.
##   Normal: cuenta cartas y compara plantarse (con o sin carta del mercado)
##          con el valor esperado de robar a ciegas una vez más.
##   Difícil: mira dos robos por delante, valora la Gaviota según a quién
##          perjudica y, cuando la partida se decide en esta ronda, juega para
##          ganar (prefiere arriesgar si plantarse no le basta, y asegurar si
##          ya le basta).
##
## Contar cartas no es hacer trampa: todo lo que no está en el mazo está a la
## vista (redes, redes reforzadas, mercado y descartes), así que lo
## que queda en el mazo se deduce de la mesa. Solo el orden es secreto.
##
## Misma interfaz que el resto de IAs: new(pid, nivel, semilla) y
## choose_action(game).

const AILevel := PlayerInfo.AILevel
const D := preload("res://games/bajamar/logic/bajamar_defs.gd")
const G := preload("res://games/bajamar/logic/bajamar_game.gd")

# --- Fácil ------------------------------------------------------------------
const EASY_STOP := 18
const EASY_MISTAKE_CHANCE := 0.12

# --- Valoraciones -----------------------------------------------------------
## Valor de una Marea alta para quien la roba (un robo extra, más o menos).
const TIDE_VALUE := 3.0
## Difícil: peso del daño hecho a la víctima de la gaviota y extra si es quien
## va ganando.
const HARM_WEIGHT := 0.5
const LEADER_HARM_WEIGHT := 0.5
## Difícil: con la partida decidiéndose, cuánto vale ganar frente a puntos.
const WIN_UTILITY := 1000.0
## Difícil: puntos que se supone que aún sumará un rival que sigue en el mar.
const AT_SEA_MARGIN := 6

var pid: int
var level: int
var _rng := RandomNumberGenerator.new()

## Cartas que quedan en el mazo (carta -> copias) y cuántas son. Se calcula
## al empezar cada decisión.
var _pool := {}
var _pool_size := 0
## Difícil: si la partida se decide esta ronda, puntos totales que tiene que
## superar (y los que ya tiene antes de esta ronda).
var _must_beat := -1
var _my_total := 0


func _init(p_pid: int, p_level: int = AILevel.NORMAL, p_seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng.seed = hash([p_seed, p_pid, "bajamar"])


func choose_action(game: BajamarGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	if not game.pending_gulls.is_empty():
		return _choose_gull_target(game, legal)
	if level == AILevel.EASY:
		if _rng.randf() < EASY_MISTAKE_CHANCE:
			return legal[_rng.randi_range(0, legal.size() - 1)]
		return _easy(game, legal)
	_count_cards(game)
	_must_beat = _final_round_threshold(game) if level == AILevel.HARD else -1
	_my_total = game.scores[pid]
	var depth := 2 if level == AILevel.HARD else 1
	var net: Array = game.net(pid)
	var best: GameAction = null
	var best_value := -INF
	for action in legal:
		var value := 0.0
		match action.type:
			G.GO_TO_PORT:
				value = _utility(D.score(net)["total"])
			G.TAKE_MARKET:
				value = _market_value(game, net, game.market[int(action.data["slot"])])
			G.DRAW_BLIND:
				value = _draw_value(game, net, game.shields[pid], depth)
		if value > best_value + 0.0001:
			best_value = value
			best = action
	return best


# --- Fácil ----------------------------------------------------------------------

func _easy(game: BajamarGame, legal: Array[GameAction]) -> GameAction:
	var points: int = game.net_score(pid)["total"]
	var can_draw := legal.any(func(a: GameAction) -> bool: return a.type == G.DRAW_BLIND)
	if points < EASY_STOP and can_draw:
		return GameAction.new(G.DRAW_BLIND, pid)
	# Se planta: con la carta del mercado que más le suma (si alguna suma).
	var best := GameAction.new(G.GO_TO_PORT, pid)
	var best_points := points
	for slot in game.market.size():
		var card: int = game.market[slot]
		if not D.is_fish(card):
			continue
		var after: int = D.score(game.net(pid) + [card])["total"]
		if after > best_points:
			best_points = after
			best = GameAction.new(G.TAKE_MARKET, pid, {"slot": slot})
	return best


# --- Contar cartas ----------------------------------------------------------------

## Deduce el contenido del mazo con lo que está a la vista. Si el mazo está
## vacío, el siguiente robo sale de los descartes barajados.
func _count_cards(game: BajamarGame) -> void:
	_pool.clear()
	if game.deck.is_empty():
		for card in game.discard:
			_pool[card] = _pool.get(card, 0) + 1
	else:
		for card in D.deck():
			_pool[card] = _pool.get(card, 0) + 1
		var seen: Array = game.discard + game.market
		for p in game.players.size():
			seen.append_array(game.net(p))
			if game.shields[p]:
				seen.append(D.SHIELD)
		for card in seen:
			_pool[card] = _pool.get(card, 0) - 1
		for card in _pool.keys():
			if _pool[card] <= 0:
				_pool.erase(card)
	_pool_size = 0
	for card in _pool:
		_pool_size += _pool[card]


# --- Valor de las jugadas -------------------------------------------------------

## Valor de plantarse con la red tal cual o con la mejor carta del mercado.
func _stop_value(game: BajamarGame, net: Array) -> float:
	var best := _utility(D.score(net)["total"])
	for card in game.market:
		best = maxf(best, _market_value(game, net, card))
	return best


## Valor de coger `card` del mercado y volver a puerto.
func _market_value(game: BajamarGame, net: Array, card: int) -> float:
	if D.is_fish(card):
		return _utility(D.score(net + [card])["total"])
	if card == D.GULL:
		var steal := _best_steal(game, net)
		return _utility(D.score(net + steal["fish"])["total"]) + steal["harm"]
	# Red reforzada y Marea alta no le sirven a quien vuelve a puerto (la
	# marea solo afecta a los demás: la difícil le da un pequeño valor).
	var bonus := TIDE_VALUE * 0.5 if card == D.HIGH_TIDE and level == AILevel.HARD else 0.0
	return _utility(D.score(net)["total"]) + bonus


## Valor esperado de robar a ciegas, mirando `depth` robos por delante (las
## probabilidades no se actualizan entre robos: es una aproximación).
func _draw_value(game: BajamarGame, net: Array, shielded: bool, depth: int) -> float:
	if _pool_size == 0:
		return -INF
	var total := 0.0
	for card in _pool:
		var p := float(_pool[card]) / _pool_size
		total += p * _after_card(game, net, shielded, card, depth - 1)
	return total


## Valor de la situación tras recibir `card`, con `depth` robos más por
## delante como mucho.
func _after_card(game: BajamarGame, net: Array, shielded: bool, card: int, depth: int) -> float:
	if D.is_fish(card):
		return _state_value(game, net + [card], shielded, depth)
	if D.is_storm(card):
		if shielded:
			return _utility(int(D.score(net)["total"]) / 2)
		return _utility(0)
	if card == D.SHIELD:
		return _state_value(game, net, true, depth)
	if card == D.GULL:
		var steal := _best_steal(game, net)
		return _state_value(game, net + steal["fish"], shielded, depth) + steal["harm"]
	return _state_value(game, net, shielded, depth) + TIDE_VALUE


## Lo mejor entre plantarse y seguir robando.
func _state_value(game: BajamarGame, net: Array, shielded: bool, depth: int) -> float:
	var stop := _stop_value(game, net)
	if depth <= 0:
		return stop
	return maxf(stop, _draw_value(game, net, shielded, depth))


## Mejor pez que podría quitar una gaviota y cuánto vale el daño causado
## (solo la difícil lo tiene en cuenta).
func _best_steal(game: BajamarGame, net: Array) -> Dictionary:
	var best := {"fish": [], "harm": 0.0, "target": -1}
	var best_value := -INF
	for t in game.gull_targets(pid):
		var value := _steal_value(game, net, t)
		if value > best_value:
			best_value = value
			var fish: int = game.net(t)[-1]
			best = {"fish": [fish], "harm": value - (D.score(net + [fish])["total"] - D.score(net)["total"]), "target": t}
	return best


## Lo que gana quitándole el último pez a `target` (más el daño que le hace,
## en la difícil).
func _steal_value(game: BajamarGame, net: Array, target: int) -> float:
	var theirs: Array = game.net(target)
	var fish: int = theirs[-1]
	var gain: int = D.score(net + [fish])["total"] - D.score(net)["total"]
	if level != AILevel.HARD:
		return gain
	var loss: int = D.score(theirs)["total"] - D.score(theirs.slice(0, theirs.size() - 1))["total"]
	var weight := HARM_WEIGHT
	if target == _leader(game):
		weight += LEADER_HARM_WEIGHT
	return gain + weight * loss


func _choose_gull_target(game: BajamarGame, legal: Array[GameAction]) -> GameAction:
	if level == AILevel.EASY:
		return legal[_rng.randi_range(0, legal.size() - 1)]
	var best: GameAction = legal[0]
	var best_value := -INF
	for action in legal:
		var value := _steal_value(game, game.net(pid), int(action.data["target"]))
		if value > best_value:
			best_value = value
			best = action
	return best


# --- Final de partida (difícil) ---------------------------------------------------

## Rival con más puntos (contando lo que ya tiene asegurado en puerto).
func _leader(game: BajamarGame) -> int:
	var best := -1
	var best_points := -1
	for p in game.players.size():
		if p == pid:
			continue
		var points := _projected(game, p)
		if points > best_points:
			best_points = points
			best = p
	return best


## Puntos de un jugador al final de esta ronda si se plantara ya.
func _projected(game: BajamarGame, p: int) -> int:
	if game.status[p] == G.Status.BROKEN:
		return game.scores[p]
	return game.scores[p] + int(game.net_score(p)["total"])


## Si la partida va a terminar al acabar esta ronda (alguien llega ya a la
## meta con lo que lleva), devuelve los puntos que hay que superar para
## ganar; si no, -1.
func _final_round_threshold(game: BajamarGame) -> int:
	var ends := false
	var rival_best := 0
	for p in game.players.size():
		var points := _projected(game, p)
		if p != pid:
			# Quien sigue en el mar seguramente pescará algo más.
			var margin := AT_SEA_MARGIN if game.status[p] == G.Status.AT_SEA else 0
			rival_best = maxi(rival_best, points + margin)
		if p != pid and points >= game.target_score:
			ends = true
	if game.scores[pid] + int(game.net_score(pid)["total"]) >= game.target_score:
		ends = true
	return rival_best if ends else -1


## Utilidad de acabar la ronda con `points`: los puntos, o (si la partida
## se decide ahora) sobre todo si se gana.
func _utility(points: int) -> float:
	if _must_beat < 0:
		return float(points)
	var mine := float(points)
	return mine + (WIN_UTILITY if _my_total + points > _must_beat else 0.0)

