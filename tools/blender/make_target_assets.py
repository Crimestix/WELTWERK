"""Bestand für die Zielszene (Blender, ohne Oberfläche).

Aufruf:
  blender -b --factory-startup --python tools/blender/make_target_assets.py -- <projektordner>

Bäume: Stamm, Äste und Zweige rekursiv verzweigt; an den Zweigenden lockere Blattbüschel aus
Karten (Laubatlas 2 × 2). Normalen der Karten zwischen Büschel- und Kronenrichtung gemischt,
dadurch wirken Kronen weich und haben trotzdem Lücken. Rinde mit UV für eine Rindentextur.
Büsche: dichte Kartenbüschel (Strauchatlas). Felsen: verformte Würfel mit abgeflachter Oberseite
(Uferbänke, Findlinge, Steine) – Oberfläche in Godot per Dreiseitprojektion.
Fester Ausgangswert je Stück (random.Random) – gleiches Ergebnis bei jedem Lauf.
"""
import bpy
import bmesh
import math
import os
import random
import sys
import time
from mathutils import Vector, Matrix, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PROJECT = os.path.abspath(argv[0] if argv else os.getcwd())
OUT = os.path.join(PROJECT, "assets", "target")
for sub in ("trees", "bushes", "rocks"):
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)
started = time.time()
report = []
QUADRANTS = [(0.0, 0.5), (0.5, 0.5), (0.0, 0.0), (0.5, 0.0)]
UP = Vector((0, 0, 1))

