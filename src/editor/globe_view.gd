class_name GlobeView
extends Node3D
## Der Globus mit allen Kontinenten.
##
## Klick wählt einen Kontinent, Ziehen auf dem gewählten verschiebt ihn (Breite/Länge),
## Ziehen daneben dreht den Globus, Doppelklick öffnet. Mausrad zoomt; am Anschlag weiter
## hineinzoomen öffnet den gewählten Kontinent.

signal continent_clicked(id: String)
signal continent_opened(id: String)
signal empty_clicked
## Verschieben läuft (vorläufig) bzw. ist beendet (endgültig, als ein Schritt).
signal continent_dragged(id: String, latitude: float, longitude: float, final: bool)
signal enter_continent

const RADIUS := 300.0
const SHADER := preload("res://src/editor/globe.gdshader")
## Überhöhung des Reliefs auf dem Globus (nur Darstellung).
const RELIEF_EXAGGERATION := 30.0
const TEXTURE_RES := 129

@onready var camera: Camera3D = $Camera3D

var selected_id := ""
var _sphere: MeshInstance3D
var _material: ShaderMaterial
var _ids: Array[String] = []
var _continents: Array = []
var _windows: Array = []
## Gebackene Bilder je Ausschnitt (nur geänderte Kontinente werden neu gebacken).
var _baked := {}
var _planet_radius_m := 6371000.0
var _pitch := 0.0
var _yaw := 0.0
var _distance := 900.0
var _target_distance := 900.0
var _rotating := false
var _dragging_continent := false
var _drag_offset := Vector2.ZERO
var _press_position := Vector2.ZERO
var _limit_count := 0
var _limit_time := 0.0


func _ready() -> void:
	_sphere = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 384
	mesh.rings = 192
	_sphere.mesh = mesh
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_sphere.material_override = _material
	_sphere.custom_aabb = AABB(Vector3.ONE * -RADIUS * 1.2, Vector3.ONE * RADIUS * 2.4)
	add_child(_sphere)
	# Eigenes Licht: von vorn links oben, damit die zugewandte Seite hell ist (die Sonne der
	# Landschaft steht für den Globus ungünstig).
	var light := DirectionalLight3D.new()
	light.name = "GlobeLight"
	light.light_energy = 1.25
	light.light_color = Color(1.0, 0.95, 0.88)
	add_child(light)
	light.look_at_from_position(Vector3(-1.1, 0.9, 1.6), Vector3.ZERO)
	light.visible = visible
	visibility_changed.connect(func() -> void: light.visible = visible)


## Alle Kontinente zeigen. windows: grober Ausschnitt je Kontinent (gleiche Reihenfolge).
## Die Anzahl ist nicht begrenzt (nur durch die Grafikkarte: über 2000 Ebenen).
func show_world(continents: Array, planet: Dictionary, windows: Array) -> void:
	_continents = continents
	_windows = windows
	_ids.clear()
	for c in continents:
		_ids.append(c["id"])
	_planet_radius_m = planet["radius_km"] * 1000.0
	var colors: Array[Image] = []
	var datas: Array[Image] = []
	var cache := {}
	for w in windows:
		var pair: Array = _baked.get(w, [])
		if pair.is_empty():
			pair = [bake_colors(w), _height_image(w)]
		cache[w] = pair
		colors.append(pair[0])
		datas.append(pair[1])
	_baked = cache
	if colors.is_empty():
		colors.append(Image.create(TEXTURE_RES, TEXTURE_RES, false, Image.FORMAT_RGBA8))
		datas.append(Image.create(TEXTURE_RES, TEXTURE_RES, false, Image.FORMAT_RF))
	var color_array := Texture2DArray.new()
	color_array.create_from_images(colors)
	var data_array := Texture2DArray.new()
	data_array.create_from_images(datas)
	_material.set_shader_parameter("continent_color", color_array)
	_material.set_shader_parameter("continent_data", data_array)
	update_placement(continents, planet)


