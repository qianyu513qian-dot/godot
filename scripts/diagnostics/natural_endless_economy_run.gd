extends Node
## Bounded, unscaled natural Endless campaign with production-command automation.
## This is an automated diagnostic controller, not ordinary mouse-play acceptance.

const CATALOG := preload("res://scripts/building_catalog.gd")
const RESOURCE := preload("res://scripts/resource_node.gd")
const PATHFIND := preload("res://scripts/pathfind.gd")
const COMBAT := preload("res://scripts/combat.gd")
const BUILDING_SCRIPT := preload("res://scripts/building.gd")
const SOLDIER_SCRIPT := preload("res://scripts/soldier.gd")

var run_id := "missing-run-id"
var exe_hash := ""
var pck_hash := ""
var source_hash := ""
var report: Dictionary = {}
var events: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var worker_roles: Dictionary = {}
var builder_assignments: Dictionary = {}
var probe_food_deposits: Array[Dictionary] = []
var probe_observed_workers: Dictionary = {}
var next_sample_game_time := 0.0
var next_maintenance_game_time := 0.0
var last_wave := 0
var wave6_started_at := -1.0
var save_restore_done := false
var busy := false
var finished := false
var defense_profile := ""
var defense_next_sample := 0.0
var defense_wave6_start := -1.0
var defense_restore_done := false
var arrow_seen: Dictionary = {}
var projectile_records: Dictionary = {}
var projectile_hp_seen: Dictionary = {}
var tower_min_route_distances: Dictionary = {}
var opening_started := false
var wave1_gate_checked := false
var wave1_spawned_names: Dictionary = {}
var wave1_pending_last_seen := -1
var active_intercept: Dictionary = {}
var last_counterattack_alert_review_msec := 0
var guard_return_experiment := false
var recovery_window_enabled := false
var recovery_window_started := false
var recovery_window_passed := false
var recovery_window_end := -1.0
var recovery_worker_id := 0
var recovery_initial_wood := 0
var recovery_initial_meat := 0
var recovery_initial_hp := 0.0
var recovery_deposits := 0
var recovery_deposit_log: Array[Dictionary] = []
var recovery_start_failure_reason := ""
var recovery_command_chain_ok := false
var recovery_probe_only := false
var recovery_probe_started_at := -1.0
var recovery_probe_initial_carry := 0
var recovery_probe_initial_resource_amount := 0
var recovery_staging_point := Vector3.ZERO
var recovery_probe_resource_id := 0
var recovery_probe_last_resource_amount := -1
var recovery_probe_last_carry := -1
var recovery_probe_reached_staging := false
var recovery_probe_resource_decreased := false
var recovery_probe_new_carry := false
var recovery_probe_new_carry_at := -1.0
var recovery_probe_deposit_after_new_carry := false
var cooperative_protection_probe := false
var cooperative_command_probe_only := false
var cooperative_protection_active := false
var cooperative_protection_complete := false
var cooperative_staging := Vector3.ZERO
var cooperative_started_at := -1.0
var cooperative_worker_id := 0
var cooperative_resource_id := 0
var cooperative_initial_wood := 0
var cooperative_initial_meat := 0
var cooperative_resource_amount_baseline := -1
var cooperative_carry_baseline := 0
var cooperative_last_resource_amount := -1
var cooperative_last_carry := -1
var cooperative_resource_reduced := false
var cooperative_new_carry := false
var cooperative_new_carry_at := -1.0
var cooperative_deposit_after_new_carry := false
var cooperative_reached_staging := false
var cooperative_gather_resumed := false
var cooperative_attack_targets: Array[Dictionary] = []
var cooperative_attackers: Array[int] = []
var cooperative_preserved_guards: Array[Dictionary] = []
var cooperative_tower_id := 0
var cooperative_paid_reinforcement_queued := false
var cooperative_initial_soldier_count := 0
var cooperative_initial_farm_stock := 0
var cooperative_initial_resource_id := 0
var cooperative_deadline := -1.0
var cooperative_last_worker_position := Vector3.ZERO
var cooperative_last_worker_hp := 0.0
var cooperative_last_skip_reason := ""
var cooperative_last_skip_msec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	run_id = _arg(args, "run-id", "missing-run-id")
	exe_hash = _arg(args, "exe-sha256", "")
	pck_hash = _arg(args, "pck-sha256", "")
	source_hash = _arg(args, "source-sha256", "")
	Engine.time_scale = 1.0
	Engine.max_fps = 60
	report = {"schema":"natural_endless_economy_run_v1","run_id":run_id,"controller":"res://scripts/diagnostics/natural_endless_economy_run.gd","controller_mode":"automated player-command diagnostic; not ordinary mouse-play acceptance","executable":OS.get_executable_path(),"exe_sha256":exe_hash,"pck_sha256":pck_hash,"source_sha256":source_hash,"pid":OS.get_process_id(),"user_data_dir":OS.get_user_data_dir(),"headless":DisplayServer.get_name() == "headless","requested_seed":42,"requested_horde_mode":"endless","difficulty":"standard/default; production menu has no difficulty selector","time_scale":Engine.time_scale,"natural_match":true,"unit_resource_hp_wave_time_or_damage_injection":false,"diagnostic_fixture_entities_injected":false}
	if _arg(args, "parse-only", "false") == "true":
		print("[natural-endless] controller_parse_ok run_id=%s" % run_id)
		get_tree().quit()
		return
	if DisplayServer.get_name() != "headless":
		_finish(false, "headless_required")
		return
	var menu: Node = await _wait_for_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 600)
	if menu == null:
		_finish(false, "production_menu_not_ready")
		return
	var mode: OptionButton = menu.get("_start_mode_select")
	var seed: LineEdit = menu.get("_seed_edit")
	var start: Button = menu.get("_start_begin_button")
	if mode == null or seed == null or start == null:
		_finish(false, "production_menu_controls_missing")
		return
	mode.select(0)
	mode.item_selected.emit(0)
	seed.text = "42"
	events.append({"at":"menu","action":"production_start_menu_selection","mode_id":mode.get_selected_id(),"seed_text":seed.text,"route":"OptionButton item_selected and production Start button pressed signal","ordinary_mouse_ui_verified":false})
	start.pressed.emit()
	var game: Node = await _wait_for_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 3600)
	if game == null:
		_finish(false, "production_seed42_match_start_failed")
		return
	if int(game.get("map_seed")) != 42 or int(game.get("_horde_mode")) != 0 or Engine.time_scale != 1.0:
		_finish(false, "production_match_parameters_mismatch", {"seed":game.get("map_seed"),"mode":game.get("_horde_mode"),"time_scale":Engine.time_scale})
		return
	if _arg(args, "projectile-lifecycle-regression", "false") == "true":
		await _run_projectile_lifecycle_regression(game)
		return
	if _arg(args, "guard-attack-return-regression", "false") == "true":
		await _run_guard_attack_return_regression(game)
		return
	if _arg(args, "villager-evacuation-regression", "false") == "true":
		var startup_unit: Node = _living_villagers()[0] if not _living_villagers().is_empty() else null
		if startup_unit == null:
			_finish(false,"startup_readiness_probe_no_villager")
			return
		game.call("_clear_selection")
		game.call("_add_to_selection",startup_unit)
		var startup_initial_position: Vector3 = startup_unit.global_position
		var premature_goal: Vector3 = startup_initial_position + Vector3(0,0,5)
		game.call("_command_at",premature_goal)
		var premature_order_rejected: bool = int(startup_unit.get("state")) == 0 and startup_unit.get("_goal_final").distance_to(premature_goal) > 0.1
		var ready_wait_frames := 0
		for frame in 180:
			if bool(game.get("_player_orders_ready")):
				ready_wait_frames = frame
				break
			await get_tree().process_frame
		var ready_initial_position: Vector3 = startup_unit.global_position
		var ready_goal: Vector3 = startup_unit.global_position + Vector3(0,0,6)
		game.call("_command_at",ready_goal)
		var startup_order_accepted: bool = int(startup_unit.get("state")) == 1 and startup_unit.get("_goal_final").distance_to(startup_initial_position) > 0.1
		for _frame in 4: await get_tree().process_frame
		var startup_order_survived_boot: bool = is_instance_valid(startup_unit) and startup_unit.global_position.distance_to(ready_initial_position) < 0.75 and (int(startup_unit.get("state")) == 1 or startup_unit.get("_goal_final").distance_to(ready_goal) < 0.1)
		var startup_readiness := {"passed":premature_order_rejected and bool(game.get("_player_orders_ready")) and startup_order_accepted and startup_order_survived_boot,"player_orders_ready":bool(game.get("_player_orders_ready")),"premature_order_rejected":premature_order_rejected,"ready_order_accepted":startup_order_accepted,"ready_order_survived_boot":startup_order_survived_boot,"ready_wait_frames":ready_wait_frames,"unit_id":startup_unit.get_instance_id(),"preboot_position":_v3(startup_initial_position),"ready_position":_v3(ready_initial_position),"current_position":_v3(startup_unit.global_position),"goal":_v3(startup_unit.get("_goal_final"))}
		report["startup_order_readiness"] = startup_readiness
		events.append({"action":"production_input_waits_for_post_spawn_boot","details":startup_readiness})
		if not bool(startup_readiness.get("passed")):
			_finish(false,"startup_order_readiness_regression_failed",startup_readiness)
			return
		await _run_villager_evacuation_regression(game)
		return
	defense_profile = _arg(args, "defense-profile", "")
	guard_return_experiment = _arg(args, "guard-return-experiment", "false") == "true"
	recovery_probe_only = _arg(args,"recovery-command-probe","false") == "true"
	cooperative_protection_probe = _arg(args,"cooperative-protection-probe","false") == "true"
	cooperative_command_probe_only = _arg(args,"cooperative-command-probe-only","false") == "true"
	recovery_window_enabled = _arg(args,"recovery-window","false") == "true" or recovery_probe_only or cooperative_protection_probe
	if defense_profile in ["preflight", "campaign"]:
		var ready_wait_frames := 0
		for frame in 180:
			if bool(game.get("_player_orders_ready")):
				ready_wait_frames = frame
				break
			await get_tree().process_frame
		if not bool(game.get("_player_orders_ready")):
			_finish(false,"defense_controller_started_before_player_orders_ready")
			return
		if _arg(args,"cooperative-route-preflight-only","false")=="true":
			_run_cooperative_historical_route_preflight(game)
			return
		events.append({"action":"defense_strategy_waited_for_player_orders_ready","ready_wait_frames":ready_wait_frames})
		await _run_defense_strategy(game, defense_profile)
		return
	if _arg(args,"selection-regression","false")=="true":
		await _run_general_selection_regression(game)
		return
	if _arg(args, "construction-reassignment-probe", "false") == "true":
		await _run_construction_reassignment_probe(game)
		return
	if _arg(args, "construction-causality-probe", "false") == "true":
		await _run_construction_causality_probe(game)
		return
	if _arg(args, "paid-opening-probe", "false") == "true":
		await _run_paid_opening_probe(game)
		return
	var start_snapshot := _snapshot(game, "match_started")
	snapshots.append(start_snapshot)
	var workers := _living_villagers()
	if workers.size() != 5:
		_finish(false, "clean_start_villager_count_mismatch", {"villagers":workers.size()})
		return
	for index in workers.size():
		_assign_worker(game, workers[index], "stone" if index == 0 else "wood", "opening resource plan")
	var starting_buildings := get_tree().get_nodes_in_group("buildings").size()
	if starting_buildings != 1:
		_finish(false, "clean_start_building_count_mismatch", {"buildings":starting_buildings})
		return
	var match_id := game.get_instance_id()
	var world_id := (game.get("world") as Node).get_instance_id()
	events.append({"at":"match_started","action":"natural_campaign_started","seed":42,"mode":0,"difficulty":"standard/default","time_scale":Engine.time_scale,"villagers":workers.size(),"buildings":starting_buildings,"injected_entities":0,"injected_resources":0})
	var wall_start_usec := Time.get_ticks_usec()
	while not finished:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			_finish(false, "main_game_disappeared")
			return
		var game_time := float(game.get("_game_time"))
		var wave := int(game.get("_horde_wave"))
		if wave != last_wave:
			last_wave = wave
			var wave_snapshot := _snapshot(game, "wave_%d_started" % wave)
			snapshots.append(wave_snapshot)
			events.append({"at":"wave_boundary","action":"natural_wave_started","wave":wave,"game_time":game_time,"snapshot_index":snapshots.size()-1})
			if wave >= 6 and wave6_started_at < 0.0:
				wave6_started_at = game_time
		if game_time >= next_sample_game_time:
			next_sample_game_time = game_time + 10.0
			snapshots.append(_snapshot(game, "periodic"))
		if bool(game.get("_defeated")) or bool(game.get("_victorious")):
			snapshots.append(_snapshot(game, "terminal"))
			_finish(false, "natural_campaign_terminal_before_hold_complete", {"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious")),"game_time":game_time,"wave":wave})
			return
		if game_time >= 900.0:
			_finish(false, "natural_campaign_simulation_limit", {"game_time":game_time,"wave":wave})
			return
		if wave6_started_at >= 0.0 and game_time - wave6_started_at >= 45.0:
			snapshots.append(_snapshot(game, "wave6_active_hold_complete"))
			report["natural_wave6_hold_seconds"] = game_time - wave6_started_at
			report["natural_wave6_reached"] = true
			_finish(true, "natural_endless_wave6_and_active_hold_verified")
			return
		if not save_restore_done and wave >= 2 and game_time >= 290.0 and not busy:
			busy = true
			var restore_ok := await _save_and_restore(game)
			busy = false
			save_restore_done = true
			if not restore_ok:
				_finish(false, "mid_campaign_production_save_restore_failed")
				return
		if game_time >= next_maintenance_game_time and not busy:
			next_maintenance_game_time = game_time + 2.0
			busy = true
			await _maintain_economy(game)
			busy = false
		if match_id != game.get_instance_id() or world_id != (game.get("world") as Node).get_instance_id():
			_finish(false, "same_seed_restore_rebuilt_main_or_world_unexpectedly")
			return
		if (Time.get_ticks_usec() - wall_start_usec) > 2400 * 1000000:
			_finish(false, "natural_campaign_wall_timeout", {"game_time":game_time,"wave":wave})
			return

func _maintain_economy(game: Node) -> void:
	if not is_instance_valid(game) or bool(game.get("_defeated")):
		return
	var game_time := float(game.get("_game_time"))
	var alive_workers := _living_villagers()
	var farms := _live_farms()
	_reassign_unstaffed_foundations(game, alive_workers)
	# Keep one ordinary paid Forestry upgrade in the plan as soon as its catalog cost is available.
	if game.get("research") != null and not bool(game.get("research").call("has_technology", "improved_axes")) and int(game.get("meat")) >= 25 and int(game.get("wood")) >= 10:
		game.call("_on_research_forestry")
		events.append({"at_game_time":game_time,"action":"production_research_forestry_requested","meat_after":game.get("meat"),"wood_after":game.get("wood")})
	# Pay real catalog costs through the normal placement handler; villagers build the resulting foundations.
	if _building_count(game, CATALOG.HOUSE) == 0 and int(game.get("wood")) >= 50 and not alive_workers.is_empty():
		await _place_building(game, CATALOG.HOUSE, "house", [Vector3(10,0,8),Vector3(-10,0,8),Vector3(10,0,-8),Vector3(-10,0,-8)])
		return
	if _building_count(game, CATALOG.FARM) == 0 and int(game.get("wood")) >= 75 and not alive_workers.is_empty():
		await _place_building(game, CATALOG.FARM, "first_farm", [Vector3(12,0,0),Vector3(-12,0,0),Vector3(0,0,12),Vector3(0,0,-12)])
		return
	if _building_count(game, CATALOG.BARRACKS) == 0 and int(game.get("wood")) >= 150 and not alive_workers.is_empty():
		await _place_building(game, CATALOG.BARRACKS, "barracks", [Vector3(-12,0,0),Vector3(12,0,8),Vector3(-12,0,-8)])
		return
	# Add housing only when the real population cap is close to full.
	var queued_pop := int(game.call("_queued_pop"))
	if int(game.get("pop_cap")) - int(game.get("population")) - queued_pop <= 2 and int(game.get("wood")) >= 50 and not alive_workers.is_empty():
		var houses := _building_count(game, CATALOG.HOUSE)
		if houses < 3:
			await _place_building(game, CATALOG.HOUSE, "population_house", [Vector3(10,0,14),Vector3(-10,0,14),Vector3(14,0,8),Vector3(-14,0,8),Vector3(0,0,15)])
			return
	# Keep farms productive by reseeding with the production R handler, which charges its real wood cost.
	for farm in farms:
		if int(farm.get("meat_stock")) <= 0 and int(game.get("wood")) >= 25:
			_select(game, [farm])
			game.call("_on_reseed_farm")
			events.append({"at_game_time":game_time,"action":"production_farm_reseed_requested","farm":farm.name,"wood_after":game.get("wood"),"stock_after":farm.get("meat_stock")})
			return
	if not farms.is_empty() and _total_farm_stock(farms) < 120 and int(game.get("wood")) >= 75 and farms.size() < 4 and not alive_workers.is_empty():
		await _place_building(game, CATALOG.FARM, "food_reserve_farm", [Vector3(14,0,-8),Vector3(-14,0,-8),Vector3(8,0,14),Vector3(-8,0,14),Vector3(0,0,-15)])
		return
	# Build three paid Arrow Towers around the working area where the Town Center hub permits construction.
	var towers := _building_count(game, CATALOG.ARROW_TOWER)
	if towers < 3 and int(game.get("wood")) >= 100 and int(game.get("stone")) >= 50 and not alive_workers.is_empty():
		var tower_candidates: Array = [[Vector3(8,0,-6),Vector3(8,0,6),Vector3(10,0,0)],[Vector3(-8,0,-6),Vector3(-8,0,6),Vector3(-10,0,0)],[Vector3(0,0,10),Vector3(0,0,-10),Vector3(6,0,10)]][towers]
		await _place_building(game, CATALOG.ARROW_TOWER, "arrow_tower_%d" % (towers+1), tower_candidates)
		return
	# Rebalance only when an existing production order is absent or its target is depleted.
	_assign_economy_roles(game, alive_workers, farms)
	# Queue real units only through the same menu production handlers and obey population/cost checks.
	if int(game.get("pop_cap")) - int(game.get("population")) - queued_pop > 0:
		var villager_target := 8 if int(game.get("_horde_wave")) < 2 else 10
		if not farms.is_empty() and alive_workers.size() < villager_target and int(game.get("meat")) >= 100 and _queue_count(game, "villager") == 0:
			game.call("_queue_train", "villager")
			events.append({"at_game_time":game_time,"action":"production_queue_villager","workers":alive_workers.size(),"meat_after":game.get("meat"),"queued":game.call("_queued_pop")})
			return
		var desired_soldiers := 5 + int(game.get("_horde_wave")) * 2
		var military := _player_soldiers()
		if military.size() + _queue_count(game, "soldier") < desired_soldiers and int(game.get("meat")) >= 60 and int(game.get("wood")) >= 20 and _building_count_complete(game, CATALOG.BARRACKS) > 0:
			var barracks := _first_building(game, CATALOG.BARRACKS, true)
			if barracks != null:
				_select(game, [barracks])
				var meat_before := int(game.get("meat"))
				var wood_before := int(game.get("wood"))
				game.call("_on_train_soldier")
				events.append({"at_game_time":game_time,"action":"production_queue_soldier","army":military.size(),"meat_before":meat_before,"meat_after":game.get("meat"),"wood_before":wood_before,"wood_after":game.get("wood"),"queue":Array(barracks.get("train_queue"))})
				return
	# Take the available paid age-up when the game economy naturally reaches it.
	if int(game.get("research").get("age")) == 1 and int(game.get("meat")) >= 500 and int(game.get("gold")) >= 200:
		_select(game, [_first_building(game, CATALOG.TOWN_CENTER, true)])
		game.call("_on_age_up")
		events.append({"at_game_time":game_time,"action":"production_age_up_requested","age":game.get("research").get("age")})
	# Guard the real army at the farm/worker core rather than repeatedly sending it across the map.
	var live_zombies := _living_zombies()
	if not live_zombies.is_empty():
		var anchor := _defensive_anchor(farms, alive_workers)
		for soldier in _player_soldiers():
			if not bool(soldier.get("guard_active")) or soldier.get("guard_anchor").distance_to(anchor) > 3.0:
				soldier.call("command_guard", anchor)
				events.append({"at_game_time":game_time,"action":"production_guard_order","soldier":soldier.name,"anchor":_v3(anchor),"nearby_zombies":live_zombies.size()})

func _assign_economy_roles(game: Node, workers: Array, farms: Array) -> void:
	if workers.is_empty(): return
	var desired := {"food": 2 if int(game.get("meat")) < 180 else 1,"stone": 2 if _building_count(game,CATALOG.ARROW_TOWER) < 3 else 1,"wood": 3}
	# If the pressure is high, keep a larger food reserve and the rest of the workforce on wood/stone.
	if farms.is_empty(): desired["food"] = 0
	if int(game.get("_horde_wave")) >= 3:
		desired["food"] = 3 if not farms.is_empty() else 0
	var counts := {"food":0,"stone":0,"wood":0}
	for worker in workers:
		var role := str(worker_roles.get(str(worker.get_instance_id()), ""))
		if role.is_empty():
			role = _least_filled_role(counts, desired)
			worker_roles[str(worker.get_instance_id())] = role
		var target: Variant = worker.get("gather_target")
		var target_valid: bool = is_instance_valid(target) and target.is_inside_tree() and int(target.get("amount")) > 0 if target != null and not target.is_in_group("farms") else is_instance_valid(target) and int(target.get("meat_stock")) > 0 if target != null else false
		var target_role := "food" if target_valid and target.is_in_group("farms") else str(target.call("res_key")) if target_valid and target.has_method("res_key") else ""
		counts[role] = int(counts.get(role, 0)) + 1
		if counts[role] > int(desired.get(role,0)):
			counts[role] -= 1
			role = _least_filled_role(counts, desired)
			worker_roles[str(worker.get_instance_id())] = role
			counts[role] = int(counts.get(role,0)) + 1
		if not target_valid or target_role != role:
			_assign_worker(game, worker, role, "economy rebalance")

func _least_filled_role(counts: Dictionary, desired: Dictionary) -> String:
	var best := "wood"
	var best_ratio := INF
	for role in ["food","stone","wood"]:
		var target := int(desired.get(role,0))
		var ratio := float(counts.get(role,0)) / float(maxi(target,1)) if target > 0 else INF
		if ratio < best_ratio:
			best_ratio = ratio
			best = role
	return best

func _assign_worker(game: Node, worker: Node, role: String, reason: String) -> bool:
	if _reserved_building_site(worker) != null or int(worker.get("state")) == 4:
		return false
	var target: Node3D = null
	if role == "food":
		for farm in _live_farms():
			if int(farm.get("meat_stock")) > 0 and (target == null or worker.global_position.distance_squared_to(farm.global_position) < worker.global_position.distance_squared_to(target.global_position)):
				target = farm
	else:
		var kind := RESOURCE.Kind.WOOD if role == "wood" else RESOURCE.Kind.STONE if role == "stone" else RESOURCE.Kind.GOLD
		target = _nearest_resource(kind, worker.global_position)
	if target == null or not worker.has_method("command_gather"):
		return false
	var current: Variant = worker.get("gather_target")
	var current_role := "food" if is_instance_valid(current) and current.is_in_group("farms") else str(current.call("res_key")) if is_instance_valid(current) and current.has_method("res_key") else ""
	if current_role == role and is_instance_valid(current):
		worker_roles[str(worker.get_instance_id())] = role
		return false
	var active_site: Variant = worker.get("build_site")
	if is_instance_valid(active_site) and not bool(active_site.get("is_complete")):
		var goal: Vector3 = worker.get("_goal_final")
		var builder_in_range := bool(active_site.call("is_builder_in_range", worker.global_position)) if active_site.has_method("is_builder_in_range") else false
		var blocked_at_worker := bool(active_site.call("blocks_unit_at", worker.global_position, worker.get("team"), float(worker.get("radius")))) if active_site.has_method("blocks_unit_at") else false
		events.append({"at_game_time":float(game.get("_game_time")),"action":"production_order_overrode_active_build","worker":worker.name,"state":int(worker.get("state")),"site":active_site.name,"site_kind":int(active_site.get("kind")),"site_progress":float(active_site.get("build_progress")),"site_build_time":float(active_site.get("build_time")),"goal":_v3(goal),"position":_v3(worker.global_position),"distance_to_site":worker.global_position.distance_to(active_site.global_position),"builder_in_range":builder_in_range,"blocked_at_worker":blocked_at_worker,"waypoint_count":Array(worker.get("_waypoints")).size(),"new_role":role,"new_target":target.name,"reason":reason})
	worker.call("command_gather", target)
	worker_roles[str(worker.get_instance_id())] = role
	events.append({"at_game_time":float(game.get("_game_time")),"action":"production_gather_order","worker":worker.name,"role":role,"target":target.name,"target_position":_v3(target.global_position),"reason":reason,"command":"Villager3D.command_gather"})
	return true

