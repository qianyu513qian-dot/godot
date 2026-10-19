extends Node
## Production-input and repeated-lifecycle coverage for same-seed in-place Continue.

const VILLAGER := preload("res://scripts/villager.gd")
const SOLDIER := preload("res://scripts/soldier.gd")
const BUILDING := preload("res://scripts/building.gd")
const CATALOG := preload("res://scripts/building_catalog.gd")
const PATHFIND := preload("res://scripts/pathfind.gd")
const PROFILE := preload("res://scripts/diagnostics/restore_profile.gd")

var _run_id := "missing-run-id"
var _fixture_path := ""
var _report: Dictionary = {"schema": "restore_in_place_regression_v1", "passed": false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_run_id = _arg(args, "run-id", _run_id)
	_fixture_path = _arg(args, "fixture-path", "")
	if DisplayServer.get_name() != "headless" or _fixture_path.is_empty():
		_finish(false, "headless_or_fixture_missing")
		return
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	Engine.set_meta(PROFILE.TRACE_META, true)
	Engine.set_meta(PROFILE.ORIGIN_META, Time.get_ticks_usec())
	Engine.set_meta(PROFILE.EVENTS_META, [])
	if _arg(args, "case", "repeat") == "mismatch":
		await _run_seed_mismatch()
		return
	if _arg(args, "case", "repeat") == "waves":
		await _run_wave_boundaries()
		return
	_report.merge({"run_id": _run_id, "pid": OS.get_process_id(), "executable": OS.get_executable_path(), "user_data_dir": OS.get_user_data_dir(), "fixture_path": _fixture_path, "headless": true, "natural_full_match_verified": false, "boundary_fixture_scope": "same-seed 180-unit saved-state repeated Continue and cleanup; not a natural full match"}, true)
	var menu: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 300)
	if menu == null:
		_finish(false, "initial_menu_timeout")
		return
	await _start_from_menu(menu, 42)
	var game: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 3600)
	if game == null:
		_finish(false, "seed_42_start_timeout")
		return
	for _frame in 120: await get_tree().process_frame
	var setup := _populate_fixture(game)
	if not bool(setup.get("ok", false)):
		_finish(false, str(setup.get("error", "unit_fixture_setup_failed")), {"setup": setup})
		return
	var fixture := FileAccess.open(_fixture_path, FileAccess.READ)
	if fixture == null:
		_finish(false, "fixture_open_failed")
		return
	var fixture_bytes := fixture.get_buffer(fixture.get_length())
	fixture.close()
	var fixture_data: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	if not fixture_data is Dictionary:
		_finish(false, "fixture_json_invalid")
		return
	var save_file := FileAccess.open("user://aoelite3d_save.json", FileAccess.WRITE)
	if save_file == null:
		_finish(false, "user_save_write_failed")
		return
	save_file.store_buffer(fixture_bytes)
	save_file.close()
	var save_hash := FileAccess.get_sha256("user://aoelite3d_save.json")
	var cycles: Array[Dictionary] = []
	var expected_timer := float(fixture_data.entities.buildings[-1].get("train_timer", 3.25))
	var expected_queue: Array = fixture_data.entities.buildings[-1].get("train_queue", ["soldier", "villager"])
	for cycle_index in 3:
		game = get_tree().get_first_node_in_group("main_game")
		if game == null or get_tree().paused:
			_finish(false, "game_or_pause_state_unexpected_before_cycle", {"cycle": cycle_index})
			return
		var world_before: Node = game.get("world")
		var world_id_before := world_before.get_instance_id()
		var main_id_before := game.get_instance_id()
		var entities_before := _entity_ids()
		var barracks_before := _find_building(12)
		var old_selection: Node = barracks_before
		if barracks_before == null or old_selection == null:
			_finish(false, "fixture_buildings_missing_before_cycle", {"cycle": cycle_index})
			return
		var selected_queue: Array = old_selection.get("train_queue")
		selected_queue.clear()
		selected_queue.append("villager")
		old_selection.set("train_timer", 1.0)
		old_selection.set("train_paid", true)
		game.call("_clear_selection")
		game.call("_add_to_selection", old_selection)
		game.call("_refresh_selection_hud")
		await get_tree().process_frame
		var hud: Node = game.get("hud")
		var hud_info_before := str(hud.get("_info_name").text) if hud != null else ""
		var hud_queue_before := int(hud.get("_train_row").get_child_count()) if hud != null else 0
		if hud_queue_before <= 0:
			_finish(false, "training_queue_not_visible_before_continue", {"cycle": cycle_index, "hud_info": hud_info_before, "hud_queue": hud_queue_before, "building_queue": old_selection.get("train_queue"), "selected_count": Array(game.get("selected")).size(), "selection_fp": game.get("_sel_fp")})
			return
		await _send_key(KEY_ESCAPE)
		if not bool(game.get("_pause_menu_open")) or not get_tree().paused:
			_finish(false, "escape_did_not_open_production_pause_menu", {"cycle": cycle_index})
			return
		var route := "pause_menu_f9_input"
		if cycle_index == 1:
			route = "pause_menu_continue_button_signal"
			var continue_button := _find_button(game.get("_pause_layer"), "读取存档（F9）")
			if continue_button == null:
				_finish(false, "pause_continue_button_missing", {"cycle": cycle_index})
				return
			continue_button.pressed.emit()
		else:
			await _send_key(KEY_F9)
		if not await _wait_until(func() -> bool: return get_tree().paused and not bool(game.get("_start_operation_busy")) and bool(game.get("_match_started")), 360):
			_finish(false, "same_scene_continue_timeout", {"cycle": cycle_index, "route": route})
			return
		await get_tree().process_frame
		var restored_state := _state_snapshot(game)
		var stale_selection := not Array(game.get("selected")).is_empty()
		var hud_info_after := str(hud.get("_info_name").text) if hud != null else ""
		var hud_queue_after := int(hud.get("_train_row").get_child_count()) if hud != null else -1
		var pause_status: Label = game.get("_pause_status_label")
		var pause_status_text := pause_status.text if is_instance_valid(pause_status) else ""
		var loaded_barracks := _find_building(12)
		if loaded_barracks == null:
			_finish(false, "restored_barracks_missing", {"cycle": cycle_index})
			return
		game.call("_clear_selection")
		game.call("_add_to_selection", loaded_barracks)
		game.call("_refresh_selection_hud")
		var restored_hud_queue := int(hud.get("_train_row").get_child_count()) if hud != null else 0
		game.call("_clear_selection")
		game.call("_refresh_selection_hud")
		var selection_cleared := Array(game.get("selected")).is_empty() and hud_info_after != hud_info_before and str(hud.get("_info_name").text) == "未选择" and hud_queue_after == 0
		var nav_before_rebuild: Dictionary = PATHFIND.diagnostic_snapshot()
		PATHFIND.rebuild(get_tree())
		var nav_after_rebuild: Dictionary = PATHFIND.diagnostic_snapshot()
		var connections: Array = loaded_barracks.train_finished.get_connections()
		var cycle_checks := {
			"same_main_and_world_reused": game.get_instance_id() == main_id_before and game.get("world").get_instance_id() == world_id_before,
			"unit_groups_match_save": restored_state.units == {"villagers": 30, "player_soldiers": 75, "enemy_zombies": 75, "total": 180},
			"selection_and_hud_cleared": selection_cleared and not stale_selection,
			"training_queue_hud_and_signal": Array(loaded_barracks.get("train_queue")) == expected_queue and is_equal_approx(float(loaded_barracks.get("train_timer")), expected_timer) and restored_hud_queue > 0 and connections.size() == 1,
			"pause_status_cleared": pause_status_text == "对局已读取。",
			"gather_targets_restored": bool(restored_state.gather_target_valid) and bool(restored_state.resume_target_same),
			"saved_payload_cleared_and_hash_stable": game.get("_pending_restore").is_empty() and not Engine.has_meta("aoelite_load_payload") and FileAccess.get_sha256("user://aoelite3d_save.json") == save_hash,
			"path_cache_invalidated_then_rebuilt": bool(nav_before_rebuild.dirty) and not bool(nav_after_rebuild.dirty) and int(nav_after_rebuild.blocked_cells) > 0,
			"temporary_timer_count_stable": _timer_count() == 0,
		}
		var check_ok := true
		for value in cycle_checks.values(): check_ok = check_ok and bool(value)
		cycles.append({"cycle": cycle_index + 1, "input_route": route, "continue_usec": _latest_duration("continue_saved_match.in_place_restore.end"), "restore_state": restored_state, "checks": cycle_checks, "pause_status": pause_status_text, "hud_info_before": hud_info_before, "hud_info_after": str(hud.get("_info_name").text), "hud_queue_before": hud_queue_before, "hud_queue_after_restore": hud_queue_after, "hud_queue_after_selecting_restored_barracks": restored_hud_queue, "path_cache_before_rebuild": nav_before_rebuild, "path_cache_after_rebuild": nav_after_rebuild, "old_entity_ids": entities_before, "old_entity_refs_freed": _freed_ids(entities_before), "timer_nodes": _timer_count(), "signal_connections": connections.size(), "static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC))})
		if not check_ok:
			_finish(false, "repeat_cycle_assertion_failed", {"cycles": cycles, "failed_cycle": cycle_index + 1})
			return
		await _send_key(KEY_ESCAPE)
		if get_tree().paused:
			_finish(false, "escape_did_not_resume_after_restore", {"cycle": cycle_index})
			return
		var before_time := float(game.get("_game_time"))
		var before_timer := float(loaded_barracks.get("train_timer"))
		for _frame in 60: await get_tree().process_frame
		var progressed := float(game.get("_game_time")) > before_time and float(loaded_barracks.get("train_timer")) < before_timer
		cycles[-1]["continued_after_unpause"] = progressed
		if not progressed:
			_finish(false, "simulation_or_training_stalled_after_restore", {"cycles": cycles, "cycle": cycle_index + 1})
			return
	# Exercise production pause-menu return, teardown, and a clean new start in this process.
	game = get_tree().get_first_node_in_group("main_game")
	await _send_key(KEY_ESCAPE)
	var menu_button := _find_button(game.get("_pause_layer"), "返回主菜单")
	if menu_button == null:
		_finish(false, "return_to_menu_button_missing", {"cycles": cycles})
		return
	var closing_game_id := game.get_instance_id()
	menu_button.pressed.emit()
	var menu_after: Node = await _wait_for_game(func(g: Node) -> bool: return g.get_instance_id() != closing_game_id and g.get("_start_begin_button") != null, 3600)
	var groups_after_menu := _group_counts()
	var teardown_ok := menu_after != null and _groups_empty(groups_after_menu) and not Engine.has_meta("aoelite_load_payload") and not Engine.has_meta("aoelite_resume_paused_after_load")
	if not teardown_ok:
		_finish(false, "return_to_menu_left_runtime_state", {"groups": groups_after_menu, "cycles": cycles})
		return
	await _start_from_menu(menu_after, 42)
	var reopened: Node = await _wait_for_game(func(g: Node) -> bool: return g.get_instance_id() != closing_game_id and bool(g.get("_match_started")), 3600)
	if reopened == null or int(reopened.get("map_seed")) != 42 or int(_group_counts().get("soldiers", -1)) != 0 or int(_group_counts().get("zombies", -1)) != 0:
		_finish(false, "clean_reopen_inherited_old_world_state", {"groups": _group_counts(), "game_instance": reopened.get_instance_id() if reopened != null else -1})
		return
	_report.merge({"passed": true, "reason": "repeat_in_place_continue_and_cleanup_verified", "repeat_cycles": cycles, "production_fixture": setup, "same_save_sha256": save_hash, "groups_after_menu_return": groups_after_menu, "groups_after_clean_reopen": _group_counts(), "final_path_cache": PATHFIND.diagnostic_snapshot(), "restore_trace_events": Engine.get_meta(PROFILE.EVENTS_META, []), "natural_full_match_verified": false}, true)
	_finish(true, "repeat_in_place_continue_and_cleanup_verified")

func _populate_fixture(game: Node) -> Dictionary:
	var world: Node3D = game.get("world")
	var wood: Array[Node] = []
	for node in get_tree().get_nodes_in_group("resources"):
		if int(node.get("kind")) == 0 and int(node.get("amount")) > 0: wood.append(node)
	if world == null or wood.is_empty(): return {"ok": false, "error": "seeded_world_or_wood_missing"}
	wood.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.length_squared() < b.global_position.length_squared())
	var target: Node3D = wood[0]
	var workers: Array = get_tree().get_nodes_in_group("villagers")
	for i in 25:
		var angle := TAU * float(i) / 25.0
		var worker: Node3D = VILLAGER.new()
		worker.setup(Vector3(cos(angle) * 8.0, 0.0, sin(angle) * 8.0), "player")
		world.add_child(worker)
		workers.append(worker)
	for worker in workers: worker.call("command_gather", target)
	for i in 75:
		var angle := TAU * float(i) / 75.0
		var fighter: Node3D = SOLDIER.new()
		fighter.setup(Vector3(cos(angle) * 12.0, 0.0, sin(angle) * 12.0), "player", false)
		world.add_child(fighter)
		fighter.command_attack_move(Vector3.ZERO)
	var spawned: Array = game.call("_spawn_horde_wave", 1, 75)
	if spawned.size() < 75: spawned.append_array(game.call("_flush_horde_spawn_queue", 75 - spawned.size()))
	var barracks: Node3D = BUILDING.new()
	barracks.setup(CATALOG.BARRACKS, Vector3(-15.0, 0.0, -15.0), "player", true)
	world.add_child(barracks)
	barracks.train_finished.connect(Callable(game, "_on_train_finished"))
	var counts := _unit_counts()
	return {"ok": int(counts.total) == 180, "units": counts, "resource_nodes": get_tree().get_nodes_in_group("resources").size(), "buildings": get_tree().get_nodes_in_group("buildings").size(), "horde_spawned": spawned.size(), "gather_target_position": _v3(target.global_position)}

func _run_seed_mismatch() -> void:
	var menu: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 300)
	if menu == null:
		_finish(false, "mismatch_initial_menu_timeout")
		return
	await _start_from_menu(menu, 43)
	var seed_43_game: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 3600)
	if seed_43_game == null:
		_finish(false, "seed_43_start_timeout")
		return
	for _frame in 60: await get_tree().process_frame
	var saved_target: Node = null
	for resource in get_tree().get_nodes_in_group("resources"):
		if int(resource.get("kind")) == 0 and int(resource.get("amount")) > 0:
			saved_target = resource
			break
	if saved_target == null:
		_finish(false, "seed_43_target_resource_missing")
		return
	for worker in get_tree().get_nodes_in_group("villagers"):
		if str(worker.get("team")) == "player": worker.call("command_gather", saved_target)
	for _frame in 30: await get_tree().process_frame
	seed_43_game.call("_save_match")
	var saved_file := FileAccess.open("user://aoelite3d_save.json", FileAccess.READ)
	if saved_file == null:
		_finish(false, "seed_43_save_missing")
		return
	var saved: Variant = JSON.parse_string(saved_file.get_as_text())
	saved_file.close()
	if not saved is Dictionary or int(saved.get("map_seed", -1)) != 43:
		_finish(false, "seed_43_save_invalid")
		return
	var expected_resources: Array = saved.get("entities", {}).get("resources", [])
	var expected_resource_positions := _sorted_positions(expected_resources)
	var expected_target_id := ""
	for worker in saved.get("entities", {}).get("villagers", []):
		if str(worker.get("team", "")) == "player" and not str(worker.get("gather_id", "")).is_empty():
			expected_target_id = str(worker.get("gather_id"))
			break
	if expected_resources.size() != 33 or expected_target_id.is_empty():
		_finish(false, "seed_43_fixture_missing_resources_or_target", {"resources": expected_resources.size(), "target_id": expected_target_id})
		return
	var seed_43_world_id := (seed_43_game.get("world") as Node).get_instance_id()
	await _return_to_menu(seed_43_game)
	var menu_42: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 3600)
	if menu_42 == null:
		_finish(false, "menu_after_seed_43_missing")
		return
	await _start_from_menu(menu_42, 42)
	var seed_42_game: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 3600)
	if seed_42_game == null:
		_finish(false, "seed_42_start_timeout")
		return
	await _send_key(KEY_ESCAPE)
	if not get_tree().paused:
		_finish(false, "mismatch_pause_open_failed")
		return
	var old_game_id := seed_42_game.get_instance_id()
	await _send_key(KEY_F9)
	var restored_43: Node = await _wait_for_game(func(g: Node) -> bool: return g.get_instance_id() != old_game_id and bool(g.get("_match_started")) and int(g.get("map_seed")) == 43, 3600)
	if restored_43 == null:
		_finish(false, "different_seed_f9_did_not_reload_saved_seed", {"current_seed": seed_42_game.get("map_seed") if is_instance_valid(seed_42_game) else -1})
		return
	await get_tree().process_frame
	var actual_resources := _sorted_group_positions("resources")
	var restored_target_found := false
	for worker in get_tree().get_nodes_in_group("villagers"):
		if str(worker.get("team")) != "player": continue
		var target: Node = worker.get("gather_target")
		if is_instance_valid(target) and _position_in_list(_v3(target.global_position), expected_resource_positions):
			restored_target_found = true
			break
	var mismatch_status: Label = restored_43.get("_pause_status_label")
	var mismatch_checks := {"new_world_after_seed_mismatch": (restored_43.get("world") as Node).get_instance_id() != seed_43_world_id, "saved_seed_restored": int(restored_43.get("map_seed")) == 43, "all_seeded_resource_positions_restored": _positions_equal(actual_resources, expected_resource_positions), "gather_target_resolved_to_restored_resource": restored_target_found, "pause_menu_f9_status": is_instance_valid(mismatch_status) and mismatch_status.text == "对局已读取。"}
	if not _all_checks(mismatch_checks):
		_finish(false, "seed_mismatch_restore_assertion_failed", {"checks": mismatch_checks, "expected_resource_count": expected_resource_positions.size(), "actual_resource_count": actual_resources.size(), "expected_sample": expected_resource_positions.slice(0, 3), "actual_sample": actual_resources.slice(0, 3)})
		return
	await _return_to_menu(restored_43)
	var clean_menu: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_continue_button") != null and not bool(g.get("_match_started")), 3600)
	if clean_menu == null:
		_finish(false, "fresh_menu_continue_button_missing", {"checks": mismatch_checks})
		return
	(clean_menu.get("_start_continue_button") as Button).pressed.emit()
	var start_menu_restored: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and int(g.get("map_seed")) == 43, 3600)
	if start_menu_restored == null:
		_finish(false, "start_menu_continue_restore_failed", {"checks": mismatch_checks})
		return
	var menu_resource_positions := _sorted_group_positions("resources")
	var menu_resources_ok := _positions_equal(menu_resource_positions, expected_resource_positions)
	_report.merge({"passed": menu_resources_ok, "reason": "seed_mismatch_reload_and_fresh_menu_continue_verified" if menu_resources_ok else "fresh_menu_resource_layout_mismatch", "case": "mismatch", "checks": mismatch_checks, "mismatch_load_status": mismatch_status.text if is_instance_valid(mismatch_status) else "no_pause_status_label", "start_menu_continue_restored_seed": int(start_menu_restored.get("map_seed")), "start_menu_continue_resources_match": menu_resources_ok, "expected_resource_count": expected_resource_positions.size(), "natural_full_match_verified": false}, true)
	_finish(menu_resources_ok, str(_report.reason), {"expected_resource_count": expected_resource_positions.size(), "actual_resource_count": menu_resource_positions.size(), "expected_sample": expected_resource_positions.slice(0, 3), "actual_sample": menu_resource_positions.slice(0, 3)})

