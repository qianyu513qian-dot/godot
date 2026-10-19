extends Node
## One-shot natural recovery sample from a copied production F5 checkpoint.
## It does not inject game state or save over the supplied checkpoint.

const REPORT_PATH := "user://natural_checkpoint_recovery_probe.json"
const Catalog := preload("res://scripts/building_catalog.gd")
const VillagerScript := preload("res://scripts/villager.gd")

var report: Dictionary = {
	"schema": 1, "passed": false, "events": [], "samples": [],
	"runtime": {"pid": OS.get_process_id(), "headless": DisplayServer.get_name() == "headless", "time_scale": Engine.time_scale, "executable": OS.get_executable_path(), "user_data_dir": OS.get_user_data_dir(), "engine": Engine.get_version_info().string},
	"injections": []
}
var game: Node3D
var wall_deadline_msec := 0
var game_start := 0.0
var next_sample_at := 0.0
var last_villager_count := -1
var recovery_attempted := false
var replacement: Node3D
var wood_node: Node3D
var gather_issued_at := -1.0
var start_wood := 0
var start_meat := 0
var start_tc_hp := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless" or absf(Engine.time_scale - 1.0) > 0.001:
		_finish("requires_hidden_headless_unscaled_runtime")
		return
	wall_deadline_msec = Time.get_ticks_msec() + 145000
	call_deferred("_run")

func _run() -> void:
	var menu := await _wait_for_menu(20.0)
	if menu == null:
		_finish("production_menu_missing")
		return
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish("copied_f5_continue_button_not_available")
		return
	var old_main_id := menu.get_instance_id()
	report["events"].append({"at": 0.0, "event": "production_f5_continue_clicked", "button": continue_button.text})
	continue_button.pressed.emit()
	game = await _wait_loaded_match(old_main_id, 35.0)
	if game == null:
		_finish("f5_checkpoint_continue_timeout")
		return
	await get_tree().create_timer(0.4).timeout
	var horde_mode := int(game.get("_horde_mode"))
	game_start = float(game.get("_game_time"))
	start_wood = int(game.get("wood"))
	start_meat = int(game.get("meat"))
	var tc := _player_tc()
	start_tc_hp = float(tc.get("hp")) if tc != null else -1.0
	var initial := _snapshot()
	initial["restored_checkpoint_game_time"] = game_start
	initial["horde_mode"] = horde_mode
	initial["continue_was_real_menu_action"] = true
	report["checkpoint"] = initial
	if horde_mode != 0 or absf(game_start - 221.485187333453) > 1.5 or get_tree().paused:
		report["first_divergence"] = {"at": game_start, "step": "continue_loaded_checkpoint_identity", "actual": initial, "expected_game_time_near": 221.485187333453, "expected_mode": 0, "expected_unpaused": true}
		_finish("continued_save_was_not_expected_unpaused_endless_f5")
		return
	var military_response := _issue_one_visible_threat_order()
	report["events"].append({"at": _elapsed(), "event": "one_time_military_response", "details": military_response, "no_periodic_guard_reissues": true})
	last_villager_count = _live_player_villagers().size()
	next_sample_at = _elapsed()
	var max_game_delta := 120.0
	while Time.get_ticks_msec() < wall_deadline_msec and _elapsed() <= max_game_delta:
		var elapsed := _elapsed()
		var villagers := _live_player_villagers()
		if villagers.size() != last_villager_count:
			report["events"].append({"at": elapsed, "event": "player_villager_count_changed", "from": last_villager_count, "to": villagers.size(), "state": _snapshot()})
			last_villager_count = villagers.size()
		if elapsed >= next_sample_at:
			report["samples"].append(_snapshot())
			next_sample_at = elapsed + 5.0
		if not recovery_attempted and villagers.is_empty():
			recovery_attempted = true
			var recovery := await _run_recovery_once()
			if not bool(recovery.get("started", false)):
				report["first_divergence"] = recovery.get("first_divergence", recovery)
				_finish("zero_villager_recovery_prompt_path_diverged")
				return
			if not await _wait_replacement_and_issue_gather(30.0):
				report["first_divergence"] = {"at": _elapsed(), "step": "paid_training_to_new_worker_gather_order", "details": recovery.get("details", {}), "actual": _snapshot()}
				_finish("replacement_worker_or_gather_order_not_reached")
				return
		if replacement != null and is_instance_valid(replacement):
			var wood_after := int(game.get("wood"))
			if wood_after > start_wood:
				report["recovery_result"] = {"elapsed_game_seconds": _elapsed(), "wood_before": start_wood, "wood_after_deposit": wood_after, "wood_deposited": wood_after - start_wood, "resource_stock_after": int(wood_node.get("amount")) if is_instance_valid(wood_node) else -1, "replacement_hp": float(replacement.get("hp")), "replacement_effects": {"wood_multiplier": float(replacement.get("wood_gather_multiplier")), "carry_bonus": int(replacement.get("wood_carry_bonus"))}, "tc_hp": float(_player_tc().get("hp")) if _player_tc() != null else -1.0}
				report["natural_campaign_claim"] = false
				report["events"].append({"at": _elapsed(), "event": "new_worker_deposited_after_paid_training", "result": report["recovery_result"]})
				report["passed"] = true
				_finish("")
				return
		if _player_tc() == null:
			report["first_divergence"] = {"at": elapsed, "step": "town_center_lost_before_natural_worker_recovery", "actual": _snapshot(), "recovery_attempted": recovery_attempted}
			_finish("town_center_lost_before_recovery_deposit")
			return
		await get_tree().create_timer(0.2).timeout
	if recovery_attempted and replacement != null:
		report["first_divergence"] = {"at": _elapsed(), "step": "new_worker_did_not_deposit_within_checkpoint_window", "actual": _snapshot(), "worker_state": _worker_snapshot(replacement)}
		_finish("120_game_second_checkpoint_window_expired_without_deposit")
	else:
		report["first_divergence"] = {"at": _elapsed(), "step": "no_zero_villager_recovery_prompt_before_window_end", "actual": _snapshot()}
		_finish("120_game_second_checkpoint_window_expired_before_recovery")

