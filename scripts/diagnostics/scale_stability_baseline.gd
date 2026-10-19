extends SceneTree
## Controlled, production-entity scale sample. It is a load fixture, not a match result.

const GAME_SCENE: PackedScene = preload("res://main.tscn")
const VILLAGER: Script = preload("res://scripts/villager.gd")
const SOLDIER: Script = preload("res://scripts/soldier.gd")
const PATHFIND: Script = preload("res://scripts/pathfind.gd")
const RESTORE_PROFILE: Script = preload("res://scripts/diagnostics/restore_profile.gd")

const SMALL_UNITS := {"extra_villagers": 15, "player_soldiers": 5, "enemy_zombies": 5, "total": 30}
const LARGE_UNITS := {"extra_villagers": 25, "player_soldiers": 75, "enemy_zombies": 75, "total": 180}

var run_id := ""
var scenario := ""
var sample_seconds := 90.0
var result_path := ""
var progress_path := ""
var game: Node
var samples: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var events: Array[Dictionary] = []
var replacement_totals := {"villagers": 0, "player_soldiers": 0, "enemy_zombies": 0}
var started_usec := 0
var depleted_resource_id := 0
var depletion_revision_before := -1
var depletion_revision_after := -1
var gather_node_position := Vector3.ZERO
var gather_node_instance_id := 0
var navigation_revision_at_sample_start := -1
var initial_wood_node_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	run_id = _arg_value(args, "run-id", "missing-run-id")
	scenario = _arg_value(args, "scenario", "small")
	sample_seconds = float(_arg_value(args, "sample-seconds", "90"))
	result_path = "user://scale_stability_%s_%s.json" % [scenario, run_id]
	progress_path = "user://scale_stability_%s_%s.progress.json" % [scenario, run_id]
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	Engine.set_meta(RESTORE_PROFILE.TRACE_META, true)
	Engine.set_meta(RESTORE_PROFILE.ORIGIN_META, Time.get_ticks_usec())
	Engine.set_meta(RESTORE_PROFILE.EVENTS_META, [])
	var spec: Dictionary = LARGE_UNITS if scenario == "large" else SMALL_UNITS
	var setup_error := ""
	var warmup_frames := 0
	var continue_report: Dictionary = {"attempted": false, "passed": false}
	var report: Dictionary = {
		"schema": "controlled_rts_scale_baseline_v1",
		"run_id": run_id,
		"scenario": scenario,
		"candidate": "godot-source-working-tree-20261016",
		"fixture_not_natural_match": true,
		"victory_or_strategy_verified": false,
		"map_seed": 42,
		"engine_max_fps": Engine.max_fps,
		"time_scale": Engine.time_scale,
		"requested_units": spec.duplicate(true),
		"headless": DisplayServer.get_name() == "headless",
		"runtime": {"executable": OS.get_executable_path(), "pid": OS.get_process_id(), "user_data_dir": OS.get_user_data_dir(), "driver_resource": "res://scripts/diagnostics/scale_stability_baseline.gd"},
	}
	if not report.headless:
		_finish(report, false, "headless_required")
		return
	if run_id == "missing-run-id" or (scenario != "small" and scenario != "large"):
		_finish(report, false, "invalid_arguments")
		return

	# Run the production start menu and the seed-42 start signal.
	game = GAME_SCENE.instantiate()
	root.add_child(game)
	current_scene = game
	if not await _wait_until(func() -> bool: return is_instance_valid(game) and game.get("_seed_edit") != null, 600):
		_finish(report, false, "start_menu_timeout")
		return
	(game.get("_seed_edit") as LineEdit).text = "42"
	(game.get("_start_begin_button") as Button).pressed.emit()
	if not await _wait_until(func() -> bool: return is_instance_valid(game) and bool(game.get("_match_started")) and game.get("world") != null, 3600):
		_finish(report, false, "seeded_match_start_timeout")
		return
	# Allow production deferred boot work and imported assets to settle before adding load.
	for _i in 180:
		await process_frame
	warmup_frames = 180
	var setup: Dictionary = await _populate_fixture(spec)
	setup_error = str(setup.get("error", ""))
	if not setup_error.is_empty():
		report["fixture_setup_failed"] = setup.duplicate(true)
		_finish(report, false, setup_error)
		return
	initial_wood_node_count = _count_resource_kind(0)
	for _i in 300:
		await process_frame
	warmup_frames += 300
	PATHFIND.reset_measurements()
	navigation_revision_at_sample_start = PATHFIND.navigation_revision
	var unit_counts := _unit_counts()
	report["fixture"] = {
		"warmup_frames": warmup_frames,
		"active_counts_at_sample_start": unit_counts,
		"building_count": get_nodes_in_group("buildings").size(),
		"resource_nodes_at_sample_start": get_nodes_in_group("resources").size(),
		"wood_nodes_after_fixture_setup": initial_wood_node_count,
		"town_center_count": _count_group_kind("buildings", 0),
		"production_start_signal_used": true,
		"seeded_layout": "production VillageDayLayout seed 42",
		"orders": setup.get("orders", {}),
	}
	report["sampling"] = {"requested_wall_seconds": sample_seconds, "metric_sample_interval": "each rendered engine process frame", "warmup_seconds_approx": 8.0, "samples": samples, "per_second_snapshots": snapshots}
	started_usec = Time.get_ticks_usec()
	var last_snapshot_second := -1
	var last_depletion_checked := false
	var last_frame_usec := started_usec
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < sample_seconds:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var elapsed := float(now_usec - started_usec) / 1000000.0
		var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		samples.append({
			"wall_elapsed_s": elapsed,
			"frame_wall_ms": float(now_usec - last_frame_usec) / 1000.0,
			"script_process_ms": process_ms,
			"physics_process_ms": physics_ms,
			"process_frame": Engine.get_process_frames(),
			"physics_frame": Engine.get_physics_frames(),
			"path_search_count": PATHFIND.search_count,
			"navigation_revision": PATHFIND.navigation_revision,
		})
		last_frame_usec = now_usec
		var second := int(floor(elapsed))
		if second > last_snapshot_second:
			last_snapshot_second = second
			if scenario == "large":
				var replacements := _maintain_large_fixture()
				if int(replacements.get("total", 0)) > 0:
					events.append({"event": "controlled_load_replenishment", "second": second, "added": replacements, "active_after": _unit_counts()})
			var s := _snapshot(second, elapsed)
			snapshots.append(s)
			_write_progress({"run_id": run_id, "scenario": scenario, "elapsed_seconds": elapsed, "snapshot": s})
		if not last_depletion_checked:
			var depletion := _check_depletion_and_reassign()
			if bool(depletion.get("depleted", false)):
				last_depletion_checked = true
				depleted_resource_id = int(depletion.get("source_instance_id", 0))
				depletion_revision_before = int(depletion.get("revision_before_depletion", -1))
				depletion_revision_after = int(depletion.get("revision_after_depletion", -1))
				events.append(depletion)
	if not last_depletion_checked:
		var final_depletion := _check_depletion_and_reassign()
		if bool(final_depletion.get("depleted", false)):
			last_depletion_checked = true
			depleted_resource_id = int(final_depletion.get("source_instance_id", 0))
			depletion_revision_before = int(final_depletion.get("revision_before_depletion", -1))
			depletion_revision_after = int(final_depletion.get("revision_after_depletion", -1))
			events.append(final_depletion)
	var path_durations: Array = PATHFIND.search_durations_usec.duplicate()
	report["controlled_replenishments"] = replacement_totals.duplicate(true)
	if scenario == "large":
		report["controlled_replacement_target"] = {"living_villagers": 30, "living_player_soldiers_minimum": 60, "living_enemy_zombies_minimum": 60, "active_unit_floor": 150, "meaning": "maintain a repeatable 150-unit controlled stress load after naturally simulated combat deaths; not a natural match"}
	report["resource_depletion"] = {"observed": depleted_resource_id != 0, "source_instance_id": depleted_resource_id, "navigation_revision_before": depletion_revision_before, "navigation_revision_after": depletion_revision_after, "path_search_samples_captured": path_durations.size()}
	report["pathfinding"] = {"search_count": PATHFIND.search_count, "sampled_duration_usec": path_durations, "duration_percentiles_usec": _percentiles(path_durations)}
	report["sampling"].merge({"elapsed_wall_seconds": float(Time.get_ticks_usec() - started_usec) / 1000000.0, "sample_count": samples.size(), "samples": samples, "per_second_snapshots": snapshots}, true)
	report["frame_percentiles"] = {"wall_frame_ms": _percentiles_from_key(samples, "frame_wall_ms"), "script_process_ms": _percentiles_from_key(samples, "script_process_ms"), "physics_process_ms": _percentiles_from_key(samples, "physics_process_ms")}
	if scenario == "large":
		continue_report = await _save_and_continue()
		events.append({"event": "save_continue", "wall_elapsed_after_sample_s": float(Time.get_ticks_usec() - started_usec) / 1000000.0, "passed": continue_report.get("passed", false)})
		game = _find_main_game()
	report["events"] = events
	report["save_continue"] = continue_report
	var cleanup := await _cleanup_and_observe()
	report["exit_cleanup"] = cleanup
	if Engine.has_meta("scale_baseline_gather_node_position"):
		Engine.remove_meta("scale_baseline_gather_node_position")
	var sample_start_units: Dictionary = report.fixture.active_counts_at_sample_start
	var minimum_end_units := 150 if scenario == "large" else 20
	var passed: bool = setup_error.is_empty() and int(unit_counts.get("total", 0)) == int(spec.total) and int(sample_start_units.get("total", 0)) >= minimum_end_units and bool(report.headless) and bool(cleanup.get("groups_empty_after_exit", false))
	if scenario == "large":
		passed = passed and bool(continue_report.get("passed", false))
	_finish(report, passed, "scale_sample_complete" if passed else "scale_sample_incomplete")

