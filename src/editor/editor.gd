extends Node3D
## Der Editor: Weltdokument, Maßstäbe (Globus → Kontinent → Ausschnitte), Werkzeuge, Speichern.
##
## Auf dem Globus liegen beliebig viele Kontinente; einer ist gewählt (active_id). Ein Ausschnitt
## ist ein Fenster (Mitte, Größe) auf dem geöffneten Kontinent; „Vertiefen“ öffnet eines mit 1/8
## der Größe (Annahme A3). Alle Maßstäbe werten dieselbe Strichliste aus – eine Welt.
##
## Aufruf-Schalter (nach `--`): --welt=<Pfad> eigene Weltdatei · --neu neue, leere Welt (ohne
## --welt in einer eigenen Testdatei, nie in der Hauptwelt) · --demo=<Ordner> Ablauf vorführen ·
## --abnahme=<Ordner> Abnahmeablauf (Schritt über --schritt=1|2) · --vergleich=<Ordner> Vergleich mit
## der Kontinentalreferenz (ComparisonRun) · --screenshot=<Pfad>.

const DEFAULT_PATH := "user://welt.json"
const FACTOR := 8.0
const SMALLEST := 190.0
## Auflösung der Kontinentbilder auf dem Globus und in der Übersichtskarte.
const GLOBE_RES := 129

@onready var landscape: LandscapeView = $Landscape
@onready var camera_rig: StrategyCamera = $CameraRig
@onready var globe: GlobeView = $Globe
@onready var ui: EditorUI = $Interface

var doc: WorldDocument
var save_path := DEFAULT_PATH
var active_id := ""
var sampler: TerrainSampler
var levels: Array = []
var in_globe := false
var tool := "navigate"
var size_fraction := 0.04
var strength := 0.6
var _samplers := {}
var _globe_windows := {}
var _painted_live := false
var _placement_before := {}
var _drag_before := {}
var _save_timer: Timer
var _view_timer: Timer
var _args := {}
## Einmaliger Hinweis in der Statuszeile (bis zur nächsten Änderung).
var _notice := ""
var _confirm: ConfirmationDialog
## Ungespeicherte Änderungen vorhanden.
var _dirty := false
## Laufender Vergleich mit der Referenz (hält das Objekt am Leben, solange es wartet).
var _comparison: ComparisonRun


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else ""
	if _args.has("demo"):
		save_path = _args["demo"].path_join("welt.json")
		DirAccess.make_dir_recursive_absolute(_args["demo"])
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
	if _args.has("abnahme"):
		save_path = _args["abnahme"].path_join("welt.json")
		DirAccess.make_dir_recursive_absolute(_args["abnahme"])
	if _args.has("vergleich"):
		save_path = _args["vergleich"].path_join("welt.json")
		DirAccess.make_dir_recursive_absolute(_args["vergleich"])
	if _args.has("neu") and not _args.has("welt") and not _args.has("demo") and not _args.has("abnahme"):
		# Eine neue Welt zum Ausprobieren berührt nie die Hauptwelt.
		save_path = "user://welt_neu.json"
	save_path = _args.get("welt", save_path)
	var fresh: bool = _args.has("neu") or _args.has("vergleich") or (_args.has("abnahme") and _args.get("schritt", "1") == "1")

	doc = null if fresh else WorldDocument.load_file(save_path)
	if WorldDocument.load_problem != "":
		_notice = WorldDocument.load_problem
	var rescue := save_path.get_basename() + "_ersatz.json"
	if doc == null and not fresh and FileAccess.file_exists(save_path) and FileAccess.file_exists(rescue):
		# Hauptdatei beschädigt, aber schon eine Ersatzwelt angelegt: dort weiterarbeiten.
		doc = WorldDocument.load_file(rescue)
		if doc:
			save_path = rescue
			_notice = "Weltdatei beschädigt – es wird in %s weitergearbeitet." % rescue.get_file()
	if doc == null:
		if _args.has("demo"):
			doc = WorldDocument.create(4242)
		else:
			doc = WorldDocument.new()
		if not fresh and FileAccess.file_exists(save_path):
			# Beschädigte Datei ohne guten Ersatz: nichts überschreiben, bis der Spielleiter handelt.
			save_path = rescue
			_notice += " Neue Welt wird unter %s gespeichert." % save_path.get_file()
	doc.changed.connect(_on_doc_changed)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)
	_view_timer = Timer.new()
	_view_timer.one_shot = true
	_view_timer.wait_time = 1.0
	_view_timer.timeout.connect(_save_view)
	add_child(_view_timer)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Kontinent löschen"
	_confirm.ok_button_text = "Löschen"
	_confirm.cancel_button_text = "Behalten"
	_confirm.confirmed.connect(_delete_active)
	add_child(_confirm)

	landscape.camera = camera_rig.camera
	landscape.stroke_finished.connect(_on_stroke_finished)
	landscape.hint.connect(func(text: String) -> void:
		_notice = text
		_update_ui())
	camera_rig.zoom_limit.connect(_on_zoom_limit)
	globe.enter_continent.connect(func() -> void: open_continent(active_id))
	globe.continent_clicked.connect(_select)
	globe.continent_opened.connect(func(id: String) -> void: open_continent(id))
	globe.empty_clicked.connect(func() -> void: _select(""))
	globe.continent_dragged.connect(_on_continent_dragged)
	globe.continent_drag_cancelled.connect(_on_continent_drag_cancelled)
	ui.tool_selected.connect(_on_tool)
	ui.brush_changed.connect(_on_brush)
	ui.undo_pressed.connect(_undo)
	ui.redo_pressed.connect(_redo)
	ui.level_pressed.connect(_on_level_pressed)
	ui.variant_pressed.connect(_on_variant)
	ui.globe_pressed.connect(func() -> void: open_globe())
	ui.edit_continent_pressed.connect(func() -> void: open_continent(active_id))
	ui.marks_toggled.connect(func(on: bool) -> void: landscape.show_marks = on)
	ui.placement_changed.connect(_on_placement)
	ui.new_continent_pressed.connect(_on_new_continent)
	ui.delete_continent_pressed.connect(_ask_delete)
	ui.name_changed.connect(_on_name_changed)
	ui.reroll_pressed.connect(_on_reroll)
	ui.minimap_clicked.connect(_on_minimap_clicked)
	ui.set_saved(true)

	_apply_target_light()
	if not doc.continents.is_empty():
		active_id = doc.continents[0]["id"]
	if _args.has("demo"):
		open_continent(active_id)
		_run_demo(_args["demo"])
		return
	if not fresh and _restore_view():
		pass
	else:
		open_globe()
	if _args.has("vergleich"):
		_comparison = ComparisonRun.new(self)
		_comparison.run(_args["vergleich"])
	elif _args.has("stufen"):
		_run_levels(_args["stufen"])
	elif _args.has("abnahme"):
		_run_acceptance(_args["abnahme"], _args.get("schritt", "1"))
	elif _args.has("screenshot"):
		_screenshot_and_quit(_args["screenshot"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and doc:
		if _dirty:
			_save_now()
		_save_view()


## Licht wie in der Zielszene: warme Sonne von links hinten, weiche Verschattung.
func _apply_target_light() -> void:
	var sun: DirectionalLight3D = $Lighting/Sun
	sun.rotation = Vector3(-0.86, -2.05, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.54)
	sun.light_energy = 2.75
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 2.6
	if _args.get("schatten", "") == "aus":
		sun.shadow_enabled = false
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


# --- Kontinente ----------------------------------------------------------------------------

func continent() -> Dictionary:
	return doc.continent(active_id)


## Anzeigename: der vom Spielleiter vergebene Name, sonst neutral nach Platz (nicht gespeichert).
func display_name(id: String) -> String:
	var c := doc.continent(id)
	if c.is_empty():
		return "Kontinent"
	var name: String = c.get("name", "")
	return name if name != "" else "Kontinent %d" % (doc.index_of(id) + 1)


func sampler_for(id: String) -> TerrainSampler:
	if not _samplers.has(id):
		_samplers[id] = TerrainSampler.new(doc.continent(id), doc.planet)
	return _samplers[id]


## Grober Ausschnitt eines ganzen Kontinents (für Globus, Übersicht und Fläche).
func globe_window(id: String) -> TerrainWindow:
	if not _globe_windows.has(id):
		var c := doc.continent(id)
		_globe_windows[id] = sampler_for(id).window(0.0, 0.0, c["size_km"] * 1000.0, GLOBE_RES)
	return _globe_windows[id]


func _forget(id: String) -> void:
	_samplers.erase(id)
	_globe_windows.erase(id)


func _select(id: String) -> void:
	ui.commit_name()
	active_id = id
	globe.select(id)
	_update_ui()


func _on_new_continent(drawn: bool) -> void:
	ui.commit_name()
	var center := globe.view_center() if in_globe else Vector2(35.0, 10.0)
	var seed_value := Crypto.new().generate_random_bytes(4).decode_u32(0) & 0x7FFFFFFF
	var data := WorldDocument.new_continent(seed_value, WorldDocument.BASE_DRAWN if drawn else WorldDocument.BASE_GENERATED,
		1600.0, clampf(center.x, -70.0, 70.0), center.y)
	doc.execute(WorldDocument.add_continent_command(data))
	active_id = data["id"]
	if drawn:
		open_continent(active_id)
		ui.select_tool("shape_add")
		_on_tool("shape_add")
		_notice = "Neuer Kontinent: mit gedrückter linker Maustaste den Umriss ziehen."
		_update_ui()
	else:
		_select(active_id)


func _ask_delete() -> void:
	if active_id == "":
		return
	ui.commit_name()
	_confirm.dialog_text = "„%s“ vom Globus entfernen?\nRückgängig ist mit Strg/⌘ + Z möglich." % display_name(active_id)
	_confirm.popup_centered()


func _delete_active() -> void:
	if active_id == "" or not doc.has_continent(active_id):
		return
	doc.execute(doc.remove_continent_command(active_id))


func _on_name_changed(text: String) -> void:
	var name := text.strip_edges()
	if active_id == "" or not doc.has_continent(active_id) or name == continent().get("name", ""):
		return
	doc.execute(doc.set_command(active_id, "name", name))


# --- Maßstäbe ------------------------------------------------------------------------------

func open_continent(id: String) -> void:
	if id == "" or not doc.has_continent(id):
		return
	ui.commit_name()
	active_id = id
	sampler = sampler_for(id)
	levels = [{"cx": 0.0, "cy": 0.0, "size": continent()["size_km"] * 1000.0}]
	_set_globe(false)
	_show_level()
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.9)
	_queue_view()


func open_globe() -> void:
	_set_globe(true)
	_refresh_globe()
	globe.select(active_id)
	if active_id != "":
		globe.face(continent()["latitude"], continent()["longitude"])
	_update_ui()
	_queue_view()


func _refresh_globe() -> void:
	var windows := []
	for c in doc.continents:
		windows.append(globe_window(c["id"]))
	globe.show_world(doc.continents, doc.planet, windows)


func deepen_at(render_point: Vector3) -> void:
	var current: Dictionary = levels.back()
	var size: float = current["size"] / FACTOR
	if size < SMALLEST:
		return
	var half: float = continent()["size_km"] * 500.0
	# Mitte auf das Raster des neuen Ausschnitts einrasten (gleiche Punkte bei Wiederkehr) und im
	# Kontinentfenster halten.
	var cell := size / 256.0
	var cx := clampf(snappedf(landscape.continent_x(render_point), cell), -half, half)
	var cy := clampf(snappedf(landscape.continent_y(render_point), cell), -half, half)
	levels.append({"cx": cx, "cy": cy, "size": size})
	doc.remember_region(active_id, cx, cy, size)
	_queue_save()
	_show_level()
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.95)
	_queue_view()