func _run_recovery_once() -> Dictionary:
	game.call("_refresh_operational_alerts")
	var hud: Node = game.get("hud")
	var prompt_label: Label = hud.get("_operational_label_by_key").get("workforce:no_villagers_recruit") as Label
	var locator: Button = hud.get("_operational_button_by_key").get("workforce:no_villagers_recruit") as Button
	var tc := _player_tc()
	var initial_meat := int(game.get("meat"))
	var initial_queue: Array = Array(tc.get("train_queue")).duplicate() if tc != null else []
	var status := {"at": _elapsed(), "villagers": _live_player_villagers().size(), "prompt_text": str(prompt_label.text) if is_instance_valid(prompt_label) else "", "meat": initial_meat, "queue": initial_queue, "tc_hp": float(tc.get("hp")) if tc != null else -1.0, "pop": int(game.get("population")), "pop_cap": int(game.get("pop_cap"))}
	report["recovery_prompt"] = status
	if tc == null or not is_instance_valid(locator) or locator.disabled or locator.get_meta("operational_alert_target", null) != tc:
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "zero_villager_prompt_or_live_tc_locator", "actual": status, "available_alert_keys": Array(hud.get("_operational_button_by_key").keys())}}
	if not str(prompt_label.text).contains("可训练农民") or initial_meat < 50 or int(game.get("population")) >= int(game.get("pop_cap")) or not initial_queue.is_empty():
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "eligibility_not_reflected_by_recovery_prompt", "actual": status}}
	locator.pressed.emit()
	await get_tree().process_frame
	if not tc in game.get("selected") or int(game.get("meat")) != initial_meat or Array(tc.get("train_queue")) != initial_queue:
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "locator_selection_without_side_effect", "before": status, "actual": _snapshot(), "tc_selected": tc in game.get("selected")}}
	var train_button: Button = hud.get("_cmd_btns").get("train") as Button
	if train_button == null or train_button.disabled or not train_button.visible:
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "production_tc_villager_button_availability", "before": status, "button": is_instance_valid(train_button)}}
	train_button.pressed.emit()
	await get_tree().process_frame
	var after_queue: Array = Array(tc.get("train_queue")).duplicate()
	var meat_after := int(game.get("meat"))
	var paid := bool(tc.get("train_paid"))
	var details := {"at": _elapsed(), "route": "HUD zero-villager locator -> selected TC -> real TC Villager Button.pressed", "prompt": str(prompt_label.text), "resources_before": initial_meat, "resources_after": meat_after, "paid_cost": initial_meat - meat_after, "queue_after": after_queue, "train_paid": paid, "tc_hp": float(tc.get("hp")), "population": int(game.get("population")), "pop_cap": int(game.get("pop_cap"))}
	report["recruitment"] = details
	if after_queue != ["villager"] or initial_meat - meat_after != 50 or not paid:
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "real_villager_button_payment_and_queue", "actual": details}}
	game.call("_refresh_operational_alerts")
	var training_label: Label = hud.get("_operational_label_by_key").get("workforce:no_villagers_training") as Label
	if training_label == null or not str(training_label.text).contains("付费训练中"):
		return {"started": false, "first_divergence": {"at": _elapsed(), "step": "paid_training_recovery_status", "actual": details, "training_prompt": str(training_label.text) if is_instance_valid(training_label) else ""}}
	report["events"].append({"at": _elapsed(), "event": "actual_prompt_locator_and_paid_training", "details": details, "paid_training_prompt": training_label.text})
	return {"started": true, "details": details}

