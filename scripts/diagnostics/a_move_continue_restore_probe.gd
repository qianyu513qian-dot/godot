extends Node
## Full-scene headless integration for the production Continue -> reload -> restore path.
## This is a bounded order-state integration check, not a natural match.

const SoldierScript := preload("res://scripts/soldier.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const RESULT_PATH := "user://a_move_continue_restore_probe.json"

var report: Dictionary = {
	"mode": "production_a_move_continue_reload_restore",
	"ordinary_mouse_ui_verified": false,
	"headless": false,
}
var errors: Array[String] = []
var order_events: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	report["headless"] = DisplayServer.get_name() == "headless"
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
		_finish(false, "start_scene_not_ready")
		return
	game.set("map_seed", 42)
	game.set("_horde_mode", 0)
	report["start"] = {"seed": 42, "mode_id": 0, "route": "main._begin_match", "ordinary_start_menu_input_verified": false}
	await game.call("_begin_match")
	for _frame in range(600):
		if bool(game.get("_match_started")) and game.get("world") != null:
			break
		await get_tree().process_frame
	if not bool(game.get("_match_started")):
		_finish(false, "production_match_did_not_start")
		return

	var start := Vector3(-24.0, 0.0, 14.0)
	var a_destination := Vector3(-8.0, 0.0, 14.0)
	var queued_destination := Vector3(-8.0, 0.0, 21.0)
	var soldier: Node = SoldierScript.new()
	soldier.name = "A_Move_Save_Restore_Player"
	game.get("world").add_child(soldier)
	soldier.setup(start, "player", false)
	Pathfind.find_path(start, a_destination, get_tree())
	report["a_destination_path_diagnostics"] = Pathfind.last_path_report.duplicate(true)
	soldier.command_attack_move(a_destination)
	soldier.command_move(queued_destination, true)
	var start_position: Vector3 = soldier.global_position
	for _frame in range(60):
		if soldier.global_position.distance_to(start_position) > 1.0:
			break
		await get_tree().process_frame
	var target: Node = SoldierScript.new()
	target.name = "A_Move_Save_Restore_Enemy"
	game.get("world").add_child(target)
	target.setup(soldier.global_position + Vector3(4.0, 0.0, 0.0), "enemy", false)
	var auto_engaged := false
	for _frame in range(600):
		if int(soldier.get("state")) == SoldierScript.State.ATTACK and soldier.get("attack_target") == target and bool(soldier.get("_attack_move_active")) and not _near(soldier.get("_goal_final"), a_destination, 0.1):
			auto_engaged = true
			break
		await get_tree().process_frame
	if not auto_engaged:
		_finish(false, "player_never_entered_mid_a_move_auto_combat", {"position": _vec(soldier.global_position), "state": soldier.get("state"), "goal": _vec(soldier.get("_goal_final"))})
		return

	var old_game_id := game.get_instance_id()
	var save_ok: bool = game.call("_save_match")
	var save_data: Dictionary = {}
	if save_ok:
		var save_file := FileAccess.open("user://aoelite3d_save.json", FileAccess.READ)
		if save_file:
			var parsed: Variant = JSON.parse_string(save_file.get_as_text())
			if parsed is Dictionary:
				save_data = parsed
			save_file.close()
	var saved_soldier: Dictionary = {}
	for item in save_data.get("entities", {}).get("soldiers", []):
		if str(item.get("team", "")) == "player" and int(item.get("state", -1)) == SoldierScript.State.ATTACK and bool(item.get("attack_move_active", false)):
			saved_soldier = item
			break
	var pre_reload := {
		"save_ok": save_ok,
		"saved_combat_soldier_found": not saved_soldier.is_empty(),
		"saved_state": int(saved_soldier.get("state", -1)),
		"saved_a_intent": bool(saved_soldier.get("attack_move_active", false)),
		"saved_a_destination": saved_soldier.get("attack_move_goal", []),
		"saved_attack_target_id": str(saved_soldier.get("attack_id", "")),
		"saved_shift_queue_size": Array(saved_soldier.get("orders", [])).size(),
		"pre_reload_position": _vec(soldier.global_position),
	}
	report["pre_reload"] = pre_reload
	if not save_ok or saved_soldier.is_empty() or int(saved_soldier.get("state", -1)) != SoldierScript.State.ATTACK or not bool(saved_soldier.get("attack_move_active", false)):
		_finish(false, "production_save_did_not_capture_a_move_combat_intent")
		return

	# Call the real Continue implementation: it validates the save, loads the payload,
	# and invokes SceneTree.reload_current_scene. The root diagnostic node survives it.
	game.call_deferred("_continue_saved_match")
	var restored_game: Node = null
	for _frame in range(1800):
		var candidate: Node = get_tree().get_first_node_in_group("main_game")
		if candidate != null and candidate.get_instance_id() != old_game_id and bool(candidate.get("_match_started")):
			restored_game = candidate
			break
		await get_tree().process_frame
	if restored_game == null:
		_finish(false, "continue_reload_did_not_create_restored_match")
		return

	var restored_soldier: Node = null
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("_attack_move_active")):
			restored_soldier = unit
			break
	var restored_target: Node = restored_soldier.get("attack_target") if restored_soldier != null else null
	var restored_ok := restored_soldier != null and int(restored_soldier.get("state")) == SoldierScript.State.ATTACK and restored_target != null and is_instance_valid(restored_target) and bool(restored_soldier.get("_attack_move_active")) and _near(restored_soldier.get("_attack_move_goal"), a_destination, 0.1) and Array(restored_soldier.get("order_queue")).size() == 1 and str(restored_target.get("team")) == "enemy"
	report["after_continue_reload"] = {
		"new_main_instance": restored_game.get_instance_id() != old_game_id,
		"match_started": restored_game.get("_match_started"),
		"mode_id": restored_game.get("_horde_mode"),
		"seed": restored_game.get("map_seed"),
		"attacking_a_move_soldier_restored": restored_soldier != null,
		"restored_state": int(restored_soldier.get("state")) if restored_soldier != null else -1,
		"restored_target_alive": CombatTargetAlive(restored_target),
		"restored_a_intent": bool(restored_soldier.get("_attack_move_active")) if restored_soldier != null else false,
		"restored_a_destination": _vec(restored_soldier.get("_attack_move_goal")) if restored_soldier != null else [],
		"restored_shift_queue_size": Array(restored_soldier.get("order_queue")).size() if restored_soldier != null else -1,
		"restored_position": _vec(restored_soldier.global_position) if restored_soldier != null else [],
	}
	if not restored_ok:
		_finish(false, "continue_reload_lost_a_move_combat_state")
		return

	restored_soldier.order_completed.connect(_on_order_completed)
	restored_soldier.queued_order_started.connect(_on_queued_order_started)
	restored_target.call("take_damage", 1000.0, false)
	var resumed := false
	for _frame in range(1800):
		if is_instance_valid(restored_soldier) and int(restored_soldier.get("state")) == SoldierScript.State.ATTACK_MOVE and restored_soldier.get("attack_target") == null:
			resumed = true
			break
		await get_tree().process_frame
	var reached_partial_endpoint := false
	for _frame in range(1800):
		if not is_instance_valid(restored_soldier):
			break
		if bool(restored_soldier.get("_partial_attack_move_waiting")):
			reached_partial_endpoint = true
			break
		if not order_events.is_empty():
			break
		await get_tree().process_frame
	var a_complete_index := -1
	var queued_start_index := -1
	for index in range(order_events.size()):
		var event: Dictionary = order_events[index]
		if str(event.get("event", "")) == "order_completed" and str(event.get("kind", "")) == "attack_move":
			a_complete_index = index
		if str(event.get("event", "")) == "queued_order_started" and str(event.get("kind", "")) == "move" and queued_start_index < 0:
			queued_start_index = index
	var a_completed_at_destination := false
	var queued_move_started_at_a := false
	var queued_started_at_legal_a_endpoint := false
	if a_complete_index >= 0:
		var complete_event: Dictionary = order_events[a_complete_index]
		a_completed_at_destination = float(complete_event.get("distance_to_legal_goal", 999.0)) <= 0.75
	if queued_start_index >= 0:
		var start_event: Dictionary = order_events[queued_start_index]
		queued_move_started_at_a = float(start_event.get("distance_to_a", 999.0)) <= 0.75
		if a_complete_index >= 0:
			var complete_event: Dictionary = order_events[a_complete_index]
			queued_started_at_legal_a_endpoint = (_vec_to_vector(start_event.get("position", []))).distance_to(_vec_to_vector(complete_event.get("position", []))) <= 0.1
	var completion_preceded_queue_start: bool = a_complete_index >= 0 and queued_start_index > a_complete_index
	var a_order_still_pending := reached_partial_endpoint and is_instance_valid(restored_soldier) and bool(restored_soldier.get("_attack_move_active")) and int(restored_soldier.get("state")) == SoldierScript.State.ATTACK_MOVE and Array(restored_soldier.get("order_queue")).size() == 1
	var queued_order_not_started_early := queued_start_index < 0
	report["post_restore_behavior"] = {
		"target_destroyed_then_a_resumed": resumed,
		"order_events": order_events,
		"partial_path_endpoint_reached": reached_partial_endpoint,
		"a_completed_within_tolerance_of_legal_goal": a_completed_at_destination,
		"queued_move_started_within_tolerance_of_a": queued_move_started_at_a,
		"queued_move_started_at_recorded_a_endpoint": queued_started_at_legal_a_endpoint,
		"a_completion_preceded_queued_move_start": completion_preceded_queue_start,
		"a_order_still_pending_at_partial_path_endpoint": a_order_still_pending,
		"queued_order_not_started_early": queued_order_not_started_early,
		"final_position": _vec(restored_soldier.global_position) if is_instance_valid(restored_soldier) else [],
		"final_state": int(restored_soldier.get("state")) if is_instance_valid(restored_soldier) else -1,
	}
	var behavior_handled := (a_order_still_pending and queued_order_not_started_early and not a_completed_at_destination) or (a_completed_at_destination and queued_started_at_legal_a_endpoint and completion_preceded_queue_start)
	_finish(resumed and behavior_handled, "actual_continue_reload_resolved_a_move_path_safely" if resumed and behavior_handled else "restored_a_move_behavior_incomplete")

