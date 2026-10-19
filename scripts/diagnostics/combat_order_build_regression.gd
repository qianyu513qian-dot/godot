extends Node
## Focused live-match regression for Attack dispatch during a paid construction await.

const ControllerScript := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const Catalog := preload("res://scripts/building_catalog.gd")
const RESULT_PATH := "user://combat_order_build_regression.json"
const WALL_LIMIT_MSEC := 180000

var events: Array[Dictionary] = []
var controller: Node
var build_task_done := false
var started_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at = Time.get_ticks_msec()
	call_deferred("_run")

func _run() -> void:
	var save_path := "user://aoelite3d_save.json"
	if not FileAccess.file_exists(save_path):
		_finish(false, "production_save_missing")
		return
	var save_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not save_data is Dictionary or int(save_data.get("map_seed", -1)) != 42 or int(save_data.get("horde_mode", -1)) != 1:
		_finish(false, "production_save_not_challenge5_seed42")
		return
	var menu := _main_game()
	if menu == null or menu.get("_start_layer") == null:
		_finish(false, "production_start_menu_missing")
		return
	var menu_id := int(menu.get_instance_id())
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish(false, "production_continue_button_unavailable")
		return
	continue_button.pressed.emit()
	events.append({"action":"production_continue_pressed","route":"start menu Continue Button.pressed","saved_game_time":float(save_data.get("game_time", 0.0))})
	var game: Node
	while _within_wall_limit():
		await get_tree().process_frame
		game = _main_game()
		if game != null and int(game.get_instance_id()) != menu_id and bool(game.get("_match_started")) and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 1 and float(game.get("_game_time")) >= float(save_data.get("game_time", 0.0)) - 0.1:
			break
	if game == null or not bool(game.get("_match_started")):
		_finish(false, "production_continue_restore_timeout_or_scene_lost")
		return
	var resumed_id := int(game.get_instance_id())
	events.append({"action":"same_match_restored","game_time":float(game.get("_game_time")),"seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode"))})
	# Wait for the next natural live wave. This uses only the saved units and the
	# game's ordinary spawn timer, so no synthetic enemies or orders are injected.
	while _within_wall_limit() and int(game.get("_horde_wave")) < 2:
		await get_tree().process_frame
		if not _same_live_game(game, resumed_id):
			_finish(false, "same_match_scene_lost_before_wave2")
			return
	while _within_wall_limit() and (not bool(game.get("_horde_active")) or _living_enemies().is_empty()):
		await get_tree().process_frame
		if not _same_live_game(game, resumed_id):
			_finish(false, "same_match_scene_lost_waiting_for_wave2_enemies")
			return
	if not _within_wall_limit():
		_finish(false, "wall_clock_limit_waiting_for_natural_wave2")
		return

	controller = ControllerScript.new()
	controller.name = "CombatOrderBuildRegressionController"
	controller.set_process(false)
	get_tree().root.add_child(controller)
	await get_tree().process_frame
	controller.phase = "defend"
	controller.old_game_id = resumed_id
	controller.original_seed = 42
	controller.last_game = game
	controller.campaign_command_reason = "focused regression: actual paid house build awaits while wave2 is active"
	var optional_tower_allowed := bool(controller.call("_can_build_optional_tower", game))
	events.append({"action":"optional_tower_safety_gate","wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"live_enemies":_living_enemies().size(),"allowed":optional_tower_allowed,"expected_allowed":false})
	var candidates: Array[Vector3] = [Vector3(0, 0, 16), Vector3(8, 0, 16), Vector3(-14, 0, 8), Vector3(8, 0, 16)]
	var house_cost := int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 50))
	events.append({"action":"paid_build_budget_precheck","wood":int(game.get("wood")),"wood_cost":house_cost,"candidate_positions":candidates.map(func(p): return [p.x,p.y,p.z])})
	if int(game.get("wood")) < house_cost:
		_finish(false, "normal_house_build_site_or_budget_unavailable")
		return
	controller.busy = true
	controller.campaign_command_reason = "actual paid house construction await during wave2"
	controller.set_process(true)
	_start_house_build(game, candidates)
	while _within_wall_limit() and not build_task_done:
		await get_tree().process_frame
		if not _same_live_game(game, resumed_id):
			_finish(false, "same_match_scene_lost_during_construction_await")
			return
	if not build_task_done:
		_finish(false, "wall_clock_limit_during_construction_await")
		return
	controller.busy = false
	var interruption_index := -1
	for i in controller.events.size():
		if str(controller.events[i].get("action")) == "busy_wave_combat_interruption":
			interruption_index = i
			break
	var attack_order: Dictionary = {}
	if interruption_index >= 0:
		for i in range(interruption_index + 1, controller.events.size()):
			var row: Dictionary = controller.events[i]
			if str(row.get("action")) == "army_attack_order" and bool(row.get("accepted")):
				attack_order = row
				break
	var target_progress := false
	if not attack_order.is_empty():
		var target_name := str(attack_order.get("enemy", ""))
		var initial_hp := float(attack_order.get("enemy_hp", 0.0))
		var progress_deadline := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < progress_deadline and _within_wall_limit():
			var target := _find_enemy_by_name(target_name)
			if target == null or not bool(target.get("alive")) or float(target.get("hp")) < initial_hp:
				target_progress = true
				break
			await get_tree().process_frame
	var build_event: Dictionary = {}
	for row in controller.events:
		if str(row.get("action")) == "building_placed" and int(row.get("kind", -1)) == Catalog.HOUSE:
			build_event = row
			break
	var busy_attack_ok := interruption_index >= 0 and not attack_order.is_empty()
	var house_ok := not build_event.is_empty() and bool(build_event.get("accepted", false))
	events.append({"action":"busy_combat_and_paid_build_assertions","busy_attack_accepted":busy_attack_ok,"production_attack_order":attack_order,"target_damaged_or_killed":target_progress,"paid_house_placed":house_ok,"house_build":build_event,"tower_build_allowed_during_active_wave":optional_tower_allowed,"controller_event_count":controller.events.size()})
	var ok := busy_attack_ok and target_progress and house_ok and not optional_tower_allowed
	_finish(ok, "production_continue_paid_house_await_busy_attack_and_tower_gate_verified" if ok else "focused_combat_build_assertion_failed")

func _start_house_build(game: Node, candidates: Array[Vector3]) -> void:
	await controller.call("_build_at", game, Catalog.HOUSE, "房屋", candidates)
	controller.busy = false
	build_task_done = true

func _main_game() -> Node:
	return get_tree().get_first_node_in_group("main_game")

func _living_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy_units").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")) and float(n.get("hp")) > 0.0)

func _find_enemy_by_name(enemy_name: String) -> Node3D:
	for enemy in _living_enemies():
		if str(enemy.name) == enemy_name:
			return enemy as Node3D
	return null

func _same_live_game(game: Node, expected_id: int) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and int(game.get_instance_id()) == expected_id and bool(game.get("_match_started")) and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 1

func _within_wall_limit() -> bool:
	return Time.get_ticks_msec() - started_at < WALL_LIMIT_MSEC

func _finish(ok: bool, reason: String) -> void:
	var data := {"run_id":"combat_order_build_regression","success":ok,"reason":reason,"wall_elapsed_msec":Time.get_ticks_msec()-started_at,"events":events,"controller_events":controller.events if is_instance_valid(controller) else [],"runtime":{"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_data_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name()=="headless"}}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	print("[combat_order_build_regression] ", JSON.stringify({"success":ok,"reason":reason,"path":RESULT_PATH,"wall_elapsed_msec":data.wall_elapsed_msec}))
	get_tree().quit(0 if ok else 1)