func _populate_fixture(spec: Dictionary) -> Dictionary:
	var game_world: Node3D = game.get("world") as Node3D
	if game_world == null:
		return {"error": "production_world_missing"}
	var resources: Array = get_nodes_in_group("resources")
	var wood_nodes: Array[Node] = []
	for candidate in resources:
		if is_instance_valid(candidate) and int(candidate.get("kind")) == 0 and int(candidate.get("amount")) > 0:
			wood_nodes.append(candidate)
	if wood_nodes.is_empty():
		return {"error": "seeded_wood_nodes_missing"}
	wood_nodes.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.length_squared() < b.global_position.length_squared())
	var gather_node: Node3D = wood_nodes[0] as Node3D
	gather_node_position = gather_node.global_position
	gather_node_instance_id = gather_node.get_instance_id()
	Engine.set_meta("scale_baseline_gather_node_position", gather_node_position)
	game.set_meta("scale_baseline_gather_node_id", gather_node.get_instance_id())
	var villagers: Array = get_nodes_in_group("villagers")
	var initial_villager_count := villagers.size()
	for i in int(spec.extra_villagers):
		var angle := TAU * float(i) / float(maxi(int(spec.extra_villagers), 1))
		var radius := 8.0 + float(i % 7) * 0.8
		var unit: Node3D = VILLAGER.new()
		unit.setup(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), "player")
		game_world.add_child(unit)
		villagers.append(unit)
	for i in int(spec.player_soldiers):
		var angle := TAU * float(i) / float(maxi(int(spec.player_soldiers), 1))
		var radius := 12.0 + float(i % 9) * 0.45
		var unit: Node3D = SOLDIER.new()
		unit.setup(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), "player", false)
		game_world.add_child(unit)
		unit.command_attack_move(Vector3(0.0, 0.0, 0.0))
	for worker in villagers:
		if is_instance_valid(worker) and str(worker.get("team")) == "player" and bool(worker.get("alive")):
			worker.call("command_gather", gather_node)
	var spawned: Array = game.call("_spawn_horde_wave", 1, int(spec.enemy_zombies))
	var queued_count := int(spec.enemy_zombies) - spawned.size()
	if queued_count > 0:
		spawned.append_array(game.call("_flush_horde_spawn_queue", queued_count))
	var counts := _unit_counts()
	var expected_total := int(spec.total)
	if int(counts.get("total", 0)) != expected_total:
		return {"error": "fixture_unit_count_mismatch", "actual": counts, "requested": spec, "initial_villagers": initial_villager_count, "wave_immediate_spawned": spawned.size()}
	return {"orders": {"living_villagers_gathering_one_real_seeded_wood_node": villagers.size(), "player_soldiers_attack_move_to_town_center": int(spec.player_soldiers), "production_horde_wave": int(spec.enemy_zombies), "gather_node_instance_id": gather_node.get_instance_id(), "gather_node_initial_amount": int(gather_node.get("amount")), "horde_first_batch": spawned.size()}}

