extends Node3D
class_name EcoBuilding3D
## 3D building: collision footprint, full-mesh pick, gate anim, wall links.

signal train_finished(unit_type: String, spawn_pos: Vector3, building: Node3D)

const Catalog := preload("res://scripts/building_catalog.gd")
const Hub := preload("res://scripts/hub_grid.gd")
const Kit := preload("res://scripts/mesh_kit.gd")
const Assets := preload("res://scripts/asset_kit.gd")
const Fort := preload("res://scripts/fortify.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const Combat := preload("res://scripts/combat.gd")
const ArrowScr := preload("res://scripts/arrow_projectile.gd")

var kind: int = Catalog.TOWN_CENTER
var team: String = "player"
var hp: float = 500.0
var alive: bool = true
var max_hp: float = 500.0
var selected: bool = false
var is_dropoff: bool = false
var dropoff_keys: Array = []
var pop_bonus: int = 0
var radius: float = 1.6
var footprint: Vector3 = Vector3(2, 1.5, 2)  # XZ collision + height

var meat_stock: int = 0
var is_meat_source: bool = false
var is_arid: bool = false
var meat_max: int = 800

var needs_hub: bool = false
var is_hub: bool = false
var hub_range: float = 0.0
var in_hub_range: bool = true
var powered: bool = true
var is_lab: bool = false
var is_wall: bool = false
var is_gate: bool = false
var is_tower: bool = false
var attack_range: float = 0.0
var attack_damage: float = 0.0
var attack_interval: float = 1.75
var _tower_cd: float = 0.0
var armor_melee: int = 0
var armor_pierce: int = 0
var military_role: String = ""
var blocks_path: bool = true
var is_complete: bool = true
var build_progress: float = 0.0
var build_time: float = 1.0
var _builders: Dictionary = {}  # instance_id -> Node
var _build_bar: Label3D = null
var train_durations: Dictionary = {}

var train_queue: Array[String] = []
var train_timer: float = 0.0
var train_duration: float = 3.0
var train_paid: bool = false  ## front unit cost deducted (started)
var train_paused: bool = false  ## waiting for resources to start front
var has_rally: bool = false
var rally_point: Vector3 = Vector3.ZERO
var _rally_flag: Node3D = null
var _rally_line: MeshInstance3D = null

var _mesh: MeshInstance3D
var _select_ring: MeshInstance3D
var _name_label: Label3D
var _hub_ring: MeshInstance3D
var _hub_force_show: bool = false
var _link_root: Node3D = null
var _linked_ids: Dictionary = {}  # instance_id -> true

# Gate animation
var _door_l: Node3D = null
var _door_r: Node3D = null
var _gate_closed: Node3D = null
var _door_l_base: Transform3D
var _door_r_base: Transform3D
var _gate_open: float = 0.0  # 0 closed .. 1 open
var gate_locked: bool = false  ## locked = stay closed; no ally auto-open
var _gate_want_open: bool = false
var _gate_open_dist: float = 5.0  # doorway proximity only
var _doors_base_ok: bool = false
var _gate_dbg_t: float = 0.0
var _block_segs: Array = []

func setup(p_kind: int, pos: Vector3, p_team: String = "player", complete: bool = true) -> void:
	kind = p_kind
	team = p_team
	position = pos
	add_to_group("buildings")
	_apply_catalog()
	hp = max_hp
	is_complete = complete
	if complete and (kind == Catalog.TOWN_CENTER or kind == Catalog.ATTACK_BARRACKS):
		has_rally = true
		rally_point = position + Vector3(radius + 3.0, 0.0, 0.0)
	if not complete:
		build_progress = 0.0
		# Farms don't produce until complete
		if is_meat_source:
			is_meat_source = false
			if is_in_group("resources"):
				remove_from_group("resources")
	else:
		build_progress = build_time
	_build_visual()
	_ensure_build_bar()
	_apply_construction_visual()
	set_selected(false)
	Hub.invalidate()
	Pathfind.invalidate()
	set_process(true)
	if is_gate:
		call_deferred("_apply_door_swing", 0.0)
	if is_wall or is_gate or is_tower:
		call_deferred("_deferred_fort_refresh")

func _deferred_fort_refresh() -> void:
	Fort.refresh_all(get_tree())

func _apply_catalog() -> void:
	var d: Dictionary = Catalog.get_def(kind)
	if d.is_empty():
		return
	max_hp = float(d.get("hp", 200.0))
	radius = float(d.get("radius", 1.5))
	footprint = d.get("size", Vector3(2, 1.5, 2))
	pop_bonus = int(d.get("pop_bonus", 0))
	needs_hub = bool(d.get("needs_hub", false))
	is_hub = bool(d.get("is_hub", false))
	hub_range = float(d.get("hub_range", 0.0))
	is_dropoff = bool(d.get("is_dropoff", false))
	dropoff_keys = d.get("dropoff_keys", []).duplicate()
	is_lab = bool(d.get("is_lab", false))
	is_wall = bool(d.get("is_wall", false))
	is_gate = bool(d.get("is_gate", false))
	is_tower = bool(d.get("is_tower", false))
	alive = true
	military_role = str(d.get("military_role", ""))
	attack_range = float(d.get("attack_range", 0.0))
	attack_damage = float(d.get("attack_damage", 0.0))
	attack_interval = float(d.get("attack_interval", 1.75))
	is_meat_source = bool(d.get("is_meat_source", false))
	blocks_path = bool(d.get("blocks_path", true))
	armor_melee = int(d.get("armor_melee", 0))
	armor_pierce = int(d.get("armor_pierce", 0))
	build_time = maxf(float(d.get("build_time", 0.0)), 0.01)
	if bool(d.get("is_meat_source", false)) or kind == Catalog.FARM:
		blocks_path = false
		meat_max = int(d.get("meat_stock", 800))
		meat_stock = meat_max
		is_meat_source = meat_stock > 0
		is_arid = false
		add_to_group("farms")
		if is_meat_source:
			add_to_group("resources")
	in_hub_range = not needs_hub
	powered = in_hub_range

func _build_visual() -> void:
	var d: Dictionary = Catalog.get_def(kind)
	var size: Vector3 = d.get("size", Vector3(2, 1.5, 2))
	var col: Color = d.get("color", Color(0.6, 0.5, 0.4))
	footprint = size

	_add_dirt_pad(size)

	match kind:
		Catalog.TOWN_CENTER:
			if Assets.attach(self, "town_center", size) == null:
				Kit.build_town_center(self, size)
		Catalog.HOUSE:
			if Assets.attach(self, "house", size) == null:
				Kit.build_house(self, size)
		Catalog.RELAY:
			if Assets.attach(self, "relay", size) == null:
				Kit.build_relay(self, size)
		Catalog.WALL:
			if Assets.attach(self, "wall", size) == null:
				Kit.build_wall_segment(self, size)
		Catalog.GATE:
			# GLB frame from Fantastic Village + procedural hinged doors for anim
			Assets.attach(self, "gate", size)
			Kit.build_gate(self, size)
			_cache_gate_doors()
			# Keep only hinged door nodes from Kit; hide the rest of procedural gate body
			for c in get_children():
				var n := str(c.name)
				if n.begins_with("GateHinge") or n.begins_with("GateDoor") or n == "GateClosed":
					continue
				if n.begins_with("Asset_"):
					continue
				if c is MeshInstance3D and c.get_parent() == self:
					c.visible = false
				elif n.begins_with("Gate") and c is Node3D and c.get_parent() == self:
					# hide GateTower etc., but not hinges (already continued)
					if not n.begins_with("GateHinge"):
						c.visible = false
		Catalog.ARROW_TOWER:
			if Assets.attach(self, "arrow_tower", size) == null:
				Kit.build_arrow_tower(self, size)
		Catalog.SCOUT_CAMP:
			if Assets.attach(self, "scout_camp", size) == null:
				Kit.build_scout_camp(self, size)
		Catalog.ATTACK_BARRACKS:
			if Assets.attach(self, "barracks", size) == null:
				Kit.build_attack_barracks(self, size)
		Catalog.DEFEND_GARRISON:
			if Assets.attach(self, "garrison", size) == null:
				Kit.build_defend_garrison(self, size)
		Catalog.FARM:
			if Assets.attach(self, "farm", size) == null:
				_build_farm(size, col)
		_:
			_mesh = MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			_mesh.mesh = box
			_mesh.position.y = size.y * 0.5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 0.78
			_mesh.material_override = mat
			_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(_mesh)
			if kind == Catalog.LUMBER_CAMP:
				_mesh.visible = false
				if Assets.attach(self, "lumber", size) == null:
					Kit.add_prism(self, Vector3(size.x * 1.05, size.y * 0.35, size.z * 1.05), Vector3(0, size.y + size.y * 0.12, 0), Color(0.45, 0.28, 0.16))
			elif kind == Catalog.WAREHOUSE or kind == Catalog.QUARRY:
				Kit.add_prism(self, Vector3(size.x * 1.05, size.y * 0.35, size.z * 1.05), Vector3(0, size.y + size.y * 0.12, 0), Color(0.45, 0.28, 0.16))

	_link_root = Node3D.new()
	_link_root.name = "WallLinks"
	add_child(_link_root)

	_select_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(radius * 0.88, footprint.x * 0.35)
	tor.outer_radius = maxf(radius * 1.05, footprint.x * 0.42)
	_select_ring.mesh = tor
	_select_ring.position.y = 0.06
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.2, 0.85, 0.3, 0.85)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = -4
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_ring.material_override = sm
	_select_ring.visible = false
	_select_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_select_ring)

	# Hub coverage is sandy ground creep in main 鈥?no per-building cyan ring.

	_name_label = Label3D.new()
	_name_label.text = str(d.get("name", ""))
	_name_label.position = Vector3(0, size.y + 2.2, 0)
	_name_label.font_size = 64
	_name_label.modulate = Color(1, 0.95, 0.8)
	_name_label.outline_size = 10
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_name_label)

