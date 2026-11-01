class_name ArchCardTracker
extends RefCounted
## Cuenta cartas como lo haría un jugador atento: solo con información
## pública (producción, construcciones, comercio, descartes, cartas jugadas)
## más lo que el propio jugador sabe de sus robos.
##
## Para cada rival estima cuántas cartas de cada recurso tiene. Los robos
## entre otros jugadores no revelan el recurso: ahí la estimación se reparte
## de forma proporcional.

const G := preload("res://games/archipelago/logic/archipelago_game.gd")

## Jugador que observa (conoce los robos en los que participa).
var observer: int
## Por jugador: cartas estimadas de cada recurso (floats).
var known: Array = []
var _game: ArchipelagoGame


func observe(game: ArchipelagoGame, p_observer: int) -> void:
	_game = game
	observer = p_observer
	known.clear()
	for p in game.players.size():
		known.append([0.0, 0.0, 0.0, 0.0, 0.0])
	game.event.connect(_on_event)
	game.action_applied.connect(_on_action)


## Estimación de la mano de un jugador, ajustada a su número de cartas (que
## es público).
func estimate(p: int) -> Array[float]:
	var result: Array[float] = []
	var total := 0.0
	for r in 5:
		total += known[p][r]
	var size := float(_game.hand_size(p))
	var scale := 1.0 if total <= size or total == 0.0 else size / total
	for r in 5:
		result.append(known[p][r] * scale)
	return result


## Cartas que se estima que tienen los rivales de un recurso.
func others_have(resource: int) -> float:
	var total := 0.0
	for p in known.size():
		if p != observer:
			total += estimate(p)[resource]
	return total


func _add(p: int, amounts: Array, sign: float) -> void:
	for r in 5:
		known[p][r] = maxf(0.0, known[p][r] + sign * amounts[r])


## Quita una carta de recurso desconocido (robo que no vemos).
func _remove_unknown(p: int) -> void:
	var est := estimate(p)
	var total := 0.0
	for r in 5:
		total += est[r]
	if total <= 0.0:
		return
	for r in 5:
		known[p][r] = maxf(0.0, est[r] - est[r] / total)


func _on_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"production":
			for p in data["gains"].size():
				_add(p, data["gains"][p], 1.0)
		&"setup_resources":
			_add(data["player"], data["gains"], 1.0)


func _on_action(action: GameAction) -> void:
	var p := action.player_id
	var data := action.data
	match action.type:
		G.BUILD_ROAD, G.BUILD_SETTLEMENT:
			if data.get("paid", false):
				_add(p, G.COSTS[action.type], -1.0)
		G.BUILD_CITY, G.BUY_DEV:
			_add(p, G.COSTS[action.type], -1.0)
		G.TRADE_BANK:
			known[p][data["give"]] = maxf(0.0, known[p][data["give"]] - data["ratio"])
			known[p][data["receive"]] += 1.0
		G.DISCARD:
			_add(p, data["cards"], -1.0)
		G.ACCEPT_TRADE:
			var offer: Dictionary = data["offer"]
			_add(offer["from"], offer["give"], -1.0)
			_add(offer["from"], offer["receive"], 1.0)
			_add(offer["to"], offer["receive"], -1.0)
			_add(offer["to"], offer["give"], 1.0)
		G.MOVE_BANDIT:
			var victim := int(data.get("victim", -1))
			if victim < 0:
				return
			var stolen: int = data["stolen"]
			if p == observer or victim == observer:
				# Quien participa en el robo sabe qué carta fue.
				known[victim][stolen] = maxf(0.0, known[victim][stolen] - 1.0)
				known[p][stolen] += 1.0
			else:
				_remove_unknown(victim)
		G.PLAY_DEV:
			match int(data["card"]):
				ArchDefs.DevCard.HARVEST:
					for r in data["resources"]:
						known[p][r] += 1.0
				ArchDefs.DevCard.MONOPOLY:
					var r: int = data["resource"]
					var before: float = known[p][r]
					for other in known.size():
						known[other][r] = 0.0
					known[p][r] = before + data["taken"]
