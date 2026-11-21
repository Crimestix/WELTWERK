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
##
## Geländeformen: Gebirge sind Züge mit durchgehendem Hauptkamm, Seitengraten und Kerbtälern quer
## zum Kamm (Rauschen in Koordinaten, die zum Kamm hin gestaucht sind), Vorbergen am Rand. Küsten
## gezeichneter Formen und der erzeugten Grundform sind fraktal (Buchten, Halbinseln, Inseln).

const LOW_LIMIT := 8000.0  ## Wellenlänge, ab der Relief als „grob“ gilt (bleibt beim Glätten)
const MIN_WAVELENGTH := 4.0
## Uferböschung von Flüssen und Seen (Meter Anstieg je Meter Abstand, feinster Maßstab).
const BANK_SLOPE := 0.25
## Erzeugung: Der Kamm pendelt um bis zu diesen Anteil des Radius um den gezogenen Strich.
const GEN_WARP := 0.18
## Erzeugung: Weichheit, mit der die Kammrichtung zwischen Strichteilen überblendet (Anteil des Radius).
const GEN_BLEND := 0.12
## Gezeichnete Formen: fraktale Küste – Auslenkung und größte Wellenlänge im Verhältnis zur Randbreite.
const SHAPE_COAST_AMP := 1.0
const SHAPE_COAST_WAVE := 5.0
## Höchste Erhebung der Gebirgsgürtel einer erzeugten Grundform (m).
const BELT_HEIGHT := 3000.0

var continent: Dictionary
var planet: Dictionary
var climate: Dictionary
var drawn: bool

var _noises: Dictionary
## Lage des Erosionsreliefs in diesem Kontinent (fest aus dem Streu-Ausgangswert).
var _relief_alpine: Array
var _relief_hills: Array
## Rauschen für Küstendetail gezeichneter Formen und Seeufer – fest je Kontinent (Streuung),
## bleibt also bei „Variante erzeugen“ gleich.
var _detail: Dictionary
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
	var relief_seed := int(continent.get("scatter_seed", continent["seed"]))
	_relief_alpine = ErosionField.placements(ErosionField.ALPINE_SCALES, relief_seed)
	_relief_hills = ErosionField.placements(ErosionField.HILLS_SCALES, FixedRandom.derive(relief_seed, "Vorberge"))
	_detail = noise_set(FixedRandom.derive(int(continent.get("scatter_seed", continent["seed"])), "Küstenform"))


## Rauschfelder der Grundform zu einem Ausgangswert (zwischengespeichert). Nur im Hauptfaden rufen.
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
		"plateau": _noise(seed_value, "Hochfläche"),
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
	# Schutz wirkt zweifach: Für die Grundform gilt jeder Schutz (er hält die damalige Variante fest),
	# gegen Erzeugung aber erst ab seiner Stelle in der Strichliste – ältere Erzeugung bleibt.
	for stroke in continent["strokes"]:
		if stroke["tool"] == "protect" and touches(w, stroke):
			apply_stroke(w, stroke)
	var block := w.gen_block
	block.fill(0.0)
	w.gen_block = block
	_evaluate_base_cached(w)
	for stroke in continent["strokes"]:
		if touches(w, stroke):
			apply_stroke(w, stroke)
	w.compose_all()
	return w


## Zuletzt berechnete Grundformen (Ausschnitt nach Schutz und Grundform, vor allen übrigen
## Bearbeitungen). Eine neue Bearbeitung ändert die Grundform nicht – so muss nach einem Strich,
## einer Form oder Rückgängig nur die Strichliste neu angewandt werden. Abgeleitet, nie gespeichert.
const BASE_CACHE_SIZE := 6
static var _base_cache := {}
static var _base_order: Array = []


## Lage des Erosionsreliefs (für die Darstellung des Anteils feiner als das Raster).
func relief_placements() -> Dictionary:
	return {"alpine": _relief_alpine, "hills": _relief_hills, "base_scale": base_scale}


func _base_key(w: TerrainWindow) -> String:
	var protects := []
	for stroke in continent["strokes"]:
		if stroke["tool"] == "protect" and touches(w, stroke):
			protects.append(stroke)
	# Volle Genauigkeit (JSON mit allen Stellen): kleinste Lageunterschiede ergeben einen anderen Schlüssel.
	return JSON.stringify([int(continent["seed"]), int(continent.get("scatter_seed", 0)), str(continent.get("base", "")),
		base_scale, float(continent["size_km"]), float(climate["dryness"]), w.cx, w.cy, w.res, w.size, protects], "", false, true)


static func clear_base_cache() -> void:
	_base_cache.clear()
	_base_order.clear()


func _evaluate_base_cached(w: TerrainWindow) -> void:
	var key := _base_key(w)
	if _base_cache.has(key):
		var hit: Array = _base_cache[key]
		w.base_land = (hit[0] as PackedFloat32Array).duplicate()
		w.relief_low = (hit[1] as PackedFloat32Array).duplicate()
		w.relief_detail = (hit[2] as PackedFloat32Array).duplicate()
		w.base_forest = (hit[3] as PackedFloat32Array).duplicate()
		w.erosion_alpine = (hit[4] as PackedFloat32Array).duplicate()
		w.erosion_hills = (hit[5] as PackedFloat32Array).duplicate()
		w.erosion_alpine_fine = (hit[6] as PackedFloat32Array).duplicate()
		_base_order.erase(key)
		_base_order.append(key)
		return
	evaluate_base(w)
	_base_cache[key] = [w.base_land.duplicate(), w.relief_low.duplicate(), w.relief_detail.duplicate(), w.base_forest.duplicate(),
		w.erosion_alpine.duplicate(), w.erosion_hills.duplicate(), w.erosion_alpine_fine.duplicate()]
	_base_order.append(key)
	while _base_order.size() > BASE_CACHE_SIZE:
		_base_cache.erase(_base_order.pop_front())