func _maintain_large_fixture() -> Dictionary:
	if not is_instance_valid(game) or not bool(game.get("_match_started")):
		return {"total": 0}
	var counts := _unit_counts()
	var added := {"villagers": 0, "player_soldiers": 0, "enemy_zombies": 0, "total": 0}
	var world: Node3D = game.get("world") as Node3D
	if world == null:
		return added
	for i in maxi(0, 30 - int(counts.villagers)):
		var worker: Node3D = VILLAGER.new()
		var angle := TAU * float(replacement_totals.villagers + i) / 10.0
		worker.setup(Vector3(cos(angle) * 8.5, 0.0, sin(angle) * 8.5), "player")
		world.add_child(worker)
		var wood := _nearest_live_wood_node(worker.global_position)
		if wood != null:
			worker.call("command_gather", wood)
		added.villagers += 1
	for i in maxi(0, 60 - int(counts.player_soldiers)):
		var fighter: Node3D = SOLDIER.new()
		var angle := TAU * float(replacement_totals.player_soldiers + i) / 18.0
		fighter.setup(Vector3(cos(angle) * 13.0, 0.0, sin(angle) * 13.0), "player", false)
		world.add_child(fighter)
		fighter.command_attack_move(Vector3.ZERO)
		added.player_soldiers += 1
	var enemy_missing := maxi(0, 60 - int(counts.enemy_zombies))
	if enemy_missing > 0:
		var wave := maxi(1, int(game.get("_horde_wave")) + 1)
		var spawned: Array = game.call("_spawn_horde_wave", wave, enemy_missing)
		var queued := enemy_missing - spawned.size()
		if queued > 0:
			spawned.append_array(game.call("_flush_horde_spawn_queue", queued))
		added.enemy_zombies = spawned.size()
	added.total = int(added.villagers) + int(added.player_soldiers) + int(added.enemy_zombies)
	for key in ["villagers", "player_soldiers", "enemy_zombies"]:
		replacement_totals[key] = int(replacement_totals[key]) + int(added[key])
	return added