func zoom_out() -> void:
	if levels.size() <= 1:
		open_globe()
		return
	var child: Dictionary = levels.pop_back()
	_show_level()
	camera_rig.jump_to(landscape.to_render(child["cx"], child["cy"]), camera_rig.min_distance * 1.3)
	_queue_view()


## Den aktuellen Ausschnitt an eine andere Stelle des Kontinents verlegen (gleiche Größe).
## Nachbarbereiche sind dieselbe Auswertung – die Übergänge passen ohne Naht.
func move_level_to(x: float, y: float, remember: bool = true) -> void:
	if levels.size() <= 1:
		camera_rig.jump_to(landscape.to_render(x, y), camera_rig.min_distance * 2.0)
		return
	var level: Dictionary = levels.back()
	var half: float = continent()["size_km"] * 500.0
	var cell: float = level["size"] / 256.0
	level["cx"] = clampf(snappedf(x, cell), -half, half)
	level["cy"] = clampf(snappedf(y, cell), -half, half)
	level["window"] = null
	if remember:
		doc.remember_region(active_id, level["cx"], level["cy"], level["size"])
		_queue_save()
	_follow_parents()
	_show_level()
	if remember:
		camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.6)
	_queue_view()


## Übergeordnete Ausschnitte nachziehen, sobald ihr feinerer Ausschnitt ihren inneren Bereich
## verlässt – so bleibt die Umgebung vollständig und Herauszoomen landet an derselben Stelle.
func _follow_parents() -> void:
	var half: float = continent()["size_km"] * 500.0
	for i in range(levels.size() - 2, 0, -1):
		var parent: Dictionary = levels[i]
		var child: Dictionary = levels[i + 1]
		var inner: float = parent["size"] * 0.3
		if absf(child["cx"] - parent["cx"]) <= inner and absf(child["cy"] - parent["cy"]) <= inner:
			continue
		var cell: float = parent["size"] / 256.0
		parent["cx"] = clampf(snappedf(child["cx"], cell), -half, half)
		parent["cy"] = clampf(snappedf(child["cy"], cell), -half, half)
		parent["window"] = null


## Mitführen: Nähert sich der Blickpunkt dem Rand eines feineren Ausschnitts, wandert der Ausschnitt
## mit. Die Stelle unter dem Blickpunkt bleibt dabei an ihrem Platz im Bild.
func _process(_delta: float) -> void:
	_update_scale_bar()
	if in_globe or levels.size() <= 1 or landscape.is_busy() or landscape.window == null:
		return
	var f := camera_rig.focus_point()
	var limit := LandscapeView.PLANE * 0.34
	if absf(f.x) < limit and absf(f.z) < limit:
		return
	var p := landscape.to_continent(f)
	var level: Dictionary = levels.back()
	var half: float = continent()["size_km"] * 500.0
	var target := Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))
	# Am Kontinentrand bewegt sich der Ausschnitt nicht weiter – dann nicht jedes Bild neu rechnen.
	if target.distance_to(Vector2(level["cx"], level["cy"])) < level["size"] * 0.1:
		return
	move_level_to(target.x, target.y, false)
	var now := landscape.to_render(p.x, p.y)
	camera_rig.shift_focus(Vector3(now.x - f.x, 0.0, now.z - f.z))


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
	landscape.continent_seed = continent()["seed"]
	landscape.show_window(w, sampler, continent()["regions"], parent)
	ui.set_window_size(current["size"])
	_on_brush(size_fraction, strength)
	_update_minimap()
	_update_ui()
	print("Ausschnitt %s berechnet in %d ms" % [EditorUI.meters(current["size"]), (Time.get_ticks_usec() - started) / 1000])