## Kann der Strich diesen Ausschnitt überhaupt berühren? (Spart die Arbeit für alle anderen.)
func touches(w: TerrainWindow, stroke: Dictionary) -> bool:
	var b := Stroke.bounds(stroke)
	var r: float = stroke["radius"]
	var margin := maxf(r * 0.7, 300.0) + w.cell * 2.0
	match stroke["tool"]:
		"river":
			margin += _river_bank(w.cell)
		"lake":
			margin += _lake_bank(r, w.cell)
		"shape_add", "shape_remove":
			margin += r * SHAPE_COAST_AMP * 1.6
		"land_add", "land_remove", "water":
			margin += r * 0.3
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


## Anteil einer Rauschwelle der Länge lambda, den ein Raster der Zellgröße cell noch zeigen kann.
static func _fade(lambda: float, cell: float) -> float:
	return clampf((lambda / cell - 2.0) * 0.5, 0.0, 1.0)


# --- Grundform -----------------------------------------------------------------------------

func evaluate_base(w: TerrainWindow) -> void:
	_rows.clear()
	_rows.resize(w.res)
	# Pyramiden im Hauptfaden laden (einmal je Programmlauf).
	ErosionField.pyramid("alpine")
	ErosionField.pyramid("hills")
	var task := WorkerThreadPool.add_group_task(_base_row.bind(w), w.res, -1, true, "Weltwerk Gelände")
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Zusammensetzen im Hauptfaden, in lokale Felder, dann einmal zuweisen (keine Kopie je Wert).
	var land := w.base_land
	var low := w.relief_low
	var detail := w.relief_detail
	var forest := w.base_forest
	var alpine := w.erosion_alpine
	var alpine_fine := w.erosion_alpine_fine
	var hills := w.erosion_hills
	var res := w.res
	for j in res:
		var row: Array = _rows[j]
		var offset := j * res
		for i in res:
			land[offset + i] = row[0][i]
			low[offset + i] = row[1][i]
			detail[offset + i] = row[2][i]
			forest[offset + i] = row[3][i]
			alpine[offset + i] = row[4][i]
			hills[offset + i] = row[5][i]
			alpine_fine[offset + i] = row[6][i]
	w.erosion_alpine = alpine
	w.erosion_alpine_fine = alpine_fine
	w.erosion_hills = hills
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
		land[k] = lerpf(land[k], b[0], p)
		low[k] = lerpf(low[k], b[1], p)
		detail[k] = lerpf(detail[k], b[2], p)
		forest[k] = lerpf(forest[k], b[3], p)
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
	var alpine := PackedFloat32Array()
	var alpine_fine := PackedFloat32Array()
	var hills := PackedFloat32Array()
	alpine_fine.resize(res)
	land.resize(res)
	low.resize(res)
	detail.resize(res)
	forest.resize(res)
	alpine.resize(res)
	hills.resize(res)
	var s := base_scale
	# Gebirge getrennt: große Form (Massive, Haupttäler) und feinere Täler/Rinnen – „Glätten“
	# nimmt nur die feineren zurück.
	var alp := ErosionField.prepare(ErosionField.pyramid("alpine"), _relief_alpine, w.cell * s, 0, 1)
	var alp_fine := ErosionField.prepare(ErosionField.pyramid("alpine"), _relief_alpine, w.cell * s, 1)
	var hil := ErosionField.prepare(ErosionField.pyramid("hills"), _relief_hills, w.cell * s)
	var y := w.y_at(j) * s
	var half: float = continent["size_km"] * 500.0 * s
	var dryness: float = climate["dryness"]
	for i in res:
		var sample := sample_base(w.x_at(i) * s, y, w.cell * s, half, dryness, _noises)
		land[i] = sample[0]
		low[i] = sample[1]
		detail[i] = sample[2]
		forest[i] = sample[3]
		# Erosionsrelief jede zweite Spalte (es ist auf mindestens zwei Zellen geglättet),
		# dazwischen linear – halbiert die Rechenzeit ohne sichtbaren Unterschied.
		if i % 2 == 0 or i == res - 1:
			var x := w.x_at(i) * s
			alpine[i] = ErosionField.value_prepared(alp, x, y)
			alpine_fine[i] = ErosionField.value_prepared(alp_fine, x, y)
			hills[i] = ErosionField.value_prepared(hil, x, y)
	for i in range(1, res - 1, 2):
		alpine[i] = (alpine[i - 1] + alpine[i + 1]) * 0.5
		alpine_fine[i] = (alpine_fine[i - 1] + alpine_fine[i + 1]) * 0.5
		hills[i] = (hills[i - 1] + hills[i + 1]) * 0.5
	_mutex.lock()
	_rows[j] = [land, low, detail, forest, alpine, hills, alpine_fine]
	_mutex.unlock()


