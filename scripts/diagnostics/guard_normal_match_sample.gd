extends Node

const SoldierScript := preload("res://scripts/soldier.gd")
const Combat := preload("res://scripts/combat.gd")
const ResourceScript := preload("res://scripts/resource_node.gd")

var _events: Array[Dictionary] = []
var _max_deviation: float = 0.0
var _guard_kills: int = 0
var _last_target: Node = null
var _last_target_name: String = ""
var _worker_max_carry: int = 0
var _worker_gather_frames: int = 0
var _guard_destroyed: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		_finish({"sampled": false, "reason": "headless_required"})
		return
	var game: Node = null
	for _frame in range(600):
		game = get_tree().get_first_node_in_group("main_game")
		if game != null and game.get("_start_layer") != null:
			break
		await get_tree().process_frame
	if game == null or game.get("_start_layer") == null:
		_finish({"sampled": false, "reason": "start_scene_missing"})
		return
	game.set("map_seed", 42)
	game.set("_horde_mode", 0)
	await game.call("_begin_match")
	for _frame in range(600):
		if bool(game.get("_match_started")) and game.get("world") != null:
			break
		await get_tree().process_frame
	if not bool(game.get("_match_started")):
		_finish({"sampled": false, "reason": "match_start_failed"})
		return
	# Let the production post-spawn boot finish restoring its normal opening layout
	# before issuing the worker's gather order.
	for _frame in range(3):
		await get_tree().process_frame
	var tc: Node = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == 0:
			tc = building
			break
	var villager: Node = null
	for candidate in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(candidate) and str(candidate.get("team")) == "player":
			villager = candidate
			break
	var nearest_wood: Node = null
	var nearest_wood_dist := INF
	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource) or int(resource.get("kind")) != ResourceScript.Kind.WOOD:
			continue
		var d: float = villager.global_position.distance_to(resource.global_position) if villager != null else INF
		if d < nearest_wood_dist:
			nearest_wood_dist = d
			nearest_wood = resource
	var wood_at_start: int = int(game.get("wood"))
	if villager != null and nearest_wood != null:
		villager.command_gather(nearest_wood, false)
	var worker_state_after_order: int = int(villager.get("state")) if villager != null else -1
	var wood_node_amount_start: int = int(nearest_wood.get("amount")) if nearest_wood != null else 0
	var anchor := Vector3(3.85, 0.0, 0.0)
	var guard: Node = SoldierScript.new()
	guard.name = "NaturalMatch_Guard_Sample"
	game.get("world").add_child(guard)
	guard.setup(anchor, "player", false)
	guard.command_guard(anchor)
	var tc_hp_start: float = float(tc.get("hp")) if tc != null else 0.0
	for _frame in range(600):
		await get_tree().process_frame
	game.call("_spawn_horde_wave", 1)
	var wave_frame := -1
	var frame_count := 0
	var sample_end := false
	for frame in range(4801):
		await get_tree().process_frame
		frame_count = frame + 1
		if villager != null and is_instance_valid(villager):
			_worker_max_carry = maxi(_worker_max_carry, int(villager.get("carry_amount")))
			if int(villager.get("state")) == 2:
				_worker_gather_frames += 1
		if is_instance_valid(guard):
			_max_deviation = maxf(_max_deviation, Vector2(guard.global_position.x - guard.guard_resolved_anchor.x, guard.global_position.z - guard.guard_resolved_anchor.z).length())
		else:
			if not _guard_destroyed:
				_guard_destroyed = true
				_events.append({"event": "guard_destroyed", "frame": frame_count, "wave": int(game.get("_horde_wave"))})
		var target: Node = guard.get("attack_target") if is_instance_valid(guard) else null
		if is_instance_valid(target) and target != _last_target:
			_events.append({"event": "guard_acquired_horde_target", "frame": frame_count, "wave": int(game.get("_horde_wave")), "target": target.name, "position": _vec(guard.global_position), "target_position": _vec(target.global_position)})
			_last_target = target
			_last_target_name = str(target.name)
		if is_instance_valid(_last_target) and not Combat.is_alive(_last_target):
			_guard_kills += 1
			_events.append({"event": "guard_killed_target", "frame": frame_count, "wave": int(game.get("_horde_wave")), "target": _last_target_name})
			_last_target = null
		elif _last_target != null and not is_instance_valid(_last_target):
			_last_target = null
		if int(game.get("_horde_wave")) >= 1 and wave_frame < 0:
			wave_frame = frame_count
			_events.append({"event": "first_natural_horde_spawned", "frame": frame_count, "game_time": float(game.get("_game_time"))})
		if wave_frame >= 0 and frame_count - wave_frame >= 4800:
			sample_end = true
			break
		if not bool(game.get("_match_started")) and bool(game.get("_defeated")):
			break
	var tc_hp_end: float = float(tc.get("hp")) if is_instance_valid(tc) else 0.0
	var report := {"sampled": wave_frame >= 0 and sample_end, "scope": "normal_seeded_match_economy_opening_and_production_horde_combat_window", "full_playthrough_verified": false, "headless": true, "time_scale": Engine.time_scale, "instrumentation_note": "The seeded production match and villagers ran for an unscaled economy opening. The harness then invoked the production _spawn_horde_wave(1) entry point rather than waiting 210 in-game seconds; spawned enemies use production pathing/combat. A production Soldier3D was injected beside the Town Center, so its training cost was not simulated.", "frame_count": frame_count, "game_time": float(game.get("_game_time")), "next_horde_at": float(game.get("_horde_next_at")), "defeated": bool(game.get("_defeated")), "economy": {"wood_start": wood_at_start, "wood_end": int(game.get("wood")), "wood_delta": int(game.get("wood")) - wood_at_start, "gather_worker_found": villager != null, "gather_node_found": nearest_wood != null, "wood_node_amount_start": wood_node_amount_start, "wood_node_amount_end": int(nearest_wood.get("amount")) if is_instance_valid(nearest_wood) else 0, "worker_state_after_order": worker_state_after_order, "worker_state": int(villager.get("state")) if villager != null else -1, "worker_carry": int(villager.get("carry_amount")) if villager != null else 0, "worker_max_carry": _worker_max_carry, "worker_gather_frames": _worker_gather_frames}, "defense": {"wave": int(game.get("_horde_wave")), "wave_spawn_frame": wave_frame, "sample_frames_after_wave": frame_count - wave_frame if wave_frame >= 0 else 0, "guard_active": bool(guard.get("guard_active")) if is_instance_valid(guard) else false, "guard_destroyed": _guard_destroyed, "guard_kills": _guard_kills, "guard_max_deviation": _max_deviation, "leash": SoldierScript.GUARD_LEASH, "tc_hp_start": tc_hp_start, "tc_hp_end": tc_hp_end, "tc_damage_taken": maxf(0.0, tc_hp_start - tc_hp_end)}, "events": _events, "runtime": {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/guard_normal_match_sample.gd", "user_data_dir": OS.get_user_data_dir()}}
	_finish(report)

func _vec(pos: Vector3) -> Array:
	return [pos.x, pos.y, pos.z]

func _finish(report: Dictionary) -> void:
	var out := FileAccess.open("user://guard_normal_match_sample.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(report, "\t"))
		out.close()
	print(JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("sampled", false)) else 1)
