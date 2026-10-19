extends SceneTree
## Focused production behavior regression for Soldier3D A-move intent.
## Run only with --headless; it does not start Main or a normal match.

const SoldierScript := preload("res://scripts/soldier.gd")
const MainScript := preload("res://scripts/main.gd")
const Pathfind := preload("res://scripts/pathfind.gd")

class SaveCodecStub:
	extends "res://scripts/main.gd"

	func _ready() -> void:
		pass

class TestCombatant extends Node3D:
	var team := "enemy"
	var is_zombie := false
	var horde_wave_id := 0
	var alive := true
	var hp := 100.0
	var radius := 0.45
	var state := 0
	var move_target := Vector3.ZERO
	var attack_target: Node3D
	var _goal_final := Vector3.ZERO
	var _attack_move_goal := Vector3.ZERO
	var _attack_cd := 0.0
	var _night_buffed := false
	var guard_active := false
	var guard_anchor := Vector3.ZERO
	var guard_resolved_anchor := Vector3.ZERO
	var order_queue: Array = []

	func _ready() -> void:
		add_to_group("combatants")
		add_to_group("enemy_units")
		add_to_group("soldiers")

	func is_melee_in_range(attacker_pos: Vector3) -> bool:
		return Vector2(global_position.x - attacker_pos.x, global_position.z - attacker_pos.z).length() <= 1.35 + radius

	func melee_approach(from_pos: Vector3) -> Vector3:
		var delta := Vector3(from_pos.x - global_position.x, 0.0, from_pos.z - global_position.z)
		return global_position + (delta.normalized() if delta.length_squared() > 0.0001 else Vector3.RIGHT) * (radius + 0.6)

	func take_damage(amount: float, _pierce: bool = false, _attacker: Node3D = null) -> void:
		hp = maxf(0.0, hp - amount)
		if hp <= 0.0:
			alive = false
			remove_from_group("enemy_units")
			remove_from_group("combatants")

	func save_attack_move_intent() -> Dictionary:
		return {"attack_move_active": false, "attack_move_goal": [0.0, 0.0, 0.0]}

	func save_attack_return_guard_intent() -> Dictionary:
		return {"attack_return_guard_active": false, "attack_return_guard_anchor": [global_position.x, global_position.y, global_position.z]}

class TestObstacle extends Node3D:
	var blocks_path := true
	var footprint := Vector3(2.4, 2.0, 3.6)
	var team := "player"
	var alive := true
	var hp := 1000.0
	var kind := 0
	var is_complete := true
	var build_progress := 1.0
	var meat_stock := 0
	var is_arid := false
	var train_queue: Array[String] = []
	var train_timer := 0.0
	var train_paid := false
	var train_paused := false
	var has_rally := false
	var rally_point := Vector3.ZERO
	var gate_locked := false

	func blocks_unit_at(pos: Vector3, _team: String, clearance: float) -> bool:
		return absf(pos.x - global_position.x) <= footprint.x * 0.5 + clearance and absf(pos.z - global_position.z) <= footprint.z * 0.5 + clearance

var failures: Array[String] = []
var checks: Array[Dictionary] = []
var world: Node3D
var obstacle: TestObstacle
var main_codec: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		_fail("headless_required", "Runner refuses a non-headless display.")
		await _finish()
		return
	world = Node3D.new()
	world.name = "SoldierAttackMoveRegressionWorld"
	root.add_child(world)
	main_codec = SaveCodecStub.new()
	main_codec.name = "ProductionSaveCodec"
	main_codec.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main_codec)
	main_codec.set("_match_started", true)
	obstacle = TestObstacle.new()
	obstacle.name = "BlockingObstacle"
	obstacle.position = Vector3(8.0, 0.0, 0.0)
	obstacle.add_to_group("buildings")
	world.add_child(obstacle)
	Pathfind.invalidate()
	await process_frame

	_test_legacy_finish_branch_reproduces_drop()
	await _test_interrupted_attack_move_save_restore()
	await _test_freed_target_resumes_attack_move()
	await _test_stop_cancels_attack_move()
	await _test_move_cancels_attack_move()
	await _test_attack_cancels_attack_move()
	await _test_guard_attack_returns_after_target_and_save_restore()
	await _test_guard_return_overrides_and_queue_fallback()
	_test_legacy_save_defaults()

	await _finish()

