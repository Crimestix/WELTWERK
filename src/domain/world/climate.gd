class_name Climate
extends RefCounted
## Einfaches Klima aus Lage und Planeteinstellungen – ein Hinweis, keine Vorgabe.
## Der Spielleiter kann jeden Wert über `climate_override` des Kontinents verschieben.


## Ergebnis: {"snowline", "treeline" (m), "dryness" (0–1), "zone" (Text), "derived" (Grundwerte)}.
static func derive(latitude: float, planet: Dictionary, override: Dictionary) -> Dictionary:
	var lat := absf(latitude)
	var temperature: float = planet.get("temperature_offset", 0.0)
	# Schneegrenze: am Äquator rund 4800 m, zu den Polen hin bis auf Meereshöhe; je Grad Wärme +150 m.
	var snowline := 4800.0 * pow(cos(deg_to_rad(minf(lat, 89.0))), 1.4) + temperature * 150.0
	# Trockenheit: Wendekreis-Wüstengürtel um 27°, feuchte Tropen, feuchtere mittlere Breiten.
	var dryness := 0.3 + 0.45 * exp(-pow((lat - 27.0) / 9.0, 2.0)) - 0.2 * exp(-pow(lat / 10.0, 2.0))
	var zone := "Polar"
	if lat < 15.0:
		zone = "Tropen"
	elif lat < 35.0:
		zone = "Subtropen, trocken" if dryness > 0.55 else "Subtropen"
	elif lat < 55.0:
		zone = "Gemäßigt"
	elif lat < 68.0:
		zone = "Kühl"
	var derived := {"snowline": snowline, "dryness": clampf(dryness, 0.0, 1.0)}
	var snow_final := snowline + float(override.get("snowline_offset", 0.0))
	return {
		"snowline": snow_final,
		"treeline": snow_final - 900.0,
		"dryness": clampf(dryness - float(override.get("humidity_offset", 0.0)), 0.0, 1.0),
		"zone": zone,
		"derived": derived,
	}
