class_name RegionStore
extends RefCounted
## Dauerhaft gespeicherte Detailregionen.
##
## Beim Vertiefen entsteht aus dem gewählten Ausschnitt eine Detailregion: Die Grunddaten der
## Erzeugung (Landanteil, Relief, Wald, Erosionsrelief) werden in Regionsauflösung berechnet – mit
## allen Feinheiten, die die gröbere Stufe nicht zeigen kann – und als Datei neben der Weltdatei
## abgelegt (<welt>_regionen/<id>.region, komprimiert, mit Prüfsumme in der Weltdatei).
## Die Bearbeitungen (Strichliste) bleiben verknüpft: Sie werden in jedem Maßstab darauf
## angewandt. Gröbere Ansichten zeigen das Zellmittel des fertigen Regionsergebnisses.
## Reine Daten und Rechnung, keine Knoten.

const LAYERS := ["base_land", "relief_low", "relief_detail", "forest_potential",
	"erosion_alpine", "erosion_alpine_fine", "erosion_hills"]
const MAGIC := "WWRG"
## 2: Waldanlage ohne Klima (forest_potential) statt fertiger Waldanlage.
const FORMAT := 2
const EXTENSION := ".region"
const RESULT_MAGIC := "WWR2"
const RESULT_EXTENSION := ".ergebnis"
## Breite des Übergangs am Regionsrand (Anteil der Regionsgröße), wo Regionsdaten und Erzeugung
## ineinander übergehen (nur wichtig, wenn sich die Erzeugung seither geändert hat).
const FEATHER := 0.04

static var _cache := {}
static var _mutex := Mutex.new()


static func folder_for(world_path: String) -> String:
	return world_path.get_basename() + "_regionen"


static func file_for(world_path: String, region: Dictionary) -> String:
	return folder_for(world_path).path_join(str(region["id"]) + EXTENSION)


static func new_id() -> String:
	return "region-" + Crypto.new().generate_random_bytes(6).hex_encode()


## Rohdaten (unkomprimiert) einer Region aus einem berechneten Ausschnitt.
static func encode(w: TerrainWindow) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	var head := PackedByteArray()
	head.resize(4 + 4 + 8 * 3)
	head.encode_u32(0, FORMAT)
	head.encode_u32(4, w.res)
	head.encode_double(8, w.cx)
	head.encode_double(16, w.cy)
	head.encode_double(24, w.size)
	out.append_array(head)
	for layer in LAYERS:
		out.append_array((w.get(layer) as PackedFloat32Array).to_byte_array())
	return out


