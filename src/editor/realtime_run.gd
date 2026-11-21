class_name RealtimeRun
extends RecordingRun
## Durchgehend in Echtzeit aufgezeichneter Zoom- und Bearbeitungsablauf (Aufruf:
## godot --position 2000,60 --path <Projekt> -- --echtzeit=<Ordner>). Echte Mausereignisse und
## sichtbarer Zeiger wie in RecordingRun, aufgenommen von RealtimeCapture (Wanduhr, Rechenpausen
## bleiben als stehendes Bild sichtbar). Film daraus: python tools/make_video.py <Ordner>.
##
## Ablauf: neue Welt → „Neu zeichnen“ → Umriss → Gebirge → mit dem Mausrad fortlaufend zum
## höchsten Gipfel hinein (Kontinent → 200 km → 25 km → Detail; am Zoom-Anschlag wechselt der
## Editor den Maßstab) → am Berg „Erhöhen“ und „Senken“ → hinaus bis zum Kontinent → Rückgängig →
## Wiederholen. Gipfel und Malstellen werden aus den Geländedaten gesucht, keine festen Koordinaten.

var capture: RealtimeCapture
var sections := []


func _init(p_editor: Node) -> void:
	super(p_editor)


func _strokes() -> int:
	var c: Dictionary = editor.continent()
	return (c["strokes"] as Array).size() if not c.is_empty() else 0


## Zustand je Bild für die Pausenliste (Maßstab, Lage des Ausschnitts, Bearbeitungen).
func _state() -> Dictionary:
	if editor.in_globe or editor.levels.is_empty():
		return {"text": "Globus", "globe": true, "strokes": _strokes()}
	var level: Dictionary = editor.levels.back()
	var level_name := "Kontinent" if editor.levels.size() == 1 else "Ausschnitt"
	return {"text": "%s %s, %d Bearb." % [level_name, EditorUI.meters(level["size"]), _strokes()], "globe": false,
		"size": level["size"], "cx": level["cx"], "cy": level["cy"], "strokes": _strokes(),
		"latitude": editor.continent().get("latitude", 0.0), "busy": editor.landscape.is_busy()}


## Was die Pause ausgelöst hat – aus dem Zustand vor und nach der Lücke und der letzten Handlung.
func _cause(before: Dictionary, after: Dictionary, action_text: String) -> String:
	if before.is_empty():
		return action_text
	if before.get("globe", false) and not after.get("globe", false):
		return "%s: Kontinent geöffnet, Ansicht %s berechnet" % [action_text, EditorUI.meters(after["size"])]
	if after.get("globe", false):
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


## Mausrad in einzelnen Rasten (alle every Bilder eine), bis done() wahr ist.
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


## Höchster Punkt des angezeigten Ausschnitts, dessen Bildstelle frei liegt (aus den Daten).
func peak_on_screen() -> Dictionary:
	var w: TerrainWindow = editor.landscape.window
	var free := _free_rect()
	var best := {}
	var n := 72
	for j in n:
		for i in n:
			var x: float = w.cx + (float(i) / (n - 1) - 0.5) * w.size * 0.96
			var y: float = w.cy + (float(j) / (n - 1) - 0.5) * w.size * 0.96
			var h := w.height_at(x, y)
			if h <= float(best.get("h", 0.0)):
				continue
			var s: Vector2 = editor._screen_of(Vector2(x, y))
			if not free.has_point(s):
				continue
			best = {"h": h, "ground": Vector2(x, y), "screen": s}
	return best


## Einen Maßstab tiefer: Zeiger auf den höchsten freien Gipfel, Mausrad bis zum Wechsel.
func zoom_into_peak(label: String) -> Dictionary:
	var peak := peak_on_screen()
	checks["Gipfel gefunden vor „%s“" % label] = not peak.is_empty()
	if peak.is_empty():
		return {}
	await move_to(peak["screen"], 24)
	var count: int = editor.levels.size()
	act("Mausrad hinein → %s" % label)
	var steps := await wheel_until(peak["screen"], true, func() -> bool: return editor.levels.size() > count, 6)
	checks["Maßstab gewechselt: %s (%d Rasten)" % [label, steps]] = editor.levels.size() == count + 1
	await frames(70)
	return peak