func _add_dirt_pad(size: Vector3) -> void:
	var pad := MeshInstance3D.new()
	pad.mesh = Kit.make_bevel_box(Vector3(size.x * 1.15, 0.12, size.z * 1.15), 0.06, 2)
	pad.position.y = 0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.68, 0.42)
	mat.roughness = 0.45
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.2
	pad.material_override = mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(pad)

func _build_farm(size: Vector3, dirt_col: Color) -> void:
	## Flat ground farm 鈥?walkable, flush with terrain (no raised platform).
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Kit.make_bevel_box(Vector3(size.x * 0.95, 0.14, size.z * 0.95), 0.05, 2)
	_mesh.position.y = 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = dirt_col
	mat.roughness = 0.95
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var crop_mat := StandardMaterial3D.new()
	crop_mat.albedo_color = Color(0.45, 0.82, 0.28)
	crop_mat.roughness = 0.35
	crop_mat.clearcoat_enabled = true
	crop_mat.clearcoat = 0.25
	var rows := 4
	var cols := 4
	var margin := 0.55
	var usable_x := size.x - margin * 2.0
	var usable_z := size.z - margin * 2.0
	for iz in rows:
		for ix in cols:
			var crop := MeshInstance3D.new()
			var cbox := BoxMesh.new()
			cbox.size = Vector3(usable_x / cols * 0.78, 0.12, usable_z / rows * 0.62)
			crop.mesh = cbox
			var px := -usable_x * 0.5 + (ix + 0.5) * (usable_x / cols)
			var pz := -usable_z * 0.5 + (iz + 0.5) * (usable_z / rows)
			crop.position = Vector3(px, 0.12, pz)
			crop.material_override = crop_mat
			crop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(crop)
	# Tiny corner pegs (fence markers), not blocking posts
	var wood := Color(0.42, 0.30, 0.16)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var peg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.06
			cyl.bottom_radius = 0.06
			cyl.height = 0.35
			peg.mesh = cyl
			peg.position = Vector3(x * size.x * 0.46, 0.18, z * size.z * 0.46)
			var pm := StandardMaterial3D.new()
			pm.albedo_color = wood
			peg.material_override = pm
			peg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(peg)

