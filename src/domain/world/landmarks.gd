class_name Landmarks
extends RefCounted
## Markante Geländestellen in einem Ausschnitt finden und auf jeder Stufe einordnen (reine
## Funktionen, nur Höhendaten eines TerrainWindow, keine Szenen). Genutzt von der Ortsprüfung
## (LandmarkRun, --orte): Gipfel, Pass (Joch auf dem Hauptkamm) und Talgrund an festen Stellen
## des Kontinents, verglichen über Kontinent-, Regions- und Detailstufe.
##
## Begriffe: Ein Gipfel ist der höchste Punkt eines großen Massivs. Ein Pass ist das Joch (der
## Sattel) auf dem höchsten Verbindungsweg zwischen dem Gipfel und einem anderen hohen Gipfel –
## der tiefste Punkt der Kammlinie dazwischen. Ein Talgrund ist die am stärksten eingetiefte
## Stelle eines langen Tals (beide Talseiten deutlich höher, auch einige Kilometer talauf und
## talab), weit genug von der Küste.

## Auflösung: Eine Form gilt auf einer Stufe als darstellbar, wenn ihre Größe (Radius) mindestens
## 1,5 Rasterzellen beträgt – Formen unter etwa 3 Zellen Durchmesser dürfen geglättet sein.
const RESOLVE_CELLS := 1.5
## Wie viel der Form auf einer gröberen Stufe mindestens erhalten bleiben muss.
const KEEP_SHARE := 0.3
const GOLDEN := 2.399963


# --- Hilfen ----------------------------------------------------------------------------------

static func index_of(w: TerrainWindow, p: Vector2) -> int:
	var g := w.grid_of(p.x, p.y)
	var i := clampi(int(round(g.x)), 0, w.res - 1)
	var j := clampi(int(round(g.y)), 0, w.res - 1)
	return j * w.res + i


static func point_of(w: TerrainWindow, k: int) -> Vector2:
	return Vector2(w.x_at(k % w.res), w.y_at(k / w.res))


## Gibt es dort Binnenwasser (See, Fluss) über dem Grund?
static func is_wet(w: TerrainWindow, k: int) -> bool:
	return w.water_level[k] > w.height[k]


## Mittlere Höhe auf einem Kreis (n Punkte).
static func ring_mean(w: TerrainWindow, p: Vector2, r: float, n: int = 32) -> float:
	var sum := 0.0
	for k in n:
		var a := TAU * k / n
		sum += w.height_at(p.x + cos(a) * r, p.y + sin(a) * r)
	return sum / n


## Höchst- und Tiefstwert in einer Kreisscheibe (Sonnenblumenmuster, n Punkte plus Mitte).
static func disc_range(w: TerrainWindow, p: Vector2, r: float, n: int = 64) -> Vector2:
	var lo := w.height_at(p.x, p.y)
	var hi := lo
	for k in n:
		var a := k * GOLDEN
		var q := p + Vector2(cos(a), sin(a)) * r * sqrt((k + 0.5) / n)
		var v := w.height_at(q.x, q.y)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(lo, hi)


## Mittel aus beiden Richtungen ±d·u minus Höhe in p (positiv: beidseits höher).
static func two_sided(w: TerrainWindow, p: Vector2, u: Vector2, d: float) -> float:
	var a := p + u * d
	var b := p - u * d
	return (w.height_at(a.x, a.y) + w.height_at(b.x, b.y)) * 0.5 - w.height_at(p.x, p.y)


## Achsen einer Stelle: rise = Richtung, in der es beidseits am stärksten ansteigt (beim Pass der
## Kamm, beim Tal quer zum Tal), fall = senkrecht dazu. Werte in Metern beim Abstand d.
static func axes(w: TerrainWindow, p: Vector2, d: float) -> Dictionary:
	var best := -INF
	var dir := Vector2.RIGHT
	for k in 16:
		var a := PI * k / 16.0
		var u := Vector2(cos(a), sin(a))
		var v := two_sided(w, p, u, d)
		if v > best:
			best = v
			dir = u
	var across := Vector2(-dir.y, dir.x)
	return {"rise": dir, "fall": across, "rise_m": best, "fall_m": two_sided(w, p, across, d)}


# --- Gipfel ----------------------------------------------------------------------------------

