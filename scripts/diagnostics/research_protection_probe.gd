extends Node

const SoldierScript := preload("res://scripts/soldier.gd")
const BuildingScript := preload("res://scripts/building.gd")
const Catalog := preload("res://scripts/building_catalog.gd")
const Research := preload("res://scripts/research.gd")

var report: Dictionary = {"schema":"research_and_move_warning_production_regression_v1","normal_seed":42,"natural_horde_rules_changed":false,"injected_resources_or_tech":false,"gpu_required":false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var game := _main_game()
	if game == null:
		_finish(false, "production_main_missing")
		return
	var start: Button = game.get("_start_begin_button")
	var seed: LineEdit = game.get("_seed_edit")
	if start == null or seed == null:
		_finish(false, "production_start_controls_missing")
		return
	seed.text = "42"
	start.pressed.emit()
	if not await _wait_until(func() -> bool: return _main_game() != null and bool(_main_game().get("_match_started")) and bool(_main_game().get("_player_orders_ready")), 90000):
		_finish(false, "production_match_start_timeout")
		return
	game = _main_game()
	var workers := _living_player_villagers()
	if workers.size() < 2:
		_finish(false, "production_workers_missing")
		return
	var worker: Node3D = workers[0]
	var second_worker: Node3D = workers[1]
	var camera_pivot: Node3D = game.get("cam_pivot")
	camera_pivot.global_position = worker.global_position
	var attackers: Array[Node3D] = []
	for victim in [worker, second_worker]:
		var attacker: Node3D = SoldierScript.new()
		attacker.call("setup", victim.global_position + Vector3(0.4, 0.0, 0.1), "enemy", true)
		(game.get("world") as Node).add_child(attacker)
		attacker.set("attack_target", victim)
		attackers.append(attacker)
	var hp_before: Array[float] = [float(worker.get("hp")), float(second_worker.get("hp"))]
	if not await _wait_until(func() -> bool: return float(worker.get("hp")) < hp_before[0] and float(second_worker.get("hp")) < hp_before[1], 5000):
		_finish(false, "real_visible_attacker_damage_missing")
		return
	var alert := _fresh_unit_alert(game, [worker, second_worker])
	var visible_attackers := attackers.all(func(enemy: Node3D) -> bool: return _enemy_on_screen(game, enemy) and enemy.get("attack_target") in [worker, second_worker])
	if alert.is_empty() or not visible_attackers:
		_finish(false, "fresh_alert_or_visible_pursuer_missing")
		return
	var target := worker.global_position + Vector3(5.0, 0.0, 5.0)
	game.call("_clear_selection")
	game.call("_add_to_selection", worker)
	game.call("_refresh_selection_hud")
	_clear_hud_message(game)
	game.call("_issue_formation_move", [worker], target, false)
	var move_goal: Vector3 = worker.get("_goal_final")
	var move_points: Array = worker.get("_waypoints")
	var move_message := _hud_message(game)
	var move_order_untouched := move_goal.distance_to(target) < 0.05 and not move_points.is_empty()
	var move_warning := "路线旁有1名可见追兵" in move_message
	_clear_hud_message(game)
	var queued_goal := target + Vector3(3.0, 0.0, -2.0)
	var queue_before: int = (worker.get("order_queue") as Array).size()
	game.call("_issue_formation_move", [worker], queued_goal, true)
	var queued_orders: Array = worker.get("order_queue")
	var shift_preserved := queued_orders.size() == queue_before + 1 and Vector3(queued_orders.back().get("p", Vector3.ZERO)).distance_to(queued_goal) < 0.05
	report["fresh_alert_production_move"] = {"alert_category":alert.get("category"),"victims":Array(alert.get("victim_instance_ids", [])).size(),"visible_live_pursuers":attackers.size(),"requested_goal":_v3(target),"resolved_goal":_v3(move_goal),"actual_waypoints":_points(move_points),"hud_flash_msg":move_message,"command_preserved":move_order_untouched and move_goal.distance_to(Vector3(worker.get("_goal_final"))) < 0.05}
	report["shift_append_preserved"] = {"queue_before":queue_before,"queue_after":queued_orders.size(),"queued_goal":_v3(queued_goal),"passed":shift_preserved}
	if not move_warning or not move_order_untouched or not shift_preserved:
		_finish(false, "production_move_warning_or_order_preservation_failed")
		return
	# The warning must not count the same pursuer twice when several workers are selected.
	game.call("_clear_selection")
	game.call("_add_to_selection", worker)
	game.call("_add_to_selection", second_worker)
	_clear_hud_message(game)
	game.call("_issue_formation_move", [worker, second_worker], target, false)
	var multi_message := _hud_message(game)
	var multi_count_ok := "路线旁有2名可见追兵" in multi_message
	report["multi_villager_count"] = {"selected_villagers":2,"unique_visible_pursuers":2,"hud_flash_msg":multi_message,"passed":multi_count_ok}
	if not multi_count_ok:
		_finish(false, "multi_villager_pursuer_count_not_entity_count")
		return
	# Dead, stale and off-screen pursuers do not generate a pursuit warning.
	for attacker in attackers:
		attacker.set("attack_target", null)
		attacker.set("alive", false)
	var dead_message := _warning_after_move(game, worker, target)
	var expired_alerts: Dictionary = game.get("_combat_damage_alerts").duplicate(true)
	for key in expired_alerts:
		var event: Dictionary = expired_alerts[key]
		if str(event.get("category", "")) == "economy_unit":
			event["last_hit_msec"] = Time.get_ticks_msec() - 13000
			expired_alerts[key] = event
	game.set("_combat_damage_alerts", expired_alerts)
	var expired_message := _warning_after_move(game, worker, target)
	report["dead_and_expired_alert_filter"] = {"dead_attacker_hud":"%s" % dead_message,"expired_alert_hud":"%s" % expired_message,"passed":dead_message.is_empty() and expired_message.is_empty()}
	if not dead_message.is_empty() or not expired_message.is_empty():
		_finish(false, "dead_or_expired_pursuer_warned")
		return
	# Off-screen is checked using the production camera predicate, including behind-camera state.
	var live_attacker: Node3D = attackers[0]
	live_attacker.set("alive", true)
	live_attacker.set("attack_target", worker)
	var fresh_again: Dictionary = _fresh_unit_alert(game, [worker])
	if fresh_again.is_empty():
		game.get("_combat_damage_alerts").clear()
		var key := "probe:visible-again"
		game.get("_combat_damage_alerts")[key] = {"category":"economy_unit","last_hit_msec":Time.get_ticks_msec(),"victim_instance_ids":[worker.get_instance_id()]}
	camera_pivot.global_position = Vector3(45.0, 0.0, 45.0)
	var offscreen_warning: Dictionary = game.call("_alerted_villager_move_warning", worker)
	var offscreen_ok := offscreen_warning.is_empty()
	report["offscreen_pursuer_filtered"] = {"camera_pivot":_v3(camera_pivot.global_position),"warning":offscreen_warning,"passed":offscreen_ok}
	if not offscreen_ok:
		_finish(false, "offscreen_pursuer_counted")
		return
	for attacker in attackers:
		attacker.queue_free()
	if not _check_multi_tower_endpoint(game,worker):
		return
	# Then run the real paid technology order and preserve it through F5/F9.
	var healthiest_worker: Node3D = worker
	for candidate in workers:
		if float(candidate.get("hp")) > float(healthiest_worker.get("hp")):
			healthiest_worker = candidate
	if not await _run_paid_research_save_restore(game, healthiest_worker):
		_finish(false,"paid_research_save_restore_or_training_slice_failed")
		return
	_finish(true, "production_move_warning_and_paid_research_restore_passed")

func _run_paid_research_save_restore(game: Node, worker: Node3D) -> bool:
	# The standard new game starts without stocked wood; collect it with normal
	# villager gather orders before purchasing the technology.
	var pre_research_wood := int(game.get("wood"))
	var lumber_target := _nearest_wood(worker)
	if lumber_target == null:
		_finish(false, "natural_wood_node_missing_for_research_prerequisite")
		return false
	for gatherer in _living_player_villagers():
		gatherer.call("command_gather", lumber_target)
	if not await _wait_until(func() -> bool: return int(game.get("wood")) >= 10, 60000):
		report["wood_prerequisite_gather"] = {"starting_wood":pre_research_wood,"wood_after":int(game.get("wood")),"target_stock":int(lumber_target.get("amount")),"passed":false}
		_finish(false, "normal_gather_orders_did_not_fund_research")
		return false
	report["wood_prerequisite_gather"] = {"starting_wood":pre_research_wood,"wood_after":int(game.get("wood")),"target_stock_after":int(lumber_target.get("amount")),"player_gather_orders":true,"passed":true}
	var town_center: Node3D = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if int(building.get("kind")) == Catalog.TOWN_CENTER and str(building.get("team")) == "player":
			town_center = building
			break
	if town_center == null:
		_finish(false, "town_center_missing_for_research_command")
		return false
	game.call("_clear_selection")
	game.call("_add_to_selection", town_center)
	game.call("_refresh_selection_hud")
	var hud: Node = game.get("hud")
	var buttons: Dictionary = hud.get("_cmd_btns")
	var research_button: Button = buttons.get("forestry") as Button
	if research_button == null or not research_button.text.contains("改良斧具"):
		report["research_menu_debug"] = {"button_found":research_button != null,"button_text":research_button.text if research_button != null else "","button_tooltip":research_button.tooltip_text if research_button != null else "","hud_keys":buttons.keys()}
		_finish(false, "player_research_menu_command_missing")
		return false
	var initial := _resources(game)
	research_button.pressed.emit()
	var model: Node = game.get("research")
	var paid_once: bool = int(game.get("meat")) == initial.meat - 25 and int(game.get("wood")) == initial.wood - 10
	var completed_immediately: bool = bool(model.call("has_technology", Research.TECH_FORESTRY))
	var benefit_applied: bool = is_equal_approx(float(worker.get("wood_gather_multiplier")), 1.25) and int(worker.get("wood_carry_bonus")) == 5
	if not paid_once or not completed_immediately or not benefit_applied:
		report["research_command_debug"] = {"button_text":research_button.text,"resources_before":initial,"resources_after":_resources(game),"researched":completed_immediately,"worker_multiplier":float(worker.get("wood_gather_multiplier")),"wood_carry_bonus":int(worker.get("wood_carry_bonus")),"paid_once":paid_once}
		_finish(false, "immediate_research_payment_or_effect_failed")
		return false
	var worker_position_before_save: Vector3 = worker.global_position
	# F5 and F9 are routed through the production input handler. Since the default
	# technology completes in the same button action, there is no mid-research state.
	print("[research-protection] immediate research completed; saving through F5")
	game.call("_set_pause_menu_open", true)
	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	game.call("_unhandled_input", f5)
	var saved_data := _read_json(game.call("_active_save_path"))
	var save_persisted := Array(saved_data.get("researched_techs", [])).has(Research.TECH_FORESTRY) and not saved_data.has("active_tech_id")
	f5.pressed = false
	game.call("_unhandled_input", f5)
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	game.call("_unhandled_input", f9)
	if not await _wait_until(func() -> bool: return _main_game() != null and not bool(_main_game().get("_start_operation_busy")), 30000):
		_finish(false, "immediate_research_f9_timeout")
		return false
	game = _main_game()
	var restored_model: Node = game.get("research")
	worker = _nearest_worker(worker_position_before_save)
	var restored_resources := _resources(game)
	var restored_completed: bool = bool(restored_model.call("has_technology", Research.TECH_FORESTRY))
	var no_refund_or_second_charge := restored_resources == _resource_dict(saved_data.get("resources", {}))
	var restored_effect_once := is_equal_approx(float(worker.get("wood_gather_multiplier")), 1.25) and int(worker.get("wood_carry_bonus")) == 5
	report["paid_research_save_restore"] = {"menu_button":"改良斧具（TC command grid）","resources_before":initial,"resources_after_order":_resources_after_cost(initial),"paid_once":paid_once,"completed_immediately":completed_immediately,"save_state":"completed technology; no in-progress fields","f9":{"completed":restored_completed,"resources_unchanged":no_refund_or_second_charge,"effect_applied_once":restored_effect_once},"mid_research_progress_test":"not applicable to default instant research"}
	if not save_persisted or not restored_completed or not no_refund_or_second_charge or not restored_effect_once:
		_finish(false, "immediate_research_save_restore_changed_payment_or_effect")
		return false
	print("[research-protection] F9 restored completed research; resuming ordinary play")
	var benefit := restored_effect_once
	var resume_button := _find_button(game.get("_pause_layer"), "继续游戏")
	if resume_button == null:
		_finish(false, "pause_resume_button_missing_after_research_f9")
		return false
	resume_button.pressed.emit()
	for gatherer in _living_player_villagers():
		if gatherer != worker:
			gatherer.call("command_stop")
	worker = _nearest_worker(worker_position_before_save)
	var wood_node: Node3D = _nearest_wood(worker)
	if wood_node == null or not is_instance_valid(wood_node):
		_finish(false, "post_restore_live_wood_node_missing")
		return false
	var wood_node_id := wood_node.get_instance_id()
	var wood_before_gather := int(game.get("wood"))
	var wood_stock_before_gather := int(wood_node.get("amount"))
	var carry_before_gather := int(worker.get("carry_amount"))
	if wood_node != null:
		worker.call("command_gather", wood_node)
	var harvest_observed := await _wait_until(func() -> bool: return is_instance_valid(wood_node) and wood_node.get_instance_id() == wood_node_id and int(wood_node.get("amount")) < wood_stock_before_gather and int(worker.get("carry_amount")) > carry_before_gather, 30000)
	var wood_stock_after_gather := int(wood_node.get("amount")) if is_instance_valid(wood_node) and wood_node.get_instance_id() == wood_node_id else -1
	var carry_after_gather := int(worker.get("carry_amount"))
	var post_restore_harvest := wood_stock_before_gather - wood_stock_after_gather
	var carry_gain := carry_after_gather - carry_before_gather
	var post_restore_stock_evidence := harvest_observed and post_restore_harvest > 0 and post_restore_harvest == carry_gain
	report["post_restore_live_wood_harvest"] = {"wood_node_instance_id":wood_node_id,"wood_stock_before":wood_stock_before_gather,"wood_stock_after":wood_stock_after_gather,"wood_decreased":post_restore_harvest,"worker_carry_before":carry_before_gather,"worker_carry_after":carry_after_gather,"worker_carry_increase":carry_gain,"same_live_node_validated":is_instance_valid(wood_node) and wood_node.get_instance_id() == wood_node_id,"harvest_observed":harvest_observed,"passed":post_restore_stock_evidence}
	if not post_restore_stock_evidence:
		_finish(false, "post_restore_wood_node_stock_and_carry_delta_missing")
		return false
	# Exercise legacy R10 save migration in an isolated model without changing the
	# active match: a paid active tech becomes completed exactly once on restore.
	var migration_model: Node = Research.new()
	add_child(migration_model)
	migration_model.call("restore_research", [], Research.TECH_FORESTRY)
	var migrated_once := bool(migration_model.call("has_technology", Research.TECH_FORESTRY)) and (migration_model.get("researched_techs") as Array).size() == 1
	migration_model.call("restore_research", migration_model.get("researched_techs"), Research.TECH_FORESTRY)
	var migration_idempotent := bool(migration_model.call("has_technology", Research.TECH_FORESTRY)) and (migration_model.get("researched_techs") as Array).size() == 1
	report["legacy_r10_paid_research_migration"] = {"legacy_active_tech_id":Research.TECH_FORESTRY,"promoted_to_completed":migrated_once,"repeated_restore_idempotent":migration_idempotent,"passed":migrated_once and migration_idempotent}
	migration_model.queue_free()
	if not migrated_once or not migration_idempotent:
		return false
	return await _continue_into_normal_training(game, worker)

func _continue_into_normal_training(game: Node, worker: Node3D) -> bool:
	if int(game.get("wood")) < 75:
		var wood_before_farm_gather := int(game.get("wood"))
		var gather_node: Node3D = _nearest_wood(worker)
		if gather_node == null or not is_instance_valid(gather_node):
			_finish(false,"normal_wood_node_missing_for_farm_cost")
			return false
		var gather_node_id := gather_node.get_instance_id()
		var stock_before_farm_gather := int(gather_node.get("amount"))
		for gatherer in _living_player_villagers():
			gatherer.call("command_gather",gather_node)
		if not await _wait_until(func() -> bool: return int(game.get("wood")) >= 75,90000):
			_finish(false,"normal_gather_orders_did_not_fund_farm")
			return false
		report["normal_wood_gather_for_farm"] = {"starting_wood":wood_before_farm_gather,"wood_after":int(game.get("wood")),"wood_node_instance_id":gather_node_id,"wood_node_stock_before":stock_before_farm_gather,"wood_node_stock_after":int(gather_node.get("amount")) if is_instance_valid(gather_node) and gather_node.get_instance_id() == gather_node_id else -1,"normal_gather_orders":true,"passed":int(game.get("wood")) >= 75}
	game.call("_clear_selection")
	game.call("_add_to_selection",worker)
	game.call("_refresh_selection_hud")
	game.call("_on_build_kind",Catalog.FARM)
	var placement: Vector3 = Vector3.ZERO
	var placement_found := false
	for candidate in [Vector3(-9.0,0.0,8.0),Vector3(9.0,0.0,8.0),Vector3(-9.0,0.0,-8.0),Vector3(9.0,0.0,-8.0),Vector3(-12.0,0.0,0.0),Vector3(12.0,0.0,0.0)]:
		if bool(game.call("_placement_valid_at",candidate)):
			placement = candidate
			placement_found = true
			break
	if not placement_found:
		_finish(false,"normal_farm_construction_site_unavailable")
		return false
	var wood_before_farm := int(game.get("wood"))
	game.call("_try_place",placement)
	var farm: Node3D = null
	for building in get_tree().get_nodes_in_group("farms"):
		if is_instance_valid(building) and not bool(building.get("is_complete")):
			farm = building
			break
	if farm == null or int(game.get("wood")) != wood_before_farm - 75:
		_finish(false,"paid_normal_farm_order_failed")
		return false
	var builders := _living_player_villagers()
	for index in range(mini(2,builders.size())):
		builders[index].call("command_build",farm)
	if not await _wait_until(func() -> bool: return is_instance_valid(farm) and bool(farm.get("is_complete")),30000):
		_finish(false,"normal_farm_build_timeout")
		return false
	var food_before := int(game.get("meat"))
	for gatherer in _living_player_villagers():
		gatherer.call("command_gather",farm)
	if not await _wait_until(func() -> bool: return int(game.get("meat")) >= 50,60000):
		_finish(false,"normal_farm_gather_did_not_fund_training")
		return false
	var town_center: Node3D = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if int(building.get("kind")) == Catalog.TOWN_CENTER and str(building.get("team")) == "player":
			town_center = building
			break
	if town_center == null:
		_finish(false,"town_center_missing_for_training")
		return false
	game.call("_clear_selection")
	game.call("_add_to_selection",town_center)
	game.call("_refresh_selection_hud")
	var training_button: Button = (game.get("hud").get("_cmd_btns") as Dictionary).get("train") as Button
	if training_button == null:
		_finish(false,"player_train_menu_command_missing")
		return false
	var workers_before := _living_player_villagers().size()
	var meat_before_training := int(game.get("meat"))
	var training_button_text := training_button.text
	training_button.pressed.emit()
	var paid_training := int(game.get("meat")) == meat_before_training - 50
	if not paid_training:
		_finish(false,"normal_paid_villager_training_not_started")
		return false
	var training_completed := await _wait_until(func() -> bool: return _living_player_villagers().size() > workers_before,30000)
	report["continued_normal_paid_training"] = {"farm_placement":_v3(placement),"farm_wood_cost":75,"wood_before_farm":wood_before_farm,"wood_after_farm":int(game.get("wood")),"normal_builder_count":mini(2,builders.size()),"farm_completed":bool(farm.get("is_complete")),"food_before":food_before,"food_before_paid_training":meat_before_training,"training_button_text":training_button_text,"training_food_cost":50,"training_paid_once":paid_training,"new_villagers_before":workers_before,"new_villagers_after":_living_player_villagers().size(),"training_completed":training_completed}
	return training_completed

func _resources(game: Node) -> Dictionary:
	return {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}

func _resources_after_cost(initial: Dictionary) -> Dictionary:
	return {"wood":int(initial.wood)-10,"meat":int(initial.meat)-25,"stone":int(initial.stone),"gold":int(initial.gold)}

func _resource_dict(value: Dictionary) -> Dictionary:
	return {"wood":int(value.get("wood",0)),"meat":int(value.get("meat",0)),"stone":int(value.get("stone",0)),"gold":int(value.get("gold",0))}

func _nearest_wood(worker: Node3D) -> Node3D:
	var nearest: Node3D = null
	var best := INF
	for candidate in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or int(candidate.get("kind")) != 0 or int(candidate.get("amount")) <= 0:
			continue
		var distance: float = worker.global_position.distance_to(candidate.global_position)
		if distance < best:
			best = distance
			nearest = candidate
	return nearest

func _warning_after_move(game: Node, worker: Node3D, destination: Vector3) -> String:
	_clear_hud_message(game)
	game.call("_issue_formation_move", [worker], destination, false)
	return _hud_message(game)

func _check_multi_tower_endpoint(game: Node, worker: Node3D) -> bool:
	var old_tower_positions: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("is_tower")) and str(building.get("team")) == "player":
			old_tower_positions.append({"node":building,"position":(building as Node3D).global_position})
			(building as Node3D).global_position = Vector3(100.0,0.0,100.0)
	var endpoint: Vector3 = worker.get("_goal_final")
	var tower_near: Node3D = BuildingScript.new()
	tower_near.call("setup",Catalog.ARROW_TOWER,endpoint+Vector3(0.0,0.0,7.0),"player",true)
	(game.get("world") as Node).add_child(tower_near)
	var tower_cover: Node3D = BuildingScript.new()
	tower_cover.call("setup",Catalog.ARROW_TOWER,endpoint+Vector3(1.0,0.0,0.0),"player",true)
	(game.get("world") as Node).add_child(tower_cover)
	game.get("_combat_damage_alerts").clear()
	game.get("_combat_damage_alerts")["probe:fresh-visible-alert"] = {"category":"economy_unit","last_hit_msec":Time.get_ticks_msec(),"victim_instance_ids":[worker.get_instance_id()]}
	var coverage_result: Dictionary = game.call("_alerted_villager_move_warning",worker)
	var alternate_tower_covers := coverage_result.is_empty()
	# Move the covering tower far away: the nearest tower is now 7 m away, beyond its range.
	tower_cover.global_position = endpoint+Vector3(20.0,0.0,0.0)
	var outside_result: Dictionary = game.call("_alerted_villager_move_warning",worker)
	var outside_correct := bool(outside_result.get("endpoint_outside_all_tower_ranges",false)) and not bool(outside_result.get("endpoint_in_tower_edge_band",false))
	# Within 6.5 m but with no tower able to cover a melee attacker at the endpoint.
	tower_near.global_position = endpoint+Vector3(0.0,0.0,6.0)
	var edge_result: Dictionary = game.call("_alerted_villager_move_warning",worker)
	var edge_correct := bool(edge_result.get("endpoint_in_tower_edge_band",false)) and not bool(edge_result.get("endpoint_outside_all_tower_ranges",false))
	report["tower_endpoint_classification"] = {"nearest_tower_range":float(tower_near.get("attack_range")),"nearest_tower_when_other_covers":7.0,"other_tower_covers_endpoint":alternate_tower_covers,"all_towers_outside_result":outside_result,"outside_range_classified_separately":outside_correct,"edge_result":edge_result,"edge_classified_separately":edge_correct,"passed":alternate_tower_covers and outside_correct and edge_correct}
	tower_near.queue_free()
	tower_cover.queue_free()
	for saved in old_tower_positions:
		if is_instance_valid(saved.node):
			(saved.node as Node3D).global_position = saved.position
	if not alternate_tower_covers or not outside_correct or not edge_correct:
		_finish(false,"tower_coverage_any_tower_or_edge_classification_failed")
		return false
	return true