## Erzeugte Grundlage an einem Punkt: (Landanteil, grobes Relief, feines Relief, Wald).
## Bei gezeichneter Grundform gibt es keinen Fleck – Land entsteht nur aus Formen und Pinseln;
## Küstendetail, sanftes Relief und Wald wirken trotzdem überall (dort, wo Land ist).
func sample_base(x: float, y: float, cell: float, half: float, dryness: float, set: Dictionary) -> Vector4:
	var land := 0.0
	var low := 0.0
	var detail := 0.0
	if drawn:
		land = _bands(set["coast"], x, y, cell, 40000.0, 10, 0.10, 0.6, 0.0, false).x
	else:
		# Umriss: verzerrter Abstand zur Mitte, darauf fraktale Küste – Buchten, Halbinseln und
		# vorgelagerte Inseln. Die Verzerrung streckt den Fleck zu einer unregelmäßigen Landmasse.
		var ns: FastNoiseLite = set["shape"]
		var l1 := half * 0.7
		var l2 := half * 0.25
		var wx := ns.get_noise_2d(x / l1, y / l1) * 0.42 + ns.get_noise_2d(x / l2 + 31.0, y / l2 - 17.0) * 0.13
		var wy := ns.get_noise_2d(x / l1 - 47.0, y / l1 + 23.0) * 0.42 + ns.get_noise_2d(x / l2 + 5.0, y / l2 + 71.0) * 0.13
		var ux := x / half + wx
		var uy := y / half + wy
		var r := sqrt(ux * ux + uy * uy)
		var coast := _bands(set["coast"], x, y, cell, half * 0.28, 12, 0.12, 0.56, 0.0, false).x
		land = 1.0 - smoothstep(0.50, 0.80, r - coast)

	# Sanftes Hügelland überall, dazu breite Hochflächen mit weichen Stufen.
	var hills := _bands(set["hills"], x, y, cell, 64000.0, 14, 170.0 if drawn else 230.0, 0.5, LOW_LIMIT, false)
	low += hills.x
	detail += hills.y
	var pn: FastNoiseLite = set["plateau"]
	var lp := half * 0.32
	var plateau := smoothstep(0.12, 0.32, pn.get_noise_2d(x / lp, y / lp))
	low += plateau * (230.0 if drawn else 420.0)
	if not drawn:
		var belt := _belt(set, x, y, cell, half)
		low += belt.x
		detail += belt.y

	# Wald in natürlichen Flecken: großräumig verzerrt, mit fraktalem Rand; Hochlagen lichter.
	var fn: FastNoiseLite = set["forest"]
	var fx := x + pn.get_noise_2d(x / 60000.0 + 3.0, y / 60000.0 + 41.0) * 9000.0
	var fy := y + pn.get_noise_2d(x / 60000.0 - 29.0, y / 60000.0 - 7.0) * 9000.0
	var f := fn.get_noise_2d(fx / 110000.0, fy / 110000.0) * 0.4 \
		+ _bands(fn, fx, fy, cell, 30000.0, 8, 0.36, 0.6, 0.0, false).x
	f -= maxf(low - 300.0, 0.0) / 3000.0
	var forest := smoothstep(0.0, 0.22, f + 0.1 - dryness * 0.5)
	return Vector4(land, low, detail, forest)


## Gebirgsgürtel der erzeugten Grundform: entlang der Nulllinien eines großräumigen Rauschens
## (lange, gewundene Linien), dort ein Gebirgszug wie aus dem Gebirgswerkzeug. (grob, fein) in m.
func _belt(set: Dictionary, x: float, y: float, cell: float, half: float) -> Vector2:
	var nb: FastNoiseLite = set["mask"]
	var lb := half * 0.95
	var b := nb.get_noise_2d(x / lb, y / lb)
	var rb := half * 0.13
	# Grob vorsortieren: Weit weg von einer Nulllinie entsteht kein Gebirge.
	if absf(b) > 0.5:
		return Vector2.ZERO
	var e := lb * 0.002
	var gx := (nb.get_noise_2d((x + e) / lb, y / lb) - nb.get_noise_2d((x - e) / lb, y / lb)) / (2.0 * e)
	var gy := (nb.get_noise_2d(x / lb, (y + e) / lb) - nb.get_noise_2d(x / lb, (y - e) / lb)) / (2.0 * e)
	var g2 := gx * gx + gy * gy
	if g2 < 1e-24:
		return Vector2.ZERO
	var d := absf(b) / sqrt(g2)
	if d >= rb:
		return Vector2.ZERO
	# Nächster Punkt auf der Kammlinie (Newton-Schritt) – daran hängen Kammhöhe und Ausrichtung.
	var cx := x - b * gx / g2
	var cy := y - b * gy / g2
	var lm := half * 0.55
	var presence := smoothstep(-0.15, 0.25, (set["ridges"] as FastNoiseLite).get_noise_2d(cx / lm + 11.0, cy / lm - 5.0))
	if presence <= 0.0:
		return Vector2.ZERO
	return _range_shape(set, rb, d / rb, x, y, cx, cy, cell, LOW_LIMIT) * (BELT_HEIGHT * presence)


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


# --- Geländeformen der Erzeugung -------------------------------------------------------------