## Mitte des größten Massivs: Höhen (über dem Meer) über eine Kreisfläche gemittelt, dort das Maximum.
static func massif_center(w: TerrainWindow, radius: float) -> Vector2:
	var res := w.res
	var h := w.height
	var r := maxi(1, int(round(radius / w.cell)))
	# Laufende Summen: erst je Zeile, dann je Spalte (Kastenfilter).
	var rows := PackedFloat32Array()
	rows.resize(res * res)
	for j in res:
		var prefix := PackedFloat64Array()
		prefix.resize(res + 1)
		prefix[0] = 0.0
		for i in res:
			prefix[i + 1] = prefix[i] + maxf(h[j * res + i], 0.0)
		for i in res:
			rows[j * res + i] = prefix[mini(i + r, res - 1) + 1] - prefix[maxi(i - r, 0)]
	var best := -INF
	var best_k := 0
	for i in res:
		var prefix := PackedFloat64Array()
		prefix.resize(res + 1)
		prefix[0] = 0.0
		for j in res:
			prefix[j + 1] = prefix[j] + rows[j * res + i]
		for j in res:
			var v := prefix[mini(j + r, res - 1) + 1] - prefix[maxi(j - r, 0)]
			if v > best:
				best = v
				best_k = j * res + i
	return point_of(w, best_k)


## Höchster Rasterpunkt in einer Kreisscheibe.
static func highest_in(w: TerrainWindow, center: Vector2, radius: float) -> Vector2:
	var k := _extreme_in(w, center, radius, true)
	return point_of(w, k) if k >= 0 else center


## Tiefster Rasterpunkt einer Kreisscheibe auf Land ohne Binnenwasser (Talgrund, nicht Seeboden).
static func lowest_in(w: TerrainWindow, center: Vector2, radius: float) -> Vector2:
	var k := _extreme_in(w, center, radius, false)
	return point_of(w, k) if k >= 0 else center


static func _extreme_in(w: TerrainWindow, center: Vector2, radius: float, highest: bool) -> int:
	var res := w.res
	var h := w.height
	var lvl := w.water_level
	var g := w.grid_of(center.x, center.y)
	var rc := radius / w.cell
	var best := -INF if highest else INF
	var best_k := -1
	for j in range(maxi(0, int(floor(g.y - rc))), mini(res - 1, int(ceil(g.y + rc))) + 1):
		for i in range(maxi(0, int(floor(g.x - rc))), mini(res - 1, int(ceil(g.x + rc))) + 1):
			if Vector2(i, j).distance_to(g) > rc:
				continue
			var k := j * res + i
			var v := h[k]
			if highest:
				if v > best:
					best = v
					best_k = k
			elif v > 2.0 and lvl[k] <= v and v < best:
				best = v
				best_k = k
	return best_k


# --- Pass ------------------------------------------------------------------------------------

## Fluten von oben: Rasterpunkte nach fallender Höhe hinzufügen und zu Gebieten verbinden. Für
## jeden Kandidaten der Rasterpunkt, an dem sein Gebiet zuerst mit dem von start zusammenwächst –
## das Joch des höchsten Verbindungswegs (-1: im Ausschnitt nie verbunden).
static func connecting_cols(w: TerrainWindow, start: int, candidates: PackedInt32Array) -> PackedInt32Array:
	var res := w.res
	var n := res * res
	var h := w.height
	var keys := PackedInt64Array()
	keys.resize(n)
	for k in n:
		keys[k] = (int(round((clampf(h[k], -20000.0, 20000.0) + 20000.0) * 100.0)) << 21) | k
	keys.sort()
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var result := PackedInt32Array()
	result.resize(candidates.size())
	result.fill(-1)
	# Kandidaten je Gebiet (Schlüssel: Wurzel), nur für Gebiete, die start noch nicht erreicht haben.
	var waiting := {}
	for c in candidates.size():
		var cell := candidates[c]
		if cell == start:
			result[c] = start
			continue
		if not waiting.has(cell):
			waiting[cell] = []
		(waiting[cell] as Array).append(c)
	var offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	for idx in range(n - 1, -1, -1):
		var k := int(keys[idx] & 0x1FFFFF)
		parent[k] = k
		var i := k % res
		var j := k / res
		for o in offsets:
			var ni: int = i + o.x
			var nj: int = j + o.y
			if ni < 0 or nj < 0 or ni >= res or nj >= res:
				continue
			var nk := nj * res + ni
			if parent[nk] == -1:
				continue
			var a := _root(parent, k)
			var b := _root(parent, nk)
			if a == b:
				continue
			var s := _root(parent, start) if parent[start] != -1 else -1
			parent[b] = a
			var list_a: Array = waiting.get(a, [])
			var list_b: Array = waiting.get(b, [])
			waiting.erase(a)
			waiting.erase(b)
			if s == a or s == b:
				# Das andere Gebiet erreicht start genau hier.
				for c in (list_b if s == a else list_a):
					result[c] = k
			else:
				list_a.append_array(list_b)
				if not list_a.is_empty():
					waiting[a] = list_a
	return result