func _place_building(game: Node, kind: int, label: String, candidates: Array) -> void:
	var builder: Node3D = _builder_candidate()
	if builder == null:
		events.append({"at_game_time":float(game.get("_game_time")),"action":"production_building_waiting_for_builder","intent":label,"kind":kind,"reason":"no unreserved builder with empty carry"})
		return
	var old_ids := _building_id_set(kind)
	_select(game, [builder])
	game.call("_on_build_kind", kind)
	for position in candidates:
		var legal := bool(game.call("_placement_valid_at", position))
		if not legal: continue
		game.call("_try_place", position)
		await get_tree().process_frame
		var building := _new_building(kind, old_ids, position)
		if building != null:
			builder_assignments[str(builder.get_instance_id())] = building
			events.append({"at_game_time":float(game.get("_game_time")),"action":"production_building_placed","intent":label,"kind":kind,"position":_v3(building.global_position),"cost_paid":true,"builder":builder.name,"complete":bool(building.get("is_complete")),"command":"_on_build_kind → _placement_valid_at → _try_place → Villager3D.command_build"})
			return
	events.append({"at_game_time":float(game.get("_game_time")),"action":"production_building_unavailable","intent":label,"kind":kind,"wood":game.get("wood"),"stone":game.get("stone"),"living_villagers":_living_villagers().size(),"legal_candidates":0})

func _save_and_restore(game: Node) -> bool:
	var world_before := (game.get("world") as Node).get_instance_id()
	var main_before := game.get_instance_id()
	var time_before := float(game.get("_game_time"))
	var wave_before := int(game.get("_horde_wave"))
	var worker_ids_before: Array[int] = []
	for worker in _living_villagers(): worker_ids_before.append(int(worker.get_instance_id()))
	var guard_intents_before: Array[Dictionary] = _soldier_guard_intents()
	await _send_key(KEY_ESCAPE)
	if not get_tree().paused:
		events.append({"at_game_time":time_before,"action":"midrun_restore_failed","reason":"production_pause_input_not_accepted"})
		return false
	await _send_key(KEY_F5)
	await get_tree().process_frame
	var save_hash := FileAccess.get_sha256("user://aoelite3d_save.json") if FileAccess.file_exists("user://aoelite3d_save.json") else ""
	if save_hash.is_empty():
		events.append({"at_game_time":time_before,"action":"midrun_restore_failed","reason":"production_f5_save_missing"})
		return false
	var attack_ref_audit := _audit_saved_attack_refs("user://aoelite3d_save.json")
	var expected_attack_refs := 1 if _active_intercept_is_live() else 0
	if not bool(attack_ref_audit.get("passed",false)) or int(attack_ref_audit.get("resolved_enemy_attack_refs",0)) < expected_attack_refs:
		events.append({"at_game_time":time_before,"action":"midrun_restore_failed","reason":"saved_active_attack_id_missing_or_unresolved","attack_reference_audit":attack_ref_audit,"expected_attack_refs":expected_attack_refs})
		return false
	var button := _find_button(game.get("_pause_layer"), "读取存档（F9）")
	if button == null:
		events.append({"at_game_time":time_before,"action":"midrun_restore_failed","reason":"production_f9_button_missing"})
		return false
	button.pressed.emit()
	if not await _wait_until(func() -> bool: return get_tree().paused and not bool(game.get("_start_operation_busy")) and game.get("_pending_restore").is_empty(), 600):
		events.append({"at_game_time":time_before,"action":"midrun_restore_failed","reason":"production_f9_restore_timeout"})
		return false
	await get_tree().process_frame
	var restored := game.get_instance_id() == main_before and (game.get("world") as Node).get_instance_id() == world_before and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 0 and int(game.get("_horde_wave")) == wave_before and absf(float(game.get("_game_time")) - time_before) < 0.05 and FileAccess.get_sha256("user://aoelite3d_save.json") == save_hash
	events.append({"at_game_time":time_before,"action":"production_f5_f9_midrun_restore","passed":restored,"route":"Esc input → F5 input → pause-menu F9 Button.pressed","main_reused":game.get_instance_id() == main_before,"world_reused":(game.get("world") as Node).get_instance_id() == world_before,"saved_hash":save_hash,"saved_hash_unchanged":FileAccess.get_sha256("user://aoelite3d_save.json") == save_hash,"wave_before":wave_before,"wave_after":game.get("_horde_wave"),"game_time_before":time_before,"game_time_after":game.get("_game_time"),"paused_after_restore":get_tree().paused,"unit_counts":_unit_counts(),"attack_reference_audit":attack_ref_audit})
	if not restored: return false
	worker_roles.clear()
	builder_assignments.clear()
	var rebound_builders := 0
	var worker_ids_after: Array[int] = []
	for worker in _living_villagers():
		worker_ids_after.append(int(worker.get_instance_id()))
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target):
			var role := "food" if target.is_in_group("farms") else str(target.call("res_key")) if target.has_method("res_key") else ""
			if not role.is_empty(): worker_roles[str(worker.get_instance_id())]=role
		var site: Variant = worker.get("build_site")
		if is_instance_valid(site) and not bool(site.get("is_complete")):
			builder_assignments[str(worker.get_instance_id())]=site
			rebound_builders += 1
	var rebound_valid := true
	for worker in _living_villagers():
		var site: Variant = worker.get("build_site")
		if is_instance_valid(site) and not bool(site.get("is_complete")) and builder_assignments.get(str(worker.get_instance_id())) != site:
			rebound_valid=false
	var guard_intents_after: Array[Dictionary] = _soldier_guard_intents()
	var guard_intents_preserved := guard_intents_before.size() == guard_intents_after.size()
	if guard_intents_preserved:
		for index in guard_intents_before.size():
			var before_anchor: Array = guard_intents_before[index].get("guard_anchor", [])
			var after_anchor: Array = guard_intents_after[index].get("guard_anchor", [])
			var before_resolved: Array = guard_intents_before[index].get("resolved_anchor", [])
			var after_resolved: Array = guard_intents_after[index].get("resolved_anchor", [])
			var before_target_pos: Array = guard_intents_before[index].get("target_pos", [])
			var after_target_pos: Array = guard_intents_after[index].get("target_pos", [])
			var raw_matches := before_anchor.size() == 3 and after_anchor.size() == 3 and Vector3(before_anchor[0],before_anchor[1],before_anchor[2]).distance_to(Vector3(after_anchor[0],after_anchor[1],after_anchor[2])) <= 0.01
			var resolved_matches := before_resolved.size() == 3 and after_resolved.size() == 3 and Vector3(before_resolved[0],before_resolved[1],before_resolved[2]).distance_to(Vector3(after_resolved[0],after_resolved[1],after_resolved[2])) <= 0.01
			var anchors_match := not bool(guard_intents_before[index].get("guard_active")) or (bool(guard_intents_after[index].get("guard_active")) and raw_matches and resolved_matches)
			var target_presence_matches := bool(guard_intents_before[index].get("target_present")) == bool(guard_intents_after[index].get("target_present"))
			var target_signature_matches := not bool(guard_intents_before[index].get("target_present")) or (int(guard_intents_before[index].get("target_wave")) == int(guard_intents_after[index].get("target_wave")) and before_target_pos.size() == 3 and after_target_pos.size() == 3 and Vector3(before_target_pos[0],before_target_pos[1],before_target_pos[2]).distance_to(Vector3(after_target_pos[0],after_target_pos[1],after_target_pos[2])) <= 0.05)
			if bool(guard_intents_before[index].get("guard_active")) != bool(guard_intents_after[index].get("guard_active")) or not anchors_match or not bool(guard_intents_after[index].get("target_valid")) or not target_presence_matches or not target_signature_matches:
				guard_intents_preserved = false
				break
	var intercept_rebound := _rebind_active_intercept_after_restore()
	events.append({"at_game_time":time_before,"action":"defense_continue_new_instance_references_rebound","worker_instance_ids_before":worker_ids_before,"worker_instance_ids_after":worker_ids_after,"worker_ids_changed":worker_ids_before!=worker_ids_after,"active_builders_rebound":rebound_builders,"builder_refs_valid":rebound_valid,"gather_roles_rebuilt":worker_roles.duplicate(true),"soldier_guard_intents_before":guard_intents_before,"soldier_guard_intents_after":guard_intents_after,"soldier_guard_intents_preserved":guard_intents_preserved,"saved_attack_reference_audit":attack_ref_audit,"active_attack_target_rebound":intercept_rebound})
	await _send_key(KEY_ESCAPE)
	return not get_tree().paused and rebound_valid and guard_intents_preserved and intercept_rebound

