class_name Stroke
extends RefCounted
## Eine Bearbeitung in Kontinentkoordinaten (Meter; x = Osten, y = Norden).
##
## Gespeichert als Dictionary, damit sie unverändert in die Weltdatei (JSON) passt:
##   {"tool": "forest_add", "radius": 120.0, "strength": 0.8, "points": [x0, y0, x1, y1, …]}
## Pinsel-Werkzeuge: Tupfer im Abstand von höchstens 30 % des Radius.
## Form-Werkzeuge (shape_*): geschlossener Linienzug; radius = Breite des weichen Küstenrands.
## Fluss: Linienzug mit "heights" (Wasserspiegel je Punkt, m, flussabwärts nie steigend),
##   radius = halbe Breite, "depth" = Tiefe. See: Tupfer mit "level" (Wasserspiegel) und "depth".
## Erzeugende Werkzeuge (gen_*) tragen einen eigenen Ausgangswert "seed" – wiederholbar.

## Pinsel, die nur Höhe, Land oder Wald direkt ändern.
const BRUSH_TOOLS := ["land_add", "land_remove", "raise", "lower", "smooth", "flatten",
	"forest_add", "forest_remove", "water", "protect"]
## Örtlich begrenzte, wiederholbare Erzeugung.
const GENERATE_TOOLS := ["gen_mountains", "gen_hills", "gen_forest", "gen_islands"]
const SHAPE_TOOLS := ["shape_add", "shape_remove"]
const WATER_TOOLS := ["river", "lake"]
const TOOLS := BRUSH_TOOLS + GENERATE_TOOLS + SHAPE_TOOLS + WATER_TOOLS
const SPACING := 0.3


static func create(tool: String, radius: float, strength: float) -> Dictionary:
	assert(tool in TOOLS)
	return {"tool": tool, "radius": radius, "strength": strength, "points": []}


static func create_generated(tool: String, radius: float, strength: float, seed_value: int) -> Dictionary:
	var s := create(tool, radius, strength)
	s["seed"] = seed_value
	return s


## Geschlossene Form aus einem Linienzug [x0, y0, x1, y1, …]; edge = Breite des weichen Rands (m).
static func create_shape(add: bool, outline: PackedVector2Array, edge: float) -> Dictionary:
	var s := create("shape_add" if add else "shape_remove", edge, 1.0)
	var points: Array = s["points"]
	for p in outline:
		points.append(p.x)
		points.append(p.y)
	return s


## Fluss aus Linienzug und Wasserspiegel je Punkt; der Spiegel wird flussabwärts nie höher.
static func create_river(path: PackedVector2Array, levels: PackedFloat32Array, half_width: float, depth: float) -> Dictionary:
	var s := create("river", half_width, 1.0)
	var points: Array = s["points"]
	var heights := []
	var last := INF
	for i in path.size():
		points.append(path[i].x)
		points.append(path[i].y)
		last = minf(last, levels[i])
		heights.append(last)
	s["heights"] = heights
	s["depth"] = depth
	return s


static func create_lake(radius: float, level: float, depth: float) -> Dictionary:
	var s := create("lake", radius, 1.0)
	s["level"] = level
	s["depth"] = depth
	return s


static func is_generator(stroke: Dictionary) -> bool:
	return stroke["tool"] in GENERATE_TOOLS


## Fügt einen Punkt hinzu und füllt Lücken mit Zwischentupfern. Gibt die Anzahl neuer Tupfer zurück.
static func add_point(stroke: Dictionary, x: float, y: float) -> int:
	var points: Array = stroke["points"]
	if points.is_empty():
		points.append(x)
		points.append(y)
		return 1
	var lx: float = points[points.size() - 2]
	var ly: float = points[points.size() - 1]
	var dx := x - lx
	var dy := y - ly
	var distance := sqrt(dx * dx + dy * dy)
	var step: float = stroke["radius"] * SPACING
	if distance < step:
		return 0
	var count := int(floor(distance / step))
	for k in range(1, count + 1):
		var t := float(k) * step / distance
		points.append(lx + dx * t)
		points.append(ly + dy * t)
	return count


static func dab_count(stroke: Dictionary) -> int:
	return (stroke["points"] as Array).size() / 2


static func point(stroke: Dictionary, i: int) -> Vector2:
	var points: Array = stroke["points"]
	return Vector2(points[i * 2], points[i * 2 + 1])


## Wirkung eines Tupfers in Abstand d bei Radius r: innen voll, zum Rand weich auslaufend.
static func falloff(d: float, r: float) -> float:
	return 1.0 - smoothstep(0.35, 1.0, d / r)


## Umgebendes Rechteck [min_x, min_y, max_x, max_y] einschließlich Radius.
static func bounds(stroke: Dictionary) -> Array:
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	var result := [INF, INF, -INF, -INF]
	for k in range(0, points.size(), 2):
		result[0] = minf(result[0], points[k] - r)
		result[1] = minf(result[1], points[k + 1] - r)
		result[2] = maxf(result[2], points[k] + r)
		result[3] = maxf(result[3], points[k + 1] + r)
	return result


## Kopie mit Faktor skaliert (Kontinent wächst mit): Lage, Radius, Rand. Höhen/Tiefen bleiben.
static func scaled(stroke: Dictionary, factor: float) -> Dictionary:
	var s: Dictionary = stroke.duplicate(true)
	s["radius"] = float(s["radius"]) * factor
	var points: Array = s["points"]
	for k in points.size():
		points[k] = float(points[k]) * factor
	return s
