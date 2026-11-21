class_name RealtimeCapture
extends Node
## Bildaufnahme in Echtzeit: Der Editor läuft normal (Wanduhr, Bildsynchronisierung), jedes
## gezeichnete Bild bekommt einen Zeitstempel, bis zu max_fps Bilder je Sekunde werden als JPG
## gespeichert (verkleinert und geschrieben in Hintergrundaufgaben, damit die Aufnahme den Editor
## kaum bremst).
##
## Rechenpausen werden nicht nachgestellt, sondern gemessen: Solange der Editor rechnet (z. B. ein
## Ausschnitt neu berechnet wird), entsteht kein neues Bild. Die Lücke zwischen zwei gezeichneten
## Bildern IST die Pause; tools/make_video.py lässt das letzte Bild davor so lange stehen, wie die
## Pause wirklich dauerte. (Godots --write-movie rechnet jedes Bild in fester Zeit und verdeckt
## solche Pausen – deshalb hier nicht verwendet.)
##
## Lücken ab pause_ms (Vorgabe 100 ms, im Ablauf --pause-ab=<ms>) gelten als Rechenpause und werden
## im Film beschriftet; Lücken von HITCH_MS bis unter pause_ms sind Ruckler – sie werden mit Zeit,
## Handlung und Zustand gesammelt (Anzahl, Summe, je Handlung, die größten).
##
## Ergebnis in <Ordner>: frames/f_000000.jpg …, frames/zeiten.csv (Bild;Millisekunden) und – über
## finish() – echtzeit.json (bzw. report_name) mit Bildraten, Pausen und Rucklern. Ohne Bilder
## (max_fps <= 0) bleibt <Ordner>/frames unberührt.

## Ab dieser Lücke als Ruckler gezählt (deutlich länger als ein Bild bei 60 Hz).
const HITCH_MS := 50.0
## Höchstens so viele Bilder warten gleichzeitig aufs Speichern (sonst wird eins ausgelassen).
const MAX_PENDING := 16
## So viele der größten Ruckler kommen einzeln in den Bericht.
const LARGEST_HITCHES := 20

var dir := ""
var max_fps := 30.0
var out_size := Vector2i(1280, 800)
var quality := 0.85
## Ab dieser Lücke zwischen zwei Bildern gilt sie als Rechenpause.
var pause_ms := 100.0
## Dateiname des Berichts in dir.
var report_name := "echtzeit.json"
## Liefert je Bild den Zustand als Dictionary mit mindestens "text" (Maßstab, Bearbeitungen …).
var state_provider := Callable()
## Optional: Ursache einer Pause aus (Zustand davor, Zustand danach, Handlung) → Text.
var cause_provider := Callable()
## Was der Ablauf gerade tut (setzt der Ablauf vor jedem Schritt).
var action := ""

var _start_us := 0
var _last_draw_us := 0
var _last_capture_us := -1000000000
var _draws := PackedInt64Array()
var _captures := PackedFloat64Array()
var _pending: Array[int] = []
var _pauses: Array = []
var _hitches: Array = []
var _state_before := {}
var _skipped := 0
var _running := false


func start(p_dir: String) -> void:
	dir = p_dir
	DirAccess.make_dir_recursive_absolute(dir)
	if max_fps > 0.0:
		var frames_dir := dir.path_join("frames")
		DirAccess.make_dir_recursive_absolute(frames_dir)
		for f in DirAccess.get_files_at(frames_dir):
			DirAccess.remove_absolute(frames_dir.path_join(f))
	_start_us = Time.get_ticks_usec()
	_last_draw_us = _start_us
	_running = true
	RenderingServer.frame_post_draw.connect(_on_drawn)


## Sekunden seit Beginn der Aufnahme (Wanduhr).
func elapsed() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1000000.0


func pauses() -> Array:
	return _pauses


func _on_drawn() -> void:
	if not _running:
		return
	var now := Time.get_ticks_usec()
	var gap_ms := (now - _last_draw_us) / 1000.0
	var state: Dictionary = state_provider.call() if state_provider.is_valid() else {"text": ""}
	if not _draws.is_empty() and gap_ms >= HITCH_MS:
		# Handlung: die zuletzt gesetzte – der Ablauf setzt sie unmittelbar vor dem auslösenden
		# Ereignis, die Rechnung läuft danach im selben Bild.
		var start_s := snappedf((_last_draw_us - _start_us) / 1000000.0, 0.001)
		if gap_ms >= pause_ms:
			var pause := {
				"start_s": start_s,
				"duration_s": snappedf(gap_ms / 1000.0, 0.001),
				"handlung": action,
				"vorher": _state_before.get("text", ""),
				"nachher": state.get("text", ""),
			}
			pause["ursache"] = cause_provider.call(_state_before, state, action) if cause_provider.is_valid() else action
			_pauses.append(pause)
			print("Rechenpause %s s bei %s s: %s" % [String.num(pause["duration_s"], 2), String.num(pause["start_s"], 2), pause["ursache"]])
		else:
			_hitches.append({"start_s": start_s, "dauer_ms": snappedf(gap_ms, 0.1), "handlung": action,
				"zustand": state.get("text", ""), "beim_malen": state.get("busy", false) or _state_before.get("busy", false)})
	_draws.append(now - _start_us)
	_last_draw_us = now
	_state_before = state
	_collect_finished()
	# max_fps <= 0: nur messen, keine Bilder (Vergleichslauf ohne Aufnahmekosten).
	# Kleine Toleranz: bei 60 Hz wird so jedes zweite Bild gespeichert (30 Bilder/s).
	if max_fps <= 0.0 or now - _last_capture_us < 1000000.0 / max_fps - 2500.0:
		return
	if _pending.size() >= MAX_PENDING:
		_skipped += 1
		return
	var image := get_viewport().get_texture().get_image()
	var index := _captures.size()
	_captures.append((now - _start_us) / 1000.0)
	_last_capture_us = now
	var path := dir.path_join("frames/f_%06d.jpg" % index)
	_pending.append(WorkerThreadPool.add_task(_save.bind(image, path, out_size, quality), false, "Weltwerk Aufnahme"))


