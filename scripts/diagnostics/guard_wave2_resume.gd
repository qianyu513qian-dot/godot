extends Node
## Continue an actual wave-1 production save, persist both Guard and A-move intents,
## Continue again, then observe the naturally timed second wave.
const Catalog := preload("res://scripts/building_catalog.gd")
const REPORT_PATH := "user://guard_wave2_resume.json"
const WALL_LIMIT := 480.0
var _started := 0
var _last_write := 0
var _done := false
var _report: Dictionary = {"schema": 1, "scope": "continue_saved_wave1_guard_and_a_move_then_natural_wave2", "headless": true, "time_scale": Engine.time_scale, "events": [], "checkpoints": [], "samples": [], "save_continue": {}, "complete": false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started = Time.get_ticks_msec()
	_last_write = _started
	call_deferred("_run")

func _process(_delta: float) -> void:
	if _done:
		return
	if _seconds() > WALL_LIMIT:
		_finish(false, "wall_clock_bound_exceeded")
	elif Time.get_ticks_msec() - _last_write >= 3000:
		_last_write = Time.get_ticks_msec()
		_persist()

func _run() -> void:
	if DisplayServer.get_name() != "headless" or absf(Engine.time_scale - 1.0) > 0.001:
		_finish(false, "headless_unscaled_required")
		return
	var menu := await _wait_menu(40.0)
	if menu == null:
		_finish(false, "start_menu_not_ready")
		return
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish(false, "saved_match_continue_button_unavailable")
		return
	var source_save := _read_json("user://aoelite3d_save.json")
	var source_resources: Dictionary = source_save.get("resources", {})
	var source_barracks_queue := _saved_queue(source_save)
	_report["source_save"] = {"seed": int(source_save.get("map_seed", -1)), "mode": int(source_save.get("horde_mode", -1)), "game_time": float(source_save.get("game_time", -1.0)), "wave": int(source_save.get("horde_wave", -1)), "resources": source_resources, "barracks_queue": source_barracks_queue, "guard_entities": _saved_guard_intents(source_save), "a_move_entities": _saved_a_move_intents(source_save), "entity_count": Array(source_save.get("entities", {}).get("soldiers", [])).size()}
	var old_id := menu.get_instance_id()
	continue_button.pressed.emit()
	_report["events"].append({"event": "start_menu_continue_button_pressed", "route": "production Continue Button.pressed signal", "button_text": continue_button.text})
	var game := await _wait_new_game(old_id, 90.0)
	if game == null:
		_finish(false, "start_menu_continue_restore_timeout")
		return
	_report["runtime"] = {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/guard_wave2_resume.gd", "user_data_dir": OS.get_user_data_dir()}
	var guard := _find_guard()
	var barracks := _building(Catalog.BARRACKS)
	var a_unit := _find_a_move()
	_report["after_menu_continue"] = _snapshot(game, guard, a_unit, barracks)
	_checkpoint("real_start_menu_continue_restored_wave_1_save", game)
	if int(game.get("_horde_wave")) < 1 or guard == null or not bool(guard.get("guard_active")) or not is_instance_valid(guard.get("attack_target")):
		_finish(false, "menu_continue_did_not_restore_active_guard_combat")
		return
	if not _train_queue(barracks).is_empty() and a_unit == null:
		# The previously saved A-move had naturally finished; issue a fresh player A-move to a living paid soldier before making the audit save.
		a_unit = _find_other_soldier(guard)
	if a_unit == null:
		a_unit = _find_other_soldier(guard)
	if a_unit == null:
		_finish(false, "no_second_paid_soldier_survived_for_a_move_restore")
		return
	var goal := a_unit.global_position + Vector3(0, 0, -18.0)
	if not await _issue_a_move(game, a_unit, goal):
		_finish(false, "production_a_move_order_failed")
		return
	_report["events"].append({"event": "a_move_issued_during_live_wave_1_guard_combat", "unit": str(a_unit.name), "goal": _v3(goal), "guard_target": str(guard.get("attack_target").name), "game_time": float(game.get("_game_time"))})
	var before := _snapshot(game, guard, a_unit, barracks)
	var old_game_id := game.get_instance_id()
	await _send_key(KEY_F5)
	var audit_save := _read_json("user://aoelite3d_save.json")
	_report["save_continue"]["serialized_orders"] = {"guard": _saved_guard_intents(audit_save), "a_move": _saved_a_move_intents(audit_save), "barracks_queue": _saved_queue(audit_save), "resources": audit_save.get("resources", {})}
	_report["save_continue"]["before"] = before
	_report["events"].append({"event": "f5_during_guard_combat_with_a_move_and_waiting_queue", "game_time": float(game.get("_game_time")), "wave": int(game.get("_horde_wave")), "enemy_count": _enemy_count()})
	await _send_key(KEY_F9)
	game = await _wait_new_game(old_game_id, 60.0)
	if game == null:
		_finish(false, "f9_continue_reload_timeout")
		return
	guard = _find_guard()
	a_unit = _find_a_move()
	barracks = _building(Catalog.BARRACKS)
	var after := _snapshot(game, guard, a_unit, barracks)
	var restored := _matches(before, after)
	_report["save_continue"]["after"] = after
	_report["save_continue"]["restored"] = restored
	_checkpoint("f9_continue_restored_guard_a_queue_resources_wave", game)
	if not restored:
		_finish(false, "f9_continue_state_mismatch")
		return
	var wave2_seen := await _wait_wave(game, 2, 180.0)
	if not wave2_seen:
		if bool(game.get("_defeated")):
			_report["outcome"] = {"result": "defeat_before_wave_2", "snapshot": _world_snapshot(game)}
			await _retry_or_return(game)
			_finish(true, "restore_verified_but_defeated_before_second_wave")
		else:
			_finish(false, "natural_wave_2_timeout")
		return
	game = get_tree().get_first_node_in_group("main_game")
	_checkpoint("natural_wave_2_spawned_after_combat_continue", game)
	var wave2 := await _observe_wave2(game, 240.0)
	_report["outcome"] = wave2
	if bool(wave2.get("defeated", false)):
		game = get_tree().get_first_node_in_group("main_game")
		await _retry_or_return(game)
	else:
		game = get_tree().get_first_node_in_group("main_game")
		await _return_to_menu(game)
	_finish(true, "wave_2_observed_after_production_continue")

func _issue_a_move(game: Node, unit: Node3D, goal: Vector3) -> bool:
	game.call("_clear_selection")
	game.call("_add_to_selection", unit)
	game.call("_refresh_selection_hud")
	await _send_key(KEY_A)
	var mode := str(game.get("_cmd_mode"))
	game.call("_route_pending_command", goal, Vector2.ZERO)
	game.set("_cmd_mode", "")
	await get_tree().process_frame
	_report["events"].append({"event": "production_a_move_dispatch", "pending_mode": mode, "active": bool(unit.get("_attack_move_active")), "goal": _v3(unit.get("_attack_move_goal"))})
	return bool(unit.get("_attack_move_active"))

func _wait_menu(limit: float) -> Node:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(limit * 1000.0):
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and game.get("_start_layer") != null:
			return game
		await get_tree().process_frame
	return null

func _wait_new_game(old_id: int, limit: float) -> Node:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(limit * 1000.0):
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and game.get_instance_id() != old_id and bool(game.get("_match_started")):
			return game
		await get_tree().process_frame
	return null

func _wait_wave(game: Node, wave: int, limit: float) -> bool:
	var start := Time.get_ticks_msec()
	var last_game_checkpoint := -1.0
	while Time.get_ticks_msec() - start < int(limit * 1000.0):
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			return false
		var now := float(game.get("_game_time"))
		if int(game.get("_horde_wave")) >= wave:
			return true
		if now >= last_game_checkpoint + 10.0:
			last_game_checkpoint = now
			_checkpoint("natural_game_clock_waiting_wave_%d" % wave, game)
		if bool(game.get("_defeated")):
			return false
		await get_tree().process_frame
	return false

func _observe_wave2(game: Node, limit: float) -> Dictionary:
	var start := Time.get_ticks_msec()
	var last_sample_time := -1.0
	while Time.get_ticks_msec() - start < int(limit * 1000.0):
		game = get_tree().get_first_node_in_group("main_game")
		if game == null:
			return {"result": "main_scene_missing"}
		var now := float(game.get("_game_time"))
		if now >= last_sample_time + 5.0:
			last_sample_time = now
			_report["samples"].append(_world_snapshot(game))
			_persist()
		var alive := _enemy_count()
		if bool(game.get("_defeated")):
			return {"result": "defeat_during_wave_2", "defeated": true, "snapshot": _world_snapshot(game)}
		if int(game.get("_horde_wave")) >= 2 and not bool(game.get("_horde_active")) and alive == 0 and Array(game.get("_horde_spawn_queue")).is_empty():
			return {"result": "wave_2_cleared", "defeated": false, "snapshot": _world_snapshot(game)}
		await get_tree().process_frame
	return {"result": "bounded_wave_2_observation", "defeated": false, "snapshot": _world_snapshot(game)}

func _snapshot(game: Node, guard: Node, a_unit: Node, barracks: Node) -> Dictionary:
	return {"seed": int(game.get("map_seed")), "mode": int(game.get("_horde_mode")), "game_time": float(game.get("_game_time")), "next_wave_at": float(game.get("_horde_next_at")), "wave": int(game.get("_horde_wave")), "wave_active": bool(game.get("_horde_active")), "enemy_count": _enemy_count(), "wood": int(game.get("wood")), "meat": int(game.get("meat")), "stone": int(game.get("stone")), "gold": int(game.get("gold")), "guard_active": bool(guard.get("guard_active")) if is_instance_valid(guard) else false, "guard_state": int(guard.get("state")) if is_instance_valid(guard) else -1, "guard_anchor": _v3(guard.get("guard_anchor")) if is_instance_valid(guard) else [], "guard_in_combat": is_instance_valid(guard.get("attack_target")) if is_instance_valid(guard) else false, "a_move_active": bool(a_unit.get("_attack_move_active")) if is_instance_valid(a_unit) else false, "a_move_goal": _v3(a_unit.get("_attack_move_goal")) if is_instance_valid(a_unit) else [], "queue": _train_queue(barracks), "train_paid": bool(barracks.get("train_paid")) if is_instance_valid(barracks) else false, "train_paused": bool(barracks.get("train_paused")) if is_instance_valid(barracks) else false, "soldiers_alive": _player_soldiers().size(), "town_center_hp": _building_hp(Catalog.TOWN_CENTER)}

func _matches(before: Dictionary, after: Dictionary) -> bool:
	return before.seed == after.seed and before.mode == after.mode and before.wave == after.wave and before.wave_active == after.wave_active and before.enemy_count == after.enemy_count and before.wood == after.wood and before.meat == after.meat and before.stone == after.stone and before.gold == after.gold and before.guard_active and after.guard_active and before.guard_anchor == after.guard_anchor and before.a_move_active and after.a_move_active and before.a_move_goal == after.a_move_goal and before.queue == after.queue and before.train_paid == after.train_paid and before.train_paused == after.train_paused and before.soldiers_alive == after.soldiers_alive

func _find_guard() -> Node3D:
	for unit in _player_soldiers():
		if bool(unit.get("guard_active")):
			return unit as Node3D
	return null

func _find_a_move() -> Node3D:
	for unit in _player_soldiers():
		if bool(unit.get("_attack_move_active")):
			return unit as Node3D
	return null

func _find_other_soldier(except_unit: Node) -> Node3D:
	for unit in _player_soldiers():
		if unit != except_unit:
			return unit as Node3D
	return null

func _player_soldiers() -> Array:
	return get_tree().get_nodes_in_group("military").filter(func(unit): return is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("alive")))

func _building(kind: int) -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == kind and bool(building.get("is_complete")):
			return building as Node3D
	return null

func _train_queue(barracks: Variant) -> Array:
	if not is_instance_valid(barracks):
		return []
	return Array(barracks.get("train_queue")).duplicate(true)

func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("zombies").filter(func(enemy): return is_instance_valid(enemy) and bool(enemy.get("alive"))).size()

func _building_hp(kind: int) -> float:
	var building := _building(kind)
	return float(building.get("hp")) if building != null else -1.0

func _world_snapshot(game: Node) -> Dictionary:
	return {"wall_elapsed_seconds": _seconds(), "game_time": float(game.get("_game_time")), "next_wave_at": float(game.get("_horde_next_at")), "wave": int(game.get("_horde_wave")), "wave_active": bool(game.get("_horde_active")), "enemy_count": _enemy_count(), "soldiers": _player_soldiers().map(func(unit): return {"hp": float(unit.get("hp")), "guard_active": bool(unit.get("guard_active")), "attack_move_active": bool(unit.get("_attack_move_active")), "state": int(unit.get("state"))}), "queue": _train_queue(_building(Catalog.BARRACKS)), "wood": int(game.get("wood")), "meat": int(game.get("meat")), "town_center_hp": _building_hp(Catalog.TOWN_CENTER), "defeated": bool(game.get("_defeated"))}

func _saved_queue(payload: Dictionary) -> Array:
	for building in payload.get("entities", {}).get("buildings", []):
		if str(building.get("team", "")) == "player" and int(building.get("kind", -1)) == Catalog.BARRACKS:
			return Array(building.get("train_queue", [])).duplicate(true)
	return []

func _saved_guard_intents(payload: Dictionary) -> Array:
	return Array(payload.get("entities", {}).get("soldiers", [])).filter(func(unit): return str(unit.get("team", "")) == "player" and bool(unit.get("guard_active", false))).map(func(unit): return {"guard_active": true, "anchor": unit.get("guard_anchor", []), "state": int(unit.get("state", -1))})

func _saved_a_move_intents(payload: Dictionary) -> Array:
	return Array(payload.get("entities", {}).get("soldiers", [])).filter(func(unit): return str(unit.get("team", "")) == "player" and bool(unit.get("attack_move_active", false))).map(func(unit): return {"active": true, "goal": unit.get("attack_move_goal", [])})

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}