func _run_wave_boundaries() -> void:
	var menu: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 300)
	if menu == null:
		_finish(false, "wave_menu_timeout")
		return
	await _start_from_menu(menu, 42)
	var game: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 3600)
	if game == null:
		_finish(false, "wave_seed_42_start_timeout")
		return
	var fixture_file := FileAccess.open(_fixture_path, FileAccess.READ)
	if fixture_file == null:
		_finish(false, "wave_fixture_open_failed")
		return
	var base: Variant = JSON.parse_string(fixture_file.get_as_text())
	fixture_file.close()
	if not base is Dictionary:
		_finish(false, "wave_fixture_invalid")
		return
	var outcomes: Array[Dictionary] = []
	for mode in [0, 1]:
		var boundary: Dictionary = base.duplicate(true)
		boundary["map_seed"] = 42
		boundary["horde_mode"] = mode
		boundary["horde_wave"] = 5 if mode == 0 else 4
		boundary["horde_active"] = false
		boundary["horde_next_at"] = float(boundary.get("game_time", 0.0)) + 0.05
		boundary["horde_spawn_queue"] = []
		var save_file := FileAccess.open("user://aoelite3d_save.json", FileAccess.WRITE)
		if save_file == null:
			_finish(false, "wave_save_write_failed", {"mode": mode})
			return
		save_file.store_string(JSON.stringify(boundary))
		save_file.close()
		if get_tree().paused:
			await _send_key(KEY_ESCAPE)
		await _send_key(KEY_ESCAPE)
		if not get_tree().paused:
			_finish(false, "wave_pause_open_failed", {"mode": mode})
			return
		await _send_key(KEY_F9)
		if not await _wait_until(func() -> bool: return get_tree().paused and not bool(game.get("_start_operation_busy")), 360):
			_finish(false, "wave_fixture_restore_timeout", {"mode": mode})
			return
		var restored_mode := int(game.get("_horde_mode"))
		var restored_wave := int(game.get("_horde_wave"))
		await _send_key(KEY_ESCAPE)
		for _frame in 12: await get_tree().process_frame
		var next_wave := int(game.get("_horde_wave"))
		var due_boundary_spawned := bool(game.get("_horde_active")) and next_wave == (6 if mode == 0 else 5)
		if mode == 0:
			var endless_ok := restored_mode == 0 and restored_wave == 5 and due_boundary_spawned and not bool(game.get("_victorious"))
			outcomes.append({"mode": "endless", "restored_mode": restored_mode, "restored_wave": restored_wave, "post_tick_wave": next_wave, "due_boundary_spawned": due_boundary_spawned, "no_victory_at_wave_6": not bool(game.get("_victorious")), "passed": endless_ok})
			if not endless_ok:
				_finish(false, "endless_wave_6_restore_boundary_failed", {"outcomes": outcomes})
				return
		else:
			var challenge_spawn_ok := restored_mode == 1 and restored_wave == 4 and due_boundary_spawned
			var pending_spawn_queue: Array = game.get("_horde_spawn_queue")
			pending_spawn_queue.clear()
			for zombie in get_tree().get_nodes_in_group("soldiers"):
				if zombie.get("is_zombie") == true: zombie.queue_free()
			for _frame in 90: await get_tree().process_frame
			var challenge_wave := int(game.get("_horde_wave"))
			var challenge_no_six := challenge_wave == 5 and not bool(game.get("_horde_active"))
			var challenge_ok := challenge_spawn_ok and challenge_no_six and bool(game.get("_victorious"))
			outcomes.append({"mode": "five_wave_challenge", "restored_mode": restored_mode, "restored_wave": restored_wave, "post_tick_wave": next_wave, "boundary_five_spawned": challenge_spawn_ok, "synthetic_clear": true, "wave_after_clear": challenge_wave, "no_wave_6": challenge_no_six, "victory_after_synthetic_clear": bool(game.get("_victorious")), "passed": challenge_ok})
			if not challenge_ok:
				_finish(false, "challenge_wave_5_restore_boundary_failed", {"outcomes": outcomes})
				return
	_report.merge({"passed": true, "reason": "endless_and_challenge_restore_boundaries_verified", "case": "waves", "wave_boundaries": outcomes, "boundary_fixture_scope": "Controlled due-now save fixtures; Challenge wave-5 completion used a synthetic zombie clear. Natural full match completion was not run.", "natural_full_match_verified": false}, true)
	_finish(true, "endless_and_challenge_restore_boundaries_verified")

