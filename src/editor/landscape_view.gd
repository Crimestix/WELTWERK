class_name LandscapeView
extends Node3D
## Zeigt einen Ausschnitt (TerrainWindow) als Landschaft und nimmt Pinselstriche entgegen.
##
## Jeder Ausschnitt wird auf 1000 × 1000 Darstellungseinheiten gebracht; grobe Ausschnitte
## werden in der Höhe überhöht (nur Darstellung, Annahme A4). Für die Kamera liefert der Knoten
## height_at, raycast und world_rect in Darstellungseinheiten.

signal stroke_finished(stroke: Dictionary)
signal hover_changed(x: float, y: float, valid: bool)

const PLANE := 1000.0
const SHADER := preload("res://src/editor/landscape.gdshader")
const DETAIL_SHADER := preload("res://src/editor/landscape_detail.gdshader")
const WATER_SHADER := preload("res://src/world/water.gdshader")
const CLEAR_WATER_SHADER := preload("res://src/target/water_clear.gdshader")
const FOLIAGE_SHADER := preload("res://src/style_test/foliage.gdshader")
## Bäume als einzelne Modelle erst ab diesem Ausschnitt (m) – darüber zeigt die Farbe den Wald.
const TREES_BELOW := 3500.0
## Ab hier Aussehen wie das Zielbild (Fototexturen, klares Wasser).
const DETAIL_BELOW := 3600.0
## Ab hier echte Bäume, Felsen, Büsche, Gras und Blumen im Zielstil.
const DETAILED_TREES_BELOW := 450.0


## Überhöhung je Ausschnittgröße (nur Darstellung): 1 im Detail, bis 8 auf Kontinentebene.
static func exaggeration_for(size_m: float) -> float:
	return clampf(0.8 * pow(size_m / 2000.0, 0.4), 1.0, 8.0)

var window: TerrainWindow
var sampler: TerrainSampler
var units_per_m := 1.0
var exaggeration := 1.0
var height_scale := 1.0
var camera: Camera3D

## Aktives Werkzeug ("navigate" oder ein Stroke.TOOLS-Eintrag) und Pinsel in Metern.
var tool := "navigate"
var brush_radius_m := 100.0
var brush_strength := 1.0
var show_marks := true:
	set(value):
		show_marks = value
		if _material:
			_material.set_shader_parameter("show_marks", value)

var _ground: MeshInstance3D
var _material: ShaderMaterial
var _coarse_material: ShaderMaterial
var _detail_material: ShaderMaterial
var _water_material: ShaderMaterial
var _clear_water_material: ShaderMaterial
var _context: MeshInstance3D
var _context_material: ShaderMaterial
var _context_texture: ImageTexture
var _water: MeshInstance3D
var _trees: Node3D
var _details: Node3D
var _frames: MeshInstance3D
var _field: Heightfield
var _texture: ImageTexture
var _mesh_res := 0
var _stroke := {}
var _peak := PackedFloat32Array()
var _painting := false
var _tree_meshes: Array = []
var _blob_mesh: Mesh


