"""Stiltest-Variante C: Laubbäume und Büsche aus Blattkarten (Blender, ohne Oberfläche).

Aufruf:
  blender -b --factory-startup --python tools/blender/make_style_c.py -- <projektordner>

- Stamm und Äste als verjüngte Zylinder (Eckpunktfarben).
- Krone aus vielen Blattkarten (Flächen mit dem Laubatlas assets/style_c/leaf_atlas.png,
  2 × 2 Laubbüschel, erzeugt mit Higgsfield). Jede Karte nimmt zufällig eines der vier Büschel.
- Normalen der Karten zeigen vom Mittelpunkt ihres Kronenballens nach außen: Die Krone wird
  wie ein weiches Volumen beleuchtet statt wie lose Zettel.
- Eckpunktfarben auf den Karten: innen/unten dunkler (vorgebackene Verschattung).
Fester Ausgangswert (random.Random) – gleiches Ergebnis bei jedem Lauf.
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
OUT = os.path.join(PROJECT, "assets", "style_c")
os.makedirs(os.path.join(OUT, "trees"), exist_ok=True)
os.makedirs(os.path.join(OUT, "bushes"), exist_ok=True)
started = time.time()
report = []

QUADRANTS = [(0.0, 0.5), (0.5, 0.5), (0.0, 0.0), (0.5, 0.0)]  # (u0, v0) je Büschel, Größe 0,5


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_tube(bm, col, start, end, r0, r1, sides, segments, color, rng, bend=0.0):
    axis = end - start
    length = axis.length
    direction = axis.normalized()
    side = direction.orthogonal().normalized()
    other = direction.cross(side).normalized()
    bend_dir = (side * rng.uniform(-1, 1) + other * rng.uniform(-1, 1)).normalized()
    rings = []
    for s in range(segments + 1):
        t = s / segments
        center = start + axis * t + bend_dir * (math.sin(t * math.pi) * bend * length)
        radius = r0 + (r1 - r0) * t
        rings.append([bm.verts.new(center + (side * math.cos(2 * math.pi * k / sides)
                                              + other * math.sin(2 * math.pi * k / sides)) * radius)
                      for k in range(sides)])
    for s in range(segments):
        for k in range(sides):
            f = bm.faces.new((rings[s][k], rings[s][(k + 1) % sides], rings[s + 1][(k + 1) % sides], rings[s + 1][k]))
            f.material_index = 0
            for loop in f.loops:
                loop[col] = color


def add_cards(bm, col, uv, center, radii, count, card_size, rng, normals_out):
    """Blattkarten auf und in einem Ellipsoid; Normale je Ecke = nach außen vom Mittelpunkt."""
    for _ in range(count):
        # Punkt im Ellipsoid, bevorzugt nahe der Oberfläche.
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        depth = 1.0 - rng.random() ** 2.5 * 0.7
        p = center + Vector((d.x * radii.x, d.y * radii.y, d.z * radii.z)) * depth
        out = (p - center)
        out = Vector((out.x / radii.x, out.y / radii.y, out.z / radii.z)).normalized()
        # Karte grob zur Außenseite gedreht, mit Zufall; leicht nach oben geneigt.
        facing = (out + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0.0, 0.9)))).normalized()
        tangent = facing.orthogonal().normalized()
        tangent.rotate(Matrix.Rotation(rng.uniform(0, 2 * math.pi), 3, facing))
        bitangent = facing.cross(tangent).normalized()
        s = card_size * rng.uniform(0.75, 1.25)
        corners = [p + (tangent * a + bitangent * b) * s * 0.5 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        verts = [bm.verts.new(c) for c in corners]
        f = bm.faces.new(verts)
        f.material_index = 1
        u0, v0 = QUADRANTS[rng.randrange(4)]
        shade = 0.55 + 0.45 * (out.z * 0.5 + 0.5) * depth
        tint = rng.uniform(-0.06, 0.06)
        for loop, (a, b) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = (u0 + a * 0.5, v0 + b * 0.5)
            loop[col] = (shade + tint, shade + tint * 0.5, shade, 1.0)
            co = loop.vert.co
            n = Vector(((co.x - center.x) / radii.x, (co.y - center.y) / radii.y, (co.z - center.z) / radii.z)).normalized()
            normals_out.append((n * 0.85 + Vector((0, 0, 0.15))).normalized())


def finish(mesh, bm, normals, card_material_index_start):
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials.get("Bark") or bpy.data.materials.new("Bark"))
    mesh.materials.append(bpy.data.materials.get("LeafCards") or bpy.data.materials.new("LeafCards"))
    # Eigene Normalen: Rinde glatt aus der Geometrie, Karten nach außen.
    custom = []
    it = iter(normals)
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            if poly.material_index == 1:
                custom.append(next(it))
            else:
                custom.append(None)
        poly.use_smooth = True
    mesh.update()
    computed = [l.normal.copy() for l in mesh.loops]
    mesh.normals_split_custom_set([c if c is not None else computed[i] for i, c in enumerate(custom)])
    attrs = mesh.color_attributes
    attrs.active_color_name = attrs[0].name
    attrs.render_color_index = 0


def make_tree(index, seed):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(f"tree_c_{index}")
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    normals = []

    bark = (0.22, 0.18, 0.14, 1.0)
    height = rng.uniform(7.0, 10.0)
    lean = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0))
    fork = Vector((0, 0, height * rng.uniform(0.38, 0.48))) + lean * 0.5
    add_tube(bm, col, Vector((0, 0, -0.3)), fork, 0.34, 0.22, 8, 4, bark, rng, bend=0.06)
    clumps = []
    for b in range(rng.randint(3, 5)):
        a = 2 * math.pi * (b + rng.uniform(-0.25, 0.25)) / 4.0
        reach = rng.uniform(1.4, 2.6)
        end = fork + Vector((math.cos(a) * reach, math.sin(a) * reach, rng.uniform(1.6, 3.2)))
        add_tube(bm, col, fork, end, 0.18, 0.06, 6, 3, bark, rng, bend=0.12)
        size = rng.uniform(1.7, 2.4)
        clumps.append((end + Vector((0, 0, size * 0.25)), Vector((size, size * rng.uniform(0.85, 1.1), size * 0.75))))
    top = fork + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), height * 0.45))
    add_tube(bm, col, fork, top, 0.18, 0.06, 6, 3, bark, rng, bend=0.05)
    clumps.append((top, Vector((2.3, 2.3, 1.7))))
    for center, radii in clumps:
        volume = radii.x * radii.y * radii.z
        add_cards(bm, col, uv, center, radii, int(10 * volume), 1.6, rng, normals)

    finish(mesh, bm, normals, 1)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    path = os.path.join(OUT, "trees", f"tree_c_{index}.glb")
    export(path)
    report.append(f"tree_c_{index}: {tris} Dreiecke, {os.path.getsize(path) / 1024:.0f} KB")


def make_bush(index, seed):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(f"bush_c_{index}")
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    normals = []
    add_tube(bm, col, Vector((0, 0, -0.1)), Vector((0, 0, 0.4)), 0.06, 0.03, 5, 1, (0.2, 0.16, 0.12, 1), rng)
    for i in range(rng.randint(2, 3)):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.1, 0.4)
        s = rng.uniform(0.55, 0.8)
        add_cards(bm, col, uv, Vector((math.cos(a) * r, math.sin(a) * r, s * 0.65)), Vector((s, s, s * 0.75)), 28, 0.7, rng, normals)
    finish(mesh, bm, normals, 1)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    path = os.path.join(OUT, "bushes", f"bush_c_{index}.glb")
    export(path)
    report.append(f"bush_c_{index}: {tris} Dreiecke")


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_normals=True)


for i, seed in enumerate((701, 702, 703), start=1):
    make_tree(i, seed)
for i, seed in enumerate((751, 752), start=1):
    make_bush(i, seed)
report.append(f"Dauer: {time.time() - started:.1f} s")
with open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(report) + "\n")
print("\n".join(report))
