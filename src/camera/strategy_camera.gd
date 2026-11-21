class_name StrategyCamera
extends Node3D
## Kamera wie in einem Aufbauspiel: fester Blickwinkel schräg von oben, verschieben und zoomen.
##
## Der Knoten selbst ist der Blickpunkt am Boden; die Camera3D (Kind) schaut aus festem Winkel
## und Abstand darauf. Gedreht wird nicht (Entscheidung des Spielleiters, 21. 11. 2026).
## Bedienung mit Maus, Tastatur und Trackpad (MacBook).

## Gelände, auf dem der Blickpunkt liegt (braucht height_at, raycast, world_rect).
## Ohne Gelände gilt ebener Boden auf Höhe 0.
@export var terrain: Node3D
## Sonne: Ihre Schattenweite folgt dem Zoom, damit Schatten nah scharf und fern vorhanden sind.
@export var sun: DirectionalLight3D

@export_group("Blick")
## Neigung der Kamera über dem Horizont in Grad (fest).
@export_range(20.0, 89.0) var pitch_degrees: float = 52.0
## Neigung ganz nah (< 0: aus). Wie in Aufbauspielen wird der Blick beim Hineinzoomen flacher –
## nur abhängig vom Zoom, nicht frei drehbar.
@export var near_pitch_degrees: float = -1.0
## Himmelsrichtung, aus der die Kamera schaut, in Grad (fest; 0 = von Süden).
@export_range(-180.0, 180.0) var yaw_degrees: float = 0.0
## Bildwinkel (senkrecht, Grad) ganz nah und ganz fern: Fern schmaler wie eine Landkarte (wenig
## Verzerrung zwischen Vorder- und Hintergrund), nah weiter wie im Aufbauspiel. < 0: fest.
@export var near_fov_degrees: float = -1.0
@export var far_fov_degrees: float = -1.0
@export var min_distance: float = 8.0
@export var max_distance: float = 520.0
@export var start_distance: float = 260.0

@export_group("Tempo")
## Verschieben per Tastatur in Bildschirmhöhen pro Sekunde.
@export var key_pan_speed: float = 0.9
## Faktor je Mausrad-Raste.
@export var zoom_step: float = 1.18
## Zoom per Tastatur: Verdopplungen pro Sekunde.
@export var key_zoom_speed: float = 1.6
## Mit Umschalt so viel schneller.
@export var fast_factor: float = 3.0
## Wie schnell die Kamera ihrem Ziel folgt (größer = direkter).
@export var smoothing: float = 14.0

## Wird weiter gezoomt, obwohl der Anschlag erreicht ist (zweimal kurz hintereinander):
## inward = hinein. Dient dem Wechsel in einen feineren oder gröberen Maßstab.
signal zoom_limit(inward: bool, screen_position: Vector2)

@onready var camera: Camera3D = $Camera3D

var _limit_count := 0
var _limit_time := 0.0

var _focus := Vector3.ZERO
var _target_focus := Vector3.ZERO
var _distance := 0.0
var _target_distance := 0.0
var _dragging := false


func _ready() -> void:
	reset_view()
	_distance = _target_distance
	_focus = _target_focus
	_apply()


## Zurück zur Übersicht über die Mitte der Welt.
func reset_view() -> void:
	_target_focus = Vector3.ZERO
	_target_distance = clampf(start_distance, min_distance, max_distance)


## Blickpunkt (Darstellungskoordinaten), auf den die Kamera zusteuert.
func focus_point() -> Vector3:
	return _target_focus


## Blickpunkt verschieben, ohne Übergang (z. B. wenn der Ausschnitt mitwandert).
func shift_focus(delta: Vector3) -> void:
	_target_focus += delta
	_focus += delta
	_apply()


## Springt ohne Übergang zu einem Blickpunkt und Abstand.
func jump_to(focus: Vector3, distance: float) -> void:
	_target_focus = _clamp_to_world(focus)
	_target_distance = clampf(distance, min_distance, max_distance)
	_focus = _target_focus
	_distance = _target_distance
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_reset"):
		reset_view()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_towards(button.position, 1.0 / pow(zoom_step, maxf(button.factor, 1.0)))
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_towards(button.position, pow(zoom_step, maxf(button.factor, 1.0)))
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_by_pixels((event as InputEventMouseMotion).relative)
	elif event is InputEventPanGesture:
		# Trackpad: zwei Finger schieben. Mit Strg/Befehl wie Mausrad zoomen.
		var pan := event as InputEventPanGesture
		if pan.ctrl_pressed or pan.meta_pressed:
			_zoom_towards(pan.position, pow(zoom_step, pan.delta.y))
		else:
			_pan_by_pixels(-pan.delta * 12.0)
	elif event is InputEventMagnifyGesture:
		# Trackpad: Finger spreizen = hineinzoomen.
		var magnify := event as InputEventMagnifyGesture
		_zoom_towards(magnify.position, 1.0 / maxf(magnify.factor, 0.01))