static func checksum(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Rohdaten lesen: {"res", "cx", "cy", "size", "layers": {Name: Feld}} oder {} bei Fehler.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 36 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {}
	if bytes.decode_u32(4) != FORMAT:
		return {}
	var res := int(bytes.decode_u32(8))
	var n := res * res
	if bytes.size() != 36 + LAYERS.size() * n * 4:
		return {}
	var data := {"res": res, "cx": bytes.decode_double(12), "cy": bytes.decode_double(20),
		"size": bytes.decode_double(28), "layers": {}}
	var offset := 36
	for layer in LAYERS:
		data["layers"][layer] = bytes.slice(offset, offset + n * 4).to_float32_array()
		offset += n * 4
	return data


## Speichert die Regionsdaten (komprimiert) und gibt die Prüfsumme zurück ("" bei Fehler).
static func save(world_path: String, region: Dictionary, w: TerrainWindow) -> String:
	var bytes := encode(w)
	var sum := checksum(bytes)
	DirAccess.make_dir_recursive_absolute(folder_for(world_path))
	var path := file_for(world_path, region)
	var file := FileAccess.open_compressed(path + ".neu", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(path + ".neu", path) != OK:
		return ""
	_remember(sum, decode(bytes))
	return sum


## Lädt die Daten einer Region (zwischengespeichert nach Prüfsumme); {} wenn Datei fehlt,
## beschädigt ist oder die Prüfsumme nicht stimmt.
static func load_data(world_path: String, region: Dictionary) -> Dictionary:
	var sum: String = region.get("checksum", "")
	if sum == "":
		return {}
	_mutex.lock()
	var hit: Variant = _cache.get(sum)
	_mutex.unlock()
	if hit != null:
		return hit
	var path := file_for(world_path, region)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var bytes := file.get_buffer(36 + LAYERS.size() * int(region.get("res", 257)) * int(region.get("res", 257)) * 4)
	file.close()
	if checksum(bytes) != sum:
		return {}
	var data := decode(bytes)
	if not data.is_empty():
		_remember(sum, data)
	return data


static func _remember(sum: String, data: Dictionary) -> void:
	if data.is_empty():
		return
	data["checksum"] = sum
	_mutex.lock()
	_cache[sum] = data
	_mutex.unlock()


static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


## Wert eines Feldes der Region an (x, y) (Kontinentmeter), bilinear im Regionsraster.
static func sample(data: Dictionary, layer: String, x: float, y: float) -> float:
	return bilinear(data["layers"][layer], data["res"], x, y, data["cx"], data["cy"], data["size"])


static func bilinear(field: PackedFloat32Array, res: int, x: float, y: float, cx: float, cy: float, size: float) -> float:
	var gx := clampf(((x - cx) / size + 0.5) * float(res - 1), 0.0, float(res - 1))
	var gy := clampf(((cy - y) / size + 0.5) * float(res - 1), 0.0, float(res - 1))
	var i0 := mini(int(gx), res - 2)
	var j0 := mini(int(gy), res - 2)
	var fx := gx - i0
	var fy := gy - j0
	var k := j0 * res + i0
	return lerpf(lerpf(field[k], field[k + 1], fx), lerpf(field[k + res], field[k + res + 1], fx), fy)


## Zwei Felder gleichen Rasters an derselben Stelle (x = erstes, y = zweites).
static func bilinear2(a: PackedFloat32Array, b: PackedFloat32Array, res: int, x: float, y: float, cx: float, cy: float, size: float) -> Vector2:
	var gx := clampf(((x - cx) / size + 0.5) * float(res - 1), 0.0, float(res - 1))
	var gy := clampf(((cy - y) / size + 0.5) * float(res - 1), 0.0, float(res - 1))
	var i0 := mini(int(gx), res - 2)
	var j0 := mini(int(gy), res - 2)
	var fx := gx - i0
	var fy := gy - j0
	var k := j0 * res + i0
	return Vector2(lerpf(lerpf(a[k], a[k + 1], fx), lerpf(a[k + res], a[k + res + 1], fx), fy),
		lerpf(lerpf(b[k], b[k + 1], fx), lerpf(b[k + res], b[k + res + 1], fx), fy))


## Zwischenstand des fertigen Ergebnisses (Höhe, Wald) einer Region neben ihren Daten – abgeleitet:
## gilt nur für genau den Stand, aus dem es berechnet wurde (Prüfwert des Stands in der Datei), sonst
## wird neu gerechnet. Spart nach dem Öffnen das Durchrechnen aller Regionen für die Übersicht.
static func result_file_for(world_path: String, region: Dictionary) -> String:
	return folder_for(world_path).path_join(str(region["id"]) + RESULT_EXTENSION)


static func save_result(path: String, key: String, result: Dictionary) -> void:
	var payload := PackedByteArray()
	payload.append_array((result["height"] as PackedFloat32Array).to_byte_array())
	payload.append_array((result["forest"] as PackedFloat32Array).to_byte_array())
	var file := FileAccess.open_compressed(path + ".neu", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return
	file.store_buffer(RESULT_MAGIC.to_ascii_buffer())
	file.store_buffer(_result_sum(key, payload).to_ascii_buffer())
	file.store_buffer(payload)
	var ok := file.get_error() == OK
	file.close()
	if ok:
		DirAccess.rename_absolute(path + ".neu", path)
	else:
		DirAccess.remove_absolute(path + ".neu")


## Prüfwert über Stand und Inhalt: Ein beschädigter Zwischenstand wird nicht verwendet.
static func _result_sum(key: String, payload: PackedByteArray) -> String:
	var bytes := key.to_utf8_buffer()
	bytes.append_array(payload)
	return checksum(bytes)


## Ergebnis lesen, wenn es zu diesem Stand gehört: {"height", "forest"}, sonst {}.
static func load_result(path: String, key: String, res: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var n := res * res * 4
	var bytes := file.get_buffer(68 + 2 * n)
	var ok := file.get_error() == OK or file.get_error() == ERR_FILE_EOF
	file.close()
	if not ok or bytes.size() != 68 + 2 * n or bytes.slice(0, 4).get_string_from_ascii() != RESULT_MAGIC:
		return {}
	var payload := bytes.slice(68, 68 + 2 * n)
	if bytes.slice(4, 68).get_string_from_ascii() != _result_sum(key, payload):
		return {}
	return {"height": payload.slice(0, n).to_float32_array(), "forest": payload.slice(n, 2 * n).to_float32_array()}


## Gewicht der Regionsdaten an (x, y): 1 im Inneren, zum Rand hin weich 0 (außerhalb 0).
static func weight(data: Dictionary, x: float, y: float) -> float:
	var half: float = data["size"] * 0.5
	var d := minf(half - absf(x - float(data["cx"])), half - absf(y - float(data["cy"])))
	if d <= 0.0:
		return 0.0
	return smoothstep(0.0, float(data["size"]) * FEATHER, d)
