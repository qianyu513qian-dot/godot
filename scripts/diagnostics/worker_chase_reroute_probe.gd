extends Node
## Minimal matched fixture for the pending-worker pursuit reroute.
const Controller := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const RESULT_PATH := "user://worker_chase_reroute_fixture.json"
const MAX_GAME_SECONDS := 50.0
const WALL_LIMIT_MSEC := 90000

var run_id := ""
var behavior := "candidate"
var phase := "continue"
var done := false
var started_msec := 0
var game: Node
var worker: Node3D
var pursuer: Node3D
var helper: Node
var worker_id := ""
var last_sweep_game_time := -1.0
var start_game_time := -1.0
var fixture_mutations: Array[Dictionary] = []
var test_results: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--run-id="): run_id = str(arg).get_slice("=", 1)
		if str(arg).begins_with("--reroute-behavior="): behavior = str(arg).get_slice("=", 1)
	if run_id.is_empty(): run_id = "worker_chase_%d" % Time.get_ticks_usec()
	started_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if done: return
	if Time.get_ticks_msec() - started_msec > WALL_LIMIT_MSEC:
		_finish(false, "fixture_wall_timeout")
		return
	if phase == "continue":
		_try_continue(); return
	if phase == "wait_match":
		game = get_tree().get_first_node_in_group("main_game")
		if game == null or not bool(game.get("_match_started")): return
		if int(game.get("map_seed")) != 42 or int(game.get("_horde_mode")) != 1 or absf(float(game.get("_game_time")) - 230.004932333475) > 1.0:
			_finish(false, "frozen_checkpoint_mismatch"); return
		_begin_fixture(); return
	if phase == "pursuit_window":
		var now := float(game.get("_game_time"))
		if now - last_sweep_game_time >= 0.5:
			last_sweep_game_time = now
			helper.call("_maintain_threat_response_plan", game)
			_capture_sample(now)
		if is_instance_valid(worker) and not bool(worker.get("alive")):
			_evaluate("fixture_worker_lost_before_window_end")
		elif _same_worker_chain_deposited() and now - _last_worker_deposit_time() >= 2.0:
			_evaluate("same_worker_real_harvest_and_deposit_observed")
		elif now - start_game_time >= MAX_GAME_SECONDS:
			_evaluate("bounded_pursuit_window_elapsed")

func _try_continue() -> void:
	var current := get_tree().get_first_node_in_group("main_game")
	if current == null or current.get("_start_layer") == null: return
	var button := current.get("_start_continue_button") as Button
	var mode := current.get("_start_mode_select") as OptionButton
	if button == null or button.disabled or mode == null:
		_finish(false, "production_continue_unavailable"); return
	mode.select(1)
	Engine.set_meta("aoelite_challenge5_run", true)
	button.pressed.emit()
	phase = "wait_match"

