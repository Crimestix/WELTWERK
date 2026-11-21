class_name ShapeEdit
extends RefCounted
## Gezeichnete Landformen nachträglich finden und verändern.
##
## Eine Landform ist ein Strich "shape_add" oder "shape_remove" (geschlossener Linienzug in
## Kontinentmetern, x = Osten, y = Norden; radius = Breite des weichen Rands). Alle Funktionen
## sind rein: Sie geben eine neue Kopie zurück und lassen den übergebenen Strich unverändert.
## Der Editor macht aus dem Ergebnis einen Befehl (replace_stroke / remove_stroke) – so gehen
## Rückgängig und Speichern den gewohnten Weg.

## Weniger als drei Punkte ergeben keine Fläche.
const MIN_POINTS := 3


## Ist der Strich eine bearbeitbare Landform?
static func is_shape(stroke: Variant) -> bool:
	return stroke is Dictionary and (stroke as Dictionary).get("tool", "") in Stroke.SHAPE_TOOLS \
		and Stroke.dab_count(stroke) >= MIN_POINTS


## Umriss als Punktliste.
static func outline(stroke: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var points: Array = stroke["points"]
	for k in range(0, points.size() - 1, 2):
		result.append(Vector2(float(points[k]), float(points[k + 1])))
	return result


## Innen? (Gerade-ungerade-Regel wie bei der Auswertung im TerrainSampler.)
static func contains(stroke: Dictionary, p: Vector2) -> bool:
	return polygon_contains(outline(stroke), p)


static func polygon_contains(poly: PackedVector2Array, p: Vector2) -> bool:
	var inside := false
	var n := poly.size()
	for e in n:
		var a := poly[e]
		var b := poly[(e + 1) % n]
		if (a.y <= p.y and b.y > p.y) or (b.y <= p.y and a.y > p.y):
			if p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x):
				inside = not inside
	return inside