func _clear_hud_message(game: Node) -> void:
	var hud: Node = game.get("hud")
	var label: Label = hud.get("_msg_l") if hud != null else null
	if label != null:
		label.text = ""
		hud.set("_msg_t", 0.0)

func _hud_message(game: Node) -> String:
	var hud: Node = game.get("hud")
	var label: Label = hud.get("_msg_l") if hud != null else null
	return str(label.text) if label != null else ""

func _fresh_unit_alert(game: Node, victims: Array) -> Dictionary:
	for event in game.get("_combat_damage_alerts").values():
		if str(event.get("category", "")) != "economy_unit" or Time.get_ticks_msec()-int(event.get("last_hit_msec",0)) > 12000:
			continue
		var ids: Array = event.get("victim_instance_ids", [])
		if victims.all(func(v: Node3D) -> bool: return ids.has(v.get_instance_id())):
			return event
	return {}

func _enemy_on_screen(game: Node, enemy: Node3D) -> bool:
	var camera: Camera3D = game.get("camera")
	var point: Vector3 = enemy.global_position + Vector3(0.0,0.8,0.0)
	var screen: Vector2 = camera.unproject_position(point)
	return not camera.is_position_behind(point) and game.get_viewport().get_visible_rect().has_point(screen)

func _living_player_villagers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(node) and bool(node.get("alive")) and str(node.get("team")) == "player":
			result.append(node)
	return result

func _living_player_soldiers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(node) and bool(node.get("alive")) and not bool(node.get("is_zombie")) and str(node.get("team")) == "player":
			result.append(node)
	return result

func _nearest_worker(position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for candidate in _living_player_villagers():
		var distance: float = candidate.global_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

func _find_button(root: Node, label: String) -> Button:
	if root == null:
		return null
	for node in root.find_children("*", "Button", true, false):
		if label in str(node.text):
			return node
	return null

func _main_game() -> Node:
	for node in get_tree().get_nodes_in_group("main_game"):
		if is_instance_valid(node):
			return node
	return null

func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var end := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _points(value: Array) -> Array:
	var points: Array = []
	for item in value:
		if item is Vector3:
			points.append(_v3(item))
	return points

func _finish(passed: bool, reason: String) -> void:
	if bool(report.get("finished",false)):
		return
	report["passed"] = passed
	report["reason"] = reason
	report["completed_utc"] = Time.get_datetime_string_from_system(true,true)
	report["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open("user://research_protection_probe.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("[research-protection] ",JSON.stringify({"passed":passed,"reason":reason,"report":"user://research_protection_probe.json"}))
	get_tree().quit(0 if passed else 1)
