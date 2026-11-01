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
			"rules": "res://games/archipelago/rules.txt",
			"min_players": 2,
			"max_players": 4,
		},
		{
			"id": "pests",
			"name": "Pests!",
			"description": "Exterminadores rivales en una casa infestada: sella tu nido, elimina tus plagas y atrapa a tu reina antes que nadie.",
			"scene": "res://games/pests/pests.tscn",
			"rules": "res://games/pests/rules.txt",
			"min_players": 2,
			"max_players": 6,
			"options": [
				{"key": "quick_species", "label": "Reglas rápidas: exterminadores y cartas al azar", "default": false},
				{"key": "auto_house", "label": "Construir la casa al azar", "default": true},
				{"key": "teams", "label": "Por equipos (con 4 o 6 jugadores)", "default": false},
			],
		},
	]


static func find(game_id: String) -> Dictionary:
	for game in all_games():
		if game["id"] == game_id:
			return game
	return {}
