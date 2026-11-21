"""Erzeugt die Bestände für Stiltest-Variante B in Blender (ohne Oberfläche).

Aufruf:
  blender -b --factory-startup --python tools/blender/make_style_b.py -- <projektordner>

- Eigene Laubbäume (3 Varianten): Stamm und Äste als verjüngte Zylinder, Krone aus verformten
  Blattballen; Farben als Eckpunktfarben (dunkler innen/unten, heller oben).
- Eigene Grasbüschel aus Halmen (echte Dreiecke, keine Transparenz – günstig auf dem Mac).
- Poly-Haven-Felsen (CC0) ausgedünnt auf Spielmaß, Texturen bleiben.
Alles mit festem Ausgangswert (random.Random), gleiches Ergebnis bei jedem Lauf.
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
OUT = os.path.join(PROJECT, "assets", "style_b")
SRC = os.path.join(PROJECT, "assets", "external", "polyhaven", "models")
os.makedirs(os.path.join(OUT, "trees"), exist_ok=True)
os.makedirs(os.path.join(OUT, "rocks"), exist_ok=True)
os.makedirs(os.path.join(OUT, "grass"), exist_ok=True)
os.makedirs(os.path.join(OUT, "bushes"), exist_ok=True)

started = time.time()
report = []


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return mat


def add_tube(bm, start, end, r0, r1, sides, segments, color, rng, bend=0.0):
    """Verjüngter Zylinder von start nach end, leicht gebogen."""
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
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            offset = (side * math.cos(a) + other * math.sin(a)) * radius
            ring.append(bm.verts.new(center + offset))
        rings.append(ring)
    col = bm.loops.layers.color.active
    for s in range(segments):
        for k in range(sides):
            a, b = rings[s][k], rings[s][(k + 1) % sides]
            c, d = rings[s + 1][(k + 1) % sides], rings[s + 1][k]
            f = bm.faces.new((a, b, c, d))
            f.material_index = 0
            for loop in f.loops:
                loop[col] = color
    return rings[-1]


def add_clump(bm, center, radii, rng, seed, base_color, top_color):
    """Blattballen: verformte Ikosaederkugel mit Höhenfarbverlauf."""
    sub = bmesh.new()
    bmesh.ops.create_icosphere(sub, subdivisions=3, radius=1.0)
    col_layer = None
    verts_map = {}
    for v in sub.verts:
        n = v.co.normalized()
        bump = noise.noise(n * 2.2 + Vector((seed, seed * 0.37, seed * 0.71))) * 0.28
        bump += noise.noise(n * 5.0 + Vector((seed * 1.3, 0, seed))) * 0.10
        p = Vector((n.x * radii.x, n.y * radii.y, n.z * radii.z)) * (1.0 + bump)
        verts_map[v] = bm.verts.new(center + p)
    col = bm.loops.layers.color.active
    for f in sub.faces:
        nf = bm.faces.new([verts_map[v] for v in f.verts])
        nf.material_index = 1
        for loop, src in zip(nf.loops, f.loops):
            n = src.vert.co.normalized()
            up = n.z * 0.5 + 0.5
            jitter = rng.uniform(-0.05, 0.05)
            c = [base_color[i] + (top_color[i] - base_color[i]) * up + jitter for i in range(3)]
            loop[col] = (max(c[0], 0), max(c[1], 0), max(c[2], 0), 1.0)
    sub.free()


def make_tree(index, seed):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(f"tree_b_{index}")
    obj = bpy.data.objects.new(f"tree_b_{index}", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.loops.layers.color.new("Col")

    bark = (0.20, 0.15, 0.11, 1.0)
    height = rng.uniform(6.0, 9.0)
    trunk_top = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), height * 0.55))
    add_tube(bm, Vector((0, 0, -0.3)), trunk_top, 0.32, 0.18, 8, 5, bark, rng, bend=0.05)

    tips = [trunk_top + Vector((0, 0, height * 0.25))]
    add_tube(bm, trunk_top, tips[0], 0.18, 0.08, 6, 3, bark, rng, bend=0.05)
    branch_count = rng.randint(4, 6)
    for b in range(branch_count):
        a = 2 * math.pi * (b + rng.uniform(-0.2, 0.2)) / branch_count
        start = Vector((0, 0, height * rng.uniform(0.35, 0.55))) + trunk_top * 0.6
        reach = rng.uniform(1.6, 2.6)
        end = start + Vector((math.cos(a) * reach, math.sin(a) * reach, rng.uniform(1.0, 2.2)))
        add_tube(bm, start, end, 0.12, 0.05, 6, 3, bark, rng, bend=0.1)
        tips.append(end)

    dark = (0.10, 0.20, 0.05)
    light = (0.36, 0.50, 0.14)
    for i, tip in enumerate(tips):
        size = rng.uniform(1.4, 2.0) * (1.25 if i == 0 else 1.0)
        radii = Vector((size, size * rng.uniform(0.85, 1.1), size * rng.uniform(0.7, 0.9)))
        add_clump(bm, tip + Vector((0, 0, size * 0.2)), radii, rng, seed * 10 + i, dark, light)
    # Füllballen in der Mitte, damit die Krone geschlossen wirkt.
    add_clump(bm, Vector((0, 0, height * 0.78)), Vector((2.4, 2.4, 1.6)), rng, seed * 10 + 99, dark, light)

    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material("Bark"))
    mesh.materials.append(material("Leaves"))
    for p in mesh.polygons:
        p.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    path = os.path.join(OUT, "trees", f"tree_b_{index}.glb")
    export(path)
    report.append(f"tree_b_{index}: {tris} Dreiecke, {os.path.getsize(path) / 1024:.0f} KB")


def make_bush(index, seed):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(f"bush_b_{index}")
    obj = bpy.data.objects.new(f"bush_b_{index}", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.loops.layers.color.new("Col")
    dark = (0.09, 0.18, 0.05)
    light = (0.32, 0.45, 0.13)
    for i in range(rng.randint(3, 5)):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.5)
        size = rng.uniform(0.5, 0.8)
        center = Vector((math.cos(a) * r, math.sin(a) * r, size * 0.6))
        add_clump(bm, center, Vector((size, size, size * 0.8)), rng, seed * 10 + i, dark, light)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material("Bark"))
    mesh.materials.append(material("Leaves"))
    for p in mesh.polygons:
        p.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    path = os.path.join(OUT, "bushes", f"bush_b_{index}.glb")
    export(path)
    report.append(f"bush_b_{index}: {tris} Dreiecke")


def make_grass(index, seed):
    clear_scene()
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(f"grass_b_{index}")
    obj = bpy.data.objects.new(f"grass_b_{index}", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    for _ in range(36):
        r = rng.uniform(0.0, 0.35)
        a = rng.uniform(0, 2 * math.pi)
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        h = rng.uniform(0.25, 0.6)
        lean = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
        w = rng.uniform(0.012, 0.025)
        d = Vector((math.cos(a + 1.57), math.sin(a + 1.57), 0)) * w
        v0 = bm.verts.new(base - d)
        v1 = bm.verts.new(base + d)
        v2 = bm.verts.new(base + lean * 0.5 + Vector((0, 0, h * 0.55)) + d * 0.6)
        v3 = bm.verts.new(base + lean * 0.5 + Vector((0, 0, h * 0.55)) - d * 0.6)
        v4 = bm.verts.new(base + lean + Vector((0, 0, h)))
        tone = rng.uniform(-0.04, 0.04)
        bottom = (0.10 + tone, 0.18 + tone, 0.04, 1.0)
        mid = (0.25 + tone, 0.38 + tone, 0.10, 1.0)
        top = (0.48 + tone, 0.52 + tone, 0.20, 1.0)
        for verts, colors in (((v0, v1, v2, v3), (bottom, bottom, mid, mid)), ((v3, v2, v4), (mid, mid, top))):
            f = bm.faces.new(verts)
            for loop, c in zip(f.loops, colors):
                loop[col] = c
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material("Grass"))
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    path = os.path.join(OUT, "grass", f"grass_b_{index}.glb")
    export(path)
    report.append(f"grass_b_{index}: {tris} Dreiecke")


def decimate_rock(source_id, target_tris):
    clear_scene()
    src = os.path.join(SRC, source_id, f"{source_id}.gltf")
    if not os.path.exists(src):
        report.append(f"{source_id}: Quelle fehlt ({src})")
        return
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    ratio = min(1.0, target_tris / max(before, 1))
    for o in meshes:
        o.data = o.data.copy()  # geteilte Netze einzeln machen, sonst greift das Ausdünnen nicht
        mod = o.modifiers.new("Ausduennen", "DECIMATE")
        mod.ratio = ratio
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    after = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    path = os.path.join(OUT, "rocks", f"{source_id}_b.glb")
    export(path)
    report.append(f"{source_id}_b: {before} → {after} Dreiecke, {os.path.getsize(path) / 1024:.0f} KB")


def activate_colors():
    """Farbebene als aktiv markieren – sonst schreibt der glTF-Export keine Eckpunktfarben."""
    for mesh in bpy.data.meshes:
        attrs = mesh.color_attributes
        if len(attrs) == 0:
            continue
        name = attrs[0].name
        attrs.active_color_name = name
        attrs.render_color_index = 0


def export(path):
    activate_colors()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True)


for i, seed in enumerate((101, 202, 303), start=1):
    make_tree(i, seed)
for i, seed in enumerate((11, 22), start=1):
    make_grass(i, seed)
for i, seed in enumerate((51, 52), start=1):
    make_bush(i, seed)
decimate_rock("rock_moss_set_02", 6000)
decimate_rock("boulder_01", 4000)
decimate_rock("rock_07", 2500)

report.append(f"Dauer: {time.time() - started:.1f} s")
with open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(report) + "\n")
print("\n".join(report))
