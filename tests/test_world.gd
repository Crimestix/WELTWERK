extends TestSuite
## Abnahme des Funktionsnachweises auf Ebene der Fachlogik.

const RES := 129


func _doc() -> WorldDocument:
	var doc := WorldDocument.create(4242)
	return doc


func _sampler(doc: WorldDocument) -> TerrainSampler:
	return TerrainSampler.new(doc.continents[0], doc.planet)


func _painted(tool: String, x: float, y: float, radius: float, strength: float) -> Dictionary:
	var s := Stroke.create(tool, radius, strength)
	Stroke.add_point(s, x, y)
	Stroke.add_point(s, x + radius, y)
	return s


func test_globe_roundtrip() -> void:
	var ll := GlobeMath.local_to_latlon(35.0, 10.0, 30.0, 250000.0, -120000.0, 6371000.0)
	var back := GlobeMath.latlon_to_local(35.0, 10.0, 30.0, ll.x, ll.y, 6371000.0)
	check_near(back.x, 250000.0, 1.0, "Osten zurück")
	check_near(back.y, -120000.0, 1.0, "Norden zurück")
	var center := GlobeMath.local_to_latlon(35.0, 10.0, 30.0, 0.0, 0.0, 6371000.0)
	check_near(center.x, 35.0, 0.0001, "Mitte = Breitengrad des Kontinents")


func test_continent_knows_size_and_place() -> void:
	var doc := _doc()
	var c: Dictionary = doc.continents[0]
	# 400 km nach Norden auf einer Erde ≈ 3,6 Breitengrade.
	var north := GlobeMath.local_to_latlon(c["latitude"], c["longitude"], 0.0, 0.0, 400000.0, 6371000.0)
	check_near(north.x - c["latitude"], 3.597, 0.01, "Lage und Maßstab passen zusammen")


func test_generation_is_repeatable() -> void:
	var doc := _doc()
	var a := _sampler(doc).window(0.0, 0.0, 800000.0, RES)
	var b := _sampler(doc).window(0.0, 0.0, 800000.0, RES)
	check_equal(a.height, b.height, "gleicher Ausgangswert → gleiche Höhen")
	check_equal(a.forest, b.forest, "gleicher Ausgangswert → gleicher Wald")
	check(a.height_at(0.0, 0.0) > 0.0, "Mitte ist Land")


func test_contour_change_carries_into_region() -> void:
	var doc := _doc()
	var size: float = doc.continents[0]["size_km"] * 1000.0
	var sea := Vector2(size * 0.49, 0.0)
	var before := _sampler(doc).window(0.0, 0.0, size, RES)
	check(before.height_at(sea.x, sea.y) < 0.0, "Ausgangspunkt liegt im Meer")
	doc.execute(WorldDocument.add_stroke_command(0, _painted("land_add", sea.x - size * 0.05, sea.y, size * 0.075, 1.0)))
	var continent := _sampler(doc).window(0.0, 0.0, size, RES)
	check(continent.height_at(sea.x, sea.y) > 0.0, "Kontur geändert: dort ist jetzt Land")
	var region := _sampler(doc).window(sea.x, sea.y, 100000.0, RES)
	check(region.height_at(sea.x, sea.y) > 0.0, "vertiefte Region übernimmt die neue Küste")


func test_detail_edit_found_again_when_zooming_out() -> void:
	var doc := _doc()
	var p := Vector2(12345.0, -6789.0)
	var detail_before := _sampler(doc).window(p.x, p.y, 1562.5, RES)
	var coarse_before := {}
	for size in [12500.0, 100000.0, 800000.0]:
		coarse_before[size] = _sampler(doc).window(p.x, p.y, size, RES)
	doc.execute(WorldDocument.add_stroke_command(0, _painted("forest_add", p.x, p.y, 150.0, 1.0)))
	doc.execute(WorldDocument.add_stroke_command(0, _painted("raise", p.x, p.y, 150.0, 40.0)))
	var detail := _sampler(doc).window(p.x, p.y, 1562.5, RES)
	check(detail.forest_at(p.x, p.y) > detail_before.forest_at(p.x, p.y) + 0.3, "Wald im Detail gemalt")
	check(detail.height_at(p.x, p.y) > detail_before.height_at(p.x, p.y) + 30.0, "Höhe im Detail erhöht")
	for size in coarse_before:
		var w := _sampler(doc).window(p.x, p.y, size, RES)
		var old: TerrainWindow = coarse_before[size]
		check(w.forest_at(p.x, p.y) >= old.forest_at(p.x, p.y), "%d m: Wald nicht weniger" % size)
		check(w.height_at(p.x, p.y) > old.height_at(p.x, p.y), "%d m: Höhe vereinfacht sichtbar" % size)
		check(w.mark_at(p.x, p.y) > 0.5, "%d m: Bearbeitung am richtigen Ort markiert" % size)
		check(w.mark_at(p.x + size * 0.3, p.y) < 0.01, "%d m: nicht anderswo markiert" % size)