func _send_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _retry_or_return(game: Node) -> void:
	var retry := _find_button(game.get("hud"), "再来一局")
	if retry != null:
		retry.pressed.emit()
		_report["events"].append({"event": "production_retry_pressed_after_defeat"})
	else:
		await _return_to_menu(game)

func _return_to_menu(game: Node) -> void:
	if game == null:
		return
	await _send_key(KEY_ESCAPE)
	var button := _find_button(game.get("_pause_layer"), "返回主菜单")
	if button != null:
		button.pressed.emit()
		_report["events"].append({"event": "production_return_to_menu_pressed"})

func _find_button(root: Node, fragment: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.is_visible_in_tree() and button.text.contains(fragment):
			return button
	return null

func _checkpoint(label: String, game: Node) -> void:
	_report["checkpoints"].append({"label": label, "snapshot": _world_snapshot(game)})
	_persist()

func _seconds() -> float:
	return float(Time.get_ticks_msec() - _started) / 1000.0

func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _persist() -> void:
	_report["wall_elapsed_seconds"] = _seconds()
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()

func _finish(ok: bool, reason: String) -> void:
	if _done:
		return
	_done = true
	_report["complete"] = true
	_report["result"] = {"passed": ok, "reason": reason}
	_persist()
	print(JSON.stringify(_report))
	get_tree().quit(0 if ok else 1)
