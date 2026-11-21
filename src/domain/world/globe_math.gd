class_name GlobeMath
extends RefCounted
## Rechnung zwischen Globus (Breite, Länge in Grad) und Kontinentkoordinaten (Meter).
##
## Annahme A1: Ein Kontinent ist lokal eben, abgebildet mittabstandstreu um seinen Mittelpunkt
## (Breite lat0, Länge lon0), gedreht um seine Ausrichtung (Grad im Uhrzeigersinn von Norden).
## Einheitsvektor-Konvention (Godot, y nach oben): v = (cos φ sin λ, sin φ, cos φ cos λ).


static func unit_vector(latitude: float, longitude: float) -> Vector3:
	var phi := deg_to_rad(latitude)
	var lam := deg_to_rad(longitude)
	return Vector3(cos(phi) * sin(lam), sin(phi), cos(phi) * cos(lam))


static func latlon_of(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))


## Kontinentkoordinaten (x Osten, y Norden, Meter) → Vector2(Breite, Länge).
static func local_to_latlon(lat0: float, lon0: float, heading: float, x: float, y: float, radius: float) -> Vector2:
	var h := deg_to_rad(heading)
	var e := x * cos(h) + y * sin(h)
	var n := -x * sin(h) + y * cos(h)
	var c := sqrt(e * e + n * n) / radius
	if c < 1e-12:
		return Vector2(lat0, lon0)
	var theta := atan2(e, n)
	var phi0 := deg_to_rad(lat0)
	var phi := asin(clampf(sin(phi0) * cos(c) + cos(phi0) * sin(c) * cos(theta), -1.0, 1.0))
	var lam := atan2(sin(theta) * sin(c) * cos(phi0), cos(c) - sin(phi0) * sin(phi))
	return Vector2(rad_to_deg(phi), wrapf(lon0 + rad_to_deg(lam), -180.0, 180.0))


## Vector2(Breite, Länge) → Kontinentkoordinaten (Meter).
static func latlon_to_local(lat0: float, lon0: float, heading: float, latitude: float, longitude: float, radius: float) -> Vector2:
	var phi0 := deg_to_rad(lat0)
	var phi := deg_to_rad(latitude)
	var dlam := deg_to_rad(longitude - lon0)
	var cos_c := clampf(sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(dlam), -1.0, 1.0)
	var c := acos(cos_c)
	var k := 1.0 if c < 1e-12 else c / sin(c)
	var e := radius * k * cos(phi) * sin(dlam)
	var n := radius * k * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(dlam))
	var h := deg_to_rad(heading)
	return Vector2(e * cos(h) - n * sin(h), e * sin(h) + n * cos(h))