func _ready() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_coarse_material = ShaderMaterial.new()
	_coarse_material.shader = SHADER
	_detail_material = ShaderMaterial.new()
	_detail_material.shader = DETAIL_SHADER
	var maps := {"grass": ["rocky_terrain_02", "diffuse"], "grass_normal": ["rocky_terrain_02", "nor_gl"],
		"meadow": ["aerial_grass_rock", "diffuse"], "rock": ["rock_boulder_dry", "diffuse"],
		"rock_normal": ["rock_boulder_dry", "nor_gl"], "bottom": ["river_small_rocks", "diffuse"],
		"forest": ["brown_mud_leaves_01", "diffuse"]}
	for slot in maps:
		var name: String = slot if slot.ends_with("normal") else slot + "_albedo"
		_detail_material.set_shader_parameter(name, TargetMaterials.polyhaven(maps[slot][0], maps[slot][1]))
	_material = _coarse_material
	_ground.material_override = _material

	_context = MeshInstance3D.new()
	_context.name = "Context"
	_context_material = ShaderMaterial.new()
	_context_material.shader = SHADER
	_context_material.set_shader_parameter("is_context", true)
	_context_material.set_shader_parameter("show_marks", false)
	_context.material_override = _context_material
	_context.visible = false
	add_child(_context)

	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLANE * 24.0, PLANE * 24.0)
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	# Tiefenverlauf in Darstellungseinheiten: kurz, damit Meer außerhalb des Ausschnitts gleich aussieht.
	_water_material.set_shader_parameter("depth_fade", 2.5)
	_clear_water_material = ShaderMaterial.new()
	_clear_water_material.shader = CLEAR_WATER_SHADER
	plane.material = _water_material
	_water.mesh = plane
	add_child(_water)

	_trees = Node3D.new()
	_trees.name = "Trees"
	add_child(_trees)
	_details = Node3D.new()
	_details.name = "Details"
	add_child(_details)

	_frames = MeshInstance3D.new()
	_frames.name = "RegionFrames"
	_frames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var frame_material := StandardMaterial3D.new()
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_material.albedo_color = Color(0.88, 0.70, 0.38)
	_frames.material_override = frame_material
	add_child(_frames)


## Zeigt einen Ausschnitt. regions: gemerkte vertiefte Ausschnitte (als Rahmen gezeigt).
## parent: der gröbere Ausschnitt darüber, als Umgebung gezeigt (oder null).
func show_window(w: TerrainWindow, p_sampler: TerrainSampler, regions: Array, parent: TerrainWindow = null) -> void:
	window = w
	sampler = p_sampler
	units_per_m = PLANE / w.size
	exaggeration = exaggeration_for(w.size)
	height_scale = units_per_m * exaggeration
	_show_context(parent)
	if _mesh_res != w.res:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(PLANE, PLANE)
		mesh.subdivide_width = w.res - 2
		mesh.subdivide_depth = w.res - 2
		_ground.mesh = mesh
		_mesh_res = w.res
		_texture = null
	var detail := w.size <= DETAIL_BELOW
	_material = _detail_material if detail else _coarse_material
	_ground.material_override = _material
	_upload()
	_material.set_shader_parameter("data_tex", _texture)
	if detail:
		_detail_material.set_shader_parameter("meadow_origin", Vector2(w.cx, -w.cy))
		_detail_material.set_shader_parameter("meadow_scale", units_per_m)
		# Wasser in Darstellungseinheiten: Tiefen und Schluckweg auf Meter umrechnen.
		_clear_water_material.set_shader_parameter("deep_depth", 7.0 * height_scale)
		_clear_water_material.set_shader_parameter("absorption", Vector3(0.42, 0.11, 0.07) / height_scale)
	(_water.mesh as PlaneMesh).material = _clear_water_material if detail else _water_material
	_material.set_shader_parameter("res", w.res)
	_material.set_shader_parameter("plane_size", PLANE)
	_material.set_shader_parameter("height_scale", height_scale)
	_material.set_shader_parameter("snowline", w.climate["snowline"])
	_material.set_shader_parameter("treeline", w.climate["treeline"])
	_material.set_shader_parameter("dryness", w.climate["dryness"])
	_material.set_shader_parameter("canopy", 0.0 if w.size <= TREES_BELOW else 1.0)
	_material.set_shader_parameter("show_marks", show_marks)
	_rebuild_field()
	_build_trees()
	_build_details()
	_build_frames(regions)


# --- Umrechnung ----------------------------------------------------------------------------

func to_continent(render_point: Vector3) -> Vector2:
	return Vector2(window.cx + render_point.x / units_per_m, window.cy - render_point.z / units_per_m)


func continent_x(render_point: Vector3) -> float:
	return window.cx + render_point.x / units_per_m


func continent_y(render_point: Vector3) -> float:
	return window.cy - render_point.z / units_per_m


func to_render(x: float, y: float) -> Vector3:
	var rx := (x - window.cx) * units_per_m
	var rz := -(y - window.cy) * units_per_m
	return Vector3(rx, maxf(window.height_at(x, y), 0.0) * height_scale, rz)


