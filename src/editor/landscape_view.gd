class_name LandscapeView
extends Node3D
## Zeigt einen Ausschnitt (TerrainWindow) als Landschaft und nimmt Pinselstriche entgegen.
##
## Jeder Ausschnitt wird auf 1000 × 1000 Darstellungseinheiten gebracht; grobe Ausschnitte
## werden in der Höhe überhöht (nur Darstellung, Annahme A4). Für die Kamera liefert der Knoten
## height_at, raycast und world_rect in Darstellungseinheiten.

signal stroke_finished(stroke: Dictionary)
signal hover_changed(x: float, y: float, valid: bool)
## Kurzer Hinweis für die Statuszeile (z. B. warum etwas nicht angelegt wurde).
signal hint(text: String)

const PLANE := 1000.0
const SHADER := preload("res://src/editor/landscape.gdshader")
const DETAIL_SHADER := preload("res://src/editor/landscape_detail.gdshader")
const WATER_SHADER := preload("res://src/world/water.gdshader")
const CLEAR_WATER_SHADER := preload("res://src/target/water_clear.gdshader")
## Bäume als einzelne Modelle erst ab diesem Ausschnitt (m) – darüber zeigt die Farbe den Wald.
const TREES_BELOW := 1700.0
## Ab hier Aussehen wie das Zielbild (Fototexturen, klares Wasser).
const DETAIL_BELOW := 4200.0
## Ab hier echte Bäume, Felsen, Büsche, Gras und Blumen im Zielstil.
const DETAILED_TREES_BELOW := 620.0


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
var tool := "navigate":
	set(value):
		tool = value
		_cancel_line()
		if _material and value == "navigate":
			_material.set_shader_parameter("brush", Vector3(0.0, 0.0, -1.0))
var brush_radius_m := 100.0
var brush_strength := 1.0
## Ausgangswert für die nächste erzeugende Bearbeitung (vom Editor fest abgeleitet).
var generator_seed := 0
## Ausgangswert der Grundform (für Schutzbereiche: diese Grundform bleibt dort erhalten).
var continent_seed := 0
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
## Linienwerkzeuge (Umriss, Fluss): gesammelte Punkte in Kontinentmetern und Vorschau.
var _line := PackedVector2Array()
var _drawing_line := false
var _line_preview: MeshInstance3D
var _lin_texture: ImageTexture


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
	var broad := TargetMaterials.texture(TargetMaterials.T + "canopy_broadleaf.jpg")
	var needles := TargetMaterials.texture(TargetMaterials.T + "canopy_conifer.jpg")
	for m in [_coarse_material, _detail_material]:
		m.set_shader_parameter("canopy_broadleaf", broad)
		m.set_shader_parameter("canopy_conifer", needles)
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

	_line_preview = MeshInstance3D.new()
	_line_preview.name = "LinePreview"
	_line_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(1.0, 0.82, 0.45)
	line_material.no_depth_test = true
	line_material.render_priority = 10
	_line_preview.material_override = line_material
	add_child(_line_preview)


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
	_material.set_shader_parameter("meadow_origin", Vector2(w.cx, -w.cy))
	_material.set_shader_parameter("meadow_scale", units_per_m)
	_material.set_shader_parameter("conifer_bias", 1.0 - smoothstep(1400.0, 2600.0, w.climate.get("treeline", 2500.0)))
	if detail:
		_detail_material.set_shader_parameter("canopy", 1.0 if w.size > TREES_BELOW else 0.0)
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

## Läuft gerade ein Strich oder eine Linie? (Dann kein Rückgängig und kein Maßstabswechsel.)
func is_busy() -> bool:
	return _painting or _drawing_line


static func is_line_tool(t: String) -> bool:
	return t in ["shape_add", "shape_remove", "river"]


