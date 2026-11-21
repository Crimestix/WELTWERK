extends TestSuite
## Markante Stellen (Landmarks): Gipfel, Pass und Talgrund an bekannten Stellen künstlicher
## Höhenfelder, Formgröße und Einordnung je Rasterweite, Küstenabstand.


## Ausschnitt mit Höhen aus einer Funktion f(x, y) in Metern.
func _window(size: float, res: int, f: Callable) -> TerrainWindow:
	var w := TerrainWindow.new(0.0, 0.0, size, res)
	var h := w.height
	for j in res:
		for i in res:
			h[j * res + i] = f.call(w.x_at(i), w.y_at(j))
	w.height = h
	return w


static func _bump(x: float, y: float, cx: float, cy: float, height: float, radius: float) -> float:
	return height * exp(-((x - cx) * (x - cx) + (y - cy) * (y - cy)) / (radius * radius))


## Zwei Gipfel (West höher) auf einem Kamm, dessen tiefste Stelle bei x = 5 km liegt.
static func _ridge(x: float, y: float) -> float:
	var crest := (1500.0 - 300.0 * exp(-pow((x - 5000.0) / 4000.0, 2.0))) * exp(-pow(y / 5000.0, 2.0))
	if absf(x) > 30000.0:
		crest *= exp(-pow((absf(x) - 30000.0) / 5000.0, 2.0))
	return 100.0 + maxf(crest, maxf(_bump(x, y, -20000.0, 0.0, 2500.0, 6000.0), _bump(x, y, 20000.0, 0.0, 2200.0, 6000.0)))


## Hochfläche mit einem Tal entlang x = 10 km (in der Mitte am tiefsten), Meer im Westen.
static func _valley(x: float, y: float) -> float:
	if x < -40000.0:
		return -200.0
	return 1500.0 - 1000.0 * exp(-pow((x - 10000.0) / 3000.0, 2.0)) * (0.7 + 0.3 * exp(-pow(y / 20000.0, 2.0)))


func test_peak_and_massif() -> void:
	var w := _window(100000.0, 129, _ridge)
	var center := Landmarks.massif_center(w, 8000.0)
	check(center.distance_to(Vector2(-20000.0, 0.0)) < 6000.0, "Massiv beim höheren Gipfel (%s)" % str(center))
	var peak := Landmarks.highest_in(w, center, 10000.0)
	check(peak.distance_to(Vector2(-20000.0, 0.0)) <= w.cell, "Gipfel gefunden (%s)" % str(peak))


func test_pass_is_lowest_point_of_the_crest_between_two_peaks() -> void:
	var w := _window(100000.0, 257, _ridge)
	var found := Landmarks.find_pass(w, Vector2(-20000.0, 0.0), 15000.0)
	check(not found.is_empty(), "Pass gefunden")
	if found.is_empty():
		return
	var col: Vector2 = found["col"]
	check(col.distance_to(Vector2(5000.0, 0.0)) < 2.0 * w.cell, "Joch an der tiefsten Kammstelle (%s)" % str(col))
	check((found["partner"] as Vector2).distance_to(Vector2(20000.0, 0.0)) < 2.0 * w.cell, "Partnergipfel im Osten")
	check_near(found["col_height"], 1300.0, 30.0, "Höhe des Jochs")
	var axis := Landmarks.axes(w, col, 1500.0)
	check(absf((axis["rise"] as Vector2).x) > 0.9, "Kamm verläuft Ost–West (%s)" % str(axis["rise"]))
	check(axis["rise_m"] > 0.0 and axis["fall_m"] < 0.0, "Sattel: entlang höher, quer tiefer")
	# Genauer im feineren Ausschnitt: dieselbe Stelle.
	var fine := _window(8000.0, 257, func(x: float, y: float) -> float: return _ridge(x + 5000.0, y))
	var refined := Landmarks.refine_col(fine, Vector2(300.0, 200.0), axis["rise"], 2500.0, 1000.0)
	check(refined.distance_to(Vector2(0.0, 0.0)) < 4.0 * fine.cell, "Joch verfeinert (%s)" % str(refined))


