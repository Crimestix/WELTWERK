class_name Terrain
extends Node3D
## Zeigt ein Höhenfeld als Gelände mit Wasserfläche.
##
## Die Fachlogik (Erzeugung, Höhe an einem Punkt, Strahl trifft Gelände) liegt in Heightfield;
## dieser Knoten baut daraus nur Netz und Materialien. Die Kamera fragt ihn nach Höhe,
## Treffpunkt und Ausdehnung (height_at, raycast, world_rect).

signal generated(field: Heightfield)

## Beim Start selbst ein Gelände erzeugen (sonst setzt jemand anderes es über show_field).
@export var generate_on_ready: bool = true
## Ausgangswert für die Erzeugung. Gleicher Wert → gleiches Gelände.
@export var terrain_seed: int = 1
## Seitenlänge in Metern.
@export var extent: float = 400.0
## Rasterabstand in Metern. Kleiner = feiner, aber teurer.
@export var spacing: float = 1.0

const TERRAIN_SHADER := preload("res://src/world/terrain.gdshader")
const WATER_SHADER := preload("res://src/world/water.gdshader")

var field: Heightfield

var _ground: MeshInstance3D
var _water: MeshInstance3D


func _ready() -> void:
	if generate_on_ready:
		rebuild()


## Erzeugt das Gelände neu aus Ausgangswert, Größe und Raster.
func rebuild() -> void:
	show_field(Heightfield.generate(terrain_seed, extent, spacing))


## Zeigt ein fertiges Höhenfeld. Ohne Material wird das Platzhaltermaterial verwendet.
func show_field(p_field: Heightfield, ground_material: Material = null, water_size_factor: float = 6.0) -> void:
	field = p_field
	if ground_material == null:
		var material := ShaderMaterial.new()
		material.shader = TERRAIN_SHADER
		material.set_shader_parameter("sea_level", Heightfield.SEA_LEVEL)
		ground_material = material
	_build_ground(ground_material)
	_build_water(water_size_factor)
	generated.emit(field)


func set_ground_material(material: Material) -> void:
	if _ground and _ground.mesh:
		_ground.mesh.surface_set_material(0, material)


func height_at(x: float, z: float) -> float:
	return field.height_at(x, z) if field else 0.0


func raycast(from: Vector3, direction: Vector3, max_distance: float = 5000.0) -> Variant:
	return field.raycast(from, direction, max_distance) if field else null


## Ausdehnung in Weltkoordinaten (x, z).
func world_rect() -> Rect2:
	return Rect2(field.origin, field.size()) if field else Rect2()


func _build_ground(material: Material) -> void:
	var vertex_count := field.columns * field.rows
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	tangents.resize(vertex_count * 4)
	uvs.resize(vertex_count)

	var s := field.size()
	for row in field.rows:
		for column in field.columns:
			var i := row * field.columns + column
			var x := field.origin.x + column * field.spacing
			var z := field.origin.y + row * field.spacing
			var n := field.normal_at(column, row)
			vertices[i] = Vector3(x, field.heights[i], z)
			normals[i] = n
			# Tangente entlang +x (Texturen liegen in Weltrichtung x/z); w = −1 → Binormale +z.
			var t := (Vector3.RIGHT - n * n.x).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
			tangents[i * 4 + 3] = -1.0
			uvs[i] = Vector2((x - field.origin.x) / s.x, (z - field.origin.y) / s.y)

	var indices := PackedInt32Array()
	indices.resize((field.columns - 1) * (field.rows - 1) * 6)
	var k := 0
	for row in field.rows - 1:
		for column in field.columns - 1:
			var a := row * field.columns + column
			var b := a + 1
			var c := a + field.columns
			var d := c + 1
			# Im Uhrzeigersinn von oben gesehen = Vorderseite in Godot.
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)

	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		add_child(_ground)
	_ground.mesh = mesh


func _build_water(size_factor: float) -> void:
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)
	var plane := PlaneMesh.new()
	plane.size = field.size() * size_factor
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	plane.material = material
	_water.mesh = plane
	_water.position = Vector3(field.origin.x + field.size().x * 0.5, Heightfield.SEA_LEVEL, field.origin.y + field.size().y * 0.5)
