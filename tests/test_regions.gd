extends TestSuite
## Dauerhaft gespeicherte Detailregionen (RegionStore, TerrainSampler.set_regions, WorldDocument).

const DIR := "user://tests/regionen"


func _continent() -> Dictionary:
	var c := WorldDocument.new_continent(4711, WorldDocument.BASE_GENERATED, 800.0)
	var range_stroke := Stroke.create_generated("gen_mountains", 60000.0, 2500.0, 99)
	for k in 6:
		Stroke.add_point(range_stroke, -100000.0 + k * 40000.0, 20000.0)
	(c["strokes"] as Array).append(range_stroke)
	return c


func _planet() -> Dictionary:
	return {"radius_km": 6371.0, "temperature_offset": 0.0}


## Region anlegen wie der Editor: Ausschnitt rechnen, Daten speichern, Prüfsumme eintragen.
func _make_region(c: Dictionary, world: String, cx: float, cy: float, size: float) -> Dictionary:
	var w := TerrainSampler.new(c, _planet()).window(cx, cy, size, 257)
	var region := {"id": RegionStore.new_id(), "cx": cx, "cy": cy, "size": size, "res": 257}
	region["checksum"] = RegionStore.save(world, region, w)
	return region


func _load(world: String, region: Dictionary) -> Dictionary:
	var data := RegionStore.load_data(world, region).duplicate()
	data["cx"] = region["cx"]
	data["cy"] = region["cy"]
	data["size"] = region["size"]
	return data


func test_region_file_roundtrip_and_damage() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_a.json")
	var c := _continent()
	var region := _make_region(c, world, 10000.0, 5000.0, 100000.0)
	check(region["checksum"] != "", "Regionsdaten gespeichert")
	RegionStore.clear_cache()
	var data := RegionStore.load_data(world, region)
	check(not data.is_empty(), "Regionsdaten wieder gelesen")
	var w := TerrainSampler.new(c, _planet()).window(10000.0, 5000.0, 100000.0, 257)
	check(data["layers"]["relief_low"] == w.relief_low, "gelesene Grunddaten bitgleich")
	# Beschädigte Datei: wird abgewiesen (dort gilt dann wieder die Erzeugung).
	var path := RegionStore.file_for(world, region)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("kaputt")
	f.close()
	RegionStore.clear_cache()
	check(RegionStore.load_data(world, region).is_empty(), "beschädigte Regionsdatei abgewiesen")


func test_region_view_equals_generation_until_generation_changes() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_b.json")
	var c := _continent()
	TerrainSampler.clear_base_cache()
	var before := TerrainSampler.new(c, _planet()).window(0.0, 20000.0, 100000.0, 257)
	var region := _make_region(c, world, 0.0, 20000.0, 100000.0)
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([_load(world, region)])
	TerrainSampler.clear_base_cache()
	var with_region := s.window(0.0, 20000.0, 100000.0, 257)
	check(with_region.height == before.height, "Region zeigt genau das übernommene Gelände (bitgleich)")
	# Neue Variante der Grundform: In der Region bleibt das gespeicherte Gelände, außerhalb nicht.
	c["seed"] = 8888
	var s2 := TerrainSampler.new(c, _planet())
	s2.set_regions([_load(world, region)])
	TerrainSampler.clear_base_cache()
	var after := s2.window(0.0, 20000.0, 100000.0, 257)
	check(after.height == before.height, "Region bleibt nach neuer Variante erhalten (dauerhaft gespeichert)")
	var outside_before := TerrainSampler.new(_continent(), _planet()).window(300000.0, -300000.0, 100000.0, 65)
	var outside_after := s2.window(300000.0, -300000.0, 100000.0, 65)
	check(outside_after.height != outside_before.height, "außerhalb der Region wirkt die neue Variante")


