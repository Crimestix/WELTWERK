class_name WorldDocument
extends RefCounted
## Der Weltstand: Planeteinstellungen und Kontinente mit Lage, Größe, Grundform und Strichliste.
##
## Jede Änderung läuft als Befehl über execute(); daraus entstehen Rückgängig und Wiederholen.
## Befehle verweisen auf die feste ID eines Kontinents, nie auf seinen Listenplatz – so bleibt
## Rückgängig richtig, auch wenn inzwischen Kontinente angelegt oder gelöscht wurden.
## Abgeleitetes (Höhen, Wald, Globusbild, Bäume) wird nie gespeichert, sondern aus diesem Stand
## neu berechnet – deshalb nimmt Rückgängig abgeleitete Änderungen automatisch mit.
## Namen bleiben leer, bis der Spielleiter sie vergibt.

signal changed(command: Dictionary, undone: bool)

const FORMAT := "weltwerk-welt"
const VERSION := 2
## Grundform: aus Ausgangswert erzeugter Fleck oder leer (nur gezeichnete Formen).
const BASE_GENERATED := "generated"
const BASE_DRAWN := "drawn"
## Statt einer Kontinent-ID: Wert des Planeten (z. B. set_command(PLANET, "radius_km", …)).
const PLANET := "@planet"

var planet := {"radius_km": 6371.0, "temperature_offset": 0.0}
var continents: Array = []

var _undo: Array = []
var _redo: Array = []


static func create(seed_value: int) -> WorldDocument:
	var doc := WorldDocument.new()
	doc.continents.append(new_continent(seed_value))
	return doc


static func new_id() -> String:
	return "kontinent-" + Crypto.new().generate_random_bytes(6).hex_encode()


static func new_continent(seed_value: int, base: String = BASE_GENERATED, size_km: float = 1600.0,
		latitude: float = 35.0, longitude: float = 10.0) -> Dictionary:
	return {
		"id": new_id(),
		"name": "",
		"base": base,
		"seed": seed_value,
		## Streuung von Bäumen, Felsen, Gras – bleibt bei einer neuen Variante der Grundform gleich.
		"scatter_seed": FixedRandom.derive(seed_value, "Streuung") & 0x7FFFFFFF,
		"size_km": size_km,
		## Größe, für die die Grundform gilt; beim Skalieren wächst sie mit (Auswertung × size/base).
		"base_size_km": size_km,
		"latitude": latitude,
		"longitude": longitude,
		"heading": 0.0,
		"climate_override": {"snowline_offset": 0.0, "humidity_offset": 0.0},
		"strokes": [],
		"regions": [],
	}


func index_of(id: String) -> int:
	for i in continents.size():
		if continents[i]["id"] == id:
			return i
	return -1


func continent(id: String) -> Dictionary:
	var i := index_of(id)
	return continents[i] if i >= 0 else {}


func has_continent(id: String) -> bool:
	return index_of(id) >= 0


# --- Befehle -------------------------------------------------------------------------------

## Strich an einen Kontinent anhängen.
static func add_stroke_command(continent_id: String, stroke: Dictionary) -> Dictionary:
	return {"kind": "add_stroke", "continent": continent_id, "stroke": stroke}


## Einen Strich ersetzen (z. B. „neu würfeln“: gleicher Strich, anderer Ausgangswert).
func replace_stroke_command(continent_id: String, index: int, new_stroke: Dictionary) -> Dictionary:
	var old: Dictionary = (continent(continent_id)["strokes"][index] as Dictionary).duplicate(true)
	return {"kind": "replace_stroke", "continent": continent_id, "index": index, "old": old, "new": new_stroke}


## Einen Strich entfernen (z. B. eine gezeichnete Landform löschen). Der Befehl trägt eine Kopie
## und den Listenplatz – Rückgängig setzt ihn genau dorthin zurück.
func remove_stroke_command(continent_id: String, index: int) -> Dictionary:
	var stroke: Dictionary = (continent(continent_id)["strokes"][index] as Dictionary).duplicate(true)
	return {"kind": "remove_stroke", "continent": continent_id, "index": index, "stroke": stroke}


## Neuen Kontinent anlegen (am Ende der Liste).
static func add_continent_command(data: Dictionary) -> Dictionary:
	return {"kind": "add_continent", "data": data.duplicate(true)}


## Kontinent löschen – der Befehl trägt eine vollständige Kopie, damit Rückgängig ihn wiederherstellt.
func remove_continent_command(continent_id: String) -> Dictionary:
	var i := index_of(continent_id)
	return {"kind": "remove_continent", "index": i, "data": (continents[i] as Dictionary).duplicate(true)}