func _update_minimap() -> void:
	if active_id == "" or levels.is_empty():
		return
	var w := globe_window(active_id)
	var image := GlobeView.bake_colors(w)
	# Meer sichtbar machen (im Globusbild durchsichtig).
	image.convert(Image.FORMAT_RGBA8)
	for j in image.get_height():
		for i in image.get_width():
			var c := image.get_pixel(i, j)
			image.set_pixel(i, j, Color(0.06, 0.2, 0.32).lerp(Color(c.r, c.g, c.b), c.a))
	var full := w.size
	var level: Dictionary = levels.back()
	var s: float = level["size"] / full
	var x0: float = (level["cx"] - level["size"] * 0.5 + full * 0.5) / full
	var y0: float = (full * 0.5 - (level["cy"] + level["size"] * 0.5)) / full
	ui.set_minimap(image, Rect2(x0, y0, s, s))


func _on_minimap_clicked(fraction: Vector2) -> void:
	if active_id == "":
		return
	var full: float = continent()["size_km"] * 1000.0
	move_level_to((fraction.x - 0.5) * full, (0.5 - fraction.y) * full)


func _set_globe(on: bool) -> void:
	in_globe = on
	var env: Environment = $Lighting/WorldEnvironment.environment
	env.fog_enabled = not on
	env.background_mode = Environment.BG_COLOR if on else Environment.BG_SKY
	env.background_color = Color(0.075, 0.065, 0.055)
	env.fog_density = 0.00006
	env.fog_aerial_perspective = 0.03
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if on else Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.42, 0.44, 0.5)
	($Lighting/Sun as DirectionalLight3D).visible = not on
	globe.visible = on
	globe.camera.current = on
	landscape.visible = not on
	camera_rig.camera.current = not on
	camera_rig.set_process(not on)
	camera_rig.set_process_unhandled_input(not on)


func _on_zoom_limit(inward: bool, screen_position: Vector2) -> void:
	if landscape.is_busy():
		return
	if inward:
		var hit: Variant = camera_rig.ground_point_under(screen_position)
		if hit != null:
			deepen_at(hit)
	else:
		zoom_out()


## Pfad oben: 0 = Welt, 1 = Kontinent, 2 = Region (die aktuelle – bleibt, wo sie ist).
func _on_level_pressed(index: int) -> void:
	if index == 0:
		open_globe()
		return
	if in_globe:
		open_continent(active_id)
		return
	if index >= 2 or levels.size() <= 1:
		return
	var child: Dictionary = levels[1]
	levels.resize(1)
	_show_level()
	camera_rig.jump_to(landscape.to_render(child["cx"], child["cy"]), camera_rig.min_distance * 1.3)
	_queue_view()


# --- Werkzeuge -----------------------------------------------------------------------------

func _on_tool(p_tool: String) -> void:
	tool = p_tool
	landscape.tool = tool
	_on_brush(size_fraction, strength)
	_update_ui()


func _on_brush(fraction: float, p_strength: float) -> void:
	size_fraction = fraction
	strength = p_strength
	if levels.is_empty():
		return
	var radius: float = fraction * levels.back()["size"]
	landscape.brush_radius_m = radius
	landscape.brush_strength = stroke_strength(tool, radius, p_strength)
	if active_id != "" and doc.has_continent(active_id):
		landscape.generator_seed = next_generator_seed()


## Stärke eines Strichs: Erhöhen/Senken/Gebirge/Hügel in Metern, sonst Anteil.
static func stroke_strength(p_tool: String, radius: float, slider: float) -> float:
	match p_tool:
		"raise", "lower":
			return slider * clampf(radius * 0.25, 1.0, 1500.0)
		"gen_mountains":
			return slider * clampf(radius * 0.12, 15.0, 3800.0)
		"gen_hills":
			return slider * clampf(radius * 0.04, 4.0, 700.0)
		"gen_islands":
			return slider * 1.6
	return slider


## Ausgangswert der nächsten Erzeugung: fest aus Kontinent und Zahl der Bearbeitungen.
func next_generator_seed() -> int:
	var c := continent()
	return FixedRandom.derive(c["seed"], "Erzeugung %d" % (c["strokes"] as Array).size()) & 0x7FFFFFFF


func _on_stroke_finished(stroke: Dictionary) -> void:
	if active_id == "":
		return
	# Pinsel wurden schon live in den Ausschnitt gemalt; Linien, Seen und Formen werden neu berechnet.
	_painted_live = stroke["tool"] in Stroke.BRUSH_TOOLS or stroke["tool"] in Stroke.GENERATE_TOOLS
	doc.execute(WorldDocument.add_stroke_command(active_id, stroke))
	_painted_live = false


func _on_variant() -> void:
	var next := FixedRandom.derive(continent()["seed"], "Variante") & 0x7FFFFFFF
	doc.execute(doc.set_command(active_id, "seed", next))


## Die letzte Erzeugung an gleicher Stelle mit neuem Ausgangswert.
func _on_reroll() -> void:
	var strokes: Array = continent()["strokes"]
	if strokes.is_empty() or not Stroke.is_generator(strokes.back()):
		return
	var stroke: Dictionary = (strokes.back() as Dictionary).duplicate(true)
	stroke["seed"] = FixedRandom.derive(int(stroke["seed"]), "neu gewürfelt") & 0x7FFFFFFF
	doc.execute(doc.replace_stroke_command(active_id, strokes.size() - 1, stroke))


func _on_placement(key: String, value: float, final: bool) -> void:
	var target := active_id
	var field := key
	if key.begins_with("planet."):
		target = WorldDocument.PLANET
		field = key.trim_prefix("planet.")
	elif active_id == "":
		return
	var memo := target + "|" + field
	if not _placement_before.has(memo):
		_placement_before[memo] = doc.get_value(target, field)
	if not final:
		# Vorschau ohne Verlaufseintrag; der Schritt entsteht beim Loslassen.
		doc.preview_value(target, field, value)
		_after_placement_preview(field)
		return
	var before: Variant = _placement_before[memo]
	_placement_before.erase(memo)
	doc.preview_value(target, field, before)
	if is_equal_approx(float(before), value):
		return
	if field == "size_km" and target != WorldDocument.PLANET:
		var count := (continent()["strokes"] as Array).size()
		doc.execute(doc.resize_command(target, value, before))
		if count > 0:
			_notice = "%d Bearbeitung%s mitvergrößert (Rückgängig mit Strg/⌘ + Z)" % [count, "" if count == 1 else "en"]
			_update_ui()
	else:
		doc.execute(doc.set_command(target, field, value, before))


func _after_placement_preview(field: String) -> void:
	if active_id != "" and (field.begins_with("climate") or field == "latitude"):
		sampler_for(active_id).climate = Climate.derive(continent()["latitude"], doc.planet, continent()["climate_override"])
	globe.update_placement(doc.continents, doc.planet)
	if active_id != "":
		ui.set_placement(continent(), sampler_for(active_id).climate)