func update_placement(continents: Array, planet: Dictionary) -> void:
	_continents = continents
	_planet_radius_m = planet["radius_km"] * 1000.0
	var count := continents.size()
	var data := PackedFloat32Array()
	data.resize(maxi(count, 1) * 2 * 4)
	var selected := -1
	var width := maxi(count, 1)
	for k in count:
		var c: Dictionary = continents[k]
		var size_m: float = c["size_km"] * 1000.0
		data[k * 4] = c["latitude"]
		data[k * 4 + 1] = c["longitude"]
		data[k * 4 + 2] = c["heading"]
		data[k * 4 + 3] = size_m
		var center := GlobeMath.unit_vector(c["latitude"], c["longitude"])
		# Reichweite: halbe Fensterdiagonale als Winkel, mit etwas Zugabe.
		var reach := minf(size_m * 0.75 / _planet_radius_m, PI)
		var row := (width + k) * 4
		data[row] = center.x
		data[row + 1] = center.y
		data[row + 2] = center.z
		data[row + 3] = cos(reach)
		if c["id"] == selected_id:
			selected = k
	var image := Image.create_from_data(width, 2, false, Image.FORMAT_RGBAF, data.to_byte_array())
	_material.set_shader_parameter("params", ImageTexture.create_from_image(image))
	_material.set_shader_parameter("count", count)
	_material.set_shader_parameter("selected", selected)
	_material.set_shader_parameter("planet_radius_m", _planet_radius_m)
	_material.set_shader_parameter("relief_scale", RADIUS / _planet_radius_m * RELIEF_EXAGGERATION)


func select(id: String) -> void:
	selected_id = id
	update_placement(_continents, {"radius_km": _planet_radius_m / 1000.0})


## Dreht den Globus so, dass die Lage zur Kamera zeigt.
func face(latitude: float, longitude: float) -> void:
	_pitch = deg_to_rad(latitude)
	_yaw = -deg_to_rad(longitude)
	_apply()


## Bildschirmstelle einer Breite/Länge (für die Abnahme mit echten Mausereignissen).
func screen_of(latitude: float, longitude: float) -> Vector2:
	return camera.unproject_position(_sphere.global_transform * (GlobeMath.unit_vector(latitude, longitude) * RADIUS))


## Breite/Länge in der Bildmitte (für neue Kontinente).
func view_center() -> Vector2:
	return Vector2(rad_to_deg(_pitch), -rad_to_deg(_yaw))


