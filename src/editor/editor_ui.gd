class_name EditorUI
extends CanvasLayer
## Bedienoberfläche des Editors (Wayfarer-Stil: geschwärztes Holz, Leder, Messing, Pergament).
## Baut sich selbst auf und meldet alles über Signale; Entscheidungen trifft der Editor.
##
## Aufbau: Kopfleiste (Pfad Welt / Kontinent / Region, Rückgängig, Gespeichert) · schmale
## Leiste links mit wenigen Werkzeuggruppen · nach Wahl einer Gruppe deren Werkzeuge unten in der
## Mitte · erst nach Wahl eines Werkzeugs eine kleine Karte mit seinen Einstellungen · eine dezente
## Hinweiszeile, die von selbst verblasst · Übersichtskarte mit Nordpfeil, Maßstab unten links.
## Auf dem Globus: rechts „Kontinent platzieren“, unten links „Planet einstellen“.

signal tool_selected(tool: String)
signal brush_changed(size_fraction: float, strength: float)
signal undo_pressed
signal redo_pressed
## Pfad: 0 = Welt (Globus), 1 = Kontinent, 2 = Region (bleibt).
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

const WOOD := Color(0.075, 0.06, 0.05, 0.94)
const WOOD_DARK := Color(0.05, 0.04, 0.034, 0.97)
const WOOD_LIGHT := Color(0.16, 0.125, 0.095, 1.0)
const LEATHER := Color(0.23, 0.16, 0.10, 1.0)
const BRASS := Color(0.70, 0.55, 0.30)
const BRASS_BRIGHT := Color(0.88, 0.70, 0.38)
const BRASS_LINE := Color(0.70, 0.55, 0.30, 0.38)
const PARCHMENT := Color(0.91, 0.86, 0.75)
const PARCHMENT_DIM := Color(0.70, 0.65, 0.56)
const BLOOD := Color(0.62, 0.17, 0.14)
const BLOOD_TEXT := Color(0.88, 0.47, 0.40)
const EARTH_RADIUS_KM := 6371.0
const ICON_DIR := "res://assets/ui/icons/"
const TOP_HEIGHT := 48.0
const RAIL_WIDTH := 60.0
const MINIMAP_SIZE := 172.0

## Werkzeuggruppen: [Kennung, Name, Bild, [[Werkzeug, Name], …]]. „Schützen“ gehört zum Gelände
## (es hält die Grundform einer Fläche fest).
const GROUPS := [
	["view", "Ansehen", "view", []],
	["form", "Form", "form", [["select", "Formen bearbeiten"], ["shape_add", "Land zeichnen"],
		["shape_remove", "Land wegschneiden"], ["land_add", "Küste anfügen"], ["land_remove", "Küste abtragen"],
		["gen_islands", "Inseln"]]],
	["terrain", "Gelände", "terrain", [["raise", "Erhöhen"], ["lower", "Senken"], ["smooth", "Glätten"],
		["flatten", "Ebene"], ["gen_mountains", "Gebirge"], ["gen_hills", "Hügelland"], ["protect", "Schützen"]]],
	["water", "Wasser", "water", [["river", "Fluss"], ["lake", "See"]]],
	["vegetation", "Bewuchs", "vegetation", [["forest_add", "Wald malen"], ["forest_remove", "Wald entfernen"],
		["gen_forest", "Wald verteilen"]]],
]

const GROUP_TIPS := {
	"view": "Ansehen – verschieben und zoomen, nichts verändern",
	"form": "Form – Umrisse zeichnen, wegschneiden, Küsten nacharbeiten, Inseln",
	"terrain": "Gelände – erhöhen, senken, glätten, Gebirge und Hügelland, Flächen schützen",
	"water": "Wasser – Flüsse und Seen",
	"vegetation": "Bewuchs – Wald malen, entfernen oder natürlich verteilen",
}

const HINTS := {
	"navigate": "Rechte Maustaste zieht die Karte, Mausrad zoomt. Am Zoom-Anschlag weiter: feinere Region.",
	"select": "Form anklicken: ziehen verschiebt, Punkte ziehen formt um, Doppelklick auf den Rand fügt einen Punkt ein, Entf löscht; Umschalt+Mausrad skaliert, Strg+Mausrad dreht.",
	"shape_add": "Mit gedrückter linker Maustaste einen Umriss ziehen – beim Loslassen wird er Land.",
	"shape_remove": "Einen Umriss ziehen: Das Innere wird Meer – für Buchten, Fjorde, Meerengen.",
	"land_add": "Malen fügt Land an der Küste an.",
	"land_remove": "Malen trägt Land an der Küste ab.",
	"gen_islands": "Im Strich entsteht eine Inselgruppe.",
	"raise": "Malen hebt das Gelände.",
	"lower": "Malen senkt das Gelände.",
	"smooth": "Malen glättet feines Relief, große Formen bleiben.",
	"flatten": "Malen ebnet auf die Höhe der Stelle ein, an der der Strich beginnt.",
	"gen_mountains": "Entlang des Strichs entsteht ein Gebirgszug – mit „Neu würfeln“ anders.",
	"gen_hills": "Im Strich entsteht welliges Hügelland.",
	"protect": "Geschützte Flächen behalten ihre Form – Varianten und Erzeugung wirken dort nicht.",
	"river": "Den Lauf von der Quelle zur Mündung ziehen; der Wasserspiegel folgt dem Gefälle.",
	"lake": "Klicken setzt einen See; der Spiegel richtet sich nach dem niedrigsten Ufer.",
	"forest_add": "Malen legt Wald an.",
	"forest_remove": "Malen entfernt Wald.",
	"gen_forest": "Im Strich entstehen natürliche Waldflecken.",
}

## Werkzeuge ohne Einstellungen (keine Karte).
const NO_SETTINGS := ["navigate", "select", "shape_add", "shape_remove"]
## Werkzeuge ohne Stärke-Regler.
const NO_STRENGTH := ["navigate", "select", "shape_add", "shape_remove", "lake", "river", "protect", "flatten"]
const REROLL_TOOLS := ["gen_mountains", "gen_hills", "gen_islands", "gen_forest"]
## Anfangsgröße (Reglerstellung 0–1) für Werkzeuge, die sonst zu grob begännen.
const DEFAULT_SIZE := {"river": 0.4, "lake": 0.35}
const HINT_SECONDS := 6.0
const NOTICE_SECONDS := 5.0

