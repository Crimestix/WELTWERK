class_name RealtimeRun
extends RecordingRun
## Durchgehend in Echtzeit aufgezeichneter Zoom- und Bearbeitungsablauf (Aufruf:
## godot --position 2000,60 --path <Projekt> -- --echtzeit=<Ordner> [--pause-ab=<ms>] [--ohne-bilder]).
## Echte Mausereignisse und sichtbarer Zeiger wie in RecordingRun, aufgenommen von RealtimeCapture
## (Wanduhr, Rechenpausen bleiben als stehendes Bild sichtbar). Film daraus:
## python tools/make_video.py <Ordner>.
##
## Ablauf: neue Welt → „Neu zeichnen“ → zurück zum Globus, Breitengrad mit dem Regler → „Kontinent
## bearbeiten“ → Umriss → Gebirge → der Gipfel wird EINMAL auf Kontinentebene aus den Geländedaten
## bestimmt (Landmarks: Mitte des größten Massivs, dort der höchste Punkt, zweimal verfeinert) und
## in Kontinentmetern gemerkt → auf jeder Stufe zielt das Mausrad auf genau diese Stelle
## (Kontinent → 200 km → 25 km → Detail) → am Berg „Erhöhen“ und „Senken“ → im Detail, wo die
## Bearbeitung zu sehen ist, Rückgängig und Wiederholen mit Höhenmessung → hinaus bis zum Kontinent.
## --ohne-bilder: gleicher Ablauf ohne Bildaufnahme (nur Zeiten), Bericht echtzeit_ohne_bilder.json.

## Suchradius „Gipfel bleibt Höchstpunkt“ als Anteil der Ausschnittsgröße.
const LOCAL_SHARE := 0.05

var capture: RealtimeCapture
var sections := []
## Gemerkter Gipfel in Kontinentmetern (einmal bestimmt, auf allen Stufen derselbe).
var peak := Vector2.ZERO
var _has_peak := false
var _marker: Control
var _marker_on := false
var _levels_report := []
var _camera_moves := []
var _undo_report := {}
## Eigene Rechnung des Ablaufs (keine Bedienung) – erklärt eine Pause, die sie verursacht.
var _own_work := ""


func _init(p_editor: Node) -> void:
	super(p_editor)


func _strokes() -> int:
	var c: Dictionary = editor.continent()
	return (c["strokes"] as Array).size() if not c.is_empty() else 0


## Zustand je Bild für die Pausenliste (Maßstab, Lage des Ausschnitts, Bearbeitungen).
func _state() -> Dictionary:
	var c: Dictionary = editor.continent() if editor.active_id != "" else {}
	var latitude: float = c.get("latitude", 0.0)
	if editor.in_globe or editor.levels.is_empty():
		return {"text": "Globus", "globe": true, "strokes": _strokes(), "latitude": latitude}
	var level: Dictionary = editor.levels.back()
	var level_name := "Kontinent" if editor.levels.size() == 1 else "Ausschnitt"
	return {"text": "%s %s, %d Bearb." % [level_name, EditorUI.meters(level["size"]), _strokes()], "globe": false,
		"size": level["size"], "cx": level["cx"], "cy": level["cy"], "strokes": _strokes(),
		"latitude": latitude, "busy": editor.landscape.is_busy()}