## Farbbild eines Kontinents; Alpha = Land (weich an der Küste).
static func bake_colors(w: TerrainWindow) -> Image:
	var snowline: float = w.climate["snowline"]
	var dryness: float = w.climate["dryness"]
	var meadow := Color(0.36, 0.47, 0.13).lerp(Color(0.64, 0.56, 0.26), clampf(dryness - 0.2, 0.0, 0.8))
	var forest_c := Color(0.08, 0.20, 0.06)
	var rock := Color(0.50, 0.47, 0.43)
	var sand := Color(0.80, 0.72, 0.52)
	var snow := Color(0.94, 0.95, 0.97)
	var lake := Color(0.10, 0.36, 0.55)
	var bytes := PackedByteArray()
	bytes.resize(w.res * w.res * 4)
	for k in w.res * w.res:
		var h: float = w.height[k]
		var c := meadow.lerp(forest_c, smoothstep(0.15, 0.6, w.forest[k]))
		c = c.lerp(rock, smoothstep(1200.0, 2200.0, h))
		c = c.lerp(sand, 1.0 - smoothstep(2.0, 40.0, h))
		c = c.lerp(snow, smoothstep(snowline - 200.0, snowline + 200.0, h))
		if w.water_level[k] > h:
			c = lake
		bytes[k * 4] = int(clampf(c.r, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
		bytes[k * 4 + 3] = int(smoothstep(-3.0, 3.0, h) * 255.0)
	return Image.create_from_data(w.res, w.res, false, Image.FORMAT_RGBA8, bytes)


static func _height_image(w: TerrainWindow) -> Image:
	return Image.create_from_data(w.res, w.res, false, Image.FORMAT_RF, w.height.to_byte_array())


# --- Bedienung -----------------------------------------------------------------------------

## Breite/Länge unter einer Bildschirmstelle oder null (daneben).
func latlon_under(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var dir := camera.project_ray_normal(screen_position)
	# Kugel im eigenen Raum (sie ist gedreht).
	var inv := _sphere.global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var b := o.dot(d)
	var c := o.dot(o) - RADIUS * RADIUS
	var disc := b * b - c
	if disc < 0.0:
		return null
	var t := -b - sqrt(disc)
	if t < 0.0:
		return null
	return GlobeMath.latlon_of(o + d * t)


## Kontinent an einer Breite/Länge ("" wenn keiner): Land des Kontinents an dieser Stelle.
func continent_at(latlon: Vector2) -> String:
	for k in range(_continents.size() - 1, -1, -1):
		var c: Dictionary = _continents[k]
		var local := GlobeMath.latlon_to_local(c["latitude"], c["longitude"], c["heading"], latlon.x, latlon.y, _planet_radius_m)
		var half: float = c["size_km"] * 500.0
		if absf(local.x) > half or absf(local.y) > half:
			continue
		if k < _windows.size() and (_windows[k] as TerrainWindow).height_at(local.x, local.y) > 0.0:
			return c["id"]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_LEFT:
				if b.pressed:
					_press_position = b.position
					var ll: Variant = latlon_under(b.position)
					var hit := continent_at(ll) if ll != null else ""
					if b.double_click and hit != "":
						continent_opened.emit(hit)
						return
					if hit != "" and hit == selected_id:
						var c: Dictionary = _continents[_ids.find(hit)]
						_drag_offset = Vector2(c["latitude"], c["longitude"]) - (ll as Vector2)
						_dragging_continent = true
					else:
						_rotating = true
				else:
					var moved := b.position.distance_to(_press_position) > 4.0
					if _dragging_continent:
						_dragging_continent = false
						if moved:
							_emit_drag(b.position, true)
					elif not moved:
						var ll: Variant = latlon_under(b.position)
						var hit := continent_at(ll) if ll != null else ""
						if hit != "":
							continent_clicked.emit(hit)
						else:
							empty_clicked.emit()
					_rotating = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_rotating = b.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if b.pressed:
					_zoom(1.0 / 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if b.pressed:
					_zoom(1.15)
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _dragging_continent:
			_emit_drag(m.position, false)
		elif _rotating:
			_rotate(m.relative)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		if pan.ctrl_pressed or pan.meta_pressed:
			_zoom(pow(1.15, pan.delta.y))
		else:
			_rotate(-pan.delta * 10.0)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))


func _emit_drag(screen_position: Vector2, final: bool) -> void:
	var ll: Variant = latlon_under(screen_position)
	if ll == null:
		return
	var target: Vector2 = (ll as Vector2) + _drag_offset
	continent_dragged.emit(selected_id, clampf(target.x, -80.0, 80.0), wrapf(target.y, -180.0, 180.0), final)


func _rotate(relative: Vector2) -> void:
	var speed := 0.004 * (_distance - RADIUS) / 600.0
	_yaw += relative.x * speed
	_pitch = clampf(_pitch + relative.y * speed, -1.4, 1.4)


func _zoom(factor: float) -> void:
	if factor < 1.0 and _target_distance <= 420.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _limit_time > 0.8:
			_limit_count = 0
		_limit_time = now
		_limit_count += 1
		if _limit_count >= 2:
			_limit_count = 0
			enter_continent.emit()
		return
	_target_distance = clampf(_target_distance * factor, 420.0, 1600.0)


func _process(delta: float) -> void:
	_distance = lerpf(_distance, _target_distance, 1.0 - exp(-12.0 * delta))
	_apply()


func _apply() -> void:
	_sphere.basis = Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.UP, _yaw)
	camera.position = Vector3(0.0, 0.0, _distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)
