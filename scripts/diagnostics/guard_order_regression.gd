extends SceneTree

const Soldier := preload("res://scripts/soldier.gd")
const ResourceNode := preload("res://scripts/resource_node.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const REPORT := "res://verification/guard_order_regression.json"
const MAX_RETRIES_FOR_REPORT: int = 4

class PassiveTarget extends Node3D:
	var team: String = "enemy"
	var alive: bool = true
	var hp: float = 80.0
	var armor_melee: int = 0

	func configure(pos: Vector3, health: float = 80.0) -> void:
		global_position = pos
		hp = health
		add_to_group("enemy_units")
		add_to_group("combatants")

	func take_damage(amount: float, _pierce: bool = false) -> void:
		hp = maxf(0.0, hp - amount)
		if hp <= 0.0:
			alive = false
			remove_from_group("enemy_units")

class TestMain extends Node:
	var world: Node3D
	var _match_started: bool = true
	var _world_teardown_in_progress: bool = false

class TestBarrier extends Node3D:
	var block_radius: float = 48.0
	var blocks_path: bool = true
	var wall_z: float = -20.0

	func blocks_unit_at(pos: Vector3, _radius: float = 0.4) -> bool:
		return absf(pos.z - wall_z) < 1.5 and absf(pos.x) <= 55.0


var fixture_root: Node3D
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var test_main: TestMain

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	fixture_root = Node3D.new()
	fixture_root.name = "GuardRegressionFixture"
	test_main = TestMain.new()
	test_main.name = "main_game"
	test_main.world = fixture_root
	get_root().add_child(test_main)
	test_main.add_to_group("main_game")
	test_main.add_child(fixture_root)
	var defender := _soldier("Defender", Vector3.ZERO, "player", false)
	var enemy := _passive_target("NearbyEnemy", Vector3(4.8, 0, 0), 14.0)
	defender.command_guard(Vector3.ZERO)
	defender.order_completed.connect(func(kind, pos, goal, frame): events.append({"kind": kind, "frame": frame, "position": _vec(pos), "goal": _vec(goal)}))
	var enemy_was_killed := false
	var max_deviation := 0.0
	var max_departure := 0.0
	var acquired_recorded := false
	var killed_recorded := false
	for i in range(900):
		await process_frame
		if not acquired_recorded and defender.attack_target == enemy:
			events.append({"event": "nearby_enemy_acquired", "frame": Engine.get_process_frames(), "anchor": _vec(defender.guard_anchor), "position": _vec(defender.global_position)})
			acquired_recorded = true
		if is_instance_valid(defender):
			max_deviation = maxf(max_deviation, _dist(defender.global_position, defender.guard_anchor))
			max_departure = maxf(max_departure, _dist(defender.global_position, defender.guard_anchor))
		if not is_instance_valid(enemy) or not enemy.alive:
			enemy_was_killed = true
			if not killed_recorded:
				events.append({"event": "target_killed", "frame": Engine.get_process_frames(), "anchor": _vec(defender.guard_anchor), "position": _vec(defender.global_position)})
				killed_recorded = true
		if enemy_was_killed and _dist(defender.global_position, Vector3.ZERO) <= 0.5:
			events.append({"event": "returned_to_anchor", "frame": Engine.get_process_frames(), "anchor": _vec(defender.guard_anchor), "position": _vec(defender.global_position)})
			break
	var kill_return := {"enemy_killed": enemy_was_killed, "anchor": [0.0, 0.0, 0.0], "final_position": _vec(defender.global_position), "max_deviation": max_deviation, "max_departure": max_departure, "guard_still_active": defender.guard_active}

	var far_guard := _soldier("FarGuard", Vector3(20, 0, 0), "player", false)
	var far_enemy := _passive_target("FarEnemy", Vector3(31, 0, 0))
	far_guard.command_guard(far_guard.global_position)
	var far_max := 0.0
	for i in range(90):
		await process_frame
		far_max = maxf(far_max, _dist(far_guard.global_position, Vector3(20, 0, 0)))
	var far_leash := {"enemy_alive": far_enemy.alive, "enemy_hp": far_enemy.hp, "anchor": [20.0, 0.0, 0.0], "final_position": _vec(far_guard.global_position), "max_deviation": far_max, "leash": Soldier.GUARD_LEASH}

	var vanish_guard := _soldier("VanishGuard", Vector3(40, 0, 0), "player", false)
	var vanish_enemy := _passive_target("VanishEnemy", Vector3(44.8, 0, 0))
	vanish_guard.command_guard(Vector3(40, 0, 0))
	var vanish_departure := 0.0
	for i in range(180):
		await process_frame
		vanish_departure = maxf(vanish_departure, _dist(vanish_guard.global_position, Vector3(40, 0, 0)))
		if vanish_guard.state == Soldier.State.ATTACK and vanish_departure >= 2.0:
			break
	var vanish_was_engaged: bool = vanish_guard.state == Soldier.State.ATTACK and vanish_guard.attack_target == vanish_enemy
	events.append({"event": "vanish_target_acquired", "frame": Engine.get_process_frames(), "anchor": _vec(vanish_guard.guard_anchor), "position": _vec(vanish_guard.global_position)})
	vanish_enemy.queue_free()
	events.append({"event": "target_removed", "frame": Engine.get_process_frames(), "anchor": _vec(vanish_guard.guard_anchor)})
	var vanish_max := 0.0
	var return_start_dist: float = _dist(vanish_guard.global_position, Vector3(40,0,0))
	var return_distance_decreased := false
	for i in range(90):
		await process_frame
		vanish_max = maxf(vanish_max, _dist(vanish_guard.global_position, Vector3(40, 0, 0)))
		if _dist(vanish_guard.global_position, Vector3(40,0,0)) < return_start_dist - 0.25:
			return_distance_decreased = true
	if vanish_guard.global_position.distance_to(Vector3(40, 0, 0)) <= 0.5:
		events.append({"event": "returned_after_target_removed", "frame": Engine.get_process_frames(), "anchor": _vec(vanish_guard.guard_anchor), "position": _vec(vanish_guard.global_position)})
	var disappear_return := {"target_was_engaged": vanish_was_engaged, "target_disappeared": not is_instance_valid(vanish_enemy), "departure_before_removal": vanish_departure, "return_distance_decreased": return_distance_decreased, "final_position": _vec(vanish_guard.global_position), "max_deviation": vanish_max, "guard_still_active": vanish_guard.guard_active}

	var leash_guard := _soldier("LeashGuard", Vector3(20,0,20), "player", false)
	var fleeing_enemy := _passive_target("LeashEnemy", Vector3(24.8,0,20))
	leash_guard.command_guard(Vector3(20,0,20))
	var chase_departure := 0.0
	for i in range(180):
		await process_frame
		chase_departure = maxf(chase_departure, _dist(leash_guard.global_position, Vector3(20,0,20)))
		if leash_guard.state == Soldier.State.ATTACK and chase_departure >= 2.0:
			break
	var crossed_leash := false
	for i in range(180):
		await process_frame
		fleeing_enemy.global_position.x += 8.0 * fixture_root.get_process_delta_time()
		if _dist(fleeing_enemy.global_position, Vector3(20,0,20)) > Soldier.GUARD_LEASH:
			crossed_leash = true
			break
	var leash_return_start: float = _dist(leash_guard.global_position, Vector3(20,0,20))
	var leash_return_decreased := false
	var leash_max_departure := chase_departure
	for i in range(240):
		await process_frame
		leash_max_departure = maxf(leash_max_departure, _dist(leash_guard.global_position, Vector3(20,0,20)))
		if _dist(leash_guard.global_position, Vector3(20,0,20)) < leash_return_start - 0.25:
			leash_return_decreased = true
		if leash_guard.state == Soldier.State.GUARD and _dist(leash_guard.global_position, Vector3(20,0,20)) <= 0.45:
			break
	var leash_return := {"target_crossed_leash": crossed_leash, "enemy_alive": fleeing_enemy.alive, "max_chase_departure": chase_departure, "max_departure": leash_max_departure, "return_distance_decreased": leash_return_decreased, "final_position": _vec(leash_guard.global_position), "anchor": [20.0,0.0,20.0]}

	var idle_unit := _soldier("IdleBaseline", Vector3(-18,-0.0,-25), "player", false)
	var idle_target := _passive_target("IdleBaselineTarget", Vector3(-15,-0.0,-25))
	for i in range(5):
		await process_frame
	var idle_baseline := {"still_unguarded": not idle_unit.guard_active, "auto_acquired": idle_unit.attack_target == idle_target, "state": int(idle_unit.state)}
	var a_unit := _soldier("AMoveBaseline", Vector3(-35,0,-35), "player", false)
	var a_goal := Vector3(-25,0,-35)
	a_unit.command_attack_move(a_goal)
	for i in range(360):
		await process_frame
		if a_unit.state == Soldier.State.IDLE and a_unit.global_position.distance_to(a_goal) <= 0.6:
			break
	var a_baseline := {"guard_inactive": not a_unit.guard_active, "arrived": a_unit.global_position.distance_to(a_goal) <= 0.6, "state": int(a_unit.state), "position": _vec(a_unit.global_position), "goal": _vec(a_goal)}
	var explicit_unit := _soldier("ExplicitAttackBaseline", Vector3(35,0,-35), "player", false)
	var explicit_target := _passive_target("ExplicitAttackBaselineTarget", Vector3(24,0,-35))
	var explicit_start_dist: float = explicit_unit.global_position.distance_to(explicit_target.global_position)
	explicit_unit.command_attack_unit(explicit_target)
	for i in range(180):
		await process_frame
		if explicit_unit.global_position.distance_to(explicit_target.global_position) < explicit_start_dist - 2.0:
			break
	var explicit_baseline := {"guard_inactive": not explicit_unit.guard_active, "explicit_attack_chases": explicit_unit.global_position.distance_to(explicit_target.global_position) < explicit_start_dist - 2.0, "start_distance": explicit_start_dist, "final_distance": explicit_unit.global_position.distance_to(explicit_target.global_position), "state": int(explicit_unit.state)}

	var mine := _resource("GuardAnchorMine", Vector3(-32,0,30))
	var mine_guard := _soldier("MineAnchorGuard", Vector3(-32,0,41), "player", false)
	var raw_mine_anchor := mine.global_position
	mine_guard.command_guard(raw_mine_anchor)
	var mine_arrived := false
	for i in range(720):
		await process_frame
		if mine_guard.global_position.distance_to(mine_guard.guard_resolved_anchor) <= 0.45:
			mine_arrived = true
			break
	var mine_settle := {"requested_raw_anchor": _vec(raw_mine_anchor), "legal_anchor": _vec(mine_guard.guard_resolved_anchor), "soldier_position": _vec(mine_guard.global_position), "resolved_distance": mine_guard.global_position.distance_to(mine_guard.guard_resolved_anchor), "raw_anchor_blocked": mine.blocks_unit_at(raw_mine_anchor, mine_guard.radius), "soldier_clear_of_mine": not mine.blocks_unit_at(mine_guard.global_position, mine_guard.radius), "arrived": mine_arrived}
	var revision_before_mine_removed: int = Pathfind.navigation_revision
	mine.harvest(999)
	var max_frame_step := 0.0
	var mine_recovered := false
	for i in range(720):
		var previous := mine_guard.global_position
		await process_frame
		max_frame_step = maxf(max_frame_step, previous.distance_to(mine_guard.global_position))
		if mine_guard.global_position.distance_to(raw_mine_anchor) <= 0.5:
			mine_recovered = true
			break
	var mine_recovery := {"navigation_revision_before": revision_before_mine_removed, "navigation_revision_after": Pathfind.navigation_revision, "recovered_to_original_click": mine_recovered, "final_position": _vec(mine_guard.global_position), "max_frame_step": max_frame_step, "no_teleport": max_frame_step <= mine_guard.speed / 30.0 + 0.05}

	for unit in get_nodes_in_group("military"):
		if is_instance_valid(unit) and str(unit.get("team")) == "player":
			unit.command_stop()
	var barrier := TestBarrier.new()
	barrier.name = "GuardPathBarrier"
	barrier.wall_z = -20.0
	barrier.add_to_group("resources")
	fixture_root.add_child(barrier)
	Pathfind.invalidate()
	var blocked_guard := _soldier("BlockedGuard", Vector3(-30,0,-32), "player", false)
	var blocked_anchor := Vector3(-30,0,28)
	blocked_guard.command_guard(blocked_anchor)
	var blocked_search_start: int = Pathfind.search_count
	var reached_partial_wait := false
	for i in range(900):
		await process_frame
		if blocked_guard._guard_partial_waiting:
			reached_partial_wait = true
			break
	for i in range(3600):
		if reached_partial_wait and blocked_guard._guard_partial_waiting and blocked_guard._guard_partial_retries >= MAX_RETRIES_FOR_REPORT and blocked_guard._guard_retry_t <= 0.0:
			break
		await process_frame
	var blocked_searches: int = Pathfind.search_count - blocked_search_start
	var stable_search_count: int = Pathfind.search_count
	for i in range(120):
		await process_frame
	var retries_quiet: bool = Pathfind.search_count == stable_search_count
	var blocked_before_remove := {"partial_wait_reached": reached_partial_wait, "retry_count": blocked_guard._guard_partial_retries, "searches": blocked_searches, "position": _vec(blocked_guard.global_position), "anchor": _vec(blocked_anchor), "path_report": Pathfind.last_path_report.duplicate(true)}
	barrier.remove_from_group("resources")
	barrier.queue_free()
	await process_frame
	Pathfind.invalidate()
	await process_frame
	var reopened_path: Array = Pathfind.find_path(blocked_guard.global_position, blocked_anchor, self)
	var reopened_diagnostics: Dictionary = Pathfind.last_path_report.duplicate(true)
	var blocked_return_step := 0.0
	var restored_after_opening := false
	for i in range(1800):
		var previous_blocked := blocked_guard.global_position
		await process_frame
		blocked_return_step = maxf(blocked_return_step, previous_blocked.distance_to(blocked_guard.global_position))
		if blocked_guard.global_position.distance_to(blocked_anchor) <= 0.5:
			restored_after_opening = true
			break
	var obstacle_recovery := {"bounded_searches": blocked_searches <= MAX_RETRIES_FOR_REPORT + 1, "no_search_spam_while_waiting": retries_quiet, "searches_while_blocked": blocked_searches, "partial_wait_reached": reached_partial_wait, "retries": blocked_guard._guard_partial_retries, "reopened_path_waypoints": reopened_path.size(), "reopened_path_diagnostics": reopened_diagnostics, "recovered_after_blockers_removed": restored_after_opening, "final_position": _vec(blocked_guard.global_position), "max_frame_step": blocked_return_step}

	vanish_guard.command_stop()
	var stop := {"active": vanish_guard.guard_active, "state": int(vanish_guard.state), "queue_size": vanish_guard.order_queue.size()}
	var replace_guard := _soldier("ReplaceGuard", Vector3(50, 0, 0), "player", false)
	replace_guard.command_guard(Vector3(50, 0, 0))
	replace_guard.command_move(Vector3(52, 0, 0))
	var replacement := {"guard_active": replace_guard.guard_active, "state": int(replace_guard.state), "queue_size": replace_guard.order_queue.size()}
	var restore_guard := _soldier("RestoreGuard", Vector3(60, 0, 0), "player", false)
	restore_guard.command_guard(Vector3(58, 0, 2))
	var saved: Dictionary = restore_guard.save_guard_intent()
	var restored := _soldier("RestoredGuard", Vector3(60, 0, 0), "player", false)
	restored.restore_guard_intent(bool(saved.guard_active), Vector3(saved.guard_anchor[0], saved.guard_anchor[1], saved.guard_anchor[2]))
	var restore := {"saved": saved, "restored_active": restored.guard_active, "restored_anchor": _vec(restored.guard_anchor), "state": int(restored.state)}
	var passed: bool = enemy_was_killed and max_departure >= 2.0 and kill_return.guard_still_active and max_deviation <= Soldier.GUARD_LEASH + 0.05 and defender.global_position.distance_to(Vector3.ZERO) <= 0.5 and far_enemy.alive and far_max <= 0.05 and bool(disappear_return.target_was_engaged) and bool(disappear_return.target_disappeared) and disappear_return.departure_before_removal >= 2.0 and disappear_return.return_distance_decreased and vanish_guard.global_position.distance_to(Vector3(40, 0, 0)) <= 0.5 and crossed_leash and chase_departure >= 2.0 and leash_return_decreased and leash_guard.global_position.distance_to(Vector3(20,0,20)) <= 0.5 and bool(idle_baseline.still_unguarded) and bool(idle_baseline.auto_acquired) and bool(a_baseline.guard_inactive) and bool(a_baseline.arrived) and bool(explicit_baseline.guard_inactive) and bool(explicit_baseline.explicit_attack_chases) and mine_arrived and bool(mine_settle.raw_anchor_blocked) and bool(mine_settle.soldier_clear_of_mine) and mine_recovered and mine_recovery.no_teleport and reached_partial_wait and int(blocked_before_remove.retry_count) == MAX_RETRIES_FOR_REPORT and retries_quiet and obstacle_recovery.bounded_searches and obstacle_recovery.recovered_after_blockers_removed and not stop.active and not replacement.guard_active and int(replacement.state) == Soldier.State.MOVE and restore.restored_active and Vector3(58,0,2).distance_to(restored.guard_anchor) < 0.01
	var result := {"passed": passed, "runtime": {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/guard_order_regression.gd", "user_data_dir": OS.get_user_data_dir(), "time_scale": Engine.time_scale}, "kill_then_return": kill_return, "far_enemy_leash": far_leash, "target_disappears_then_return": disappear_return, "target_leaves_leash_then_return": leash_return, "ordinary_idle_baseline": idle_baseline, "a_move_baseline": a_baseline, "explicit_attack_baseline": explicit_baseline, "mine_click_legal_anchor": mine_settle, "mine_removal_recovery": mine_recovery, "sealed_route_before_remove": blocked_before_remove, "sealed_route_retry_and_recovery": obstacle_recovery, "stop_cancels": stop, "new_command_cancels": replacement, "intent_restore": restore, "events": events, "natural_process_frames": Engine.get_process_frames()}
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)

func _soldier(label: String, pos: Vector3, side: String, enemy_side: bool) -> Node3D:
	var s: Node3D = Soldier.new()
	s.name = label
	fixture_root.add_child(s)
	s.setup(pos, side, false)
	if enemy_side:
		s.team = "enemy"
	return s

func _passive_target(label: String, pos: Vector3, health: float = 80.0) -> Node3D:
	var target := PassiveTarget.new()
	target.name = label
	fixture_root.add_child(target)
	target.configure(pos, health)
	return target

func _resource(label: String, pos: Vector3) -> Node3D:
	var resource: Node3D = ResourceNode.new()
	resource.name = label
	fixture_root.add_child(resource)
	resource.setup(ResourceNode.Kind.STONE, pos, 200)
	Pathfind.invalidate()
	return resource

func _vec(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