## Was die Pause ausgelöst hat – aus dem Zustand vor und nach der Lücke und der letzten Handlung.
func _cause(before: Dictionary, after: Dictionary, action_text: String) -> String:
	if before.is_empty():
		return action_text
	if _own_work != "":
		return "%s: %s" % [action_text, _own_work]
	if before.get("globe", false) and not after.get("globe", false):
		return "%s: Kontinent geöffnet, Ansicht %s berechnet" % [action_text, EditorUI.meters(after["size"])]
	if after.get("globe", false):
		if before.get("globe", false) and before.get("latitude") != after.get("latitude"):
			return "%s: Lage auf dem Globus geändert, Globus nachgeführt" % action_text
		if before.get("globe", false):
			return "%s: auf dem Globus" % action_text
		return "%s: Globus aufgebaut" % action_text
	var b_size: float = before.get("size", 0.0)
	var a_size: float = after.get("size", 0.0)
	if a_size < b_size:
		return "%s: vertieft, Ausschnitt %s berechnet" % [action_text, EditorUI.meters(a_size)]
	if a_size > b_size:
		return "%s: herausgezoomt, Ausschnitt %s berechnet" % [action_text, EditorUI.meters(a_size)]
	if int(after["strokes"]) > int(before["strokes"]):
		return "%s: neue Bearbeitung, Gelände neu berechnet" % action_text
	if int(after["strokes"]) < int(before["strokes"]):
		return "%s: Bearbeitung entfernt, Gelände neu berechnet" % action_text
	if before.get("busy", false) or after.get("busy", false):
		return "%s: während des Malens nachgerechnet" % action_text
	if before.get("latitude") != after.get("latitude"):
		return "%s: Lage auf dem Globus geändert, Kontinent neu berechnet" % action_text
	if before.get("cx") != after.get("cx") or before.get("cy") != after.get("cy"):
		return "%s: Ausschnitt wandert mit, neu berechnet" % action_text
	return "%s: Ursache nicht erkannt (Ausschnitt und Bearbeitungen unverändert)" % action_text


## Abschnitt beginnen: Beschriftung im Bild, Merker für die Pausenliste.
func step(text: String, action_text: String = "") -> void:
	caption(text)
	capture.action = action_text if action_text != "" else text
	sections.append({"t_s": snappedf(capture.elapsed(), 0.01), "text": text})


func act(action_text: String) -> void:
	capture.action = action_text


# --- Gipfelmarke -----------------------------------------------------------------------------

## Messingring an der gemerkten Gipfelstelle (folgt jedem Bild, nur in der Landschaft).
func _setup_marker() -> void:
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(func() -> void:
		_marker.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 4.0, true)
		_marker.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0.85, 0.66, 0.34, 0.95), 2.0, true)
		_marker.draw_line(Vector2(0, -20), Vector2(0, -9), Color(0.85, 0.66, 0.34, 0.95), 2.0, true))
	_marker.visible = false
	_layer.add_child(_marker)
	_layer.move_child(_marker, 0)
	editor.get_tree().process_frame.connect(_update_marker)


func _update_marker() -> void:
	if _marker == null:
		return
	var show: bool = _marker_on and _has_peak and not editor.in_globe and editor.landscape.window != null
	if show:
		var render: Vector3 = editor.landscape.to_render(peak.x, peak.y)
		show = not editor.camera_rig.camera.is_position_behind(render)
		if show:
			_marker.position = editor.camera_rig.camera.unproject_position(render)
	_marker.visible = show
	if show:
		_marker.queue_redraw()


# --- Gipfel bestimmen und prüfen --------------------------------------------------------------

## Einmal auf Kontinentebene: Mitte des größten Massivs, dort der höchste Punkt, verfeinert in
## einem 10-km- und einem 1,5-km-Ausschnitt (wie die Ortsprüfung LandmarkRun).
func find_peak() -> Vector2:
	var cw: TerrainWindow = editor._level_window(0)
	var sampler: TerrainSampler = editor.sampler
	var massif := Landmarks.massif_center(cw, 30000.0)
	var area := sampler.window(massif.x, massif.y, 200000.0, 257)
	var p := Landmarks.highest_in(area, massif, 60000.0)
	for refine in [[10000.0, 2500.0], [1500.0, 400.0]]:
		var w := sampler.window(p.x, p.y, refine[0], 257)
		p = Landmarks.highest_in(w, p, refine[1])
	return p