func set_selected(v: bool) -> void:
	selected = v
	if _select_ring:
		_select_ring.visible = v
	# No hub ring overlay 鈥?coverage is ground creep
	# Rally uses global_position / look_at 鈥?only when in tree
	if has_rally and is_inside_tree():
		_update_rally_visuals()


func set_hub_overlay_visible(_v: bool) -> void:
	## Deprecated: cyan rings removed; main owns sandy creep discs.
	_hub_force_show = false
	if _hub_ring:
		_hub_ring.visible = false

func _ensure_hub_ring() -> void:
	## No-op 鈥?range shown as sandy ground tint, not a torus ring.
	if _hub_ring:
		_hub_ring.visible = false

func contains_point_xz(p: Vector3) -> bool:
	## Legacy ground-foot check (kept for gather/drop). Prefer ray_hit_distance for select.
	var hx := footprint.x * 0.55
	var hz := footprint.z * 0.55
	return absf(p.x - global_position.x) <= hx and absf(p.z - global_position.z) <= hz

func ray_hit_distance(origin: Vector3, dir: Vector3) -> float:
	## Full building AABB pick (not just feet). Returns hit distance or -1.
	var hy: float = footprint.y * 0.55 + 0.4
	if is_meat_source:
		hy = maxf(hy, 0.8)
	var half := Vector3(footprint.x * 0.55, hy, footprint.z * 0.55)
	var center := global_position + Vector3(0, half.y, 0)
	# Transform ray into local AABB space (account for Y rotation)
	var inv := global_transform.affine_inverse()
	var local_o := inv * origin
	var local_d := inv.basis * dir
	var aabb := AABB(-half, half * 2.0)
	var t0: float = 0.0
	# Manual AABB ray (Godot AABB.intersects_ray returns Variant in 4.x)
	var hit = aabb.intersects_ray(local_o, local_d)
	if hit == null:
		return -1.0
	var hp: Vector3 = hit
	return origin.distance_to(global_transform * hp)

func overlaps_footprint(other_pos: Vector3, other_fp: Vector3) -> bool:
	return Fort.footprint_overlap(global_position, footprint, other_pos, other_fp)

func is_open_for(unit_team: String) -> bool:
	if gate_locked:
		return false
	return is_gate and unit_team == team and _gate_open > 0.25

func set_gate_locked(locked: bool) -> void:
	if not is_gate:
		return
	var prev: bool = gate_locked
	gate_locked = locked
	if gate_locked:
		_gate_want_open = false
		_gate_open = 0.0
		blocks_path = true
		_apply_door_swing(0.0)
	if prev != gate_locked:
		Pathfind.invalidate()

func toggle_gate_lock() -> bool:
	set_gate_locked(not gate_locked)
	return gate_locked

func is_gate_locked() -> bool:
	return is_gate and gate_locked

func gate_passage_clear(unit_pos: Vector3, unit_team: String, unit_radius: float = 0.4) -> bool:
	## Doorway corridor between towers 鈥?side walls stay solid.
	## Slightly generous half_open so coarse pathfind CELL (1.5) fits through.
	if not is_open_for(unit_team):
		return false
	var local: Vector3 = to_local(unit_pos)
	local.y = 0.0
	var half_open: float = footprint.x * 0.22 + maxf(unit_radius - 0.2, 0.0)
	var depth: float = footprint.z * 0.65 + unit_radius + 0.85
	return absf(local.x) <= half_open and absf(local.z) <= depth

func _seg_blocks_point(unit_pos: Vector3, unit_radius: float) -> bool:
	for seg in _block_segs:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var hw: float = float(seg["hw"]) + unit_radius
		var ab: Vector2 = Vector2(b.x - a.x, b.z - a.z)
		var ap: Vector2 = Vector2(unit_pos.x - a.x, unit_pos.z - a.z)
		var len2: float = ab.length_squared()
		var t: float = 0.0 if len2 < 0.0001 else clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var closest: Vector2 = Vector2(a.x, a.z) + ab * t
		if closest.distance_to(Vector2(unit_pos.x, unit_pos.z)) <= hw:
			return true
	return false