## Gebirgszug, Höhe etwa 0–1. t = Abstand zum Kamm / Radius (0 Kamm, 1 Rand), p = Punkt,
## c = nächster Kammpunkt, r = Radius (Maßstab der Formen). Ergebnis (grob, fein), getrennt an split.
##
## Hauptkamm: Profil (1 − t)^1,5 mit Gipfeln und Sätteln entlang des Kamms (Rauschen am Kammpunkt).
## Seitengrate und Kerbtäler: Rauschen in q = p + α·(c − p) – quer zum Kamm gestaucht, darum laufen
## Täler und Grate vom Kamm hinab. Feinere Grate verzweigen (weniger ausgerichtet, stärker auf Graten).
func _range_shape(set: Dictionary, r: float, t: float, px: float, py: float, cx: float, cy: float,
		cell: float, split: float) -> Vector2:
	if t >= 1.0:
		return Vector2.ZERO
	var nc: FastNoiseLite = set["mask"]
	var nr: FastNoiseLite = set["ridges"]
	# Breite und Kammhöhe wechseln entlang des Zugs: Gipfelgruppen, Pässe, schmalere Abschnitte.
	var lc := 1.4 * r
	var along := nc.get_noise_2d(cx / lc, cy / lc)
	t /= 0.84 + 0.16 * nc.get_noise_2d(cx / (2.1 * r) + 23.0, cy / (2.1 * r) - 31.0)
	if t >= 1.0:
		return Vector2.ZERO
	var u := 1.0 - t
	# Scharfer Kamm, aber kräftige Flanken (fällt monoton, am Rand ohne Kante aus).
	var profile := pow(u, 1.3) * (1.0 + t)
	var crest := 0.72 + 0.28 * along
	var lp := 0.3 * r
	var fp := _fade(lp, cell)
	if fp > 0.0:
		crest *= 1.0 - 0.18 * fp * absf(nc.get_noise_2d(cx / lp + 7.1, cy / lp - 3.3))
	var coarse := profile * crest
	var fine := 0.0
	# Hauptäste: Grate und Kerbtäler quer zum Kamm.
	var l0 := 0.5 * r
	var f0 := _fade(l0, cell)
	var spur := 1.0
	if f0 > 0.0:
		# Leicht gekrümmte Täler: der gestauchte Punkt pendelt selbst ein wenig.
		var bend := nc.get_noise_2d(px / (0.6 * r) - 13.0, py / (0.6 * r) + 5.0) * 0.12 * r
		var qx := px + 0.72 * (cx - px) + bend
		var qy := py + 0.72 * (cy - py) - bend
		var a := minf(absf(nr.get_noise_2d(qx / l0, qy / l0)) / 0.42, 1.0)
		spur = 1.0 - (1.0 - a) * (1.0 - a)
		var cut := (0.14 + 0.6 * smoothstep(0.0, 0.45, t)) * (1.0 - spur) * f0
		var v := -coarse * cut
		if l0 >= split:
			coarse += v
		else:
			fine += v
	# Verzweigungen: je feiner, desto weniger ausgerichtet; wirken vor allem auf den Graten.
	var envelope := pow(u, 0.8)
	var lambda := l0 * 0.5
	var amp := 0.26
	var alpha := 0.5
	var weight := 0.45 + 0.55 * spur
	for k in 8:
		var f := _fade(lambda, cell)
		if f <= 0.0:
			break
		var ax := px + alpha * (cx - px)
		var ay := py + alpha * (cy - py)
		var ridge := 1.0 - absf(nr.get_noise_2d(ax / lambda + k * 17.31, ay / lambda - k * 9.17))
		ridge *= ridge
		var v := (ridge - 0.45) * amp * weight * f * envelope
		if lambda >= split:
			coarse += v
		else:
			fine += v
		weight = clampf(ridge * 1.3, 0.3, 1.0)
		lambda *= 0.5
		amp *= 0.62
		alpha *= 0.6
	# Vorberge: niedrige, rundliche Kuppen am Rand des Zugs.
	var foot := smoothstep(0.35, 0.65, t) * (1.0 - smoothstep(0.8, 1.0, t))
	var lf := 0.2 * r
	var ff := _fade(lf, cell)
	if foot > 0.0 and ff > 0.0:
		var nh: FastNoiseLite = set["hills"]
		var v := foot * 0.08 * ff * (0.5 + 0.5 * nh.get_noise_2d(px / lf, py / lf))
		if lf >= split:
			coarse += v
		else:
			fine += v
	return Vector2(coarse, fine)


## Hügelland (0–1): rundliche Kuppen, zur Mitte des Strichs hin dichter und höher.
func _hill_shape(set: Dictionary, r: float, t: float, px: float, py: float, cell: float) -> float:
	var mask := 1.0 - smoothstep(0.3, 1.0, t)
	var nh: FastNoiseLite = set["hills"]
	var lambda := 0.28 * r
	var amp := 1.0
	var sum := 0.0
	var total := 0.0
	for k in 7:
		var f := _fade(lambda, cell)
		if f <= 0.0:
			break
		var n := nh.get_noise_2d(px / lambda + k * 17.31, py / lambda - k * 9.17)
		# Kuppen: oben rund, Mulden enger (umgekehrtes Betragsrauschen, gemildert).
		var v := 1.0 - absf(n)
		v = v * v * 2.0 - 1.0
		sum += (lerpf(n, v, 0.45)) * amp * f
		total += amp
		lambda *= 0.5
		amp *= 0.5
	var v01 := 0.5 + 0.5 * (sum / maxf(total, 1.0))
	return mask * (0.3 + 0.7 * clampf(v01, 0.0, 1.0)) * (0.75 + 0.25 * (1.0 - t))


## Wald in Flecken (0–1) mit fraktalem Rand; zum Strich hin geschlossener.
func _forest_shape(set: Dictionary, r: float, t: float, px: float, py: float, cell: float) -> float:
	var mask := 1.0 - smoothstep(0.55, 1.0, t)
	var v := _bands(set["forest"], px, py, cell * 1.3, 0.3 * r, 8, 0.6, 0.55, 0.0, false).x
	return smoothstep(-0.1, 0.12, v + 0.3 * (1.0 - t) - 0.08) * mask


## Inselkette (Landzuwachs 0–1): Inseln verschiedener Größe, entlang des Strichs größer und dichter.
## Nimmt nie ab, wenn der Strich näher rückt (wichtig für die Reihenfolge der Landbegrenzung).
func _island_shape(set: Dictionary, r: float, t: float, px: float, py: float, cell: float) -> float:
	# Große Wellen bilden die Hauptinseln, feinere die Buchten und kleinen Nachbarinseln.
	var v := _bands(set["coast"], px, py, cell * 1.3, 0.9 * r, 10, 1.0, 0.5, 0.0, false).x
	var u := 1.0 - t
	return smoothstep(0.0, 0.16, v + 0.75 * u * u - 0.7) * (1.0 - smoothstep(0.75, 1.0, t))


## Form einer erzeugenden Bearbeitung an einem Punkt (ohne Stärke).
func _gen_shape(tool: String, set: Dictionary, r: float, t: float, px: float, py: float,
		cx: float, cy: float, cell: float) -> float:
	match tool:
		"gen_mountains":
			var m := _range_shape(set, r, t, px, py, cx, cy, cell, 0.0)
			return maxf(m.x + m.y, 0.0)
		"gen_hills":
			return _hill_shape(set, r, t, px, py, cell)
		"gen_forest":
			return _forest_shape(set, r, t, px, py, cell)
		"gen_islands":
			return _island_shape(set, r, t, px, py, cell)
	return 0.0