func _begin_fixture() -> void:
	var villagers := _living_villagers()
	var candidates: Array[Node3D] = villagers.filter(func(v: Node3D) -> bool: return str(v.get("resume_key")) == "wood")
	if candidates.is_empty():
		_finish(false, "no_wood_resume_worker_in_saved_checkpoint"); return
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return float(a.get("hp")) > float(b.get("hp")))
	worker = candidates[0]
	worker_id = str(worker.get_instance_id())
	var enemies := _living_zombies()
	if enemies.is_empty():
		_finish(false, "no_live_pursuer_in_saved_checkpoint"); return
	enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(worker.global_position) < b.global_position.distance_squared_to(worker.global_position))
	pursuer = enemies[0]
	start_game_time = float(game.get("_game_time"))
	var before_worker := _entity_state(worker)
	var before_enemy := _entity_state(pursuer)
	# Natural-pressure fixture: leave all villagers, military, towers, and enemies
	# active. Change only one existing zombie's target and position to create a
	# reproducible pursuit; no old worker order is injected or restored by hand.
	pursuer.global_position = worker.global_position + Vector3(0.0, 0.0, 10.0)
	pursuer.set("attack_target", worker)
	fixture_mutations.append({"item":"inject_one_pursuit_using_saved_enemy","worker_before":before_worker,"worker_after":_entity_state(worker),"pursuer_before":before_enemy,"pursuer_after":_entity_state(pursuer),"changed_fields":["pursuer.position","pursuer.attack_target"],"all_other_entities_continue_normally":true,"preserved_fields":["worker.state","worker.gather_target","worker.resume_resource","worker.resume_key","worker.HP","pursuer.HP","pursuer.alive","all_unit_stats","resources","buildings","wave_schedule"],"reason":"reproducible enemy pressure only; does not inject a worker order takeover, force unlock, kill an enemy, heal, or alter production"})
	helper = Controller.new()
	helper.name = "WorkerChaseControllerUnderTest"
	helper.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(helper)
	helper.set_process(false)
	helper.set("run_id", run_id)
	helper.set("last_game", game)
	helper.set("original_seed", 42)
	helper.set("phase", "defend")
	helper.set("old_game_id", game.get_instance_id())
	helper.set("start_game_time", start_game_time)
	helper.set("enable_pending_worker_reroutes", behavior == "candidate")
	helper.set("fixture_trace", [])
	fixture_mutations.append({"item":"select_controller_behavior","behavior":behavior,"pending_worker_reroutes_enabled":behavior == "candidate"})
	# Run the full protection sweep so guard maintenance, initial evacuation,
	# throttled reroute, safe resume, and audit-progress checks share one lifecycle.
	helper.call("_maintain_threat_response_plan", game)
	var pending: Dictionary = helper.get("evacuated_worker_ids").get(worker_id, {})
	var goal: Variant = worker.get("_goal_final")
	var move_ok := not pending.is_empty() and int(worker.get("state")) == 1 and goal is Vector3 and (goal as Vector3).distance_to(worker.global_position) > 0.5
	test_results["initial_actual_move"] = {"passed":move_ok,"pending":not pending.is_empty(),"worker":worker.name,"runtime_id":worker_id,"goal":_v3(goal) if goal is Vector3 else [],"gather_target_after":_node_name(worker.get("gather_target")),"resume_key_in_pending":pending.get("resume_key"),"first_threat_preserved":pending.get("first_threat",[])}
	if not move_ok:
		_finish(false, "initial_production_move_not_accepted"); return
	fixture_mutations.append({"item":"issue_evacuation_through_production_Main_Move_and_map_route","before":before_worker,"after":_entity_state(worker),"record":pending.duplicate(true)})
	fixture_mutations.append({"item":"explicitly_observe_r41_old_order_retakeover_without_injection","worker_after_production_move":_entity_state(worker),"order_queue":worker.get("order_queue").duplicate(true),"source_attribution":"only production/controller/worker transition events will be considered; absence of a direct command receipt remains unknown"})
	start_game_time = float(game.get("_game_time"))
	last_sweep_game_time = start_game_time
	phase = "pursuit_window"