## Liegt der gemerkte Gipfel im angezeigten Ausschnitt, und ist er dort der höchste Punkt seiner
## Umgebung (Kreis mit 5 % der Ausschnittsgröße; erlaubt: 3 Rasterzellen Versatz)?
func check_level(label: String) -> void:
	var w: TerrainWindow = editor.landscape.window
	var dx := absf(peak.x - w.cx)
	var dy := absf(peak.y - w.cy)
	var inside := dx <= w.size * 0.5 and dy <= w.size * 0.5
	checks["%s: gemerkter Gipfel im Ausschnitt (Versatz zur Mitte %s / %s, halbe Größe %s)" % [label,
		EditorUI.meters(dx), EditorUI.meters(dy), EditorUI.meters(w.size * 0.5)]] = inside
	var r := w.size * LOCAL_SHARE
	var q := Landmarks.highest_in(w, peak, r)
	var hp := w.height_at(peak.x, peak.y)
	var hq := w.height_at(q.x, q.y)
	var allowed := 2.0 * Landmarks.RESOLVE_CELLS * w.cell
	var dist := q.distance_to(peak)
	checks["%s: Gipfel bleibt Höchstpunkt im Umkreis %s (höchster Rasterpunkt %s entfernt, erlaubt %s; %+d m)" % [
		label, EditorUI.meters(r), EditorUI.meters(dist), EditorUI.meters(allowed), int(round(hq - hp))]] = dist <= allowed
	_levels_report.append({"stufe": label, "groesse_m": w.size, "zelle_m": w.cell, "mitte": [w.cx, w.cy],
		"gipfel_versatz_m": [peak.x - w.cx, peak.y - w.cy], "im_ausschnitt": inside, "umkreis_m": r,
		"hoechster_rasterpunkt": [q.x, q.y], "abstand_m": dist, "erlaubt_m": allowed,
		"hoehe_gipfel_m": hp, "hoehe_hoechster_m": hq})


## Gipfel in den freien Bildbereich holen: liegt er außerhalb, wird die Kamera hingeschoben
## (vom Ablauf gesetzt, keine Bedienung – im Bericht vermerkt).
func bring_peak_on_screen(label: String) -> Vector2:
	var s: Vector2 = editor._screen_of(peak)
	var behind: bool = editor.camera_rig.camera.is_position_behind(editor.landscape.to_render(peak.x, peak.y))
	if behind or not _free_rect().has_point(s):
		act("Ansicht zum Gipfel geschoben (vom Ablauf gesetzt)")
		editor.camera_rig.jump_to(editor.landscape.to_render(peak.x, peak.y), editor.camera_rig._target_distance)
		_camera_moves.append({"vor": label, "bildstelle_vorher": [s.x, s.y], "t_s": snappedf(capture.elapsed(), 0.01)})
		await frames(12)
		s = editor._screen_of(peak)
	checks["Gipfel im freien Bildbereich vor „%s“" % label] = _free_rect().has_point(s)
	return s


## Mausrad in einzelnen Rasten auf den gemerkten Gipfel: vor jeder Raste wandert der Zeiger zur
## aktuellen Bildstelle des Gipfels (wie eine Hand, die das Ziel unter dem Zeiger hält).
func wheel_at_peak(inward: bool, done: Callable, every: int, max_steps: int) -> int:
	for k in max_steps:
		if done.call():
			return k
		var p: Vector2 = editor._screen_of(peak)
		if p.distance_to(_pos) > 2.0:
			_motion(p, 0)
		var b := MOUSE_BUTTON_WHEEL_UP if inward else MOUSE_BUTTON_WHEEL_DOWN
		_button(p, b, true)
		_button(p, b, false)
		await frames(every)
	return max_steps


## Mausrad in einzelnen Rasten an fester Stelle, bis done() wahr ist.
func wheel_until(p: Vector2, inward: bool, done: Callable, every: int = 4, max_steps: int = 90) -> int:
	for k in max_steps:
		if done.call():
			return k
		var b := MOUSE_BUTTON_WHEEL_UP if inward else MOUSE_BUTTON_WHEEL_DOWN
		_button(p, b, true)
		_button(p, b, false)
		await frames(every)
	return max_steps