func test_coarse_view_summarises_region() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_c.json")
	var c := _continent()
	var region := _make_region(c, world, 0.0, 20000.0, 100000.0)
	var data := _load(world, region)
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([data])
	TerrainSampler.clear_base_cache()
	TerrainSampler.clear_region_results()
	var fine := s.window(0.0, 20000.0, 100000.0, 257)
	var coarse := s.window(0.0, 0.0, 800000.0, 129)
	# Höhe der groben Ansicht = Mittel des fertigen Regionsgeländes über eine grobe Zelle.
	var worst := 0.0
	var count := 0
	for k in 25:
		var x := -30000.0 + (k % 5) * 15000.0
		var y := -10000.0 + (k / 5) * 15000.0
		var g := coarse.grid_of(x, y)
		var i := int(round(g.x))
		var j := int(round(g.y))
		var px := coarse.x_at(i)
		var py := coarse.y_at(j)
		if RegionStore.weight(data, px, py) < 0.999:
			continue
		# Gleichmäßig über die grobe Zelle (6.250 m), 16 × 16 Stichproben ≈ eine je Regionszelle.
		var mean := 0.0
		for dj in 16:
			for di in 16:
				mean += fine.height_at(px + ((di + 0.5) / 16.0 - 0.5) * coarse.cell, py + ((dj + 0.5) / 16.0 - 0.5) * coarse.cell)
		mean /= 256.0
		worst = maxf(worst, absf(coarse.height[j * coarse.res + i] - mean))
		count += 1
	check(count >= 9, "genug Prüfpunkte innerhalb der Region (%d)" % count)
	check(worst < 0.5, "grobe Ansicht zeigt das Zellmittel der Region (größte Abweichung %.2f m)" % worst)


func test_edit_recomputes_only_touched_region_result() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_d.json")
	var c := _continent()
	var a := _make_region(c, world, -100000.0, 20000.0, 50000.0)
	var b := _make_region(c, world, 120000.0, 20000.0, 50000.0)
	a["result_path"] = RegionStore.result_file_for(world, a)
	b["result_path"] = RegionStore.result_file_for(world, b)
	var regions := [_load(world, a), _load(world, b)]
	regions[0]["result_path"] = a["result_path"]
	regions[1]["result_path"] = b["result_path"]
	TerrainSampler.clear_region_results()
	var s := TerrainSampler.new(c, _planet())
	s.set_regions(regions)
	var coarse_before := s.window(0.0, 0.0, 800000.0, 129)
	check(FileAccess.file_exists(a["result_path"]) and FileAccess.file_exists(b["result_path"]), "Zwischenstände gespeichert")
	# Nach „Neustart“: Zwischenstände von der Platte ergeben dieselbe Übersicht (bitgleich).
	TerrainSampler.clear_region_results()
	TerrainSampler.clear_base_cache()
	var s_disk := TerrainSampler.new(c, _planet())
	s_disk.set_regions(regions)
	check(s_disk.window(0.0, 0.0, 800000.0, 129).height == coarse_before.height, "Übersicht aus gespeicherten Zwischenständen bitgleich")
	# Bearbeitung in Region a: deren Ergebnis ändert sich, das von b bleibt (gleicher Stand).
	var key_a := s._result_key(regions[0])
	var key_b := s._result_key(regions[1])
	var raise := Stroke.create("raise", 8000.0, 1.0)
	Stroke.add_point(raise, -100000.0, 20000.0)
	(c["strokes"] as Array).append(raise)
	var s2 := TerrainSampler.new(c, _planet())
	s2.set_regions(regions)
	check(s2._result_key(regions[1]) == key_b, "unberührte Region behält ihren Stand")
	check(s2._result_key(regions[0]) != key_a, "berührte Region bekommt einen neuen Stand")
	var coarse_after := s2.window(0.0, 0.0, 800000.0, 129)
	var at_a := coarse_after.height_at(-100000.0, 20000.0) - coarse_before.height_at(-100000.0, 20000.0)
	check(at_a > 0.1, "Bearbeitung erscheint in der Übersicht (%.2f m)" % at_a)
	# Gegenprobe ohne jeden Zwischenspeicher.
	TerrainSampler.clear_region_results()
	TerrainSampler.clear_base_cache()
	var plain := [regions[0].duplicate(), regions[1].duplicate()]
	plain[0].erase("result_path")
	plain[1].erase("result_path")
	var s3 := TerrainSampler.new(c, _planet())
	s3.set_regions(plain)
	check(s3.window(0.0, 0.0, 800000.0, 129).height == coarse_after.height, "Übersicht gleich der Neuberechnung ohne Zwischenstand")