## Kontinent vergrößern oder verkleinern: Alle Bearbeitungen und gemerkten Regionen wachsen mit
## (Lage, Pinselgröße und Breiten mal Faktor; Höhenangaben in Metern bleiben). Entscheidung des
## Spielleiters, 21. 11. 2026: „Alles wächst mit.“ Rückgängig stellt den alten Stand exakt her.
func resize_command(continent_id: String, new_size_km: float, old_size_km: float = -1.0) -> Dictionary:
	var c := continent(continent_id)
	if old_size_km <= 0.0:
		old_size_km = c["size_km"]
	var factor := new_size_km / old_size_km
	var new_strokes := []
	for stroke in c["strokes"]:
		new_strokes.append(Stroke.scaled(stroke, factor))
	var new_regions := []
	for region in c["regions"]:
		# Detailregionen behalten Kennung und Daten; ihre Lage wächst mit (die Daten werden gestreckt).
		var scaled_region: Dictionary = (region as Dictionary).duplicate(true)
		scaled_region["cx"] = region["cx"] * factor
		scaled_region["cy"] = region["cy"] * factor
		scaled_region["size"] = region["size"] * factor
		new_regions.append(scaled_region)
	return {"kind": "resize", "continent": continent_id, "old": old_size_km, "new": new_size_km,
		"old_strokes": (c["strokes"] as Array).duplicate(true), "new_strokes": new_strokes,
		"old_regions": (c["regions"] as Array).duplicate(true), "new_regions": new_regions}


## Einen Wert setzen; key darf ein Pfad sein, z. B. "climate_override.snowline_offset".
func set_command(continent_id: String, key: String, new_value: Variant, old_value: Variant = null) -> Dictionary:
	if old_value == null:
		old_value = get_value(continent_id, key)
	return {"kind": "set", "continent": continent_id, "key": key, "old": old_value, "new": new_value}


## Mehrere Befehle als ein Schritt (z. B. Kontinent anlegen und gleich platzieren).
static func group_command(commands: Array) -> Dictionary:
	return {"kind": "group", "commands": commands}


func execute(command: Dictionary) -> void:
	_apply(command, true)
	_undo.append(command)
	_redo.clear()
	changed.emit(command, false)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> Dictionary:
	if _undo.is_empty():
		return {}
	var command: Dictionary = _undo.pop_back()
	_apply(command, false)
	_redo.append(command)
	changed.emit(command, true)
	return command


func redo() -> Dictionary:
	if _redo.is_empty():
		return {}
	var command: Dictionary = _redo.pop_back()
	_apply(command, true)
	_undo.append(command)
	changed.emit(command, false)
	return command


## Ziel eines Werts: ein Kontinent oder (mit PLANET) der Planet selbst.
func _target(continent_id: String) -> Dictionary:
	return planet if continent_id == PLANET else continent(continent_id)


## Planetengröße (Radius in km); Grenzen: kleiner Mond bis doppelte Erde.
const MIN_RADIUS_KM := 1000.0
const MAX_RADIUS_KM := 12742.0


func get_value(continent_id: String, key: String) -> Variant:
	var target: Dictionary = _target(continent_id)
	var parts := key.split(".")
	for k in parts.size() - 1:
		target = target[parts[k]]
	return target[parts[parts.size() - 1]]


## Wert vorläufig setzen (z. B. während ein Regler gezogen wird) – ohne Verlaufseintrag und
## ohne Signal. Der endgültige Schritt kommt danach als Befehl.
func preview_value(continent_id: String, key: String, value: Variant) -> void:
	_set_value(continent_id, key, value)


func _set_value(continent_id: String, key: String, value: Variant) -> void:
	var target: Dictionary = _target(continent_id)
	var parts := key.split(".")
	for k in parts.size() - 1:
		target = target[parts[k]]
	target[parts[parts.size() - 1]] = value


## Kontinent, auf den sich ein Befehl bezieht ("" bei Befehlen ohne festen Kontinent).
static func command_continent(command: Dictionary) -> String:
	match command.get("kind", ""):
		"add_continent", "remove_continent":
			return command["data"]["id"]
		"add_stroke", "replace_stroke", "remove_stroke":
			return command["continent"]
		"group":
			for c in command["commands"]:
				var id := command_continent(c)
				if id != "":
					return id
			return ""
		_:
			return command.get("continent", "")