# --- Für die Kamera ------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return maxf(_field.height_at(x, z), 0.0) if _field else 0.0


func raycast(from: Vector3, direction: Vector3, max_distance: float = 5000.0) -> Variant:
	if _field == null:
		return null
	var hit: Variant = _field.raycast(from, direction, max_distance)
	# Wasseroberfläche zählt als Boden.
	if direction.y < 0.0 and from.y > 0.0:
		var t := -from.y / direction.y
		var on_water := from + direction * t
		if hit == null or (hit as Vector3).y < 0.0:
			return on_water
	return hit


func world_rect() -> Rect2:
	return Rect2(-PLANE * 0.5, -PLANE * 0.5, PLANE, PLANE)


# --- Malen ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if window == null or not visible:
		return
	if event is InputEventMouseMotion:
		var hit: Variant = _hit((event as InputEventMouseMotion).position)
		_update_brush(hit)
		if _painting and hit != null:
			_continue_stroke(hit)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if tool == "navigate":
			return
		if button.pressed:
			var hit: Variant = _hit(button.position)
			if hit != null:
				_start_stroke(hit)
				get_viewport().set_input_as_handled()
		elif _painting:
			_finish_stroke()
			get_viewport().set_input_as_handled()


func _hit(screen_position: Vector2) -> Variant:
	if camera == null:
		return null
	return raycast(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position), 20000.0)


func _update_brush(hit: Variant) -> void:
	if hit == null or tool == "navigate":
		_material.set_shader_parameter("brush", Vector3(0.0, 0.0, -1.0))
		hover_changed.emit(0.0, 0.0, false)
		return
	var p: Vector3 = hit
	_material.set_shader_parameter("brush", Vector3(p.x, p.z, brush_radius_m * units_per_m))
	hover_changed.emit(continent_x(p), continent_y(p), true)


func _start_stroke(hit: Vector3) -> void:
	_stroke = Stroke.create(tool, brush_radius_m, brush_strength)
	_peak.resize(window.res * window.res)
	_peak.fill(0.0)
	_painting = true
	Stroke.add_point(_stroke, continent_x(hit), continent_y(hit))
	_apply_new_dabs(0)


func _continue_stroke(hit: Vector3) -> void:
	var before := Stroke.dab_count(_stroke)
	if Stroke.add_point(_stroke, continent_x(hit), continent_y(hit)) > 0:
		_apply_new_dabs(before)


func _apply_new_dabs(first: int) -> void:
	var result := sampler.apply_dabs(window, _stroke, first, _peak)
	_peak = result[1]
	var rect: Rect2i = result[0]
	if rect.size != Vector2i.ZERO:
		window.compose_rect(rect.position.x - 1, rect.position.y - 1, rect.end.x + 1, rect.end.y + 1)
		_upload()


func _finish_stroke() -> void:
	_painting = false
	_rebuild_field()
	_build_trees()
	_build_details()
	stroke_finished.emit(_stroke)
	_stroke = {}


# --- Aufbau --------------------------------------------------------------------------------

func _upload() -> void:
	var n := window.res * window.res
	var h := window.height
	var image := _data_image(window)
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
		_material.set_shader_parameter("data_tex", _texture)
	else:
		_texture.update(image)
	# Grenzen für die Sichtbarkeitsprüfung (das Gitter wird erst im Shader gehoben).
	var low := 0.0
	var high := 0.0
	for k in n:
		low = minf(low, h[k])
		high = maxf(high, h[k])
	_ground.custom_aabb = AABB(Vector3(-PLANE * 0.5, low * height_scale - 1.0, -PLANE * 0.5),
		Vector3(PLANE, (high - low) * height_scale + 2.0, PLANE))


