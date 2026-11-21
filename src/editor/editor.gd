extends Node3D
## Der Editor: Weltdokument, Maßstäbe (Globus → Kontinent → Ausschnitte), Werkzeuge, Speichern.
##
## Ein Ausschnitt ist ein Fenster (Mitte, Größe) auf dem Kontinent; „Vertiefen“ öffnet eines mit
## 1/8 der Größe (Annahme A3). Der Wechsel ist im Nachweis sichtbar; die Daten sind für einen
## späteren flüssigen Übergang bereits maßstabsunabhängig.
##
## Aufruf-Schalter (nach `--`): --welt=<Pfad> eigene Weltdatei · --neu neue Welt ·
## --demo=<Ordner> Ablauf vorführen, Bilder und Messwerte speichern, beenden ·
## --screenshot=<Pfad> nach dem Laden ein Bild speichern und beenden.

const DEFAULT_PATH := "user://welt.json"
const FACTOR := 8.0
const SMALLEST := 190.0

@onready var landscape: LandscapeView = $Landscape
@onready var camera_rig: StrategyCamera = $CameraRig
@onready var globe: GlobeView = $Globe
@onready var ui: EditorUI = $Interface

var doc: WorldDocument
var sampler: TerrainSampler
var save_path := DEFAULT_PATH
var levels: Array = []
var in_globe := false
var tool := "navigate"
var size_fraction := 0.04
var strength := 0.6
var _continent_window: TerrainWindow
var _painted_live := false
var _placement_before := {}
var _save_timer: Timer
var _args := {}
## Einmaliger Hinweis in der Statuszeile (bis zur nächsten Änderung).
var _notice := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else ""
	if _args.has("demo"):
		save_path = _args["demo"].path_join("welt.json")
		DirAccess.make_dir_recursive_absolute(_args["demo"])
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
	save_path = _args.get("welt", save_path)

	doc = null if _args.has("neu") else WorldDocument.load_file(save_path)
	if doc == null:
		var seed_value := Crypto.new().generate_random_bytes(4).decode_u32(0) & 0x7FFFFFFF
		if _args.has("demo"):
			seed_value = 4242
		doc = WorldDocument.create(seed_value)
	doc.changed.connect(_on_doc_changed)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)

	landscape.camera = camera_rig.camera
	landscape.stroke_finished.connect(_on_stroke_finished)
	landscape.hover_changed.connect(_on_hover)
	camera_rig.zoom_limit.connect(_on_zoom_limit)
	globe.enter_continent.connect(func() -> void: open_continent())
	ui.tool_selected.connect(_on_tool)
	ui.brush_changed.connect(_on_brush)
	ui.undo_pressed.connect(func() -> void: doc.undo())
	ui.redo_pressed.connect(func() -> void: doc.redo())
	ui.level_pressed.connect(_on_level_pressed)
	ui.variant_pressed.connect(_on_variant)
	ui.globe_pressed.connect(func() -> void: open_globe())
	ui.edit_continent_pressed.connect(func() -> void: open_continent())
	ui.marks_toggled.connect(func(on: bool) -> void: landscape.show_marks = on)
	ui.placement_changed.connect(_on_placement)
	ui.set_saved(true)

	_apply_target_light()
	_rebuild_sampler()
	open_continent()

	if _args.has("demo"):
		_run_demo(_args["demo"])
	elif _args.has("screenshot"):
		_screenshot_and_quit(_args["screenshot"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and doc:
		_save_now()


## Licht wie in der Zielszene: warme Sonne von links hinten, weiche Verschattung.
func _apply_target_light() -> void:
	var sun: DirectionalLight3D = $Lighting/Sun
	sun.rotation = Vector3(-0.86, -2.05, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.54)
	sun.light_energy = 2.75
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 2.6
	var env: Environment = $Lighting/WorldEnvironment.environment
	env.ambient_light_energy = 0.75
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 0.7
	env.adjustment_contrast = 1.13
	env.adjustment_saturation = 1.14
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.2, 0.42, 0.75)
	sky.sky_horizon_color = Color(0.74, 0.84, 0.93)


func continent() -> Dictionary:
	return doc.continents[0]


func _rebuild_sampler() -> void:
	sampler = TerrainSampler.new(continent(), doc.planet)
	_continent_window = null


# --- Maßstäbe ------------------------------------------------------------------------------

func open_continent() -> void:
	levels = [{"cx": 0.0, "cy": 0.0, "size": continent()["size_km"] * 1000.0}]
	_set_globe(false)
	_show_level()
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.9)


