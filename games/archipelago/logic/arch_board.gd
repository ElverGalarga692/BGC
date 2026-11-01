class_name ArchBoard
extends RefCounted
## Tablero de Archipiélago: la topología (HexGrid) más lo que hay encima
## (terreno y número de cada casilla, y los puertos de la costa).

var grid: HexGrid
## Por casilla: valor de ArchDefs.Terrain.
var tile_terrain: Array[int] = []
## Por casilla: ficha numérica (0 = sin ficha, p.ej. el desierto).
var tile_number: Array[int] = []
## Puertos: [{"edge": int, "type": int}], type es un ResourceType o PORT_GENERIC.
var ports: Array[Dictionary] = []
## Casilla donde está el bandido (empieza en el desierto).
var bandit_tile: int = -1


func _init(p_grid: HexGrid = null) -> void:
	grid = p_grid if p_grid != null else HexGrid.hexagonal(ArchDefs.BOARD_RADIUS)
	tile_terrain.resize(grid.tile_count())
	tile_number.resize(grid.tile_count())


func tile_resource(t: int) -> int:
	return ArchDefs.TERRAIN_RESOURCE[tile_terrain[t]]


## Casillas que producen con una tirada de dados (ignorando el bandido).
func tiles_with_number(n: int) -> Array[int]:
	var result: Array[int] = []
	for t in grid.tile_count():
		if tile_number[t] == n:
			result.append(t)
	return result


## Puerto al que da acceso un vértice, o null.
func vertex_port(v: int) -> Variant:
	for port in ports:
		if v in grid.edge_vertices[port["edge"]]:
			return port
	return null


## Puerto situado en una arista, o null.
func edge_port(e: int) -> Variant:
	for port in ports:
		if port["edge"] == e:
			return port
	return null


func to_dict() -> Dictionary:
	return {
		"terrain": tile_terrain.duplicate(),
		"numbers": tile_number.duplicate(),
		"ports": ports.duplicate(true),
		"bandit": bandit_tile,
	}