## Natürliches Pendeln des Kamms (Verschiebung des Auswertepunkts, höchstens GEN_WARP · r).
static func _gen_warp(n: FastNoiseLite, x: float, y: float, r: float, cell: float) -> Vector2:
	var l1 := 1.3 * r
	var l2 := 0.45 * r
	var f2 := _fade(l2, cell) * 0.05 * r
	var wx := n.get_noise_2d(x / l1, y / l1) * 0.12 * r
	var wy := n.get_noise_2d(x / l1 + 41.3, y / l1 - 12.7) * 0.12 * r
	if f2 > 0.0:
		wx += n.get_noise_2d(x / l2 - 8.9, y / l2 + 3.1) * f2
		wy += n.get_noise_2d(x / l2 + 15.2, y / l2 + 27.5) * f2
	return Vector2(wx, wy)


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


## Wendet die Tupfer ab first_dab an. peak hält je Rasterpunkt die bisher stärkste Wirkung
## dieses Strichs (ein Strich wirkt nicht doppelt, wo er sich überlappt).
## Je Rasterpunkt zählt die stärkste Wirkung aller neuen Tupfer – das ist dasselbe Ergebnis wie
## Tupfer für Tupfer, lässt sich aber zeilenweise parallel rechnen.
## Gibt [geändertes Rechteck, neues peak] zurück.
func apply_dabs(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var tool: String = stroke["tool"]
	if tool == "lake":
		return _apply_lake(w, stroke, first_dab, peak)
	if Stroke.is_generator(stroke):
		return _apply_generator(w, stroke, first_dab, peak)
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	# Feiner als das Raster: Fläche erhalten statt verschwinden lassen (vereinfachte Darstellung).
	var r_eff := maxf(r, w.cell * 0.75)
	var amount: float = stroke["strength"] * pow(r / r_eff, 2.0)
	if tool in ["land_remove", "water", "lower", "forest_remove"]:
		amount = -amount
	# Markiert wird nur, wo die Bearbeitung in diesem Maßstab kaum noch zu sehen ist.
	var mark := r < w.cell * 4.0 and tool != "protect"
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	# Land-Pinsel: Rand mit natürlichem, fraktalem Verlauf statt Kreisbogen.
	var land_tool := tool in ["land_add", "land_remove", "water"]
	var jag := r * 0.25 if land_tool else 0.0
	var reach := maxf(r_eff + jag, r_mark)

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

	var rows := _dab_rows(w, stroke, dabs, changed, r_eff, r_mark, reach, jag)

	var layer: PackedFloat32Array
	match tool:
		"land_add", "land_remove", "water": layer = w.land_edit
		"raise", "lower": layer = w.height_edit
		"smooth": layer = w.smooth_edit
		"flatten": layer = w.flat_weight
		"protect": layer = w.protect
		_: layer = w.forest_edit
	var marks := w.edit_marks
	var block := w.gen_block
	var levels := w.flat_level
	var seeds := w.protect_seed
	if land_tool:
		# Vorher begrenzen: dann ergeben Teilaufrufe (Live-Malen) und ein Aufruf dasselbe.
		clamp_land(w, changed)
		layer = w.land_edit
	var level: float = stroke.get("level", 0.0)
	var seed_value: int = int(stroke.get("seed", continent["seed"]))
	for j in range(changed.position.y, changed.end.y):
		var row: Array = rows[j - changed.position.y]
		var fmax: PackedFloat32Array = row[0]
		var mrow: PackedFloat32Array = row[1]
		for c in changed.size.x:
			var k := j * res + changed.position.x + c
			if mark and mrow[c] > marks[k]:
				marks[k] = mrow[c]
			var f := fmax[c]
			if f <= peak[k]:
				continue
			var before := peak[k]
			var delta := f - before
			peak[k] = f
			match tool:
				"protect":
					# Ausgangswert nur übernehmen, wo dieser Schutz der stärkere ist.
					if f >= layer[k]:
						seeds[k] = seed_value
					layer[k] = maxf(layer[k], f)
					block[k] = maxf(block[k], f)
				"flatten":
					if layer[k] < 0.01:
						levels[k] = level
					else:
						# Gleich in Teilen wie in einem Zug: ergibt lerp(Ausgang, Ziel, stärkste Wirkung).
						levels[k] = lerpf(levels[k], level, delta / maxf(1.0 - before, 1e-6))
					layer[k] = clampf(layer[k] + amount * delta, 0.0, 1.0)
				_:
					layer[k] += amount * delta

	match tool:
		"land_add", "land_remove", "water":
			w.land_edit = layer
			clamp_land(w, changed)
		"raise", "lower": w.height_edit = layer
		"smooth": w.smooth_edit = layer
		"flatten":
			w.flat_weight = layer
			w.flat_level = levels
		"protect":
			w.protect = layer
			w.protect_seed = seeds
			w.gen_block = block
		_: w.forest_edit = layer
	w.edit_marks = marks
	return [changed, peak]


## Je Zeile des Rechtecks: stärkste Wirkung (falloff) und Marke. Zeilen parallel;
## Ergebnis [[fmax, mark], …]. jag > 0: Rand um bis zu jag Meter fraktal verschoben (Land-Pinsel).
func _dab_rows(w: TerrainWindow, stroke: Dictionary, dabs: PackedVector2Array, rect: Rect2i, r_eff: float,
		r_mark: float, reach: float, jag: float) -> Array:
	var rows := []
	rows.resize(rect.size.y)
	var x_min := w.cx - w.size * 0.5
	var r: float = stroke["radius"]
	var coast: FastNoiseLite = _detail["coast"]
	var job := func(rr: int) -> void:
		var j := rect.position.y + rr
		var y := w.y_at(j)
		var cols := rect.size.x
		var dmin := PackedFloat32Array()
		var marks := PackedFloat32Array()
		dmin.resize(cols)
		marks.resize(cols)
		dmin.fill(INF)
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
				if dist < dmin[c]:
					dmin[c] = dist
				if dist < r_mark:
					var m := 1.0 - smoothstep(0.6, 1.0, dist / r_mark)
					if m > marks[c]:
						marks[c] = m
		# Stärkste Wirkung = Wirkung des nächsten Tupfers (falloff fällt mit dem Abstand).
		var fmax := PackedFloat32Array()
		fmax.resize(cols)
		for c in cols:
			var dist := dmin[c]
			if jag > 0.0 and dist < reach:
				var x := w.x_at(rect.position.x + c)
				dist -= clampf(_bands(coast, x, y, w.cell, r * 0.8, 8, jag * 0.62, 0.55, 0.0, false).x, -jag, jag)
			fmax[c] = Stroke.falloff(dist, r_eff) if dist < r_eff else 0.0
		_mutex.lock()
		rows[rr] = [fmax, marks]
		_mutex.unlock()
	var task := WorkerThreadPool.add_group_task(job, rect.size.y, -1, true, "Weltwerk Pinsel")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return rows


## Erzeugende Bearbeitung (Gebirge, Hügel, Wald, Inseln). Gerechnet wird mit den Strecken zwischen
## aufeinanderfolgenden Tupfern: Abstand zum Linienzug (Kamm) und nächster Kammpunkt, beides am
## natürlich pendelnden Auswertepunkt. Teilaufrufe (Live-Malen) addieren im berührten Rechteck
## „Form mit allen Strecken − Form mit den bisherigen“ – die Summe aller Teile ist genau die
## Neuberechnung in einem Zug. Gibt [geändertes Rechteck, peak (unverändert)] zurück.
func _apply_generator(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var tool: String = stroke["tool"]
	var points: Array = stroke["points"]
	var n := points.size() / 2
	if first_dab >= n:
		return [Rect2i(), peak]
	var r: float = stroke["radius"]
	var r_eff := maxf(r, w.cell * 0.75)
	var amount: float = stroke["strength"] * pow(r / r_eff, 2.0)
	var mark := r < w.cell * 4.0
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	var reach := maxf(r_eff * (1.0 + GEN_WARP), r_mark)
	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	# Neu sind die Strecken ab first_dab; die erste reicht bis zum letzten alten Tupfer zurück.
	var changed := Rect2i()
	for d in range(maxi(first_dab - 1, 0), n):
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
	if changed.size == Vector2i.ZERO:
		return [changed, peak]
	# Strecke s verbindet Tupfer max(s − 1, 0) und s (die erste ist ein Punkt).
	var seg := PackedFloat64Array()
	seg.resize(n * 4)
	for s in n:
		var a := maxi(s - 1, 0)
		seg[s * 4] = points[a * 2]
		seg[s * 4 + 1] = points[a * 2 + 1]
		seg[s * 4 + 2] = points[s * 2]
		seg[s * 4 + 3] = points[s * 2 + 1]
	var set := noise_set(int(stroke.get("seed", 0)))  # im Hauptfaden anlegen
	var warp_noise: FastNoiseLite = set["shape"]
	var tau := r_eff * GEN_BLEND
	var cell := w.cell
	var rows := []
	rows.resize(changed.size.y)
	var job := func(rr: int) -> void:
		var j := changed.position.y + rr
		var y := w.y_at(j)
		var cols := changed.size.x
		var gen := PackedFloat32Array()
		var marks := PackedFloat32Array()
		gen.resize(cols)
		marks.resize(cols)
		gen.fill(0.0)
		marks.fill(0.0)
		var cand := PackedInt32Array()
		for s in n:
			var o := s * 4
			if minf(seg[o + 1], seg[o + 3]) - reach <= y and maxf(seg[o + 1], seg[o + 3]) + reach >= y:
				cand.append(s)
		if not cand.is_empty():
			var need := PackedByteArray()
			need.resize(cols)
			need.fill(0)
			for s in cand:
				var o := s * 4
				var c0 := maxi(int(floor((minf(seg[o], seg[o + 2]) - reach - x_min) / cell)) - changed.position.x, 0)
				var c1 := mini(int(ceil((maxf(seg[o], seg[o + 2]) + reach - x_min) / cell)) - changed.position.x, cols - 1)
				for c in range(c0, c1 + 1):
					need[c] = 1
			for c in cols:
				if need[c] == 0:
					continue
				var x := w.x_at(changed.position.x + c)
				var wv := _gen_warp(warp_noise, x, y, r, cell)
				var px := x + wv.x
				var py := y + wv.y
				var best := INF
				var sw := 0.0
				var sx := 0.0
				var sy := 0.0
				var best_old := INF
				var sw_old := 0.0
				var sx_old := 0.0
				var sy_old := 0.0
				var plain := INF
				for s in cand:
					var o := s * 4
					var ax: float = seg[o]
					var ay: float = seg[o + 1]
					var abx: float = seg[o + 2] - ax
					var aby: float = seg[o + 3] - ay
					var len2 := abx * abx + aby * aby
					var tt := 0.0
					if len2 > 1e-6:
						tt = clampf(((px - ax) * abx + (py - ay) * aby) / len2, 0.0, 1.0)
					var qx := ax + abx * tt
					var qy := ay + aby * tt
					var dist := sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy))
					if dist < r_eff:
						var wgt := exp(-dist / tau)
						sw += wgt
						sx += wgt * qx
						sy += wgt * qy
						if dist < best:
							best = dist
						if s < first_dab:
							sw_old += wgt
							sx_old += wgt * qx
							sy_old += wgt * qy
							if dist < best_old:
								best_old = dist
					if mark:
						var tp := 0.0
						if len2 > 1e-6:
							tp = clampf(((x - ax) * abx + (y - ay) * aby) / len2, 0.0, 1.0)
						var ex := x - ax - abx * tp
						var ey := y - ay - aby * tp
						plain = minf(plain, sqrt(ex * ex + ey * ey))
				var v := 0.0
				if best < r_eff:
					v = _gen_shape(tool, set, r, best / r_eff, px, py, sx / sw, sy / sw, cell)
					if best_old < r_eff:
						v -= _gen_shape(tool, set, r, best_old / r_eff, px, py, sx_old / sw_old, sy_old / sw_old, cell)
				gen[c] = v
				if plain < r_mark:
					marks[c] = 1.0 - smoothstep(0.6, 1.0, plain / r_mark)
		_mutex.lock()
		rows[rr] = [gen, marks]
		_mutex.unlock()
	var task := WorkerThreadPool.add_group_task(job, changed.size.y, -1, true, "Weltwerk Erzeugung")
	WorkerThreadPool.wait_for_group_task_completion(task)

	var land_tool := tool == "gen_islands"
	var layer: PackedFloat32Array
	if land_tool:
		# Vorher begrenzen: dann ergeben Teilaufrufe (Live-Malen) und ein Aufruf dasselbe.
		clamp_land(w, changed)
		layer = w.land_edit
	elif tool == "gen_forest":
		layer = w.forest_edit
	else:
		layer = w.height_edit
	var marks_buf := w.edit_marks
	var block := w.gen_block
	for j in range(changed.position.y, changed.end.y):
		var row: Array = rows[j - changed.position.y]
		var grow: PackedFloat32Array = row[0]
		var mrow: PackedFloat32Array = row[1]
		for c in changed.size.x:
			var k := j * res + changed.position.x + c
			if mark and mrow[c] > marks_buf[k]:
				marks_buf[k] = mrow[c]
			var g := grow[c]
			if g != 0.0:
				layer[k] += amount * g * (1.0 - block[k])
	if land_tool:
		w.land_edit = layer
		clamp_land(w, changed)
	elif tool == "gen_forest":
		w.forest_edit = layer
	else:
		w.height_edit = layer
	w.edit_marks = marks_buf
	return [changed, peak]


