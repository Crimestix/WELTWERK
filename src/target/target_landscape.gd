class_name TargetLandscape
extends RefCounted
## Landschaft der Zielszene, aufgebaut wie das bestätigte Zielbild: Hügel links hinten,
## sonnige Wiese fällt nach rechts zum See ab, Uferlinie schräg von hinten Mitte nach vorn
## rechts, flache Uferzone mit Steinen, dahinter Wald auf ansteigenden Hügeln.
##
## Reine Fachlogik: Höhen und Platzierungen, alles aus festem Zufall. Koordinaten in Metern,
## x nach rechts (Osten), z nach vorn zur Kamera (Süden), Wasserspiegel auf Höhe 0.

const EXTENT := 640.0
const SPACING := 1.0
const SEED := 2111
const HILL := Vector2(-75.0, -105.0)
## Gestalteter Kern (davor/dahinter Hintergrund).
const CORE := Rect2(-150.0, -170.0, 280.0, 260.0)

var _shore_noise: FastNoiseLite
var _detail: FastNoiseLite
var _fine: FastNoiseLite
var _hills: FastNoiseLite
var _bottom: FastNoiseLite


func _init() -> void:
	_shore_noise = _make("Ufer", 1.0 / 32.0, 4)
	_detail = _make("Feinheit", 1.0 / 24.0, 4)
	_fine = _make("Kleinstes", 1.0 / 4.5, 2)
	_hills = _make("Hügel", 1.0 / 160.0, 3)
	_bottom = _make("Seegrund", 1.0 / 9.0, 2)


