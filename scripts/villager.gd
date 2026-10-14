extends Node3D
class_name Villager3D
## 3D villager: move / gather / return drop / build.

const Catalog := preload("res://scripts/building_catalog.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const Combat := preload("res://scripts/combat.gd")
const Assets := preload("res://scripts/asset_kit.gd")

enum State { IDLE, MOVE, GATHER, RETURN_DROP, BUILD }

signal deposited(res_key: String, amount: int)

var team: String = "player"
var speed: float = 4.5
var radius: float = 0.45
var selected: bool = false
var hp: float = 50.0
var max_hp: float = 50.0
var armor_melee: int = 0
var armor_pierce: int = 0
var attack_damage: float = 6.0
var unit_type: String = "villager"
var alive: bool = true
var attack_interval: float = 2.0
var attack_range: float = Combat.MELEE_RANGE
var _attack_cd: float = 0.0
var attack_target: Node3D = null
var _corpse_t: float = 0.0
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var state: State = State.IDLE

var move_target: Vector3 = Vector3.ZERO
var gather_target: Node3D = null
var drop_target: Node3D = null
var resume_key: String = ""
var resume_resource: Node3D = null
var build_site: Node3D = null
var order_queue: Array = []  ## Shift-queued orders: {k, p?, n?}

var carry_key: String = ""
var carry_amount: int = 0
var carry_capacity: int = 10  # AoE4 villager
var gather_timer: float = 0.0
var gather_rate: float = 0.55
var gather_chunk: int = 2

var _body: MeshInstance3D
var _select: MeshInstance3D
var _carry_label: Label3D
var _bob_t: float = 0.0
var _sep_smooth: Vector3 = Vector3.ZERO
var _avoid_smooth: Vector3 = Vector3.ZERO
var _wall_side: float = 0.0
var _waypoints: Array = []
var _wp_i: int = 0
var _goal_final: Vector3 = Vector3.ZERO
var _repath_cd: float = 0.0

func setup(pos: Vector3, p_team: String = "player") -> void:
	team = p_team
	position = pos
	add_to_group("villagers")
	add_to_group("player_units" if team == "player" else "enemy_units")
	add_to_group("combatants")
	alive = true
	hp = max_hp
	# Stable tangent side when sliding around buildings (avoids flip-flop buzz)
	_wall_side = 1.0 if (get_instance_id() % 2 == 0) else -1.0
	_build_visual()
	set_selected(false)

func _build_visual() -> void:
	if Assets.attach(self, "villager", Vector3(0.9, 1.7, 0.7)) == null:
		const Kit := preload("res://scripts/mesh_kit.gd")
		Kit.build_toy_villager(self)
	_body = MeshInstance3D.new()
	_body.visible = false
	add_child(_body)

	_select = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.35
	tor.outer_radius = 0.48
	_select.mesh = tor
	_select.position.y = 0.04
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.2, 0.9, 0.3, 0.9)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = -4
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select.material_override = sm
	_select.visible = false
	_select.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_select)

	_carry_label = Label3D.new()
	_carry_label.position = Vector3(0, 1.95, 0)
	_carry_label.font_size = 36
	_carry_label.modulate = Color(1, 0.9, 0.3)
	_carry_label.outline_size = 8
	_carry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_carry_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_carry_label)
	_update_carry_label()

func set_selected(v: bool) -> void:
	selected = v
	if _select:
		_select.visible = v
	_update_hp_bar()

func contains_point_xz(p: Vector3) -> bool:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d <= radius + 0.45

func ray_hit_distance(origin: Vector3, dir: Vector3) -> float:
	## Full-body capsule approx as AABB (~1.7m tall).
	var half := Vector3(0.45, 0.95, 0.45)
	var center := global_position + Vector3(0, half.y, 0)
	var inv := Transform3D(Basis.IDENTITY, center).affine_inverse()
	var local_o := inv * origin
	var local_d := inv.basis * dir
	var aabb := AABB(-half, half * 2.0)
	var hit = aabb.intersects_ray(local_o, local_d)
	if hit == null:
		return -1.0
	var hp3: Vector3 = hit
	return origin.distance_to(center + hp3)


