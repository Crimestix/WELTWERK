class_name TargetMaterials
extends RefCounted
## Gemeinsame Bestände und Materialien im Stil des Zielbilds (Zielszene und Editor).

const PH := "res://assets/external/polyhaven/textures/"
const T := "res://assets/target/"
const LEAF_SHADER := preload("res://src/style_test/leaf_cards.gdshader")
const ROCK_SHADER := preload("res://src/target/rock_granite.gdshader")
const GRASS_SHADER := preload("res://src/target/grass_cards.gdshader")

const TREES := {
	"oak": ["oak_1", "oak_2", "oak_3"],
	"beech": ["beech_1", "beech_2"],
	"young": ["young_1", "young_2"],
	"far": ["far_1", "far_2", "far_3"],
}
const ROCKS := ["granite_hf", "granite_hf_2"]
const BUSHES := ["bush_1", "bush_2", "bush_3"]

static var _cache := {}


static func texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func polyhaven(id: String, map: String) -> Texture2D:
	return texture(PH + "%s/%s_%s.jpg" % [id, id, map])


static func material_for(surface_name: String, bush: bool) -> Material:
	if surface_name.begins_with("LeafCards"):
		var leaf := ShaderMaterial.new()
		leaf.shader = LEAF_SHADER
		var atlas := texture(T + ("shrub_leaf_atlas.png" if bush else "leaf_atlas_sunlit.png"))
		leaf.set_shader_parameter("leaf_atlas", atlas if atlas else load("res://assets/style_c/leaf_atlas.png"))
		leaf.set_shader_parameter("tint", Vector3(1.12, 1.16, 0.95) if not bush else Vector3(1.05, 1.15, 0.8))
		leaf.set_shader_parameter("backlight", 0.75)
		return leaf
	if surface_name.begins_with("Bark"):
		var bark := StandardMaterial3D.new()
		bark.albedo_texture = polyhaven("bark_brown_02", "diffuse")
		bark.normal_enabled = true
		bark.normal_texture = polyhaven("bark_brown_02", "nor_gl")
		bark.albedo_color = Color(1.25, 1.18, 1.08)
		bark.roughness = 0.9
		return bark
	var rock := ShaderMaterial.new()
	rock.shader = ROCK_SHADER
	var granite := texture(T + "granite_lichen_texture.png")
	rock.set_shader_parameter("granite", granite if granite else polyhaven("rock_boulder_dry", "diffuse"))
	rock.set_shader_parameter("rock_normal", polyhaven("rock_boulder_dry", "nor_gl"))
	return rock


## Netz eines Modells mit Materialien im Zielstil (einmal je Datei; Higgsfield-Modelle behalten ihre).
static func mesh(path: String, bush: bool = false) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var result: Mesh = mi.mesh.duplicate()
	if not path.contains("_hf"):
		for s in result.get_surface_count():
			var original := result.surface_get_material(s)
			result.surface_set_material(s, material_for(original.resource_name if original else "", bush))
	root.free()
	_cache[path] = result
	return result


static func tree_mesh(file: String) -> Mesh:
	return mesh(T + "trees/" + file + ".glb")


static func rock_mesh(file: String) -> Mesh:
	return mesh(T + "rocks/" + file + ".glb")


static func bush_mesh(file: String) -> Mesh:
	return mesh(T + "bushes/" + file + ".glb", true)


## Grasbüschel: drei gekreuzte Karten, Farbe vom Boden (meadow.gdshaderinc).
static func tuft_mesh(width: float, height: float, atlas: Texture2D, flowers: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0.0, sin(a)) * width * 0.5
		var corners := [-d, d, d + Vector3(0.0, height, 0.0), -d + Vector3(0.0, height, 0.0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	var result := st.commit()
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("atlas", atlas)
	if flowers:
		material.set_shader_parameter("saturation", 1.1)
		material.set_shader_parameter("from_ground", false)
		material.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
	result.surface_set_material(0, material)
	return result