var _icons := {}
## Größe und Stärke je Werkzeug (Reglerstellungen).
var _tool_brush := {}
var _breadcrumb: HBoxContainer
var _crumbs: Array[Button] = []
var _back_pill: Button
var _undo: Button
var _redo: Button
var _saved: Label
var _saved_icon: TextureRect
var _rail: PanelContainer
var _group_buttons := {}
var _toolbar: PanelContainer
var _group_rows := {}
var _tool_buttons := {}
var _card: PanelContainer
var _card_icon: TextureRect
var _card_title: Label
var _size_row: Control
var _strength_row: Control
var _size_slider: HSlider
var _size_label: Label
var _strength_slider: HSlider
var _strength_label: Label
var _reroll: Button
var _variant_bar: Control
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_tween: Tween
var _hint_is_notice := false
var _hint_style: StyleBoxFlat
var _notice_style: StyleBoxFlat
var _scale_bar: ScaleBar
var _minimap_panel: PanelContainer
var _minimap: TextureRect
var _minimap_frame: Panel
var _marks: Button
var _globe_panel: PanelContainer
var _globe_title: Label
var _selected_box: VBoxContainer
var _count_label: Label
var _facts_label: Label
var _warning_label: Label
var _name_edit: LineEdit
var _placement := {}
var _climate_toggle: Button
var _climate_box: VBoxContainer
var _climate_label: Label
var _planet_toggle: Button
var _planet_box: PanelContainer
var _dragging := {}
var _window_size := 1000.0
var _tool := "navigate"
var _group := "view"
var _globe := false
var _continent_level := true
var _has_selection := false
var _variant_available := false
var _facts := ""
var _warning := ""
var _shown_navigation_hint := false
var _crumb_current := 0
var _crumb_count := 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_build_top_bar(root)
	_build_rail(root)
	_build_toolbar(root)
	_build_card(root)
	_build_variant_bar(root)
	_build_hint(root)
	_build_scale_bar(root)
	_build_minimap(root)
	_build_globe_panel(root)
	_build_planet(root)
	_select_group("view", false)
	_emit_brush()
	# Frei liegende Knöpfe auf ihre Mindestgröße bringen (vor dem Thema war das Bild noch groß).
	_marks.reset_size()
	_back_pill.reset_size()


# --- Aufbau --------------------------------------------------------------------------------

func _build_top_bar(root: Control) -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_HEIGHT
	var style := _box(WOOD_DARK, 0, 0)
	style.border_width_bottom = 1
	style.border_color = BRASS_LINE
	style.content_margin_left = 18
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	top.add_theme_stylebox_override("panel", style)
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	top.add_child(bar)
	var mark := _icon_rect("terrain", 22)
	mark.modulate = BRASS_BRIGHT
	bar.add_child(mark)
	var title := Label.new()
	title.text = "WELTWERK"
	var wordmark := FontVariation.new()
	wordmark.base_font = ThemeDB.fallback_font
	wordmark.spacing_glyph = 3
	wordmark.variation_embolden = 0.4
	title.add_theme_font_override("font", wordmark)
	title.add_theme_color_override("font_color", BRASS_BRIGHT)
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	bar.add_child(VSeparator.new())
	_breadcrumb = HBoxContainer.new()
	_breadcrumb.add_theme_constant_override("separation", 2)
	bar.add_child(_breadcrumb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_undo = _icon_button("undo", "Rückgängig (Strg/⌘ + Z)", func() -> void: undo_pressed.emit())
	bar.add_child(_undo)
	_redo = _icon_button("redo", "Wiederholen (Strg/⌘ + Y oder Strg/⌘ + Umschalt + Z)", func() -> void: redo_pressed.emit())
	bar.add_child(_redo)
	bar.add_child(VSeparator.new())
	_saved_icon = _icon_rect("check", 16)
	bar.add_child(_saved_icon)
	_saved = Label.new()
	_saved.custom_minimum_size.x = 128
	_saved.add_theme_font_size_override("font_size", 14)
	bar.add_child(_saved)

	# „‹ Kontinent“ unter der Kopfleiste, nur in einer Region.
	_back_pill = Button.new()
	_back_pill.text = "Kontinent"
	_back_pill.icon = _icon("chevron_left")
	_back_pill.theme_type_variation = "PillButton"
	_back_pill.focus_mode = Control.FOCUS_NONE
	_back_pill.tooltip_text = "Zurück zur Übersicht des ganzen Kontinents"
	_back_pill.position = Vector2(RAIL_WIDTH + 14.0, TOP_HEIGHT + 12.0)
	_back_pill.pressed.connect(func() -> void: level_pressed.emit(1))
	root.add_child(_back_pill)


func _build_rail(root: Control) -> void:
	_rail = PanelContainer.new()
	_rail.anchor_bottom = 1.0
	_rail.offset_top = TOP_HEIGHT
	_rail.offset_right = RAIL_WIDTH
	var style := _box(WOOD, 0, 0)
	style.border_width_right = 1
	style.border_color = BRASS_LINE
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_rail.add_theme_stylebox_override("panel", style)
	root.add_child(_rail)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_rail.add_child(column)
	var group := ButtonGroup.new()
	for entry in GROUPS:
		var id: String = entry[0]
		var b := Button.new()
		b.icon = _icon(entry[2])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "RailButton"
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = GROUP_TIPS[id]
		b.pressed.connect(_on_group_button.bind(id))
		column.add_child(b)
		_group_buttons[id] = b
		if id == "view":
			var line := HSeparator.new()
			line.custom_minimum_size.y = 6
			column.add_child(line)


func _build_toolbar(root: Control) -> void:
	_toolbar = PanelContainer.new()
	_anchor_bottom_center(_toolbar, 16.0)
	var style := _box(WOOD, 1, 8)
	style.border_color = BRASS_LINE
	style.set_content_margin_all(6)
	_toolbar.add_theme_stylebox_override("panel", style)
	root.add_child(_toolbar)
	var stack := HBoxContainer.new()
	_toolbar.add_child(stack)
	var tools := ButtonGroup.new()
	tools.allow_unpress = true
	for entry in GROUPS:
		if (entry[3] as Array).is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		stack.add_child(row)
		_group_rows[entry[0]] = row
		var first := true
		for t in entry[3]:
			if not first:
				var line := VSeparator.new()
				line.custom_minimum_size.x = 2
				row.add_child(line)
			first = false
			var b := Button.new()
			b.text = t[1]
			b.icon = _icon(t[0])
			b.toggle_mode = true
			b.button_group = tools
			b.focus_mode = Control.FOCUS_NONE
			b.theme_type_variation = "ToolButton"
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.custom_minimum_size = Vector2(86, 58)
			b.tooltip_text = HINTS.get(t[0], "")
			b.pressed.connect(_on_tool_button.bind(t[0]))
			row.add_child(b)
			_tool_buttons[t[0]] = b


func _build_card(root: Control) -> void:
	_card = PanelContainer.new()
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -292
	_card.offset_right = -16
	_card.offset_top = TOP_HEIGHT + 16.0
	root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_card_icon = _icon_rect("terrain", 22)
	_card_icon.modulate = BRASS_BRIGHT
	head.add_child(_card_icon)
	_card_title = _heading("")
	_card_title.add_theme_font_size_override("font_size", 16)
	head.add_child(_card_title)
	box.add_child(HSeparator.new())

	_size_slider = _slider(0.0, 1.0, 0.45, 0.001)
	_size_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	_size_label = _value_label()
	_size_row = _setting_block("Größe", _size_slider, _size_label)
	box.add_child(_size_row)
	_strength_slider = _slider(0.05, 1.0, 0.6, 0.01)
	_strength_slider.value_changed.connect(func(_v: float) -> void: _emit_brush())
	_strength_label = _value_label()
	_strength_row = _setting_block("Stärke", _strength_slider, _strength_label)
	box.add_child(_strength_row)
	_reroll = _button("Neu würfeln", func() -> void: reroll_pressed.emit())
	_reroll.icon = _icon("dice")
	_reroll.tooltip_text = "Die zuletzt erzeugte Fläche mit neuem Ausgangswert – gleicher Ort, andere Form."
	box.add_child(_reroll)


func _build_variant_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	_anchor_bottom_center(bar, 20.0)
	root.add_child(bar)
	var variant := _button("Variante erzeugen", func() -> void: variant_pressed.emit())
	variant.icon = _icon("dice")
	variant.custom_minimum_size.y = 38
	variant.tooltip_text = "Neue Grundform aus neuem Ausgangswert – Bearbeitungen und geschützte Flächen bleiben erhalten."
	bar.add_child(variant)
	_variant_bar = bar


func _build_hint(root: Control) -> void:
	_hint_style = _box(Color(0.03, 0.025, 0.02, 0.62), 0, 14)
	_hint_style.content_margin_left = 16
	_hint_style.content_margin_right = 16
	_hint_style.content_margin_top = 6
	_hint_style.content_margin_bottom = 6
	_notice_style = _hint_style.duplicate() as StyleBoxFlat
	_notice_style.bg_color = Color(0.06, 0.045, 0.03, 0.88)
	_notice_style.border_color = BRASS
	_notice_style.set_border_width_all(1)
	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom_center(_hint_panel, 24.0)
	_hint_panel.add_theme_stylebox_override("panel", _hint_style)
	_hint_panel.visible = false
	root.add_child(_hint_panel)
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_panel.add_child(_hint_label)


func _build_scale_bar(root: Control) -> void:
	_scale_bar = ScaleBar.new()
	_scale_bar.anchor_top = 1.0
	_scale_bar.anchor_bottom = 1.0
	_scale_bar.offset_left = RAIL_WIDTH + 18.0
	_scale_bar.offset_right = RAIL_WIDTH + 18.0 + 220.0
	_scale_bar.offset_top = -46
	_scale_bar.offset_bottom = -14
	_scale_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_scale_bar)