func _ensure_hp_bar() -> void:
	if _hp_root != null:
		return
	_hp_root = Node3D.new()
	_hp_root.position = Vector3(0, 1.85, 0)
	add_child(_hp_root)
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(0.8, 0.09, 0.07)
	bg.mesh = bgm
	var bgmat := StandardMaterial3D.new()
	bgmat.albedo_color = Color(0.1, 0.1, 0.1, 0.85)
	bgmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bgmat
	_hp_root.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.76, 0.07, 0.08)
	_hp_fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.9, 0.3)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = fmat
	_hp_root.add_child(_hp_fill)
	_hp_root.visible = false

func _update_hp_bar() -> void:
	_ensure_hp_bar()
	if _hp_root == null or _hp_fill == null:
		return
	var show: bool = selected or hp < max_hp - 0.05
	_hp_root.visible = show and alive
	if not show:
		return
	var pct: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_fill.scale = Vector3(pct, 1.0, 1.0)
	_hp_fill.position.x = -0.38 * (1.0 - pct)
	var mat: StandardMaterial3D = _hp_fill.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.25, 0.9, 0.3) if pct > 0.35 else Color(0.9, 0.25, 0.2)

func take_damage(amount: float, _pierce: bool = false) -> void:
	if not alive:
		return
	hp = maxf(0.0, hp - amount)
	_update_hp_bar()
	# Defend: acquire attacker if idle/moving without gather/build
	if alive and state != State.BUILD and state != State.GATHER and state != State.RETURN_DROP:
		var e: Node3D = Combat.find_nearest_enemy(self, team, Combat.VILL_ACQUIRE)
		if e != null:
			attack_target = e
	if hp <= 0.0:
		_die_vill()

func _die_vill() -> void:
	alive = false
	attack_target = null
	_corpse_t = Combat.CORPSE_LIFE
	state = State.IDLE
	if _select:
		_select.visible = false
	if _hp_root:
		_hp_root.visible = false
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	remove_from_group("combatants")


func clear_order_queue() -> void:
	order_queue.clear()

func _queue_or_run(order: Dictionary, queued: bool) -> bool:
	## If queued and currently busy, append and return true (deferred).
	## If queued and idle, append then run via advance. Returns true if deferred.
	if queued:
		order_queue.append(order)
		if state != State.IDLE:
			return true
		_advance_order_queue()
		return true
	clear_order_queue()
	return false

func _advance_order_queue() -> void:
	while not order_queue.is_empty():
		var o: Dictionary = order_queue.pop_front()
		var k: String = str(o.get("k", ""))
		if k == "move":
			_exec_move(o.get("p", global_position))
			return
		elif k == "build":
			var site = o.get("n")
			if site != null and is_instance_valid(site) and site.get("is_complete") != true:
				_exec_build(site)
				return
		elif k == "gather":
			var node = o.get("n")
			if node != null and is_instance_valid(node):
				_exec_gather(node)
				return
		elif k == "attack":
			var t = o.get("n")
			if t != null and is_instance_valid(t) and Combat.is_alive(t):
				_exec_attack(t)
				return
		elif k == "attack_move":
			_exec_move(o.get("p", global_position))
			# villager attack-move ≈ move (auto-acquire still works)
			return
	state = State.IDLE

func _finish_order() -> void:
	## Current order done — pull next Shift-queued order or go IDLE.
	if not order_queue.is_empty():
		_advance_order_queue()
	else:
		state = State.IDLE

func _exec_attack(target: Node3D) -> void:
	gather_target = null
	build_site = null
	drop_target = null
	attack_target = target
	_set_move_goal(target.global_position)
	state = State.MOVE

func _exec_move(pos: Vector3) -> void:
	gather_target = null
	drop_target = null
	resume_key = ""
	resume_resource = null
	build_site = null
	attack_target = null
	_set_move_goal(Vector3(pos.x, 0, pos.z))
	state = State.MOVE

func _exec_gather(node: Node3D) -> void:
	gather_target = node
	resume_resource = node
	resume_key = _resource_key_of(node)
	drop_target = null
	build_site = null
	attack_target = null
	_set_move_goal(_gather_stand_pos(node))
	state = State.MOVE