func _test_legacy_finish_branch_reproduces_drop() -> void:
	## Baseline control for the pre-fix `_do_attack` branch in git HEAD:
	## dead target => clear target => `_finish_order()`. This intentionally calls
	## that unchanged old completion path after setting up a real A-move chase.
	var destination := Vector3(15.0, 0.0, 24.0)
	var queued_destination := Vector3(15.0, 0.0, 32.0)
	var soldier: Node = _new_soldier("Legacy_Baseline_A", Vector3(0.0, 0.0, 24.0))
	soldier.command_attack_move(destination)
	soldier.command_move(queued_destination, true)
	for _i in range(12):
		_step(soldier, 0.05)
	var enemy: TestCombatant = _new_enemy("Legacy_Baseline_Target", soldier.global_position + Vector3(3.2, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	_step(soldier, 0.05)
	var auto_engaged_and_chasing: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == enemy and not _near(soldier.get("_goal_final"), destination, 0.01)
	var chase_goal_before_death: Vector3 = soldier.get("_goal_final")
	enemy.take_damage(1000.0, false)
	# This is the exact pre-fix branch body from the old production implementation.
	soldier.attack_target = null
	soldier._finish_order()
	var skipped_a_for_shift_order: bool = soldier.state == SoldierScript.State.MOVE and _near(soldier.get("_goal_final"), queued_destination, 0.01) and soldier.order_queue.is_empty() and soldier.global_position.distance_to(destination) > 3.0
	var details := {"auto_engaged_and_chasing": auto_engaged_and_chasing, "chase_goal_overwrote_a_goal": not _near(chase_goal_before_death, destination, 0.01), "old_finish_activated_shift_before_a_destination": skipped_a_for_shift_order, "actual_position_when_shift_started": _vec_data(soldier.global_position)}
	_check("pre_fix_finish_branch_reproduces_attack_move_drop", auto_engaged_and_chasing and details.chase_goal_overwrote_a_goal and skipped_a_for_shift_order, details)
	soldier.queue_free()
	enemy.queue_free()
	await process_frame

func _test_interrupted_attack_move_save_restore() -> void:
	var destination := Vector3(15.0, 0.0, 0.0)
	var queued_destination := Vector3(15.0, 0.0, 9.0)
	var soldier: Node = _new_soldier("A_Move_Through_Combat", Vector3.ZERO)
	soldier.command_attack_move(destination)
	soldier.command_move(queued_destination, true)
	var start_pos: Vector3 = soldier.global_position
	for _i in range(12):
		_step(soldier, 0.05)
	var moved_before_combat: bool = soldier.global_position.distance_to(start_pos) > 1.0
	var enemy: TestCombatant = _new_enemy("Auto_Acquired_Target", soldier.global_position + Vector3(0.65, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	var auto_engaged: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == enemy and soldier._attack_move_active
	_step(soldier, 0.05)
	var hp_after_swing := enemy.hp

	# Mirror the production soldier fields in main._save_match, JSON round-trip
	# them, then use main's production queue decoder for Shift follow-up orders.
	var save_path := "user://soldier_attack_move_roundtrip.json"
	var production_save_written: bool = main_codec._save_match(save_path)
	var parsed_document: Dictionary = {}
	if production_save_written:
		var save_file := FileAccess.open(save_path, FileAccess.READ)
		if save_file:
			var parsed_value: Variant = JSON.parse_string(save_file.get_as_text())
			if parsed_value is Dictionary:
				parsed_document = parsed_value
			save_file.close()
	var parsed_save: Dictionary = {}
	for saved_soldier in parsed_document.get("entities", {}).get("soldiers", []):
		if str(saved_soldier.get("team", "")) == "player" and int(saved_soldier.get("state", -1)) == SoldierScript.State.ATTACK:
			parsed_save = saved_soldier
			break
	var restored: Node = _new_soldier("Restored_A_Move_Through_Combat", _data_vec(parsed_save.pos))
	restored.state = int(parsed_save.state)
	restored.attack_target = enemy
	restored._set_move_goal(_data_vec(parsed_save.goal), true)
	restored.state = int(parsed_save.state)
	var saved_state := int(parsed_save.state)
	var legacy_fallback := saved_state == SoldierScript.State.ATTACK_MOVE
	restored.restore_attack_move_intent(bool(parsed_save.get("attack_move_active", legacy_fallback)), _data_vec(parsed_save.get("attack_move_goal", parsed_save.get("goal", parsed_save.get("pos", [])))))
	var target_ids := {str(parsed_save.get("attack_id", "")): enemy}
	restored.order_queue = main_codec._restore_order_queue(parsed_save.get("orders", []), target_ids)
	soldier.queue_free()
	await process_frame

	var restored_in_combat: bool = restored.state == SoldierScript.State.ATTACK and restored.attack_target == enemy and restored.get("_attack_move_active") and restored.order_queue.size() == 1
	enemy.take_damage(1000.0, false)
	_step(restored, 0.05)
	var resumed_a_move: bool = restored.state == SoldierScript.State.ATTACK_MOVE and restored.attack_target == null and restored.get("_attack_move_active") and _near(restored.get("_attack_move_goal"), destination, 0.01)
	var obstacle_route_ok: bool = not restored.get("_waypoints").is_empty()
	var obstacle_avoided := not obstacle.blocks_unit_at(restored.global_position, "player", 0.4)
	var reached_destination := false
	var queued_order_activated_at_destination := false
	for _i in range(900):
		_step(restored, 0.05)
		if obstacle.blocks_unit_at(restored.global_position, "player", 0.4):
			obstacle_avoided = false
		if restored.state == SoldierScript.State.MOVE:
			reached_destination = restored.global_position.distance_to(destination) <= 0.75
			queued_order_activated_at_destination = _near(restored.get("_goal_final"), queued_destination, 0.01) and restored.order_queue.is_empty()
			break
	var details := {
		"moved_before_combat": moved_before_combat,
		"auto_engaged": auto_engaged,
		"enemy_hp_after_real_swing": hp_after_swing,
		"saved_and_restored_in_combat": restored_in_combat,
		"production_save_contained_a_state": production_save_written and not parsed_save.is_empty(),
		"resumed_original_attack_move": resumed_a_move,
		"obstacle_route_nonempty": obstacle_route_ok,
		"obstacle_collision_avoided": obstacle_avoided,
		"reached_original_destination": reached_destination,
		"queued_shift_move_started_at_destination": queued_order_activated_at_destination,
		"final_position": _vec_data(restored.global_position),
		"final_state": int(restored.state),
		"remaining_orders": restored.order_queue.size(),
	}
	var production_save_contained_a_state: bool = production_save_written and not parsed_save.is_empty()
	var passed := moved_before_combat and auto_engaged and hp_after_swing < 100.0 and production_save_contained_a_state and restored_in_combat and resumed_a_move and obstacle_route_ok and obstacle_avoided and reached_destination and queued_order_activated_at_destination
	_check("combat_interruption_save_restore_and_shift_queue", passed, details)
	restored.queue_free()
	enemy.queue_free()
	await process_frame

func _test_stop_cancels_attack_move() -> void:
	var soldier: Node = _new_soldier("Stop_Cancels_A", Vector3(-20.0, 0.0, 0.0))
	var destination := Vector3(-5.0, 0.0, 0.0)
	soldier.command_attack_move(destination)
	var enemy: TestCombatant = _new_enemy("Stop_Target", soldier.global_position + Vector3(0.6, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	var engaged: bool = soldier.state == SoldierScript.State.ATTACK and soldier.get("_attack_move_active")
	soldier.command_stop()
	enemy.alive = false
	enemy.hp = 0.0
	enemy.remove_from_group("enemy_units")
	for _i in range(5):
		_step(soldier, 0.05)
	var details := {"was_auto_engaged": engaged, "stopped_idle": soldier.state == SoldierScript.State.IDLE, "old_a_cleared": not soldier.get("_attack_move_active"), "position_stayed": soldier.global_position.distance_to(Vector3(-20.0, 0.0, 0.0)) < 0.01}
	_check("stop_cancels_old_attack_move", details.values().all(func(v): return bool(v)), details)
	soldier.queue_free()
	enemy.queue_free()
	await process_frame

func _test_freed_target_resumes_attack_move() -> void:
	var start := Vector3(24.0, 0.0, 15.0)
	var destination := Vector3(36.0, 0.0, 15.0)
	var soldier: Node = _new_soldier("Freed_Target_Resumes_A", start)
	soldier.command_attack_move(destination)
	var enemy: TestCombatant = _new_enemy("Freed_Target", start + Vector3(0.6, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	_step(soldier, 0.05)
	var engaged: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == enemy
	enemy.free()
	_step(soldier, 0.05)
	var resumed: bool = soldier.state == SoldierScript.State.ATTACK_MOVE and soldier.attack_target == null and soldier.get("_attack_move_active") and _near(soldier.get("_attack_move_goal"), destination, 0.01)
	for _i in range(400):
		_step(soldier, 0.05)
		if soldier.global_position.distance_to(destination) <= 0.75:
			break
	var details := {"was_auto_engaged": engaged, "destroyed_target_detected": not is_instance_valid(enemy), "original_a_resumed": resumed, "reached_original_destination": soldier.global_position.distance_to(destination) <= 0.75}
	_check("freed_target_resumes_attack_move", details.values().all(func(v): return v == true), details)
	soldier.queue_free()
	await process_frame

func _test_move_cancels_attack_move() -> void:
	var start := Vector3(-20.0, 0.0, 12.0)
	var soldier: Node = _new_soldier("Move_Cancels_A", start)
	var old_destination := Vector3(-5.0, 0.0, 12.0)
	var new_destination := Vector3(-18.0, 0.0, 20.0)
	soldier.command_attack_move(old_destination)
	var enemy: TestCombatant = _new_enemy("Move_Target", start + Vector3(0.6, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	var engaged: bool = soldier.state == SoldierScript.State.ATTACK
	soldier.command_move(new_destination)
	enemy.alive = false
	enemy.hp = 0.0
	enemy.remove_from_group("enemy_units")
	_step(soldier, 0.05)
	var details := {"was_auto_engaged": engaged, "new_move_active": soldier.state == SoldierScript.State.MOVE, "old_a_cleared": not soldier.get("_attack_move_active"), "new_goal_kept": _near(soldier.get("_goal_final"), new_destination, 0.01)}
	_check("ordinary_move_cancels_old_attack_move", details.values().all(func(v): return bool(v)), details)
	soldier.queue_free()
	enemy.queue_free()
	await process_frame

func _test_attack_cancels_attack_move() -> void:
	var start := Vector3(-20.0, 0.0, -12.0)
	var soldier: Node = _new_soldier("Attack_Cancels_A", start)
	var old_destination := Vector3(-5.0, 0.0, -12.0)
	soldier.command_attack_move(old_destination)
	var auto_enemy: TestCombatant = _new_enemy("Auto_Target_For_Explicit_Attack", start + Vector3(0.6, 0.0, 0.0), 100.0)
	_step(soldier, 0.05)
	var explicit_target: TestCombatant = _new_enemy("Explicit_Attack_Target", Vector3(-18.0, 0.0, -12.0), 100.0)
	var engaged: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == auto_enemy
	soldier.command_attack_unit(explicit_target)
	var explicit_attack_active: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == explicit_target and not soldier.get("_attack_move_active")
	explicit_target.alive = false
	explicit_target.hp = 0.0
	explicit_target.remove_from_group("enemy_units")
	_step(soldier, 0.05)
	var details := {"was_auto_engaged": engaged, "explicit_attack_replaced_target": explicit_attack_active, "old_a_cleared": not soldier.get("_attack_move_active"), "did_not_resume_old_a": soldier.state == SoldierScript.State.IDLE and soldier.global_position.distance_to(start) < 0.1}
	_check("explicit_attack_cancels_old_attack_move", details.values().all(func(v): return bool(v)), details)
	soldier.queue_free()
	auto_enemy.queue_free()
	explicit_target.queue_free()
	await process_frame

func _test_legacy_save_defaults() -> void:
	var legacy: Node = _new_soldier("Legacy_Save_Default", Vector3(-30.0, 0.0, -20.0))
	var legacy_goal := Vector3(-18.0, 0.0, -20.0)
	var legacy_data := {"state": int(SoldierScript.State.ATTACK_MOVE), "goal": _vec_data(legacy_goal)}
	var legacy_state := int(legacy_data.state)
	legacy.state = legacy_state
	legacy.restore_attack_move_intent(bool(legacy_data.get("attack_move_active", legacy_state == SoldierScript.State.ATTACK_MOVE)), _data_vec(legacy_data.get("attack_move_goal", legacy_data.get("goal", []))))
	var details := {"legacy_state_loaded": legacy.state == SoldierScript.State.ATTACK_MOVE, "legacy_attack_move_inferred": legacy.get("_attack_move_active"), "legacy_goal_defaulted": _near(legacy.get("_attack_move_goal"), legacy_goal, 0.01)}
	_check("legacy_save_missing_new_fields_is_compatible", details.values().all(func(v): return bool(v)), details)
	legacy.queue_free()
	await process_frame

func _test_guard_attack_returns_after_target_and_save_restore() -> void:
	var anchor := Vector3(-25.0, 0.0, 18.0)
	var soldier: Node = _new_soldier("Guard_Attack_Return", Vector3(-20.0, 0.0, 18.0))
	soldier.command_guard(anchor)
	var enemy := _new_enemy("Guard_Return_Target", soldier.global_position + Vector3(0.6, 0.0, 0.0), 100.0)
	soldier.command_attack_unit(enemy)
	var attack_preserved_return: bool = soldier.state == SoldierScript.State.ATTACK and soldier.attack_target == enemy and bool(soldier.get("_attack_return_guard_active")) and not bool(soldier.get("guard_active"))
	var save_path := "user://soldier_guard_attack_return_roundtrip.json"
	var save_written: bool = main_codec._save_match(save_path)
	var saved_record: Dictionary = {}
	if save_written:
		var save_file := FileAccess.open(save_path, FileAccess.READ)
		if save_file:
			var parsed: Variant = JSON.parse_string(save_file.get_as_text())
			if parsed is Dictionary:
				for record in parsed.get("entities", {}).get("soldiers", []):
					if str(record.get("team", "")) == "player" and bool(record.get("attack_return_guard_active", false)):
						saved_record = record
						break
			save_file.close()
	var restore := _new_soldier("Guard_Attack_Return_Restored", _data_vec(saved_record.get("pos", [])))
	restore.state = int(saved_record.get("state", SoldierScript.State.IDLE))
	restore.attack_target = enemy
	restore._set_move_goal(_data_vec(saved_record.get("goal", [])), true)
	restore.state = int(saved_record.get("state", SoldierScript.State.IDLE))
	restore.restore_attack_move_intent(bool(saved_record.get("attack_move_active", false)), _data_vec(saved_record.get("attack_move_goal", [])))
	restore.restore_guard_intent(bool(saved_record.get("guard_active", false)), _data_vec(saved_record.get("guard_anchor", [])), _data_vec(saved_record.get("guard_resolved_anchor", [])))
	restore.restore_attack_return_guard_intent(bool(saved_record.get("attack_return_guard_active", false)), _data_vec(saved_record.get("attack_return_guard_anchor", [])))
	var save_roundtrip := save_written and not saved_record.is_empty() and bool(saved_record.get("attack_return_guard_active", false)) and _near(_data_vec(saved_record.get("attack_return_guard_anchor", [])), anchor, 0.01)
	soldier.queue_free()
	await process_frame
	enemy.take_damage(1000.0, false)
	_step(restore, 0.05)
	var returned_to_guard: bool = restore.state == SoldierScript.State.GUARD and bool(restore.get("guard_active")) and _near(restore.get("guard_anchor"), anchor, 0.01) and _near(restore.get("_goal_final"), anchor, 0.01)
	var details := {"attack_from_guard_active":attack_preserved_return,"production_save_round_trip":save_roundtrip,"restored_attack_target_cleared":restore.attack_target == null,"returned_to_guard_anchor":returned_to_guard,"guard_anchor":_vec_data(restore.guard_anchor),"state_after_target_death":int(restore.state)}
	_check("guarded_soldier_attack_resumes_guard_after_target_and_save_restore", attack_preserved_return and save_roundtrip and returned_to_guard and restore.attack_target == null, details)
	restore.queue_free()
	enemy.queue_free()
	await process_frame

func _test_guard_return_overrides_and_queue_fallback() -> void:
	var anchor := Vector3(-48.0, 0.0, 24.0)
	var start := Vector3(-44.0, 0.0, 24.0)
	var results: Dictionary = {}
	for override in ["move", "attack_move", "stop", "guard"]:
		var unit: Node = _new_soldier("Guard_Override_" + override, start)
		unit.command_guard(anchor)
		var enemy := _new_enemy("Guard_Override_Target_" + override, start + Vector3(0.6, 0.0, 0.0), 100.0)
		unit.command_attack_unit(enemy)
		match override:
			"move": unit.command_move(start + Vector3(0.0, 0.0, 7.0))
			"attack_move": unit.command_attack_move(start + Vector3(0.0, 0.0, 8.0))
			"stop": unit.command_stop()
			"guard": unit.command_guard(start + Vector3(0.0, 0.0, 9.0))
		results[override] = not bool(unit.get("_attack_return_guard_active"))
		unit.queue_free()
		enemy.queue_free()
	await process_frame

	var a := _new_soldier("Guard_Queued_A", start)
	a.command_guard(anchor)
	var target_a := _new_enemy("Guard_Queued_Target_A", start + Vector3(0.6, 0.0, 0.0), 100.0)
	var target_b := _new_enemy("Guard_Queued_Target_B", start + Vector3(1.0, 0.0, 0.0), 100.0)
	a.command_attack_unit(target_a)
	a.command_attack_unit(target_b, true)
	target_b.free()
	target_a.alive = false
	target_a.hp = 0.0
	target_a.remove_from_group("enemy_units")
	_step(a, 0.05)
	results["freed_queued_attack_returns_to_guard"] = a.state == SoldierScript.State.GUARD and bool(a.get("guard_active")) and _near(a.get("guard_anchor"), anchor, 0.01) and a.order_queue.is_empty()
	a.queue_free()
	target_a.queue_free()
	await process_frame

	var b := _new_soldier("Guard_Queued_Valid_A", start)
	b.command_guard(anchor)
	var first := _new_enemy("Guard_Queued_Valid_Target_A", start + Vector3(0.6, 0.0, 0.0), 100.0)
	var followup := _new_enemy("Guard_Queued_Valid_Target_B", start + Vector3(1.0, 0.0, 0.0), 100.0)
	b.command_attack_unit(first)
	b.command_attack_unit(followup, true)
	first.alive = false
	first.hp = 0.0
	first.remove_from_group("enemy_units")
	_step(b, 0.05)
	var valid_shift_started: bool = b.state == SoldierScript.State.ATTACK and b.attack_target == followup and bool(b.get("_attack_return_guard_active"))
	followup.alive = false
	followup.hp = 0.0
	followup.remove_from_group("enemy_units")
	_step(b, 0.05)
	results["valid_queued_attack_then_guard_return"] = valid_shift_started and b.state == SoldierScript.State.GUARD and _near(b.get("guard_anchor"), anchor, 0.01)
	_check("guard_return_override_and_shift_queue_semantics", results.values().all(func(v): return bool(v)), results)
	b.queue_free()
	first.queue_free()
	followup.queue_free()
	await process_frame

func _new_soldier(label: String, pos: Vector3) -> Node:
	var soldier = SoldierScript.new()
	soldier.name = label
	world.add_child(soldier)
	soldier.setup(pos, "player", false)
	return soldier

func _new_enemy(label: String, pos: Vector3, target_hp: float) -> TestCombatant:
	var enemy := TestCombatant.new()
	enemy.name = label
	enemy.position = pos
	enemy.hp = target_hp
	world.add_child(enemy)
	return enemy

func _step(soldier: Node, delta: float) -> void:
	soldier._process(delta)

func _vec_data(pos: Vector3) -> Array:
	return [pos.x, pos.y, pos.z]

func _data_vec(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _near(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return a.distance_to(b) <= tolerance

func _check(name: String, passed: bool, details: Dictionary) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	if not passed:
		_fail(name, JSON.stringify(details))

func _fail(name: String, reason: String) -> void:
	failures.append("%s: %s" % [name, reason])

func _finish() -> void:
	var report := {"suite": "production_soldier_attack_move_behavior_regression", "headless": DisplayServer.get_name() == "headless", "passed": failures.is_empty(), "checks": checks, "failures": failures}
	var path := "user://soldier_attack_move_regression.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(main_codec):
		main_codec.free()
	await process_frame
	print("SOLDIER_ATTACK_MOVE_REGRESSION=" + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

