class_name ComparisonRun
extends RefCounted
## Vergleich mit der Kontinentalreferenz (docs/referenz/kontinent_konzept.webp): Der Umriss der
## Referenz wird in gleicher Bildlage mit der Maus nachgezeichnet, danach werden Gebirge, Wald,
## Flüsse, Seen und Inseln an den Stellen der Referenz mit den Werkzeugen gemalt. Ergebnis aus
## gleichem Blickwinkel, Seite an Seite mit der Referenz. Dazu Prüfungen: Bearbeiten, Speichern,
## Rückgängig, nachträgliches Verändern der gezeichneten Form („Formen bearbeiten“, Bild
## form_gewaehlt.jpg). Aufruf: --vergleich=<Ordner> (immer neue Welt in <Ordner>/welt.json).

const REFERENCE := "res://docs/referenz/kontinent_konzept.webp"
## Bildgröße der Referenz (Koordinaten unten beziehen sich darauf).
const REF_SIZE := Vector2(1586.0, 992.0)

## Küstenlinie der Referenz (Bildpunkte, aus dem Bild verfolgt und vereinfacht).
const OUTLINE := "240,0 244,52 260,64 284,56 284,0 884,0 884,56 908,68 904,88 892,96 900,108 936,88 928,80 952,68 948,56 980,56 1000,60 1016,76 1048,80 1040,88 1028,80 1012,96 1024,104 1008,112 1032,128 1044,120 1064,136 1100,128 1092,136 1096,148 1152,132 1200,156 1216,152 1232,180 1224,188 1232,212 1244,212 1252,224 1292,216 1300,236 1344,252 1356,248 1368,268 1400,276 1424,312 1440,316 1448,308 1468,328 1488,332 1496,364 1484,360 1480,376 1548,424 1540,432 1524,424 1500,428 1508,456 1484,452 1484,436 1472,440 1472,456 1456,448 1440,456 1416,444 1404,460 1408,480 1392,492 1376,488 1376,472 1344,480 1324,476 1320,460 1308,472 1280,460 1268,472 1272,488 1256,484 1240,516 1252,532 1276,524 1276,536 1256,544 1252,584 1260,600 1252,612 1260,620 1256,632 1276,648 1272,660 1260,660 1256,676 1276,704 1288,700 1324,728 1348,728 1364,740 1412,728 1428,708 1424,700 1412,704 1416,692 1456,680 1440,660 1444,628 1412,608 1392,612 1396,596 1412,596 1416,584 1424,592 1452,588 1468,620 1488,620 1516,648 1516,660 1532,672 1516,664 1508,672 1532,708 1532,724 1516,740 1524,752 1532,744 1540,760 1524,788 1516,776 1500,784 1488,772 1476,780 1480,788 1496,808 1492,832 1456,860 1452,876 1440,868 1428,876 1436,888 1424,908 1400,912 1388,932 1380,920 1352,936 1352,916 1316,916 1312,904 1300,944 1272,928 1260,908 1232,904 1216,880 1196,892 1180,888 1168,904 1124,904 1120,892 1100,896 1076,872 1032,856 1020,868 988,860 960,872 956,864 956,892 940,904 924,904 928,888 896,904 736,904 740,896 708,884 680,848 656,864 632,852 636,876 628,880 616,880 620,868 608,860 576,868 564,852 544,852 544,836 524,828 520,808 500,804 504,788 496,780 480,776 472,788 424,780 380,796 372,784 392,756 404,768 408,752 388,744 376,756 340,756 312,740 328,728 308,712 308,696 292,688 288,696 264,680 252,664 268,660 244,640 244,624 224,604 212,608 220,592 212,544 228,536 236,548 252,520 268,512 264,504 308,476 348,476 332,488 344,500 332,500 332,512 352,520 396,512 436,460 436,392 392,336 392,324 372,336 348,300 324,284 312,288 304,276 256,284 268,268 264,244 256,260 244,244 216,284 200,292 188,272 148,268 160,248 184,252 200,236 192,224 176,224 188,208 180,196 168,196 172,184 164,176 148,192 144,212 124,212 120,204 132,196 136,148 156,152 164,136 156,120 136,120 144,112 136,104 124,108 128,100 140,92 160,100 184,88 208,92 216,80 208,60 240,52"

