extends Node3D
## Stiltest: dieselbe kleine Landschaft (Hügel, Felsufer, See, Wiese, Baumgruppe) in zwei
## Varianten. Gleiche Geländeform, gleiche Positionen, gleiches Licht, gleiche Kamera.
##
##   A – vorhandener Bestand, unverändert (Poly Haven, CC0)
##   B – in Blender angepasst bzw. selbst gebaut (tools/blender/make_style_b.py)
##
##   C – Blattkarten-Bäume aus Blender mit Higgsfield-Laub, sonst wie B
## Tasten: 1 / 2 / 3 Variante, 4 / 5 Arbeits- bzw. Nahansicht.
## Aufruf mit `-- --variant=A --ansicht=nah --bench=<json> --screenshot=<png>` misst und beendet.

const PH := "res://assets/external/polyhaven/"
const B := "res://assets/style_b/"
const C := "res://assets/style_c/"
const LEAF_CARDS_SHADER := preload("res://src/style_test/leaf_cards.gdshader")
const LEAF_ATLAS := preload("res://assets/style_c/leaf_atlas.png")

const VARIANTS := {
	"A": {
		"title": "Variante A – Poly Haven, unverändert",
		"tree": {"paths": [PH + "models/island_tree_02/island_tree_02.gltf"], "size": 8.5, "mode": "whole"},
		"shrub": {"paths": [PH + "models/shrub_04/shrub_04.gltf", PH + "models/shrub_02/shrub_02.gltf"], "size": 1.5, "mode": "whole"},
		"rock": {"paths": [PH + "models/rock_moss_set_02/rock_moss_set_02.gltf", PH + "models/boulder_01/boulder_01.gltf", PH + "models/rock_07/rock_07.gltf"], "size": 1.6, "mode": "set"},
		"grass": {"paths": [PH + "models/grass_medium_02/grass_medium_02.gltf"], "size": 0.45, "mode": "whole"},
		"terrain": {"tint": Vector3(1.0, 1.0, 1.0), "saturation": 1.0, "brightness": 1.0},
		"own_materials": false,
	},
	"B": {
		"title": "Variante B – in Blender angepasst und selbst gebaut",
		"tree": {"paths": [B + "trees/tree_b_1.glb", B + "trees/tree_b_2.glb", B + "trees/tree_b_3.glb"], "size": 8.5, "mode": "whole"},
		"shrub": {"paths": [B + "bushes/bush_b_1.glb", B + "bushes/bush_b_2.glb"], "size": 1.5, "mode": "whole"},
		"rock": {"paths": [B + "rocks/rock_moss_set_02_b.glb", B + "rocks/boulder_01_b.glb", B + "rocks/rock_07_b.glb"], "size": 1.6, "mode": "set"},
		"grass": {"paths": [B + "grass/grass_b_1.glb", B + "grass/grass_b_2.glb"], "size": 0.45, "mode": "whole"},
		"terrain": {"tint": Vector3(1.04, 1.06, 0.86), "saturation": 1.3, "brightness": 1.08},
		"own_materials": true,
	},
	"C": {
		"title": "Variante C – Blattkarten-Bäume (Blender + Higgsfield-Laub)",
		"tree": {"paths": [C + "trees/tree_c_1.glb", C + "trees/tree_c_2.glb", C + "trees/tree_c_3.glb"], "size": 8.5, "mode": "whole"},
		"shrub": {"paths": [C + "bushes/bush_c_1.glb", C + "bushes/bush_c_2.glb"], "size": 1.5, "mode": "whole"},
		"rock": {"paths": [B + "rocks/rock_moss_set_02_b.glb", B + "rocks/boulder_01_b.glb", B + "rocks/rock_07_b.glb"], "size": 1.6, "mode": "set"},
		"grass": {"paths": [B + "grass/grass_b_1.glb", B + "grass/grass_b_2.glb"], "size": 0.45, "mode": "whole"},
		"terrain": {"tint": Vector3(1.04, 1.06, 0.86), "saturation": 1.3, "brightness": 1.08},
		"own_materials": true,
	},
}

