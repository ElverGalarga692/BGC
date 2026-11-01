"""Genera los modelos 3D de Archipiélago con Blender y los exporta a glTF.

Uso (cualquiera de las dos formas):
  - Desde Blender: abre la pestaña Scripting, carga este archivo y pulsa
    "Run Script".
  - Sin abrir Blender:  pip install bpy  &&  python art/blender/build_models.py

Resultado:
  - games/archipelago/assets/models/*.glb   (lo que carga Godot)
  - art/blender/archipelago_models.blend     (para retocar a mano en Blender)

Convenciones (las usa games/archipelago/view/board_view_3d.gd):
  - Unidades = "unidades de hexágono": radio de ficha 0.965, altura 0.22.
    El centro de cada modelo está en el origen y su base en z = 0.
  - Las fichas de terreno dejan libre el círculo central (radio ~0.36) para
    la ficha numérica.
  - Materiales especiales que Godot recolorea:
      "player"       color del jugador
      "player_dark"  color del jugador oscurecido (tejados)
      "port_flag"    color del recurso del puerto
"""

import math
import os
import random

import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "games", "archipelago", "assets", "models")
BLEND_PATH = os.path.join(HERE, "archipelago_models.blend")

TILE_RADIUS = 0.965
TILE_HEIGHT = 0.22
CLEAR_RADIUS = 0.36  # zona central libre para la ficha numérica


# --- Utilidades ----------------------------------------------------------------

def hex_color(value, alpha=1.0):
    value = value.lstrip("#")
    srgb = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # Blender trabaja en espacio lineal.
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, alpha)


_materials = {}


