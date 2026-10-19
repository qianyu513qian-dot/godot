extends RefCounted
class_name AssetKit
## Map gameplay entities 1:1 onto Fantastic Village Pack GLBs (textured).
## Buildings use exported aliases under assets/fantastic_village/;
## resources/farm compose from pieces/; units fall back to assets/models/
## (pack has no character meshes).

const ROOT := "res://assets/fantastic_village/"
const PIECES := "res://assets/fantastic_village/pieces/"
const FALLBACK_ROOT := "res://assets/models/"
const ENV := "res://assets/fantastic_village/env/"
const MaterialProfile := preload("res://scripts/village_material_profile.gd")

## gameplay key -> primary GLB (relative to ROOT unless starts with pieces/ or res://)
const MAP := {
	"town_center": "town_center.glb",           # SM_BLD_body_v01_01
	"house": "house.glb",                       # SM_BLD_body_v03_02
	"arrow_tower": "arrow_tower.glb",           # SM_PROP_watchtower_wood_01
	"barracks": "barracks.glb",                 # SM_BLD_body_v02_01
	"gate": "gate.glb",                         # SM_PROP_wall_wood_gate_frame_01
	"wall": "wall.glb",                         # SM_PROP_wall_wood (reoriented)
	"relay": "relay.glb",                       # SM_PROP_market_v04_01
	"garrison": "garrison.glb",                 # SM_BLD_body_v04_01
	"scout_camp": "scout_camp.glb",             # SM_PROP_market_v01_01
	"candy_tree": "candy_tree.glb",             # SM_ENV_TREE_village_LOD0
	"wood": "candy_tree.glb",
	# composed at runtime (not single file):
	"farm": "",
	"stone": "",
	"gold": "",
	"lumber": "pieces/SM_PROP_cart_01.glb",
	# pack has no characters — models/ toy GLBs
	"villager": "villager.glb",
	"soldier": "soldier.glb",
	"enemy": "enemy.glb",
	"zombie": "zombie.glb",
}

## Native AABB after glTF Y-up import (aliases match piece probes).
const NATIVE := {
	"town_center": Vector3(8.21, 14.28, 7.11),
	"house": Vector3(7.22, 8.36, 6.90),
	"arrow_tower": Vector3(5.01, 11.21, 4.48),
	"barracks": Vector3(7.91, 8.47, 7.88),
	"gate": Vector3(6.48, 7.47, 1.53),
	"wall": Vector3(10.30, 6.26, 3.60),
	"relay": Vector3(6.68, 3.78, 3.49),
	"garrison": Vector3(7.59, 10.78, 12.88),
	"scout_camp": Vector3(4.21, 3.50, 3.62),
	"candy_tree": Vector3(4.71, 5.94, 4.71),
	"wood": Vector3(4.71, 5.94, 4.71),
	"lumber": Vector3(2.34, 1.68, 4.38),
	"farm": Vector3(5.5, 1.2, 5.5),
	"gold": Vector3(2.6, 1.8, 2.4),
	"stone": Vector3(2.8, 1.9, 2.5),
	# Source character GLBs are Z-up. These are measured extents after the runtime
	# wrapper rotates the source's Z axis onto gameplay Y.
	"villager": Vector3(0.84, 1.59, 0.80),
	"soldier": Vector3(0.80, 1.772, 0.80),
	"enemy": Vector3(0.80, 1.772, 0.80),
	"zombie": Vector3(0.80, 1.772, 0.80),
}

## Human-readable pack source for docs / selftest.
const PACK_SOURCE := {
	"town_center": "SM_BLD_body_v01_01",
	"house": "SM_BLD_body_v03_02",
	"barracks": "SM_BLD_body_v02_01",
	"garrison": "SM_BLD_body_v04_01",
	"arrow_tower": "SM_PROP_watchtower_wood_01",
	"wall": "SM_PROP_wall_wood",
	"gate": "SM_PROP_wall_wood_gate_frame_01",
	"relay": "SM_PROP_market_v04_01",
	"scout_camp": "SM_PROP_market_v01_01",
	"candy_tree": "SM_ENV_TREE_village_LOD0",
	"wood": "SM_ENV_TREE_village_LOD0",
	"farm": "T_ENV_farmfield_BC + SM_PROP_hay_* + SM_PROP_fence_v01_01",
	"stone": "SM_PROP_stone_* + SM_PROP_wall_stone_small_* pile",
	"gold": "same pile, gold tint",
	"lumber": "SM_PROP_cart_01",
	"villager": "(no pack char) models/villager.glb",
	"soldier": "(no pack char) models/soldier.glb",
	"enemy": "(no pack char) models/enemy.glb",
	"zombie": "(no pack char) models/zombie.glb",
}