## Läuft in einer Hintergrundaufgabe: verkleinern und als JPG schreiben.
static func _save(image: Image, path: String, size: Vector2i, q: float) -> void:
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	image.save_jpg(path, q)


func _collect_finished() -> void:
	var still: Array[int] = []
	for id in _pending:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			still.append(id)
	_pending = still


## Ruckler zusammengefasst: Anzahl, Summe, je Handlung, die größten einzeln (mit Zeit und Handlung).
func _hitch_report() -> Dictionary:
	var total := 0.0
	var by_action := {}
	var while_painting := 0
	for h in _hitches:
		total += h["dauer_ms"]
		if h["beim_malen"]:
			while_painting += 1
		var key: String = h["handlung"]
		if not by_action.has(key):
			by_action[key] = {"anzahl": 0, "gesamt_ms": 0.0, "groesster_ms": 0.0}
		var entry: Dictionary = by_action[key]
		entry["anzahl"] += 1
		entry["gesamt_ms"] = snappedf(entry["gesamt_ms"] + h["dauer_ms"], 0.1)
		entry["groesster_ms"] = maxf(entry["groesster_ms"], h["dauer_ms"])
	var largest := _hitches.duplicate()
	largest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dauer_ms"] > b["dauer_ms"])
	return {
		"bereich_ms": [HITCH_MS, pause_ms],
		"anzahl": _hitches.size(),
		"gesamt_s": snappedf(total / 1000.0, 0.001),
		"beim_malen": while_painting,
		"je_handlung": by_action,
		"groesste": largest.slice(0, LARGEST_HITCHES),
	}


## Aufnahme beenden: alle Bilder schreiben, Zeitliste und Bericht ablegen. extra wird in den
## Bericht übernommen (Prüfungen, Abschnitte des Ablaufs).
func finish(extra: Dictionary = {}) -> Dictionary:
	_running = false
	if RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_drawn)
	for id in _pending:
		WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()
	if max_fps > 0.0:
		var csv := FileAccess.open(dir.path_join("frames/zeiten.csv"), FileAccess.WRITE)
		csv.store_line("bild;ms")
		for k in _captures.size():
			csv.store_line("%d;%.2f" % [k, _captures[k]])
		csv.close()

	var gaps := PackedFloat64Array()
	for k in range(1, _draws.size()):
		gaps.append((_draws[k] - _draws[k - 1]) / 1000.0)
	var sorted := gaps.duplicate()
	sorted.sort()
	var total_pause := 0.0
	for p in _pauses:
		total_pause += p["duration_s"]
	var duration := _draws[_draws.size() - 1] / 1000000.0 if not _draws.is_empty() else 0.0
	var report := {
		"dauer_s": snappedf(duration, 0.01),
		"mit_bildern": max_fps > 0.0,
		"gezeichnete_bilder": _draws.size(),
		"gespeicherte_bilder": _captures.size(),
		"ausgelassen_weil_speicher_voll": _skipped,
		"aufnahme_bilder_je_s_hoechstens": max_fps,
		"bildgroesse": [out_size.x, out_size.y],
		"bildabstand_ms": {
			"mittel": snappedf(_mean(gaps), 0.01),
			"median": snappedf(_quantile(sorted, 0.5), 0.01),
			"p95": snappedf(_quantile(sorted, 0.95), 0.01),
			"p99": snappedf(_quantile(sorted, 0.99), 0.01),
			"groesster": snappedf(sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0, 0.01),
		},
		"pause_ab_ms": pause_ms,
		"pausen_anzahl": _pauses.size(),
		"pausen_gesamt_s": snappedf(total_pause, 0.001),
		"pausen": _pauses,
		"ruckler": _hitch_report(),
	}
	report.merge(extra)
	var file := FileAccess.open(dir.path_join(report_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false))
	file.close()
	return report


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var s := 0.0
	for v in values:
		s += v
	return s / values.size()


static func _quantile(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(q * (sorted.size() - 1))), 0, sorted.size() - 1)]
