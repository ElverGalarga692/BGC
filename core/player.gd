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
	Color("2bb5b8"),  # turquesa
	Color("e86fb0"),  # rosa
	Color("a8743c"),  # marrón
	Color("9aa3ad"),  # gris
]

## Niveles de IA (0 = jugador humano).
enum AILevel { HUMAN, EASY, NORMAL, HARD }

const AI_LEVEL_NAMES := {
	AILevel.HUMAN: "Humano",
	AILevel.EASY: "IA fácil",
	AILevel.NORMAL: "IA normal",
	AILevel.HARD: "IA difícil",
}

var id: int
var display_name: String
var color: Color
var ai_level: int = AILevel.HUMAN
var is_ai: bool:
	get:
		return ai_level != AILevel.HUMAN


func _init(p_id: int = 0, p_name: String = "", p_color: Color = Color.WHITE, p_ai_level: int = AILevel.HUMAN) -> void:
	id = p_id
	display_name = p_name if p_name != "" else "Jugador %d" % (p_id + 1)
	color = p_color
	ai_level = p_ai_level


static func default_color(index: int) -> Color:
	return DEFAULT_COLORS[index % DEFAULT_COLORS.size()]


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "color": color.to_html(false), "ai": ai_level}


static func from_dict(d: Dictionary) -> PlayerInfo:
	return PlayerInfo.new(int(d.get("id", 0)), String(d.get("name", "")), Color(String(d.get("color", "ffffff"))), int(d.get("ai", AILevel.HUMAN)))