func blocks_unit_at(unit_pos: Vector3, unit_team: String, unit_radius: float = 0.4) -> bool:
	var local: Vector3 = to_local(unit_pos)
	local.y = 0.0
	if is_gate:
		var tw_x: float = footprint.x * 0.36
		var tw_hx: float = footprint.x * 0.16 + unit_radius
		var tw_hz: float = footprint.z * 0.55 + unit_radius
		if absf(local.x + tw_x) <= tw_hx and absf(local.z) <= tw_hz:
			return true
		if absf(local.x - tw_x) <= tw_hx and absf(local.z) <= tw_hz:
			return true
		if is_open_for(unit_team) and gate_passage_clear(unit_pos, unit_team, unit_radius):
			return false
		var cx: float = footprint.x * 0.28 + unit_radius
		var cz: float = footprint.z * 0.55 + unit_radius
		if absf(local.x) <= cx and absf(local.z) <= cz:
			return true
		return _seg_blocks_point(unit_pos, unit_radius)
	if not blocks_path:
		return false
	var hx: float = footprint.x * 0.5 + unit_radius
	var hz: float = maxf(footprint.z * 0.5, 0.75) + unit_radius
	if is_wall:
		hz = maxf(hz, 0.95 + unit_radius)
	if absf(local.x) <= hx and absf(local.z) <= hz:
		# Wall body solid. Only allow if point is strictly in an OPEN gate doorway
		# (walls at 卤9 should not overlap doorway 鈥?this is a safety valve).
		if is_wall or is_tower:
			var tree: SceneTree = get_tree()
			if tree:
				for g in tree.get_nodes_in_group("buildings"):
					if g.has_method("gate_passage_clear") and g.gate_passage_clear(unit_pos, unit_team, unit_radius):
						return false
		return true
	if _seg_blocks_point(unit_pos, unit_radius):
		return true
	return false

func clear_wall_links() -> void:
	_linked_ids.clear()
	_block_segs.clear()
	if _link_root:
		for c in _link_root.get_children():
			c.queue_free()

func link_anchor_toward(other: Node3D) -> Vector3:
	## Gates connect at L/R towers 鈥?never through the doorway center.
	if is_gate:
		var lx: float = to_local(other.global_position).x
		var side: float = 1.0 if lx >= 0.0 else -1.0
		return to_global(Vector3(side * footprint.x * 0.38, 0.0, 0.0))
	return global_position

func add_wall_link(other: Node3D) -> void:
	var id: int = other.get_instance_id()
	if _linked_ids.has(id):
		return
	_linked_ids[id] = true
	var a_pos: Vector3 = link_anchor_toward(other)
	var b_pos: Vector3 = other.global_position
	if other.has_method("link_anchor_toward"):
		b_pos = other.call("link_anchor_toward", self)
	var delta: Vector3 = b_pos - a_pos
	delta.y = 0.0
	var dist: float = delta.length()
	if dist < 0.15:
		return
	var dir: Vector3 = delta.normalized()
	var ra: float = 0.1
	var rb: float = 0.1
	var start: Vector3 = a_pos + dir * ra
	var end: Vector3 = b_pos - dir * rb
	# Collision on BOTH forts so the curtain gap is solid
	var seg: Dictionary = {"a": start, "b": end, "hw": 0.85}
	_block_segs.append(seg)
	if other.get("_block_segs") != null:
		var osegs: Array = other.get("_block_segs")
		osegs.append(seg)
		other.set("_block_segs", osegs)
	# Only one side draws the visual connector
	if get_instance_id() > id:
		return
	if _link_root == null:
		return
	var length: float = maxf(start.distance_to(end), 0.2)
	var mid: Vector3 = (start + end) * 0.5
	mid.y = 1.5
	var link: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.85, 2.2, length + 0.25)
	link.mesh = box
	var basis: Basis = Basis.looking_at(dir, Vector3.UP)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.50, 0.46)
	mat.roughness = 0.88
	link.material_override = mat
	link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_link_root.add_child(link)
	link.global_transform = Transform3D(basis, mid)

func orient_along(dir: Vector2) -> void:
	## Rotate wall so long axis (X) is perpendicular to link dir (face the opening).
	if not is_wall:
		return
	var yaw := atan2(dir.x, dir.y)  # face along dir
	rotation.y = yaw + PI * 0.5

func can_accept_drop(key: String) -> bool:
	return is_complete and is_dropoff and (dropoff_keys.is_empty() or key in dropoff_keys) and in_hub_range

func harvest_meat(chunk: int) -> int:
	if not is_meat_source or is_arid:
		return 0
	var took := mini(chunk, meat_stock)
	meat_stock -= took
	if meat_stock <= 0:
		_become_arid()
	return took

func _become_arid() -> void:
	## Classic AoE: farm stays, goes dry 鈥?reseed to restore stock.
	is_meat_source = false
	is_arid = true
	meat_stock = 0
	if is_in_group("resources"):
		remove_from_group("resources")
	_apply_farm_arid_visual(true)
	if _name_label:
		_name_label.text = "鏋敯"

