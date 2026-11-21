extends TestSuite
## Mehrere Kontinente, gezeichnete Formen, örtliche Erzeugung, Schutz, Flüsse, Seen, Ebene.

const RES := 129


func _drawn_doc() -> WorldDocument:
	var doc := WorldDocument.new()
	doc.continents.append(WorldDocument.new_continent(77, WorldDocument.BASE_DRAWN, 1000.0))
	return doc


func _square(cx: float, cy: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - half, cy - half), Vector2(cx + half, cy - half),
		Vector2(cx + half, cy + half), Vector2(cx - half, cy + half)])


func _window(doc: WorldDocument, id: String, cx: float, cy: float, size: float) -> TerrainWindow:
	return TerrainSampler.new(doc.continent(id), doc.planet).window(cx, cy, size, RES)


func test_drawn_continent_is_sea_until_shape_is_drawn() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	var empty := _window(doc, id, 0.0, 0.0, 1000000.0)
	check(empty.height_at(0.0, 0.0) < 0.0, "leer gezeichnet = Meer")
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 200000.0), 15000.0)))
	var w := _window(doc, id, 0.0, 0.0, 1000000.0)
	check(w.height_at(0.0, 0.0) > 0.0, "innen Land")
	check(w.height_at(350000.0, 0.0) < 0.0, "außen Meer")
	doc.undo()
	check(_window(doc, id, 0.0, 0.0, 1000000.0).height_at(0.0, 0.0) < 0.0, "Rückgängig nimmt die Form weg")


func test_shape_remove_cuts_a_bay() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 250000.0), 15000.0)))
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(false, _square(150000.0, 0.0, 60000.0), 10000.0)))
	var w := _window(doc, id, 0.0, 0.0, 1000000.0)
	check(w.height_at(150000.0, 0.0) < 0.0, "Bucht ist Wasser")
	check(w.height_at(-100000.0, 0.0) > 0.0, "Rest bleibt Land")


func test_several_continents_with_ids_and_undo() -> void:
	var doc := WorldDocument.create(1)
	var first: String = doc.continents[0]["id"]
	var second := WorldDocument.new_continent(2, WorldDocument.BASE_GENERATED, 900.0, -20.0, 80.0)
	doc.execute(WorldDocument.add_continent_command(second))
	check_equal(doc.continents.size(), 2, "zwei Kontinente")
	doc.execute(doc.set_command(second["id"], "latitude", -30.0))
	doc.execute(doc.remove_continent_command(first))
	check_equal(doc.continents.size(), 1, "einer gelöscht")
	check_near(doc.get_value(second["id"], "latitude"), -30.0, 0.0001, "der andere bleibt unverändert")
	doc.undo()
	check_equal(doc.continents[0]["id"], first, "gelöschter Kontinent wieder an seinem Platz")
	doc.undo()
	check_near(doc.get_value(second["id"], "latitude"), -20.0, 0.0001, "Lage zurück – über ID, nicht Platz")
	doc.undo()
	check_equal(doc.continents.size(), 1, "Anlegen rückgängig")
	doc.redo()
	doc.redo()
	doc.redo()
	check_equal(doc.continents.size(), 1, "wiederholt: zweiter angelegt, erster gelöscht")
	check_equal(doc.continents[0]["id"], second["id"], "richtiger Kontinent übrig")


