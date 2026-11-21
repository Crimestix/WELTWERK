"""Lädt ein GLB, gibt Größe, Dreiecke und Materialien aus und rendert eine Vorschau (Eevee).

Aufruf: blender -b --factory-startup --python tools/blender/inspect_render_glb.py -- <glb> <png>
"""
import bpy
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
lo = Vector((1e9, 1e9, 1e9))
hi = -lo
tris = 0
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
        hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
print("Objekte", len(meshes), "Dreiecke", tris, "Größe", tuple(round(v, 3) for v in (hi - lo)))
for m in bpy.data.materials:
    print("Material", m.name, [n.image.name + f" {n.image.size[0]}x{n.image.size[1]}" for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image] if m.use_nodes else "")
center = (lo + hi) * 0.5
size = (hi - lo).length
cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.scene.collection.objects.link(cam)
cam.location = center + Vector((size * 0.9, -size * 1.1, size * 0.7))
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.rotation_euler = (0.8, 0.2, 0.6)
bpy.context.scene.collection.objects.link(sun)
world = bpy.data.worlds.new("W")
world.color = (0.6, 0.65, 0.7)
bpy.context.scene.world = world
bpy.context.scene.camera = cam
bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
bpy.context.scene.render.resolution_x = 900
bpy.context.scene.render.resolution_y = 600
bpy.context.scene.render.filepath = out
bpy.ops.render.render(write_still=True)
