class_name TerrainSampler
extends RefCounted
## Die eine Auswertungsfunktion eines Kontinents: Grundform nach festem Ausgangswert plus
## Bearbeitungen, für jeden Ausschnitt und jede Feinheit.
##
## Rauschanteile werden nur so fein ausgewertet, wie das Raster des Ausschnitts es zeigen kann
## (sanft eingeblendet, damit beim Hineinzoomen nichts springt). Darum zeigt dieselbe Funktion
## grob eine vereinfachte und fein eine detaillierte Landschaft – an denselben Orten.
##
## Reihenfolge je Ausschnitt: Schutzbereiche → Grundform (geschützt: Grundform des damaligen
## Ausgangswerts) → alle übrigen Bearbeitungen in der Reihenfolge der Strichliste → Ergebnis.

const LOW_LIMIT := 8000.0  ## Wellenlänge, ab der Relief als „grob“ gilt (bleibt beim Glätten)
const MIN_WAVELENGTH := 4.0
## Uferböschung von Flüssen und Seen (Meter Anstieg je Meter Abstand).
const BANK_SLOPE := 0.25

var continent: Dictionary
var planet: Dictionary
var climate: Dictionary
var drawn: bool

var _noises: Dictionary
var _noise_cache := {}
var _mutex := Mutex.new()
var _rows: Array = []


## Grundform wächst beim Skalieren mit: ausgewertet wird bei (x, y) × base_scale.
var base_scale := 1.0
var _peak := PackedFloat32Array()


func _init(p_continent: Dictionary, p_planet: Dictionary) -> void:
	continent = p_continent
	planet = p_planet
	climate = Climate.derive(continent["latitude"], planet, continent["climate_override"])
	drawn = continent.get("base", WorldDocument.BASE_GENERATED) == WorldDocument.BASE_DRAWN
	base_scale = float(continent.get("base_size_km", continent["size_km"])) / float(continent["size_km"])
	_noises = noise_set(continent["seed"])


## Rauschfelder der Grundform zu einem Ausgangswert (zwischengespeichert).
func noise_set(seed_value: int) -> Dictionary:
	if _noise_cache.has(seed_value):
		return _noise_cache[seed_value]
	var set := {
		"shape": _noise(seed_value, "Grundform"),
		"coast": _noise(seed_value, "Küste"),
		"hills": _noise(seed_value, "Hügel"),
		"ridges": _noise(seed_value, "Gebirge"),
		"mask": _noise(seed_value, "Gebirgslage"),
		"forest": _noise(seed_value, "Wald"),
	}
	_noise_cache[seed_value] = set
	return set


static func _noise(seed_value: int, label: String) -> FastNoiseLite:
	var n := FixedRandom.noise_of(FixedRandom.derive(seed_value, label))
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = 1.0
	return n


## Kompletter Ausschnitt: Schutz, Grundform, alle Bearbeitungen, Ergebnis.
func window(cx: float, cy: float, size: float, res: int = 257) -> TerrainWindow:
	var w := TerrainWindow.new(cx, cy, size, res)
	w.climate = climate
	w.extent_half = continent["size_km"] * 500.0
	_peak.resize(res * res)
	_peak.fill(0.0)
	for stroke in continent["strokes"]:
		if stroke["tool"] == "protect" and touches(w, stroke):
			apply_stroke(w, stroke)
	evaluate_base(w)
	for stroke in continent["strokes"]:
		if stroke["tool"] != "protect" and touches(w, stroke):
			apply_stroke(w, stroke)
	w.compose_all()
	return w


## Kann der Strich diesen Ausschnitt überhaupt berühren? (Spart die Arbeit für alle anderen.)
func touches(w: TerrainWindow, stroke: Dictionary) -> bool:
	var b := Stroke.bounds(stroke)
	var r: float = stroke["radius"]
	var margin := maxf(r * 0.7, 300.0) + w.cell * 2.0
	if stroke["tool"] == "river":
		margin += 60.0 / BANK_SLOPE
	var half := w.size * 0.5
	return b[0] - margin <= w.cx + half and b[2] + margin >= w.cx - half \
		and b[1] - margin <= w.cy + half and b[3] + margin >= w.cy - half