func test_save_and_load_several_continents_and_new_tools() -> void:
	var doc := WorldDocument.create(5)
	var other := WorldDocument.new_continent(6, WorldDocument.BASE_DRAWN, 700.0, 50.0, -40.0)
	other["name"] = ""
	doc.execute(WorldDocument.add_continent_command(other))
	doc.execute(WorldDocument.add_stroke_command(other["id"], Stroke.create_shape(true, _square(0.0, 0.0, 100000.0), 8000.0)))
	var mountains := Stroke.create_generated("gen_mountains", 40000.0, 1800.0, 1234)
	Stroke.add_point(mountains, -50000.0, 0.0)
	Stroke.add_point(mountains, 50000.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(other["id"], mountains))
	var path := "user://tests/welt_mehrere.json"
	check_equal(doc.save(path), OK, "speichern")
	var loaded := WorldDocument.load_file(path)
	check(loaded != null, "laden")
	if loaded:
		check_equal(loaded.continents.size(), 2, "beide Kontinente")
		check_equal(typeof(loaded.continent(other["id"])["strokes"][1]["seed"]), TYPE_INT, "Ausgangswert bleibt ganzzahlig")
		var a := _window(doc, other["id"], 0.0, 0.0, 700000.0)
		var b := _window(loaded, other["id"], 0.0, 0.0, 700000.0)
		check_equal(a.height, b.height, "gleiche Landschaft nach Neustart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_generated_mountains_are_repeatable_and_rise() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 300000.0), 15000.0)))
	var before := _window(doc, id, 0.0, 0.0, 400000.0)
	var m := Stroke.create_generated("gen_mountains", 50000.0, 2000.0, 99)
	for k in 5:
		Stroke.add_point(m, -100000.0 + k * 50000.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(id, m))
	var a := _window(doc, id, 0.0, 0.0, 400000.0)
	var b := _window(doc, id, 0.0, 0.0, 400000.0)
	check_equal(a.height, b.height, "wiederholbar")
	check(a.height_at(0.0, 0.0) > before.height_at(0.0, 0.0) + 500.0, "Gebirge hebt das Land")
	check_near(a.height_at(0.0, 250000.0), before.height_at(0.0, 250000.0), 0.01, "außerhalb unverändert")


func test_protected_area_keeps_old_variant_and_blocks_generation() -> void:
	var doc := WorldDocument.create(11)
	var id: String = doc.continents[0]["id"]
	var p := Vector2(30000.0, -20000.0)
	var original := _window(doc, id, p.x, p.y, 100000.0)
	var protect := Stroke.create_generated("protect", 30000.0, 1.0, 11)
	Stroke.add_point(protect, p.x, p.y)
	doc.execute(WorldDocument.add_stroke_command(id, protect))
	doc.execute(doc.set_command(id, "seed", 12))
	var varied := _window(doc, id, p.x, p.y, 100000.0)
	check_near(varied.height_at(p.x, p.y), original.height_at(p.x, p.y), 0.5, "geschützt: alte Grundform bleibt")
	check(absf(varied.height_at(p.x + 45000.0, p.y + 45000.0) - original.height_at(p.x + 45000.0, p.y + 45000.0)) > 0.01,
		"außerhalb: neue Variante wirkt")
	var m := Stroke.create_generated("gen_mountains", 40000.0, 2000.0, 5)
	Stroke.add_point(m, p.x, p.y)
	doc.execute(WorldDocument.add_stroke_command(id, m))
	var after := _window(doc, id, p.x, p.y, 100000.0)
	check_near(after.height_at(p.x, p.y), varied.height_at(p.x, p.y), 1.0, "Erzeugung wirkt nicht im Schutzbereich")


func test_river_carves_bed_and_sets_water_level() -> void:
	var doc := WorldDocument.create(21)
	var id: String = doc.continents[0]["id"]
	var path := PackedVector2Array([Vector2(-3000.0, 0.0), Vector2(0.0, 0.0), Vector2(3000.0, 0.0)])
	var before := _window(doc, id, 0.0, 0.0, 8000.0)
	var levels := PackedFloat32Array()
	for q in path:
		levels.append(before.height_at(q.x, q.y) - 1.0)
	var river := Stroke.create_river(path, levels, 40.0, 3.0)
	check(river["heights"][1] <= river["heights"][0] and river["heights"][2] <= river["heights"][1], "Spiegel fällt flussabwärts")
	doc.execute(WorldDocument.add_stroke_command(id, river))
	var w := _window(doc, id, 0.0, 0.0, 8000.0)
	var lvl := w.water_level_at(0.0, 0.0)
	check(lvl > TerrainWindow.NO_WATER, "Wasserspiegel im Fluss")
	check(w.height_at(0.0, 0.0) < lvl, "Bett unter dem Spiegel")
	check_equal(w.water_level_at(0.0, 1500.0), TerrainWindow.NO_WATER, "neben dem Fluss kein Wasser")
	# Grob (Kontinent) ist der Fluss mindestens eine Zelle breit vorhanden.
	var coarse := _window(doc, id, 0.0, 0.0, 400000.0)
	check(coarse.water_level_at(0.0, 0.0) > TerrainWindow.NO_WATER, "grob sichtbar")


func test_lake_and_flatten() -> void:
	var doc := WorldDocument.create(31)
	var id: String = doc.continents[0]["id"]
	var c := Vector2(5000.0, 5000.0)
	var base := _window(doc, id, c.x, c.y, 6000.0)
	var lake := Stroke.create_lake(400.0, base.height_at(c.x, c.y) - 2.0, 6.0)
	Stroke.add_point(lake, c.x, c.y)
	doc.execute(WorldDocument.add_stroke_command(id, lake))
	var w := _window(doc, id, c.x, c.y, 6000.0)
	check(w.water_level_at(c.x, c.y) > TerrainWindow.NO_WATER, "See hat Wasserspiegel")
	check(w.height_at(c.x, c.y) < w.water_level_at(c.x, c.y), "Grund unter dem Spiegel")
	var flat := Stroke.create("flatten", 600.0, 1.0)
	flat["level"] = 300.0
	Stroke.add_point(flat, c.x + 2000.0, c.y)
	doc.execute(WorldDocument.add_stroke_command(id, flat))
	var f := _window(doc, id, c.x, c.y, 6000.0)
	check_near(f.height_at(c.x + 2000.0, c.y), 300.0, 5.0, "Ebene auf Zielhöhe")


func test_islands_generator_creates_land_in_sea() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	var g := Stroke.create_generated("gen_islands", 60000.0, 1.0, 7)
	Stroke.add_point(g, 0.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(id, g))
	var w := _window(doc, id, 0.0, 0.0, 200000.0)
	var land := 0
	for k in w.height.size():
		if w.height[k] > 0.0:
			land += 1
	check(land > 20 and land < w.height.size() / 2, "einige Inseln (%d Punkte Land)" % land)


func test_resize_scales_new_tools_too() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(100000.0, 0.0, 50000.0), 10000.0)))
	doc.execute(doc.resize_command(id, 2000.0))
	var s: Dictionary = doc.continent(id)["strokes"][0]
	check_near(s["points"][0], 100000.0 * 2.0 - 100000.0, 0.01, "Form wandert mit")
	check_near(s["radius"], 20000.0, 0.01, "Rand wächst mit")