func open_globe() -> void:
	_set_globe(true)
	globe.show_continent(continent(), doc.planet, _coarse_window())
	globe.face(continent())
	_update_ui()


func deepen_at(render_point: Vector3) -> void:
	var current: Dictionary = levels.back()
	var size: float = current["size"] / FACTOR
	if size < SMALLEST:
		return
	var cx := landscape.continent_x(render_point)
	var cy := landscape.continent_y(render_point)
	levels.append({"cx": cx, "cy": cy, "size": size})
	doc.remember_region(0, cx, cy, size)
	_queue_save()
	_show_level()
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.95)


func zoom_out() -> void:
	if levels.size() <= 1:
		open_globe()
		return
	var child: Dictionary = levels.pop_back()
	_show_level()
	camera_rig.jump_to(landscape.to_render(child["cx"], child["cy"]), camera_rig.min_distance * 1.3)


func _level_window(index: int) -> TerrainWindow:
	var level: Dictionary = levels[index]
	if level.get("window") == null:
		level["window"] = sampler.window(level["cx"], level["cy"], level["size"])
	return level["window"]


func _forget_windows() -> void:
	for level in levels:
		level["window"] = null


func _show_level() -> void:
	var current: Dictionary = levels.back()
	var started := Time.get_ticks_usec()
	var w := _level_window(levels.size() - 1)
	var parent := _level_window(levels.size() - 2) if levels.size() > 1 else null
	if levels.size() == 1:
		_continent_window = w
	landscape.show_window(w, sampler, continent()["regions"], parent)
	ui.set_window_size(current["size"])
	_on_brush(size_fraction, strength)
	_update_ui()
	print("Ausschnitt %s berechnet in %d ms" % [EditorUI.meters(current["size"]), (Time.get_ticks_usec() - started) / 1000])


func _coarse_window() -> TerrainWindow:
	if _continent_window == null:
		var size: float = continent()["size_km"] * 1000.0
		_continent_window = sampler.window(0.0, 0.0, size)
	return _continent_window


func _set_globe(on: bool) -> void:
	in_globe = on
	var env: Environment = $Lighting/WorldEnvironment.environment
	env.fog_enabled = not on
	env.background_mode = Environment.BG_COLOR if on else Environment.BG_SKY
	env.background_color = Color(0.075, 0.065, 0.055)
	env.fog_density = 0.00006
	env.fog_aerial_perspective = 0.03
	globe.visible = on
	globe.camera.current = on
	landscape.visible = not on
	camera_rig.camera.current = not on
	camera_rig.set_process(not on)
	camera_rig.set_process_unhandled_input(not on)


func _on_zoom_limit(inward: bool, screen_position: Vector2) -> void:
	if inward:
		var hit: Variant = camera_rig.ground_point_under(screen_position)
		if hit != null:
			deepen_at(hit)
	else:
		zoom_out()


func _on_level_pressed(index: int) -> void:
	if index == 0:
		open_globe()
		return
	if in_globe:
		open_continent()
		return
	var target := index - 1
	if target >= levels.size() - 1:
		return
	var child: Dictionary = levels[target + 1]
	levels.resize(target + 1)
	_show_level()
	camera_rig.jump_to(landscape.to_render(child["cx"], child["cy"]), camera_rig.min_distance * 1.3)


# --- Werkzeuge -----------------------------------------------------------------------------

func _on_tool(p_tool: String) -> void:
	tool = p_tool
	landscape.tool = tool
	_on_brush(size_fraction, strength)


func _on_brush(fraction: float, p_strength: float) -> void:
	size_fraction = fraction
	strength = p_strength
	if levels.is_empty():
		return
	var radius: float = fraction * levels.back()["size"]
	landscape.brush_radius_m = radius
	landscape.brush_strength = stroke_strength(tool, radius, p_strength)


## Stärke eines Strichs: Erhöhen/Senken in Metern, sonst Anteil.
static func stroke_strength(p_tool: String, radius: float, slider: float) -> float:
	if p_tool in ["raise", "lower"]:
		return slider * clampf(radius * 0.25, 1.0, 1500.0)
	return slider


func _on_stroke_finished(stroke: Dictionary) -> void:
	_painted_live = true
	doc.execute(WorldDocument.add_stroke_command(0, stroke))
	_painted_live = false


