class_name HexCoords
extends RefCounted
## Utilidades para hexágonos "pointy-top" (con un vértice arriba) en
## coordenadas axiales (q, r), guardadas como Vector2i(q, r).
## Referencia: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772

## Las 6 direcciones vecinas, en sentido antihorario empezando por el este
## (en pantalla, con el eje Y hacia abajo).
const DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbor(h: Vector2i, direction: int) -> Vector2i:
	return h + DIRECTIONS[posmod(direction, 6)]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(h + d)
	return result


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Hexágonos a distancia exacta `radius` del centro.
static func ring(radius: int, center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if radius <= 0:
		result.append(center)
		return result
	var h: Vector2i = center + DIRECTIONS[4] * radius
	for i in 6:
		for j in radius:
			result.append(h)
			h = neighbor(h, i)
	return result


## Todos los hexágonos a distancia <= `radius`, del centro hacia fuera.
static func spiral(radius: int, center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for k in radius + 1:
		result.append_array(ring(k, center))
	return result


## Centro del hexágono en píxeles (o en unidades si size = 1).
static func to_pixel(h: Vector2i, size: float = 1.0) -> Vector2:
	return Vector2(size * SQRT3 * (h.x + h.y / 2.0), size * 1.5 * h.y)


## Hexágono que contiene el punto `p`.
static func from_pixel(p: Vector2, size: float = 1.0) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


## Redondea coordenadas axiales fraccionarias al hexágono más cercano.
static func cube_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


## Vértice `i` (0..5) de un hexágono. El 0 está arriba a la derecha y siguen
## en sentido horario en pantalla.
static func corner(center: Vector2, size: float, i: int) -> Vector2:
	var angle := deg_to_rad(60.0 * i - 30.0)
	return center + Vector2(cos(angle), sin(angle)) * size


static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 6:
		result.append(corner(center, size, i))
	return result
