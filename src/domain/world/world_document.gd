class_name WorldDocument
extends RefCounted
## Der Weltstand: Planeteinstellungen und Kontinente mit Lage, Ausgangswert und Strichliste.
##
## Jede Änderung läuft als Befehl über execute(); daraus entstehen Rückgängig und Wiederholen.
## Abgeleitetes (Höhen, Wald, Globusbild, Bäume) wird nie gespeichert, sondern aus diesem Stand
## neu berechnet – deshalb nimmt Rückgängig abgeleitete Änderungen automatisch mit.
## Namen bleiben leer, bis der Spielleiter sie vergibt.

signal changed(command: Dictionary, undone: bool)

const FORMAT := "weltwerk-welt"
const VERSION := 1

var planet := {"radius_km": 6371.0, "temperature_offset": 0.0}
var continents: Array = []

var _undo: Array = []
var _redo: Array = []


static func create(seed_value: int) -> WorldDocument:
	var doc := WorldDocument.new()
	doc.continents.append(new_continent(seed_value))
	return doc


static func new_continent(seed_value: int) -> Dictionary:
	return {
		"id": "kontinent-" + Crypto.new().generate_random_bytes(6).hex_encode(),
		"name": "",
		"seed": seed_value,
		"size_km": 1600.0,
		"latitude": 35.0,
		"longitude": 10.0,
		"heading": 0.0,
		"climate_override": {"snowline_offset": 0.0, "humidity_offset": 0.0},
		"strokes": [],
		"regions": [],
	}


# --- Befehle -------------------------------------------------------------------------------

## Strich an einen Kontinent anhängen.
static func add_stroke_command(continent: int, stroke: Dictionary) -> Dictionary:
	return {"kind": "add_stroke", "continent": continent, "stroke": stroke}


## Einen Wert setzen; key darf ein Pfad sein, z. B. "climate_override.snowline_offset".
func set_command(continent: int, key: String, new_value: Variant, old_value: Variant = null) -> Dictionary:
	if old_value == null:
		old_value = get_value(continent, key)
	return {"kind": "set", "continent": continent, "key": key, "old": old_value, "new": new_value}


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


func get_value(continent: int, key: String) -> Variant:
	var target: Dictionary = continents[continent]
	var parts := key.split(".")
	for k in parts.size() - 1:
		target = target[parts[k]]
	return target[parts[parts.size() - 1]]


## Wert vorläufig setzen (z. B. während ein Regler gezogen wird) – ohne Verlaufseintrag und
## ohne Signal. Der endgültige Schritt kommt danach als Befehl.
func preview_value(continent: int, key: String, value: Variant) -> void:
	_set_value(continent, key, value)


func _set_value(continent: int, key: String, value: Variant) -> void:
	var target: Dictionary = continents[continent]
	var parts := key.split(".")
	for k in parts.size() - 1:
		target = target[parts[k]]
	target[parts[parts.size() - 1]] = value


func _apply(command: Dictionary, forward: bool) -> void:
	match command["kind"]:
		"add_stroke":
			var strokes: Array = continents[command["continent"]]["strokes"]
			if forward:
				strokes.append(command["stroke"])
			else:
				strokes.pop_back()
		"set":
			_set_value(command["continent"], command["key"], command["new"] if forward else command["old"])


# --- Navigation (kein Befehl: gehört nicht zum Rückgängig-Verlauf) -----------------------------

## Merkt sich einen vertieften Ausschnitt, damit er in gröberen Ansichten als Rahmen erscheint.
func remember_region(continent: int, cx: float, cy: float, size: float) -> void:
	var regions: Array = continents[continent]["regions"]
	for r in regions:
		if absf(r["cx"] - cx) < size * 0.25 and absf(r["cy"] - cy) < size * 0.25 and is_equal_approx(r["size"], size):
			return
	regions.append({"cx": cx, "cy": cy, "size": size})


# --- Speichern -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "planet": planet.duplicate(true), "continents": continents.duplicate(true)}


static func from_dict(data: Dictionary) -> WorldDocument:
	var doc := WorldDocument.new()
	doc.planet = data.get("planet", doc.planet)
	doc.continents = data.get("continents", [])
	# JSON kennt nur Kommazahlen: ganzzahlige Felder zurückwandeln.
	for c in doc.continents:
		c["seed"] = int(c["seed"])
	return doc


func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".neu"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	# Erst vollständig schreiben, dann ersetzen – ein Absturz hinterlässt keine halbe Datei.
	return DirAccess.rename_absolute(temp, path)


static func load_file(path: String) -> WorldDocument:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("format", "") != FORMAT:
		return null
	return from_dict(data)
