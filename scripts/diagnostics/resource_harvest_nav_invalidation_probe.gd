extends SceneTree
## Uses the production ResourceNode3D.harvest/queue_free path and natural frames
## to verify that mining a navigation blocker refreshes a pending A-move route.

const Soldier := preload("res://scripts/soldier.gd")
const ResourceNode := preload("res://scripts/resource_node.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const RESULT_PATH := "user://resource_harvest_nav_invalidation_probe.json"
const START := Vector3(-10.0, 0.0, 0.0)
const A_GOAL := Vector3(10.0, 0.0, 0.0)
const QUEUED_GOAL := Vector3(10.0, 0.0, 6.0)
const RETRY_LIMIT := 4

class TestMain:
	extends Node
	var _match_started := true
	var _world_teardown_in_progress := false
	var world: Node3D

class TestBarrier:
	extends Node3D
	var footprint := Vector3(2.4, 1.0, 100.0)
	var blocks_path := true
	var is_wall := false
	var is_gate := false
	var is_tower := false
	var gap_half_width := 4.6

	func blocks_unit_at(point: Vector3, team_or_radius: Variant = "player", radius_override: Variant = null) -> bool:
		var radius := float(radius_override) if radius_override != null else float(team_or_radius)
		var local := point - global_position
		if absf(local.z) < gap_half_width:
			return false
		return absf(local.x) < footprint.x * 0.5 + radius and absf(local.z) < footprint.z * 0.5 + radius

var _baseline_mode := false
var _main: TestMain
var _world: Node3D
var _resource: Node
var _soldier: Node
var _events: Array[Dictionary] = []
var _report: Dictionary = {"suite": "resource_harvest_navigation_invalidation", "headless": false, "passed": false}

func _initialize() -> void:
	_baseline_mode = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	_report["headless"] = DisplayServer.get_name() == "headless"
	if not _report["headless"]:
		_finish(false, "headless_required")
		return
	_main = TestMain.new()
	_main.name = "ResourceHarvestProbeMain"
	_main.add_to_group("main_game")
	root.add_child(_main)
	_world = Node3D.new()
	_world.name = "world"
	_main.world = _world
	_main.add_child(_world)
	var barrier := TestBarrier.new()
	barrier.name = "MineablePassageWall"
	barrier.add_to_group("buildings")
	_world.add_child(barrier)
	_resource = ResourceNode.new()
	_resource.name = "PassageGold"
	_resource.setup(ResourceNode.Kind.GOLD, Vector3.ZERO, 1)
	_world.add_child(_resource)
	_soldier = Soldier.new()
	_soldier.name = "ResourceBlockedAttackMoveSoldier"
	_world.add_child(_soldier)
	_soldier.setup(START, "player", false)
	_soldier.order_completed.connect(_on_order_completed)
	_soldier.queued_order_started.connect(_on_queued_order_started)
	Pathfind.invalidate()  # Initial world build only; never invalidate after harvest in the probe.
	Pathfind.find_path(START, A_GOAL, self)
	_report["initial_path"] = Pathfind.last_path_report.duplicate(true)
	_soldier.command_attack_move(A_GOAL)
	_soldier.command_move(QUEUED_GOAL, true)
	var partial_frames := await _wait_for_partial_wait(1800)
	for _frame in range(3600):
		if int(_soldier.get("_partial_attack_move_retries")) >= RETRY_LIMIT and float(_soldier.get("_repath_cd")) <= 0.0:
			break
		await process_frame
	var calls_before: int = Pathfind.search_count
	var revision_before: int = Pathfind.navigation_revision
	var position_before: Vector3 = _soldier.global_position
	var queue_before: int = Array(_soldier.get("order_queue")).size()
	for _frame in range(120):
		await process_frame
	var calls_stable_before_harvest: bool = calls_before == Pathfind.search_count
	_report["before_harvest"] = {
		"partial_wait_frames": partial_frames,
		"retry_count": _soldier.get("_partial_attack_move_retries"),
		"path_calls": calls_before,
		"searches_stable_for_120_frames": calls_stable_before_harvest,
		"navigation_revision": revision_before,
		"resource_inside_tree": _resource.is_inside_tree(),
		"resource_position": _as_array(_resource.global_position),
		"soldier_position": _as_array(position_before),
		"soldier_pending_a": bool(_soldier.get("_attack_move_active")),
		"queued_orders": queue_before,
	}
	var resource_ref: WeakRef = weakref(_resource)
	var harvested: int = int(_resource.call("harvest", 1))
	var queued_before_exit: bool = _resource.is_queued_for_deletion() and _resource.is_inside_tree()
	for _frame in range(4):
		if resource_ref.get_ref() == null:
			break
		await process_frame
	var remaining_resource: bool = resource_ref.get_ref() != null and resource_ref.get_ref().is_inside_tree()
	var revision_after: int = Pathfind.navigation_revision
	var searches_after_exit: int = Pathfind.search_count
	_report["after_harvest_exit"] = {
		"harvested": harvested,
		"queued_for_deletion_before_frame": queued_before_exit,
		"resource_still_inside_tree": remaining_resource,
		"resource_group_count": get_nodes_in_group("resources").size(),
		"navigation_revision_before": revision_before,
		"navigation_revision_after": revision_after,
		"path_calls_before": calls_before,
		"path_calls_after_exit": searches_after_exit,
		"a_order_active": bool(_soldier.get("_attack_move_active")),
		"queued_orders": Array(_soldier.get("order_queue")).size(),
	}
	if _baseline_mode:
		for _frame in range(120):
			await process_frame
		var reproduced_stale_cache: bool = revision_after == revision_before and searches_after_exit == calls_before and bool(_soldier.get("_partial_attack_move_waiting")) and bool(_soldier.get("_attack_move_active")) and Array(_soldier.get("order_queue")).size() == 1
		_report["baseline"] = {"stale_cache_reproduced": reproduced_stale_cache, "searches_stable_for_additional_120_frames": searches_after_exit == Pathfind.search_count, "soldier_position_after_wait": _as_array(_soldier.global_position), "events": _events}
		_finish(reproduced_stale_cache, "baseline_stale_navigation_cache_reproduced" if reproduced_stale_cache else "baseline_not_reproduced")
		return
	var resumed := false
	for _frame in range(2400):
		if _events.size() >= 2 and int(_soldier.get("state")) == Soldier.State.IDLE:
			resumed = true
			break
		await process_frame
	var event_order: bool = _events.size() >= 2 and _events[0]["event"] == "order_completed" and _events[1]["event"] == "queued_order_started"
	var boundary_ok := false
	if _events.size() >= 2:
		boundary_ok = int(_events[0]["frame"]) == int(_events[1]["frame"]) and _as_vector(_events[0]["position"]).distance_to(A_GOAL) <= 0.75 and _as_vector(_events[0]["position"]).distance_to(_as_vector(_events[0]["destination"])) <= 0.75 and _as_vector(_events[0]["position"]).distance_to(_as_vector(_events[1]["position"])) <= 0.001
	var invalidated_on_exit: bool = revision_after == revision_before + 1
	var searches_resumed: bool = Pathfind.search_count > searches_after_exit
	var before_report: Dictionary = _report.get("before_harvest", {})
	var passed: bool = partial_frames > 0 and int(before_report.get("retry_count", -1)) == RETRY_LIMIT and calls_stable_before_harvest and harvested == 1 and queued_before_exit and not remaining_resource and invalidated_on_exit and searches_resumed and resumed and event_order and boundary_ok
	_report["after_harvest_behavior"] = {
		"navigation_invalidated_once_on_resource_exit": invalidated_on_exit,
		"navigation_revision_after_recovery": Pathfind.navigation_revision,
		"path_search_resumed": searches_resumed,
		"path_calls_after_recovery": Pathfind.search_count,
		"a_completed_then_shift_started": resumed,
		"events_in_order": event_order,
		"both_events_at_legal_a_boundary": boundary_ok,
		"events": _events,
		"final_position": _as_array(_soldier.global_position),
	}
	var teardown_resource: Node = ResourceNode.new()
	teardown_resource.name = "DepletedDuringWorldTeardown"
	teardown_resource.setup(ResourceNode.Kind.GOLD, Vector3(24.0, 0.0, 24.0), 1)
	_world.add_child(teardown_resource)
	var teardown_revision_before: int = Pathfind.navigation_revision
	teardown_resource.call("harvest", 1)
	_main._world_teardown_in_progress = true
	await process_frame
	var teardown_suppressed: bool = Pathfind.navigation_revision == teardown_revision_before
	_report["scene_teardown_suppression"] = {"depletion_queued_for_free": not is_instance_valid(teardown_resource), "navigation_revision_unchanged": teardown_suppressed}
	passed = passed and teardown_suppressed
	_finish(passed, "depleted_resource_invalidated_navigation_and_resumed_a" if passed else "depleted_resource_did_not_resume_a")

func _wait_for_partial_wait(max_frames: int) -> int:
	for frame in range(max_frames):
		if bool(_soldier.get("_partial_attack_move_waiting")):
			return frame + 1
		await process_frame
	return -1

func _on_order_completed(kind: String, position: Vector3, destination: Vector3, frame: int) -> void:
	_events.append({"event": "order_completed", "kind": kind, "position": _as_array(position), "destination": _as_array(destination), "frame": frame})

func _on_queued_order_started(kind: String, position: Vector3, destination: Vector3, frame: int) -> void:
	_events.append({"event": "queued_order_started", "kind": kind, "position": _as_array(position), "destination": _as_array(destination), "frame": frame})

func _as_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _as_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _finish(passed: bool, reason: String) -> void:
	_report["passed"] = passed
	_report["reason"] = reason
	_report["events"] = _events
	_report["runtime"] = {"executable": OS.get_executable_path(), "driver_resource": "res://scripts/diagnostics/resource_harvest_nav_invalidation_probe.gd", "user_data_dir": OS.get_user_data_dir()}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, "\t"))
		f.close()
	print("[RESOURCE_HARVEST_NAV_INVALIDATION] " + JSON.stringify(_report))
	quit(0 if passed else 1)