## Gröberer Ausschnitt als Umgebung: gleiche Höhenskala wie der aktuelle, horizontal gestreckt,
## mit Loch, wo der aktuelle liegt. Grundstein für den späteren flüssigen Zoom.
func _show_context(parent: TerrainWindow) -> void:
	if parent == null:
		_context.visible = false
		return
	var factor := parent.size / window.size
	var mesh := _context.mesh as PlaneMesh
	if mesh == null or mesh.subdivide_width != parent.res - 2:
		mesh = PlaneMesh.new()
		mesh.size = Vector2(PLANE, PLANE)
		mesh.subdivide_width = parent.res - 2
		mesh.subdivide_depth = parent.res - 2
		_context.mesh = mesh
	_context.position = Vector3((parent.cx - window.cx) * units_per_m, -0.2, -(parent.cy - window.cy) * units_per_m)
	_context.scale = Vector3(factor, 1.0, factor)
	_context_texture = ImageTexture.create_from_image(_data_image(parent))
	_context_material.set_shader_parameter("data_tex", _context_texture)
	_context_material.set_shader_parameter("res", parent.res)
	_context_material.set_shader_parameter("plane_size", PLANE)
	_context_material.set_shader_parameter("height_scale", height_scale)
	_context_material.set_shader_parameter("snowline", parent.climate["snowline"])
	_context_material.set_shader_parameter("treeline", parent.climate["treeline"])
	_context_material.set_shader_parameter("dryness", parent.climate["dryness"])
	_context_material.set_shader_parameter("canopy", 1.0)
	var half := PLANE * 0.5 - 0.5
	_context_material.set_shader_parameter("hole", Vector4(-half, -half, half, half))
	var high := 0.0
	for h in parent.height:
		high = maxf(high, h)
	_context.custom_aabb = AABB(Vector3(-PLANE * 0.5, -2000.0 * height_scale, -PLANE * 0.5),
		Vector3(PLANE, (high + 2000.0) * height_scale + 2.0, PLANE))
	_context.visible = true


static func _data_image(w: TerrainWindow) -> Image:
	var n := w.res * w.res
	var data := PackedFloat32Array()
	data.resize(n * 3)
	var h := w.height
	var f := w.forest
	var m := w.edit_marks
	for k in n:
		data[k * 3] = h[k]
		data[k * 3 + 1] = f[k]
		data[k * 3 + 2] = m[k]
	return Image.create_from_data(w.res, w.res, false, Image.FORMAT_RGBF, data.to_byte_array())


func _rebuild_field() -> void:
	var field := Heightfield.new(window.res, window.res, PLANE / float(window.res - 1))
	var heights := field.heights
	var h := window.height
	for k in window.res * window.res:
		heights[k] = h[k] * height_scale
	field.heights = heights
	_field = field


func _build_frames(regions: Array) -> void:
	var mesh := ImmediateMesh.new()
	var any := false
	for r in regions:
		var size: float = r["size"]
		if size >= window.size * 0.99 or size < window.size / 70.0:
			continue
		var cx: float = r["cx"]
		var cy: float = r["cy"]
		if absf(cx - window.cx) > window.size * 0.5 + size or absf(cy - window.cy) > window.size * 0.5 + size:
			continue
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for c in 4:
			for s in 33:
				var t := s / 32.0
				var p: Vector2 = (corners[c] as Vector2).lerp(corners[c + 1], t) * size * 0.5
				var rp := to_render(cx + p.x, cy + p.y)
				mesh.surface_add_vertex(rp + Vector3(0.0, 1.5, 0.0))
		mesh.surface_end()
		any = true
	_frames.mesh = mesh if any else null


