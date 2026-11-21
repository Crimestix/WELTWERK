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


## Standbild für die Übersicht (in <Ordner>/bilder/).
var _dir := ""
var _snap_count := 0


func snap(label: String) -> void:
	if _dir == "":
		return
	await RenderingServer.frame_post_draw
	_snap_count += 1
	var image := editor.get_viewport().get_texture().get_image()
	image.save_jpg(_dir.path_join("bilder/%02d_%s.jpg" % [_snap_count, label]), 0.85)


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


## Regler mit der Maus auf einen Wert ziehen (wie ein Nutzer: Knopf greifen, schieben).
func drag_slider(slider: Range, value: float) -> void:
	if slider == null or not slider.is_visible_in_tree():
		checks["Regler sichtbar"] = false
		return
	var rect := slider.get_global_rect()
	var span := slider.max_value - slider.min_value
	var from := Vector2(rect.position.x + rect.size.x * (slider.value - slider.min_value) / span, rect.get_center().y)
	var to := Vector2(rect.position.x + rect.size.x * (value - slider.min_value) / span, rect.get_center().y)
	await drag(PackedVector2Array([from, to]), 4.0)


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


## Referenz-Bildpunkt (1586 × 992) auf den eigenen Bildschirm.
func ref(p: Vector2) -> Vector2:
	var view: Vector2 = editor.get_viewport().get_visible_rect().size
	return p / ComparisonRun.REF_SIZE * view


func ref_points(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(ref(p))
	return out


## Werkzeug über die Oberfläche wählen: erst die Gruppe in der linken Leiste, dann das Werkzeug.
func choose(group: String, tool_label: String) -> void:
	# Ist die Gruppe schon offen, würde ein zweiter Klick sie schließen.
	if find_button(tool_label) == null:
		await press(group)
		await frames(8)
	await press(tool_label)
	await frames(10)


func run(dir: String) -> void:
	_dir = dir
	DirAccess.make_dir_recursive_absolute(dir.path_join("bilder"))
	_setup_overlay()
	var started := Time.get_ticks_usec()
	var comparison := ComparisonRun.new(editor)
	await frames(30)
	caption("Neue Welt: leerer Globus")
	await frames(45)

	# 1 Kontinent anlegen
	caption("1 · Neuen Kontinent anlegen und den Umriss zeichnen")
	await press("Neu zeichnen")
	await frames(20)
	comparison._frame()
	await frames(25)
	var outline := comparison.outline_points()
	var screen := PackedVector2Array()
	for k in range(0, outline.size(), 2):
		screen.append(ref(outline[k]))
	var t := Time.get_ticks_usec()
	await drag(screen, 14.0)
	timing["Umriss zeichnen → Kontinent berechnet"] = (Time.get_ticks_usec() - t) / 1000.0
	checks["Umriss ergibt Land"] = (editor.continent()["strokes"] as Array).size() == 1
	await frames(30)
	await snap("umriss")

	# 2 Bucht wegschneiden
	caption("2 · Eine Bucht wegschneiden")
	await choose("Form", "Land wegschneiden")
	await drag(ref_points(ComparisonRun.BAY + [ComparisonRun.BAY[0]]), 10.0)
	await frames(30)
	await snap("bucht")

	# 3 Gebirge, Wald, Fluss, See
	await choose("Gelände", "Gebirge")
	caption("3 · Gebirge: Größe und Stärke einstellen, dann entlang eines Strichs malen")
	await drag_slider(editor.ui._size_slider, 0.62)
	await drag_slider(editor.ui._strength_slider, 0.95)
	await frames(10)
	for chain in ComparisonRun.MOUNTAINS.slice(0, 2):
		await drag(ref_points(chain), 7.0)
		await frames(10)
	await snap("gebirge")
	caption("Neu würfeln: gleiche Stelle, andere Form")
	await press("Neu würfeln")
	await frames(30)
	await snap("neu_gewuerfelt")
	caption("4 · Wald verteilen")
	await choose("Bewuchs", "Wald verteilen")
	for chain in ComparisonRun.FORESTS.slice(0, 3):
		await drag(ref_points(chain), 8.0)
	await frames(20)
	caption("5 · Fluss vom Gebirge zum Meer, ein See")
	await choose("Wasser", "Fluss")
	await drag(ref_points(ComparisonRun.RIVERS[0]), 8.0)
	await frames(20)
	await choose("Wasser", "See")
	await click(ref(ComparisonRun.LAKES[0]))
	await frames(30)
	await snap("wald_fluss_see")

	# 4 Form nachträglich ändern
	caption("6 · Die gezeichnete Form nachträglich ändern")
	await choose("Form", "Formen bearbeiten")
	var land_point := ref(Vector2(700, 640))
	await click(land_point)
	await frames(20)
	await snap("form_gewaehlt")
	# Ostküste ein Stück nach außen ziehen (Punkt der Form unter dem Zeiger).
	var shape: Dictionary = editor.continent()["strokes"][0]
	var best := Vector2.ZERO
	var best_x := -INF
	for i in Stroke.dab_count(shape):
		var p := Stroke.point(shape, i)
		var s: Vector2 = editor.camera_rig.camera.unproject_position(editor.landscape.to_render(p.x, p.y))
		if s.y > 350 and s.y < 600 and s.x > best_x and s.x < 1300:
			best_x = s.x
			best = s
	var before := (editor.continent()["strokes"] as Array).size()
	if best_x > -INF:
		await drag(PackedVector2Array([best, best + Vector2(70, 20)]), 4.0)
	await frames(30)
	checks["Umriss durch Ziehen verändert"] = not ShapeEdit.same_outline(shape, editor.continent()["strokes"][0], 1.0)
	await snap("form_geaendert")
	caption("Rückgängig und Wiederholen")
	await press("Rückgängig")
	await frames(30)
	await snap("rueckgaengig")
	await press("Wiederholen")
	await frames(30)
	checks["Nach Rückgängig und Wiederholen gleiche Zahl Bearbeitungen"] = (editor.continent()["strokes"] as Array).size() == before

	# 5 Näher heran und zurück
	caption("7 · Näher heran: Gebirge, Wald, Fluss")
	await press("Ansehen")
	await wheel(ref(Vector2(560, 400)), 6, true, 6)
	await frames(40)
	await snap("naeher")
	await wheel(ref(Vector2(560, 400)), 6, false, 6)
	await frames(30)

	# 6 Auf dem Globus
	caption("8 · Zurück zum Globus")
	await press("Welt")
	await frames(60)
	await snap("globus")
	caption("")
	await frames(20)
	timing["Ablauf gesamt (Wanduhr)"] = (Time.get_ticks_usec() - started) / 1000.0
	editor._save_now()
	var file := FileAccess.open(dir.path_join("aufnahme.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "timing_ms": timing}, "  "))
	file.close()
	for key in checks:
		print("  %s %s" % ["ok  " if checks[key] else "FEHLT", key])
	editor.get_tree().quit()