func _unhandled_input(event: InputEvent) -> void:
	if window == null or not visible:
		return
	if event is InputEventMouseMotion:
		var hit: Variant = _hit((event as InputEventMouseMotion).position)
		_update_brush(hit)
		if hit == null:
			return
		if _painting:
			_continue_stroke(hit)
			get_viewport().set_input_as_handled()
		elif _drawing_line:
			_continue_line(hit)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if tool == "navigate":
			return
		if button.pressed:
			var hit: Variant = _hit(button.position)
			if hit == null:
				return
			if is_line_tool(tool):
				_start_line(hit)
			elif tool == "lake":
				_place_lake(hit)
			else:
				_start_stroke(hit)
			get_viewport().set_input_as_handled()
		elif _painting:
			_finish_stroke()
			get_viewport().set_input_as_handled()
		elif _drawing_line:
			_finish_line()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE and _drawing_line:
		_cancel_line()
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
	# Umriss-Werkzeuge: nur ein kleiner Punkt als Zeiger; sonst der Pinselkreis in echter Größe.
	var r := brush_radius_m * units_per_m
	if tool in ["shape_add", "shape_remove"]:
		r = PLANE * 0.004
	_material.set_shader_parameter("brush", Vector3(p.x, p.z, r))
	hover_changed.emit(continent_x(p), continent_y(p), true)


func _start_stroke(hit: Vector3) -> void:
	var x := continent_x(hit)
	var y := continent_y(hit)
	match tool:
		"gen_mountains", "gen_hills", "gen_forest", "gen_islands":
			_stroke = Stroke.create_generated(tool, brush_radius_m, brush_strength, generator_seed)
		"protect":
			_stroke = Stroke.create_generated("protect", brush_radius_m, 1.0, continent_seed)
		"flatten":
			_stroke = Stroke.create("flatten", brush_radius_m, 0.9)
			_stroke["level"] = maxf(window.height_at(x, y), 0.5)
		_:
			_stroke = Stroke.create(tool, brush_radius_m, brush_strength)
	_peak.resize(window.res * window.res)
	_peak.fill(0.0)
	_painting = true
	Stroke.add_point(_stroke, x, y)
	_apply_new_dabs(0)


# --- Linien: Umriss und Fluss ----------------------------------------------------------------

func _start_line(hit: Vector3) -> void:
	_line = PackedVector2Array([to_continent(hit)])
	_drawing_line = true
	_draw_line_preview()


func _continue_line(hit: Vector3) -> void:
	var p := to_continent(hit)
	if p.distance_to(_line[_line.size() - 1]) >= window.size * 0.004:
		_line.append(p)
		_draw_line_preview()


func _cancel_line() -> void:
	_drawing_line = false
	_line = PackedVector2Array()
	if _line_preview:
		_line_preview.mesh = null


func _finish_line() -> void:
	var line := _line
	var t := tool
	_cancel_line()
	if t == "river":
		if line.size() < 2:
			return
		stroke_finished.emit(make_river(window, line, brush_radius_m))
		return
	if line.size() < 3:
		return
	# Rand: sichtbar weich, aber im Verhältnis zum Ausschnitt schmal.
	var edge := maxf(window.size * 0.012, window.cell * 1.5)
	stroke_finished.emit(Stroke.create_shape(t == "shape_add", line, edge))


## Fluss aus einem gezogenen Linienzug: Er fließt vom höheren zum tieferen Ende; der Spiegel
## liegt knapp unter dem Gelände und steigt flussabwärts nie an (Stroke.create_river).
static func make_river(w: TerrainWindow, line: PackedVector2Array, half_width: float) -> Dictionary:
	var path := line
	if w.height_at(path[0].x, path[0].y) < w.height_at(path[path.size() - 1].x, path[path.size() - 1].y):
		path.reverse()
	var depth := clampf(half_width * 0.15, 0.8, 25.0)
	var levels := PackedFloat32Array()
	for p in path:
		levels.append(w.height_at(p.x, p.y) - minf(depth * 0.4, 3.0))
	return Stroke.create_river(path, levels, half_width, depth)


## See: Spiegel knapp unter dem niedrigsten Ufer – so schwebt kein Wasser am Hang.
func _place_lake(hit: Vector3) -> void:
	var c := to_continent(hit)
	var lake := make_lake(window, c, brush_radius_m)
	if lake.is_empty():
		hint.emit("Kein See angelegt: Das Ufer läge auf Meereshöhe – weiter landeinwärts setzen oder kleiner wählen.")
		return
	stroke_finished.emit(lake)


static func make_lake(w: TerrainWindow, c: Vector2, radius: float) -> Dictionary:
	var rim := INF
	for k in 32:
		var a := TAU * k / 32.0
		var q := c + Vector2(cos(a), sin(a)) * radius * 1.1
		rim = minf(rim, w.height_at(q.x, q.y))
	var level := rim - 0.3
	if level < 0.5:
		# Das niedrigste Ufer liegt am Meer: Der Spiegel läge über dem Ufer und das Wasser schwebte.
		return {}
	var depth := clampf(radius * 0.04, 2.0, 80.0)
	var lake := Stroke.create_lake(radius, level, depth)
	Stroke.add_point(lake, c.x, c.y)
	return lake


