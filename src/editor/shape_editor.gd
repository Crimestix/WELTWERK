class_name ShapeEditor
extends Node3D
## Gezeichnete Landformen nachträglich wählen und verändern (Werkzeug „Formen bearbeiten“).
##
## Kind der LandscapeView; bekommt deren Eingaben, solange das Werkzeug "select" gewählt ist.
## Zeigen: dünner Messingumriss unter dem Mauszeiger. Klicken: wählen (hellerer Umriss und
## Punktgriffe). Ziehen im Inneren verschiebt, Ziehen an einem Punkt formt um (Nachbarn gehen weich
## mit; mit Alt nur dieser Punkt), Doppelklick auf den Rand fügt einen Punkt ein, Entf löscht den
## Punkt unter dem Zeiger oder sonst die Form, Umschalt + Mausrad skaliert, Strg + Mausrad dreht,
## Esc hebt die Wahl auf. Während des Ziehens und Drehens entsteht nur eine Vorschau des Umrisses;
## ein Loslassen (bzw. das Ende einer Mausrad-Folge) ist genau ein Befehl – Rückgängig stellt exakt her.
## Die Rechnung selbst steckt in ShapeEdit (rein, getestet); hier nur Eingabe und Darstellung.

## Eine Form wurde verändert: Strich an Listenplatz index durch stroke ersetzen.
signal shape_changed(index: int, stroke: Dictionary)
## Eine Form soll gelöscht werden.
signal shape_removed(index: int)

## Fanggröße für Punkte und Rand (Bildpunkte).
const PICK_PX := 9.0
## Wie weit Nachbarpunkte beim Ziehen mitgehen (Bildpunkte, entlang des Umrisses).
const FALLOFF_PX := 70.0
## Doppelklick näher als das an einem vorhandenen Punkt fügt keinen neuen ein (Bildpunkte).
const INSERT_GAP_PX := 2.5
## Ab dieser Mausbewegung (Bildpunkte) gilt ein Klick als Ziehen.
const DRAG_PX := 3.0
const SCALE_STEP := 1.05
const ROTATE_STEP_DEG := 3.0
## Nach der letzten Mausrad-Raste wird die Änderung als ein Schritt übernommen (Sekunden).
const WHEEL_COMMIT := 0.5

const HOVER_COLOR := Color(0.88, 0.70, 0.38, 0.8)
const SELECTED_COLOR := Color(1.0, 0.87, 0.55, 1.0)
const ORIGINAL_COLOR := Color(0.88, 0.70, 0.38, 0.45)
const HANDLE_FILL := Color(0.98, 0.93, 0.80, 1.0)
const HANDLE_HOT := Color(1.0, 0.80, 0.35, 1.0)
const HANDLE_RIM := Color(0.16, 0.11, 0.06, 0.9)

const HINT_SELECTED := "Form gewählt: Ziehen verschiebt · Punkte ziehen formt um (Alt: nur der Punkt) · Doppelklick auf den Rand fügt einen Punkt ein · Entf löscht · Umschalt+Mausrad skaliert · Strg+Mausrad dreht · Esc hebt die Wahl auf"
const HINT_NOTHING := "Hier liegt keine gezeichnete Landform. Formen entstehen mit „Land zeichnen“ und „Land wegschneiden“."

var view: LandscapeView
## Nur aktiv, solange das Werkzeug „Formen bearbeiten“ gewählt ist.
var active := false:
	set(value):
		if active == value:
			return
		active = value
		if not value:
			_commit_wheel()
			_cancel_drag()
			_deselect()
			hovered = -1
			hovered_vertex = -1
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_dirty = true

## Gewählte Form (Listenplatz in der Strichliste) oder -1.
var selected := -1
## Form unter dem Mauszeiger oder -1; Punkt der gewählten Form unter dem Zeiger oder -1.
var hovered := -1
var hovered_vertex := -1

var _continent_id := ""
## "" (nichts), "move" (Form verschieben) oder "vertex" (Punkt ziehen).
var _mode := ""
var _original := {}
var _preview := {}
var _drag_start := Vector2.ZERO
var _press_screen := Vector2.ZERO
var _moved := false
var _drag_vertex := -1
var _falloff := 0.0
var _wheel_pending := false
var _wheel_timer: Timer
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _dirty := true
var _last_camera := Transform3D()


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "ShapeOverlay"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 20
	_mesh.material_override = _material
	add_child(_mesh)
	_wheel_timer = Timer.new()
	_wheel_timer.one_shot = true
	_wheel_timer.wait_time = WHEEL_COMMIT
	_wheel_timer.timeout.connect(_commit_wheel)
	add_child(_wheel_timer)