func run(dir: String) -> void:
	_dir = ""
	_setup_overlay()
	capture = RealtimeCapture.new()
	capture.state_provider = _state
	capture.cause_provider = _cause
	# --ohne-bilder: gleicher Ablauf, nur Zeiten messen (zeigt, was die Aufnahme selbst kostet).
	if editor._args.has("ohne-bilder"):
		capture.max_fps = 0.0
	editor.add_child(capture)
	capture.start(dir)
	var comparison := ComparisonRun.new(editor)
	await frames(20)
	step("Neue Welt: leerer Globus", "Start")
	await frames(90)

	# 1 Kontinent anlegen und Umriss zeichnen.
	step("1 · Neuen Kontinent anlegen und den Umriss zeichnen")
	act("Klick „Neu zeichnen“")
	await press("Neu zeichnen")
	await frames(15)
	# Breitengrad direkt gesetzt (wie in RecordingRun), damit Schnee und Wald gemäßigt wirken.
	act("Breitengrad 42° gesetzt")
	editor._on_placement("latitude", 42.0, true)
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

	# 3 Fortlaufend hineinzoomen bis ins Detail – immer zum höchsten sichtbaren Gipfel.
	step("3 · Mit dem Mausrad zum Gipfel hinein – am Anschlag öffnet sich der feinere Ausschnitt")
	var sizes := []
	for stage in ["Region", "Ausschnitt", "Detail"]:
		await zoom_into_peak("%s %s" % [stage, EditorUI.meters(editor.levels.back()["size"] / editor.FACTOR)])
		sizes.append(EditorUI.meters(editor.levels.back()["size"]))
		caption("3 · Hineinzoomen: jetzt %s" % sizes.back())
	checks["Stufen erreicht: %s" % ", ".join(sizes)] = editor.levels.size() == 4
	# Im Detail noch etwas näher an den Gipfel.
	var peak := peak_on_screen()
	if not peak.is_empty():
		await move_to(peak["screen"], 14)
		act("Mausrad hinein (Detail)")
		await wheel_until(peak["screen"], true, func() -> bool: return false, 8, 8)
		await frames(45)

	# 4 Am Berg bearbeiten: Erhöhen und Senken.
	peak = peak_on_screen()
	checks["Gipfel im Detail gefunden"] = not peak.is_empty()
	if not peak.is_empty():
		var top: Vector2 = peak["screen"]
		var ground: Vector2 = peak["ground"]
		var w: TerrainWindow = editor.landscape.window
		await choose("Gelände", "Erhöhen")
		step("4 · Am Berg: „Erhöhen“ – eine Schulter aufbauen")
		await drag_slider(editor.ui._size_slider, 0.5)
		await drag_slider(editor.ui._strength_slider, 0.9)
		var raise_line := _screen_line_beside(top, Vector2(-1.0, 0.35), 130.0)
		var raise_ground := _ground_at(raise_line[1])
		var h_before := w.height_at(raise_ground.x, raise_ground.y)
		var count := _strokes()
		act("Strich „Erhöhen“")
		await drag(raise_line, 6.0)
		await frames(12)
		w = editor.landscape.window
		var h_after := w.height_at(raise_ground.x, raise_ground.y)
		checks["Erhöhen: Bearbeitung angelegt, Boden höher (%d → %d m)" % [int(h_before), int(h_after)]] = \
			_strokes() == count + 1 and h_after > h_before
		await choose("Gelände", "Senken")
		step("4 · Am Berg: „Senken“ – eine Scharte einschneiden")
		var lower_line := _screen_line_beside(top, Vector2(1.0, 0.1), 90.0)
		var lower_ground := _ground_at(lower_line[1])
		h_before = w.height_at(lower_ground.x, lower_ground.y)
		count = _strokes()
		act("Strich „Senken“")
		await drag(lower_line, 6.0)
		await frames(12)
		w = editor.landscape.window
		h_after = w.height_at(lower_ground.x, lower_ground.y)
		checks["Senken: Bearbeitung angelegt, Boden tiefer (%d → %d m)" % [int(h_before), int(h_after)]] = \
			_strokes() == count + 1 and h_after < h_before
		checks["Bearbeitung nahe am Gipfel (%s vom höchsten Punkt)" % EditorUI.meters(ground.distance_to(raise_ground))] = \
			ground.distance_to(raise_ground) < float(editor.levels.back()["size"]) * 0.4
		act("Bearbeitung betrachten (keine Eingabe)")
		await frames(100)

	# 5 Hinaus bis zum Kontinent.
	await press("Ansehen")
	step("5 · Mit dem Mausrad hinaus bis zum Kontinent")
	var center: Vector2 = editor.get_viewport().get_visible_rect().size * Vector2(0.5, 0.48)
	await move_to(center, 16)
	act("Mausrad hinaus")
	await wheel_until(center, false, func() -> bool: return editor.levels.size() == 1, 7, 160)
	# Auf Kontinentebene bis zur Übersicht – aber nicht weiter (sonst folgt der Globus).
	await wheel_until(center, false, _at_overview, 7, 60)
	checks["Zurück auf Kontinentebene"] = not editor.in_globe and editor.levels.size() == 1
	act("Übersicht betrachten (keine Eingabe)")
	await frames(120)

	# 6 Rückgängig und Wiederholen auf Kontinentebene.
	var before := _strokes()
	step("6 · Rückgängig: „Senken“ wird zurückgenommen")
	act("Klick „Rückgängig“")
	await press("Rückgängig")
	await frames(70)
	checks["Rückgängig nimmt die letzte Bearbeitung zurück"] = _strokes() == before - 1
	step("6 · Wiederholen: „Senken“ ist wieder da")
	act("Klick „Wiederholen“")
	await press("Wiederholen")
	await frames(70)
	checks["Wiederholen stellt sie wieder her"] = _strokes() == before
	editor._save_now()
	var reloaded := WorldDocument.load_file(editor.save_path)
	checks["Gespeichert = geladen"] = reloaded != null and editor.same_data(editor.doc.to_dict(), reloaded.to_dict())
	step("Ende", "Ende")
	caption("Ende: gleiche Landschaft, alle Bearbeitungen gespeichert")
	await frames(120)

	var report := capture.finish({"pruefungen": checks, "abschnitte": sections})
	print("ECHTZEIT: %s s, %d Bilder gespeichert, %d Pausen (zusammen %s s)" % [String.num(report["dauer_s"], 1),
		report["gespeicherte_bilder"], report["pausen_anzahl"], String.num(report["pausen_gesamt_s"], 2)])
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
