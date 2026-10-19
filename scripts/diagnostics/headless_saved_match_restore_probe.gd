extends Node
## Headless diagnostic for the production Continue button signal and restore path.
## It reads/writes only the isolated user data directory for this test process.

const RESULT_PATH := "user://headless_saved_match_restore_probe.json"
const ERROR_RESULT_PATH := "user://headless_saved_match_error_probe.json"
const RESTORED_COPY_PATH := "user://headless_restored_state.json"
const ADVANCED_COPY_PATH := "user://headless_advanced_state.json"

var phase := "continue_from_menu"
var elapsed := 0.0
var phase_elapsed := 0.0
var old_scene_id := 0
var game: Node
var source_data: Dictionary = {}
var report: Dictionary = {"mode": "headless_production_continue_signal", "ordinary_ui_verified": false}
var busy := false
var start_time := 0.0
var advanced_frames := 0
var last_loading_sample := -1.0
var error_probe_mode := false
var error_probe_case := "corrupt_json"
var economy_probe_mode := false
var forestry_probe_mode := false
var recovery_probe_mode := false
var recovery_observe_mode := false
var economy_sample_mark := 0
var economy_orders_sent := false
var recovery_started := false
var recovery_build_started := false
var recovery_farm: Node3D = null
var recovery_builder_ids: Array[int] = []
var recovery_food_worker_ids: Array[int] = []
var recovery_lumber_worker_ids: Array[int] = []
var recovery_attack_orders: Array[Dictionary] = []
var recovery_training_started := false
var recovery_training_record: Dictionary = {}
var recovery_last_sample := 0.0
var recovery_food_deposits := 0
var recovery_wood_deposits := 0
var recovery_wave2_seen := false
var recovery_wave2_peak_alive := 0

func configure_error_probe(enabled: bool, test_case: String) -> void:
	error_probe_mode = enabled
	error_probe_case = test_case

func configure_economy_probe(enabled: bool) -> void:
	economy_probe_mode = enabled

func configure_forestry_probe(enabled: bool) -> void:
	forestry_probe_mode = enabled

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	report["runtime"] = {"executable": OS.get_executable_path(), "headless": DisplayServer.get_name() == "headless", "driver_resource": get_script().resource_path}
	if DisplayServer.get_name() != "headless":
		_finish(false, "headless_runner_required", {})
		return
	if error_probe_mode:
		call_deferred("_run_error_path_probe")
		return
	var source_path := "user://aoelite3d_save.json"
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		_finish(false, "isolated_target_save_missing", {})
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_finish(false, "isolated_target_save_invalid_json", {})
		return
	source_data = parsed
	if recovery_probe_mode and float(source_data.get("game_time", 0.0)) >= 360.0 and int(source_data.get("horde_wave", 0)) >= 3:
		recovery_observe_mode = true
	report["mode"] = "logical_unresearched_wave2_continuation_observer" if recovery_observe_mode else "logical_unresearched_farm_rebuild_and_wave2_recovery" if recovery_probe_mode else "logical_forestry_research_and_economy_after_real_save_restore" if forestry_probe_mode else "logical_economy_recovery_after_real_save_restore" if economy_probe_mode else "headless_production_continue_signal"
	report["seed_save"] = {"path": ProjectSettings.globalize_path(source_path), "sha256": FileAccess.get_sha256(source_path), "snapshot": _snapshot_data(source_data)}

func _run_error_path_probe() -> void:
	await get_tree().process_frame
	game = get_tree().get_first_node_in_group("main_game")
	var button := _find_button(game.get("_start_layer") if game != null else null, "继续上次对局")
	var test_case := error_probe_case
	if game == null or button == null:
		_finish_error(false, test_case, "continue_menu_missing", {})
		return
	var scene_before: int = game.get_instance_id()
	var path := "user://aoelite3d_save.json"
	if test_case == "corrupt_json":
		var corrupt_file := FileAccess.open(path, FileAccess.WRITE)
		if corrupt_file != null:
			corrupt_file.store_string("{broken json")
			corrupt_file.close()
	elif test_case == "unsupported_version":
		var version_file := FileAccess.open(path, FileAccess.WRITE)
		if version_file != null:
			version_file.store_string("{\"version\":2,\"map_seed\":42,\"game_time\":278.9,\"resources\":{},\"entities\":{\"buildings\":[],\"resources\":[],\"villagers\":[],\"soldiers\":[]}}")
			version_file.close()
	elif test_case == "missing_file":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if test_case != "missing_file": button.disabled = false
	var before_hash := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var expected_status := ""
	match test_case:
		"corrupt_json": expected_status = "存档校验失败：文件不是有效的 JSON 对象。原存档未修改。"
		"unsupported_version": expected_status = "存档校验失败：不支持的存档版本。原存档未修改。"
		"read_locked": expected_status = "存档读取失败；当前对局保持不变。"
		"missing_file": expected_status = "没有可读取的存档；当前对局保持不变。"
		_:
			_finish_error(false, test_case, "unknown_error_case", {})
			return
	button.pressed.emit()
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var status := str(game.get("_start_status_label").text) if is_instance_valid(game.get("_start_status_label")) else ""
	var after_hash := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var expected_disabled: bool = test_case == "missing_file"
	var menu_retryable := not bool(game.get("_start_operation_busy")) and (button.disabled == expected_disabled)
	var checks := {"expected_message": status == expected_status, "same_scene": game.get_instance_id() == scene_before, "menu_retryable": menu_retryable, "save_unchanged": before_hash == after_hash, "duplicate_submit_ignored": game.get("_start_operation_busy") == false}
	var success := true
	for value in checks.values(): success = success and bool(value)
	_finish_error(success, test_case, "error_path_handled" if success else "error_path_check_failed", {"checks": checks, "expected_status": expected_status, "actual_status": status, "scene_id_before": scene_before, "scene_id_after": game.get_instance_id(), "save_sha256_before": before_hash, "save_sha256_after": after_hash, "continue_button_disabled_after": button.disabled, "signal_emit_count": 2})

