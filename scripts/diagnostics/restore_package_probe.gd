extends Node
## Runs from the exported game's normal main-scene entrypoint for standalone restore verification.

const VILLAGER := preload("res://scripts/villager.gd")
const SOLDIER := preload("res://scripts/soldier.gd")
const PROFILE := preload("res://scripts/diagnostics/restore_profile.gd")

var _run_id := "missing-run-id"
var _fixture_path := ""
var _report: Dictionary = {"schema": "standalone_restore_continue_probe_v1", "passed": false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_run_id = _arg(args, "run-id", _run_id)
	_fixture_path = _arg(args, "fixture-path", "")
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	Engine.set_meta(PROFILE.TRACE_META, true)
	Engine.set_meta(PROFILE.ORIGIN_META, Time.get_ticks_usec())
	Engine.set_meta(PROFILE.EVENTS_META, [])
	_report.merge({"run_id": _run_id, "headless": DisplayServer.get_name() == "headless", "executable": OS.get_executable_path(), "user_data_dir": OS.get_user_data_dir(), "fixture_path": _fixture_path, "pid": OS.get_process_id(), "seed": 42, "unit_scale_expected": 180}, true)
	if not bool(_report.headless) or _fixture_path.is_empty():
		_finish(false, "headless_or_fixture_argument_missing")
		return
	var menu_game: Node = await _wait_for_game(func(game: Node) -> bool: return game.get("_start_begin_button") != null, 300)
	if menu_game == null:
		_finish(false, "production_start_menu_timeout")
		return
	(menu_game.get("_seed_edit") as LineEdit).text = "42"
	(menu_game.get("_start_begin_button") as Button).pressed.emit()
	var game: Node = await _wait_for_game(func(candidate: Node) -> bool: return bool(candidate.get("_match_started")) and candidate.get("world") != null, 3600)
	if game == null:
		_finish(false, "production_seed_42_start_timeout")
		return
	for _frame in 120:
		await get_tree().process_frame
	var setup := _populate_180_unit_fixture(game)
	if not bool(setup.get("ok", false)):
		_finish(false, str(setup.get("error", "fixture_setup_failed")))
		return
	var fixture_file := FileAccess.open(_fixture_path, FileAccess.READ)
	if fixture_file == null:
		_finish(false, "fixed_save_fixture_open_failed")
		return
	var fixture_bytes := fixture_file.get_buffer(fixture_file.get_length())
	fixture_file.close()
	var fixture_save: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	if not fixture_save is Dictionary:
		_finish(false, "fixed_save_fixture_invalid_json")
		return
	var active_save := FileAccess.open("user://aoelite3d_save.json", FileAccess.WRITE)
	if active_save == null:
		_finish(false, "isolated_user_save_open_failed")
		return
	active_save.store_buffer(fixture_bytes)
	active_save.close()
	var save_hash := FileAccess.get_sha256("user://aoelite3d_save.json")
	var original_scene_id := game.get_instance_id()
	var before_counts := _unit_counts()
	var continue_start_usec := Time.get_ticks_usec()
	PROFILE.mark("package_probe.production_continue_method_called", {"route": "Main._continue_saved_match", "map_seed": 42})
	game.call("_continue_saved_match")
	var ready := false
	for _frame in 360:
		await get_tree().process_frame
		game = get_tree().get_first_node_in_group("main_game")
		if game != null and game.get_instance_id() == original_scene_id and not bool(game.get("_start_operation_busy")) and get_tree().paused:
			ready = true
			break
	if not ready:
		_finish(false, "production_continue_restore_timeout")
		return
	var ready_usec := Time.get_ticks_usec()
	var restored := _state_snapshot(game)
	var expected_resources: Dictionary = fixture_save.get("resources", {})
	var expected_barracks: Dictionary = {}
	for building in fixture_save.get("entities", {}).get("buildings", []):
		if int(building.get("kind", -1)) == 12:
			expected_barracks = building
			break
	var expected_villager: Dictionary = fixture_save.get("entities", {}).get("villagers", [])[0]
	var expected_active_soldier: Dictionary = {}
	for soldier in fixture_save.get("entities", {}).get("soldiers", []):
		if not bool(soldier.get("is_zombie", false)) and bool(soldier.get("attack_move_active", false)):
			expected_active_soldier = soldier
			break
	var checks := {
		"fixed_save_hash_preserved": save_hash == _sha256_bytes(fixture_bytes),
		"seed_and_same_scene_reused": int(game.get("map_seed")) == 42 and game.get_instance_id() == original_scene_id,
		"unit_scale_matches": int(restored.units.get("villagers", 0)) == 30 and int(restored.units.get("player_soldiers", 0)) == 75 and int(restored.units.get("enemy_zombies", 0)) == 75,
		"resources": int(restored.resources.get("wood", -1)) == int(expected_resources.get("wood", -2)) and int(restored.resources.get("meat", -1)) == int(expected_resources.get("meat", -2)) and int(restored.resources.get("stone", -1)) == int(expected_resources.get("stone", -2)) and int(restored.resources.get("gold", -1)) == int(expected_resources.get("gold", -2)),
		"research_age_and_forestry_effect": int(restored.age) == int(fixture_save.get("age", -1)) and Array(restored.researched_techs).has("improved_axes") and is_equal_approx(float(restored.wood_gather_multiplier), 1.25) and int(restored.wood_carry_bonus) == 5,
		"paid_training_queue_and_progress_seed": Array(restored.train_queue) == Array(expected_barracks.get("train_queue", [])) and bool(restored.train_paid) == bool(expected_barracks.get("train_paid", false)) and is_equal_approx(float(restored.train_timer), float(expected_barracks.get("train_timer", -1))),
		"villager_target_and_order_queue": bool(restored.villager_target_valid) and bool(restored.villager_resume_same_target) and str(restored.villager_resume_key) == str(expected_villager.get("resume_key", "")) and int(restored.villager_orders) == Array(expected_villager.get("orders", [])).size(),
		"soldier_attack_move_and_queued_commands": bool(restored.attack_move_active) and int(restored.attack_move_orders) == Array(expected_active_soldier.get("orders", [])).size() and int(restored.queued_soldier_orders) > 0,
		"night_clock_and_zombie_buffs": bool(restored.is_night) and is_equal_approx(float(restored.clock_minutes), float(fixture_save.get("clock_minutes", -1))) and int(restored.night_buffed_zombies) == _expected_night_zombies(fixture_save),
		"challenge_wave_and_spawn_queue": int(restored.horde_wave) == int(fixture_save.get("horde_wave", -1)) and int(restored.horde_mode) == int(fixture_save.get("horde_mode", -1)) and Array(restored.horde_spawn_queue).size() == Array(fixture_save.get("horde_spawn_queue", [])).size(),
		"paused_state_preserved": bool(restored.paused),
	}
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	game.call("_set_pause_menu_open", false)
	for _frame in 60:
		await get_tree().process_frame
	var settled := _state_snapshot(game)
	var progressed := float(settled.game_time) > float(restored.game_time) and float(settled.train_timer) < float(restored.train_timer) and not get_tree().paused
	checks["resumes_and_advances_after_unpause"] = progressed
	passed = passed and progressed
	_report.merge({"production_fixture_setup": setup, "fixed_save_sha256": save_hash, "restored": restored, "checks": checks, "post_60_frames": settled, "continue_to_ready_usec": ready_usec - continue_start_usec, "same_scene_instance": game.get_instance_id() == original_scene_id, "unit_counts_before_continue": before_counts, "restore_trace_events": Engine.get_meta(PROFILE.EVENTS_META, [])}, true)
	_finish(passed, "standalone_package_restore_verified" if passed else "standalone_package_restore_state_mismatch")

func _populate_180_unit_fixture(game: Node) -> Dictionary:
	var world: Node3D = game.get("world")
	if world == null:
		return {"ok": false, "error": "world_missing"}
	var wood: Array[Node] = []
	for node in get_tree().get_nodes_in_group("resources"):
		if int(node.get("kind")) == 0 and int(node.get("amount")) > 0: wood.append(node)
	if wood.is_empty():
		return {"ok": false, "error": "seeded_wood_missing"}
	wood.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.length_squared() < b.global_position.length_squared())
	var target: Node3D = wood[0]
	var existing_villagers: Array = get_tree().get_nodes_in_group("villagers")
	for i in 25:
		var angle := TAU * float(i) / 25.0
		var worker: Node3D = VILLAGER.new()
		worker.setup(Vector3(cos(angle) * (8.0 + float(i % 7) * 0.8), 0.0, sin(angle) * (8.0 + float(i % 7) * 0.8)), "player")
		world.add_child(worker)
		existing_villagers.append(worker)
	for worker in existing_villagers:
		worker.call("command_gather", target)
	for i in 75:
		var angle := TAU * float(i) / 75.0
		var fighter: Node3D = SOLDIER.new()
		fighter.setup(Vector3(cos(angle) * (12.0 + float(i % 9) * 0.45), 0.0, sin(angle) * (12.0 + float(i % 9) * 0.45)), "player", false)
		world.add_child(fighter)
		fighter.command_attack_move(Vector3.ZERO)
	var spawned: Array = game.call("_spawn_horde_wave", 1, 75)
	if spawned.size() < 75:
		spawned.append_array(game.call("_flush_horde_spawn_queue", 75 - spawned.size()))
	var counts := _unit_counts()
	return {"ok": int(counts.total) == 180, "unit_counts": counts, "gather_target_kind": int(target.get("kind")), "zombies_spawned": spawned.size()}