SPECIES = {
    # Stammhöhe, Stammradius, Tiefe, Winkel, Aufwärtsneigung, Längenfaktor, erste Astlänge,
    # Büschelradius, Karten je Büschel, Kartengröße, Kinder je Ast
    "oak": dict(trunk=(1.7, 2.4), radius=0.45, depth=4, angle=(50, 75), up=0.18, shrink=0.74,
                limb=(3.4, 4.4), cluster=1.2, cards=22, card=0.95, children=(2, 3), limbs=(4, 5)),
    "beech": dict(trunk=(2.6, 3.4), radius=0.34, depth=4, angle=(30, 48), up=0.45, shrink=0.76,
                  limb=(3.2, 4.0), cluster=1.15, cards=22, card=0.92, children=(2, 3), limbs=(3, 4)),
    # Fernbaum für dichten Hintergrundwald: wenige, große Karten.
    "far": dict(trunk=(2.6, 3.4), radius=0.3, depth=3, angle=(30, 50), up=0.45, shrink=0.78,
                limb=(3.4, 4.2), cluster=1.6, cards=9, card=1.9, children=(2, 3), limbs=(3, 4)),
    "young": dict(trunk=(1.2, 1.8), radius=0.15, depth=3, angle=(30, 50), up=0.5, shrink=0.74,
                  limb=(1.9, 2.5), cluster=0.85, cards=12, card=0.95, children=(2, 3), limbs=(3, 4)),
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def perpendicular(v, rng):
    a = v.orthogonal().normalized()
    a.rotate(Matrix.Rotation(rng.uniform(0, 2 * math.pi), 3, v))
    return a


def add_tube(bm, col, uv, start, end, r0, r1, sides, segments, color, rng, bend=0.0, gravity=0.0):
    axis = end - start
    length = axis.length
    direction = axis.normalized()
    side = direction.orthogonal().normalized()
    other = direction.cross(side).normalized()
    bend_dir = perpendicular(direction, rng)
    rings = []
    for s in range(segments + 1):
        t = s / segments
        center = start + axis * t + bend_dir * (math.sin(t * math.pi) * bend * length) - UP * (gravity * t * t * length)
        radius = r0 + (r1 - r0) * t
        rings.append([bm.verts.new(center + (side * math.cos(2 * math.pi * k / sides)
                                              + other * math.sin(2 * math.pi * k / sides)) * radius)
                      for k in range(sides)])
    for s in range(segments):
        for k in range(sides):
            f = bm.faces.new((rings[s][k], rings[s][(k + 1) % sides], rings[s + 1][(k + 1) % sides], rings[s + 1][k]))
            f.material_index = 0
            for loop, (a, b) in zip(f.loops, ((k, s), (k + 1, s), (k + 1, s + 1), (k, s + 1))):
                loop[uv].uv = (a / sides * 2.0, (b / segments) * length / 1.2)
                loop[col] = color
    last = rings[-1]
    return start + axis - UP * (gravity * length)


def grow(bm, col, uv, start, direction, length, radius, depth, p, rng, tips, bark):
    sides = max(3, 8 - 2 * (p["depth"] - depth))
    end_target = start + direction * length
    end = add_tube(bm, col, uv, start, end_target, radius, radius * 0.62, sides, 3 if depth > 1 else 2,
                   bark, rng, bend=0.08, gravity=0.04 * (p["depth"] - depth))
    if depth == 0:
        tips.append((end, direction))
        return
    children = rng.randint(*p["children"])
    for c in range(children):
        axis = perpendicular(direction, rng)
        angle = math.radians(rng.uniform(*p["angle"]))
        nd = direction.copy()
        nd.rotate(Matrix.Rotation(angle, 3, axis))
        nd = (nd + UP * p["up"]).normalized()
        origin = start + (end - start) * rng.uniform(0.65, 1.0)
        grow(bm, col, uv, origin, nd, length * p["shrink"] * rng.uniform(0.85, 1.1), radius * 0.62,
             depth - 1, p, rng, tips, bark)
    # Laub auch entlang der Äste, damit die Krone voll und rund wird statt nur außen belaubt.
    if depth < p["depth"] - 1:
        for t in (0.45, 0.75):
            if rng.random() < 0.85:
                tips.append((start + (end - start) * t, direction))


def add_leaf_cards(bm, col, uv, tips, p, rng, normals_out, crown_center, crown_radii):
    for tip, direction in tips:
        center = tip + direction * p["cluster"] * 0.35
        cluster_out = (center - crown_center)
        crown_out = Vector((cluster_out.x / crown_radii.x, cluster_out.y / crown_radii.y,
                            cluster_out.z / crown_radii.z)).normalized()
        for _ in range(p["cards"]):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * 0.8)).normalized()
            pos = center + d * p["cluster"] * rng.uniform(0.15, 1.0)
            facing = (d * 0.6 + crown_out * 0.5 + UP * rng.uniform(0.1, 0.7)).normalized()
            tangent = perpendicular(facing, rng)
            bitangent = facing.cross(tangent).normalized()
            s = p["card"] * rng.uniform(0.75, 1.25)
            verts = [bm.verts.new(pos + (tangent * a + bitangent * b) * s * 0.5)
                     for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            f = bm.faces.new(verts)
            f.material_index = 1
            u0, v0 = QUADRANTS[rng.randrange(4)]
            rel = pos - crown_center
            depth_in = max(0.0, 1.0 - Vector((rel.x / crown_radii.x, rel.y / crown_radii.y, rel.z / crown_radii.z)).length)
            height_in_crown = rel.z / crown_radii.z * 0.5 + 0.5
            shade = 0.68 + 0.4 * min(max(height_in_crown, 0.0), 1.0) - 0.25 * depth_in
            tint = rng.uniform(-0.07, 0.07)
            for loop, (a, b) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                loop[uv].uv = (u0 + a * 0.5, v0 + b * 0.5)
                loop[col] = (shade + tint, shade + tint * 0.6, shade - tint * 0.3, 1.0)
                vp = loop.vert.co
                n_cluster = (vp - center).normalized()
                n_crown = Vector(((vp.x - crown_center.x) / crown_radii.x, (vp.y - crown_center.y) / crown_radii.y,
                                  (vp.z - crown_center.z) / crown_radii.z)).normalized()
                normals_out.append((n_cluster * 0.3 + n_crown * 0.6 + UP * 0.15).normalized())


def finish(mesh, bm, normals):
    bm.to_mesh(mesh)
    bm.free()
    for name in ("Bark", "LeafCards"):
        mesh.materials.append(bpy.data.materials.get(name) or bpy.data.materials.new(name))
    custom = []
    it = iter(normals)
    for poly in mesh.polygons:
        poly.use_smooth = True
        for _ in poly.loop_indices:
            custom.append(next(it) if poly.material_index == 1 else None)
    mesh.update()
    computed = [l.normal.copy() for l in mesh.loops]
    mesh.normals_split_custom_set([c if c is not None else computed[i] for i, c in enumerate(custom)])
    attrs = mesh.color_attributes
    attrs.active_color_name = attrs[0].name
    attrs.render_color_index = 0


def make_tree(species, index, seed):
    clear_scene()
    p = SPECIES[species]
    rng = random.Random(seed)
    name = f"{species}_{index}"
    mesh = bpy.data.meshes.new(name)
    bpy.context.scene.collection.objects.link(bpy.data.objects.new(name, mesh))
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    bark = (1.0, 1.0, 1.0, 1.0)
    trunk_height = rng.uniform(*p["trunk"])
    lean = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1.0)).normalized()
    fork = add_tube(bm, col, uv, Vector((0, 0, -0.4)), lean * trunk_height, p["radius"] * 1.25, p["radius"],
                    9, 4, bark, rng, bend=0.05)
    tips = []
    limbs = rng.randint(*p["limbs"])
    for k in range(limbs):
        a = 2 * math.pi * (k + rng.uniform(-0.3, 0.3)) / limbs
        direction = Vector((math.cos(a), math.sin(a), 0.0)) * math.sin(math.radians(rng.uniform(*p["angle"]))) + UP
        grow(bm, col, uv, fork, direction.normalized(), rng.uniform(*p["limb"]), p["radius"] * 0.7,
             p["depth"] - 1, p, rng, tips, bark)
    xs = [t[0] for t in tips]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    crown_center = (lo + hi) * 0.5
    crown_radii = Vector((max((hi - lo).x * 0.5, 1.0), max((hi - lo).y * 0.5, 1.0), max((hi - lo).z * 0.5, 1.0)))
    normals = []
    add_leaf_cards(bm, col, uv, tips, p, rng, normals, crown_center, crown_radii)
    finish(mesh, bm, normals)
    tris = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
    path = os.path.join(OUT, "trees", f"{name}.glb")
    export(path)
    report.append(f"{name}: {tris} Dreiecke, Höhe {hi.z + p['cluster']:.1f} m, {os.path.getsize(path) / 1024:.0f} KB")


