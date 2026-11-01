class_name PlayerInfo
extends RefCounted
## Datos de un jugador comunes a todos los juegos.

const DEFAULT_COLORS: Array[Color] = [
	Color("d64545"),  # rojo
	Color("3f72d6"),  # azul
	Color("e8a33c"),  # naranja
	Color("f2f2f2"),  # blanco
	Color("4caf50"),  # verde
	Color("8e5bd6"),  # morado
]

var id: int
var display_name: String
var color: Color
var is_ai: bool


func _init(p_id: int = 0, p_name: String = "", p_color: Color = Color.WHITE, p_is_ai: bool = false) -> void:
	id = p_id
	display_name = p_name if p_name != "" else "Jugador %d" % (p_id + 1)
	color = p_color
	is_ai = p_is_ai


static func default_color(index: int) -> Color:
	return DEFAULT_COLORS[index % DEFAULT_COLORS.size()]


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "color": color.to_html(false), "ai": is_ai}


static func from_dict(d: Dictionary) -> PlayerInfo:
	return PlayerInfo.new(int(d.get("id", 0)), String(d.get("name", "")), Color(String(d.get("color", "ffffff"))), bool(d.get("ai", false)))