func test_resize_keeps_region_identity() -> void:
	var doc := WorldDocument.new()
	doc.continents.append(_continent())
	var id: String = doc.continents[0]["id"]
	doc.add_region(id, {"id": "region-x", "cx": 1000.0, "cy": 2000.0, "size": 50000.0, "res": 257, "checksum": "abc"})
	doc.execute(doc.resize_command(id, 1600.0))
	var r: Dictionary = doc.continent(id)["regions"][0]
	check(r.get("id") == "region-x" and r.get("checksum") == "abc", "Kennung und Daten bleiben beim Vergrößern")
	check(is_equal_approx(float(r["size"]), 100000.0), "Lage und Größe wachsen mit")
	doc.undo()
	check(is_equal_approx(float(doc.continent(id)["regions"][0]["size"]), 50000.0), "Rückgängig stellt die Größe wieder her")


func test_result_key_survives_save_and_load() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("welt_e.json")
	var doc := WorldDocument.new()
	var c := _continent()
	var brush := Stroke.create("raise", 1234.5678901234567, 0.3333333333333333)
	for k in 40:
		Stroke.add_point(brush, -12345.678901234567 + k * 101.10101010101, 9876.54321 + sin(k * 0.7) * 333.3333333)
	(c["strokes"] as Array).append(brush)
	doc.continents.append(c)
	check(doc.save(path) == OK, "Welt gespeichert")
	var loaded := WorldDocument.load_file(path)
	var region := {"cx": -10000.0, "cy": 10000.0, "size": 25000.0, "res": 257, "checksum": "x"}
	var a := TerrainSampler.new(doc.continents[0], _planet())._result_key(region)
	var b := TerrainSampler.new(loaded.continents[0], _planet())._result_key(region)
	check(a == b, "Stand einer Region nach Speichern und Laden unverändert (Zwischenstand bleibt gültig)")


func test_disk_result_follows_undo_and_redo() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_f.json")
	var c := _continent()
	var region := _make_region(c, world, 30000.0, 20000.0, 50000.0)
	var data := _load(world, region)
	data["result_path"] = RegionStore.result_file_for(world, region)
	TerrainSampler.clear_region_results()
	var raise := Stroke.create("raise", 6000.0, 1.0)
	Stroke.add_point(raise, 30000.0, 20000.0)
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([data])
	s.window(0.0, 0.0, 800000.0, 129)                    # Stand ohne Bearbeitung
	(c["strokes"] as Array).append(raise)
	var s1 := TerrainSampler.new(c, _planet())
	s1.set_regions([data])
	s1.window(0.0, 0.0, 800000.0, 129)                   # Stand mit Bearbeitung
	(c["strokes"] as Array).pop_back()                   # Rückgängig
	var s0 := TerrainSampler.new(c, _planet())
	s0.set_regions([data])
	s0.window(0.0, 0.0, 800000.0, 129)                   # aus dem Speicher
	s0.keep_results_on_disk()                            # wie beim Speichern der Welt
	check(not RegionStore.load_result(data["result_path"], s0._result_key(data), 257).is_empty(),
		"nach Rückgängig liegt der Stand ohne Bearbeitung auf der Platte (Ergebnis kam aus dem Speicher)")
	(c["strokes"] as Array).append(raise)                # Wiederholen
	var s2 := TerrainSampler.new(c, _planet())
	s2.set_regions([data])
	s2.keep_results_on_disk()
	var key := s2._result_key(data)
	check(not RegionStore.load_result(data["result_path"], key, 257).is_empty(),
		"nach Rückgängig und Wiederholen liegt der aktuelle Stand als Zwischenstand auf der Platte")


func test_live_painting_does_not_change_cached_result() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_g.json")
	var c := _continent()
	var region := _make_region(c, world, 0.0, 20000.0, 50000.0)
	var data := _load(world, region)
	TerrainSampler.clear_region_results()
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([data])
	var shown := s.window(0.0, 20000.0, 50000.0, 257)
	var before: PackedFloat32Array = s.region_result(data)["height"].duplicate()
	# Wie Live-Malen: der angezeigte Ausschnitt wird an Ort und Stelle zusammengesetzt.
	var h := shown.height
	for k in h.size():
		h[k] += 100.0
	shown.height = h
	shown.compose_rect(0, 0, 256, 256)
	check(s.region_result(data)["height"] == before, "gemerktes Regionsergebnis bleibt beim Live-Malen unverändert")


