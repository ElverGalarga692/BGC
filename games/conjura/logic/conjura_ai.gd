class_name ConjuraAI
extends RefCounted
## IA de La Conjura. Solo usa game.view_for(pid): no hace trampa.
##
## Guardia: deduce con ConjuraDeduction quién es probablemente traidor;
##   nomina y aprueba gobiernos fiables, siempre dice la verdad y usa los
##   poderes contra los más sospechosos.
## Sombra: conoce a su equipo. Miente de forma coordinada en las
##   declaraciones («robé tres de la Sombra», «me pasó dos de la Sombra»),
##   mide cuánto sospecha la mesa de cada uno (deducción pública) y solo se
##   arriesga cuando le compensa. Intenta que elijan Consejero al Usurpador
##   en cuanto hay 3 edictos de la Sombra.
## Usurpador: juega «limpio» para ganarse la confianza de la mesa.
##
## Niveles: fácil (sin deducción, mucho ruido), normal y difícil (menos
## ruido; la Sombra difícil vigila mejor cuánto se expone).

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const G := preload("res://games/conjura/logic/conjura_game.gd")
const Deduction := preload("res://games/conjura/logic/conjura_deduction.gd")
const Role := ConjuraDefs.Role
const Faction := ConjuraDefs.Faction
const Edict := ConjuraDefs.Edict
const Power := ConjuraDefs.Power

## Ajustes de la Sombra (equilibrados con simulaciones entre IAs).
const BOLD_HEAT := 0.8
const BOLD_MARGIN := 0.4
const USURPER_MAX_HEAT := 0.35

var pid: int
var level: int
var _rng: BGCRng
var _view: Dictionary
var _probs: Array[float] = []
var _public: Array[float] = []
var _cache_key := ""


