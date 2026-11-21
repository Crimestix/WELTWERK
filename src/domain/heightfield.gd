class_name Heightfield
extends RefCounted
## Höhenfeld eines Geländes: ein regelmäßiges Raster von Höhen in Metern.
##
## Reine Fachlogik – keine Knoten, keine Szene. Erzeugt wird nach festen Regeln aus einem
## Ausgangswert; gleicher Ausgangswert ergibt dasselbe Gelände. Die Höhen lassen sich später
## von Hand übersteuern (set_height).

## Meereshöhe in Metern; darunter steht Wasser.
const SEA_LEVEL := 0.0

## Anzahl der Rasterpunkte entlang x und z.
var columns: int
var rows: int
## Abstand zweier Rasterpunkte in Metern.
var spacing: float
## Weltposition (x, z) des Rasterpunkts (0, 0). Das Feld liegt mittig um den Ursprung.
var origin: Vector2
## Höhen zeilenweise: Index = row * columns + column.
var heights: PackedFloat32Array
## Ausgangswert, aus dem das Feld erzeugt wurde – Erzeugtes bleibt erkennbar.
var seed_value: int


func _init(p_columns: int, p_rows: int, p_spacing: float) -> void:
	columns = p_columns
	rows = p_rows
	spacing = p_spacing
	origin = Vector2(-(columns - 1) * spacing * 0.5, -(rows - 1) * spacing * 0.5)
	heights = PackedFloat32Array()
	heights.resize(columns * rows)


## Ausdehnung in Metern (x, z).
func size() -> Vector2:
	return Vector2((columns - 1) * spacing, (rows - 1) * spacing)


func get_height(column: int, row: int) -> float:
	column = clampi(column, 0, columns - 1)
	row = clampi(row, 0, rows - 1)
	return heights[row * columns + column]


func set_height(column: int, row: int, height: float) -> void:
	heights[row * columns + column] = height


## Höhe an einer beliebigen Weltposition (bilinear zwischen den Rasterpunkten).
## Außerhalb des Felds gilt die Höhe des nächsten Randpunkts.
func height_at(x: float, z: float) -> float:
	var gx := clampf((x - origin.x) / spacing, 0.0, columns - 1.0)
	var gz := clampf((z - origin.y) / spacing, 0.0, rows - 1.0)
	var c0 := mini(int(gx), columns - 2)
	var r0 := mini(int(gz), rows - 2)
	var fx := gx - c0
	var fz := gz - r0
	var top := lerpf(get_height(c0, r0), get_height(c0 + 1, r0), fx)
	var bottom := lerpf(get_height(c0, r0 + 1), get_height(c0 + 1, r0 + 1), fx)
	return lerpf(top, bottom, fz)


## Flächennormale an einem Rasterpunkt (aus den Nachbarhöhen).
func normal_at(column: int, row: int) -> Vector3:
	var dx := get_height(column + 1, row) - get_height(column - 1, row)
	var dz := get_height(column, row + 1) - get_height(column, row - 1)
	return Vector3(-dx, 2.0 * spacing, -dz).normalized()


## Liegt (x, z) innerhalb des Felds?
func contains(x: float, z: float) -> bool:
	var s := size()
	return x >= origin.x and z >= origin.y and x <= origin.x + s.x and z <= origin.y + s.y


## Punkt, an dem ein Strahl das Gelände trifft – oder null, wenn er es nicht trifft.
## Schrittweise vorantasten, dann zwischen letztem freien und erstem getroffenen Punkt teilen.
func raycast(from: Vector3, direction: Vector3, max_distance: float = 5000.0) -> Variant:
	var dir := direction.normalized()
	var t := 0.0
	var previous_t := 0.0
	var min_step := spacing * 0.5
	while t <= max_distance:
		var p := from + dir * t
		var gap := p.y - height_at(p.x, p.z)
		if gap <= 0.0:
			if t == 0.0:
				return p
			var low := previous_t
			var high := t
			for i in 16:
				var mid := (low + high) * 0.5
				var q := from + dir * mid
				if q.y - height_at(q.x, q.z) > 0.0:
					low = mid
				else:
					high = mid
			return from + dir * high
		previous_t = t
		t += maxf(gap * 0.5, min_step)
	return null


## Erzeugt ein Gelände nach festen Regeln: sanfte Hügel, dazwischen Gebirgszüge, zum Rand hin
## abfallend ins Meer. Gleicher Ausgangswert → gleiches Gelände.
static func generate(p_seed: int, extent: float, p_spacing: float) -> Heightfield:
	var count := int(round(extent / p_spacing)) + 1
	var field := Heightfield.new(count, count, p_spacing)
	field.seed_value = p_seed

	var hills := FixedRandom.noise_of(FixedRandom.derive(p_seed, "Hügel"))
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 6
	hills.frequency = 1.0 / 180.0

	var ridges := FixedRandom.noise_of(FixedRandom.derive(p_seed, "Berge"))
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	ridges.frequency = 1.0 / 260.0

	var mountain_mask := FixedRandom.noise_of(FixedRandom.derive(p_seed, "Gebirge"))
	mountain_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountain_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
	mountain_mask.fractal_octaves = 2
	mountain_mask.frequency = 1.0 / 420.0

	var coast := FixedRandom.noise_of(FixedRandom.derive(p_seed, "Küste"))
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	coast.fractal_octaves = 5
	coast.frequency = 1.0 / 140.0

	var half := extent * 0.5
	for row in field.rows:
		var z := field.origin.y + row * p_spacing
		for column in field.columns:
			var x := field.origin.x + column * p_spacing
			# Grundland: sanfte Hügel, Tiefland flacher (gut zum Bauen).
			var base := hills.get_noise_2d(x, z) * 0.5 + 0.5
			var h := pow(base, 1.6) * 24.0 + 3.0
			# Gebirge nur dort, wo die Maske es zulässt.
			var mask := smoothstep(0.0, 0.4, mountain_mask.get_noise_2d(x, z))
			var ridge := ridges.get_noise_2d(x, z) * 0.5 + 0.5
			h += pow(ridge, 2.2) * 62.0 * mask
			# Insel: zum Rand hin ins Meer abfallen, Küstenlinie unregelmäßig.
			var edge := Vector2(x, z).length() / half + coast.get_noise_2d(x, z) * 0.32
			var land := 1.0 - smoothstep(0.62, 0.92, edge)
			var sea_floor := lerpf(-6.0, -40.0, smoothstep(0.85, 1.25, edge))
			h = lerpf(sea_floor, h, land)
			field.heights[row * field.columns + column] = h
	return field
