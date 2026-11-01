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
		{
			"id": "conjura",
			"name": "La Conjura",
			"description": "Roles ocultos y engaños en la corte: la Guardia Real contra la Hermandad de la Sombra y su Usurpador.",
			"scene": "res://games/conjura/conjura.tscn",
			"rules": "res://games/conjura/rules.txt",
			"min_players": 5,
			"max_players": 10,
			# Colores del emblema de la tarjeta del menú.
			"colors": [Color("4f8fd6"), Color("b8404f"), Color("c9a96e"), Color("3a2d4a"), Color("e3b34c"), Color("7a2f3b")],
		},
		{
			"id": "bajamar",
			"name": "Bajamar",
			"description": "Pesca a tu suerte: sigue robando cartas para llenar la red o vuelve a puerto antes de que llegue la tormenta.",
			"scene": "res://games/bajamar/bajamar.tscn",
			"rules": "res://games/bajamar/rules.txt",
			"min_players": 2,
			"max_players": 6,
			# Colores del emblema de la tarjeta del menú (las especies).
			"colors": [Color("9fb8c8"), Color("3f8f8a"), Color("c4566b"), Color("d9c48c"), Color("3f5fa8"), Color("1f5f86")],
		},
	]


static func find(game_id: String) -> Dictionary:
	for game in all_games():
		if game["id"] == game_id:
			return game
	return {}
