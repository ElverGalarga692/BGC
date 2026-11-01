class_name GameRegistry
extends RefCounted
## Lista de los juegos de la colección. Para añadir un juego nuevo, añade
## aquí su entrada y crea su carpeta en res://games/<id>/.

static func all_games() -> Array[Dictionary]:
	return [
		{
			"id": "archipelago",
			"name": "Archipiélago",
			"description": "Coloniza un archipiélago de islas hexagonales, recoge recursos, comercia y construye.",
			"scene": "res://games/archipelago/archipelago.tscn",
			"min_players": 2,
			"max_players": 4,
		},
	]


static func find(game_id: String) -> Dictionary:
	for game in all_games():
		if game["id"] == game_id:
			return game
	return {}
