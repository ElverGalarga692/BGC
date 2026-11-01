class_name HexGrid
extends RefCounted
## Topología de un tablero de hexágonos: casillas, vértices (esquinas) y
## aristas (lados), y quién toca a quién. Son datos puros, sin nodos.
##
## Las posiciones están en "unidades de hexágono" (radio 1); la vista las
## multiplica por el tamaño en píxeles.
##
## Todo se identifica con índices enteros:
##   casilla (tile) 0..tile_count()-1
##   vértice (vertex) 0..vertex_count()-1
##   arista (edge) 0..edge_count()-1

## Coordenada axial de cada casilla.
var tile_coords: Array[Vector2i] = []
## Vector2i -> índice de casilla.
var tile_index: Dictionary = {}
## Por casilla: sus 6 vértices en orden (ver HexCoords.corner).
var tile_vertices: Array = []
## Por casilla: sus 6 aristas; la arista i une los vértices i e i+1.
var tile_edges: Array = []

var vertex_positions: Array[Vector2] = []
## Por vértice: casillas que lo tocan (1 a 3).
var vertex_tiles: Array = []
## Por vértice: aristas que salen de él (2 o 3).
var vertex_edges: Array = []
## Por vértice: vértices adyacentes (2 o 3).
var vertex_neighbors: Array = []

## Por arista: sus dos vértices [a, b] con a < b.
var edge_vertices: Array = []
## Por arista: casillas que la tocan (1 en la costa, 2 en el interior).
var edge_tiles: Array = []


## Tablero hexagonal de `radius` anillos alrededor del centro
## (radio 2 = 19 casillas).
static func hexagonal(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	grid.build(HexCoords.spiral(radius))
	return grid


## Construye la topología a partir de una lista de coordenadas (sirve para
## tableros de cualquier forma).
func build(coords: Array[Vector2i]) -> void:
	var vertex_lookup := {}  # posición redondeada -> vértice
	var edge_lookup := {}    # Vector2i(a, b) -> arista
	for coord in coords:
		assert(not tile_index.has(coord), "Casilla duplicada: %s" % coord)
		var t := tile_coords.size()
		tile_coords.append(coord)
		tile_index[coord] = t
		var center := HexCoords.to_pixel(coord)

		var verts: Array[int] = []
		for i in 6:
			var p := HexCoords.corner(center, 1.0, i)
			var key := Vector2i(roundi(p.x * 1000.0), roundi(p.y * 1000.0))
			var v: int
			if vertex_lookup.has(key):
				v = vertex_lookup[key]
			else:
				v = vertex_positions.size()
				vertex_lookup[key] = v
				vertex_positions.append(p)
				vertex_tiles.append([])
				vertex_edges.append([])
				vertex_neighbors.append([])
			vertex_tiles[v].append(t)
			verts.append(v)
		tile_vertices.append(verts)

		var edges: Array[int] = []
		for i in 6:
			var a := verts[i]
			var b := verts[(i + 1) % 6]
			var key := Vector2i(mini(a, b), maxi(a, b))
			var e: int
			if edge_lookup.has(key):
				e = edge_lookup[key]
			else:
				e = edge_vertices.size()
				edge_lookup[key] = e
				edge_vertices.append([key.x, key.y])
				edge_tiles.append([])
				vertex_edges[a].append(e)
				vertex_edges[b].append(e)
				vertex_neighbors[a].append(b)
				vertex_neighbors[b].append(a)
			edge_tiles[e].append(t)
			edges.append(e)
		tile_edges.append(edges)


func tile_count() -> int:
	return tile_coords.size()


func vertex_count() -> int:
	return vertex_positions.size()


func edge_count() -> int:
	return edge_vertices.size()


func tile_center(t: int) -> Vector2:
	return HexCoords.to_pixel(tile_coords[t])


## Casillas vecinas de una casilla (las que existen en el tablero).
func tile_neighbors(t: int) -> Array[int]:
	var result: Array[int] = []
	for c in HexCoords.neighbors(tile_coords[t]):
		if tile_index.has(c):
			result.append(tile_index[c])
	return result


func edge_midpoint(e: int) -> Vector2:
	var ev: Array = edge_vertices[e]
	return (vertex_positions[ev[0]] + vertex_positions[ev[1]]) * 0.5


## Arista que une dos vértices, o -1 si no son adyacentes.
func edge_between(a: int, b: int) -> int:
	for e in vertex_edges[a]:
		if b in edge_vertices[e]:
			return e
	return -1


func is_coastal_edge(e: int) -> bool:
	return edge_tiles[e].size() == 1


## Aristas de la costa ordenadas por ángulo alrededor del centro del tablero.
func coastal_edges() -> Array[int]:
	var result: Array[int] = []
	for e in edge_count():
		if is_coastal_edge(e):
			result.append(e)
	var c := _board_center()
	result.sort_custom(func(a: int, b: int) -> bool:
		return (edge_midpoint(a) - c).angle() < (edge_midpoint(b) - c).angle())
	return result


## Casilla que contiene el punto (en unidades), o -1.
func tile_at(p: Vector2) -> int:
	return tile_index.get(HexCoords.from_pixel(p), -1)


## Vértice más cercano al punto si está a menos de `max_distance`, o -1.
func vertex_near(p: Vector2, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance
	for v in vertex_count():
		var d := vertex_positions[v].distance_to(p)
		if d < best_d:
			best = v
			best_d = d
	return best


## Arista cuyo punto medio está más cerca del punto, si está a menos de
## `max_distance`, o -1.
func edge_near(p: Vector2, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance
	for e in edge_count():
		var d := edge_midpoint(e).distance_to(p)
		if d < best_d:
			best = e
			best_d = d
	return best


func _board_center() -> Vector2:
	var sum := Vector2.ZERO
	for t in tile_count():
		sum += tile_center(t)
	return sum / maxf(1.0, tile_count())