## Breite der Seeböschung: mindestens einige Rasterzellen, damit grob kein Wall entsteht.
static func _lake_bank(r: float, cell: float) -> float:
	return maxf(r * 0.6, cell * 4.0)


static func _river_bank(cell: float) -> float:
	return maxf(60.0 / BANK_SLOPE, cell * 3.0)


## Anstieg der Böschung bei Anteil u (0 am Wasser, 1 am Rand): sanft beginnend, zum Rand hin so
## steil, dass jedes Gelände erreicht wird – ohne Kante an der Grenze der Böschung.
static func _bank_rise(u: float, height: float) -> float:
	return height * u * u / maxf(1.0 - u, 1e-4)


## See: Bett innen auf Spiegel minus Tiefe, außen eine weite, sanft ansteigende Böschung (Mulde
## statt Kraterwall); Spiegel innen. Das Ufer ist natürlich gebuchtet (nur nach innen verschoben,
## damit kein Wasser über tieferem Ufer steht).
func _apply_lake(w: TerrainWindow, stroke: Dictionary, first_dab: int, peak: PackedFloat32Array) -> Array:
	var points: Array = stroke["points"]
	var r: float = stroke["radius"]
	var r_eff := maxf(r, w.cell * 0.75)
	var level: float = stroke.get("level", 0.0)
	var depth: float = stroke.get("depth", 0.0)
	var bank := _lake_bank(r, w.cell)
	var bank_height := clampf(bank * 0.03, 15.0, 600.0)
	var mark := r < w.cell * 4.0
	var r_mark := maxf(r, w.cell * 1.5) if mark else 0.0
	var reach := maxf(r_eff, r_mark) + bank
	var bed_buf := w.water_bed
	var levels := w.water_level
	var marks := w.edit_marks
	var coast: FastNoiseLite = _detail["coast"]
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
			var y := w.y_at(j)
			var dy := y - py
			for i in range(i0, i1 + 1):
				var x := w.x_at(i)
				var dx := x - px
				var dist := sqrt(dx * dx + dy * dy)
				var k := j * res + i
				if dist < r_mark:
					marks[k] = maxf(marks[k], 1.0 - smoothstep(0.6, 1.0, dist / r_mark))
				if dist >= reach:
					continue
				# Buchten: Abstand nach außen verschoben (0 … 0,3 r), fein nur so weit wie das Raster.
				var inner := smoothstep(0.3, 0.55, dist / r_eff)
				if inner > 0.0:
					var b := _bands(coast, x, y, w.cell, r * 0.9, 7, 0.16 * r, 0.55, 0.0, false).x
					dist += maxf(b + 0.12 * r, 0.0) * inner
				var bed: float
				if dist <= r_eff:
					bed = level - depth * Stroke.falloff(dist, r_eff)
				else:
					bed = level + _bank_rise((dist - r_eff) / bank, bank_height)
				if bed < bed_buf[k]:
					bed_buf[k] = bed
				if dist < r_eff * 0.92:
					levels[k] = maxf(levels[k], level)
	w.water_bed = bed_buf
	w.water_level = levels
	w.edit_marks = marks
	return [changed, peak]