func _apply(command: Dictionary, forward: bool) -> void:
	match command["kind"]:
		"add_stroke":
			var strokes: Array = continent(command["continent"])["strokes"]
			if forward:
				strokes.append((command["stroke"] as Dictionary).duplicate(true))
			else:
				strokes.pop_back()
		"replace_stroke":
			var strokes: Array = continent(command["continent"])["strokes"]
			strokes[command["index"]] = (command["new" if forward else "old"] as Dictionary).duplicate(true)
		"remove_stroke":
			var strokes: Array = continent(command["continent"])["strokes"]
			if forward:
				strokes.remove_at(command["index"])
			else:
				strokes.insert(mini(command["index"], strokes.size()), (command["stroke"] as Dictionary).duplicate(true))
		"set":
			_set_value(command["continent"], command["key"], command["new"] if forward else command["old"])
		"resize":
			var c := continent(command["continent"])
			var side := "new" if forward else "old"
			var factor: float = float(command[side]) / float(c["size_km"])
			var other := "old" if forward else "new"
			var regions := (command[side + "_regions"] as Array).duplicate(true)
			# Detailregionen entstehen außerhalb des Verlaufs (beim Vertiefen): Die seither angelegten
			# bleiben erhalten und wachsen mit, statt vom gemerkten Stand verdrängt zu werden. Sie
			# werden in beiden gemerkten Ständen nachgetragen (je Kennung einmal), damit weitere
			# Rückgängig/Wiederholen sie weder verlieren noch verdoppeln.
			var known := {}
			for r in regions:
				if (r as Dictionary).has("id"):
					known[r["id"]] = true
			var known_other := {}
			for r in command[other + "_regions"]:
				if (r as Dictionary).has("id"):
					known_other[r["id"]] = true
			for r in c["regions"]:
				var rid: String = str(r.get("id", ""))
				if not (r as Dictionary).has("checksum") or rid == "" or known.has(rid):
					continue
				known[rid] = true
				var kept: Dictionary = (r as Dictionary).duplicate(true)
				kept["cx"] = float(r["cx"]) * factor
				kept["cy"] = float(r["cy"]) * factor
				kept["size"] = float(r["size"]) * factor
				regions.append(kept)
				(command[side + "_regions"] as Array).append(kept.duplicate(true))
				if not known_other.has(rid):
					known_other[rid] = true
					(command[other + "_regions"] as Array).append((r as Dictionary).duplicate(true))
			c["size_km"] = command[side]
			c["strokes"] = (command[side + "_strokes"] as Array).duplicate(true)
			c["regions"] = regions
		"add_continent":
			if forward:
				continents.append((command["data"] as Dictionary).duplicate(true))
			else:
				# Stand beim Entfernen merken (Detailregionen entstehen außerhalb des Verlaufs).
				command["data"] = (continents[index_of(command["data"]["id"])] as Dictionary).duplicate(true)
				continents.remove_at(index_of(command["data"]["id"]))
		"remove_continent":
			if forward:
				command["data"] = (continents[index_of(command["data"]["id"])] as Dictionary).duplicate(true)
				continents.remove_at(index_of(command["data"]["id"]))
			else:
				continents.insert(mini(command["index"], continents.size()), (command["data"] as Dictionary).duplicate(true))
		"group":
			var list: Array = command["commands"]
			if forward:
				for c in list:
					_apply(c, true)
			else:
				for k in range(list.size() - 1, -1, -1):
					_apply(list[k], false)


# --- Navigation (kein Befehl: gehört nicht zum Rückgängig-Verlauf) -----------------------------

## Gespeicherte Detailregion an dieser Stelle (gleiche Größe, Mitte innerhalb eines Viertels der
## Größe), oder {} – Regionen mit Daten tragen "id" und "checksum".
func region_near(continent_id: String, cx: float, cy: float, size: float) -> Dictionary:
	var c := continent(continent_id)
	if c.is_empty():
		return {}
	for r in c["regions"]:
		if r.has("checksum") and is_equal_approx(float(r["size"]), size) \
				and absf(float(r["cx"]) - cx) < size * 0.25 and absf(float(r["cy"]) - cy) < size * 0.25:
			return r
	return {}


## Detailregion eintragen (Daten liegen schon in der Regionsdatei). Ein bloßer Rahmen derselben
## Stelle wird dabei ersetzt. Kein Befehl: Regionen sind Ergebnis des Vertiefens, kein Rückgängig-Schritt.
func add_region(continent_id: String, region: Dictionary) -> void:
	var c := continent(continent_id)
	if c.is_empty():
		return
	var regions: Array = c["regions"]
	for k in range(regions.size() - 1, -1, -1):
		var r: Dictionary = regions[k]
		if not r.has("checksum") and is_equal_approx(float(r["size"]), float(region["size"])) \
				and absf(float(r["cx"]) - float(region["cx"])) < float(region["size"]) * 0.25 \
				and absf(float(r["cy"]) - float(region["cy"])) < float(region["size"]) * 0.25:
			regions.remove_at(k)
	regions.append(region.duplicate(true))