func _unit_counts() -> Dictionary:
	var villagers := 0
	var players := 0
	var zombies := 0
	for unit in get_tree().get_nodes_in_group("villagers"):
		if bool(unit.get("alive")) and str(unit.get("team")) == "player": villagers += 1
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not bool(unit.get("alive")): continue
		if bool(unit.get("is_zombie")): zombies += 1
		elif str(unit.get("team")) == "player": players += 1
	return {"villagers": villagers, "player_soldiers": players, "enemy_zombies": zombies, "total": villagers + players + zombies}

func _state_snapshot(game: Node) -> Dictionary:
	var research: Node = game.get("research")
	var barracks: Node = null
	for building in get_tree().get_nodes_in_group("buildings"):
		if int(building.get("kind")) == 12: barracks = building; break
	var villager: Node = null
	for candidate in get_tree().get_nodes_in_group("villagers"):
		if str(candidate.get("team")) == "player": villager = candidate; break
	var active_soldier: Node = null
	var queued_soldier_orders := 0
	for candidate in get_tree().get_nodes_in_group("soldiers"):
		if str(candidate.get("team")) != "player" or bool(candidate.get("is_zombie")): continue
		if active_soldier == null and candidate.get("_attack_move_active") == true: active_soldier = candidate
		queued_soldier_orders += Array(candidate.get("order_queue")).size()
	var night_zombies := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie.get("_night_buffed") == true: night_zombies += 1
	var v_orders: Array = villager.get("order_queue") if villager != null else []
	var s_orders: Array = active_soldier.get("order_queue") if active_soldier != null else []
	return {"units": _unit_counts(), "resources": {"wood": int(game.get("wood")), "meat": int(game.get("meat")), "stone": int(game.get("stone")), "gold": int(game.get("gold"))}, "age": int(research.get("age")) if research != null else -1, "researched_techs": Array(research.get("researched_techs")) if research != null else [], "wood_gather_multiplier": float(villager.get("wood_gather_multiplier")) if villager != null else -1.0, "wood_carry_bonus": int(villager.get("wood_carry_bonus")) if villager != null else -1, "train_queue": Array(barracks.get("train_queue")) if barracks != null else [], "train_paid": barracks.get("train_paid") == true if barracks != null else false, "train_timer": float(barracks.get("train_timer")) if barracks != null else -1.0, "villager_target_valid": villager != null and is_instance_valid(villager.get("gather_target")), "villager_resume_same_target": villager != null and villager.get("resume_resource") == villager.get("gather_target"), "villager_resume_key": str(villager.get("resume_key")) if villager != null else "", "villager_orders": v_orders.size(), "attack_move_active": active_soldier != null, "attack_move_orders": s_orders.size(), "queued_soldier_orders": queued_soldier_orders, "clock_minutes": float(game.get("_clock_minutes")), "is_night": game.call("_is_game_night") == true, "night_buffed_zombies": night_zombies, "game_time": float(game.get("_game_time")), "horde_wave": int(game.get("_horde_wave")), "horde_mode": int(game.get("_horde_mode")), "horde_spawn_queue": Array(game.get("_horde_spawn_queue")).duplicate(true), "paused": game.get_tree().paused}

func _wait_for_game(predicate: Callable, max_frames: int) -> Node:
	for _frame in max_frames:
		var game := get_tree().get_first_node_in_group("main_game")
		if game != null and predicate.call(game): return game
		await get_tree().process_frame
	return null

func _expected_night_zombies(data: Dictionary) -> int:
	var count := 0
	for soldier in data.get("entities", {}).get("soldiers", []):
		if bool(soldier.get("is_zombie", false)) and bool(soldier.get("night_buffed", false)): count += 1
	return count

func _arg(args: Array, key: String, fallback: String) -> String:
	for arg in args:
		var text := str(arg)
		if text.begins_with("--" + key + "="): return text.get_slice("=", 1)
	return fallback

func _sha256_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

func _finish(passed: bool, reason: String) -> void:
	_report["passed"] = passed
	_report["reason"] = reason
	_report["completed_utc_ticks_usec"] = Time.get_ticks_usec()
	var file := FileAccess.open("user://restore_package_%s.json" % _run_id, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	print("[standalone-restore-probe] ", JSON.stringify({"passed": passed, "reason": reason, "run_id": _run_id, "report": "user://restore_package_%s.json" % _run_id}))
	get_tree().quit(0 if passed else 1)
