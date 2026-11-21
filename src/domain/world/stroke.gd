class_name Stroke
extends RefCounted
## Ein Pinselstrich in Kontinentkoordinaten (Meter; x = Osten, y = Norden).
##
## Gespeichert als Dictionary, damit er unverändert in die Weltdatei (JSON) passt:
##   {"tool": "forest_add", "radius": 120.0, "strength": 0.8, "points": [x0, y0, x1, y1, …]}
## Die Punkte sind Tupfer im Abstand von höchstens 30 % des Radius.

const TOOLS := ["land_add", "land_remove", "raise", "lower", "smooth", "forest_add", "forest_remove", "water"]
const SPACING := 0.3


static func create(tool: String, radius: float, strength: float) -> Dictionary:
	assert(tool in TOOLS)
	return {"tool": tool, "radius": radius, "strength": strength, "points": []}


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