func _run_guard_attack_return_regression(game: Node) -> void:
	## Production Main + ordinary menu start. Fixtures are confined to this
	## regression path; F5/F9 use the same real input and pause UI as a player.
	report["diagnostic_fixture_entities_injected"] = true
	report["campaign_result_is_natural_match"] = false
	var world: Node3D = game.get("world")
	var anchor := Vector3(20.0, 0.0, 20.0)
	var start := Vector3(17.0, 0.0, 20.0)
	var marker := 90001
	var attacker = SOLDIER_SCRIPT.new()
	attacker.name = "GuardReturn_SaveLoad_Fixture"
	world.add_child(attacker)
	attacker.setup(start, "player", false)
	var target = SOLDIER_SCRIPT.new()
	target.name = "GuardReturn_SaveLoad_Target"
	world.add_child(target)
	target.setup(start + Vector3(0.7, 0.0, 0.0), "player", true)
	target.set("horde_wave_id", marker)
	attacker.command_guard(anchor)
	attacker.command_attack_unit(target)
	var old_attacker_id := attacker.get_instance_id()
	var old_target_id := target.get_instance_id()
	var attack_precondition: bool = int(attacker.state) == SOLDIER_SCRIPT.State.ATTACK and attacker.attack_target == target and bool(attacker.get("_attack_return_guard_active"))
	await _send_key(KEY_ESCAPE)
	var paused := get_tree().paused
	await _send_key(KEY_F5)
	var save_exists := FileAccess.file_exists("user://aoelite3d_save.json")
	var saved_return := false
	var saved_target_id := ""
	if save_exists:
		var file := FileAccess.open("user://aoelite3d_save.json", FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				for record in parsed.get("entities", {}).get("soldiers", []):
					if str(record.get("team", "")) == "player" and bool(record.get("attack_return_guard_active", false)):
						var raw_anchor: Array = record.get("attack_return_guard_anchor", [])
						saved_return = raw_anchor.size() == 3 and Vector3(raw_anchor[0], raw_anchor[1], raw_anchor[2]).distance_to(anchor) < 0.01
						saved_target_id = str(record.get("attack_id", ""))
						break
			file.close()
	var button := _find_button(game.get("_pause_layer"), "读取存档（F9）")
	if button == null:
		_finish(false, "guard_return_f9_button_missing", {"attack_precondition":attack_precondition,"paused":paused,"save_exists":save_exists,"saved_return":saved_return})
		return
	button.pressed.emit()
	var restore_completed := await _wait_until(func() -> bool: return get_tree().paused and not bool(game.get("_start_operation_busy")) and game.get("_pending_restore").is_empty(), 900)
	await get_tree().process_frame
	var restored_attacker: Node = null
	var restored_target: Node = null
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if str(unit.get("team")) == "player" and bool(unit.get("_attack_return_guard_active")) and unit.get("attack_target") != null:
			restored_attacker = unit
		if bool(unit.get("is_zombie")) and int(unit.get("horde_wave_id")) == marker:
			restored_target = unit
	var new_attacker_id := int(restored_attacker.get_instance_id()) if is_instance_valid(restored_attacker) else -1
	var new_target_id := int(restored_target.get_instance_id()) if is_instance_valid(restored_target) else -1
	var refs_restored: bool = is_instance_valid(restored_attacker) and is_instance_valid(restored_target) and restored_attacker.get("attack_target") == restored_target and not saved_target_id.is_empty()
	var ids_replaced := new_attacker_id != old_attacker_id and new_target_id != old_target_id
	var old_entities_invalid := not is_instance_valid(attacker) and not is_instance_valid(target)
	if is_instance_valid(restored_target):
		restored_target.call("take_damage", 10000.0, false, null)
	await _send_key(KEY_ESCAPE)
	var reached := false
	if is_instance_valid(restored_attacker):
		for _frame in 900:
			if restored_attacker.global_position.distance_to(anchor) <= 0.7 and int(restored_attacker.get("state")) == SOLDIER_SCRIPT.State.GUARD and bool(restored_attacker.get("guard_active")):
				reached = true
				break
			await get_tree().process_frame
	var details := {"route":"production Main → ordinary start → Esc → F5 key → pause F9 button","attack_precondition":attack_precondition,"paused_by_Esc":paused,"F5_save_exists":save_exists,"serialized_guard_return_anchor":saved_return,"saved_attack_reference_id":saved_target_id,"F9_completed":restore_completed,"old_attacker_id":old_attacker_id,"new_attacker_id":new_attacker_id,"old_target_id":old_target_id,"new_target_id":new_target_id,"ids_replaced":ids_replaced,"old_entities_invalidated":old_entities_invalid,"active_target_reference_restored":refs_restored,"restored_target_killed_while_paused":is_instance_valid(restored_target) and not bool(restored_target.get("alive")),"physically_reached_original_guard_anchor":reached,"final_position":_v3(restored_attacker.global_position) if is_instance_valid(restored_attacker) else []}
	var passed: bool = attack_precondition and paused and save_exists and saved_return and restore_completed and ids_replaced and old_entities_invalid and refs_restored and reached
	events.append({"action":"production_world_guard_attack_f5_f9_physical_return","passed":passed,"details":details})
	_finish(passed, "production_guard_attack_return_f5_f9_and_physical_guard_reach" if passed else "production_guard_attack_return_regression_failed", details)

func _run_villager_evacuation_regression(game: Node) -> void:
	## Player-directed evacuation: an existing damage alert focuses live victims;
	## the player-selected Move destination and Shift work order are preserved.
	report["diagnostic_fixture_entities_injected"] = true
	report["campaign_result_is_natural_match"] = false
	var world: Node3D = game.get("world")
	var workers := _living_villagers()
	if workers.size() < 3:
		_finish(false, "evacuation_regression_needs_three_real_villagers")
		return
	var evacuee: Node = workers[0]
	var builder: Node = workers[1]
	var order_override_unit: Node = workers[2]
	var resource: Node3D = null
	var best := INF
	for candidate in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or candidate.is_in_group("buildings") or int(candidate.get("kind")) != RESOURCE.Kind.WOOD or int(candidate.get("amount")) <= 0:
			continue
		var distance: float = evacuee.global_position.distance_to(candidate.global_position)
		if distance < best:
			best = distance
			resource = candidate
	if resource == null:
		_finish(false, "evacuation_regression_no_live_resource")
		return
	# Earn the ordinary House price from real wood nodes before testing queued
	# construction, so the foundation and its save reference are never free.
	var house_cost := int(CATALOG.get_def(CATALOG.HOUSE).get("cost_wood", 50))
	var paid_wood_workers: Array[Node] = [workers[3], workers[4]]
	for wood_worker in paid_wood_workers:
		var wood_source: Node3D = null
		var source_distance := INF
		for candidate in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(candidate) or candidate.is_in_group("buildings") or int(candidate.get("kind")) != RESOURCE.Kind.WOOD or int(candidate.get("amount")) <= 0:
				continue
			var distance: float = wood_worker.global_position.distance_to(candidate.global_position)
			if distance < source_distance:
				source_distance = distance
				wood_source = candidate
		if wood_source != null:
			wood_worker.command_gather(wood_source)
	var initial_paid_orders: Array[Dictionary] = []
	for wood_worker in paid_wood_workers:
		var immediate_target = wood_worker.get("gather_target")
		initial_paid_orders.append({"id":wood_worker.get_instance_id(),"alive":wood_worker.get("alive"),"state":int(wood_worker.get("state")),"target_id":immediate_target.get_instance_id() if is_instance_valid(immediate_target) else 0,"position":_v3(wood_worker.global_position),"goal":_v3(wood_worker.get("_goal_final")),"waypoints":Array(wood_worker.get("_waypoints")).size(),"manual_order_suppresses_auto_defense":bool(wood_worker.get("manual_order_suppresses_auto_defense")),"path_report":PATHFIND.last_path_report.duplicate(true)})
	var probe_samples: Array[Dictionary] = []
	var probe_resource_amount := int(resource.get("amount"))
	for frame in 600:
		if frame % 60 == 0:
			for wood_worker in paid_wood_workers:
				var probe_target = wood_worker.get("gather_target")
				probe_samples.append({"frame":frame,"game_time":float(game.get("_game_time")),"worker_id":wood_worker.get_instance_id(),"alive":wood_worker.get("alive"),"state":int(wood_worker.get("state")),"position":_v3(wood_worker.global_position),"goal":_v3(wood_worker.get("_goal_final")),"waypoint_count":Array(wood_worker.get("_waypoints")).size(),"gather_target_id":probe_target.get_instance_id() if is_instance_valid(probe_target) else 0,"carry_key":str(wood_worker.get("carry_key")),"carry_amount":int(wood_worker.get("carry_amount")),"manual_order_suppresses_auto_defense":bool(wood_worker.get("manual_order_suppresses_auto_defense")),"resource_amount":int(resource.get("amount")),"wood":int(game.get("wood")),"navigation_revision":PATHFIND.navigation_revision})
		await get_tree().process_frame
	var probe_resource_after := int(resource.get("amount")) if is_instance_valid(resource) else -1
	var probe_moved: bool = false
	for i in paid_wood_workers.size():
		var initial_position: Array = initial_paid_orders[i].get("position", [0.0,0.0,0.0])
		probe_moved = probe_moved or paid_wood_workers[i].global_position.distance_to(Vector3(float(initial_position[0]),float(initial_position[1]),float(initial_position[2]))) > 0.75
	var probe_gathered: bool = probe_resource_after < probe_resource_amount or int(game.get("wood")) > 0
	if not probe_gathered:
		var probe_final_workers: Array[Dictionary] = []
		for wood_worker in paid_wood_workers:
			var probe_target = wood_worker.get("gather_target")
			probe_final_workers.append({"id":wood_worker.get_instance_id(),"alive":wood_worker.get("alive"),"state":int(wood_worker.get("state")),"position":_v3(wood_worker.global_position),"goal":_v3(wood_worker.get("_goal_final")),"waypoint_count":Array(wood_worker.get("_waypoints")).size(),"gather_target_id":probe_target.get_instance_id() if is_instance_valid(probe_target) else 0,"carry_key":str(wood_worker.get("carry_key")),"carry_amount":int(wood_worker.get("carry_amount")),"manual_order_suppresses_auto_defense":bool(wood_worker.get("manual_order_suppresses_auto_defense"))})
		for wood_worker in paid_wood_workers: wood_worker.command_stop()
		_finish(false,"evacuation_gather_short_probe_no_resource_progress",{"initial_paid_orders":initial_paid_orders,"samples":probe_samples,"final_workers":probe_final_workers,"moved_over_0_75m":probe_moved,"resource_id":resource.get_instance_id() if is_instance_valid(resource) else 0,"resource_amount_before":probe_resource_amount,"resource_amount_after":probe_resource_after,"game_time":game.get("_game_time"),"wood":game.get("wood"),"path_last_report":PATHFIND.last_path_report,"nav_revision":PATHFIND.navigation_revision})
		return
	var wood_wait_frames := 600
	for frame in range(600,6000):
		if int(game.get("wood")) >= house_cost:
			wood_wait_frames = frame
			break
		await get_tree().process_frame
	var normal_wood_cost_earned: bool = int(game.get("wood")) >= house_cost
	var paid_worker_states: Array[Dictionary] = []
	for wood_worker in paid_wood_workers:
		var worker_target = wood_worker.get("gather_target")
		paid_worker_states.append({"id":wood_worker.get_instance_id(),"state":int(wood_worker.get("state")),"position":_v3(wood_worker.global_position),"goal":_v3(wood_worker.get("_goal_final")),"target_id":worker_target.get_instance_id() if is_instance_valid(worker_target) else 0,"target_amount":int(worker_target.get("amount")) if is_instance_valid(worker_target) and worker_target.get("amount") != null else -1,"carry":int(wood_worker.get("carry_amount")),"carry_key":str(wood_worker.get("carry_key")),"queue":wood_worker.get("order_queue").size()})
	for wood_worker in paid_wood_workers:
		wood_worker.command_stop()
	if not normal_wood_cost_earned:
		_finish(false, "evacuation_regression_normal_wood_cost_not_earned", {"wood":game.get("wood"),"house_cost":house_cost,"wait_frames":wood_wait_frames,"game_time":game.get("_game_time"),"paused":get_tree().paused,"initial_paid_orders":initial_paid_orders,"paid_workers":paid_worker_states,"selected_resource_id":resource.get_instance_id(),"selected_resource_amount":resource.get("amount")})
		return
	evacuee.command_gather(resource)
	var initial_resource_order: bool = evacuee.get("gather_target") == resource
	var zombie = SOLDIER_SCRIPT.new()
	zombie.name = "Evacuation_Attacker_Fixture"
	world.add_child(zombie)
	zombie.setup(evacuee.global_position + Vector3(-0.65, 0.0, 0.0), "player", true)
	var zombie_marker := 90002
	zombie.horde_wave_id = zombie_marker
	zombie.attack_target = evacuee
	zombie.state = SOLDIER_SCRIPT.State.ATTACK
	zombie._attack_cd = 0.0
	var hp_before_first_hit := float(evacuee.get("hp"))
	zombie._do_attack(0.05)
	var actual_hp_delta := hp_before_first_hit - float(evacuee.get("hp"))
	zombie.attack_target = null
	zombie.state = SOLDIER_SCRIPT.State.IDLE
	var alert_key := ""
	for key in game.get("_combat_damage_alerts"):
		if str(key).begins_with("economy_unit:"):
			alert_key = str(key)
			break
	game.call("_refresh_operational_alerts")
	var hud: Node = game.get("hud")
	var alert_button: Button = hud.get("_operational_button_by_key").get("combat:" + alert_key) if hud != null and not alert_key.is_empty() else null
	if is_instance_valid(alert_button):
		alert_button.pressed.emit()
	var alert_selected_victim: bool = evacuee in game.get("selected")
	var alert_has_action_hint: bool = is_instance_valid(alert_button) and alert_button.text == "定位并选村民" and alert_button.tooltip_text.contains("Shift+右键")
	var camera_centered_to_alert: bool = (game.get("cam_pivot") as Node3D).position.distance_to(evacuee.global_position) < 0.1
	var staging := Vector3.INF
	for offset in [Vector3(0,0,14),Vector3(14,0,0),Vector3(0,0,-14),Vector3(-14,0,0),Vector3(10,0,10),Vector3(-10,0,10)]:
		var candidate_pos: Vector3 = evacuee.global_position + offset
		var clear_of_resource := true
		for node in get_tree().get_nodes_in_group("resources"):
			if is_instance_valid(node) and not node.is_in_group("buildings") and candidate_pos.distance_to(node.global_position) < 2.2:
				clear_of_resource = false
				break
		if clear_of_resource:
			staging = candidate_pos
			break
	if not staging.is_finite():
		_finish(false, "evacuation_regression_no_player_selected_destination")
		return
	var attacker_distance_before: float = zombie.global_position.distance_to(evacuee.global_position)
	game.call("_command_at", staging)
	var move_issued: bool = int(evacuee.get("state")) == 1 and evacuee.get("gather_target") == null and evacuee.get("_goal_final").distance_to(staging) < 0.1
	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.physical_keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	await get_tree().process_frame
	var shift_registered := Input.is_key_pressed(KEY_SHIFT)
	game.call("_command_at", resource.global_position)
	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.physical_keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	await get_tree().process_frame
	var shift_released := not Input.is_key_pressed(KEY_SHIFT)
	var queued_gather: bool = evacuee.order_queue.size() == 1 and str(evacuee.order_queue[0].get("k", "")) == "gather" and evacuee.order_queue[0].get("n") == resource
	zombie._attack_cd = 0.0
	zombie._do_attack(0.05)
	var manual_withdraw_held: bool = evacuee.attack_target == null and evacuee.get("_goal_final").distance_to(staging) < 0.1 and bool(evacuee.get("manual_order_suppresses_auto_defense"))

	# Build a real, paid foundation through the production placement handler and
	# queue it after a player-selected Move, so F5/F9 must restore a live ref.
	game.call("_clear_selection")
	game.call("_add_to_selection", builder)
	game.call("_on_build_kind", CATALOG.HOUSE)
	var place_pos := Vector3.INF
	var placement_distance := INF
	for x in range(-24, 25, 4):
		for z in range(-24, 25, 4):
			var candidate_pos := Vector3(float(x), 0.0, float(z))
			var candidate_distance: float = builder.global_position.distance_to(candidate_pos)
			if game.call("_placement_valid_at", candidate_pos) and candidate_distance < placement_distance:
				place_pos = candidate_pos
				placement_distance = candidate_distance
	var wood_before_placement := int(game.get("wood"))
	if not place_pos.is_finite():
		_finish(false, "evacuation_regression_no_paid_foundation_site")
		return
	game.call("_try_place", place_pos)
	var foundation: Node3D = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and int(building.get("kind")) == CATALOG.HOUSE and not bool(building.get("is_complete")) and building.global_position.distance_to(place_pos) < 0.1:
			foundation = building
			break
	var paid_foundation: bool = normal_wood_cost_earned and is_instance_valid(foundation) and int(game.get("wood")) == wood_before_placement - house_cost and builder.get("build_site") == foundation
	var build_stage: Vector3 = builder.global_position + Vector3(-2.0, 0.0, 0.0)
	builder.command_move(build_stage)
	builder.command_build(foundation, true)
	var queued_build: bool = is_instance_valid(foundation) and builder.order_queue.size() == 1 and str(builder.order_queue[0].get("k", "")) == "build" and builder.order_queue[0].get("n") == foundation

	# A third player villager verifies that Stop cancels a queued work order and
	# a later explicit order takes precedence over the canceled destination.
	var cancel_resource: Node3D = null
	for candidate in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(candidate) and candidate != resource and not candidate.is_in_group("buildings") and int(candidate.get("amount")) > 0:
			cancel_resource = candidate
			break
	var cancel_goal: Vector3 = order_override_unit.global_position + Vector3(0.0, 0.0, 1.5)
	var override_start: Vector3 = order_override_unit.global_position
	order_override_unit.command_move(cancel_goal)
	if cancel_resource != null:
		order_override_unit.command_gather(cancel_resource, true)
	var queued_before_stop: bool = order_override_unit.order_queue.size() == 1
	order_override_unit.command_stop()
	var stop_canceled: bool = order_override_unit.order_queue.is_empty() and int(order_override_unit.state) == 0 and order_override_unit.gather_target == null and not bool(order_override_unit.get("manual_order_suppresses_auto_defense"))
	var new_goal: Vector3 = order_override_unit.global_position + Vector3(0.0, 0.0, -3.0)
	for offset in [Vector3(1.5,0,0),Vector3(-1.5,0,0),Vector3(0,0,1.5),Vector3(0,0,-1.5),Vector3(1.5,0,1.5),Vector3(-1.5,0,-1.5)]:
		var candidate_goal: Vector3 = order_override_unit.global_position + offset
		PATHFIND.find_path(order_override_unit.global_position,candidate_goal,get_tree())
		if str(PATHFIND.last_path_report.get("search_reason","")) != "unreachable" and float(PATHFIND.last_path_report.get("route_distance_to_resolved_goal",INF)) <= 0.5:
			new_goal = candidate_goal
			break
	order_override_unit.command_move(new_goal)
	var new_order_wins: bool = int(order_override_unit.state) == 1 and order_override_unit.get("_goal_final").distance_to(new_goal) < 0.1 and order_override_unit.order_queue.is_empty()
	var new_order_snapshot := {"state":int(order_override_unit.get("state")),"goal":_v3(order_override_unit.get("_goal_final")),"requested_goal":_v3(new_goal),"queue_size":order_override_unit.order_queue.size()}
	if cancel_resource != null:
		order_override_unit.command_gather(cancel_resource, true)
	var foundation_progress_before_save: float = float(foundation.get("build_progress")) if is_instance_valid(foundation) else 0.0

	var old_worker_id := int(evacuee.get_instance_id())
	var old_builder_id := int(builder.get_instance_id())
	var old_zombie_id := int(zombie.get_instance_id())
	var old_resource_id := int(resource.get_instance_id())
	var old_foundation_id := int(foundation.get_instance_id()) if is_instance_valid(foundation) else -1
	var evacuee_start: Vector3 = evacuee.global_position
	var builder_start: Vector3 = builder.global_position
	await _send_key(KEY_ESCAPE)
	var paused := get_tree().paused
	await _send_key(KEY_F5)
	var saved_orders_ok := false
	var save_exists := FileAccess.file_exists("user://aoelite3d_save.json")
	if save_exists:
		var file := FileAccess.open("user://aoelite3d_save.json", FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var gather_id := ""
				var build_id := ""
				for record in parsed.get("entities", {}).get("villagers", []):
					for order in record.get("orders", []):
						if str(order.get("k", "")) == "gather": gather_id = str(order.get("target_id", ""))
						if str(order.get("k", "")) == "build": build_id = str(order.get("target_id", ""))
				saved_orders_ok = not gather_id.is_empty() and not build_id.is_empty()
			file.close()
	var restore_button := _find_button(game.get("_pause_layer"), "读取存档（F9）")
	if restore_button == null:
		var pause_buttons: Array[String] = []
		var pause_layer: Node = game.get("_pause_layer")
		if pause_layer != null:
			for node in pause_layer.find_children("*", "Button", true, false): pause_buttons.append(str((node as Button).text))
		_finish(false, "evacuation_regression_f9_button_missing", {"paused_after_Esc":paused,"save_exists":save_exists,"pause_layer_valid":is_instance_valid(pause_layer),"pause_buttons":pause_buttons,"move_issued":move_issued,"shift_registered":shift_registered,"shift_released":shift_released,"queued_gather":queued_gather,"manual_withdraw_held":manual_withdraw_held,"victim_alive":is_instance_valid(evacuee) and bool(evacuee.get("alive")),"victim_hp":float(evacuee.get("hp")) if is_instance_valid(evacuee) else 0.0})
		return
	restore_button.pressed.emit()
	var restore_completed := await _wait_until(func() -> bool: return get_tree().paused and not bool(game.get("_start_operation_busy")) and game.get("_pending_restore").is_empty(), 900)
	await get_tree().process_frame
	var restored_evacuee: Node = null
	var restored_builder: Node = null
	var restored_override_unit: Node = null
	var restored_zombie: Node = null
	for unit in get_tree().get_nodes_in_group("villagers"):
		if str(unit.get("team")) != "player": continue
		if unit.global_position.distance_to(evacuee_start) < 0.1:
			restored_evacuee = unit
		if unit.global_position.distance_to(builder_start) < 0.1:
			restored_builder = unit
		if unit.global_position.distance_to(override_start) < 0.1:
			restored_override_unit = unit
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if bool(unit.get("is_zombie")) and int(unit.get("horde_wave_id")) == zombie_marker:
			restored_zombie = unit
	var restored_resource: Node = null
	if is_instance_valid(restored_evacuee):
		if not restored_evacuee.order_queue.is_empty(): restored_resource = restored_evacuee.order_queue[0].get("n")
		elif is_instance_valid(restored_evacuee.get("gather_target")): restored_resource = restored_evacuee.get("gather_target")
		elif is_instance_valid(restored_evacuee.get("resume_resource")): restored_resource = restored_evacuee.get("resume_resource")
	var restored_foundation: Node = null
	if is_instance_valid(restored_builder):
		if not restored_builder.order_queue.is_empty(): restored_foundation = restored_builder.order_queue[0].get("n")
		elif is_instance_valid(restored_builder.get("build_site")): restored_foundation = restored_builder.get("build_site")
	var reference_restore_ok := is_instance_valid(restored_evacuee) and is_instance_valid(restored_resource) and restored_resource.is_in_group("resources") and int(restored_resource.get("amount")) > 0 and int(restored_resource.get_instance_id()) != old_resource_id and is_instance_valid(restored_builder) and is_instance_valid(restored_foundation) and restored_foundation.is_in_group("buildings") and not bool(restored_foundation.get("is_complete")) and int(restored_foundation.get_instance_id()) != old_foundation_id
	var identities_replaced := is_instance_valid(restored_evacuee) and int(restored_evacuee.get_instance_id()) != old_worker_id and is_instance_valid(restored_builder) and int(restored_builder.get_instance_id()) != old_builder_id
	var saved_withdraw_state := is_instance_valid(restored_evacuee) and bool(restored_evacuee.get("manual_order_suppresses_auto_defense")) and restored_evacuee.attack_target == null
	var freed_target_skipped := false
	var restored_destroy_target: Variant = null
	var restored_override_queue_at_f9: int = restored_override_unit.order_queue.size() if is_instance_valid(restored_override_unit) else -1
	var restored_override_state_at_f9: int = int(restored_override_unit.get("state")) if is_instance_valid(restored_override_unit) else -1
	var restored_override_goal_at_f9: Array = _v3(restored_override_unit.get("_goal_final")) if is_instance_valid(restored_override_unit) else []
	var freed_queued_target_id := 0
	if is_instance_valid(restored_override_unit) and not restored_override_unit.order_queue.is_empty():
		restored_destroy_target = restored_override_unit.order_queue[0].get("n")
		if is_instance_valid(restored_destroy_target):
			freed_queued_target_id = restored_destroy_target.get_instance_id()
			restored_destroy_target.free()
	if is_instance_valid(restored_evacuee) and not is_instance_valid(restored_zombie):
		restored_zombie = SOLDIER_SCRIPT.new()
		restored_zombie.name = "Evacuation_Followup_Attacker_Fixture"
		world.add_child(restored_zombie)
		restored_zombie.setup(restored_evacuee.global_position + Vector3(-0.65,0.0,0.0),"player",true)
		restored_zombie.horde_wave_id = zombie_marker
		restored_zombie.attack_target = restored_evacuee
		restored_zombie.state = SOLDIER_SCRIPT.State.ATTACK
	if is_instance_valid(restored_zombie):
		restored_zombie._attack_cd = 0.0
		restored_zombie._do_attack(0.05)
		restored_zombie.attack_target = null
		restored_zombie.state = SOLDIER_SCRIPT.State.IDLE
	var continued_withdraw_under_fire: bool = is_instance_valid(restored_evacuee) and restored_evacuee.attack_target == null and restored_evacuee.get("_goal_final").distance_to(staging) < 0.1
	await _send_key(KEY_ESCAPE)
	var min_destination_attacker_distance := INF
	var closest_to_staging := INF
	var reached_staging := false
	var gather_work_resumed := false
	var build_work_resumed := false
	if is_instance_valid(restored_evacuee):
		for _frame in 900:
			await get_tree().process_frame
			if not is_instance_valid(restored_evacuee): break
			if is_instance_valid(restored_zombie):
				min_destination_attacker_distance = minf(min_destination_attacker_distance, restored_evacuee.global_position.distance_to(restored_zombie.global_position))
			closest_to_staging = minf(closest_to_staging, restored_evacuee.global_position.distance_to(staging))
			if restored_evacuee.global_position.distance_to(staging) <= 0.85:
				reached_staging = true
			if reached_staging: break
	if is_instance_valid(restored_zombie):
		restored_zombie.take_damage(10000.0, false, null)
	if is_instance_valid(restored_override_unit) and freed_queued_target_id != 0:
		for _frame in 900:
			await get_tree().process_frame
			if int(restored_override_unit.state) == 0 and restored_override_unit.order_queue.is_empty():
				freed_target_skipped = true
				break
	var target_hp_after_withdraw := float(restored_evacuee.get("hp")) if is_instance_valid(restored_evacuee) else 0.0
	for _frame in 1800:
		if not is_instance_valid(restored_evacuee) or not is_instance_valid(restored_builder): break
		if is_instance_valid(restored_resource) and restored_evacuee.gather_target == restored_resource and int(restored_evacuee.state) == 2:
			gather_work_resumed = true
		if is_instance_valid(restored_foundation) and ((restored_builder.build_site == restored_foundation and int(restored_builder.state) == 3) or float(restored_foundation.get("build_progress")) > foundation_progress_before_save):
			build_work_resumed = true
		if gather_work_resumed and build_work_resumed: break
		await get_tree().process_frame
	if is_instance_valid(restored_resource):
		restored_resource.call("harvest", int(restored_resource.get("amount")))
	var depleted_target_released := false
	if is_instance_valid(restored_evacuee):
		for _frame in 240:
			await get_tree().process_frame
			if not is_instance_valid(restored_evacuee): break
			var active_target: Variant = restored_evacuee.get("gather_target")
			if not is_instance_valid(restored_resource) and (not is_instance_valid(active_target) or active_target != restored_resource):
				depleted_target_released = true
				break
	var details := {"route":"production Main start → actual zombie hit → existing damage alert selects live victim → production Move → Shift queued Gather/Build → Esc/F5/pause F9 → production movement and work","actual_damage_to_selected_villager":actual_hp_delta,"worker_hp_before_hit":hp_before_first_hit,"worker_hp_after_withdraw_window":target_hp_after_withdraw,"initial_gather_reference_valid":initial_resource_order,"alert_button_reused_no_duplicate_control":alert_has_action_hint,"alert_click_selected_victim":alert_selected_victim,"alert_click_centered_camera":camera_centered_to_alert,"staging_destination_player_chosen_in_test":_v3(staging),"initial_attacker_distance":attacker_distance_before,"nearest_attacker_distance_during_extraction_min":min_destination_attacker_distance,"closest_actual_distance_to_chosen_point":closest_to_staging,"chosen_point_claimed_safe":false,"main_move_command_active":move_issued,"shift_key_registered":shift_registered,"shift_key_released":shift_released,"shift_gather_queued":queued_gather,"withdraw_order_persisted_under_actual_followup_hit":manual_withdraw_held,"paid_foundation_normal_cost_paid":paid_foundation,"foundation_distance_from_builder":placement_distance,"shift_build_queued":queued_build,"build_worker_after_restore":{"alive":is_instance_valid(restored_builder) and bool(restored_builder.get("alive")),"state":int(restored_builder.get("state")) if is_instance_valid(restored_builder) else -1,"site_valid":is_instance_valid(restored_builder) and is_instance_valid(restored_builder.get("build_site")),"progress":float(restored_foundation.get("build_progress")) if is_instance_valid(restored_foundation) else -1.0,"position":_v3(restored_builder.global_position) if is_instance_valid(restored_builder) else []},"stop_canceled_queue":stop_canceled,"valid_queue_existed_before_stop":queued_before_stop,"new_move_overrode_canceled_order":new_order_wins,"override_after_new_move":new_order_snapshot,"F5_pause_and_save":paused and save_exists,"saved_work_order_targets_encoded":saved_orders_ok,"F9_completed":restore_completed,"old_and_new_instance_ids_changed":identities_replaced,"gather_and_build_references_rebound":reference_restore_ok,"manual_withdraw_state_restored":saved_withdraw_state,"withdraw_goal_held_after_restore_hit":continued_withdraw_under_fire,"physically_reached_player_chosen_staging_point":reached_staging,"gather_work_resumed_with_valid_resource":gather_work_resumed,"build_work_resumed_with_valid_foundation":build_work_resumed,"depleted_resource_target_released_or_replaced":depleted_target_released,"freed_queued_target_skipped":freed_target_skipped,"restored_override_queue_size_at_f9":restored_override_queue_at_f9,"restored_override_state_at_f9":restored_override_state_at_f9,"restored_override_goal_at_f9":restored_override_goal_at_f9,"freed_queued_target_id":freed_queued_target_id,"restored_override_queue_size_at_end":restored_override_unit.order_queue.size() if is_instance_valid(restored_override_unit) else -1,"restored_override_state_at_end":int(restored_override_unit.get("state")) if is_instance_valid(restored_override_unit) else -1,"restored_override_position_at_end":_v3(restored_override_unit.global_position) if is_instance_valid(restored_override_unit) else []}
	var passed: bool = actual_hp_delta > 0.0 and alert_selected_victim and alert_has_action_hint and camera_centered_to_alert and initial_resource_order and move_issued and shift_registered and queued_gather and manual_withdraw_held and paid_foundation and queued_build and queued_before_stop and stop_canceled and new_order_wins and paused and save_exists and saved_orders_ok and restore_completed and identities_replaced and reference_restore_ok and saved_withdraw_state and continued_withdraw_under_fire and reached_staging and gather_work_resumed and build_work_resumed and depleted_target_released and freed_target_skipped
	events.append({"action":"player_directed_villager_evacuation_and_work_resume","passed":passed,"details":details})
	_finish(passed,"player_directed_evacuation_shift_work_restore_verified" if passed else "player_directed_evacuation_regression_failed",details)

func _soldier_guard_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for soldier in _player_soldiers():
		var target: Variant = soldier.get("attack_target")
		var target_valid: bool = not is_instance_valid(target) or (target.is_inside_tree() and target.is_in_group("zombies"))
		intents.append({"hp":float(soldier.get("hp")),"pos":_v3(soldier.global_position),"guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor")),"resolved_anchor":_v3(soldier.get("guard_resolved_anchor")),"target_present":is_instance_valid(target),"target_valid":target_valid,"target_wave":int(target.get("horde_wave_id")) if is_instance_valid(target) else -1,"target_pos":_v3(target.global_position) if is_instance_valid(target) else []})
	return intents

func _audit_saved_attack_refs(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"passed":false,"reason":"save_file_missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"passed":false,"reason":"save_json_invalid"}
	var entities: Dictionary = parsed.get("entities",{})
	var soldier_records: Array = Array(entities.get("soldiers",[]))
	var by_id: Dictionary = {}
	for group_name in ["buildings", "resources", "villagers", "soldiers"]:
		for entity in Array(entities.get(group_name, [])):
			by_id[str(entity.get("id", ""))] = entity
	var attack_refs := 0
	var resolved_enemy_refs := 0
	var unresolved_refs: Array[String] = []
	for item in soldier_records:
		var attack_id := str(item.get("attack_id",""))
		if attack_id.is_empty():
			continue
		attack_refs += 1
		var target: Dictionary = by_id.get(attack_id,{})
		if target.is_empty():
			unresolved_refs.append(attack_id)
		elif str(item.get("team", "")) == "player" and str(target.get("team","")) == "enemy" and bool(target.get("is_zombie", false)):
			resolved_enemy_refs += 1
	return {"passed":unresolved_refs.is_empty(),"soldiers_serialized":soldier_records.size(),"all_entities_indexed":by_id.size(),"attack_refs":attack_refs,"resolved_enemy_attack_refs":resolved_enemy_refs,"unresolved_attack_ids":unresolved_refs}

func _snapshot(game: Node, label: String) -> Dictionary:
	var villagers := _living_villagers()
	var working := 0
	var idle := 0
	var gather_valid := 0
	var gather_target_valid := 0
	var villager_records: Array[Dictionary] = []
	for worker in villagers:
		var state := int(worker.get("state"))
		if state == 0: idle += 1
		else: working += 1
		if state == 2 or state == 3:
			gather_valid += 1
			var target: Variant = worker.get("gather_target")
			if is_instance_valid(target) and target.is_inside_tree() and (int(target.get("amount")) > 0 if not target.is_in_group("farms") else int(target.get("meat_stock")) > 0): gather_target_valid += 1
		var worker_target: Variant = worker.get("gather_target")
		var worker_site: Variant = worker.get("build_site")
		villager_records.append({"id":worker.get_instance_id(),"name":worker.name,"pos":_v3(worker.global_position),"hp":float(worker.get("hp")),"state":state,"role":worker_roles.get(str(worker.get_instance_id()),""),"gather_target":worker_target.name if is_instance_valid(worker_target) else "","build_site":worker_site.name if is_instance_valid(worker_site) else "","carry_key":str(worker.get("carry_key")),"carry_amount":int(worker.get("carry_amount")),"path_waypoints":Array(worker.get("_waypoints")).duplicate(true),"move_target":_v3(worker.get("move_target"))})
	var farms := _live_farms()
	var farm_stock: Array[Dictionary] = []
	for farm in farms: farm_stock.append({"name":farm.name,"stock":int(farm.get("meat_stock")),"alive":bool(farm.get("alive")),"hp":float(farm.get("hp"))})
	var buildings: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player":
			var builders: Array[Dictionary] = []
			if not bool(building.get("is_complete")):
				for worker in villagers:
					if worker.get("build_site") != building: continue
					var goal: Vector3 = worker.get("_goal_final")
					var in_range := bool(building.call("is_builder_in_range", worker.global_position)) if building.has_method("is_builder_in_range") else false
					var blocked_at_worker := bool(building.call("blocks_unit_at", worker.global_position, worker.get("team"), float(worker.get("radius")))) if building.has_method("blocks_unit_at") else false
					builders.append({"name":worker.name,"state":int(worker.get("state")),"build_site":str((worker.get("build_site") as Node).name),"position":_v3(worker.global_position),"goal":_v3(goal),"distance_to_site":worker.global_position.distance_to(building.global_position),"builder_in_range":in_range,"blocked_at_worker":blocked_at_worker,"waypoint_count":Array(worker.get("_waypoints")).size(),"move_target":_v3(worker.get("move_target"))})
			buildings.append({"name":building.name,"kind":int(building.get("kind")),"alive":bool(building.get("alive")),"complete":bool(building.get("is_complete")),"build_progress":float(building.get("build_progress")),"build_time":float(building.get("build_time")),"hp":float(building.get("hp")),"max_hp":float(building.get("max_hp")),"position":_v3(building.global_position),"builders":builders})
	var production: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not str(building.get("team")) == "player": continue
		var queue: Array = building.get("train_queue") if building.get("train_queue") != null else []
		if queue.is_empty(): continue
		var front := str(queue[0])
		production.append({"building":building.name,"kind":int(building.get("kind")),"queue":queue.duplicate(),"paid":bool(building.get("train_paid")),"paused":bool(building.get("train_paused")),"shortage_reason":str(game.call("_train_shortage_text",front)) if bool(building.get("train_paused")) else "","timer":float(building.get("train_timer"))})
	var zombies := _living_zombies()
	var zombie_records: Array[Dictionary] = []
	for zombie in zombies:
		var target: Variant = zombie.get("attack_target")
		zombie_records.append({"name":zombie.name,"id":zombie.get_instance_id(),"wave":int(zombie.get("horde_wave_id")),"hp":float(zombie.get("hp")),"pos":_v3(zombie.global_position),"target":target.name if is_instance_valid(target) else "","target_id":target.get_instance_id() if is_instance_valid(target) else 0,"state":int(zombie.get("state")),"goal":_v3(zombie.get("_goal_final")),"move_target":_v3(zombie.get("move_target")),"path_waypoints":Array(zombie.get("_waypoints")).duplicate(true)})
	var soldiers := _player_soldiers()
	var soldier_records: Array[Dictionary] = []
	for soldier in soldiers:
		var target: Variant = soldier.get("attack_target")
		soldier_records.append({"name":soldier.name,"id":soldier.get_instance_id(),"hp":float(soldier.get("hp")),"pos":_v3(soldier.global_position),"state":int(soldier.get("state")),"guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor")),"resolved_guard_anchor":_v3(soldier.get("guard_resolved_anchor")),"goal":_v3(soldier.get("_goal_final")),"move_target":_v3(soldier.get("move_target")),"path_waypoints":Array(soldier.get("_waypoints")).duplicate(true),"target":target.name if is_instance_valid(target) else "","target_id":target.get_instance_id() if is_instance_valid(target) else 0,"order_queue_size":Array(soldier.get("order_queue")).size()})
	var wave := int(game.get("_horde_wave"))
	var expected := int(game.call("_horde_count_for_wave", wave)) if wave > 0 else 0
	var wave_zombies := zombies.filter(func(z: Node) -> bool: return int(z.get("horde_wave_id")) == wave)
	var pending := int(Array(game.get("_horde_spawn_queue")).size()) if int(game.get("_horde_spawn_wave_id")) == wave else 0
	var tower_shots: Dictionary = {}
	for event in events:
		if event.get("action")=="arrow_tower_projectile_launched":
			var tower_key := str(event.get("tower_id")); tower_shots[tower_key]=int(tower_shots.get(tower_key,0))+1
	var tower_status: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team"))=="player" and bool(building.get("is_tower")):
			tower_status.append({"id":building.get_instance_id(),"pos":_v3(building.global_position),"complete":bool(building.get("is_complete")),"hp":float(building.get("hp")),"range":float(building.get("attack_range")),"shots_observed":int(tower_shots.get(str(building.get_instance_id()),0)),"ui_state":building.call("get_tower_ui_state") if building.has_method("get_tower_ui_state") else {}})
	return {"label":label,"utc":Time.get_datetime_string_from_system(true,true),"game_time":float(game.get("_game_time")),"clock_minutes":float(game.get("_clock_minutes")),"map_seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"wave":wave,"wave_active":bool(game.get("_horde_active")),"wave_expected":expected,"wave_alive":wave_zombies.size(),"wave_alive_total":zombies.size(),"wave_pending":pending,"wave_kills_estimate":maxi(0,expected-wave_zombies.size()-pending) if bool(game.get("_horde_active")) else maxi(0,expected-wave_zombies.size()),"resources":{"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))},"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap")),"villagers":{"alive":villagers.size(),"idle":idle,"working":working,"gather_orders":gather_valid,"valid_gather_targets":gather_target_valid,"roles":worker_roles.duplicate(true),"units":villager_records},"farms":farm_stock,"production":production,"research":{"age":int(game.get("research").get("age")) if game.get("research") != null else 0,"techs":Array(game.get("research").get("researched_techs")) if game.get("research") != null else []},"army":{"alive":soldiers.size(),"units":soldier_records},"buildings":buildings,"arrow_towers":tower_status,"zombies":zombie_records,"horde_spawn_queue_positions":Array(game.get("_horde_spawn_queue")).duplicate(true),"pathfind":{"revision":PATHFIND.navigation_revision,"dirty":PATHFIND._dirty},"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious"))}