func _exec_build(site: Node3D) -> void:
	build_site = site
	gather_target = null
	drop_target = null
	resume_key = ""
	resume_resource = null
	attack_target = null
	if site.has_method("register_builder"):
		site.call("register_builder", self)
	_set_move_goal(_build_stand_pos(site))
	state = State.MOVE

func command_attack_unit(target: Node3D, queued: bool = false) -> void:
	if not alive or target == null or not Combat.is_hostile(self, target):
		return
	if _queue_or_run({"k": "attack", "n": target}, queued):
		return
	_exec_attack(target)

func _combat_tick(delta: float) -> void:
	if not alive:
		_corpse_t -= delta
		if _corpse_t <= 0.0:
			queue_free()
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if attack_target == null or not Combat.is_alive(attack_target):
		attack_target = null
		return
	if state == State.GATHER or state == State.BUILD or state == State.RETURN_DROP:
		return
	var in_reach: bool = false
	if attack_target.has_method("is_melee_in_range"):
		in_reach = bool(attack_target.call("is_melee_in_range", global_position))
	else:
		in_reach = Combat.xz_dist(self, attack_target) <= attack_range * 1.1
	if not in_reach:
		var stand: Vector3 = attack_target.global_position
		if attack_target.has_method("melee_approach"):
			stand = attack_target.call("melee_approach", global_position)
		elif attack_target.has_method("build_approach"):
			stand = attack_target.call("build_approach", global_position)
		_set_move_goal(stand)
		if state == State.IDLE:
			state = State.MOVE
		return
	# Melee
	if _attack_cd <= 0.0:
		var armor: int = int(attack_target.get("armor_melee") if attack_target.get("armor_melee") != null else 0)
		var dmg: float = Combat.melee_damage(attack_damage, armor)
		if attack_target.has_method("take_damage"):
			attack_target.call("take_damage", dmg, false)
		_attack_cd = attack_interval

func _set_move_goal(goal: Vector3) -> void:
	## Plan A* waypoints around solids; fall back to straight line.
	_goal_final = Vector3(goal.x, 0.0, goal.z)
	_waypoints.clear()
	_wp_i = 0
	var tree: SceneTree = get_tree()
	if tree != null:
		_waypoints = Pathfind.find_path(global_position, _goal_final, tree)
	if _waypoints.is_empty():
		move_target = _goal_final
	else:
		move_target = _waypoints[0]
	_repath_cd = 0.35

func _advance_waypoint() -> void:
	if _waypoints.is_empty():
		move_target = _goal_final
		return
	if _wp_i < _waypoints.size() - 1:
		_wp_i += 1
		move_target = _waypoints[_wp_i]
	else:
		move_target = _goal_final

func command_stop() -> void:
	clear_order_queue()
	gather_target = null
	drop_target = null
	resume_key = ""
	resume_resource = null
	build_site = null
	attack_target = null
	_waypoints.clear()
	_wp_i = 0
	move_target = global_position
	state = State.IDLE

func command_move(pos: Vector3, queued: bool = false) -> void:
	if _queue_or_run({"k": "move", "p": Vector3(pos.x, 0, pos.z)}, queued):
		return
	_exec_move(pos)

func command_gather(node: Node3D, queued: bool = false) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _queue_or_run({"k": "gather", "n": node}, queued):
		return
	_exec_gather(node)

func command_build(site: Node3D, queued: bool = false) -> void:
	## Resume / start construction on unfinished foundation (keeps current %).
	if site == null or not is_instance_valid(site):
		return
	if site.get("is_complete") == true:
		return
	if _queue_or_run({"k": "build", "n": site}, queued):
		return
	_exec_build(site)

func _resource_key_of(node: Node3D) -> String:
	if node.has_method("res_key"):
		return str(node.call("res_key"))
	if "is_meat_source" in node and node.is_meat_source:
		return "meat"
	return "wood"

func _update_carry_label() -> void:
	if carry_amount > 0:
		_carry_label.text = "%s %d" % [carry_key, carry_amount]
	else:
		_carry_label.text = ""