func _wait_replacement_and_issue_gather(seconds: float) -> bool:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < wall_deadline_msec:
		var current := _live_player_villagers()
		if not current.is_empty():
			replacement = current[0]
			for candidate in current:
				if int(candidate.get_instance_id()) > int(replacement.get_instance_id()):
					replacement = candidate
			wood_node = _wood_node()
			if wood_node == null:
				report["first_divergence"] = {"at": _elapsed(), "step": "new_worker_no_live_wood_node", "actual": _snapshot()}
				return false
			var old_wood := int(game.get("wood"))
			game.call("_clear_selection")
			game.call("_add_to_selection", replacement)
			game.call("_refresh_selection_hud")
			game.call("_on_cmd_gather")
			game.call("_route_pending_command", wood_node.global_position)
			gather_issued_at = _elapsed()
			var worker_order := _worker_snapshot(replacement)
			var valid_order: bool = replacement.get("gather_target") == wood_node or (str(replacement.get("resume_key")) == "wood" and is_instance_valid(replacement.get("resume_resource")))
			report["gather_order"] = {"at": gather_issued_at, "route": "normal Main gather mode + pending map command route", "wood_before": old_wood, "node_stock_before": int(wood_node.get("amount")), "worker": worker_order, "valid_target": valid_order}
			report["events"].append({"at": gather_issued_at, "event": "replacement_worker_given_normal_gather_order", "details": report["gather_order"]})
			return valid_order
		await get_tree().create_timer(0.1).timeout
	return false

func _issue_one_visible_threat_order() -> Dictionary:
	var soldiers := _live_player_soldiers()
	var threats := _live_enemy_units()
	if soldiers.is_empty() or threats.is_empty():
		return {"issued": false, "reason": "no_live_player_soldier_or_visible_enemy_at_checkpoint", "soldiers": soldiers.size(), "enemies": threats.size()}
	var best_soldier: Node3D
	var best_enemy: Node3D
	var best_distance := INF
	for soldier in soldiers:
		if is_instance_valid(soldier.get("attack_target")) and CombatAlive(soldier.get("attack_target")):
			continue
		for enemy in threats:
			var distance := Vector2(soldier.global_position.x - enemy.global_position.x, soldier.global_position.z - enemy.global_position.z).length()
			if distance < best_distance:
				best_distance = distance
				best_soldier = soldier
				best_enemy = enemy
	if best_soldier == null or best_enemy == null:
		return {"issued": false, "reason": "all_live_soldiers_already_have_combat_targets", "soldiers": soldiers.size(), "enemies": threats.size()}
	var before := _soldier_snapshot(best_soldier)
	game.call("_clear_selection")
	game.call("_add_to_selection", best_soldier)
	game.call("_refresh_selection_hud")
	var hud: Node = game.get("hud")
	var attack_button: Button = hud.get("_cmd_btns").get("attack") as Button
	if attack_button == null or not attack_button.visible:
		return {"issued": false, "reason": "production_attack_command_button_unavailable", "soldier_before": before}
	attack_button.pressed.emit()
	game.call("_route_pending_command", best_enemy.global_position)
	var after := _soldier_snapshot(best_soldier)
	return {"issued": best_soldier.get("attack_target") == best_enemy, "route": "production HUD Attack button + Main pending map command", "soldier_before": before, "soldier_after": after, "target": {"instance_id": best_enemy.get_instance_id(), "wave": int(best_enemy.get("horde_wave_id")), "hp": float(best_enemy.get("hp")), "position": [best_enemy.global_position.x, best_enemy.global_position.z]}, "distance_at_issue": best_distance}