func _init(p_pid: int, p_level: int = PlayerInfo.AILevel.NORMAL, seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng = BGCRng.new(seed * 31 + p_pid * 7919 + 17)


func choose_action(game: ConjuraGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	_view = game.view_for(pid)
	_update_beliefs(game)
	if _view["phase"] == G.Phase.CLAIMS:
		return GameAction.new(G.CLAIM, pid, {"cards": _claim()})
	var best: GameAction = legal[0]
	var best_score := -INF
	for action in legal:
		var score := _score(action) + _noise()
		if score > best_score:
			best_score = score
			best = action
	return best


# --- Creencias ---------------------------------------------------------------

func _update_beliefs(game: ConjuraGame) -> void:
	var govs: Array = _view["governments"]
	var claims: int = 0 if govs.is_empty() else govs[-1].get("claims", {}).size()
	var key := "%d|%d|%d|%d" % [govs.size(), _view["knowledge"].size(), claims, _view["alive"].count(true)]
	if key == _cache_key:
		return
	_cache_key = key
	var n: int = _view["player_count"]
	if level == PlayerInfo.AILevel.EASY:
		_probs = _naive_probs()
		_public = _probs.duplicate()
		return
	_probs = Deduction.evil_probabilities(_view)
	_public = Deduction.evil_probabilities(game.view_for(-1)) if _is_sombra() else _probs.duplicate()
	assert(_probs.size() == n)


## Nivel fácil: solo cuenta edictos de la Sombra de cada gobierno.
func _naive_probs() -> Array[float]:
	var n: int = _view["player_count"]
	var k: float = D.ROLE_TABLE[n][1] + 1
	var result: Array[float] = []
	result.resize(n)
	result.fill(k / n)
	var known: Dictionary = _view["known_roles"]
	for gov in _view["governments"]:
		if not gov["approved"] or gov["crisis"]:
			continue
		var delta := 0.12 if gov["edict"] == Edict.SOMBRA else (-0.08 if gov["edict"] == Edict.GUARDIA else 0.0)
		result[gov["regent"]] = clampf(result[gov["regent"]] + delta, 0.02, 0.98)
		result[gov["nominee"]] = clampf(result[gov["nominee"]] + delta * 1.2, 0.02, 0.98)
	for p in known:
		result[p] = 1.0 if D.faction_of(known[p]) == Faction.SOMBRA else 0.0
	return result


func _noise() -> float:
	match level:
		PlayerInfo.AILevel.EASY: return _rng.randf() * 1.5
		PlayerInfo.AILevel.NORMAL: return _rng.randf() * 0.8
	return _rng.randf() * 0.08


func _my_role() -> int:
	return _view["known_roles"][pid]


## Juega como Sombra (conoce a su equipo). El Usurpador que no conoce a sus
## aliados juega como si fuera de la Guardia, para ganarse confianza.
func _is_sombra() -> bool:
	var role := _my_role()
	return role == Role.SOMBRA or (role == Role.USURPADOR and _view["known_roles"].size() > 1)


func _is_ally(other: int) -> bool:
	var known: Dictionary = _view["known_roles"]
	return other != pid and known.has(other) and D.faction_of(known[other]) == Faction.SOMBRA and D.faction_of(_my_role()) == Faction.SOMBRA


func _is_usurper(other: int) -> bool:
	return _view["known_roles"].get(other, -1) == Role.USURPADOR


func _usurper_ready() -> bool:
	return int(_view["sombra_edicts"]) >= D.USURPER_THRESHOLD


## Cuánto sospecha la mesa de `other` (0..1).
func _heat(other: int) -> float:
	return _public[other]


## La Sombra se arriesga si está cerca de ganar o si sospechan poco de ella.
func _bold(regent: int, council: int) -> bool:
	var sombra: int = _view["sombra_edicts"]
	if sombra >= D.SOMBRA_TO_WIN - 1:
		return true
	if _my_role() == Role.USURPADOR and _heat(pid) > USURPER_MAX_HEAT:
		return false  # el Usurpador no puede quemarse: lo necesitan limpio
	var other := council if regent == pid else regent
	# La difícil se fija en si el otro cargará con la culpa (si la mesa
	# sospecha más de él que de mí); la normal solo en lo quemado que estoy.
	if level == PlayerInfo.AILevel.HARD:
		return _heat(pid) < 0.8 and _heat(pid) <= _heat(other) + BOLD_MARGIN
	return _heat(pid) < BOLD_HEAT


# --- Puntuación de jugadas ----------------------------------------------------------

func _score(action: GameAction) -> float:
	match action.type:
		G.NOMINATE:
			return _nominate_score(int(action.data["target"]))
		G.VOTE:
			return _vote_score(bool(action.data["yes"]))
		G.DISCARD:
			var hand: Array = _view["hand"]
			var rest := hand.duplicate()
			rest.remove_at(int(action.data["index"]))
			return _pass_score(rest)
		G.ENACT:
			var hand: Array = _view["hand"]
			return _enact_score(int(hand[int(action.data["index"])]))
		G.CHOOSE_POWER:
			return _power_value(int(_view["power_options"][int(action.data["index"])]))
		G.USE_POWER:
			return _power_target_score(int(action.data["target"]))
	return 0.0


func _nominate_score(t: int) -> float:
	if _is_sombra():
		if _is_usurper(t):
			if _usurper_ready():
				return 50.0
			return 0.4 - _heat(t)
		if _is_ally(t):
			return 0.9 - _heat(t) * 1.5
		return 0.5 - _heat(t)  # parecer normal: elegir a alguien fiable
	var score := -_probs[t] * 2.0
	if _usurper_ready():
		score -= _probs[t] * 2.0  # que no sea el Usurpador
	return score


func _vote_score(yes: bool) -> float:
	var regent: int = _view["regent"]
	var nominee: int = _view["nominee"]
	var approve: float
	if _is_sombra():
		if _is_usurper(nominee) and _usurper_ready():
			approve = 10.0
		elif _is_ally(regent) or _is_ally(nominee) or regent == pid or nominee == pid:
			approve = 1.0
		else:
			# Gobierno honrado: se bloquea (la crisis suele sacar Sombra),
			# salvo que votar siempre en contra empiece a cantar.
			approve = -0.3 if int(_view["guardia_edicts"]) >= 2 else 0.05
	else:
		if regent == pid or nominee == pid:
			approve = 1.0
		else:
			var risk := Deduction.government_risk(_probs, regent, nominee)
			var n: int = _view["player_count"]
			var prior := float(D.ROLE_TABLE[n][1] + 1) / (n - 1)
			var limit := 1.0 - (1.0 - prior) * (1.0 - prior) + 0.05
			if int(_view["crisis"]) == D.MAX_CRISIS - 1:
				limit += 0.15
			if _usurper_ready() and _probs[nominee] > 0.45:
				limit = -1.0  # podría ser el Usurpador
			approve = (limit - risk) * 4.0
			if _my_role() == Role.USURPADOR:
				# El Usurpador también quiere gobiernos con sus aliados probables.
				approve += 0.5 * (_probs[regent] + _probs[nominee])
	return approve if yes else -approve


## Qué edictos pasar al Consejero (como Regente).
func _pass_score(passed: Array) -> float:
	var g := passed.count(Edict.GUARDIA)
	var s := passed.count(Edict.SOMBRA)
	if not _is_sombra():
		if _my_role() == Role.USURPADOR and int(_view["sombra_edicts"]) >= D.SOMBRA_TO_WIN - 1:
			return s * 2.0
		return g * 2.0 - s * 1.5 + _neutral_bonus() * passed.count(Edict.NEUTRAL)
	var council: int = _view["council"]
	if _is_ally(council):
		return s * 2.0 - g
	if _bold(pid, council):
		return s * 1.5 - g  # pasar dos de la Sombra y decir que robé tres
	return g * 0.5 + s * 0.3  # jugar seguro: pasar uno de cada


func _enact_score(edict: int) -> float:
	if not _is_sombra():
		match edict:
			Edict.GUARDIA:
				return 3.0
			Edict.SOMBRA:
				if _my_role() == Role.USURPADOR and int(_view["sombra_edicts"]) >= D.SOMBRA_TO_WIN - 1:
					return 5.0
				return -2.0
		return _neutral_bonus()
	var regent: int = _view["regent"]
	var bold := _is_ally(regent) or _bold(regent, pid)
	match edict:
		Edict.SOMBRA:
			return 3.0 if bold else -1.0
		Edict.GUARDIA:
			return 0.0
	return 0.5 if not bold else -0.5


## Edicto neutral: sube el descontento, que favorece a quien tiene menos.
func _neutral_bonus() -> float:
	var mine: int = _view["sombra_edicts"] if D.faction_of(_my_role()) == Faction.SOMBRA else _view["guardia_edicts"]
	var theirs: int = _view["guardia_edicts"] if D.faction_of(_my_role()) == Faction.SOMBRA else _view["sombra_edicts"]
	return 1.0 if mine < theirs else -0.5


func _power_value(power: int) -> float:
	var sombra := _is_sombra()
	match power:
		Power.DESTIERRO:
			if sombra:
				return 2.5
			return 3.0 if _probs.max() > 0.5 else 1.0
		Power.ESPIAR:
			return 0.3 if sombra else 2.2
		Power.SUCESION:
			return 1.5
		Power.AUGURIO:
			return 0.8 if sombra else 1.2
	return 0.6 if sombra else 1.0


func _power_target_score(t: int) -> float:
	if t < 0:
		return 0.0
	var power: int = _view["pending_power"]
	if _is_sombra():
		match power:
			Power.DESTIERRO:
				return -20.0 if _is_ally(t) else 1.0 - _heat(t)  # al guardia más fiable
			Power.SUCESION:
				return (1.0 - _heat(t)) if _is_ally(t) else -_heat(t)
		return 0.0
	match power:
		Power.DESTIERRO:
			return _probs[t]
		Power.ESPIAR:
			return 0.5 - absf(_probs[t] - 0.5)  # el más dudoso
		Power.SUCESION:
			return -_probs[t]
	return 0.0


# --- Declaraciones ---------------------------------------------------------------

## Qué declarar tras la legislatura (la verdad o una mentira útil).
func _claim() -> Variant:
	var govs: Array = _view["governments"]
	var round_index := govs.size() - 1
	var gov: Dictionary = govs[-1]
	var edict: int = gov["edict"]
	var as_regent: bool = gov["regent"] == pid
	var truth: Array = []
	for kn in _view["knowledge"]:
		if int(kn.get("round", -1)) == round_index and kn["kind"] == ("drawn" if as_regent else "received"):
			truth = kn["cards"].duplicate()
	truth.sort()
	if not _is_sombra() or edict != Edict.SOMBRA:
		return truth
	var partner: int = gov["nominee"] if as_regent else gov["regent"]
	if as_regent:
		# Promulgaron Sombra: «robé tres de la Sombra» cubre al Consejero
		# (aliado) o a mí mismo (si le pasé dos de la Sombra).
		if _is_ally(partner) or truth.count(Edict.SOMBRA) >= 2:
			return [Edict.SOMBRA, Edict.SOMBRA, Edict.SOMBRA]
		return truth
	# Como Consejero: «me pasó dos de la Sombra» (culpa al Regente, o cuadra
	# con lo que declarará mi aliado).
	if _is_ally(partner) or truth.count(Edict.SOMBRA) >= 1:
		return [Edict.SOMBRA, Edict.SOMBRA]
	return truth