func _finish_error(success: bool, test_case: String, reason: String, extra: Dictionary) -> void:
	var output := FileAccess.open(ERROR_RESULT_PATH, FileAccess.WRITE)
	var error_report := {"mode": "production_continue_error_path", "case": test_case, "success": success, "reason": reason, "ordinary_ui_verified": false, "runtime": {"executable": OS.get_executable_path(), "headless": DisplayServer.get_name() == "headless", "driver_resource": get_script().resource_path}}
	error_report.merge(extra, true)
	if output != null:
		output.store_string(JSON.stringify(error_report, "\t"))
		output.close()
	print("[HEADLESS_SAVED_MATCH_ERROR] ", JSON.stringify(error_report))
	get_tree().quit(0 if success else 1)

func _process(delta: float) -> void:
	if error_probe_mode:
		return
	elapsed += delta
	phase_elapsed += delta
	game = get_tree().get_first_node_in_group("main_game")
	if busy or report.has("success"):
		return
	if elapsed > 180.0:
		_finish(false, "headless_restore_probe_timeout", {"phase": phase})
		return
	match phase:
		"continue_from_menu":
			if game != null and game.get("_start_layer") != null:
				var button := _find_button(game.get("_start_layer"), "继续上次对局")
				if button == null or button.disabled:
					_finish(false, "continue_button_unavailable", {"disabled": button.disabled if button else true})
					return
				var callbacks: Array[String] = []
				for connection in button.pressed.get_connections():
					var callback: Callable = connection.get("callable", Callable())
					callbacks.append(String(callback.get_method()))
				old_scene_id = game.get_instance_id()
				report["menu_continue"] = {"control_path": str(button.get_path()), "rect": _rect(button), "disabled": button.disabled, "pressed_connection_count": button.pressed.get_connections().size(), "callbacks": callbacks, "scene_id_before": old_scene_id, "viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]}
				if not callbacks.has("_continue_saved_match"):
					_finish(false, "continue_button_callback_missing", {})
					return
				busy = true
				button.pressed.emit()
				button.pressed.emit()
				report["menu_continue"]["pressed_emitted"] = true
				report["menu_continue"]["signal_emit_count"] = 2
				report["menu_continue"]["callback"] = "_continue_saved_match"
				phase = "wait_restore"
				phase_elapsed = 0.0
				busy = false
		"wait_restore":
			if game != null and game.get("_loading_label") != null and is_instance_valid(game.get("_loading_label")) and phase_elapsed - last_loading_sample >= 0.25:
				last_loading_sample = phase_elapsed
				if not report.has("loading_samples"):
					report["loading_samples"] = []
				report["loading_samples"].append({"elapsed": phase_elapsed, "text": str(game.get("_loading_label").text), "progress": float(game.get("_loading_progress").value) if game.get("_loading_progress") != null else -1.0})
			if game != null and game.get_instance_id() != old_scene_id and bool(game.get("_match_started")):
				var snapshot := _snapshot_game(game)
				if not bool(game.call("_save_match", RESTORED_COPY_PATH)):
					_finish(false, "restored_snapshot_save_failed", {})
					return
				var restored_copy := _read_json(RESTORED_COPY_PATH)
				var comparison := _compare_to_seed(source_data, snapshot, restored_copy)
				report["restore"] = {"snapshot": snapshot, "matches_source": comparison, "restore_log_state": "new scene instance with _match_started=true"}
				if not comparison.get("ok", false):
					_finish(false, "restored_state_differs_from_real_save", {"comparison": comparison})
					return
				report["restored_copy"] = {"path": RESTORED_COPY_PATH, "snapshot": _snapshot_data(restored_copy), "matches_source": _compare_data(source_data, restored_copy)}
				var resume_button := _find_button(game.get("_pause_layer"), "继续游戏")
				if resume_button == null:
					_finish(false, "restored_pause_resume_button_missing", {})
					return
				resume_button.pressed.emit()
				start_time = float(game.get("_game_time"))
				report["resume_button"] = {"rect": _rect(resume_button), "pressed_connection_count": resume_button.pressed.get_connections().size(), "callback": "_resume_from_pause"}
				phase = "advance_naturally"
				phase_elapsed = 0.0
			elif phase_elapsed > 120.0:
				var status := ""
				if game != null and game.get("_start_status_label") != null:
					status = str(game.get("_start_status_label").text)
				_finish(false, "continue_restore_timeout", {"start_status": status, "same_scene": game != null and game.get_instance_id() == old_scene_id})
		"advance_naturally":
			advanced_frames += 1
			if game == null or not is_instance_valid(game):
				_finish(false, "game_scene_lost_after_resume", {})
				return
			if recovery_probe_mode:
				_process_recovery_probe(game)
				return
			if economy_probe_mode or forestry_probe_mode:
				if not economy_orders_sent:
					if forestry_probe_mode:
						var before_research := {"wood": int(game.get("wood")), "meat": int(game.get("meat"))}
						game.call("_on_research_forestry")
						var multipliers: Array[float] = []
						for worker in get_tree().get_nodes_in_group("villagers"):
							if is_instance_valid(worker) and str(worker.get("team")) == "player":
								multipliers.append(float(worker.get("wood_gather_multiplier")))
						report["forestry_research"] = {"invoked_production_handler": true, "resources_before": before_research, "resources_after": {"wood": int(game.get("wood")), "meat": int(game.get("meat"))}, "researched": game.get("research").call("has_technology", "improved_axes"), "player_villager_wood_multipliers": multipliers}
					_assign_lumber_orders(game)
					economy_orders_sent = true
				_capture_economy_sample(game)
			if float(game.get("_game_time")) >= 290.0 or phase_elapsed > 90.0:
				game.call("_set_pause_menu_open", true)
				if not get_tree().paused:
					_finish(false, "pause_after_advance_failed", {})
					return
				if not bool(game.call("_save_match", ADVANCED_COPY_PATH)):
					_finish(false, "advanced_snapshot_save_failed", {})
					return
				var advanced_copy := _read_json(ADVANCED_COPY_PATH)
				var after := _snapshot_data(advanced_copy)
				report["natural_advance"] = {"game_time_before": start_time, "game_time_after": after.get("game_time", 0.0), "frames": advanced_frames, "wall_seconds": phase_elapsed, "snapshot": after, "reached_second_wave": int(after.get("horde_wave", 0)) >= 2}
				if economy_probe_mode or forestry_probe_mode:
					report["natural_advance"]["economy_samples"] = report.get("economy_samples", [])
					report["natural_advance"]["defeated"] = bool(game.get("_defeated"))
					report["natural_advance"]["farm_restore_affordable"] = int(after.resources.wood) >= 75
					report["natural_advance"]["farm_reseed_affordable"] = int(after.resources.wood) >= 25
					if forestry_probe_mode:
						report["natural_advance"]["researched_techs"] = advanced_copy.get("researched_techs", [])
				var success := float(after.get("game_time", 0.0)) > start_time and int(after.get("horde_wave", 0)) >= 2 and bool(report.restore.matches_source.ok)
				_finish(success, "natural_second_wave_reached" if success else "natural_second_wave_not_reached", {})

func _assign_lumber_orders(target: Node) -> void:
	var workers := 0
	var assigned: Array[Dictionary] = []
	var available: Array = []
	for candidate in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(candidate) and int(candidate.get("kind")) == 0 and int(candidate.get("amount")) > 0:
			available.append(candidate)
	for villager in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(villager) or not bool(villager.get("alive")) or str(villager.get("team")) != "player":
			continue
		var nearest: Node3D = null
		var nearest_distance := INF
		for node in available:
			var distance: float = villager.global_position.distance_to(node.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = node
		if nearest != null:
			villager.call("command_gather", nearest)
			workers += 1
			assigned.append({"wood_node": nearest.name, "initial_node_stock": int(nearest.get("amount")), "distance": nearest_distance})
	report["economy_probe"] = {"logical_investigation": true, "interaction_layer": "production command_gather methods; no mouse UI", "starting_resources": {"wood": int(target.get("wood")), "meat": int(target.get("meat"))}, "farm_count": get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and int(b.get("kind")) == 2 and bool(b.get("alive"))).size(), "living_player_villagers_ordered_to_lumber": workers, "assignments": assigned}

func _capture_economy_sample(target: Node) -> void:
	var elapsed_game := float(target.get("_game_time")) - start_time
	var checkpoints := [5.0, 15.0, 25.0, 31.0, 36.0]
	if economy_sample_mark >= checkpoints.size() or elapsed_game < float(checkpoints[economy_sample_mark]):
		return
	var snapshot := _snapshot_game(target)
	var lumber: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and int(node.get("kind")) == 0:
			lumber.append({"amount": int(node.get("amount")), "position": _vec_to_array(node.global_position)})
	if not report.has("economy_samples"):
		report["economy_samples"] = []
	report["economy_samples"].append({"elapsed_game_seconds": elapsed_game, "game_time": snapshot.game_time, "resources": snapshot.resources, "alive_enemy": snapshot.alive_enemy, "wave": snapshot.horde_wave, "villagers_alive": snapshot.villager_hp.size(), "wood_node_stocks": lumber})
	economy_sample_mark += 1

func _process_recovery_probe(target: Node) -> void:
	if not recovery_started:
		if recovery_observe_mode:
			_start_recovery_observation(target)
		else:
			_start_recovery_orders(target)
	if not recovery_observe_mode and not recovery_build_started and int(target.get("wood")) >= 75:
		_start_farm_rebuild(target)
	if not recovery_observe_mode and recovery_farm != null and is_instance_valid(recovery_farm):
		if bool(recovery_farm.get("is_complete")) and recovery_food_worker_ids.is_empty():
			for worker_id in recovery_builder_ids:
				var worker := instance_from_id(worker_id) as Node
				if worker != null and is_instance_valid(worker) and bool(worker.get("alive")):
					worker.call("command_gather", recovery_farm)
					recovery_food_worker_ids.append(worker_id)
			for worker_id in recovery_lumber_worker_ids:
				var worker := instance_from_id(worker_id) as Node
				if worker != null and is_instance_valid(worker) and bool(worker.get("alive")):
					var nearest := _nearest_wood_for(worker)
					if nearest != null:
						worker.call("command_gather", nearest)
			report["farm_complete"] = {"game_time": float(target.get("_game_time")), "farm_instance_id": recovery_farm.get_instance_id(), "farm_node_name": recovery_farm.name, "complete": true, "meat_stock": int(recovery_farm.get("meat_stock")), "food_worker_instance_ids": recovery_food_worker_ids.duplicate(), "lumber_worker_instance_ids": recovery_lumber_worker_ids.duplicate()}
	if not recovery_observe_mode and (recovery_farm == null or not is_instance_valid(recovery_farm) or bool(recovery_farm.get("is_complete"))):
		_try_paid_soldier_training(target)
	var now := float(target.get("_game_time"))
	if now - recovery_last_sample >= 5.0:
		recovery_last_sample = now
		report["recovery_samples"].append(_recovery_snapshot(target))
	if bool(target.get("_defeated")):
		_finish_recovery_probe(target, "defeat")
		return
	var wave2_count := _alive_enemies_by_wave(2)
	if wave2_count > 0:
		recovery_wave2_seen = true
		recovery_wave2_peak_alive = maxi(recovery_wave2_peak_alive, wave2_count)
	if recovery_wave2_seen and wave2_count == 0:
		_finish_recovery_probe(target, "wave2_cleared")
		return
	if recovery_observe_mode and now >= float(target.get("_horde_next_at")):
		_finish_recovery_probe(target, "wave2_unresolved_at_next_wave")
		return
	if not recovery_observe_mode and now >= 360.0:
		_finish_recovery_probe(target, "wave2_unresolved_at_wave3")

func _start_recovery_observation(target: Node) -> void:
	recovery_started = true
	recovery_farm = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and int(building.get("kind")) == 2:
			recovery_farm = building
			break
	recovery_build_started = true
	recovery_training_started = true
	recovery_wave2_seen = _alive_enemies_by_wave(2) > 0
	report["recovery_samples"] = []
	report["recovery_plan"] = {"logical_investigation": true, "interaction_layer": "production Continue and Resume only; no new commands, no mouse UI", "observer_only": true, "research_enabled": false, "continued_from_time": float(target.get("_game_time")), "horde_wave": int(target.get("_horde_wave")), "wave1_alive": _alive_enemies_by_wave(1), "wave2_alive": _alive_enemies_by_wave(2), "wave3_alive": _alive_enemies_by_wave(3), "farm_present": recovery_farm != null, "starting_resources": {"wood": int(target.get("wood")), "meat": int(target.get("meat"))}}

func _start_recovery_orders(target: Node) -> void:
	recovery_started = true
	report["recovery_samples"] = []
	report["recovery_plan"] = {"logical_investigation": true, "interaction_layer": "production Continue/pause buttons, command_gather, _on_build_kind + _try_place, command_build, command_attack_unit, and _queue_train methods; no mouse UI", "research_enabled": false, "initial_time": float(target.get("_game_time")), "next_wave_at": float(target.get("_horde_next_at")), "starting_resources": {"wood": int(target.get("wood")), "meat": int(target.get("meat"))}, "farm_originally_present": false}
	var workers: Array[Node] = []
	for worker in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and bool(worker.get("alive")) and str(worker.get("team")) == "player":
			workers.append(worker)
			var deposited := Callable(self, "_on_recovery_deposited").bind(worker.get_instance_id())
			if not worker.is_connected("deposited", deposited):
				worker.connect("deposited", deposited)
	var original_tc := target.call("_find_tc") as Node3D
	var original_barracks: Node3D = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and int(building.get("kind")) == 12:
			original_barracks = building
	var enemies: Array[Node3D] = []
	for enemy in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(enemy) and bool(enemy.get("alive")) and str(enemy.get("team")) == "enemy":
			enemies.append(enemy)
	var player_soldiers: Array[Node3D] = []
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(soldier) and bool(soldier.get("alive")) and str(soldier.get("team")) == "player":
			player_soldiers.append(soldier)
	for i in range(player_soldiers.size()):
		if enemies.is_empty():
			break
		var target_index := mini(i * enemies.size() / maxi(player_soldiers.size(), 1), enemies.size() - 1)
		var enemy: Node3D = enemies[target_index]
		player_soldiers[i].call("command_attack_unit", enemy)
		recovery_attack_orders.append({"soldier_instance_id": player_soldiers[i].get_instance_id(), "enemy_instance_id": enemy.get_instance_id(), "enemy_wave_id": int(enemy.get("horde_wave_id"))})
	var worker_orders: Array[Dictionary] = []
	for worker in workers:
		var node := _nearest_wood_for(worker)
		if node != null:
			worker.call("command_gather", node)
			recovery_lumber_worker_ids.append(worker.get_instance_id())
			worker_orders.append({"villager_instance_id": worker.get_instance_id(), "resource_instance_id": node.get_instance_id(), "resource_stock": int(node.get("amount")), "distance": worker.global_position.distance_to(node.global_position)})
	report["initial_commands"] = {"farm_was_absent": true, "town_center_hp": float(original_tc.get("hp")) if original_tc else -1.0, "barracks_hp": float(original_barracks.get("hp")) if original_barracks else -1.0, "player_soldiers": player_soldiers.size(), "existing_wave1_enemies": enemies.size(), "attack_orders": recovery_attack_orders, "wood_gather_orders": worker_orders}

func _start_farm_rebuild(target: Node) -> void:
	var workers: Array[Node] = []
	for worker in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and bool(worker.get("alive")) and str(worker.get("team")) == "player":
			workers.append(worker)
	if workers.size() < 2:
		return
	var positions := [Vector3(-9.0, 0.0, 7.0), Vector3(-10.0, 0.0, 10.0), Vector3(-10.0, 0.0, 4.0), Vector3(-5.0, 0.0, 10.0), Vector3(-12.0, 0.0, 7.0)]
	var reference := Vector3(-9.0, 0.0, 7.0)
	workers.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.distance_squared_to(reference) < b.global_position.distance_squared_to(reference))
	recovery_builder_ids = [workers[0].get_instance_id(), workers[1].get_instance_id()]
	recovery_lumber_worker_ids.clear()
	for i in range(2, workers.size()):
		recovery_lumber_worker_ids.append(workers[i].get_instance_id())
	target.call("_clear_selection")
	for worker_id in recovery_builder_ids:
		target.call("_add_to_selection", instance_from_id(worker_id))
	var wood_before := int(target.get("wood"))
	target.call("_on_build_kind", 2)
	var placed_at := Vector3(INF, 0, INF)
	for candidate in positions:
		if bool(target.call("_placement_valid_at", candidate)):
			target.call("_try_place", candidate)
			placed_at = candidate
			break
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and int(building.get("kind")) == 2:
			recovery_farm = building
			break
	recovery_build_started = recovery_farm != null
	if recovery_farm != null:
		report["farm_build_order"] = {"game_time": float(target.get("_game_time")), "wood_before": wood_before, "wood_after": int(target.get("wood")), "original_cost_wood": 75, "cost_deducted": wood_before - int(target.get("wood")), "placement": _vec_to_array(placed_at), "farm_instance_id": recovery_farm.get_instance_id(), "farm_node_name": recovery_farm.name, "complete_at_placement": bool(recovery_farm.get("is_complete")), "builders": recovery_builder_ids.duplicate(), "lumber_workers": recovery_lumber_worker_ids.duplicate()}
	else:
		report["farm_build_order"] = {"game_time": float(target.get("_game_time")), "wood_before": wood_before, "placement_failed": true, "place_kind_after_order": int(target.get("place_kind")), "candidate_positions": positions.map(func(p: Vector3): return _vec_to_array(p))}