func _return_to_menu(game: Node) -> void:
	if not get_tree().paused:
		await _send_key(KEY_ESCAPE)
	var button := _find_button(game.get("_pause_layer"), "返回主菜单")
	if button != null:
		button.pressed.emit()

func _sorted_positions(items: Array) -> Array:
	var positions: Array = []
	for item in items:
		positions.append(item.get("pos", []))
	positions.sort_custom(func(a: Array, b: Array) -> bool: return _position_key(a) < _position_key(b))
	return positions

func _sorted_group_positions(group_name: String) -> Array:
	var positions: Array = []
	for node in get_tree().get_nodes_in_group(group_name):
		positions.append(_v3(node.global_position))
	positions.sort_custom(func(a: Array, b: Array) -> bool: return _position_key(a) < _position_key(b))
	return positions

func _position_key(pos: Array) -> String:
	return "%+.5f,%+.5f,%+.5f" % [float(pos[0]), float(pos[1]), float(pos[2])]

func _positions_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	var unmatched := b.duplicate(true)
	for position in a:
		var found := -1
		for i in unmatched.size():
			var same := true
			for axis in 3:
				if absf(float(position[axis]) - float(unmatched[i][axis])) > 0.001: same = false
			if same:
				found = i
				break
		if found < 0: return false
		unmatched.remove_at(found)
	return true

