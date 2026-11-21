class_name LandmarkRun
extends RefCounted
## Ortsprüfung: dieselbe erkennbare Landschaft auf allen Maßstäben (docs/ORTE_PRUEFUNG.md).
## Aufruf: --orte=<Ordner> --schritt=1|2 (Welt in <Ordner>/welt.json).
##
## Schritt 1 (neue Welt): Kontinent wie im Referenzvergleich mit echten Mausereignissen bauen
## (ComparisonRun.build_outline/build_features), dann aus den Höhendaten drei markante Stellen
## suchen – Gipfel, Pass, Talgrund (Landmarks) – und an festen Kontinentkoordinaten festhalten.
## Jede Stelle mit Markierung auf Kontinent-, Regions- (1:8, 1:64) und Detailstufe (1:512) zeigen,
## Vergleichsbögen zusammensetzen, Höhen und Formen je Stufe messen, dazu im Maßstab des
## Kontinents (120-km-Raster, Verlauf von Hauptkamm und Haupttal). Danach dort mit der Maus
## bearbeiten (Erhöhen, Senken, Glätten), je Bearbeitung Rückgängig/Wiederholen, Speichern.
## Schritt 2 (neuer Prozess, gleiche Datei): Stand, Höhen (bitgleich) und letzte Ansicht prüfen,
## Rückgängig/Wiederholen nach dem Neustart, eine weitere Bearbeitung und Rückgängig.

const PLACES := [
	{"key": "gipfel", "name": "Gipfel", "kind": "peak"},
	{"key": "pass", "name": "Pass", "kind": "pass"},
	{"key": "tal", "name": "Tal", "kind": "valley"},
]
## Stufen der Prüfung: Kontinent, 1:8, 1:64, 1:512 (Vertiefen = 1/8).
const LEVELS := 4
## Stufe, auf der bearbeitet wird (Region 25 km).
const EDIT_LEVEL := 2
## Kameraabstand (Darstellungseinheiten) für alle Vergleichsbilder – gleicher Blick auf jeder Stufe.
const VIEW_DISTANCE := 560.0
## Vergleichsausschnitt je Stelle (Formgröße, Toleranzen grober Stufen): 24 km, 94-m-Raster.
const REF_SIZE := 24000.0
## Prüfraster um jede Stelle: 5 × 5 Punkte im Abstand 1/40 des 25-km-Ausschnitts.
const GRID_SPACING := 25000.0 / 40.0
## Prüfraster im Maßstab des Kontinents: 13 × 13 Punkte im Abstand 10 km (120 km).
const CONTINENT_GRID := 13
const CONTINENT_SPACING := 10000.0
## Haupttalachse: ± so weit entlang des Tals (Richtung aus der Talsuche im 200-km-Ausschnitt).
const VALLEY_HALF := 10000.0
const BRASS := Color(0.88, 0.70, 0.38)
const DARK := Color(0.07, 0.055, 0.04, 0.9)
const PARCHMENT := Color(0.95, 0.9, 0.78)

var editor: Node
var checks := {}
var timing := {}
var report := {}
## Gefundene Stellen: {"key", "name", "kind", "x", "y", "height", "axis", "scale", …}.
var places: Array = []
var _refs := {}
## Linien für den Verlauf auf der Kontinentstufe: "ridge" Gipfel → Joch → Nachbargipfel,
## "valley" Haupttalachse.
var _lines := {}
var _layer: CanvasLayer
var _marks: Control
var _caption: Label


func _init(p_editor: Node) -> void:
	editor = p_editor