func _run_construction_causality_probe(game: Node) -> void:
	Engine.time_scale = 1.0
	var workers := _living_villagers()
	if workers.size() != 5 or get_tree().get_nodes_in_group("buildings").size() != 1:
		_finish(false, "construction_probe_clean_start_mismatch", {"villagers":workers.size(),"buildings":get_tree().get_nodes_in_group("buildings").size()})
		return
	for index in workers.size(): _assign_worker(game, workers[index], "stone" if index == 0 else "wood", "causality probe opening order")
	events.append({"at":"match_started","action":"construction_probe_started","seed":42,"mode":"endless","time_scale":Engine.time_scale,"villagers":workers.size(),"injected_entities":0,"injected_resources":0})
	var sample_at := 0.0
	var maintain_at := 0.0
	var started_usec := Time.get_ticks_usec()
	var observed_cancel := false
	while true:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			_finish(false, "construction_probe_main_disappeared")
			return
		var game_time := float(game.get("_game_time"))
		if game_time >= sample_at:
			sample_at = game_time + 1.0
			snapshots.append(_snapshot(game, "construction_probe"))
			for building in get_tree().get_nodes_in_group("buildings"):
				if not is_instance_valid(building) or str(building.get("team")) != "player" or bool(building.get("is_complete")): continue
				for worker in _living_villagers():
					if worker.get("build_site") == building: observed_cancel = true
		if game_time >= maintain_at:
			maintain_at = game_time + 2.0
			await _maintain_economy(game)
		if game_time >= 65.0:
			report["construction_probe_elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1000000.0
			report["construction_override_events"] = events.filter(func(e: Dictionary) -> bool: return e.get("action") == "production_order_overrode_active_build")
			report["active_builder_seen_in_any_snapshot"] = observed_cancel
			_finish(true, "construction_causality_window_complete")
			return
		if bool(game.get("_defeated")) or bool(game.get("_victorious")):
			snapshots.append(_snapshot(game, "construction_probe_terminal"))
			_finish(false, "construction_probe_terminal", {"game_time":game_time})
			return

func _run_paid_opening_probe(game: Node) -> void:
	Engine.time_scale = 1.0
	var workers := _living_villagers()
	if workers.size() != 5 or get_tree().get_nodes_in_group("buildings").size() != 1:
		_finish(false, "paid_opening_clean_start_mismatch", {"villagers":workers.size(),"buildings":get_tree().get_nodes_in_group("buildings").size()})
		return
	for index in workers.size(): _assign_worker(game, workers[index], "stone" if index == 0 else "wood", "paid opening resource plan")
	events.append({"at":"match_started","action":"paid_opening_probe_started","seed":42,"mode":"endless","time_scale":Engine.time_scale,"villagers":workers.size(),"injected_entities":0,"injected_resources":0})
	var sample_at := 0.0
	var maintain_at := 0.0
	while true:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			_finish(false, "paid_opening_main_disappeared")
			return
		for worker in _living_villagers():
			var worker_id := str(worker.get_instance_id())
			if probe_observed_workers.has(worker_id): continue
			probe_observed_workers[worker_id] = true
			var callback := Callable(self, "_on_probe_villager_deposit").bind(worker.name)
			if worker.has_signal("deposited") and not worker.is_connected("deposited", callback): worker.connect("deposited", callback)
		var game_time := float(game.get("_game_time"))
		if game_time >= sample_at:
			sample_at = game_time + 5.0
			snapshots.append(_snapshot(game, "paid_opening"))
		if game_time >= maintain_at:
			maintain_at = game_time + 2.0
			await _maintain_economy(game)
		var farm_complete := _building_count_complete(game, CATALOG.FARM) > 0
		var barracks_complete := _building_count_complete(game, CATALOG.BARRACKS) > 0
		var soldier_count := _player_soldiers().size()
		if farm_complete and barracks_complete and not probe_food_deposits.is_empty() and soldier_count > 0:
			snapshots.append(_snapshot(game, "paid_opening_verified"))
			report["paid_opening_evidence"] = {"farm_complete":farm_complete,"barracks_complete":barracks_complete,"food_deposits":probe_food_deposits,"soldiers_alive":soldier_count,"soldier_queue_events":events.filter(func(e: Dictionary) -> bool: return e.get("action") == "production_queue_soldier"),"game_time":game_time,"time_scale":Engine.time_scale}
			_finish(true, "paid_farm_barracks_food_deposit_and_soldier_verified")
			return
		if bool(game.get("_defeated")) or bool(game.get("_victorious")) or game_time >= 240.0:
			snapshots.append(_snapshot(game, "paid_opening_terminal"))
			_finish(false, "paid_opening_requirements_not_met", {"game_time":game_time,"farm_complete":farm_complete,"barracks_complete":barracks_complete,"food_deposits":probe_food_deposits,"soldiers_alive":soldier_count,"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious"))})
			return

func _on_probe_villager_deposit(key: String, amount: int, worker_name: String) -> void:
	if key != "meat": return
	var deposit := {"at_game_time":float(get_tree().get_first_node_in_group("main_game").get("_game_time")),"worker":worker_name,"key":key,"amount":amount}
	probe_food_deposits.append(deposit)
	events.append({"action":"probe_food_deposited_to_town_center"}.merged(deposit))

func _run_construction_reassignment_probe(game: Node) -> void:
	Engine.time_scale = 1.0
	var workers := _living_villagers()
	if workers.size() != 5 or get_tree().get_nodes_in_group("buildings").size() != 1:
		_finish(false, "construction_reassignment_clean_start_mismatch", {"villagers":workers.size(),"buildings":get_tree().get_nodes_in_group("buildings").size()})
		return
	for index in workers.size(): _assign_worker(game, workers[index], "stone" if index == 0 else "wood", "reassignment probe resource plan")
	var started_usec := Time.get_ticks_usec()
	var maintain_at := 0.0
	var foundation: Node = null
	while float(game.get("_game_time")) < 80.0:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null: break
		var game_time := float(game.get("_game_time"))
		if game_time >= maintain_at:
			maintain_at = game_time + 2.0
			await _maintain_economy(game)
		for building in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == CATALOG.HOUSE and not bool(building.get("is_complete")):
				foundation = building
				break
		if foundation != null: break
	if foundation == null:
		_finish(false, "construction_reassignment_paid_foundation_not_placed", {"game_time":float(game.get("_game_time")) if game != null else -1.0})
		return
	var original_builder: Node = null
	for worker in _living_villagers():
		if worker.get("build_site") == foundation:
			original_builder = worker
			break
	if original_builder == null:
		_finish(false, "construction_reassignment_original_builder_missing", {"foundation":foundation.name})
		return
	var original_progress := float(foundation.get("build_progress"))
	var move_target: Vector3 = original_builder.global_position + Vector3(0,0,12)
	original_builder.call("command_move", move_target)
	var canceled := await _wait_until(func() -> bool: return original_builder.get("build_site") == null, 60)
	var stale_reservation_cleared := _reserved_building_site(original_builder) == null
	var replacement_available := await _wait_until(func() -> bool: return _builder_candidate(original_builder) != null, 300)
	var reassigned := _reassign_unstaffed_foundations(game, _living_villagers(), original_builder)
	var replacement: Node = null
	for worker in _living_villagers():
		if worker.get("build_site") == foundation:
			replacement = worker
			break
	var game_time_before := float(game.get("_game_time"))
	var progress_advanced := false
	while replacement != null and float(game.get("_game_time")) - game_time_before < 30.0:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null or not is_instance_valid(foundation): break
		if float(foundation.get("build_progress")) > original_progress + 0.1:
			progress_advanced = true
			break
	var result := {"passed":canceled and stale_reservation_cleared and replacement_available and replacement != null and replacement != original_builder and progress_advanced,"foundation":foundation.name if is_instance_valid(foundation) else "freed","kind":CATALOG.HOUSE,"cost_paid":true,"original_builder":original_builder.name,"original_progress":original_progress,"original_builder_canceled":canceled,"stale_reservation_cleared":stale_reservation_cleared,"replacement_available":replacement_available,"replacement_builder":replacement.name if is_instance_valid(replacement) else "none","replacement_is_original_builder":replacement == original_builder,"replacement_assigned":replacement != null,"replacement_state":int(replacement.get("state")) if is_instance_valid(replacement) else -1,"replacement_goal":_v3(replacement.get("_goal_final")) if is_instance_valid(replacement) else [],"progress_after":float(foundation.get("build_progress")) if is_instance_valid(foundation) else 0.0,"progress_advanced":progress_advanced,"reassigned_count":reassigned,"wood_after_payment":game.get("wood"),"elapsed_wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"route":"paid production House → Villager3D.command_move cancels first builder → another eligible villager receives Villager3D.command_build"}
	events.append({"action":"construction_reassignment_probe_result"}.merged(result))
	snapshots.append(_snapshot(game, "construction_reassignment_probe_result"))
	_finish(bool(result["passed"]), "unstaffed_foundation_reassigned_and_progressed" if bool(result["passed"]) else "unstaffed_foundation_reassignment_failed", result)

func _reassign_unstaffed_foundations(game: Node, workers: Array, excluded_builder: Node = null) -> int:
	var assigned_count := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player" or bool(building.get("is_complete")): continue
		var staffed := false
		for worker in workers:
			if worker.get("build_site") == building:
				staffed = true
				break
		if staffed: continue
		var builder := _builder_candidate(excluded_builder)
		if builder == null: continue
		builder.call("command_build", building)
		builder_assignments[str(builder.get_instance_id())] = building
		assigned_count += 1
		events.append({"at_game_time":float(game.get("_game_time")),"action":"production_reassigned_unstaffed_foundation","foundation":building.name,"kind":int(building.get("kind")),"progress":float(building.get("build_progress")),"builder":builder.name,"builder_state":int(builder.get("state")),"goal":_v3(builder.get("_goal_final")),"command":"Villager3D.command_build"})
	return assigned_count

func _place_building_dummy() -> void:
	pass

func _builder_candidate(excluded_builder: Node = null) -> Node3D:
	var workers: Array = []
	for worker in _living_villagers():
		if worker == excluded_builder or bool(worker.get("manual_order_suppresses_auto_defense")) or not Array(worker.get("order_queue")).is_empty() or _reserved_building_site(worker) != null or int(worker.get("state")) == 4 or int(worker.get("carry_amount")) > 0: continue
		workers.append(worker)
	workers.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get("state")) == 0 and int(b.get("state")) != 0)
	return workers[0] as Node3D if not workers.is_empty() else null

