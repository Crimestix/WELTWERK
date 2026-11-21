extends TestSuite
## Natürliche Geländeformen: Gebirgskamm entlang des Strichs, Wiederholbarkeit, Live-Malen,
## sanfte Seeufer, fraktale Küsten.

const RES := 129


func _drawn_doc() -> WorldDocument:
	var doc := WorldDocument.new()
	doc.continents.append(WorldDocument.new_continent(77, WorldDocument.BASE_DRAWN, 1000.0))
	return doc


func _square(cx: float, cy: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - half, cy - half), Vector2(cx + half, cy - half),
		Vector2(cx + half, cy + half), Vector2(cx - half, cy + half)])


func _window(doc: WorldDocument, id: String, cx: float, cy: float, size: float, res: int = RES) -> TerrainWindow:
	return TerrainSampler.new(doc.continent(id), doc.planet).window(cx, cy, size, res)


func _land_doc() -> Array:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 300000.0), 15000.0)))
	return [doc, id]


func _mountain_stroke(seed_value: int) -> Dictionary:
	var m := Stroke.create_generated("gen_mountains", 50000.0, 2000.0, seed_value)
	for k in 9:
		Stroke.add_point(m, -120000.0 + k * 30000.0, 0.0)
	return m


func test_mountain_crest_follows_the_stroke() -> void:
	var pair := _land_doc()
	var doc: WorldDocument = pair[0]
	var id: String = pair[1]
	doc.execute(WorldDocument.add_stroke_command(id, _mountain_stroke(99)))
	var w := _window(doc, id, 0.0, 0.0, 400000.0)
	var crest := 0.0
	var flank := 0.0
	var crest_low := INF
	var samples := 0
	for k in 21:
		var x := -80000.0 + k * 8000.0
		# Kamm: höchster Punkt im Streifen um den Strich (er pendelt natürlich ein wenig).
		var top := -INF
		for dy in [-9000.0, -6000.0, -3000.0, 0.0, 3000.0, 6000.0, 9000.0]:
			top = maxf(top, w.height_at(x, dy))
		crest += top
		crest_low = minf(crest_low, top)
		flank += (w.height_at(x, 40000.0) + w.height_at(x, -40000.0)) * 0.5
		samples += 1
	crest /= samples
	flank /= samples
	check(crest > flank * 2.5 and crest > flank + 800.0,
		"Kamm deutlich höher als bei 0,8 Radius (Kamm %.0f m, Flanke %.0f m)" % [crest, flank])
	check(crest_low > flank + 400.0, "durchgehender Kamm: auch der niedrigste Sattel liegt hoch (%.0f m)" % crest_low)
	# Gipfel und Sättel: Der Kamm ist nicht überall gleich hoch.
	var heights := []
	for k in 41:
		heights.append(w.height_at(-100000.0 + k * 5000.0, 0.0))
	var lo: float = heights.min()
	var hi: float = heights.max()
	check(hi - lo > 150.0, "Kamm mit Gipfeln und Sätteln (Spanne %.0f m)" % (hi - lo))
	check_near(w.height_at(0.0, 200000.0), _window(pair[0], id, 0.0, 0.0, 400000.0).height_at(0.0, 200000.0), 0.01,
		"Auswertung stabil")


func test_mountains_have_side_valleys() -> void:
	# Quer zum Kamm laufen Täler: Entlang einer Linie parallel zum Kamm (halber Radius) wechseln
	# Grate und Täler – deutlich mehr Auf und Ab als entlang der Kammlinie selbst.
	var pair := _land_doc()
	var doc: WorldDocument = pair[0]
	var id: String = pair[1]
	doc.execute(WorldDocument.add_stroke_command(id, _mountain_stroke(5)))
	var w := _window(doc, id, 0.0, 25000.0, 100000.0)
	var turns := 0
	var last_sign := 0
	var prev := w.height_at(-45000.0, 25000.0)
	for k in range(1, 91):
		var h := w.height_at(-45000.0 + k * 1000.0, 25000.0)
		var s := signi(int(signf(h - prev)))
		if s != 0 and last_sign != 0 and s != last_sign:
			turns += 1
		if s != 0:
			last_sign = s
		prev = h
	check(turns >= 4, "Grate und Täler an der Flanke (%d Richtungswechsel auf 90 km)" % turns)


func test_mountains_are_repeatable() -> void:
	var results := []
	for k in 2:
		var pair := _land_doc()
		var doc: WorldDocument = pair[0]
		var id: String = pair[1]
		doc.execute(WorldDocument.add_stroke_command(id, _mountain_stroke(1234)))
		results.append(_window(doc, id, 30000.0, 10000.0, 300000.0))
	var a: TerrainWindow = results[0]
	var b: TerrainWindow = results[1]
	check_equal(a.height_edit, b.height_edit, "gleicher Ausgangswert → gleiche Gebirgsform")
	check_equal(a.height, b.height, "gleicher Ausgangswert → gleiche Höhen")
	var other := _land_doc()
	other[0].execute(WorldDocument.add_stroke_command(other[1], _mountain_stroke(1235)))
	var c := _window(other[0], other[1], 30000.0, 10000.0, 300000.0)
	check(c.height_edit != a.height_edit, "anderer Ausgangswert → andere Form")


