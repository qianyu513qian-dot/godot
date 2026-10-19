extends SceneTree
## Natural-process-frame tests for A-move partial routes, graph invalidation,
## retry bounds, Stop, and replacement Move.

const Soldier := preload("res://scripts/soldier.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const RESULT_PATH := "user://a_move_partial_path_lifecycle_probe.json"
const START := Vector3(-10.0, 0.0, 10.0)
const A_GOAL := Vector3(10.0, 0.0, 10.0)
const QUEUED_GOAL := Vector3(10.0, 0.0, 16.0)
const MAX_WAIT_FRAMES := 2400

class TestBarrier:
	extends Node3D
	var footprint := Vector3(2.4, 1.0, 100.0)
	var blocks_path := true
	var is_wall := false
	var is_gate := false
	var is_tower := false

	func blocks_unit_at(point: Vector3, team_or_radius: Variant = "player", radius_override: Variant = null) -> bool:
		var radius := float(radius_override) if radius_override != null else float(team_or_radius)
		var local := point - global_position
		return absf(local.x) < footprint.x * 0.5 + radius and absf(local.z) < footprint.z * 0.5 + radius

var report: Dictionary = {"suite": "a_move_partial_path_lifecycle", "headless": false, "cases": {}, "passed": false}
var _events: Dictionary = {}
var _failures: Array[String] = []
var _world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	report["headless"] = DisplayServer.get_name() == "headless"
	if not report["headless"]:
		_finish(false, "headless_required")
		return
	_world = Node3D.new()
	_world.name = "A_Move_Lifecycle_Test_World"
	root.add_child(_world)
	await _test_temporary_blockage_release()
	await _test_persistent_blockage_stop()
	await _test_persistent_blockage_replacement_move()
	_finish(_failures.is_empty(), "passed" if _failures.is_empty() else "failed")

func _make_barrier(name: String) -> TestBarrier:
	var barrier := TestBarrier.new()
	barrier.name = name
	barrier.position = Vector3.ZERO
	barrier.add_to_group("buildings")
	_world.add_child(barrier)
	Pathfind.invalidate()
	return barrier

func _make_soldier(name: String) -> Node:
	var unit: Node = Soldier.new()
	unit.name = name
	_world.add_child(unit)
	unit.setup(START, "player", false)
	_events[name] = []
	unit.order_completed.connect(_on_order_completed.bind(name))
	unit.queued_order_started.connect(_on_queued_order_started.bind(name))
	unit.command_attack_move(A_GOAL)
	unit.command_move(QUEUED_GOAL, true)
	return unit

func _wait_for_partial_wait(unit: Node, max_frames: int) -> int:
	for frame in range(max_frames):
		if bool(unit.get("_partial_attack_move_waiting")):
			return frame + 1
		if int(unit.get("state")) != Soldier.State.ATTACK_MOVE:
			return -1
		await process_frame
	return -1

func _test_temporary_blockage_release() -> void:
	var barrier := _make_barrier("TemporaryRouteBarrier")
	var unit := _make_soldier("TemporaryBarrierSoldier")
	var path_report: Dictionary = Pathfind.last_path_report.duplicate(true)
	var wait_frames: int = await _wait_for_partial_wait(unit, 900)
	var held_before_release: bool = wait_frames > 0 and bool(unit.get("_attack_move_active")) and Array(unit.get("order_queue")).size() == 1 and _events[unit.name].is_empty()
	if is_instance_valid(barrier):
		barrier.queue_free()
	await process_frame
	Pathfind.invalidate()
	var completed := false
	for _frame in range(MAX_WAIT_FRAMES):
		var evs: Array = _events[unit.name]
		var completed_count := 0
		var queued_count := 0
		for event in evs:
			if event["event"] == "order_completed":
				completed_count += 1
			if event["event"] == "queued_order_started":
				queued_count += 1
		if completed_count > 0 and queued_count > 0 and int(unit.get("state")) == Soldier.State.IDLE:
			completed = true
			break
		await process_frame
	var evs: Array = _events[unit.name]
	var ordered: bool = evs.size() >= 2 and evs[0]["event"] == "order_completed" and evs[1]["event"] == "queued_order_started"
	var same_boundary := false
	if evs.size() >= 2:
		same_boundary = int(evs[0]["frame"]) == int(evs[1]["frame"]) and _vec(evs[0]["position"]).distance_to(_vec(evs[1]["position"])) <= 0.001 and _vec(evs[0]["position"]).distance_to(A_GOAL) <= 0.75
	var passed: bool = held_before_release and completed and ordered and same_boundary
	_record_case("temporary_blockage_released_then_a_and_shift_completed", passed, {
		"initial_path": path_report,
		"wait_frames_before_release": wait_frames,
		"held_order_and_queue_before_release": held_before_release,
		"events": evs,
		"completed_queued_move": completed,
		"event_order_correct": ordered,
		"both_events_at_a_boundary": same_boundary,
		"final_position": _vec_array(unit.global_position),
	})
	unit.queue_free()
	await process_frame

func _test_persistent_blockage_stop() -> void:
	var barrier := _make_barrier("PersistentStopBarrier")
	var unit := _make_soldier("PersistentStopSoldier")
	var wait_frames: int = await _wait_for_partial_wait(unit, 900)
	for _frame in range(3600):
		if int(unit.get("_partial_attack_move_retries")) >= int(unit.get("MAX_PARTIAL_ATTACK_MOVE_RETRIES")) and float(unit.get("_repath_cd")) <= 0.0:
			break
		await process_frame
	var retries := int(unit.get("_partial_attack_move_retries"))
	var calls_before: int = Pathfind.search_count
	for _frame in range(120):
		await process_frame
	var calls_after: int = Pathfind.search_count
	var pending_before_stop: bool = bool(unit.get("_attack_move_active")) and bool(unit.get("_partial_attack_move_waiting")) and Array(unit.get("order_queue")).size() == 1
	unit.command_stop()
	var stopped := int(unit.get("state")) == Soldier.State.IDLE and not bool(unit.get("_attack_move_active")) and Array(unit.get("order_queue")).is_empty()
	var no_false_completion: bool = _events[unit.name].is_empty()
	var passed: bool = wait_frames > 0 and retries == int(unit.get("MAX_PARTIAL_ATTACK_MOVE_RETRIES")) and calls_before == calls_after and pending_before_stop and stopped and no_false_completion
	_record_case("persistent_blockage_has_bounded_retries_and_stop_cancels", passed, {
		"partial_wait_frames": wait_frames,
		"retry_count": retries,
		"retry_limit": unit.get("MAX_PARTIAL_ATTACK_MOVE_RETRIES"),
		"path_calls_stable_during_120_frame_idle": calls_before == calls_after,
		"pending_before_stop": pending_before_stop,
		"stopped": stopped,
		"events_before_stop": _events[unit.name],
	})
	unit.queue_free()
	if is_instance_valid(barrier):
		barrier.queue_free()
	await process_frame
	Pathfind.invalidate()

func _test_persistent_blockage_replacement_move() -> void:
	var barrier := _make_barrier("PersistentMoveBarrier")
	var unit := _make_soldier("PersistentMoveSoldier")
	var wait_frames: int = await _wait_for_partial_wait(unit, 900)
	var replacement_goal := Vector3(-10.0, 0.0, 16.0)
	unit.command_move(replacement_goal)
	var replacement_active := not bool(unit.get("_attack_move_active")) and not bool(unit.get("_partial_attack_move_waiting")) and Array(unit.get("order_queue")).is_empty() and int(unit.get("state")) == Soldier.State.MOVE
	var reached := false
	for _frame in range(MAX_WAIT_FRAMES):
		if int(unit.get("state")) == Soldier.State.IDLE and unit.global_position.distance_to(replacement_goal) <= 0.75:
			reached = true
			break
		await process_frame
	var no_a_completion: bool = _events[unit.name].is_empty()
	var passed: bool = wait_frames > 0 and replacement_active and reached and no_a_completion
	_record_case("new_move_cancels_persistently_blocked_a", passed, {
		"partial_wait_frames": wait_frames,
		"replacement_order_active": replacement_active,
		"replacement_goal": _vec_array(replacement_goal),
		"replacement_reached": reached,
		"final_position": _vec_array(unit.global_position),
		"no_old_a_completion_event": no_a_completion,
	})
	unit.queue_free()
	if is_instance_valid(barrier):
		barrier.queue_free()
	await process_frame
	Pathfind.invalidate()

func _on_order_completed(kind: String, position: Vector3, destination: Vector3, frame: int, unit_name: String) -> void:
	_events[unit_name].append({"event": "order_completed", "kind": kind, "position": _vec_array(position), "destination": _vec_array(destination), "frame": frame, "distance_to_goal": position.distance_to(destination)})

func _on_queued_order_started(kind: String, position: Vector3, destination: Vector3, frame: int, unit_name: String) -> void:
	_events[unit_name].append({"event": "queued_order_started", "kind": kind, "position": _vec_array(position), "destination": _vec_array(destination), "frame": frame})

func _record_case(name: String, passed: bool, details: Dictionary) -> void:
	report["cases"][name] = {"passed": passed, "details": details}
	if not passed:
		_failures.append(name)

func _vec_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _finish(passed: bool, reason: String) -> void:
	report["passed"] = passed
	report["reason"] = reason
	report["failures"] = _failures
	report["runtime"] = {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/a_move_partial_path_lifecycle_probe.gd", "user_data_dir": OS.get_user_data_dir()}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[A_MOVE_PARTIAL_PATH_LIFECYCLE] " + JSON.stringify(report))
	quit(0 if passed else 1)