func _build_trees() -> void:
	for child in _trees.get_children():
		child.queue_free()
	if window.size > TREES_BELOW:
		return
	var detailed := window.size <= DETAILED_TREES_BELOW
	var spacing := 5.0 if detailed else (9.0 if window.size <= 2200.0 else 12.0)
	var options := _tree_options(detailed)
	var seed_value: int = sampler.continent["seed"]
	var half := window.size * 0.5
	var gx0 := int(floor((window.cx - half) / spacing))
	var gx1 := int(ceil((window.cx + half) / spacing))
	var gy0 := int(floor((window.cy - half) / spacing))
	var gy1 := int(ceil((window.cy + half) / spacing))
	var per_option: Array = []
	for o in options.size():
		per_option.append([])
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			# Fest je Weltzelle: In jedem Ausschnitt steht derselbe Baum am selben Ort.
			var x := (gx + _hash01(gx, gy, seed_value, 1)) * spacing
			var y := (gy + _hash01(gx, gy, seed_value, 2)) * spacing
			if not window.contains(x, y):
				continue
			var f := window.forest_at(x, y)
			if f <= 0.02 or _hash01(gx, gy, seed_value, 3) > f * 0.9:
				continue
			var h := window.height_at(x, y)
			if h < 1.0:
				continue
			var pick := int(_hash01(gx, gy, seed_value, 5) * options.size()) % options.size()
			var s: float
			var sink: float
			if detailed:
				# Zielbäume in echter Größe (10–12 m), leicht gestreut.
				s = units_per_m * (0.85 + 0.35 * _hash01(gx, gy, seed_value, 4))
				sink = 0.25 * units_per_m
			else:
				s = (9.0 + 7.0 * _hash01(gx, gy, seed_value, 4)) * units_per_m
				sink = 0.3 * s
			var basis := Basis(Vector3.UP, _hash01(gx, gy, seed_value, 6) * TAU).scaled(Vector3(s, s, s))
			var pos := Vector3((x - window.cx) * units_per_m, h * height_scale - sink, -(y - window.cy) * units_per_m)
			per_option[pick].append(Transform3D(basis, pos))
	for o in options.size():
		var list: Array = per_option[o]
		if list.is_empty():
			continue
		for part in options[o]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, (list[i] as Transform3D) * (part[1] as Transform3D))
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			_trees.add_child(inst)


## Baumformen, je als Liste von [Netz, Lage], auf Höhe 1 gebracht (Skalierung = Baumhöhe).
func _tree_options(detailed: bool) -> Array:
	if not detailed:
		if _blob_mesh == null:
			var sphere := SphereMesh.new()
			sphere.radius = 0.32
			sphere.height = 0.55
			sphere.radial_segments = 8
			sphere.rings = 4
			var m := ShaderMaterial.new()
			m.shader = FOLIAGE_SHADER
			m.set_shader_parameter("color_scale", Vector3(0.16, 0.30, 0.08))
			m.set_shader_parameter("wind_strength", 0.0)
			sphere.material = m
			_blob_mesh = sphere
		return [[[_blob_mesh, Transform3D(Basis(), Vector3(0.0, 0.62, 0.0))]]]
	if _tree_meshes.is_empty():
		# Zielbäume (Eiche häufiger), echte Größe in Metern.
		for file in ["oak_1", "oak_2", "oak_3", "beech_1", "beech_2", "young_1", "oak_1"]:
			var mesh := TargetMaterials.tree_mesh(file)
			if mesh:
				_tree_meshes.append([[mesh, Transform3D()]])
	return _tree_meshes


# --- Beiwerk im feinsten Ausschnitt ----------------------------------------------------------

