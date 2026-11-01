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
			"id": "conjura",
			"name": "La Conjura",
			"description": "Roles ocultos y engaños en la corte: la Guardia Real contra la Hermandad de la Sombra y su Usurpador.",
			"scene": "res://games/conjura/conjura.tscn",
			"rules": "res://games/conjura/rules.txt",
			"min_players": 5,
			"max_players": 10,
			# Red local: llegará en la Fase 4 (información oculta por asiento).
			"network": false,
		},
	]


static func find(game_id: String) -> Dictionary:
	for game in all_games():
		if game["id"] == game_id:
			return game
	return {}
