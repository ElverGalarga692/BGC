class_name GameAction
extends RefCounted
## Una jugada. Toda modificación del estado de un juego se expresa como una
## acción: la interfaz y la IA crean acciones y el juego las valida y aplica.
## Son serializables, lo que permite guardar partidas como historial.

var type: StringName
var player_id: int
var data: Dictionary


func _init(p_type: StringName = &"", p_player_id: int = -1, p_data: Dictionary = {}) -> void:
	type = p_type
	player_id = p_player_id
	data = p_data


func to_dict() -> Dictionary:
	return {"type": String(type), "player": player_id, "data": data.duplicate(true)}


static func from_dict(d: Dictionary) -> GameAction:
	return GameAction.new(StringName(d.get("type", "")), int(d.get("player", -1)), d.get("data", {}).duplicate(true))


func _to_string() -> String:
	return "GameAction(%s, jugador=%d, %s)" % [type, player_id, data]
