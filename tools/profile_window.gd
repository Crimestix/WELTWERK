extends SceneTree
## Misst die Auswertungszeit eines Ausschnitts je Bearbeitung. Aufruf:
##   godot --headless --path D:\WELTWERK --script res://tools/profile_window.gd -- --welt=<Pfad> [--x= --y= --size=]


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else ""
	var doc := WorldDocument.load_file(args.get("welt", "user://welt.json"))
	if doc == null or doc.continents.is_empty():
		print("Keine Welt")
		quit(1)
		return
	var c: Dictionary = doc.continents[0]
	var x := float(args.get("x", "0"))
	var y := float(args.get("y", "0"))
	var size := float(args.get("size", "30000"))
	var sampler := TerrainSampler.new(c, doc.planet)
	var t := Time.get_ticks_usec()
	var w := sampler.window(x, y, size)
	print("Gesamt %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	var w2 := TerrainWindow.new(x, y, size, 257)
	w2.climate = sampler.climate
	w2.extent_half = c["size_km"] * 500.0
	t = Time.get_ticks_usec()
	sampler.evaluate_base(w2)
	sampler.finish_forest(w2)
	print("Grundform %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	for stroke in c["strokes"]:
		t = Time.get_ticks_usec()
		var touched := sampler.touches(w2, stroke)
		if touched:
			sampler.apply_stroke(w2, stroke)
		print("  %-14s %s %6.0f ms" % [stroke["tool"], "ja  " if touched else "nein", (Time.get_ticks_usec() - t) / 1000.0])
	t = Time.get_ticks_usec()
	w2.compose_all()
	print("Zusammensetzen %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	quit()