func _position_in_list(pos: Array, positions: Array) -> bool:
	for expected in positions:
		var same := true
		for axis in 3:
			if absf(float(pos[axis]) - float(expected[axis])) > 0.001: same = false
		if same: return true
	return false

func _all_checks(checks: Dictionary) -> bool:
	for value in checks.values():
		if not bool(value): return false
	return true

func _state_snapshot(game: Node) -> Dictionary:
	var first_villager: Node = null
	for worker in get_tree().get_nodes_in_group("villagers"):
		if str(worker.get("team")) == "player": first_villager = worker; break
	return {"units": _unit_counts(), "game_time": float(game.get("_game_time")), "clock_minutes": float(game.get("_clock_minutes")), "gather_target_valid": first_villager != null and is_instance_valid(first_villager.get("gather_target")), "resume_target_same": first_villager != null and first_villager.get("resume_resource") == first_villager.get("gather_target"), "resume_key": str(first_villager.get("resume_key")) if first_villager != null else "", "resources": {"wood": int(game.get("wood")), "meat": int(game.get("meat")), "stone": int(game.get("stone")), "gold": int(game.get("gold"))}, "horde_wave": int(game.get("_horde_wave")), "horde_mode": int(game.get("_horde_mode")), "paused": game.get_tree().paused}