func _build_minimap(root: Control) -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap_panel.offset_left = -16
	_minimap_panel.offset_right = -16
	_minimap_panel.offset_top = -16
	_minimap_panel.offset_bottom = -16
	var style := _box(WOOD, 1, 6)
	style.set_content_margin_all(5)
	_minimap_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_minimap_panel)
	_minimap = TextureRect.new()
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
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
	var north := _icon_rect("north", 20)
	north.position = Vector2(MINIMAP_SIZE - 26.0, 6.0)
	north.tooltip_text = "Norden"
	north.mouse_filter = Control.MOUSE_FILTER_IGNORE
	north.modulate = Color(1, 1, 1, 0.9)
	_minimap.add_child(north)
	_marks = Button.new()
	_marks.icon = _icon("marks")
	_marks.toggle_mode = true
	_marks.button_pressed = true
	_marks.focus_mode = Control.FOCUS_NONE
	_marks.theme_type_variation = "MapButton"
	_marks.tooltip_text = "Bearbeitungen zeigen – zu kleine Änderungen werden in groben Ansichten messingfarben markiert"
	_marks.position = Vector2(4, 4)
	_marks.toggled.connect(func(on: bool) -> void: marks_toggled.emit(on))
	_minimap.add_child(_marks)


func _build_globe_panel(root: Control) -> void:
	_globe_panel = PanelContainer.new()
	_globe_panel.anchor_left = 1.0
	_globe_panel.anchor_right = 1.0
	_globe_panel.offset_left = -352
	_globe_panel.offset_right = -16
	_globe_panel.offset_top = TOP_HEIGHT + 16.0
	var style := _box(WOOD, 1, 8)
	style.border_color = BRASS_LINE
	style.set_content_margin_all(16)
	_globe_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_globe_panel)
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 10)
	_globe_panel.add_child(g)
	_globe_title = _heading("Kontinent platzieren")
	_globe_title.add_theme_font_size_override("font_size", 18)
	g.add_child(_globe_title)
	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	g.add_child(new_row)
	var draw := _button("Neu zeichnen", func() -> void: new_continent_pressed.emit(true))
	draw.icon = _icon("pencil")
	draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw.tooltip_text = "Neuer Kontinent: leere Meeresfläche – den Umriss selbst zeichnen."
	new_row.add_child(draw)
	var gen := _button("Neu erzeugen", func() -> void: new_continent_pressed.emit(false))
	gen.icon = _icon("dice")
	gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen.tooltip_text = "Neuer Kontinent mit erzeugter Grundform als Ausgangspunkt – danach frei bearbeiten."
	new_row.add_child(gen)
	_count_label = _dim_label("")
	g.add_child(_count_label)

	_selected_box = VBoxContainer.new()
	_selected_box.add_theme_constant_override("separation", 9)
	g.add_child(_selected_box)
	_selected_box.add_child(HSeparator.new())
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name (frei lassen oder selbst vergeben)"
	_name_edit.text_submitted.connect(func(text: String) -> void:
		name_changed.emit(text)
		_name_edit.release_focus())
	_name_edit.focus_exited.connect(func() -> void: name_changed.emit(_name_edit.text))
	_selected_box.add_child(_name_edit)
	_facts_label = _dim_label("")
	_selected_box.add_child(_facts_label)
	_warning_label = _dim_label("")
	_warning_label.add_theme_color_override("font_color", BRASS_BRIGHT)
	_selected_box.add_child(_warning_label)
	_add_placement(_selected_box, "size_km", "Größe", 200.0, 6000.0, 10.0, true)
	_add_placement(_selected_box, "latitude", "Breitengrad", -80.0, 80.0, 0.5, true)
	_add_placement(_selected_box, "longitude", "Längengrad", -180.0, 180.0, 0.5, true)
	_add_placement(_selected_box, "heading", "Ausrichtung", 0.0, 359.0, 1.0)

	_selected_box.add_child(HSeparator.new())
	_climate_toggle = Button.new()
	_climate_toggle.text = "Klima aus Lage"
	_climate_toggle.icon = _icon("chevron_down")
	_climate_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_climate_toggle.toggle_mode = true
	_climate_toggle.flat = true
	_climate_toggle.focus_mode = Control.FOCUS_NONE
	_climate_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_climate_toggle.theme_type_variation = "FoldButton"
	_climate_toggle.tooltip_text = "Abgeleitetes Klima zeigen und von Hand anpassen"
	_selected_box.add_child(_climate_toggle)
	_climate_box = VBoxContainer.new()
	_climate_box.add_theme_constant_override("separation", 10)
	_climate_box.visible = false
	_selected_box.add_child(_climate_box)
	_climate_toggle.toggled.connect(func(on: bool) -> void:
		_climate_box.visible = on
		_climate_toggle.icon = _icon("chevron_up" if on else "chevron_down"))
	_climate_label = _dim_label("")
	_climate_box.add_child(_climate_label)
	_add_placement(_climate_box, "climate_override.snowline_offset", "Schneegrenze", -2000.0, 2000.0, 50.0, true)
	_add_placement(_climate_box, "climate_override.humidity_offset", "Feuchter", -0.5, 0.5, 0.05, true)

	_selected_box.add_child(HSeparator.new())
	var open := _button("Kontinent bearbeiten", func() -> void: edit_continent_pressed.emit())
	open.theme_type_variation = "PrimaryButton"
	open.custom_minimum_size.y = 40
	open.tooltip_text = "Den Kontinent öffnen und gestalten (auch per Doppelklick auf dem Globus)."
	_selected_box.add_child(open)
	var delete := _button("Löschen", func() -> void: delete_continent_pressed.emit())
	delete.theme_type_variation = "DangerButton"
	delete.tooltip_text = "Kontinent entfernen (Rückgängig mit Strg/⌘ + Z)."
	_selected_box.add_child(delete)