static var _cache: Dictionary = {}
static var _unit_vertex_material: StandardMaterial3D = null

static func mapping_table() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("game_key\tpack_source\tpath")
	for k in MAP.keys():
		lines.append("%s\t%s\t%s" % [k, str(PACK_SOURCE.get(k, "?")), str(MAP[k])])
	return "\n".join(lines)

static func _resolve_path(key: String) -> String:
	var fname: String = str(MAP.get(key, ""))
	if fname == "":
		return ""
	if fname.begins_with("res://"):
		return fname
	if fname.begins_with("pieces/"):
		var p := ROOT + fname
		if ResourceLoader.exists(p):
			return p
		return ""
	var path := ROOT + fname
	if ResourceLoader.exists(path):
		return path
	path = FALLBACK_ROOT + fname
	if ResourceLoader.exists(path):
		return path
	return ""

static func _packed(key: String) -> PackedScene:
	if _cache.has(key):
		return _cache[key]
	var path := _resolve_path(key)
	if path == "":
		_cache[key] = null
		return null
	var res = load(path)
	if res is PackedScene:
		_cache[key] = res
		return res
	_cache[key] = null
	return null

static func _load_piece(mesh_name: String) -> PackedScene:
	var ck := "piece:" + mesh_name
	if _cache.has(ck):
		return _cache[ck]
	var path := PIECES + mesh_name + ".glb"
	if not ResourceLoader.exists(path):
		_cache[ck] = null
		return null
	var res = load(path)
	if res is PackedScene:
		_cache[ck] = res
		return res
	_cache[ck] = null
	return null

static func _inst_piece(mesh_name: String) -> Node3D:
	var ps := _load_piece(mesh_name)
	if ps == null:
		return null
	return ps.instantiate() as Node3D

static func attach(parent: Node3D, key: String, target_size: Vector3 = Vector3.ZERO, y_lift: float = 0.0) -> Node3D:
	if key == "farm":
		return attach_farm(parent, target_size, y_lift)
	if key == "stone":
		return attach_ore_pile(parent, target_size, false, y_lift)
	if key == "gold":
		return attach_ore_pile(parent, target_size, true, y_lift)
	var ps := _packed(key)
	if ps == null:
		return null
	var root: Node3D = ps.instantiate() as Node3D
	if root == null:
		return null
	root.name = "Asset_" + key
	parent.add_child(root)
	_fit_scale(root, key, target_size)
	root.position = Vector3(0, y_lift, 0)
	_enable_shadows(root)
	if key in ["villager", "soldier", "enemy", "zombie"]:
		_adapt_unit_axes_and_normals(root)
		_apply_unit_vertex_colors(root)
	return root

static func _adapt_unit_axes_and_normals(root: Node3D) -> void:
	## Character GLBs are authored Z-up, while gameplay uses Y-up. Keep the source
	## mesh intact and apply a reversible root wrapper transform per instance.
	root.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh is ArrayMesh:
			mesh_instance.mesh = _mesh_with_derived_normals(mesh_instance.mesh as ArrayMesh)