func _draw_line_preview() -> void:
	var mesh := ImmediateMesh.new()
	if _line.size() >= 2:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in _line:
			mesh.surface_add_vertex(_line_point(p))
		if tool in ["shape_add", "shape_remove"]:
			mesh.surface_add_vertex(_line_point(_line[0]))
		mesh.surface_end()
	_line_preview.mesh = mesh if _line.size() >= 2 else null


func _line_point(p: Vector2) -> Vector3:
	var h := maxf(window.height_at(p.x, p.y), maxf(window.water_level_at(p.x, p.y), 0.0))
	return Vector3((p.x - window.cx) * units_per_m, h * height_scale + 0.6, -(p.y - window.cy) * units_per_m)


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
	_material.set_shader_parameter("data_lin", _texture)
	# Grenzen für die Sichtbarkeitsprüfung (das Gitter wird erst im Shader gehoben).
	var low := 0.0
	var high := 0.0
	for k in n:
		low = minf(low, h[k])
		high = maxf(high, h[k])
	_ground.custom_aabb = AABB(Vector3(-PLANE * 0.5, low * height_scale - 1.0, -PLANE * 0.5),
		Vector3(PLANE, (high - low) * height_scale + 2.0, PLANE))


## Umgebung neu zeigen (nach einer Bearbeitung, die über den Ausschnitt hinausreicht).
func update_context(parent: TerrainWindow) -> void:
	_show_context(parent)


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
	_context_material.set_shader_parameter("data_lin", _context_texture)
	_context_material.set_shader_parameter("res", parent.res)
	_context_material.set_shader_parameter("plane_size", PLANE)
	_context_material.set_shader_parameter("height_scale", height_scale)
	_context_material.set_shader_parameter("snowline", parent.climate["snowline"])
	_context_material.set_shader_parameter("treeline", parent.climate["treeline"])
	_context_material.set_shader_parameter("dryness", parent.climate["dryness"])
	_context_material.set_shader_parameter("canopy", 1.0)
	_context_material.set_shader_parameter("meadow_origin", Vector2(window.cx, -window.cy))
	_context_material.set_shader_parameter("meadow_scale", units_per_m)
	_context_material.set_shader_parameter("conifer_bias", 1.0 - smoothstep(1400.0, 2600.0, parent.climate.get("treeline", 2500.0)))
	_context_material.set_shader_parameter("canopy_broadleaf", TargetMaterials.texture(TargetMaterials.T + "canopy_broadleaf.jpg"))
	_context_material.set_shader_parameter("canopy_conifer", TargetMaterials.texture(TargetMaterials.T + "canopy_conifer.jpg"))
	var half := PLANE * 0.5 - 0.5
	_context_material.set_shader_parameter("hole", Vector4(-half, -half, half, half))
	var high := 0.0
	for h in parent.height:
		high = maxf(high, h)
	_context.custom_aabb = AABB(Vector3(-PLANE * 0.5, -2000.0 * height_scale, -PLANE * 0.5),
		Vector3(PLANE, (high + 2000.0) * height_scale + 2.0, PLANE))
	_context.visible = true


## Datentextur: R Höhe (m), G Wald, B Bearbeitungsmarke + 2 wo geschützt, A Tiefe eines
## Binnengewässers (m über dem Grund; 0 = keins).
static func _data_image(w: TerrainWindow) -> Image:
	var n := w.res * w.res
	var data := PackedFloat32Array()
	data.resize(n * 4)
	var h := w.height
	var f := w.forest
	var m := w.edit_marks
	var p := w.protect
	var lvl := w.water_level
	for k in n:
		data[k * 4] = h[k]
		data[k * 4 + 1] = f[k]
		data[k * 4 + 2] = m[k] + (2.0 if p[k] > 0.5 else 0.0)
		data[k * 4 + 3] = maxf(lvl[k] - h[k], 0.0) if lvl[k] > 0.0 else 0.0
	return Image.create_from_data(w.res, w.res, false, Image.FORMAT_RGBAF, data.to_byte_array())


