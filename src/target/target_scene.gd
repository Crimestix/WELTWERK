extends Node3D
## Zielszene: Weg zum bestätigten Zielbild (docs/stiltest/zielbild_higgsfield.jpg).
##
## Aufruf mit `-- --ansicht=ziel --bench=<json> --screenshot=<jpg>` misst, speichert ein Bild und
## beendet. Tasten: 1 Zielansicht, 2 Arbeitsansicht, 3 Nahansicht.

const PH := "res://assets/external/polyhaven/textures/"
const T := "res://assets/target/"
const TERRAIN_SHADER := preload("res://src/target/target_terrain.gdshader")
const WATER_SHADER := preload("res://src/target/water_clear.gdshader")

const TREES := [
	["oak_1", "oak_2", "oak_3"],
	["beech_1", "beech_2"],
	["young_1", "young_2"],
	["far_1", "far_2", "far_3"],
]

const VIEWS := {
	"ziel": {"title": "Zielansicht", "focus": Vector3(-20.0, 0.0, -50.0), "distance": 82.0, "pitch": 20.0, "yaw": 12.0},
	"arbeit": {"title": "Arbeitsansicht", "focus": Vector3(-10.0, 0.0, -40.0), "distance": 210.0, "pitch": 48.0},
	"nah": {"title": "Nahansicht", "focus": Vector3(6.0, 0.0, -8.0), "distance": 38.0, "pitch": 36.0},
}

@export var grass_count := 230000
@export var flower_count := 13000

@onready var terrain: Terrain = $Terrain
@onready var camera_rig: StrategyCamera = $CameraRig
@onready var label: Label = $Interface/Label

var land := TargetLandscape.new()
var view := "ziel"
var build_ms := 0.0
var counts := {}
var _fps_timer := 0.0


func _ready() -> void:
	var started := Time.get_ticks_usec()
	var field := land.build()
	terrain.show_field(field, _terrain_material(), 3.0)
	var water := terrain.get_node("Water") as MeshInstance3D
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	(water.mesh as PlaneMesh).material = water_material

	_place_trees(land.trees(), "Bäume")
	_place_trees(land.background_trees(), "Wald")
	_place_simple(land.bushes(), [T + "bushes/bush_1.glb", T + "bushes/bush_2.glb", T + "bushes/bush_3.glb"], "Büsche", true)
	_place_simple(land.forest_edge_bushes(), [T + "bushes/bush_1.glb", T + "bushes/bush_3.glb"], "Unterholz", true)
	# Higgsfield-Granit (1,9 m lang) auf Uferbank-Größe gestreckt.
	var ledges: Array = []
	var rng := FixedRandom.rng_of(FixedRandom.derive(TargetLandscape.SEED, "Felsbank-Form"))
	for xform in land.ledges():
		var stretch := Vector3(rng.randf_range(3.6, 5.2), rng.randf_range(2.6, 3.8), rng.randf_range(3.0, 4.2))
		ledges.append(xform * Transform3D(Basis.from_scale(stretch), Vector3.ZERO))
	_place_simple(ledges, [T + "rocks/granite_hf.glb", T + "rocks/granite_hf_2.glb"], "Felsbänke", false)
	var boulders: Array = []
	for xform in land.boulders():
		boulders.append(xform * Transform3D(Basis.from_scale(Vector3(1.1, 1.1, 1.1)), Vector3.ZERO))
	_place_simple(boulders, [T + "rocks/granite_hf_2.glb", T + "rocks/granite_hf.glb", T + "rocks/granite_hf_2.glb"], "Findlinge", false)
	_place_simple(land.stones(), [T + "rocks/stone_1.glb", T + "rocks/boulder_2.glb"], "Steine", false)
	_place_cards(land.grass(grass_count), _texture(T + "grass_atlas.png"), 0.55, 0.8, "Gras", false)
	_place_cards(land.flowers(flower_count), _texture(T + "flower_atlas.png"), 0.6, 0.55, "Blumen", true)
	build_ms = (Time.get_ticks_usec() - started) / 1000.0

	var args := _user_args()
	show_view(args.get("ansicht", "ziel"))
	if args.has("bench") or args.has("screenshot"):
		_run_bench(args)


