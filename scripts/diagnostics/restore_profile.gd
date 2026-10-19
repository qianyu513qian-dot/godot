extends RefCounted
class_name RestoreProfile
## Opt-in tracing for controlled Continue/load analysis. Disabled in normal runs.

const TRACE_META := "aoelite_restore_profile"
const ORIGIN_META := "aoelite_restore_profile_origin_usec"
const EVENTS_META := "aoelite_restore_profile_events"

static func enabled() -> bool:
	return Engine.has_meta(TRACE_META) and bool(Engine.get_meta(TRACE_META))

static func begin(stage: String) -> int:
	if not enabled():
		return 0
	var start_usec := Time.get_ticks_usec()
	mark(stage + ".begin")
	return start_usec

static func finish(stage: String, start_usec: int, detail: Dictionary = {}) -> void:
	if start_usec <= 0 or not enabled():
		return
	var fields := detail.duplicate(true)
	fields["duration_usec"] = Time.get_ticks_usec() - start_usec
	mark(stage + ".end", fields)

static func mark(stage: String, detail: Dictionary = {}) -> void:
	if not enabled():
		return
	var now_usec := Time.get_ticks_usec()
	var origin_usec := int(Engine.get_meta(ORIGIN_META, now_usec))
	var event := {"stage": stage, "offset_usec": now_usec - origin_usec}
	event.merge(detail, true)
	var events: Array = Engine.get_meta(EVENTS_META, [])
	events.append(event)
	Engine.set_meta(EVENTS_META, events)

static func scene_resource_snapshot(root: Node) -> Dictionary:
	if root == null:
		return {"root_missing": true}
	var started := Time.get_ticks_usec()
	var mesh_refs: Dictionary = {}
	var base_material_refs: Dictionary = {}
	var override_material_refs: Dictionary = {}
	var texture_refs: Dictionary = {}
	var mesh_instance_count := 0
	var surface_count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_instance_count += 1
		var mesh_key := str(mesh_instance.mesh.get_instance_id())
		mesh_refs[mesh_key] = int(mesh_refs.get(mesh_key, 0)) + 1
		for surface in mesh_instance.mesh.get_surface_count():
			surface_count += 1
			var base_material: Material = mesh_instance.mesh.surface_get_material(surface)
			if base_material != null:
				var base_key := str(base_material.get_instance_id())
				base_material_refs[base_key] = int(base_material_refs.get(base_key, 0)) + 1
				_collect_textures(base_material, texture_refs)
			var override_material: Material = mesh_instance.get_surface_override_material(surface)
			if override_material != null:
				var override_key := str(override_material.get_instance_id())
				override_material_refs[override_key] = int(override_material_refs.get(override_key, 0)) + 1
				_collect_textures(override_material, texture_refs)
	var mesh_distribution := _distribution(mesh_refs.values())
	var base_material_distribution := _distribution(base_material_refs.values())
	var override_material_distribution := _distribution(override_material_refs.values())
	var texture_distribution := _distribution(texture_refs.values())
	return {
		"scene_root": str(root.get_path()),
		"mesh_instances": mesh_instance_count,
		"surface_references": surface_count,
		"unique_mesh_resources": mesh_refs.size(),
		"mesh_reference_distribution": mesh_distribution,
		"unique_base_material_resources": base_material_refs.size(),
		"base_material_reference_distribution": base_material_distribution,
		"unique_override_material_resources": override_material_refs.size(),
		"override_material_reference_distribution": override_material_distribution,
		"unique_texture_resources": texture_refs.size(),
		"texture_reference_distribution": texture_distribution,
		"top_shared_meshes": _top_resources(mesh_refs, 12),
		"top_shared_base_materials": _top_resources(base_material_refs, 12),
		"top_shared_override_materials": _top_resources(override_material_refs, 12),
		"top_shared_textures": _top_resources(texture_refs, 12),
		"performance_monitors": {
			"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"object_resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"object_node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		},
		"inspection_duration_usec": Time.get_ticks_usec() - started,
	}

static func _collect_textures(material: Material, refs: Dictionary) -> void:
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		for property_name in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]:
			var texture: Variant = base.get(property_name)
			if texture is Texture2D:
				var key := str(texture.get_instance_id())
				refs[key] = int(refs.get(key, 0)) + 1
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		var shader := shader_material.shader
		if shader == null:
			return
		for parameter in shader.get_shader_uniform_list():
			if int(parameter.get("type", TYPE_NIL)) != TYPE_OBJECT:
				continue
			var texture: Variant = shader_material.get_shader_parameter(str(parameter.get("name", "")))
			if texture is Texture2D:
				var key := str(texture.get_instance_id())
				refs[key] = int(refs.get(key, 0)) + 1

static func _distribution(values: Array) -> Dictionary:
	var result := {"single_reference": 0, "2_to_10": 0, "11_to_100": 0, "over_100": 0}
	for value in values:
		var count := int(value)
		if count <= 1:
			result.single_reference += 1
		elif count <= 10:
			result["2_to_10"] += 1
		elif count <= 100:
			result["11_to_100"] += 1
		else:
			result.over_100 += 1
	return result

static func _top_resources(refs: Dictionary, limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key in refs.keys():
		var instance: Object = instance_from_id(int(key))
		rows.append({
			"instance_id": int(key),
			"references_in_tree": int(refs[key]),
			"class": instance.get_class() if instance != null else "freed",
			"resource_path": str(instance.resource_path) if instance is Resource else "",
			"resource_name": str(instance.resource_name) if instance is Resource else "",
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.references_in_tree) > int(b.references_in_tree))
	if rows.size() > limit:
		rows.resize(limit)
	return rows
