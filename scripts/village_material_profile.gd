extends RefCounted
class_name VillageMaterialProfile

const NORMAL_MAPS: Dictionary = {
	"M_wood_05": "res://assets/fantastic_village/material_maps/T_wood_05_N.png",
	"M_wall_02": "res://assets/fantastic_village/material_maps/T_wall_02_N.png",
	"M_rooftiles_01": "res://assets/fantastic_village/material_maps/T_rooftiles_01_N.png",
	# The source MI_stonebrick_02 explicitly references stonebrick_01_N.
	"M_stonebrick_02": "res://assets/fantastic_village/material_maps/T_stonebrick_01_N.png",
	# Source MI_ENV_stone explicitly binds T_ENV_stone_N.
	"M_ENV_stone": "res://assets/fantastic_village/env/T_ENV_stone_N.png",
}
const FOLIAGE_MATERIAL: String = "M_ENV_plants_village"
const FOLIAGE_ALBEDO: String = "res://assets/fantastic_village/material_maps/T_ENV_plants_village_BC.png"
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage_masked_wind.gdshader")
const SOURCE_OPAQUE_ROUGHNESS: float = 1.0
const SOURCE_OPAQUE_METALLIC: float = 0.0
static var _material_cache: Dictionary = {}
## CLI-only visual A/B switch: the shipped default remains enabled.
static var enabled: bool = true

static func apply_to(root: Node) -> Dictionary:
	var stats := {"enabled": enabled, "surfaces": 0, "normal_bound": 0, "foliage_masked": 0, "unmatched": 0}
	if not enabled:
		return stats
	if root == null:
		return stats
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null:
			continue
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				stats.unmatched += 1
				continue
			var material_name := source.resource_name
			if material_name.is_empty():
				material_name = source.resource_path.get_file().get_basename()
			stats.surfaces += 1
			if material_name == FOLIAGE_MATERIAL:
				var foliage: ShaderMaterial = _material_cache.get("foliage") as ShaderMaterial
				if foliage == null:
					foliage = ShaderMaterial.new()
					foliage.shader = FOLIAGE_SHADER
					foliage.set_shader_parameter("base_color_texture", load(FOLIAGE_ALBEDO))
					foliage.set_shader_parameter("alpha_clip", 0.3333)
					foliage.set_shader_parameter("wind_directional_strength", 4.0)
					foliage.set_shader_parameter("wind_influence", 0.5)
					foliage.set_shader_parameter("wind_speed", 0.7)
					foliage.set_shader_parameter("wind_weight", 0.3)
					_material_cache["foliage"] = foliage
				mesh_instance.set_surface_override_material(surface, foliage)
				stats.foliage_masked += 1
				continue
			if not NORMAL_MAPS.has(material_name):
				stats.unmatched += 1
				continue
			var normal_path: String = str(NORMAL_MAPS[material_name])
			var cache_key: String = "%s|%s" % [source.resource_path, normal_path]
			var tuned: StandardMaterial3D = _material_cache.get(cache_key) as StandardMaterial3D
			if tuned == null:
				var normal_tex := load(normal_path) as Texture2D
				if normal_tex == null:
					push_warning("Material profile could not load source normal map: " + normal_path)
					continue
				if source is StandardMaterial3D:
					tuned = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					tuned = StandardMaterial3D.new()
				tuned.normal_enabled = true
				tuned.normal_texture = normal_tex
				# The source roof MI sets FlattenNormal's Flatness to -1.0,
				# extrapolating away from the flat normal; keep the relief stronger.
				if material_name == "M_rooftiles_01":
					tuned.normal_scale = 2.0
				# UE's shared opaque parent routes Custom Roughness (default 1.0)
				# and Custom Metallic (default 0.0) to the material outputs.
				tuned.roughness = SOURCE_OPAQUE_ROUGHNESS
				tuned.metallic = SOURCE_OPAQUE_METALLIC
				_material_cache[cache_key] = tuned
			mesh_instance.set_surface_override_material(surface, tuned)
			stats.normal_bound += 1
	return stats