func _nearest_live_wood_node(from: Vector3) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for candidate in get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or int(candidate.get("kind")) != 0 or int(candidate.get("amount")) <= 0:
			continue
		var distance := from.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate as Node3D
	return nearest

func _check_depletion_and_reassign() -> Dictionary:
	if not is_instance_valid(game):
		return {"depleted": false}
	# The map is recreated by production Continue, so locate the source by its saved map position.
	if depleted_resource_id != 0:
		return {"depleted": false}
	var source_position: Vector3 = Engine.get_meta("scale_baseline_gather_node_position", gather_node_position)
	var original_id := 0
	var still_live := false
	for candidate in get_nodes_in_group("resources"):
		if is_instance_valid(candidate) and int(candidate.get("kind")) == 0 and candidate.global_position.distance_to(source_position) <= 0.1:
			original_id = int(candidate.get_instance_id())
			still_live = true
			break
	if still_live:
		return {"depleted": false}
	var revision_before := navigation_revision_at_sample_start
	var targets: Array = []
	for candidate in get_nodes_in_group("resources"):
		if is_instance_valid(candidate) and int(candidate.get("kind")) == 0 and int(candidate.get("amount")) > 0:
			targets.append(candidate)
	if targets.is_empty():
		return {"depleted": false, "reason": "no_remaining_wood_node"}
	targets.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.length_squared() < b.global_position.length_squared())
	for worker in get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and str(worker.get("team")) == "player" and bool(worker.get("alive")):
			worker.call("command_gather", targets[0])
	return {"depleted": true, "event": "resource_depleted_navigation_invalidated", "source_instance_id": original_id if original_id != 0 else gather_node_instance_id, "revision_before_depletion": revision_before, "revision_after_depletion": PATHFIND.navigation_revision, "workers_reissued_to_live_node": get_nodes_in_group("villagers").size(), "replacement_resource_instance_id": targets[0].get_instance_id()}