func test_undo_resize_keeps_regions_created_afterwards() -> void:
	var doc := WorldDocument.new()
	doc.continents.append(_continent())
	var id: String = doc.continents[0]["id"]
	doc.execute(doc.resize_command(id, 1600.0))
	doc.add_region(id, {"id": "region-neu", "cx": 2000.0, "cy": 4000.0, "size": 50000.0, "res": 257, "checksum": "abc"})
	doc.undo()
	var after_undo: Array = doc.continent(id)["regions"]
	check(after_undo.size() == 1 and after_undo[0]["id"] == "region-neu", "Region bleibt beim Rückgängig der Größenänderung")
	check(is_equal_approx(float(after_undo[0]["size"]), 25000.0) and is_equal_approx(float(after_undo[0]["cx"]), 1000.0),
		"Region schrumpft mit dem Kontinent")
	doc.redo()
	var after_redo: Array = doc.continent(id)["regions"]
	check(after_redo.size() == 1 and is_equal_approx(float(after_redo[0]["size"]), 50000.0), "und wächst beim Wiederholen wieder mit")
	# Mehrfach hin und her: jede Region genau einmal, Größe stimmt.
	for cycle in 3:
		doc.undo()
		doc.redo()
	var cycled: Array = doc.continent(id)["regions"]
	check(cycled.size() == 1 and is_equal_approx(float(cycled[0]["size"]), 50000.0), "nach drei Wechseln genau eine Region (%d)" % cycled.size())
	# Region, die im zurückgenommenen Stand angelegt wird, bleibt nach Wiederholen und Rückgängig.
	doc.undo()
	doc.add_region(id, {"id": "region-klein", "cx": 0.0, "cy": 0.0, "size": 10000.0, "res": 257, "checksum": "ghi"})
	for cycle in 3:
		doc.redo()
		doc.undo()
	var back: Array = doc.continent(id)["regions"]
	var ids := {}
	for r in back:
		ids[r["id"]] = int(ids.get(r["id"], 0)) + 1
	check(back.size() == 2 and ids.get("region-klein", 0) == 1 and ids.get("region-neu", 0) == 1,
		"beide Regionen genau einmal nach weiteren Wechseln (%s)" % str(ids))
	# Anlegen rückgängig und wiederholen: Regionen des Kontinents bleiben.
	var doc2 := WorldDocument.new()
	var c2 := _continent()
	doc2.execute(WorldDocument.add_continent_command(c2))
	var id2: String = c2["id"]
	doc2.add_region(id2, {"id": "region-b", "cx": 0.0, "cy": 0.0, "size": 50000.0, "res": 257, "checksum": "def"})
	doc2.undo()
	doc2.redo()
	check(doc2.continent(id2).get("regions", []).size() == 1, "Region bleibt bei Anlegen rückgängig und wiederholen")


func test_finer_view_follows_region_after_new_variant() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_h.json")
	var c := _continent()
	var region := _make_region(c, world, 0.0, 20000.0, 100000.0)
	region["basis"] = TerrainSampler.new(c, _planet()).base_fingerprint(0.0, 20000.0, 100000.0, 257)
	var data := _load(world, region)
	data["basis"] = region["basis"]
	TerrainSampler.clear_base_cache()
	var fine_before := TerrainSampler.new(c, _planet()).window(5000.0, 15000.0, 12500.0, 257)
	c["seed"] = 8888
	TerrainSampler.clear_base_cache()
	var plain_after := TerrainSampler.new(c, _planet()).window(5000.0, 15000.0, 12500.0, 257)
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([data])
	var fine_after := s.window(5000.0, 15000.0, 12500.0, 257)
	var kept := 0.0
	var changed := 0.0
	for k in fine_before.relief_low.size():
		kept += pow(fine_after.relief_low[k] - fine_before.relief_low[k], 2.0)
		changed += pow(plain_after.relief_low[k] - fine_before.relief_low[k], 2.0)
	kept = sqrt(kept / fine_before.relief_low.size())
	changed = sqrt(changed / fine_before.relief_low.size())
	check(changed > 50.0, "neue Variante ändert das Gelände ohne Region deutlich (%.0f m)" % changed)
	check(kept < changed * 0.15, "feinerer Ausschnitt in der Region behält deren Gelände (%.1f m statt %.0f m)" % [kept, changed])