func reseed(stock: int = -1) -> bool:
	if kind != Catalog.FARM:
		return false
	if not is_arid and meat_stock > 0:
		return false
	if stock < 0:
		stock = meat_max if meat_max > 0 else 800
	meat_stock = stock
	meat_max = stock
	is_arid = false
	is_meat_source = true
	if not is_in_group("resources"):
		add_to_group("resources")
	_apply_farm_arid_visual(false)
	if _name_label:
		_name_label.text = "鍐滅敯"
	return true

func _apply_farm_arid_visual(arid: bool) -> void:
	if kind != Catalog.FARM:
		return
	var dirt := Color(0.55, 0.42, 0.28) if arid else Color(0.48, 0.36, 0.22)
	var crop_c := Color(0.55, 0.45, 0.28) if arid else Color(0.38, 0.62, 0.20)
	for c in get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
				# Heuristic: green-ish 鈫?crop; brown 鈫?dirt pad
				var al: Color = m.albedo_color
				if al.g > al.r and al.g > 0.4:
					m.albedo_color = crop_c
				elif al.r > 0.35 and al.g > 0.25:
					m.albedo_color = dirt

func gather_approach(from_pos: Vector3) -> Vector3:
	## Farms: stand on / near edge of plot (walkable). Prefer outer ring.
	var center: Vector3 = global_position
	var fp = footprint
	var hx: float = maxf(fp.x * 0.35, 1.2)
	var hz: float = maxf(fp.z * 0.35, 1.2)
	var dx: float = from_pos.x - center.x
	var dz: float = from_pos.z - center.z
	if absf(dx) < 0.01 and absf(dz) < 0.01:
		dx = 1.0
	var flat := Vector2(dx, dz).normalized()
	return Vector3(center.x + flat.x * hx, 0.0, center.z + flat.y * hz)

func build_ring_radius() -> float:
	## Stand just outside solid footprint (+ unit clearance).
	return maxf(footprint.x, footprint.z) * 0.5 + 1.15

func build_approach(from_pos: Vector3) -> Vector3:
	## Outside foundation 鈥?builders never walk onto incomplete mesh.
	var center: Vector3 = global_position
	var r: float = build_ring_radius()
	var dx: float = from_pos.x - center.x
	var dz: float = from_pos.z - center.z
	if absf(dx) < 0.01 and absf(dz) < 0.01:
		dx = 1.0
	var flat := Vector2(dx, dz).normalized()
	return Vector3(center.x + flat.x * r, 0.0, center.z + flat.y * r)

func build_stand_for(builder: Node) -> Vector3:
	## Spread builders on a ring so they do not stack / jitter on one point.
	var center: Vector3 = global_position
	var r: float = build_ring_radius()
	var ids: Array = []
	for id in _builders.keys():
		var bn = _builders[id]
		if is_instance_valid(bn) and bn.get("build_site") == self:
			ids.append(int(id))
	if builder != null and is_instance_valid(builder):
		var bid: int = builder.get_instance_id()
		if bid not in ids:
			ids.append(bid)
	ids.sort()
	var n: int = maxi(ids.size(), 1)
	var idx: int = 0
	if builder != null and is_instance_valid(builder):
		idx = ids.find(builder.get_instance_id())
		if idx < 0:
			idx = 0
	var ang: float = (float(idx) / float(n)) * TAU + 0.35
	return Vector3(center.x + cos(ang) * r, 0.0, center.z + sin(ang) * r)

func is_builder_in_range(builder_pos: Vector3) -> bool:
	## Any angle around the perimeter (ring 卤 slack), not a single slot.
	var r_out: float = build_ring_radius() + 1.35
	var r_in: float = maxf(build_ring_radius() * 0.35, 0.8)
	var dx: float = builder_pos.x - global_position.x
	var dz: float = builder_pos.z - global_position.z
	var d2: float = dx * dx + dz * dz
	# Must be outside solid-ish core and within outer build reach
	return d2 <= r_out * r_out and d2 >= r_in * r_in * 0.25

func melee_approach(from_pos: Vector3) -> Vector3:
	## Same perimeter ring as builders 鈥?attackers never walk into solid footprint.
	return build_approach(from_pos)

func is_melee_in_range(attacker_pos: Vector3) -> bool:
	## Strike from outside the solid core (gather/build-style ring).
	var r: float = build_ring_radius()
	var r_out: float = r + 0.9
	var r_in: float = maxf(r * 0.4, 1.0)
	var dx: float = attacker_pos.x - global_position.x
	var dz: float = attacker_pos.z - global_position.z
	var d2: float = dx * dx + dz * dz
	return d2 <= r_out * r_out and d2 >= r_in * r_in * 0.2

func can_train(unit_type: String) -> bool:
	if not is_complete:
		return false
	if unit_type == "villager":
		return kind == Catalog.TOWN_CENTER
	if unit_type == "soldier":
		return kind == Catalog.ATTACK_BARRACKS or kind == Catalog.BARRACKS
	return false

func enqueue_train(unit_type: String) -> bool:
	## Queue only 鈥?cost is deducted when that unit STARTS training.
	if not can_train(unit_type):
		return false
	if train_queue.size() >= 7:
		return false
	train_queue.append(unit_type)
	# Front starts on next _process via _try_start_front
	return true