func _on_variant() -> void:
	var next := FixedRandom.derive(continent()["seed"], "Variante") & 0x7FFFFFFF
	doc.execute(doc.set_command(0, "seed", next))


func _on_placement(key: String, value: float, final: bool) -> void:
	if not _placement_before.has(key):
		_placement_before[key] = doc.get_value(0, key)
	if not final:
		# Vorschau ohne Verlaufseintrag; der Schritt entsteht beim Loslassen.
		doc.preview_value(0, key, value)
		_after_placement_preview(key)
		return
	var before: Variant = _placement_before[key]
	_placement_before.erase(key)
	doc.preview_value(0, key, before)
	if is_equal_approx(float(before), value):
		return
	if key == "size_km":
		var count := (continent()["strokes"] as Array).size()
		doc.execute(doc.resize_command(0, value, before))
		if count > 0:
			_notice = "%d Bearbeitung%s mitvergrößert (Rückgängig mit Strg/⌘+Z)" % [count, "" if count == 1 else "en"]
			_update_ui()
	else:
		doc.execute(doc.set_command(0, key, value, before))


func _after_placement_preview(key: String) -> void:
	if key.begins_with("climate") or key == "latitude":
		sampler.climate = Climate.derive(continent()["latitude"], doc.planet, continent()["climate_override"])
	globe.update_placement(continent(), doc.planet)
	ui.set_placement(continent(), sampler.climate)


# --- Änderungen am Dokument ----------------------------------------------------------------

func _on_doc_changed(command: Dictionary, undone: bool) -> void:
	_queue_save()
	if command["kind"] == "add_stroke" and not undone and _painted_live:
		# Der aktuelle Ausschnitt ist schon live bemalt; gröbere werden beim nächsten Zeigen neu berechnet.
		_continent_window = null
		for i in levels.size() - 1:
			levels[i]["window"] = null
		_update_ui()
		return
	_forget_windows()
	_rebuild_sampler()
	if in_globe:
		globe.show_continent(continent(), doc.planet, _coarse_window())
		_update_ui()
	else:
		if command["kind"] == "resize":
			open_continent()
		else:
			_show_level()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed():
		var key := (event as InputEventKey).keycode
		if key == KEY_Z and not event.shift_pressed:
			doc.undo()
			get_viewport().set_input_as_handled()
		elif key == KEY_Y or (key == KEY_Z and event.shift_pressed):
			doc.redo()
			get_viewport().set_input_as_handled()


func _queue_save() -> void:
	ui.set_saved(false)
	_save_timer.start()


func _save_now() -> void:
	var error := doc.save(save_path)
	ui.set_saved(error == OK)
	if error != OK:
		push_error("Speichern fehlgeschlagen (%s): %s" % [error, save_path])


# --- Anzeige -------------------------------------------------------------------------------

func _update_ui() -> void:
	var names := ["Welt", "Kontinent"]
	for i in range(1, levels.size()):
		names.append("Region 1:%d" % int(pow(FACTOR, i)))
	var current := 0 if in_globe else levels.size()
	ui.set_levels(names if not in_globe else ["Welt", "Kontinent"], current)
	ui.set_mode(in_globe, levels.size() == 1)
	ui.set_history(doc.can_undo(), doc.can_redo())
	ui.set_placement(continent(), sampler.climate)
	var c := continent()
	var strokes: int = (c["strokes"] as Array).size()
	var origin := "Grundform erzeugt aus Ausgangswert %d · %d Bearbeitung%s" % [c["seed"], strokes, "" if strokes == 1 else "en"]
	if _notice != "":
		origin = _notice + " · " + origin
		_notice = ""
	if in_globe:
		ui.set_status("Globus · Ziehen dreht · am Anschlag weiter hineinzoomen öffnet den Kontinent · " + origin)
	else:
		var current_level: Dictionary = levels.back()
		ui.set_status("Ausschnitt %s · Höhen %s-fach überhöht · %s · Klima: %s · am Zoom-Anschlag weiterzoomen wechselt den Maßstab" % [
			EditorUI.meters(current_level["size"]), String.num(landscape.exaggeration, 1).replace(".", ","),
			origin, sampler.climate["zone"]])


func _on_hover(_x: float, _y: float, _valid: bool) -> void:
	pass


# --- Vorführung ----------------------------------------------------------------------------

func _screenshot_and_quit(path: String) -> void:
	await _frames(30)
	await _shot(path)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if path.ends_with(".jpg"):
		image.save_jpg(path, 0.88)
	else:
		image.save_png(path)
	print("Bild: ", path)