func _build_planet(root: Control) -> void:
	_planet_toggle = Button.new()
	_planet_toggle.text = "Planet einstellen"
	_planet_toggle.icon = _icon("settings")
	_planet_toggle.toggle_mode = true
	_planet_toggle.focus_mode = Control.FOCUS_NONE
	_planet_toggle.anchor_top = 1.0
	_planet_toggle.anchor_bottom = 1.0
	_planet_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_planet_toggle.offset_left = 16
	_planet_toggle.offset_right = 16
	_planet_toggle.offset_top = -16
	_planet_toggle.offset_bottom = -16
	_planet_toggle.custom_minimum_size.y = 38
	root.add_child(_planet_toggle)
	_planet_box = PanelContainer.new()
	_planet_box.anchor_top = 1.0
	_planet_box.anchor_bottom = 1.0
	_planet_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_planet_box.offset_left = 16
	_planet_box.offset_right = 16
	_planet_box.offset_top = -66
	_planet_box.offset_bottom = -66
	_planet_box.custom_minimum_size.x = 320
	_planet_box.visible = false
	root.add_child(_planet_box)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_planet_box.add_child(box)
	box.add_child(_heading("Planet"))
	_add_placement(box, "planet.radius_km", "Größe", WorldDocument.MIN_RADIUS_KM, WorldDocument.MAX_RADIUS_KM, 10.0)
	_planet_toggle.toggled.connect(func(on: bool) -> void: _planet_box.visible = on and _globe)


# --- Von außen gesetzt ---------------------------------------------------------------------

func set_mode(globe: bool, continent_level: bool, has_selection: bool = true) -> void:
	_globe = globe
	_continent_level = continent_level
	_has_selection = has_selection
	if not globe and not _shown_navigation_hint and _tool == "navigate":
		_shown_navigation_hint = true
		_flash(HINTS["navigate"], HINT_SECONDS, false)
	_refresh()


## Pfad oben: names = ["Welt", Kontinent, ("Region")], current = aktuelle Stufe.
func set_levels(names: Array, current: int) -> void:
	for child in _breadcrumb.get_children():
		child.queue_free()
	_crumbs.clear()
	for i in names.size():
		if i > 0:
			var slash := _label("/")
			slash.add_theme_color_override("font_color", Color(PARCHMENT_DIM, 0.6))
			_breadcrumb.add_child(slash)
		var b := _button(names[i], func() -> void: level_pressed.emit(i))
		b.flat = true
		b.theme_type_variation = "CrumbButton"
		if i == current:
			b.add_theme_color_override("font_color", BRASS_BRIGHT)
			b.add_theme_color_override("font_hover_color", BRASS_BRIGHT)
		match i:
			0: b.tooltip_text = "Zum Globus"
			1: b.tooltip_text = _facts if _facts != "" else "Ganzer Kontinent"
			_: b.tooltip_text = "Feinere Region des Kontinents\n" + _facts
		_breadcrumb.add_child(b)
		_crumbs.append(b)
	_crumb_current = current
	_crumb_count = names.size()
	_back_pill.visible = not _globe and current >= 2 and names.size() > 2


