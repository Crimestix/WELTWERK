class_name EditorUI
extends CanvasLayer
## Bedienoberfläche des Editors (Wayfarer-Stil: dunkles Holz, Messing, Pergament).
## Baut sich selbst auf und meldet alles über Signale; Entscheidungen trifft der Editor.

signal tool_selected(tool: String)
signal brush_changed(size_fraction: float, strength: float)
signal undo_pressed
signal redo_pressed
signal level_pressed(index: int)
signal variant_pressed
signal globe_pressed
signal edit_continent_pressed
signal marks_toggled(on: bool)
## Wert auf dem Globus geändert; final = Ziehen beendet (dann als rückgängig machbarer Schritt).
## Schlüssel mit "planet." betreffen den Planeten, alle anderen den gewählten Kontinent.
signal placement_changed(key: String, value: float, final: bool)
signal new_continent_pressed(drawn: bool)
signal delete_continent_pressed
signal name_changed(text: String)
## Letzte Erzeugung mit neuem Ausgangswert wiederholen.
signal reroll_pressed
## Klick in die Übersichtskarte: Stelle als Anteil (0–1, x nach Osten, y nach Süden).
signal minimap_clicked(fraction: Vector2)

const WOOD := Color(0.075, 0.06, 0.05, 0.93)
const WOOD_LIGHT := Color(0.16, 0.125, 0.095, 1.0)
const BRASS := Color(0.70, 0.55, 0.30)
const BRASS_BRIGHT := Color(0.88, 0.70, 0.38)
const PARCHMENT := Color(0.91, 0.86, 0.75)
const PARCHMENT_DIM := Color(0.70, 0.65, 0.56)
const EARTH_RADIUS_KM := 6371.0

## Werkzeuge in Gruppen: [Überschrift, [[Werkzeug, Name], …]].
const TOOL_GROUPS := [
	["", [["navigate", "Ansehen"]]],
	["FORM", [["shape_add", "Land zeichnen"], ["shape_remove", "Land wegschneiden"],
		["land_add", "Küste anfügen"], ["land_remove", "Küste abtragen"]]],
	["GELÄNDE", [["raise", "Erhöhen"], ["lower", "Senken"], ["smooth", "Glätten"], ["flatten", "Ebene"],
		["gen_mountains", "Gebirge"], ["gen_hills", "Hügelland"]]],
	["WASSER", [["river", "Fluss"], ["lake", "See"], ["gen_islands", "Inseln"]]],
	["BEWUCHS", [["forest_add", "Wald malen"], ["forest_remove", "Wald entfernen"], ["gen_forest", "Wald verteilen"]]],
	["", [["protect", "Schützen"]]],
]

const HINTS := {
	"navigate": "Rechte Maustaste ziehen verschiebt, Mausrad zoomt. Am Zoom-Anschlag weiterzoomen öffnet einen feineren Ausschnitt.",
	"shape_add": "Linke Maustaste gedrückt halten und einen Umriss ziehen. Beim Loslassen wird er geschlossen und zu Land.",
	"shape_remove": "Einen Umriss ziehen: Das Innere wird zu Meer – für Buchten, Fjorde, Meerengen.",
	"land_add": "Malen fügt Land an – zum Nacharbeiten der Küste.",
	"land_remove": "Malen trägt Land ab – zum Nacharbeiten der Küste.",
	"raise": "Malen hebt das Gelände.",
	"lower": "Malen senkt das Gelände.",
	"smooth": "Malen glättet feines Relief, große Formen bleiben.",
	"flatten": "Malen ebnet auf die Höhe der Stelle ein, an der der Strich beginnt.",
	"gen_mountains": "Entlang des Strichs entsteht ein Gebirgszug – wiederholbar, mit „Neu würfeln“ anders.",
	"gen_hills": "Im Strich entsteht welliges Hügelland.",
	"river": "Den Lauf von der Quelle zur Mündung ziehen. Der Wasserspiegel folgt dem Gefälle und steigt nie an.",
	"lake": "Klicken setzt einen See; der Wasserspiegel richtet sich nach dem niedrigsten Ufer.",
	"gen_islands": "Im Strich entsteht eine Inselgruppe.",
	"forest_add": "Malen legt Wald an.",
	"forest_remove": "Malen entfernt Wald.",
	"gen_forest": "Im Strich entstehen natürliche Waldflecken.",
	"protect": "Geschützte Flächen behalten ihre Grundform – neue Varianten und Erzeugung wirken dort nicht.",
}