const VIEWS := {
	"arbeit": {"title": "Arbeitsansicht", "focus": Vector3(0.0, 0.0, 6.0), "distance": 140.0},
	"nah": {"title": "Nahansicht", "focus": Vector3(4.0, 0.0, -4.0), "distance": 34.0},
}

const TERRAIN_SHADER := preload("res://src/style_test/style_terrain.gdshader")
const FOLIAGE_SHADER := preload("res://src/style_test/foliage.gdshader")
const GRASS_SHADER := preload("res://src/style_test/grass.gdshader")

@onready var terrain: Terrain = $Terrain
@onready var camera_rig: StrategyCamera = $CameraRig
@onready var label: Label = $Interface/Label

var field: Heightfield
var placements := {}
var variant := ""
var view := "arbeit"
var load_ms := 0.0
var _props: Node3D
var _fps_timer := 0.0


func _ready() -> void:
	field = StyleLandscape.build()
	placements = {
		"tree": StyleLandscape.trees(field),
		"shrub": StyleLandscape.shrubs(field),
		"rock": StyleLandscape.rocks(field),
		"grass": StyleLandscape.grass(field),
	}
	terrain.show_field(field, null, 1.6)

	var args := _user_args()
	show_variant(args.get("variant", "A"))
	show_view(args.get("ansicht", "arbeit"))
	if args.has("bench") or args.has("screenshot"):
		_run_bench(args)


func _user_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			result[pair[0]] = pair[1]
	return result


func show_variant(id: String) -> void:
	if id == variant or not VARIANTS.has(id):
		return
	var started := Time.get_ticks_usec()
	variant = id
	var spec: Dictionary = VARIANTS[id]
	terrain.set_ground_material(_terrain_material(spec["terrain"]))
	if _props:
		_props.queue_free()
	_props = Node3D.new()
	_props.name = "Bestand"
	add_child(_props)
	for kind in ["tree", "shrub", "rock", "grass"]:
		var options := _load_options(spec[kind], spec["own_materials"])
		_place(kind, options, placements[kind])
	load_ms = (Time.get_ticks_usec() - started) / 1000.0
	_update_label()


func show_view(id: String) -> void:
	if not VIEWS.has(id):
		return
	view = id
	camera_rig.jump_to(VIEWS[id]["focus"], VIEWS[id]["distance"])
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_1: show_variant("A")
			KEY_2: show_variant("B")
			KEY_3: show_variant("C")
			KEY_4: show_view("arbeit")
			KEY_5: show_view("nah")


func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer > 0.5:
		_fps_timer = 0.0
		_update_label()


func _update_label() -> void:
	if label == null or variant == "":
		return
	label.text = "STILTEST · %s · %s · %d Bilder/s\n1 / 2 / 3 Variante A, B, C · 4 / 5 Arbeits- oder Nahansicht" % [
		VARIANTS[variant]["title"], VIEWS[view]["title"], Engine.get_frames_per_second()]