## Merkt sich einen vertieften Ausschnitt, damit er in gröberen Ansichten als Rahmen erscheint.
func remember_region(continent_id: String, cx: float, cy: float, size: float) -> void:
	var c := continent(continent_id)
	if c.is_empty():
		return
	var regions: Array = c["regions"]
	for r in regions:
		if absf(r["cx"] - cx) < size * 0.25 and absf(r["cy"] - cy) < size * 0.25 and is_equal_approx(r["size"], size):
			return
	regions.append({"cx": cx, "cy": cy, "size": size})


# --- Speichern -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "planet": planet.duplicate(true), "continents": continents.duplicate(true)}


## Gibt null zurück, wenn die Daten keine (lesbare) Welt sind.
static func from_dict(data: Dictionary) -> WorldDocument:
	if data.get("format", "") != FORMAT or int(data.get("version", 0)) > VERSION:
		return null
	var list: Variant = data.get("continents", [])
	if not list is Array:
		return null
	var doc := WorldDocument.new()
	var p: Variant = data.get("planet", {})
	if p is Dictionary:
		doc.planet.merge(p, true)
	# JSON kennt nur Kommazahlen: ganzzahlige Felder zurückwandeln; ältere Dateien ergänzen.
	for c in list:
		if not c is Dictionary or not c.has("seed") or not c.has("size_km") or not c.has("strokes"):
			return null
		c["seed"] = int(c["seed"])
		if not c.has("id"):
			c["id"] = new_id()
		if not c.has("name"):
			c["name"] = ""
		if not c.has("base"):
			c["base"] = BASE_GENERATED
		if not c.has("base_size_km"):
			c["base_size_km"] = c["size_km"]
		# Ältere Welten: Bäume wie bisher nach dem Ausgangswert der Grundform streuen.
		c["scatter_seed"] = int(c.get("scatter_seed", c["seed"]))
		for key in ["latitude", "longitude", "heading"]:
			if not c.has(key):
				c[key] = 0.0
		if not c.has("climate_override"):
			c["climate_override"] = {"snowline_offset": 0.0, "humidity_offset": 0.0}
		if not c.has("regions"):
			c["regions"] = []
		for s in c["strokes"]:
			if not s is Dictionary or not s.has("tool") or not s.has("points"):
				return null
			if (s as Dictionary).has("seed"):
				s["seed"] = int(s["seed"])
		doc.continents.append(c)
	return doc


func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".neu"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# Volle Genauigkeit: nach dem Laden entsteht exakt dieselbe Landschaft.
	file.store_string(JSON.stringify({"format": FORMAT, "version": VERSION, "planet": planet, "continents": continents}, "", false, true))
	file.close()
	# Erst vollständig schreiben, dann ersetzen – ein Absturz hinterlässt keine halbe Datei.
	# Der vorige Stand bleibt als .bak erhalten.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(temp, path)


## Was beim letzten load_file schiefging ("" = nichts). Für einen Hinweis in der Oberfläche.
static var load_problem := ""


## Lädt eine Weltdatei. Fehlt sie, null. Ist sie beschädigt, wird sie als .defekt beiseitegelegt
## (nie überschrieben) und der letzte gute Stand (.neu, dann .bak) versucht.
static func load_file(path: String) -> WorldDocument:
	load_problem = ""
	if not FileAccess.file_exists(path):
		# Absturz zwischen Schreiben und Ersetzen: die fertige .neu-Datei übernehmen.
		if FileAccess.file_exists(path + ".neu"):
			var rescued := _read(path + ".neu")
			if rescued:
				load_problem = "Weltdatei aus der zuletzt geschriebenen Fassung wiederhergestellt."
			return rescued
		return null
	var doc := _read(path)
	if doc:
		return doc
	var aside := path + ".defekt"
	DirAccess.copy_absolute(path, aside)
	for fallback in [path + ".neu", path + ".bak"]:
		if FileAccess.file_exists(fallback):
			doc = _read(fallback)
			if doc:
				load_problem = "Weltdatei war beschädigt (beiseitegelegt als %s) – letzter guter Stand geladen." % aside.get_file()
				return doc
	load_problem = "Weltdatei ist beschädigt und wurde beiseitegelegt als %s." % aside.get_file()
	return null


static func _read(path: String) -> WorldDocument:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return null
	return from_dict(data)
