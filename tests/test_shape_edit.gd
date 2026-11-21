extends TestSuite
## Gezeichnete Landformen nachträglich wählen und verändern (ShapeEdit) und die Befehle dazu.


## Quadrat mit Kantenlänge 2·half um center, gegen den Uhrzeigersinn.
func _square(center: Vector2, half: float, add: bool = true) -> Dictionary:
	var outline := PackedVector2Array([center + Vector2(-half, -half), center + Vector2(half, -half),
		center + Vector2(half, half), center + Vector2(-half, half)])
	return Stroke.create_shape(add, outline, 500.0)


## Kreis aus count Punkten.
func _circle(center: Vector2, radius: float, count: int) -> Dictionary:
	var outline := PackedVector2Array()
	for k in count:
		var a := TAU * k / count
		outline.append(center + Vector2(cos(a), sin(a)) * radius)
	return Stroke.create_shape(true, outline, 800.0)


func _doc_with_shapes() -> WorldDocument:
	var doc := WorldDocument.new()
	doc.continents.append(WorldDocument.new_continent(7, WorldDocument.BASE_DRAWN, 400.0))
	var strokes: Array = doc.continents[0]["strokes"]
	strokes.append(_square(Vector2.ZERO, 50000.0))
	var brush := Stroke.create("raise", 3000.0, 40.0)
	Stroke.add_point(brush, 0.0, 0.0)
	strokes.append(brush)
	strokes.append(_square(Vector2(40000.0, 0.0), 20000.0, false))
	return doc


func test_outline_roundtrip() -> void:
	var s := _square(Vector2(10.0, 20.0), 5.0)
	var poly := ShapeEdit.outline(s)
	check_equal(poly.size(), 4, "vier Punkte")
	check_equal(poly[0], Vector2(5.0, 15.0), "erster Punkt")
	check(ShapeEdit.is_shape(s), "Form erkannt")
	check(not ShapeEdit.is_shape(Stroke.create("raise", 10.0, 1.0)), "Pinsel ist keine Form")


func test_shape_at_finds_topmost() -> void:
	var doc := _doc_with_shapes()
	var c: Dictionary = doc.continents[0]
	check_equal(ShapeEdit.shape_at(c, -30000.0, 0.0), 0, "im großen Umriss")
	check_equal(ShapeEdit.shape_at(c, 40000.0, 0.0), 2, "in der Bucht: die spätere Form liegt oben")
	check_equal(ShapeEdit.shape_at(c, 200000.0, 0.0), -1, "draußen: keine Form")
	check_equal(ShapeEdit.shape_at(c, -51000.0, 0.0), -1, "knapp draußen ohne Toleranz")
	check_equal(ShapeEdit.shape_at(c, -51000.0, 0.0, 2000.0), 0, "knapp draußen mit Toleranz")
	check_equal(ShapeEdit.shape_at(c, 0.0, 0.0), 0, "Pinsel an derselben Stelle zählt nicht")


func test_transforms_return_copies() -> void:
	var s := _square(Vector2.ZERO, 100.0)
	var before: Dictionary = s.duplicate(true)
	var moved := ShapeEdit.translated(s, Vector2(10.0, -5.0))
	check_equal(ShapeEdit.outline(moved)[0], Vector2(-90.0, -105.0), "verschoben")
	var big := ShapeEdit.scaled(s, 2.0, Vector2.ZERO)
	check_equal(ShapeEdit.outline(big)[2], Vector2(200.0, 200.0), "skaliert")
	check_near(big["radius"], 1000.0, 1e-6, "Randbreite wächst mit")
	var turned := ShapeEdit.rotated(s, PI * 0.5, Vector2.ZERO)
	var p := ShapeEdit.outline(turned)[1]  # (100, -100) → (100, 100)
	check_near(p.x, 100.0, 1e-3, "gedreht x")
	check_near(p.y, 100.0, 1e-3, "gedreht y")
	ShapeEdit.with_vertex(s, 0, Vector2(1.0, 1.0))
	ShapeEdit.with_inserted_vertex(s, 0, Vector2(0.0, -100.0))
	ShapeEdit.without_vertex(s, 0)
	ShapeEdit.with_vertex_moved(s, 0, Vector2(5.0, 5.0), 300.0)
	check_equal(s, before, "Eingabe bleibt unverändert")
	check_equal(moved["tool"], "shape_add", "Werkzeug bleibt")


