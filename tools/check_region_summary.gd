extends SceneTree
## Prüft die Zusammenfassung an den Rasterpunkten: Höhe eines groben Rasterpunkts gegen das Mittel des
## feinsten gespeicherten Regionsgeländes über die Fläche seiner Zelle – mit Regionen und, zum
## Vergleich, ohne (reine Erzeugung im groben Raster). Aufruf:
##   godot --headless --path D:\WELTWERK --script res://tools/check_region_summary.gd -- --welt=<Pfad>


func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0].trim_prefix("--welt=")
	var doc := WorldDocument.load_file(path)
	var c: Dictionary = doc.continents[0]
	var list := []
	for r in c.get("regions", []):
		var data := RegionStore.load_data(path, r).duplicate()
		data["result_path"] = RegionStore.result_file_for(path, r)
		list.append(data)
	var with_regions := TerrainSampler.new(c, doc.planet)
	with_regions.set_regions(list)
	var plain := TerrainSampler.new(c, doc.planet)
	var size: float = c["size_km"] * 1000.0
	# Grobe Stufen: Kontinent (513) und jede 200-km-Region; fein: jede 25-km-Region.
	var coarse_specs := [[0.0, 0.0, size, 513]]
	for d in list:
		if d["size"] > 100000.0:
			coarse_specs.append([d["cx"], d["cy"], d["size"], d["res"]])
	for spec in coarse_specs:
		var a := with_regions.window(spec[0], spec[1], spec[2], spec[3])
		var b := plain.window(spec[0], spec[1], spec[2], spec[3])
		for d in list:
			if d["size"] > 30000.0 or d["size"] < 10000.0:
				continue
			var fine := with_regions.window(d["cx"], d["cy"], d["size"], d["res"])
			var errs_a := []
			var errs_b := []
			var g := a.grid_of(d["cx"], d["cy"])
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var i := int(round(g.x)) + di
					var j := int(round(g.y)) + dj
					var x := a.x_at(i)
					var y := a.y_at(j)
					if absf(x - d["cx"]) + a.cell * 0.5 > d["size"] * 0.46 or absf(y - d["cy"]) + a.cell * 0.5 > d["size"] * 0.46:
						continue
					var mean := 0.0
					var n := 64
					for sj in n:
						for si in n:
							mean += fine.height_at(x + ((si + 0.5) / n - 0.5) * a.cell, y + ((sj + 0.5) / n - 0.5) * a.cell)
					mean /= float(n * n)
					errs_a.append(a.height[j * a.res + i] - mean)
					errs_b.append(b.height[j * b.res + i] - mean)
			print("%s über 25-km-Region (%.0f, %.0f): %d Rasterpunkte | mit Regionen: größte %s, Mittel %s | ohne: größte %s, Mittel %s" % [
				"Kontinent" if spec[2] == size else "Region 200 km", d["cx"], d["cy"], errs_a.size(),
				_m(_maxabs(errs_a)), _m(_mean(errs_a)), _m(_maxabs(errs_b)), _m(_mean(errs_b))])
	quit()


func _maxabs(v: Array) -> float:
	var m := 0.0
	for e in v:
		m = maxf(m, absf(e))
	return m


func _mean(v: Array) -> float:
	var s := 0.0
	for e in v:
		s += e
	return s / maxf(1.0, v.size())


func _m(v: float) -> String:
	return "%+.1f m" % v
