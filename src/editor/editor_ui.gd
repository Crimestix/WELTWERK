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
signal placement_changed(key: String, value: float, final: bool)

const WOOD := Color(0.075, 0.06, 0.05, 0.93)
const WOOD_LIGHT := Color(0.16, 0.125, 0.095, 1.0)
const BRASS := Color(0.70, 0.55, 0.30)
const BRASS_BRIGHT := Color(0.88, 0.70, 0.38)
const PARCHMENT := Color(0.91, 0.86, 0.75)
const PARCHMENT_DIM := Color(0.70, 0.65, 0.56)

const TOOLS := [
	["navigate", "Navigieren"],
	["land_add", "Land hinzufügen"],
	["land_remove", "Land abtragen"],
	["raise", "Erhöhen"],
	["lower", "Senken"],
	["smooth", "Glätten"],
	["water", "Gewässer"],
	["forest_add", "Wald malen"],
	["forest_remove", "Wald entfernen"],
]

var _breadcrumb: HBoxContainer
var _undo: Button
var _redo: Button
var _saved: Label
var _toolbar: VBoxContainer
var _tool_buttons := {}
var _brush_panel: PanelContainer
var _size_slider: HSlider
var _size_label: Label
var _strength_slider: HSlider
var _strength_label: Label
var _continent_actions: HBoxContainer
var _globe_panel: PanelContainer
var _placement := {}
var _climate_label: Label
var _status: Label
var _dragging := {}
var _window_size := 1000.0


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

	# Werkzeugleiste links
	var tools_panel := PanelContainer.new()
	tools_panel.position = Vector2(12, 64)
	root.add_child(tools_panel)
	_toolbar = VBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	tools_panel.add_child(_toolbar)
	var group := ButtonGroup.new()
	for entry in TOOLS:
		var b := _button(entry[1], _on_tool.bind(entry[0]))
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_toolbar.add_child(b)
		_tool_buttons[entry[0]] = b
	(_tool_buttons["navigate"] as Button).button_pressed = true

	# Pinsel
	_brush_panel = PanelContainer.new()
	_brush_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_brush_panel.position = Vector2(12, -150)
	_brush_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_brush_panel)
	var brush := GridContainer.new()
	brush.columns = 3
	brush.add_theme_constant_override("h_separation", 10)
	_brush_panel.add_child(brush)
	brush.add_child(_label("Größe"))
	_size_slider = _slider(0.0, 1.0, 0.45, 0.001)
	_size_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	brush.add_child(_size_slider)
	_size_label = _label("")
	_size_label.custom_minimum_size.x = 80
	brush.add_child(_size_label)
	brush.add_child(_label("Stärke"))
	_strength_slider = _slider(0.05, 1.0, 0.6, 0.01)
	_strength_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	brush.add_child(_strength_slider)
	_strength_label = _label("")
	brush.add_child(_strength_label)
	var marks := CheckBox.new()
	marks.text = "Bearbeitungen zeigen"
	marks.button_pressed = true
	marks.toggled.connect(func(on: bool) -> void: marks_toggled.emit(on))
	brush.add_child(Control.new())
	brush.add_child(marks)

	# Kontinent-Aktionen
	_continent_actions = HBoxContainer.new()
	_continent_actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_continent_actions.position = Vector2(-220, -64)
	_continent_actions.add_theme_constant_override("separation", 10)
	root.add_child(_continent_actions)
	var variant := _button("Variante erzeugen", func() -> void: variant_pressed.emit())
	variant.tooltip_text = "Neue Grundform aus neuem Ausgangswert – deine Bearbeitungen bleiben erhalten."
	_continent_actions.add_child(variant)
	_continent_actions.add_child(_button("Auf Globus platzieren", func() -> void: globe_pressed.emit()))

	# Globus: Kontinent platzieren
	_globe_panel = PanelContainer.new()
	_globe_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_globe_panel.position = Vector2(-372, 64)
	_globe_panel.custom_minimum_size.x = 360
	root.add_child(_globe_panel)
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 6)
	_globe_panel.add_child(g)
	g.add_child(_heading("KONTINENT PLATZIEREN"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	g.add_child(grid)
	_add_placement(grid, "size_km", "Größe", 200.0, 3000.0, 10.0)
	_add_placement(grid, "latitude", "Breitengrad", -80.0, 80.0, 0.5)
	_add_placement(grid, "longitude", "Längengrad", -180.0, 180.0, 0.5)
	_add_placement(grid, "heading", "Ausrichtung", 0.0, 359.0, 1.0)
	g.add_child(HSeparator.new())
	g.add_child(_heading("KLIMA AUS LAGE"))
	_climate_label = _label("")
	_climate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.add_child(_climate_label)
	var cgrid := GridContainer.new()
	cgrid.columns = 3
	cgrid.add_theme_constant_override("h_separation", 8)
	g.add_child(cgrid)
	_add_placement(cgrid, "climate_override.snowline_offset", "Schneegrenze", -2000.0, 2000.0, 50.0)
	_add_placement(cgrid, "climate_override.humidity_offset", "Feuchter", -0.5, 0.5, 0.05)
	g.add_child(_button("Kontinent bearbeiten", func() -> void: edit_continent_pressed.emit()))

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

	_emit_brush()


# --- Von außen gesetzt ---------------------------------------------------------------------

func set_mode(globe: bool, continent_level: bool) -> void:
	_globe_panel.visible = globe
	_toolbar.get_parent().visible = not globe
	_brush_panel.visible = not globe
	_continent_actions.visible = not globe and continent_level


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


func set_placement(continent: Dictionary, climate: Dictionary) -> void:
	for key in _placement:
		if _dragging.get(key, false):
			continue
		var slider: HSlider = _placement[key][0]
		slider.set_value_no_signal(_value_of(continent, key))
		_update_placement_label(key, slider.value)
	var derived: Dictionary = climate["derived"]
	_climate_label.text = "%s · Schneegrenze %s (aus Lage %s) · Baumgrenze %s · Trockenheit %d %%\nNur ein Hinweis – mit den Reglern anpassen." % [
		climate["zone"], meters(climate["snowline"]), meters(derived["snowline"]),
		meters(climate["treeline"]), int(round(climate["dryness"] * 100.0))]


# --- Intern --------------------------------------------------------------------------------

func _on_tool(tool: String) -> void:
	tool_selected.emit(tool)


func _emit_brush() -> void:
	var fraction := size_fraction()
	_size_label.text = meters(fraction * _window_size)
	_strength_label.text = "%d %%" % int(round(_strength_slider.value * 100.0))
	brush_changed.emit(fraction, _strength_slider.value)


## Pinselgröße als Anteil des Ausschnitts (0,5 % bis 20 %, logarithmisch).
func size_fraction() -> float:
	return 0.005 * pow(40.0, _size_slider.value)


func _add_placement(grid: GridContainer, key: String, title: String, low: float, high: float, step: float) -> void:
	grid.add_child(_label(title))
	var slider := _slider(low, high, low, step)
	slider.custom_minimum_size.x = 170
	grid.add_child(slider)
	var value := _label("")
	value.custom_minimum_size.x = 80
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
		"size_km": label.text = "%s km" % _number(v, 0)
		"latitude": label.text = "%s° %s" % [_number(absf(v), 1), "N" if v >= 0.0 else "S"]
		"longitude": label.text = "%s° %s" % [_number(absf(v), 1), "O" if v >= 0.0 else "W"]
		"heading": label.text = "%d°" % int(v)
		"climate_override.snowline_offset": label.text = "%s m" % _number(v, 0)
		"climate_override.humidity_offset": label.text = "%+d %%" % int(round(v * 100.0))


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
	normal.set_content_margin_all(6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = WOOD_LIGHT.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.36, 0.27, 0.14)
	pressed.border_color = BRASS_BRIGHT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.085, 0.07)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", BRASS_BRIGHT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.42, 0.38))
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "CheckBox", PARCHMENT)
	return t