func test_centroid() -> void:
	var c := ShapeEdit.centroid(_square(Vector2(300000.0, -200000.0), 1000.0))
	check_near(c.x, 300000.0, 1e-3, "Schwerpunkt x")
	check_near(c.y, -200000.0, 1e-3, "Schwerpunkt y")
	# Skalieren und Drehen um den Schwerpunkt lassen ihn an seinem Platz.
	var s := _circle(Vector2(5000.0, 7000.0), 2000.0, 24)
	var c2 := ShapeEdit.centroid(ShapeEdit.rotated(ShapeEdit.scaled(s, 1.3, ShapeEdit.centroid(s)), 0.4, ShapeEdit.centroid(s)))
	check(c2.distance_to(Vector2(5000.0, 7000.0)) < 0.01, "Schwerpunkt bleibt")


func test_vertex_editing() -> void:
	var s := _square(Vector2.ZERO, 100.0)
	var v := ShapeEdit.with_vertex(s, 2, Vector2(150.0, 150.0))
	check_equal(ShapeEdit.outline(v)[2], Vector2(150.0, 150.0), "Punkt gesetzt")
	var ins := ShapeEdit.with_inserted_vertex(s, 0, Vector2(0.0, -100.0))
	check_equal(ShapeEdit.outline(ins).size(), 5, "Punkt eingefügt")
	check_equal(ShapeEdit.outline(ins)[1], Vector2(0.0, -100.0), "nach Punkt 0")
	var ins_last := ShapeEdit.with_inserted_vertex(s, 3, Vector2(-100.0, 0.0))
	check_equal(ShapeEdit.outline(ins_last)[4], Vector2(-100.0, 0.0), "auf der schließenden Kante: am Ende")
	var less := ShapeEdit.without_vertex(ins, 1)
	check(ShapeEdit.same_outline(less, s), "Punkt entfernt")
	var tri := ShapeEdit.without_vertex(s, 0)
	check_equal(ShapeEdit.outline(tri).size(), 3, "auf drei Punkte")
	check_equal(ShapeEdit.outline(ShapeEdit.without_vertex(tri, 0)).size(), 3, "nie unter drei Punkte")


func test_soft_vertex_move() -> void:
	var s := _circle(Vector2.ZERO, 10000.0, 64)  # Punktabstand ≈ 982 m
	var delta := Vector2(3000.0, 0.0)
	var only := ShapeEdit.with_vertex_moved(s, 0, delta, 0.0)
	var a := ShapeEdit.outline(s)
	var b := ShapeEdit.outline(only)
	check_equal(b[0], a[0] + delta, "ohne Abfall: der Punkt")
	check_equal(b[1], a[1], "ohne Abfall: Nachbar bleibt")
	var soft := ShapeEdit.outline(ShapeEdit.with_vertex_moved(s, 0, delta, 4000.0))
	check_equal(soft[0], a[0] + delta, "gezogener Punkt voll")
	var n1 := (soft[1] - a[1]).length()
	var n2 := (soft[2] - a[2]).length()
	check(n1 > 1500.0 and n1 < 3000.0, "Nachbar geht teilweise mit (%f)" % n1)
	check(n2 < n1 and n2 > 0.0, "weiter weg weniger")
	check_near((soft[63] - a[63]).length(), n1, 1.0, "nach beiden Seiten gleich")
	check_equal(soft[10], a[10], "weit weg unverändert")
	check_equal(soft[32], a[32], "gegenüber unverändert")


func test_nearest_vertex_and_edge() -> void:
	var s := _square(Vector2.ZERO, 100.0)
	check_equal(ShapeEdit.nearest_vertex(s, Vector2(95.0, 104.0), 10.0), 2, "Ecke oben rechts")
	check_equal(ShapeEdit.nearest_vertex(s, Vector2(0.0, 0.0), 10.0), -1, "Mitte: kein Punkt nah")
	var e := ShapeEdit.nearest_edge(s, Vector2(103.0, 20.0), 10.0)
	check_equal(e.size(), 2, "Kante gefunden")
	if e.size() == 2:
		check_equal(e[0], 1, "rechte Kante (Punkt 1 → 2)")
		check((e[1] as Vector2).distance_to(Vector2(100.0, 20.0)) < 1e-3, "Fußpunkt")
	check(ShapeEdit.nearest_edge(s, Vector2(0.0, 0.0), 10.0).is_empty(), "Mitte: keine Kante nah")
	var closing := ShapeEdit.nearest_edge(s, Vector2(-101.0, 0.0), 5.0)
	check(closing.size() == 2 and closing[0] == 3, "schließende Kante (Punkt 3 → 0)")