func _snapshot() -> Dictionary:
	if not is_instance_valid(game):
		return {}
	var villagers := _live_player_villagers()
	var tc := _player_tc()
	var workforce: Dictionary = game.call("_workforce_assignment_summary")
	var hud: Node = game.get("hud")
	var active_enemies := _live_enemy_units()
	var row_text: Array = []
	if hud != null and is_instance_valid(hud):
		for label_key in hud.get("_operational_label_by_key"):
			var label: Variant = hud.get("_operational_label_by_key").get(label_key)
			if is_instance_valid(label):
				row_text.append({"key": str(label_key), "text": str(label.text)})
	return {"at": _elapsed(), "game_time": float(game.get("_game_time")), "wave": int(game.get("_horde_wave")), "wave_active": bool(game.get("_horde_active")), "mode": int(game.get("_horde_mode")), "wood": int(game.get("wood")), "meat": int(game.get("meat")), "stone": int(game.get("stone")), "gold": int(game.get("gold")), "villagers": villagers.size(), "workforce": workforce, "workforce_hud": str(hud.get("_workforce_l").text) if hud != null else "", "player_soldiers": _live_player_soldiers().size(), "visible_enemies": active_enemies.size(), "tc_hp": float(tc.get("hp")) if tc != null else -1.0, "tc_alive": tc != null, "tc_queue": Array(tc.get("train_queue")).duplicate() if tc != null else [], "tc_train_paid": bool(tc.get("train_paid")) if tc != null else false, "combat_alerts": row_text.filter(func(row): return str(row.get("key", "")).begins_with("combat:"))}

func _elapsed() -> float:
	return maxf(0.0, float(game.get("_game_time")) - game_start) if is_instance_valid(game) and game_start > 0.0 else 0.0

func _live_player_villagers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for worker in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and worker.is_inside_tree() and bool(worker.get("alive")) and str(worker.get("team")) == "player":
			result.append(worker)
	return result

func _live_player_soldiers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for soldier in get_tree().get_nodes_in_group("military"):
		if is_instance_valid(soldier) and soldier.is_inside_tree() and bool(soldier.get("alive")) and str(soldier.get("team")) == "player" and not bool(soldier.get("is_zombie")):
			result.append(soldier)
	return result

func _live_enemy_units() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for enemy in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(enemy) and enemy.is_inside_tree() and bool(enemy.get("alive")) and str(enemy.get("team")) == "enemy":
			result.append(enemy)
	return result

func _player_tc() -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.TOWN_CENTER:
			return building
	return null

func _wood_node() -> Node3D:
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and not node.is_in_group("buildings") and node.has_method("res_key") and str(node.call("res_key")) == "wood" and int(node.get("amount")) > 0:
			return node
	return null

func _worker_snapshot(worker: Node) -> Dictionary:
	return {"instance_id": worker.get_instance_id(), "alive": bool(worker.get("alive")), "hp": float(worker.get("hp")), "state": int(worker.get("state")), "carry_key": str(worker.get("carry_key")), "carry_amount": int(worker.get("carry_amount")), "wood_multiplier": float(worker.get("wood_gather_multiplier")), "wood_carry_bonus": int(worker.get("wood_carry_bonus")), "gather_target_valid": is_instance_valid(worker.get("gather_target")), "resume_key": str(worker.get("resume_key"))}

func _soldier_snapshot(soldier: Node) -> Dictionary:
	return {"instance_id": soldier.get_instance_id(), "hp": float(soldier.get("hp")), "state": int(soldier.get("state")), "guard_active": bool(soldier.get("guard_active")), "guard_anchor": str(soldier.get("guard_anchor")), "attack_target_valid": is_instance_valid(soldier.get("attack_target"))}

func CombatAlive(target: Variant) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and bool(target.get("alive"))

func _wait_for_menu(seconds: float) -> Node:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < wall_deadline_msec:
		await get_tree().process_frame
		var main := get_tree().root.get_node_or_null("Main")
		if main != null and main.get("_start_layer") != null:
			return main
	return null

func _wait_loaded_match(old_main_id: int, seconds: float) -> Node3D:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < wall_deadline_msec:
		await get_tree().process_frame
		var main := get_tree().root.get_node_or_null("Main")
		if main != null and main.get_instance_id() != old_main_id and bool(main.get("_match_started")):
			return main
	return null

func _finish(error_text: String) -> void:
	if not error_text.is_empty():
		report["error"] = error_text
	report["ended_at"] = Time.get_datetime_string_from_system(true, true)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[natural_checkpoint_recovery_probe] ", JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("passed", false)) else 1)