func cancel_last_train() -> Dictionary:
	## Pop back of queue. Refund only if canceling the paid-in-progress front.
	if train_queue.is_empty():
		return {}
	var canceling_front: bool = (train_queue.size() == 1)
	var ut: String = str(train_queue.pop_back())
	var do_refund: bool = canceling_front and train_paid
	if train_queue.is_empty():
		train_timer = 0.0
		train_paid = false
		train_paused = false
	elif canceling_front:
		# Should not happen (size was 1)
		train_paid = false
		train_paused = false
		train_timer = 0.0
	return {"unit": ut, "refund": do_refund}

func cancel_construction() -> Dictionary:
	## SC2-style cancel foundation: refund costs, free builders, remove self.
	if is_complete:
		return {}
	var d: Dictionary = Catalog.get_def(kind)
	var refund: Dictionary = {
		"wood": int(d.get("cost_wood", 0)),
		"meat": int(d.get("cost_meat", 0)),
		"stone": int(d.get("cost_stone", 0)),
		"gold": int(d.get("cost_gold", 0)),
		"name": str(d.get("name", "")),
	}
	for id in _builders.keys():
		var bn = _builders[id]
		if is_instance_valid(bn):
			if bn.get("build_site") == self:
				bn.set("build_site", null)
			if bn.get("state") != null:
				# IDLE = 0
				bn.set("state", 0)
	_builders.clear()
	Hub.invalidate()
	# Leave tree immediately so UI/selection see it gone (queue_free alone stays valid till frame end)
	if is_inside_tree():
		var p = get_parent()
		if p:
			p.remove_child(self)
	queue_free()
	return refund

func train_progress_01() -> float:
	if train_queue.is_empty() or train_duration <= 0.0 or not train_paid:
		return 0.0
	return clampf(1.0 - train_timer / train_duration, 0.0, 1.0)

func _try_start_front() -> void:
	## Deduct cost when front unit begins; pause queue if cannot afford.
	if train_queue.is_empty() or train_paid:
		train_paused = false
		return
	var ut: String = str(train_queue[0])
	var paid: bool = false
	var tree: SceneTree = get_tree()
	if tree:
		for m in tree.get_nodes_in_group("main_game"):
			if m.has_method("try_pay_train"):
				paid = bool(m.call("try_pay_train", ut))
				break
	if paid:
		var cost: Dictionary = Catalog.train_cost(ut)
		train_duration = float(cost.get("time", 10.0))
		train_timer = train_duration
		train_paid = true
		train_paused = false
	else:
		train_paused = true
		train_timer = 0.0

func register_builder(v: Node) -> void:
	if v == null or not is_instance_valid(v):
		return
	_builders[v.get_instance_id()] = v

func get_is_complete() -> bool:
	return is_complete

func add_build_progress(delta: float, builder: Node = null) -> void:
	if is_complete:
		return
	if builder != null and is_instance_valid(builder):
		_builders[builder.get_instance_id()] = builder
	# Count live builders
	var n: int = 0
	var dead: Array = []
	for id in _builders.keys():
		var bnode = _builders[id]
		if is_instance_valid(bnode) and bnode.get("build_site") == self:
			n += 1
		else:
			dead.append(id)
	for id2 in dead:
		_builders.erase(id2)
	if n < 1:
		n = 1
	# AoE4-ish: 100% + 33% per extra builder
	var rate: float = 1.0 + 0.33 * float(n - 1)
	build_progress += delta * rate
	_update_build_bar()
	if build_progress >= build_time:
		_finish_construction()

func _finish_construction() -> void:
	is_complete = true
	build_progress = build_time
	_builders.clear()
	if can_set_rally() and not has_rally:
		has_rally = true
		rally_point = global_position + Vector3(radius + 3.0, 0.0, 0.0)
	# Restore farm meat source
	var d: Dictionary = Catalog.get_def(kind)
	if bool(d.get("is_meat_source", false)):
		is_meat_source = true
		meat_stock = meat_max if meat_max > 0 else int(d.get("meat_stock", 300))
		if not is_in_group("resources"):
			add_to_group("resources")
	_apply_construction_visual()
	_update_build_bar()
	Hub.invalidate()
	Pathfind.invalidate()
	if is_wall or is_gate or is_tower:
		Fort.refresh_all(get_tree())
	var tree: SceneTree = get_tree()
	if tree:
		for m in tree.get_nodes_in_group("main_game"):
			if m.has_method("_rebuild_hub_creep"):
				m.call("_rebuild_hub_creep")

func _ensure_build_bar() -> void:
	if _build_bar != null:
		return
	_build_bar = Label3D.new()
	_build_bar.position = Vector3(0, footprint.y + 1.5, 0)
	_build_bar.font_size = 48
	_build_bar.modulate = Color(0.4, 0.9, 1.0)
	_build_bar.outline_size = 6
	_build_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_build_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_build_bar)
	_update_build_bar()

func _update_build_bar() -> void:
	if _build_bar == null:
		return
	if is_complete:
		_build_bar.visible = false
		return
	_build_bar.visible = true
	var pct: int = int(clampf(build_progress / build_time, 0.0, 1.0) * 100.0)
	_build_bar.text = "寤洪€?%d%%" % pct