## Kontinent auf dem Globus ziehen: Vorschau, beim Loslassen ein einziger Schritt.
func _on_continent_dragged(id: String, latitude: float, longitude: float, final: bool) -> void:
	if not doc.has_continent(id):
		return
	if _drag_before.get("id", "") != id:
		_restore_drag()
		_drag_before = {"id": id, "latitude": doc.get_value(id, "latitude"), "longitude": doc.get_value(id, "longitude")}
	if not final:
		doc.preview_value(id, "latitude", latitude)
		doc.preview_value(id, "longitude", longitude)
		globe.update_placement(doc.continents, doc.planet)
		ui.set_placement(continent(), sampler_for(id).climate)
		return
	var before := _drag_before
	_drag_before = {}
	doc.preview_value(id, "latitude", before["latitude"])
	doc.preview_value(id, "longitude", before["longitude"])
	doc.execute(WorldDocument.group_command([
		doc.set_command(id, "latitude", latitude, before["latitude"]),
		doc.set_command(id, "longitude", longitude, before["longitude"])]))


func _on_continent_drag_cancelled(_id: String) -> void:
	_restore_drag()
	globe.update_placement(doc.continents, doc.planet)
	_update_ui()


## Laufende Ziehvorschau verwerfen: alte Lage zurück, ohne Verlaufseintrag.
func _restore_drag() -> void:
	if _drag_before.is_empty():
		return
	var id: String = _drag_before["id"]
	if doc.has_continent(id):
		doc.preview_value(id, "latitude", _drag_before["latitude"])
		doc.preview_value(id, "longitude", _drag_before["longitude"])
	_drag_before = {}


# --- Änderungen am Dokument ----------------------------------------------------------------

## Gesperrt, solange gemalt oder ein Regler bzw. Kontinent gezogen wird.
func _history_locked() -> bool:
	return landscape.is_busy() or not _placement_before.is_empty() or not _drag_before.is_empty()


func _undo() -> void:
	if not _history_locked():
		doc.undo()


func _redo() -> void:
	if not _history_locked():
		doc.redo()


func _on_doc_changed(command: Dictionary, undone: bool) -> void:
	_queue_save()
	var id := WorldDocument.command_continent(command)
	if id == WorldDocument.PLANET:
		if in_globe:
			globe.update_placement(doc.continents, doc.planet)
		_update_ui()
		return
	_forget(id)
	# Der offene Kontinent ist verschwunden (gelöscht, Anlegen rückgängig): zum Globus.
	if active_id != "" and not doc.has_continent(active_id):
		active_id = doc.continents.back()["id"] if not doc.continents.is_empty() else ""
		if not in_globe:
			open_globe()
			return
	if command["kind"] == "add_continent" and not undone:
		active_id = id
	if in_globe:
		_refresh_globe()
		globe.select(active_id)
		_update_ui()
		return
	if id != active_id:
		_notice = "Änderung betraf „%s“ – auf dem Globus sichtbar." % display_name(id)
		_update_ui()
		return
	sampler = sampler_for(active_id)
	if command["kind"] == "add_stroke" and not undone and _painted_live:
		# Der aktuelle Ausschnitt ist schon live bemalt; gröbere werden beim nächsten Zeigen neu berechnet.
		for i in levels.size() - 1:
			levels[i]["window"] = null
		landscape.sampler = sampler
		if levels.size() > 1 and _reaches_outside(command["stroke"], levels.back()):
			landscape.update_context(_level_window(levels.size() - 2))
		_on_brush(size_fraction, strength)
		_update_minimap()
		_update_ui()
		return
	_forget_windows()
	if command["kind"] == "resize" or command["kind"] == "remove_continent" or command["kind"] == "add_continent":
		open_continent(active_id)
	else:
		_show_level()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed():
		var key := (event as InputEventKey).keycode
		if key == KEY_Z and not event.shift_pressed:
			_undo()
			get_viewport().set_input_as_handled()
		elif key == KEY_Y or (key == KEY_Z and event.shift_pressed):
			_redo()
			get_viewport().set_input_as_handled()


func _queue_save() -> void:
	_dirty = true
	ui.set_saved(false)
	_save_timer.start()


func _save_now() -> void:
	var error := doc.save(save_path)
	_dirty = error != OK
	ui.set_saved(error == OK)
	if error != OK:
		push_error("Speichern fehlgeschlagen (%s): %s" % [error, save_path])


# --- Letzte Ansicht (Komfort, nicht Teil der Welt) -----------------------------------------

func _view_path() -> String:
	return save_path.get_basename() + "_ansicht.json"


func _queue_view() -> void:
	if _view_timer:
		_view_timer.start()


func _save_view() -> void:
	var data := {"continent": active_id, "globe": in_globe, "levels": []}
	for level in levels:
		data["levels"].append({"cx": level["cx"], "cy": level["cy"], "size": level["size"]})
	var file := FileAccess.open(_view_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "", false, true))


func _restore_view() -> bool:
	if not FileAccess.file_exists(_view_path()):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_view_path()))
	if not data is Dictionary or not doc.has_continent(data.get("continent", "")):
		return false
	active_id = data["continent"]
	if data.get("globe", true):
		open_globe()
		return true
	open_continent(active_id)
	var saved: Array = data.get("levels", [])
	if saved.size() > 1:
		levels.clear()
		for level in saved:
			levels.append({"cx": float(level["cx"]), "cy": float(level["cy"]), "size": float(level["size"])})
		_show_level()
		camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.95)
	return true


# --- Anzeige -------------------------------------------------------------------------------

func _update_ui() -> void:
	# Pfad: Welt / Kontinent / Region – die Stufen feinerer Ausschnitte bilden keine Kette.
	var names := ["Welt"]
	if active_id != "":
		names.append(display_name(active_id))
		if not in_globe and levels.size() > 1:
			names.append("Region")
	var current := 0 if in_globe else mini(levels.size(), 2)
	ui.set_levels(names, current)
	ui.set_mode(in_globe, levels.size() == 1, active_id != "")
	ui.set_history(doc.can_undo(), doc.can_redo())
	ui.set_planet(doc.planet)
	ui.set_continent_count(doc.continents.size())
	var notice := _notice
	_notice = ""
	if notice != "":
		ui.show_notice(notice)
	if active_id == "":
		ui.set_facts("")
		ui.set_warning("")
		ui.set_variant_available(false)
		return
	var c := continent()
	var s := sampler_for(active_id)
	ui.set_placement(c, s.climate)
	var strokes: Array = c["strokes"]
	ui.set_reroll_available(not strokes.is_empty() and Stroke.is_generator(strokes.back()))
	ui.set_variant_available(c["base"] == WorldDocument.BASE_GENERATED)
	var stats := globe_window(active_id).land_stats()
	var extent := ""
	if stats["area_km2"] > 0.0:
		var lo: Vector2 = stats["min"]
		var hi: Vector2 = stats["max"]
		var north := GlobeMath.local_to_latlon(c["latitude"], c["longitude"], c["heading"], 0.0, hi.y, doc.planet["radius_km"] * 1000.0)
		var south := GlobeMath.local_to_latlon(c["latitude"], c["longitude"], c["heading"], 0.0, lo.y, doc.planet["radius_km"] * 1000.0)
		extent = "Landfläche %s km² · %s × %s · %s bis %s" % [EditorUI._number(stats["area_km2"], 0),
			EditorUI.meters(hi.x - lo.x + globe_window(active_id).cell), EditorUI.meters(hi.y - lo.y + globe_window(active_id).cell),
			_lat_text(south.x), _lat_text(north.x)]
	else:
		extent = "Noch kein Land"
	var origin := "%s · %d Bearbeitung%s" % ["Gezeichnete Grundform" if c["base"] == WorldDocument.BASE_DRAWN else "Erzeugte Grundform (Ausgangswert %d)" % c["seed"],
		strokes.size(), "" if strokes.size() == 1 else "en"]
	ui.set_warning(_overlap_text().trim_prefix(" · "))
	if in_globe:
		ui.set_facts(extent + "
" + origin)
	else:
		var level: Dictionary = levels.back()
		ui.set_facts("%s
Klima: %s
Ausschnitt %s · Höhen %s-fach überhöht
%s" % [extent, s.climate["zone"],
			EditorUI.meters(level["size"]), String.num(landscape.exaggeration, 1).replace(".", ","), origin])