func _process(delta: float) -> void:
	if not alive:
		_combat_tick(delta)
		return
	_combat_tick(delta)
	match state:
		State.IDLE:
			_bob_t = 0.0
			if not order_queue.is_empty():
				_advance_order_queue()
			else:
				_soft_unstack(delta)
		State.MOVE:
			_do_move(delta)
		State.GATHER:
			_do_gather(delta)
		State.RETURN_DROP:
			_do_return(delta)
		State.BUILD:
			_do_build(delta)

func _do_move(delta: float) -> void:
	_repath_cd = maxf(_repath_cd - delta, 0.0)
	# Refresh goal if gather/build stand drifted, but keep planned detour
	if gather_target != null and is_instance_valid(gather_target) and build_site == null:
		var stand_g: Vector3 = _gather_stand_pos(gather_target)
		if _repath_cd <= 0.0 and stand_g.distance_to(_goal_final) > 1.2:
			_set_move_goal(stand_g)
	elif build_site != null and is_instance_valid(build_site):
		if build_site.has_method("register_builder"):
			build_site.call("register_builder", self)
		if build_site.has_method("is_builder_in_range") and bool(build_site.call("is_builder_in_range", global_position)):
			state = State.BUILD
			_waypoints.clear()
			return
		var stand_b: Vector3 = _build_stand_pos(build_site)
		if _repath_cd <= 0.0 and stand_b.distance_to(_goal_final) > 1.2:
			_set_move_goal(stand_b)
	# Advance along waypoints early (don't wait to kiss each node)
	var to_wp := move_target - global_position
	to_wp.y = 0.0
	if not _waypoints.is_empty() and _wp_i < _waypoints.size() - 1 and to_wp.length() < 0.85:
		_advance_waypoint()
		to_wp = move_target - global_position
		to_wp.y = 0.0
	var to := to_wp
	var dist := to.length()
	_bob_t += delta * 10.0
	if _body:
		_body.position.y = 0.82 + absf(sin(_bob_t)) * 0.06
	var arrive: float = 0.7 if build_site != null else 0.45
	# Final arrive only on last goal
	var on_final: bool = _waypoints.is_empty() or _wp_i >= _waypoints.size() - 1
	if on_final and dist < arrive:
		_waypoints.clear()
		if gather_target != null and is_instance_valid(gather_target) and build_site == null:
			state = State.GATHER
			gather_timer = 0.0
		elif build_site != null and is_instance_valid(build_site):
			state = State.BUILD
		else:
			_finish_order()  # arrive → next Shift order or IDLE
		return
	if dist < 0.001:
		_advance_waypoint()
		return
	var step := to.normalized() * speed * delta
	# Path already avoids solids — light steer only as safety net
	step = _steer_around_buildings(step, delta)
	step = step.limit_length(speed * delta * 1.05)
	global_position += step
	global_position.y = 0.0
	if step.length_squared() > 0.00001:
		look_at(global_position + Vector3(step.x, 0, step.z).normalized(), Vector3.UP)