func _capture_sample(now: float) -> void:
	if not is_instance_valid(worker) or not bool(worker.get("alive")): return
	var goal: Variant = worker.get("_goal_final")
	var move_history: Array = helper.get("events").filter(func(event: Dictionary) -> bool: return str(event.get("action", "")).begins_with("withdrawn_worker_reroute_") and str(event.get("worker_runtime_id", "")) == worker_id)
	var events: Array = helper.get("events")
	var trace: Array = helper.get("fixture_trace")
	var nearest_enemy_distance := INF
	var locked_by: Array[String] = []
	for enemy in _living_zombies():
		nearest_enemy_distance = minf(nearest_enemy_distance,enemy.global_position.distance_to(worker.global_position))
		if enemy.get("attack_target") == worker: locked_by.append(str(enemy.name))
	var threatened_count := 0
	for item in _living_villagers():
		for enemy in _living_zombies():
			if enemy.get("attack_target") == item:
				threatened_count += 1; break
	var guards: Array[Dictionary] = []
	for unit in get_tree().get_nodes_in_group("military"):
		if is_instance_valid(unit) and bool(unit.get("alive")): guards.append({"name":str(unit.name),"position":_v3(unit.global_position),"target":_node_name(unit.get("attack_target")),"guard_active":bool(unit.get("guard_active"))})
	var towers: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and bool(building.get("is_tower")): towers.append({"name":str(building.name),"position":_v3(building.global_position),"hp":float(building.get("hp")),"cooldown":float(building.get("_tower_cd"))})
	var pursuer_valid := is_instance_valid(pursuer)
	trace.append({"game_time":now,"worker_position":_v3(worker.global_position),"worker_state":int(worker.get("state")),"worker_hp":float(worker.get("hp")),"worker_goal":_v3(goal) if goal is Vector3 else [],"gather_target":_node_name(worker.get("gather_target")),"drop_target":_node_name(worker.get("drop_target")),"build_site":_node_name(worker.get("build_site")),"resume_key":str(worker.get("resume_key")),"carry_key":str(worker.get("carry_key")),"carry":int(worker.get("carry_amount")),"order_queue":worker.get("order_queue").duplicate(true),"pursuer_position":_v3(pursuer.global_position) if pursuer_valid else [],"pursuer_hp":float(pursuer.get("hp")) if pursuer_valid else 0.0,"pursuer_alive":bool(pursuer.get("alive")) if pursuer_valid else false,"pursuer_distance":pursuer.global_position.distance_to(worker.global_position) if pursuer_valid else INF,"pursuer_target":_node_name(pursuer.get("attack_target")) if pursuer_valid else "freed_after_death","nearest_enemy_distance":nearest_enemy_distance,"enemies_locked_to_worker":locked_by,"all_threatened_workers_count":threatened_count,"guards":guards,"towers":towers,"reroute_events":move_history.size(),"all_worker_reroute_events":events.filter(func(event: Dictionary) -> bool: return str(event.get("action", "")).begins_with("withdrawn_worker_reroute_")).size()})
	helper.set("fixture_trace", trace)