## Läuft gerade eine Änderung (Ziehen oder Mausrad-Folge)? Dann kein Rückgängig, kein Maßstabswechsel.
func is_busy() -> bool:
	return _mode != "" or _wheel_pending


## Nach jedem neu gezeigten Ausschnitt (auch nach Rückgängig/Wiederholen): Wahl prüfen, neu zeichnen.
func refresh() -> void:
	var id: String = view.sampler.continent.get("id", "") if view and view.sampler else ""
	if id != _continent_id:
		_continent_id = id
		_cancel_drag()
		_deselect()
	if selected >= 0 and not ShapeEdit.is_shape(_stroke(selected)):
		_cancel_drag()
		_deselect()
	if hovered >= 0 and not ShapeEdit.is_shape(_stroke(hovered)):
		hovered = -1
	hovered_vertex = -1
	_dirty = true


## Von außen wählen (z. B. für Abläufe); -1 hebt die Wahl auf.
func select(index: int) -> void:
	if index >= 0 and ShapeEdit.is_shape(_stroke(index)):
		selected = index
		view.hint.emit(HINT_SELECTED)
	else:
		_deselect()
	_dirty = true


# --- Eingaben ------------------------------------------------------------------------------

## Von der LandscapeView weitergereicht (nicht behandelte Eingaben bei Werkzeug "select").
func handle_input(event: InputEvent) -> void:
	if not active or view == null or view.window == null:
		return
	if event is InputEventMouseMotion:
		if _on_motion((event as InputEventMouseMotion).position, event.alt_pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		var used := _on_press(button) if button.pressed else _on_release()
		if used:
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _on_key(event as InputEventKey):
			get_viewport().set_input_as_handled()


## Mausrad mit Umschalt/Strg vor der Kamera abfangen (sie bekäme es sonst zuerst zum Zoomen);
## Tasten schließen eine laufende Mausrad-Folge ab (z. B. damit Strg+Z sie danach zurücknimmt).
func _input(event: InputEvent) -> void:
	if not active or view == null or view.window == null or not view.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_META, KEY_ALT]:
			if not key.pressed:
				_commit_wheel()
		elif key.pressed:
			_commit_wheel()
		return
	if not event is InputEventMouseButton:
		return
	var b := event as InputEventMouseButton
	if b.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if b.pressed:
			_commit_wheel()
		return
	var rotate := b.ctrl_pressed or b.meta_pressed
	if not (rotate or b.shift_pressed) or selected < 0 or _mode != "":
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	if not b.pressed:
		get_viewport().set_input_as_handled()
		return
	var hit: Variant = view._hit(b.position)
	if hit == null:
		return
	var p := view.to_continent(hit)
	var base: Dictionary = _preview if _wheel_pending else _stroke(selected)
	if not _near_shape(base, p, _pick_m(hit)):
		return
	var up := b.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]
	var steps := clampf(b.factor, 0.2, 2.0) if b.factor > 0.0 else 1.0
	var center := ShapeEdit.centroid(base)
	if rotate:
		_preview = ShapeEdit.rotated(base, deg_to_rad(ROTATE_STEP_DEG * steps) * (1.0 if up else -1.0), center)
	else:
		_preview = ShapeEdit.scaled(base, pow(SCALE_STEP, steps * (1.0 if up else -1.0)), center)
	_wheel_pending = true
	_wheel_timer.start()
	_dirty = true
	get_viewport().set_input_as_handled()


func _on_motion(screen: Vector2, alt: bool) -> bool:
	var hit: Variant = view._hit(screen)
	if hit == null:
		return _mode != ""
	var p := view.to_continent(hit)
	if _mode != "":
		if screen.distance_to(_press_screen) >= DRAG_PX:
			_moved = true
		if not _moved:
			return true
		var delta := p - _drag_start
		if _mode == "move":
			_preview = ShapeEdit.translated(_original, delta)
		else:
			_preview = ShapeEdit.with_vertex_moved(_original, _drag_vertex, delta, 0.0 if alt else _falloff)
		_dirty = true
		return true
	var tolerance := _pick_m(hit)
	var over := ShapeEdit.shape_at(_continent(), p.x, p.y, tolerance)
	var vertex := -1
	if selected >= 0:
		vertex = ShapeEdit.nearest_vertex(_current(), p, tolerance)
	if over != hovered or vertex != hovered_vertex:
		hovered = over
		hovered_vertex = vertex
		_dirty = true
	if vertex >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	elif selected >= 0 and over == selected:
		Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	elif over >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	return false