func _steer_around_buildings(step: Vector3, delta: float) -> Vector3:
	## Smooth slide around solids — low-pass avoid vector, stable side, no zero/buzz.
	if step.length_squared() < 0.0000001:
		return step
	var max_step: float = speed * delta * 1.05
	var desired: Vector3 = step
	var in_open_doorway: bool = false
	var next: Vector3 = global_position + desired
	for g in get_tree().get_nodes_in_group("buildings"):
		if g.has_method("gate_passage_clear") and g.gate_passage_clear(next, team, radius):
			in_open_doorway = true
			break
	if not in_open_doorway:
		# Only bias toward an open gate when the MOVE GOAL is near that gate
		# (avoids sucking wall-bound walks through a nearby open doorway).
		var goal_xz: Vector3 = Vector3(_goal_final.x, 0.0, _goal_final.z)
		for g2 in get_tree().get_nodes_in_group("buildings"):
			if g2.has_method("is_open_for") and g2.is_open_for(team):
				var gd: float = Vector2(g2.global_position.x - global_position.x, g2.global_position.z - global_position.z).length()
				var goal_near_gate: float = Vector2(g2.global_position.x - goal_xz.x, g2.global_position.z - goal_xz.z).length()
				if gd < 6.0 and goal_near_gate < 5.0:
					var to_mid: Vector3 = g2.global_position - global_position
					to_mid.y = 0.0
					if desired.dot(to_mid) > 0.0 and to_mid.length_squared() > 0.01:
						var aim: Vector3 = Vector3(g2.global_position.x, 0.0, global_position.z + signf(to_mid.z) * absf(to_mid.z))
						var to_aim: Vector3 = aim - global_position
						to_aim.y = 0.0
						if to_aim.length_squared() > 0.01:
							desired = desired.lerp(to_aim.normalized() * desired.length(), 0.35)
					break
	var avoid: Vector3 = Vector3.ZERO
	var blocked: bool = false
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.get("blocks_path") == false:
			continue
		if not b.has_method("blocks_unit_at"):
			continue
		if not b.blocks_unit_at(next, team, radius):
			# Look-ahead mild nudge if close to surface
			var probe: Vector3 = global_position + desired.normalized() * maxf(radius + 0.55, desired.length() * 1.8)
			if b.blocks_unit_at(probe, team, radius):
				var away0: Vector3 = global_position - b.global_position
				away0.y = 0.0
				if away0.length_squared() < 0.0001:
					away0 = Vector3(1, 0, 0)
				var n0: Vector3 = away0.normalized()
				var side0: Vector3 = Vector3(-n0.z, 0, n0.x) * _wall_side
				avoid += side0 * 0.55 + n0 * 0.15
			continue
		blocked = true
		var away: Vector3 = global_position - b.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1, 0, 0)
		var nrm: Vector3 = away.normalized()
		var side: Vector3 = Vector3(-nrm.z, 0, nrm.x) * _wall_side
		# Prefer tangent slide toward goal if possible
		if desired.dot(side) < 0.0:
			# keep chosen wall side stable — flip only if goal strongly opposite
			if desired.dot(-side) > desired.length() * 0.85:
				side = -side
		avoid += side * 0.9 + nrm * 0.25
		desired = desired.slide(nrm)
	# Resources (non-farm)
	for r in get_tree().get_nodes_in_group("resources"):
		if r.is_in_group("farms") or r.is_in_group("buildings"):
			continue
		if r.has_method("blocks_unit_at") and r.blocks_unit_at(next, radius):
			blocked = true
			var away_r: Vector3 = global_position - r.global_position
			away_r.y = 0.0
			if away_r.length_squared() < 0.0001:
				away_r = Vector3(1, 0, 0)
			var nr: Vector3 = away_r.normalized()
			var sr: Vector3 = Vector3(-nr.z, 0, nr.x) * _wall_side
			avoid += sr * 0.85 + nr * 0.3
			desired = desired.slide(nr)
	# Low-pass avoid so direction doesn't flip every frame
	var avoid_n: Vector3 = avoid.limit_length(1.0)
	_avoid_smooth = _avoid_smooth.lerp(avoid_n, clampf(delta * 6.0, 0.0, 1.0))
	if _avoid_smooth.length_squared() > 0.0001:
		desired = (desired + _avoid_smooth * speed * delta * 0.55).limit_length(max_step)
	else:
		_avoid_smooth *= 0.9
	# Resolve: slide around solids; never accept a step that enters a solid
	# (open gate doorway already returns false from blocks_unit_at).
	next = global_position + desired
	for b2 in get_tree().get_nodes_in_group("buildings"):
		if b2.get("blocks_path") == false:
			continue
		if b2.has_method("blocks_unit_at") and b2.blocks_unit_at(next, team, radius):
			var away2: Vector3 = global_position - b2.global_position
			away2.y = 0.0
			if away2.length_squared() < 0.0001:
				away2 = Vector3(1, 0, 0)
			var n2: Vector3 = away2.normalized()
			var slid: Vector3 = desired.slide(n2)
			if slid.length_squared() < 0.00001:
				slid = Vector3(-n2.z, 0, n2.x) * _wall_side * speed * delta * 0.65
			var trial: Vector3 = global_position + slid
			if b2.blocks_unit_at(trial, team, radius):
				# Egress only — do not tunnel through wall body
				desired = n2 * speed * delta * 0.45
			else:
				desired = slid.limit_length(max_step)
			break
	# Final hard reject against any solid
	var end_pos: Vector3 = global_position + desired
	for b3 in get_tree().get_nodes_in_group("buildings"):
		if b3.get("blocks_path") == false:
			continue
		if b3.has_method("blocks_unit_at") and b3.blocks_unit_at(end_pos, team, radius):
			var away3: Vector3 = global_position - b3.global_position
			away3.y = 0.0
			if away3.length_squared() < 0.0001:
				away3 = Vector3(1, 0, 0)
			desired = away3.normalized() * speed * delta * 0.4
			break
	return desired