func run(dir: String, step: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_setup_overlay()
	await editor._frames(20)
	var started := Time.get_ticks_usec()
	if step == "1":
		await _step_one(dir)
	else:
		await _step_two(dir)
	timing["Ablauf gesamt"] = (Time.get_ticks_usec() - started) / 1000.0
	editor._save_now()
	editor._save_view()
	var failed := 0
	for key in checks:
		if not checks[key]:
			failed += 1
	report["step"] = step
	report["checks"] = checks
	report["timing_ms"] = timing
	report["failed"] = failed
	_write_json(dir.path_join("orte_%s.json" % step), report)
	print("ORTE Schritt %s: %d Prüfungen, %d fehlgeschlagen" % [step, checks.size(), failed])
	for key in checks:
		print("  %s %s" % ["ok  " if checks[key] else "FEHLT", key])
	editor.get_tree().quit()


# --- Schritt 1 -------------------------------------------------------------------------------

func _step_one(dir: String) -> void:
	# a) Kontinent mit echten Mausereignissen bauen (wie der Referenzvergleich).
	var comparison := ComparisonRun.new(editor)
	var t := Time.get_ticks_usec()
	await comparison.build_outline()
	await comparison.build_features(timing)
	editor._use_tool("navigate")
	editor.ui.visible = true
	timing["Kontinent bauen (Maus)"] = (Time.get_ticks_usec() - t) / 1000.0
	for key in comparison.checks:
		checks["Aufbau: " + key] = comparison.checks[key]
	var count: int = (editor.continent()["strokes"] as Array).size()
	checks["Aufbau: Kontinent mit %d Bearbeitungen" % count] = count >= 20

	# b) Stellen suchen (aus den Daten, keine festen Koordinaten).
	editor._forget_windows()
	editor._show_level()
	await editor._frames(5)
	t = Time.get_ticks_usec()
	_find_places()
	timing["Stellen suchen"] = (Time.get_ticks_usec() - t) / 1000.0
	for place in PLACES:
		checks["%s gefunden" % place["name"]] = _place(place["key"]) != null
	if places.is_empty():
		return
	report["continent_id"] = editor.active_id

	# c–e) Je Stelle: vier Stufen mit Markierung, Bögen, Messung.
	var all_tiles := []
	for p in places:
		var tiles := []
		var windows := []
		for level in LEVELS:
			var path := dir.path_join("ort_%s_%d.jpg" % [p["key"], level])
			await _view(p, level, path)
			tiles.append(path)
			windows.append(editor._level_window(level))
		_measure(p, windows)
		_continent_scale(p, windows)
		_sheet([tiles], dir.path_join("vergleich_%s.jpg" % p["key"]), 720)
		all_tiles.append(tiles)
	_sheet(all_tiles, dir.path_join("vergleich_alle.jpg"), 560)
	var plain := []
	for p in places:
		plain.append(_plain(p))
	_write_json(dir.path_join("orte.json"), {"continent_id": editor.active_id, "places": plain,
		"rules": _rules()})

	# f) Bearbeiten an den Stellen (Region 25 km), dann Rückgängig/Wiederholen, Speichern.
	await _edits(dir)

	# Für den Neustart: Höhen frisch berechneter Ausschnitte (gleiche Größe und Auflösung). Lagen und
	# Ausschnitte zusätzlich als Bitmuster (Godots JSON-Leser kann die letzte Binärstelle verschieben).
	var exact := {}
	var ref_windows := {}
	for p in places:
		var rise: Vector2 = p["axis"]["rise"]
		var fall: Vector2 = p["axis"]["fall"]
		exact[p["key"]] = _hex([p["x"], p["y"], rise.x, rise.y, fall.x, fall.y])
		ref_windows[p["key"]] = PackedFloat64Array([p["x"], p["y"], 25000.0, 257.0])
	report["exact_places"] = exact
	report["reference"] = _reference_heights(ref_windows)
	report["places"] = _plain(places)  # nach dem Bearbeiten: mit den Messwerten der Bearbeitungen
	report["strokes"] = (editor.continent()["strokes"] as Array).size()
	var view := []
	for level in editor.levels:
		view.append([level["cx"], level["cy"], level["size"]])
	report["view"] = view


func _find_places() -> void:
	var id: String = editor.active_id
	var sampler: TerrainSampler = editor.sampler_for(id)
	var cw: TerrainWindow = editor._level_window(0)
	var steps := {}
	# Gipfel: Mitte des größten Massivs, dort der höchste Punkt, in zwei Schritten verfeinert.
	var massif := Landmarks.massif_center(cw, 30000.0)
	var area := sampler.window(massif.x, massif.y, 200000.0, 257)
	var peak := Landmarks.highest_in(area, massif, 60000.0)
	var chain := [peak]
	for refine in [[10000.0, 2500.0], [1500.0, 400.0]]:
		var w := sampler.window(peak.x, peak.y, refine[0], 257)
		peak = Landmarks.highest_in(w, peak, refine[1])
		chain.append(peak)
	steps["gipfel"] = chain
	_add_place("gipfel", peak, sampler)

	# Pass: Joch auf dem höchsten Verbindungsweg zu einem anderen hohen Gipfel (Hauptkamm).
	var around := sampler.window(peak.x, peak.y, 120000.0, 257)
	var found := Landmarks.find_pass(around, peak, 15000.0)
	if found.is_empty():
		found = Landmarks.find_pass(around, peak, 6000.0, 60.0)
	if not found.is_empty():
		var col: Vector2 = found["col"]
		chain = [col]
		var axis := Landmarks.axes(around, col, around.cell * 2.0)
		var fine := sampler.window(col.x, col.y, 8000.0, 257)
		col = Landmarks.refine_col(fine, col, axis["rise"], 2500.0, 1200.0)
		chain.append(col)
		axis = Landmarks.axes(fine, col, fine.cell * 4.0)
		var finer := sampler.window(col.x, col.y, 2000.0, 257)
		col = Landmarks.refine_col(finer, col, axis["rise"], 650.0, 300.0)
		chain.append(col)
		steps["pass"] = chain
		steps["pass_partner"] = found["partner"]
		_lines["ridge"] = [peak, col, found["partner"]]
		_add_place("pass", col, sampler)

	# Talgrund: langes, tief eingeschnittenes Tal im Massiv, mind. 15 km von der Küste.
	var coast := Landmarks.coast_distance(cw)
	var valley := Landmarks.find_valley(area, cw, coast, 6000.0, 5000.0, 15000.0)
	if valley.is_empty():
		valley = Landmarks.find_valley(cw, cw, coast, 9000.0, 9000.0, 15000.0)
	if not valley.is_empty():
		var v: Vector2 = valley["point"]
		var along: Vector2 = valley["along"]
		_lines["valley"] = [v - along * VALLEY_HALF, v + along * VALLEY_HALF]
		chain = [v]
		# Erst grob den Haupttalgrund suchen (nicht in eine Seitenrinne rutschen), dann verfeinern.
		for refine in [[25000.0, 4000.0], [6000.0, 600.0], [1500.0, 150.0]]:
			var w := sampler.window(v.x, v.y, refine[0], 257)
			v = Landmarks.lowest_in(w, v, refine[1])
			chain.append(v)
		steps["tal"] = chain
		steps["tal_depth"] = valley["depth"]
		_add_place("tal", v, sampler)
	var plain_steps := {}
	for key in steps:
		plain_steps[key] = _plain(steps[key])
	report["search"] = plain_steps
	report["lines"] = _plain(_lines)
	report["massif_center"] = _plain(massif)


## Stelle festhalten: Höhe, Achsen und Formgröße aus dem feinen Vergleichsausschnitt.
func _add_place(key: String, p: Vector2, sampler: TerrainSampler) -> void:
	var info: Dictionary = {}
	for place in PLACES:
		if place["key"] == key:
			info = place.duplicate()
	var ref := sampler.window(p.x, p.y, REF_SIZE, 257)
	_refs[key] = ref
	var axis := Landmarks.axes(ref, p, 600.0) if info["kind"] != "peak" else {"rise": Vector2.RIGHT, "fall": Vector2.UP}
	info["x"] = p.x
	info["y"] = p.y
	info["height"] = ref.height_at(p.x, p.y)
	info["axis"] = axis
	info["scale"] = Landmarks.feature_scale(ref, info["kind"], p, axis, REF_SIZE * 0.45)
	places.append(info)


func _place(key: String) -> Variant:
	for p in places:
		if p["key"] == key:
			return p
	return null


## e) Höhen und Formen je Stufe: windows[0..3] = Kontinent … Detail (angezeigte Ausschnitte).
func _measure(p: Dictionary, windows: Array) -> void:
	var at := Vector2(p["x"], p["y"])
	var ref: TerrainWindow = _refs[p["key"]]
	var finest: TerrainWindow = windows[LEVELS - 1]
	var names := _level_names()
	var per_level := []
	for level in LEVELS:
		var w: TerrainWindow = windows[level]
		var entry := {"name": names[level], "cell_m": w.cell, "window": [w.cx, w.cy, w.size, w.res],
			"height": w.height_at(at.x, at.y)}
		# Höhen auf dem 5 × 5-Raster gegen das über eine Zelle dieser Stufe gemittelte feine Gelände.
		if level < LEVELS - 1:
			var diffs := []
			var old_diffs := []
			var inside := true
			var worst_ratio := -INF
			var worst := 0.0
			var worst_tol := 0.0
			var bias := 0.0
			var means := PackedFloat64Array()
			var old_worst := 0.0
			var old_bias := 0.0
			var old_inside := true
			for gj in 5:
				var row := []
				var old_row := []
				for gi in 5:
					var q := at + Vector2((gi - 2) * GRID_SPACING, (2 - gj) * GRID_SPACING)
					# Feinster Ausschnitt, der eine ganze Zelle um den Punkt enthält.
					var source: TerrainWindow = finest if Landmarks.fits(finest, q, w.cell) else ref
					var mean := Landmarks.cell_mean(source, q, w.cell)
					var tol := Landmarks.cell_mean_tolerance(source, q, w.cell)
					var d := w.height_at(q.x, q.y) - mean
					means.append(mean)
					row.append(snappedf(d, 0.01))
					bias += d / 25.0
					if absf(d) > tol:
						inside = false
					if absf(d) / tol > worst_ratio:
						worst_ratio = absf(d) / tol
						worst = absf(d)
						worst_tol = tol
					# Zur Information: frühere Messung gegen die Detailstufe mit weiter Toleranz.
					var od := w.height_at(q.x, q.y) - finest.height_at(q.x, q.y)
					var old_span := Landmarks.RESOLVE_CELLS * w.cell + GRID_SPACING * 2.0 * sqrt(2.0)
					var old_source: TerrainWindow = finest if old_span < finest.size * 0.5 else ref
					old_row.append(snappedf(od, 0.01))
					old_bias += od / 25.0
					old_worst = maxf(old_worst, absf(od))
					old_inside = old_inside and absf(od) <= Landmarks.height_tolerance(old_source, q, w.cell)
				diffs.append(row)
				old_diffs.append(old_row)
			var limit := Landmarks.bias_limit(means)
			entry["diff_to_cell_mean_m"] = diffs
			entry["worst_diff_to_cell_mean_m"] = worst
			entry["worst_tolerance_m"] = worst_tol
			entry["mean_bias_m"] = bias
			entry["mean_bias_limit_m"] = limit
			entry["info_diff_to_detail_m"] = old_diffs
			entry["info_max_abs_diff_to_detail_m"] = old_worst
			entry["info_mean_diff_to_detail_m"] = old_bias
			entry["info_old_tolerance_ok"] = old_inside
			checks["%s · %s: Höhen = Zellmittel des feinen Geländes (knappste Stelle %d m, erlaubt %d m)" % [p["name"],
				names[level], int(round(worst)), int(round(worst_tol))]] = inside
			checks["%s · %s: kein Höhenversatz (Mittel %+d m, erlaubt ±%d m)" % [p["name"], names[level],
				int(round(bias)), int(round(limit))]] = absf(bias) <= limit
		var form := Landmarks.classify(w, ref, p["kind"], at, p["scale"], p["axis"])
		entry["form"] = form
		var what: String = {"peak": "bleibt Höchstpunkt", "pass": "bleibt Sattel", "valley": "bleibt Tiefstpunkt"}[p["kind"]]
		if form["resolved"]:
			var detail := ""
			if form.has("offset_m") and form["offset_m"] <= form["offset_allowed_m"]:
				detail = " (Lage %s daneben, erlaubt %s)" % [EditorUI.meters(form["offset_m"]), EditorUI.meters(form["offset_allowed_m"])]
			elif form.has("offset_m"):
				detail = " (dort %s daneben, aber nur %d m Unterschied, erlaubt %d m)" % [EditorUI.meters(form["offset_m"]),
					int(round(absf(form["extreme_height"] - form["height"]))), int(round(form["tolerance_m"]))]
			else:
				var parts := []
				for part in ["rise", "fall"]:
					var name: String = "Kamm" if part == "rise" else "quer"
					var value: float = form[part + "_kept"] if part == "rise" else -form[part + "_kept"]
					if form[part + "_resolved"]:
						parts.append("%s %+d m" % [name, int(round(value))])
					else:
						parts.append("%s zu klein für das Raster, ausgenommen" % name)
				detail = " (%s)" % "; ".join(PackedStringArray(parts))
			checks["%s · %s: %s%s" % [p["name"], names[level], what, detail]] = form["ok"]
		else:
			checks["%s · %s: zu klein für das Raster (%s), darf geglättet sein" % [p["name"], names[level],
				EditorUI.meters(w.cell)]] = true
		per_level.append(entry)
	p["levels"] = per_level


## e) Im Maßstab des Kontinents selbst: 13 × 13-Raster über 120 km um die Stelle, Kontinentstufe
## gegen den 200-km-Ausschnitt, auf Kontinentzellen gemittelt. Dazu der Verlauf von Hauptkamm
## (beim Pass) bzw. Haupttalachse (beim Tal).
func _continent_scale(p: Dictionary, windows: Array) -> void:
	var cont: TerrainWindow = windows[0]
	var region: TerrainWindow = windows[1]
	var names := _level_names()
	var c := cont.cell
	var at := Vector2(p["x"], p["y"])
	var coarse := PackedFloat64Array()
	var means := PackedFloat64Array()
	var bias := 0.0
	var half := (CONTINENT_GRID - 1) / 2
	for gj in CONTINENT_GRID:
		for gi in CONTINENT_GRID:
			var q := at + Vector2(gi - half, half - gj) * CONTINENT_SPACING
			if not Landmarks.fits(region, q, c * 0.5):
				continue
			var mean := Landmarks.cell_mean(region, q, c)
			coarse.append(cont.height_at(q.x, q.y))
			means.append(mean)
			bias += cont.height_at(q.x, q.y) - mean
	var count := coarse.size()
	bias = bias / count if count > 0 else 0.0
	var r := Landmarks.correlation(coarse, means)
	var limit := Landmarks.bias_limit(means)
	var full := count == CONTINENT_GRID * CONTINENT_GRID
	var span := "%d km, %d × %d" % [int(CONTINENT_SPACING * (CONTINENT_GRID - 1) / 1000.0), CONTINENT_GRID, CONTINENT_GRID]
	checks["%s · %s ↔ %s (%s): gleicher Verlauf (Korrelation %s, mindestens 0,9%s)" % [p["name"], names[0], names[1], span,
		String.num(r, 3), "" if full else "; nur %d Punkte im Ausschnitt" % count]] = full and r >= 0.9
	checks["%s · %s ↔ %s (%s): kein Höhenversatz (Mittel %+d m, erlaubt ±%d m)" % [p["name"], names[0], names[1], span,
		int(round(bias)), int(round(limit))]] = full and absf(bias) <= limit
	var info := {"grid_points": count, "spacing_m": CONTINENT_SPACING, "correlation": r, "mean_bias_m": bias,
		"mean_bias_limit_m": limit}
	var line: Array = []
	var ridge := true
	var what := ""
	if p["kind"] == "pass" and _lines.has("ridge"):
		line = _lines["ridge"]
		what = "Hauptkamm Gipfel – Joch – Nachbargipfel bleibt Kamm"
	elif p["kind"] == "valley" and _lines.has("valley"):
		line = _lines["valley"]
		ridge = false
		what = "Haupttalachse (%s) bleibt Talgrund" % EditorUI.meters(VALLEY_HALF * 2.0)
	if not line.is_empty():
		# Linie innerhalb einer Zelle, Seiten im Abstand von zwei Zellen.
		var at_coarse := Landmarks.course(func(q: Vector2) -> float: return cont.height_at(q.x, q.y),
			line, c * 0.5, c, c * 2.0, ridge)
		var at_region := Landmarks.course(func(q: Vector2) -> float: return Landmarks.cell_mean(region, q, c),
			line, c * 0.5, c, c * 2.0, ridge)
		var valid := 0
		var shown := 0
		var kept := 0
		var kept_all := 0
		var missing := []
		for k in at_coarse.size():
			var q: Vector2 = at_coarse[k]["point"]
			if not Landmarks.fits(region, q, c * 2.5):
				continue
			valid += 1
			if at_coarse[k]["kept"]:
				kept_all += 1
			if not at_region[k]["kept"]:
				continue
			shown += 1
			if at_coarse[k]["kept"]:
				kept += 1
			else:
				missing.append(_plain(q))
		var need := int(ceil(0.9 * shown))
		info["course"] = {"samples": at_coarse.size(), "inside_region": valid, "region_shows": shown, "continent_keeps": kept,
			"continent_keeps_anywhere": kept_all, "missing": missing, "line": _plain(line)}
		checks["%s · %s: %s (%d von %d Punkten, mind. %d; im 200-km-Ausschnitt gemittelt erkennbar an %d von %d)" % [
			p["name"], names[0], what, kept, shown, need, shown, valid]] = valid >= 5 and shown * 2 >= valid and kept >= need
	p["continent_scale"] = info


# --- Ansichten -------------------------------------------------------------------------------

func _level_names() -> Array:
	var size: float = editor.continent()["size_km"] * 1000.0
	return ["Kontinent", "Region " + EditorUI.meters(size / 8.0), "Region " + EditorUI.meters(size / 64.0),
		"Detail " + EditorUI.meters(size / 512.0)]


## Zur Stufe level über der Stelle: erst ganz heraus, dann über der Stelle vertiefen.
func _goto(p: Dictionary, level: int) -> void:
	if editor.in_globe:
		editor.open_continent(editor.active_id)
	while editor.levels.size() > 1:
		editor.zoom_out()
	for k in level:
		var t := Time.get_ticks_usec()
		editor.deepen_at(editor.landscape.to_render(p["x"], p["y"]))
		var key := "Vertiefen auf %s (größte Dauer)" % EditorUI.meters(editor.levels.back()["size"])
		timing[key] = maxf(timing.get(key, 0.0), (Time.get_ticks_usec() - t) / 1000.0)
	await editor._frames(3)


func _view(p: Dictionary, level: int, path: String) -> void:
	await _goto(p, level)
	_look_at(p)
	_caption.text = "%s · %s" % [p["name"], _level_names()[level]]
	editor.ui._flash("", 0.0, false)
	await editor._frames(30)
	await editor._shot(path)


func _look_at(p: Dictionary) -> void:
	editor.camera_rig.jump_to(editor.landscape.to_render(p["x"], p["y"]), VIEW_DISTANCE)


# --- Bearbeiten ------------------------------------------------------------------------------

func _edits(dir: String) -> void:
	var peak: Variant = _place("gipfel")
	await _goto(peak if peak != null else places[0], 0)
	_look_at(peak if peak != null else places[0])
	_caption.text = "Kontinent · vor dem Bearbeiten"
	await editor._frames(25)
	await editor._shot(dir.path_join("bearbeitung_kontinent_vorher.jpg"))
	# Glätten mit großem, vollem Pinsel entlang des Kamms – eine echte, messbare Bearbeitung.
	var plan := [
		["gipfel", "raise", 0.06, 0.8, "Gipfel erhöht"],
		["tal", "lower", 0.05, 0.7, "Tal vertieft"],
		["pass", "smooth", 0.08, 1.0, "Pass geglättet"],
	]
	for item in plan:
		var p: Variant = _place(item[0])
		if p == null:
			continue
		await _edit(dir, p, item[1], item[2], item[3], item[4])
	await _goto(peak if peak != null else places[0], 0)
	_look_at(peak if peak != null else places[0])
	_caption.text = "Kontinent · nach dem Bearbeiten"
	await editor._frames(25)
	await editor._shot(dir.path_join("bearbeitung_kontinent_nachher.jpg"))
	editor._save_now()
	var reloaded := WorldDocument.load_file(editor.save_path)
	checks["Gespeichert = geladen"] = reloaded != null and editor.same_data(editor.doc.to_dict(), reloaded.to_dict())


## Eigener, frischer Sampler ohne zwischengespeicherte Grundform – unabhängig vom Editor.
func _fresh_sampler() -> TerrainSampler:
	TerrainSampler.clear_base_cache()
	return TerrainSampler.new(editor.continent(), editor.doc.planet)


func _stroke_count() -> int:
	return (editor.continent()["strokes"] as Array).size()


## Eine Bearbeitung mit echten Mausereignissen an der Stelle (Region 25 km), mit Messung, dann
## Rückgängig und Wiederholen an derselben Stelle.
func _edit(dir: String, p: Dictionary, tool: String, fraction: float, strength: float, label: String) -> void:
	await _goto(p, EDIT_LEVEL)
	_look_at(p)
	_caption.text = "%s · %s · vorher" % [p["name"], _level_names()[EDIT_LEVEL]]
	editor.ui._flash("", 0.0, false)
	await editor._frames(25)
	await editor._shot(dir.path_join("bearbeitung_%s_vorher.jpg" % p["key"]))
	var at := Vector2(p["x"], p["y"])
	var level: Dictionary = editor.levels.back()
	# Frisch berechnet: Zwischenspeicher der Grundform geleert, eigener Sampler.
	var fresh_before := _fresh_sampler().window(level["cx"], level["cy"], level["size"], 257)
	checks["%s: angezeigter Ausschnitt = frisch berechnet (bitgleich)" % p["name"]] = \
		editor.landscape.window.height == fresh_before.height
	var continent_before := _continent_window(_fresh_sampler())
	var count := _stroke_count()
	# Strich: Gipfel quer darüber, Tal entlang der Talsohle, Pass entlang des Kamms.
	var dir_vec := Vector2.RIGHT
	var half := 400.0
	if p["kind"] == "valley":
		dir_vec = p["axis"]["fall"]
		half = 1500.0
	elif p["kind"] == "pass":
		dir_vec = p["axis"]["rise"]
		half = 1500.0
	editor._use_tool(tool)
	editor.ui.set_brush(fraction, strength)
	var radius: float = editor.landscape.brush_radius_m
	var t := Time.get_ticks_usec()
	await editor._mouse_stroke([at - dir_vec * half, at, at + dir_vec * half])
	timing["%s (Malen mit der Maus)" % label] = (Time.get_ticks_usec() - t) / 1000.0
	editor._use_tool("navigate")
	await editor._frames(10)
	# Live bemalter Ausschnitt, direkt nach dem Strich (noch nicht neu berechnet).
	var shown: TerrainWindow = editor.landscape.window
	var live: PackedFloat32Array = shown.height.duplicate()
	var live_window := [shown.cx, shown.cy, shown.size, shown.res]
	checks["%s: eine neue Bearbeitung" % label] = _stroke_count() == count + 1
	var delta := shown.height_at(at.x, at.y) - fresh_before.height_at(at.x, at.y)
	var entry := {"tool": tool, "radius_m": radius, "shown_delta_m": delta}
	match p["kind"]:
		"peak":
			checks["%s: Darstellung dort deutlich höher (%+d m, mind. +100 m)" % [label, int(round(delta))]] = delta > 100.0
		"valley":
			checks["%s: Darstellung dort tiefer (%+d m)" % [label, int(round(delta))]] = delta < -30.0
		_:
			# Rauheit im voll geglätteten Inneren (der Rand des Pinsels geht weich über).
			var rough_before := _roughness(fresh_before, at, radius * 0.5)
			var rough_after := _roughness(shown, at, radius * 0.5)
			var moved := 0.0
			for k in 64:
				var q := at + Vector2(cos(k * Landmarks.GOLDEN), sin(k * Landmarks.GOLDEN)) * radius * sqrt((k + 0.5) / 64.0)
				moved = maxf(moved, absf(shown.height_at(q.x, q.y) - fresh_before.height_at(q.x, q.y)))
			entry["roughness_before_m"] = rough_before
			entry["roughness_after_m"] = rough_after
			# Zur Information: Rauheit gröberer Wellenlängen (Nachbarn im Abstand 8 bzw. 16 Zellen).
			for cells in [8.0, 16.0]:
				entry["info_roughness_%d_cells_m" % int(cells)] = [_roughness(fresh_before, at, radius * 0.5, cells),
					_roughness(shown, at, radius * 0.5, cells)]
			entry["max_change_m"] = moved
			var share := rough_after / rough_before - 1.0 if rough_before > 0.0 else 0.0
			checks["%s: Darstellung dort verändert (bis %s m, mind. 20 m)" % [label, String.num(moved, 1)]] = moved > 20.0
			checks["%s: Stelle wird ruhiger (Rauheit %s → %s m, %+d %%, mind. −15 %%)" % [label, String.num(rough_before, 2),
				String.num(rough_after, 2), int(round(share * 100.0))]] = share <= -0.15
	# Vereinfacht auf der Kontinentstufe (frisch berechnet wie beim Herauszoomen).
	t = Time.get_ticks_usec()
	var continent_after := _continent_window(_fresh_sampler())
	timing["Kontinentstufe frisch berechnen (%s)" % label] = (Time.get_ticks_usec() - t) / 1000.0
	var reach := radius + continent_after.cell
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var relief_before := Landmarks.disc_range(continent_before, at, reach)
	var relief_after := Landmarks.disc_range(continent_after, at, reach)
	for k in 41:
		var q := at if k == 40 else at + Vector2(cos(k * Landmarks.GOLDEN), sin(k * Landmarks.GOLDEN)) * reach * sqrt((k + 0.5) / 40.0)
		var d := continent_after.height_at(q.x, q.y) - continent_before.height_at(q.x, q.y)
		lo = minf(lo, d)
		hi = maxf(hi, d)
		sum += d
	entry["continent_change_m"] = {"min": lo, "max": hi, "mean": sum / 41.0, "mark": continent_after.mark_at(at.x, at.y),
		"relief_before": relief_before.y - relief_before.x, "relief_after": relief_after.y - relief_after.x}
	match p["kind"]:
		"peak":
			checks["%s: auf der Kontinentstufe vereinfacht sichtbar (bis %+d m)" % [label, int(round(hi))]] = hi > 1.0 and sum > 0.0
		"valley":
			checks["%s: auf der Kontinentstufe vereinfacht sichtbar (bis %+d m)" % [label, int(round(lo))]] = lo < -1.0 and sum < 0.0
		_:
			var rb := relief_before.y - relief_before.x
			var ra := relief_after.y - relief_after.x
			checks["%s: Kontinentstufe nicht unruhiger (Spannweite %d → %d m)" % [label, int(rb), int(ra)]] = ra <= rb * 1.01 + 10.0  # Rundung der Zellmittel; geglättet wird nur im feinen Anteil
	_caption.text = "%s · %s · nachher (%s)" % [p["name"], _level_names()[EDIT_LEVEL], label]
	await editor._frames(20)
	await editor._shot(dir.path_join("bearbeitung_%s_nachher.jpg" % p["key"]))
	_sheet([[dir.path_join("bearbeitung_%s_vorher.jpg" % p["key"]), dir.path_join("bearbeitung_%s_nachher.jpg" % p["key"])]],
		dir.path_join("bearbeitung_%s.jpg" % p["key"]), 900)

	# Rückgängig: angezeigter Ausschnitt und Kontinentstufe bitgleich wie vor der Bearbeitung.
	t = Time.get_ticks_usec()
	editor._undo()
	timing["Rückgängig (%s)" % label] = (Time.get_ticks_usec() - t) / 1000.0
	await editor._frames(5)
	var w: TerrainWindow = editor.landscape.window
	checks["%s · Rückgängig: eine Bearbeitung weniger" % label] = _stroke_count() == count
	checks["%s · Rückgängig: angezeigter Ausschnitt bitgleich wie vorher" % label] = w.height == fresh_before.height
	var undo_continent: TerrainWindow = editor._level_window(0)
	checks["%s · Rückgängig: Kontinentstufe bitgleich wie vorher" % label] = undo_continent.height == continent_before.height
	entry["undo_max_diff_m"] = _max_diff(w.height, fresh_before.height)
	entry["undo_continent_max_diff_m"] = _max_diff(undo_continent.height, continent_before.height)
	_caption.text = "%s · Rückgängig (%s)" % [p["name"], label]
	await editor._frames(20)
	await editor._shot(dir.path_join("bearbeitung_%s_rueckgaengig.jpg" % p["key"]))
	# Wiederholen: gleicher Ausschnitt wie beim Malen, Höhen wie live gemalt; Kontinentstufe wie danach.
	t = Time.get_ticks_usec()
	editor._redo()
	timing["Wiederholen (%s)" % label] = (Time.get_ticks_usec() - t) / 1000.0
	await editor._frames(5)
	w = editor.landscape.window
	var same_window: bool = [w.cx, w.cy, w.size, w.res] == live_window
	var worst := _max_diff(w.height, live)
	entry["redo_max_diff_to_live_painting_m"] = worst
	checks["%s · Wiederholen: Bearbeitung wieder da, gleicher Ausschnitt, Höhen wie live gemalt (Abweichung %s m)" % [label,
		String.num(worst, 4)]] = _stroke_count() == count + 1 and same_window and worst < 0.01
	var redo_continent: TerrainWindow = editor._level_window(0)
	entry["redo_continent_max_diff_m"] = _max_diff(redo_continent.height, continent_after.height)
	checks["%s · Wiederholen: Kontinentstufe bitgleich wie nach dem Malen" % label] = redo_continent.height == continent_after.height
	p["edit"] = entry


func _continent_window(sampler: TerrainSampler) -> TerrainWindow:
	return sampler.window(0.0, 0.0, editor.continent()["size_km"] * 1000.0, editor.CONTINENT_RES)


## Mittlere Abweichung vom Mittel der vier Nachbarn (Abstand cells Rasterzellen) in einer Scheibe.
static func _roughness(w: TerrainWindow, c: Vector2, r: float, cells: float = 2.0) -> float:
	var d := w.cell * cells
	var sum := 0.0
	for k in 80:
		var q := c + Vector2(cos(k * Landmarks.GOLDEN), sin(k * Landmarks.GOLDEN)) * r * sqrt((k + 0.5) / 80.0)
		var around := (w.height_at(q.x + d, q.y) + w.height_at(q.x - d, q.y) + w.height_at(q.x, q.y + d) + w.height_at(q.x, q.y - d)) * 0.25
		sum += absf(w.height_at(q.x, q.y) - around)
	return sum / 80.0


static func _max_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for k in a.size():
		worst = maxf(worst, absf(a[k] - b[k]))
	return worst


# --- Neustart --------------------------------------------------------------------------------

## Frisch berechnete Ausschnitte (eigener Sampler, Grundform nicht aus dem Zwischenspeicher) je
## Stelle: Prüfsumme und Höhen. windows: Schlüssel → PackedFloat64Array [cx, cy, Größe, Auflösung].
func _reference_heights(windows: Dictionary) -> Dictionary:
	var sampler := _fresh_sampler()
	var out := {}
	for key in windows:
		var spec: PackedFloat64Array = windows[key]
		var cx := spec[0]
		var cy := spec[1]
		var w := sampler.window(cx, cy, spec[2], int(spec[3]))
		var grid := []
		for gj in 5:
			for gi in 5:
				grid.append(w.height_at(cx + (gi - 2) * GRID_SPACING, cy + (2 - gj) * GRID_SPACING))
		# Genaue Werte als Bitmuster (Godots JSON-Leser kann die letzte Binärstelle verschieben).
		var exact := PackedFloat64Array([w.height_at(cx, cy)])
		exact.append_array(PackedFloat64Array(grid))
		out[key] = {"window": [cx, cy, spec[2], int(spec[3])], "window_exact": spec.to_byte_array().hex_encode(),
			"md5": _md5(w.height), "height": w.height_at(cx, cy), "grid": grid, "exact": exact.to_byte_array().hex_encode()}
	var cw := _continent_window(sampler)
	out["kontinent"] = {"md5": _md5(cw.height)}
	return out


static func _hex(values: Array) -> String:
	return PackedFloat64Array(values).to_byte_array().hex_encode()


static func _unhex(text: String) -> PackedFloat64Array:
	if text == "" or text.length() % 16 != 0:
		return PackedFloat64Array()
	return text.hex_decode().to_float64_array()


static func _md5(values: PackedFloat32Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(values.to_byte_array())
	return ctx.finish().hex_encode()


func _step_two(dir: String) -> void:
	var text := FileAccess.get_file_as_string(dir.path_join("orte_1.json"))
	var before: Variant = JSON.parse_string(text)
	checks["Ergebnis von Schritt 1 gelesen"] = before is Dictionary
	if not before is Dictionary:
		return
	# Lagen und Achsen aus den Bitmustern (genau wie in Schritt 1, ohne Umweg über JSON-Zahlen).
	var exact_places: Dictionary = before.get("exact_places", {})
	var decoded := 0
	for plain in before.get("places", []):
		var p: Dictionary = (plain as Dictionary).duplicate(true)
		var bits := _unhex(exact_places.get(p["key"], ""))
		if bits.size() == 6:
			decoded += 1
			p["x"] = bits[0]
			p["y"] = bits[1]
			p["axis"] = {"rise": Vector2(bits[2], bits[3]), "fall": Vector2(bits[4], bits[5])}
		else:
			var axis: Dictionary = p["axis"]
			p["axis"] = {"rise": Vector2(axis["rise"][0], axis["rise"][1]), "fall": Vector2(axis["fall"][0], axis["fall"][1])}
		places.append(p)
	checks["Neustart: Lagen als Bitmuster gelesen (%d von %d Stellen)" % [decoded, places.size()]] = \
		decoded == places.size() and decoded > 0
	checks["Neustart: Kontinent da"] = editor.doc.continents.size() == 1 and editor.active_id == before.get("continent_id", "")
	checks["Neustart: gleiche Zahl Bearbeitungen (%d)" % int(before.get("strokes", -1))] = \
		(editor.continent()["strokes"] as Array).size() == int(before.get("strokes", -1))
	var view: Array = before.get("view", [])
	var same_view: bool = not editor.in_globe and editor.levels.size() == view.size()
	if same_view:
		for k in view.size():
			var level: Dictionary = editor.levels[k]
			same_view = same_view and absf(level["cx"] - view[k][0]) < 0.01 and absf(level["cy"] - view[k][1]) < 0.01 \
				and absf(level["size"] - view[k][2]) < 0.01
	checks["Neustart: letzte Ansicht wiederhergestellt (%d Stufen)" % view.size()] = same_view
	var stored: Dictionary = before.get("reference", {})
	var ref_windows := {}
	for p in places:
		var spec := _unhex(stored.get(p["key"], {}).get("window_exact", ""))
		ref_windows[p["key"]] = spec if spec.size() == 4 else PackedFloat64Array([p["x"], p["y"], 25000.0, 257.0])
		var same_spot: bool = spec.size() == 4 and spec[0] == p["x"] and spec[1] == p["y"]
		checks["Neustart: %s – Ausschnitt aus Bitmuster, Mitte = Stelle (bitgleich)" % p["name"]] = same_spot
	var now := _reference_heights(ref_windows)
	for p in places:
		var a: Dictionary = now[p["key"]]
		var b: Dictionary = stored.get(p["key"], {})
		checks["Neustart: %s – Höhen bitgleich (25-km-Ausschnitt, Prüfsumme)" % p["name"]] = a["md5"] == b.get("md5", "")
		var same: bool = a["exact"] == b.get("exact", "")
		checks["Neustart: %s – %s m an derselben Stelle (und 5 × 5 Punkte)" % [p["name"], EditorUI._number(a["height"], 1)]] = same
	checks["Neustart: Kontinentstufe bitgleich (Prüfsumme)"] = now["kontinent"]["md5"] == stored.get("kontinent", {}).get("md5", "")
	_caption.text = "Nach dem Neustart · letzte Ansicht"
	await editor._frames(25)
	await editor._shot(dir.path_join("neustart_ansicht.jpg"))

	# Rückgängig/Wiederholen nach dem Neustart, an der zuletzt bearbeiteten Stelle.
	var p: Variant = _place("pass")
	if p == null:
		p = places[0]
	await _goto(p, EDIT_LEVEL)
	_look_at(p)
	await editor._frames(10)
	var level: Dictionary = editor.levels.back()
	var at := Vector2(p["x"], p["y"])
	var start: PackedFloat32Array = _fresh_sampler().window(level["cx"], level["cy"], level["size"], 257).height
	checks["Nach Neustart: angezeigter Ausschnitt = frisch berechnet (bitgleich)"] = editor.landscape.window.height == start
	var count: int = (editor.continent()["strokes"] as Array).size()
	editor._use_tool("raise")
	editor.ui.set_brush(0.05, 0.6)
	var side: Vector2 = p["axis"]["fall"]
	var spot := at + side * 1500.0
	await editor._mouse_stroke([spot - p["axis"]["rise"] * 300.0, spot + p["axis"]["rise"] * 300.0])
	editor._use_tool("navigate")
	await editor._frames(5)
	var raised: float = editor.landscape.window.height_at(spot.x, spot.y) - _height_in(start, editor.landscape.window, spot)
	checks["Nach Neustart: Erhöhen mit der Maus wirkt (%+d m)" % int(round(raised))] = \
		raised > 20.0 and (editor.continent()["strokes"] as Array).size() == count + 1
	var painted: PackedFloat32Array = editor.landscape.window.height.duplicate()
	await editor._shot(dir.path_join("neustart_bearbeitet.jpg"))
	editor._undo()
	await editor._frames(5)
	checks["Nach Neustart: Rückgängig bitgleich zum geladenen Stand"] = editor.landscape.window.height == start \
		and (editor.continent()["strokes"] as Array).size() == count
	editor._redo()
	await editor._frames(5)
	var worst := _max_diff(editor.landscape.window.height, painted)
	checks["Nach Neustart: Wiederholen stellt die Bearbeitung her (Abweichung %s m)" % String.num(worst, 4)] = \
		(editor.continent()["strokes"] as Array).size() == count + 1 and worst < 0.01
	# Eine weitere Bearbeitung (Senken am Pass) und Rückgängig.
	var redone: PackedFloat32Array = _fresh_sampler().window(level["cx"], level["cy"], level["size"], 257).height
	editor._use_tool("lower")
	editor.ui.set_brush(0.04, 0.5)
	await editor._mouse_stroke([at - p["axis"]["rise"] * 300.0, at + p["axis"]["rise"] * 300.0])
	editor._use_tool("navigate")
	await editor._frames(5)
	var lowered: float = editor.landscape.window.height_at(at.x, at.y) - _height_in(redone, editor.landscape.window, at)
	checks["Nach Neustart: weitere Bearbeitung (Senken %+d m)" % int(round(lowered))] = lowered < -10.0 \
		and (editor.continent()["strokes"] as Array).size() == count + 2
	editor._undo()
	await editor._frames(5)
	checks["Nach Neustart: Rückgängig der weiteren Bearbeitung bitgleich"] = editor.landscape.window.height == redone \
		and (editor.continent()["strokes"] as Array).size() == count + 1
	_caption.text = "Nach dem Neustart · bearbeitet, Rückgängig, Wiederholen"
	await editor._frames(20)
	await editor._shot(dir.path_join("neustart_ende.jpg"))
	editor._save_now()
	var reloaded := WorldDocument.load_file(editor.save_path)
	checks["Nach Neustart: gespeichert = geladen"] = reloaded != null and editor.same_data(editor.doc.to_dict(), reloaded.to_dict())
	report["places"] = before.get("places", [])


## Höhe an p aus einem gespeicherten Höhenfeld mit dem Raster von w (bilinear).
static func _height_in(values: PackedFloat32Array, w: TerrainWindow, p: Vector2) -> float:
	var copy := TerrainWindow.new(w.cx, w.cy, w.size, w.res)
	copy.height = values
	return copy.height_at(p.x, p.y)


# --- Markierungen ----------------------------------------------------------------------------

func _setup_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	editor.add_child(_layer)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_layer.add_child(_marks)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", PARCHMENT)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 7)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.position = Vector2(-400, 54)
	_caption.size = Vector2(800, 36)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_caption)
	editor.get_tree().process_frame.connect(_marks.queue_redraw)


## Messingnadel je Stelle: Ring am Boden, senkrechter Stiel, Kopf mit Name und Höhe dieser Stufe.
func _draw_marks() -> void:
	if editor.in_globe or editor.landscape.window == null:
		return
	var cam: Camera3D = editor.camera_rig.camera
	var w: TerrainWindow = editor.landscape.window
	var font := ThemeDB.fallback_font
	var used := []
	for p in places:
		var x: float = p["x"]
		var y: float = p["y"]
		if not w.contains(x, y):
			continue
		var r: Vector3 = editor.landscape.to_render(x, y)
		r.y = editor.landscape.height_at(r.x, r.z)
		if cam.is_position_behind(r):
			continue
		var s := cam.unproject_position(r)
		var text := "%s  %s m" % [p["name"], EditorUI._number(w.height_at(x, y), 0)]
		var top := s - Vector2(0.0, 58.0)
		# Liegen Stellen dicht beieinander, werden die Köpfe übereinander gestaffelt.
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
		var moved := true
		while moved:
			moved = false
			for rect in used:
				if (rect as Rect2).intersects(Rect2(top - Vector2(10.0, 14.0), Vector2(width, 28.0))):
					top.y -= 30.0
					moved = true
		used.append(Rect2(top - Vector2(10.0, 14.0), Vector2(width, 28.0)))
		_marks.draw_line(s, top, DARK, 5.0, true)
		_marks.draw_line(s, top, BRASS, 2.4, true)
		_marks.draw_arc(s, 9.0, 0.0, TAU, 40, DARK, 5.0, true)
		_marks.draw_arc(s, 9.0, 0.0, TAU, 40, BRASS, 2.4, true)
		_marks.draw_circle(s, 2.6, BRASS)
		_marks.draw_circle(top, 8.0, DARK)
		_marks.draw_circle(top, 6.2, BRASS)
		var at := top + Vector2(13.0, 7.0)
		_marks.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 7, Color(0, 0, 0, 0.9))
		_marks.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PARCHMENT)