func _on_press(button: InputEventMouseButton) -> bool:
	_commit_wheel()
	var hit: Variant = view._hit(button.position)
	if hit == null:
		return false
	var p := view.to_continent(hit)
	var tolerance := _pick_m(hit)
	if selected >= 0:
		var s := _stroke(selected)
		if button.double_click:
			# Auf dem Rand zwischen zwei Punkten (auch wenn sie dicht liegen): neuer Punkt dort.
			var edge := ShapeEdit.nearest_edge(s, p, tolerance)
			if not edge.is_empty():
				var poly := ShapeEdit.outline(s)
				var q: Vector2 = edge[1]
				var gap := INSERT_GAP_PX * _meters_per_pixel(hit)
				if q.distance_to(poly[edge[0]]) > gap and q.distance_to(poly[(edge[0] + 1) % poly.size()]) > gap:
					shape_changed.emit(selected, ShapeEdit.with_inserted_vertex(s, edge[0], q))
					return true
		var vertex := ShapeEdit.nearest_vertex(s, p, tolerance)
		if vertex >= 0:
			_start_drag("vertex", s, p, button.position, hit)
			_drag_vertex = vertex
			_falloff = 0.0 if button.alt_pressed else FALLOFF_PX * _meters_per_pixel(hit)
			return true
		if _near_shape(s, p, tolerance) and ShapeEdit.shape_at(_continent(), p.x, p.y, tolerance) == selected:
			_start_drag("move", s, p, button.position, hit)
			return true
	var index := ShapeEdit.shape_at(_continent(), p.x, p.y, tolerance)
	if index >= 0:
		select(index)
		# Gleich weiterziehen verschiebt die eben gewählte Form.
		_start_drag("move", _stroke(index), p, button.position, hit)
		return true
	if selected >= 0:
		_deselect()
	else:
		view.hint.emit(HINT_NOTHING)
	_dirty = true
	return true


func _on_release() -> bool:
	if _mode == "":
		return false
	var result := _preview
	var changed := _moved and not result.is_empty() and not ShapeEdit.same_outline(result, _original, 1e-6)
	var index := selected
	_cancel_drag()
	if changed:
		shape_changed.emit(index, result)
	return true


