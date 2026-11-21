class_name TerrainWindow
extends RefCounted
## Ein quadratischer Ausschnitt eines Kontinents, abgetastet mit res × res Punkten.
##
## Punkt (i, j): i wächst nach Osten, j nach Süden. Mitte und Größe in Kontinentmetern (64 Bit).
## Grundlagen kommen aus der Erzeugung, Bearbeitungen aus den Strichen; compose_* rechnet beides
## zu Höhe und Wald zusammen. Reine Daten, keine Knoten.

## Mittlere Geländehöhe im Landesinneren (m), um die das erzeugte Relief schwankt.
const BASE_ELEVATION := 140.0

var cx: float
var cy: float
var size: float
var res: int
var cell: float
var climate: Dictionary

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
	edit_marks.resize(n)
	height.resize(n)
	forest.resize(n)
	land_edit.fill(0.0)
	height_edit.fill(0.0)
	smooth_edit.fill(0.0)
	forest_edit.fill(0.0)
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
	for j in range(maxi(j0, 0), mini(j1, res - 1) + 1):
		for i in range(maxi(i0, 0), mini(i1, res - 1) + 1):
			var k := j * res + i
			var land := clampf(base_land[k] + land_edit[k], 0.0, 1.0)
			var smooth := clampf(smooth_edit[k], 0.0, 1.0)
			var relief := BASE_ELEVATION + relief_low[k] + relief_detail[k] * (1.0 - smooth)
			# Weich nach unten begrenzt (mind. 20 m): Senken werden flach, aber nicht zu Strand oder Meer.
			relief = 20.0 + 30.0 * log(1.0 + exp((relief - 20.0) / 30.0))
			var coast := smoothstep(0.47, 0.53, land)
			var inland := smoothstep(0.5, 0.66, land)
			var h_land := 1.5 + relief * inland
			var h_sea := -30.0 - 1500.0 * (1.0 - smoothstep(0.0, 0.47, land))
			var h := lerpf(h_sea, h_land, coast) + height_edit[k]
			height[k] = h
			var f := clampf(base_forest[k] + forest_edit[k], 0.0, 1.0)
			forest[k] = f * smoothstep(1.0, 4.0, h) * (1.0 - smoothstep(treeline - 250.0, treeline, h))


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