func set_history(can_undo: bool, can_redo: bool) -> void:
	_undo.disabled = not can_undo
	_redo.disabled = not can_redo


func set_saved(saved: bool) -> void:
	_saved.text = "Gespeichert" if saved else "Wird gespeichert …"
	_saved.add_theme_color_override("font_color", PARCHMENT_DIM if saved else BRASS)
	_saved_icon.visible = saved


## Früher die Statuszeile; heute nur noch die Kennzahlen (siehe set_facts).
func set_status(text: String) -> void:
	set_facts(text)


## Kennzahlen des Kontinents und der Ansicht (Fläche, Ausdehnung, Lage, Klima …): im Globusfeld
## sichtbar, sonst als Tooltip am Maßstab und am Kontinentnamen im Pfad.
func set_facts(text: String) -> void:
	_facts = text
	_facts_label.text = text
	_facts_label.visible = text != ""
	_scale_bar.tooltip_text = text
	if _crumbs.size() > 1:
		_crumbs[1].tooltip_text = text


## Kurze Meldung des Editors (z. B. „Kein See angelegt …“) – erscheint dezent und verblasst.
func show_notice(text: String) -> void:
	if text.strip_edges() == "":
		return
	_flash(text.strip_edges(), NOTICE_SECONDS, true)


## Dauerhafte Warnung (z. B. Überschneidung): im Globusfeld sichtbar, als Meldung nur beim Auftreten.
func set_warning(text: String) -> void:
	_warning_label.text = text
	_warning_label.visible = text != ""
	if text != _warning and text != "":
		show_notice(text)
	_warning = text


## Maßstab unten links: Meter je Bildpunkt in der Bildmitte.
func set_scale_bar(meters_per_pixel: float) -> void:
	_scale_bar.set_meters_per_pixel(meters_per_pixel)


## „Variante erzeugen“ gibt es nur für eine erzeugte Grundform.
func set_variant_available(on: bool) -> void:
	_variant_available = on
	_refresh()


func set_window_size(meters: float) -> void:
	_window_size = meters
	_emit_brush()


## Werkzeug von außen wählen (z. B. „Land zeichnen“ nach „Neu zeichnen“). Meldet nichts.
func select_tool(tool: String) -> void:
	var group := _group_of(tool)
	if group != _group:
		_group = group
		(_group_buttons[group] as Button).button_pressed = true
	_set_tool(tool, false)
	if tool != "navigate":
		_flash(HINTS.get(tool, ""), HINT_SECONDS, false)
	elif not _hint_is_notice:
		_fade_hint()
	_refresh()


## Pinselregler setzen (Größe als Anteil des Ausschnitts, Stärke 0–1).
func set_brush(fraction: float, strength: float) -> void:
	_size_slider.set_value_no_signal(clampf(log(fraction / _size_base()) / log(40.0), 0.0, 1.0))
	_strength_slider.set_value_no_signal(strength)
	_emit_brush()


## Offene Eingabe im Namensfeld übernehmen (vor jedem Wechsel des Kontinents aufrufen,
## damit der Name beim richtigen Kontinent landet).
func commit_name() -> void:
	if _name_edit.has_focus():
		name_changed.emit(_name_edit.text)
		_name_edit.release_focus()


func set_reroll_available(on: bool) -> void:
	_reroll.disabled = not on


func set_continent_count(count: int) -> void:
	if count > 0:
		_count_label.text = "%d Kontinent%s · Klick wählt, Ziehen verschiebt, Doppelklick öffnet" % [count, "" if count == 1 else "e"]
	else:
		_count_label.text = "Noch kein Kontinent – zeichnen oder erzeugen."


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

func _on_group_button(id: String) -> void:
	# Die gewählte Gruppe noch einmal anklicken: zurück zum Ansehen.
	if id == _group and id != "view":
		(_group_buttons["view"] as Button).button_pressed = true
		id = "view"
	_select_group(id, true)


func _select_group(id: String, emit: bool) -> void:
	_group = id
	(_group_buttons[id] as Button).button_pressed = true
	# Eine Gruppe öffnen wählt noch kein Werkzeug: erst die Wahl unten verändert die Karte.
	_set_tool("navigate", emit and _tool != "navigate")
	if id != "view":
		_flash("Werkzeug unten wählen.", 3.0, false)
	else:
		_fade_hint()
	_refresh()


func _on_tool_button(tool: String) -> void:
	# Das gewählte Werkzeug noch einmal anklicken: nur noch ansehen (Gruppe bleibt offen).
	if tool == _tool:
		_set_tool("navigate", true)
		_fade_hint()
	else:
		_set_tool(tool, true)
		_flash(HINTS.get(tool, ""), HINT_SECONDS, false)
	_refresh()


func _set_tool(tool: String, emit: bool) -> void:
	# Jedes Werkzeug behält seine eigene Größe und Stärke (ein Fluss ist schmaler als ein Wald).
	if _tool != tool:
		_tool_brush[_tool] = Vector2(_size_slider.value, _strength_slider.value)
		var saved: Vector2 = _tool_brush.get(tool, Vector2(DEFAULT_SIZE.get(tool, _size_slider.value), _strength_slider.value))
		_size_slider.set_value_no_signal(saved.x)
		_strength_slider.set_value_no_signal(saved.y)
	_tool = tool
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).set_pressed_no_signal(t == tool)
	if _tool_buttons.has(tool):
		_card_icon.texture = _icon(tool)
		_card_title.text = (_tool_buttons[tool] as Button).text
	_size_row.visible = tool not in NO_SETTINGS
	((_size_row.get_child(0) as Control).get_child(0) as Label).text = "Breite" if tool == "river" else "Größe"
	_strength_row.visible = tool not in NO_STRENGTH
	_reroll.visible = tool in REROLL_TOOLS
	if emit:
		tool_selected.emit(tool)
	_emit_brush()


func _group_of(tool: String) -> String:
	for entry in GROUPS:
		for t in entry[3]:
			if t[0] == tool:
				return entry[0]
	return "view"


