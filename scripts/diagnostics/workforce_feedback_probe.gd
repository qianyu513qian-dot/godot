extends Node
## Bounded production Main -> HUD probe for workforce classification and the
## no-villager recovery prompt. Mutated units/resources are explicitly fixtures.

const REPORT_PATH := "user://workforce_feedback_probe.json"
const Catalog := preload("res://scripts/building_catalog.gd")
const BuildingScript := preload("res://scripts/building.gd")
const VillagerScript := preload("res://scripts/villager.gd")
const SoldierScript := preload("res://scripts/soldier.gd")

var report: Dictionary = {
	"schema": 1, "passed": false, "steps": [], "injected_fixtures": [],
	"runtime": {"pid": OS.get_process_id(), "headless": DisplayServer.get_name() == "headless", "time_scale": Engine.time_scale, "executable": OS.get_executable_path(), "user_data_dir": OS.get_user_data_dir(), "engine": Engine.get_version_info().string}
}
var game: Node3D
var deadline_msec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless" or absf(Engine.time_scale - 1.0) > 0.001:
		_finish("requires_hidden_headless_unscaled_runtime")
		return
	deadline_msec = Time.get_ticks_msec() + 170000
	call_deferred("_run")

func _run() -> void:
	var menu := await _wait_for_menu(20.0)
	if menu == null:
		_finish("production_start_menu_not_found")
		return
	var mode: OptionButton = menu.get("_start_mode_select") as OptionButton
	var seed_field: LineEdit = menu.get("_seed_edit") as LineEdit
	var start_button: Button = menu.get("_start_begin_button") as Button
	if mode == null or seed_field == null or start_button == null:
		_finish("production_start_controls_missing")
		return
	mode.select(0)
	mode.item_selected.emit(0)
	seed_field.text = "518240"
	var menu_id := menu.get_instance_id()
	start_button.pressed.emit()
	game = await _wait_started_game(menu_id, 35.0)
	if game == null:
		_finish("production_menu_start_timeout")
		return
	await get_tree().create_timer(0.9).timeout
	var hud: Node = game.get("hud")
	if hud == null:
		_finish("production_hud_missing")
		return
	var villagers := _live_player_villagers()
	if villagers.size() != 5:
		_finish("unexpected_start_villager_count_%d" % villagers.size())
		return
	for worker in villagers:
		worker.call("command_stop")
	game.call("_refresh_pop")
	game.call("_refresh_operational_alerts")
	var initial: Dictionary = game.call("_workforce_assignment_summary")
	if not _counts_equal(initial, {"wood": 0, "food": 0, "idle": 5, "other": 0, "blocked": 0, "total": 5}):
		_finish("initial_idle_workforce_classification_mismatch")
		return
	var no_gather_button := _alert_button(hud, "workforce:no_gatherers")
	if no_gather_button == null:
		_finish("idle_worker_recovery_alert_missing")
		return
	var stable_row_id := no_gather_button.get_parent().get_instance_id()
	game.call("_refresh_operational_alerts")
	if _alert_button(hud, "workforce:no_gatherers").get_parent().get_instance_id() != stable_row_id:
		_finish("same_state_alert_row_was_rebuilt")
		return
	if not game.get("selected").is_empty():
		_finish("workforce_refresh_stole_selection")
		return
	no_gather_button.pressed.emit()
	await get_tree().process_frame
	if not villagers[0] in game.get("selected"):
		_finish("idle_worker_alert_did_not_select_worker")
		return
	game.call("_clear_selection")
	game.call("_refresh_selection_hud")

	var wood_node := _wood_node()
	if wood_node == null:
		_finish("natural_wood_target_missing")
		return
	var tc := _player_tc()
	if tc == null:
		_finish("player_town_center_missing")
		return
	# Controlled fixture: a paid farm with stock and a construction foundation.
	var farm: Node3D = BuildingScript.new()
	farm.setup(Catalog.FARM, Vector3(18.0, 0.0, 18.0), "player", true)
	farm.set("meat_stock", 300)
	farm.set("is_meat_source", true)
	farm.set("is_arid", false)
	game.get("world").add_child(farm)
	var foundation: Node3D = BuildingScript.new()
	foundation.setup(Catalog.HOUSE, Vector3(-18.0, 0.0, 18.0), "player", false)
	game.get("world").add_child(foundation)
	report["injected_fixtures"].append({"fixture": "farm_and_house_foundation", "farm_position": [18, 0, 18], "farm_stock": 300, "foundation_position": [-18, 0, 18]})

	# Two extra controlled villagers provide distinct simultaneous command states.
	for index in range(2):
		var extra: Node3D = VillagerScript.new()
		extra.setup(Vector3(24.0 + index * 2.0, 0.0, 24.0), "player")
		extra.deposited.connect(Callable(game, "_on_deposited"))
		game.get("world").add_child(extra)
	villagers = _live_player_villagers()
	if villagers.size() != 7:
		_finish("controlled_worker_fixture_spawn_mismatch")
		return
	var wood_worker: Node3D = villagers[0]
	var food_worker: Node3D = villagers[1]
	var return_worker: Node3D = villagers[2]
	var builder: Node3D = villagers[3]
	var mover: Node3D = villagers[4]
	var fighter: Node3D = villagers[5]
	var idle_worker: Node3D = villagers[6]
	if not _issue_gather_via_main(wood_worker, wood_node) or not _issue_gather_via_main(food_worker, farm):
		_finish("production_main_gather_order_not_issued")
		return
	if not await _wait_until(func(): return int(wood_worker.get("state")) == VillagerScript.State.GATHER and int(food_worker.get("state")) == VillagerScript.State.GATHER, 12.0):
		_finish("wood_or_food_gather_state_timeout")
		return
	# Make one carry-and-return state immediately without waiting for a full load;
	# actual return state machine and the source/carry key are retained.
	return_worker.call("command_gather", wood_node)
	return_worker.set("carry_key", "wood")
	return_worker.set("carry_amount", 4)
	return_worker.set("resume_key", "wood")
	return_worker.set("resume_resource", wood_node)
	return_worker.call("_start_return")
	builder.call("command_build", foundation)
	mover.call("command_move", Vector3(-20.0, 0.0, -16.0))
	var enemy: Node3D = SoldierScript.new()
	enemy.setup(Vector3(20.0, 0.0, -18.0), "enemy", true)
	game.get("world").add_child(enemy)
	fighter.call("command_attack_unit", enemy)
	report["injected_fixtures"].append({"fixture": "return_cargo_and_enemy_combat_target", "return_worker_instance": return_worker.get_instance_id(), "return_carry_key": "wood", "return_carry_amount": 4, "enemy_target_team": "enemy"})
	game.call("_refresh_operational_alerts")
	var mixed: Dictionary = game.call("_workforce_assignment_summary")
	var expected_mixed := {"wood": 2, "food": 1, "idle": 1, "other": 3, "blocked": 0, "total": 7}
	if not _counts_equal(mixed, expected_mixed):
		report["mixed_actual"] = mixed
		_finish("mixed_workforce_classification_mismatch")
		return
	var orders_before_refresh := villagers.map(func(worker): return _order_fingerprint(worker))
	if str(hud.get("_workforce_l").text) != "工人 木2 粮1 闲1 其他3 受阻0":
		_finish("hud_workforce_line_mismatch")
		return
	var workforce_label: Label = hud.get("_workforce_l")
	var op_panel: Control = hud.get("_operational_panel")
	var layout_separated: bool = workforce_label.get_global_rect().end.y <= op_panel.get_global_rect().position.y
	if not layout_separated:
		_finish("headless_hud_workforce_line_overlaps_alert_panel")
		return
	if not await _wait_until(func(): return orders_before_refresh == villagers.map(func(worker): return _order_fingerprint(worker)), 0.25):
		_finish("workforce_refresh_rewrote_existing_orders")
		return
	report["steps"].append({"step": "main_to_hud_classified_gather_return_build_move_combat_idle", "expected": expected_mixed, "actual": mixed, "summary_text": workforce_label.text, "stable_alert_row": true, "refresh_preserved_selection": true, "refresh_preserved_orders": true, "headless_control_bounds_do_not_overlap": layout_separated})

	# The dry-farm intent is blocked rather than idle; carrying workers retain
	# their resource assignment even if their source later dries out.
	farm.set("is_arid", true)
	farm.set("is_meat_source", false)
	farm.set("meat_stock", 0)
	game.call("_refresh_operational_alerts")
	var dry: Dictionary = game.call("_workforce_assignment_summary")
	if int(dry.get("blocked", 0)) != 1 or int(dry.get("idle", 0)) != 1 or _alert_button(hud, "farm:%s" % str(farm.get_instance_id())) == null or _alert_button(hud, "workforce:no_food_gatherers") == null:
		report["dry_farm_actual"] = dry
		_finish("depleted_farm_not_distinguished_from_idle")
		return
	report["steps"].append({"step": "dry_food_source_alert_distinguished_from_zero_food_workers", "blocked_workers": int(dry.get("blocked", 0)), "idle_workers": int(dry.get("idle", 0)), "zero_food_alert_present": true})
	idle_worker.call("command_stop")
	game.call("_refresh_operational_alerts")
	var no_target: Dictionary = game.call("_workforce_assignment_summary")
	if int(no_target.get("idle", 0)) != 1 or int(no_target.get("blocked", 0)) != 1:
		_finish("true_no_target_and_depleted_intent_collapsed")
		return
	report["steps"].append({"step": "depleted_target_separated_from_true_idle", "actual": no_target, "existing_dry_farm_alert_present": true})

	# Save and restore the production match in place; HUD counts are recomputed
	# from rebuilt node references rather than retaining the old target objects.
	# Re-prime the returning carrier far enough from the TC that the bounded
	# save/restore handoff cannot finish the trip before the snapshot is read.
	return_worker.position = Vector3(48.0, 0.0, 48.0)
	return_worker.set("carry_key", "wood")
	return_worker.set("carry_amount", 4)
	return_worker.set("resume_key", "wood")
	return_worker.set("resume_resource", wood_node)
	return_worker.set("gather_target", null)
	return_worker.call("_start_return")
	var before_restore: Dictionary = game.call("_workforce_assignment_summary")
	var old_worker_ids: Array = villagers.map(func(worker): return worker.get_instance_id())
	var save_ok: bool = bool(game.call("_save_match"))
	if not save_ok:
		_finish("production_save_failed")
		return
	var old_game_id := game.get_instance_id()
	game.call("_continue_saved_match")
	if not await _wait_until(func(): return is_instance_valid(game) and game.get_instance_id() == old_game_id and not bool(game.get("_start_operation_busy")), 15.0):
		_finish("production_in_place_restore_timeout")
		return
	await get_tree().process_frame
	var restored_workers := _live_player_villagers()
	var after_restore: Dictionary = game.call("_workforce_assignment_summary")
	var stale_worker_refs := false
	for worker in restored_workers:
		if old_worker_ids.has(worker.get_instance_id()):
			stale_worker_refs = true
	var restored_return: Node = _worker_with_state(VillagerScript.State.RETURN_DROP)
	var restored_targets_live := restored_return != null and is_instance_valid(restored_return.get("drop_target")) and is_instance_valid(restored_return.get("resume_resource"))
	if not _counts_equal(after_restore, before_restore) or stale_worker_refs or not restored_targets_live:
		report["restore_before"] = before_restore
		report["restore_after"] = after_restore
		report["stale_worker_refs"] = stale_worker_refs
		report["restored_return_targets_live"] = restored_targets_live
		report["restored_villagers"] = restored_workers.map(func(worker): return {"state": int(worker.get("state")), "carry_key": str(worker.get("carry_key")), "carry": int(worker.get("carry_amount")), "resume_key": str(worker.get("resume_key")), "gather_valid": is_instance_valid(worker.get("gather_target")), "drop_valid": is_instance_valid(worker.get("drop_target")), "resume_valid": is_instance_valid(worker.get("resume_resource"))})
		_finish("workforce_restore_recompute_or_reference_failure")
		return
	game.call("_refresh_operational_alerts")
	var expected_restored_text := _summary_text(after_restore)
	if str(game.get("hud").get("_workforce_l").text) != expected_restored_text:
		report["restore_hud_text"] = str(game.get("hud").get("_workforce_l").text)
		report["restore_expected_hud_text"] = expected_restored_text
		_finish("hud_summary_not_recomputed_after_restore")
		return
	report["steps"].append({"step": "production_save_continue_recomputed_workforce", "before": before_restore, "after": after_restore, "old_worker_instances_replaced": true, "restored_return_targets_live": restored_targets_live})

	# Test zero-villager prompts with no TC, inadequate resources, inadequate
	# population, eligible recovery and a currently paid training slot.
	tc = _player_tc()
	if tc == null:
		_finish("town_center_reference_not_rebuilt_after_restore")
		return
	villagers = _live_player_villagers()
	var preloss_targets: Array = []
	for worker in villagers:
		preloss_targets.append({"node": worker, "orders": Array(worker.get("order_queue")).duplicate(true)})
		worker.set("alive", false)
		worker.queue_free()
	game.call("_refresh_pop")
	game.set("meat", 49)
	game.call("_update_hud")
	tc.set("alive", false)
	game.call("_refresh_operational_alerts")
	var no_tc_button := _alert_button(hud, "workforce:no_villagers_no_tc")
	if no_tc_button == null or not no_tc_button.disabled or not str(hud.get("_operational_label_by_key").get("workforce:no_villagers_no_tc").text).contains("已失守"):
		_finish("zero_villager_no_tc_state_not_explained")
		return
	tc.set("alive", true)
	var pop_bonus_before := int(tc.get("pop_bonus"))
	var pop_bonus_snapshot: Array = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and str(building.get("team")) == "player":
			pop_bonus_snapshot.append({"node": building, "value": int(building.get("pop_bonus"))})
			building.set("pop_bonus", 0)
	game.call("_refresh_pop")
	game.call("_refresh_operational_alerts")
	if _alert_button(hud, "workforce:no_villagers_shortage_both") == null:
		_finish("resource_and_population_shortages_not_distinguished")
		return
	for saved_bonus in pop_bonus_snapshot:
		if is_instance_valid(saved_bonus.get("node")):
			saved_bonus["node"].set("pop_bonus", int(saved_bonus.get("value")))
	if int(tc.get("pop_bonus")) != pop_bonus_before:
		_finish("population_capacity_fixture_restore_mismatch")
		return
	game.call("_refresh_pop")
	game.call("_refresh_operational_alerts")
	if _alert_button(hud, "workforce:no_villagers_resources") == null:
		_finish("resource_shortage_recovery_message_missing")
		return
	game.set("meat", 100)
	for saved_bonus in pop_bonus_snapshot:
		if is_instance_valid(saved_bonus.get("node")):
			saved_bonus["node"].set("pop_bonus", 0)
	game.call("_refresh_pop")
	game.call("_refresh_operational_alerts")
	if _alert_button(hud, "workforce:no_villagers_population") == null:
		_finish("population_shortage_recovery_message_missing")
		return
	for saved_bonus in pop_bonus_snapshot:
		if is_instance_valid(saved_bonus.get("node")):
			saved_bonus["node"].set("pop_bonus", int(saved_bonus.get("value")))
	game.call("_refresh_pop")
	game.call("_update_hud")
	game.call("_refresh_operational_alerts")
	var recruit_button := _alert_button(hud, "workforce:no_villagers_recruit")
	if recruit_button == null or recruit_button.get_meta("operational_alert_target", null) != tc:
		_finish("eligible_recovery_tc_locator_missing")
		return
	var queue_before: Array = Array(tc.get("train_queue")).duplicate()
	var meat_before_order := int(game.get("meat"))
	# Refreshing the prompt and selecting its locator must neither spend nor queue.
	game.call("_refresh_operational_alerts")
	if int(game.get("meat")) != meat_before_order or Array(tc.get("train_queue")) != queue_before:
		_finish("recovery_prompt_automatically_changed_economy")
		return
	recruit_button.pressed.emit()
	await get_tree().process_frame
	if not tc in game.get("selected") or int(game.get("meat")) != meat_before_order or Array(tc.get("train_queue")) != queue_before:
		_finish("recovery_locator_selection_or_nonpayment_failed")
		return
	var train_button: Button = hud.get("_cmd_btns").get("train") as Button
	if train_button == null or not train_button.visible:
		_finish("selected_tc_villager_train_button_missing")
		return
	train_button.pressed.emit()
	var paid_queue: Array = Array(tc.get("train_queue")).duplicate()
	var paid_after := int(game.get("meat"))
	if paid_queue != ["villager"] or meat_before_order - paid_after != 50 or not bool(tc.get("train_paid")):
		_finish("production_villager_training_did_not_charge_50")
		return
	game.call("_refresh_operational_alerts")
	var training_button := _alert_button(hud, "workforce:no_villagers_training")
	if training_button == null or not str(hud.get("_operational_label_by_key").get("workforce:no_villagers_training").text).contains("付费训练中"):
		_finish("paid_training_status_not_reported")
		return
	report["steps"].append({"step": "zero_villager_recovery_locator_and_actual_paid_training", "no_tc_explained": true, "resource_and_population_shortages_distinguished": true, "eligible_prompt_did_not_spend_or_queue": true, "locator_selected_tc_without_order": true, "paid_queue": paid_queue, "meat_before": meat_before_order, "meat_after": paid_after, "paid_training_prompt": str(hud.get("_operational_label_by_key").get("workforce:no_villagers_training").text)})

	var trained := await _wait_live_villager_count(1, 28.0)
	if trained == null:
		report["training_timeout_state"] = {"queue": Array(tc.get("train_queue")), "paid": bool(tc.get("train_paid")), "timer": float(tc.get("train_timer")), "duration": float(tc.get("train_duration")), "population": int(game.get("population")), "pop_cap": int(game.get("pop_cap"))}
		_finish("paid_recovery_villager_completion_timeout")
		return
	var fresh_meat_before := int(game.get("meat"))
	var target_wood := _wood_node()
	if target_wood == null or not _issue_gather_via_main(trained, target_wood):
		_finish("recovered_villager_gather_order_missing")
		return
	var resource_before := int(target_wood.get("amount"))
	var harvest_deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < harvest_deadline and int(game.get("wood")) <= 0 and int(target_wood.get("amount")) == resource_before:
		await get_tree().create_timer(0.2).timeout
	# Wait through a deposit cycle; command and target remain production nodes.
	while Time.get_ticks_msec() < harvest_deadline and int(game.get("wood")) <= 0:
		await get_tree().create_timer(0.2).timeout
	var harvested_wood := int(game.get("wood"))
	var resource_after := int(target_wood.get("amount")) if is_instance_valid(target_wood) else -1
	if harvested_wood <= 0 or resource_after >= resource_before:
		report["recovery_yield"] = {"wood_before": 0, "wood_after": harvested_wood, "node_stock_before": resource_before, "node_stock_after": resource_after}
		_finish("recovered_villager_did_not_gather_and_deposit")
		return
	report["steps"].append({"step": "paid_recovered_villager_gathered_and_deposited", "paid_meat": 50, "meat_after_payment": paid_after, "meat_before_harvest": fresh_meat_before, "wood_after": harvested_wood, "resource_stock_before": resource_before, "resource_stock_after": resource_after})
	report["passed"] = true
	_finish("")