func _apply_construction_visual() -> void:
	var alpha: float = 1.0 if is_complete else 0.55
	for c in get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
				m = m.duplicate()
				mi.material_override = m
				if not is_complete:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					var col: Color = m.albedo_color
					col.a = alpha
					m.albedo_color = col
				else:
					var col2: Color = m.albedo_color
					col2.a = 1.0
					m.albedo_color = col2


func _cache_gate_doors() -> void:
	_door_l = get_node_or_null("GateHingeL")
	_door_r = get_node_or_null("GateHingeR")
	_gate_closed = get_node_or_null("GateClosed")
	# Capture CLOSED base only once (never overwrite with swung pose)
	if _door_l and not _doors_base_ok:
		_door_l_base = Transform3D(Basis.IDENTITY, _door_l.position)
		_door_l.visible = true
	if _door_r and not _doors_base_ok:
		_door_r_base = Transform3D(Basis.IDENTITY, _door_r.position)
		_door_r.visible = true
	if _door_l and _door_r:
		_doors_base_ok = true
	if _gate_closed:
		_gate_closed.visible = false

func _process(delta: float) -> void:
	_tower_combat(delta)
	# Construction builder cleanup + train queue
	if not is_complete:
		_update_build_bar()
	if train_queue.is_empty() or not is_complete:
		return
	if not train_paid:
		_try_start_front()
		if not train_paid:
			return  # paused 鈥?waiting for resources
	train_timer -= delta
	if train_timer <= 0.0:
		var ut: String = str(train_queue.pop_front())
		train_paid = false
		train_paused = false
		var spawn := global_position + Vector3(radius + 1.5, 0, radius + 0.5)
		train_finished.emit(ut, spawn, self)
		# Next front starts next frame (pay-on-start)

func _ally_near_gate() -> bool:
	## Any ally within _gate_open_dist (~5, doorway). Outside range 鈫?gate closes.
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var reach: float = _gate_open_dist
	var reach2: float = reach * reach
	var gx: float = global_position.x
	var gz: float = global_position.z
	for gname in ["villagers", "player_units"]:
		for v in tree.get_nodes_in_group(gname):
			if not is_instance_valid(v):
				continue
			var dx: float = v.global_position.x - gx
			var dz: float = v.global_position.z - gz
			if dx * dx + dz * dz <= reach2:
				return true
	return false

func _apply_door_swing(open_t: float) -> void:
	if not _doors_base_ok or _door_l == null or _door_r == null:
		_cache_gate_doors()
	var t: float = clampf(open_t, 0.0, 1.0)
	var te: float = t * t * (3.0 - 2.0 * t)
	# Outward swing toward +Z (camera / approaching units) so leaves stay visible top-down.
	# ~95 deg: doors end perpendicular to wall 鈥?obvious open book shape.
	var ang: float = te * 1.65
	var slide: float = te * 0.35  # pull leaves slightly into towers
	if _gate_closed:
		_gate_closed.visible = false
	if _door_l:
		_door_l.visible = true
		# Negative Y = outward (+Z) for left leaf
		_door_l.position = _door_l_base.origin + Vector3(-slide, 0.0, 0.0)
		_door_l.rotation = Vector3(0.0, -ang, 0.0)
	if _door_r:
		_door_r.visible = true
		_door_r.position = _door_r_base.origin + Vector3(slide, 0.0, 0.0)
		_door_r.rotation = Vector3(0.0, ang, 0.0)

func _update_gate(delta: float) -> void:
	if not is_gate:
		return
	if gate_locked:
		# Locked: force closed regardless of allies
		_gate_want_open = false
		_gate_open = move_toward(_gate_open, 0.0, delta * 6.0)
	else:
		_gate_want_open = _ally_near_gate()
		if _gate_want_open:
			_gate_open = move_toward(_gate_open, 1.0, delta * 5.0)
			if _gate_open < 0.35:
				_gate_open = 0.35  # immediate visible crack
		else:
			_gate_open = move_toward(_gate_open, 0.0, delta * 4.0)
	var was_blocking: bool = blocks_path
	blocks_path = gate_locked or _gate_open < 0.25
	if was_blocking != blocks_path:
		Pathfind.invalidate()  # reopen/reseal doorway in A* grid
	_apply_door_swing(_gate_open)
	# Debug log ~2/sec
	_gate_dbg_t += delta
	if _gate_dbg_t >= 0.5:
		_gate_dbg_t = 0.0
		var ly: float = _door_l.rotation.y if _door_l else -99.0
		var ry: float = _door_r.rotation.y if _door_r else -99.0
		var nvil: int = 0
		var nearest: float = 9999.0
		var tree: SceneTree = get_tree()
		if tree:
			for v in tree.get_nodes_in_group("villagers"):
				nvil += 1
				var d: float = Vector2(v.global_position.x - global_position.x, v.global_position.z - global_position.z).length()
				nearest = minf(nearest, d)
		var state: String = "OPEN" if _gate_want_open else "CLOSE"
		var line: String = "state=%s detect=%s open=%.2f doors=%s L=%.2f R=%.2f villagers=%d nearest=%.1f reach=%.1f pos=(%.1f,%.1f)\n" % [
			state, str(_gate_want_open), _gate_open, str(_doors_base_ok), ly, ry, nvil, nearest, _gate_open_dist,
			global_position.x, global_position.z
		]
		print("[GATE] ", line.strip_edges())
		for path in ["user://gate_debug.log", "C:/Users/cc/Documents/GodotProjects/AoELite3D/_gate_debug.log"]:
			var prev: String = ""
			if FileAccess.file_exists(path):
				var rd := FileAccess.open(path, FileAccess.READ)
				if rd:
					prev = rd.get_as_text()
					rd.close()
			var fl := FileAccess.open(path, FileAccess.WRITE)
			if fl:
				# Keep last ~8KB
				if prev.length() > 8000:
					prev = prev.substr(prev.length() - 8000)
				fl.store_string(prev + line)
				fl.close()

