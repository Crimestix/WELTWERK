class_name TerrainSampler
extends RefCounted
## Die eine Auswertungsfunktion eines Kontinents: Erzeugung nach festem Ausgangswert plus
## Striche, für jeden Ausschnitt und jede Feinheit.
##
## Rauschanteile werden nur so fein ausgewertet, wie das Raster des Ausschnitts es zeigen kann
## (sanft eingeblendet, damit beim Hineinzoomen nichts springt). Darum zeigt dieselbe Funktion
## grob eine vereinfachte und fein eine detaillierte Landschaft – an denselben Orten.

const LOW_LIMIT := 8000.0  ## Wellenlänge, ab der Relief als „grob“ gilt (bleibt beim Glätten)
const MIN_WAVELENGTH := 4.0

var continent: Dictionary
var planet: Dictionary
var climate: Dictionary

var _shape: FastNoiseLite
var _coast: FastNoiseLite
var _hills: FastNoiseLite
var _ridges: FastNoiseLite
var _mask: FastNoiseLite
var _forest: FastNoiseLite
var _mutex := Mutex.new()


func _init(p_continent: Dictionary, p_planet: Dictionary) -> void:
	continent = p_continent
	planet = p_planet
	climate = Climate.derive(continent["latitude"], planet, continent["climate_override"])
	var seed_value: int = continent["seed"]
	_shape = _noise(seed_value, "Grundform")
	_coast = _noise(seed_value, "Küste")
	_hills = _noise(seed_value, "Hügel")
	_ridges = _noise(seed_value, "Gebirge")
	_mask = _noise(seed_value, "Gebirgslage")
	_forest = _noise(seed_value, "Wald")


static func _noise(seed_value: int, label: String) -> FastNoiseLite:
	var n := FixedRandom.noise_of(FixedRandom.derive(seed_value, label))
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = 1.0
	return n


## Kompletter Ausschnitt: Erzeugung, alle Striche, Ergebnis.
func window(cx: float, cy: float, size: float, res: int = 257) -> TerrainWindow:
	var w := TerrainWindow.new(cx, cy, size, res)
	w.climate = climate
	evaluate_base(w)
	for stroke in continent["strokes"]:
		apply_stroke(w, stroke)
	w.compose_all()
	return w


# --- Erzeugung -----------------------------------------------------------------------------

var _rows: Array = []


func evaluate_base(w: TerrainWindow) -> void:
	_rows.clear()
	_rows.resize(w.res)
	var task := WorkerThreadPool.add_group_task(_base_row.bind(w), w.res, -1, true, "Weltwerk Gelände")
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Zusammensetzen im Hauptfaden, in lokale Felder, dann einmal zuweisen (keine Kopie je Wert).
	var land := w.base_land
	var low := w.relief_low
	var detail := w.relief_detail
	var forest := w.base_forest
	var res := w.res
	for j in res:
		var row: Array = _rows[j]
		var offset := j * res
		for i in res:
			land[offset + i] = row[0][i]
			low[offset + i] = row[1][i]
			detail[offset + i] = row[2][i]
			forest[offset + i] = row[3][i]
	w.base_land = land
	w.relief_low = low
	w.relief_detail = detail
	w.base_forest = forest
	_rows.clear()


func _base_row(j: int, w: TerrainWindow) -> void:
	var res := w.res
	var land := PackedFloat32Array()
	var low := PackedFloat32Array()
	var detail := PackedFloat32Array()
	var forest := PackedFloat32Array()
	land.resize(res)
	low.resize(res)
	detail.resize(res)
	forest.resize(res)
	var y := w.y_at(j)
	var half: float = continent["size_km"] * 500.0
	var dryness: float = climate["dryness"]
	for i in res:
		var x := w.x_at(i)
		var sample := sample_base(x, y, w.cell, half, dryness)
		land[i] = sample.x
		low[i] = sample.y
		detail[i] = sample.z
		forest[i] = sample.w
	_mutex.lock()
	_rows[j] = [land, low, detail, forest]
	_mutex.unlock()


## Erzeugte Grundlage an einem Punkt: (Landanteil, grobes Relief, feines Relief, Wald).
func sample_base(x: float, y: float, cell: float, half: float, dryness: float) -> Vector4:
	# Grundform: Fleck um die Mitte, Rand durch großes Rauschen verbogen.
	var r := sqrt(x * x + y * y) / half
	var warp := _shape.get_noise_2d(x / 280000.0, y / 280000.0) * 0.22 \
		+ _shape.get_noise_2d(x / 110000.0 + 31.0, y / 110000.0 - 17.0) * 0.10
	var land := 1.0 - smoothstep(0.45, 0.95, r + warp)
	land += _bands(_coast, x, y, cell, 40000.0, 10, 0.10, 0.6, 0.0, false).x

	var hills := _bands(_hills, x, y, cell, 64000.0, 14, 380.0, 0.52, LOW_LIMIT, false)
	var mask := smoothstep(0.0, 0.4, _mask.get_noise_2d(x / 300000.0, y / 300000.0) + 0.05)
	var ridges := _bands(_ridges, x, y, cell, 60000.0, 14, 2000.0, 0.5, LOW_LIMIT, true) * mask

	var f := _forest.get_noise_2d(x / 90000.0, y / 90000.0) * 0.6 \
		+ _forest.get_noise_2d(x / 22000.0 + 5.0, y / 22000.0) * 0.3 \
		+ _forest.get_noise_2d(x / 5000.0 - 3.0, y / 5000.0) * 0.1
	var forest := smoothstep(0.0, 0.3, f + 0.12 - dryness * 0.5)
	return Vector4(land, hills.x + ridges.x, hills.y + ridges.y, forest)


