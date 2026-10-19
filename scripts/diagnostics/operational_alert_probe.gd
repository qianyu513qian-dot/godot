extends Node
## Headless package probe. It enters a copied real save through the production
## Continue button; economy changes only through villager gather orders.

const REPORT_PATH := "user://operational_alert_probe.json"
const Catalog := preload("res://scripts/building_catalog.gd")

var report: Dictionary = {"headless": true, "time_scale": Engine.time_scale, "steps": [], "passed": false, "runtime": {"executable": OS.get_executable_path(), "user_data_dir": OS.get_user_data_dir(), "engine": Engine.get_version_info().string, "entry": "production start-menu Continue button pressed signal"}}
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless" or absf(Engine.time_scale - 1.0) > 0.001:
		_finish("probe_requires_headless_unscaled")
		return
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--scenario=construction-recovery"):
		await _run_stranded_construction_scenario()
		return
	var menu := await _wait_for_menu(20.0)
	if menu == null:
		_finish("start_menu_unavailable")
		return
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish("copied_wave1_continue_save_unavailable")
		return
	var old_menu_id := menu.get_instance_id()
	continue_button.pressed.emit()
	report["steps"].append({"step": "continue_real_wave1_save", "button_text": continue_button.text, "pressed_signal_connections": continue_button.pressed.get_connections().size()})
	game = await _wait_new_game(old_menu_id, 35.0)
	if game == null:
		_finish("production_continue_restore_timeout")
		return
	var farm := _building(Catalog.FARM)
	var barracks := _building(Catalog.BARRACKS)
	if farm == null or barracks == null or not bool(barracks.get("train_paused")) or bool(barracks.get("train_paid")):
		_finish("expected_real_paused_queue_missing")
		return
	var initial := _state(game, farm, barracks)
	game.call("_refresh_operational_alerts")
	var hud: Node = game.get("hud")
	var panel: Control = hud.get("_operational_panel")
	var rows: VBoxContainer = hud.get("_operational_rows")
	if not panel.visible or rows.get_child_count() != 1:
		_finish("unselected_paused_queue_alert_missing")
		return
	# Exercise the campaign target lookup against a location-only row before the
	# production queue locator. Location alerts intentionally have no target meta.
	hud.call("set_operational_alerts", [
		{"key":"probe:location_only","text":"定位测试","action":"地图","location":Vector3(1,0,1)},
		{"key":"probe:target","text":"目标测试","action":"定位","target":barracks},
	])
	var controller_script: Script = load("res://scripts/diagnostics/controlled_endless_defense.gd") as Script
	var controller: Node = controller_script.new() as Node if controller_script != null else null
	var target_locator: Button = controller.call("_alert_button_for_target", hud, barracks) as Button if controller != null else null
	var targetless_row_skipped: bool = target_locator != null and target_locator.has_meta("operational_alert_target") and target_locator.get_meta("operational_alert_target") == barracks
	if controller != null: controller.free()
	game.call("_refresh_operational_alerts")
	if not targetless_row_skipped:
		_finish("location_only_alert_target_lookup_failed")
		return
	report["steps"].append({"step":"location_only_alert_row_skipped_without_missing_meta_read","target_locator_found":true,"target_meta_verified":targetless_row_skipped})
	var alert_control_id := rows.get_child(0).get_instance_id()
	var alert_text := str((rows.get_child(0).get_child(0) as Label).text)
	game.call("_refresh_operational_alerts")
	if rows.get_child_count() != 1 or rows.get_child(0).get_instance_id() != alert_control_id:
		_finish("same_state_rebuilt_alert")
		return
	var barracks_locator: Button = rows.get_child(0).get_child(1) as Button
	if barracks_locator == null or barracks_locator.get_meta("operational_alert_target") != barracks:
		_finish("barracks_locator_target_mismatch")
		return
	barracks_locator.pressed.emit()
	await get_tree().process_frame
	var locator_selected_barracks: bool = barracks in game.get("selected")
	game.call("_refresh_selection_hud")
	var train_row: HBoxContainer = hud.get("_train_row")
	var shortage_found := false
	for child in train_row.get_children():
		if child is Label and str(child.text).contains("缺粮60") and str(child.text).contains("木5"):
			shortage_found = true
	game.call("_refresh_operational_alerts")
	if not locator_selected_barracks or not shortage_found or panel.visible:
		_finish("selected_queue_shortage_not_exact")
		return
	var selected_alert_hidden: bool = not bool(panel.visible)
	var defenders: Array = get_tree().get_nodes_in_group("military").filter(func(unit): return is_instance_valid(unit) and bool(unit.get("alive")) and str(unit.get("team")) == "player" and not bool(unit.get("is_zombie")))
	if not defenders.is_empty():
		game.call("_clear_selection")
		for defender in defenders:
			game.call("_add_to_selection", defender)
		game.call("_on_cmd_guard")
		game.call("_route_pending_command", barracks.global_position)
		report["steps"].append({"step": "saved_army_guarded_barracks", "defenders": defenders.size(), "anchor": [barracks.global_position.x, 0.0, barracks.global_position.z], "route": "production Guard command and pending-command route"})
	game.call("_clear_selection")
	game.call("_refresh_selection_hud")
	var pause_saved := await _save_and_continue(farm, barracks)
	if not bool(pause_saved.get("ok", false)):
		_finish("paused_queue_continue_mismatch")
		return
	game = pause_saved.get("game")
	farm = _building(Catalog.FARM)
	barracks = _building(Catalog.BARRACKS)
	hud = game.get("hud")
	var first_continue := {"state": pause_saved.get("after"), "alert_visible": bool(hud.get("_operational_panel").visible)}
	report["steps"].append({"step": "queue_alert_locator_and_continue", "alert_text": alert_text, "locator_selected_correct_barracks": locator_selected_barracks, "selected_card_shortage_exact": shortage_found, "selected_target_duplicate_alert_hidden": selected_alert_hidden, "unchanged_refresh_kept_control": true, "before": initial, "after": first_continue})

	var villagers: Array = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	var wood_node := _wood_node()
	if villagers.size() < 5 or wood_node == null:
		_finish("natural_gather_targets_missing")
		return
	for index in range(villagers.size()):
		villagers[index].call("command_gather", wood_node if index == 0 else farm)
	var paid_deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < paid_deadline and not bool(barracks.get("train_paid")) and not Array(barracks.get("train_queue")).is_empty():
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(barracks) or not bool(barracks.get("alive")):
			break
		if not is_instance_valid(farm) or not bool(farm.get("alive")):
			break
	if not is_instance_valid(barracks) or not bool(barracks.get("train_paid")):
		report["paid_transition_snapshot"] = {"game_time": float(game.get("_game_time")), "farm_found": is_instance_valid(farm), "farm_stock": int(farm.get("meat_stock")) if is_instance_valid(farm) else -1, "barracks_found": is_instance_valid(barracks), "queue": Array(barracks.get("train_queue")) if is_instance_valid(barracks) else [], "resources": {"wood": int(game.get("wood")), "meat": int(game.get("meat"))}}
		_finish("queue_did_not_reach_paid_state_before_building_loss")
		return
	var paid_before := _state(game, farm, barracks)
	var paid_continue := await _save_and_continue(farm, barracks, true)
	if not bool(paid_continue.get("ok", false)):
		report["paid_continue_debug"] = {"before": paid_continue.get("before", {}), "after": paid_continue.get("after", {})}
		_finish("paid_queue_continue_mismatch")
		return
	game = paid_continue.get("game")
	report["steps"].append({"step": "queue_paid_and_continue", "before": paid_before, "after": paid_continue.get("after"), "no_second_charge": paid_before["resources"] == paid_continue.get("after", {}).get("resources", {})})
	var old_game_id := game.get_instance_id()
	game.call("_on_defeat_to_start")
	var fresh_menu := await _wait_for_menu(25.0)
	if fresh_menu == null or fresh_menu.get_instance_id() == old_game_id:
		_finish("could_not_return_to_production_start_menu")
		return
	var mode: OptionButton = fresh_menu.get("_start_mode_select") as OptionButton
	var seed_field: LineEdit = fresh_menu.get("_seed_edit") as LineEdit
	var start_button: Button = fresh_menu.get("_start_begin_button") as Button
	if mode == null or seed_field == null or start_button == null:
		_finish("fresh_start_menu_controls_missing")
		return
	mode.select(0)
	mode.item_selected.emit(0)
	seed_field.text = "42"
	var fresh_menu_id := fresh_menu.get_instance_id()
	start_button.pressed.emit()
	report["steps"].append({"step": "new_match_started_from_production_menu", "mode": "endless", "seed": 42, "button_text": start_button.text})
	game = await _wait_started_game(fresh_menu_id, 35.0)
	if game == null:
		_finish("fresh_seeded_match_start_timeout")
		return
	# _match_started becomes true before the deferred clean-start worker layout
	# finishes; wait for that production initialization before issuing orders.
	await get_tree().create_timer(0.75).timeout
	report["steps"].append({"step": "fresh_match_initialization_settled", "game_time": float(game.get("_game_time")), "alive_villagers": get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive"))).size()})
	if not await _run_fresh_farm_reseed_probe():
		return
	report["passed"] = true
	_finish("")

func _run_stranded_construction_scenario() -> void:
	report["runtime"]["entry"] = "production start menu Start → paid construction → operational alert locator → F3 and R+left-click → F5/F9"
	var menu := await _wait_for_menu(20.0)
	if menu == null:
		_finish("construction_start_menu_unavailable")
		return
	var start_button: Button = menu.get("_start_begin_button") as Button
	var mode: OptionButton = menu.get("_start_mode_select") as OptionButton
	var seed_field: LineEdit = menu.get("_seed_edit") as LineEdit
	if start_button == null or mode == null or seed_field == null:
		_finish("construction_production_start_controls_missing")
		return
	var main_id := menu.get_instance_id()
	mode.select(0)
	mode.item_selected.emit(0)
	seed_field.text = "42"
	start_button.pressed.emit()
	report["steps"].append({"step":"production_menu_start","mode":"endless","seed":42,"button_pressed":true})
	game = await _wait_started_game(main_id, 35.0)
	if game == null:
		_finish("construction_production_match_start_timeout")
		return
	await get_tree().create_timer(0.75).timeout
	var pop_cap_before_house := int(game.get("pop_cap"))
	var wood := _wood_node()
	var villagers: Array = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and bool(v.get("alive")) and str(v.get("team")) == "player")
	if wood == null or villagers.is_empty():
		_finish("construction_natural_gather_inputs_missing")
		return
	for villager in villagers:
		villager.call("command_gather", wood)
	var wood_deadline := Time.get_ticks_msec() + 50000
	while int(game.get("wood")) < 50 and Time.get_ticks_msec() < wood_deadline and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.2).timeout
	if int(game.get("wood")) < 50:
		_finish("construction_natural_wood_cost_not_reached")
		return
	var initial_wood := int(game.get("wood"))
	var builder: Node = villagers[0]
	game.call("_clear_selection")
	game.call("_add_to_selection", builder)
	game.call("_refresh_selection_hud")
	var hud: Node = game.get("hud")
	hud.call("_on_build_toggle")
	var house_button: Button = null
	for child in (hud.get("_build_grid") as Control).get_children():
		if child is Button and str(child.text).begins_with("房屋"):
			house_button = child as Button
			break
	if house_button == null:
		_finish("construction_house_build_card_missing")
		return
	house_button.pressed.emit()
	var placement := Vector3(10.0, 0.0, 8.0)
	if not bool(game.call("_placement_valid_at", placement)):
		_finish("construction_paid_house_placement_unavailable")
		return
	game.call("_try_place", placement)
	var foundation: Node = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.HOUSE and not bool(building.get("is_complete")):
			foundation = building
			break
	var paid_cost := initial_wood - int(game.get("wood"))
	if foundation == null or paid_cost != 50 or builder.get("build_site") != foundation:
		_finish("construction_paid_foundation_or_builder_mismatch")
		return
	game.call("_refresh_operational_alerts")
	var no_alert_while_builder_active := _alert_button_for_target(hud, foundation) == null
	var queue_worker: Node = villagers[1] if villagers.size() > 1 else null
	if queue_worker == null:
		_finish("construction_queue_worker_missing")
		return
	queue_worker.call("command_gather", wood)
	var queue_ready_deadline := Time.get_ticks_msec() + 4000
	while int(queue_worker.get("state")) == 0 and Time.get_ticks_msec() < queue_ready_deadline:
		await get_tree().process_frame
	queue_worker.call("command_build", foundation, true)
	var valid_queued_task := Array(queue_worker.get("order_queue")).any(func(order): return order is Dictionary and str(order.get("k", "")) == "build" and order.get("n") == foundation)
	if int(queue_worker.get("state")) == 0:
		_finish("construction_queued_builder_did_not_queue")
		return
	# Use the existing selected-villager Move command and pending map target.
	var move_button: Button = hud.get("_cmd_btns").get("move") as Button
	if move_button == null:
		_finish("construction_villager_move_button_missing")
		return
	move_button.pressed.emit()
	var move_target: Vector3 = builder.global_position + Vector3(0.0, 0.0, 12.0)
	game.call("_route_pending_command", move_target)
	game.set("_cmd_mode", "") # The real map click consumes the one-shot move mode.
	game.call("_clear_selection")
	game.call("_refresh_selection_hud")
	var builder_left_site := builder.get("build_site") == null and int(builder.get("state")) == 1
	await get_tree().create_timer(0.5).timeout
	game.call("_refresh_operational_alerts")
	hud = game.get("hud")
	var rows: VBoxContainer = hud.get("_operational_rows") as VBoxContainer
	hud.call("set_operational_alerts", [
		{"key":"probe:location_only","text":"定位测试","action":"地图","location":Vector3(1,0,1)},
		{"key":"probe:construction_target","text":"工地测试","action":"定位","target":foundation},
	])
	var controller_script: Script = load("res://scripts/diagnostics/controlled_endless_defense.gd") as Script
	var controller: Node = controller_script.new() as Node if controller_script != null else null
	var target_locator: Button = controller.call("_alert_button_for_target", hud, foundation) as Button if controller != null else null
	var location_row_lookup_safe: bool = target_locator != null and target_locator.has_meta("operational_alert_target") and target_locator.get_meta("operational_alert_target") == foundation
	if controller != null: controller.free()
	game.call("_refresh_operational_alerts")
	if not location_row_lookup_safe:
		_finish("location_only_alert_target_lookup_failed")
		return
	report["steps"].append({"step":"location_only_alert_row_skipped_without_missing_meta_read","target_locator_found":true,"target_meta_verified":location_row_lookup_safe})
	var no_alert_for_queued_task := _alert_button_for_target(hud, foundation) == null
	queue_worker.call("command_stop")
	await get_tree().create_timer(2.0).timeout
	game.call("_refresh_operational_alerts")
	var locator := _alert_button_for_target(hud, foundation)
	var initial_terminal := _terminal_hud_state(hud)
	var repeated_row_ids: Array = rows.get_children().map(func(row): return row.get_instance_id())
	game.call("_refresh_operational_alerts")
	game.call("_refresh_operational_alerts")
	var stable_row_ids: Array = rows.get_children().map(func(row): return row.get_instance_id())
	var repeated_refresh_stable := rows.get_child_count() > 0 and repeated_row_ids == stable_row_ids
	if locator == null or not bool(hud.get("_operational_panel").visible) or not builder_left_site or not valid_queued_task or not no_alert_while_builder_active or not no_alert_for_queued_task or not repeated_refresh_stable:
		report["construction_alert_debug"] = {"locator_found":locator != null,"panel_visible":bool(hud.get("_operational_panel").visible),"row_count":rows.get_child_count(),"row_texts":rows.get_children().map(func(row): return str((row.get_child(0) as Label).text) if row.get_child_count() > 0 else ""),"builder_left_site":builder_left_site,"valid_queued_task":valid_queued_task,"no_alert_while_builder_active":no_alert_while_builder_active,"no_alert_for_queued_task":no_alert_for_queued_task,"repeated_refresh_stable":repeated_refresh_stable,"foundation_complete":bool(foundation.get("is_complete")),"construction_assignment":game.call("_construction_assignment_summary", foundation),"missing_since":game.get("_construction_alert_missing_since_msec").get(foundation.get_instance_id(), -1)}
		_finish("construction_stranded_alert_or_refresh_missing")
		return
	var foundation_row: HBoxContainer = hud.get("_operational_row_by_key").get("construction:%s" % str(foundation.get_instance_id()))
	var alert_text := str((foundation_row.get_child(0) as Label).text) if is_instance_valid(foundation_row) else ""
	var terminal_after_alert_refresh := _terminal_hud_state(hud)
	locator.pressed.emit()
	await get_tree().process_frame
	var located: bool = foundation in game.get("selected") and game.get("cam_pivot").position.distance_to(foundation.global_position) < 0.1
	var selection_status: Label = hud.get("_construction_status_l") as Label
	var selection_hint: Label = hud.get("_hint_l") as Label
	var selected_status_visible := selection_status != null and selection_status.visible and str(selection_status.text).contains("施工暂停") and str(selection_status.text).contains("/15.0秒")
	var selected_continue_guidance := selection_hint != null and str(selection_hint.text).contains("按 R") and str(selection_hint.text).contains("左键")
	var selected_status_text := str(selection_status.text) if selection_status != null else ""
	var selected_instruction_text := str(selection_hint.text) if selection_hint != null else ""
	var retired_locator_disabled := not is_instance_valid(locator) or locator.disabled
	var terminal_after_locate := _terminal_hud_state(hud)
	if not located or not selected_status_visible or not selected_continue_guidance or not retired_locator_disabled:
		report["construction_locator_debug"] = {"located":located,"selected_status":str(selection_status.text) if selection_status != null else "missing","selected_status_visible":selected_status_visible,"selected_hint":str(selection_hint.text) if selection_hint != null else "missing","guidance":selected_continue_guidance,"old_locator_disabled":retired_locator_disabled,"terminal_before":initial_terminal,"terminal_after_alert":terminal_after_alert_refresh,"terminal_after_locate":terminal_after_locate}
		_finish("construction_locator_or_selected_guidance_mismatch")
		return
	game.call("_clear_selection")
	game.call("_refresh_selection_hud")
	game.call("_refresh_operational_alerts")
	var pause_key := InputEventKey.new()
	pause_key.pressed = true
	pause_key.keycode = KEY_ESCAPE
	game.call("_unhandled_input", pause_key)
	var paused_alert_before_save := get_tree().paused and bool(hud.get("_operational_panel").visible) and _alert_button_for_target(hud, foundation) != null
	var save_path: String = str(game.call("_active_save_path"))
	var save_ok := bool(game.call("_save_match"))
	var save_hash_before := FileAccess.get_sha256(save_path) if save_ok and FileAccess.file_exists(save_path) else ""
	var main_id_before_restore := game.get_instance_id()
	var old_foundation: Node = foundation
	var old_foundation_id := foundation.get_instance_id()
	if not save_ok or save_hash_before.is_empty():
		_finish("construction_stalled_save_failed")
		return
	game.call("_continue_saved_match")
	var restore_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < restore_deadline and (bool(game.get("_start_operation_busy")) or game.get("_pending_restore") != null and not game.get("_pending_restore").is_empty()):
		await get_tree().process_frame
	game = get_tree().root.get_node_or_null("Main")
	if game == null or game.get_instance_id() != main_id_before_restore or bool(game.get("_start_operation_busy")):
		_finish("construction_stalled_in_place_continue_failed")
		return
	foundation = _building(Catalog.HOUSE)
	hud = game.get("hud")
	var loaded_as_new_entity := foundation != null and foundation.get_instance_id() != old_foundation_id and not is_instance_valid(old_foundation)
	await get_tree().create_timer(1.8).timeout
	game.call("_refresh_operational_alerts")
	locator = _alert_button_for_target(hud, foundation) if foundation != null else null
	var restored_target_current: bool = locator != null and locator.get_meta("operational_alert_target") == foundation and is_instance_valid(foundation) and foundation.is_inside_tree()
	var paused_alert_survives_load := paused_alert_before_save and get_tree().paused and bool(hud.get("_operational_panel").visible) and restored_target_current
	var restored_alert_not_stale := true
	for row in (hud.get("_operational_rows") as VBoxContainer).get_children():
		var row_button := row.get_child(1) as Button if row.get_child_count() > 1 else null
		if row_button != null:
			var row_target: Variant = row_button.get_meta("operational_alert_target", null)
			if not is_instance_valid(row_target) or not row_target.is_inside_tree():
				restored_alert_not_stale = false
	var stalled_save_hash_unchanged := FileAccess.get_sha256(save_path) == save_hash_before
	if not loaded_as_new_entity or not restored_target_current or not restored_alert_not_stale or not stalled_save_hash_unchanged or not paused_alert_survives_load:
		_finish("construction_stalled_alert_restore_reference_mismatch")
		return
	game.call("_set_pause_menu_open", false)
	await get_tree().process_frame
	var restored_button_id := locator.get_instance_id()
	locator.pressed.emit()
	await get_tree().process_frame
	var restored_locator_selected: bool = foundation in game.get("selected")
	# Player choice: use the existing idle-villager HUD button, then R + left-click repair route.
	var idle_button: Button = hud.get("_idle_btn") as Button
	if idle_button == null:
		_finish("construction_idle_villager_button_missing")
		return
	var idle_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < idle_deadline:
		var idle_exists := get_tree().get_nodes_in_group("villagers").any(func(v): return is_instance_valid(v) and bool(v.get("alive")) and str(v.get("team")) == "player" and int(v.get("state")) == 0)
		if idle_exists: break
		await get_tree().process_frame
	idle_button.pressed.emit()
	var selected_workers: Array = game.get("selected").filter(func(v): return is_instance_valid(v) and v.is_in_group("villagers") and str(v.get("team")) == "player")
	if selected_workers.is_empty():
		_finish("construction_no_idle_villager_selected")
		return
	var repair_key := InputEventKey.new()
	repair_key.pressed = true
	repair_key.keycode = KEY_R
	game.call("_unhandled_input", repair_key)
	if str(game.get("_cmd_mode")) != "repair":
		_finish("construction_repair_hotkey_not_accepted")
		return
	game.call("_route_pending_command", foundation.global_position)
	var manually_assigned := selected_workers.any(func(v): return v.get("build_site") == foundation)
	report["manual_recovery_debug"] = {"restored_locator_selected":restored_locator_selected,"selected_workers":selected_workers.map(func(v): return {"name":v.name,"state":int(v.get("state")),"alive":bool(v.get("alive")),"carry":int(v.get("carry_amount"))}),"cmd_mode_after_R":str(game.get("_cmd_mode")),"manual_assignment":manually_assigned,"foundation_progress_before_completion":float(foundation.get("build_progress")),"foundation_complete_at_assignment":bool(foundation.get("is_complete"))}
	var build_time := float(foundation.get("build_time"))
	var completion_deadline := Time.get_ticks_msec() + 50000
	while Time.get_ticks_msec() < completion_deadline and is_instance_valid(foundation) and not bool(foundation.get("is_complete")) and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.2).timeout
	var completed := is_instance_valid(foundation) and bool(foundation.get("is_complete")) and float(foundation.get("build_progress")) >= build_time
	game.call("_refresh_pop")
	game.call("_refresh_selection_hud")
	game.call("_refresh_operational_alerts")
	var completed_alert_gone := _alert_button_for_target(hud, foundation) == null
	var completed_hud_cleared := selection_status != null and not selection_status.visible
	game.call("_clear_selection")
	game.set("_cmd_mode", "")
	if is_instance_valid(locator): locator.pressed.emit()
	await get_tree().process_frame
	var retired_button_click_noop: bool = game.get("selected").is_empty() and str(game.get("_cmd_mode")).is_empty() and _alert_button_for_target(hud, foundation) == null
	var expected_house_pop_bonus := int(Catalog.get_def(Catalog.HOUSE).get("pop_bonus", 0))
	var pop_functional := expected_house_pop_bonus > 0 and int(game.get("pop_cap")) >= pop_cap_before_house + expected_house_pop_bonus
	if not restored_locator_selected or not manually_assigned or not completed or not completed_alert_gone or not completed_hud_cleared or not retired_button_click_noop or not pop_functional:
		report["manual_recovery_debug"].merge({"completed":completed,"alert_gone":completed_alert_gone,"construction_status_hidden":completed_hud_cleared,"retired_button_click_noop":retired_button_click_noop,"house_pop_cap_functional":pop_functional,"final_progress":float(foundation.get("build_progress")) if is_instance_valid(foundation) else -1.0,"final_state":int(foundation.get("is_complete")) if is_instance_valid(foundation) else -1})
		_finish("construction_manual_resume_or_completion_failed")
		return
	var completed_save_ok := bool(game.call("_save_match"))
	var completed_save_hash := FileAccess.get_sha256(save_path) if completed_save_ok and FileAccess.file_exists(save_path) else ""
	game.call("_continue_saved_match")
	restore_deadline = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < restore_deadline and (bool(game.get("_start_operation_busy")) or game.get("_pending_restore") != null and not game.get("_pending_restore").is_empty()):
		await get_tree().process_frame
	game = get_tree().root.get_node_or_null("Main")
	foundation = _building(Catalog.HOUSE)
	hud = game.get("hud") if game != null else null
	game.call("_refresh_operational_alerts")
	var completed_roundtrip := completed_save_ok and foundation != null and bool(foundation.get("is_complete")) and _alert_button_for_target(hud, foundation) == null and int(game.get("pop_cap")) >= pop_cap_before_house + expected_house_pop_bonus and FileAccess.get_sha256(save_path) == completed_save_hash
	var terminal_before := _terminal_hud_state(hud)
	hud.call("show_defeat", "终局面板回归检查", "告警刷新不得重建或隐藏此面板。")
	var fake_alert := {"key":"construction_terminal_identity_probe","text":"终局期间告警面板身份检查","action":"定位", "target":foundation}
	hud.call("set_operational_alerts", [fake_alert])
	hud.call("set_operational_alerts", [])
	hud.call("set_operational_alerts", [])
	var terminal_after := _terminal_hud_state(hud)
	var terminal_stable := int(terminal_before.get("id", 0)) == int(terminal_after.get("id", -1)) and int(terminal_before.get("count", 0)) == 1 and int(terminal_after.get("count", 0)) == 1 and bool(terminal_after.get("visible")) and int(terminal_before.get("retry_connections", 0)) == 1 and int(terminal_after.get("retry_connections", 0)) == 1 and int(terminal_before.get("start_connections", 0)) == 1 and int(terminal_after.get("start_connections", 0)) == 1
	var panel := hud.get("_defeat_panel") as Control
	if panel != null: panel.hide()
	report["steps"].append({"step":"stalled_alert_locate_save_load_manual_resume_complete","passed":true,"paid_cost_wood":paid_cost,"alert_text":alert_text,"active_builder_suppresses_alert":no_alert_while_builder_active,"valid_queued_task_suppresses_alert":valid_queued_task and no_alert_for_queued_task,"alert_locator_selected_foundation":located,"selected_status":selected_status_text,"selected_instruction":selected_instruction_text,"stale_button_retired":retired_locator_disabled,"saved_stalled_foundation_recreated":loaded_as_new_entity,"restored_alert_target_rebound":restored_target_current,"paused_alert_survives_save_load":paused_alert_survives_load,"restored_button_id":restored_button_id,"alert_refs_valid":restored_alert_not_stale,"stalled_save_hash_unchanged":stalled_save_hash_unchanged,"player_idle_select_and_R_left_click_assigned":manually_assigned,"completed":completed,"build_time":build_time,"build_progress_final":float(foundation.get("build_progress")),"retired_button_click_noop":retired_button_click_noop,"pop_cap_before_house":pop_cap_before_house,"pop_cap_after_house":int(game.get("pop_cap")),"house_pop_bonus":expected_house_pop_bonus,"house_population_cap_function":pop_functional,"completion_removed_alert_and_status":completed_alert_gone and completed_hud_cleared,"completed_save_load_roundtrip":completed_roundtrip,"terminal_panel_identity_and_visibility_stable":terminal_stable,"terminal_before":terminal_before,"terminal_after":terminal_after,"terminal_identity_after_alert_refresh":terminal_after_alert_refresh,"terminal_identity_after_locate":terminal_after_locate})
	if not completed_roundtrip or not terminal_stable:
		_finish("construction_completed_roundtrip_or_terminal_hud_regression")
		return
	var completed_game_id := game.get_instance_id()
	var completed_hud: Node = hud
	game.call("_on_defeat_to_start")
	var fresh_menu := await _wait_for_menu(25.0)
	var menu_alerts_cleared := fresh_menu != null and fresh_menu.get_instance_id() != completed_game_id and (not is_instance_valid(completed_hud) or completed_hud.get("_operational_rows") == null or (completed_hud.get("_operational_rows") as VBoxContainer).get_child_count() == 0)
	if not menu_alerts_cleared:
		_finish("construction_alert_return_to_menu_cleanup_failed")
		return
	report["steps"].append({"step":"return_to_menu_alert_cleanup","passed":menu_alerts_cleared,"new_menu_instance":fresh_menu.get_instance_id(),"old_game_instance":completed_game_id,"old_hud_retired":not is_instance_valid(completed_hud)})
	report["passed"] = true
	_finish("")