func _near(value: Vector3, expected: Vector3, tolerance: float) -> bool:
	return value.distance_to(expected) <= tolerance

func _on_order_completed(kind: String, position_at_completion: Vector3, destination: Vector3, frame: int) -> void:
	order_events.append({"event": "order_completed", "kind": kind, "position": _vec(position_at_completion), "destination": _vec(destination), "frame": frame, "distance_to_a": position_at_completion.distance_to(Vector3(-8.0, 0.0, 14.0)), "distance_to_legal_goal": position_at_completion.distance_to(destination)})

func _on_queued_order_started(kind: String, position_at_start: Vector3, destination: Vector3, frame: int) -> void:
	order_events.append({"event": "queued_order_started", "kind": kind, "position": _vec(position_at_start), "destination": _vec(destination), "frame": frame, "distance_to_a": position_at_start.distance_to(Vector3(-8.0, 0.0, 14.0))})

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _vec_to_vector(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)

func CombatTargetAlive(target: Node) -> bool:
	return target != null and is_instance_valid(target) and bool(target.get("alive")) and float(target.get("hp")) > 0.0

func _finish(passed: bool, reason: String, extra: Dictionary = {}) -> void:
	report["passed"] = passed
	report["reason"] = reason
	report["headless"] = DisplayServer.get_name() == "headless"
	report["runtime"] = {"executable": OS.get_executable_path(), "driver_resource": get_script().resource_path, "user_data_dir": OS.get_user_data_dir()}
	report.merge(extra, true)
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[A_MOVE_CONTINUE_RESTORE] " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