func _issue_gather_via_main(worker: Node, target: Node3D) -> bool:
	game.call("_clear_selection")
	game.call("_add_to_selection", worker)
	game.call("_on_cmd_gather")
	game.call("_route_pending_command", target.global_position)
	return worker.get("gather_target") == target or str(worker.get("resume_key")) == str(target.call("res_key")) or target.is_in_group("farms")

func _counts_equal(actual: Dictionary, expected: Dictionary) -> bool:
	for key in expected:
		if int(actual.get(key, -999)) != int(expected[key]):
			return false
	return true

func _summary_text(summary: Dictionary) -> String:
	return "工人 木%d 粮%d 闲%d 其他%d 受阻%d" % [int(summary.get("wood", 0)), int(summary.get("food", 0)), int(summary.get("idle", 0)), int(summary.get("other", 0)), int(summary.get("blocked", 0))]

func _order_fingerprint(worker: Node) -> Dictionary:
	return {"state": int(worker.get("state")), "gather": worker.get("gather_target").get_instance_id() if is_instance_valid(worker.get("gather_target")) else 0, "resume": worker.get("resume_resource").get_instance_id() if is_instance_valid(worker.get("resume_resource")) else 0, "resume_key": str(worker.get("resume_key")), "drop": worker.get("drop_target").get_instance_id() if is_instance_valid(worker.get("drop_target")) else 0, "build": worker.get("build_site").get_instance_id() if is_instance_valid(worker.get("build_site")) else 0, "attack": worker.get("attack_target").get_instance_id() if is_instance_valid(worker.get("attack_target")) else 0, "queue": Array(worker.get("order_queue")).duplicate(true)}

