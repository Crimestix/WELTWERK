extends PanelContainer
## Kleine Steuerungshilfe unten links. F1 blendet sie ein und aus.
## Gestaltung vorläufig (Holz, Messing, Pergament); die Schriften kommen später.

const WOOD := Color(0.09, 0.07, 0.055, 0.88)
const BRASS := Color(0.62, 0.49, 0.27)
const PARCHMENT := Color(0.91, 0.86, 0.75)
const PARCHMENT_DIM := Color(0.75, 0.70, 0.60)

const LINES := [
	["Verschieben", "W A S D · rechte Maustaste ziehen · zwei Finger"],
	["Zoomen", "Mausrad · + und − · Finger spreizen"],
	["Schneller", "Umschalt gedrückt halten"],
	["Übersicht", "Pos1"],
	["Hilfe", "F1"],
]

var _info: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = WOOD
	style.border_color = BRASS
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var title := Label.new()
	title.text = "STEUERUNG"
	title.add_theme_color_override("font_color", BRASS)
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for entry in LINES:
		var key := Label.new()
		key.text = entry[0]
		key.add_theme_color_override("font_color", PARCHMENT)
		key.add_theme_font_size_override("font_size", 13)
		grid.add_child(key)
		var value := Label.new()
		value.text = entry[1]
		value.add_theme_color_override("font_color", PARCHMENT_DIM)
		value.add_theme_font_size_override("font_size", 13)
		grid.add_child(value)

	_info = Label.new()
	_info.add_theme_color_override("font_color", PARCHMENT_DIM)
	_info.add_theme_font_size_override("font_size", 12)
	box.add_child(_info)


## Zeigt an, woraus das Gelände erzeugt wurde – Erzeugtes bleibt erkennbar.
func show_terrain_origin(field: Heightfield) -> void:
	var s := field.size()
	_info.text = "Gelände: erzeugt aus Ausgangswert %d · %d × %d Meter" % [field.seed_value, s.x, s.y]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		visible = not visible
		get_viewport().set_input_as_handled()