func _nearest_wood_for(worker: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and int(node.get("kind")) == 0 and int(node.get("amount")) > 0:
			var distance: float = worker.global_position.distance_to(node.global_position)
			if distance < best_distance:
				best = node
				best_distance = distance
	return best

func _try_paid_soldier_training(target: Node) -> void:
	if recovery_training_started:
		return
	var barracks: Node3D = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and int(building.get("kind")) == 12 and bool(building.get("is_complete")):
			barracks = building
			break
	if barracks == null or int(target.get("meat")) < 60 or int(target.get("wood")) < 20:
		return
	target.call("_clear_selection")
	target.call("_add_to_selection", barracks)
	var resources_before := {"meat": int(target.get("meat")), "wood": int(target.get("wood"))}
	var army_before := _alive_player_soldiers()
	target.call("_queue_train", "soldier")
	if Array(barracks.get("train_queue")).has("soldier"):
		recovery_training_started = true
		recovery_training_record = {"game_time": float(target.get("_game_time")), "resources_before": resources_before, "resources_after": {"meat": int(target.get("meat")), "wood": int(target.get("wood"))}, "expected_cost": {"meat": 60, "wood": 20}, "train_queue": Array(barracks.get("train_queue")).duplicate(), "train_paid": bool(barracks.get("train_paid")), "train_paused": bool(barracks.get("train_paused")), "soldiers_before": army_before, "soldiers_after_queue": _alive_player_soldiers(), "barracks_instance_id": barracks.get_instance_id()}

func _recovery_snapshot(target: Node) -> Dictionary:
	var wave_counts := {"1": _alive_enemies_by_wave(1), "2": _alive_enemies_by_wave(2), "3": _alive_enemies_by_wave(3)}
	var buildings: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and str(building.get("team")) == "player":
			buildings.append({"instance_id": building.get_instance_id(), "kind": int(building.get("kind")), "hp": float(building.get("hp")), "complete": bool(building.get("is_complete")), "meat_stock": int(building.get("meat_stock")), "train_queue": Array(building.get("train_queue")).duplicate(), "train_paid": bool(building.get("train_paid")), "train_paused": bool(building.get("train_paused"))})
	var counts := {"villagers": 0, "soldiers": _alive_player_soldiers()}
	var soldier_hp: Array[float] = []
	for worker in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and bool(worker.get("alive")) and str(worker.get("team")) == "player":
			counts.villagers += 1
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(soldier) and bool(soldier.get("alive")) and str(soldier.get("team")) == "player":
			soldier_hp.append(float(soldier.get("hp")))
	soldier_hp.sort()
	return {"game_time": float(target.get("_game_time")), "elapsed_since_restore": float(target.get("_game_time")) - start_time, "resources": {"wood": int(target.get("wood")), "meat": int(target.get("meat"))}, "food_deposited_since_restore": recovery_food_deposits, "wood_deposited_since_restore": recovery_wood_deposits, "horde_wave": int(target.get("_horde_wave")), "next_wave_at": float(target.get("_horde_next_at")), "alive_enemies_by_wave": wave_counts, "alive_player_units": counts, "player_soldier_hp": soldier_hp, "buildings": buildings, "farm_is_complete": recovery_farm != null and is_instance_valid(recovery_farm) and bool(recovery_farm.get("is_complete")), "farm_meat_stock": int(recovery_farm.get("meat_stock")) if recovery_farm != null and is_instance_valid(recovery_farm) else -1}

func _alive_enemies_by_wave(wave_id: int) -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(enemy) and bool(enemy.get("alive")) and str(enemy.get("team")) == "enemy" and int(enemy.get("horde_wave_id")) == wave_id:
			count += 1
	return count

func _alive_player_soldiers() -> int:
	var count := 0
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(soldier) and bool(soldier.get("alive")) and str(soldier.get("team")) == "player":
			count += 1
	return count

func _on_recovery_deposited(key: String, amount: int, _worker_id: int) -> void:
	if key == "meat": recovery_food_deposits += amount
	elif key == "wood": recovery_wood_deposits += amount

func _finish_recovery_probe(target: Node, outcome: String) -> void:
	if not bool(target.get("_defeated")) and not get_tree().paused:
		target.call("_set_pause_menu_open", true)
	var saved_ok := bool(target.call("_save_match", ADVANCED_COPY_PATH))
	var saved_data := _read_json(ADVANCED_COPY_PATH) if saved_ok else {}
	var saved_farm: Dictionary = {}
	for item in saved_data.get("entities", {}).get("buildings", []):
		if int(item.get("kind", -1)) == 2 and str(item.get("team", "")) == "player":
			saved_farm = item
			break
	var final_snapshot := _recovery_snapshot(target)
	var final_counts := {"wave1_remaining": _alive_enemies_by_wave(1), "wave2_remaining": _alive_enemies_by_wave(2), "wave2_peak_alive_observed": recovery_wave2_peak_alive, "wave3_remaining": _alive_enemies_by_wave(3), "spawn_queue_wave_id": int(target.get("_horde_spawn_wave_id")), "spawn_queue_remaining": Array(target.get("_horde_spawn_queue")).size()}
	report["recovery_result"] = {"outcome": outcome, "defeated": bool(target.get("_defeated")), "game_time": float(target.get("_game_time")), "elapsed_since_restore": float(target.get("_game_time")) - start_time, "food_net_change": int(target.get("meat")) - int(source_data.get("resources", {}).get("meat", 0)), "food_deposited_since_restore": recovery_food_deposits, "wood_deposited_since_restore": recovery_wood_deposits, "farm_saved_entity_id": str(saved_farm.get("id", "")), "farm_instance_id": recovery_farm.get_instance_id() if recovery_farm != null and is_instance_valid(recovery_farm) else -1, "farm_complete": bool(saved_farm.get("complete", false)), "farm_meat_stock": int(saved_farm.get("meat_stock", 0)), "farm_build_order": report.get("farm_build_order", {}), "farm_complete_event": report.get("farm_complete", {}), "builder_instance_ids": recovery_builder_ids, "food_worker_instance_ids": recovery_food_worker_ids, "lumber_worker_instance_ids": recovery_lumber_worker_ids, "training": recovery_training_record, "alive_player_soldiers": _alive_player_soldiers(), "player_soldier_hp": final_snapshot.get("player_soldier_hp", []), "town_center_hp": _building_hp(target, 0), "barracks_hp": _building_hp(target, 12), "enemy_wave_counts": final_counts, "final_snapshot": final_snapshot, "paused": get_tree().paused, "advanced_save_written": saved_ok}
	report["recovery_samples"] = report.get("recovery_samples", [])
	_finish(true, "recovery_probe_%s" % outcome, {})

func _building_hp(target: Node, kind: int) -> float:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and str(building.get("team")) == "player" and int(building.get("kind")) == kind:
			return float(building.get("hp"))
	return 0.0

func _find_button(parent: Node, text_part: String) -> Button:
	if parent == null:
		return null
	for child in parent.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.is_visible_in_tree() and button.text.contains(text_part):
			return button
	return null

func _rect(control: Control) -> Array:
	var rect := control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _snapshot_game(target: Node) -> Dictionary:
	var soldier_hp: Array[float] = []
	var villager_hp: Array[float] = []
	var buildings: Array[Dictionary] = []
	var enemy_count := 0
	var relations := {"attack": 0, "gather": 0, "drop": 0, "resume": 0, "build": 0, "orders": 0, "train_queue": 0}
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(soldier) or not bool(soldier.get("alive")):
			continue
		if str(soldier.get("team")) == "player":
			soldier_hp.append(float(soldier.get("hp")))
			if _has_target(soldier.get("attack_target")): relations.attack += 1
			relations.orders += soldier.get("order_queue").size()
		else:
			enemy_count += 1
			if _has_target(soldier.get("attack_target")): relations.attack += 1
			relations.orders += soldier.get("order_queue").size()
	for villager in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(villager) or not bool(villager.get("alive")) or str(villager.get("team")) != "player":
			continue
		villager_hp.append(float(villager.get("hp")))
		for pair in [["attack", "attack_target"], ["gather", "gather_target"], ["drop", "drop_target"], ["resume", "resume_resource"], ["build", "build_site"]]:
			if _has_target(villager.get(pair[1])): relations[pair[0]] += 1
		relations.orders += villager.get("order_queue").size()
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not bool(building.get("alive")) or str(building.get("team")) != "player":
			continue
		var queue: Array = building.get("train_queue").duplicate()
		relations.train_queue += queue.size()
		buildings.append({"kind": int(building.get("kind")), "hp": float(building.get("hp")), "train_queue": queue, "train_timer": float(building.get("train_timer")), "train_paid": bool(building.get("train_paid"))})
	soldier_hp.sort()
	villager_hp.sort()
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.kind) < int(b.kind))
	return {"map_seed": int(target.get("map_seed")), "mode": int(target.get("_horde_mode")), "game_time": float(target.get("_game_time")), "paused": get_tree().paused, "horde_wave": int(target.get("_horde_wave")), "horde_next_at": float(target.get("_horde_next_at")), "resources": {"wood": int(target.get("wood")), "meat": int(target.get("meat")), "stone": int(target.get("stone")), "gold": int(target.get("gold"))}, "soldier_hp": soldier_hp, "villager_hp": villager_hp, "buildings": buildings, "target_relations": relations, "alive_enemy": enemy_count}