func _rebuild_field() -> void:
	var field := Heightfield.new(window.res, window.res, PLANE / float(window.res - 1))
	var heights := field.heights
	var h := window.height
	var lvl := window.water_level
	for k in window.res * window.res:
		# Seen und Flüsse zählen als Boden (man malt auf der Wasserfläche).
		heights[k] = maxf(h[k], lvl[k]) * height_scale
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
	var spacing := 5.0 if detailed else (9.0 if window.size <= 1000.0 else 12.0)
	var seed_value: int = sampler.continent.get("scatter_seed", sampler.continent["seed"])
	var treeline: float = window.climate.get("treeline", 2500.0)
	# Kälteres Klima: mehr Nadelbäume (Hinweis aus dem Klima, kein Zwang).
	var cold := 1.0 - smoothstep(1400.0, 2600.0, treeline)
	var half := window.size * 0.5
	var gx0 := int(floor((window.cx - half) / spacing))
	var gx1 := int(ceil((window.cx + half) / spacing))
	var gy0 := int(floor((window.cy - half) / spacing))
	var gy1 := int(ceil((window.cy + half) / spacing))
	var groups := {}
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
			if h < 1.0 or window.water_level_at(x, y) > h:
				continue
			var conifer_share := clampf(0.12 + smoothstep(300.0, 1400.0, h) * 0.8 + cold * 0.5, 0.0, 0.95)
			var conifer := _hash01(gx, gy, seed_value, 7) < conifer_share
			var pick := _hash01(gx, gy, seed_value, 5)
			var file: String
			var variant := ""
			var size := 1.0
			if detailed:
				if conifer:
					file = TargetMaterials.TREES["spruce"][int(pick * 3.0) % 3]
					size = 0.8 + 0.45 * _hash01(gx, gy, seed_value, 4)
				elif f < 0.45 and pick < 0.45:
					# Am Waldrand und in lockerem Bestand: junge Bäume.
					file = TargetMaterials.TREES["young"][int(pick * 20.0) % 2]
					size = 0.8 + 0.5 * _hash01(gx, gy, seed_value, 4)
				else:
					var broad: Array = TargetMaterials.TREES["oak"] + TargetMaterials.TREES["beech"]
					file = broad[int(pick * broad.size()) % broad.size()]
					size = 0.75 + 0.55 * _hash01(gx, gy, seed_value, 4)
				variant = "deep" if _hash01(gx, gy, seed_value, 8) < 0.35 else ""
			else:
				file = (["spruce_3", "spruce_1"] if conifer else TargetMaterials.TREES["far"])[int(pick * 6.0) % (2 if conifer else 3)]
				size = 0.8 + 0.5 * _hash01(gx, gy, seed_value, 4)
			# Farbstreuung je Baum: Helligkeit und ein Hauch Gelb oder Blau.
			var light := 0.84 + 0.26 * _hash01(gx, gy, seed_value, 9)
			var warm := _hash01(gx, gy, seed_value, 10) - 0.5
			var tint := Color(0.5 * light * (1.0 + warm * 0.14), 0.5 * light * (1.0 + warm * 0.05), 0.5 * light * (1.0 - warm * 0.16), 1.0)
			var s := size * units_per_m
			var basis := Basis(Vector3.UP, _hash01(gx, gy, seed_value, 6) * TAU).scaled(Vector3(s, s * (0.92 + 0.16 * pick), s))
			var pos := Vector3((x - window.cx) * units_per_m, h * height_scale - 0.25 * units_per_m, -(y - window.cy) * units_per_m)
			var key := file + "|" + variant
			if not groups.has(key):
				groups[key] = [[], []]
			groups[key][0].append(Transform3D(basis, pos))
			groups[key][1].append(tint)
	for key in groups:
		var parts: PackedStringArray = (key as String).split("|")
		var mesh := TargetMaterials.tree_mesh(parts[0], parts[1])
		if mesh == null:
			continue
		var list: Array = groups[key][0]
		var tints: Array = groups[key][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, tints[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		_trees.add_child(inst)

# --- Beiwerk im feinsten Ausschnitt ----------------------------------------------------------

## Felsen am Ufer und an Steilstellen, Büsche, Gras und Blumen – fest je Weltzelle.
func _build_details() -> void:
	for child in _details.get_children():
		child.queue_free()
	if window.size > DETAILED_TREES_BELOW:
		return
	var seed_value: int = sampler.continent.get("scatter_seed", sampler.continent["seed"])
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

	# Gras und Blumen: dicht auf offener Wiese, nicht im Wald, nicht im Wasser. Zeilenweise auf allen
	# Kernen; jede Zeile schreibt fertige MultiMesh-Daten (fest je Weltzelle, gleiche Reihenfolge).
	var cards := _scan_cards(0.72, 21, seed_value)
	_add_card_buffer(cards[0], cards[1], TargetMaterials.texture(TargetMaterials.T + "grass_atlas.png"), 0.6, 1.1, false)
	_add_card_buffer(cards[2], cards[3], TargetMaterials.texture(TargetMaterials.T + "flower_atlas.png"), 0.6, 0.55, true)


## Gras- und Blumenkarten als MultiMesh-Puffer: [Gras, Anzahl, Blumen, Anzahl].
## Je Karte 16 Zahlen: Lage (3 × 4) und Zusatzdaten (Atlasfeld, –, Phase, –).
func _scan_cards(spacing: float, salt: int, seed_value: int) -> Array:
	var half := window.size * 0.5
	var gy0 := int(floor((window.cy - half) / spacing))
	var gy1 := int(ceil((window.cy + half) / spacing))
	var gx0 := int(floor((window.cx - half) / spacing))
	var gx1 := int(ceil((window.cx + half) / spacing))
	var rows := []
	rows.resize(gy1 - gy0 + 1)
	var u := units_per_m
	var w := window
	var hs := height_scale
	var mutex := Mutex.new()
	var job := func(r: int) -> void:
		var gy := gy0 + r
		var grass := PackedFloat32Array()
		var flowers := PackedFloat32Array()
		for gx in range(gx0, gx1 + 1):
			var x := (gx + _hash01(gx, gy, seed_value, salt)) * spacing
			var y := (gy + _hash01(gx, gy, seed_value, salt + 1)) * spacing
			if not w.contains(x, y):
				continue
			var h := w.height_at(x, y)
			# Zum Ufer und zum Waldrand hin lichter statt mit harter Kante.
			var edge := _hash01(gx, gy, seed_value, 26)
			if h < 0.7 + 1.6 * edge or w.forest_at(x, y) > 0.2 + 0.35 * (1.0 - edge):
				continue
			var k := _hash01(gx, gy, seed_value, 22)
			var s := u * (0.95 + 0.65 * _hash01(gx, gy, seed_value, 23))
			var b := Basis(Vector3.UP, k * 97.0).scaled(Vector3(s, s, s))
			var o := Vector3((x - w.cx) * u, h * hs - 0.02 * u, -(y - w.cy) * u)
			var cell := 0.0
			var target := grass
			if k < 0.045:
				cell = float(int(_hash01(gx, gy, seed_value, 24) * 8.0)) / 8.0
				target = flowers
			else:
				cell = float(int(k * 8.0) % 8) / 8.0
			target.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
				cell, 0.0, _hash01(gx, gy, seed_value, 25), 0.0])
			if k < 0.045:
				flowers = target
			else:
				grass = target
		mutex.lock()
		rows[r] = [grass, flowers]
		mutex.unlock()
	var task := WorkerThreadPool.add_group_task(job, rows.size(), -1, true, "Weltwerk Gras")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var all_grass := PackedFloat32Array()
	var all_flowers := PackedFloat32Array()
	for row in rows:
		all_grass.append_array(row[0])
		all_flowers.append_array(row[1])
	return [all_grass, all_grass.size() / 16, all_flowers, all_flowers.size() / 16]


func _add_card_buffer(buffer: PackedFloat32Array, count: int, atlas: Texture2D, height: float, width: float, flowers: bool) -> void:
	if atlas == null or count == 0:
		return
	var mesh := TargetMaterials.tuft_mesh(width, height, atlas, flowers)
	var material := mesh.surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("meadow_origin", Vector2(window.cx, -window.cy))
	material.set_shader_parameter("meadow_scale", units_per_m)
	material.set_shader_parameter("fade_start", 230.0)
	material.set_shader_parameter("fade_end", 340.0)
	material.set_shader_parameter("calm_start", 60.0)
	material.set_shader_parameter("calm_end", 200.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buffer
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_details.add_child(inst)

## Geht ein Weltgitter (Abstand spacing in m) im Ausschnitt durch; Punkt je Zelle fest verschoben.
func _scan(spacing: float, salt: int, visit: Callable) -> void:
	var seed_value: int = sampler.continent.get("scatter_seed", sampler.continent["seed"])
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