## Maßstab unten links: Meter je Bildpunkt in der Bildmitte (waagrecht, auf Meereshöhe).
func _update_scale_bar() -> void:
	if in_globe or landscape.window == null:
		return
	var cam := camera_rig.camera
	var center := get_viewport().get_visible_rect().size * 0.5
	var ground := Plane(Vector3.UP, 0.0)
	var side := center + Vector2(40.0, 0.0)
	var a: Variant = ground.intersects_ray(cam.project_ray_origin(center), cam.project_ray_normal(center))
	var b: Variant = ground.intersects_ray(cam.project_ray_origin(side), cam.project_ray_normal(side))
	if a == null or b == null:
		return
	ui.set_scale_bar((a as Vector3).distance_to(b) / 40.0 / landscape.units_per_m)


## Reicht ein Strich (mit Radius) über den Ausschnitt hinaus? Dann ändert er auch die Umgebung.
static func _reaches_outside(stroke: Dictionary, level: Dictionary) -> bool:
	var b := Stroke.bounds(stroke)
	var half: float = level["size"] * 0.5
	return b[0] < level["cx"] - half or b[2] > level["cx"] + half or b[1] < level["cy"] - half or b[3] > level["cy"] + half


static func _lat_text(latitude: float) -> String:
	return "%s° %s" % [EditorUI._number(absf(latitude), 1), "N" if latitude >= 0.0 else "S"]


## Hinweis, wenn sich das Fenster des gewählten Kontinents mit einem anderen überschneidet.
func _overlap_text() -> String:
	var c := continent()
	var a := GlobeMath.unit_vector(c["latitude"], c["longitude"])
	var radius_m: float = doc.planet["radius_km"] * 1000.0
	for other in doc.continents:
		if other["id"] == active_id:
			continue
		var b := GlobeMath.unit_vector(other["latitude"], other["longitude"])
		var angle := a.angle_to(b) * radius_m
		if angle < (c["size_km"] + other["size_km"]) * 500.0 * 0.85:
			return " · Achtung: überschneidet sich mit „%s“ (es gilt jeweils das höhere Land)" % display_name(other["id"])
	return ""


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