def make_conifer(index, seed, height):
    """Nadelbaum: gerader Stamm, Astquirle, unten lang und hängend, oben kurz; an jedem Ast
    mehrere flache Nadelzweig-Karten (Nadelatlas 2 × 2), Material "NeedleCards"."""
    clear_scene()
    rng = random.Random(seed)
    name = f"spruce_{index}"
    mesh = bpy.data.meshes.new(name)
    bpy.context.scene.collection.objects.link(bpy.data.objects.new(name, mesh))
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    lean = Vector((rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), 1.0)).normalized()
    add_tube(bm, col, uv, Vector((0, 0, -0.4)), lean * height, 0.32 + height * 0.006, 0.04, 8, 6, (1, 1, 1, 1), rng)
    base = rng.uniform(1.6, 2.6)
    max_len = height * rng.uniform(0.2, 0.24)
    normals = []
    z = base
    while z < height - 0.3:
        t = (z - base) / (height - base)
        length = max(0.35, max_len * (1.0 - t) ** 0.85)
        count = rng.randint(5, 7)
        phase = rng.uniform(0, 2 * math.pi)
        for k in range(count):
            a = phase + 2 * math.pi * (k + rng.uniform(-0.25, 0.25)) / count
            droop = math.radians(rng.uniform(8, 26) * (1.0 - t * 0.7))
            out = Vector((math.cos(a), math.sin(a), 0.0))
            direction = (out * math.cos(droop) - UP * math.sin(droop)).normalized()
            origin = lean * z
            tip = add_tube(bm, col, uv, origin, origin + direction * length, 0.05 * (1.0 - t) + 0.015, 0.01,
                           3, 1, (1, 1, 1, 1), rng, gravity=0.06)
            side = direction.cross(UP).normalized()
            for c in range(3 if length > 0.8 else 2):
                along = direction.copy()
                along.rotate(Matrix.Rotation(rng.uniform(-0.25, 0.25), 3, UP))
                along = (along + UP * rng.uniform(0.0, 0.18)).normalized()
                roll = rng.uniform(-0.45, 0.45)
                across = side.copy()
                across.rotate(Matrix.Rotation(roll, 3, along))
                s = min(length * rng.uniform(0.85, 1.05), 2.6)
                start = origin + direction * length * rng.uniform(0.0, 0.25)
                w = s * rng.uniform(0.6, 0.8)
                verts = [bm.verts.new(start + across * (a2 * w * 0.5) + along * (b2 * s))
                         for a2, b2 in ((-1, 0), (1, 0), (1, 1), (-1, 1))]
                f = bm.faces.new(verts)
                f.material_index = 1
                u0, v0 = QUADRANTS[rng.randrange(4)]
                shade = 0.62 + 0.42 * t + rng.uniform(-0.06, 0.06)
                tint = rng.uniform(-0.05, 0.05)
                for loop, (a3, b3) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                    loop[uv].uv = (u0 + a3 * 0.5, v0 + b3 * 0.5)
                    loop[col] = (shade + tint, shade + tint * 0.5, shade, 1.0)
                    vp = loop.vert.co
                    cone = Vector((vp.x, vp.y, 0.0))
                    cone = (cone.normalized() if cone.length > 0.01 else Vector((0, 0, 0))) * 0.6
                    normals.append((cone + UP * 0.8).normalized())
        z += rng.uniform(0.45, 0.65)
    bm.to_mesh(mesh)
    bm.free()
    for mat_name in ("Bark", "NeedleCards"):
        mesh.materials.append(bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name))
    custom = []
    it = iter(normals)
    for poly in mesh.polygons:
        poly.use_smooth = True
        for _ in poly.loop_indices:
            custom.append(next(it) if poly.material_index == 1 else None)
    mesh.update()
    computed = [l.normal.copy() for l in mesh.loops]
    mesh.normals_split_custom_set([c if c is not None else computed[i] for i, c in enumerate(custom)])
    attrs = mesh.color_attributes
    attrs.active_color_name = attrs[0].name
    attrs.render_color_index = 0
    tris = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
    path = os.path.join(OUT, "trees", f"{name}.glb")
    export(path)
    report.append(f"{name}: {tris} Dreiecke, Höhe {height:.1f} m, {os.path.getsize(path) / 1024:.0f} KB")