# --- Bögen und Ausgabe -----------------------------------------------------------------------

## Bilder als Raster zusammensetzen (rows: Liste von Zeilen, je Liste von Pfaden).
func _sheet(rows: Array, out_path: String, tile_width: int) -> void:
	var tiles := []
	var tile_height := 0
	var columns := 0
	for row in rows:
		var line := []
		for path in row:
			var img := Image.load_from_file(path)
			if img == null:
				continue
			img.convert(Image.FORMAT_RGB8)
			var h := int(img.get_height() * float(tile_width) / img.get_width())
			img.resize(tile_width, h, Image.INTERPOLATE_LANCZOS)
			tile_height = maxi(tile_height, h)
			line.append(img)
		columns = maxi(columns, line.size())
		tiles.append(line)
	if columns == 0:
		return
	var gap := 8
	var out := Image.create(columns * (tile_width + gap) - gap, tiles.size() * (tile_height + gap) - gap, false, Image.FORMAT_RGB8)
	out.fill(Color(0.06, 0.05, 0.04))
	for r in tiles.size():
		for c in (tiles[r] as Array).size():
			var img: Image = tiles[r][c]
			out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(c * (tile_width + gap), r * (tile_height + gap)))
	out.save_jpg(out_path, 0.88)
	print("Bild: ", out_path)