## Malt einen Strich Tupfer für Tupfer in einen fertigen Ausschnitt (wie beim Live-Malen).
func _paint_live(doc: WorldDocument, id: String, stroke: Dictionary, cx: float, cy: float, size: float) -> TerrainWindow:
	var sampler := TerrainSampler.new(doc.continent(id), doc.planet)
	var w := sampler.window(cx, cy, size, RES)
	var peak := PackedFloat32Array()
	peak.resize(RES * RES)
	peak.fill(0.0)
	for d in Stroke.dab_count(stroke):
		var partial := stroke.duplicate(true)
		(partial["points"] as Array).resize((d + 1) * 2)
		peak = sampler.apply_dabs(w, partial, d, peak)[1]
	w.compose_all()
	return w


func test_live_generation_equals_recomputation() -> void:
	for tool in ["gen_mountains", "gen_hills", "gen_forest", "gen_islands", "land_add"]:
		var pair := _land_doc()
		var doc: WorldDocument = pair[0]
		var id: String = pair[1]
		var strength := {"gen_mountains": 1800.0, "gen_hills": 400.0, "gen_forest": 0.9, "gen_islands": 1.3, "land_add": 1.0}
		var s: Dictionary
		if tool == "land_add":
			s = Stroke.create(tool, 25000.0, 1.0)
		else:
			s = Stroke.create_generated(tool, 25000.0, strength[tool], 4711)
		# Kurve mit Knick, teils im Meer (Inseln), Tupfer im Abstand wie beim Malen.
		var x0 := 220000.0 if tool in ["gen_islands", "land_add"] else 60000.0
		for k in 8:
			Stroke.add_point(s, x0 + k * 9000.0, 20000.0 - k * 6000.0 + (k % 3) * 4000.0)
		for k in 5:
			Stroke.add_point(s, x0 + 63000.0 + k * 5000.0, -22000.0 - k * 9000.0)
		var cx := x0 + 30000.0
		var live := _paint_live(doc, id, s, cx, 0.0, 200000.0)
		doc.execute(WorldDocument.add_stroke_command(id, s))
		var full := _window(doc, id, cx, 0.0, 200000.0)
		var worst := 0.0
		for k in full.height.size():
			worst = maxf(worst, absf(full.height[k] - live.height[k]))
		var worst_forest := 0.0
		for k in full.forest.size():
			worst_forest = maxf(worst_forest, absf(full.forest[k] - live.forest[k]))
		check(worst < 0.05 and worst_forest < 0.001,
			"%s: live wie neu berechnet (Höhe %.4f m, Wald %.5f)" % [tool, worst, worst_forest])


func test_lake_has_gentle_banks_at_continent_scale() -> void:
	var pair := _land_doc()
	var doc: WorldDocument = pair[0]
	var id: String = pair[1]
	# Ein Hügel, an dessen Flanke ein See liegt: Das Ufer steigt sanft an, kein Wall.
	var hill := Stroke.create("raise", 60000.0, 700.0)
	Stroke.add_point(hill, 0.0, 0.0)
	doc.execute(WorldDocument.add_stroke_command(id, hill))
	var size := 800000.0
	var before := _window(doc, id, 0.0, 0.0, size, 257)
	var c := Vector2(40000.0, 0.0)
	var level := before.height_at(c.x, c.y) - 150.0
	var lake := Stroke.create_lake(20000.0, level, 40.0)
	Stroke.add_point(lake, c.x, c.y)
	doc.execute(WorldDocument.add_stroke_command(id, lake))
	var w := _window(doc, id, 0.0, 0.0, size, 257)
	check(w.water_level_at(c.x, c.y) > TerrainWindow.NO_WATER, "See vorhanden")
	var steepest := 0.0
	var step := w.cell
	for dir in [Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var prev := w.height_at(c.x + dir.x * 20000.0, c.y + dir.y * 20000.0)
		for k in range(1, 12):
			var q: Vector2 = c + dir * (20000.0 + k * step)
			var h := w.height_at(q.x, q.y)
			steepest = maxf(steepest, h - prev)
			prev = h
	var original := 0.0
	for dir in [Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var q: Vector2 = c + dir * 20000.0
		original = maxf(original, before.height_at(q.x, q.y) - level)
	check(original > 100.0, "Ufergelände liegt ursprünglich über dem Spiegel (%.0f m)" % original)
	check(steepest < original * 0.6, "Böschung steigt über mehrere Zellen an (größter Schritt %.0f m von %.0f m)" % [steepest, original])


func test_drawn_coast_is_natural_but_stays_in_place() -> void:
	var doc := _drawn_doc()
	var id: String = doc.continents[0]["id"]
	doc.execute(WorldDocument.add_stroke_command(id, Stroke.create_shape(true, _square(0.0, 0.0, 200000.0), 15000.0)))
	var w := _window(doc, id, 0.0, 0.0, 600000.0, 257)
	# Küstenlänge in Rasterkanten zwischen Land und Meer; ein glattes Quadrat hätte etwa 4 · 400 km / Zelle.
	var edges := 0
	for j in w.res - 1:
		for i in w.res - 1:
			var k := j * w.res + i
			if (w.height[k] > 0.0) != (w.height[k + 1] > 0.0):
				edges += 1
			if (w.height[k] > 0.0) != (w.height[k + w.res] > 0.0):
				edges += 1
	var smooth := 4.0 * 400000.0 / w.cell
	check(edges > smooth * 1.25, "Küste gebuchtet (%d Kanten statt %.0f)" % [edges, smooth])
	check(w.height_at(0.0, 0.0) > 0.0 and w.height_at(150000.0, 150000.0) > 0.0, "innen Land")
	check(w.height_at(0.0, 260000.0) < 0.0 and w.height_at(-260000.0, -260000.0) < 0.0, "weit außen Meer")
