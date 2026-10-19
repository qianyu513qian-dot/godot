extends Node

const ControlledEndlessDefenseScript := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const RESULT_PATH := "user://worker_evacuation_recovery_fixture.json"
const WALL_LIMIT_MSEC := 120000

var run_id := ""
var phase := "menu_continue"
var done := false
var fixture_started_at_msec := 0
var game: Node
var helper: Node
var worker: Node3D
var attacker: Node3D
var wood_source: Node3D
var town_center: Node3D
var worker_runtime_id := ""
var audit_before: Array = []
var test_results: Dictionary = {}
var fixture_mutations: Array[Dictionary] = []
var initial_resources: Dictionary = {}
var receipt_window_resources: Dictionary = {}
var initial_worker_state: Dictionary = {}
var initial_enemy_state: Dictionary = {}
var order_count_after_safe_return := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--run-id="):
			run_id = str(arg).get_slice("=", 1)
	if run_id.is_empty():
		run_id = "worker_recovery_fixture_%d" % Time.get_ticks_usec()
	fixture_started_at_msec = Time.get_ticks_msec()
	print("[worker_evacuation_fixture] started run_id=%s pid=%d" % [run_id, OS.get_process_id()])

func _process(_delta: float) -> void:
	if done:
		return
	if Time.get_ticks_msec() - fixture_started_at_msec > WALL_LIMIT_MSEC:
		_finish(false, "fixture_wall_timeout")
		return
	if phase == "menu_continue":
		_try_production_continue()
		return
	if phase == "wait_restored_match":
		game = get_tree().get_first_node_in_group("main_game")
		if game == null or not bool(game.get("_match_started")):
			return
		if int(game.get("map_seed")) != 42 or int(game.get("_horde_mode")) != 1 or absf(float(game.get("_game_time")) - 230.004932333475) > 1.0:
			_finish(false, "production_continue_checkpoint_mismatch")
			return
		_begin_fixture()
		return
	if phase == "await_worker_deposit":
		var rows: Array = helper.get("events")
		for event in rows:
			if str(event.get("action", "")) == "withdrawn_worker_production_deposit_receipt" and str(event.get("worker_runtime_id", "")) == worker_runtime_id:
				var audit_id := str(event.get("audit_id", ""))
				var audit: Dictionary = helper.get("worker_resume_audits").get(audit_id, {})
				var same_resource_harvest := int(audit.get("harvested_after_resume", 0)) > 0 and bool(event.get("receipt_has_post_resume_harvest", false))
				var actual_balance_increase := int(event.get("inventory_after_deposit", -1)) > int(event.get("inventory_before_resume", -1))
				test_results["same_worker_real_deposit"] = {"passed":same_resource_harvest and actual_balance_increase,"worker":worker.name,"worker_runtime_id":worker_runtime_id,"audit_id":audit_id,"game_time":event.get("game_time"),"resource_key":event.get("resource_key"),"harvested_after_resume":audit.get("harvested_after_resume", 0),"deposit_amount":event.get("deposit_amount"),"inventory_before_resume":event.get("inventory_before_resume"),"inventory_after_deposit":event.get("inventory_after_deposit"),"inventory_delta_since_resume":event.get("inventory_delta_since_resume"),"production_signal_source":event.get("receipt_source"),"other_villagers_frozen_during_receipt_window":true}
				_finish(bool(test_results["same_worker_real_deposit"].passed), "evacuation_recovery_fixture_complete" if bool(test_results["same_worker_real_deposit"].passed) else "same_worker_deposit_attribution_failed")
				return
		if Time.get_ticks_msec() - fixture_started_at_msec > WALL_LIMIT_MSEC - 5000:
			_finish(false, "same_worker_deposit_timeout")

func _try_production_continue() -> void:
	var current := get_tree().get_first_node_in_group("main_game")
	if current == null or current.get("_start_layer") == null:
		return
	var continue_button := current.get("_start_continue_button") as Button
	var mode_select := current.get("_start_mode_select") as OptionButton
	if continue_button == null or continue_button.disabled or mode_select == null:
		_finish(false, "production_continue_unavailable")
		return
	mode_select.select(1)
	Engine.set_meta("aoelite_challenge5_run", true)
	continue_button.pressed.emit()
	phase = "wait_restored_match"
	print("[worker_evacuation_fixture] production Continue emitted pid=%d" % OS.get_process_id())