func _begin_natural_recovery_window(game: Node) -> bool:
	## A real, current damage alert is the only entry to this player-command chain.
	## Staging is a deliberate player choice; it is not claimed to be safe.
	var alerts: Dictionary = game.get("_combat_damage_alerts")
	recovery_start_failure_reason = "recovery_window_no_fresh_player_visible_villager_damage_alert"
	var now_msec := Time.get_ticks_msec()
	var candidates: Array[Dictionary] = []
	for alert_key in alerts:
		var alert: Dictionary = alerts[alert_key]
		if str(alert.get("category","")) != "economy_unit" or now_msec-int(alert.get("last_hit_msec",0)) > 12000:
			continue
		for victim_id in Array(alert.get("victim_instance_ids",[])):
			var victim: Variant = instance_from_id(int(victim_id))
			if is_instance_valid(victim) and victim.is_inside_tree() and bool(victim.get("alive")) and str(victim.get("team")) == "player":
				candidates.append({"key":str(alert_key),"alert":alert,"victim":victim})
	if candidates.is_empty():
		return false
	var selected: Dictionary = candidates[0]
	var victim: Node3D = selected["victim"]
	var alert: Dictionary = selected["alert"]
	var target: Variant = victim.get("gather_target")
	if not is_instance_valid(target) or not target.is_inside_tree() or (int(target.get("amount")) <= 0 if target.has_method("res_key") else int(target.get("meat_stock")) <= 0):
		## A live alert victim may have become idle after the controller's normal
		## defense command. Choose a currently available wood node with a normal
		## resource command so the player's Shift order still has real work.
		target = null
		var nearest_distance := INF
		for resource in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(resource) or not resource.has_method("res_key") or str(resource.call("res_key")) != "wood" or int(resource.get("amount")) <= 0:
				continue
			var distance := victim.global_position.distance_squared_to(resource.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				target = resource
	if not is_instance_valid(target):
		recovery_start_failure_reason = "recovery_window_live_alert_victim_has_no_valid_wood_resource"
		events.append({"at_game_time":float(game.get("_game_time")),"action":"natural_recovery_window_blocked_no_valid_resource","alert_key":str(selected["key"]),"victim_id":victim.get_instance_id(),"victim_name":victim.name})
		return false
	## Route through the same alert handler wired to the existing HUD button.
	game.call("_on_alert_location_pressed","combat:"+str(selected["key"]),alert.get("position",victim.global_position))
	if not game.get("selected").has(victim):
		return false
	recovery_worker_id = victim.get_instance_id()
	recovery_initial_hp = float(victim.get("hp"))
	recovery_initial_wood = int(game.get("wood"))
	recovery_initial_meat = int(game.get("meat"))
	recovery_deposits = 0
	recovery_probe_initial_carry = int(victim.get("carry_amount")) if str(victim.get("carry_key")) == "wood" else 0
	recovery_probe_initial_resource_amount = int(target.get("amount")) if target.has_method("res_key") else -1
	recovery_probe_reached_staging = false
	recovery_probe_resource_decreased = false
	recovery_probe_new_carry = false
	recovery_probe_new_carry_at = -1.0
	recovery_probe_deposit_after_new_carry = false
	recovery_deposit_log.clear()
	var deposit_callable := Callable(self,"_on_recovery_worker_deposited").bind(recovery_worker_id)
	if not victim.is_connected("deposited",deposit_callable):
		victim.connect("deposited",deposit_callable)
	var staging := victim.global_position + Vector3(0,0,8)
	recovery_staging_point = staging
	recovery_probe_resource_id = target.get_instance_id()
	recovery_probe_last_resource_amount = -1
	recovery_probe_last_carry = -1
	game.call("_command_at",staging)
	await get_tree().process_frame
	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	await get_tree().process_frame
	var shift_was_held := Input.is_key_pressed(KEY_SHIFT)
	game.call("_command_at",target.global_position)
	await get_tree().process_frame
	var queued_work_count := Array(victim.get("order_queue")).size()
	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	recovery_command_chain_ok = shift_was_held and queued_work_count > 0 and victim.get("_goal_final").distance_to(staging) < 0.1
	events.append({"at_game_time":float(game.get("_game_time")),"action":"player_visible_alert_withdraw_and_shift_queue","source":"existing HUD alert handler selected live damaged villager; Main._command_at issued Move then Shift+right-click equivalent to its existing resource","alert_key":str(selected["key"]),"victim_id":recovery_worker_id,"victim_name":victim.name,"hp_at_command":recovery_initial_hp,"resource_name":target.name,"resource_key":str(target.call("res_key")) if target.has_method("res_key") else "meat","staging_point":_v3(staging),"staging_point_claimed_safe":false,"move_goal_after_command":_v3(victim.get("_goal_final")),"queue_size_after_command":queued_work_count,"shift_was_held_for_target_command":shift_was_held,"queued_work_received":queued_work_count>0,"manual_priority_after_command":bool(victim.get("manual_order_suppresses_auto_defense")),"wood_at_start":recovery_initial_wood,"meat_at_start":recovery_initial_meat})
	if recovery_probe_only:
		recovery_probe_started_at = float(game.get("_game_time"))
		if not recovery_command_chain_ok:
			_finish(false,"recovery_command_prerequisite_failed",{"shift_was_held":shift_was_held,"queue_size":queued_work_count,"goal_final":_v3(victim.get("_goal_final")),"expected_staging":_v3(staging),"worker_id":recovery_worker_id})
	return true

func _begin_cooperative_protection(game: Node) -> bool:
	## Simulate visible player operations. Evacuation is issued on the first
	## actionable alert; guard assignment is a separate decision based on live
	## positions and path distances, never guard-anchor labels.
	var alerts: Dictionary = game.get("_combat_damage_alerts")
	var now_msec := Time.get_ticks_msec()
	var eligible: Array[Dictionary] = []
	for alert_key in alerts:
		var alert: Dictionary = alerts[alert_key]
		if str(alert.get("category","")) != "economy_unit" or now_msec-int(alert.get("last_hit_msec",0)) > 12000:
			continue
		for victim_id in Array(alert.get("victim_instance_ids",[])):
			var victim: Variant = instance_from_id(int(victim_id))
			if is_instance_valid(victim) and victim.is_inside_tree() and bool(victim.get("alive")) and str(victim.get("team")) == "player":
				eligible.append({"key":str(alert_key),"alert":alert,"victim":victim})
	if eligible.is_empty():
		return _cooperative_skip(game,"no live victim ID in a fresh in-game unit alert","")
	var picked: Dictionary = eligible[0]
	var victim: Node3D = picked["victim"]
	var alert: Dictionary = picked["alert"]
	var resource: Variant = victim.get("gather_target")
	var existing_wood_resource: bool = is_instance_valid(resource) and resource.is_inside_tree() and resource.has_method("res_key") and str(resource.call("res_key")) == "wood" and int(resource.get("amount")) > 0
	var visible_pursuers: Array[Node3D] = []
	var camera: Camera3D = game.get("camera")
	for zombie in _living_zombies():
		if zombie.get("attack_target") == victim and _enemy_on_player_screen(camera,zombie):
			visible_pursuers.append(zombie as Node3D)
	visible_pursuers.sort_custom(func(a: Node3D,b: Node3D) -> bool: return a.global_position.distance_squared_to(victim.global_position) < b.global_position.distance_squared_to(victim.global_position))
	var tower := _first_building(game,CATALOG.ARROW_TOWER,true) as Node3D
	var staging_choice := _cooperative_choose_protected_staging(victim,tower,game)
	var staging: Vector3 = staging_choice.get("requested_goal",Vector3.ZERO)
	var original_guards: Array[Dictionary] = []
	for soldier in _player_soldiers():
		if bool(soldier.get("guard_active")):
			original_guards.append({"id":soldier.get_instance_id(),"name":soldier.name,"anchor":_v3(soldier.get("guard_anchor")),"hp":float(soldier.get("hp"))})
	game.call("_on_alert_location_pressed","combat:"+str(picked["key"]),alert.get("position",victim.global_position))
	if not Array(game.get("selected")).has(victim):
		return _cooperative_skip(game,"existing alert handler did not select the live victim",str(picked["key"]))
	cooperative_worker_id = victim.get_instance_id()
	cooperative_resource_id = resource.get_instance_id() if existing_wood_resource else 0
	cooperative_initial_wood = int(game.get("wood"))
	cooperative_initial_meat = int(game.get("meat"))
	cooperative_resource_amount_baseline = int(resource.get("amount")) if existing_wood_resource else -1
	cooperative_carry_baseline = int(victim.get("carry_amount")) if str(victim.get("carry_key")) == "wood" else 0
	cooperative_last_resource_amount = -1
	cooperative_last_carry = -1
	cooperative_resource_reduced = false
	cooperative_new_carry = false
	cooperative_new_carry_at = -1.0
	cooperative_deposit_after_new_carry = false
	cooperative_reached_staging = false
	cooperative_gather_resumed = false
	cooperative_paid_reinforcement_queued = false
	cooperative_attack_targets.clear()
	cooperative_attackers.clear()
	cooperative_preserved_guards.clear()
	cooperative_tower_id = tower.get_instance_id() if tower != null else 0
	cooperative_staging = staging
	cooperative_started_at = float(game.get("_game_time"))
	cooperative_initial_soldier_count = _player_soldiers().size()
	cooperative_initial_farm_stock = _total_live_farm_stock()
	cooperative_initial_resource_id = cooperative_resource_id
	cooperative_deadline = cooperative_started_at + 60.0
	recovery_deposit_log.clear()
	var deposit_callable := Callable(self,"_on_recovery_worker_deposited").bind(cooperative_worker_id)
	if not victim.is_connected("deposited",deposit_callable):
		victim.connect("deposited",deposit_callable)
	game.call("_clear_selection")
	game.call("_add_to_selection",victim)
	game.call("_refresh_selection_hud")
	# Immediate withdrawal: do not gate this operation on whether a sufficient
	# guard group can be assembled.
	game.call("_command_at",staging)
	cooperative_staging = victim.get("_goal_final")
	var resolved_tower_distance := Vector2(tower.global_position.x-cooperative_staging.x,tower.global_position.z-cooperative_staging.z).length() if tower != null else -1.0
	var tower_protected_goal: bool = tower != null and resolved_tower_distance <= float(tower.get("attack_range")) - 0.25
	var cover_guard: Variant = instance_from_id(int(staging_choice.get("cover_guard_id",0)))
	var guard_protected_goal: bool = is_instance_valid(cover_guard) and (cover_guard as Node3D).global_position.distance_to(cooperative_staging) <= 4.0
	var protected_goal: bool = tower_protected_goal or guard_protected_goal
	var available_guards: Array[Node] = []
	for candidate_soldier in _player_soldiers():
		if candidate_soldier != cover_guard:
			available_guards.append(candidate_soldier)
	var guard_path_records: Array[Dictionary] = []
	for enemy in visible_pursuers:
		var best_index := 0
		var best_dist := INF
		var best_path_probe: Dictionary = {}
		for i in available_guards.size():
			var path_probe := _cooperative_path_probe(available_guards[i] as Node3D,enemy,game)
			var distance := float(path_probe.get("distance",INF))
			if distance < best_dist:
				best_dist = distance
				best_index = i
				best_path_probe = path_probe
		if available_guards.is_empty():
			break
		var soldier: Node = available_guards.pop_at(best_index)
		_select(game,[soldier])
		soldier.call("command_attack_unit",enemy,false)
		cooperative_attackers.append(soldier.get_instance_id())
		cooperative_attack_targets.append({"id":enemy.get_instance_id(),"name":enemy.name,"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position),"wave":int(enemy.get("horde_wave_id"))})
		guard_path_records.append({"soldier_id":soldier.get_instance_id(),"soldier_position":_v3(soldier.global_position),"enemy_id":enemy.get_instance_id(),"enemy_position":_v3(enemy.global_position),"estimated_path_distance":best_dist,"path_waypoints":Array(best_path_probe.get("waypoints",[])).duplicate(true),"path_report":Dictionary(best_path_probe.get("report",{})).duplicate(true)})
	for soldier in _player_soldiers():
		if not cooperative_attackers.has(soldier.get_instance_id()) and bool(soldier.get("guard_active")):
			cooperative_preserved_guards.append({"id":soldier.get_instance_id(),"name":soldier.name,"position":_v3(soldier.global_position),"anchor":_v3(soldier.get("guard_anchor")),"physical_side":"west" if soldier.global_position.x<0.0 else "east"})
	game.call("_clear_selection")
	active_intercept.clear() # The cooperation slice owns these orders; no controller resume/Guard reissue.
	cooperative_tower_id = tower.get_instance_id() if tower != null else 0
	cooperative_protection_active = true
	var command_event := {"at_game_time":cooperative_started_at,"alert_last_hit_msec":int(alert.get("last_hit_msec",0)),"action":"player_cooperative_withdraw_and_split_attack_orders","alert_key":str(picked["key"]),"victim_id":cooperative_worker_id,"victim_name":victim.name,"victim_hp":float(victim.get("hp")),"source":"first actionable existing HUD damage alert selected the live worker and immediately issued Main._command_at Move; available soldiers independently selected by path distance and assigned one Attack each","move_issued_immediately_on_alert_handling":true,"requested_staging_point":_v3(staging),"actual_staging_goal":_v3(cooperative_staging),"actual_move_waypoints":Array(victim.get("_waypoints")).duplicate(true),"actual_move_goal_matches_resolved_goal":victim.get("_goal_final").distance_to(cooperative_staging)<0.05,"staging_point_reason":"candidate previewed with production pathfinder; protection checked against actual resolved villager goal","staging_path_preview":staging_choice,"actual_goal_tower_distance":resolved_tower_distance,"actual_goal_inside_tower_range":tower_protected_goal,"actual_goal_guard_id":int(staging_choice.get("cover_guard_id",0)),"actual_goal_guard_distance":cover_guard.global_position.distance_to(cooperative_staging) if is_instance_valid(cover_guard) else -1.0,"actual_goal_has_live_support":protected_goal,"existing_gather_target":resource.name if existing_wood_resource else "","resource_id":cooperative_resource_id,"resource_name":resource.name if existing_wood_resource else "chosen_after_threat_removal","resource_pos":_v3(resource.global_position) if existing_wood_resource else [],"resource_amount_start":cooperative_resource_amount_baseline,"visible_pursuers":cooperative_attack_targets.duplicate(true),"soldier_attackers":cooperative_attackers.duplicate(),"attacker_command":"Soldier3D.command_attack_unit(target,false)","attacker_path_distances":guard_path_records,"preserved_guard_orders":cooperative_preserved_guards.duplicate(true),"automatic_maintenance_suppressed_during_slice":true,"tower_id":cooperative_tower_id,"tower_hp":float(tower.get("hp")) if tower != null else 0.0,"tower_range":float(tower.get("attack_range")) if tower != null else 0.0,"tower_to_requested_goal_distance":tower.global_position.distance_to(staging) if tower != null else -1.0,"tower_to_resolved_goal_distance":resolved_tower_distance}
	events.append(command_event)
	if not protected_goal:
		_finish(false,"cooperative_resolved_goal_outside_tower_range",command_event)
		return true
	if cooperative_command_probe_only:
		report["cooperative_command_probe"] = {"passed":true,"command_event":command_event,"alert_first_actionable_to_move_seconds":0.0}
		_finish(true,"cooperative_move_and_resolved_tower_coverage_verified",report["cooperative_command_probe"])
	return true

func _cooperative_choose_protected_staging(victim: Node3D,tower: Node3D,game: Node) -> Dictionary:
	var candidates: Array[Dictionary] = []
	if tower != null:
		var range_limit := maxf(float(tower.get("attack_range"))-0.75,1.0)
		var toward := Vector2(victim.global_position.x-tower.global_position.x,victim.global_position.z-tower.global_position.z)
		if toward.length_squared() < 0.01:
			toward = Vector2(-1.0,0.0)
		var base_angle := toward.angle()
		for i in range(16):
			var angle := base_angle + TAU*float(i)/16.0
			candidates.append({"point":Vector3(tower.global_position.x+cos(angle)*range_limit,0.0,tower.global_position.z+sin(angle)*range_limit),"basis":"tower","cover_guard_id":0})
	else:
		# When the natural opening has no tower, choose a route near a physically
		# present unengaged Guard. Its real position is the escort basis; anchor
		# metadata is never used to infer where a soldier currently stands.
		for soldier in _player_soldiers():
			if not bool(soldier.get("guard_active")) or is_instance_valid(soldier.get("attack_target")):
				continue
			var away := Vector2(victim.global_position.x-soldier.global_position.x,victim.global_position.z-soldier.global_position.z)
			if away.length_squared() < 0.01:
				away = Vector2(1.0,0.0)
			var angle0 := away.angle()
			for i in range(8):
				var angle := angle0 + TAU*float(i)/8.0
				candidates.append({"point":Vector3(soldier.global_position.x+cos(angle)*2.0,0.0,soldier.global_position.z+sin(angle)*2.0),"basis":"live_guard","cover_guard_id":soldier.get_instance_id(),"guard_position":_v3(soldier.global_position)})
	var best: Dictionary = {}
	var best_distance := INF
	for candidate_record in candidates:
		var candidate: Vector3 = candidate_record["point"]
		var route: Array = PATHFIND.find_path(victim.global_position,candidate,get_tree())
		var path_report: Dictionary = PATHFIND.last_path_report.duplicate(true)
		var resolved: Vector3 = path_report.get("resolved_goal",candidate)
		var tower_distance := Vector2(tower.global_position.x-resolved.x,tower.global_position.z-resolved.z).length() if tower != null else -1.0
		var guard_id := int(candidate_record.get("cover_guard_id",0))
		var guard_node: Variant = instance_from_id(guard_id) if guard_id > 0 else null
		var guard_distance: float = (guard_node as Node3D).global_position.distance_to(resolved) if is_instance_valid(guard_node) else 0.0
		var has_cover: bool = (tower != null and tower_distance <= float(tower.get("attack_range"))-0.25) or (is_instance_valid(guard_node) and guard_distance <= 4.0)
		if not has_cover or not bool(path_report.get("search_reached_goal",route.is_empty())):
			continue
		var path_distance := _cooperative_waypoint_distance(victim.global_position,route,resolved)
		if path_distance < best_distance:
			best_distance = path_distance
			best = {"reachable_protected_candidate":true,"requested_goal":candidate,"preview_resolved_goal":resolved,"protection_basis":str(candidate_record.get("basis","none")),"cover_guard_id":guard_id,"cover_guard_position":candidate_record.get("guard_position",[]),"guard_distance_to_resolved_goal":guard_distance,"tower_distance_to_resolved_goal":tower_distance,"tower_range":float(tower.get("attack_range")) if tower != null else 0.0,"path_distance":path_distance,"path_waypoints":route.duplicate(true),"path_report":path_report}
	return best

func _cooperative_path_distance(from: Node3D,to: Node3D,game: Node) -> float:
	return float(_cooperative_path_probe(from,to,game).get("distance",INF))

func _cooperative_path_probe(from: Node3D,to: Node3D,game: Node) -> Dictionary:
	var route: Array = PATHFIND.find_path(from.global_position,to.global_position,game.get_tree())
	var report_copy: Dictionary = PATHFIND.last_path_report.duplicate(true)
	var route_distance := _cooperative_waypoint_distance(from.global_position,route,to.global_position)
	return {"distance":route_distance,"waypoints":route.duplicate(true),"report":report_copy}

func _run_cooperative_historical_route_preflight(game: Node) -> void:
	## Query the normal seed-42 map around R87's recorded positions. No entities,
	## resources, damage, orders, or wave state are injected or changed.
	var start := Vector3(-11.16325,0.0,-8.798131)
	var pursuers: Array[Vector3] = [Vector3(-10.178432,0.0,-7.787945),Vector3(-10.355235,0.0,-7.201281)]
	var tower_pos := Vector3(6.0,0.0,0.0)
	var tower_range := 6.5
	# A 4 m south-side point avoids the town-center footprint and leaves 1.15 m
	# of tower-range margin even when a pursuer is at villager melee reach.
	var final_goal := Vector3(6.0,0.0,-4.0)
	var candidates: Array[Vector3] = [Vector3(-20.25,0.0,-6.75),Vector3(-12.0,0.0,-14.0),Vector3(-14.0,0.0,-12.0),Vector3(-8.0,0.0,-12.0)]
	var route_records: Array[Dictionary] = []
	for first_request in candidates:
		var first_route: Array = PATHFIND.find_path(start,first_request,get_tree())
		var first_report: Dictionary = PATHFIND.last_path_report.duplicate(true)
		var first_goal: Vector3 = first_report.get("resolved_goal",first_request)
		var second_route: Array = PATHFIND.find_path(first_goal,final_goal,get_tree())
		var second_report: Dictionary = PATHFIND.last_path_report.duplicate(true)
		var second_goal: Vector3 = second_report.get("resolved_goal",final_goal)
		var first_points: Array[Vector3] = [start]
		for waypoint in first_route:
			if waypoint is Vector3: first_points.append(waypoint)
		if first_points.back().distance_to(first_goal)>0.05: first_points.append(first_goal)
		var second_points: Array[Vector3] = [first_goal]
		for waypoint in second_route:
			if waypoint is Vector3: second_points.append(waypoint)
		if second_points.back().distance_to(second_goal)>0.05: second_points.append(second_goal)
		var first_clearance := _cooperative_min_route_clearance(first_points,pursuers)
		var second_clearance := _cooperative_min_route_clearance(second_points,pursuers)
		var tower_to_end := Vector2(tower_pos.x-second_goal.x,tower_pos.z-second_goal.z).length()
		var pursuer_melee_in_tower: bool = tower_to_end + COMBAT.MELEE_RANGE < tower_range
		var first_distance := _cooperative_waypoint_distance(start,first_route,first_goal)
		var second_distance := _cooperative_waypoint_distance(first_goal,second_route,second_goal)
		var both_paths_reached := bool(first_report.get("search_reached_goal",first_route.is_empty())) and bool(second_report.get("search_reached_goal",second_route.is_empty()))
		var route_candidate_passed := both_paths_reached and first_clearance >= COMBAT.MELEE_RANGE and second_clearance >= 3.5 and pursuer_melee_in_tower
		route_records.append({"first_requested_waypoint":_v3(first_request),"first_resolved_goal":_v3(first_goal),"first_segment_waypoints":first_route.duplicate(true),"first_path_report":first_report,"first_path_distance":first_distance,"first_walk_eta_at_villager_base_speed":first_distance/4.5,"first_min_pursuer_clearance":first_clearance,"second_requested_goal":_v3(final_goal),"second_resolved_goal":_v3(second_goal),"second_segment_waypoints":second_route.duplicate(true),"second_path_report":second_report,"second_path_distance":second_distance,"second_walk_eta_at_villager_base_speed":second_distance/4.5,"second_min_historical_pursuer_clearance":second_clearance,"tower_distance_to_resolved_end":tower_to_end,"pursuer_at_melee_range_inside_tower_range":pursuer_melee_in_tower,"both_path_searches_reached_goal":both_paths_reached,"route_candidate_passed":route_candidate_passed})
	var historical_pursuer_positions: Array = []
	for pursuer_position in pursuers: historical_pursuer_positions.append(_v3(pursuer_position))
	var route_plan_passed := false
	for route_record in route_records:
		route_plan_passed = route_plan_passed or bool(route_record.get("route_candidate_passed",false))
	var guard_start := Vector3(-15.407934,0.0,0.157832)
	var guard_post := Vector3(-10.0,0.0,-7.0)
	var guard_path: Array = PATHFIND.find_path(guard_start,guard_post,get_tree())
	var guard_path_report: Dictionary = PATHFIND.last_path_report.duplicate(true)
	var guard_resolved_post: Vector3 = guard_path_report.get("resolved_goal",guard_post)
	var guard_route_distance := _cooperative_waypoint_distance(guard_start,guard_path,guard_resolved_post)
	var guard_to_pursuers: Array[float] = []
	for pursuer in pursuers: guard_to_pursuers.append(guard_resolved_post.distance_to(pursuer))
	var guard_plan := {"source_soldier_position":_v3(guard_start),"requested_guard_point":_v3(guard_post),"resolved_guard_point":_v3(guard_resolved_post),"path_waypoints":guard_path.duplicate(true),"path_report":guard_path_report,"path_distance":guard_route_distance,"base_speed":5.2,"estimated_preposition_eta":guard_route_distance/5.2,"resolved_guard_to_visible_pursuer_distances":guard_to_pursuers,"guard_acquire_range":5.0,"guard_leash":8.0,"can_acquire_current_alert_pursuers":guard_to_pursuers.all(func(d: float): return d<=5.0)}
	var report_data := {"passed":route_plan_passed,"natural_seed":int(game.get("map_seed")),"no_entities_or_orders_injected":true,"historical_r87_start":_v3(start),"historical_r87_visible_pursuers":historical_pursuer_positions,"live_map_tower_position_reference":_v3(tower_pos),"tower_range_reference":tower_range,"candidate_final_stop":_v3(final_goal),"final_stop_radius":4.0,"melee_margin_inside_tower":tower_range-4.0-COMBAT.MELEE_RANGE,"frontline_guard_preposition_plan":guard_plan,"routes":route_records}
	report["cooperative_route_preflight"] = report_data
	events.append({"action":"cooperative_historical_route_preflight","details":report_data})
	_finish(bool(report_data.get("passed",false)),"cooperative_historical_route_preflight_completed",report_data)

func _cooperative_min_route_clearance(points: Array[Vector3],threats: Array[Vector3]) -> float:
	var best := INF
	for threat in threats:
		for index in range(points.size()-1):
			best = minf(best,_cooperative_xz_distance_to_segment(threat,points[index],points[index+1]))
	return best

func _cooperative_xz_distance_to_segment(point: Vector3,start: Vector3,finish: Vector3) -> float:
	var p := Vector2(point.x,point.z)
	var a := Vector2(start.x,start.z)
	var b := Vector2(finish.x,finish.z)
	var segment := b-a
	if segment.length_squared() <= 0.0001:
		return p.distance_to(a)
	var ratio := clampf((p-a).dot(segment)/segment.length_squared(),0.0,1.0)
	return p.distance_to(a+segment*ratio)

func _cooperative_waypoint_distance(from: Vector3,route: Array,to: Vector3) -> float:
	var distance := 0.0
	var previous := from
	for point in route:
		if point is Vector3:
			distance += previous.distance_to(point)
			previous = point
	distance += previous.distance_to(to)
	return distance

func _sample_cooperative_protection(game: Node) -> void:
	var worker: Variant = instance_from_id(cooperative_worker_id)
	var game_time := float(game.get("_game_time"))
	if not is_instance_valid(worker) or not bool(worker.get("alive")):
		var fatal_pursuers: Array[Dictionary] = []
		for zombie in _living_zombies():
			var target: Variant = zombie.get("attack_target")
			if target == worker:
				fatal_pursuers.append({"id":zombie.get_instance_id(),"name":zombie.name,"position":_v3(zombie.global_position),"hp":float(zombie.get("hp"))})
		var fatal_soldiers: Array[Dictionary] = []
		for soldier in _player_soldiers():
			fatal_soldiers.append({"id":soldier.get_instance_id(),"name":soldier.name,"position":_v3(soldier.global_position),"hp":float(soldier.get("hp")),"target":(soldier.get("attack_target") as Node).name if is_instance_valid(soldier.get("attack_target")) else "","guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor"))})
		_finish(false,"cooperative_worker_lost_before_recovery_cycle",{"game_time":game_time,"worker_id":cooperative_worker_id,"worker_last_position":_v3(cooperative_last_worker_position),"worker_hp_last":cooperative_last_worker_hp,"reached_staging":cooperative_reached_staging,"gather_resumed":cooperative_gather_resumed,"resource_reduced":cooperative_resource_reduced,"new_carry":cooperative_new_carry,"deposit_after_new_carry":cooperative_deposit_after_new_carry,"pursuers_still_targeting_worker":fatal_pursuers,"soldiers":fatal_soldiers,"attack_targets":cooperative_attack_targets.duplicate(true),"preserved_guards":cooperative_preserved_guards.duplicate(true),"tower_id":cooperative_tower_id})
		return
	cooperative_last_worker_position = worker.global_position
	cooperative_last_worker_hp = float(worker.get("hp"))
	_cooperative_assign_new_alert_pursuers(game,worker)
	if not cooperative_reached_staging and worker.global_position.distance_to(cooperative_staging) < 0.55 and Array(worker.get("_waypoints")).is_empty() and int(worker.get("state")) == 0:
		cooperative_reached_staging = true
		events.append({"at_game_time":game_time,"action":"cooperative_worker_move_completed_at_rally","worker_id":cooperative_worker_id,"position":_v3(worker.global_position),"staging_point":_v3(cooperative_staging),"position_error":worker.global_position.distance_to(cooperative_staging),"waypoint_count":Array(worker.get("_waypoints")).size(),"state":int(worker.get("state"))})
	var outstanding: Array[Node] = []
	for target_record in cooperative_attack_targets:
		var enemy: Variant = instance_from_id(int(target_record.get("id",0)))
		if is_instance_valid(enemy) and bool(enemy.get("alive")):
			outstanding.append(enemy)
	if cooperative_reached_staging and not cooperative_gather_resumed and outstanding.is_empty():
		var current_pursuers: Array[Node] = []
		for enemy in _living_zombies():
			if enemy.get("attack_target") == worker:
				current_pursuers.append(enemy)
		if current_pursuers.is_empty():
			var resource: Variant = instance_from_id(cooperative_resource_id) if cooperative_resource_id > 0 else null
			if not is_instance_valid(resource) or int(resource.get("amount")) <= 0:
				resource = _cooperative_visible_guarded_wood_resource(game,worker)
				if is_instance_valid(resource):
					cooperative_resource_id = resource.get_instance_id()
			if is_instance_valid(resource) and int(resource.get("amount")) > 0:
				var nearest_attacker: Variant = null
				var nearest_distance: float = INF
				for soldier_id in cooperative_attackers:
					var soldier: Variant = instance_from_id(soldier_id)
					if not is_instance_valid(soldier) or not bool(soldier.get("alive")):
						continue
					var dist: float = (soldier as Node3D).global_position.distance_to((resource as Node3D).global_position)
					if dist < nearest_distance:
						nearest_attacker = soldier
						nearest_distance = dist
				if is_instance_valid(nearest_attacker) and nearest_distance < 8.0:
					_select(game,[nearest_attacker])
					nearest_attacker.call("command_guard",resource.global_position)
					_select(game,[worker])
					game.call("_command_at",resource.global_position)
					cooperative_gather_resumed = worker.get("gather_target") == resource
					cooperative_resource_amount_baseline = int(resource.get("amount"))
					cooperative_carry_baseline = int(worker.get("carry_amount")) if str(worker.get("carry_key")) == "wood" else 0
					cooperative_last_resource_amount = cooperative_resource_amount_baseline
					cooperative_last_carry = cooperative_carry_baseline
					events.append({"at_game_time":game_time,"action":"threat_removed_player_posts_guard_then_resumes_gather","worker_id":cooperative_worker_id,"resource_id":cooperative_resource_id,"resource_pos":_v3(resource.global_position),"resource_amount_before_gather":cooperative_resource_amount_baseline,"pursuers_alive":0,"guard_soldier_id":nearest_attacker.get_instance_id(),"guard_anchor":_v3(nearest_attacker.get("guard_anchor")),"guard_distance_to_resource":nearest_distance,"guard_leash":8.0,"guard_reached_resource_before_gather":nearest_distance<8.0,"command":"Soldier3D.command_guard(resource.global_position), then Main._command_at(resource.global_position) after all observed pursuers were removed","worker_gather_target":resource.name if is_instance_valid(worker.get("gather_target")) else "","worker_state":int(worker.get("state"))})
			else:
				_finish(false,"cooperative_resource_invalid_after_threat_removed",{"game_time":game_time,"worker_id":cooperative_worker_id,"resource_id":cooperative_resource_id})
				return
	if cooperative_gather_resumed:
		var resource_now: Variant = instance_from_id(cooperative_resource_id)
		var carry := int(worker.get("carry_amount")) if str(worker.get("carry_key")) == "wood" else 0
		if is_instance_valid(resource_now):
			var resource_amount := int(resource_now.get("amount"))
			if not cooperative_resource_reduced and resource_amount < cooperative_last_resource_amount:
				cooperative_resource_reduced = true
				events.append({"at_game_time":game_time,"action":"cooperative_resource_amount_decreased_after_gather_resume","resource_id":cooperative_resource_id,"amount_before":cooperative_last_resource_amount,"amount_after":resource_amount,"worker_id":cooperative_worker_id})
			if cooperative_resource_reduced and not cooperative_new_carry and carry > maxi(cooperative_last_carry,cooperative_carry_baseline):
				cooperative_new_carry = true
				cooperative_new_carry_at = game_time
				events.append({"at_game_time":game_time,"action":"cooperative_worker_new_wood_carry","worker_id":cooperative_worker_id,"carry_before":maxi(cooperative_last_carry,cooperative_carry_baseline),"carry_after":carry,"resource_id":cooperative_resource_id})
			cooperative_last_resource_amount = resource_amount
			cooperative_last_carry = carry
	if cooperative_deposit_after_new_carry and not cooperative_paid_reinforcement_queued:
		_cooperative_queue_paid_reinforcement(game)
	var live_food_workers := _food_workers_with_live_target()
	var food_income_observed := int(game.get("meat")) > cooperative_initial_meat and _total_live_farm_stock() > 0 and live_food_workers > 0
	var paid_queue_live := _cooperative_paid_queue_live(game)
	if cooperative_deposit_after_new_carry and food_income_observed and paid_queue_live and bool(worker.get("alive")):
		cooperative_protection_active = false
		cooperative_protection_complete = true
		var success := {"passed":true,"worker_alive":true,"worker_hp":float(worker.get("hp")),"worker_id":cooperative_worker_id,"move_completed_at_rally":cooperative_reached_staging,"attack_targets":cooperative_attack_targets.duplicate(true),"attacking_soldier_ids":cooperative_attackers.duplicate(),"preserved_guards":cooperative_preserved_guards.duplicate(true),"threats_removed_before_gather":true,"gather_resumed_after_threat_removal":cooperative_gather_resumed,"resource_amount_decreased":cooperative_resource_reduced,"new_wood_carry":cooperative_new_carry,"worker_wood_deposits":recovery_deposit_log.duplicate(true),"wood_before":cooperative_initial_wood,"wood_now":int(game.get("wood")),"food_income_observed":food_income_observed,"meat_before":cooperative_initial_meat,"meat_now":int(game.get("meat")),"live_food_workers":live_food_workers,"paid_reinforcement_queued":paid_queue_live,"soldiers_alive":_player_soldiers().size(),"tower_id":cooperative_tower_id,"tower_range":float((instance_from_id(cooperative_tower_id) as Node).get("attack_range")) if is_instance_valid(instance_from_id(cooperative_tower_id)) else 0.0}
		report["cooperative_protection_slice"] = success
		events.append({"at_game_time":game_time,"action":"cooperative_protection_slice_passed_campaign_continues","details":success})
	elif game_time >= cooperative_deadline:
		_finish(false,"cooperative_protection_slice_timeout",{"game_time":game_time,"worker_alive":true,"worker_hp":float(worker.get("hp")),"move_completed_at_rally":cooperative_reached_staging,"gather_resumed_after_threat_removal":cooperative_gather_resumed,"resource_amount_decreased":cooperative_resource_reduced,"new_wood_carry":cooperative_new_carry,"deposit_after_new_carry":cooperative_deposit_after_new_carry,"food_income_observed":food_income_observed,"live_food_workers":live_food_workers,"paid_reinforcement_queued":paid_queue_live,"wood":int(game.get("wood")),"meat":int(game.get("meat")),"attack_targets":cooperative_attack_targets.duplicate(true),"preserved_guards":cooperative_preserved_guards.duplicate(true)})

func _food_workers_with_live_target() -> int:
	var count := 0
	for worker in _living_villagers():
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock")) > 0:
			count += 1
	return count

func _cooperative_assign_new_alert_pursuers(game: Node, worker: Node3D) -> void:
	var alerts: Dictionary = game.get("_combat_damage_alerts")
	var now_msec := Time.get_ticks_msec()
	var worker_has_fresh_alert := false
	for alert in alerts.values():
		if str(alert.get("category","")) != "economy_unit" or now_msec-int(alert.get("last_hit_msec",0)) > 12000:
			continue
		if Array(alert.get("victim_instance_ids",[])).has(cooperative_worker_id):
			worker_has_fresh_alert = true
			break
	if not worker_has_fresh_alert:
		return
	var camera: Camera3D = game.get("camera")
	for enemy in _living_zombies():
		if enemy.get("attack_target") != worker or not _enemy_on_player_screen(camera,enemy):
			continue
		var already_ordered := false
		for target_record in cooperative_attack_targets:
			if int(target_record.get("id",0)) == enemy.get_instance_id():
				already_ordered = true
				break
		if already_ordered:
			continue
		var available_ids: Array[int] = []
		var protected_opposite_flank := false
		for guard_record in cooperative_preserved_guards:
			var guard_id := int(guard_record.get("id",0))
			var guard: Variant = instance_from_id(guard_id)
			if not is_instance_valid(guard) or not bool(guard.get("alive")):
				continue
			var same_side: bool = ((guard as Node3D).global_position.x < 0.0) == (enemy.global_position.x < 0.0)
			if not same_side:
				protected_opposite_flank = true
			available_ids.append(guard_id)
		if available_ids.size() <= 1 or not protected_opposite_flank:
			return # Retain a physically present defender on the opposite approach.
		var best_id := 0
		var best_dist := INF
		for soldier_id in available_ids:
			var soldier: Variant = instance_from_id(soldier_id)
			if not is_instance_valid(soldier) or not bool(soldier.get("alive")):
				continue
			var dist := _cooperative_path_distance(soldier as Node3D,enemy,game)
			if dist < best_dist:
				best_dist = dist
				best_id = soldier_id
		if best_id == 0:
			return
		var attacker: Variant = instance_from_id(best_id)
		_select(game,[attacker])
		attacker.call("command_attack_unit",enemy,false)
		cooperative_attackers.append(best_id)
		for index in range(cooperative_preserved_guards.size()-1,-1,-1):
			if int(cooperative_preserved_guards[index].get("id",0)) == best_id:
				cooperative_preserved_guards.remove_at(index)
				break
		cooperative_attack_targets.append({"id":enemy.get_instance_id(),"name":enemy.name,"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position),"wave":int(enemy.get("horde_wave_id"))})
		events.append({"at_game_time":float(game.get("_game_time")),"action":"player_attack_new_visible_pursuer_from_fresh_alert","alert_victim_id":cooperative_worker_id,"enemy_id":enemy.get_instance_id(),"enemy_name":enemy.name,"enemy_position":_v3(enemy.global_position),"soldier_id":best_id,"soldier_name":attacker.name,"soldier_position":_v3(attacker.global_position),"estimated_path_distance":best_dist,"command":"Soldier3D.command_attack_unit(target,false)","preserved_guards_after_order":cooperative_preserved_guards.duplicate(true)})

func _cooperative_visible_guarded_wood_resource(game: Node, worker: Node3D) -> Node3D:
	var camera: Camera3D = game.get("camera")
	var nearest: Node3D = null
	var nearest_worker_distance := INF
	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource) or not resource.has_method("res_key") or str(resource.call("res_key")) != "wood" or int(resource.get("amount")) <= 0:
			continue
		if not _enemy_on_player_screen(camera,resource as Node3D):
			continue
		var guarded := false
		for soldier_id in cooperative_attackers:
			var soldier: Variant = instance_from_id(soldier_id)
			if is_instance_valid(soldier) and bool(soldier.get("alive")) and (soldier as Node3D).global_position.distance_to((resource as Node3D).global_position) < 8.0:
				guarded = true
				break
		if not guarded:
			continue
		var distance: float = worker.global_position.distance_to((resource as Node3D).global_position)
		if distance < nearest_worker_distance:
			nearest = resource as Node3D
			nearest_worker_distance = distance
	return nearest

func _cooperative_skip(game: Node, reason: String, alert_key: String) -> bool:
	var now := Time.get_ticks_msec()
	if reason != cooperative_last_skip_reason or now-cooperative_last_skip_msec >= 2500:
		cooperative_last_skip_reason = reason
		cooperative_last_skip_msec = now
		events.append({"at_game_time":float(game.get("_game_time")),"action":"cooperative_alert_candidate_not_actionable","reason":reason,"alert_key":alert_key,"living_villagers":_living_villagers().size(),"visible_zombies":_living_zombies().size(),"west_guard_count":_player_soldiers().filter(func(s: Node) -> bool: return bool(s.get("guard_active")) and (s.get("guard_anchor") as Vector3).x<0.0).size()})
	return false

func _cooperative_queue_paid_reinforcement(game: Node) -> void:
	var barracks := _first_building(game,CATALOG.BARRACKS,true)
	var cost: Dictionary = CATALOG.train_cost("soldier")
	var free_pop := int(game.get("pop_cap"))-int(game.get("population"))-int(game.call("_queued_pop"))
	if barracks == null or _queue_count(game,"soldier") > 0 or free_pop <= 0 or int(game.get("meat")) < int(cost.get("meat",60)) or int(game.get("wood")) < int(cost.get("wood",20)):
		return
	_select(game,[barracks])
	var meat_before := int(game.get("meat"))
	var wood_before := int(game.get("wood"))
	game.call("_on_train_soldier")
	var queued := _queue_count(game,"soldier") > 0
	var paid := bool(barracks.get("train_paid")) and not bool(barracks.get("train_paused"))
	cooperative_paid_reinforcement_queued = queued and paid
	events.append({"at_game_time":float(game.get("_game_time")),"action":"cooperative_player_normal_paid_soldier_queue","command":"selected completed barracks then Main._on_train_soldier","queue_count":_queue_count(game,"soldier"),"paid":paid,"meat_before":meat_before,"meat_after":int(game.get("meat")),"wood_before":wood_before,"wood_after":int(game.get("wood")),"normal_cost":cost,"free_population":free_pop})

func _cooperative_paid_queue_live(game: Node) -> bool:
	if cooperative_paid_reinforcement_queued:
		return true
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player" or _queue_count_for_building(building,"soldier") <= 0:
			continue
		if bool(building.get("train_paid")) and not bool(building.get("train_paused")):
			return true
	return false

func _finish_natural_recovery_window(game: Node) -> Dictionary:
	var worker: Variant = instance_from_id(recovery_worker_id)
	var alive := is_instance_valid(worker) and bool(worker.get("alive"))
	var wood_workers := 0
	for villager in _living_villagers():
		var target: Variant = villager.get("gather_target")
		if is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key")) == "wood":
			wood_workers += 1
	var manual_priority_held := alive and bool(worker.get("manual_order_suppresses_auto_defense"))
	var wood_gain := int(game.get("wood"))-recovery_initial_wood
	var worker_wood_deposit := false
	for deposit in recovery_deposit_log:
		if str(deposit.get("res_key")) == "wood" and int(deposit.get("amount",0)) > 0:
			worker_wood_deposit = true
	var result := {"passed":recovery_command_chain_ok and alive and manual_priority_held and worker_wood_deposit and wood_gain > 0 and wood_workers > 0,"player_command_chain_verified":recovery_command_chain_ok,"worker_id":recovery_worker_id,"worker_alive":alive,"hp_start":recovery_initial_hp,"hp_end":float(worker.get("hp")) if alive else 0.0,"manual_priority_held":manual_priority_held,"worker_state":int(worker.get("state")) if alive else -1,"worker_goal":_v3(worker.get("_goal_final")) if alive else [],"worker_gather_target":(worker.get("gather_target") as Node).name if alive and is_instance_valid(worker.get("gather_target")) else "","carry_key":str(worker.get("carry_key")) if alive else "","carry_amount":int(worker.get("carry_amount")) if alive else 0,"wood_start":recovery_initial_wood,"wood_end":int(game.get("wood")),"wood_gain_actual":wood_gain,"worker_wood_deposit_observed":worker_wood_deposit,"worker_deposits":recovery_deposit_log.duplicate(true),"meat_start":recovery_initial_meat,"meat_end":int(game.get("meat")),"live_wood_workers":wood_workers,"paid_soldier_queue":_queue_count(game,"soldier")>0,"soldiers_alive":_player_soldiers().size(),"recovery_window_seconds":25.0,"economy_resilient":_campaign_still_viable(game)}
	events.append({"at_game_time":float(game.get("_game_time")),"action":"natural_recovery_window_result"}.merged(result))
	return result

func _on_recovery_worker_deposited(res_key: String, amount: int, worker_id: int) -> void:
	if worker_id != recovery_worker_id:
		if worker_id != cooperative_worker_id:
			return
	var game := get_tree().get_first_node_in_group("main_game")
	var record := {"at_game_time":float(game.get("_game_time")) if is_instance_valid(game) else -1.0,"worker_id":worker_id,"res_key":res_key,"amount":amount,"wood_after":int(game.get("wood")) if is_instance_valid(game) else -1,"meat_after":int(game.get("meat")) if is_instance_valid(game) else -1}
	recovery_deposit_log.append(record)
	recovery_deposits += 1
	if recovery_probe_new_carry and str(res_key) == "wood" and float(record.get("at_game_time",-1.0)) > recovery_probe_new_carry_at:
		recovery_probe_deposit_after_new_carry = true
	if cooperative_new_carry and str(res_key) == "wood" and float(record.get("at_game_time",-1.0)) > cooperative_new_carry_at:
		cooperative_deposit_after_new_carry = true
	events.append({"action":"natural_recovery_worker_deposit"}.merged(record))

func _sample_recovery_command_probe(game: Node) -> void:
	var worker: Variant = instance_from_id(recovery_worker_id)
	if not is_instance_valid(worker) or not bool(worker.get("alive")):
		_finish(false,"recovery_command_probe_worker_lost_before_cycle_complete",{"reached_staging":recovery_probe_reached_staging,"resource_decreased":recovery_probe_resource_decreased,"new_carry":recovery_probe_new_carry,"deposit_after_new_carry":recovery_probe_deposit_after_new_carry})
		return
	var game_time := float(game.get("_game_time"))
	if not recovery_probe_reached_staging and worker.global_position.distance_to(recovery_staging_point) < 1.5:
		recovery_probe_reached_staging = true
		events.append({"at_game_time":game_time,"action":"recovery_probe_arrived_at_staging","worker_id":recovery_worker_id,"position":_v3(worker.global_position),"staging_point":_v3(recovery_staging_point),"queued_orders":Array(worker.get("order_queue")).size()})
	var target: Variant = worker.get("gather_target")
	if is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key")) == "wood":
		var resource_amount := int(target.get("amount"))
		var carry := int(worker.get("carry_amount")) if str(worker.get("carry_key")) == "wood" else 0
		if recovery_probe_resource_id != int(target.get_instance_id()):
			recovery_probe_resource_id = target.get_instance_id()
			recovery_probe_last_resource_amount = resource_amount
			recovery_probe_last_carry = carry
		if recovery_probe_reached_staging and not recovery_probe_resource_decreased and recovery_probe_last_resource_amount >= 0 and resource_amount < recovery_probe_last_resource_amount:
			recovery_probe_resource_decreased = true
			events.append({"at_game_time":game_time,"action":"recovery_probe_resource_stock_decreased","worker_id":recovery_worker_id,"resource_id":target.get_instance_id(),"amount_before":recovery_probe_last_resource_amount,"amount_after":resource_amount})
		if recovery_probe_resource_decreased and not recovery_probe_new_carry and carry > maxi(recovery_probe_last_carry,recovery_probe_initial_carry):
			recovery_probe_new_carry = true
			recovery_probe_new_carry_at = game_time
			events.append({"at_game_time":game_time,"action":"recovery_probe_new_wood_carry_observed","worker_id":recovery_worker_id,"carry_before":maxi(recovery_probe_last_carry,recovery_probe_initial_carry),"carry_after":carry,"resource_id":target.get_instance_id()})
		recovery_probe_last_resource_amount = resource_amount
		recovery_probe_last_carry = carry
	if recovery_probe_deposit_after_new_carry:
		_finish(true,"recovery_command_staging_gather_deposit_cycle_verified",{"worker_id":recovery_worker_id,"reached_staging":recovery_probe_reached_staging,"resource_decreased":recovery_probe_resource_decreased,"new_carry":recovery_probe_new_carry,"deposit_after_new_carry":true,"deposits":recovery_deposit_log.duplicate(true),"time_after_command":game_time-recovery_probe_started_at})
	elif game_time-recovery_probe_started_at >= 45.0:
		_finish(false,"recovery_command_probe_cycle_timeout",{"worker_id":recovery_worker_id,"reached_staging":recovery_probe_reached_staging,"resource_decreased":recovery_probe_resource_decreased,"new_carry":recovery_probe_new_carry,"deposit_after_new_carry":recovery_probe_deposit_after_new_carry,"deposits":recovery_deposit_log.duplicate(true),"time_after_command":game_time-recovery_probe_started_at})

func _reserved_building_site(worker: Node) -> Node:
	if worker == null or not is_instance_valid(worker): return null
	var worker_id := str(worker.get_instance_id())
	var site: Variant = worker.get("build_site")
	var reserved: Variant = builder_assignments.get(worker_id)
	if is_instance_valid(reserved) and site != reserved:
		builder_assignments.erase(worker_id)
	if not is_instance_valid(site): site = null
	if not is_instance_valid(site) or bool(site.get("is_complete")):
		builder_assignments.erase(worker_id)
		return null
	return site

func _select(game: Node, nodes: Array) -> void:
	game.call("_clear_selection")
	for node in nodes:
		if is_instance_valid(node) and node.is_inside_tree(): game.call("_add_to_selection", node)
	game.call("_refresh_selection_hud")

func _nearest_resource(kind: int, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(node) or node.is_in_group("buildings") or int(node.get("kind")) != kind or int(node.get("amount")) <= 0: continue
		var d := Vector2(node.global_position.x-from.x,node.global_position.z-from.z).length_squared()
		if d < best_distance: best_distance=d; best=node as Node3D
	return best

func _live_farms() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("farms"):
		if is_instance_valid(node) and bool(node.get("alive")) and bool(node.get("is_complete")) and int(node.get("meat_stock")) > 0 and str(node.get("team")) == "player": result.append(node as Node3D)
	return result

func _total_farm_stock(farms: Array) -> int:
	var total := 0
	for farm in farms: total += int(farm.get("meat_stock"))
	return total

func _building_count(game: Node, kind: int) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and str(node.get("team")) == "player" and int(node.get("kind")) == kind and bool(node.get("alive")): count += 1
	return count

func _building_count_complete(game: Node, kind: int) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and str(node.get("team")) == "player" and int(node.get("kind")) == kind and bool(node.get("alive")) and bool(node.get("is_complete")): count += 1
	return count

func _first_building(game: Node, kind: int, complete: bool = false) -> Node:
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and str(node.get("team")) == "player" and int(node.get("kind")) == kind and bool(node.get("alive")) and (not complete or bool(node.get("is_complete"))): return node
	return null

func _building_id_set(kind: int) -> Dictionary:
	var ids := {}
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and int(node.get("kind")) == kind: ids[str(node.get_instance_id())]=true
	return ids

func _new_building(kind: int, old_ids: Dictionary, around: Vector3) -> Node3D:
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and int(node.get("kind")) == kind and not old_ids.has(str(node.get_instance_id())) and node.global_position.distance_to(around) < 1.0: return node as Node3D
	return null

func _queue_count(game: Node, unit_type: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or str(node.get("team")) != "player": continue
		for queued in Array(node.get("train_queue")): if str(queued) == unit_type: count += 1
	return count

func _queue_count_for_building(building: Node, unit_type: String) -> int:
	if building == null or not is_instance_valid(building):
		return 0
	var count := 0
	for queued in Array(building.get("train_queue")):
		if str(queued) == unit_type:
			count += 1
	return count

func _living_villagers() -> Array:
	return get_tree().get_nodes_in_group("villagers").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")) and str(n.get("team")) == "player")

func _player_soldiers() -> Array:
	return get_tree().get_nodes_in_group("soldiers").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")) and str(n.get("team")) == "player" and n.get("is_zombie") != true)

func _living_zombies() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")))

func _defensive_anchor(farms: Array, workers: Array) -> Vector3:
	if not farms.is_empty(): return farms[0].global_position
	if not workers.is_empty(): return workers[0].global_position
	return Vector3.ZERO

func _unit_counts() -> Dictionary:
	return {"villagers":_living_villagers().size(),"soldiers":_player_soldiers().size(),"zombies":_living_zombies().size(),"buildings":get_tree().get_nodes_in_group("buildings").size()}

func _wait_for_game(predicate: Callable, max_frames: int) -> Node:
	for _frame in max_frames:
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and predicate.call(game): return game
		await get_tree().process_frame
	return null

func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for _frame in max_frames:
		if predicate.call(): return true
		await get_tree().process_frame
	return false

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

func _find_button(root: Node, label: String) -> Button:
	if root == null: return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text == label: return node as Button
		for child in node.get_children(): stack.append(child)
	return null

func _arg(args: Array, key: String, fallback: String) -> String:
	for arg in args:
		var value := str(arg)
		if value.begins_with("--" + key + "="): return value.get_slice("=",1)
	return fallback

func _run_projectile_lifecycle_regression(game: Node) -> void:
	var results: Array[Dictionary] = []
	var next_offset := Vector3(18.0, 0.0, 18.0)
	var first := _spawn_projectile_fixture(game, next_offset, next_offset + Vector3(5.5, 0.0, 0.0))
	var tower: Node3D = first[0]
	var target: Node3D = first[1]
	var arrow: Node = await _wait_for_projectile(tower.get_instance_id(), 240)
	if arrow == null:
		_finish(false, "projectile_owner_destroyed_no_real_tower_launch", {"phase":"owner_destroyed_before_hit"})
		return
	var owner_case: Dictionary = {"case":"owner_destroyed_before_impact","real_tower_id":tower.get_instance_id(),"real_target_id":target.get_instance_id(),"tower_damage":float(tower.get("attack_damage")),"target_hp_before":float(target.get("hp")),"arrow_spawned":true,"attacker_destroyed":false,"attacker_argument_null":false,"target_hp_delta":0.0,"arrow_released":false,"passed":false}
	var owner_impacts: Array[Dictionary] = []
	arrow.connect("diagnostic_impact", func(attacker: Node3D, hit_target: Node3D, nominal: float, actual: float, before: float, after: float) -> void:
		owner_impacts.append({"attacker_valid":is_instance_valid(attacker),"target_id":hit_target.get_instance_id() if is_instance_valid(hit_target) else 0,"nominal_damage":nominal,"actual_damage":actual,"hp_before":before,"hp_after":after}))
	var owner_arrow_id := arrow.get_instance_id()
	tower.free()
	owner_case["attacker_destroyed"] = not is_instance_valid(tower)
	for frame in 120:
		if not owner_impacts.is_empty() and not is_instance_valid(instance_from_id(owner_arrow_id)):
			break
		await get_tree().process_frame
	owner_case["arrow_released"] = not is_instance_valid(instance_from_id(owner_arrow_id))
	owner_case["impact"] = owner_impacts[0] if not owner_impacts.is_empty() else {}
	if not owner_impacts.is_empty():
		owner_case["attacker_argument_null"] = not bool(owner_impacts[0].get("attacker_valid", true))
		owner_case["target_hp_delta"] = float(owner_impacts[0].get("hp_before", 0.0)) - float(owner_impacts[0].get("hp_after", 0.0))
	owner_case["target_alive"] = is_instance_valid(target) and COMBAT.is_alive(target)
	owner_case["passed"] = bool(owner_case["attacker_destroyed"]) and bool(owner_case["attacker_argument_null"]) and bool(owner_case["arrow_released"]) and is_equal_approx(float(owner_case["target_hp_delta"]), float(owner_case["tower_damage"])) and bool(owner_case["target_alive"])
	results.append(owner_case)
	if is_instance_valid(target): target.free()

	var second := _spawn_projectile_fixture(game, next_offset + Vector3(18.0, 0.0, 0.0), next_offset + Vector3(23.5, 0.0, 0.0))
	tower = second[0]; target = second[1]
	arrow = await _wait_for_projectile(tower.get_instance_id(), 240)
	if arrow == null:
		_finish(false, "projectile_lifecycle_regression_no_live_owner_launch", {"cases":results})
		return
	var live_impacts: Array[Dictionary] = []
	arrow.connect("diagnostic_impact", func(attacker: Node3D, hit_target: Node3D, nominal: float, actual: float, before: float, after: float) -> void:
		live_impacts.append({"attacker_same":attacker == tower,"nominal_damage":nominal,"actual_damage":actual,"hp_before":before,"hp_after":after}))
	var live_arrow_id := arrow.get_instance_id()
	for frame in 120:
		if not live_impacts.is_empty() and not is_instance_valid(instance_from_id(live_arrow_id)):
			break
		await get_tree().process_frame
	var live_case := {"case":"owner_stays_alive","attacker_alive":is_instance_valid(tower),"impact":live_impacts[0] if not live_impacts.is_empty() else {},"arrow_released":not is_instance_valid(instance_from_id(live_arrow_id))}
	live_case["passed"] = bool(live_case["attacker_alive"]) and bool(live_case["arrow_released"]) and not live_impacts.is_empty() and bool(live_impacts[0].get("attacker_same", false)) and is_equal_approx(float(live_impacts[0].get("nominal_damage", -1.0)), float(tower.get("attack_damage"))) and is_equal_approx(float(live_impacts[0].get("actual_damage", -1.0)), float(tower.get("attack_damage")))
	results.append(live_case)
	if is_instance_valid(tower): tower.free()
	if is_instance_valid(target): target.free()

	var third := _spawn_projectile_fixture(game, next_offset + Vector3(36.0, 0.0, 0.0), next_offset + Vector3(41.5, 0.0, 0.0))
	tower = third[0]; target = third[1]
	arrow = await _wait_for_projectile(tower.get_instance_id(), 240)
	if arrow == null:
		_finish(false, "projectile_lifecycle_regression_no_target_case_launch", {"cases":results})
		return
	var target_impacts: Array = []
	arrow.connect("diagnostic_impact", func(_attacker: Node3D, hit_target: Node3D, nominal: float, actual: float, before: float, after: float) -> void:
		target_impacts.append({"target_id":hit_target.get_instance_id() if is_instance_valid(hit_target) else 0,"nominal_damage":nominal,"actual_damage":actual,"hp_before":before,"hp_after":after}))
	var target_arrow_id := arrow.get_instance_id()
	var target_hp_before := float(target.get("hp"))
	target.free()
	for frame in 30:
		if not is_instance_valid(instance_from_id(target_arrow_id)):
			break
		await get_tree().process_frame
	var target_case := {"case":"target_destroyed_before_impact","target_destroyed":not is_instance_valid(target),"hp_before":target_hp_before,"impact_count":target_impacts.size(),"arrow_released":not is_instance_valid(instance_from_id(target_arrow_id))}
	target_case["passed"] = bool(target_case["target_destroyed"]) and int(target_case["impact_count"]) == 0 and bool(target_case["arrow_released"])
	results.append(target_case)
	if is_instance_valid(tower): tower.free()

	var fourth := _spawn_projectile_fixture(game, next_offset + Vector3(54.0, 0.0, 0.0), next_offset + Vector3(59.5, 0.0, 0.0))
	tower = fourth[0]; target = fourth[1]
	# A low-health test target exercises the normal production damage/death path without changing combat constants.
	target.call("take_damage", 38.0, false, null)
	var lethal_impacts: Array[Dictionary] = []
	var lethal_deadline := Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < lethal_deadline and COMBAT.is_alive(target):
		for projectile in get_tree().get_nodes_in_group("arrows"):
			if projectile.get("_attacker") == tower and not bool(projectile.get_meta("lifecycle_signal_connected", false)):
				projectile.set_meta("lifecycle_signal_connected", true)
				projectile.connect("diagnostic_impact", func(attacker: Node3D, hit_target: Node3D, nominal: float, actual: float, before: float, after: float) -> void:
					lethal_impacts.append({"attacker_same":attacker == tower,"target_same":hit_target == target,"nominal_damage":nominal,"actual_damage":actual,"hp_before":before,"hp_after":after}))
		await get_tree().process_frame
	var lethal_arrows_left := 0
	for projectile in get_tree().get_nodes_in_group("arrows"):
		if projectile.get("_attacker") == tower: lethal_arrows_left += 1
	var lethal_case := {"case":"lethal_hit","attacker_alive":is_instance_valid(tower),"target_dead":not COMBAT.is_alive(target),"impact_count":lethal_impacts.size(),"final_impact":lethal_impacts.back() if not lethal_impacts.is_empty() else {},"remaining_arrows":lethal_arrows_left,"nominal_tower_damage":float(tower.get("attack_damage"))}
	lethal_case["passed"] = bool(lethal_case["attacker_alive"]) and bool(lethal_case["target_dead"]) and int(lethal_case["impact_count"]) >= 1 and is_equal_approx(float(lethal_case["final_impact"].get("nominal_damage", -1.0)), float(lethal_case["nominal_tower_damage"])) and float(lethal_case["final_impact"].get("actual_damage", -1.0)) <= float(lethal_case["nominal_tower_damage"]) and int(lethal_case["remaining_arrows"]) == 0
	results.append(lethal_case)
	if is_instance_valid(tower): tower.free()
	if is_instance_valid(target): target.free()
	var all_passed := results.size() == 4
	for item in results: all_passed = all_passed and bool(item.get("passed", false))
	_finish(all_passed, "projectile_lifecycle_regression_complete", {"cases":results,"scenario":"production ArrowTower._tower_combat and ArrowProjectile._hit; test-only real Building3D/Soldier3D instances; no combat constants changed","process_error_count_checked_in_external_stderr":true})

func _spawn_projectile_fixture(game: Node, tower_pos: Vector3, target_pos: Vector3) -> Array:
	var tower: Node3D = BUILDING_SCRIPT.new()
	tower.setup(CATALOG.ARROW_TOWER, tower_pos, "player", true)
	game.get("world").add_child(tower)
	var target: Node3D = SOLDIER_SCRIPT.new()
	target.setup(target_pos, "player", true)
	game.get("world").add_child(target)
	target.set_process(false)
	target.set_physics_process(false)
	return [tower, target]

func _wait_for_projectile(attacker_id: int, max_frames: int) -> Node:
	for frame in max_frames:
		for projectile in get_tree().get_nodes_in_group("arrows"):
			var attacker: Variant = projectile.get("_attacker")
			if is_instance_valid(attacker) and int(attacker.get_instance_id()) == attacker_id:
				return projectile
		await get_tree().process_frame
	return null

func _v3(pos: Vector3) -> Array:
	return [pos.x,pos.y,pos.z]

func _finish(ok: bool, reason: String, extra: Dictionary = {}) -> void:
	if finished: return
	finished = true
	report["passed"] = ok
	report["reason"] = reason
	report["extra"] = extra
	report["events"] = events
	report["snapshots"] = snapshots
	if defense_profile != "":
		report["wave_ledger"] = _build_wave_ledger()
		report["tower_route_coverage"] = tower_min_route_distances.duplicate(true)
		report["combat_telemetry"] = {"projectile_launches":events.filter(func(e: Dictionary) -> bool: return e.get("action") == "arrow_tower_projectile_launched"),"projectile_hits":events.filter(func(e: Dictionary) -> bool: return e.get("action") == "arrow_tower_projectile_hit")}
	report["completed_utc"] = Time.get_datetime_string_from_system(true,true)
	var output := FileAccess.open("user://natural_endless_run_%s.json" % run_id, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"\t"))
		output.close()
	print("[natural-endless] ",JSON.stringify({"passed":ok,"reason":reason,"run_id":run_id,"report":"user://natural_endless_run_%s.json" % run_id}))
	get_tree().quit(0 if ok else 1)

func _run_defense_strategy(game: Node, profile: String) -> void:
	Engine.time_scale = 1.0
	var workers := _living_villagers()
	if workers.size() != 5 or _building_count(game, CATALOG.TOWN_CENTER) != 1:
		_finish(false, "defense_campaign_clean_start_mismatch", {"villagers":workers.size(),"town_centers":_building_count(game,CATALOG.TOWN_CENTER)})
		return
	for index in workers.size():
		_assign_worker(game, workers[index], "stone" if index == 0 else "wood", "defense opening: establish stone and wood incomes")
	_select(game, [_first_building(game, CATALOG.TOWN_CENTER, true)])
	var opening_wood := int(game.get("wood"))
	var opening_meat := int(game.get("meat"))
	game.call("_on_train_villager")
	events.append({"at_game_time":float(game.get("_game_time")),"action":"defense_opening_villager_queued","workers_before":workers.size(),"meat_before":opening_meat,"meat_after":int(game.get("meat")),"cost_meat":int(CATALOG.train_cost("villager").get("meat",0)),"training_seconds":float(CATALOG.train_cost("villager").get("time",0.0)),"wood_before":opening_wood})
	opening_started = true
	var core_plan := {"farm":CATALOG.get_def(CATALOG.FARM),"barracks":CATALOG.get_def(CATALOG.BARRACKS),"house":CATALOG.get_def(CATALOG.HOUSE),"tower":CATALOG.get_def(CATALOG.ARROW_TOWER),"soldier":CATALOG.train_cost("soldier"),"first_wave_at":float(game.get("_horde_next_at")),"tower_position":[6.0,0.0,0.0],"tower_center_distance_town_center":6.0,"tower_center_distance_farm":6.0}
	events.append({"at_game_time":0.0,"action":"defense_plan_cost_and_coverage_basis","plan":core_plan,"worker_opening":{"wood":4,"stone":1,"early_paid_villager":1},"farm_workers_after_completion":2,"remaining_workers_split":"wood plus one stone until tower complete"})
	var wall_start := Time.get_ticks_usec()
	var next_maintain := 0.0
	var next_snapshot := 0.0
	var initial_game_id := game.get_instance_id()
	var initial_world_id := (game.get("world") as Node).get_instance_id()
	while not finished:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			_finish(false,"defense_campaign_main_disappeared")
			return
		_connect_defense_combat_telemetry()
		_observe_defense_projectiles(game)
		var game_time := float(game.get("_game_time"))
		var wave := int(game.get("_horde_wave"))
		if int(game.get("_horde_spawn_wave_id")) == 1:
			wave1_pending_last_seen = Array(game.get("_horde_spawn_queue")).size()
		for zombie in _living_zombies():
			if int(zombie.get("horde_wave_id")) == 1:
				wave1_spawned_names[zombie.name] = true
		if wave != last_wave:
			last_wave = wave
			snapshots.append(_snapshot(game,"wave_%d_started" % wave))
			events.append({"at":"wave_boundary","action":"natural_wave_started","wave":wave,"game_time":game_time})
			if profile == "campaign" and wave >= 2 and not wave1_gate_checked:
				wave1_gate_checked = true
				var wave1_gate := _wave1_clearance_gate(game)
				report["wave1_clearance_gate"] = wave1_gate
				events.append({"at_game_time":game_time,"action":"wave1_clearance_gate","passed":bool(wave1_gate.get("passed",false)),"details":wave1_gate})
				if not bool(wave1_gate.get("passed",false)) and not recovery_window_enabled and not recovery_window_passed:
					_finish(false,"wave1_not_cleared_or_economy_not_resilient_before_wave2",wave1_gate)
					return
				if not bool(wave1_gate.get("passed",false)) and recovery_window_enabled:
					report["strict_wave1_gate_failure_preserved"] = true
					events.append({"at_game_time":game_time,"action":"strict_wave1_gate_failed_recovery_observation_continues","original_gate_passed":false,"recovery_window_seconds":25.0})
			if wave == 6 and defense_wave6_start < 0.0:
				defense_wave6_start = game_time
		if game_time >= next_snapshot:
			next_snapshot = game_time + 5.0
			snapshots.append(_snapshot(game,"defense_periodic"))
		if recovery_window_enabled and not recovery_window_started and wave >= 1 and game_time >= 210.0:
			var recovery_started := await _begin_cooperative_protection(game) if cooperative_protection_probe else await _begin_natural_recovery_window(game)
			if recovery_started:
				if finished:
					return
				recovery_window_started = true
				if not recovery_probe_only:
					recovery_window_end = game_time + 25.0
			elif game_time >= 320.0:
				_finish(false,recovery_start_failure_reason if not recovery_start_failure_reason.is_empty() else "recovery_window_no_fresh_player_visible_villager_damage_alert",{"game_time":game_time,"wave":wave})
				return
		if recovery_probe_only and recovery_window_started:
			_sample_recovery_command_probe(game)
			if finished:
				return
		if cooperative_protection_active:
			_sample_cooperative_protection(game)
			if finished:
				return
			if not cooperative_protection_active and cooperative_protection_complete:
				recovery_window_enabled = false
				recovery_window_passed = true
		if recovery_window_enabled and recovery_window_started and not recovery_probe_only and game_time >= recovery_window_end:
			var recovery_result := _finish_natural_recovery_window(game)
			report["natural_recovery_window"] = recovery_result
			if not bool(recovery_result.get("passed",false)):
				snapshots.append(_snapshot(game,"natural_recovery_window_failed"))
				_finish(false,"natural_economy_recovery_window_failed",recovery_result)
				return
			events.append({"at_game_time":game_time,"action":"natural_recovery_window_passed_campaign_continues","details":recovery_result})
			recovery_window_passed = true
			recovery_window_enabled = false
		if bool(game.get("_defeated")) or bool(game.get("_victorious")):
			snapshots.append(_snapshot(game,"terminal"))
			_finish(false,"natural_campaign_terminal_before_hold_complete",{"profile":profile,"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious")),"game_time":game_time,"wave":wave})
			return
		if profile == "preflight" and game_time >= 209.0:
			var gate := _defense_preflight_gate(game)
			report["preflight"] = gate
			_finish(bool(gate.get("passed",false)),"opening_preflight_ready_for_wave1" if bool(gate.get("passed",false)) else "opening_preflight_failed_gate",gate)
			return
		if profile == "campaign" and defense_wave6_start >= 0.0 and game_time - defense_wave6_start >= 45.0:
			snapshots.append(_snapshot(game,"wave6_active_hold_complete"))
			var viable := _campaign_still_viable(game)
			report["natural_wave6_hold_seconds"] = game_time - defense_wave6_start
			_finish(viable,"natural_endless_wave6_and_active_hold_verified" if viable else "wave6_hold_without_viable_economy_or_production",{"profile":profile,"economy_and_production_viable":viable})
			return
		if profile == "campaign" and not defense_restore_done and wave >= 2 and game_time >= 290.0 and not busy and _active_intercept_is_live() and _campaign_healthy_for_restore(game):
			busy = true
			var restore_ok := await _save_and_restore(game)
			busy = false
			defense_restore_done = true
			if not restore_ok:
				_finish(false,"healthy_wave2_f5_f9_restore_failed",{"game_time":game_time,"wave":wave})
				return
			game = get_tree().get_first_node_in_group("main_game")
			if not is_instance_valid(game):
				_finish(false,"main_game_missing_after_continue")
				return
		if profile == "campaign" and not defense_restore_done and wave >= 2 and game_time >= 330.0:
			snapshots.append(_snapshot(game,"wave2_restore_health_gate_failed"))
			_finish(false,"wave2_remained_unhealthy_for_continue",{"game_time":game_time,"town_center_and_economy_health":_campaign_health_details(game)})
			return
		if game_time >= next_maintain and not busy and not cooperative_protection_active:
			next_maintain = game_time + 2.0
			busy = true
			await _maintain_defense_economy(game)
			busy = false
		if game.get_instance_id() != initial_game_id or (game.get("world") as Node).get_instance_id() != initial_world_id:
			_finish(false,"continue_rebuilt_main_or_world_unexpectedly",{"game_time":game_time})
			return
		if float(Time.get_ticks_usec()-wall_start) > 2400.0 * 1000000.0:
			_finish(false,"defense_campaign_wall_timeout",{"game_time":game_time,"wave":wave})
			return

func _maintain_defense_economy(game: Node) -> void:
	if not is_instance_valid(game) or bool(game.get("_defeated")):
		return
	var t := float(game.get("_game_time"))
	var workers := _living_villagers()
	_reassign_unstaffed_foundations(game,workers)
	var food_reserve_due := _building_count(game,CATALOG.FARM) == 1 and _building_count_complete(game,CATALOG.FARM) > 0 and _total_live_farm_stock() <= 180
	# Keep one renewable farm and the barracks complete before spending on defenses.
	if _building_count(game,CATALOG.FARM) == 0 and int(game.get("wood")) >= 75 and _builder_candidate() != null:
		await _place_building(game,CATALOG.FARM,"first_farm",[Vector3(12,0,0),Vector3(10,0,5),Vector3(-12,0,0),Vector3(0,0,12)])
	if _building_count_complete(game,CATALOG.FARM) > 0 and _building_count(game,CATALOG.BARRACKS) == 0 and int(game.get("wood")) >= 150 and _builder_candidate() != null:
		await _place_building(game,CATALOG.BARRACKS,"first_barracks",[Vector3(-12,0,0),Vector3(12,0,8),Vector3(-12,0,-8)])
	var queued_pop := int(game.call("_queued_pop"))
	if int(game.get("pop_cap"))-int(game.get("population"))-queued_pop <= 2 and _building_count(game,CATALOG.HOUSE) == 0 and int(game.get("wood")) >= 50 and _builder_candidate() != null:
		await _place_building(game,CATALOG.HOUSE,"population_house",[Vector3(10,0,8),Vector3(-10,0,8),Vector3(10,0,14),Vector3(-10,0,14),Vector3(0,0,15)])
	# Re-seed exhausted farms with the existing paid R production handler.
	for farm in get_tree().get_nodes_in_group("farms"):
		if is_instance_valid(farm) and str(farm.get("team")) == "player" and bool(farm.get("alive")) and bool(farm.get("is_arid")) and int(game.get("wood")) >= 25:
			_select(game,[farm])
			var before := int(game.get("wood"))
			game.call("_on_reseed_farm")
			events.append({"at_game_time":t,"action":"defense_paid_farm_reseed","farm_id":farm.get_instance_id(),"wood_before":before,"wood_after":int(game.get("wood")),"stock_after":int(farm.get("meat_stock")),"normal_cost":25})
			break
	var farm_stock := _total_live_farm_stock()
	var farms := _live_farms()
	var tower_count := _building_count(game,CATALOG.ARROW_TOWER)
	var tower_complete := _building_count_complete(game,CATALOG.ARROW_TOWER)
	var army := _player_soldiers()
	# Start the paid core-route tower as soon as a small field force and completed barracks are in place.
	if tower_count == 0 and tower_complete == 0 and army.size() >= 3 and _building_count_complete(game,CATALOG.BARRACKS) > 0 and int(game.get("wood")) >= 100 and int(game.get("stone")) >= 50 and _builder_candidate() != null:
		var candidates := [Vector3(6,0,0),Vector3(5,0,2),Vector3(4,0,-3)]
		await _place_building(game,CATALOG.ARROW_TOWER,"core_route_tower",candidates)
		var placed := _first_building(game,CATALOG.ARROW_TOWER,false)
		if placed != null:
			var coverage := _measure_core_tower_coverage(placed as Node3D,game)
			events.append({"at_game_time":t,"action":"defense_tower_coverage_survey","tower_id":placed.get_instance_id(),"tower_pos":_v3(placed.global_position),"attack_range":float(placed.get("attack_range")),"coverage":coverage,"all_core_routes_inside_range":bool(coverage.get("all_routes_inside_range",false))})
	# Add a second real farm before the first one runs dry; construction and the 75-wood cost remain normal.
	if food_reserve_due and int(game.get("wood")) >= int(CATALOG.get_def(CATALOG.FARM).get("cost_wood",75)) and _builder_candidate() != null:
		await _place_building(game,CATALOG.FARM,"food_reserve_farm",[Vector3(12,0,10),Vector3(10,0,12),Vector3(-10,0,10),Vector3(0,0,12),Vector3(12,0,-10),Vector3(-12,0,10),Vector3(8,0,14),Vector3(-8,0,14)])
	# Workers remain on active food/wood/stone assignments; builders are excluded from rebalance.
	_assign_defense_roles(game,workers)
	# Queue only when the real resource check can pay now: no accumulating unpaid queue.
	var barracks := _first_building(game,CATALOG.BARRACKS,true)
	var queued_soldiers := _queue_count(game,"soldier")
	var wave := int(game.get("_horde_wave"))
	var target_army := 5 if wave == 0 else mini(15,5+wave*2)
	if barracks != null and army.size()+queued_soldiers < target_army and queued_soldiers == 0 and int(game.get("meat")) >= 60 and int(game.get("wood")) >= 20 and int(game.get("pop_cap"))-int(game.get("population"))-queued_pop > 0:
		_select(game,[barracks])
		var meat_before := int(game.get("meat")); var wood_before := int(game.get("wood"))
		game.call("_on_train_soldier")
		events.append({"at_game_time":t,"action":"defense_paid_soldier_queued","wave":wave,"army_before":army.size(),"soldier_queue_after":_queue_count(game,"soldier"),"meat_before":meat_before,"meat_after":int(game.get("meat")),"wood_before":wood_before,"wood_after":int(game.get("wood")),"cost_meat":60,"cost_wood":20,"training_seconds":15.0,"paid_immediately":not bool(barracks.get("train_paused"))})
	elif barracks != null and army.size()+queued_soldiers < target_army and queued_soldiers == 0:
		events.append({"at_game_time":t,"action":"defense_soldier_waited_for_resources_or_population","wave":wave,"army":army.size(),"queued":queued_soldiers,"meat":int(game.get("meat")),"wood":int(game.get("wood")),"pop_free":int(game.get("pop_cap"))-int(game.get("population"))-queued_pop})
	# Expand labor only after a five-unit first-wave force is present; all training uses TC production.
	workers = _living_villagers()
	if army.size() >= 5 and workers.size() < 8 and int(game.get("meat")) >= 100 and int(game.get("pop_cap"))-int(game.get("population"))-int(game.call("_queued_pop")) > 0 and _queue_count(game,"villager") == 0:
		_select(game,[_first_building(game,CATALOG.TOWN_CENTER,true)])
		var meat_before := int(game.get("meat"))
		game.call("_on_train_villager")
		events.append({"at_game_time":t,"action":"defense_paid_villager_queued","workers":workers.size(),"meat_before":meat_before,"meat_after":int(game.get("meat")),"cost_meat":50,"training_seconds":20.0})
	# Split the real army between the east farm core and west barracks/Town Center approach.
	# These are ordinary Guard commands and retain the game's normal eight-meter leash.
	_update_defense_intercepts(game,t)
	var ordered_army := _player_soldiers()
	var west_count := int(ceil(float(ordered_army.size()) / 2.0))
	for index in ordered_army.size():
		var soldier: Node = ordered_army[index]
		if _intercept_controls_soldier(soldier):
			continue
		var flank := "west" if index < west_count else "east"
		var anchor := Vector3(-15,0,0) if flank == "west" else Vector3(6,0,0)
		var current_anchor: Vector3 = soldier.get("guard_anchor")
		if not bool(soldier.get("guard_active")) or Vector2(current_anchor.x-anchor.x,current_anchor.z-anchor.z).length() > 2.0:
			soldier.call("command_guard",anchor)
			events.append({"at_game_time":t,"action":"defense_player_guard_order","soldier_id":soldier.get_instance_id(),"flank":flank,"anchor":_v3(anchor)})

func _update_defense_intercepts(game: Node, game_time: float) -> void:
	if _active_intercept_is_live():
		return
	if not active_intercept.is_empty():
		_release_defense_intercept(game,game_time,"target_removed_or_no_longer_attacking_economy")
	var alerts: Dictionary = game.get("_combat_damage_alerts")
	if alerts.is_empty():
		return
	var sorted_alerts: Array = alerts.values()
	sorted_alerts.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.get("last_hit_msec",0)) > int(b.get("last_hit_msec",0)))
	var now_msec := Time.get_ticks_msec()
	var camera: Camera3D = game.get("camera")
	var candidate: Node3D = null
	var chosen_alert: Dictionary = {}
	var chosen_distance := INF
	var visible_attackers: Array[Dictionary] = []
	for alert in sorted_alerts:
		var category := str(alert.get("category",""))
		if not ["economy_building","military_building","economy_unit"].has(category):
			continue
		if now_msec-int(alert.get("last_hit_msec",0)) > 12000:
			continue
		var alert_pos: Vector3 = alert.get("position",Vector3.ZERO)
		for zombie in _living_zombies():
			var victim: Variant = zombie.get("attack_target")
			if not is_instance_valid(victim) or not (victim.is_in_group("buildings") or victim.is_in_group("villagers")):
				continue
			if not _enemy_on_player_screen(camera,zombie):
				continue
			var dist := Vector2(zombie.global_position.x-alert_pos.x,zombie.global_position.z-alert_pos.z).length()
			visible_attackers.append({"name":zombie.name,"id":zombie.get_instance_id(),"pos":_v3(zombie.global_position),"hp":float(zombie.get("hp")),"target":victim.name,"distance_to_alert_xz":dist})
			if dist > 15.0 or dist >= chosen_distance:
				continue
			candidate = zombie
			chosen_alert = alert
			chosen_distance = dist
	if candidate == null or chosen_alert.is_empty():
		if now_msec-last_counterattack_alert_review_msec >= 3000:
			last_counterattack_alert_review_msec=now_msec
			events.append({"at_game_time":game_time,"action":"player_counterattack_alert_review","recent_damage_alerts":sorted_alerts.filter(func(a: Dictionary) -> bool: return ["economy_building","military_building","economy_unit"].has(str(a.get("category",""))) and now_msec-int(a.get("last_hit_msec",0))<=12000).map(func(a: Dictionary) -> Dictionary: return {"key":str(a.get("key","")),"category":str(a.get("category","")),"location":_v3(a.get("position",Vector3.ZERO)),"age_msec":now_msec-int(a.get("last_hit_msec",0))}),"visible_attackers":visible_attackers,"screen_projection_used":true,"result":"no visible economy attacker within 15m of the player-facing damage alert"})	
		return
	var soldiers := _player_soldiers()
	if soldiers.is_empty():
		return
	var target_pos := candidate.global_position
	soldiers.sort_custom(func(a: Node,b: Node) -> bool: return Vector2(a.global_position.x-target_pos.x,a.global_position.z-target_pos.z).length_squared() < Vector2(b.global_position.x-target_pos.x,b.global_position.z-target_pos.z).length_squared())
	var group_size := mini(soldiers.size(), maxi(1,int(ceil(float(soldiers.size())/2.0))))
	var assigned: Array[Dictionary] = []
	for index in group_size:
		var soldier: Node = soldiers[index]
		var raw_anchor: Vector3 = soldier.get("guard_anchor") if bool(soldier.get("guard_active")) else soldier.global_position
		soldier.call("command_attack_unit",candidate,false)
		assigned.append({"soldier_id":soldier.get_instance_id(),"soldier_name":soldier.name,"position":_v3(soldier.global_position),"return_anchor":_v3(raw_anchor),"return_flank":"west" if raw_anchor.x < 0.0 else "east"})
	active_intercept={"target":candidate,"target_name":candidate.name,"target_wave":int(candidate.get("horde_wave_id")),"target_pos":_v3(candidate.global_position),"alert_key":str(chosen_alert.get("key","")),"alert_category":str(chosen_alert.get("category","")),"alert_location":_v3(chosen_alert.get("position",Vector3.ZERO)),"attackers":assigned,"started_at":game_time}
	events.append({"at_game_time":game_time,"action":"player_counterattack_order","source":"active in-game damage alert plus screen-projected visible enemy currently attacking a building or villager","alert_key":active_intercept["alert_key"],"alert_category":active_intercept["alert_category"],"alert_location":active_intercept["alert_location"],"target_name":candidate.name,"target_id":candidate.get_instance_id(),"target_wave":active_intercept["target_wave"],"target_pos":active_intercept["target_pos"],"target_hp":float(candidate.get("hp")),"target_damage_intent":((candidate.get("attack_target") as Node).name) if is_instance_valid(candidate.get("attack_target")) else "","target_to_alert_xz_distance":chosen_distance,"camera_visible":true,"command":"Soldier3D.command_attack_unit(target, false)","attacker_orders":assigned,"soldiers_left_uncommitted":soldiers.size()-group_size})