func test_valley_floor_of_a_long_trough() -> void:
	var w := _window(100000.0, 257, _valley)
	var coast := Landmarks.coast_distance(w)
	var found := Landmarks.find_valley(w, w, coast, 6000.0, 5000.0, 15000.0)
	check(not found.is_empty(), "Tal gefunden")
	if found.is_empty():
		return
	var p: Vector2 = found["point"]
	check(absf(p.x - 10000.0) <= w.cell and absf(p.y) < 6000.0, "Talgrund in der Talmitte (%s)" % str(p))
	check(absf((found["across"] as Vector2).x) > 0.9, "Quer zum Tal = Ost–West")


func test_coast_distance() -> void:
	var w := _window(100000.0, 129, _valley)
	var d := Landmarks.coast_distance(w)
	var at := d[Landmarks.index_of(w, Vector2(0.0, 0.0))]
	check_near(at, 40000.0, 2.0 * w.cell, "Abstand zur Küste bei x = 0")
	check_equal(d[Landmarks.index_of(w, Vector2(-45000.0, 0.0))], 0.0, "Meer hat Abstand 0")


func test_feature_scale_and_resolution_per_level() -> void:
	var fine := _window(12000.0, 257, func(x: float, y: float) -> float: return 200.0 + _bump(x, y, 0.0, 0.0, 1200.0, 2000.0))
	var scale := Landmarks.feature_scale(fine, "peak", Vector2.ZERO, {}, 5500.0)
	# Halbrelief-Radius einer Glocke mit 2 km Radius: 2 km × √ln 2 ≈ 1,67 km.
	check(scale["size"] > 1400.0 and scale["size"] < 2000.0, "Formgröße des Gipfels (%.0f m)" % scale["size"])
	# Gröbere Stufe derselben Landschaft: Gipfel bleibt Gipfel.
	var coarse := _window(25000.0, 65, func(x: float, y: float) -> float: return 200.0 + _bump(x, y, 0.0, 0.0, 1200.0, 2000.0))
	var c := Landmarks.classify(coarse, fine, "peak", Vector2.ZERO, scale, {})
	check(c["resolved"] and c["ok"], "Auf 390-m-Raster aufgelöst und Höchstpunkt (%s)" % str(c))
	# Viel gröber: nicht aufgelöst (darf geglättet sein).
	var rough := _window(400000.0, 65, func(x: float, y: float) -> float: return 200.0 + _bump(x, y, 0.0, 0.0, 1200.0, 2000.0))
	check(not Landmarks.classify(rough, fine, "peak", Vector2.ZERO, scale, {})["resolved"], "6-km-Raster löst ihn nicht auf")
	# Ein flacher Buckel an derselben Stelle ist kein Gipfel mehr.
	var flat := _window(25000.0, 65, func(x: float, y: float) -> float: return 200.0 + _bump(x, y, 3000.0, 0.0, 1200.0, 2000.0))
	check(not Landmarks.classify(flat, fine, "peak", Vector2.ZERO, scale, {})["ok"], "Versetzter Gipfel fällt auf")
	# Höhentoleranz wächst mit dem nicht auflösbaren Relief.
	check(Landmarks.height_tolerance(fine, Vector2.ZERO, 3000.0) > Landmarks.height_tolerance(fine, Vector2.ZERO, 12.0) + 200.0,
		"Toleranz grober Stufen größer")


func test_pass_classification() -> void:
	var w := _window(16000.0, 257, func(x: float, y: float) -> float: return _ridge(x + 5000.0, y))
	var axis := Landmarks.axes(w, Vector2.ZERO, 300.0)
	var scale := Landmarks.feature_scale(w, "pass", Vector2.ZERO, axis, 7000.0)
	check(scale["rise"] > 0.0 and scale["fall"] > 0.0, "Sattel hat Anstieg und Abfall (%s)" % str(scale))
	var c := Landmarks.classify(w, w, "pass", Vector2.ZERO, scale, axis)
	check(c["ok"], "Sattel bleibt Sattel im selben Ausschnitt (%s)" % str(c))
	# Gröber (250-m-Raster) bleibt der Sattel erhalten.
	var coarse := _window(64000.0, 257, func(x: float, y: float) -> float: return _ridge(x + 5000.0, y))
	var cc := Landmarks.classify(coarse, w, "pass", Vector2.ZERO, scale, axis)
	check(cc["resolved"] and cc["ok"], "Sattel auf gröberem Raster (%s)" % str(cc))