func _terrain_material(grading: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	var maps := {
		"grass": "rocky_terrain_02", "meadow": "aerial_grass_rock", "forest": "brown_mud_leaves_01",
		"rock": "aerial_rocks_02", "sand": "coast_sand_01",
	}
	for slot in maps:
		var id: String = maps[slot]
		var base := PH + "textures/%s/%s_" % [id, id]
		m.set_shader_parameter(slot + "_albedo", load(base + "diffuse.jpg"))
		m.set_shader_parameter(slot + "_normal", load(base + "nor_gl.jpg"))
		m.set_shader_parameter(slot + "_arm", load(base + "arm.jpg"))
	m.set_shader_parameter("cliff_albedo", load(PH + "textures/mossy_rock/mossy_rock_diffuse.jpg"))
	m.set_shader_parameter("grove_center", StyleLandscape.GROVE)
	m.set_shader_parameter("grove_radius", StyleLandscape.GROVE_RADIUS)
	m.set_shader_parameter("bank_from", StyleLandscape.BANK_FROM)
	m.set_shader_parameter("bank_to", StyleLandscape.BANK_TO)
	m.set_shader_parameter("tint", grading["tint"])
	m.set_shader_parameter("saturation", grading["saturation"])
	m.set_shader_parameter("brightness", grading["brightness"])
	return m


## Lädt die Modelle einer Art. Ergebnis: Liste von Möglichkeiten, jede eine Liste von [Netz, Lage].
func _load_options(spec: Dictionary, own_materials: bool) -> Array:
	var options := []
	for path in spec["paths"]:
		var scene: PackedScene = load(path)
		if scene == null:
			push_warning("Modell fehlt: " + path)
			continue
		var root := scene.instantiate()
		var parts := []
		_collect_meshes(root, Transform3D.IDENTITY, parts)
		root.free()
		if own_materials:
			for part in parts:
				part[0] = _with_own_materials(part[0])
		if spec["mode"] == "set":
			for part in parts:
				options.append(_normalized([part], spec["size"], true))
		else:
			options.append(_normalized(parts, spec["size"], false))
	return options


func _collect_meshes(node: Node, parent: Transform3D, parts: Array) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		parts.append([(node as MeshInstance3D).mesh, xform])
	for child in node.get_children():
		_collect_meshes(child, xform, parts)


## Bringt ein Modell auf Zielgröße (Höhe bzw. größte Ausdehnung), Fußpunkt in den Ursprung.
func _normalized(parts: Array, size: float, by_largest: bool) -> Array:
	var box := AABB()
	var first := true
	for part in parts:
		var b: AABB = part[1] * (part[0] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var reference := box.get_longest_axis_size() if by_largest else box.size.y
	var s := size / maxf(reference, 0.001)
	var center := box.get_center()
	var shift := Transform3D(Basis.from_scale(Vector3(s, s, s)), -Vector3(center.x, box.position.y, center.z) * s)
	var result := []
	for part in parts:
		result.append([part[0], shift * part[1]])
	return result


func _with_own_materials(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var original := copy.surface_get_material(i)
		var name := original.resource_name if original else ""
		if name.begins_with("LeafCards"):
			var cards := ShaderMaterial.new()
			cards.shader = LEAF_CARDS_SHADER
			cards.set_shader_parameter("leaf_atlas", LEAF_ATLAS)
			copy.surface_set_material(i, cards)
		elif name.begins_with("Leaves"):
			var m := ShaderMaterial.new()
			m.shader = FOLIAGE_SHADER
			copy.surface_set_material(i, m)
		elif name.begins_with("Grass"):
			var g := ShaderMaterial.new()
			g.shader = GRASS_SHADER
			copy.surface_set_material(i, g)
		elif name.begins_with("Bark"):
			var bark := StandardMaterial3D.new()
			bark.vertex_color_use_as_albedo = true
			bark.roughness = 0.95
			copy.surface_set_material(i, bark)
	return copy


func _place(kind: String, options: Array, transforms: Array[Transform3D]) -> void:
	if options.is_empty():
		return
	for k in options.size():
		var mine: Array[Transform3D] = []
		for i in transforms.size():
			if i % options.size() == k:
				mine.append(transforms[i])
		if mine.is_empty():
			continue
		for part in options[k]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = mine.size()
			for i in mine.size():
				mm.set_instance_transform(i, mine[i] * part[1])
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_%d" % [kind, k]
			instance.multimesh = mm
			if kind == "grass":
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_props.add_child(instance)


## Misst Bildzeit, Speicher und Zeichenaufrufe, speichert ein Bild und beendet.
func _run_bench(args: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 90:
		await get_tree().process_frame
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in 300:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var result := {
		"variant": variant,
		"view": view,
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(get_viewport().get_visible_rect().size),
		"frame_ms_avg": total / times.size(),
		"frame_ms_p95": sorted[int(sorted.size() * 0.95)],
		"fps_avg": 1000.0 / (total / times.size()),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"load_ms": load_ms,
		"instances": {"tree": placements["tree"].size(), "shrub": placements["shrub"].size(),
			"rock": placements["rock"].size(), "grass": placements["grass"].size()},
	}
	if args.has("bench"):
		var file := FileAccess.open(args["bench"], FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	if args.has("screenshot"):
		$Interface.visible = args.get("overlay", "ja") == "ja"
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path: String = args["screenshot"]
		if path.ends_with(".jpg"):
			image.save_jpg(path, 0.9)
		else:
			image.save_png(path)
	print(JSON.stringify(result))
	get_tree().quit()