static func _root(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k


## Lokale Höchstpunkte (höher als alle Punkte im Umkreis von reach Zellen).
static func local_maxima(w: TerrainWindow, reach: int = 2) -> PackedInt32Array:
	var res := w.res
	var h := w.height
	var out := PackedInt32Array()
	for j in range(reach, res - reach):
		for i in range(reach, res - reach):
			var v := h[j * res + i]
			if v <= 2.0:
				continue
			var top := true
			for dj in range(-reach, reach + 1):
				for di in range(-reach, reach + 1):
					if (di != 0 or dj != 0) and h[(j + dj) * res + i + di] >= v:
						top = false
						break
				if not top:
					break
			if top:
				out.append(j * res + i)
	return out


## Pass am Gipfel: unter allen anderen hohen Gipfeln (mindestens min_distance entfernt, mindestens
## prominence über dem Joch) der mit dem höchsten Joch – das ist der Hauptkamm. Ergebnis
## {"col", "partner": Vector2, "col_height", "partner_height"}; leer, wenn keiner gefunden.
static func find_pass(w: TerrainWindow, peak: Vector2, min_distance: float, prominence: float = 120.0) -> Dictionary:
	var start := index_of(w, peak)
	var candidates := local_maxima(w)
	var cols := connecting_cols(w, start, candidates)
	var h := w.height
	var best := -INF
	var found := {}
	for c in candidates.size():
		var col := cols[c]
		if col < 0 or col == start:
			continue
		var partner := point_of(w, candidates[c])
		if partner.distance_to(peak) < min_distance:
			continue
		if h[candidates[c]] - h[col] < prominence or h[col] <= 2.0:
			continue
		if h[col] > best:
			best = h[col]
			found = {"col": point_of(w, col), "partner": partner, "col_height": h[col], "partner_height": h[candidates[c]]}
	return found


## Joch genauer bestimmen: zwei Kammstücke beiderseits (± arm entlang axis, je höchster Punkt in
## einer Scheibe mit radius) und deren höchster Verbindungsweg im feineren Ausschnitt.
static func refine_col(w: TerrainWindow, center: Vector2, axis: Vector2, arm: float, radius: float) -> Vector2:
	var a := index_of(w, highest_in(w, center + axis * arm, radius))
	var b := index_of(w, highest_in(w, center - axis * arm, radius))
	var cols := connecting_cols(w, a, PackedInt32Array([b]))
	return point_of(w, cols[0]) if cols[0] >= 0 else center


# --- Tal -------------------------------------------------------------------------------------

## Abstand zur Meeresküste (m) je Rasterpunkt (Fasenabstand; Meer = Höhe unter 0).
static func coast_distance(w: TerrainWindow) -> PackedFloat32Array:
	var res := w.res
	var h := w.height
	var d := PackedFloat32Array()
	d.resize(res * res)
	var big := 1e12
	for k in res * res:
		d[k] = 0.0 if h[k] < 0.0 else big
	var c := w.cell
	var diag := c * sqrt(2.0)
	for j in res:
		for i in res:
			var k := j * res + i
			var v := d[k]
			if i > 0:
				v = minf(v, d[k - 1] + c)
			if j > 0:
				v = minf(v, d[k - res] + c)
				if i > 0:
					v = minf(v, d[k - res - 1] + diag)
				if i < res - 1:
					v = minf(v, d[k - res + 1] + diag)
			d[k] = v
	for j in range(res - 1, -1, -1):
		for i in range(res - 1, -1, -1):
			var k := j * res + i
			var v := d[k]
			if i < res - 1:
				v = minf(v, d[k + 1] + c)
			if j < res - 1:
				v = minf(v, d[k + res] + c)
				if i < res - 1:
					v = minf(v, d[k + res + 1] + diag)
				if i > 0:
					v = minf(v, d[k + res - 1] + diag)
			d[k] = v
	return d


## Talgrund: Rasterpunkt, an dem beide Talseiten im Abstand span am deutlichsten höher sind – und
## zwar auch length talauf und talab (lange Rinne, kein einzelnes Loch). Nur Land ohne Binnenwasser,
## mindestens min_coast von der Küste (Abstand aus coast_window/coast). Ergebnis {"point",
## "depth", "across": Vector2 (quer zum Tal), "along"}; leer, wenn nichts gefunden.
static func find_valley(w: TerrainWindow, coast_window: TerrainWindow, coast: PackedFloat32Array,
		span: float, length: float, min_coast: float) -> Dictionary:
	var res := w.res
	var h := w.height
	var lvl := w.water_level
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	var perps := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(1, 1)]
	var steps := []
	var runs := []
	for k in 4:
		var scale := 1.0 if k < 2 else sqrt(2.0)
		steps.append(maxi(1, int(round(span / (w.cell * scale)))))
		runs.append(maxi(1, int(round(length / (w.cell * scale)))))
	var margin := 0
	for k in 4:
		margin = maxi(margin, maxi(steps[k], runs[k]) + steps[k])
	var best := 0.0
	var found := {}
	for j in range(margin, res - margin):
		for i in range(margin, res - margin):
			var k := j * res + i
			var v := h[k]
			if v <= 2.0 or lvl[k] > v:
				continue
			for t in 4:
				var u: Vector2i = dirs[t]
				var along: Vector2i = perps[t]
				var s: int = steps[t]
				var l: int = runs[t]
				var score := INF
				for m in [-1, 0, 1]:
					var ci: int = i + along.x * l * m
					var cj: int = j + along.y * l * m
					var c := cj * res + ci
					var side_a := h[(cj + u.y * s) * res + ci + u.x * s]
					var side_b := h[(cj - u.y * s) * res + ci - u.x * s]
					score = minf(score, minf(side_a, side_b) - h[c])
				if score <= best:
					continue
				var p := point_of(w, k)
				if coast[index_of(coast_window, p)] < min_coast:
					continue
				best = score
				found = {"point": p, "depth": score,
					"across": Vector2(u.x, -u.y).normalized(), "along": Vector2(along.x, -along.y).normalized()}
	return found


