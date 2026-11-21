class_name GlobeView
extends Node3D
## Der Globus mit dem platzierten Kontinent. Ziehen dreht den Globus, Mausrad zoomt;
## am Anschlag weiter hineinzoomen öffnet den Kontinent.

signal enter_continent

const RADIUS := 300.0
const SHADER := preload("res://src/editor/globe.gdshader")
## Überhöhung des Reliefs auf dem Globus (nur Darstellung).
const RELIEF_EXAGGERATION := 30.0

@onready var camera: Camera3D = $Camera3D

var _sphere: MeshInstance3D
var _material: ShaderMaterial
var _pitch := 0.0
var _yaw := 0.0
var _distance := 900.0
var _target_distance := 900.0
var _dragging := false
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


## Kontinentbild (aus dem gröbsten Ausschnitt) und Lage übernehmen.
func show_continent(continent: Dictionary, planet: Dictionary, w: TerrainWindow) -> void:
	var data := PackedFloat32Array()
	data.resize(w.res * w.res)
	for k in w.res * w.res:
		data[k] = w.height[k]
	var data_image := Image.create_from_data(w.res, w.res, false, Image.FORMAT_RF, data.to_byte_array())
	_material.set_shader_parameter("continent_data", ImageTexture.create_from_image(data_image))
	_material.set_shader_parameter("continent_color", ImageTexture.create_from_image(bake_colors(w)))
	update_placement(continent, planet)


func update_placement(continent: Dictionary, planet: Dictionary) -> void:
	var radius_m: float = planet["radius_km"] * 1000.0
	_material.set_shader_parameter("lat0", continent["latitude"])
	_material.set_shader_parameter("lon0", continent["longitude"])
	_material.set_shader_parameter("heading", continent["heading"])
	_material.set_shader_parameter("size_m", continent["size_km"] * 1000.0)
	_material.set_shader_parameter("planet_radius_m", radius_m)
	_material.set_shader_parameter("relief_scale", RADIUS / radius_m * RELIEF_EXAGGERATION)


## Dreht den Globus so, dass der Kontinent zur Kamera zeigt.
func face(continent: Dictionary) -> void:
	_pitch = deg_to_rad(continent["latitude"])
	_yaw = -deg_to_rad(continent["longitude"])
	_target_distance = 900.0
	_distance = _target_distance
	_apply()


## Farbbild des Kontinents; Alpha = Land (weich an der Küste).
static func bake_colors(w: TerrainWindow) -> Image:
	var image := Image.create(w.res, w.res, false, Image.FORMAT_RGBA8)
	var snowline: float = w.climate["snowline"]
	var dryness: float = w.climate["dryness"]
	var meadow := Color(0.36, 0.47, 0.13).lerp(Color(0.64, 0.56, 0.26), clampf(dryness - 0.2, 0.0, 0.8))
	var forest_c := Color(0.08, 0.20, 0.06)
	var rock := Color(0.50, 0.47, 0.43)
	var sand := Color(0.80, 0.72, 0.52)
	var snow := Color(0.94, 0.95, 0.97)
	for j in w.res:
		for i in w.res:
			var k := j * w.res + i
			var h: float = w.height[k]
			var c := meadow.lerp(forest_c, smoothstep(0.15, 0.6, w.forest[k]))
			c = c.lerp(rock, smoothstep(1200.0, 2200.0, h))
			c = c.lerp(sand, 1.0 - smoothstep(2.0, 40.0, h))
			c = c.lerp(snow, smoothstep(snowline - 200.0, snowline + 200.0, h))
			c.a = smoothstep(-3.0, 3.0, h)
			image.set_pixel(i, j, c)
	return image


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = b.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if b.pressed:
					_zoom(1.0 / 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if b.pressed:
					_zoom(1.15)
	elif event is InputEventMouseMotion and _dragging:
		_rotate((event as InputEventMouseMotion).relative)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		if pan.ctrl_pressed or pan.meta_pressed:
			_zoom(pow(1.15, pan.delta.y))
		else:
			_rotate(-pan.delta * 10.0)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))


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