func _save_and_continue() -> Dictionary:
	var before := _snapshot(-1, float(Time.get_ticks_usec() - started_usec) / 1000000.0)
	var scene_resources_before: Dictionary = RESTORE_PROFILE.scene_resource_snapshot(game)
	var save_path := "user://aoelite3d_save.json"
	var user_args := OS.get_cmdline_user_args()
	var fixture_path := _arg_value(user_args, "save-fixture-path", "")
	if fixture_path.is_empty():
		if not bool(game.call("_save_match")):
			return {"attempted": true, "passed": false, "reason": "production_save_failed", "before": before}
	else:
		var fixture := FileAccess.open(fixture_path, FileAccess.READ)
		if fixture == null:
			return {"attempted": true, "passed": false, "reason": "fixture_save_open_failed", "path": fixture_path}
		var fixture_bytes := fixture.get_buffer(fixture.get_length())
		fixture.close()
		var destination := FileAccess.open(save_path, FileAccess.WRITE)
		if destination == null:
			return {"attempted": true, "passed": false, "reason": "fixture_save_destination_open_failed"}
		destination.store_buffer(fixture_bytes)
		destination.close()
	var save_hash := FileAccess.get_sha256(save_path)
	var saved_state_file := FileAccess.open(save_path, FileAccess.READ)
	var saved_state: Dictionary = JSON.parse_string(saved_state_file.get_as_text()) if saved_state_file != null else {}
	if saved_state_file != null:
		saved_state_file.close()
	var continue_in_place := _arg_value(user_args, "continue-in-place", "false") == "true"
	Engine.set_meta("aoelite_disable_in_place_continue", not continue_in_place)
	var continue_pressed_usec := 0
	var enabled_before := true
	var old_instance_id := game.get_instance_id()
	if continue_in_place:
		continue_pressed_usec = Time.get_ticks_usec()
		RESTORE_PROFILE.mark("probe.production_continue_method_called", {"in_place_expected": true})
		game.call("_continue_saved_match")
		if not await _wait_until(func() -> bool: return _find_main_game() != null and _find_main_game().get_instance_id() == old_instance_id and not bool(_find_main_game().get("_start_operation_busy")), 3600):
			return {"attempted": true, "passed": false, "reason": "production_in_place_continue_restore_timeout", "save_sha256": save_hash}
		game = _find_main_game()
	else:
		# Recreate the normal production menu over a clean scene, then activate its real Continue signal.
		Engine.set_meta("aoelite_show_start", true)
		var reload_error: Error = reload_current_scene()
		if reload_error != OK:
			return {"attempted": true, "passed": false, "reason": "menu_scene_reload_failed", "error": error_string(reload_error), "save_sha256": save_hash}
		if not await _wait_until(func() -> bool: return _find_main_game() != null and _find_main_game().get_instance_id() != old_instance_id and _find_main_game().get("_start_continue_button") != null, 3600):
			return {"attempted": true, "passed": false, "reason": "continue_menu_after_save_timeout", "save_sha256": save_hash}
		game = _find_main_game()
		var continue_button: Button = game.get("_start_continue_button") as Button
		enabled_before = not continue_button.disabled
		continue_pressed_usec = Time.get_ticks_usec()
		RESTORE_PROFILE.mark("probe.continue_button_pressed")
		continue_button.pressed.emit()
		if not await _wait_until(func() -> bool: return _find_main_game() != null and bool(_find_main_game().get("_match_started")) and _find_main_game().get("_pending_restore").is_empty(), 3600):
			return {"attempted": true, "passed": false, "reason": "production_continue_restore_timeout", "save_sha256": save_hash}
		game = _find_main_game()
	var restored_ready_usec := Time.get_ticks_usec()
	var immediately_after := _snapshot(-2, float(Time.get_ticks_usec() - started_usec) / 1000000.0)
	var scene_resources_after: Dictionary = RESTORE_PROFILE.scene_resource_snapshot(game)
	var restored_state := _restore_state_snapshot(game)
	game.call("_set_pause_menu_open", false)
	for _i in 60:
		await process_frame
	var after_settle := _snapshot(-3, float(Time.get_ticks_usec() - started_usec) / 1000000.0)
	var save_still_present := FileAccess.file_exists(save_path) and FileAccess.get_sha256(save_path) == save_hash
	var source_counts: Dictionary = before.get("units", {})
	var restored_counts: Dictionary = immediately_after.get("units", {})
	var counts_match := int(source_counts.get("villagers", -1)) == int(restored_counts.get("villagers", -2)) and int(source_counts.get("player_soldiers", -1)) == int(restored_counts.get("player_soldiers", -2)) and int(source_counts.get("enemy_zombies", -1)) == int(restored_counts.get("enemy_zombies", -2))
	var expected_resources: Dictionary = saved_state.get("resources", {})
	var state_checks := {
		"resource_stock": int(restored_state.get("resources", {}).get("wood", -1)) == int(expected_resources.get("wood", -2)) and int(restored_state.get("resources", {}).get("meat", -1)) == int(expected_resources.get("meat", -2)) and int(restored_state.get("resources", {}).get("stone", -1)) == int(expected_resources.get("stone", -2)) and int(restored_state.get("resources", {}).get("gold", -1)) == int(expected_resources.get("gold", -2)),
		"research_age": int(restored_state.get("research", {}).get("age", -1)) == int(saved_state.get("age", 1)),
		"forestry_technology": Array(restored_state.get("research", {}).get("researched_techs", [])).has("improved_axes") == Array(saved_state.get("researched_techs", [])).has("improved_axes") and is_equal_approx(float(restored_state.get("research", {}).get("wood_gather_multiplier", -1)), 1.25) and int(restored_state.get("research", {}).get("wood_carry_bonus", -1)) == 5,
		"paid_training_queue": Array(restored_state.get("production", {}).get("queue", [])) == _expected_queue(saved_state) and bool(restored_state.get("production", {}).get("paid", false)) == _expected_queue_paid(saved_state) and is_equal_approx(float(restored_state.get("production", {}).get("training_timer", -1)), _expected_queue_timer(saved_state)),
		"villager_target_and_orders": bool(restored_state.get("villager", {}).get("target_valid", false)) and int(restored_state.get("villager", {}).get("order_count", 0)) == _expected_order_count(saved_state, "villagers"),
		"soldier_attack_move_and_orders": bool(restored_state.get("soldier", {}).get("attack_move_active", false)) and int(restored_state.get("soldier", {}).get("order_count", -1)) == _expected_active_soldier_order_count(saved_state) and int(restored_state.get("queued_soldier_orders", 0)) > 0,
		"clock_and_horde_state": is_equal_approx(float(restored_state.get("clock_minutes", -1)), float(saved_state.get("clock_minutes", -2))) and restored_state.get("is_night", false) == _expected_is_night(float(saved_state.get("clock_minutes", 0))) and int(restored_state.get("horde_wave", -1)) == int(saved_state.get("horde_wave", -2)) and int(restored_state.get("horde_mode", -1)) == int(saved_state.get("horde_mode", -2)) and Array(restored_state.get("horde_spawn_queue", [])).size() == Array(saved_state.get("horde_spawn_queue", [])).size() and restored_state.get("paused", false) == (saved_state.get("paused", false) == true),
		"zombie_night_flags": int(restored_state.get("night_buffed_zombies", -1)) == _expected_night_buffed_zombies(saved_state),
	}
	var all_state_checks := true
	for check in state_checks.values(): all_state_checks = all_state_checks and bool(check)
	var settled_state := _restore_state_snapshot(game)
	var continued_progress := float(settled_state.get("game_time", -1)) > float(restored_state.get("game_time", INF)) and (float(restored_state.get("training_timer", -1)) < 0.0 or float(settled_state.get("training_timer", INF)) < float(restored_state.get("training_timer", INF)))
	return {"attempted": true, "passed": enabled_before and save_still_present and counts_match and all_state_checks and continued_progress and bool(immediately_after.get("match_started", false)), "continue_in_place_requested": continue_in_place, "same_scene_instance_after_continue": old_instance_id == game.get_instance_id(), "production_continue_signal_emitted": not continue_in_place, "production_continue_method_called": continue_in_place, "continue_button_was_enabled": enabled_before, "save_sha256_before": save_hash, "save_preserved_after_continue": save_still_present, "continue_to_restored_ready_usec": restored_ready_usec - continue_pressed_usec, "scene_resources_before": scene_resources_before, "scene_resources_after": scene_resources_after, "restore_trace_events": Engine.get_meta(RESTORE_PROFILE.EVENTS_META, []), "before": before, "immediately_after_restore": immediately_after, "after_60_settle_frames": after_settle, "unit_counts_match_at_restore": counts_match, "restored_state": restored_state, "expected_state_checks": state_checks, "after_60_state": settled_state, "game_time_and_training_progressed": continued_progress, "pending_restore_cleared": game.get("_pending_restore").is_empty()}

