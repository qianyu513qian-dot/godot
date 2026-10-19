extends Node3D
class_name ResourceNode3D
const Assets := preload("res://scripts/asset_kit.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
## Map resource (tree / stone / gold). Meat comes from farms.

enum Kind { WOOD, STONE, GOLD }

var kind: Kind = Kind.WOOD
var amount: int = 200
var max_amount: int = 200
var radius: float = 1.2
var block_radius: float = 1.0  # units must stay outside this

var _mesh: MeshInstance3D
var _label: Label3D
var selected: bool = false
var _select: MeshInstance3D = null
var _depleted_for_navigation: bool = false
var _navigation_owner_ref: WeakRef = null

func _ready() -> void:
	var main: Node = get_tree().get_first_node_in_group("main_game")
	if main != null:
		_navigation_owner_ref = weakref(main)

func _exit_tree() -> void:
	# Harvest depletion removes a blocker during live play. Ordinary scene
	# teardown must not invalidate the outgoing navigation grid.
	if not _depleted_for_navigation or not is_queued_for_deletion():
		return
	var main: Node = _navigation_owner_ref.get_ref() if _navigation_owner_ref != null else null
	if main == null or not is_instance_valid(main):
		return
	if bool(main.get("_world_teardown_in_progress")) or not bool(main.get("_match_started")):
		return
	var active_world: Node = main.get("world")
	if active_world == null or not is_instance_valid(active_world) or not active_world.is_inside_tree() or not active_world.is_ancestor_of(self):
		return
	Pathfind.invalidate()

func setup(p_kind: Kind, pos: Vector3, p_amount: int = 200) -> void:
	kind = p_kind
	amount = p_amount
	max_amount = p_amount
	position = pos
	add_to_group("resources")
	match kind:
		Kind.WOOD:
			radius = 1.4
			block_radius = 0.85
		Kind.STONE:
			radius = 1.6
			block_radius = 1.35
		Kind.GOLD:
			radius = 1.55
			block_radius = 1.4
	_build_visual()
	_ensure_select_ring()
	set_selected(false)

func res_key() -> String:
	match kind:
		Kind.WOOD: return "wood"
		Kind.STONE: return "stone"
		Kind.GOLD: return "gold"
	return "wood"

func harvest(chunk: int) -> int:
	var took := mini(chunk, amount)
	amount -= took
	_update_label()
	if amount <= 0:
		_depleted_for_navigation = true
		queue_free()
	return took

func blocks_unit_at(unit_pos: Vector3, unit_radius: float = 0.4) -> bool:
	var d := Vector2(unit_pos.x - global_position.x, unit_pos.z - global_position.z).length()
	return d < block_radius + unit_radius

func gather_approach(from_pos: Vector3) -> Vector3:
	## Stand just outside the block radius, facing the node.
	var dx: float = from_pos.x - global_position.x
	var dz: float = from_pos.z - global_position.z
	var flat := Vector2(dx, dz)
	if flat.length_squared() < 0.0001:
		flat = Vector2(1, 0)
	flat = flat.normalized()
	var stand: float = block_radius + 0.55
	return Vector3(global_position.x + flat.x * stand, 0.0, global_position.z + flat.y * stand)

func _build_visual() -> void:
	match kind:
		Kind.WOOD:
			if Assets.attach(self, "wood", Vector3(2.8, 5.0, 2.8)) == null:
				if Assets.attach(self, "candy_tree", Vector3(2.8, 5.0, 2.8)) == null:
					const Kit := preload("res://scripts/mesh_kit.gd")
					Kit.build_candy_tree(self)
			_mesh = MeshInstance3D.new()
			_mesh.visible = false
			add_child(_mesh)
		Kind.STONE:
			if Assets.attach(self, "stone", Vector3(2.4, 1.6, 2.2)) == null:
				# last resort: models/stone.glb via broken key path — procedural rock
				const Kit2 := preload("res://scripts/mesh_kit.gd")
				Kit2.add_sphere(self, 1.1, 1.6, Vector3(0, 0.8, 0), Color(0.55, 0.52, 0.48), 0.92)
			_mesh = MeshInstance3D.new()
			_mesh.visible = false
			add_child(_mesh)
		Kind.GOLD:
			if Assets.attach(self, "gold", Vector3(2.2, 1.5, 2.0)) == null:
				const Kit3 := preload("res://scripts/mesh_kit.gd")
				Kit3.add_sphere(self, 1.0, 1.5, Vector3(0, 0.75, 0), Color(0.95, 0.78, 0.22), 0.55)
			_mesh = MeshInstance3D.new()
			_mesh.visible = false
			add_child(_mesh)
	_label = Label3D.new()
	_label.position = Vector3(0, 6.5, 0)
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.font_size = 48
	_label.modulate = Color(1, 1, 0.85)
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)
	_update_label()

func _update_label() -> void:
	if _label:
		_label.text = "%d" % amount


func display_name() -> String:
	match kind:
		Kind.WOOD: return "树林"
		Kind.STONE: return "石矿"
		Kind.GOLD: return "金矿"
	return "资源"

func set_selected(v: bool) -> void:
	selected = v
	_ensure_select_ring()
	if _select:
		_select.visible = v

func _ensure_select_ring() -> void:
	if _select != null:
		return
	_select = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(block_radius * 0.9, 0.8)
	tor.outer_radius = maxf(block_radius * 1.15, 1.05)
	tor.rings = 6
	tor.ring_segments = 24
	_select.mesh = tor
	_select.position.y = 0.05
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.95, 0.85, 0.2, 0.9)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = -4
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select.material_override = sm
	_select.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_select.visible = false
	add_child(_select)

func contains_point_xz(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < maxf(radius, block_radius) + 0.4

func ray_hit_distance(origin: Vector3, dir: Vector3) -> float:
	var center := global_position + Vector3(0, 1.0, 0)
	var half := Vector3(maxf(block_radius, 1.0), 2.5, maxf(block_radius, 1.0))
	var inv := global_transform.affine_inverse()
	var local_o := inv * origin
	var local_d := inv.basis * dir
	var aabb := AABB(-half, half * 2.0)
	var hit = aabb.intersects_ray(local_o, local_d)
	if hit == null:
		# Fallback xz proximity along ray-ground
		if absf(dir.y) > 0.0001:
			var t := -origin.y / dir.y
			if t > 0.0:
				var gp: Vector3 = origin + dir * t
				if contains_point_xz(gp):
					return origin.distance_to(gp)
		return -1.0
	return origin.distance_to(to_global(hit))
