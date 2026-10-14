extends Node3D
class_name Soldier3D
const Pathfind := preload("res://scripts/pathfind.gd")
const Combat := preload("res://scripts/combat.gd")
const Assets := preload("res://scripts/asset_kit.gd")
## Spearman-ish melee unit (AoE4-ish: atk7 HP80 0/0 ROF~1.875s).

enum State { IDLE, MOVE, ATTACK_MOVE, ATTACK, DEAD }

var team: String = "player"
var speed: float = 5.2
var radius: float = 0.4
var selected: bool = false
var hp: float = 80.0
var max_hp: float = 80.0
var armor_melee: int = 0
var armor_pierce: int = 0
var attack_damage: float = 7.0
var attack_interval: float = 1.875
var attack_range: float = Combat.MELEE_RANGE
var acquire_range: float = Combat.ACQUIRE_RANGE
var unit_type: String = "soldier"
var is_zombie: bool = false  ## horde seeker (They Are Billions-style)
var _base_speed: float = 5.2
var _base_attack_damage: float = 7.0
var _base_attack_interval: float = 1.875
var _base_attack_range: float = Combat.MELEE_RANGE
var _base_acquire_range: float = Combat.ACQUIRE_RANGE
var _base_armor_melee: int = 0
var _base_armor_pierce: int = 0
var _night_buffed: bool = false
var alive: bool = true

var state: State = State.IDLE
var move_target: Vector3 = Vector3.ZERO
var attack_target: Node3D = null
var _attack_cd: float = 0.0
var _corpse_t: float = 0.0
var _sep_smooth: Vector3 = Vector3.ZERO
var _wall_side: float = 1.0
var _waypoints: Array = []
var _wp_i: int = 0
var _goal_final: Vector3 = Vector3.ZERO
var _body: MeshInstance3D
var _select: MeshInstance3D
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _enemy_flash_t: float = 0.0
var order_queue: Array = []  ## Shift-queued orders
var _repath_cd: float = 0.0

func apply_day_night(night: bool) -> void:
	## Night: all combat stats ×2 except HP. Day: restore base.
	if not is_zombie or not alive:
		return
	if night == _night_buffed:
		return
	_night_buffed = night
	var m: float = 2.0 if night else 1.0
	speed = _base_speed * m
	attack_damage = _base_attack_damage * m
	# Rate ×2 → interval halves
	attack_interval = _base_attack_interval / m
	attack_range = _base_attack_range * m
	acquire_range = _base_acquire_range  # keep map-wide seek
	armor_melee = int(round(float(_base_armor_melee) * m))
	armor_pierce = int(round(float(_base_armor_pierce) * m))
	# HP untouched

func display_name() -> String:
	if is_zombie:
		return "丧尸"
	return "矛兵"

func setup(pos: Vector3, p_team: String = "player", as_zombie: bool = false) -> void:
	is_zombie = as_zombie
	team = "enemy" if as_zombie else p_team
	position = pos
	alive = true
	if is_zombie:
		unit_type = "zombie"
		max_hp = 48.0
		hp = max_hp
		_base_speed = 3.35
		_base_attack_damage = 6.0
		_base_attack_interval = 1.55
		_base_attack_range = Combat.MELEE_RANGE
		_base_acquire_range = 220.0
		_base_armor_melee = 0
		_base_armor_pierce = 0
		speed = _base_speed
		attack_damage = _base_attack_damage
		attack_interval = _base_attack_interval
		attack_range = _base_attack_range
		acquire_range = _base_acquire_range
		armor_melee = _base_armor_melee
		armor_pierce = _base_armor_pierce
		_night_buffed = false
	else:
		hp = max_hp
		_base_speed = speed
		_base_attack_damage = attack_damage
		_base_attack_interval = attack_interval
	add_to_group("soldiers")
	add_to_group("military")
	add_to_group("combatants")
	add_to_group("player_units" if team == "player" else "enemy_units")
	if is_zombie:
		add_to_group("zombies")
	_wall_side = 1.0 if (get_instance_id() % 2 == 0) else -1.0
	_build_visual()
	set_selected(false)
	_update_hp_bar()