func show_view(id: String) -> void:
	if not VIEWS.has(id):
		return
	view = id
	camera_rig.pitch_degrees = VIEWS[id]["pitch"]
	camera_rig.yaw_degrees = VIEWS[id].get("yaw", 0.0)
	camera_rig.jump_to(VIEWS[id]["focus"], VIEWS[id]["distance"])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_1: show_view("ziel")
			KEY_2: show_view("arbeit")
			KEY_3: show_view("nah")


func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer > 0.5:
		_fps_timer = 0.0
		label.text = "ZIELSZENE · %s · %d Bilder/s · 1 Ziel · 2 Arbeit · 3 nah" % [VIEWS[view]["title"], Engine.get_frames_per_second()]


func _user_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			result[pair[0]] = pair[1]
	return result


# --- Materialien ---------------------------------------------------------------------------

func _texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	var maps := {"grass": "rocky_terrain_02", "meadow": "aerial_grass_rock", "dry": "withered_grass",
		"rock": "rock_boulder_dry", "bottom": "river_small_rocks"}
	for slot in maps:
		var base := PH + "%s/%s_" % [maps[slot], maps[slot]]
		m.set_shader_parameter(slot + "_albedo", load(base + "diffuse.jpg"))
		if ResourceLoader.exists(base + "nor_gl.jpg"):
			m.set_shader_parameter(slot + "_normal", load(base + "nor_gl.jpg"))
	return m


## Netz eines Modells mit Materialien im Zielstil (gemeinsam mit dem Editor).
func _mesh(path: String, bush: bool = false) -> Mesh:
	return TargetMaterials.mesh(path, bush)


# --- Platzieren ----------------------------------------------------------------------------

func _multimesh(mesh: Mesh, transforms: Array, name: String, shadows: bool = true) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = name
	inst.multimesh = mm
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _place_trees(entries: Array, name: String) -> void:
	var by_file := {}
	for entry in entries:
		var kind: int = entry[1]
		var xform: Transform3D = entry[0]
		var files: Array = TREES[kind]
		var file: String = files[int(absf(xform.origin.x * 7.31 + xform.origin.z * 3.17)) % files.size()]
		if not by_file.has(file):
			by_file[file] = []
		by_file[file].append(xform)
	for file in by_file:
		_multimesh(_mesh(T + "trees/" + file + ".glb"), by_file[file], name + "_" + file)
	counts[name] = entries.size()


func _place_simple(transforms: Array, files: Array, name: String, bush: bool) -> void:
	var lists := []
	for f in files:
		lists.append([])
	for i in transforms.size():
		lists[i % files.size()].append(transforms[i])
	for k in files.size():
		_multimesh(_mesh(files[k], bush), lists[k], "%s_%d" % [name, k])
	counts[name] = transforms.size()


## Gras/Blumen: Karten aus drei gekreuzten Flächen; Atlaszelle und Trockenheit je Instanz.
func _place_cards(entries: Array, atlas: Texture2D, height: float, width: float, name: String, flowers: bool) -> void:
	if atlas == null:
		push_warning("Atlas fehlt für " + name)
		return
	var mesh := TargetMaterials.tuft_mesh(width, height, atlas, flowers)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = entries.size()
	var rng := FixedRandom.rng_of(FixedRandom.derive(TargetLandscape.SEED, name + " Farbe"))
	for i in entries.size():
		var e: Array = entries[i]
		mm.set_instance_transform(i, e[0])
		var dry: float = e[2] if e.size() > 2 else 0.0
		mm.set_instance_custom_data(i, Color(float(e[1]) / 8.0, dry, rng.randf(), 0.0))
	var inst := MultiMeshInstance3D.new()
	inst.name = name
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	counts[name] = entries.size()


# --- Messen --------------------------------------------------------------------------------

func _run_bench(args: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 90:
		await get_tree().process_frame
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in 240:
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
		"view": view,
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(get_viewport().get_visible_rect().size),
		"fps_avg": 1000.0 / (total / times.size()),
		"frame_ms_avg": total / times.size(),
		"frame_ms_p95": sorted[int(sorted.size() * 0.95)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"build_ms": build_ms,
		"counts": counts,
	}
	if args.has("bench"):
		var file := FileAccess.open(args["bench"], FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	if args.has("screenshot"):
		$Interface.visible = false
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path: String = args["screenshot"]
		if path.ends_with(".jpg"):
			image.save_jpg(path, 0.9)
		else:
			image.save_png(path)
	print(JSON.stringify(result))
	get_tree().quit()