static func _mesh_with_derived_normals(source: ArrayMesh) -> ArrayMesh:
	var derived := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_NORMAL:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		if normals.size() == 0 and vertices.size() > 0:
			normals.resize(vertices.size())
			for vertex_index in normals.size():
				normals[vertex_index] = Vector3.ZERO
			var triangle_count := indices.size() if indices.size() > 0 else vertices.size()
			for triangle_start in range(0, triangle_count - 2, 3):
				var i0 := indices[triangle_start] if indices.size() > 0 else triangle_start
				var i1 := indices[triangle_start + 1] if indices.size() > 0 else triangle_start + 1
				var i2 := indices[triangle_start + 2] if indices.size() > 0 else triangle_start + 2
				if i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
					continue
				var face_normal := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
				if face_normal.length_squared() <= 0.00000001:
					continue
				normals[i0] += face_normal
				normals[i1] += face_normal
				normals[i2] += face_normal
			for vertex_index in normals.size():
				normals[vertex_index] = normals[vertex_index].normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		derived.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		derived.surface_set_material(surface, source.surface_get_material(surface))
	return derived

static func _apply_unit_vertex_colors(root: Node3D) -> void:
	## The fallback character GLBs contain authored COLOR_0 palettes but no materials.
	## Godot's default white material ignores those colors unless this flag is enabled.
	if _unit_vertex_material == null:
		_unit_vertex_material = StandardMaterial3D.new()
		# Keep the authored palette from washing out under the game's directional sun.
		_unit_vertex_material.albedo_color = Color(0.72, 0.72, 0.72)
		_unit_vertex_material.vertex_color_use_as_albedo = true
		_unit_vertex_material.vertex_color_is_srgb = false
		_unit_vertex_material.roughness = 0.86
		_unit_vertex_material.metallic = 0.0
		_unit_vertex_material.cull_mode = BaseMaterial3D.CULL_BACK
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, _unit_vertex_material)

static func _fit_scale(root: Node3D, key: String, target_size: Vector3) -> void:
	var native: Vector3 = NATIVE.get(key, Vector3(1, 1, 1))
	var s := 1.0
	if target_size.length() > 0.01 and native.length() > 0.01:
		var sx := target_size.x / maxf(native.x, 0.01)
		var sy := target_size.y / maxf(native.y, 0.01)
		var sz := target_size.z / maxf(native.z, 0.01)
		if key == "wall" or key == "gate":
			s = sx
		elif key == "villager" or key == "soldier" or key == "enemy" or key == "zombie":
			s = sy
		elif key == "candy_tree" or key == "wood":
			s = sy * 0.95
		elif key == "arrow_tower":
			s = minf(sx, sz)
		elif key == "lumber":
			s = minf(sx, sz) * 0.9
		else:
			s = minf(sx, sz)
	root.scale = Vector3(s, s, s)

static func attach_farm(parent: Node3D, target_size: Vector3 = Vector3(5.5, 0.1, 5.5), y_lift: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Asset_farm"
	parent.add_child(root)
	var sx: float = maxf(target_size.x, 3.0)
	var sz: float = maxf(target_size.z, 3.0)
	# Farm field plane (Fantastic Village farmfield albedo)
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sx * 0.98, sz * 0.98)
	field.mesh = plane
	field.position = Vector3(0, 0.04 + y_lift, 0)
	var fmat := StandardMaterial3D.new()
	fmat.roughness = 0.95
	fmat.metallic = 0.0
	var tex_path := ENV + "T_ENV_farmfield_BC.png"
	if ResourceLoader.exists(tex_path):
		fmat.albedo_texture = load(tex_path)
		fmat.uv1_scale = Vector3(2.5, 2.5, 2.5)
		fmat.albedo_color = Color(1, 1, 1)
	else:
		fmat.albedo_color = Color(0.55, 0.48, 0.28)
	field.material_override = fmat
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(field)
	# Hay stacks (pack props)
	var hay_names: Array = ["SM_PROP_hay_01", "SM_PROP_hay_03", "SM_PROP_hay_04", "SM_PROP_hay_02"]
	var hay_slots: Array = [
		Vector3(-sx * 0.28, 0, -sz * 0.28),
		Vector3(sx * 0.22, 0, -sz * 0.18),
		Vector3(-sx * 0.12, 0, sz * 0.22),
		Vector3(sx * 0.28, 0, sz * 0.12),
	]
	for i in mini(hay_names.size(), hay_slots.size()):
		var h: Node3D = _inst_piece(str(hay_names[i]))
		if h == null:
			continue
		h.name = "Hay_%d" % i
		h.position = hay_slots[i] + Vector3(0, y_lift, 0)
		h.scale = Vector3(0.85, 0.85, 0.85)
		h.rotation_degrees.y = float(i) * 37.0
		root.add_child(h)
		_enable_shadows(h)
	# Fence ring (low posts)
	var fence_ps := _load_piece("SM_PROP_fence_v01_01")
	if fence_ps:
		var half_x := sx * 0.48
		var half_z := sz * 0.48
		var segs: Array = [
			[Vector3(0, 0, -half_z), 0.0, sx / 2.86],
			[Vector3(0, 0, half_z), 180.0, sx / 2.86],
			[Vector3(-half_x, 0, 0), 90.0, sz / 2.86],
			[Vector3(half_x, 0, 0), -90.0, sz / 2.86],
		]
		for si in segs.size():
			var spec: Array = segs[si]
			var fnode: Node3D = fence_ps.instantiate() as Node3D
			if fnode == null:
				continue
			fnode.name = "Fence_%d" % si
			var sc: float = clampf(float(spec[2]) * 0.92, 0.55, 1.35)
			fnode.scale = Vector3(sc, 0.55, sc)
			fnode.position = spec[0] + Vector3(0, y_lift, 0)
			fnode.rotation_degrees.y = float(spec[1])
			root.add_child(fnode)
			_enable_shadows(fnode)
	return root