func _build_visual() -> void:
	var key := "zombie" if is_zombie else ("enemy" if team == "enemy" else "soldier")
	if Assets.attach(self, key, Vector3(0.95, 1.7, 0.95)) == null:
		const Kit := preload("res://scripts/mesh_kit.gd")
		Kit.build_toy_soldier(self, team, is_zombie)
	_body = MeshInstance3D.new()
	_body.visible = false
	var mat := StandardMaterial3D.new()
	if is_zombie:
		mat.albedo_color = Color(0.45, 0.75, 0.38)
	elif team == "enemy":
		mat.albedo_color = Color(1.0, 0.28, 0.90)
	else:
		mat.albedo_color = Color(0.90, 0.28, 0.22)
	_body.material_override = mat
	add_child(_body)
	_select = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.55
	tor.outer_radius = 0.85 if team == "enemy" else 0.72
	tor.rings = 6
	tor.ring_segments = 20
	_select.mesh = tor
	_select.position.y = 0.04
	var sm := StandardMaterial3D.new()
	if is_zombie:
		sm.albedo_color = Color(0.4, 0.9, 0.25, 0.9)
	elif team == "enemy":
		sm.albedo_color = Color(1.0, 0.2, 0.95, 0.95)
	else:
		sm.albedo_color = Color(0.2, 1.0, 0.35, 0.9)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = -4
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select.material_override = sm
	_select.visible = (team == "enemy")
	_select.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_select)
	if team == "enemy":
		var tag := Label3D.new()
		tag.text = "尸" if is_zombie else "敌"
		tag.font_size = 48
		tag.pixel_size = 0.018
		tag.position = Vector3(0, 2.35, 0)
		tag.modulate = Color(0.55, 1.0, 0.35) if is_zombie else Color(1.0, 0.95, 0.2)
		tag.outline_modulate = Color(0.1, 0.25, 0.05) if is_zombie else Color(0.4, 0, 0.3)
		tag.outline_size = 8
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		add_child(tag)
		# Brief flash disc
		var flash := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.4
		disc.bottom_radius = 1.4
		disc.height = 0.05
		disc.radial_segments = 20
		flash.mesh = disc
		flash.position.y = 0.08
		var fm := StandardMaterial3D.new()
		if is_zombie:
			fm.albedo_color = Color(0.4, 0.95, 0.25, 0.5)
			fm.emission = Color(0.25, 0.8, 0.15)
		else:
			fm.albedo_color = Color(1.0, 0.3, 1.0, 0.55)
			fm.emission = Color(1.0, 0.2, 0.9)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		fm.render_priority = -3
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.emission_enabled = true
		fm.emission_energy_multiplier = 2.0
		flash.material_override = fm
		flash.name = "EnemyFlash"
		add_child(flash)
	_hp_root = Node3D.new()
	_hp_root.position = Vector3(0, 2.05, 0)
	add_child(_hp_root)
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(0.9, 0.1, 0.08)
	bg.mesh = bgm
	var bgmat := StandardMaterial3D.new()
	bgmat.albedo_color = Color(0.1, 0.1, 0.1, 0.85)
	bgmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bgmat
	_hp_root.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.86, 0.08, 0.09)
	_hp_fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.9, 0.3)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = fmat
	_hp_root.add_child(_hp_fill)
	_hp_root.visible = false

func set_selected(v: bool) -> void:
	selected = v
	if _select:
		_select.visible = v or team == "enemy"
	_update_hp_bar()

func _update_hp_bar() -> void:
	if _hp_root == null or _hp_fill == null:
		return
	var show: bool = selected or hp < max_hp - 0.05
	_hp_root.visible = show and alive
	if not show:
		return
	var pct: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_fill.scale = Vector3(pct, 1.0, 1.0)
	_hp_fill.position.x = -0.43 * (1.0 - pct)
	var mat: StandardMaterial3D = _hp_fill.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.25, 0.9, 0.3) if pct > 0.35 else Color(0.9, 0.25, 0.2)