func _do_gather(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		_try_resume_or_idle()
		return
	# Arid / empty farm — stop
	if gather_target.get("is_arid") == true or (gather_target.has_method("res_key") and str(gather_target.call("res_key")) == ""):
		gather_target = null
		_try_resume_or_idle()
		return
	var stand: Vector3 = _gather_stand_pos(gather_target)
	var d := Vector2(stand.x - global_position.x, stand.z - global_position.z).length()
	# Also allow if close to node surface
	var d_center := Vector2(gather_target.global_position.x - global_position.x,
		gather_target.global_position.z - global_position.z).length()
	var reach: float = 0.7
	if gather_target.is_in_group("farms"):
		reach = 1.6
	elif gather_target.has_method("gather_approach"):
		reach = 0.65
	if d > reach and d_center > (2.4 if gather_target.is_in_group("farms") else 1.8):
		move_target = stand
		state = State.MOVE
		return
	# Gather bob
	_bob_t += delta * 8.0
	if _body:
		_body.rotation.x = sin(_bob_t) * 0.25
	gather_timer += delta
	if gather_timer >= gather_rate:
		gather_timer = 0.0
		var key: String = _resource_key_of(gather_target)
		var room := carry_capacity - carry_amount
		if room <= 0 or (carry_key != "" and carry_key != key):
			_start_return()
			return
		var took: int = 0
		if gather_target.has_method("harvest"):
			took = int(gather_target.call("harvest", mini(gather_chunk, room)))
		elif gather_target.has_method("harvest_meat"):
			took = int(gather_target.call("harvest_meat", mini(gather_chunk, room)))
		if took > 0:
			carry_key = key
			carry_amount += took
			_update_carry_label()
		if carry_amount >= carry_capacity or took == 0:
			_start_return()

func _start_return() -> void:
	drop_target = _find_dropoff(carry_key)
	if drop_target == null:
		state = State.IDLE
		return
	_set_move_goal(_dropoff_approach(drop_target))
	state = State.RETURN_DROP
	if _body:
		_body.rotation.x = 0

func _do_return(delta: float) -> void:
	_repath_cd = maxf(_repath_cd - delta, 0.0)
	if drop_target == null or not is_instance_valid(drop_target):
		drop_target = _find_dropoff(carry_key)
		if drop_target == null:
			state = State.IDLE
			return
		_set_move_goal(_dropoff_approach(drop_target))
	var stand: Vector3 = _dropoff_approach(drop_target)
	if _repath_cd <= 0.0 and stand.distance_to(_goal_final) > 1.0:
		_set_move_goal(stand)
	var to := move_target - global_position
	to.y = 0
	if not _waypoints.is_empty() and _wp_i < _waypoints.size() - 1 and to.length() < 0.85:
		_advance_waypoint()
		to = move_target - global_position
		to.y = 0
	var dist := to.length()
	_bob_t += delta * 10.0
	if _body:
		_body.position.y = 0.55 + absf(sin(_bob_t)) * 0.06
	var deposit_r: float = _dropoff_radius(drop_target)
	var on_final: bool = _waypoints.is_empty() or _wp_i >= _waypoints.size() - 1
	if on_final and dist < deposit_r:
		_waypoints.clear()
		deposited.emit(carry_key, carry_amount)
		carry_amount = 0
		carry_key = ""
		_update_carry_label()
		if resume_resource != null and is_instance_valid(resume_resource):
			command_gather(resume_resource)
		elif resume_key != "":
			var n: Node3D = _find_nearest_resource(resume_key)
			if n:
				command_gather(n)
			else:
				state = State.IDLE
		else:
			state = State.IDLE
		return
	if dist < 0.001:
		return
	var step := to.normalized() * speed * delta
	step = _steer_around_buildings(step, delta)
	var escape: Vector3 = _escape_buildings()
	if escape.length_squared() > 0.0001:
		step = escape * speed * delta
	global_position += step
	global_position.y = 0.0

func _dropoff_radius(_b: Node3D) -> float:
	## Tight hug — only deposit when nearly at approach point.
	return 0.55

func _dropoff_approach(b: Node3D) -> Vector3:
	## Stand hugging the outside of the Town Center footprint.
	var center: Vector3 = b.global_position
	var fp = b.get("footprint")
	var hx: float = 2.2
	var hz: float = 2.2
	if fp != null:
		hx = float(fp.x) * 0.5 + 0.45
		hz = float(fp.z) * 0.5 + 0.45
	var dx: float = global_position.x - center.x
	var dz: float = global_position.z - center.z
	if absf(dx) < 0.01 and absf(dz) < 0.01:
		dx = 1.0
	# Clamp to nearest point on expanded AABB ring (outside)
	var ax: float = clampf(dx, -hx, hx)
	var az: float = clampf(dz, -hz, hz)
	# If inside box, push to nearest edge
	if absf(dx) <= hx and absf(dz) <= hz:
		var sx: float = 1.0 if absf(dx) <= 0.01 else signf(dx)
		var sz: float = 1.0 if absf(dz) <= 0.01 else signf(dz)
		if hx - absf(dx) < hz - absf(dz):
			ax = hx * sx
			az = clampf(dz, -hz, hz)
		else:
			az = hz * sz
			ax = clampf(dx, -hx, hx)
	else:
		# Outside: approach nearest point on expanded rect
		ax = clampf(dx, -hx, hx)
		az = clampf(dz, -hz, hz)
	return Vector3(center.x + ax, 0.0, center.z + az)

func _escape_buildings() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.has_method("blocks_unit_at") and b.blocks_unit_at(global_position, team, radius):
			var away: Vector3 = global_position - b.global_position
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = Vector3(1, 0, 0)
			push += away.normalized()
	return push.normalized() if push.length_squared() > 0.0001 else Vector3.ZERO

func _separation_push(min_dist: float) -> Vector3:
	## Proportional spring (not unit-normalized) — stops high-frequency jitter.
	var push: Vector3 = Vector3.ZERO
	for u in get_tree().get_nodes_in_group("player_units"):
		if u == self or not is_instance_valid(u):
			continue
		var dvec: Vector3 = global_position - u.global_position
		dvec.y = 0.0
		var d: float = dvec.length()
		if d < 0.001:
			var ang: float = float(get_instance_id() % 360) * 0.0174533
			push += Vector3(cos(ang), 0, sin(ang)) * 0.35
		elif d < min_dist:
			var t: float = (min_dist - d) / min_dist
			push += dvec.normalized() * (t * t)  # soft falloff
	return push.limit_length(1.0)

func _soft_unstack(delta: float) -> void:
	## Idle-only spread after arrive — stronger settle, still low-pass damped.
	var raw: Vector3 = _separation_push(1.45)
	_sep_smooth = _sep_smooth.lerp(raw, clampf(delta * 9.0, 0.0, 1.0))
	var bout: Vector3 = _building_escape_dir()
	var blended: Vector3 = _sep_smooth * 0.7 + bout * 0.7
	if blended.length_squared() < 0.00005:
		_sep_smooth *= 0.85
		return
	var step: Vector3 = blended.limit_length(1.0) * speed * 0.48 * delta
	global_position += step
	global_position.y = 0.0
	_escape_building_overlap(delta)

func _building_escape_dir() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		# Skip non-blocking (farms)
		if b.get("blocks_path") == false:
			continue
		if b.has_method("blocks_unit_at") and b.blocks_unit_at(global_position, team, radius):
			var away: Vector3 = global_position - b.global_position
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = Vector3(1, 0, 0)
			push += away.normalized()
	return push.limit_length(1.0)

func _escape_building_overlap(delta: float) -> void:
	## If clipped into a solid, nudge out smoothly (no oscillation).
	var dir: Vector3 = _building_escape_dir()
	if dir.length_squared() < 0.0001:
		return
	global_position += dir * speed * 0.55 * delta
	global_position.y = 0.0

func _build_stand_pos(site: Node3D) -> Vector3:
	## Nearest point on the perimeter ring from CURRENT position (any side).
	if site == null or not is_instance_valid(site):
		return global_position
	if site.has_method("build_approach"):
		return site.call("build_approach", global_position)
	return site.global_position

func _do_build(delta: float) -> void:
	if build_site == null or not is_instance_valid(build_site):
		_finish_order()
		return
	if build_site.has_method("register_builder"):
		build_site.call("register_builder", self)
	if build_site.get("is_complete") == true:
		_on_build_finished(build_site)
		return
	_escape_building_overlap(delta)
	var in_range: bool = true
	if build_site.has_method("is_builder_in_range"):
		in_range = bool(build_site.call("is_builder_in_range", global_position))
	# If clipped inside solid footprint, step to nearest exterior ring point
	if build_site.get("blocks_path") != false and build_site.has_method("blocks_unit_at"):
		if bool(build_site.call("blocks_unit_at", global_position, team, radius)):
			var stand_out: Vector3 = _build_stand_pos(build_site)
			var out: Vector3 = stand_out - global_position
			out.y = 0.0
			if out.length_squared() > 0.0001:
				global_position += out.normalized() * speed * 0.6 * delta
				global_position.y = 0.0
	if in_range and build_site.has_method("add_build_progress"):
		# Stay where we are on the perimeter — do NOT chase a fixed slot
		var sep: Vector3 = _separation_push(1.05)
		_sep_smooth = _sep_smooth.lerp(sep, clampf(delta * 6.0, 0.0, 1.0))
		global_position += _sep_smooth * speed * 0.10 * delta
		global_position.y = 0.0
		build_site.call("add_build_progress", delta, self)
		if build_site.get("is_complete") == true:
			_on_build_finished(build_site)
			return
		_bob_t += delta * 6.0
		if _body:
			_body.rotation.x = sin(_bob_t) * 0.3
		var face: Vector3 = build_site.global_position - global_position
		face.y = 0.0
		if face.length_squared() > 0.01:
			look_at(global_position + face.normalized(), Vector3.UP)
	elif not in_range:
		# Too far: walk to nearest perimeter point from current angle
		state = State.MOVE
		move_target = _build_stand_pos(build_site)
	else:
		state = State.IDLE

func _on_build_finished(site: Node3D) -> void:
	## Foundation done. If farm and no queued orders → auto gather that farm.
	var farm: Node3D = site
	build_site = null
	var is_farm: bool = false
	if farm != null and is_instance_valid(farm):
		is_farm = farm.is_in_group("farms") or int(farm.get("kind")) == Catalog.FARM
	if is_farm and order_queue.is_empty() and is_instance_valid(farm):
		command_gather(farm)
		return
	_finish_order()

func _try_resume_or_idle() -> void:
	if resume_key != "":
		var n: Node3D = _find_nearest_resource(resume_key)
		if n:
			command_gather(n)
			return
	_finish_order()
	if _body:
		_body.rotation.x = 0

func _find_dropoff(_key: String) -> Node3D:
	## All deposits go to Town Center / command center only.
	var best_tc: Node3D = null
	var best_d: float = 1e9
	for b in get_tree().get_nodes_in_group("buildings"):
		if int(b.get("kind")) != Catalog.TOWN_CENTER:
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best_tc = b
	return best_tc

func _gather_stand_pos(node: Node3D) -> Vector3:
	if node == null or not is_instance_valid(node):
		return global_position
	if node.has_method("gather_approach"):
		return node.call("gather_approach", global_position)
	return node.global_position

func _find_nearest_resource(key: String) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1e9
	for r in get_tree().get_nodes_in_group("resources"):
		var rk := ""
		if r.has_method("res_key"):
			rk = str(r.call("res_key"))
		if rk == key:
			var d := global_position.distance_to(r.global_position)
			if d < best_d:
				best_d = d
				best = r
	return best
