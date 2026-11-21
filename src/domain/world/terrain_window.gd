class_name TerrainWindow
extends RefCounted
## Ein quadratischer Ausschnitt eines Kontinents, abgetastet mit res × res Punkten.
##
## Punkt (i, j): i wächst nach Osten, j nach Süden. Mitte und Größe in Kontinentmetern (64 Bit).
## Grundlagen kommen aus der Erzeugung, Bearbeitungen aus den Strichen; compose_* rechnet beides
## zu Höhe, Wald und Wasserspiegel zusammen. Reine Daten, keine Knoten.

## Mittlere Geländehöhe im Landesinneren (m), um die das erzeugte Relief schwankt.
const BASE_ELEVATION := 140.0
## Kein Binnengewässer an diesem Punkt.
const NO_WATER := -100000.0
const NO_BED := 1000000.0

var cx: float
var cy: float
var size: float
var res: int
var cell: float
var climate: Dictionary
## Halbe Seitenlänge des Kontinentfensters (m): Land läuft zum Rand hin weich aus, damit
## Globus und alle Ausschnitte dieselbe Welt zeigen (kein Land jenseits des Fensters).
var extent_half := INF

# Aus der Erzeugung
var base_land := PackedFloat32Array()
var relief_low := PackedFloat32Array()
var relief_detail := PackedFloat32Array()
var base_forest := PackedFloat32Array()
# Aus den Strichen
var land_edit := PackedFloat32Array()
var height_edit := PackedFloat32Array()
var smooth_edit := PackedFloat32Array()
var forest_edit := PackedFloat32Array()
## Geschützter Anteil (0–1) und Ausgangswert, dessen Grundform dort gilt.
var protect := PackedFloat32Array()
var protect_seed := PackedInt64Array()
## Ebene: Gewicht und Zielhöhe.
var flat_weight := PackedFloat32Array()
var flat_level := PackedFloat32Array()
## Gewässer: tiefste zulässige Geländehöhe (Bett) und Wasserspiegel.
var water_bed := PackedFloat32Array()
var water_level := PackedFloat32Array()
## Wo überhaupt bearbeitet wurde (zum Wiederfinden in gröberen Ansichten).
var edit_marks := PackedFloat32Array()
# Ergebnis
var height := PackedFloat32Array()
var forest := PackedFloat32Array()


func _init(p_cx: float, p_cy: float, p_size: float, p_res: int) -> void:
	cx = p_cx
	cy = p_cy
	size = p_size
	res = p_res
	cell = size / float(res - 1)
	var n := res * res
	# Einzeln: Gepackte Felder in einer Liste wären Kopien.
	base_land.resize(n)
	relief_low.resize(n)
	relief_detail.resize(n)
	base_forest.resize(n)
	land_edit.resize(n)
	height_edit.resize(n)
	smooth_edit.resize(n)
	forest_edit.resize(n)
	protect.resize(n)
	protect_seed.resize(n)
	flat_weight.resize(n)
	flat_level.resize(n)
	water_bed.resize(n)
	water_level.resize(n)
	edit_marks.resize(n)
	height.resize(n)
	forest.resize(n)
	land_edit.fill(0.0)
	height_edit.fill(0.0)
	smooth_edit.fill(0.0)
	forest_edit.fill(0.0)
	protect.fill(0.0)
	protect_seed.fill(0)
	flat_weight.fill(0.0)
	flat_level.fill(0.0)
	water_bed.fill(NO_BED)
	water_level.fill(NO_WATER)
	edit_marks.fill(0.0)


func x_at(i: int) -> float:
	return cx + (float(i) / float(res - 1) - 0.5) * size


func y_at(j: int) -> float:
	return cy - (float(j) / float(res - 1) - 0.5) * size


## Gebrochener Rasterindex (i, j) zu Kontinentkoordinaten.
func grid_of(x: float, y: float) -> Vector2:
	return Vector2((x - cx) / size + 0.5, (cy - y) / size + 0.5) * float(res - 1)


func contains(x: float, y: float) -> bool:
	return absf(x - cx) <= size * 0.5 and absf(y - cy) <= size * 0.5


