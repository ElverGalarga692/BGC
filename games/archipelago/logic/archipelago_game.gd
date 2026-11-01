class_name ArchipelagoGame
extends GameBase
## Lógica de una partida de Archipiélago.
##
## Fase 1: solo crea el tablero. Las reglas (colocación inicial, dados,
## construcción, comercio...) llegarán en la fase 2 como acciones.

var board: ArchBoard


func _on_setup() -> void:
	board = ArchBoardGenerator.generate(rng)
