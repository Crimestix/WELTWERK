class_name RecordingRun
extends RefCounted
## Aufgezeichneter Bedienablauf: vom Anlegen eines Kontinents bis zum Verändern der Landschaft,
## mit sichtbarem Mauszeiger und echten Klicks auf die Oberfläche (Godots Filmaufnahme:
## godot --write-movie <datei.ogv> --fixed-fps 30 … -- --aufnahme=<Ordner>).
## Hinweis: In der Filmaufnahme läuft jedes Bild in fester Zeit – Rechenpausen (Ausschnitt neu
## berechnen) sind im Film nicht zu sehen; sie werden in <Ordner>/aufnahme.json gemessen.

var editor: Node
var _layer: CanvasLayer
var _cursor: Control
var _caption: Label
var _pos := Vector2(720, 450)
var _pressed := false
var timing := {}
var checks := {}


func _init(p_editor: Node) -> void:
	editor = p_editor


func _setup_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	editor.add_child(_layer)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_color_override("font_color", Color(0.93, 0.88, 0.76))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.position = Vector2(-300, 62)
	_caption.size = Vector2(600, 30)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_caption)
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.draw.connect(_draw_cursor)
	_layer.add_child(_cursor)


## Pfeil-Mauszeiger (die Filmaufnahme zeigt den echten Zeiger nicht).
func _draw_cursor() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 21), Vector2(5.5, 16), Vector2(9.5, 24.5),
		Vector2(13, 23), Vector2(9.2, 14.8), Vector2(16, 14.8)])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(1.5, 2.0))
	_cursor.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	_cursor.draw_colored_polygon(pts, Color(0.98, 0.97, 0.94))
	var outline := pts.duplicate()
	outline.append(pts[0])
	_cursor.draw_polyline(outline, Color(0.08, 0.07, 0.06), 1.4, true)
	if _pressed:
		_cursor.draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(0.95, 0.75, 0.35, 0.9), 2.0, true)


func _place_cursor(p: Vector2) -> void:
	_pos = p
	_cursor.position = p
	_cursor.queue_redraw()


func caption(text: String) -> void:
	_caption.text = text


func frames(n: int) -> void:
	await editor._frames(n)


func _motion(p: Vector2, buttons: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = p - _pos
	e.button_mask = buttons
	Input.parse_input_event(e)
	_place_cursor(p)


func _button(p: Vector2, index: MouseButton, pressed: bool, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = index
	e.pressed = pressed
	e.double_click = double
	if index == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


## Zeiger gleitet zu p (weich beschleunigt), ohne Taste.
func move_to(p: Vector2, n: int = 20) -> void:
	var start := _pos
	for k in n:
		var t := float(k + 1) / n
		t = t * t * (3.0 - 2.0 * t)
		_motion(start.lerp(p, t), MOUSE_BUTTON_MASK_LEFT if _pressed else 0)
		await editor._frames(1)


func click(p: Vector2, travel: int = 20) -> void:
	await move_to(p, travel)
	await frames(4)
	_pressed = true
	_cursor.queue_redraw()
	_button(p, MOUSE_BUTTON_LEFT, true)
	await frames(3)
	_button(p, MOUSE_BUTTON_LEFT, false)
	_pressed = false
	_cursor.queue_redraw()
	await frames(6)


func double_click(p: Vector2) -> void:
	await click(p)
	_button(p, MOUSE_BUTTON_LEFT, true, true)
	await frames(2)
	_button(p, MOUSE_BUTTON_LEFT, false)
	await frames(6)


## Mit gedrückter linker Taste durch die Punkte (Bildschirm), je Abschnitt step Bildpunkte je Bild.
func drag(points: PackedVector2Array, step: float = 9.0) -> void:
	await move_to(points[0], 18)
	_pressed = true
	_button(points[0], MOUSE_BUTTON_LEFT, true)
	await frames(2)
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		var n := maxi(1, int(a.distance_to(b) / step))
		for s in n:
			_motion(a.lerp(b, float(s + 1) / n), MOUSE_BUTTON_MASK_LEFT)
			await editor._frames(1)
	_button(points[points.size() - 1], MOUSE_BUTTON_LEFT, false)
	_pressed = false
	_cursor.queue_redraw()
	await frames(8)


func wheel(p: Vector2, steps: int, inward: bool, every: int = 3) -> void:
	await move_to(p, 12)
	for k in steps:
		_button(p, MOUSE_BUTTON_WHEEL_UP if inward else MOUSE_BUTTON_WHEEL_DOWN, true)
		_button(p, MOUSE_BUTTON_WHEEL_UP if inward else MOUSE_BUTTON_WHEEL_DOWN, false)
		await frames(every)


func key(code: Key, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await frames(4)


## Sichtbare Schaltfläche der Oberfläche finden (Text oder Hinweistext beginnt mit label).
func find_button(label: String) -> Button:
	return _find_button(editor.ui, label)


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).is_visible_in_tree():
			var b := child as Button
			if b.text.strip_edges() == label or b.tooltip_text.begins_with(label):
				return b
		var found := _find_button(child, label)
		if found:
			return found
	return null


func center_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


## Klick auf eine Schaltfläche der Oberfläche; fehlt sie, wird das als Prüfung vermerkt.
func press(label: String) -> bool:
	var b := find_button(label)
	checks["Schaltfläche „%s“ gefunden" % label] = b != null
	if b == null:
		return false
	await click(center_of(b))
	return true
