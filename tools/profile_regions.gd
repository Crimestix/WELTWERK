extends SceneTree
## Misst die Rechenzeit mit Detailregionen: Laden, jede Region als Ausschnitt, Kontinent mit
## Zusammenfassung (ohne und mit gespeicherten Zwischenständen), eine Bearbeitung. Aufruf:
##   godot --headless --path D:\WELTWERK --script res://tools/profile_regions.gd -- --welt=<Pfad>
## Schreibt Zwischenstände (*.ergebnis) neben die Regionen der angegebenen Welt.


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else ""
	var path: String = args.get("welt", "user://welt.json")
	var doc := WorldDocument.load_file(path)
	if doc == null or doc.continents.is_empty():
		print("Keine Welt")
		quit(1)
		return
	var c: Dictionary = doc.continents[0]
	var t := Time.get_ticks_usec()
	var list := []
	for r in c.get("regions", []):
		if (r as Dictionary).has("checksum"):
			var data := RegionStore.load_data(path, r).duplicate()
			if not data.is_empty():
				data["result_path"] = RegionStore.result_file_for(path, r)
				list.append(data)
	print("Laden %d Regionen: %.0f ms" % [list.size(), (Time.get_ticks_usec() - t) / 1000.0])
	var plain := []
	for data in list:
		var own: Dictionary = data.duplicate()
		own.erase("result_path")
		plain.append(own)
	var size: float = c["size_km"] * 1000.0
	TerrainSampler.clear_region_results()
	for data in plain:
		var s := TerrainSampler.new(c, doc.planet)
		s.set_regions(plain)
		t = Time.get_ticks_usec()
		s.window(data["cx"], data["cy"], data["size"], data["res"])
		print("Region %.0f km (Zwischenstand im Speicher wächst): %.0f ms" % [data["size"] / 1000.0, (Time.get_ticks_usec() - t) / 1000.0])
	_time("Kontinent ohne Regionen", TerrainSampler.new(c, doc.planet), size)
	TerrainSampler.clear_region_results()
	TerrainSampler.clear_base_cache()
	_time("Kontinent, alle Regionen neu gerechnet (erstes Öffnen ohne Zwischenstand)", _sampler(c, doc, list), size)
	TerrainSampler.clear_region_results()
	TerrainSampler.clear_base_cache()
	_time("Kontinent nach Neustart (Zwischenstände von der Platte)", _sampler(c, doc, list), size)
	_time("Kontinent noch einmal (gleicher Stand)", _sampler(c, doc, list), size)
	if not list.is_empty():
		var first: Dictionary = list.back()
		var stroke := Stroke.create("raise", float(first["size"]) * 0.1, 1.0)
		Stroke.add_point(stroke, float(first["cx"]), float(first["cy"]))
		(c["strokes"] as Array).append(stroke)
		var s := _sampler(c, doc, list)
		t = Time.get_ticks_usec()
		s.window(first["cx"], first["cy"], first["size"], first["res"])
		print("Bearbeitung in der feinsten Region, deren Ausschnitt: %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
		_time("danach Kontinent", s, size)
		(c["strokes"] as Array).pop_back()
	quit()


func _sampler(c: Dictionary, doc: WorldDocument, list: Array) -> TerrainSampler:
	var s := TerrainSampler.new(c, doc.planet)
	s.set_regions(list)
	return s


func _time(label: String, s: TerrainSampler, size: float) -> void:
	var t := Time.get_ticks_usec()
	s.window(0.0, 0.0, size, 513)
	print("%s: %.0f ms" % [label, (Time.get_ticks_usec() - t) / 1000.0])
