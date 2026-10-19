extends Node
## Controlled production behavior fixture. Resources are explicitly injected;
## every building, queue payment, training completion, and villager spawn uses Main/Building production paths.

const CATALOG := preload("res://scripts/building_catalog.gd")
const REPORT_PATH := "user://barracks_recovery_behavior_probe.json"
var _run_id := "R28_barracks_recovery_behavior_probe"
var _report: Dictionary = {}
var _events: Array[Dictionary] = []
var _last_placed_building: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--run-id="):
			_run_id = str(arg).get_slice("=", 1)
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	Engine.max_fps = 60
	_report = {"schema":"barracks_recovery_behavior_probe_v1","run_id":_run_id,"fixture_injected":true,"fixture_scope":"resource balances and removal of the five initial villagers only; no injected villagers, soldiers, buildings, free costs, or changed game stats","headless":DisplayServer.get_name()=="headless","time_scale":Engine.time_scale,"events":_events}
	if not bool(_report.headless):
		_finish(false,"headless_required")
		return
	var menu: Node = await _wait_game(func(g: Node) -> bool: return g.get("_start_begin_button") != null, 600)
	if menu == null:
		_finish(false,"production_start_menu_unavailable")
		return
	var mode: OptionButton = menu.get("_start_mode_select") as OptionButton
	var seed: LineEdit = menu.get("_seed_edit") as LineEdit
	var start: Button = menu.get("_start_begin_button") as Button
	if mode == null or seed == null or start == null:
		_finish(false,"production_start_controls_missing")
		return
	mode.select(0)
	mode.item_selected.emit(0)
	seed.text = "42"
	start.pressed.emit()
	var game: Node = await _wait_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and g.get("world") != null, 1800)
	if game == null or int(game.get("map_seed")) != 42 or int(game.get("_horde_mode")) != 0:
		_finish(false,"normal_seed42_match_start_failed")
		return
	game = await _wait_game(func(g: Node) -> bool: return bool(g.get("_match_started")) and bool(g.get("_player_orders_ready")), 1800)
	if game == null:
		_finish(false,"production_player_orders_never_became_ready")
		return
	_events.append({"action":"waited_for_production_player_orders_ready","game_time":float(game.get("_game_time")),"player_orders_ready":bool(game.get("_player_orders_ready"))})
	var initial_workers := _living_workers()
	if initial_workers.size() != 5:
		_finish(false,"initial_real_worker_count_mismatch",{"workers":initial_workers.size()})
		return
	var injection := {"at_game_time":float(game.get("_game_time")),"wood_before":int(game.get("wood")),"food_before":int(game.get("meat")),"wood_set_to":245,"food_set_to":120,"reason":"fixture budget for 150 barracks + 20 first soldier + 75 farm; 60 food first soldier then food income can resume"}
	game.set("wood",245)
	game.set("meat",120)
	game.call("_update_hud")
	_events.append({"action":"explicit_resource_fixture_injected","fixture":injection,"workers_injected":0,"soldiers_injected":0,"buildings_injected":0})
	var barracks_result: Dictionary = await _place_paid_building(game,CATALOG.BARRACKS,[Vector3(-12,0,0),Vector3(-14,0,8),Vector3(14,0,4),Vector3(14,0,-6)])
	if not bool(barracks_result.get("complete",false)):
		_finish(false,"production_paid_barracks_construction_failed",{"barracks":barracks_result})
		return
	var barracks: Node3D = _last_placed_building
	if not is_instance_valid(barracks):
		_finish(false,"production_barracks_reference_not_retained")
		return
	var queue_wood_before := int(game.get("wood"))
	var queue_food_before := int(game.get("meat"))
	game.call("_clear_selection")
	game.call("_add_to_selection",barracks)
	var queue_before: int = Array(barracks.get("train_queue")).size()
	game.call("_on_train_soldier")
	var queue_after: int = Array(barracks.get("train_queue")).size()
	var soldier_accepted := queue_after == queue_before + 1
	var soldier_paid_at_start := bool(barracks.get("train_paid")) and int(game.get("wood")) == queue_wood_before - 20 and int(game.get("meat")) == queue_food_before - 60
	_events.append({"action":"normal_soldier_queue_and_pay_on_start","game_time":float(game.get("_game_time")),"accepted":soldier_accepted,"train_paid":bool(barracks.get("train_paid")),"queue_before":queue_before,"queue_after":queue_after,"wood_before":queue_wood_before,"wood_after":int(game.get("wood")),"food_before":queue_food_before,"food_after":int(game.get("meat")),"expected_cost":{"wood":20,"food":60},"path":"Main._on_train_soldier -> Main._queue_train -> Building.enqueue_train -> Building._try_start_front -> Main.try_pay_train"})
	if not soldier_accepted or not soldier_paid_at_start:
		_finish(false,"ordinary_soldier_queue_or_payment_failed")
		return
	var soldiers_before := _player_soldiers().size()
	var soldier_spawned := await _wait_until(func() -> bool: return _player_soldiers().size() > soldiers_before, 900)
	var soldier_count_after := _player_soldiers().size()
	_events.append({"action":"normal_soldier_spawn_observed","game_time":float(game.get("_game_time")),"spawned":soldier_spawned,"soldiers_before":soldiers_before,"soldiers_after":soldier_count_after,"remaining_wood":int(game.get("wood")),"remaining_food":int(game.get("meat"))})
	if not soldier_spawned:
		_finish(false,"ordinary_soldier_did_not_spawn")
		return
	var farm_wood_before := int(game.get("wood"))
	var farm_food_before := int(game.get("meat"))
	var farm_result: Dictionary = await _place_paid_building(game,CATALOG.FARM,[Vector3(10,0,-12),Vector3(14,0,6),Vector3(-12,0,12),Vector3(12,0,0)])
	if not bool(farm_result.get("complete",false)) or farm_wood_before - int(game.get("wood")) != 75:
		_finish(false,"ordinary_75_wood_food_farm_recovery_failed",{"farm":farm_result,"wood_before":farm_wood_before,"wood_after":int(game.get("wood"))})
		return
	var farm: Node3D = _last_placed_building
	if not is_instance_valid(farm):
		_finish(false,"production_farm_reference_not_retained")
		return
	var food_worker: Node3D = _living_workers()[0]
	var food_before_deposit := int(game.get("meat"))
	var food_worker_id := str(food_worker.get_instance_id())
	food_worker.call("command_gather",farm)
	var food_deposited := await _wait_until(func() -> bool: return int(game.get("meat")) > food_before_deposit, 1200)
	_events.append({"action":"farm_food_production_resumed","game_time":float(game.get("_game_time")),"farm_id":str(farm.get_instance_id()),"farm_complete":bool(farm.get("is_complete")),"wood_before_payment":farm_wood_before,"wood_after_payment":int(game.get("wood")),"food_before_first_deposit":food_before_deposit,"food_after":int(game.get("meat")),"worker_id":food_worker_id,"food_deposited":food_deposited})
	if not food_deposited:
		_finish(false,"restored_farm_did_not_deposit_food")
		return
	var workers_removed := _living_workers().size()
	for worker in _living_workers(): worker.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	game.call("_refresh_pop")
	var tc: Node3D = game.call("_find_tc") as Node3D
	if _living_workers().size() != 0 or tc == null:
		_finish(false,"zero_worker_fixture_or_town_center_unavailable",{"workers":_living_workers().size(),"tc_valid":is_instance_valid(tc)})
		return
	var villager_food_before := int(game.get("meat"))
	var villager_wood_before := int(game.get("wood"))
	var villager_queue_before: int = Array(tc.get("train_queue")).size()
	game.call("_clear_selection")
	game.call("_on_train_villager")
	var villager_queue_after: int = Array(tc.get("train_queue")).size()
	var villager_paid := bool(tc.get("train_paid")) and villager_food_before-int(game.get("meat")) == 50
	var villager_order_accepted := villager_queue_after == villager_queue_before+1
	_events.append({"action":"zero_worker_tc_recruit_paid","game_time":float(game.get("_game_time")),"initial_workers_removed_as_fixture":workers_removed,"town_center_id":str(tc.get_instance_id()),"accepted":villager_order_accepted,"train_paid":bool(tc.get("train_paid")),"queue_before":villager_queue_before,"queue_after":villager_queue_after,"food_before":villager_food_before,"food_after":int(game.get("meat")),"wood_before":villager_wood_before,"wood_after":int(game.get("wood")),"expected_food_cost":50,"path":"Main._on_train_villager -> Main._queue_train -> Town Center normal queue/payment"})
	if not villager_order_accepted or not villager_paid:
		_finish(false,"zero_worker_tc_recruit_not_accepted_and_paid")
		return
	var workers_before_spawn := _living_workers().size()
	# TC villager training is longer than the short soldier timer. Keep polling
	# through the production train completion and the deferred spawn callback.
	var villager_spawned := await _wait_until(func() -> bool: return _living_workers().size() > workers_before_spawn, 3000)
	if not villager_spawned:
		_finish(false,"ordinary_tc_villager_did_not_spawn")
		return
	var new_worker: Node3D = _living_workers()[0]
	var construction_wood_injection := {"at_game_time":float(game.get("_game_time")),"wood_before":int(game.get("wood")),"wood_set_to":50,"reason":"fixture-only budget for a post-recruitment paid house build; no worker is created by this injection"}
	game.set("wood",50)
	game.call("_update_hud")
	_events.append({"action":"explicit_post_recruitment_build_budget_injected","fixture":construction_wood_injection,"worker_id":str(new_worker.get_instance_id()),"workers_injected":0})
	var house_result: Dictionary = await _place_paid_building(game,CATALOG.HOUSE,[Vector3(0,0,16),Vector3(10,0,10),Vector3(-10,0,12),Vector3(8,0,16)])
	if not bool(house_result.get("complete",false)) or int(game.get("wood")) != 0:
		_finish(false,"tc_recruited_villager_could_not_build_after_spawn",{"house":house_result,"remaining_wood":int(game.get("wood"))})
		return
	var success := {"fixture_resource_injections":[injection,construction_wood_injection],"production_barracks":barracks_result,"production_soldier_payment_and_spawn":_events.filter(func(e: Dictionary) -> bool: return str(e.get("action","")).begins_with("normal_soldier")),"paid_farm_and_food_deposit":_events.filter(func(e: Dictionary) -> bool: return str(e.get("action","")).begins_with("farm_food")),"zero_worker_tc_recruit":_events.filter(func(e: Dictionary) -> bool: return str(e.get("action","")).begins_with("zero_worker")),"recruited_builder_house":house_result,"injected_villagers":0,"injected_soldiers":0,"injected_buildings":0,"remaining_wood_after_house_payment":int(game.get("wood")),"remaining_food":int(game.get("meat")),"seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"game_time":float(game.get("_game_time"))}
	_report["evidence"] = success
	_finish(true,"paid_barracks_soldier_farm_food_and_tc_builder_recovery_verified",success)

func _place_paid_building(game: Node, kind: int, candidates: Array[Vector3]) -> Dictionary:
	_last_placed_building = null
	var workers := _living_workers()
	if workers.is_empty(): return {"complete":false,"failure":"no_living_builder"}
	var builder: Node3D = workers[0]
	var before_wood := int(game.get("wood"))
	var before_food := int(game.get("meat"))
	var existing: Dictionary = {}
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building): existing[str(building.get_instance_id())]=true
	game.call("_clear_selection")
	game.call("_add_to_selection",builder)
	game.call("_refresh_selection_hud")
	var selected_before_build: Array = game.get("selected")
	var selected_builder := selected_before_build.has(builder)
	game.call("_on_build_kind",kind)
	var selected_after_build_kind: Array = game.get("selected")
	var placed: Node3D = null
	var chosen_position := Vector3.ZERO
	var selection_at_placement := 0
	var builder_site_at_placement := ""
	var builder_state_at_placement := -1
	for position in candidates:
		if not bool(game.call("_placement_valid_at",position)): continue
		selection_at_placement = (game.get("selected") as Array).size()
		game.call("_try_place",position)
		await get_tree().process_frame
		builder_site_at_placement = str(builder.get("build_site").get_instance_id()) if is_instance_valid(builder.get("build_site")) else ""
		builder_state_at_placement = int(builder.get("state"))
		for building in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(building) or existing.has(str(building.get_instance_id())): continue
			if int(building.get("kind")) == kind and str(building.get("team")) == "player":
				placed=building
				chosen_position=position
				break
		if placed != null: break
	if placed == null:
		return {"complete":false,"failure":"production_paid_placement_rejected","kind":kind,"wood_before":before_wood,"wood_after":int(game.get("wood")),"food_before":before_food,"food_after":int(game.get("meat")),"selected_builder":str(builder.name),"selected_builder_in_selection_before_build":selected_builder,"selection_before_build_kind":selected_before_build.map(func(n): return str(n.name)),"selection_after_build_kind":selected_after_build_kind.map(func(n): return str(n.name)),"selection_count_at_placement":selection_at_placement,"builder_state":int(builder.get("state")),"builder_site":str(builder.get("build_site").name) if is_instance_valid(builder.get("build_site")) else ""}
	_last_placed_building = placed
	var cost: Dictionary = CATALOG.get_def(kind)
	var builder_assigned: bool = builder.get("build_site") == placed
	var production_build_command_reissued := false
	if not builder_assigned:
		# Exercise the same ordinary Villager3D.command_build method Main uses for
		# selected villagers. This remains a paid, live-worker production build.
		builder.call("command_build",placed,false)
		production_build_command_reissued = true
		await get_tree().process_frame
		builder_assigned = builder.get("build_site") == placed
	var started := float(game.get("_game_time"))
	while is_instance_valid(placed) and not bool(placed.get("is_complete")) and float(game.get("_game_time"))-started < 90.0:
		await get_tree().process_frame
	var result := {"kind":kind,"building_id":str(placed.get_instance_id()) if is_instance_valid(placed) else "","position":[chosen_position.x,chosen_position.y,chosen_position.z],"builder_id":str(builder.get_instance_id()),"builder_name":str(builder.name),"builder_assigned_at_placement":builder_assigned,"builder_site_at_placement":builder_site_at_placement,"builder_state_at_placement":builder_state_at_placement,"builder_has_command_build":builder.has_method("command_build"),"builder_in_main_selection_at_placement":(game.get("selected") as Array).has(builder),"selection_count_at_placement":selection_at_placement,"selected_names_at_placement":(game.get("selected") as Array).map(func(n): return str(n.name)),"production_build_command_reissued":production_build_command_reissued,"builder_site_after":str(builder.get("build_site").get_instance_id()) if is_instance_valid(builder.get("build_site")) else "","builder_state_after":int(builder.get("state")),"wood_before":before_wood,"wood_after":int(game.get("wood")),"wood_cost":int(cost.get("cost_wood",0)),"food_before":before_food,"food_after":int(game.get("meat")),"food_cost":int(cost.get("cost_meat",0)),"build_progress":float(placed.get("build_progress")) if is_instance_valid(placed) else -1.0,"build_time":float(placed.get("build_time")) if is_instance_valid(placed) else -1.0,"complete":is_instance_valid(placed) and bool(placed.get("is_complete")),"path":"Main._on_build_kind -> Main._placement_valid_at -> Main._try_place paid deduction -> selected Villager3D.command_build / explicit normal builder order if selection route did not attach -> Building.add_build_progress"}
	_events.append({"action":"production_building_paid_and_completed","game_time":float(game.get("_game_time")),"evidence":result})
	return result

func _living_workers() -> Array[Node3D]:
	var workers: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("alive")): workers.append(unit)
	return workers

func _player_soldiers() -> Array[Node3D]:
	var soldiers: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit is Soldier3D and is_instance_valid(unit) and str(unit.get("team")) == "player" and not bool(unit.get("is_zombie")): soldiers.append(unit)
	return soldiers

func _wait_game(predicate: Callable, max_frames: int) -> Node:
	for _i in max_frames:
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and predicate.call(game): return game
		await get_tree().process_frame
	return null

func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func _finish(passed: bool, reason: String, evidence: Dictionary = {}) -> void:
	_report["passed"] = passed
	_report["reason"] = reason
	_report["evidence"] = evidence
	_report["events"] = _events
	_report["ended_utc"] = Time.get_datetime_string_from_system(true,true)
	var file := FileAccess.open(REPORT_PATH,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report,"\t"))
		file.close()
	print("[barracks-recovery-behavior-probe] ",JSON.stringify({"passed":passed,"reason":reason,"report":REPORT_PATH,"evidence":evidence}))
	get_tree().quit(0 if passed else 1)