## Älterer Nachweis (Funktionsnachweis): Globus → Kontinent → Kontur → vertiefen → Detail →
## herauszoomen → Rückgängig/Wiederholen → Malen mit der Maus → feinste Stufe → Ufer.
func _run_demo(dir: String) -> void:
	var results := {}
	var timing := {}
	await _frames(20)
	open_globe()
	await _frames(20)
	await _shot(dir.path_join("1_globus.jpg"))
	await _measure("Globus", results)

	open_continent(active_id)
	await _frames(20)
	await _shot(dir.path_join("2_kontinent.jpg"))
	await _measure("Kontinent", results)

	var half: float = continent()["size_km"] * 500.0
	var coast := _find_coast(Vector2(1.0, 0.15), half)
	camera_rig.jump_to(landscape.to_render(coast.x, coast.y), 520.0)
	await _frames(20)
	await _shot(dir.path_join("3a_kueste_vorher.jpg"))
	var bump := Stroke.create("land_add", half * 0.08, 1.0)
	Stroke.add_point(bump, coast.x - half * 0.02, coast.y - half * 0.08)
	Stroke.add_point(bump, coast.x + half * 0.04, coast.y + half * 0.04)
	var t0 := Time.get_ticks_usec()
	doc.execute(WorldDocument.add_stroke_command(active_id, bump))
	timing["Kontur ändern (Kontinent neu berechnen)"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(20)
	await _shot(dir.path_join("3b_kueste_nachher.jpg"))
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.9)

	var p := _find_land(800.0)
	for i in 2:
		t0 = Time.get_ticks_usec()
		deepen_at(landscape.to_render(p.x, p.y))
		timing["Vertiefen auf %s" % EditorUI.meters(levels.back()["size"])] = (Time.get_ticks_usec() - t0) / 1000.0
		await _frames(15)
	await _shot(dir.path_join("4_region.jpg"))
	await _measure("Region 1:64", results)

	deepen_at(landscape.to_render(p.x, p.y))
	p = Vector2(levels.back()["cx"], levels.back()["cy"])
	await _frames(15)
	await _shot(dir.path_join("5_ausschnitt_vorher.jpg"))
	var forest := Stroke.create("forest_add", 260.0, 1.0)
	for k in 7:
		Stroke.add_point(forest, p.x - 400.0 + k * 130.0, p.y + 200.0 * sin(k * 0.8))
	var hill := Stroke.create("raise", 220.0, 60.0)
	Stroke.add_point(hill, p.x + 350.0, p.y - 300.0)
	Stroke.add_point(hill, p.x + 420.0, p.y - 250.0)
	t0 = Time.get_ticks_usec()
	doc.execute(WorldDocument.add_stroke_command(active_id, forest))
	doc.execute(WorldDocument.add_stroke_command(active_id, hill))
	timing["Zwei Striche im Ausschnitt (neu berechnen)"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(15)
	await _shot(dir.path_join("6_ausschnitt_bearbeitet.jpg"))
	await _measure("Ausschnitt 1:512 mit Bäumen", results)

	zoom_out()
	await _frames(15)
	await _shot(dir.path_join("7_region_danach.jpg"))
	zoom_out()
	zoom_out()
	await _frames(15)
	camera_rig.jump_to(landscape.to_render(p.x, p.y), camera_rig.min_distance * 1.5)
	await _frames(15)
	await _shot(dir.path_join("8_kontinent_danach.jpg"))

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

	_on_tool("forest_add")
	var before := (continent()["strokes"] as Array).size()
	var view_size := get_viewport().get_visible_rect().size
	var start := view_size * Vector2(0.45, 0.6)
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

	var hit: Variant = camera_rig.ground_point_under(start + Vector2(14.0 * 15, -4.0 * 15))
	if hit != null:
		deepen_at(hit)
		camera_rig.jump_to(Vector3.ZERO, camera_rig.min_distance * 2.5)
		await _frames(20)
		await _shot(dir.path_join("13_ausschnitt_390m.jpg"))
		await _measure("Ausschnitt 1:4096 mit Blattkarten-Bäumen", results)

	open_continent(active_id)
	var half2: float = continent()["size_km"] * 500.0
	var direction := Vector2(-0.3, -1.0).normalized()
	var shore := _find_coast(direction, half2)
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


## Abnahme mit echten Mausereignissen. Schritt 1: neue Welt → Kontinent zeichnen → bearbeiten →
## auf dem Globus setzen → zweiter Kontinent → Region → speichern. Schritt 2 (neuer Prozess,
## gleiche Datei): Stand prüfen → weiterarbeiten → Rückgängig/Wiederholen → speichern.
func _run_acceptance(dir: String, step: String) -> void:
	var report := {"step": step, "checks": {}, "timing_ms": {}}
	var checks: Dictionary = report["checks"]
	await _frames(20)
	if step == "1":
		await _acceptance_build(dir, report)
	else:
		await _acceptance_continue(dir, report)
	_save_now()
	_save_view()
	# Inhaltlicher Vergleich mit Toleranz: Godots JSON-Leser kann die letzte Binärstelle einer Zahl
	# verschieben (10⁻¹¹ m) – die Höhen bleiben trotzdem bitgleich (eigene Prüfung im Schritt 2).
	report["world_data"] = doc.to_dict()
	var reloaded := WorldDocument.load_file(save_path)
	report["checks"]["Gespeichert = geladen (gleicher Stand)"] = reloaded != null and same_data(doc.to_dict(), reloaded.to_dict())
	report["continents"] = doc.continents.size()
	report["strokes"] = []
	for c in doc.continents:
		report["strokes"].append((c["strokes"] as Array).size())
	var failed := 0
	for key in checks:
		if not checks[key]:
			failed += 1
	report["failed"] = failed
	var file := FileAccess.open(dir.path_join("abnahme_%s.json" % step), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ABNAHME Schritt %s: %d Prüfungen, %d fehlgeschlagen" % [step, checks.size(), failed])
	for key in checks:
		print("  %s %s" % ["ok  " if checks[key] else "FEHLT", key])
	get_tree().quit()


func _acceptance_build(dir: String, report: Dictionary) -> void:
	var checks: Dictionary = report["checks"]
	await _shot(dir.path_join("a01_globus_leer.jpg"))
	checks["Neue Welt ist leer"] = doc.continents.is_empty()

	# 1 Kontinent zeichnen: „Neu zeichnen“, dann Umriss mit der Maus.
	ui.new_continent_pressed.emit(true)
	await _frames(10)
	var id := active_id
	checks["Gezeichneter Kontinent angelegt und geöffnet"] = doc.continents.size() == 1 and not in_globe and tool == "shape_add"
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance)
	await _frames(20)
	await _shot(dir.path_join("a02_leere_flaeche.jpg"))
	var outline := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		var r := 330000.0 * (1.0 + 0.22 * sin(3.0 * a + 0.4) + 0.09 * cos(5.0 * a) + 0.05 * sin(9.0 * a))
		outline.append(Vector2(cos(a) * r * 1.15, sin(a) * r * 0.9))
	await _mouse_line(outline)
	checks["Umriss mit der Maus gezeichnet"] = (continent()["strokes"] as Array).size() == 1
	await _frames(10)
	await _shot(dir.path_join("a03_umriss.jpg"))

	# Bucht wegschneiden.
	_use_tool("shape_remove")
	var bay := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		bay.append(Vector2(330000.0, -60000.0) + Vector2(cos(a) * 90000.0, sin(a) * 45000.0))
	await _mouse_line(bay)
	checks["Bucht weggeschnitten (Meer)"] = globe_window(id).height_at(300000.0, -60000.0) < 0.0

	# Gebirge entlang eines Strichs, neu würfeln.
	_use_tool("gen_mountains")
	ui.set_brush(0.045, 0.8)
	await _mouse_stroke([Vector2(-260000.0, 120000.0), Vector2(-120000.0, 160000.0), Vector2(20000.0, 120000.0)])
	var mountains_seed: int = continent()["strokes"].back()["seed"]
	var peak := _max_height(globe_window(id), Vector2(-120000.0, 150000.0), 60000.0)
	checks["Gebirge erzeugt (höchster Punkt %d m)" % int(peak)] = peak > 1200.0
	ui.reroll_pressed.emit()
	await _frames(5)
	checks["Neu würfeln ersetzt die Erzeugung (gleiche Zahl Bearbeitungen)"] = (continent()["strokes"] as Array).size() == 3 \
		and int(continent()["strokes"].back()["seed"]) != mountains_seed

	# Hügelland, Wald verteilen, Ebene.
	_use_tool("gen_hills")
	ui.set_brush(0.05, 0.7)
	await _mouse_stroke([Vector2(-150000.0, -150000.0), Vector2(0.0, -180000.0)])
	_use_tool("gen_forest")
	ui.set_brush(0.08, 0.9)
	await _mouse_stroke([Vector2(-200000.0, -40000.0), Vector2(100000.0, -60000.0), Vector2(150000.0, 80000.0)])
	checks["Wald verteilt"] = globe_window(id).forest_at(-50000.0, -50000.0) > 0.0 or _max_forest(globe_window(id), Vector2(-50000.0, -50000.0), 90000.0) > 0.3

	# Fluss vom Gebirge zur Küste.
	_use_tool("river")
	ui.set_brush(0.006, 0.5)
	var river := PackedVector2Array()
	for k in 14:
		var t := k / 13.0
		river.append(Vector2(lerpf(-90000.0, 255000.0, t), lerpf(105000.0, -50000.0, t) + sin(t * 7.0) * 30000.0))
	await _mouse_line(river)
	var last: Dictionary = continent()["strokes"].back()
	checks["Fluss angelegt, Spiegel fällt"] = last["tool"] == "river" and float(last["heights"][0]) >= float(last["heights"].back())

	# See setzen.
	_use_tool("lake")
	ui.set_brush(0.02, 0.5)
	await _mouse_click(Vector2(-180000.0, -100000.0))
	var lake_window := sampler_for(id).window(-180000.0, -100000.0, 100000.0, 129)
	checks["See hat Wasser über Grund"] = lake_window.water_level_at(-180000.0, -100000.0) > lake_window.height_at(-180000.0, -100000.0)

	# Inseln vor der Küste, Fläche schützen.
	_use_tool("gen_islands")
	ui.set_brush(0.04, 0.8)
	await _mouse_stroke([Vector2(-480000.0, -280000.0), Vector2(-380000.0, -360000.0)])
	_use_tool("protect")
	ui.set_brush(0.06, 0.5)
	await _mouse_stroke([Vector2(-120000.0, 150000.0), Vector2(-20000.0, 150000.0)])
	checks["Schutzfläche angelegt"] = continent()["strokes"].back()["tool"] == "protect"
	_use_tool("navigate")
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance)
	await _frames(20)
	await _shot(dir.path_join("a04_kontinent_bearbeitet.jpg"))
	camera_rig.jump_to(landscape.to_render(-100000.0, 150000.0), camera_rig.max_distance * 0.45)
	await _frames(20)
	await _shot(dir.path_join("a05_gebirge_fluss_nah.jpg"))

	# 2 Auf den Globus setzen: zurück, Kontinent ziehen.
	ui.globe_pressed.emit()
	await _frames(30)
	await _shot(dir.path_join("a06_globus.jpg"))
	var lat0: float = continent()["latitude"]
	var lon0: float = continent()["longitude"]
	var from := globe.screen_of(lat0, lon0)
	var to := globe.screen_of(lat0 + 12.0, lon0 + 18.0)
	_send_mouse(from, true, true)
	await _frames(2)
	for k in 12:
		_send_motion(from.lerp(to, (k + 1) / 12.0))
		await _frames(1)
	_send_mouse(to, false, true)
	await _frames(10)
	checks["Kontinent auf dem Globus verschoben (%s° → %s°)" % [String.num(lat0, 1), String.num(continent()["latitude"], 1)]] = \
		absf(continent()["latitude"] - lat0) > 4.0
	var history_before := doc._undo.size()
	_on_placement("heading", 25.0, true)
	_on_placement("size_km", 1900.0, true)
	checks["Ausrichtung und Größe als je ein Schritt"] = doc._undo.size() == history_before + 2
	_on_placement("planet.radius_km", 9000.0, true)
	checks["Planetengröße 9.000 km"] = is_equal_approx(doc.planet["radius_km"], 9000.0)
	globe.face(continent()["latitude"], continent()["longitude"])
	await _frames(20)
	await _shot(dir.path_join("a07_globus_platziert.jpg"))

	# 3 Zweiter, erzeugter Kontinent; löschen, rückgängig.
	globe.face(-20.0, 120.0)
	await _frames(5)
	ui.new_continent_pressed.emit(false)
	await _frames(10)
	var second := active_id
	checks["Zweiter Kontinent erzeugt"] = doc.continents.size() == 2 and second != id
	doc.execute(doc.remove_continent_command(second))
	checks["Gelöscht"] = doc.continents.size() == 1
	_undo()
	checks["Rückgängig stellt ihn wieder her"] = doc.continents.size() == 2 and doc.has_continent(second)
	globe.face(5.0, 70.0)
	_select(second)
	await _frames(30)
	await _shot(dir.path_join("a08_zwei_kontinente.jpg"))

	# 4 Region: ersten Kontinent per Doppelklick öffnen, vertiefen, malen, herauszoomen.
	globe.face(continent_lat(id), continent_lon(id))
	await _frames(20)
	var at := globe.screen_of(continent_lat(id), continent_lon(id))
	_send_mouse(at, true, true, true)
	await _frames(3)
	_send_mouse(at, false, true)
	await _frames(15)
	checks["Doppelklick öffnet den Kontinent"] = not in_globe and active_id == id
	var spot := _find_land(900.0)
	deepen_at(landscape.to_render(spot.x, spot.y))
	deepen_at(landscape.to_render(spot.x, spot.y))
	await _frames(10)
	var region: Dictionary = levels.back()
	var rp := Vector2(region["cx"], region["cy"])
	var region_before := sampler_for(id).window(rp.x, rp.y, region["size"], 129)
	_use_tool("forest_add")
	ui.set_brush(0.05, 1.0)
	await _mouse_stroke([rp + Vector2(-3000.0, 1000.0), rp + Vector2(0.0, -500.0), rp + Vector2(3000.0, 500.0)])
	_use_tool("raise")
	ui.set_brush(0.04, 0.8)
	await _mouse_stroke([rp + Vector2(-2000.0, -4000.0), rp + Vector2(2000.0, -4000.0)])
	_use_tool("navigate")
	camera_rig.jump_to(Vector3.ZERO, camera_rig.max_distance * 0.7)
	await _frames(20)
	await _shot(dir.path_join("a09_region_bearbeitet.jpg"))
	var region_after := sampler_for(id).window(rp.x, rp.y, region["size"], 129)
	checks["Region: Wald und Höhe geändert"] = region_after.forest_at(rp.x, rp.y) > region_before.forest_at(rp.x, rp.y) + 0.2
	zoom_out()
	zoom_out()
	await _frames(10)
	camera_rig.jump_to(landscape.to_render(rp.x, rp.y), camera_rig.min_distance * 1.6)
	await _frames(20)
	await _shot(dir.path_join("a10_kontinent_mit_regionsmarke.jpg"))
	var coarse := sampler_for(id).window(rp.x, rp.y, levels.back()["size"] * 0.2, 129)
	checks["Kontinent zeigt die Detailarbeit markiert"] = coarse.mark_at(rp.x, rp.y) > 0.5
	# Wieder hinein in die Region – so bleibt sie für den Neustart als letzte Ansicht.
	deepen_at(landscape.to_render(rp.x, rp.y))
	deepen_at(landscape.to_render(rp.x, rp.y))
	await _frames(10)
	report["region"] = [rp.x, rp.y, levels.back()["size"]]
	report["probe"] = _probe(id, rp)