## Land-Bearbeitungen wirken in Reihenfolge: Nach jeder wird der Landanteil auf 0–1 begrenzt,
## damit z. B. Abtragen nach zweimal Anfügen wirklich Meer ergibt.
static func clamp_land(w: TerrainWindow, rect: Rect2i) -> void:
	if rect.size == Vector2i.ZERO:
		return
	var edit := w.land_edit
	var base := w.base_land
	for j in range(maxi(rect.position.y, 0), mini(rect.end.y, w.res)):
		for i in range(maxi(rect.position.x, 0), mini(rect.end.x, w.res)):
			var k := j * w.res + i
			edit[k] = clampf(base[k] + edit[k], 0.0, 1.0) - base[k]
	w.land_edit = edit


# --- Grundform -----------------------------------------------------------------------------

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
	_rows.clear()

	# Geschützte Bereiche behalten die Grundform des Ausgangswerts, der beim Schützen galt.
	var current: int = continent["seed"]
	var s := base_scale
	var half: float = continent["size_km"] * 500.0 * s
	var dryness: float = climate["dryness"]
	var protect := w.protect
	var seeds := w.protect_seed
	for k in res * res:
		var p := protect[k]
		if p <= 0.0 or seeds[k] == current:
			continue
		var set := noise_set(seeds[k])
		var i := k % res
		var j := k / res
		var b := sample_base(w.x_at(i) * s, w.y_at(j) * s, w.cell * s, half, dryness, set)
		land[k] = lerpf(land[k], b.x, p)
		low[k] = lerpf(low[k], b.y, p)
		detail[k] = lerpf(detail[k], b.z, p)
		forest[k] = lerpf(forest[k], b.w, p)
	w.base_land = land
	w.relief_low = low
	w.relief_detail = detail
	w.base_forest = forest


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
	var s := base_scale
	var y := w.y_at(j) * s
	var half: float = continent["size_km"] * 500.0 * s
	var dryness: float = climate["dryness"]
	for i in res:
		var sample := sample_base(w.x_at(i) * s, y, w.cell * s, half, dryness, _noises)
		land[i] = sample.x
		low[i] = sample.y
		detail[i] = sample.z
		forest[i] = sample.w
	_mutex.lock()
	_rows[j] = [land, low, detail, forest]
	_mutex.unlock()


## Erzeugte Grundlage an einem Punkt: (Landanteil, grobes Relief, feines Relief, Wald).
## Bei gezeichneter Grundform gibt es keinen Fleck – Land entsteht nur aus Formen und Pinseln;
## Küstendetail, Relief und Wald wirken trotzdem überall (dort, wo Land ist).
func sample_base(x: float, y: float, cell: float, half: float, dryness: float, set: Dictionary) -> Vector4:
	var land := 0.0
	if not drawn:
		var r := sqrt(x * x + y * y) / half
		var shape: FastNoiseLite = set["shape"]
		var warp := shape.get_noise_2d(x / 280000.0, y / 280000.0) * 0.22 \
			+ shape.get_noise_2d(x / 110000.0 + 31.0, y / 110000.0 - 17.0) * 0.10
		land = 1.0 - smoothstep(0.45, 0.95, r + warp)
	land += _bands(set["coast"], x, y, cell, 40000.0, 10, 0.10, 0.6, 0.0, false).x

	var hills := _bands(set["hills"], x, y, cell, 64000.0, 14, 380.0, 0.52, LOW_LIMIT, false)
	var mask_noise: FastNoiseLite = set["mask"]
	var mask := smoothstep(0.0, 0.4, mask_noise.get_noise_2d(x / 300000.0, y / 300000.0) + 0.05)
	var ridges := _bands(set["ridges"], x, y, cell, 60000.0, 14, 2000.0, 0.5, LOW_LIMIT, true) * mask

	var fn: FastNoiseLite = set["forest"]
	var f := fn.get_noise_2d(x / 90000.0, y / 90000.0) * 0.6 \
		+ fn.get_noise_2d(x / 22000.0 + 5.0, y / 22000.0) * 0.3 \
		+ fn.get_noise_2d(x / 5000.0 - 3.0, y / 5000.0) * 0.1
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