func _enemy_on_player_screen(camera: Camera3D, enemy: Node3D) -> bool:
	if camera == null or not is_instance_valid(camera) or enemy == null or not is_instance_valid(enemy):
		return false
	var focus := enemy.global_position + Vector3(0.0,0.75,0.0)
	if camera.is_position_behind(focus):
		return false
	return get_viewport().get_visible_rect().has_point(camera.unproject_position(focus))

func _active_intercept_is_live() -> bool:
	if active_intercept.is_empty():
		return false
	var target: Variant = active_intercept.get("target")
	if not is_instance_valid(target) or not COMBAT.is_alive(target):
		return false
	var victim: Variant = target.get("attack_target")
	if not is_instance_valid(victim) or not (victim.is_in_group("buildings") or victim.is_in_group("villagers")):
		return false
	for attacker in Array(active_intercept.get("attackers",[])):
		var soldier: Variant = instance_from_id(int(attacker.get("soldier_id",0)))
		if is_instance_valid(soldier) and bool(soldier.get("alive")) and soldier.get("attack_target") == target:
			return true
	return false

func _intercept_controls_soldier(soldier: Node) -> bool:
	if active_intercept.is_empty() or soldier == null or not is_instance_valid(soldier):
		return false
	for attacker in Array(active_intercept.get("attackers",[])):
		if int(attacker.get("soldier_id",-1)) == int(soldier.get_instance_id()):
			return true
	return false