func _acceptance_continue(dir: String, report: Dictionary) -> void:
	var checks: Dictionary = report["checks"]
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("abnahme_1.json")))
	checks["Neustart: beide Kontinente da"] = doc.continents.size() == 2
	checks["Neustart: gleicher Weltstand"] = same_data(doc.to_dict(), before["world_data"])
	checks["Neustart: letzte Ansicht (Region) wiederhergestellt"] = not in_globe and levels.size() == 3
	var id := active_id
	var rp := Vector2(before["region"][0], before["region"][1])
	var probe := _probe(id, rp)
	checks["Neustart: Höhen bitgleich"] = str(probe) == str(before["probe"])
	await _frames(20)
	await _shot(dir.path_join("b01_nach_neustart_region.jpg"))
	var count := (continent()["strokes"] as Array).size()
	_use_tool("gen_hills")
	ui.set_brush(0.06, 0.8)
	await _mouse_stroke([rp + Vector2(-4000.0, 3000.0), rp + Vector2(4000.0, 3000.0)])
	checks["Weiterarbeiten: neue Bearbeitung"] = (continent()["strokes"] as Array).size() == count + 1
	_undo()
	checks["Rückgängig nach Neustart"] = (continent()["strokes"] as Array).size() == count
	_redo()
	checks["Wiederholen nach Neustart"] = (continent()["strokes"] as Array).size() == count + 1
	_use_tool("navigate")
	await _frames(15)
	await _shot(dir.path_join("b02_weitergearbeitet.jpg"))
	# Nachbarbereich: über den Rand schieben – der Ausschnitt wandert mit, die Stelle bleibt im Bild.
	var level: Dictionary = levels.back()
	var before_center := Vector2(level["cx"], level["cy"])
	var focus_before := landscape.to_continent(camera_rig.focus_point())
	camera_rig.shift_focus(Vector3(LandscapeView.PLANE * 0.42, 0.0, 0.0))
	var aimed := landscape.to_continent(camera_rig.focus_point())
	await _frames(10)
	var moved := Vector2(levels.back()["cx"], levels.back()["cy"]).distance_to(before_center)
	var still := landscape.to_continent(camera_rig.focus_point()).distance_to(aimed)
	checks["Ausschnitt wandert beim Verschieben über den Rand mit (%s)" % EditorUI.meters(moved)] = moved > level["size"] * 0.2 and still < level["size"] * 0.01 and focus_before != aimed
	await _shot(dir.path_join("b02b_nachbarbereich.jpg"))
	open_globe()
	await _frames(30)
	await _shot(dir.path_join("b03_globus_nach_neustart.jpg"))
	# Viele Landmassen: 70 weitere Kontinente (mehr als eine Texturebene) in einem Schritt.
	var adds := []
	for k in 70:
		var lat := -60.0 + float(k / 10) * 18.0
		var lon := -170.0 + float(k % 10) * 34.0
		adds.append(WorldDocument.add_continent_command(WorldDocument.new_continent(1000 + k, WorldDocument.BASE_GENERATED, 500.0, lat, lon)))
	var t_many := Time.get_ticks_usec()
	doc.execute(WorldDocument.group_command(adds))
	report["timing_ms"]["70 Kontinente anlegen und Globus zeigen"] = (Time.get_ticks_usec() - t_many) / 1000.0
	var last: Dictionary = doc.continents.back()
	globe.face(last["latitude"], last["longitude"])
	await _frames(20)
	var hit_last := globe.continent_at(Vector2(last["latitude"], last["longitude"]))
	checks["72 Kontinente auf dem Globus, der letzte ist anklickbar"] = doc.continents.size() == 72 and hit_last == last["id"]
	await _shot(dir.path_join("b04_viele_kontinente.jpg"))
	_undo()
	await _frames(5)
	checks["Rückgängig entfernt die 70 wieder (ein Schritt)"] = doc.continents.size() == 2