## Sichtbarkeit aller Teile nach Maßstab, Gruppe und Werkzeug.
func _refresh() -> void:
	var land := not _globe
	_rail.visible = land
	_toolbar.visible = land and _group != "view"
	for id in _group_rows:
		(_group_rows[id] as Control).visible = id == _group
	_card.visible = land and _tool not in NO_SETTINGS
	_variant_bar.visible = land and _group == "view" and _continent_level and _variant_available
	_minimap_panel.visible = land
	_scale_bar.visible = land
	_back_pill.visible = land and _crumb_current >= 2 and _crumb_count > 2
	_globe_panel.visible = _globe
	_selected_box.visible = _has_selection
	_globe_title.text = "Kontinent platzieren" if _has_selection else "Neuer Kontinent"
	_planet_toggle.visible = _globe
	_planet_box.visible = _globe and _planet_toggle.button_pressed
	_layout_hint()


func _layout_hint() -> void:
	var bottom := 22.0
	if _toolbar.visible:
		bottom = 16.0 + _toolbar.get_combined_minimum_size().y + 10.0
	elif _variant_bar.visible:
		bottom = 20.0 + _variant_bar.get_combined_minimum_size().y + 10.0
	_hint_panel.offset_top = -bottom
	_hint_panel.offset_bottom = -bottom
	_hint_panel.offset_left = 0.0
	_hint_panel.offset_right = 0.0


## Hinweiszeile zeigen und nach `seconds` verblassen lassen.
func _flash(text: String, seconds: float, notice: bool) -> void:
	if _hint_tween:
		_hint_tween.kill()
	if text == "":
		_hint_panel.visible = false
		return
	_hint_label.text = text
	# Lange Hinweise umbrechen statt über den Bildrand hinauszulaufen.
	var font := _hint_label.get_theme_font("font")
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > 720.0
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide else TextServer.AUTOWRAP_OFF
	_hint_label.custom_minimum_size.x = 720.0 if wide else 0.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", PARCHMENT if notice else PARCHMENT_DIM)
	_hint_panel.add_theme_stylebox_override("panel", _notice_style if notice else _hint_style)
	_hint_is_notice = notice
	_hint_panel.modulate.a = 1.0
	_hint_panel.visible = true
	_layout_hint()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.8)
	_hint_tween.tween_callback(func() -> void: _hint_panel.visible = false)


func _fade_hint() -> void:
	if not _hint_panel.visible:
		return
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.4)
	_hint_tween.tween_callback(func() -> void: _hint_panel.visible = false)


## Nach dem ersten Strich auf der Karte verblasst der Werkzeughinweis (Meldungen bleiben).
func _input(event: InputEvent) -> void:
	if not visible or not _hint_panel.visible or _globe or _tool == "navigate":
		return
	if event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not _hint_is_notice and get_viewport().gui_get_hovered_control() == null:
			_fade_hint()


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		minimap_clicked.emit((event as InputEventMouseButton).position / _minimap.size)
		_minimap.accept_event()


func _emit_brush() -> void:
	var fraction := size_fraction()
	# Beim Fluss zählt die ganze Breite (der Pinsel ist die halbe).
	_size_label.text = meters(fraction * _window_size * (2.0 if _tool == "river" else 1.0))
	_strength_label.text = "%d %%" % int(round(_strength_slider.value * 100.0))
	brush_changed.emit(fraction, _strength_slider.value)


## Pinselgröße als Anteil des Ausschnitts (0,5 % bis 20 %, logarithmisch; Flüsse feiner:
## halbe Breite 0,06 % bis 2,4 %, damit sie auf der Kontinentkarte schmal bleiben können).
func size_fraction() -> float:
	return _size_base() * pow(40.0, _size_slider.value)


func _size_base() -> float:
	return 0.0006 if _tool == "river" else 0.005


func _set_slider(key: String, value: float) -> void:
	if _dragging.get(key, false) or not _placement.has(key):
		return
	var control: Variant = _placement[key][0]
	control.set_value_no_signal(value)
	_update_placement_label(key, control.value)


## Ein Regler mit Titel und Wertfeld (Ausrichtung als Drehscheibe).
func _add_placement(parent: Control, key: String, title: String, low: float, high: float, step: float, row := false) -> void:
	var value := _value_label()
	var control: Variant
	if key == "heading":
		var dial := Dial.new()
		dial.custom_minimum_size = Vector2(64, 64)
		control = dial
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var t := _label(title)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(t)
		line.add_child(dial)
		var holder := CenterContainer.new()
		holder.add_child(_value_box(value))
		line.add_child(holder)
		parent.add_child(line)
	else:
		var slider := _slider(low, high, low, step)
		control = slider
		parent.add_child(_setting_row(title, slider, value) if row else _setting_block(title, slider, value))
	_placement[key] = [control, value]
	control.drag_started.connect(func() -> void: _dragging[key] = true)
	control.drag_ended.connect(func(_changed: bool) -> void:
		_dragging[key] = false
		placement_changed.emit(key, control.value, true))
	control.value_changed.connect(func(v: float) -> void:
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


# --- Bausteine -----------------------------------------------------------------------------

func _icon(name: String) -> Texture2D:
	if not _icons.has(name):
		var path := ICON_DIR + name + ".svg"
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]