func _live_player_villagers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for worker in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(worker) and worker.is_inside_tree() and bool(worker.get("alive")) and str(worker.get("team")) == "player":
			result.append(worker)
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

func _alert_button(hud: Node, key: String) -> Button:
	var by_key: Dictionary = hud.get("_operational_button_by_key")
	var button: Variant = by_key.get(key)
	return button as Button if is_instance_valid(button) and not button.is_queued_for_deletion() else null

func _worker_with_state(wanted_state: int) -> Node:
	for worker in _live_player_villagers():
		if int(worker.get("state")) == wanted_state:
			return worker
	return null

func _wait_live_villager_count(count: int, seconds: float) -> Node:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		var workers := _live_player_villagers()
		if workers.size() == count:
			return workers[0] if count > 0 else null
	return null

func _wait_for_menu(seconds: float) -> Node:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		var main := get_tree().root.get_node_or_null("Main")
		if main != null and main.get("_start_layer") != null:
			return main
	return null

func _wait_started_game(old_menu_id: int, seconds: float) -> Node3D:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		var main := get_tree().root.get_node_or_null("Main")
		if main != null and main.get_instance_id() == old_menu_id and bool(main.get("_match_started")):
			return main
	return null

func _wait_until(predicate: Callable, seconds: float) -> bool:
	var end_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_at and Time.get_ticks_msec() < deadline_msec:
		if predicate.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return bool(predicate.call())

func _finish(error_text: String) -> void:
	if not error_text.is_empty():
		report["error"] = error_text
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[workforce_feedback_probe] ", JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("passed")) else 1)