func compose_all() -> void:
	compose_rect(0, 0, res - 1, res - 1)


## Rechnet Höhe und Wald im Rechteck [i0..i1] × [j0..j1] aus Grundlagen und Bearbeitungen.
func compose_rect(i0: int, j0: int, i1: int, j1: int) -> void:
	var treeline: float = climate.get("treeline", 3000.0)
	var fade_from := extent_half * 0.9
	for j in range(maxi(j0, 0), mini(j1, res - 1) + 1):
		var ay := absf(y_at(j))
		for i in range(maxi(i0, 0), mini(i1, res - 1) + 1):
			var k := j * res + i
			var land := clampf(base_land[k] + land_edit[k], 0.0, 1.0)
			var edge := maxf(absf(x_at(i)), ay)
			if edge > fade_from:
				land *= 1.0 - smoothstep(fade_from, extent_half, edge)
			var smooth := clampf(smooth_edit[k], 0.0, 1.0)
			var relief := BASE_ELEVATION + relief_low[k] + relief_detail[k] * (1.0 - smooth)
			# Weich nach unten begrenzt (mind. 20 m): Senken werden flach, aber nicht zu Strand oder Meer.
			relief = 20.0 + 30.0 * log(1.0 + exp((relief - 20.0) / 30.0))
			var coast := smoothstep(0.47, 0.53, land)
			var inland := smoothstep(0.5, 0.66, land)
			var h_land := 1.5 + relief * inland
			var h_sea := -30.0 - 1500.0 * (1.0 - smoothstep(0.0, 0.47, land))
			var h := lerpf(h_sea, h_land, coast) + height_edit[k]
			var fw := flat_weight[k]
			if fw > 0.0:
				h = lerpf(h, flat_level[k], clampf(fw, 0.0, 1.0))
			if water_bed[k] < h:
				h = water_bed[k]
			height[k] = h
			var f := clampf(base_forest[k] + forest_edit[k], 0.0, 1.0)
			f *= smoothstep(1.0, 4.0, h) * (1.0 - smoothstep(treeline - 250.0, treeline, h))
			if water_level[k] > h:
				f = 0.0
			forest[k] = f


## Landfläche und Ausdehnung (abgeleitet, nie gespeichert):
## {"area_km2", "min": Vector2 (West, Süd), "max": Vector2 (Ost, Nord)} in Metern; ohne Land area 0.
func land_stats() -> Dictionary:
	var count := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in res:
		var y := y_at(j)
		for i in res:
			if height[j * res + i] > 0.0:
				count += 1
				var x := x_at(i)
				lo = Vector2(minf(lo.x, x), minf(lo.y, y))
				hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
	return {"area_km2": count * cell * cell / 1000000.0, "min": lo, "max": hi}


func _bilinear(buffer: PackedFloat32Array, x: float, y: float) -> float:
	var g := grid_of(x, y)
	var gx := clampf(g.x, 0.0, res - 1.0)
	var gy := clampf(g.y, 0.0, res - 1.0)
	var i0 := mini(int(gx), res - 2)
	var j0 := mini(int(gy), res - 2)
	var fx := gx - i0
	var fy := gy - j0
	var k := j0 * res + i0
	var top := lerpf(buffer[k], buffer[k + 1], fx)
	var bottom := lerpf(buffer[k + res], buffer[k + res + 1], fx)
	return lerpf(top, bottom, fy)


func height_at(x: float, y: float) -> float:
	return _bilinear(height, x, y)


func forest_at(x: float, y: float) -> float:
	return _bilinear(forest, x, y)


func mark_at(x: float, y: float) -> float:
	return _bilinear(edit_marks, x, y)


func protect_at(x: float, y: float) -> float:
	return _bilinear(protect, x, y)


## Wasserspiegel eines Binnengewässers am nächsten Rasterpunkt (NO_WATER, wenn keins).
func water_level_at(x: float, y: float) -> float:
	var g := grid_of(x, y)
	var i := clampi(int(round(g.x)), 0, res - 1)
	var j := clampi(int(round(g.y)), 0, res - 1)
	return water_level[j * res + i]
