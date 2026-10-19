extends Node

const BuildingScript := preload("res://scripts/building.gd")
const SoldierScript := preload("res://scripts/soldier.gd")
const Catalog := preload("res://scripts/building_catalog.gd")

var report: Dictionary = {
	"schema":"tower_coverage_probe_v1",
	"scenario":"controlled_arrow_tower_coverage_and_hit_feedback",
	"fixture":"one no-cost foundation built by a normal villager build order; standard zombie stats; enemy movement AI paused during controlled targeting/flight samples to hold positions",
	"damage_range_wave_rules_changed":false,
	"natural_win_claim":false,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var game := _main_game()
	if game == null:
		_finish(false, "initial_main_missing")
		return
	var start_button: Button = game.get("_start_begin_button")
	var seed_edit: LineEdit = game.get("_seed_edit")
	if start_button == null or seed_edit == null:
		_finish(false, "production_start_menu_missing")
		return
	seed_edit.text = "42"
	start_button.emit_signal("pressed")
	if not await _wait_until(func() -> bool: return _main_game() != null and bool(_main_game().get("_match_started")), 90000):
		_finish(false, "production_match_start_timeout")
		return
	game = _main_game()
	var tower_def: Dictionary = Catalog.get_def(Catalog.ARROW_TOWER)
	var tower_range: float = float(tower_def.get("attack_range", 0.0))
	var tower_damage: float = float(tower_def.get("attack_damage", 0.0))
	var tower_interval: float = float(tower_def.get("attack_interval", 0.0))
	var ghost_before: int = _count_named(get_tree().root, "AttackRangePreviewXZ")
	game.set("place_kind", Catalog.ARROW_TOWER)
	game.call("_ensure_ghost", tower_def)
	var ghost: Node3D = game.get("ghost")
	var preview: MeshInstance3D = ghost.get_node_or_null("AttackRangePreviewXZ") as MeshInstance3D if ghost != null else null
	var preview_mesh: TorusMesh = preview.mesh as TorusMesh if preview != null else null
	var preview_no_physics: bool = preview != null and ghost.find_children("*", "CollisionObject3D", true, false).is_empty() and ghost.find_children("*", "CollisionShape3D", true, false).is_empty()
	var preview_exact_catalog_range: bool = preview_mesh != null and is_equal_approx(preview_mesh.inner_radius, tower_range - 0.065) and is_equal_approx(preview_mesh.outer_radius, tower_range + 0.065)
	report["placement_preview_real_xz_range"] = preview_exact_catalog_range
	report["placement_preview_non_physical"] = preview_no_physics
	report["placement_preview_before_count"] = ghost_before
	game.set("place_kind", -1)
	game.call("_clear_ghost")
	await _wait_frames(2)
	var preview_cleanup: bool = _count_named(get_tree().root, "AttackRangePreviewXZ") == 0
	report["placement_preview_cleanup"] = preview_cleanup
	if not preview_exact_catalog_range or not preview_no_physics or not preview_cleanup:
		_finish(false, "placement_preview_range_or_cleanup_failed")
		return

	# The only free part is the controlled test fixture: the production building
	# node uses its ordinary incomplete state and a real villager build order.
	var tower_pos := Vector3(11.0, 0.0, 7.0)
	game.set("place_kind", Catalog.ARROW_TOWER)
	var tower_site_buildable: bool = bool(game.call("_placement_valid_at", tower_pos))
	game.set("place_kind", -1)
	if not tower_site_buildable:
		_finish(false, "tower_fixture_site_not_buildable")
		return
	var tower: Node3D = BuildingScript.new()
	tower.call("setup", Catalog.ARROW_TOWER, tower_pos, "player", false)
	(game.get("world") as Node).add_child(tower)
	var builder := _nearest_living_villager(game, tower_pos)
	if builder == null:
		_finish(false, "production_builder_missing")
		return
	game.call("_clear_selection")
	game.call("_add_to_selection", tower)
	game.call("_refresh_selection_hud")
	var hud: Node = game.get("hud")
	var unfinished_status: Dictionary = tower.call("get_tower_ui_state")
	var unfinished_hud_status: String = str(hud.get("_hint_l").text)
	var unfinished_no_range_ring: bool = not bool(tower.get("_attack_range_ring").visible)
	(builder as Node3D).call("command_build", tower)
	var progress_before: float = float(tower.get("build_progress"))
	if not await _wait_until(func() -> bool: return is_instance_valid(tower) and bool(tower.get("is_complete")), 60000):
		_finish(false, "production_tower_construction_timeout")
		return
	var progress_after: float = float(tower.get("build_progress"))
	game.call("_refresh_selection_hud")
	var completed_ring: MeshInstance3D = tower.get_node_or_null("AttackRangeXZ") as MeshInstance3D
	var selected_range_ring_visible: bool = completed_ring != null and completed_ring.visible
	var selection_info: String = str(hud.get("_info_armor").text)
	var no_target_status: Dictionary = tower.call("get_tower_ui_state")
	report["tower_fixture"] = {"building_instance_id":tower.get_instance_id(),"builder_instance_id":builder.get_instance_id(),"position":_vec(tower.global_position),"constructed_from_production_foundation":true,"build_progress_before":progress_before,"build_progress_after":progress_after,"build_time":float(tower.get("build_time")),"complete":bool(tower.get("is_complete"))}
	report["tower_selected_ui_stats"] = selection_info
	report["unfinished_tower_status"] = {"state":unfinished_status.get("state"),"text":unfinished_status.get("text"),"hud":unfinished_hud_status,"range_ring_hidden":unfinished_no_range_ring}
	report["selected_tower_range_ring_visible"] = selected_range_ring_visible
	report["no_target_status"] = no_target_status
	var stats_ok: bool = "射程%.1fm" % tower_range in selection_info and "伤害%.0f" % tower_damage in selection_info and "间隔%.2fs" % tower_interval in selection_info
	if not bool(tower.get("is_complete")) or not selected_range_ring_visible or not stats_ok or str(no_target_status.get("state")) != "no_target" or str(unfinished_status.get("state")) != "unfinished" or not unfinished_no_range_ring or not unfinished_hud_status.contains("未完工"):
		_finish(false, "selected_tower_stats_or_unfinished_state_failed")
		return

	# Build placement and tower use the same catalog radius. Combat itself uses
	# Combat.find_nearest_enemy's strict target-center XZ comparison: d < range.
	var out_target: Node3D = _spawn_zombie(game, tower.global_position + Vector3(tower_range, 0.0, 0.0))
	var out_id: int = out_target.get_instance_id()
	out_target.set_process(false)
	out_target.set_physics_process(false)
	var boundary_status: Dictionary = tower.call("get_tower_ui_state")
	game.call("_refresh_selection_hud")
	var boundary_hud_status: String = str(hud.get("_hint_l").text)
	var arrows_before_boundary: int = _arrow_count_for(tower)
	await _wait_seconds(0.5)
	var arrows_at_boundary: int = _arrow_count_for(tower)
	report["exact_boundary"] = {"comparison":"strict center XZ distance < attack_range; equality is outside","target_id":out_id,"target_pos":_vec(out_target.global_position),"center_distance":CombatUtilDistance(tower.global_position, out_target.global_position),"range":tower_range,"status":boundary_status,"arrows_before":arrows_before_boundary,"arrows_after_half_second":arrows_at_boundary}
	if arrows_at_boundary != arrows_before_boundary or str(boundary_status.get("state")) != "out_of_range":
		_finish(false, "exact_range_boundary_not_exclusive")
		return
	out_target.global_position = tower.global_position + Vector3(tower_range - 0.01, 0.0, 0.0)
	var in_range_status: Dictionary = tower.call("get_tower_ui_state")
	game.call("_refresh_selection_hud")
	var ready_hud_status: String = str(hud.get("_hint_l").text)
	if str(in_range_status.get("state")) != "ready":
		_finish(false, "within_range_status_not_ready")
		return

	# Observe actual tower-created projectiles and actual victim HP changes until
	# standard zombie death; no direct take_damage call or injected HP is used.
	var zombie_hp_before: float = float(out_target.get("hp"))
	var seen_projectiles: Dictionary = {}
	var shot_records: Array = []
	var hp_records: Array = []
	var previous_hp: float = zombie_hp_before
	var first_cooldown: float = -1.0
	var firing_state: Dictionary = {}
	var cooling_state: Dictionary = {}
	var firing_hud_status := ""
	var cooling_hud_status := ""
	var death_deadline: int = Time.get_ticks_msec() + 20000
	while bool(out_target.get("alive")) and Time.get_ticks_msec() < death_deadline:
		for projectile in get_tree().get_nodes_in_group("arrows"):
			if projectile.get("_attacker") == tower and projectile.get("_target") == out_target:
				var projectile_id: int = projectile.get_instance_id()
				if not seen_projectiles.has(projectile_id):
					seen_projectiles[projectile_id] = true
					if first_cooldown < 0.0:
						first_cooldown = float(tower.get("_tower_cd"))
					shot_records.append({"projectile_id":projectile_id,"attacker_id":tower.get_instance_id(),"target_id":out_target.get_instance_id(),"launch_pos":_vec(projectile.global_position),"target_pos_at_launch":_vec(out_target.global_position),"center_distance_at_launch":CombatUtilDistance(tower.global_position, out_target.global_position),"cooldown_after_launch":float(tower.get("_tower_cd"))})
					var active_state: Dictionary = tower.call("get_tower_ui_state")
					if str(active_state.get("state", "")) == "firing":
						firing_state = active_state
						game.call("_refresh_selection_hud")
						firing_hud_status = str(hud.get("_hint_l").text)
		var current_hp: float = float(out_target.get("hp"))
		if current_hp < previous_hp:
			hp_records.append({"hp_before":previous_hp,"hp_after":current_hp,"actual_delta":previous_hp-current_hp,"target_id":out_target.get_instance_id(),"attacker_id":tower.get_instance_id()})
			previous_hp = current_hp
		if not cooling_state.is_empty() or _has_arrow_for(tower, out_target):
			pass
		else:
			var cooling_candidate: Dictionary = tower.call("get_tower_ui_state")
			if str(cooling_candidate.get("state", "")) == "cooldown":
				cooling_state = cooling_candidate
				game.call("_refresh_selection_hud")
				cooling_hud_status = str(hud.get("_hint_l").text)
		await get_tree().process_frame
	var zombie_died: bool = not bool(out_target.get("alive")) and float(out_target.get("hp")) <= 0.0
	var final_zombie_hp: float = float(out_target.get("hp"))
	if final_zombie_hp < previous_hp:
		hp_records.append({"hp_before":previous_hp,"hp_after":final_zombie_hp,"actual_delta":previous_hp-final_zombie_hp,"target_id":out_target.get_instance_id(),"attacker_id":tower.get_instance_id()})
	var expected_arrow_damage: float = maxf(1.0, tower_damage - float(out_target.get("armor_pierce")))
	var damage_ok: bool = not hp_records.is_empty() and hp_records.all(func(record: Dictionary) -> bool: return is_equal_approx(float(record.get("actual_delta", 0.0)), minf(float(record.get("hp_before", 0.0)), expected_arrow_damage)))
	report["real_arrow_combat"] = {"attacker_id":tower.get_instance_id(),"target_id":out_id,"target_initial_hp":zombie_hp_before,"target_max_hp":float(out_target.get("max_hp")),"target_armor_pierce":int(out_target.get("armor_pierce")),"base_damage":tower_damage,"projectile_speed":28.0,"attack_interval":tower_interval,"first_cooldown_after_launch":first_cooldown,"shot_count_observed":shot_records.size(),"shots":shot_records,"actual_hp_deltas":hp_records,"target_hp_at_end":float(out_target.get("hp")),"normal_target_death":zombie_died}
	var hud_states_ok: bool = boundary_hud_status.contains("射程外") and ready_hud_status.contains("可攻击") and firing_hud_status.contains("正在射击") and cooling_hud_status.contains("冷却中")
	report["firing_and_cooldown_ui_states"] = {"firing":firing_state,"cooldown":cooling_state,"ready_before_fire":in_range_status,"hud":{"out_of_range":boundary_hud_status,"ready":ready_hud_status,"firing":firing_hud_status,"cooldown":cooling_hud_status}}
	if not zombie_died or not damage_ok or shot_records.size() < 1 or firing_state.is_empty() or cooling_state.is_empty() or not hud_states_ok:
		_finish(false, "arrow_launch_hit_damage_or_death_failed")
		return
	var after_death_status: Dictionary = tower.call("get_tower_ui_state")
	game.call("_refresh_selection_hud")
	var no_target_hud_status: String = str(hud.get("_hint_l").text)
	report["target_death_reacquire_state"] = after_death_status
	report["target_death_reacquire_hud"] = no_target_hud_status
	if str(after_death_status.get("state")) != "no_target" or not no_target_hud_status.contains("无敌方目标"):
		_finish(false, "dead_target_not_cleared_from_tower_status")
		return
	var melee_villager: Node3D = _nearest_living_villager(game, Vector3.ZERO)
	if melee_villager == null:
		_finish(false, "melee_regression_worker_missing")
		return
	var melee_attacker: Node3D = _spawn_zombie(game, melee_villager.global_position + Vector3(0.25, 0.0, 0.0))
	melee_attacker.set("attack_target", melee_villager)
	melee_attacker.set("state", 3)
	var melee_hp_before: float = float(melee_villager.get("hp"))
	var melee_attack_id: int = melee_attacker.get_instance_id()
	var melee_target_id: int = melee_villager.get_instance_id()
	if not await _wait_until(func() -> bool: return float(melee_villager.get("hp")) < melee_hp_before, 3500):
		_finish(false, "standard_melee_did_not_land")
		return
	var melee_hp_after: float = float(melee_villager.get("hp"))
	var melee_actual_delta: float = melee_hp_before - melee_hp_after
	var melee_expected_delta: float = maxf(1.0, float(melee_attacker.get("attack_damage")) - float(melee_villager.get("armor_melee")))
	report["melee_attacker_parameter_regression"] = {"attacker_id":melee_attack_id,"target_id":melee_target_id,"attacker_pos":_vec(melee_attacker.global_position),"target_pos":_vec(melee_villager.global_position),"center_distance":CombatUtilDistance(melee_attacker.global_position, melee_villager.global_position),"attack_damage":float(melee_attacker.get("attack_damage")),"target_melee_armor":int(melee_villager.get("armor_melee")),"expected_actual_damage":melee_expected_delta,"actual_hp_before":melee_hp_before,"actual_hp_after":melee_hp_after,"actual_hp_delta":melee_actual_delta,"unchanged_formula_verified":is_equal_approx(melee_actual_delta, melee_expected_delta)}
	melee_attacker.queue_free()
	if not is_equal_approx(melee_actual_delta, melee_expected_delta):
		_finish(false, "melee_damage_formula_changed")
		return

	# A live in-flight arrow is allowed to finish tracking its launched target.
	# Once the target moves beyond range and the next cooldown ends, the tower
	# must stop launching at it; a new in-range enemy must then be reacquired.
	var moving_target: Node3D = _spawn_zombie(game, tower.global_position + Vector3(5.0, 0.0, 0.0))
	moving_target.set_process(false)
	moving_target.set_physics_process(false)
	if not await _wait_until(func() -> bool: return _has_arrow_for(tower, moving_target), 3000):
		_finish(false, "second_target_not_acquired")
		return
	var moving_shot: Node3D = _arrow_for(tower, moving_target)
	var moving_shot_id: int = moving_shot.get_instance_id() if moving_shot != null else 0
	moving_target.global_position = tower.global_position + Vector3(tower_range + 0.5, 0.0, 0.0)
	var moved_out_in_flight_state: Dictionary = tower.call("get_tower_ui_state")
	await _wait_until(func() -> bool: return not _has_arrow_for(tower, moving_target) and float(tower.get("_tower_cd")) <= 0.0, 5000)
	await _wait_seconds(0.35)
	var no_repeat_shot_outside: bool = not _has_arrow_for(tower, moving_target)
	var moved_out_state: Dictionary = tower.call("get_tower_ui_state")
	var reacquire_target: Node3D = _spawn_zombie(game, tower.global_position + Vector3(tower_range - 0.02, 0.0, 0.0))
	reacquire_target.set_process(false)
	reacquire_target.set_physics_process(false)
	var reacquired: bool = await _wait_until(func() -> bool: return _has_arrow_for(tower, reacquire_target), 5000)
	report["moving_target_reacquire"] = {"target_id":moving_target.get_instance_id(),"projectile_id":moving_shot_id,"out_position":_vec(moving_target.global_position),"out_center_distance":CombatUtilDistance(tower.global_position, moving_target.global_position),"out_state_during_projectile_flight":moved_out_in_flight_state,"out_state_after_projectile_cooldown":moved_out_state,"no_repeat_shot_while_outside":no_repeat_shot_outside,"new_target_id":reacquire_target.get_instance_id(),"new_target_position":_vec(reacquire_target.global_position),"new_target_center_distance":CombatUtilDistance(tower.global_position, reacquire_target.global_position),"new_target_reacquired":reacquired}
	if not no_repeat_shot_outside or not reacquired or str(moved_out_state.get("state", "")) != "out_of_range":
		_finish(false, "moving_target_reacquire_failed")
		return
	for controlled_enemy in [out_target, moving_target, reacquire_target]:
		if is_instance_valid(controlled_enemy):
			controlled_enemy.queue_free()
	await _wait_frames(2)

	# Pause hides the display-only range object. Save/load replaces the building
	# node and recreates exactly one hidden ring; selection/camera are not changed.
	var tower_before_load_id: int = tower.get_instance_id()
	game.call("_set_pause_menu_open", true)
	var hidden_while_paused: bool = not bool(tower.get("_attack_range_ring").visible) and get_tree().paused
	var save_ok: bool = bool(game.call("_save_match"))
	if not save_ok:
		_finish(false, "save_during_tower_selection_failed")
		return
	game.call("_continue_saved_match")
	if not await _wait_until(func() -> bool: return not bool(game.get("_start_operation_busy")), 40000):
		_finish(false, "tower_continue_load_timeout")
		return
	await _wait_seconds(0.1)
	var restored_tower := _find_player_tower(game)
	var restored_ring: MeshInstance3D = restored_tower.get_node_or_null("AttackRangeXZ") as MeshInstance3D if restored_tower != null else null
	var tower_ring_count: int = _count_named(game.get("world"), "AttackRangeXZ")
	var no_preview_after_load: bool = _count_named(get_tree().root, "AttackRangePreviewXZ") == 0
	game.call("_resume_from_pause")
	var restored_pause_cleared: bool = not get_tree().paused
	if restored_tower != null:
		game.call("_clear_selection")
		game.call("_add_to_selection", restored_tower)
		game.call("_refresh_selection_hud")
	var restored_ring_visible: bool = restored_ring != null and restored_ring.visible
	report["pause_save_load_cleanup"] = {"hidden_while_paused":hidden_while_paused,"save_ok":save_ok,"old_tower_id":tower_before_load_id,"restored_tower_id":restored_tower.get_instance_id() if restored_tower != null else 0,"one_range_ring_after_load":tower_ring_count == 1,"preview_absent_after_load":no_preview_after_load,"pause_cleared":restored_pause_cleared,"selected_range_ring_visible_after_resume":restored_ring_visible}
	if not hidden_while_paused or not save_ok or restored_tower == null or tower_ring_count != 1 or not no_preview_after_load or not restored_pause_cleared or not restored_ring_visible:
		_finish(false, "pause_save_load_range_overlay_cleanup_failed")
		return

	var old_game_id: int = game.get_instance_id()
	game.call("_clear_selection")
	game.call("_on_defeat_to_start")
	if not await _wait_until(func() -> bool: return _main_game() != null and _main_game().get_instance_id() != old_game_id and not bool(_main_game().get("_match_started")), 40000):
		_finish(false, "return_to_menu_timeout")
		return
	var menu_clear: bool = _count_named(get_tree().root, "AttackRangeXZ") == 0 and _count_named(get_tree().root, "AttackRangePreviewXZ") == 0
	report["return_to_menu_clears_range_objects"] = menu_clear
	_finish(menu_clear, "tower_coverage_actual_fire_damage_reacquire_and_overlay_lifecycle_passed" if menu_clear else "range_objects_remained_after_menu_reload")

func _main_game() -> Node:
	return get_tree().get_first_node_in_group("main_game")

func _spawn_zombie(game: Node, pos: Vector3) -> Node3D:
	var zombie: Node3D = SoldierScript.new()
	zombie.call("setup", pos, "enemy", true)
	(game.get("world") as Node).add_child(zombie)
	return zombie

func _nearest_living_villager(game: Node, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for villager in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(villager) or not bool(villager.get("alive")) or str(villager.get("team")) != "player":
			continue
		var distance: float = CombatUtilDistance((villager as Node3D).global_position, pos)
		if distance < best_distance:
			best_distance = distance
			best = villager as Node3D
	return best

func _find_player_tower(game: Node) -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.ARROW_TOWER and bool(building.get("alive")):
			return building as Node3D
	return null

func _arrow_for(tower: Node, target: Node) -> Node3D:
	for projectile in get_tree().get_nodes_in_group("arrows"):
		if projectile.get("_attacker") == tower and projectile.get("_target") == target:
			return projectile as Node3D
	return null

func _has_arrow_for(tower: Node, target: Node) -> bool:
	return _arrow_for(tower, target) != null

func _arrow_count_for(tower: Node) -> int:
	var count: int = 0
	for projectile in get_tree().get_nodes_in_group("arrows"):
		if projectile.get("_attacker") == tower:
			count += 1
	return count

func _count_named(root: Node, node_name: String) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var count: int = 1 if root.name == node_name else 0
	for child in root.get_children():
		count += _count_named(child, node_name)
	return count

func _vec(pos: Vector3) -> Array:
	return [pos.x, pos.y, pos.z]

func CombatUtilDistance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()

func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame

func _wait_seconds(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _finish(passed: bool, reason: String) -> void:
	if bool(report.get("finished", false)):
		return
	report["passed"] = passed
	report["reason"] = reason
	report["completed_utc"] = Time.get_datetime_string_from_system(true, true)
	report["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open("user://tower_coverage_probe.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[tower-coverage] ", JSON.stringify({"passed":passed,"reason":reason,"report":"user://tower_coverage_probe.json"}))
	get_tree().quit(0 if passed else 1)