def material(name, color, roughness=0.8, metallic=0.0):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hex_color(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = hex_color(color)
    _materials[name] = mat
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def flat(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def cone(r1, r2, depth, loc, mat, verts=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=(loc[0], loc[1], loc[2] + depth / 2), rotation=rot)
    return flat(assign(bpy.context.active_object, mat))


def cylinder(r, depth, loc, mat, verts=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                        location=(loc[0], loc[1], loc[2] + depth / 2), rotation=rot)
    return flat(assign(bpy.context.active_object, mat))


def box(size, loc, mat, rot=(0, 0, 0)):
    """Caja con la base en loc.z."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1], loc[2] + size[2] / 2), rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return flat(assign(obj, mat))


def blob(radius, squash, loc, mat, subdiv=1, jitter=0.0, rng=None):
    """Esfera low-poly achatada y algo irregular (rocas, colinas, dunas)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    obj = bpy.context.active_object
    if jitter and rng:
        for v in obj.data.vertices:
            v.co.x += rng.uniform(-jitter, jitter)
            v.co.y += rng.uniform(-jitter, jitter)
            v.co.z += rng.uniform(-jitter, jitter)
    obj.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return flat(assign(obj, mat))


def prism_roof(width, depth, height, loc, mat):
    """Tejado a dos aguas: prisma triangular con la cumbrera a lo largo de Y."""
    mesh = bpy.data.meshes.new("roof")
    w, d, h = width / 2, depth / 2, height
    verts = [(-w, -d, 0), (w, -d, 0), (0, -d, h), (-w, d, 0), (w, d, 0), (0, d, h)]
    faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("roof", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    return flat(assign(obj, mat))


def hex_base(top_mat, side_mat):
    """Ficha hexagonal "pointy-top" con el borde superior biselado."""
    bm = bmesh.new()
    top, bottom = [], []
    for i in range(6):
        a = math.radians(60 * i - 30)
        x, y = math.cos(a) * TILE_RADIUS, math.sin(a) * TILE_RADIUS
        bottom.append(bm.verts.new((x, y, 0)))
        top.append(bm.verts.new((x, y, TILE_HEIGHT)))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    top_edges = [e for e in bm.edges if all(v.co.z > TILE_HEIGHT - 1e-4 for v in e.verts)]
    bmesh.ops.bevel(bm, geom=top_edges, offset=0.035, segments=2, affect="EDGES", profile=0.5)
    mesh = bpy.data.meshes.new("hex")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("hex", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(top_mat)
    obj.data.materials.append(side_mat)
    for poly in obj.data.polygons:
        poly.material_index = 0 if poly.normal.z > 0.95 else 1
    return flat(obj)


def ring_spots(rng, count, r_min=0.48, r_max=0.8, offset=0.0):
    """Posiciones repartidas en un anillo alrededor de la zona central."""
    spots = []
    for i in range(count):
        a = offset + 2 * math.pi * i / count + rng.uniform(-0.25, 0.25)
        r = rng.uniform(r_min, r_max)
        spots.append((math.cos(a) * r, math.sin(a) * r))
    return spots


def finish(name, parts):
    """Une las piezas en un objeto, lo exporta a .glb y lo deja en su colección."""
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    # Lo apartamos para que no se mezcle con el siguiente modelo.
    obj.location.x += 3 * len(bpy.data.collections)
    return obj


# --- Materiales -------------------------------------------------------------------

def mats():
    return {
        "earth": material("earth", "6b4a2f"),
        "forest": material("forest_ground", "3f7d3a"),
        "pine": material("pine", "1f5e2b"),
        "pine_light": material("pine_light", "2f7a3b"),
        "trunk": material("trunk", "5b3a1e"),
        "hills": material("hills_ground", "b8683f"),
        "clay": material("clay", "a8502f"),
        "brick": material("brick", "8e3b22"),
        "pasture": material("pasture_ground", "7aab4c"),
        "grass": material("grass", "6fa64a"),
        "wool": material("wool", "f4f1e8"),
        "black": material("black", "262626"),
        "fields": material("fields_ground", "c9a23e"),
        "wheat": material("wheat", "dbb535"),
        "hay": material("hay", "c99a2e"),
        "mountains": material("mountains_ground", "7d838c"),
        "rock": material("rock", "6f747d"),
        "rock_dark": material("rock_dark", "555a62"),
        "snow": material("snow", "f2f4f7"),
        "desert": material("desert_ground", "cdb57e"),
        "sand": material("sand", "c2a96c"),
        "cactus": material("cactus", "4f8a3c"),
        "wood": material("wood", "9c7a4e"),
        "wood_dark": material("wood_dark", "6e5232"),
        "token": material("token", "f3e6c4"),
        "player": material("player", "d64545"),
        "player_dark": material("player_dark", "8f2b2b"),
        "stone": material("stone", "8a8178"),
        "window": material("window", "2b2b33"),
        "bandit": material("bandit", "2a2a2a"),
        "port_flag": material("port_flag", "ffffff"),
    }


# --- Fichas de terreno ------------------------------------------------------------

def pine(M, rng, x, y, scale=1.0):
    s = scale * rng.uniform(0.85, 1.15)
    parts = [cylinder(0.025 * s, 0.07 * s, (x, y, TILE_HEIGHT), M["trunk"], verts=6)]
    z = TILE_HEIGHT + 0.06 * s
    for i, (r, h) in enumerate([(0.13, 0.16), (0.1, 0.14), (0.065, 0.12)]):
        mat = M["pine"] if (i + int(x * 10)) % 2 == 0 else M["pine_light"]
        parts.append(cone(r * s, 0.0, h * s, (x, y, z), mat, verts=7, rot=(0, 0, rng.uniform(0, 3))))
        z += h * s * 0.55
    return parts


def tile_forest(M):
    rng = random.Random(1)
    parts = [hex_base(M["forest"], M["earth"])]
    for x, y in ring_spots(rng, 7):
        parts += pine(M, rng, x, y)
    for x, y in ring_spots(rng, 4, 0.55, 0.7, offset=0.4):
        parts += pine(M, rng, x, y, 0.7)
    return finish("tile_forest", parts)


def tile_hills(M):
    rng = random.Random(2)
    parts = [hex_base(M["hills"], M["earth"])]
    for x, y in ring_spots(rng, 5, 0.55, 0.75):
        parts.append(blob(rng.uniform(0.2, 0.26), 0.5, (x, y, TILE_HEIGHT), M["clay"], 1, 0.02, rng))
    # Montón de ladrillos.
    for i in range(3):
        for j in range(2 - (i // 2)):
            parts.append(box((0.14, 0.07, 0.055), (0.48 + j * 0.15 - i * 0.03, -0.12, TILE_HEIGHT + i * 0.055), M["brick"]))
    return finish("tile_hills", parts)


def sheep(M, rng, x, y):
    a = rng.uniform(0, math.tau)
    dx, dy = math.cos(a), math.sin(a)
    parts = [blob(0.11, 0.75, (x, y, TILE_HEIGHT + 0.12), M["wool"], 1)]
    parts.append(box((0.07, 0.065, 0.07), (x + dx * 0.12, y + dy * 0.12, TILE_HEIGHT + 0.1), M["black"], rot=(0, 0, a)))
    for lx, ly in ((0.05, 0.045), (-0.05, 0.045), (0.05, -0.045), (-0.05, -0.045)):
        parts.append(cylinder(0.016, 0.07, (x + lx, y + ly, TILE_HEIGHT), M["black"], verts=5))
    return parts


def tile_pasture(M):
    rng = random.Random(3)
    parts = [hex_base(M["pasture"], M["earth"])]
    for x, y in ring_spots(rng, 4, 0.5, 0.72):
        parts += sheep(M, rng, x, y)
    for x, y in ring_spots(rng, 12, 0.45, 0.85, offset=0.3):
        parts.append(cone(0.05, 0.0, 0.1, (x, y, TILE_HEIGHT), M["grass"], verts=4))
    # Valla de madera.
    for i in range(4):
        parts.append(cylinder(0.012, 0.09, (-0.62 + i * 0.09, 0.38, TILE_HEIGHT), M["wood"], verts=5))
    parts.append(box((0.3, 0.015, 0.015), (-0.485, 0.38, TILE_HEIGHT + 0.06), M["wood"]))
    return finish("tile_pasture", parts)


def tile_fields(M):
    rng = random.Random(4)
    parts = [hex_base(M["fields"], M["earth"])]
    # Surcos de trigo en el anillo exterior.
    for row in range(-4, 5):
        y = row * 0.17
        for k in range(-5, 6):
            x = k * 0.15
            r = math.hypot(x, y)
            if CLEAR_RADIUS + 0.06 < r < 0.8:
                parts.append(box((0.11, 0.09, 0.1 + rng.uniform(0, 0.05)), (x, y, TILE_HEIGHT), M["wheat"]))
    # Almiares.
    for x, y in ((0.0, 0.62), (0.0, -0.62)):
        parts.append(cylinder(0.1, 0.12, (x, y, TILE_HEIGHT), M["hay"], verts=8))
        parts.append(cone(0.11, 0.0, 0.11, (x, y, TILE_HEIGHT + 0.12), M["hay"], verts=8))
    return finish("tile_fields", parts)


def tile_mountains(M):
    rng = random.Random(5)
    parts = [hex_base(M["mountains"], M["earth"])]
    for i, (x, y) in enumerate(ring_spots(rng, 4, 0.5, 0.65, offset=0.5)):
        h = rng.uniform(0.38, 0.55)
        r = rng.uniform(0.2, 0.26)
        peak = cone(r, 0.0, h, (x, y, TILE_HEIGHT), M["rock"] if i % 2 else M["rock_dark"], verts=6, rot=(0, 0, rng.uniform(0, 3)))
        for v in peak.data.vertices:
            if v.co.z < h * 0.4:
                v.co.x += rng.uniform(-0.03, 0.03)
                v.co.y += rng.uniform(-0.03, 0.03)
        parts.append(peak)
        parts.append(cone(r * 0.38, 0.0, h * 0.38, (x, y, TILE_HEIGHT + h * 0.62), M["snow"], verts=6))
    for x, y in ring_spots(rng, 4, 0.7, 0.82, offset=1.2):
        parts.append(blob(0.06, 0.6, (x, y, TILE_HEIGHT + 0.01), M["rock_dark"], 1, 0.01, rng))
    return finish("tile_mountains", parts)


def cactus(M, x, y, h):
    parts = [cylinder(0.055, h, (x, y, TILE_HEIGHT), M["cactus"], verts=8)]
    parts.append(cylinder(0.034, 0.14, (x + 0.085, y, TILE_HEIGHT + h * 0.45), M["cactus"], verts=6))
    parts.append(cylinder(0.034, 0.11, (x - 0.085, y, TILE_HEIGHT + h * 0.6), M["cactus"], verts=6))
    parts.append(box((0.09, 0.034, 0.034), (x + 0.045, y, TILE_HEIGHT + h * 0.45), M["cactus"]))
    parts.append(box((0.09, 0.034, 0.034), (x - 0.045, y, TILE_HEIGHT + h * 0.6), M["cactus"]))
    return parts


def tile_desert(M):
    rng = random.Random(6)
    parts = [hex_base(M["desert"], M["earth"])]
    for x, y in ring_spots(rng, 4, 0.55, 0.72):
        parts.append(blob(rng.uniform(0.2, 0.28), 0.3, (x, y, TILE_HEIGHT - 0.02), M["sand"], 2, 0.0))
    parts += cactus(M, 0.5, -0.45, 0.4)
    parts += cactus(M, -0.45, 0.5, 0.32)
    for x, y in ring_spots(rng, 3, 0.65, 0.8, offset=0.9):
        parts.append(blob(0.05, 0.7, (x, y, TILE_HEIGHT), M["rock"], 1, 0.01, rng))
    return finish("tile_desert", parts)


# --- Piezas -----------------------------------------------------------------------

def token(M):
    parts = [cylinder(0.3, 0.045, (0, 0, 0), M["token"], verts=28)]
    bpy.ops.object.modifier_add(type="BEVEL")
    parts[0].modifiers["Bevel"].width = 0.012
    parts[0].modifiers["Bevel"].segments = 2
    return finish("token", parts)


def settlement(M):
    parts = [box((0.2, 0.2, 0.15), (0, 0, 0), M["player"])]
    parts.append(prism_roof(0.25, 0.23, 0.13, (0, 0, 0.15), M["player_dark"]))
    parts.append(box((0.04, 0.04, 0.09), (0.06, 0.05, 0.19), M["stone"]))      # chimenea
    parts.append(box((0.055, 0.01, 0.08), (0, -0.1, 0), M["window"]))         # puerta
    parts.append(box((0.01, 0.05, 0.045), (0.1, 0.0, 0.07), M["window"]))     # ventana
    return finish("settlement", parts)


def city(M):
    parts = [box((0.34, 0.22, 0.17), (0.05, 0, 0), M["player"])]
    parts.append(prism_roof(0.24, 0.25, 0.11, (0.12, 0, 0.17), M["player_dark"]))
    # Torre con almenas.
    parts.append(box((0.15, 0.15, 0.36), (-0.1, 0, 0), M["player"]))
    for dx, dy in ((-0.05, -0.05), (0.05, -0.05), (-0.05, 0.05), (0.05, 0.05)):
        parts.append(box((0.04, 0.04, 0.05), (-0.1 + dx, dy, 0.36), M["player_dark"]))
    parts.append(box((0.06, 0.01, 0.09), (0.12, -0.11, 0), M["window"]))
    for wx in (-0.03, 0.2):
        parts.append(box((0.04, 0.01, 0.04), (wx, -0.11, 0.1), M["window"]))
    parts.append(box((0.04, 0.01, 0.06), (-0.1, -0.076, 0.24), M["window"]))
    return finish("city", parts)


def road(M):
    parts = [box((0.64, 0.15, 0.1), (0, 0, 0), M["player"])]
    bpy.ops.object.modifier_add(type="BEVEL")
    parts[0].modifiers["Bevel"].width = 0.02
    parts[0].modifiers["Bevel"].segments = 1
    return finish("road", parts)


def bandit(M):
    parts = [cylinder(0.13, 0.04, (0, 0, 0), M["bandit"], verts=12)]
    parts.append(cone(0.11, 0.05, 0.3, (0, 0, 0.04), M["bandit"], verts=10))
    parts.append(blob(0.075, 1.0, (0, 0, 0.4), M["bandit"], 2))
    parts.append(cone(0.085, 0.0, 0.12, (0, 0.01, 0.39), M["bandit"], verts=8))  # capucha
    return finish("bandit", parts)


def port(M):
    parts = []
    # Plataforma de tablones.
    for i in range(5):
        parts.append(box((0.09, 0.42, 0.04), (-0.2 + i * 0.1, 0, 0.06), M["wood"] if i % 2 else M["wood_dark"]))
    for x, y in ((-0.2, -0.19), (0.2, -0.19), (-0.2, 0.19), (0.2, 0.19)):
        parts.append(cylinder(0.025, 0.12, (x, y, -0.02), M["wood_dark"], verts=6))
    # Mástil con bandera del color del recurso.
    parts.append(cylinder(0.012, 0.36, (0.2, 0.17, 0.1), M["wood_dark"], verts=6))
    parts.append(box((0.15, 0.012, 0.1), (0.28, 0.17, 0.34), M["port_flag"]))
    return finish("port", parts)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = mats()
    for build in (tile_forest, tile_hills, tile_pasture, tile_fields, tile_mountains, tile_desert,
                  token, settlement, city, road, bandit, port):
        build(M)
        print("  modelo:", build.__name__)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
    print("Modelos exportados a", OUT_DIR)


if __name__ == "__main__":
    main()