## Gebirgszüge, Hügel, Wald, Flüsse, Seen, Inseln an den Stellen der Referenz (Bildpunkte).
const MOUNTAINS := [
	[Vector2(150, 110), Vector2(260, 90), Vector2(360, 120), Vector2(460, 175), Vector2(560, 240), Vector2(650, 300), Vector2(740, 360), Vector2(830, 430), Vector2(900, 500)],
	[Vector2(900, 500), Vector2(980, 580), Vector2(1060, 650), Vector2(1150, 700), Vector2(1240, 760), Vector2(1330, 830), Vector2(1400, 880)],
	[Vector2(1000, 760), Vector2(1080, 820), Vector2(1160, 860)],
]
const HILLS := [
	[Vector2(420, 700), Vector2(560, 760), Vector2(700, 800)],
	[Vector2(1250, 330), Vector2(1350, 380), Vector2(1430, 420)],
	[Vector2(620, 120), Vector2(760, 150)],
]
const FORESTS := [
	[Vector2(300, 470), Vector2(420, 520), Vector2(540, 560), Vector2(660, 620)],
	[Vector2(520, 110), Vector2(640, 170), Vector2(760, 230)],
	[Vector2(1100, 260), Vector2(1220, 300), Vector2(1350, 330)],
	[Vector2(560, 800), Vector2(720, 860), Vector2(880, 860), Vector2(1040, 830)],
	[Vector2(860, 620), Vector2(940, 700)],
]
const BAY := [Vector2(850, 190), Vector2(905, 150), Vector2(960, 110), Vector2(985, 60), Vector2(1015, 70), Vector2(1000, 140), Vector2(1060, 190), Vector2(1090, 240), Vector2(1040, 300), Vector2(960, 330), Vector2(880, 300), Vector2(830, 250)]
const RIVERS := [
	[Vector2(660, 340), Vector2(600, 380), Vector2(540, 400), Vector2(480, 430), Vector2(420, 450), Vector2(370, 480), Vector2(320, 520), Vector2(270, 545)],
	[Vector2(960, 640), Vector2(990, 720), Vector2(960, 800), Vector2(985, 880)],
	[Vector2(1180, 560), Vector2(1260, 540), Vector2(1330, 500), Vector2(1400, 470)],
]
const LAKES := [Vector2(720, 560), Vector2(1110, 430)]
const ISLANDS := [
	[Vector2(100, 170), Vector2(130, 240)],
	[Vector2(470, 850), Vector2(540, 870)],
	[Vector2(1210, 950), Vector2(1280, 940)],
]

var editor: Node
var checks := {}


func _init(p_editor: Node) -> void:
	editor = p_editor


## Bildpunkt der Referenz auf den eigenen Bildschirm umgerechnet.
func screen_of_ref(p: Vector2) -> Vector2:
	var view: Vector2 = editor.get_viewport().get_visible_rect().size
	return p / REF_SIZE * view


## Bodenpunkt (Kontinentmeter) unter einem Referenz-Bildpunkt.
func ground_of_ref(p: Vector2) -> Vector2:
	var cam: Camera3D = editor.camera_rig.camera
	var s := screen_of_ref(p)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(s), cam.project_ray_normal(s))
	if hit == null:
		return Vector2.ZERO
	return editor.landscape.to_continent(hit)


func outline_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for pair in OUTLINE.split(" "):
		var xy := pair.split(",")
		var p := Vector2(float(xy[0]), float(xy[1]))
		# Oben schneidet die Kopfleiste der Referenz das Land ab: dort eine ruhige Nordküste.
		if p.y < 64.0:
			p.y = 64.0 + 10.0 * sin(p.x / 55.0)
		# Unten verdeckt die Werkzeugleiste die Küste: leicht nach Süden gewölbt.
		if p.y >= 900.0 and p.x > 735.0 and p.x < 900.0:
			p.y = 912.0
		result.append(p)
	return result


