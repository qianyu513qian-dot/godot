extends Node

const SoldierScript := preload("res://scripts/soldier.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		_finish(false, "headless_required")
		return
	var game: Node = null
	for _frame in range(600):
		game = get_tree().get_first_node_in_group("main_game")
		if game != null and game.get("_start_layer") != null:
			break
		await get_tree().process_frame
	if game == null or game.get("_start_layer") == null:
		_finish(false, "start_scene_missing")
		return
	game.set("map_seed", 42)
	game.set("_horde_mode", 0)
	await game.call("_begin_match")
	for _frame in range(600):
		if bool(game.get("_match_started")) and game.get("world") != null:
			break
		await get_tree().process_frame
	if not bool(game.get("_match_started")):
		_finish(false, "match_start_failed")
		return
	var anchor := Vector3(8.0, 0.0, 8.0)
	var soldier: Node = SoldierScript.new()
	soldier.name = "Guard_Continue_Restore_Player"
	game.get("world").add_child(soldier)
	soldier.setup(anchor, "player", false)
	game.set("selected", [soldier])
	game.call("_refresh_selection_hud")
	var hotkey := InputEventKey.new()
	hotkey.keycode = KEY_F
	hotkey.pressed = true
	game.call("_unhandled_input", hotkey)
	var f_opened_guard_mode: bool = str(game.get("_cmd_mode")) == "guard"
	game.call("_route_pending_command", anchor)
	game.set("_cmd_mode", "")
	var hotkey_route_issued_guard: bool = bool(soldier.get("guard_active")) and soldier.get("guard_anchor").distance_to(anchor) < 0.05
	var hud: Node = game.get("hud")
	var command_buttons: Dictionary = hud.get("_cmd_btns") if hud != null else {}
	var guard_button: Button = command_buttons.get("guard") as Button
	if guard_button != null:
		guard_button.emit_signal("pressed")
	var button_opened_guard_mode: bool = str(game.get("_cmd_mode")) == "guard"
	var button_anchor := anchor + Vector3(1.0, 0.0, 0.0)
	game.call("_route_pending_command", button_anchor)
	game.set("_cmd_mode", "")
	var button_route_issued_guard: bool = guard_button != null and soldier.get("guard_anchor").distance_to(button_anchor) < 0.05
	soldier.command_move(anchor + Vector3(0.0, 0.0, 5.0), true)
	var saved_ok: bool = game.call("_save_match")
	var saved_guard: Dictionary = {}
	var f := FileAccess.open("user://aoelite3d_save.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			for item in parsed.get("entities", {}).get("soldiers", []):
				if str(item.get("team", "")) == "player" and bool(item.get("guard_active", false)):
					saved_guard = item
					break
	var old_id: int = game.get_instance_id()
	if not saved_ok or saved_guard.is_empty():
		_finish(false, "save_missing_guard_intent", {"save_ok": saved_ok, "soldier": saved_guard})
		return
	game.call_deferred("_continue_saved_match")
	var restored_game: Node = null
	for _frame in range(1800):
		var candidate: Node = get_tree().get_first_node_in_group("main_game")
		if candidate != null and candidate.get_instance_id() != old_id and bool(candidate.get("_match_started")):
			restored_game = candidate
			break
		await get_tree().process_frame
	var restored: Node = null
	if restored_game != null:
		for unit in get_tree().get_nodes_in_group("soldiers"):
			if is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("guard_active")):
				restored = unit
				break
	var expected_anchor: Vector3 = button_anchor
	var restored_ok: bool = restored_game != null and restored != null and int(restored.get("state")) == SoldierScript.State.GUARD and restored.get("guard_anchor").distance_to(expected_anchor) < 0.05 and Array(restored.get("order_queue")).size() == 1 and str(Array(restored.get("order_queue"))[0].get("k", "")) == "move"
	var event_route_ok: bool = f_opened_guard_mode and hotkey_route_issued_guard and button_opened_guard_mode and button_route_issued_guard
	report_guard_probe(restored_ok and event_route_ok, f_opened_guard_mode, hotkey_route_issued_guard, button_opened_guard_mode, button_route_issued_guard, saved_ok, saved_guard, restored_game, restored, old_id)

func report_guard_probe(passed: bool, f_opened: bool, f_issued: bool, button_opened: bool, button_issued: bool, saved_ok: bool, saved_guard: Dictionary, restored_game: Node, restored: Node, old_id: int) -> void:
	var report := {"passed": passed, "mode": "production_continue_guard_restore", "ordinary_mouse_ui_verified": false, "headless": true, "production_event_route": {"f_hotkey_opened_mode": f_opened, "map_dispatch_issued_guard": f_issued, "button_signal_opened_mode": button_opened, "button_to_map_dispatch_issued_guard": button_issued}, "pre_continue": {"save_ok": saved_ok, "saved_guard_active": bool(saved_guard.get("guard_active", false)), "saved_anchor": saved_guard.get("guard_anchor", []), "saved_queue": saved_guard.get("orders", [])}, "after_continue": {"new_main": restored_game != null and restored_game.get_instance_id() != old_id, "restored_guard": restored != null, "state": int(restored.get("state")) if restored != null else -1, "active": bool(restored.get("guard_active")) if restored != null else false, "anchor": [restored.get("guard_anchor").x, restored.get("guard_anchor").y, restored.get("guard_anchor").z] if restored != null else [], "queue": restored.get("order_queue") if restored != null else []}, "runtime": {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/guard_continue_restore_probe.gd", "user_data_dir": OS.get_user_data_dir()}}
	var out := FileAccess.open("user://guard_continue_restore_probe.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(report, "\t"))
		out.close()
	print(JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

func _finish(passed: bool, reason: String, extra: Dictionary = {}) -> void:
	print(JSON.stringify({"passed": passed, "reason": reason, "extra": extra, "user_data_dir": OS.get_user_data_dir()}))
	get_tree().quit(0 if passed else 1)