def make_bush(index, seed):
    clear_scene()
    rng = random.Random(seed)
    name = f"bush_{index}"
    mesh = bpy.data.meshes.new(name)
    bpy.context.scene.collection.objects.link(bpy.data.objects.new(name, mesh))
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    tips = []
    for k in range(rng.randint(5, 8)):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.1, 0.6)
        h = rng.uniform(0.3, 1.1)
        tips.append((Vector((math.cos(a) * r, math.sin(a) * r, h)), Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, 1)).normalized()))
        add_tube(bm, col, uv, Vector((0, 0, -0.1)), tips[-1][0], 0.04, 0.015, 3, 1, (1, 1, 1, 1), rng)
    p = dict(cluster=0.45, cards=12, card=0.55)
    normals = []
    add_leaf_cards(bm, col, uv, tips, p, rng, normals, Vector((0, 0, 0.6)), Vector((0.8, 0.8, 0.6)))
    finish(mesh, bm, normals)
    tris = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
    path = os.path.join(OUT, "bushes", f"{name}.glb")
    export(path)
    report.append(f"{name}: {tris} Dreiecke")


def make_rock(name, seed, size, cuts, roundness, flat_top, roughness):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(name)
    bpy.context.scene.collection.objects.link(bpy.data.objects.new(name, mesh))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    offset = Vector((rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100)))
    for v in bm.verts:
        p = v.co.copy()
        # Kanten runden: Richtung Kugel ziehen.
        p = p.lerp(p.normalized() * 1.25, roundness)
        n = p.normalized()
        d = noise.fractal(p * 0.9 + offset, 0.6, 2.0, 4) * 0.22 * roughness
        d += noise.ridged_multi_fractal(p * 2.2 + offset, 0.8, 2.1, 3, 0.9, 2.0) * 0.04 * roughness
        p += n * d
        p = Vector((p.x * size.x * 0.5, p.y * size.y * 0.5, p.z * size.z * 0.5))
        # Oberseite abflachen (Granitbank), leicht geneigt.
        top = size.z * 0.5 * flat_top + p.x * 0.05
        if p.z > top:
            p.z = top + (p.z - top) * 0.15
        v.co = p
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials.new("Rock"))
    for poly in mesh.polygons:
        poly.use_smooth = True
    # Boden des Felsens liegt bei z = 0 minus ein Stück (wird ins Gelände gesteckt).
    tris = len(mesh.polygons)
    path = os.path.join(OUT, "rocks", f"{name}.glb")
    export(path)
    report.append(f"{name}: {tris} Dreiecke")


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_normals=True)


for i, seed in enumerate((1101, 1102, 1103), start=1):
    make_tree("oak", i, seed)
for i, seed in enumerate((1201, 1202), start=1):
    make_tree("beech", i, seed)
for i, seed in enumerate((1301, 1302), start=1):
    make_tree("young", i, seed)
for i, seed in enumerate((1351, 1352, 1353), start=1):
    make_tree("far", i, seed)
for i, (seed, h) in enumerate(((1451, 17.0), (1452, 21.0), (1453, 13.5)), start=1):
    make_conifer(i, seed, h)
for i, seed in enumerate((1401, 1402, 1403), start=1):
    make_bush(i, seed)
make_rock("ledge_1", 1501, Vector((6.5, 3.8, 2.6)), 12, 0.55, 0.72, 1.5)
make_rock("ledge_2", 1502, Vector((4.8, 3.2, 2.2)), 12, 0.60, 0.70, 1.6)
make_rock("ledge_3", 1503, Vector((8.5, 4.5, 3.0)), 14, 0.50, 0.75, 1.5)
make_rock("boulder_1", 1601, Vector((1.8, 1.5, 1.2)), 7, 0.55, 0.75, 1.0)
make_rock("boulder_2", 1602, Vector((1.3, 1.1, 0.9)), 7, 0.60, 0.80, 1.2)
make_rock("stone_1", 1701, Vector((0.5, 0.4, 0.25)), 4, 0.65, 0.9, 1.0)
report.append(f"Dauer: {time.time() - started:.1f} s")
with open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(report) + "\n")
print("\n".join(report))