func _unit_counts() -> Dictionary:
	var villagers := 0
	var player_soldiers := 0
	var zombies := 0
	for node in get_tree().get_nodes_in_group("villagers"):
		if node.get("alive") == true and str(node.get("team")) == "player": villagers += 1
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node.get("alive") != true: continue
		if node.get("is_zombie") == true: zombies += 1
		elif str(node.get("team")) == "player": player_soldiers += 1
	return {"villagers": villagers, "player_soldiers": player_soldiers, "enemy_zombies": zombies, "total": villagers + player_soldiers + zombies}

func _entity_ids() -> Array[int]:
	var ids: Array[int] = []
	for group_name in ["buildings", "resources", "villagers", "soldiers"]:
		for node in get_tree().get_nodes_in_group(group_name): ids.append(node.get_instance_id())
	return ids

func _freed_ids(ids: Array[int]) -> bool:
	for id in ids:
		if is_instance_id_valid(id): return false
	return true

func _find_building(kind: int) -> Node:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and int(building.get("kind")) == kind: return building
	return null

func _find_button(root: Node, label: String) -> Button:
	if root == null: return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text == label: return node as Button
		for child in node.get_children(): stack.append(child)
	return null

func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for _frame in max_frames:
		if predicate.call(): return true
		await get_tree().process_frame
	return false