func _process(delta: float) -> void:
	var fast := fast_factor if Input.is_action_pressed("camera_fast") else 1.0

	var move := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if move != Vector2.ZERO:
		var meters_per_second := _visible_height() * key_pan_speed * fast
		_target_focus += (_right() * move.x + _ground_forward() * -move.y) * meters_per_second * delta

	var zoom_axis := Input.get_axis("camera_zoom_in", "camera_zoom_out")
	if zoom_axis != 0.0:
		_target_distance *= pow(2.0, zoom_axis * key_zoom_speed * fast * delta)

	_target_distance = clampf(_target_distance, min_distance, max_distance)
	_target_focus = _clamp_to_world(_target_focus)

	var t := 1.0 - exp(-smoothing * delta)
	_focus = _focus.lerp(_target_focus, t)
	_distance = lerpf(_distance, _target_distance, t)
	_apply()


## Setzt Position und Blick der Kamera aus Blickpunkt und Abstand.
func _apply() -> void:
	var ground := _ground_height(_focus.x, _focus.z)
	position = Vector3(_focus.x, ground, _focus.z)

	var offset := _view_direction() * -_distance
	var eye := position + offset
	# Nie unter das Gelände tauchen.
	var floor_height := _ground_height(eye.x, eye.z) + 2.0
	if eye.y < floor_height:
		eye.y = floor_height
	camera.global_position = eye
	camera.look_at(position, Vector3.UP)

	if near_fov_degrees > 0.0 and far_fov_degrees > 0.0:
		camera.fov = lerpf(near_fov_degrees, far_fov_degrees, _zoom_t())
	camera.near = clampf(_distance * 0.005, 0.05, 1.0)
	camera.far = maxf(4000.0, _distance * 10.0)
	if sun:
		sun.directional_shadow_max_distance = clampf(_distance * 2.5, 60.0, 6000.0)


## Zoomt so, dass der Punkt unter dem Mauszeiger an seiner Stelle bleibt.
func _zoom_towards(screen_position: Vector2, factor: float) -> void:
	if factor < 1.0 and _target_distance <= min_distance + 0.001:
		_push_limit(true, screen_position)
		return
	if factor > 1.0 and _target_distance >= max_distance - 0.001:
		_push_limit(false, screen_position)
		return
	var old_distance := _target_distance
	_target_distance = clampf(_target_distance * factor, min_distance, max_distance)
	var anchor: Variant = _ground_under(screen_position)
	if anchor == null:
		return
	var anchor_point: Vector3 = anchor
	var shift := 1.0 - _target_distance / old_distance
	var towards := Vector3(anchor_point.x - _target_focus.x, 0.0, anchor_point.z - _target_focus.z)
	_target_focus += towards * shift


func _push_limit(inward: bool, screen_position: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _limit_time > 0.8:
		_limit_count = 0
	_limit_time = now
	_limit_count += 1
	if _limit_count >= 2:
		_limit_count = 0
		zoom_limit.emit(inward, screen_position)


## Bodenpunkt unter einer Bildschirmposition (Darstellungskoordinaten) oder null.
func ground_point_under(screen_position: Vector2) -> Variant:
	return _ground_under(screen_position)


## Verschiebt die Welt mit dem Mauszeiger („anfassen und ziehen“).
func _pan_by_pixels(relative: Vector2) -> void:
	var meters_per_pixel := _visible_height() / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var forward_scale := 1.0 / maxf(sin(deg_to_rad(current_pitch())), 0.3)
	var shift := (_right() * -relative.x + _ground_forward() * relative.y * forward_scale) * meters_per_pixel
	_target_focus += shift
	_focus += shift


## Bodenpunkt unter einer Bildschirmposition – Gelände, sonst die Ebene des Blickpunkts.
func _ground_under(screen_position: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_position)
	var dir := camera.project_ray_normal(screen_position)
	if terrain:
		var hit: Variant = terrain.raycast(from, dir, _distance * 6.0 + 500.0)
		if hit != null:
			return hit
	var plane := Plane(Vector3.UP, position.y)
	return plane.intersects_ray(from, dir)


## Höhe des sichtbaren Ausschnitts am Blickpunkt in Metern.
func _visible_height() -> float:
	return 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5))


## Aktuelle Neigung in Grad (fest oder mit dem Zoom flacher).
func current_pitch() -> float:
	if near_pitch_degrees < 0.0:
		return pitch_degrees
	return lerpf(near_pitch_degrees, pitch_degrees, _zoom_t())


## 0 ganz nah … 1 fern (für Neigung und Bildwinkel).
func _zoom_t() -> float:
	# Erst ganz nah flacher und weiter: in Arbeitsentfernung bleibt der Kartenblick steil.
	return smoothstep(min_distance, lerpf(min_distance, max_distance, 0.3), _distance)


func _view_direction() -> Vector3:
	var pitch := deg_to_rad(current_pitch())
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))


func _ground_forward() -> Vector3:
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _right() -> Vector3:
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else 0.0


func _clamp_to_world(point: Vector3) -> Vector3:
	if terrain == null:
		return point
	var rect: Rect2 = terrain.world_rect()
	if rect.size == Vector2.ZERO:
		return point
	return Vector3(
		clampf(point.x, rect.position.x, rect.end.x),
		point.y,
		clampf(point.z, rect.position.y, rect.end.y))
