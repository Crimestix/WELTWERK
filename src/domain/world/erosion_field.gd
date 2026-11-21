class_name ErosionField
extends RefCounted
## Geografisches Erosionsrelief: Grate, Haupttäler und Seitentäler der Gebirge als Teil der Welt.
##
## Quelle sind die selbst erzeugten, nahtlosen Erosionskacheln (assets/map/erosion_*_height.r32,
## tools/blender/make_erosion_tiles.py). Die Kachel liegt in mehreren Größen fest in der Welt
## (Lage und Drehung je Kontinent aus dessen Streu-Ausgangswert) und wird je Ausschnitt nur so fein
## ausgewertet, wie dessen Raster es zeigen kann (Mipmap-Pyramide, weich überblendet). Darum zeigt
## jede grobe Ansicht eine geglättete Fassung derselben Grate und Täler wie die feine.
## Reine Daten und Rechnung, keine Knoten.

const TILE := 1024
const FILES := {"alpine": "res://assets/map/erosion_alpine_height.r32", "hills": "res://assets/map/erosion_hills_height.r32"}
## Größen der Kachel in der Welt (m) und ihr Anteil: große Massive und Haupttäler, Seitentäler,
## Rinnen. Gebirge ("alpine") und Vorberge ("hills").
const ALPINE_SCALES := [[256000.0, 0.62, 0.6], [64000.0, 0.27, 2.1], [16000.0, 0.11, 4.0]]
const HILLS_SCALES := [[64000.0, 0.6, 1.3], [16000.0, 0.4, 3.3]]

static var _pyramids := {}
static var _mutex := Mutex.new()


## Mipmap-Pyramide einer Kachel (Stufe 0 = 1024², jede weitere halb so groß, mit Umlauf).
static func pyramid(name: String) -> Array:
	_mutex.lock()
	if not _pyramids.has(name):
		_pyramids[name] = _build(name)
	var p: Array = _pyramids[name]
	_mutex.unlock()
	return p


static func _build(name: String) -> Array:
	var levels := []
	var bytes := FileAccess.get_file_as_bytes(FILES[name])
	if bytes.size() != TILE * TILE * 4:
		push_error("Erosionskachel fehlt oder ist unvollständig: %s" % FILES[name])
		var flat := PackedFloat32Array()
		flat.resize(1)
		flat[0] = 0.5
		return [flat]
	var level := bytes.to_float32_array()
	var size := TILE
	levels.append(level)
	while size > 1:
		var half := size / 2
		var next := PackedFloat32Array()
		next.resize(half * half)
		for j in half:
			for i in half:
				var a := (2 * j) * size + 2 * i
				next[j * half + i] = (level[a] + level[a + 1] + level[a + size] + level[a + size + 1]) * 0.25
		levels.append(next)
		level = next
		size = half
	return levels


## Wert der Kachel (0–1) an Kachelkoordinate (u, v in Texeln der Stufe 0), Mipmap-Stufe lod.
static func sample(levels: Array, u: float, v: float, lod: float) -> float:
	var top := levels.size() - 1
	lod = clampf(lod, 0.0, float(top))
	var l0 := int(floor(lod))
	var t := lod - l0
	var a := _bilinear(levels[l0], TILE >> l0, u / float(1 << l0), v / float(1 << l0))
	if t <= 0.0 or l0 >= top:
		return a
	var b := _bilinear(levels[l0 + 1], TILE >> (l0 + 1), u / float(1 << (l0 + 1)), v / float(1 << (l0 + 1)))
	return lerpf(a, b, t)


static func _bilinear(data: PackedFloat32Array, size: int, u: float, v: float) -> float:
	if size <= 1:
		return data[0]
	u -= 0.5
	v -= 0.5
	var fu := floorf(u)
	var fv := floorf(v)
	var tx := u - fu
	var ty := v - fv
	var i0 := posmod(int(fu), size)
	var j0 := posmod(int(fv), size)
	var i1 := (i0 + 1) % size
	var j1 := (j0 + 1) % size
	var top := lerpf(data[j0 * size + i0], data[j0 * size + i1], tx)
	var bottom := lerpf(data[j1 * size + i0], data[j1 * size + i1], tx)
	return lerpf(top, bottom, ty)


## Lage der Kachelgrößen eines Kontinents: [[Größe m, Anteil, cos, sin, Versatz u, Versatz v], …].
static func placements(scales: Array, seed_value: int) -> Array:
	var out := []
	var k := 0
	for s in scales:
		var rng := FixedRandom.rng_of(FixedRandom.derive(seed_value, "Relief %d" % k))
		var angle: float = s[2] + rng.randf_range(-0.4, 0.4)
		out.append([s[0], s[1], cos(angle), sin(angle), rng.randf() * TILE, rng.randf() * TILE])
		k += 1
	return out


## Für ein Raster der Weite cell vorbereiten (Mipmap-Stufen je Kachelgröße stehen für den ganzen
## Ausschnitt fest): [[1/Texelgröße, cos, sin, Versatz u, Versatz v, Anteil, Daten a, Größe a,
## Daten b, Größe b, Mischung], …]. Texel mindestens zwei Zellen groß – nur, was das Raster trägt.
static func prepare(levels: Array, placed: Array, cell: float, first: int = 0, count: int = 99) -> Array:
	var out := []
	var total := 0.0
	for p in placed:
		total += float(p[1])
	var top := levels.size() - 1
	for idx in range(first, mini(first + count, placed.size())):
		var p: Array = placed[idx]
		var size: float = p[0]
		# Texel etwa eine Zelle: so fein, wie das Raster trägt (Mittel der feinen Stufe über eine Zelle).
		var lod := clampf(log(maxf(cell * TILE / size, 1.0)) / log(2.0), 0.0, float(top))
		var l0 := int(floor(lod))
		var l1 := mini(l0 + 1, top)
		out.append([float(TILE) / size, p[2], p[3], p[4], p[5], float(p[1]) / total,
			levels[l0], TILE >> l0, levels[l1], TILE >> l1, lod - l0])
	return out


## Summe der Kachelgrößen an (x, y) (m) für ein vorbereitetes Raster, um die Mitte: Anteil je
## Größe mal (Kachelwert − 0,5). Alle Größen zusammen ergeben −0,5 … +0,5.
static func value_prepared(prep: Array, x: float, y: float) -> float:
	var v := 0.0
	for p in prep:
		var k: float = p[0]
		var u: float = (x * p[1] - y * p[2]) * k + p[3]
		var w: float = (x * p[2] + y * p[1]) * k + p[4]
		var size_a: int = p[7]
		var a := _bilinear(p[6], size_a, u * size_a / TILE, w * size_a / TILE)
		var t: float = p[10]
		if t > 0.001:
			var size_b: int = p[9]
			a = lerpf(a, _bilinear(p[8], size_b, u * size_b / TILE, w * size_b / TILE), t)
		v += (a - 0.5) * p[5]
	return v


## Summe der Kachelgrößen an (x, y) (m), geglättet für ein Raster der Weite cell (m): 0–1, Mitte 0,5.
static func value(levels: Array, placed: Array, x: float, y: float, cell: float) -> float:
	return value_prepared(prepare(levels, placed, cell), x, y) + 0.5