## Felsen am Ufer und an Steilstellen, Büsche, Gras und Blumen – fest je Weltzelle.
func _build_details() -> void:
	for child in _details.get_children():
		child.queue_free()
	if window.size > DETAILED_TREES_BELOW:
		return
	var seed_value: int = sampler.continent["seed"]
	var u := units_per_m
	var rocks := [[], []]
	var bushes := [[], [], []]
	_scan(6.0, 11, func(gx: int, gy: int, x: float, y: float, h: float) -> void:
		var near_water := minf(minf(window.height_at(x + 5.0, y), window.height_at(x - 5.0, y)),
			minf(window.height_at(x, y + 5.0), window.height_at(x, y - 5.0))) < -0.3
		var steep := absf(window.height_at(x + 3.0, y) - window.height_at(x - 3.0, y)) > 5.0
		var r := _hash01(gx, gy, seed_value, 12)
		if (near_water and h > -1.2 and h < 1.8 and r < 0.55) or (steep and r < 0.12):
			var s := u * (1.2 + 2.2 * _hash01(gx, gy, seed_value, 13))
			var basis := Basis(Vector3.UP, _hash01(gx, gy, seed_value, 14) * TAU).scaled(Vector3(s * 1.6, s, s * 1.3))
			rocks[int(r * 20.0) % 2].append(Transform3D(basis, _render(x, y, h) - Vector3(0.0, 0.35 * s, 0.0)))
		elif h > 0.8 and r > 0.93 and window.forest_at(x, y) < 0.6:
			var b := u * (1.2 + 1.2 * _hash01(gx, gy, seed_value, 15))
			var basis := Basis(Vector3.UP, r * 97.0).scaled(Vector3(b, b, b))
			bushes[int(r * 300.0) % 3].append(Transform3D(basis, _render(x, y, h)))
	)
	for k in 2:
		_add_multimesh(_details, TargetMaterials.rock_mesh(TargetMaterials.ROCKS[k]), rocks[k], true)
	for k in 3:
		_add_multimesh(_details, TargetMaterials.bush_mesh(TargetMaterials.BUSHES[k]), bushes[k], true)

	# Gras und Blumen: dicht auf offener Wiese, nicht im Wald, nicht im Wasser.
	var grass := []
	var flowers := []
	_scan(0.85, 21, func(gx: int, gy: int, x: float, y: float, h: float) -> void:
		if h < 0.7 or window.forest_at(x, y) > 0.45:
			return
		var r := _hash01(gx, gy, seed_value, 22)
		var s := u * (1.3 + 0.9 * _hash01(gx, gy, seed_value, 23))
		var basis := Basis(Vector3.UP, r * 97.0).scaled(Vector3(s, s, s))
		var xform := Transform3D(basis, _render(x, y, h) - Vector3(0.0, 0.02 * u, 0.0))
		if r < 0.045:
			flowers.append([xform, int(_hash01(gx, gy, seed_value, 24) * 8.0)])
		else:
			grass.append([xform, int(r * 8.0) % 8])
	)
	_add_cards(grass, TargetMaterials.texture(TargetMaterials.T + "grass_atlas.png"), 0.6, 1.1, false)
	_add_cards(flowers, TargetMaterials.texture(TargetMaterials.T + "flower_atlas.png"), 0.6, 0.55, true)


## Geht ein Weltgitter (Abstand spacing in m) im Ausschnitt durch; Punkt je Zelle fest verschoben.
func _scan(spacing: float, salt: int, visit: Callable) -> void:
	var seed_value: int = sampler.continent["seed"]
	var half := window.size * 0.5
	for gy in range(int(floor((window.cy - half) / spacing)), int(ceil((window.cy + half) / spacing)) + 1):
		for gx in range(int(floor((window.cx - half) / spacing)), int(ceil((window.cx + half) / spacing)) + 1):
			var x := (gx + _hash01(gx, gy, seed_value, salt)) * spacing
			var y := (gy + _hash01(gx, gy, seed_value, salt + 1)) * spacing
			if window.contains(x, y):
				visit.call(gx, gy, x, y, window.height_at(x, y))


func _render(x: float, y: float, h: float) -> Vector3:
	return Vector3((x - window.cx) * units_per_m, h * height_scale, -(y - window.cy) * units_per_m)


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array, shadows: bool) -> void:
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


func _add_cards(entries: Array, atlas: Texture2D, height: float, width: float, flowers: bool) -> void:
	if atlas == null or entries.is_empty():
		return
	var mesh := TargetMaterials.tuft_mesh(width, height, atlas, flowers)
	var material := mesh.surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("meadow_origin", Vector2(window.cx, -window.cy))
	material.set_shader_parameter("meadow_scale", units_per_m)
	material.set_shader_parameter("fade_start", 280.0)
	material.set_shader_parameter("fade_end", 420.0)
	material.set_shader_parameter("calm_start", 60.0)
	material.set_shader_parameter("calm_end", 240.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = entries.size()
	for i in entries.size():
		mm.set_instance_transform(i, entries[i][0])
		mm.set_instance_custom_data(i, Color(float(entries[i][1]) / 8.0, 0.0, float(i % 97) / 97.0, 0.0))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_details.add_child(inst)


static func _hash01(gx: int, gy: int, seed_value: int, salt: int) -> float:
	var h := (gx * 73856093) ^ (gy * 19349663) ^ (seed_value * 83492791) ^ (salt * 2654435761)
	h &= 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0