# --- Formgröße und Einordnung je Stufe -------------------------------------------------------

## Höhenverlauf einer Form über dem Abstand r (positiv = Form ausgeprägt): Gipfel h − Kreismittel,
## Tal und Pass-Kamm Anstieg beidseits entlang axis["rise"], Pass quer Abfall entlang axis["fall"].
static func profile(w: TerrainWindow, kind: String, p: Vector2, axis: Dictionary, r: float, part: String = "") -> float:
	match kind:
		"peak":
			return w.height_at(p.x, p.y) - ring_mean(w, p, r)
		"valley":
			return two_sided(w, p, axis["rise"], r)
	return two_sided(w, p, axis["rise"], r) if part == "rise" else -two_sided(w, p, axis["fall"], r)


## Halbrelief-Radius: kleinster Abstand, in dem der Verlauf die Hälfte seines Höchstwerts (bis
## max_radius) erreicht. Ergebnis [Radius, Höchstwert].
static func _half_radius(w: TerrainWindow, kind: String, p: Vector2, axis: Dictionary, max_radius: float, part: String) -> Array:
	var radii := []
	var r := maxf(w.cell * 2.0, 30.0)
	while r <= max_radius:
		radii.append(r)
		r *= 1.15
	var values := []
	var top := 0.0
	for rr in radii:
		var v := profile(w, kind, p, axis, rr, part)
		values.append(v)
		top = maxf(top, v)
	for k in radii.size():
		if values[k] >= top * 0.5:
			return [radii[k], top]
	return [max_radius, top]


## Größe einer Form aus einem feinen Ausschnitt: Halbrelief-Radius (beim Gipfel: Abstand, in dem
## das Kreismittel um die Hälfte des Gipfelreliefs gefallen ist; beim Tal: quer zum Tal; beim Pass
## der kleinere von Kammanstieg und Querabfall). kind: "peak", "pass", "valley". axis: {"rise",
## "fall"} (Tal: rise = quer, fall = entlang; Pass: rise = Kamm, fall = quer).
static func feature_scale(w: TerrainWindow, kind: String, p: Vector2, axis: Dictionary, max_radius: float) -> Dictionary:
	if kind != "pass":
		var hr := _half_radius(w, kind, p, axis, max_radius, "")
		return {"size": hr[0], "relief": hr[1]}
	var rise := _half_radius(w, kind, p, axis, max_radius, "rise")
	var fall := _half_radius(w, kind, p, axis, max_radius, "fall")
	return {"size": minf(rise[0], fall[0]), "rise_size": rise[0], "fall_size": fall[0], "rise": rise[1], "fall": fall[1],
		"relief": minf(rise[1], fall[1])}