func _restore_state_snapshot(game_node: Node) -> Dictionary:
	var research_node: Node = game_node.get("research")
	var producer: Node = null
	for candidate in get_nodes_in_group("buildings"):
		if int(candidate.get("kind")) == 12:
			producer = candidate
			break
	var villager: Node = null
	for candidate in get_nodes_in_group("villagers"):
		if str(candidate.get("team")) == "player":
			villager = candidate
			break
	var soldier: Node = null
	var queued_soldier_orders := 0
	for candidate in get_nodes_in_group("soldiers"):
		if str(candidate.get("team")) != "player" or candidate.get("is_zombie") == true: continue
		if soldier == null and candidate.get("_attack_move_active") == true: soldier = candidate
		queued_soldier_orders += Array(candidate.get("order_queue")).size()
	if soldier == null:
		for candidate in get_nodes_in_group("soldiers"):
			if str(candidate.get("team")) == "player" and candidate.get("is_zombie") != true:
				soldier = candidate
				break
	var valid_zombies := 0
	var buffed_zombies := 0
	for candidate in get_nodes_in_group("zombies"):
		if not is_instance_valid(candidate): continue
		valid_zombies += 1
		if candidate.get("_night_buffed") == true: buffed_zombies += 1
	var resources := {"wood": int(game_node.get("wood")), "meat": int(game_node.get("meat")), "stone": int(game_node.get("stone")), "gold": int(game_node.get("gold"))}
	var techs: Array = Array(research_node.get("researched_techs")) if research_node != null else []
	var villager_orders: Array = villager.get("order_queue") if villager != null else []
	var soldier_orders: Array = soldier.get("order_queue") if soldier != null else []
	return {
		"resources": resources,
		"research": {"age": int(research_node.get("age")) if research_node != null else -1, "researched_techs": techs, "wood_gather_multiplier": float(villager.get("wood_gather_multiplier")) if villager != null else -1.0, "wood_carry_bonus": int(villager.get("wood_carry_bonus")) if villager != null else -1},
		"production": {"queue_count": Array(producer.get("train_queue")).size() if producer != null else 0, "queue": Array(producer.get("train_queue")) if producer != null else [], "training_timer": float(producer.get("train_timer")) if producer != null else -1.0, "paid": (producer.get("train_paid") == true) if producer != null else false, "paused": (producer.get("train_paused") == true) if producer != null else false},
		"training_timer": float(producer.get("train_timer")) if producer != null else -1.0,
		"villager": {"target_valid": villager != null and is_instance_valid(villager.get("gather_target")) and is_instance_valid(villager.get("resume_resource")), "gather_kind": int(villager.get("gather_target").get("kind")) if villager != null and is_instance_valid(villager.get("gather_target")) else -1, "resume_key": str(villager.get("resume_key")) if villager != null else "", "order_count": villager_orders.size(), "orders": _runtime_order_snapshot(villager_orders)},
		"soldier": {"attack_move_active": soldier.get("_attack_move_active") == true if soldier != null else false, "attack_move_goal": _v3(soldier.get("_attack_move_goal")) if soldier != null else [], "order_count": soldier_orders.size(), "orders": _runtime_order_snapshot(soldier_orders)},
		"queued_soldier_orders": queued_soldier_orders,
		"paused": game_node.get_tree().paused, "clock_minutes": float(game_node.get("_clock_minutes")), "is_night": game_node.call("_is_game_night") == true, "game_time": float(game_node.get("_game_time")), "horde_wave": int(game_node.get("_horde_wave")), "horde_mode": int(game_node.get("_horde_mode")), "horde_next_at": float(game_node.get("_horde_next_at")), "horde_active": game_node.get("_horde_active") == true, "horde_spawn_queue": Array(game_node.get("_horde_spawn_queue")).duplicate(true),
		"night_buffed_zombies": buffed_zombies, "zombie_count": valid_zombies,
	}