func _icon_rect(name: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _icon(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _icon_button(name: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = _icon(name)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(36, 34)
	b.pressed.connect(action)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _dim_label(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	l.add_theme_color_override("font_color", PARCHMENT_DIM)
	l.add_theme_font_size_override("font_size", 13)
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", BRASS_BRIGHT)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _value_label() -> Label:
	var l := _label("")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 14)
	return l


func _value_box(label: Label) -> PanelContainer:
	var box := PanelContainer.new()
	var style := _box(Color(0.04, 0.032, 0.027, 0.9), 1, 4)
	style.border_color = BRASS_LINE
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size.x = 92
	box.add_child(label)
	return box


## Kompakt in einer Zeile: Titel, Regler, Wert.
func _setting_row(title: String, slider: HSlider, value: Label) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var t := _label(title)
	t.custom_minimum_size.x = 98
	line.add_child(t)
	slider.custom_minimum_size.x = 90
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(slider)
	line.add_child(_value_box(value))
	return line


## Titel links, Wert rechts, darunter der Regler über die ganze Breite.
func _setting_block(title: String, slider: HSlider, value: Label) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	var t := _label(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(_value_box(value))
	block.add_child(row)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(slider)
	return block


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
	s.custom_minimum_size = Vector2(200, 22)
	s.focus_mode = Control.FOCUS_NONE
	return s


## Mittig am unteren Rand verankern; wächst nach oben und zu beiden Seiten.
static func _anchor_bottom_center(c: Control, margin: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_top = -margin
	c.offset_bottom = -margin


func _box(color: Color, border: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = BRASS
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	return s


func _theme() -> Theme:
	var t := Theme.new()
	var panel := _box(WOOD, 1, 8)
	panel.border_color = BRASS_LINE
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_font_size("font_size", "Label", 14)

	var normal := _box(WOOD_LIGHT, 1, 5)
	normal.border_color = BRASS_LINE
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = WOOD_LIGHT.lightened(0.1)
	hover.border_color = BRASS
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = LEATHER
	pressed.border_color = BRASS_BRIGHT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.085, 0.07)
	disabled.border_color = Color(BRASS_LINE, 0.15)
	_button_styles(t, "Button", normal, hover, pressed, disabled)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.97, 0.9))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.86, 0.55))
	t.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.86, 0.55))
	t.set_color("font_focus_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.42, 0.38))
	t.set_color("icon_normal_color", "Button", PARCHMENT)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", Color(1.0, 0.8, 0.48))
	t.set_color("icon_hover_pressed_color", "Button", Color(1.0, 0.84, 0.55))
	t.set_color("icon_focus_color", "Button", PARCHMENT)
	t.set_color("icon_disabled_color", "Button", Color(0.5, 0.47, 0.42, 0.45))
	t.set_font_size("font_size", "Button", 14)
	t.set_constant("icon_max_width", "Button", 18)
	t.set_constant("h_separation", "Button", 8)

	# Werkzeuggruppen links: quadratisch, ohne Rahmen; gewählt mit Messingrahmen.
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	clear.set_corner_radius_all(6)
	clear.set_content_margin_all(6)
	var clear_hover := clear.duplicate() as StyleBoxFlat
	clear_hover.bg_color = Color(1, 0.9, 0.7, 0.07)
	var chosen := clear.duplicate() as StyleBoxFlat
	chosen.bg_color = Color(0.40, 0.29, 0.13, 0.55)
	chosen.border_color = BRASS_BRIGHT
	chosen.set_border_width_all(1)
	t.set_type_variation("RailButton", "Button")
	_button_styles(t, "RailButton", clear, clear_hover, chosen, clear)
	t.set_constant("icon_max_width", "RailButton", 26)

	t.set_type_variation("ToolButton", "Button")
	var tool_normal := clear.duplicate() as StyleBoxFlat
	tool_normal.content_margin_top = 6
	tool_normal.content_margin_bottom = 4
	tool_normal.content_margin_left = 8
	tool_normal.content_margin_right = 8
	var tool_hover := tool_normal.duplicate() as StyleBoxFlat
	tool_hover.bg_color = Color(1, 0.9, 0.7, 0.07)
	var tool_chosen := tool_normal.duplicate() as StyleBoxFlat
	tool_chosen.bg_color = Color(0.40, 0.29, 0.13, 0.5)
	tool_chosen.border_color = BRASS_BRIGHT
	tool_chosen.set_border_width_all(1)
	_button_styles(t, "ToolButton", tool_normal, tool_hover, tool_chosen, tool_normal)
	t.set_constant("icon_max_width", "ToolButton", 24)
	t.set_constant("h_separation", "ToolButton", 2)
	t.set_font_size("font_size", "ToolButton", 13)

	t.set_type_variation("IconButton", "Button")
	var icon_clear := clear.duplicate() as StyleBoxFlat
	icon_clear.set_content_margin_all(6)
	var icon_hover := icon_clear.duplicate() as StyleBoxFlat
	icon_hover.bg_color = Color(1, 0.9, 0.7, 0.08)
	_button_styles(t, "IconButton", icon_clear, icon_hover, icon_hover, icon_clear)
	t.set_constant("icon_max_width", "IconButton", 20)

	t.set_type_variation("MapButton", "Button")
	var map_normal := clear.duplicate() as StyleBoxFlat
	map_normal.bg_color = Color(0.04, 0.03, 0.025, 0.7)
	map_normal.set_content_margin_all(4)
	var map_on := map_normal.duplicate() as StyleBoxFlat
	map_on.border_color = BRASS_BRIGHT
	map_on.set_border_width_all(1)
	_button_styles(t, "MapButton", map_normal, map_normal, map_on, map_normal)
	t.set_constant("icon_max_width", "MapButton", 18)

	t.set_type_variation("CrumbButton", "Button")
	var crumb := clear.duplicate() as StyleBoxFlat
	crumb.content_margin_left = 8
	crumb.content_margin_right = 8
	crumb.content_margin_top = 4
	crumb.content_margin_bottom = 4
	var crumb_hover := crumb.duplicate() as StyleBoxFlat
	crumb_hover.bg_color = Color(1, 0.9, 0.7, 0.07)
	_button_styles(t, "CrumbButton", crumb, crumb_hover, crumb_hover, crumb)
	t.set_font_size("font_size", "CrumbButton", 15)
	t.set_color("font_color", "CrumbButton", PARCHMENT_DIM)

	t.set_type_variation("PillButton", "Button")
	var pill := _box(Color(0.06, 0.048, 0.04, 0.88), 1, 15)
	pill.border_color = BRASS_LINE
	pill.content_margin_left = 10
	pill.content_margin_right = 14
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	var pill_hover := pill.duplicate() as StyleBoxFlat
	pill_hover.border_color = BRASS
	_button_styles(t, "PillButton", pill, pill_hover, pill_hover, pill)
	t.set_constant("icon_max_width", "PillButton", 16)

	t.set_type_variation("FoldButton", "Button")
	var fold := clear.duplicate() as StyleBoxFlat
	fold.content_margin_left = 0
	_button_styles(t, "FoldButton", fold, fold, fold, fold)
	t.set_color("font_color", "FoldButton", PARCHMENT)
	t.set_color("font_pressed_color", "FoldButton", BRASS_BRIGHT)
	t.set_color("font_hover_pressed_color", "FoldButton", BRASS_BRIGHT)

	t.set_type_variation("PrimaryButton", "Button")
	var primary := _box(Color(0.80, 0.61, 0.30), 1, 5)
	primary.border_color = Color(0.95, 0.78, 0.45)
	primary.set_content_margin_all(8)
	var primary_hover := primary.duplicate() as StyleBoxFlat
	primary_hover.bg_color = Color(0.88, 0.69, 0.36)
	_button_styles(t, "PrimaryButton", primary, primary_hover, primary_hover, primary)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "PrimaryButton", Color(0.12, 0.085, 0.05))
	t.set_font_size("font_size", "PrimaryButton", 15)

	t.set_type_variation("DangerButton", "Button")
	var danger := normal.duplicate() as StyleBoxFlat
	danger.bg_color = Color(0.09, 0.05, 0.045, 0.9)
	danger.border_color = Color(BLOOD, 0.8)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = Color(BLOOD, 0.35)
	_button_styles(t, "DangerButton", danger, danger_hover, danger_hover, danger)
	t.set_color("font_color", "DangerButton", BLOOD_TEXT)
	t.set_color("font_hover_color", "DangerButton", Color(1.0, 0.75, 0.7))

	var edit := _box(Color(0.04, 0.032, 0.027, 1.0), 1, 4)
	edit.border_color = BRASS_LINE
	edit.set_content_margin_all(7)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = BRASS
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", PARCHMENT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.46, 0.4))
	t.set_font_size("font_size", "LineEdit", 14)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.26, 0.21, 0.16)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = BRASS
	var filled_hover := track.duplicate() as StyleBoxFlat
	filled_hover.bg_color = BRASS_BRIGHT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled_hover)
	if _icon("knob"):
		t.set_icon("grabber", "HSlider", _icon("knob"))
		t.set_icon("grabber_highlight", "HSlider", _icon("knob_hover"))

	var line := StyleBoxLine.new()
	line.color = BRASS_LINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = BRASS_LINE
	vline.thickness = 1
	vline.vertical = true
	vline.grow_begin = -8
	vline.grow_end = -8
	t.set_stylebox("separator", "VSeparator", vline)

	var tip := _box(Color(0.06, 0.048, 0.04, 0.97), 1, 5)
	tip.border_color = BRASS_LINE
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", PARCHMENT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	return t