func _snapshot_data(data: Dictionary) -> Dictionary:
	var entities: Dictionary = data.get("entities", {})
	var soldiers: Array[float] = []
	var villagers: Array[float] = []
	var buildings: Array[Dictionary] = []
	var enemy_count := 0
	var relations := {"attack": 0, "gather": 0, "drop": 0, "resume": 0, "build": 0, "orders": 0, "train_queue": 0}
	for group_name in ["buildings", "villagers", "soldiers"]:
		for entity in entities.get(group_name, []):
			for field in ["attack_id", "gather_id", "drop_id", "resume_id", "build_id"]:
				if not str(entity.get(field, "")).is_empty():
					var key: String = str(field).trim_suffix("_id")
					relations[key] = int(relations.get(key, 0)) + 1
			relations.orders += entity.get("orders", []).size()
	for entity in entities.get("soldiers", []):
		if bool(entity.get("alive", true)) and str(entity.get("team", "")) == "player": soldiers.append(float(entity.get("hp", 0.0)))
		elif bool(entity.get("alive", true)) and str(entity.get("team", "")) == "enemy": enemy_count += 1
	for entity in entities.get("villagers", []):
		if bool(entity.get("alive", true)) and str(entity.get("team", "")) == "player": villagers.append(float(entity.get("hp", 0.0)))
	for entity in entities.get("buildings", []):
		if bool(entity.get("alive", true)) and str(entity.get("team", "")) == "player":
			var queue: Array = entity.get("train_queue", [])
			relations.train_queue += queue.size()
			buildings.append({"kind": int(entity.get("kind", -1)), "hp": float(entity.get("hp", 0.0)), "train_queue": queue, "train_timer": float(entity.get("train_timer", 0.0)), "train_paid": bool(entity.get("train_paid", false))})
	soldiers.sort();villagers.sort();buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.kind) < int(b.kind))
	var resource_data: Dictionary = data.get("resources", {})
	var resources := {"wood": int(resource_data.get("wood", 0)), "meat": int(resource_data.get("meat", 0)), "stone": int(resource_data.get("stone", 0)), "gold": int(resource_data.get("gold", 0))}
	return {"map_seed": int(data.get("map_seed", 0)), "mode": int(data.get("horde_mode", 0)), "game_time": float(data.get("game_time", 0.0)), "paused": bool(data.get("paused", false)), "horde_wave": int(data.get("horde_wave", 0)), "horde_next_at": float(data.get("horde_next_at", 0.0)), "resources": resources, "soldier_hp": soldiers, "villager_hp": villagers, "buildings": buildings, "target_relations": relations, "alive_enemy": enemy_count}