func _wait_for_game(predicate: Callable, max_frames: int) -> Node:
	for _frame in max_frames:
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and predicate.call(game): return game
		await get_tree().process_frame
	return null

func _start_from_menu(game: Node, seed: int) -> void:
	(game.get("_seed_edit") as LineEdit).text = str(seed)
	(game.get("_start_begin_button") as Button).pressed.emit()
	await get_tree().process_frame

func _timer_count() -> int:
	return get_tree().root.find_children("*", "Timer", true, false).size()

func _group_counts() -> Dictionary:
	var result := {}
	for group_name in ["buildings", "resources", "villagers", "soldiers", "zombies"]:
		result[group_name] = get_tree().get_nodes_in_group(group_name).size()
	return result

func _groups_empty(groups: Dictionary) -> bool:
	for count in groups.values():
		if int(count) != 0: return false
	return true

func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _arg(args: Array, key: String, fallback: String) -> String:
	for arg in args:
		var value := str(arg)
		if value.begins_with("--" + key + "="): return value.get_slice("=", 1)
	return fallback

func _latest_duration(stage_name: String) -> int:
	var events: Array = Engine.get_meta(PROFILE.EVENTS_META, [])
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if str(event.get("stage", "")) == stage_name:
			return int(event.get("duration_usec", -1))
	return -1

func _finish(passed: bool, reason: String, extra: Dictionary = {}) -> void:
	_report["passed"] = passed
	_report["reason"] = reason
	_report["extra"] = extra
	_report["completed_usec"] = Time.get_ticks_usec()
	var file := FileAccess.open("user://restore_regression_%s.json" % _run_id, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	print("[restore-regression] ", JSON.stringify({"passed": passed, "reason": reason, "run_id": _run_id, "report": "user://restore_regression_%s.json" % _run_id}))
	get_tree().quit(0 if passed else 1)