## Bereich des Bildes, in dem keine Oberfläche liegt (Werkzeugleiste links, Pfad oben,
## Einstellungen und Übersichtskarte rechts).
func _free_rect() -> Rect2:
	var view: Vector2 = editor.get_viewport().get_visible_rect().size
	return Rect2(view.x * 0.24, view.y * 0.2, view.x * 0.5, view.y * 0.55)


## Einen Maßstab tiefer: Zeiger auf den gemerkten Gipfel, Mausrad bis zum Wechsel.
func zoom_into_peak(label: String) -> void:
	var s := await bring_peak_on_screen(label)
	await move_to(s, 24)
	var count: int = editor.levels.size()
	act("Mausrad hinein → %s" % label)
	var steps := await wheel_at_peak(true, func() -> bool: return editor.levels.size() > count, 6, 90)
	checks["Maßstab gewechselt: %s (%d Rasten)" % [label, steps]] = editor.levels.size() == count + 1
	act("Ausschnitt betrachten (keine Eingabe)")
	await frames(70)


## Regler wie ein Nutzer auf einen Wert ziehen: Knopf greifen, schieben; liegt der Wert danach
## daneben, wird nachgezogen (höchstens dreimal). Der Knopf läuft über Breite minus Knopfbreite.
func set_slider(slider: Range, value: float) -> void:
	if slider == null or not slider.is_visible_in_tree():
		checks["Regler sichtbar"] = false
		return
	var grabber: Texture2D = slider.get_theme_icon("grabber")
	var knob := float(grabber.get_width()) if grabber else 0.0
	for attempt in 3:
		if absf(slider.value - value) <= slider.step * 0.5:
			return
		var rect := slider.get_global_rect()
		var span := slider.max_value - slider.min_value
		var travel := maxf(rect.size.x - knob, 1.0)
		var x0 := rect.position.x + knob * 0.5
		var from := Vector2(x0 + travel * (slider.value - slider.min_value) / span, rect.get_center().y)
		var to := Vector2(x0 + travel * (value - slider.min_value) / span, rect.get_center().y)
		await drag(PackedVector2Array([from, to]), 3.0)
		await frames(4)


## Höhe des angezeigten Geländes an einer Kontinentstelle.
func _height(p: Vector2) -> float:
	return (editor.landscape.window as TerrainWindow).height_at(p.x, p.y)


## Warten, bis der Editor nicht mehr malt oder rechnet.
func _settle(n: int) -> void:
	await frames(n)
	for k in 120:
		if not editor.landscape.is_busy():
			break
		await frames(1)