func test_replace_undo_redo() -> void:
	var doc := _doc_with_shapes()
	var id: String = doc.continents[0]["id"]
	var original: Dictionary = (doc.continents[0]["strokes"][0] as Dictionary).duplicate(true)
	var moved := ShapeEdit.translated(original, Vector2(5000.0, 0.0))
	doc.execute(doc.replace_stroke_command(id, 0, moved))
	check(ShapeEdit.same_outline(doc.continents[0]["strokes"][0], moved), "verschoben")
	doc.undo()
	check_equal(doc.continents[0]["strokes"][0], original, "Rückgängig stellt exakt her")
	doc.redo()
	check(ShapeEdit.same_outline(doc.continents[0]["strokes"][0], moved), "Wiederholen")
	check_equal((doc.continents[0]["strokes"] as Array).size(), 3, "Zahl der Bearbeitungen bleibt")


func test_remove_undo_reinserts_at_index() -> void:
	var doc := _doc_with_shapes()
	var id: String = doc.continents[0]["id"]
	var strokes: Array = doc.continents[0]["strokes"]
	var before: Array = strokes.duplicate(true)
	var command := doc.remove_stroke_command(id, 0)
	check_equal(WorldDocument.command_continent(command), id, "Befehl kennt den Kontinent")
	doc.execute(command)
	check_equal(strokes.size(), 2, "entfernt")
	check_equal(strokes[0]["tool"], "raise", "der Rest rückt auf")
	doc.undo()
	check_equal(strokes, before, "Rückgängig: an derselben Stelle zurück")
	doc.redo()
	check_equal(strokes.size(), 2, "Wiederholen entfernt wieder")
	check_equal(strokes[1]["tool"], "shape_remove", "richtige Form entfernt")
	doc.undo()
	# Befehl verändert die Kopie im Verlauf nicht: zweimal hin und her bleibt gleich.
	doc.redo()
	doc.undo()
	check_equal(strokes, before, "mehrfach hin und zurück")


func test_removed_shape_changes_terrain_and_back() -> void:
	var doc := _doc_with_shapes()
	var id: String = doc.continents[0]["id"]
	var bay_point := Vector2(40000.0, 0.0)
	var land := TerrainSampler.new(doc.continents[0], doc.planet).window(0.0, 0.0, 200000.0, 65)
	check(land.height_at(bay_point.x, bay_point.y) < 0.0, "Bucht ist Meer")
	doc.execute(doc.remove_stroke_command(id, 2))
	var without := TerrainSampler.new(doc.continents[0], doc.planet).window(0.0, 0.0, 200000.0, 65)
	check(without.height_at(bay_point.x, bay_point.y) > 0.0, "ohne Bucht: Land")
	doc.undo()
	var back := TerrainSampler.new(doc.continents[0], doc.planet).window(0.0, 0.0, 200000.0, 65)
	check_equal(back.height, land.height, "Rückgängig: bitgleiche Höhen")


func test_save_load_after_edit() -> void:
	var doc := _doc_with_shapes()
	var id: String = doc.continents[0]["id"]
	var s: Dictionary = doc.continents[0]["strokes"][0]
	var edited := ShapeEdit.with_inserted_vertex(ShapeEdit.rotated(s, 0.3, ShapeEdit.centroid(s)), 1, Vector2(70000.0, 10000.0))
	doc.execute(doc.replace_stroke_command(id, 0, edited))
	doc.execute(doc.remove_stroke_command(id, 2))
	var path := "user://tests/welt_formen.json"
	check_equal(doc.save(path), OK, "speichern")
	var loaded := WorldDocument.load_file(path)
	check(loaded != null, "geladen")
	if loaded == null:
		return
	var strokes: Array = loaded.continents[0]["strokes"]
	check_equal(strokes.size(), 2, "zwei Bearbeitungen")
	check(ShapeEdit.same_outline(strokes[0], edited, 1e-6), "veränderte Form exakt gespeichert")
	check_equal(ShapeEdit.shape_at(loaded.continents[0], 40000.0, 0.0), 0, "Form nach dem Laden wählbar")