func test_region_forest_follows_climate() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_i.json")
	var c := _continent()
	c["latitude"] = 27.0
	var region := _make_region(c, world, 0.0, 20000.0, 100000.0)
	var data := _load(world, region)
	c["latitude"] = 50.0
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([data])
	TerrainSampler.clear_base_cache()
	var w := s.window(0.0, 20000.0, 100000.0, 257)
	var dry: float = s.climate["dryness"]
	var worst := 0.0
	var pot: PackedFloat32Array = data["layers"]["forest_potential"]
	for k in range(0, pot.size(), 97):
		worst = maxf(worst, absf(w.base_forest[k] - TerrainSampler.forest_from_potential(pot[k], dry)))
	check(worst < 1.0e-5, "Waldanlage der Region folgt dem jetzigen Klima (Abweichung %.6f)" % worst)


func test_damaged_result_file_is_rejected() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("kaputt.ergebnis")
	var a := PackedFloat32Array()
	a.resize(9)
	a.fill(1.0)
	RegionStore.save_result(path, "stand", {"height": a, "forest": a})
	check(not RegionStore.load_result(path, "stand", 3).is_empty(), "unbeschädigter Zwischenstand wird gelesen")
	# Gleicher Kopf, anderer Inhalt (wie ein beschädigter Block).
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var bytes := file.get_buffer(68 + 72)
	file.close()
	bytes[100] = bytes[100] ^ 0xFF
	var out := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	out.store_buffer(bytes)
	out.close()
	check(RegionStore.load_result(path, "stand", 3).is_empty(), "beschädigter Inhalt wird abgewiesen (neu gerechnet)")


func test_nested_regions_after_variant_are_not_counted_twice() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := DIR.path_join("welt_j.json")
	var c := _continent()
	var outer := _make_region(c, world, 0.0, 20000.0, 100000.0)
	outer["basis"] = TerrainSampler.new(c, _planet()).base_fingerprint(0.0, 20000.0, 100000.0, 257)
	var outer_data := _load(world, outer)
	outer_data["basis"] = outer["basis"]
	var s0 := TerrainSampler.new(c, _planet())
	s0.set_regions([outer_data])
	var inner_window := s0.window(5000.0, 15000.0, 12500.0, 257)
	var inner := {"id": RegionStore.new_id(), "cx": 5000.0, "cy": 15000.0, "size": 12500.0, "res": 257}
	inner["checksum"] = RegionStore.save(world, inner, inner_window)
	inner["basis"] = s0.base_fingerprint(5000.0, 15000.0, 12500.0, 257)
	var inner_data := _load(world, inner)
	inner_data["basis"] = inner["basis"]
	c["seed"] = 8888
	TerrainSampler.clear_base_cache()
	var s := TerrainSampler.new(c, _planet())
	s.set_regions([outer_data, inner_data])
	var finer := s.window(5000.0, 15000.0, 1562.5, 257)
	# Im Raster der inneren Region muss der feinere Ausschnitt deren gespeicherte Daten zeigen.
	var worst := 0.0
	var stored: PackedFloat32Array = inner_data["layers"]["relief_low"]
	for gj in range(-6, 7):
		for gi in range(-6, 7):
			var x := 5000.0 + gi * 12500.0 / 256.0
			var y := 15000.0 + gj * 12500.0 / 256.0
			var want := RegionStore.bilinear(stored, 257, x, y, 5000.0, 15000.0, 12500.0)
			worst = maxf(worst, absf(finer.relief_low[finer.res * int(round(finer.grid_of(x, y).y)) + int(round(finer.grid_of(x, y).x))] - want))
	check(worst < 25.0, "feinerer Ausschnitt in verschachtelten Regionen folgt der inneren (größte Abweichung im groben Relief %.1f m)" % worst)