## Geschlossene Form: innen Land (bzw. abgetragen), weicher Rand der Breite radius. Die Küste ist
## fraktal verschoben (Buchten, Halbinseln, vorgelagerte Inseln), im Verhältnis zur Randbreite –
## also zum Maßstab, in dem die Form gezeichnet wurde –, fein nur so weit wie das Raster.
func _apply_shape(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	var n := Stroke.dab_count(stroke)
	if n < 3:
		return Rect2i()
	var points: Array = stroke["points"]
	var poly := PackedFloat64Array()
	poly.resize(n * 2)
	for k in n * 2:
		poly[k] = points[k]
	var edge: float = maxf(stroke["radius"], w.cell * 0.75)
	var coast_amp: float = stroke["radius"] * SHAPE_COAST_AMP
	var shift_max := coast_amp * 1.6
	var band := edge + shift_max
	var sign := 1.0 if stroke["tool"] == "shape_add" else -1.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in n:
		lo = Vector2(minf(lo.x, poly[k * 2]), minf(lo.y, poly[k * 2 + 1]))
		hi = Vector2(maxf(hi.x, poly[k * 2]), maxf(hi.y, poly[k * 2 + 1]))
	var x_min := w.cx - w.size * 0.5
	var y_max := w.cy + w.size * 0.5
	var res := w.res
	var i0 := maxi(int(floor((lo.x - band - x_min) / w.cell)), 0)
	var i1 := mini(int(ceil((hi.x + band - x_min) / w.cell)), res - 1)
	var j0 := maxi(int(floor((y_max - (hi.y + band)) / w.cell)), 0)
	var j1 := mini(int(ceil((y_max - (lo.y - band)) / w.cell)), res - 1)
	if i0 > i1 or j0 > j1:
		return Rect2i()
	var cols := i1 - i0 + 1
	var coast: FastNoiseLite = _detail["coast"]
	var wave: float = stroke["radius"] * SHAPE_COAST_WAVE
	var cell := w.cell
	var rows := []
	rows.resize(j1 - j0 + 1)
	var job := func(rr: int) -> void:
		var j := j0 + rr
		var y := w.y_at(j)
		# Abstand zum Rand – nur im Randstreifen der Kanten, die diese Zeile erreichen.
		var dist := PackedFloat32Array()
		dist.resize(cols)
		dist.fill(INF)
		var crossings: Array[float] = []
		for e in n:
			var ax := poly[e * 2]
			var ay := poly[e * 2 + 1]
			var e2 := (e + 1) % n
			var bx := poly[e2 * 2]
			var by := poly[e2 * 2 + 1]
			if (ay <= y and by > y) or (by <= y and ay > y):
				crossings.append(ax + (y - ay) / (by - ay) * (bx - ax))
			if minf(ay, by) - band > y or maxf(ay, by) + band < y:
				continue
			var c0 := maxi(int(floor((minf(ax, bx) - band - x_min) / cell)), i0) - i0
			var c1 := mini(int(ceil((maxf(ax, bx) + band - x_min) / cell)), i1) - i0
			var abx := bx - ax
			var aby := by - ay
			var len2 := maxf(abx * abx + aby * aby, 1e-6)
			for c in range(c0, c1 + 1):
				var x := w.x_at(i0 + c)
				var t := clampf(((x - ax) * abx + (y - ay) * aby) / len2, 0.0, 1.0)
				var qx := ax + abx * t - x
				var qy := ay + aby * t - y
				var d := sqrt(qx * qx + qy * qy)
				if d < dist[c]:
					dist[c] = d
		# Innen/außen über die Schnittpunkte der Kanten mit der Zeile.
		crossings.sort()
		var values := PackedFloat32Array()
		values.resize(cols)
		var m := 0
		for c in cols:
			var x := w.x_at(i0 + c)
			while m < crossings.size() and crossings[m] < x:
				m += 1
			var inside := m % 2 == 1
			var d := dist[c]
			var sd := d if inside else -d
			if d < band:
				var shift := _bands(coast, x, y, cell, wave, 12, coast_amp, 0.56, 0.0, false).x
				sd += clampf(shift, -shift_max, shift_max)
			var s := smoothstep(0.0, edge, absf(sd)) * 0.5
			values[c] = 0.5 + s if sd > 0.0 else 0.5 - s
		_mutex.lock()
		rows[rr] = values
		_mutex.unlock()
	var task := WorkerThreadPool.add_group_task(job, j1 - j0 + 1, -1, true, "Weltwerk Form")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var layer := w.land_edit
	for rr in j1 - j0 + 1:
		var values: PackedFloat32Array = rows[rr]
		var offset := (j0 + rr) * res + i0
		for c in cols:
			layer[offset + c] += sign * values[c]
	w.land_edit = layer
	return Rect2i(i0, j0, cols, j1 - j0 + 1)


## Fluss: Bett entlang des Linienzugs auf Wasserspiegel minus Tiefe, Böschung zu beiden Seiten;
## Wasserspiegel im Fluss. Grob bleibt er mindestens eine Rasterzelle breit (vereinfacht), sein
## Bett ist dann flacher und die Böschung mehrere Zellen breit – ein Tal statt eines Grabens.
func _apply_river(w: TerrainWindow, stroke: Dictionary) -> Rect2i:
	var n := Stroke.dab_count(stroke)
	if n < 2:
		return Rect2i()
	var heights: Array = stroke.get("heights", [])
	var r: float = stroke["radius"]
	var bank := _river_bank(w.cell)
	var bank_height := clampf(bank * BANK_SLOPE * 0.5, 30.0, 500.0)
	var r_bed := maxf(r, w.cell * 0.6)
	var depth: float = float(stroke.get("depth", 2.0)) * clampf(r / w.cell, 0.25, 1.0)
	var reach := r_bed + bank
	var r_vis := r_bed
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
					var bed: float
					if d <= r_bed:
						bed = level - depth * (1.0 - smoothstep(r_bed * 0.3, r_bed, d))
					else:
						bed = level + _bank_rise((d - r_bed) / bank, bank_height)
					if bed < bed_buf[k]:
						bed_buf[k] = bed
				if d < r_vis and level > level_buf[k]:
					level_buf[k] = level
	w.water_bed = bed_buf
	w.water_level = level_buf
	return changed