static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	var none := StyleBoxEmpty.new()
	t.set_stylebox("focus", type, none)


# --- Eigene Bedienelemente -----------------------------------------------------------------

## Maßstab: Balken mit runder Entfernung („100 km“, „5 km“, „500 m“) für die Bildmitte.
class ScaleBar extends Control:
	const TARGET_PX := 150.0
	var _meters_per_pixel := 0.0
	var _length_px := 0.0
	var _text := ""

	func set_meters_per_pixel(mpp: float) -> void:
		if mpp <= 0.0 or not is_finite(mpp):
			return
		if absf(mpp - _meters_per_pixel) <= _meters_per_pixel * 0.002:
			return
		_meters_per_pixel = mpp
		var raw := mpp * TARGET_PX
		var step := pow(10.0, floor(log(raw) / log(10.0)))
		var nice := step
		if raw / step >= 5.0:
			nice = step * 5.0
		elif raw / step >= 2.0:
			nice = step * 2.0
		_length_px = nice / mpp
		_text = ("%s km" % EditorUI._number(nice / 1000.0, 0)) if nice >= 1000.0 else ("%s m" % EditorUI._number(nice, 0))
		queue_redraw()

	func _draw() -> void:
		if _length_px <= 0.0:
			return
		var font := get_theme_default_font()
		var y := size.y - 6.0
		var x0 := 2.0
		var x1 := x0 + _length_px
		var shade := Color(0, 0, 0, 0.55)
		draw_line(Vector2(x0, y + 1), Vector2(x1, y + 1), shade, 4.0)
		draw_line(Vector2(x0, y), Vector2(x1, y), EditorUI.PARCHMENT, 2.0)
		draw_line(Vector2(x0, y - 6), Vector2(x0, y + 2), EditorUI.PARCHMENT, 2.0)
		draw_line(Vector2(x1, y - 6), Vector2(x1, y + 2), EditorUI.PARCHMENT, 2.0)
		draw_line(Vector2((x0 + x1) * 0.5, y - 3), Vector2((x0 + x1) * 0.5, y + 1), EditorUI.PARCHMENT_DIM, 1.5)
		var pos := Vector2(x0, y - 10.0)
		draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, shade)
		draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, EditorUI.PARCHMENT)


## Drehscheibe für die Ausrichtung (0° = Norden, im Uhrzeigersinn). Gleiche Signale wie ein Regler.
class Dial extends Control:
	signal value_changed(v: float)
	signal drag_started
	signal drag_ended(changed: bool)
	var value := 0.0
	var _dragging := false
	var _changed := false

	func set_value_no_signal(v: float) -> void:
		value = fposmod(roundf(v), 360.0)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 7.0
		draw_circle(c, r, Color(0.04, 0.032, 0.027, 0.9))
		draw_arc(c, r, 0.0, TAU, 64, EditorUI.BRASS_LINE, 1.5, true)
		for k in 4:
			var a := k * PI * 0.5
			var d := Vector2(sin(a), -cos(a))
			draw_line(c + d * (r - 6.0), c + d * r, EditorUI.PARCHMENT_DIM, 1.5, true)
		var font := get_theme_default_font()
		draw_string(font, c + Vector2(-3.5, -r - 2.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, EditorUI.PARCHMENT_DIM)
		var a := deg_to_rad(value)
		var tip := c + Vector2(sin(a), -cos(a)) * (r - 9.0)
		draw_line(c, tip, EditorUI.BRASS_BRIGHT, 2.5, true)
		draw_circle(tip, 4.0, EditorUI.BRASS_BRIGHT)
		draw_circle(c, 3.0, EditorUI.BRASS)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_changed = false
				drag_started.emit()
				_set_from((event as InputEventMouseButton).position)
			elif _dragging:
				_dragging = false
				drag_ended.emit(_changed)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from((event as InputEventMouseMotion).position)
			accept_event()

	func _set_from(p: Vector2) -> void:
		var d := p - size * 0.5
		if d.length() < 3.0:
			return
		var a := fposmod(roundf(rad_to_deg(atan2(d.x, -d.y))), 360.0)
		if a >= 359.5:
			a = 0.0
		if a != value:
			value = a
			_changed = true
			queue_redraw()
			value_changed.emit(a)