func _rules() -> Dictionary:
	return {
		"grid": "5 × 5 Punkte im Abstand %s um jede Stelle; Höhen jeder Stufe gegen das über eine Zelle dieser Stufe gemittelte feine Gelände" % EditorUI.meters(GRID_SPACING),
		"height_tolerance": "je Punkt 20 m + 15 % der Spannweite des feinen Geländes innerhalb einer Zelle der Stufe; mittlerer Versatz über das Raster höchstens 20 m + 10 % der Höhenspanne des Rasters",
		"height_info": "nur zur Information: Abweichung gegen die Detailstufe und die frühere Toleranz (20 m + halbe Spannweite innerhalb von 1,5 Zellen)",
		"continent_grid": "%d × %d Punkte im Abstand %s (120 km) um jede Stelle: Kontinentstufe gegen den 200-km-Ausschnitt, auf Kontinentzellen gemittelt; Korrelation mindestens 0,9, mittlerer Versatz höchstens 20 m + 10 %% der Höhenspanne" % [CONTINENT_GRID, CONTINENT_GRID, EditorUI.meters(CONTINENT_SPACING)],
		"continent_course": "Hauptkamm Gipfel – Joch – Nachbargipfel bzw. Haupttalachse (± %s): Punkte im Abstand einer halben Kontinentzelle; höchster bzw. tiefster Wert innerhalb einer Zelle quer zur Linie über bzw. unter beiden Seiten im Abstand von zwei Zellen; gezählt werden Punkte, an denen der gemittelte 200-km-Ausschnitt den Verlauf zeigt (mind. die Hälfte), davon mind. 90 %% auf der Kontinentstufe" % EditorUI.meters(VALLEY_HALF),
		"resolution": "Form(teil) gilt als aufgelöst, wenn seine Größe (Radius) mindestens 1,5 Zellen beträgt; kleinere Teile dürfen geglättet sein, aufgelöste Teile werden geprüft",
		"form": "aufgelöst: mindestens 30 % des Reliefs (gemessen im selben Abstand im Vergleichsausschnitt) erhalten; Gipfel/Talgrund dieser Stufe höchstens eine Rasterzelle (mind. ¼ Formgröße) neben der Stelle oder kaum höher/tiefer (20 m + 10 % des Reliefs); Pass steigt entlang des Kamms und fällt quer dazu",
		"feature_size": "Halbrelief-Radius: Gipfel Kreismittel, Tal quer zum Tal, Pass Kammanstieg und Querabfall – kleinster Abstand mit halbem Höchstwert (bis 10,8 km)",
		"edits": "Erhöhen mind. +100 m; Glätten: Rauheit mind. −15 %, Änderung mind. 20 m; je Bearbeitung Rückgängig (Ausschnitt und Kontinentstufe bitgleich wie vorher) und Wiederholen (Ausschnitt wie live gemalt, Kontinentstufe bitgleich wie danach)",
	}


static func _plain(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Array:
		var out := []
		for v in value:
			out.append(_plain(v))
		return out
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _plain(value[k])
		return out
	return value


func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_plain(data), "  ", true, true))
	file.close()