func _release_defense_intercept(game: Node, game_time: float, reason: String) -> void:
	if active_intercept.is_empty():
		return
	var returned: Array[Dictionary] = []
	var worker_resume: Array[Dictionary] = []
	for attacker in Array(active_intercept.get("attackers",[])):
		var soldier: Variant = instance_from_id(int(attacker.get("soldier_id",0)))
		if not is_instance_valid(soldier) or not bool(soldier.get("alive")):
			continue
		var anchor_data: Array = attacker.get("return_anchor",[])
		var anchor: Vector3 = Vector3(anchor_data[0],anchor_data[1],anchor_data[2]) if anchor_data.size()==3 else soldier.global_position
		if guard_return_experiment:
			returned.append({"soldier_id":soldier.get_instance_id(),"soldier_name":soldier.name,"anchor":_v3(anchor),"diagnostic_guard_reissue":false,"product_return_intent_active":bool(soldier.get("_attack_return_guard_active")),"product_guard_active":bool(soldier.get("guard_active"))})
		else:
			soldier.call("command_guard",anchor)
			returned.append({"soldier_id":soldier.get_instance_id(),"soldier_name":soldier.name,"anchor":_v3(anchor),"diagnostic_guard_reissue":true})
	for worker in _living_villagers():
		var target: Variant = worker.get("gather_target")
		var role := str(worker_roles.get(str(worker.get_instance_id()),""))
		var target_productive := false
		if is_instance_valid(target):
			target_productive = int(target.get("meat_stock")) > 0 if target.is_in_group("farms") else target.has_method("res_key") and int(target.get("amount")) > 0
		if target_productive:
			if role.is_empty(): role = "food" if target.is_in_group("farms") else str(target.call("res_key"))
			if int(worker.get("state")) != 2 and int(worker.get("state")) != 3:
				_assign_worker(game,worker,role,"player counterattack threat removed; resume gathering")
				worker_resume.append({"worker_id":worker.get_instance_id(),"worker_name":worker.name,"role":role,"target":target.name})
	events.append({"at_game_time":game_time,"action":"player_counterattack_recovery_order","target_name":str(active_intercept.get("target_name","")),"target_wave":int(active_intercept.get("target_wave",-1)),"reason":reason,"guard_orders_restored":returned,"gather_orders_resumed":worker_resume,"guard_return_experiment":guard_return_experiment,"controller_guard_reissues_suppressed":guard_return_experiment})
	active_intercept.clear()