func _evaluate(reason: String) -> void:
	var pending: Dictionary = helper.get("evacuated_worker_ids").get(worker_id, {})
	var moves: Array = helper.get("events").filter(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_reroute_issued" and str(event.get("worker_runtime_id", "")) == worker_id)
	var rejected: Array = helper.get("events").filter(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_no_safer_reachable_point" and str(event.get("worker_runtime_id", "")) == worker_id)
	var chain_receipts: Array = helper.get("events").filter(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_production_deposit_receipt" and str(event.get("worker_runtime_id", "")) == worker_id and bool(event.get("receipt_has_post_resume_harvest", false)))
	var full_chain := not chain_receipts.is_empty()
	var reroute_attempts := int(pending.get("reroute_attempts", 0))
	var surviving := is_instance_valid(worker) and bool(worker.get("alive")) and float(worker.get("hp")) > 0.0
	var unsafe_gather_orders: Array = []
	for event in helper.get("events"):
		if str(event.get("action", "")) != "main_gather_order" or not Array(event.get("workers", [])).any(func(value: String) -> bool: return value.contains(worker_id)): continue
		var nearest_sample: Dictionary = {}
		var sample_delta := INF
		for sample in helper.get("fixture_trace"):
			var candidate_delta: float = absf(float(sample.get("game_time", -INF))-float(event.get("game_time", INF)))
			if candidate_delta < sample_delta: sample_delta=candidate_delta; nearest_sample=sample
		if not nearest_sample.is_empty() and (float(nearest_sample.get("nearest_enemy_distance", INF)) < 14.0 or not Array(nearest_sample.get("enemies_locked_to_worker", [])).is_empty()): unsafe_gather_orders.append(event)
	var reroute_attempt_bound := moves.size() <= 3 and reroute_attempts <= 3
	var safe_move_records := moves.all(func(event: Dictionary) -> bool: return bool(event.get("accepted", false)) and int(event.get("state_after", 0)) == 1 and str(event.get("gather_target_after", "")).is_empty())
	var safe_resume_observed: bool = helper.get("events").any(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_safely_returned_to_gathering" and str(event.get("worker_runtime_id", "")) == worker_id)
	var pending_retained_or_resolved: bool = helper.get("evacuated_worker_ids").has(worker_id) or safe_resume_observed or helper.get("events").any(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_lost_before_safe_resume" and str(event.get("worker_runtime_id", "")) == worker_id)
	var reroute_protection: bool = reroute_attempt_bound and safe_move_records and unsafe_gather_orders.is_empty() and pending_retained_or_resolved
	var trace: Array = helper.get("fixture_trace")
	var pursued_movement := false
	if trace.size() >= 2 and not bool(trace[-1].get("pursuer_alive", false)):
		pursued_movement = true
	elif trace.size() >= 2:
		var first_position: Array = trace[0].get("pursuer_position", [])
		var last_position: Array = trace[-1].get("pursuer_position", [])
		if first_position.size() >= 3 and last_position.size() >= 3:
			pursued_movement = Vector3(float(first_position[0]),float(first_position[1]),float(first_position[2])).distance_to(Vector3(float(last_position[0]),float(last_position[1]),float(last_position[2]))) > 0.2
	test_results["fixture_run_completed"] = {"passed":true,"reason":reason,"game_seconds":float(game.get("_game_time"))-start_game_time,"target_window_game_seconds":MAX_GAME_SECONDS,"wall_seconds":float(Time.get_ticks_msec()-started_msec)/1000.0}
	var interception_resolved: bool = not is_instance_valid(pursuer) or not bool(pursuer.get("alive")) or (pursuer.get("attack_target") != worker and pursuer.global_position.distance_to(worker.global_position) >= 14.0)
	test_results["reroute_protection_passed"] = {"passed":reroute_protection,"behavior":behavior,"accepted_reroutes":moves.size(),"reroute_required":not interception_resolved,"reroute_not_required_reason":"live defense intercepted/repelled the only forced pursuer before a persistent unsafe route required another Move" if interception_resolved and moves.is_empty() else "persistent unsafe pressure","candidate_rejections":rejected,"attempts":reroute_attempts,"attempt_limit":3,"unsafe_gather_orders":unsafe_gather_orders,"safe_resume_observed":safe_resume_observed,"pending_retained_or_resolved":pending_retained_or_resolved,"no_unsafe_resume_enforced":true}
	test_results["survival_passed"] = {"passed":surviving,"alive_at_end":surviving,"hp_at_end":float(worker.get("hp")) if is_instance_valid(worker) else 0.0,"controller_loss_event":helper.get("events").any(func(event: Dictionary) -> bool: return str(event.get("action", "")) == "withdrawn_worker_lost_before_safe_resume" and str(event.get("worker_runtime_id", "")) == worker_id)}
	test_results["real_new_harvest_deposit_passed"] = {"passed":full_chain,"explicit_failure":not full_chain,"reason":"same-worker post-resume harvest and deposit receipt observed" if full_chain else "bounded fixture ended without same-worker post-resume harvest plus deposit receipt","receipts":chain_receipts}
	test_results["pursuer_updated_and_defense_live"] = {"passed":pursued_movement,"pursuer_position_or_alive_changed":pursued_movement,"pursuer_final":_entity_state(pursuer) if is_instance_valid(pursuer) else {"alive":false},"guards_left_active":true,"tower_left_active":true,"trace_sample_count":trace.size()}
	test_results["R41_retakeover_attribution"] = {"status":"unknown_from_R41_evidence","evidence":"R41 observer shows gather_target remained after an accepted Move, but no Main gather/build event for this worker follows the Move; Villager._exec_move clears gather/drop/resume/build/attack fields. R41 did not record order_queue transitions or internal return resumption, so the reasserting caller cannot be uniquely attributed."}
	_finish(true, reason)

func _entity_state(item: Node3D) -> Dictionary:
	var target: Variant = item.get("attack_target")
	return {"name":str(item.name),"runtime_id":str(item.get_instance_id()),"position":_v3(item.global_position),"hp":float(item.get("hp")),"alive":bool(item.get("alive")),"state":int(item.get("state")),"attack_target":_node_name(target)}

func _living_villagers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for item in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(item) and str(item.get("team")) == "player" and bool(item.get("alive")): out.append(item as Node3D)
	return out

func _living_zombies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for item in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(item) and bool(item.get("alive")): out.append(item as Node3D)
	return out

func _nearest_wood_source(from: Node3D) -> Node3D:
	var best: Node3D
	var best_distance := INF
	for item in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(item) or not item.has_method("res_key") or str(item.call("res_key")) != "wood" or int(item.get("amount")) <= 0: continue
		var distance: float = from.global_position.distance_squared_to(item.global_position)
		if distance < best_distance: best_distance=distance; best=item as Node3D
	return best

func _node_name(value: Variant) -> String:
	return str(value.name) if is_instance_valid(value) else ""

func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _finish(passed: bool, reason: String) -> void:
	if done: return
	done = true
	var data := {"schema":2,"run_id":run_id,"behavior":behavior,"status":"fixture_completed" if passed else "setup_failed","fixture_run_complete":passed,"reason":reason,"fixture":true,"natural_gameplay_result":false,"seed":int(game.get("map_seed")) if is_instance_valid(game) else -1,"mode":int(game.get("_horde_mode")) if is_instance_valid(game) else -1,"saved_game_time":230.004932333475,"start_game_time":start_game_time,"end_game_time":float(game.get("_game_time")) if is_instance_valid(game) else -1.0,"worker":_entity_state(worker) if is_instance_valid(worker) else {},"pursuer":_entity_state(pursuer) if is_instance_valid(pursuer) else {},"fixture_mutations":fixture_mutations,"test_results":test_results,"controller_events":helper.get("events") if is_instance_valid(helper) else [],"trace":helper.get("fixture_trace") if is_instance_valid(helper) else [],"max_threatened_workers":_max_threatened_count(helper.get("fixture_trace")) if is_instance_valid(helper) else 0,"R41_retakeover_attribution":test_results.get("R41_retakeover_attribution",{}),"supervision_data_written":false,"engine_pid":OS.get_process_id(),"headless":DisplayServer.get_name()=="headless"}
	var file := FileAccess.open(RESULT_PATH,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data,"\t")); file.close()
	print("[worker_chase_reroute_fixture_result] ",JSON.stringify({"run_id":run_id,"status":data.status,"reason":reason,"behavior":behavior,"result_path":RESULT_PATH,"fixture_run_complete":passed,"product_results":test_results}))
	get_tree().quit(0 if passed else 1)

func _max_threatened_count(trace: Array) -> int:
	var maximum := 0
	for row in trace: maximum=maxi(maximum,int(row.get("all_threatened_workers_count",0)))
	return maximum

func _same_worker_chain_deposited() -> bool:
	for event in helper.get("events"):
		if str(event.get("action", "")) == "withdrawn_worker_production_deposit_receipt" and str(event.get("worker_runtime_id", "")) == worker_id and bool(event.get("receipt_has_post_resume_harvest", false)):
			return true
	return false

func _last_worker_deposit_time() -> float:
	var result := -INF
	for event in helper.get("events"):
		if str(event.get("action", "")) == "withdrawn_worker_production_deposit_receipt" and str(event.get("worker_runtime_id", "")) == worker_id and bool(event.get("receipt_has_post_resume_harvest", false)):
			result = maxf(result,float(event.get("game_time", -INF)))
	return result
