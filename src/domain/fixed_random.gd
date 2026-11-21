class_name FixedRandom
extends RefCounted
## Fester Zufall: Aus demselben Ausgangswert entsteht immer dieselbe Folge.
##
## Alles, was Weltwerk erzeugt (Gelände, Bewuchs, Beiwerk), rechnet hiermit – nie mit den
## globalen randi()/randf()/randomize(). So findet der Spielleiter beim nächsten Öffnen dieselbe
## Welt vor, und Tests sehen dasselbe Ergebnis.


## Ein eigener Zufallsgenerator mit festem Ausgangswert.
static func rng_of(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Leitet aus einem Ausgangswert und einer Bezeichnung einen neuen, festen Ausgangswert ab –
## etwa für „Hügel“ und „Berge“ eines Geländes, damit sich die Teile nicht gegenseitig ändern.
static func derive(seed_value: int, label: String) -> int:
	return ("%d/%s" % [seed_value, label]).hash()


## Rauschen (für Gelände und Bewuchs) mit festem Ausgangswert.
static func noise_of(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	return noise