func run(dir: String) -> void:
	_dir = ""
	_setup_overlay()
	_setup_marker()
	capture = RealtimeCapture.new()
	capture.state_provider = _state
	capture.cause_provider = _cause
	capture.pause_ms = float(editor._args.get("pause-ab", "100"))
	# --ohne-bilder: gleicher Ablauf, nur Zeiten messen (zeigt, was die Aufnahme selbst kostet).
	# Bilder und Bericht der Filmaufnahme im selben Ordner bleiben unberührt.
	if editor._args.has("ohne-bilder"):
		capture.max_fps = 0.0
		capture.report_name = "echtzeit_ohne_bilder.json"
		editor.save_path = dir.path_join("welt_ohne_bilder.json")
	editor.add_child(capture)
	capture.start(dir)
	var comparison := ComparisonRun.new(editor)
	await frames(20)
	step("Neue Welt: leerer Globus", "Start")
	await frames(90)

	# 1 Kontinent anlegen, Lage auf dem Globus mit dem Regler, Umriss zeichnen.
	step("1 · Neuen Kontinent anlegen")
	act("Klick „Neu zeichnen“")
	await press("Neu zeichnen")
	await frames(20)
	step("1 · Zurück zum Globus: Breitengrad mit dem Regler einstellen")
	act("Klick „Welt“")
	await press("Welt")
	await frames(40)
	var lat_slider: Range = (editor.ui._placement["latitude"][0] as Range) if editor.ui._placement.has("latitude") else null
	act("Regler „Breitengrad“ ziehen")
	await set_slider(lat_slider, 42.0)
	await frames(30)
	var latitude: float = editor.continent()["latitude"]
	checks["Breitengrad über den Regler gesetzt (%s°, Ziel 42°)" % String.num(latitude, 1)] = absf(latitude - 42.0) <= 1.0
	act("Klick „Kontinent bearbeiten“")
	await press("Kontinent bearbeiten")
	await frames(20)
	step("1 · Den Umriss zeichnen")
	# „Neu zeichnen“ hat „Land zeichnen“ schon gewählt; ein zweiter Klick würde es abwählen.
	if editor.tool != "shape_add":
		await choose("Form", "Land zeichnen")
	checks["Werkzeug „Land zeichnen“ gewählt"] = editor.tool == "shape_add"
	comparison._frame()
	await frames(20)
	var outline := comparison.outline_points()
	var screen := PackedVector2Array()
	for k in range(0, outline.size(), 2):
		screen.append(ref(outline[k]))
	act("Umriss zeichnen")
	await drag(screen, 14.0)
	checks["Umriss ergibt Land"] = _strokes() == 1
	await frames(50)

	# 2 Gebirge.
	await choose("Gelände", "Gebirge")
	step("2 · Gebirge entlang eines Strichs malen")
	await drag_slider(editor.ui._size_slider, 0.62)
	await drag_slider(editor.ui._strength_slider, 0.95)
	await frames(6)
	for chain_index in [0, 1, 3]:
		act("Strich „Gebirge“")
		await drag(ref_points(ComparisonRun.MOUNTAINS[chain_index]), 8.0)
		await frames(8)
	checks["Drei Gebirgsstriche angelegt"] = _strokes() == 4
	await press("Ansehen")
	await frames(60)

	# 3 Gipfel einmal bestimmen, dann auf jeder Stufe genau dorthin hineinzoomen.
	step("3 · Höchster Gipfel des größten Massivs (aus den Geländedaten) – mit dem Mausrad hinein")
	act("Gipfel aus den Geländedaten bestimmt")
	_own_work = "Auswertung des Ablaufs (Gipfelsuche in drei Ausschnitten), keine Bedienung"
	peak = find_peak()
	# Nur die Lücke unmittelbar nach der Suche gehört ihr; danach wieder nach Zustand einordnen.
	await frames(2)
	_own_work = ""
	_has_peak = true
	_marker_on = true
	await frames(30)
	check_level("Kontinent")
	var sizes := []
	for stage in ["Region", "Ausschnitt", "Detail"]:
		var label := "%s %s" % [stage, EditorUI.meters(editor.levels.back()["size"] / editor.FACTOR)]
		await zoom_into_peak(label)
		sizes.append(EditorUI.meters(editor.levels.back()["size"]))
		caption("3 · Hineinzoomen: jetzt %s – der Ring markiert den gemerkten Gipfel" % sizes.back())
		check_level(label)
	checks["Stufen erreicht: %s" % ", ".join(sizes)] = editor.levels.size() == 4
	# Im Detail noch etwas näher an den Gipfel (ohne einen weiteren Maßstab zu öffnen).
	var s := await bring_peak_on_screen("Detail näher")
	await move_to(s, 14)
	act("Mausrad hinein (Detail)")
	var near_enough := func() -> bool: return editor.camera_rig._target_distance <= editor.camera_rig.min_distance * 2.2
	await wheel_at_peak(true, near_enough, 8, 8)
	await frames(45)
	checks["Im Detail geblieben (kein weiterer Maßstab)"] = editor.levels.size() == 4

	# 4 Am Berg bearbeiten: Erhöhen und Senken – gemessen an der Malstelle.
	var top := await bring_peak_on_screen("Bearbeiten")
	await choose("Gelände", "Erhöhen")
	step("4 · Am Berg: „Erhöhen“ – eine Schulter aufbauen")
	await drag_slider(editor.ui._size_slider, 0.5)
	await drag_slider(editor.ui._strength_slider, 0.9)
	top = editor._screen_of(peak)
	var raise_line := _screen_line_beside(top, Vector2(-1.0, 0.35), 130.0)
	var raise_ground := _ground_at(raise_line[1])
	var h_before := _height(raise_ground)
	var count := _strokes()
	act("Strich „Erhöhen“")
	await drag(raise_line, 6.0)
	await _settle(12)
	var h_after := _height(raise_ground)
	checks["Erhöhen: Bearbeitung angelegt, Boden höher (%d → %d m)" % [int(h_before), int(h_after)]] = \
		_strokes() == count + 1 and h_after > h_before
	await choose("Gelände", "Senken")
	step("4 · Am Berg: „Senken“ – eine Scharte einschneiden")
	top = editor._screen_of(peak)
	var lower_line := _screen_line_beside(top, Vector2(1.0, 0.1), 90.0)
	var spot := _ground_at(lower_line[1])
	await _settle(4)
	var h0 := _height(spot)
	count = _strokes()
	act("Strich „Senken“")
	await drag(lower_line, 6.0)
	await _settle(12)
	var h_lowered := _height(spot)
	checks["Senken: Bearbeitung angelegt, Boden tiefer (%d → %d m)" % [int(h0), int(h_lowered)]] = \
		_strokes() == count + 1 and h_lowered < h0
	checks["Bearbeitung nahe am Gipfel (%s vom gemerkten Gipfel)" % EditorUI.meters(peak.distance_to(raise_ground))] = \
		peak.distance_to(raise_ground) < float(editor.levels.back()["size"]) * 0.4
	act("Bearbeitung betrachten (keine Eingabe)")
	await _settle(80)
	var h1 := _height(spot)

	# 5 Rückgängig und Wiederholen dort, wo die Bearbeitung zu sehen ist (Detail, Malstelle im Bild).
	var spot_screen: Vector2 = editor._screen_of(spot)
	var detail_size: float = editor.levels.back()["size"]
	checks["Rückgängig im Detail, Malstelle im Bild (%s)" % EditorUI.meters(detail_size)] = \
		editor.levels.size() == 4 and _free_rect().grow(40.0).has_point(spot_screen)
	var before := _strokes()
	step("5 · Rückgängig im Detail: „Senken“ wird zurückgenommen")
	act("Klick „Rückgängig“")
	await press("Rückgängig")
	await _settle(70)
	var h2 := _height(spot)
	checks["Rückgängig nimmt die letzte Bearbeitung zurück (%d → %d Bearb.)" % [before, _strokes()]] = _strokes() == before - 1
	checks["Rückgängig stellt die Höhe an der Malstelle genau her (vorher %s m, nach Rückgängig %s m, Abweichung %s m)" % [
		String.num(h0, 3), String.num(h2, 3), "%.4f" % (h2 - h0)]] = h2 == h0
	step("5 · Wiederholen im Detail: „Senken“ ist wieder da")
	act("Klick „Wiederholen“")
	await press("Wiederholen")
	await _settle(70)
	var h3 := _height(spot)
	checks["Wiederholen stellt die Bearbeitung wieder her (%d Bearb.)" % _strokes()] = _strokes() == before
	checks["Wiederholen stellt die Höhe an der Malstelle genau her (nach Senken %s m, nach Wiederholen %s m, Abweichung %s m)" % [
		String.num(h1, 3), String.num(h3, 3), "%.4f" % (h3 - h1)]] = h3 == h1
	_undo_report = {"stelle": [spot.x, spot.y], "ausschnitt_m": detail_size, "bildstelle": [spot_screen.x, spot_screen.y],
		"hoehe_vorher_m": h0, "hoehe_direkt_nach_senken_m": h_lowered, "hoehe_nach_senken_beruhigt_m": h1,
		"hoehe_nach_rueckgaengig_m": h2, "hoehe_nach_wiederholen_m": h3}
	act("Ergebnis betrachten (keine Eingabe)")
	await frames(60)

	# 6 Hinaus bis zum Kontinent.
	_marker_on = false
	await press("Ansehen")
	step("6 · Mit dem Mausrad hinaus bis zum Kontinent")
	var center: Vector2 = editor.get_viewport().get_visible_rect().size * Vector2(0.5, 0.48)
	await move_to(center, 16)
	act("Mausrad hinaus")
	await wheel_until(center, false, func() -> bool: return editor.levels.size() == 1, 7, 160)
	# Auf Kontinentebene bis zur Übersicht – aber nicht weiter (sonst folgt der Globus).
	await wheel_until(center, false, _at_overview, 7, 60)
	checks["Zurück auf Kontinentebene"] = not editor.in_globe and editor.levels.size() == 1
	checks["Auf Kontinentebene alle Bearbeitungen da (%d)" % _strokes()] = _strokes() == before
	act("Übersicht betrachten (keine Eingabe)")
	await frames(120)
	editor._save_now()
	var reloaded := WorldDocument.load_file(editor.save_path)
	checks["Gespeichert = geladen"] = reloaded != null and editor.same_data(editor.doc.to_dict(), reloaded.to_dict())
	step("Ende", "Ende")
	caption("Ende: gleiche Landschaft, alle Bearbeitungen gespeichert")
	await frames(120)

	editor.get_tree().process_frame.disconnect(_update_marker)
	var report := capture.finish({"pruefungen": checks, "abschnitte": sections,
		"gipfel": {"x": peak.x, "y": peak.y, "stufen": _levels_report, "kamera_verschoben": _camera_moves},
		"rueckgaengig_im_detail": _undo_report})
	print("ECHTZEIT: %s s, %d Bilder gespeichert, %d Pausen ab %d ms (zusammen %s s), %d Ruckler (zusammen %s s) → %s" % [
		String.num(report["dauer_s"], 1), report["gespeicherte_bilder"], report["pausen_anzahl"], int(report["pause_ab_ms"]),
		String.num(report["pausen_gesamt_s"], 2), report["ruckler"]["anzahl"], String.num(report["ruckler"]["gesamt_s"], 2),
		capture.report_name])
	for key in checks:
		print("  %s %s" % ["ok  " if checks[key] else "FEHLT", key])
	editor.get_tree().quit()


func _at_overview() -> bool:
	return editor.in_globe or editor.camera_rig._target_distance >= editor.camera_rig.max_distance - 0.01


## Kurzer Strich neben dem Gipfel (Bildpunkte): Mitte um offset_px in Richtung dir versetzt,
## quer dazu 3 Punkte, im freien Bildbereich gehalten.
func _screen_line_beside(top: Vector2, dir: Vector2, offset_px: float) -> PackedVector2Array:
	var free := _free_rect()
	var d := dir.normalized()
	var mid := top + d * offset_px
	var across := Vector2(-d.y, d.x) * 90.0
	var out := PackedVector2Array()
	for p in [mid - across, mid, mid + across]:
		out.append(Vector2(clampf(p.x, free.position.x, free.end.x), clampf(p.y, free.position.y, free.end.y)))
	return out


func _ground_at(screen_point: Vector2) -> Vector2:
	var hit: Variant = editor.landscape._hit(screen_point)
	return editor.landscape.to_continent(hit) if hit != null else Vector2.ZERO