func _seg_dist_xz(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var ap: Vector2 = Vector2(p.x - a.x, p.z - a.z)
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	var closest: Vector2 = Vector2(a.x, a.z) + ab * t
	return closest.distance_to(Vector2(p.x, p.z))




func res_key() -> String:
	if kind == Catalog.FARM:
		return "meat" if is_meat_source and not is_arid else ""
	return "meat" if is_meat_source else ""



func can_set_rally() -> bool:
	## Production buildings: TC / barracks.
	return is_complete and (kind == Catalog.TOWN_CENTER or kind == Catalog.ATTACK_BARRACKS)

func set_rally(pos: Vector3) -> void:
	if not can_set_rally():
		return
	has_rally = true
	rally_point = Vector3(pos.x, 0.0, pos.z)
	_ensure_rally_visuals()
	_update_rally_visuals()

func get_rally() -> Vector3:
	if has_rally:
		return rally_point
	# Default: slightly in front of building
	return global_position + Vector3(radius + 2.5, 0.0, 0.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and has_rally:
		# setup() may call set_selected before add_child 鈥?catch up here
		_update_rally_visuals()

func _ensure_rally_visuals() -> void:
	if not is_inside_tree():
		return
	if _rally_flag != null:
		return
	_rally_flag = Node3D.new()
	_rally_flag.name = "RallyFlag"
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.06
	pcyl.bottom_radius = 0.08
	pcyl.height = 1.6
	pole.mesh = pcyl
	pole.position.y = 0.8
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.35, 0.3, 0.25)
	pole.material_override = pmat
	_rally_flag.add_child(pole)
	var flag := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.7, 0.45, 0.05)
	flag.mesh = fbox
	flag.position = Vector3(0.35, 1.45, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.2, 0.85, 0.35)
	fmat.emission_enabled = true
	fmat.emission = Color(0.1, 0.6, 0.2)
	fmat.emission_energy_multiplier = 0.8
	flag.material_override = fmat
	_rally_flag.add_child(flag)
	# Parent under world so flag stays at rally world pos
	var parent_n: Node = get_parent()
	if parent_n:
		parent_n.add_child(_rally_flag)
	else:
		add_child(_rally_flag)
	_rally_line = MeshInstance3D.new()
	_rally_line.name = "RallyLine"
	_rally_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent_n:
		parent_n.add_child(_rally_line)
	else:
		add_child(_rally_line)

func _update_rally_visuals() -> void:
	if not has_rally:
		if _rally_flag and is_instance_valid(_rally_flag):
			_rally_flag.visible = false
		if _rally_line and is_instance_valid(_rally_line):
			_rally_line.visible = false
		return
	if not is_inside_tree():
		return  # avoid get_global_transform / look_at before add_child
	_ensure_rally_visuals()
	if _rally_flag == null or _rally_line == null:
		return
	_rally_flag.visible = selected
	_rally_flag.global_position = rally_point
	_rally_line.visible = selected
	# Thin box from building to rally (SC2-like line)
	var a: Vector3 = global_position + Vector3(0, 0.35, 0)
	var bpos: Vector3 = rally_point + Vector3(0, 0.35, 0)
	var mid: Vector3 = (a + bpos) * 0.5
	var dist: float = a.distance_to(bpos)
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.08, maxf(dist, 0.1))
	_rally_line.mesh = box
	_rally_line.global_position = mid
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.95, 0.4, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rally_line.material_override = mat
	if dist > 0.05 and _rally_line.is_inside_tree():
		_rally_line.look_at(bpos, Vector3.UP)

func take_damage(amount: float, _pierce: bool = false) -> void:
	if not alive or not is_complete:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		alive = false
		# Simple ruin: free after brief delay via process flag
		_tower_cd = -1.0
		queue_free()

func _tower_combat(delta: float) -> void:
	if not is_tower or not is_complete or not alive:
		return
	_tower_cd = maxf(_tower_cd - delta, 0.0)
	if _tower_cd > 0.0:
		return
	var e: Node3D = Combat.find_nearest_enemy(self, team, attack_range)
	if e == null:
		return
	# Base attack power 鈫?pierce damage; fly arrow at that single target
	var armor: int = int(e.get("armor_pierce") if e.get("armor_pierce") != null else 0)
	var dmg: float = Combat.pierce_damage(attack_damage, armor)
	_launch_arrow(e, dmg)
	_tower_cd = maxf(attack_interval, 0.5)

func _launch_arrow(target: Node3D, dmg: float) -> void:
	if target == null or ArrowScr == null:
		return
	var arrow = ArrowScr.new()
	var from: Vector3 = global_position + Vector3(0, footprint.y * 0.85 + 1.2, 0)
	var parent_n: Node = get_parent()
	if parent_n == null:
		parent_n = get_tree().current_scene
	parent_n.add_child(arrow)
	arrow.setup(from, target, dmg)