## Kürzester Abstand zum Umriss (m).
static func distance_to_outline(stroke: Dictionary, p: Vector2) -> float:
	var poly := outline(stroke)
	var best := INF
	for e in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[e], poly[(e + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## Oberste Landform (zuletzt in der Strichliste) an einem Punkt: innen oder höchstens tolerance
## vom Umriss entfernt. -1, wenn keine.
static func shape_at(continent: Dictionary, x: float, y: float, tolerance: float = 0.0) -> int:
	var strokes: Array = continent.get("strokes", [])
	var p := Vector2(x, y)
	for i in range(strokes.size() - 1, -1, -1):
		var stroke: Variant = strokes[i]
		if not is_shape(stroke):
			continue
		var b := _box(stroke)
		if p.x < b.position.x - tolerance or p.x > b.end.x + tolerance \
				or p.y < b.position.y - tolerance or p.y > b.end.y + tolerance:
			continue
		if contains(stroke, p) or (tolerance > 0.0 and distance_to_outline(stroke, p) <= tolerance):
			return i
	return -1


## Schwerpunkt der Fläche (bei entarteter Fläche: Mittel der Punkte).
static func centroid(stroke: Dictionary) -> Vector2:
	var poly := outline(stroke)
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	# Bezogen auf den ersten Punkt rechnen: genauer bei großen Koordinaten.
	var o := poly[0]
	var area := 0.0
	var c := Vector2.ZERO
	for e in n:
		var a := poly[e] - o
		var b := poly[(e + 1) % n] - o
		var cross := a.x * b.y - b.x * a.y
		area += cross
		c += (a + b) * cross
	if absf(area) < 1e-9:
		var mean := Vector2.ZERO
		for p in poly:
			mean += p
		return mean / n
	return o + c / (3.0 * area)


## Verschoben um delta (m).
static func translated(stroke: Dictionary, delta: Vector2) -> Dictionary:
	var poly := outline(stroke)
	for k in poly.size():
		poly[k] += delta
	return _with_outline(stroke, poly)


## Um center mit factor skaliert; die Randbreite wächst mit.
static func scaled(stroke: Dictionary, factor: float, center: Vector2) -> Dictionary:
	var poly := outline(stroke)
	for k in poly.size():
		poly[k] = center + (poly[k] - center) * factor
	var result := _with_outline(stroke, poly)
	result["radius"] = float(stroke["radius"]) * absf(factor)
	return result


## Um center gedreht (Bogenmaß, gegen den Uhrzeigersinn von Norden aus gesehen: x Osten, y Norden).
static func rotated(stroke: Dictionary, radians: float, center: Vector2) -> Dictionary:
	var poly := outline(stroke)
	for k in poly.size():
		poly[k] = center + (poly[k] - center).rotated(radians)
	return _with_outline(stroke, poly)


## Punkt i an die Stelle p gesetzt.
static func with_vertex(stroke: Dictionary, i: int, p: Vector2) -> Dictionary:
	var poly := outline(stroke)
	if i < 0 or i >= poly.size():
		return stroke.duplicate(true)
	poly[i] = p
	return _with_outline(stroke, poly)


## Punkt i um delta verschoben; Nachbarn entlang des Umrisses bis zur Bogenlänge falloff (m)
## gehen weich mit (Kosinus-Abfall). falloff = 0: nur dieser Punkt. So entsteht beim Ziehen eine
## natürliche Ausbuchtung statt eines spitzen Zackens.
static func with_vertex_moved(stroke: Dictionary, i: int, delta: Vector2, falloff: float = 0.0) -> Dictionary:
	var poly := outline(stroke)
	var n := poly.size()
	if i < 0 or i >= n:
		return stroke.duplicate(true)
	var moved := poly.duplicate()
	moved[i] = poly[i] + delta
	if falloff > 0.0:
		for direction in [1, -1]:
			var along := 0.0
			# Höchstens halb herum, damit sich beide Richtungen nicht überschneiden.
			for step in range(1, (n - 1) / 2 + 1 if direction == 1 else n / 2 + 1):
				var k := posmod(i + step * direction, n)
				var prev := posmod(i + (step - 1) * direction, n)
				along += poly[k].distance_to(poly[prev])
				if along >= falloff:
					break
				var weight := 0.5 + 0.5 * cos(PI * along / falloff)
				moved[k] = poly[k] + delta * weight
	return _with_outline(stroke, moved)


## Neuer Punkt p nach Punkt after_i (also auf der Kante after_i → after_i + 1).
static func with_inserted_vertex(stroke: Dictionary, after_i: int, p: Vector2) -> Dictionary:
	var poly := outline(stroke)
	var at := clampi(after_i + 1, 0, poly.size())
	poly.insert(at, p)
	return _with_outline(stroke, poly)


## Punkt i entfernt – aber nie unter drei Punkte (dann unverändert).
static func without_vertex(stroke: Dictionary, i: int) -> Dictionary:
	var poly := outline(stroke)
	if poly.size() <= MIN_POINTS or i < 0 or i >= poly.size():
		return stroke.duplicate(true)
	poly.remove_at(i)
	return _with_outline(stroke, poly)


## Nächster Punkt zu p innerhalb max_dist (m), sonst -1.
static func nearest_vertex(stroke: Dictionary, p: Vector2, max_dist: float) -> int:
	var poly := outline(stroke)
	var best := -1
	var best_d := max_dist
	for k in poly.size():
		var d := poly[k].distance_to(p)
		if d <= best_d:
			best_d = d
			best = k
	return best


## Nächste Kante zu p innerhalb max_dist (m): [Kante, Fußpunkt auf der Kante] oder [].
## Kante e verbindet Punkt e mit Punkt e + 1 (die letzte schließt zum ersten).
static func nearest_edge(stroke: Dictionary, p: Vector2, max_dist: float) -> Array:
	var poly := outline(stroke)
	var n := poly.size()
	var result := []
	var best_d := max_dist
	for e in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[e], poly[(e + 1) % n])
		var d := q.distance_to(p)
		if d <= best_d:
			best_d = d
			result = [e, q]
	return result


## Gleicher Umriss? (Punktweise, mit Toleranz in Metern.)
static func same_outline(a: Dictionary, b: Dictionary, tolerance: float = 0.001) -> bool:
	var pa := outline(a)
	var pb := outline(b)
	if pa.size() != pb.size():
		return false
	for k in pa.size():
		if pa[k].distance_to(pb[k]) > tolerance:
			return false
	return is_equal_approx(float(a["radius"]), float(b["radius"])) and a["tool"] == b["tool"]


# --- Intern --------------------------------------------------------------------------------

static func _with_outline(stroke: Dictionary, poly: PackedVector2Array) -> Dictionary:
	var result: Dictionary = stroke.duplicate(true)
	var points := []
	points.resize(poly.size() * 2)
	for k in poly.size():
		points[k * 2] = poly[k].x
		points[k * 2 + 1] = poly[k].y
	result["points"] = points
	return result


static func _box(stroke: Dictionary) -> Rect2:
	var poly := outline(stroke)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)