func test_land_edits_apply_in_order() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	var sq := _square(0.0, 0.0, 150000.0)
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, sq, 10000.0)))
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, sq, 10000.0)))
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(false, _square(0.0, 0.0, 60000.0), 8000.0)))
	var w := _window(doc, id, 0.0, 0.0, 1000000.0)
	check(w.height_at(0.0, 0.0) < 0.0, "zweimal Form, dann wegschneiden: Meer")
	var paint := Stroke.create("land_add", 20000.0, 1.0)
	Stroke.add_point(paint, 100000.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(id, paint))
	var cut := Stroke.create("land_remove", 20000.0, 1.0)
	Stroke.add_point(cut, 100000.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(id, cut))
	check(_window(doc, id, 100000.0, 0.0, 200000.0).height_at(100000.0, 0.0) < 0.0, "Land auf Land, dann abtragen: Meer")


func test_no_land_beyond_continent_window() -> void:
	for seed_value in [1, 2, 3, 4242]:
		var doc := WorldDocument.create(seed_value)
		var id: String = doc.continents[0]["id"]
		var big := Stroke.create("land_add", 300000.0, 1.0)
		Stroke.add_point(big, 790000.0, 0.0)
		doc.execute(WorldDocument.add_stroke_command(id, big))
		var w := _window(doc, id, 0.0, 0.0, 2000000.0)
		check(w.height_at(820000.0, 0.0) < 0.0, "Ausgangswert %d: außerhalb des Kontinentfensters kein Land" % seed_value)
		check(w.height_at(700000.0, 0.0) > 0.0, "Ausgangswert %d: innen bleibt das angefügte Land" % seed_value)


func test_resize_grows_the_generated_base_too() -> void:
	var doc := WorldDocument.create(9)
	var id: String = doc.continents[0]["id"]
	var p := Vector2(120000.0, -80000.0)
	var before := _window(doc, id, p.x, p.y, 50000.0).height_at(p.x, p.y)
	doc.execute(doc.resize_command(id, 3200.0))
	var after := _window(doc, id, p.x * 2.0, p.y * 2.0, 100000.0).height_at(p.x * 2.0, p.y * 2.0)
	check_near(after, before, 40.0, "Grundform an p·Faktor wie vorher an p")


func test_planet_size_is_an_undoable_value() -> void:
	var doc := WorldDocument.create(3)
	doc.execute(doc.set_command(WorldDocument.PLANET, "radius_km", 12742.0))
	check_near(doc.planet["radius_km"], 12742.0, 0.001, "doppelte Erde")
	doc.undo()
	check_near(doc.planet["radius_km"], 6371.0, 0.001, "zurück")


func test_land_area_of_a_drawn_square() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 200000.0), 4000.0)))
	var stats := TerrainSampler.new(doc.continent(id), doc.planet).window(0.0, 0.0, 1000000.0, 257).land_stats()
	check_near(stats["area_km2"], 160000.0, 160000.0 * 0.06, "400 km × 400 km ≈ 160.000 km²")


func test_damaged_file_is_kept_and_last_good_state_loaded() -> void:
	var path := "user://tests/welt_defekt.json"
	var doc := WorldDocument.create(5)
	check_equal(doc.save(path), OK, "speichern")
	check_equal(doc.save(path), OK, "nochmal speichern (legt .bak an)")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{kaputt")
	f.close()
	var loaded := WorldDocument.load_file(path)
	check(loaded != null, "letzter guter Stand geladen")
	check(FileAccess.file_exists(path + ".defekt"), "beschädigte Datei beiseitegelegt")
	check(WorldDocument.load_problem != "", "Hinweis vorhanden")
	for suffix in ["", ".bak", ".defekt", ".neu"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func test_old_world_file_without_ids_loads() -> void:
	var data := {"format": "weltwerk-welt", "version": 1, "planet": {"radius_km": 6371.0},
		"continents": [{"seed": 4242.0, "size_km": 1600.0, "latitude": 35.0, "longitude": 10.0, "heading": 0.0,
			"climate_override": {"snowline_offset": 0.0, "humidity_offset": 0.0}, "strokes": [], "regions": []}]}
	var doc := WorldDocument.from_dict(data)
	check(doc != null, "geladen")
	if doc:
		check((doc.continents[0]["id"] as String).length() > 4, "ID ergänzt")
		check_equal(doc.continents[0]["scatter_seed"], 4242, "Streuung wie bisher")
