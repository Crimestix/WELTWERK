class_name StyleLandscape
extends RefCounted
## Die kleine Landschaft für den Stiltest: Hügel, Felsufer, See, Wiese und Baumgruppe.
##
## Reine Fachlogik. Die grobe Form ist hier fest beschrieben, Feinheiten und Verteilung
## kommen aus festem Zufall. Beide Varianten (A und B) nutzen genau dieselbe Form und dieselben
## Positionen, damit nur der Bestand den Unterschied macht.

## Gesamtfläche; der gestaltete Teil liegt innerhalb von ±CORE, außen fällt das Land ins Wasser.
const EXTENT := 260.0
const CORE := 85.0
const SPACING := 0.5
const SEED := 2026

const HILL := Vector2(-40.0, -36.0)
const LAKE := Vector2(34.0, 30.0)
const GROVE := Vector2(-20.0, -12.0)
const GROVE_RADIUS := 17.0
## Felsbank am Seeufer, als Strecke.
const BANK_FROM := Vector2(2.0, -4.0)
const BANK_TO := Vector2(30.0, 4.0)


static func build() -> Heightfield:
	var count := int(round(EXTENT / SPACING)) + 1
	var field := Heightfield.new(count, count, SPACING)
	field.seed_value = SEED

	var detail := FixedRandom.noise_of(FixedRandom.derive(SEED, "Feinheit"))
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 5
	detail.frequency = 1.0 / 22.0

	var shore := FixedRandom.noise_of(FixedRandom.derive(SEED, "Ufer"))
	shore.frequency = 1.0 / 14.0
	shore.fractal_octaves = 3

	var rock := FixedRandom.noise_of(FixedRandom.derive(SEED, "Fels"))
	rock.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	rock.frequency = 1.0 / 7.0
	rock.fractal_octaves = 3

	for row in field.rows:
		var z := field.origin.y + row * SPACING
		for column in field.columns:
			var x := field.origin.x + column * SPACING
			var p := Vector2(x, z)
			var h := 2.2
			h += 16.0 * exp(-p.distance_squared_to(HILL) / (2.0 * 30.0 * 30.0))
			h += 0.9 * detail.get_noise_2d(x, z)
			# Felsbank: steile Kante zum See hin.
			var bank_distance := _distance_to_segment(p, BANK_FROM, BANK_TO)
			var bank := exp(-pow(bank_distance / 6.0, 2.0))
			h += bank * (2.5 + 2.0 * (rock.get_noise_2d(x, z) * 0.5 + 0.5))
			# See: Ufer mit unregelmäßiger Linie, auf der Felsseite steiler.
			var lake_distance := p.distance_to(LAKE) + shore.get_noise_2d(x, z) * 7.0
			var steep := lerpf(1.0, 0.35, bank)
			var water := 1.0 - smoothstep(22.0, 22.0 + 20.0 * steep, lake_distance)
			h = lerpf(h, -7.0, water)
			# Außerhalb des gestalteten Teils sanft ins Wasser abfallen.
			var edge := maxf(absf(x), absf(z)) + shore.get_noise_2d(x * 0.5, z * 0.5) * 12.0
			h = lerpf(h, -3.0, smoothstep(CORE + 6.0, CORE + 20.0, edge))
			h = lerpf(h, -30.0, smoothstep(CORE + 20.0, CORE + 36.0, edge))
			field.heights[row * field.columns + column] = h
	return field


## Baumgruppe auf der Hügelflanke: Abstand mindestens 4,5 m.
static func trees(field: Heightfield) -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Bäume"))
	var points := _scatter(rng, 6000, 24, 4.5, func(p: Vector2) -> bool:
		return p.distance_to(GROVE) < GROVE_RADIUS and field.height_at(p.x, p.y) > 1.5)
	return _transforms(field, rng, points, 0.85, 1.2, -0.25, false)


## Büsche am Rand der Baumgruppe und vereinzelt am Ufer.
static func shrubs(field: Heightfield) -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Büsche"))
	var points := _scatter(rng, 6000, 40, 2.6, func(p: Vector2) -> bool:
		var d := p.distance_to(GROVE)
		var h := field.height_at(p.x, p.y)
		return (d > GROVE_RADIUS - 3.0 and d < GROVE_RADIUS + 9.0 and h > 1.2) \
			or (h > 0.6 and h < 2.0 and p.distance_to(LAKE) < 40.0))
	return _transforms(field, rng, points, 0.7, 1.3, -0.1, false)


## Felsen entlang der Felsbank und der Uferlinie daneben.
static func rocks(field: Heightfield) -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Felsen"))
	var points := _scatter(rng, 8000, 46, 2.0, func(p: Vector2) -> bool:
		var h := field.height_at(p.x, p.y)
		var near_bank := _distance_to_segment(p, BANK_FROM, BANK_TO) < 9.0
		var on_shore := h > -1.0 and h < 1.4 and p.distance_to(LAKE) < 46.0 and p.x < 40.0
		return near_bank or (on_shore and rng.randf() < 0.35))
	return _transforms(field, rng, points, 0.6, 1.9, -0.35, true)


## Grasbüschel auf der Wiese (flach, über Wasser, nicht unter den Bäumen).
static func grass(field: Heightfield, count: int = 6000) -> Array[Transform3D]:
	var rng := FixedRandom.rng_of(FixedRandom.derive(SEED, "Gras"))
	var points: Array[Vector2] = []
	var tries := count * 4
	var half := CORE
	while points.size() < count and tries > 0:
		tries -= 1
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var h := field.height_at(p.x, p.y)
		if h < 0.5 or h > 14.0:
			continue
		if p.distance_to(GROVE) < GROVE_RADIUS - 4.0:
			continue
		if _distance_to_segment(p, BANK_FROM, BANK_TO) < 6.0:
			continue
		var column := int((p.x - field.origin.x) / field.spacing)
		var row := int((p.y - field.origin.y) / field.spacing)
		if field.normal_at(column, row).y < 0.88:
			continue
		points.append(p)
	return _transforms(field, rng, points, 0.7, 1.4, -0.03, false)


static func _scatter(rng: RandomNumberGenerator, tries: int, limit: int, min_distance: float, accept: Callable) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var half := CORE
	for i in tries:
		if points.size() >= limit:
			break
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if not accept.call(p):
			continue
		var free := true
		for q in points:
			if p.distance_to(q) < min_distance:
				free = false
				break
		if free:
			points.append(p)
	return points


static func _transforms(field: Heightfield, rng: RandomNumberGenerator, points: Array[Vector2],
		min_scale: float, max_scale: float, sink: float, tumble: bool) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for p in points:
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		if tumble:
			basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		var s := rng.randf_range(min_scale, max_scale)
		basis = basis.scaled(Vector3(s, s, s))
		var y := field.height_at(p.x, p.y) + sink * s
		result.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	return result


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