func _compare_to_seed(seed: Dictionary, restored: Dictionary, restored_data: Dictionary) -> Dictionary:
	var expected := _snapshot_data(seed)
	var navigation := _compare_navigation(seed, restored_data)
	var checks := {"seed": restored.map_seed == 42 and restored.map_seed == expected.map_seed, "mode": restored.mode == 1 and restored.mode == expected.mode, "time": absf(restored.game_time - expected.game_time) < 0.001, "paused": restored.paused and restored.paused == expected.paused, "next_wave": absf(restored.horde_next_at - expected.horde_next_at) < 0.001, "resources": restored.resources == expected.resources, "soldier_hp": restored.soldier_hp == expected.soldier_hp, "villager_hp": restored.villager_hp == expected.villager_hp, "buildings_and_queues": restored.buildings == expected.buildings, "target_counts_and_queues": restored.target_relations == expected.target_relations, "navigation_restore_semantics": bool(navigation.get("ok", false)), "enemy_count_matches": restored.alive_enemy == expected.alive_enemy}
	var ok := true
	for value in checks.values(): ok = ok and bool(value)
	return {"ok": ok, "checks": checks, "expected": expected, "navigation": navigation}

func _compare_navigation(seed: Dictionary, restored: Dictionary) -> Dictionary:
	var source_villagers: Dictionary = {}
	var restored_villagers: Dictionary = {}
	for item in seed.get("entities", {}).get("villagers", []): source_villagers[str(item.get("id", ""))] = item
	for item in restored.get("entities", {}).get("villagers", []): restored_villagers[str(item.get("id", ""))] = item
	var differences: Array[Dictionary] = []
	var unexpected: Array[String] = []
	for identifier in source_villagers:
		if not restored_villagers.has(identifier):
			unexpected.append("missing_restored_villager:%s" % identifier)
			continue
		var source: Dictionary = source_villagers[identifier]
		var actual: Dictionary = restored_villagers[identifier]
		var source_move := _array_to_vec(source.get("move_target", []))
		var restored_move := _array_to_vec(actual.get("move_target", []))
		var source_goal := _array_to_vec(source.get("goal", source.get("move_target", [])))
		var restored_goal := _array_to_vec(actual.get("goal", actual.get("move_target", [])))
		if source_move.distance_to(restored_move) <= 0.001 and source_goal.distance_to(restored_goal) <= 0.001:
			continue
		var inactive: bool = int(source.get("state", -1)) == 0 and source.get("orders", []).is_empty()
		for target_field in ["attack_id", "gather_id", "drop_id", "resume_id", "build_id"]:
			inactive = inactive and str(source.get(target_field, "")).is_empty()
		var stale_waypoint_normalized: bool = inactive and source_goal.distance_to(restored_goal) <= 0.001 and restored_move.distance_to(restored_goal) <= 0.001 and source_move.distance_to(source_goal) <= 0.5
		var difference := {"id": identifier, "state": int(source.get("state", -1)), "source_move_target": _vec_to_array(source_move), "source_goal": _vec_to_array(source_goal), "restored_move_target": _vec_to_array(restored_move), "restored_goal": _vec_to_array(restored_goal), "source_waypoint_to_goal_distance": source_move.distance_to(source_goal), "idle_without_targets_or_queued_orders": inactive, "classification": "idle_stale_waypoint_replaced_by_saved_goal" if stale_waypoint_normalized else "unexpected_navigation_change"}
		differences.append(difference)
		if not stale_waypoint_normalized:
			unexpected.append("unexpected_navigation_change:%s" % identifier)
	return {"ok": unexpected.is_empty(), "semantics": "Only idle villagers with no target references or queued orders may normalize a stale live waypoint to their unchanged saved goal; the source waypoint must be within 0.5 world units. This field is inert while idle, so no move or work command is replayed.", "tolerance_world_units": 0.5, "difference_count": differences.size(), "differences": differences, "unexpected": unexpected}

func _array_to_vec(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)

func _vec_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _compare_data(seed: Dictionary, copy: Dictionary) -> Dictionary:
	var a := _snapshot_data(seed)
	var b := _snapshot_data(copy)
	return {"same_time": absf(a.game_time - b.game_time) < 0.001, "same_seed": a.map_seed == b.map_seed, "same_mode": a.mode == b.mode, "same_resources": a.resources == b.resources, "same_units": a.soldier_hp == b.soldier_hp and a.villager_hp == b.villager_hp, "same_buildings_queues": a.buildings == b.buildings, "same_targets_queues": a.target_relations == b.target_relations}

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _has_target(value: Variant) -> bool:
	return value != null and is_instance_valid(value)

func _finish(success: bool, reason: String, extra: Dictionary) -> void:
	if report.has("success"):
		return
	report["success"] = success
	report["reason"] = reason
	report.merge(extra, true)
	var output := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("[HEADLESS_SAVED_MATCH_RESTORE] ", JSON.stringify(report))
	get_tree().quit(0 if success else 1)