func _terminal_hud_state(target_hud: Node) -> Dictionary:
	if target_hud == null:
		return {"id":0,"count":0,"visible":false,"retry_connections":0,"start_connections":0}
	var panel: Control = target_hud.get("_defeat_panel") as Control
	var retry: Button = null
	var start: Button = null
	if panel != null:
		for node in panel.find_children("*", "Button", true, false):
			if str(node.name) == "BtnRetry": retry = node as Button
			if str(node.name) == "BtnToStart": start = node as Button
	return {"id":panel.get_instance_id() if panel != null else 0,"count":target_hud.find_children("DefeatBanner", "Panel", true, false).size(),"visible":panel.visible if panel != null else false,"retry_connections":retry.pressed.get_connections().size() if retry != null else 0,"start_connections":start.pressed.get_connections().size() if start != null else 0}

func _run_fresh_farm_reseed_probe() -> bool:
	var villagers: Array = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	var wood_node := _wood_node()
	if villagers.size() < 5 or wood_node == null:
		_finish("fresh_match_gather_targets_missing")
		return false
	for villager in villagers:
		villager.call("command_gather", wood_node)
	var wood_deadline := Time.get_ticks_msec() + 90000
	while int(game.get("wood")) < 100 and Time.get_ticks_msec() < wood_deadline and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.25).timeout
	if int(game.get("wood")) < 100:
		report["wood_probe_debug"] = {"game_time": float(game.get("_game_time")), "resources": {"wood": int(game.get("wood")), "meat": int(game.get("meat"))}, "tree_stock": int(wood_node.get("amount")) if is_instance_valid(wood_node) else -1, "paused": get_tree().paused, "villagers": villagers.map(func(v): return {"alive": bool(v.get("alive")), "state": int(v.get("state")), "carry": int(v.get("carry_amount")), "carry_key": str(v.get("carry_key")), "target_valid": is_instance_valid(v.get("gather_target")) if v.get("gather_target") != null else false})}
		_finish("natural_wood_income_did_not_fund_farm_and_reseed")
		return false
	game.call("_clear_selection")
	villagers = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	for villager in villagers:
		game.call("_add_to_selection", villager)
	game.call("_on_cmd_stop")
	game.call("_on_build_kind", Catalog.FARM)
	var farm: Node3D = null
	for position in [Vector3(12, 0, 0), Vector3(12, 0, 12), Vector3(14, 0, -6)]:
		if bool(game.call("_placement_valid_at", position)):
			game.call("_try_place", position)
			farm = _building(Catalog.FARM)
			if farm != null:
				break
	if farm == null or int(game.get("wood")) != 25:
		_finish("paid_farm_build_or_reseed_reserve_mismatch")
		return false
	var build_deadline := Time.get_ticks_msec() + 35000
	while not bool(farm.get("is_complete")) and Time.get_ticks_msec() < build_deadline and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.25).timeout
	if not bool(farm.get("is_complete")):
		_finish("production_farm_did_not_complete")
		return false
	villagers = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	for villager in villagers:
		villager.call("command_gather", farm)
	var depletion_deadline := Time.get_ticks_msec() + 80000
	while not bool(farm.get("is_arid")) and Time.get_ticks_msec() < depletion_deadline and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.25).timeout
	if not bool(farm.get("is_arid")) or int(farm.get("meat_stock")) != 0:
		_finish("natural_farm_depletion_not_observed")
		return false
	game.call("_clear_selection")
	game.call("_refresh_operational_alerts")
	var hud: Node = game.get("hud")
	var farm_locator := _alert_button_for_target(hud, farm)
	if farm_locator == null or not bool(hud.get("_operational_panel").visible):
		_finish("fresh_farm_depletion_alert_missing")
		return false
	var before_dry_continue := {"wood": int(game.get("wood")), "meat": int(game.get("meat")), "farm_stock": int(farm.get("meat_stock")), "farm_arid": bool(farm.get("is_arid"))}
	game.call("_save_match")
	var old_id := game.get_instance_id()
	game.call("_continue_saved_match")
	game = await _wait_new_game(old_id, 30.0)
	if game == null:
		_finish("fresh_dry_farm_continue_timeout")
		return false
	farm = _building(Catalog.FARM)
	if farm == null or not bool(farm.get("is_arid")) or int(farm.get("meat_stock")) != 0:
		_finish("fresh_dry_farm_state_not_restored")
		return false
	game.call("_refresh_operational_alerts")
	hud = game.get("hud")
	var after_dry_continue := {"wood": int(game.get("wood")), "meat": int(game.get("meat")), "farm_stock": int(farm.get("meat_stock")), "farm_arid": bool(farm.get("is_arid"))}
	var farm_alert_visible := bool(hud.get("_operational_panel").visible) and _alert_button_for_target(hud, farm) != null
	if not farm_alert_visible:
		_finish("dry_farm_alert_not_restored_after_continue")
		return false
	var locator := _alert_button_for_target(hud, farm)
	locator.pressed.emit()
	await get_tree().process_frame
	var selected_correct_farm: bool = farm in game.get("selected")
	var wood_before_reseed := int(game.get("wood"))
	var reseed_key := InputEventKey.new()
	reseed_key.pressed = true
	reseed_key.keycode = KEY_R
	game.call("_unhandled_input", reseed_key)
	var reseed_cost_paid := wood_before_reseed - int(game.get("wood"))
	var farm_reseeded := not bool(farm.get("is_arid")) and int(farm.get("meat_stock")) == int(farm.get("meat_max"))
	if not selected_correct_farm or reseed_cost_paid != 25 or not farm_reseeded:
		_finish("farm_locator_r_reseed_or_cost_mismatch")
		return false
	var meat_before_resume := int(game.get("meat"))
	villagers = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	game.call("_clear_selection")
	for villager in villagers:
		villager.call("command_gather", farm)
	var regather_deadline := Time.get_ticks_msec() + 30000
	while int(game.get("meat")) <= meat_before_resume and Time.get_ticks_msec() < regather_deadline and not bool(game.get("_defeated")):
		await get_tree().create_timer(0.25).timeout
	var regathered := int(game.get("meat")) > meat_before_resume
	report["steps"].append({"step": "natural_farm_alert_continue_locator_r_reseed_regather", "before_continue": before_dry_continue, "after_continue": after_dry_continue, "farm_alert_survived_continue": farm_alert_visible, "locator_selected_correct_farm": selected_correct_farm, "wood_before_reseed": wood_before_reseed, "wood_after_reseed": int(game.get("wood")), "reseed_wood_cost": reseed_cost_paid, "farm_stock_after_reseed": int(farm.get("meat_stock")), "food_gather_resumed": regathered, "food_before": meat_before_resume, "food_after": int(game.get("meat"))})
	if not regathered:
		_finish("reseeded_farm_did_not_resume_natural_gather")
		return false
	return true