func _runtime_order_snapshot(queue: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order in queue:
		if order is Dictionary:
			var row := {"k": str(order.get("k", ""))}
			if order.get("p", null) is Vector3: row["p"] = _v3(order.p)
			if order.get("n", null) is Node: row["target_valid"] = is_instance_valid(order.n)
			result.append(row)
	return result

func _expected_queue_count(data: Dictionary) -> int:
	for building in data.get("entities", {}).get("buildings", []):
		if int(building.get("kind", -1)) == 12: return Array(building.get("train_queue", [])).size()
	return 0

func _expected_queue_paid(data: Dictionary) -> bool:
	for building in data.get("entities", {}).get("buildings", []):
		if int(building.get("kind", -1)) == 12: return bool(building.get("train_paid", false))
	return false

func _expected_queue(data: Dictionary) -> Array:
	for building in data.get("entities", {}).get("buildings", []):
		if int(building.get("kind", -1)) == 12: return Array(building.get("train_queue", []))
	return []

func _expected_queue_timer(data: Dictionary) -> float:
	for building in data.get("entities", {}).get("buildings", []):
		if int(building.get("kind", -1)) == 12: return float(building.get("train_timer", -1))
	return -1.0

func _expected_is_night(clock_minutes: float) -> bool:
	var hour := int(floor(clock_minutes)) / 60 % 24
	return hour >= 22 or hour < 6

func _expected_order_count(data: Dictionary, group_name: String) -> int:
	var rows: Array = data.get("entities", {}).get(group_name, [])
	return Array(rows[0].get("orders", [])).size() if not rows.is_empty() else 0

func _expected_active_soldier_order_count(data: Dictionary) -> int:
	for soldier in data.get("entities", {}).get("soldiers", []):
		if not bool(soldier.get("is_zombie", false)) and bool(soldier.get("attack_move_active", false)):
			return Array(soldier.get("orders", [])).size()
	return -1

func _expected_night_buffed_zombies(data: Dictionary) -> int:
	var count := 0
	for soldier in data.get("entities", {}).get("soldiers", []):
		if bool(soldier.get("is_zombie", false)) and bool(soldier.get("night_buffed", false)): count += 1
	return count

func _v3(value: Variant) -> Array:
	if value is Vector3: return [value.x, value.y, value.z]
	return []

func _cleanup_and_observe() -> Dictionary:
	game = _find_main_game()
	if game == null:
		quit(1)
		return {"performed": false, "reason": "main_game_missing_before_cleanup"}
	game.set("_world_teardown_in_progress", true)
	game.queue_free()
	for _i in 5:
		await process_frame
	var remaining := {"buildings": get_nodes_in_group("buildings").size(), "resources": get_nodes_in_group("resources").size(), "villagers": get_nodes_in_group("villagers").size(), "soldiers": get_nodes_in_group("soldiers").size(), "zombies": get_nodes_in_group("zombies").size()}
	var empty := true
	for value in remaining.values():
		empty = empty and int(value) == 0
	return {"performed": true, "groups_after_scene_exit": remaining, "groups_empty_after_exit": empty, "engine_process_frame": Engine.get_process_frames(), "engine_physics_frame": Engine.get_physics_frames()}

func _snapshot(second: int, elapsed: float) -> Dictionary:
	var game_now := _find_main_game()
	var path_delta := PATHFIND.search_count
	if not snapshots.is_empty():
		path_delta -= int(snapshots[-1].get("path_search_count", 0))
	return {"second": second, "wall_elapsed_s": elapsed, "game_time_s": float(game_now.get("_game_time")) if game_now != null else -1.0, "match_started": bool(game_now.get("_match_started")) if game_now != null else false, "units": _unit_counts(), "building_count": get_nodes_in_group("buildings").size(), "resource_nodes": _resource_summary(), "path_search_count": PATHFIND.search_count, "path_searches_since_previous_snapshot": path_delta, "navigation_revision": PATHFIND.navigation_revision, "process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames()}

func _resource_summary() -> Dictionary:
	var out := {"wood_nodes": 0, "wood_total_stock": 0, "wood_min_stock": -1, "wood_depleted_count": 0}
	var min_stock := 2147483647
	for candidate in get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or int(candidate.get("kind")) != 0:
			continue
		var amount := int(candidate.get("amount"))
		out.wood_nodes = int(out.wood_nodes) + 1
		out.wood_total_stock = int(out.wood_total_stock) + amount
		min_stock = mini(min_stock, amount)
	if int(out.wood_nodes) > 0:
		out.wood_min_stock = min_stock
	out.wood_depleted_count = maxi(0, initial_wood_node_count - int(out.wood_nodes))
	return out

func _count_resource_kind(kind_id: int) -> int:
	var count := 0
	for candidate in get_nodes_in_group("resources"):
		if is_instance_valid(candidate) and int(candidate.get("kind")) == kind_id:
			count += 1
	return count

func _unit_counts() -> Dictionary:
	var villagers := get_nodes_in_group("villagers")
	var soldiers := get_nodes_in_group("soldiers")
	var alive_player_soldiers := 0
	var alive_zombies := 0
	for unit in soldiers:
		if not is_instance_valid(unit) or unit.get("alive") == false:
			continue
		if bool(unit.get("is_zombie")):
			alive_zombies += 1
		elif str(unit.get("team")) == "player":
			alive_player_soldiers += 1
	var alive_villagers := 0
	for unit in villagers:
		if is_instance_valid(unit) and unit.get("alive") != false:
			alive_villagers += 1
	return {"villagers": alive_villagers, "player_soldiers": alive_player_soldiers, "enemy_zombies": alive_zombies, "total": alive_villagers + alive_player_soldiers + alive_zombies}

func _count_group_kind(group_name: String, kind_id: int) -> int:
	var n := 0
	for candidate in get_nodes_in_group(group_name):
		if is_instance_valid(candidate) and int(candidate.get("kind")) == kind_id:
			n += 1
	return n

func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _find_main_game() -> Node:
	return get_first_node_in_group("main_game")

func _write_progress(data: Dictionary) -> void:
	var f := FileAccess.open(progress_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func _finish(report: Dictionary, passed: bool, reason: String) -> void:
	report["passed"] = passed
	report["exit_reason"] = reason
	_write_json(result_path, report)
	print("[scale-baseline] ", JSON.stringify({"run_id": run_id, "scenario": scenario, "passed": passed, "reason": reason, "result_path": ProjectSettings.globalize_path(result_path)}))
	quit(0 if passed else 1)

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	var prefix := "--%s=" % key
	for arg in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

func _percentiles(raw: Array) -> Dictionary:
	if raw.is_empty():
		return {"count": 0, "p50": null, "p95": null, "p99": null, "max": null}
	var sorted: Array = raw.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "p50": _at_percentile(sorted, 0.50), "p95": _at_percentile(sorted, 0.95), "p99": _at_percentile(sorted, 0.99), "max": sorted[-1]}

func _percentiles_from_key(rows: Array, key: String) -> Dictionary:
	var values: Array = []
	for row in rows:
		values.append(float(row.get(key, 0.0)))
	return _percentiles(values)

func _at_percentile(sorted: Array, pct: float) -> Variant:
	return sorted[clampi(int(ceil(pct * float(sorted.size()))) - 1, 0, sorted.size() - 1)]