## Bildreihe über alle Maßstäbe an einer Küstenstelle des gewählten Kontinents (zur Bewertung
## der Grafik): --stufen=<Ordner> [--richtung=<Grad>]. Speichert stufe_<n>.jpg und beendet.
func _run_levels(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(10)
	if active_id == "":
		get_tree().quit()
		return
	open_continent(active_id)
	var angle := deg_to_rad(float(_args.get("richtung", "200")))
	var direction := Vector2(cos(angle), sin(angle))
	var half: float = continent()["size_km"] * 500.0
	var coast := _find_coast(direction, half)
	var target := coast - direction * half * 0.004
	var results := {}
	for level in 5:
		if level > 0:
			deepen_at(landscape.to_render(target.x, target.y))
			# Küste im neuen, feineren Ausschnitt genauer suchen: der Mitte nächste Uferstelle.
			var w: TerrainWindow = levels.back()["window"]
			var shore: Variant = _nearest_shore(w)
			if shore != null:
				target = shore
		var size: float = levels.back()["size"]
		camera_rig.jump_to(landscape.to_render(target.x, target.y).lerp(Vector3.ZERO, 0.5), camera_rig.max_distance * 0.55)
		await _frames(25)
		await _shot(dir.path_join("stufe_%d_%s.jpg" % [level, EditorUI.meters(size).replace(" ", "").replace(",", "_").replace(".", "")]))
		camera_rig.jump_to(landscape.to_render(target.x, target.y), camera_rig.min_distance * 1.3)
		await _frames(25)
		await _shot(dir.path_join("stufe_%d_nah.jpg" % level))
		await _measure("Stufe %d (%s)" % [level, EditorUI.meters(size)], results)
	var file := FileAccess.open(dir.path_join("messwerte.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	get_tree().quit()


## Uferstelle (Land neben Meer oder See) nächst der Mitte eines Ausschnitts, oder null.
static func _nearest_shore(w: TerrainWindow) -> Variant:
	var best: Variant = null
	var best_d := INF
	var step := w.size / 96.0
	for j in 97:
		for i in 97:
			var p := Vector2(w.cx - w.size * 0.5 + i * step, w.cy - w.size * 0.5 + j * step)
			if w.height_at(p.x, p.y) <= 0.3:
				continue
			var wet := false
			for d in [Vector2(step, 0.0), Vector2(-step, 0.0), Vector2(0.0, step), Vector2(0.0, -step)]:
				var q: Vector2 = p + d
				if w.contains(q.x, q.y) and (w.height_at(q.x, q.y) < -0.3 or w.water_level_at(q.x, q.y) > w.height_at(q.x, q.y)):
					wet = true
			var dist := p.distance_to(Vector2(w.cx, w.cy))
			if wet and dist < best_d:
				best_d = dist
				best = p
	return best


## Gleicher Inhalt? Zahlen auf 10⁻⁶ relativ gleich (ganz- und Kommazahlen gelten als gleich).
static func same_data(a: Variant, b: Variant) -> bool:
	var na := typeof(a) in [TYPE_INT, TYPE_FLOAT]
	var nb := typeof(b) in [TYPE_INT, TYPE_FLOAT]
	if na or nb:
		return na and nb and absf(float(a) - float(b)) <= 1e-6 * maxf(1.0, absf(float(a)))
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same_data(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key in a:
			if not (b as Dictionary).has(key) or not same_data(a[key], b[key]):
				return false
		return true
	return a == b


func continent_lat(id: String) -> float:
	return doc.continent(id)["latitude"]


func continent_lon(id: String) -> float:
	return doc.continent(id)["longitude"]


func _use_tool(t: String) -> void:
	ui.select_tool(t)
	_on_tool(t)


## Bildschirmstelle eines Kontinentpunkts im aktuellen Ausschnitt.
func _screen_of(p: Vector2) -> Vector2:
	return camera_rig.camera.unproject_position(landscape.to_render(p.x, p.y))


## Linienwerkzeug: Punkte nacheinander mit gedrückter Maustaste abfahren.
func _mouse_line(points: PackedVector2Array) -> void:
	_send_mouse(_screen_of(points[0]), true, true)
	await _frames(1)
	for k in range(1, points.size()):
		_send_motion(_screen_of(points[k]))
		await _frames(1)
	_send_mouse(_screen_of(points[points.size() - 1]), false, true)
	await _frames(5)


## Pinselstrich durch die Stützpunkte (dazwischen fein unterteilt).
func _mouse_stroke(points: Array) -> void:
	var fine := PackedVector2Array()
	for k in points.size() - 1:
		for s in 10:
			fine.append((points[k] as Vector2).lerp(points[k + 1], s / 10.0))
	fine.append(points.back())
	await _mouse_line(fine)


func _mouse_click(p: Vector2) -> void:
	_send_mouse(_screen_of(p), true, true)
	await _frames(2)
	_send_mouse(_screen_of(p), false, true)
	await _frames(5)


static func _max_height(w: TerrainWindow, c: Vector2, r: float) -> float:
	var best := -INF
	for k in 200:
		var q := c + Vector2(cos(k * 2.4), sin(k * 2.4)) * r * sqrt(k / 200.0)
		best = maxf(best, w.height_at(q.x, q.y))
	return best


static func _max_forest(w: TerrainWindow, c: Vector2, r: float) -> float:
	var best := 0.0
	for k in 200:
		var q := c + Vector2(cos(k * 2.4), sin(k * 2.4)) * r * sqrt(k / 200.0)
		best = maxf(best, w.forest_at(q.x, q.y))
	return best


## Stichprobe der Höhen um einen Punkt (für den Vergleich nach dem Neustart).
func _probe(id: String, p: Vector2) -> Array:
	var w := sampler_for(id).window(p.x, p.y, 20000.0, 65)
	var values := []
	for k in 9:
		values.append(w.height[k * 500])
	return values


func _send_mouse(position: Vector2, pressed: bool, left: bool, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = position
	e.global_position = position
	e.button_index = MOUSE_BUTTON_LEFT if left else MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	e.double_click = double
	Input.parse_input_event(e)


func _send_motion(position: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = position
	e.global_position = position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


## Feinster verfügbarer Ausschnitt des ganzen Kontinents (für die Suche nach Küste und Land).
func _whole_continent_window() -> TerrainWindow:
	if not levels.is_empty() and not in_globe:
		return _level_window(0)
	return globe_window(active_id)


func _find_coast(direction: Vector2, half: float) -> Vector2:
	var w := _whole_continent_window()
	# Von außen nach innen: der erste Landpunkt ist die Küste (Seen im Inneren zählen nicht).
	var d := direction.normalized()
	for s in 200:
		var q := d * half * (1.0 - s / 200.0)
		if w.height_at(q.x, q.y) > 0.0:
			return q
	return Vector2.ZERO


func _find_land(max_height: float) -> Vector2:
	var w := _whole_continent_window()
	var half: float = continent()["size_km"] * 500.0
	for s in 400:
		var a := s * 2.399963
		var r := half * 0.5 * sqrt(s / 400.0)
		var q := Vector2(cos(a), sin(a)) * r
		var h := w.height_at(q.x, q.y)
		if h > 60.0 and h < max_height and w.forest_at(q.x, q.y) < 0.3:
			return q
	return Vector2.ZERO