func _on_key(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_ESCAPE:
			if _mode != "":
				_cancel_drag()
				return true
			if selected >= 0:
				_deselect()
				return true
		KEY_DELETE, KEY_BACKSPACE:
			if _mode != "" or selected < 0:
				return false
			var s := _stroke(selected)
			var vertex := hovered_vertex
			if vertex >= 0:
				if Stroke.dab_count(s) <= ShapeEdit.MIN_POINTS:
					view.hint.emit("Eine Form braucht mindestens drei Punkte – Entf über der Fläche löscht die ganze Form.")
					return true
				hovered_vertex = -1
				shape_changed.emit(selected, ShapeEdit.without_vertex(s, vertex))
				return true
			var removed := selected
			_deselect()
			shape_removed.emit(removed)
			view.hint.emit("Form gelöscht – Strg+Z holt sie zurück.")
			return true
	return false


func _start_drag(mode: String, stroke: Dictionary, p: Vector2, screen: Vector2, _hit: Vector3) -> void:
	_mode = mode
	_original = stroke.duplicate(true)
	_preview = {}
	_drag_start = p
	_press_screen = screen
	_moved = false
	_drag_vertex = -1


func _cancel_drag() -> void:
	_mode = ""
	_original = {}
	_preview = {}
	_moved = false
	_drag_vertex = -1
	_dirty = true


func _commit_wheel() -> void:
	if not _wheel_pending:
		return
	_wheel_pending = false
	if _wheel_timer:
		_wheel_timer.stop()
	var result := _preview
	_preview = {}
	_dirty = true
	if selected >= 0 and not result.is_empty() and not ShapeEdit.same_outline(result, _stroke(selected), 1e-6):
		shape_changed.emit(selected, result)


func _deselect() -> void:
	selected = -1
	hovered_vertex = -1
	_dirty = true


# --- Daten ---------------------------------------------------------------------------------

func _continent() -> Dictionary:
	return view.sampler.continent if view and view.sampler else {}


func _stroke(index: int) -> Dictionary:
	var strokes: Array = _continent().get("strokes", [])
	return strokes[index] if index >= 0 and index < strokes.size() else {}


## Gewählte Form, wie sie gerade aussieht (mit laufender Vorschau).
func _current() -> Dictionary:
	return _preview if not _preview.is_empty() else _stroke(selected)


func _near_shape(stroke: Dictionary, p: Vector2, tolerance: float) -> bool:
	return ShapeEdit.is_shape(stroke) and (ShapeEdit.contains(stroke, p) or ShapeEdit.distance_to_outline(stroke, p) <= tolerance)


## Meter je Bildpunkt an einer Stelle der Darstellung.
func _meters_per_pixel(render_point: Vector3) -> float:
	return _units_per_pixel(render_point) / view.units_per_m


func _units_per_pixel(render_point: Vector3) -> float:
	var cam := view.camera
	var height := get_viewport().get_visible_rect().size.y
	if cam == null or height <= 0.0:
		return 1.0
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return cam.size / height
	var distance := cam.global_position.distance_to(render_point)
	return 2.0 * distance * tan(deg_to_rad(cam.fov) * 0.5) / height


func _pick_m(render_point: Vector3) -> float:
	return PICK_PX * _meters_per_pixel(render_point)


# --- Darstellung ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if view == null or view.window == null or view.camera == null:
		return
	if not active or not view.visible:
		if _mesh.mesh != null:
			_mesh.mesh = null
		return
	var cam := view.camera.global_transform
	if not _dirty and cam.is_equal_approx(_last_camera):
		return
	_last_camera = cam
	_dirty = false
	_rebuild()


func _rebuild() -> void:
	var mesh := ImmediateMesh.new()
	var any := false
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if hovered >= 0 and hovered != selected and ShapeEdit.is_shape(_stroke(hovered)):
		_add_outline(mesh, _stroke(hovered), HOVER_COLOR, 1.6)
		any = true
	if selected >= 0 and ShapeEdit.is_shape(_stroke(selected)):
		var shape := _current()
		if not _preview.is_empty():
			_add_outline(mesh, _stroke(selected), ORIGINAL_COLOR, 1.2)
		_add_outline(mesh, shape, SELECTED_COLOR, 2.6)
		_add_handles(mesh, shape)
		any = true
	if not any:
		# Leere Fläche wäre ungültig: ein entartetes Dreieck genügt.
		for k in 3:
			mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	_mesh.mesh = mesh if any else null


## Kontinentpunkt in der Darstellung, knapp über Boden bzw. Wasser (außerhalb: Meereshöhe).
func _render_point(p: Vector2) -> Vector3:
	var w := view.window
	var h := 0.0
	if w.contains(p.x, p.y):
		h = maxf(w.height_at(p.x, p.y), maxf(w.water_level_at(p.x, p.y), 0.0))
	return Vector3((p.x - w.cx) * view.units_per_m, h * view.height_scale + 0.6, -(p.y - w.cy) * view.units_per_m)


## Umriss als Band gleichbleibender Bildbreite (width_px), dem Gelände folgend.
func _add_outline(mesh: ImmediateMesh, stroke: Dictionary, color: Color, width_px: float) -> void:
	var poly := ShapeEdit.outline(stroke)
	var n := poly.size()
	if n < 2:
		return
	var step := view.window.size / 96.0
	var points := PackedVector3Array()
	for e in n:
		var a := poly[e]
		var b := poly[(e + 1) % n]
		var parts := clampi(int(ceil(a.distance_to(b) / step)), 1, 24)
		for s in parts:
			points.append(_render_point(a.lerp(b, float(s) / parts)))
	points.append(points[0])
	var cam_pos := view.camera.global_position
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var mid := (a + b) * 0.5
		var side := (b - a).cross(cam_pos - mid)
		if side.length_squared() < 1e-12:
			continue
		side = side.normalized() * width_px * 0.5 * _units_per_pixel(mid)
		_quad(mesh, a - side, a + side, b + side, b - side, color)


## Punktgriffe als kleine Quadrate, der Kamera zugewandt; der Punkt unter dem Zeiger größer.
func _add_handles(mesh: ImmediateMesh, stroke: Dictionary) -> void:
	var poly := ShapeEdit.outline(stroke)
	var w := view.window
	var basis := view.camera.global_transform.basis
	var right := basis.x
	var up := basis.y
	for k in poly.size():
		var p := poly[k]
		if absf(p.x - w.cx) > w.size * 0.75 or absf(p.y - w.cy) > w.size * 0.75:
			continue
		var c := _render_point(p)
		var u := _units_per_pixel(c)
		var hot := k == hovered_vertex or (_mode == "vertex" and k == _drag_vertex)
		var outer := (6.5 if hot else 4.5) * u
		var inner := (5.0 if hot else 3.2) * u
		_quad(mesh, c - right * outer - up * outer, c + right * outer - up * outer,
			c + right * outer + up * outer, c - right * outer + up * outer, HANDLE_RIM)
		_quad(mesh, c - right * inner - up * inner, c + right * inner - up * inner,
			c + right * inner + up * inner, c - right * inner + up * inner, HANDLE_HOT if hot else HANDLE_FILL)


static func _quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for v in [a, b, c, a, c, d]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v)