## Summe von Rauschbändern ab Wellenlänge lambda0, halbiert je Band. Ergebnis (grob, fein),
## getrennt an split (0 = alles grob). Zu feine Bänder für das Raster werden ausgeblendet.
func _bands(noise: FastNoiseLite, x: float, y: float, cell: float, lambda0: float, count: int,
		amplitude: float, persistence: float, split: float, ridged: bool) -> Vector2:
	var coarse := 0.0
	var fine := 0.0
	var lambda := lambda0
	var a := amplitude
	for k in count:
		if lambda < MIN_WAVELENGTH:
			break
		var weight := clampf((lambda / cell - 2.0) * 0.5, 0.0, 1.0)
		if weight <= 0.0:
			break
		var n := noise.get_noise_2d(x / lambda + k * 17.31, y / lambda - k * 9.17)
		if ridged:
			n = (1.0 - absf(n))
			n = n * n
		var v := n * a * weight
		if lambda >= split:
			coarse += v
		else:
			fine += v
		lambda *= 0.5
		a *= persistence
	return Vector2(coarse, fine)


# --- Striche -------------------------------------------------------------------------------

## Wendet einen ganzen Strich an.
func apply_stroke(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	var peak := PackedFloat32Array()
	peak.resize(w.res * w.res)
	peak.fill(0.0)
	return apply_dabs(w, stroke, 0, peak)[0]


## Wendet die Tupfer ab first_dab an. peak hält je Rasterpunkt die bisher stärkste Wirkung
## dieses Strichs (ein Strich wirkt nicht doppelt, wo er sich überlappt).
## Gibt [geändertes Rechteck, neues peak] zurück.
func apply_dabs(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var tool: String = stroke["tool"]
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	# Feiner als das Raster: Fläche erhalten statt verschwinden lassen (vereinfachte Darstellung).
	var r_eff := maxf(r, w.cell * 0.75)
	var amount: float = stroke["strength"] * pow(r / r_eff, 2.0)
	if tool in ["land_remove", "water", "lower", "forest_remove"]:
		amount = -amount
	# Markiert wird nur, wo die Bearbeitung in diesem Maßstab kaum noch zu sehen ist.
	var mark := r < w.cell * 4.0
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	var reach := maxf(r_eff, r_mark)

	var layer: PackedFloat32Array
	match tool:
		"land_add", "land_remove", "water": layer = w.land_edit
		"raise", "lower": layer = w.height_edit
		"smooth": layer = w.smooth_edit
		_: layer = w.forest_edit
	var marks := w.edit_marks

	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	var changed := Rect2i()
	for d in range(first_dab, points.size() / 2):
		var px: float = points[d * 2]
		var py: float = points[d * 2 + 1]
		var i0 := maxi(int(floor((px - reach - x_min) / w.cell)), 0)
		var i1 := mini(int(ceil((px + reach - x_min) / w.cell)), res - 1)
		var j0 := maxi(int(floor((y_max - (py + reach)) / w.cell)), 0)
		var j1 := mini(int(ceil((y_max - (py - reach)) / w.cell)), res - 1)
		if i0 > i1 or j0 > j1:
			continue
		var rect := Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)
		changed = rect if changed.size == Vector2i.ZERO else changed.merge(rect)
		for j in range(j0, j1 + 1):
			var dy := w.y_at(j) - py
			for i in range(i0, i1 + 1):
				var dx := w.x_at(i) - px
				var dist := sqrt(dx * dx + dy * dy)
				var k := j * res + i
				if dist < r_eff:
					var f := Stroke.falloff(dist, r_eff)
					if f > peak[k]:
						layer[k] += amount * (f - peak[k])
						peak[k] = f
				if dist < r_mark:
					marks[k] = maxf(marks[k], 1.0 - smoothstep(0.6, 1.0, dist / r_mark))

	match tool:
		"land_add", "land_remove", "water": w.land_edit = layer
		"raise", "lower": w.height_edit = layer
		"smooth": w.smooth_edit = layer
		_: w.forest_edit = layer
	w.edit_marks = marks
	return [changed, peak]