func _begin_fixture() -> void:
	get_tree().paused = true
	game.set_process(false)
	game.set_physics_process(false)
	var villagers := _living_villagers()
	var candidates: Array[Node3D] = villagers.filter(func(v: Node3D) -> bool: return str(v.get("resume_key")) == "wood")
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return float(a.get("hp")) > float(b.get("hp")))
	if candidates.is_empty():
		_finish(false, "no_saved_wood_worker_available")
		return
	worker = candidates[0]
	worker_runtime_id = str(worker.get_instance_id())
	wood_source = _nearest_wood_source()
	town_center = _player_town_center()
	var enemies := _living_zombies()
	if wood_source == null or town_center == null or enemies.is_empty():
		_finish(false, "saved_checkpoint_fixture_dependencies_missing")
		return
	attacker = enemies[0]
	receipt_window_resources = {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}
	initial_worker_state = {"name":str(worker.name),"runtime_id":worker_runtime_id,"hp":float(worker.get("hp")),"position":_v3(worker.global_position),"resume_key":str(worker.get("resume_key")),"carry_key":str(worker.get("carry_key")),"carry_amount":int(worker.get("carry_amount")),"state":int(worker.get("state"))}
	initial_enemy_state = {"name":str(attacker.name),"runtime_id":str(attacker.get_instance_id()),"hp":float(attacker.get("hp")),"alive":bool(attacker.get("alive")),"original_target":str(attacker.get("attack_target").name) if is_instance_valid(attacker.get("attack_target")) else "","position":_v3(attacker.global_position)}
	for other in villagers:
		if other != worker:
			other.set_process(false)
			other.set_physics_process(false)
	for enemy in enemies:
		var enemy_before := {"name":str(enemy.name),"runtime_id":str(enemy.get_instance_id()),"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position),"attack_target":str(enemy.get("attack_target").name) if is_instance_valid(enemy.get("attack_target")) else ""}
		enemy.set("attack_target", null)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		if enemy != attacker:
			enemy.global_position = Vector3(45.0, 0.0, 45.0) + Vector3(float(enemies.find(enemy)) * 0.5, 0.0, 0.0)
		fixture_mutations.append({"item":"freeze live enemy and clear existing target","before":enemy_before,"after":{"name":str(enemy.name),"runtime_id":str(enemy.get_instance_id()),"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position),"attack_target":""},"reason":"fixture only; no enemy HP/alive/count changes"})
	for unit in get_tree().get_nodes_in_group("military"):
		unit.set_process(false)
		unit.set_physics_process(false)
	for projectile in get_tree().get_nodes_in_group("projectiles"):
		projectile.set_process(false)
		projectile.set_physics_process(false)
	fixture_mutations.append({"item":"freeze non-fixture villagers, military, projectiles, and enemy updates; disable Main process during the short receipt window","reason":"isolate one real production worker and prevent unrelated combat/economy events; does not change HP/damage/resource prices/wave schedule"})
	worker.global_position = Vector3(-6.0, 0.0, -5.0)
	worker.set("hp", float(worker.get("max_hp")))
	worker.set("attack_target", null)
	worker.set("gather_target", null)
	worker.set("resume_resource", wood_source)
	worker.set("resume_key", "wood")
	worker.set("build_site", null)
	worker.set("drop_target", town_center)
	worker.set("carry_amount", 0)
	worker.set("carry_key", "")
	worker.set("state", 0)
	worker.set("manual_order_suppresses_auto_defense", true)
	worker.set("_goal_final", worker.global_position)
	worker.set("move_target", worker.global_position)
	fixture_mutations.append({"item":"fixture villager %s" % worker_runtime_id,"before":initial_worker_state,"after":{"hp":worker.get("hp"),"position":_v3(worker.global_position),"resume_key":"wood","carry_key":"","carry_amount":0,"state":"IDLE"},"reason":"deterministic recovery fixture; this is explicit worker-state injection, not a natural-play result"})
	helper = ControlledEndlessDefenseScript.new()
	helper.name = "WorkerRecoveryControllerUnderTest"
	helper.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(helper)
	helper.set_process(false)
	helper.set("run_id", run_id)
	helper.set("last_game", game)
	helper.set("original_seed", 42)
	helper.set("phase", "defend")
	helper.set("old_game_id", game.get_instance_id())
	helper.set("start_game_time", float(game.get("_game_time")))
	helper.set("elapsed", 0.0)
	helper.set("economy_guard_runtime_ids", {})
	helper.set("evacuated_worker_ids", {})
	helper.set("worker_resume_audits", {})
	attacker.global_position = worker.global_position + Vector3(0.0, 0.0, 10.0)
	attacker.set("attack_target", worker)
	fixture_mutations.append({"item":"reuse existing live enemy %s as injected pursuer" % attacker.name,"before":initial_enemy_state,"after":{"hp":attacker.get("hp"),"position":_v3(attacker.global_position),"attack_target":str(worker.name)},"reason":"only target and position change for unsafe/safe/re-threat gates; enemy HP/alive are unchanged"})
	var threat_before: int = (helper.get("events") as Array).size()
	helper.call("_evacuate_targeted_workers", game)
	var entry: Dictionary = helper.get("evacuated_worker_ids").get(worker_runtime_id, {})
	var move_accepted := not entry.is_empty() and float(entry.get("issued_game_time", -1.0)) >= 0.0
	test_results["accepted_evacuation"] = {"passed":move_accepted,"event_count_delta":helper.get("events").size() - threat_before,"worker":str(worker.name),"worker_runtime_id":worker_runtime_id,"resume_key_preserved":str(entry.get("resume_key", "")),"record":entry.duplicate(true)}
	if not move_accepted:
		_finish(false, "fixture_move_not_accepted")
		return
	var blocked_gather := bool(helper.call("_issue_gather_order", game, [worker], wood_source, "fixture ordinary gather must remain blocked while evacuation is active"))
	var unsafe_order_count := _main_gather_order_count(helper, worker_runtime_id)
	helper.call("_resume_safe_evacuated_workers", game)
	var unsafe_held: bool = helper.get("evacuated_worker_ids").has(worker_runtime_id) and _main_gather_order_count(helper, worker_runtime_id) == unsafe_order_count
	test_results["unsafe_retains_protection"] = {"passed":not blocked_gather and unsafe_held,"ordinary_gather_rejected":not blocked_gather,"pending_retained":helper.get("evacuated_worker_ids").has(worker_runtime_id),"no_resume_gather_issued":_main_gather_order_count(helper, worker_runtime_id) == unsafe_order_count,"attacker_target":str(attacker.get("attack_target").name) if is_instance_valid(attacker.get("attack_target")) else "","distance":attacker.global_position.distance_to(worker.global_position)}
	attacker.set("attack_target", null)
	attacker.global_position = Vector3(45.0, 0.0, 45.0)
	var invalid_target := Node3D.new()
	var invalid_accepted := bool(helper.call("_issue_gather_order_authorized", game, [worker], invalid_target, "fixture authorized gather with detached target", "fixture_recovery_probe", worker_runtime_id))
	invalid_target.free()
	var rejected_retained: bool = helper.get("evacuated_worker_ids").has(worker_runtime_id) and _has_action(helper, "gather_order_rejected_invalid_target")
	test_results["command_rejection_retains_retry"] = {"passed":not invalid_accepted and rejected_retained,"accepted":invalid_accepted,"pending_retained":helper.get("evacuated_worker_ids").has(worker_runtime_id),"invalid_target_rejection_logged":_has_action(helper, "gather_order_rejected_invalid_target")}
	var record: Dictionary = helper.get("evacuated_worker_ids")[worker_runtime_id]
	record["resume_key"] = "fixture_missing_resource"
	record["retry_after_game_time"] = float(game.get("_game_time"))
	helper.call("_resume_safe_evacuated_workers", game)
	var invalid_retained: bool = helper.get("evacuated_worker_ids").has(worker_runtime_id)
	var invalid_event := _has_event(helper, "withdrawn_worker_gather_resume_deferred", worker_runtime_id)
	test_results["invalid_target_retains_retry"] = {"passed":invalid_retained and invalid_event,"pending_retained":invalid_retained,"deferred_event":invalid_event,"attempts":record.get("resume_attempts"),"retry_after_game_time":record.get("retry_after_game_time")}
	record["resume_key"] = "wood"
	record["retry_after_game_time"] = float(game.get("_game_time"))
	helper.call("_resume_safe_evacuated_workers", game)
	var safe_order_count := _main_gather_order_count(helper, worker_runtime_id)
	var first_return_passed: bool = safe_order_count == 1 and not helper.get("evacuated_worker_ids").has(worker_runtime_id)
	helper.call("_resume_safe_evacuated_workers", game)
	var single_issue_passed := _main_gather_order_count(helper, worker_runtime_id) == safe_order_count
	test_results["safe_once_and_pending_cleared"] = {"passed":first_return_passed and single_issue_passed,"main_gather_order_count":safe_order_count,"pending_cleared":not helper.get("evacuated_worker_ids").has(worker_runtime_id),"repeat_sweep_did_not_reissue":single_issue_passed}
	var audit_count_before_rethreat: int = (helper.get("worker_resume_audits") as Dictionary).size()
	attacker.set("attack_target", worker)
	attacker.global_position = worker.global_position + Vector3(0.0, 0.0, 8.0)
	helper.call("_evacuate_targeted_workers", game)
	var rethreat_accepted: bool = helper.get("evacuated_worker_ids").has(worker_runtime_id)
	var second_record: Dictionary = helper.get("evacuated_worker_ids").get(worker_runtime_id, {})
	attacker.set("attack_target", null)
	attacker.global_position = Vector3(45.0, 0.0, 45.0)
	second_record["retry_after_game_time"] = float(game.get("_game_time"))
	helper.call("_resume_safe_evacuated_workers", game)
	var second_gather_count := _main_gather_order_count(helper, worker_runtime_id)
	var rethreat_passed: bool = rethreat_accepted and not helper.get("evacuated_worker_ids").has(worker_runtime_id) and second_gather_count == safe_order_count + 1 and (helper.get("worker_resume_audits") as Dictionary).size() == audit_count_before_rethreat + 1
	test_results["repeated_threat_reenters_and_resumes"] = {"passed":rethreat_passed,"second_move_accepted":rethreat_accepted,"second_gather_count":second_gather_count,"audit_count_before":audit_count_before_rethreat,"audit_count_after":helper.get("worker_resume_audits").size(),"pending_cleared_after_safe_return":not helper.get("evacuated_worker_ids").has(worker_runtime_id)}
	if not first_return_passed or not single_issue_passed or not rethreat_passed:
		_finish(false, "fixture_command_state_transition_failed")
		return
	order_count_after_safe_return = second_gather_count
	initial_resources = {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}
	fixture_mutations.append({"item":"freeze every other villager and all live enemies for exclusive receipt window","reason":"ensures any new wood receipt during this window is attributable to the selected runtime worker; no HP/resources/enemy HP are modified"})
	get_tree().paused = false
	phase = "await_worker_deposit"
	print("[worker_evacuation_fixture] waiting for same-worker real harvest+deposit name=%s id=%s" % [worker.name, worker_runtime_id])

func _main_gather_order_count(controller: Node, id: String) -> int:
	var count := 0
	for event in controller.get("events"):
		if str(event.get("action", "")) == "main_gather_order" and str(event.get("workers", "")).contains(id):
			count += 1
	return count

func _has_event(controller: Node, action: String, id: String) -> bool:
	for event in controller.get("events"):
		if str(event.get("action", "")) == action and str(event.get("worker_runtime_id", "")) == id:
			return true
	return false

func _has_action(controller: Node, action: String) -> bool:
	for event in controller.get("events"):
		if str(event.get("action", "")) == action:
			return true
	return false

func _living_villagers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for item in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(item) and str(item.get("team")) == "player" and bool(item.get("alive")):
			result.append(item as Node3D)
	return result

func _living_zombies() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for item in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(item) and bool(item.get("alive")):
			result.append(item as Node3D)
	return result

func _nearest_wood_source() -> Node3D:
	var best: Node3D
	var best_distance := INF
	for item in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(item) or not item.has_method("res_key") or str(item.call("res_key")) != "wood" or int(item.get("amount")) <= 0:
			continue
		var distance := worker.global_position.distance_squared_to(item.global_position)
		if distance < best_distance:
			best_distance = distance
			best = item as Node3D
	return best

func _player_town_center() -> Node3D:
	for item in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(item) and str(item.get("team")) == "player" and int(item.get("kind")) == 0 and bool(item.get("alive")):
			return item as Node3D
	return null

func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _finish(passed: bool, reason: String) -> void:
	if done:
		return
	done = true
	if get_tree().paused:
		get_tree().paused = false
	var expected := ["accepted_evacuation", "unsafe_retains_protection", "command_rejection_retains_retry", "invalid_target_retains_retry", "safe_once_and_pending_cleared", "repeated_threat_reenters_and_resumes", "same_worker_real_deposit"]
	var all_passed := passed
	for key in expected:
		all_passed = all_passed and bool(test_results.get(key, {}).get("passed", false))
	var data := {"schema":1,"run_id":run_id,"status":"passed" if all_passed else "failed","reason":reason,"fixture":true,"natural_gameplay_result":false,"time_scale":Engine.time_scale,"engine_pid":OS.get_process_id(),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name() == "headless","source_checkpoint":{"seed":int(game.get("map_seed")) if is_instance_valid(game) else -1,"mode":int(game.get("_horde_mode")) if is_instance_valid(game) else -1,"game_time_at_continue":float(game.get("_game_time")) if is_instance_valid(game) else -1.0,"resources_before_injection":initial_resources},"worker":initial_worker_state,"worker_runtime_id":worker_runtime_id,"attacker_before_fixture":initial_enemy_state,"fixture_mutations":fixture_mutations,"test_results":test_results,"controller_events":helper.get("events") if is_instance_valid(helper) else [],"resources_before_receipt_window":receipt_window_resources,"final_resources":{"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))} if is_instance_valid(game) else {},"end_game_time":float(game.get("_game_time")) if is_instance_valid(game) else -1.0,"wall_elapsed_msec":Time.get_ticks_msec()-fixture_started_at_msec,"supervision_data_written":false}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	print("[worker_evacuation_fixture_result] ", JSON.stringify({"run_id":run_id,"status":data.status,"reason":reason,"worker":worker.name if is_instance_valid(worker) else "","worker_runtime_id":worker_runtime_id,"result_path":RESULT_PATH,"passed":all_passed}))
	get_tree().quit(0 if all_passed else 1)