func _save_and_continue(farm: Node3D, barracks: Node3D, allow_farm_drain: bool = false) -> Dictionary:
	game.call("_save_match")
	var before := _state(game, farm, barracks)
	var old_id := game.get_instance_id()
	game.call("_continue_saved_match")
	var loaded := await _wait_new_game(old_id, 25.0)
	if loaded == null:
		return {"ok": false, "before": before, "after": {}}
	game = loaded
	var after := _state(game, _building(Catalog.FARM), _building(Catalog.BARRACKS))
	var stock_matches: bool = bool(allow_farm_drain) or before["farm_stock"] == after["farm_stock"]
	var matches: bool = before["resources"] == after["resources"] and before["train_queue"] == after["train_queue"] and before["train_paid"] == after["train_paid"] and before["train_paused"] == after["train_paused"] and before["farm_arid"] == after["farm_arid"] and stock_matches
	return {"ok": matches, "game": loaded, "before": before, "after": after}

func _wait_for_menu(seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get("_start_layer") != null:
			return current
	return null

func _wait_new_game(old_id: int, seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get_instance_id() != old_id and bool(current.get("_match_started")):
			return current
	return null

func _wait_started_game(expected_id: int, seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get_instance_id() == expected_id and bool(current.get("_match_started")):
			return current
	return null

func _wood_node() -> Node3D:
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and not node.is_in_group("buildings") and node.has_method("res_key") and str(node.call("res_key")) == "wood":
			return node
	return null

func _alert_button_for_target(hud: Node, target: Node3D) -> Button:
	var rows: VBoxContainer = hud.get("_operational_rows")
	for row in rows.get_children():
		if row.get_child_count() < 2:
			continue
		var button := row.get_child(1) as Button
		if button != null and button.has_meta("operational_alert_target") and button.get_meta("operational_alert_target") == target:
			return button
	return null

func _building(kind: int) -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and int(building.get("kind")) == kind and bool(building.get("alive")) and str(building.get("team")) == "player":
			return building
	return null

func _state(target_game: Node, farm: Node, barracks: Node) -> Dictionary:
	return {"game_time": float(target_game.get("_game_time")), "resources": {"wood": int(target_game.get("wood")), "meat": int(target_game.get("meat")), "stone": int(target_game.get("stone")), "gold": int(target_game.get("gold"))}, "farm_arid": bool(farm.get("is_arid")), "farm_stock": int(farm.get("meat_stock")), "train_queue": Array(barracks.get("train_queue")).duplicate(), "train_paid": bool(barracks.get("train_paid")), "train_paused": bool(barracks.get("train_paused")), "soldiers": get_tree().get_nodes_in_group("military").filter(func(unit): return is_instance_valid(unit) and bool(unit.get("alive")) and str(unit.get("team")) == "player").size()}

func _finish(error_text: String) -> void:
	if not error_text.is_empty():
		report["error"] = error_text
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[operational_alert_probe] ", JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("passed", false)) else 1)