## Werkzeuge ohne Stärke-Regler.
const NO_STRENGTH := ["navigate", "shape_add", "shape_remove", "lake", "protect", "flatten"]
const REROLL_TOOLS := ["gen_mountains", "gen_hills", "gen_islands", "gen_forest"]

var _breadcrumb: HBoxContainer
var _undo: Button
var _redo: Button
var _saved: Label
var _tools_panel: PanelContainer
var _tool_buttons := {}
var _context_panel: PanelContainer
var _tool_title: Label
var _tool_hint: Label
var _size_row: Array = []
var _strength_row: Array = []
var _size_slider: HSlider
var _size_label: Label
var _strength_slider: HSlider
var _strength_label: Label
var _reroll: Button
var _continent_actions: HBoxContainer
var _globe_panel: PanelContainer
var _selected_box: VBoxContainer
var _count_label: Label
var _name_edit: LineEdit
var _placement := {}
var _climate_label: Label
var _status: Label
var _minimap_panel: PanelContainer
var _minimap: TextureRect
var _minimap_frame: Panel
var _dragging := {}
var _window_size := 1000.0
var _tool := "navigate"


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)

	# Kopfleiste
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", _box(WOOD, 0, 0))
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	top.add_child(bar)
	var title := Label.new()
	title.text = "WELTWERK"
	title.add_theme_color_override("font_color", BRASS_BRIGHT)
	title.add_theme_font_size_override("font_size", 20)
	bar.add_child(title)
	_breadcrumb = HBoxContainer.new()
	bar.add_child(_breadcrumb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_undo = _button("↶ Rückgängig", func() -> void: undo_pressed.emit())
	_undo.tooltip_text = "Strg/⌘ + Z"
	bar.add_child(_undo)
	_redo = _button("↷ Wiederholen", func() -> void: redo_pressed.emit())
	_redo.tooltip_text = "Strg/⌘ + Y oder Strg/⌘ + Umschalt + Z"
	bar.add_child(_redo)
	_saved = Label.new()
	_saved.custom_minimum_size.x = 150
	bar.add_child(_saved)

	# Werkzeugleiste links, in Gruppen
	_tools_panel = PanelContainer.new()
	_tools_panel.position = Vector2(12, 60)
	root.add_child(_tools_panel)
	var toolbar := VBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 2)
	_tools_panel.add_child(toolbar)
	var group := ButtonGroup.new()
	for entry in TOOL_GROUPS:
		if entry[0] != "":
			var h := _heading(entry[0])
			h.add_theme_font_size_override("font_size", 11)
			toolbar.add_child(h)
		else:
			toolbar.add_child(HSeparator.new())
		for t in entry[1]:
			var b := _button(t[1], _on_tool.bind(t[0]))
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 13)
			toolbar.add_child(b)
			_tool_buttons[t[0]] = b
	(_tool_buttons["navigate"] as Button).button_pressed = true
	toolbar.add_child(HSeparator.new())
	var marks := CheckBox.new()
	marks.text = "Bearbeitungen zeigen"
	marks.button_pressed = true
	marks.focus_mode = Control.FOCUS_NONE
	marks.add_theme_font_size_override("font_size", 12)
	marks.toggled.connect(func(on: bool) -> void: marks_toggled.emit(on))
	toolbar.add_child(marks)

	# Kontextfeld: aktives Werkzeug, Hinweis, Größe, Stärke, ggf. „Neu würfeln“
	_context_panel = PanelContainer.new()
	_context_panel.position = Vector2(200, 60)
	_context_panel.custom_minimum_size.x = 330
	root.add_child(_context_panel)
	var ctx := VBoxContainer.new()
	ctx.add_theme_constant_override("separation", 6)
	_context_panel.add_child(ctx)
	_tool_title = _heading("")
	_tool_title.add_theme_font_size_override("font_size", 16)
	ctx.add_child(_tool_title)
	_tool_hint = _label("")
	_tool_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_hint.custom_minimum_size.x = 310
	_tool_hint.add_theme_color_override("font_color", PARCHMENT_DIM)
	_tool_hint.add_theme_font_size_override("font_size", 13)
	ctx.add_child(_tool_hint)
	var brush := GridContainer.new()
	brush.columns = 3
	brush.add_theme_constant_override("h_separation", 10)
	ctx.add_child(brush)
	var size_title := _label("Größe")
	brush.add_child(size_title)
	_size_slider = _slider(0.0, 1.0, 0.45, 0.001)
	_size_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	brush.add_child(_size_slider)
	_size_label = _label("")
	_size_label.custom_minimum_size.x = 80
	brush.add_child(_size_label)
	_size_row = [size_title, _size_slider, _size_label]
	var strength_title := _label("Stärke")
	brush.add_child(strength_title)
	_strength_slider = _slider(0.05, 1.0, 0.6, 0.01)
	_strength_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	brush.add_child(_strength_slider)
	_strength_label = _label("")
	brush.add_child(_strength_label)
	_strength_row = [strength_title, _strength_slider, _strength_label]
	_reroll = _button("Neu würfeln", func() -> void: reroll_pressed.emit())
	_reroll.tooltip_text = "Die zuletzt erzeugte Fläche mit neuem Ausgangswert – gleicher Ort, andere Form."
	ctx.add_child(_reroll)

	# Kontinent-Aktionen
	_continent_actions = HBoxContainer.new()
	_continent_actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_continent_actions.position = Vector2(-220, -64)
	_continent_actions.add_theme_constant_override("separation", 10)
	root.add_child(_continent_actions)
	var variant := _button("Variante erzeugen", func() -> void: variant_pressed.emit())
	variant.tooltip_text = "Neue Grundform aus neuem Ausgangswert – Bearbeitungen und geschützte Flächen bleiben erhalten."
	_continent_actions.add_child(variant)
	_continent_actions.add_child(_button("Zum Globus", func() -> void: globe_pressed.emit()))

	# Globus: Planet und Kontinente
	_globe_panel = PanelContainer.new()
	_globe_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_globe_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_globe_panel.offset_right = -12
	_globe_panel.offset_left = -412
	_globe_panel.offset_top = 60
	_globe_panel.custom_minimum_size.x = 400
	root.add_child(_globe_panel)
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 6)
	_globe_panel.add_child(g)
	g.add_child(_heading("PLANET"))
	var pgrid := _grid()
	g.add_child(pgrid)
	_add_placement(pgrid, "planet.radius_km", "Größe", WorldDocument.MIN_RADIUS_KM, WorldDocument.MAX_RADIUS_KM, 10.0)
	g.add_child(HSeparator.new())
	g.add_child(_heading("KONTINENTE"))
	_count_label = _label("")
	_count_label.add_theme_color_override("font_color", PARCHMENT_DIM)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count_label.custom_minimum_size.x = 370
	_count_label.add_theme_font_size_override("font_size", 13)
	g.add_child(_count_label)
	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	g.add_child(new_row)
	var draw := _button("Neu zeichnen", func() -> void: new_continent_pressed.emit(true))
	draw.tooltip_text = "Leere Meeresfläche in der Bildmitte – Umriss selbst zeichnen."
	new_row.add_child(draw)
	var gen := _button("Neu erzeugen", func() -> void: new_continent_pressed.emit(false))
	gen.tooltip_text = "Erzeugte Grundform als Ausgangspunkt – danach frei bearbeiten."
	new_row.add_child(gen)

	_selected_box = VBoxContainer.new()
	_selected_box.add_theme_constant_override("separation", 6)
	g.add_child(_selected_box)
	_selected_box.add_child(HSeparator.new())
	_selected_box.add_child(_heading("GEWÄHLTER KONTINENT"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name (frei lassen oder selbst vergeben)"
	_name_edit.text_submitted.connect(func(text: String) -> void:
		name_changed.emit(text)
		_name_edit.release_focus())
	_name_edit.focus_exited.connect(func() -> void: name_changed.emit(_name_edit.text))
	_selected_box.add_child(_name_edit)
	var grid := _grid()
	_selected_box.add_child(grid)
	_add_placement(grid, "size_km", "Größe", 200.0, 6000.0, 10.0)
	_add_placement(grid, "latitude", "Breitengrad", -80.0, 80.0, 0.5)
	_add_placement(grid, "longitude", "Längengrad", -180.0, 180.0, 0.5)
	_add_placement(grid, "heading", "Ausrichtung", 0.0, 359.0, 1.0)
	_selected_box.add_child(_heading("KLIMA AUS LAGE"))
	_climate_label = _label("")
	_climate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_climate_label.custom_minimum_size.x = 370
	_climate_label.add_theme_font_size_override("font_size", 13)
	_selected_box.add_child(_climate_label)
	var cgrid := _grid()
	_selected_box.add_child(cgrid)
	_add_placement(cgrid, "climate_override.snowline_offset", "Schneegrenze", -2000.0, 2000.0, 50.0)
	_add_placement(cgrid, "climate_override.humidity_offset", "Feuchter", -0.5, 0.5, 0.05)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_selected_box.add_child(actions)
	actions.add_child(_button("Kontinent öffnen", func() -> void: edit_continent_pressed.emit()))
	var delete := _button("Löschen", func() -> void: delete_continent_pressed.emit())
	delete.tooltip_text = "Kontinent entfernen (Rückgängig mit Strg/⌘ + Z)."
	delete.add_theme_color_override("font_color", Color(0.85, 0.45, 0.38))
	actions.add_child(delete)

	# Übersichtskarte unten rechts
	_minimap_panel = PanelContainer.new()
	_minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap_panel.position = Vector2(-212, -244)
	root.add_child(_minimap_panel)
	_minimap = TextureRect.new()
	_minimap.custom_minimum_size = Vector2(180, 180)
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.tooltip_text = "Übersicht des Kontinents – Klick springt dorthin."
	_minimap.gui_input.connect(_on_minimap_input)
	_minimap_panel.add_child(_minimap)
	_minimap_frame = Panel.new()
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = BRASS_BRIGHT
	frame_style.set_border_width_all(2)
	_minimap_frame.add_theme_stylebox_override("panel", frame_style)
	_minimap.add_child(_minimap_frame)

	# Statuszeile
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.position.y = -26
	_status.offset_left = 16
	_status.add_theme_color_override("font_color", PARCHMENT_DIM)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("outline_size", 4)
	_status.add_theme_font_size_override("font_size", 13)
	root.add_child(_status)

	_show_tool("navigate")
	_emit_brush()


# --- Von außen gesetzt ---------------------------------------------------------------------

func set_mode(globe: bool, continent_level: bool, has_selection: bool = true) -> void:
	_globe_panel.visible = globe
	_selected_box.visible = has_selection
	_tools_panel.visible = not globe
	_context_panel.visible = not globe
	_continent_actions.visible = not globe and continent_level
	_minimap_panel.visible = not globe


func set_levels(names: Array, current: int) -> void:
	for child in _breadcrumb.get_children():
		child.queue_free()
	for i in names.size():
		if i > 0:
			_breadcrumb.add_child(_label("/"))
		var b := _button(names[i], func() -> void: level_pressed.emit(i))
		b.flat = true
		if i == current:
			b.add_theme_color_override("font_color", BRASS_BRIGHT)
		_breadcrumb.add_child(b)


func set_history(can_undo: bool, can_redo: bool) -> void:
	_undo.disabled = not can_undo
	_redo.disabled = not can_redo


func set_saved(saved: bool) -> void:
	_saved.text = "✓ Gespeichert" if saved else "Wird gespeichert …"
	_saved.add_theme_color_override("font_color", PARCHMENT_DIM if saved else BRASS)


func set_status(text: String) -> void:
	_status.text = text


func set_window_size(meters: float) -> void:
	_window_size = meters
	_emit_brush()


## Werkzeug von außen wählen (z. B. „Land zeichnen“ nach „Neu zeichnen“).
func select_tool(tool: String) -> void:
	if _tool_buttons.has(tool):
		(_tool_buttons[tool] as Button).button_pressed = true
	_show_tool(tool)


## Pinselregler setzen (Größe als Anteil des Ausschnitts, Stärke 0–1).
func set_brush(fraction: float, strength: float) -> void:
	_size_slider.set_value_no_signal(clampf(log(fraction / 0.005) / log(40.0), 0.0, 1.0))
	_strength_slider.set_value_no_signal(strength)
	_emit_brush()


func set_reroll_available(on: bool) -> void:
	_reroll.disabled = not on


func set_continent_count(count: int) -> void:
	_count_label.text = ("%d Kontinent%s auf dem Globus · Klick wählt, Ziehen verschiebt, Doppelklick öffnet" % [count, "" if count == 1 else "e"]) \
		if count > 0 else "Noch kein Kontinent – „Neu zeichnen“ oder „Neu erzeugen“."


func set_planet(planet: Dictionary) -> void:
	_set_slider("planet.radius_km", planet["radius_km"])


func set_placement(continent: Dictionary, climate: Dictionary) -> void:
	if continent.is_empty():
		return
	if not _name_edit.has_focus():
		_name_edit.text = continent.get("name", "")
	for key in _placement:
		if not (key as String).begins_with("planet."):
			_set_slider(key, _value_of(continent, key))
	var derived: Dictionary = climate["derived"]
	_climate_label.text = "%s · Schneegrenze %s (aus Lage %s) · Baumgrenze %s · Trockenheit %d %%\nNur ein Hinweis – mit den Reglern anpassen." % [
		climate["zone"], meters(climate["snowline"]), meters(derived["snowline"]),
		meters(climate["treeline"]), int(round(climate["dryness"] * 100.0))]


## Übersichtskarte: Bild des Kontinents und Rahmen des sichtbaren Ausschnitts (Anteile 0–1).
func set_minimap(image: Image, view: Rect2) -> void:
	if image:
		_minimap.texture = ImageTexture.create_from_image(image)
	var s := _minimap.custom_minimum_size
	var r := Rect2(view.position * s, view.size * s)
	r.size = r.size.max(Vector2(4, 4))
	_minimap_frame.position = r.position
	_minimap_frame.size = r.size


# --- Intern --------------------------------------------------------------------------------

func _on_tool(tool: String) -> void:
	_show_tool(tool)
	tool_selected.emit(tool)


func _show_tool(tool: String) -> void:
	_tool = tool
	var name := ""
	for entry in TOOL_GROUPS:
		for t in entry[1]:
			if t[0] == tool:
				name = t[1]
	_tool_title.text = "Werkzeug: " + name
	_tool_hint.text = HINTS.get(tool, "")
	for c in _size_row:
		c.visible = tool not in ["navigate", "shape_add", "shape_remove"]
	for c in _strength_row:
		c.visible = tool not in NO_STRENGTH
	_reroll.visible = tool in REROLL_TOOLS


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		minimap_clicked.emit((event as InputEventMouseButton).position / _minimap.size)
		_minimap.accept_event()


func _emit_brush() -> void:
	var fraction := size_fraction()
	_size_label.text = meters(fraction * _window_size)
	_strength_label.text = "%d %%" % int(round(_strength_slider.value * 100.0))
	brush_changed.emit(fraction, _strength_slider.value)


## Pinselgröße als Anteil des Ausschnitts (0,5 % bis 20 %, logarithmisch).
func size_fraction() -> float:
	return 0.005 * pow(40.0, _size_slider.value)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	return grid


func _set_slider(key: String, value: float) -> void:
	if _dragging.get(key, false) or not _placement.has(key):
		return
	var slider: HSlider = _placement[key][0]
	slider.set_value_no_signal(value)
	_update_placement_label(key, slider.value)


func _add_placement(grid: GridContainer, key: String, title: String, low: float, high: float, step: float) -> void:
	grid.add_child(_label(title))
	var slider := _slider(low, high, low, step)
	slider.custom_minimum_size.x = 170
	grid.add_child(slider)
	var value := _label("")
	value.custom_minimum_size.x = 100
	grid.add_child(value)
	_placement[key] = [slider, value]
	slider.drag_started.connect(func() -> void: _dragging[key] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging[key] = false
		placement_changed.emit(key, slider.value, true))
	slider.value_changed.connect(func(v: float) -> void:
		_update_placement_label(key, v)
		placement_changed.emit(key, v, not _dragging.get(key, false)))


func _update_placement_label(key: String, v: float) -> void:
	var label: Label = _placement[key][1]
	match key:
		"planet.radius_km": label.text = "%s × Erde" % _number(v / EARTH_RADIUS_KM, 2)
		"size_km": label.text = "%s km" % _number(v, 0)
		"latitude": label.text = "%s° %s" % [_number(absf(v), 1), "N" if v >= 0.0 else "S"]
		"longitude": label.text = "%s° %s" % [_number(absf(v), 1), "O" if v >= 0.0 else "W"]
		"heading": label.text = "%d°" % int(v)
		"climate_override.snowline_offset": label.text = "%s m" % _number(v, 0)
		"climate_override.humidity_offset": label.text = "%+d %%" % int(round(v * 100.0))
	if key == "planet.radius_km":
		label.tooltip_text = "Radius %s km" % _number(v, 0)


static func _value_of(continent: Dictionary, key: String) -> float:
	var target: Variant = continent
	for part in key.split("."):
		target = target[part]
	return float(target)


## Meter lesbar: „320 m“, „12,5 km“.
static func meters(v: float) -> String:
	if absf(v) >= 10000.0:
		return "%s km" % _number(v / 1000.0, 0)
	if absf(v) >= 1000.0:
		return "%s km" % _number(v / 1000.0, 1)
	return "%s m" % _number(v, 0)


static func _number(v: float, decimals: int) -> String:
	var text := String.num(v, decimals) if decimals > 0 else str(int(round(v)))
	if decimals > 0 and not text.contains("."):
		text += "." + "0".repeat(decimals)
	var parts := text.split(".")
	var whole := parts[0]
	var sign := ""
	if whole.begins_with("-"):
		sign = "−"
		whole = whole.substr(1)
	var grouped := ""
	while whole.length() > 3:
		grouped = "." + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	grouped = whole + grouped
	return sign + grouped + ("," + parts[1] if parts.size() > 1 else "")


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", BRASS_BRIGHT)
	l.add_theme_font_size_override("font_size", 14)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _slider(low: float, high: float, value: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(160, 20)
	s.focus_mode = Control.FOCUS_NONE
	return s


func _box(color: Color, border: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = BRASS
	s.set_border_width_all(border)
	s.border_width_bottom = maxi(border, 1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	return s


func _theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("panel", "PanelContainer", _box(WOOD, 1, 6))
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_font_size("font_size", "Label", 14)
	var normal := _box(WOOD_LIGHT, 1, 4)
	normal.set_content_margin_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = WOOD_LIGHT.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.40, 0.29, 0.13)
	pressed.border_color = BRASS_BRIGHT
	pressed.set_border_width_all(2)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.085, 0.07)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.86, 0.55))
	t.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.86, 0.55))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.42, 0.38))
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "CheckBox", PARCHMENT)
	var edit := _box(Color(0.05, 0.04, 0.035, 1.0), 1, 4)
	edit.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", PARCHMENT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.46, 0.4))
	return t