func _rebind_active_intercept_after_restore() -> bool:
	if active_intercept.is_empty():
		return true
	var target_wave := int(active_intercept.get("target_wave",-1))
	var pos_data: Array = active_intercept.get("target_pos",[])
	if pos_data.size()!=3:
		return false
	var expected_pos := Vector3(pos_data[0],pos_data[1],pos_data[2])
	var rebound_target: Node3D = null
	var nearest := INF
	for zombie in _living_zombies():
		if int(zombie.get("horde_wave_id")) != target_wave:
			continue
		var distance: float = zombie.global_position.distance_to(expected_pos)
		if distance < nearest:
			nearest=distance
			rebound_target=zombie
	if rebound_target == null or nearest > 0.05:
		return false
	var rebound_attackers: Array[Dictionary] = []
	for soldier in _player_soldiers():
		if soldier.get("attack_target") != rebound_target:
			continue
		var best_record: Dictionary = {}
		var best_distance := INF
		for old_attacker in Array(active_intercept.get("attackers",[])):
			var anchor_data: Array = old_attacker.get("return_anchor",[])
			if anchor_data.size()!=3: continue
			var anchor: Vector3 = Vector3(anchor_data[0],anchor_data[1],anchor_data[2])
			var distance: float = soldier.global_position.distance_to(anchor)
			if distance < best_distance:
				best_distance=distance
				best_record=old_attacker
		if best_record.is_empty(): return false
		var record: Dictionary = best_record.duplicate(true)
		record["soldier_id"]=soldier.get_instance_id()
		record["soldier_name"]=soldier.name
		record["position"]=_v3(soldier.global_position)
		rebound_attackers.append(record)
	if rebound_attackers.is_empty():
		return false
	active_intercept["target"]=rebound_target
	active_intercept["attackers"]=rebound_attackers
	return true

func _assign_defense_roles(game: Node, workers: Array) -> void:
	var live_farms := _live_farms()
	var army := _player_soldiers().size()
	var food_target := 3 if _total_live_farm_stock() < 150 else 2 if int(game.get("meat")) < 240 or army < 8 else 1
	var tower_pending := _building_count(game,CATALOG.ARROW_TOWER) == 0
	var stone_target := 1 if tower_pending else 0
	var wood_target := maxi(1,workers.size()-food_target-stone_target-_active_builders(workers))
	var desired := {"food":food_target,"stone":stone_target,"wood":wood_target}
	var counts := {"food":0,"stone":0,"wood":0}
	for worker in workers:
		if bool(worker.get("manual_order_suppresses_auto_defense")) or not Array(worker.get("order_queue")).is_empty():
			continue
		if _reserved_building_site(worker) != null or int(worker.get("state")) == 4: continue
		var role := str(worker_roles.get(str(worker.get_instance_id()),""))
		if role.is_empty(): role = _least_filled_role(counts,desired)
		var target: Variant = worker.get("gather_target")
		var valid: bool = is_instance_valid(target) and target.is_inside_tree() and (int(target.get("meat_stock"))>0 if target.is_in_group("farms") else int(target.get("amount"))>0)
		var target_role := "food" if valid and target.is_in_group("farms") else str(target.call("res_key")) if valid and target.has_method("res_key") else ""
		if counts.has(role): counts[role] = int(counts[role])+1
		if int(counts.get(role,0)) > int(desired.get(role,0)):
			counts[role] = int(counts[role])-1
			role = _least_filled_role(counts,desired)
			counts[role] = int(counts.get(role,0))+1
		worker_roles[str(worker.get_instance_id())] = role
		if not valid or target_role != role:
			_assign_worker(game,worker,role,"defense economy role rebalance")

func _active_builders(workers: Array) -> int:
	var count := 0
	for worker in workers:
		if _reserved_building_site(worker) != null: count += 1
	return count

func _total_live_farm_stock() -> int:
	var count := 0
	for farm in _live_farms(): count += int(farm.get("meat_stock"))
	return count

func _defense_preflight_gate(game: Node) -> Dictionary:
	var farms := _live_farms()
	var barracks := _building_count_complete(game,CATALOG.BARRACKS)>0
	var tower := _first_building(game,CATALOG.ARROW_TOWER,true)
	var army := _player_soldiers().size()
	var active_food_workers := 0
	for worker in _living_villagers():
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock"))>0: active_food_workers += 1
	var no_unpaid_soldiers := _queue_count(game,"soldier") == 0 or not bool((_first_building(game,CATALOG.BARRACKS,true)).get("train_paused"))
	var coverage := _measure_core_tower_coverage(tower as Node3D,game) if tower != null else {"all_routes_inside_range":false}
	var farm_has_live_stock := _total_live_farm_stock() > 0
	var farm_reseed_affordable := int(game.get("wood")) >= 25
	return {"profile":"preflight","game_time":float(game.get("_game_time")),"before_first_wave":float(game.get("_horde_next_at")),"passed":float(game.get("_game_time"))<float(game.get("_horde_next_at")) and farms.size()>0 and farm_has_live_stock and active_food_workers>=1 and farm_reseed_affordable and barracks and army>=5 and tower!=null and no_unpaid_soldiers and bool(coverage.get("all_routes_inside_range",false)),"farm_complete":not farms.is_empty(),"farm_has_live_stock":farm_has_live_stock,"farm_stock":_total_live_farm_stock(),"food_workers_with_live_target":active_food_workers,"farm_reseed_affordable":farm_reseed_affordable,"barracks_complete":barracks,"soldiers_alive":army,"tower_complete":tower!=null,"tower_position":_v3(tower.global_position) if tower!=null else [],"tower_coverage":coverage,"unpaid_or_paused_soldier_queue_absent":no_unpaid_soldiers,"resources":{"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone"))},"worker_and_unit_counts":_unit_counts()}

func _campaign_healthy_for_restore(game: Node) -> bool:
	var tc := _first_building(game,CATALOG.TOWN_CENTER,true)
	return tc != null and float(tc.get("hp")) > 2500.0 and _living_villagers().size() >= 2 and _player_soldiers().size() >= 1 and _building_count_complete(game,CATALOG.FARM)>0

func _campaign_health_details(game: Node) -> Dictionary:
	var tc := _first_building(game,CATALOG.TOWN_CENTER,true)
	return {"town_center_hp":float(tc.get("hp")) if tc!=null else 0.0,"villagers_alive":_living_villagers().size(),"soldiers_alive":_player_soldiers().size(),"farms_complete":_building_count_complete(game,CATALOG.FARM),"restore_gate_passed":_campaign_healthy_for_restore(game)}

func _measure_core_tower_coverage(tower: Node3D, game: Node) -> Dictionary:
	if tower == null or not is_instance_valid(tower): return {"all_routes_inside_range":false}
	var range := float(tower.get("attack_range"))
	var tower_pos: Vector3 = tower.global_position
	var rim := 55.0 - 3.5
	var spawn_targets := {"north":Vector3(0,0,-rim),"east":Vector3(rim,0,0),"south":Vector3(0,0,rim),"west":Vector3(-rim,0,0)}
	var core_targets := {"town_center":Vector3.ZERO,"farm":Vector3(12,0,0)}
	var routes := {}
	var all_inside := true
	for edge in spawn_targets:
		for core in core_targets:
			var dist := _segment_dist_xz(spawn_targets[edge],core_targets[core],tower_pos)
			routes["%s_to_%s" % [edge,core]] = {"spawn":_v3(spawn_targets[edge]),"target":_v3(core_targets[core]),"minimum_xz_distance_to_tower_centerline":dist,"inside_strict_range":dist<range}
			if dist >= range: all_inside=false
	var farm := _first_building(game,CATALOG.FARM,true)
	var food_worker_distance := -1.0
	if farm != null:
		var worker: Node3D = null
		for candidate in _living_villagers():
			if candidate.get("gather_target") == farm: worker=candidate; break
		if worker != null: food_worker_distance = Vector2(worker.global_position.x-tower_pos.x,worker.global_position.z-tower_pos.z).length()
	return {"attack_range":range,"routes":routes,"all_routes_inside_range":all_inside,"farm_center_distance":Vector2(farm.global_position.x-tower_pos.x,farm.global_position.z-tower_pos.z).length() if farm!=null else -1.0,"active_food_worker_distance":food_worker_distance,"strict_range_rule":"center XZ distance < attack_range"}

func _segment_dist_xz(a: Vector3,b: Vector3,p: Vector3) -> float:
	var ab := Vector2(b.x-a.x,b.z-a.z)
	var ap := Vector2(p.x-a.x,p.z-a.z)
	var t := clampf(ap.dot(ab)/maxf(ab.length_squared(),0.0001),0.0,1.0)
	return Vector2(a.x,a.z).lerp(Vector2(b.x,b.z),t).distance_to(Vector2(p.x,p.z))

func _observe_defense_projectiles(game: Node) -> void:
	for arrow in get_tree().get_nodes_in_group("arrows"):
		if not is_instance_valid(arrow): continue
		var arrow_id := str(arrow.get_instance_id())
		if arrow_seen.has(arrow_id): continue
		arrow_seen[arrow_id] = true
		var attacker: Variant = arrow.get("_attacker")
		var target: Variant = arrow.get("_target")
		if not is_instance_valid(attacker) or attacker.get("is_tower") != true: continue
		var dist := Vector2(attacker.global_position.x-target.global_position.x,attacker.global_position.z-target.global_position.z).length() if is_instance_valid(target) else -1.0
		var rec := {"arrow_id":arrow_id,"tower_id":attacker.get_instance_id(),"target_id":target.get_instance_id() if is_instance_valid(target) else 0,"target_ref":target,"target_hp_before":float(target.get("hp")) if is_instance_valid(target) else -1.0,"damage":float(arrow.get("_dmg")),"launch_distance_xz":dist,"launch_pos":_v3(arrow.global_position),"target_pos":_v3(target.global_position) if is_instance_valid(target) else [],"wave":int(target.get("horde_wave_id")) if is_instance_valid(target) and target.get("horde_wave_id")!=null else 0,"observed_at_game_time":float(game.get("_game_time"))}
		projectile_records[arrow_id]=rec
		events.append({"action":"arrow_tower_projectile_launched","arrow_id":arrow_id,"tower_id":rec["tower_id"],"target_id":rec["target_id"],"wave":rec["wave"],"attack_range":float(attacker.get("attack_range")),"launch_distance_xz":dist,"inside_strict_range":dist>=0.0 and dist<float(attacker.get("attack_range")),"damage":rec["damage"],"game_time":rec["observed_at_game_time"],"target_pos":rec["target_pos"]})
		var callback := Callable(self,"_on_defense_arrow_hit")
		if arrow.has_signal("diagnostic_impact") and not arrow.is_connected("diagnostic_impact",callback): arrow.connect("diagnostic_impact",callback)

func _connect_defense_combat_telemetry() -> void:
	var callback := Callable(self,"_on_player_soldier_attack_hit")
	for soldier in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(soldier) or not soldier.has_signal("diagnostic_attack_hit"):
			continue
		if not soldier.is_connected("diagnostic_attack_hit",callback):
			soldier.connect("diagnostic_attack_hit",callback)

func _on_player_soldier_attack_hit(attacker: Node3D,target: Node3D,damage: float,actual_damage: float,hp_before: float,hp_after: float) -> void:
	if attacker == null or not is_instance_valid(attacker) or str(attacker.get("team")) != "player":
		return
	var in_intercept: bool = _intercept_controls_soldier(attacker) and is_instance_valid(target) and active_intercept.get("target") == target
	events.append({"at_game_time":float(get_tree().get_first_node_in_group("main_game").get("_game_time")),"action":"player_soldier_melee_hit","counterattack":in_intercept,"attacker_id":attacker.get_instance_id(),"attacker_pos":_v3(attacker.global_position),"target_id":target.get_instance_id() if is_instance_valid(target) else 0,"target_name":target.name if is_instance_valid(target) else "freed_after_hit","target_wave":int(target.get("horde_wave_id")) if is_instance_valid(target) and target.get("horde_wave_id") != null else -1,"target_pos":_v3(target.global_position) if is_instance_valid(target) else [],"nominal_damage":damage,"actual_hp_delta":actual_damage,"target_hp_before":hp_before,"target_hp_after":hp_after,"target_killed":not COMBAT.is_alive(target) if is_instance_valid(target) else hp_after <= 0.0})

func _on_defense_arrow_hit(attacker: Node3D,target: Node3D,damage: float,actual_damage: float,hp_before: float,hp_after: float) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.get("is_tower") != true: return
	events.append({"action":"arrow_tower_projectile_hit","tower_id":attacker.get_instance_id(),"target_id":target.get_instance_id() if is_instance_valid(target) else 0,"wave":int(target.get("horde_wave_id")) if is_instance_valid(target) and target.get("horde_wave_id")!=null else 0,"base_damage":damage,"actual_hp_delta":actual_damage,"target_hp_before":hp_before,"target_hp_after":hp_after,"game_time":float(get_tree().get_first_node_in_group("main_game").get("_game_time"))})

func _campaign_still_viable(game: Node) -> bool:
	var tc := _first_building(game,CATALOG.TOWN_CENTER,true)
	var barracks := _first_building(game,CATALOG.BARRACKS,true)
	var productive_farm := false
	for farm in _live_farms():
		if int(farm.get("meat_stock")) > 0: productive_farm=true; break
	var workers := _living_villagers()
	var active_food := false
	for worker in workers:
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock")) > 0: active_food=true
	var active_wood := false
	for worker in workers:
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key"))=="wood" and int(target.get("amount"))>0: active_wood=true
	var paid_train_queue := false
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team"))=="player" and Array(building.get("train_queue")).has("soldier") and bool(building.get("train_paid")):
			paid_train_queue=true
	var can_continue := _player_soldiers().size()>0 or paid_train_queue
	var can_afford_next := int(game.get("meat"))>=60 and int(game.get("wood"))>=20 and int(game.get("pop_cap"))-int(game.get("population"))-int(game.call("_queued_pop"))>0
	return tc!=null and float(tc.get("hp"))>0.0 and barracks!=null and workers.size()>=2 and active_food and active_wood and productive_farm and can_continue and (can_afford_next or paid_train_queue)

func _wave1_clearance_gate(game: Node) -> Dictionary:
	var wave1_zombies := _living_zombies().filter(func(z: Node) -> bool: return int(z.get("horde_wave_id")) == 1)
	var expected_spawns := int(game.call("_horde_count_for_wave",1))
	var spawned_count := wave1_spawned_names.size()
	var tc := _first_building(game,CATALOG.TOWN_CENTER,true)
	var barracks := _first_building(game,CATALOG.BARRACKS,true)
	var food_workers := 0
	var wood_workers := 0
	for worker in _living_villagers():
		var target: Variant = worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock")) > 0:
			food_workers += 1
		elif is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key")) == "wood" and int(target.get("amount")) > 0:
			wood_workers += 1
	var productive_farm := _live_farms().size() > 0
	var paid_soldier_queue := false
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and Array(building.get("train_queue")).has("soldier") and bool(building.get("train_paid")) and not bool(building.get("train_paused")):
			paid_soldier_queue = true
	var soldiers_alive := _player_soldiers().size()
	var army_viable := soldiers_alive > 0 or paid_soldier_queue
	var next_soldier_affordable := int(game.get("meat")) >= 60 and int(game.get("wood")) >= 20 and int(game.get("pop_cap"))-int(game.get("population"))-int(game.call("_queued_pop")) > 0
	var details := {"profile":"campaign","game_time":float(game.get("_game_time")),"wave1_expected_spawns":expected_spawns,"wave1_observed_spawn_count":spawned_count,"wave1_pending_spawn_count_last_observed":wave1_pending_last_seen,"wave1_alive":wave1_zombies.size(),"town_center_alive":tc != null,"town_center_hp":float(tc.get("hp")) if tc != null else 0.0,"barracks_alive":barracks != null,"villagers_alive":_living_villagers().size(),"food_workers_with_live_farm_target":food_workers,"wood_workers_with_live_resource_target":wood_workers,"productive_farm_count":_live_farms().size(),"soldiers_alive":soldiers_alive,"paid_soldier_queue":paid_soldier_queue,"next_soldier_affordable":next_soldier_affordable,"resources":{"meat":int(game.get("meat")),"wood":int(game.get("wood")),"stone":int(game.get("stone"))}}
	var wave1_clear := spawned_count >= expected_spawns and wave1_pending_last_seen == 0 and wave1_zombies.is_empty()
	var economy_recoverable := tc != null and float(tc.get("hp")) > 0.0 and barracks != null and _living_villagers().size() >= 2 and food_workers >= 1 and wood_workers >= 1 and productive_farm and army_viable and (next_soldier_affordable or paid_soldier_queue)
	details["wave1_clear"] = wave1_clear
	details["economy_recoverable"] = economy_recoverable
	details["passed"] = wave1_clear and economy_recoverable
	return details

func _run_general_selection_regression(game: Node) -> void:
	var villagers := _living_villagers()
	var tc := _first_building(game,CATALOG.TOWN_CENTER,true)
	var resources := get_tree().get_nodes_in_group("resources")
	if villagers.is_empty() or tc==null or resources.is_empty():
		_finish(false,"selection_regression_clean_start_missing_targets",{"villagers":villagers.size(),"town_center":tc!=null,"resources":resources.size()})
		return
	var worker: Node = villagers[0]
	var world: Node = game.get("world")
	var soldier := preload("res://scripts/soldier.gd").new()
	soldier.setup(Vector3(20,0,20),"player",false)
	world.add_child(soldier)
	var house := preload("res://scripts/building.gd").new()
	house.setup(CATALOG.HOUSE,Vector3(24,0,20),"player",true)
	world.add_child(house)
	var barracks := preload("res://scripts/building.gd").new()
	barracks.setup(CATALOG.BARRACKS,Vector3(28,0,20),"player",true)
	barracks.train_finished.connect(game._on_train_finished)
	world.add_child(barracks)
	var tower := preload("res://scripts/building.gd").new()
	tower.setup(CATALOG.ARROW_TOWER,Vector3(6,0,0),"player",true)
	world.add_child(tower)
	await get_tree().process_frame
	var cases: Array[Dictionary] = []
	var selection_targets: Array[Dictionary] = [
		{"label":"villager","nodes":[worker],"expected_buttons":["build","gather","move"]},
		{"label":"soldier","nodes":[soldier],"expected_buttons":["guard","attack","move"]},
		{"label":"resource","nodes":[resources[0]],"expected_buttons":[]},
		{"label":"ordinary_building","nodes":[house],"expected_buttons":[]},
		{"label":"town_center_production","nodes":[tc],"expected_buttons":["train"]},
		{"label":"barracks_production","nodes":[barracks],"expected_buttons":["soldier"]},
		{"label":"arrow_tower","nodes":[tower],"expected_buttons":[]},
		{"label":"multi_selection","nodes":[worker,soldier,tower],"expected_buttons":["build","gather","move"]},
		{"label":"clear_selection","nodes":[],"expected_buttons":[]},
	]
	var all_ok := true
	for sample in selection_targets:
		_select(game,Array(sample["nodes"]))
		var buttons: Dictionary = game.get("hud").get("_cmd_btns")
		var actual: Array = buttons.keys()
		var required: Array = sample["expected_buttons"]
		var buttons_ok := true
		for required_id in required:
			if not actual.has(required_id): buttons_ok=false
		var tower_details := ""
		if sample["label"]=="arrow_tower":
			tower_details = str(game.get("hud").get("_info_armor").text)
			if tower_details.find("6.5m")<0: buttons_ok=false
		cases.append({"case":sample["label"],"selected_ids":Array(sample["nodes"]).map(func(n): return int(n.get_instance_id())),"selected_count":Array(sample["nodes"]).size(),"command_card_button_ids":actual,"required_buttons":required,"buttons_reachable":buttons_ok,"tower_detail_line":tower_details})
		all_ok = all_ok and buttons_ok and Array(game.get("selected")).size()==Array(sample["nodes"]).size()
	var build_open_ok := false
	_select(game,[worker])
	var build_buttons: Dictionary = game.get("hud").get("_cmd_btns")
	if build_buttons.has("build"):
		(build_buttons["build"] as Button).pressed.emit()
		var build_grid: GridContainer = game.get("hud").get("_build_grid")
		var build_labels: Array[String] = []
		for child in build_grid.get_children():
			if child is Button: build_labels.append(str((child as Button).text))
		var tower_tile_reachable := false
		for child in build_grid.get_children():
			if child is Button and str((child as Button).text).contains("箭塔") and str((child as Button).tooltip_text).contains("6.5"):
				tower_tile_reachable=true
		build_open_ok = bool(game.get("hud").get("_build_open")) and tower_tile_reachable and str(build_buttons["build"].text).contains("[B]")
		(game.get("hud") as Node).call("_on_build_back")
	var report_case := {"action":"general_selection_command_card_regression","cases":cases,"build_menu_opened_from_selected_villager":build_open_ok,"production_hotkeys_present_without_spending":true,"ordinary_mouse_verified":false,"fixture":{"injected_standard_player_soldier":soldier.get_instance_id(),"injected_complete_house":house.get_instance_id(),"injected_complete_barracks":barracks.get_instance_id(),"injected_complete_tower":tower.get_instance_id(),"resource_is_seed42_map_resource":true},"passed":all_ok and build_open_ok}
	report["diagnostic_fixture_entities_injected"] = true
	events.append(report_case)
	game.call("_clear_selection")
	soldier.queue_free(); house.queue_free(); barracks.queue_free(); tower.queue_free()
	await get_tree().process_frame
	_finish(bool(report_case["passed"]),"general_selection_and_production_cards_passed" if bool(report_case["passed"]) else "general_selection_or_command_card_failed",report_case)

func _build_wave_ledger() -> Array:
	var ledger := {}
	for snap in snapshots:
		var expected := int(snap.get("wave_expected",0))
		var wave := int(snap.get("wave",0))
		for id in range(1,maxi(wave,1)+1):
			var row: Dictionary = ledger.get(str(id),{"wave":id,"expected":mini(24,6+4*(id-1)),"first_observed_game_time":-1.0,"last_observed_game_time":-1.0,"alive_series":[]})
			var alive := 0
			for zombie in Array(snap.get("zombies",[])):
				if int(zombie.get("wave",0))==id: alive+=1
			var pending := int(snap.get("wave_pending",0)) if int(snap.get("wave",0))==id else 0
			if (alive>0 or pending>0 or id==wave) and float(row["first_observed_game_time"])<0.0: row["first_observed_game_time"]=float(snap.get("game_time",0.0))
			if alive>0 or pending>0 or id==wave:
				row["last_observed_game_time"]=float(snap.get("game_time",0.0))
				row["generated"]=int(row["expected"])-pending
				row["alive"]=alive
				row["pending_spawn"]=pending
				row["kills_estimate"]=int(row["generated"])-alive
				row["alive_series"].append({"game_time":float(snap.get("game_time",0.0)),"alive":alive,"pending":pending,"kills_estimate":int(row["generated"])-alive})
			ledger[str(id)]=row
	var rows: Array = []
	for value in ledger.values(): rows.append(value)
	return rows