func contains_point_xz(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < 1.0

func ray_hit_distance(origin: Vector3, dir: Vector3) -> float:
	var center := global_position + Vector3(0, 0.7, 0)
	var half := Vector3(0.45, 0.9, 0.4)
	var inv := global_transform.affine_inverse()
	var local_o := inv * origin
	var local_d := inv.basis * dir
	var aabb := AABB(-half, half * 2.0)
	var hit = aabb.intersects_ray(local_o, local_d)
	if hit == null:
		return -1.0
	return origin.distance_to(center + Vector3(hit))


func clear_order_queue() -> void:
	order_queue.clear()

func _queue_or_run(order: Dictionary, queued: bool) -> bool:
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
			attack_target = null
			_set_move_goal(o.get("p", global_position))
			state = State.MOVE
			return
		elif k == "attack_move":
			attack_target = null
			_set_move_goal(o.get("p", global_position))
			state = State.ATTACK_MOVE
			return
		elif k == "attack":
			var t = o.get("n")
			if t != null and is_instance_valid(t) and Combat.is_alive(t) and Combat.is_hostile(self, t):
				attack_target = t
				state = State.ATTACK
				return
	state = State.IDLE

func _finish_order() -> void:
	if not order_queue.is_empty():
		_advance_order_queue()
	else:
		state = State.IDLE

func command_stop() -> void:
	if not alive or team == "enemy":
		return
	clear_order_queue()
	attack_target = null
	_waypoints.clear()
	_wp_i = 0
	move_target = global_position
	state = State.IDLE

func _set_move_goal(goal: Vector3, force: bool = false) -> void:
	## force=false: throttle A* (zombies were repathing every frame → AppHang).
	var g: Vector3 = Vector3(goal.x, 0.0, goal.z)
	var moved: float = g.distance_to(_goal_final)
	if not force and _repath_cd > 0.0 and moved < 2.5 and not _waypoints.is_empty():
		_goal_final = g
		return
	_goal_final = g
	_waypoints.clear()
	_wp_i = 0
	var tree: SceneTree = get_tree()
	if tree != null:
		# Always A* — straight chase stuck zombies on trees/stone/gold.
		# Repath throttle above prevents AppHang.
		_waypoints = Pathfind.find_path(global_position, _goal_final, tree)
	if _waypoints.is_empty():
		move_target = _goal_final
	else:
		move_target = _waypoints[0]
	_repath_cd = 0.85 if is_zombie else 0.35

func command_move(pos: Vector3, queued: bool = false) -> void:
	if not alive or team == "enemy":
		return
	if _queue_or_run({"k": "move", "p": Vector3(pos.x, 0, pos.z)}, queued):
		return
	attack_target = null
	_set_move_goal(Vector3(pos.x, 0, pos.z))
	state = State.MOVE

func command_attack_move(pos: Vector3, queued: bool = false) -> void:
	if not alive or team == "enemy":
		return
	if _queue_or_run({"k": "attack_move", "p": Vector3(pos.x, 0, pos.z)}, queued):
		return
	attack_target = null
	_set_move_goal(Vector3(pos.x, 0, pos.z))
	state = State.ATTACK_MOVE

func command_attack_unit(target: Node3D, queued: bool = false) -> void:
	## Player order only — enemy AI uses _try_acquire / _do_attack.
	if not alive or team == "enemy":
		return
	if target == null or not Combat.is_alive(target):
		return
	if not Combat.is_hostile(self, target):
		return
	if _queue_or_run({"k": "attack", "n": target}, queued):
		return
	attack_target = target
	state = State.ATTACK

func take_damage(amount: float, _pierce: bool = false) -> void:
	if not alive:
		return
	hp = maxf(0.0, hp - amount)
	_update_hp_bar()
	if hp <= 0.0:
		_die()

func _die() -> void:
	alive = false
	state = State.DEAD
	attack_target = null
	_corpse_t = Combat.CORPSE_LIFE
	if _select:
		_select.visible = false
	if _hp_root:
		_hp_root.visible = false
	if _body:
		var mat: StandardMaterial3D = _body.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = mat.albedo_color.darkened(0.45)
	# Leave groups so they are no longer selectable / targeted
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	remove_from_group("military")
	remove_from_group("combatants")
	if is_zombie:
		remove_from_group("zombies")

func _process(delta: float) -> void:
	if team == "enemy" and alive:
		_enemy_flash_t += delta
		var fl: Node = get_node_or_null("EnemyFlash")
		if fl is MeshInstance3D:
			if _enemy_flash_t < 4.0:
				var pulse: float = 0.55 + 0.35 * sin(_enemy_flash_t * 8.0)
				fl.scale = Vector3(pulse, 1.0, pulse)
				fl.visible = true
			else:
				fl.visible = false
	if state == State.DEAD:
		_corpse_t -= delta
		if _corpse_t <= 0.0:
			queue_free()
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_repath_cd = maxf(_repath_cd - delta, 0.0)
	match state:
		State.IDLE:
			if not order_queue.is_empty():
				_advance_order_queue()
			else:
				_soft_unstack(delta)
				_try_acquire()
		State.MOVE:
			_do_move(delta, false)
		State.ATTACK_MOVE:
			_try_acquire()
			if state == State.ATTACK:
				return
			_do_move(delta, true)
		State.ATTACK:
			_do_attack(delta)

func _try_acquire() -> void:
	var reach: float = acquire_range
	if is_zombie:
		reach = maxf(reach, 220.0)
	if attack_target != null and is_instance_valid(attack_target) and Combat.is_alive(attack_target) and Combat.is_hostile(self, attack_target):
		# Horde: keep chasing even if far; patrol foes still need in-range flip to ATTACK
		if is_zombie or Combat.xz_dist(self, attack_target) <= reach:
			state = State.ATTACK
			return
	elif attack_target != null and not is_instance_valid(attack_target):
		attack_target = null
	var e: Node3D = Combat.find_nearest_enemy(self, team, reach)
	if e != null and is_instance_valid(e):
		attack_target = e
		state = State.ATTACK

func _attack_stand_pos(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position
	if target.has_method("melee_approach"):
		return target.call("melee_approach", global_position)
	if target.has_method("build_approach"):
		return target.call("build_approach", global_position)
	return target.global_position

func _in_melee_reach(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_melee_in_range"):
		return target.call("is_melee_in_range", global_position) == true
	return Combat.xz_dist(self, target) <= attack_range * 1.05

func _do_attack(delta: float) -> void:
	_repath_cd = maxf(_repath_cd - delta, 0.0)
	if attack_target == null or not is_instance_valid(attack_target) or not Combat.is_alive(attack_target) or not Combat.is_hostile(self, attack_target):
		attack_target = null
		_finish_order()
		return
	# Buildings: stand on perimeter ring (like gather/build) — never path into solid
	if not _in_melee_reach(attack_target):
		var chase: Vector3 = _attack_stand_pos(attack_target)
		_set_move_goal(chase, false)  # throttled A*
		_do_move(delta, false)
		if state == State.MOVE or state == State.IDLE:
			state = State.ATTACK
		return
	# In range — face and swing
	if not is_instance_valid(attack_target) or not attack_target.is_inside_tree():
		attack_target = null
		_finish_order()
		return
	var face: Vector3 = attack_target.global_position - global_position
	face.y = 0.0
	if face.length_squared() > 0.0001 and is_inside_tree():
		look_at(global_position + face.normalized(), Vector3.UP)
	if _attack_cd <= 0.0:
		var armor: int = int(attack_target.get("armor_melee") if attack_target.get("armor_melee") != null else 0)
		var dmg: float = Combat.melee_damage(attack_damage, armor)
		if is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
			attack_target.call("take_damage", dmg, false)
		_attack_cd = attack_interval
		if _body:
			_body.position.z = -0.12
	else:
		if _body and _body.position.z < -0.01:
			_body.position.z = lerpf(_body.position.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))

func _do_move(delta: float, _atk_move: bool) -> void:
	var to := move_target - global_position
	to.y = 0.0
	if not _waypoints.is_empty() and _wp_i < _waypoints.size() - 1 and to.length() < 0.85:
		_wp_i += 1
		move_target = _waypoints[_wp_i]
		to = move_target - global_position
		to.y = 0.0
	var on_final: bool = _waypoints.is_empty() or _wp_i >= _waypoints.size() - 1
	if on_final and to.length() < 0.45:
		_waypoints.clear()
		if state == State.ATTACK_MOVE or state == State.MOVE:
			_finish_order()
		return
	if to.length() < 0.001:
		return
	var step: Vector3 = to.normalized() * speed * delta
	step = _steer_around_buildings(step, delta)
	step = step.limit_length(speed * delta * 1.1)
	global_position += step
	global_position.y = 0.0
	if step.length_squared() > 0.00001:
		look_at(global_position + Vector3(step.x, 0, step.z).normalized(), Vector3.UP)

func _steer_solid_blocks(pos: Vector3) -> bool:
	## Buildings + map resources (trees/stone/gold) — zombies must not tunnel through.
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.get("blocks_path") == false:
			continue
		if b.has_method("blocks_unit_at") and b.blocks_unit_at(pos, team, 0.4):
			return true
	for r in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(r):
			continue
		if r.is_in_group("buildings") or r.is_in_group("farms"):
			continue
		if r.has_method("blocks_unit_at") and r.blocks_unit_at(pos, 0.4):
			return true
	return false

func _steer_around_buildings(step: Vector3, delta: float) -> Vector3:
	if step.length_squared() < 0.0000001:
		return step
	var next: Vector3 = global_position + step
	var max_step: float = speed * delta * 1.1
	var out: Vector3 = step
	var hit: Node3D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.get("blocks_path") == false:
			continue
		if b.has_method("blocks_unit_at") and b.blocks_unit_at(next, team, 0.4):
			hit = b
			break
	if hit == null:
		for r in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(r) or r.is_in_group("buildings") or r.is_in_group("farms"):
				continue
			if r.has_method("blocks_unit_at") and r.blocks_unit_at(next, 0.4):
				hit = r
				break
	if hit != null:
		var away: Vector3 = global_position - hit.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1, 0, 0)
		var nrm: Vector3 = away.normalized()
		var side: Vector3 = Vector3(-nrm.z, 0, nrm.x) * _wall_side
		var slid: Vector3 = step.slide(nrm) + side * speed * delta * 0.4
		if slid.length_squared() < 0.00001:
			slid = side * speed * delta * 0.7
		var trial: Vector3 = global_position + slid
		if _steer_solid_blocks(trial):
			out = nrm * speed * delta * 0.45
		else:
			out = slid.limit_length(max_step)
	var end_pos: Vector3 = global_position + out
	if _steer_solid_blocks(end_pos):
		var away2: Vector3 = global_position - (hit.global_position if hit != null else end_pos)
		away2.y = 0.0
		if away2.length_squared() < 0.0001:
			away2 = Vector3(1, 0, 0)
		return away2.normalized() * speed * delta * 0.4
	return out

func _separation_push(min_dist: float) -> Vector3:
	var push: Vector3 = Vector3.ZERO
	var grp: String = "player_units" if team == "player" else "enemy_units"
	for u in get_tree().get_nodes_in_group(grp):
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
			push += dvec.normalized() * (t * t)
	return push.limit_length(1.0)

func _soft_unstack(delta: float) -> void:
	var raw: Vector3 = _separation_push(1.45)
	_sep_smooth = _sep_smooth.lerp(raw, clampf(delta * 9.0, 0.0, 1.0))
	if _sep_smooth.length_squared() < 0.00005:
		_sep_smooth *= 0.85
		return
	global_position += _sep_smooth.limit_length(1.0) * speed * 0.48 * delta
	global_position.y = 0.0