func _measure(label: String, results: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(30)
	var started := Time.get_ticks_usec()
	await _frames(120)
	var ms := (Time.get_ticks_usec() - started) / 1000.0 / 120.0
	results[label] = {
		"frame_ms": ms,
		"fps": 1000.0 / ms,
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## Spielt den Nachweis durch: Globus → Kontinent → Kontur ändern → vertiefen → Wald und Höhe im
## Detail → herauszoomen → Rückgängig/Wiederholen → speichern. Bilder und Messwerte in dir.
func _run_demo(dir: String) -> void:
	var results := {}
	var timing := {}
	await _frames(20)
	open_globe()
	await _frames(20)
	await _shot(dir.path_join("1_globus.jpg"))
	await _measure("Globus", results)

	open_continent()
	await _frames(20)
	await _shot(dir.path_join("2_kontinent.jpg"))
	await _measure("Kontinent", results)

	# Kontur ändern: an der Ostküste Land anfügen.
	var half: float = continent()["size_km"] * 500.0
	var coast := _find_coast(Vector2(1.0, 0.15), half)
	camera_rig.jump_to(landscape.to_render(coast.x, coast.y), 520.0)
	await _frames(20)
	await _shot(dir.path_join("3a_kueste_vorher.jpg"))
	var bump := Stroke.create("land_add", half * 0.08, 1.0)
	Stroke.add_point(bump, coast.x + half * 0.04, coast.y - half * 0.08)
	Stroke.add_point(bump, coast.x + half * 0.10, coast.y + half * 0.04)
	var t0 := Time.get_ticks_usec()
	doc.execute(WorldDocument.add_stroke_command(0, bump))
	timing["Kontur ändern (Kontinent neu berechnen)"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(20)
	await _shot(dir.path_join("3b_kueste_nachher.jpg"))
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.9)

	# Einen Landpunkt suchen und zweimal vertiefen (1:8, 1:64).
	var p := _find_land(800.0)
	for i in 2:
		t0 = Time.get_ticks_usec()
		deepen_at(landscape.to_render(p.x, p.y))
		timing["Vertiefen auf %s" % EditorUI.meters(levels.back()["size"])] = (Time.get_ticks_usec() - t0) / 1000.0
		await _frames(15)
	await _shot(dir.path_join("4_region.jpg"))
	await _measure("Region 1:64", results)

	# Noch einmal vertiefen (1:512 ≈ 1,6 km) und dort Wald malen und erhöhen.
	deepen_at(landscape.to_render(p.x, p.y))
	await _frames(15)
	await _shot(dir.path_join("5_ausschnitt_vorher.jpg"))
	var forest := Stroke.create("forest_add", 260.0, 1.0)
	for k in 7:
		Stroke.add_point(forest, p.x - 400.0 + k * 130.0, p.y + 200.0 * sin(k * 0.8))
	var hill := Stroke.create("raise", 220.0, 60.0)
	Stroke.add_point(hill, p.x + 350.0, p.y - 300.0)
	Stroke.add_point(hill, p.x + 420.0, p.y - 250.0)
	t0 = Time.get_ticks_usec()
	doc.execute(WorldDocument.add_stroke_command(0, forest))
	doc.execute(WorldDocument.add_stroke_command(0, hill))
	timing["Zwei Striche im Ausschnitt (neu berechnen)"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(15)
	await _shot(dir.path_join("6_ausschnitt_bearbeitet.jpg"))
	await _measure("Ausschnitt 1:512 mit Bäumen", results)

	# Herauszoomen: Änderungen vereinfacht und markiert am richtigen Ort.
	zoom_out()
	await _frames(15)
	await _shot(dir.path_join("7_region_danach.jpg"))
	zoom_out()
	zoom_out()
	await _frames(15)
	camera_rig.jump_to(landscape.to_render(p.x, p.y), camera_rig.min_distance * 1.5)
	await _frames(15)
	await _shot(dir.path_join("8_kontinent_danach.jpg"))

	# Rückgängig (Wald) und Wiederholen, in der Detailansicht.
	for i in 3:
		deepen_at(landscape.to_render(p.x, p.y))
	doc.undo()
	doc.undo()
	await _frames(15)
	await _shot(dir.path_join("9_rueckgaengig.jpg"))
	doc.redo()
	doc.redo()
	await _frames(15)
	await _shot(dir.path_join("10_wiederholt.jpg"))

	# Mit der Maus malen (echte Eingabeereignisse): Wald quer durchs Bild.
	_on_tool("forest_add")
	var before := (continent()["strokes"] as Array).size()
	var view_size := get_viewport().get_visible_rect().size
	var start := view_size * Vector2(0.35, 0.6)
	_send_mouse(start, true, true)
	t0 = Time.get_ticks_usec()
	for k in 30:
		_send_motion(start + Vector2(k * 14.0, -k * 4.0))
		await get_tree().process_frame
	timing["30 Mausbewegungen beim Malen (je Bild)"] = (Time.get_ticks_usec() - t0) / 1000.0 / 30.0
	_send_mouse(start + Vector2(29 * 14.0, -29 * 4.0), false, true)
	await _frames(15)
	results["Mit der Maus gemalt"] = {"strokes_before": before, "strokes_after": (continent()["strokes"] as Array).size()}
	await _shot(dir.path_join("12_mit_maus_gemalt.jpg"))
	_on_tool("navigate")

	# Feinste Stufe (1:4096, rund 390 m): einzelne Bäume aus Blattkarten.
	var hit: Variant = camera_rig.ground_point_under(start + Vector2(14.0 * 15, -4.0 * 15))
	if hit != null:
		deepen_at(hit)
		camera_rig.jump_to(Vector3.ZERO, camera_rig.min_distance * 2.5)
		await _frames(20)
		await _shot(dir.path_join("13_ausschnitt_390m.jpg"))
		await _measure("Ausschnitt 1:4096 mit Blattkarten-Bäumen", results)

	# Uferausschnitt (1:4096) im Zielstil: Felsen, klares Flachwasser, Wiese, Bäume.
	open_continent()
	var half2: float = continent()["size_km"] * 500.0
	var direction := Vector2(-0.3, -1.0).normalized()
	var shore := _find_coast(direction, half2)
	# Grob vertiefen, dann die Küste im feinen Ausschnitt selbst suchen (grob ist sie Kilometer ungenau).
	for i in 3:
		deepen_at(landscape.to_render(shore.x, shore.y))
	var w: TerrainWindow = levels.back()["window"]
	var scan_from := Vector2(w.cx, w.cy) - direction * w.size * 0.45
	for s in 400:
		var q := scan_from + direction * (w.size * 0.9 * s / 400.0)
		if w.height_at(q.x, q.y) < -0.5:
			shore = q
			break
	var center := shore - direction * 110.0
	deepen_at(landscape.to_render(center.x, center.y))
	camera_rig.jump_to(landscape.to_render(shore.x, shore.y).lerp(Vector3.ZERO, 0.15), camera_rig.min_distance * 1.15)
	await _frames(25)
	await _shot(dir.path_join("14_ufer_390m.jpg"))
	await _measure("Uferausschnitt 1:4096 im Zielstil", results)

	_save_now()
	var report := {"views": results, "timing_ms": timing, "point": [p.x, p.y], "world_file": ProjectSettings.globalize_path(save_path),
		"gpu": RenderingServer.get_video_adapter_name(), "resolution": str(get_viewport().get_visible_rect().size)}
	var file := FileAccess.open(dir.path_join("messwerte.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	get_tree().quit()


func _send_mouse(position: Vector2, pressed: bool, left: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = position
	e.global_position = position
	e.button_index = MOUSE_BUTTON_LEFT if left else MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	Input.parse_input_event(e)


func _send_motion(position: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = position
	e.global_position = position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _find_coast(direction: Vector2, half: float) -> Vector2:
	var w := _coarse_window()
	# Von außen nach innen: der erste Landpunkt ist die Küste (Seen im Inneren zählen nicht).
	var d := direction.normalized()
	for s in 200:
		var q := d * half * (1.0 - s / 200.0)
		if w.height_at(q.x, q.y) > 0.0:
			return q
	return Vector2.ZERO


func _find_land(max_height: float) -> Vector2:
	var w := _coarse_window()
	var half: float = continent()["size_km"] * 500.0
	for s in 400:
		var a := s * 2.399963
		var r := half * 0.5 * sqrt(s / 400.0)
		var q := Vector2(cos(a), sin(a)) * r
		var h := w.height_at(q.x, q.y)
		if h > 60.0 and h < max_height and w.forest_at(q.x, q.y) < 0.3:
			return q
	return Vector2.ZERO