func test_undo_redo_includes_derived_changes() -> void:
	var doc := _doc()
	var p := Vector2(0.0, 0.0)
	var original := _sampler(doc).window(p.x, p.y, 12500.0, RES)
	doc.execute(WorldDocument.add_stroke_command(0, _painted("raise", p.x, p.y, 1500.0, 200.0)))
	var raised := _sampler(doc).window(p.x, p.y, 12500.0, RES)
	check(raised.height != original.height, "Bearbeitung wirkt")
	doc.undo()
	check_equal(_sampler(doc).window(p.x, p.y, 12500.0, RES).height, original.height, "Rückgängig stellt Höhen her")
	doc.redo()
	check_equal(_sampler(doc).window(p.x, p.y, 12500.0, RES).height, raised.height, "Wiederholen stellt Bearbeitung her")
	check(doc.can_undo() and not doc.can_redo(), "Verlauf stimmt")


func test_placement_change_is_undoable() -> void:
	var doc := _doc()
	doc.execute(doc.set_command(0, "latitude", 55.0))
	doc.execute(doc.set_command(0, "climate_override.snowline_offset", -300.0))
	check_near(doc.get_value(0, "latitude"), 55.0, 0.0001, "Breitengrad gesetzt")
	doc.undo()
	doc.undo()
	check_near(doc.get_value(0, "latitude"), 35.0, 0.0001, "Breitengrad zurück")
	check_near(doc.get_value(0, "climate_override.snowline_offset"), 0.0, 0.0001, "Klima zurück")


func test_save_and_load_keep_state() -> void:
	var doc := _doc()
	doc.execute(WorldDocument.add_stroke_command(0, _painted("forest_add", 100.0, 200.0, 300.0, 0.7)))
	doc.execute(doc.set_command(0, "heading", 25.0))
	var path := "user://tests/welt_test.json"
	check_equal(doc.save(path), OK, "speichern")
	var loaded := WorldDocument.load_file(path)
	check(loaded != null, "laden")
	if loaded:
		check_equal(JSON.stringify(loaded.to_dict()), JSON.stringify(doc.to_dict()), "gleicher Stand nach Neustart")
		var a := _sampler(doc).window(0.0, 0.0, 12500.0, RES)
		var b := _sampler(loaded).window(0.0, 0.0, 12500.0, RES)
		check_equal(a.height, b.height, "gleiche Landschaft nach Neustart")
		check_equal(a.forest, b.forest, "gleicher Wald nach Neustart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_new_variant_keeps_hand_edits() -> void:
	var doc := _doc()
	var p := Vector2(5000.0, 5000.0)
	doc.execute(WorldDocument.add_stroke_command(0, _painted("forest_add", p.x, p.y, 400.0, 1.0)))
	doc.execute(doc.set_command(0, "seed", 99))
	var w := _sampler(doc).window(p.x, p.y, 12500.0, RES)
	var g := w.grid_of(p.x, p.y)
	check(w.forest_edit[int(round(g.y)) * w.res + int(round(g.x))] > 0.5, "Handarbeit bleibt bei neuer Variante erhalten")
	check_equal((doc.continents[0]["strokes"] as Array).size(), 1, "Strich noch da")


func test_resize_carries_hand_edits_along() -> void:
	var doc := _doc()
	var size: float = doc.continents[0]["size_km"] * 1000.0
	var sea := Vector2(size * 0.49, 0.0)
	doc.execute(WorldDocument.add_stroke_command(0, _painted("land_add", sea.x - size * 0.05, sea.y, size * 0.075, 1.0)))
	doc.remember_region(0, 1000.0, 2000.0, size / 8.0)
	var before: Dictionary = doc.to_dict()
	doc.execute(doc.resize_command(0, doc.continents[0]["size_km"] * 1.5))
	var stroke: Dictionary = doc.continents[0]["strokes"][0]
	check_near(stroke["radius"], size * 0.075 * 1.5, 0.01, "Pinselgröße wächst mit")
	check_near(stroke["points"][0], (sea.x - size * 0.05) * 1.5, 0.01, "Lage wächst mit")
	check_near(doc.continents[0]["regions"][0]["size"], size / 8.0 * 1.5, 0.01, "Region wächst mit")
	var w := _sampler(doc).window(0.0, 0.0, size * 1.5, RES)
	check(w.height_at(sea.x * 1.5, sea.y) > 0.0, "angefügtes Land liegt weiter an der Küste")
	doc.undo()
	check_equal(JSON.stringify(doc.to_dict()), JSON.stringify(before), "Rückgängig stellt alles exakt her")


func test_climate_follows_latitude_and_override() -> void:
	var warm := Climate.derive(10.0, {}, {})
	var cold := Climate.derive(60.0, {}, {})
	check(warm["snowline"] > cold["snowline"], "Schneegrenze sinkt zu den Polen")
	var moved := Climate.derive(60.0, {}, {"snowline_offset": 500.0})
	check_near(moved["snowline"] - cold["snowline"], 500.0, 0.001, "von Hand verschiebbar")


func test_window_timing() -> void:
	var doc := _doc()
	doc.execute(WorldDocument.add_stroke_command(0, _painted("forest_add", 0.0, 0.0, 300.0, 1.0)))
	for size in [800000.0, 12500.0, 195.3]:
		var started := Time.get_ticks_usec()
		_sampler(doc).window(0.0, 0.0, size, 257)
		print("    Ausschnitt %.0f m, 257×257: %.0f ms" % [size, (Time.get_ticks_usec() - started) / 1000.0])