## Ist die Form auf einer Stufe (Ausschnitt w) noch dieselbe? Verglichen wird im Abstand
## r = min(Formgröße, 0,45 × Ausschnitt) mit dem feinen Vergleichsausschnitt ref. Formen unter
## RESOLVE_CELLS Zellen gelten als nicht aufgelöst (dürfen geglättet sein). Sonst gilt:
## – Relief: mindestens KEEP_SHARE des Reliefs von ref im selben Abstand bleibt erhalten (ist es
##   dort schwach oder negativ, etwa bei gekrümmtem Kamm: höchstens 20 m + 10 % darunter);
## – Lage: Gipfel bzw. Talgrund (quer zum Tal) dieser Stufe liegt höchstens eine Rasterzelle
##   (mindestens ¼ der Formgröße) neben der Stelle – oder ist kaum höher bzw. tiefer (Toleranz);
## – Pass: entlang des Kamms steigt es, quer dazu fällt es (beides nach der Reliefregel).
static func classify(w: TerrainWindow, ref: TerrainWindow, kind: String, p: Vector2, scale: Dictionary, axis: Dictionary) -> Dictionary:
	var limit := w.size * 0.45
	var h := w.height_at(p.x, p.y)
	var out := {"cell": w.cell, "height": h}
	var resolved := true
	var ok := true
	var parts := ["rise", "fall"] if kind == "pass" else [""]
	for part in parts:
		var size: float = scale[part + "_size"] if part != "" else scale["size"]
		var r := minf(size, limit)
		var want := profile(ref, kind, p, axis, r, part)
		var kept := profile(w, kind, p, axis, r, part)
		var tol := 20.0 + 0.1 * absf(want)
		var label: String = part if part != "" else "form"
		out[label + "_radius"] = r
		out[label + "_reference"] = want
		out[label + "_kept"] = kept
		if r < RESOLVE_CELLS * w.cell:
			resolved = false
		ok = ok and kept >= minf(KEEP_SHARE * want, want - tol)
		if kind == "pass":
			continue
		# Lage des Gipfels bzw. Talgrunds auf dieser Stufe.
		var reach := maxf(r * 0.5, RESOLVE_CELLS * w.cell)
		var allowed := maxf(w.cell, 0.25 * r)
		var best := p
		var best_h := h
		if kind == "peak":
			for k in 160:
				var q := p + Vector2(cos(k * GOLDEN), sin(k * GOLDEN)) * reach * sqrt((k + 0.5) / 160.0)
				var v := w.height_at(q.x, q.y)
				if v > best_h:
					best_h = v
					best = q
		else:
			var across: Vector2 = axis["rise"]
			for k in range(-24, 25):
				var q := p + across * (reach * k / 24.0)
				var v := w.height_at(q.x, q.y)
				if v < best_h:
					best_h = v
					best = q
		out["offset_m"] = best.distance_to(p)
		out["offset_allowed_m"] = allowed
		out["extreme_height"] = best_h
		out["tolerance_m"] = tol
		ok = ok and (best.distance_to(p) <= allowed or absf(best_h - h) <= tol)
	out["resolved"] = resolved
	out["ok"] = ok
	if not resolved:
		out["note"] = "kleiner als %s Zellen – darf geglättet sein" % String.num(RESOLVE_CELLS * 2.0, 0)
	return out


## Erlaubte Höhenabweichung einer Stufe mit Zellgröße cell an p gegenüber dem feinsten Stand: 20 m
## plus die Hälfte des Reliefs, das diese Stufe nicht mehr auflösen kann (Spannweite im feinen
## Ausschnitt fine innerhalb von 1,5 Zellen).
static func height_tolerance(fine: TerrainWindow, p: Vector2, cell: float) -> float:
	var span := disc_range(fine, p, RESOLVE_CELLS * cell)
	return 20.0 + 0.5 * (span.y - span.x)


## Mittlere Höhe des feinen Ausschnitts über eine Rasterzelle (Kreis mit halber Zellbreite) – so
## sähe eine gröbere Stufe aus, die das Feine nur mittelt.
static func cell_mean(fine: TerrainWindow, p: Vector2, cell: float, n: int = 64) -> float:
	var sum := fine.height_at(p.x, p.y)
	for k in n:
		var q := p + Vector2(cos(k * GOLDEN), sin(k * GOLDEN)) * cell * 0.5 * sqrt((k + 0.5) / n)
		sum += fine.height_at(q.x, q.y)
	return sum / (n + 1)