func run(dir: String) -> void:
	var timing := {}
	await editor._frames(20)
	# 1 Neuer gezeichneter Kontinent, Ansicht wie die Referenz.
	editor.ui.new_continent_pressed.emit(true)
	await editor._frames(10)
	_frame()
	await editor._frames(20)
	var ui_was: bool = editor.ui.visible
	# Die Werkzeugleiste darf das Nachzeichnen am Westrand nicht abfangen.
	editor.ui.visible = false
	await _screen_line(outline_points(), true)
	checks["Umriss nachgezeichnet (eine Form)"] = _strokes() == 1
	editor.ui.visible = true
	await editor._frames(10)
	await editor._shot(dir.path_join("umriss.jpg"))
	editor.ui.visible = false
	_frame()
	await editor._frames(5)

	# 2 Bucht im Nordosten, Gebirge, Hügel, Wald, Flüsse, Seen, Inseln – wie ein Nutzer.
	editor._use_tool("shape_remove")
	await _screen_line(_screen_points(BAY), true)
	var t := Time.get_ticks_usec()
	for chain in MOUNTAINS:
		editor._use_tool("gen_mountains")
		editor.ui.set_brush(0.05, 0.85)
		await _ground_stroke(chain)
	timing["Gebirge malen"] = (Time.get_ticks_usec() - t) / 1000.0
	for chain in HILLS:
		editor._use_tool("gen_hills")
		editor.ui.set_brush(0.05, 0.7)
		await _ground_stroke(chain)
	for chain in FORESTS:
		editor._use_tool("gen_forest")
		editor.ui.set_brush(0.06, 0.9)
		await _ground_stroke(chain)
	for chain in RIVERS:
		editor._use_tool("river")
		editor.ui.set_brush(0.005, 0.5)
		await _screen_line(_screen_points(chain), false)
	for p in LAKES:
		editor._use_tool("lake")
		editor.ui.set_brush(0.02, 0.5)
		var g := ground_of_ref(p)
		await editor._mouse_click(g)
	for chain in ISLANDS:
		editor._use_tool("gen_islands")
		editor.ui.set_brush(0.03, 0.8)
		await _ground_stroke(chain)
	# Gezeichnete Landformen nachträglich verändern (wählen, umformen, verschieben, skalieren, löschen).
	await _edit_shapes(dir)
	editor._use_tool("navigate")
	editor.ui.visible = ui_was
	var count := _strokes()
	checks["Alle Bearbeitungen angelegt (%d)" % count] = count >= 20

	# 3 Bild aus gleicher Lage, Seite an Seite mit der Referenz.
	_frame()
	await editor._frames(30)
	await editor._shot(dir.path_join("kontinent.jpg"))
	_side_by_side(dir.path_join("kontinent.jpg"), dir.path_join("vergleich.jpg"))
	# Nahansicht: Gebirge, Fluss und Wald im Westen (wie der Ausschnitt in der Referenz).
	var near := ground_of_ref(Vector2(560, 430))
	editor.camera_rig.jump_to(editor.landscape.to_render(near.x, near.y), editor.camera_rig.max_distance * 0.42)
	await editor._frames(30)
	await editor._shot(dir.path_join("kontinent_nah.jpg"))

	# 4 Bearbeiten, Rückgängig, Speichern.
	editor.camera_rig.jump_to(Vector3.ZERO, editor.camera_rig.max_distance)
	_frame()
	await editor._frames(5)
	editor._undo()
	checks["Rückgängig entfernt die letzte Bearbeitung"] = _strokes() == count - 1
	editor._redo()
	checks["Wiederholen stellt sie wieder her"] = _strokes() == count
	editor._save_now()
	var reloaded := WorldDocument.load_file(editor.save_path)
	checks["Gespeichert = geladen"] = reloaded != null and editor.same_data(editor.doc.to_dict(), reloaded.to_dict())

	var report := {"checks": checks, "timing_ms": timing, "strokes": count}
	var file := FileAccess.open(dir.path_join("vergleich.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var failed := 0
	for key in checks:
		if not checks[key]:
			failed += 1
	print("VERGLEICH: %d Prüfungen, %d fehlgeschlagen" % [checks.size(), failed])
	for key in checks:
		print("  %s %s" % ["ok  " if checks[key] else "FEHLT", key])
	editor.get_tree().quit()


## Kamera wie in der Referenz: das Kontinentfenster füllt die Bildbreite, Blick schräg von oben.
func _frame() -> void:
	var view: Vector2 = editor.get_viewport().get_visible_rect().size
	var cam: Camera3D = editor.camera_rig.camera
	# Bildwinkel hängt vom Abstand ab: zweimal einpassen.
	for k in 3:
		var distance := LandscapeView.PLANE * 0.98 / (view.x / view.y * 2.0 * tan(deg_to_rad(cam.fov * 0.5)))
		editor.camera_rig.jump_to(Vector3(0.0, 0.0, 40.0), distance)


func _strokes() -> int:
	var c: Dictionary = editor.continent()
	return (c["strokes"] as Array).size() if not c.is_empty() else 0


func _screen_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(p)
	return result


## Linie mit gedrückter linker Maustaste über Referenz-Bildpunkte (fein unterteilt).
func _screen_line(points: PackedVector2Array, closed: bool) -> void:
	var fine := PackedVector2Array()
	for k in points.size():
		var a := points[k]
		var b := points[(k + 1) % points.size()]
		if k == points.size() - 1 and not closed:
			fine.append(a)
			break
		var steps := maxi(1, int(a.distance_to(b) / 12.0))
		for s in steps:
			fine.append(a.lerp(b, float(s) / steps))
	editor._send_mouse(screen_of_ref(fine[0]), true, true)
	await editor._frames(1)
	for k in range(1, fine.size()):
		editor._send_motion(screen_of_ref(fine[k]))
		if k % 3 == 0:
			await editor._frames(1)
	editor._send_mouse(screen_of_ref(fine[fine.size() - 1]), false, true)
	await editor._frames(5)


## Pinselstrich durch Referenz-Bildpunkte (auf den Boden umgerechnet).
func _ground_stroke(points: Array) -> void:
	var ground := []
	for p in points:
		ground.append(ground_of_ref(p))
	await editor._mouse_stroke(ground)


## Werkzeug „Formen bearbeiten“ mit echten Mausereignissen: Umriss wählen, einen Punkt der Ostküste
## nach außen ziehen (dort wird Meer zu Land), Form verschieben, mit Umschalt+Mausrad skalieren,
## die Bucht mit Entf löschen – jeweils mit Rückgängig zurück zum exakt gleichen Stand.
func _edit_shapes(dir: String) -> void:
	var shapes: ShapeEditor = editor.landscape.shape_editor
	var doc: WorldDocument = editor.doc
	var id: String = editor.active_id
	var count := _strokes()
	editor._use_tool("select")
	_frame()
	await editor._frames(10)
	var outline: Dictionary = (editor.continent()["strokes"][0] as Dictionary).duplicate(true)
	var bay: Dictionary = (editor.continent()["strokes"][1] as Dictionary).duplicate(true)
	var history := doc._undo.size()

	# Wählen: Klick ins Landesinnere im Westen.
	var inside := screen_of_ref(Vector2(600, 650))
	await _click(inside)
	checks["Form per Klick gewählt (ohne Verlaufseintrag)"] = shapes.selected == 0 and doc._undo.size() == history

	# Punkt an der Ostküste suchen, der nach außen ins Meer gezogen werden kann.
	var view: Vector2 = editor.get_viewport().get_visible_rect().size
	var poly := ShapeEdit.outline(outline)
	var vertex := -1
	var from := Vector2.ZERO
	var normal := Vector2.ZERO
	var probe := Vector2.ZERO
	var best_x := -INF
	var gw: TerrainWindow = editor.globe_window(id)
	for k in poly.size():
		var s: Vector2 = editor._screen_of(poly[k])
		# Nicht unter der Übersichtskarte (unten rechts), damit das Bild den Griff zeigt.
		if s.x < view.x * 0.6 or s.x <= best_x or s.y < view.y * 0.2 or s.y > view.y * 0.66:
			continue
		var tangent: Vector2 = editor._screen_of(poly[(k + 1) % poly.size()]) - editor._screen_of(poly[k - 1])
		var n := Vector2(tangent.y, -tangent.x).normalized()
		if ShapeEdit.contains(outline, _ground_at(s + n * 20.0)):
			n = -n
		var t := s + n * 60.0
		if t.x > view.x - 30.0 or t.y < 30.0 or t.y > view.y - 30.0:
			continue
		var g := _ground_at(s + n * 38.0)
		if gw.height_at(g.x, g.y) > -5.0 or ShapeEdit.shape_at(editor.continent(), g.x, g.y) >= 0:
			continue
		vertex = k
		from = s
		normal = n
		probe = g
		best_x = s.x
	checks["Küstenpunkt im Osten gefunden"] = vertex >= 0
	if vertex < 0:
		return
	var sea_before := gw.height_at(probe.x, probe.y)

	# Punkt um 60 Bildpunkte nach außen ziehen.
	await _drag(from, from + normal * 60.0)
	var after: Dictionary = editor.continent()["strokes"][0]
	var land_after: float = editor.globe_window(id).height_at(probe.x, probe.y)
	checks["Punkt gezogen: Meer wird Land (%d m → %d m), ein Schritt" % [int(sea_before), int(land_after)]] = \
		land_after > 0.0 and doc._undo.size() == history + 1 and _strokes() == count \
		and not ShapeEdit.same_outline(after, outline) and Stroke.dab_count(after) == poly.size()
	checks["Form bleibt nach der Änderung gewählt"] = shapes.selected == 0
	# Bild: gewählte Form mit Punktgriffen (Oberfläche sichtbar), dann näher am gezogenen Punkt.
	# Erst ohne Oberfläche zeigen (die Übersichtskarte liegt unten rechts über der Ostküste).
	await _hover(from + normal * 60.0 + Vector2(2.0, 1.0))
	checks["Gezogener Punkt unter dem Zeiger erkannt (Griff hervorgehoben)"] = shapes.hovered_vertex == vertex
	editor.ui.visible = true
	await editor._frames(10)
	await editor._shot(dir.path_join("form_gewaehlt.jpg"))
	var moved_point := ShapeEdit.outline(after)[vertex]
	editor.camera_rig.jump_to(editor.landscape.to_render(moved_point.x, moved_point.y), editor.camera_rig.max_distance * 0.3)
	await editor._frames(15)
	await editor._shot(dir.path_join("form_gewaehlt_nah.jpg"))
	editor.ui.visible = false
	_frame()
	await editor._frames(10)
	editor._undo()
	await editor._frames(5)
	checks["Rückgängig: Küste wie vorher (Meer)"] = editor.continent()["strokes"][0] == outline \
		and editor.globe_window(id).height_at(probe.x, probe.y) < 0.0 and shapes.selected == 0

	# Verschieben: im Inneren greifen und 30 Bildpunkte nach Osten ziehen.
	history = doc._undo.size()
	await _drag(inside, inside + Vector2(30.0, 0.0))
	var shifted := ShapeEdit.centroid(editor.continent()["strokes"][0]) - ShapeEdit.centroid(outline)
	checks["Form verschoben (%s nach Osten), ein Schritt" % EditorUI.meters(shifted.x)] = shifted.x > 1000.0 \
		and absf(shifted.y) < shifted.x * 0.5 and doc._undo.size() == history + 1
	editor._undo()
	checks["Rückgängig: Verschieben zurück"] = editor.continent()["strokes"][0] == outline

	# Skalieren: zweimal Umschalt + Mausrad über der Form – ein Schritt nach der Mausrad-Folge.
	history = doc._undo.size()
	await _hover(inside)
	var camera_before: Transform3D = editor.camera_rig.camera.global_transform
	for k in 2:
		_wheel(inside, true, true, false)
		await editor._frames(2)
	var locked: bool = editor._history_locked()
	await editor.get_tree().create_timer(ShapeEditor.WHEEL_COMMIT + 0.4).timeout
	await editor._frames(3)
	var scaled: Dictionary = editor.continent()["strokes"][0]
	checks["Umschalt+Mausrad skaliert (×%s), Kamera bleibt, ein Schritt" % String.num(float(scaled["radius"]) / float(outline["radius"]), 3)] = \
		locked and absf(float(scaled["radius"]) / float(outline["radius"]) - 1.1025) < 0.001 and doc._undo.size() == history + 1 \
		and editor.camera_rig.camera.global_transform.is_equal_approx(camera_before)
	editor._undo()
	checks["Rückgängig: Größe zurück"] = editor.continent()["strokes"][0] == outline

	# Einzelnen Punkt löschen: Zeiger über einen Punkt der Westküste, Entf.
	var west := -1
	var west_x := INF
	for k in poly.size():
		var s: Vector2 = editor._screen_of(poly[k])
		if s.x > 40.0 and s.x < west_x and s.y > view.y * 0.3 and s.y < view.y * 0.7:
			west = k
			west_x = s.x
	history = doc._undo.size()
	await _hover(editor._screen_of(poly[west]))
	var hovered_west := shapes.hovered_vertex == west
	_key(KEY_DELETE)
	await editor._frames(5)
	checks["Punkt unter dem Zeiger mit Entf gelöscht (Form bleibt)"] = hovered_west \
		and Stroke.dab_count(editor.continent()["strokes"][0]) == poly.size() - 1 and _strokes() == count \
		and doc._undo.size() == history + 1 and shapes.selected == 0
	editor._undo()
	checks["Rückgängig: Punkt zurück"] = editor.continent()["strokes"][0] == outline

	# Doppelklick auf den Rand zwischen zwei Punkten fügt dort einen Punkt ein.
	var mid: Vector2 = (editor._screen_of(poly[west]) + editor._screen_of(poly[(west + 1) % poly.size()])) * 0.5
	history = doc._undo.size()
	await _click(mid)
	editor._send_mouse(mid, true, true, true)
	await editor._frames(2)
	editor._send_mouse(mid, false, true)
	await editor._frames(5)
	var inserted: Dictionary = editor.continent()["strokes"][0]
	var new_point := ShapeEdit.outline(inserted)[west + 1] if Stroke.dab_count(inserted) > west + 1 else Vector2(INF, INF)
	checks["Doppelklick auf den Rand fügt einen Punkt ein"] = Stroke.dab_count(inserted) == poly.size() + 1 \
		and doc._undo.size() == history + 1 and editor._screen_of(new_point).distance_to(mid) < 12.0
	editor._undo()
	checks["Rückgängig: eingefügter Punkt weg"] = editor.continent()["strokes"][0] == outline

	# Bucht wählen und mit Entf löschen; Rückgängig setzt sie an dieselbe Stelle zurück.
	var bay_center := ShapeEdit.centroid(bay)
	var bay_screen: Vector2 = editor._screen_of(bay_center)
	await _click(bay_screen)
	var bay_selected := shapes.selected == 1
	_key(KEY_DELETE)
	await editor._frames(5)
	var land_without: float = editor.globe_window(id).height_at(bay_center.x, bay_center.y)
	checks["Bucht gewählt und mit Entf gelöscht (dort Land, %d m)" % int(land_without)] = bay_selected \
		and _strokes() == count - 1 and land_without > 0.0 and shapes.selected == -1
	editor._undo()
	await editor._frames(3)
	checks["Rückgängig: Bucht an derselben Stelle zurück"] = _strokes() == count \
		and editor.continent()["strokes"][1] == bay and editor.globe_window(id).height_at(bay_center.x, bay_center.y) < 0.0
	await _click(inside)
	_key(KEY_ESCAPE)
	await editor._frames(2)
	checks["Esc hebt die Wahl auf"] = shapes.selected == -1

	# Im vertieften Ausschnitt (1:8) an der Westküste: dieselbe Form wählen und einen Punkt ziehen.
	# (Ausschnitt ohne ihn als Region zu merken – sonst trüge das Vergleichsbild einen Rahmen.)
	var coast: Vector2 = poly[west]
	var region_size: float = editor.levels[0]["size"] / editor.FACTOR
	editor.levels.append({"cx": coast.x, "cy": coast.y, "size": region_size})
	editor._show_level()
	editor.camera_rig.jump_to(Vector3.ZERO, editor.camera_rig.max_distance * 0.95)
	await editor._frames(10)
	var inward := (ShapeEdit.centroid(outline) - coast).normalized()
	await _click(editor._screen_of(coast + inward * region_size * 0.2))
	var region_selected := shapes.selected == 0
	history = doc._undo.size()
	var handle: Vector2 = editor._screen_of(coast)
	await _drag(handle, handle - (editor._screen_of(coast + inward * 1000.0) - handle).normalized() * 50.0)
	var region_after: Dictionary = editor.continent()["strokes"][0]
	checks["Im vertieften Ausschnitt wählbar und veränderbar"] = region_selected and doc._undo.size() == history + 1 \
		and not ShapeEdit.same_outline(region_after, outline)
	editor._undo()
	checks["Rückgängig im Ausschnitt"] = editor.continent()["strokes"][0] == outline
	editor.levels.pop_back()
	editor._show_level()
	_frame()
	await editor._frames(5)


## Bodenpunkt (Kontinentmeter) unter einem Bildschirmpunkt, wie ihn das Werkzeug trifft.
func _ground_at(screen: Vector2) -> Vector2:
	var hit: Variant = editor.landscape._hit(screen)
	return editor.landscape.to_continent(hit) if hit != null else Vector2(INF, INF)


func _hover(screen: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen
	e.global_position = screen
	Input.parse_input_event(e)
	await editor._frames(2)


func _click(screen: Vector2) -> void:
	await _hover(screen)
	editor._send_mouse(screen, true, true)
	await editor._frames(2)
	editor._send_mouse(screen, false, true)
	await editor._frames(5)


## Mit gedrückter linker Maustaste von a nach b (in Schritten, wie eine Hand).
func _drag(a: Vector2, b: Vector2) -> void:
	await _hover(a)
	editor._send_mouse(a, true, true)
	await editor._frames(2)
	for k in 12:
		editor._send_motion(a.lerp(b, (k + 1) / 12.0))
		await editor._frames(1)
	editor._send_mouse(b, false, true)
	await editor._frames(5)


func _wheel(screen: Vector2, up: bool, shift: bool, ctrl: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = screen
	e.global_position = screen
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.factor = 1.0
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	Input.parse_input_event(e)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)


## Referenz links, eigenes Bild rechts, gleiche Höhe.
func _side_by_side(own_path: String, out_path: String) -> void:
	var own := Image.load_from_file(own_path)
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE))
	if own == null or ref == null:
		return
	var h := 720
	own.resize(int(own.get_width() * float(h) / own.get_height()), h, Image.INTERPOLATE_LANCZOS)
	ref.resize(int(ref.get_width() * float(h) / ref.get_height()), h, Image.INTERPOLATE_LANCZOS)
	ref.convert(own.get_format())
	var out := Image.create(ref.get_width() + own.get_width() + 12, h, false, own.get_format())
	out.fill(Color(0.06, 0.05, 0.04))
	out.blit_rect(ref, Rect2i(Vector2i.ZERO, ref.get_size()), Vector2i.ZERO)
	out.blit_rect(own, Rect2i(Vector2i.ZERO, own.get_size()), Vector2i(ref.get_width() + 12, 0))
	out.save_jpg(out_path, 0.9)