# --- Bearbeitungen -------------------------------------------------------------------------

## Wendet eine ganze Bearbeitung an. Gibt das geänderte Rasterrechteck zurück.
func apply_stroke(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	match stroke["tool"]:
		"shape_add", "shape_remove":
			var shape_rect := _apply_shape(w, stroke)
			clamp_land(w, shape_rect)
			return shape_rect
		"river":
			return _apply_river(w, stroke)
		_:
			if _peak.size() != w.res * w.res:
				_peak.resize(w.res * w.res)
				_peak.fill(0.0)
			var result := apply_dabs(w, stroke, 0, _peak)
			var rect: Rect2i = result[0]
			# Nur den berührten Teil zurücksetzen statt das ganze Feld neu anzulegen.
			var peak: PackedFloat32Array = result[1]
			for j in range(rect.position.y, rect.end.y):
				var row := j * w.res
				for i in range(rect.position.x, rect.end.x):
					peak[row + i] = 0.0
			_peak = peak
			return rect


## Rauschwert (0–1) einer erzeugenden Bearbeitung an einem Punkt – fest durch ihren Ausgangswert.
func generator_value(stroke: Dictionary, x: float, y: float, cell_size: float) -> float:
	var n: FastNoiseLite = noise_set(int(stroke.get("seed", 0)))["hills"]
	var r: float = stroke["radius"]
	match stroke["tool"]:
		"gen_mountains":
			var lambda := clampf(r * 0.55, 1500.0, 80000.0)
			var v := _bands(n, x, y, _gen_cell(cell_size, lambda), lambda, 12, 1.0, 0.5, 0.0, true).x
			return clampf(v, 0.0, 1.0)
		"gen_hills":
			var lambda := clampf(r * 0.4, 300.0, 40000.0)
			return clampf(_bands(n, x, y, _gen_cell(cell_size, lambda), lambda, 10, 0.7, 0.5, 0.0, false).x * 0.5 + 0.5, 0.0, 1.0)
		"gen_forest":
			var lambda := clampf(r * 0.25, 150.0, 30000.0)
			return smoothstep(0.42, 0.6, _bands(n, x, y, _gen_cell(cell_size, lambda), lambda, 8, 0.7, 0.55, 0.0, false).x * 0.5 + 0.5)
		"gen_islands":
			var lambda := clampf(r * 0.3, 200.0, 60000.0)
			return smoothstep(0.52, 0.72, _bands(n, x, y, _gen_cell(cell_size, lambda), lambda, 9, 0.7, 0.55, 0.0, false).x * 0.5 + 0.5)
	return 0.0


## Ausblendgrenze für erzeugte Wellen: feinere erst ab etwa acht Rasterzellen (saubere Kämme statt
## Zacken), die Grundwelle aber immer voll – sonst verschwände eine kleine Erzeugung im groben Maßstab.
static func _gen_cell(cell_size: float, lambda0: float) -> float:
	return minf(cell_size * 2.0, lambda0 / 4.0)

## Wendet die Tupfer ab first_dab an. peak hält je Rasterpunkt die bisher stärkste Wirkung
## dieses Strichs (ein Strich wirkt nicht doppelt, wo er sich überlappt).
## Je Rasterpunkt zählt die stärkste Wirkung aller neuen Tupfer – das ist dasselbe Ergebnis wie
## Tupfer für Tupfer, lässt sich aber zeilenweise parallel rechnen.
## Gibt [geändertes Rechteck, neues peak] zurück.
func apply_dabs(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var tool: String = stroke["tool"]
	if tool == "lake":
		return _apply_lake(w, stroke, first_dab, peak)
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	var generator := Stroke.is_generator(stroke)
	# Feiner als das Raster: Fläche erhalten statt verschwinden lassen (vereinfachte Darstellung).
	var r_eff := maxf(r, w.cell * 0.75)
	var amount: float = stroke["strength"] * pow(r / r_eff, 2.0)
	if tool in ["land_remove", "water", "lower", "forest_remove"]:
		amount = -amount
	# Markiert wird nur, wo die Bearbeitung in diesem Maßstab kaum noch zu sehen ist.
	var mark := r < w.cell * 4.0 and tool != "protect"
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	var reach := maxf(r_eff, r_mark)

	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	var changed := Rect2i()
	var dabs := PackedVector2Array()
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
		dabs.append(Vector2(px, py))
	if dabs.is_empty():
		return [changed, peak]

	var rows := _dab_rows(w, stroke, dabs, changed, r_eff, r_mark, reach, peak, generator)

	var layer: PackedFloat32Array
	match tool:
		"land_add", "land_remove", "water", "gen_islands": layer = w.land_edit
		"raise", "lower", "gen_mountains", "gen_hills": layer = w.height_edit
		"smooth": layer = w.smooth_edit
		"flatten": layer = w.flat_weight
		"protect": layer = w.protect
		_: layer = w.forest_edit
	var marks := w.edit_marks
	var protect := w.protect
	var levels := w.flat_level
	var seeds := w.protect_seed
	var level: float = stroke.get("level", 0.0)
	var seed_value: int = int(stroke.get("seed", continent["seed"]))
	for j in range(changed.position.y, changed.end.y):
		var row: Array = rows[j - changed.position.y]
		var fmax: PackedFloat32Array = row[0]
		var mrow: PackedFloat32Array = row[1]
		var grow: PackedFloat32Array = row[2]
		for c in changed.size.x:
			var k := j * res + changed.position.x + c
			if mark and mrow[c] > marks[k]:
				marks[k] = mrow[c]
			var f := fmax[c]
			if f <= peak[k]:
				continue
			var delta := f - peak[k]
			peak[k] = f
			match tool:
				"protect":
					layer[k] = maxf(layer[k], f)
					seeds[k] = seed_value
				"flatten":
					if layer[k] < 0.01:
						levels[k] = level
					else:
						levels[k] = lerpf(levels[k], level, delta)
					layer[k] = clampf(layer[k] + amount * delta, 0.0, 1.0)
				_:
					if generator:
						layer[k] += amount * delta * grow[c] * (1.0 - protect[k])
					else:
						layer[k] += amount * delta

	match tool:
		"land_add", "land_remove", "water", "gen_islands":
			w.land_edit = layer
			clamp_land(w, changed)
		"raise", "lower", "gen_mountains", "gen_hills": w.height_edit = layer
		"smooth": w.smooth_edit = layer
		"flatten":
			w.flat_weight = layer
			w.flat_level = levels
		"protect":
			w.protect = layer
			w.protect_seed = seeds
		_: w.forest_edit = layer
	w.edit_marks = marks
	return [changed, peak]


## Je Zeile des Rechtecks: stärkste Wirkung (falloff), Marke und – bei Erzeugung – Rauschwert
## dort, wo die Wirkung neu ist. Zeilen parallel; Ergebnis [[fmax, mark, gen], …].
func _dab_rows(w: TerrainWindow, stroke: Dictionary, dabs: PackedVector2Array, rect: Rect2i, r_eff: float,
		r_mark: float, reach: float, peak: PackedFloat32Array, generator: bool) -> Array:
	var rows := []
	rows.resize(rect.size.y)
	if generator:
		noise_set(int(stroke.get("seed", 0)))  # im Hauptfaden anlegen
	var x_min := w.cx - w.size * 0.5
	var job := func(r: int) -> void:
		var j := rect.position.y + r
		var y := w.y_at(j)
		var cols := rect.size.x
		var fmax := PackedFloat32Array()
		var marks := PackedFloat32Array()
		var gen := PackedFloat32Array()
		fmax.resize(cols)
		marks.resize(cols)
		fmax.fill(0.0)
		marks.fill(0.0)
		for dab in dabs:
			var dy := y - dab.y
			if absf(dy) >= reach:
				continue
			var chord := sqrt(reach * reach - dy * dy)
			var c0 := maxi(int(floor((dab.x - chord - x_min) / w.cell)) - rect.position.x, 0)
			var c1 := mini(int(ceil((dab.x + chord - x_min) / w.cell)) - rect.position.x, cols - 1)
			for c in range(c0, c1 + 1):
				var dx := w.x_at(rect.position.x + c) - dab.x
				var dist := sqrt(dx * dx + dy * dy)
				if dist < r_eff:
					var f := Stroke.falloff(dist, r_eff)
					if f > fmax[c]:
						fmax[c] = f
				if dist < r_mark:
					var m := 1.0 - smoothstep(0.6, 1.0, dist / r_mark)
					if m > marks[c]:
						marks[c] = m
		if generator:
			gen.resize(cols)
			for c in cols:
				var i := rect.position.x + c
				if fmax[c] > peak[j * w.res + i]:
					gen[c] = generator_value(stroke, w.x_at(i), y, w.cell)
		_mutex.lock()
		rows[r] = [fmax, marks, gen]
		_mutex.unlock()
	var task := WorkerThreadPool.add_group_task(job, rect.size.y, -1, true, "Weltwerk Pinsel")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return rows


## See: Bett innen auf Spiegel minus Tiefe, außen ansteigende Böschung; Spiegel innen.
func _apply_lake(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	var r_eff := maxf(r, w.cell * 0.75)
	var level: float = stroke.get("level", 0.0)
	var depth: float = stroke.get("depth", 0.0)
	var bank := r * 0.6
	var mark := r < w.cell * 4.0
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	var reach := maxf(r_eff, r_mark) + bank
	var bed_buf := w.water_bed
	var levels := w.water_level
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
				var bed := level - depth * Stroke.falloff(dist, r_eff) + maxf(dist - r_eff, 0.0) * BANK_SLOPE * 2.0
				if dist < r_eff + bank and bed < bed_buf[k]:
					bed_buf[k] = bed
				if dist < r_eff * 0.92:
					levels[k] = maxf(levels[k], level)
				if dist < r_mark:
					marks[k] = maxf(marks[k], 1.0 - smoothstep(0.6, 1.0, dist / r_mark))
	w.water_bed = bed_buf
	w.water_level = levels
	w.edit_marks = marks
	return [changed, peak]

## Geschlossene Form: innen Land (bzw. abgetragen), weicher Rand der Breite radius. Die Küste
## bekommt ihr natürliches Detail aus dem Küstenrauschen der Grundform (in jedem Maßstab).
func _apply_shape(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	var n := Stroke.dab_count(stroke)
	if n < 3:
		return Rect2i()
	var poly := PackedVector2Array()
	for i in n:
		poly.append(Stroke.point(stroke, i))
	var edge: float = maxf(stroke["radius"], w.cell * 0.75)
	var sign := 1.0 if stroke["tool"] == "shape_add" else -1.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	var i0 := maxi(int(floor((lo.x - edge - x_min) / w.cell)), 0)
	var i1 := mini(int(ceil((hi.x + edge - x_min) / w.cell)), res - 1)
	var j0 := maxi(int(floor((y_max - (hi.y + edge)) / w.cell)), 0)
	var j1 := mini(int(ceil((y_max - (lo.y - edge)) / w.cell)), res - 1)
	if i0 > i1 or j0 > j1:
		return Rect2i()
	var cols := i1 - i0 + 1
	# Abstand zum Rand – nur im Randstreifen jeder Kante berechnet.
	var dist := PackedFloat32Array()
	dist.resize(cols * (j1 - j0 + 1))
	dist.fill(INF)
	for e in n:
		var a := poly[e]
		var b := poly[(e + 1) % n]
		var ei0 := maxi(int(floor((minf(a.x, b.x) - edge - x_min) / w.cell)), i0)
		var ei1 := mini(int(ceil((maxf(a.x, b.x) + edge - x_min) / w.cell)), i1)
		var ej0 := maxi(int(floor((y_max - (maxf(a.y, b.y) + edge)) / w.cell)), j0)
		var ej1 := mini(int(ceil((y_max - (minf(a.y, b.y) - edge)) / w.cell)), j1)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1e-6)
		for j in range(ej0, ej1 + 1):
			var y := w.y_at(j)
			for i in range(ei0, ei1 + 1):
				var x := w.x_at(i)
				var t := clampf(((x - a.x) * ab.x + (y - a.y) * ab.y) / len2, 0.0, 1.0)
				var qx := a.x + ab.x * t - x
				var qy := a.y + ab.y * t - y
				var d := sqrt(qx * qx + qy * qy)
				var idx := (j - j0) * cols + (i - i0)
				if d < dist[idx]:
					dist[idx] = d
	# Innen/außen zeilenweise (Schnittpunkte der Kanten mit der Zeile).
	var layer := w.land_edit
	for j in range(j0, j1 + 1):
		var y := w.y_at(j)
		var crossings: Array[float] = []
		for e in n:
			var a := poly[e]
			var b := poly[(e + 1) % n]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		var c := 0
		for i in range(i0, i1 + 1):
			var x := w.x_at(i)
			while c < crossings.size() and crossings[c] < x:
				c += 1
			var inside := c % 2 == 1
			var d := dist[(j - j0) * cols + (i - i0)]
			var s := smoothstep(0.0, edge, d) * 0.5
			var value := 0.5 + s if inside else 0.5 - s
			layer[j * res + i] += sign * value
	w.land_edit = layer
	return Rect2i(i0, j0, cols, j1 - j0 + 1)


## Fluss: Bett entlang des Linienzugs auf Wasserspiegel minus Tiefe, Böschung zu beiden Seiten;
## Wasserspiegel im Fluss. Grob bleibt er mindestens eine Rasterzelle breit (vereinfacht).
func _apply_river(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	var n := Stroke.dab_count(stroke)
	if n < 2:
		return Rect2i()
	var heights: Array = stroke.get("heights", [])
	var r: float = stroke["radius"]
	var depth: float = stroke.get("depth", 2.0)
	var reach := r + 60.0 / BANK_SLOPE
	var r_vis := maxf(r, w.cell * 0.6)
	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	var bed_buf := w.water_bed
	var level_buf := w.water_level
	var changed := Rect2i()
	for e in n - 1:
		var a := Stroke.point(stroke, e)
		var b := Stroke.point(stroke, e + 1)
		var ha: float = heights[e] if e < heights.size() else 0.0
		var hb: float = heights[e + 1] if e + 1 < heights.size() else ha
		var rr := maxf(reach, r_vis)
		var i0 := maxi(int(floor((minf(a.x, b.x) - rr - x_min) / w.cell)), 0)
		var i1 := mini(int(ceil((maxf(a.x, b.x) + rr - x_min) / w.cell)), res - 1)
		var j0 := maxi(int(floor((y_max - (maxf(a.y, b.y) + rr)) / w.cell)), 0)
		var j1 := mini(int(ceil((y_max - (minf(a.y, b.y) - rr)) / w.cell)), res - 1)
		if i0 > i1 or j0 > j1:
			continue
		var rect := Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)
		changed = rect if changed.size == Vector2i.ZERO else changed.merge(rect)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1e-6)
		for j in range(j0, j1 + 1):
			var y := w.y_at(j)
			for i in range(i0, i1 + 1):
				var x := w.x_at(i)
				var t := clampf(((x - a.x) * ab.x + (y - a.y) * ab.y) / len2, 0.0, 1.0)
				var qx := a.x + ab.x * t - x
				var qy := a.y + ab.y * t - y
				var d := sqrt(qx * qx + qy * qy)
				var level := lerpf(ha, hb, t)
				var k := j * res + i
				if d < reach:
					var bed := level - depth * (1.0 - smoothstep(r * 0.4, r, d)) + maxf(d - r, 0.0) * BANK_SLOPE
					if bed < bed_buf[k]:
						bed_buf[k] = bed
				if d < r_vis and level > level_buf[k]:
					level_buf[k] = level
	w.water_bed = bed_buf
	w.water_level = level_buf
	return changed
