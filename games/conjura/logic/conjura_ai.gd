class_name ConjuraAI
extends RefCounted
## IA básica de La Conjura. Solo usa game.view_for(pid): no hace trampa.
##
## Guardia: sospecha de quien forma gobiernos que promulgan edictos de la
##   Sombra y confía en quien promulga de la Guardia; usa lo que ha espiado.
## Sombra / Usurpador: apoya a sus aliados conocidos, descarta edictos de la
##   Guardia y destierra a guardias.
## Nivel fácil: decisiones con mucho ruido. (La Fase 3 la hará más lista:
## declaraciones, mentiras y deducción.)

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Role := ConjuraDefs.Role
const Faction := ConjuraDefs.Faction
const Edict := ConjuraDefs.Edict
const Power := ConjuraDefs.Power
const G := preload("res://games/conjura/logic/conjura_game.gd")

var pid: int
var level: int
var _rng: BGCRng


func _init(p_pid: int, p_level: int = PlayerInfo.AILevel.NORMAL, seed: int = 0) -> void:
	pid = p_pid
	level = p_level
	_rng = BGCRng.new(seed * 31 + p_pid * 7919 + 17)


func choose_action(game: ConjuraGame) -> GameAction:
	var legal := game.get_legal_actions(pid)
	if legal.is_empty():
		return null
	var view := game.view_for(pid)
	var best: GameAction = legal[0]
	var best_score := -INF
	for action in legal:
		var score := _score(action, view) + _noise()
		if score > best_score:
			best_score = score
			best = action
	return best


func _noise() -> float:
	var amount := 3.0 if level == PlayerInfo.AILevel.EASY else (0.4 if level == PlayerInfo.AILevel.NORMAL else 0.1)
	return _rng.randf() * amount


func _my_role(view: Dictionary) -> int:
	return view["known_roles"][pid]


func _is_sombra(view: Dictionary) -> bool:
	return _my_role(view) != Role.GUARDIA


## Grado de confianza en que `other` es de MI facción (mayor = más fiable).
func trust(view: Dictionary, other: int) -> float:
	if other == pid:
		return 10.0
	var known: Dictionary = view["known_roles"]
	if known.has(other):
		var same := D.faction_of(known[other]) == D.faction_of(_my_role(view))
		return 10.0 if same else -10.0
	for k in view["knowledge"]:
		if k["kind"] == "faction" and k["target"] == other:
			return 10.0 if k["faction"] == D.faction_of(_my_role(view)) else -10.0
	if _is_sombra(view):
		return 0.0  # para la Sombra, quien no es aliado es de la Guardia
	var suspicion := 0.0
	for gov in view["governments"]:
		if not gov["approved"] or gov["crisis"]:
			continue
		var weight := 0.0
		match int(gov["edict"]):
			Edict.SOMBRA: weight = 1.0
			Edict.GUARDIA: weight = -0.8
		if gov["nominee"] == other:
			suspicion += weight * 1.2
		elif gov["regent"] == other:
			suspicion += weight
	return -suspicion


func _score(action: GameAction, view: Dictionary) -> float:
	var sombra := _is_sombra(view)
	match action.type:
		G.NOMINATE:
			var t := int(action.data["target"])
			# La Sombra evita nominar al Usurpador antes de tiempo... salvo
			# que ya baste para ganar.
			if sombra and view["known_roles"].get(t, -1) == Role.USURPADOR:
				return 20.0 if view["sombra_edicts"] >= D.USURPER_THRESHOLD else trust(view, t) - 3.0
			return trust(view, t)
		G.VOTE:
			var yes := bool(action.data["yes"])
			var gov_trust := minf(trust(view, view["regent"]), trust(view, view["nominee"]))
			if sombra and view["known_roles"].get(view["nominee"], -1) == Role.USURPADOR and view["sombra_edicts"] >= D.USURPER_THRESHOLD:
				gov_trust = 20.0
			var threshold := -0.5
			# Con la crisis a punto, vale la pena arriesgar un poco más.
			if view["crisis"] == D.MAX_CRISIS - 1:
				threshold -= 1.0
			return (gov_trust - threshold) if yes else (threshold - gov_trust)
		G.DISCARD, G.ENACT:
			var hand: Array = view["hand"]
			var card: int = hand[int(action.data["index"])]
			var value := _edict_value(card, view)
			# Descartar = quedarse con los otros: se descarta el peor.
			return -value if action.type == G.DISCARD else value
		G.CHOOSE_POWER:
			var power: int = view["power_options"][int(action.data["index"])]
			return _power_value(power, view)
		G.USE_POWER:
			var t := int(action.data["target"])
			if t < 0:
				return 0.0
			match int(view["pending_power"]):
				Power.DESTIERRO, Power.ESPIAR:
					return -trust(view, t)  # contra el más sospechoso
				Power.SUCESION:
					return trust(view, t)
	return 0.0


## Lo que vale un edicto para mi facción.
func _edict_value(card: int, view: Dictionary) -> float:
	var sombra := _is_sombra(view)
	match card:
		Edict.GUARDIA:
			return -2.0 if sombra else 3.0
		Edict.SOMBRA:
			return 3.0 if sombra else -2.0
	# Neutral: sube el descontento, que favorece a quien tiene menos edictos.
	var mine: int = view["sombra_edicts"] if sombra else view["guardia_edicts"]
	var theirs: int = view["guardia_edicts"] if sombra else view["sombra_edicts"]
	return 1.0 if mine < theirs else -0.5


func _power_value(power: int, view: Dictionary) -> float:
	match power:
		Power.DESTIERRO:
			return 3.0
		Power.ESPIAR:
			return 0.5 if _is_sombra(view) else 2.5
		Power.SUCESION:
			return 1.5
		Power.AUGURIO:
			return 1.0
	return 0.8