static func attach_ore_pile(parent: Node3D, target_size: Vector3, as_gold: bool, y_lift: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Asset_gold" if as_gold else "Asset_stone"
	parent.add_child(root)
	var want: Vector3 = target_size
	if want.length() < 0.01:
		want = NATIVE["gold"] if as_gold else NATIVE["stone"]
	# Rocky outcrop from wall-stone blocks + ground stones
	var pieces_spec: Array = [
		["SM_PROP_wall_stone_small_02", Vector3(0, 0, 0), Vector3(0, 90, 0), 0.95],
		["SM_PROP_wall_stone_small_01", Vector3(0.55, 0, 0.35), Vector3(0, 20, 0), 0.85],
		["SM_PROP_wall_stone_small_03", Vector3(-0.45, 0, -0.25), Vector3(0, -40, 0), 0.8],
		["SM_PROP_stone_01", Vector3(0.1, 0.55, 0.05), Vector3(0, 15, 0), 1.1],
		["SM_PROP_stone_02", Vector3(-0.35, 0.5, 0.4), Vector3(0, 55, 0), 1.2],
		["SM_PROP_stone_03", Vector3(0.5, 0.48, -0.3), Vector3(0, -25, 0), 1.3],
		["SM_PROP_stone_04", Vector3(-0.15, 0.7, -0.15), Vector3(0, 70, 0), 1.0],
	]
	var any := false
	for spec in pieces_spec:
		var n: Node3D = _inst_piece(str(spec[0]))
		if n == null:
			continue
		any = true
		n.position = spec[1] + Vector3(0, y_lift, 0)
		n.rotation_degrees = spec[2]
		var sc: float = float(spec[3])
		n.scale = Vector3(sc, sc, sc)
		root.add_child(n)
		_enable_shadows(n)
	if not any:
		root.queue_free()
		return null
	# Fit composed pile roughly to target footprint
	var approx := Vector3(2.6, 1.6, 2.4)
	var s := minf(want.x / approx.x, want.z / approx.z)
	s = clampf(s, 0.5, 2.2)
	root.scale = Vector3(s, s, s)
	if as_gold:
		_tint_subtree(root, Color(1.0, 0.82, 0.28))
	return root

static func _tint_subtree(node: Node, tint: Color) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var base: Material = mi.get_active_material(0)
		var mat: StandardMaterial3D
		if base is StandardMaterial3D:
			mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
			if base:
				mat.next_pass = base
		mat.albedo_color = tint
		if mat.albedo_texture != null:
			mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
		mi.material_override = mat

static func _enable_shadows(node: Node) -> void:
	MaterialProfile.apply_to(node)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