func _make(label: String, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FixedRandom.noise_of(FixedRandom.derive(SEED, label))
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = frequency
	return n


## x-Lage der Uferlinie bei Tiefe z (rechts davon liegt der See).
func shore_x(z: float) -> float:
	return 20.0 + 0.38 * z + 13.0 * _shore_noise.get_noise_1d(z)


## Abstand zur Uferlinie: positiv im See, negativ an Land (in x gemessen).
func shore_distance(x: float, z: float) -> float:
	return x - shore_x(z)


func height(x: float, z: float) -> float:
	var d := shore_distance(x, z)
	var inland := maxf(-d, 0.0)
	var land := 1.2 + inland * 0.16 + minf(inland, 10.0) * 0.09
	land += 34.0 * exp(-Vector2(x, z).distance_squared_to(HILL) / (2.0 * 48.0 * 48.0))
	# Hintergrund: ansteigende, bewaldete Hügel hinten und links.
	var back := smoothstep(170.0, 290.0, -z) + smoothstep(170.0, 300.0, -x) * 0.7
	land += back * (75.0 + 30.0 * _hills.get_noise_2d(x, z))
	land += 0.7 * _detail.get_noise_2d(x, z) * smoothstep(0.0, 8.0, inland)
	land += 0.12 * _fine.get_noise_2d(x, z)
	var lake := -0.25 - 1.6 * smoothstep(0.0, 16.0, d) - 9.0 * smoothstep(16.0, 50.0, d)
	lake += 0.35 * _bottom.get_noise_2d(x, z) * (1.0 - smoothstep(10.0, 25.0, d))
	# Gegenüberliegendes Ufer hinten rechts mit bewaldeten Hügeln.
	var across := d - 0.3 * (z + 100.0)
	var far_shore := smoothstep(130.0, 160.0, across)
	lake = lerpf(lake, 3.0 + 70.0 * smoothstep(160.0, 280.0, across) + 12.0 * _hills.get_noise_2d(x * 1.5, z), far_shore)
	# Hinten schließt der See ab: bewaldete Hügel statt Wasser bis zum Horizont.
	var lake_end := smoothstep(195.0, 235.0, -z)
	lake = lerpf(lake, 4.0 + 60.0 * smoothstep(225.0, 300.0, -z) + 12.0 * _hills.get_noise_2d(x, z * 1.3), lake_end)
	return lerpf(land, lake, smoothstep(-1.2, 1.6, d))


func build() -> Heightfield:
	var count := int(round(EXTENT / SPACING)) + 1
	var field := Heightfield.new(count, count, SPACING)
	field.seed_value = SEED
	var heights := field.heights
	for row in field.rows:
		var z := field.origin.y + row * SPACING
		for column in field.columns:
			heights[row * field.columns + column] = height(field.origin.x + column * SPACING, z)
	field.heights = heights
	return field


# --- Platzierung ---------------------------------------------------------------------------

## Einzelbäume auf Wiese und Hügel, locker verteilt. Ergebnis: [Transform3D, Art (0 Eiche, 1 Buche, 2 jung)].
func trees() -> Array:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Bäume"))
	var points := _scatter(rng, 30000, 46, 15.0, func(p: Vector2) -> bool:
		var d := shore_distance(p.x, p.y)
		if d > -11.0 or not CORE.has_point(p):
			return false
		# Flanken des Hügels und hinten am Ufer; Kuppe und Vordergrund offene Wiese.
		var r := p.distance_to(HILL)
		var flank := exp(-pow((r - 45.0) / 30.0, 2.0))
		var back := smoothstep(-40.0, -110.0, p.y) * smoothstep(-60.0, -15.0, d)
		var open_front := smoothstep(-50.0, 10.0, p.y)
		return rng.randf() < (0.1 + 0.75 * flank + 0.45 * back) * (1.0 - 0.8 * open_front))
	var result := []
	for p in points:
		var kind := 0 if rng.randf() < 0.45 else (1 if rng.randf() < 0.55 else 2)
		result.append([_upright(rng, p, 0.9, 1.2, -0.2), kind])
	return result


## Wald im Hintergrund (dicht).
func background_trees() -> Array:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Wald"))
	var points := _scatter(rng, 140000, 6500, 4.6, func(p: Vector2) -> bool:
		var d := shore_distance(p.x, p.y)
		var behind := p.y < -175.0 or p.x < -160.0 or (p.y < -205.0 and d > 0.0)
		var far_shore := d - 0.3 * (p.y + 100.0) > 158.0
		if not (behind or far_shore):
			return false
		return (d < -6.0 or far_shore or p.y < -205.0) and height(p.x, p.y) > 2.5, Rect2(-310.0, -310.0, 620.0, 620.0))
	var result := []
	for p in points:
		result.append([_upright(rng, p, 1.0, 1.45, -0.2), 3])
	return result


func bushes() -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Büsche"))
	var points := _scatter(rng, 30000, 140, 3.0, func(p: Vector2) -> bool:
		var d := shore_distance(p.x, p.y)
		return CORE.has_point(p) and d < -2.0 and (d > -14.0 or rng.randf() < 0.45))
	var result: Array[Transform3D] = []
	for p in points:
		result.append(_upright(rng, p, 1.2, 2.4, -0.15))
	return result


## Granitbänke entlang des Ufers, halb im Wasser, längs zur Uferlinie gedreht.
func ledges() -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Felsbänke"))
	var result: Array[Transform3D] = []
	var z := -165.0
	while z < 80.0:
		# Mal eine Bank, mal zwei, drei übereinander gestaffelt; dazwischen kurze Lücken.
		var group := rng.randi_range(1, 3)
		for g in group:
			var x := shore_x(z) + rng.randf_range(-5.0, 1.0) - g * 2.5
			var direction := Vector2(shore_x(z + 1.0) - shore_x(z), 1.0).normalized()
			var yaw := atan2(direction.x, direction.y) + PI * 0.5 + rng.randf_range(-0.45, 0.45)
			var s := rng.randf_range(0.8, 1.6)
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
			basis = basis.scaled(Vector3(s, s * rng.randf_range(0.9, 1.4), s))
			var ground := maxf(height(x, z), -0.6)
			result.append(Transform3D(basis, Vector3(x, ground - rng.randf_range(0.25, 0.6) * s, z + rng.randf_range(-1.5, 1.5))))
		z += rng.randf_range(3.0, 7.5) * (1.6 if rng.randf() < 0.2 else 1.0)
	return result


func boulders() -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Findlinge"))
	var points := _scatter(rng, 20000, 60, 4.0, func(p: Vector2) -> bool:
		var d := shore_distance(p.x, p.y)
		return CORE.has_point(p) and d < 3.0 and (d > -12.0 or rng.randf() < 0.25))
	var result: Array[Transform3D] = []
	for p in points:
		result.append(_tumbled(rng, p, 0.8, 2.0, -0.35))
	return result


## Steine im flachen Wasser (sichtbar durch das klare Wasser).
func stones() -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Steine"))
	var points := _scatter(rng, 40000, 420, 1.3, func(p: Vector2) -> bool:
		var d := shore_distance(p.x, p.y)
		return CORE.has_point(p) and d > -0.5 and d < 17.0)
	var result: Array[Transform3D] = []
	for p in points:
		result.append(_tumbled(rng, p, 0.8, 3.0, -0.15))
	return result


## Grasbüschel: [Transform3D, Atlaszelle 0–7, Trockenheit 0–1]. Dicht im Kern.
func grass(count: int) -> Array:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Gras"))
	var dry_noise := _make("Trockenstellen", 1.0 / 30.0, 3)
	var result := []
	var area := CORE.grow(-5.0)
	var tries := count * 3
	while result.size() < count and tries > 0:
		tries -= 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if shore_distance(p.x, p.y) > -1.8:
			continue
		var dry := clampf(dry_noise.get_noise_2d(p.x, p.y) * 2.5 - 0.55, 0.0, 1.0)
		result.append([_upright(rng, p, 0.9, 1.7, -0.02), rng.randi_range(0, 7), dry])
	return result


## Wildblumen in Flecken: [Transform3D, Atlaszelle 0–7].
func flowers(count: int) -> Array:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Blumen"))
	var patches := _make("Blumenflecken", 1.0 / 18.0, 2)
	var result := []
	var area := CORE.grow(-5.0)
	var tries := count * 8
	while result.size() < count and tries > 0:
		tries -= 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if shore_distance(p.x, p.y) > -2.5:
			continue
		# Locker gestreut, in Flecken etwas häufiger.
		if rng.randf() > 0.25 + 0.5 * smoothstep(0.0, 0.5, patches.get_noise_2d(p.x, p.y)):
			continue
		# Meist gelbe und weiße Blumen (Hahnenfuß, Schafgarbe, Margerite, Habichtskraut),
		# seltener Blutweiderich, Klee, Kornblume, Flockenblume; gleiche Art in einem Flecken.
		const COMMON := [0, 1, 3, 6]
		const RARE := [2, 4, 5, 7]
		var pick := int(floor((patches.get_noise_2d(p.x * 0.3 + 50.0, p.y * 0.3) * 0.5 + 0.5) * 4.0)) % 4
		if rng.randf() < 0.3:
			pick = rng.randi_range(0, 3)
		var kind: int = COMMON[pick] if rng.randf() < 0.8 else RARE[pick]
		result.append([_upright(rng, p, 0.9, 1.5, -0.02), kind])
	return result


func _upright(rng: RandomNumberGenerator, p: Vector2, s0: float, s1: float, sink: float) -> Transform3D:
	var s := rng.randf_range(s0, s1)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
	return Transform3D(basis, Vector3(p.x, height(p.x, p.y) + sink * s, p.y))


func _tumbled(rng: RandomNumberGenerator, p: Vector2, s0: float, s1: float, sink: float) -> Transform3D:
	var s := rng.randf_range(s0, s1)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
	basis = basis.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s))
	return Transform3D(basis, Vector3(p.x, height(p.x, p.y) + sink * s, p.y))


func _scatter(rng: RandomNumberGenerator, tries: int, limit: int, min_distance: float, accept: Callable,
		area: Rect2 = CORE) -> Array[Vector2]:
	# Gitter für schnelle Abstandsprüfung.
	var cell := min_distance
	var grid := {}
	var points: Array[Vector2] = []
	for i in tries:
		if points.size() >= limit:
			break
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if not accept.call(p):
			continue
		var key := Vector2i(floor(p.x / cell), floor(p.y / cell))
		var free := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for q in grid.get(key + Vector2i(dx, dy), []):
					if p.distance_to(q) < min_distance:
						free = false
		if free:
			points.append(p)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(p)
	return points
