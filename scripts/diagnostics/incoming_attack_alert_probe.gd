extends Node

const SoldierScript := preload("res://scripts/soldier.gd")
const BuildingScript := preload("res://scripts/building.gd")
const Catalog := preload("res://scripts/building_catalog.gd")

var report: Dictionary = {
	"schema": "incoming_attack_alert_probe_v1",
	"scenario": "controlled_battle_player_attack_warning",
	"controller": "production start menu + production unit combat tick + actual take_damage",
	"headless_audio_heard": false,
	"unit_or_building_hp_injected": false,
	"damage_values_changed": false,
	"natural_wave_or_win_claim": false,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _run() -> void:
	var game := _main_game()
	if game == null:
		_finish(false, "initial_main_missing")
		return
	var menu_button: Button = game.get("_start_begin_button")
	var seed_edit: LineEdit = game.get("_seed_edit")
	if menu_button == null or seed_edit == null:
		_finish(false, "production_start_menu_missing")
		return
	seed_edit.text = "42"
	menu_button.emit_signal("pressed")
	if not await _wait_until(func() -> bool: return _main_game() != null and bool(_main_game().get("_match_started")), 90000):
		_finish(false, "production_match_start_timeout")
		return
	game = _main_game()
	report["seed"] = int(game.get("map_seed"))
	report["mode"] = int(game.get("_horde_mode"))
	var villages := _living_team("villagers", "player")
	var town_center := _find_building(Catalog.TOWN_CENTER)
	if villages.is_empty() or town_center == null:
		_finish(false, "production_start_entities_missing")
		return
	var worker: Node3D = villages[0]
	# Persistent non-combat alert fixtures let the regression prove incoming
	# damage does not retire/recreate existing construction and training buttons.
	var site: Node3D = BuildingScript.new()
	site.call("setup", Catalog.HOUSE, Vector3(-13.0, 0.0, -6.0), "player", false)
	(game.get("world") as Node).add_child(site)
	var barracks: Node3D = BuildingScript.new()
	barracks.call("setup", Catalog.ATTACK_BARRACKS, Vector3(14.0, 0.0, -5.0), "player", true)
	(game.get("world") as Node).add_child(barracks)
	barracks.call("enqueue_train", "soldier")
	game.call("_refresh_operational_alerts")
	var site_alert_key := "construction:%s" % str(site.get_instance_id())
	var training_alert_key := "train:%s" % str(barracks.get_instance_id())
	if not await _wait_until(func() -> bool: return _button_for_key(game, site_alert_key) != null and _button_for_key(game, training_alert_key) != null, 4000):
		_finish(false, "construction_or_training_fixture_alert_missing")
		return
	var site_button: Button = _button_for_key(game, site_alert_key)
	var training_button: Button = _button_for_key(game, training_alert_key)
	var site_button_id: int = site_button.get_instance_id()
	var training_button_id: int = training_button.get_instance_id()
	var move_destination: Vector3 = worker.global_position + Vector3(3.0, 0.0, 5.0)
	var wood_before := int(game.get("wood"))
	var meat_before := int(game.get("meat"))
	worker.call("command_move", move_destination)
	game.call("_clear_selection")
	game.call("_add_to_selection", town_center)
	game.call("_queue_train", "villager")
	await _wait_until(func() -> bool: return int(game.get("meat")) < meat_before, 1800)
	game.call("_refresh_operational_alerts")
	await _wait_seconds(0.35)
	var no_damage_alert := Dictionary(game.get("_combat_damage_alerts")).is_empty()
	var resource_spend_observed := int(game.get("meat")) < meat_before or int(game.get("wood")) < wood_before
	report["no_alert_for_move_or_paid_production"] = no_damage_alert and resource_spend_observed
	report["normal_move_command"] = "production Villager3D.command_move to %s" % str(move_destination)
	report["production_resource_spend"] = {"wood_before":wood_before,"wood_after":int(game.get("wood")),"meat_before":meat_before,"meat_after":int(game.get("meat")),"observed":resource_spend_observed}
	if not bool(report["no_alert_for_move_or_paid_production"]):
		_finish(false, "non_combat_action_generated_alert_or_control_not_observed")
		return

	# Ordinary unit-to-unit combat must not be promoted to an economy emergency.
	var player_soldier := _spawn_soldier(game, "player", false, worker.global_position + Vector3(0.0, 0.0, -3.0))
	var skirmisher := _spawn_soldier(game, "enemy", false, player_soldier.global_position + Vector3(0.25, 0.0, 0.0))
	_set_attack(skirmisher, player_soldier)
	var soldier_hp_before := float(player_soldier.get("hp"))
	if not await _wait_until(func() -> bool: return float(player_soldier.get("hp")) < soldier_hp_before, 4500):
		_finish(false, "production_unit_skirmish_did_not_damage_soldier")
		return
	var ordinary_skirmish_suppressed := Dictionary(game.get("_combat_damage_alerts")).is_empty()
	report["ordinary_skirmish_suppressed"] = ordinary_skirmish_suppressed
	if not ordinary_skirmish_suppressed:
		_finish(false, "ordinary_skirmish_created_economy_alert")
		return
	player_soldier.queue_free()
	skirmisher.queue_free()
	await _wait_seconds(0.1)

	# A production zombie melee tick strikes a real player building and creates a
	# separate, coalesced building alert at the last-hit position.
	var building_pos: Vector3 = town_center.global_position + Vector3(5.0, 0.0, 0.0)
	var building_attacker := _spawn_soldier(game, "enemy", true, building_pos)
	_set_attack(building_attacker, town_center)
	var building_hp_before := float(town_center.get("hp"))
	if not await _wait_until(func() -> bool: return float(town_center.get("hp")) < building_hp_before, 4500):
		_finish(false, "production_attack_did_not_damage_building")
		return
	if not await _wait_until(func() -> bool: return not _event_for_category(game, "economy_building").is_empty() and _location_button(game) != null, 3000):
		_finish(false, "building_alert_hud_refresh_timeout")
		return
	var building_events: Dictionary = game.get("_combat_damage_alerts")
	var building_event_categories: Array[String] = []
	for debug_event in building_events.values():
		building_event_categories.append(str(debug_event.get("category", "")))
	report["building_alert_debug"] = {"categories":building_event_categories,"keys":building_events.keys(),"hp_delta":building_hp_before - float(town_center.get("hp")),"match_started":bool(game.get("_match_started")),"attacker_team":str(building_attacker.get("team"))}
	var building_event := _event_for_category(game, "economy_building")
	var building_button := _location_button(game)
	var building_alert_shows_kind := building_event.size() > 0 and building_button != null and "城镇中心" in _combat_text(game, building_event)
	var baseline_buttons_survived_new_combat_key := _button_for_key(game, site_alert_key) != null and _button_for_key(game, site_alert_key).get_instance_id() == site_button_id and _button_for_key(game, training_alert_key) != null and _button_for_key(game, training_alert_key).get_instance_id() == training_button_id
	if not building_alert_shows_kind:
		_finish(false, "building_alert_or_locator_missing")
		return

	# A second production attacker lands repeated hits on the economic villager.
	var last_worker_pos: Vector3 = worker.global_position
	var worker_attacker := _spawn_soldier(game, "enemy", true, last_worker_pos + Vector3(0.25, 0.0, 0.0))
	_set_attack(worker_attacker, worker)
	var worker_hp_before := float(worker.get("hp"))
	if not await _wait_until(func() -> bool: return float(worker.get("hp")) < worker_hp_before, 4500):
		_finish(false, "production_attack_did_not_damage_villager")
		return
	if not await _wait_until(func() -> bool: return _unit_alert_button(game) != null, 3000):
		_finish(false, "villager_alert_hud_refresh_timeout")
		return
	var unit_event := _event_for_category(game, "economy_unit")
	var unit_button: Button = _button_for_key(game, "combat:%s" % str(unit_event.get("key", "")))
	var unit_alert_shows_side := unit_event.size() > 0 and unit_button != null and "经济单位遇袭" in _combat_text(game, unit_event) and "侧" in _combat_text(game, unit_event)
	var alerts_are_location_only: bool = unit_button != null and (not unit_button.has_meta("operational_alert_target") or unit_button.get_meta("operational_alert_target") == null) and unit_button.has_meta("alert_location") and unit_button.get_meta("alert_location") is Vector3
	var panel_before_locate := _terminal_state(game.get("hud"))
	var pivot_before := (game.get("cam_pivot") as Node3D).position
	var unit_event_pos: Vector3 = unit_event.get("position", Vector3.ZERO)
	if unit_button != null:
		unit_button.emit_signal("pressed")
	var first_located: bool = (game.get("cam_pivot") as Node3D).position.distance_to(unit_event_pos) < 0.1
	var audio_requests_before_repeat := int(game.get("_combat_alert_audio_requests"))
	if not await _wait_until(func() -> bool: return int(_event_for_category(game, "economy_unit").get("count", 0)) >= 2, 4200):
		_finish(false, "same_region_repeat_hit_not_merged")
		return
	var merged_event := _event_for_category(game, "economy_unit")
	var sound_rate_limited := int(game.get("_combat_alert_audio_requests")) - audio_requests_before_repeat <= 1
	var merged_locator := _location_button_for_key(game, "economy_unit")
	var merged_locator_instance_id: int = merged_locator.get_instance_id() if merged_locator != null else 0
	var merged_event_pos: Vector3 = merged_event.get("position", Vector3.ZERO)
	(game.get("cam_pivot") as Node3D).position = Vector3.ZERO
	if merged_locator != null:
		merged_locator.emit_signal("pressed")
	var latest_position_located: bool = (game.get("cam_pivot") as Node3D).position.distance_to(merged_event_pos) < 0.1
	var active_alert_row_count := 0
	for row in (game.get("hud").get("_operational_rows") as VBoxContainer).get_children():
		if not row.is_queued_for_deletion():
			active_alert_row_count += 1
	var locator_signal_connections: int = merged_locator.get_signal_connection_list("pressed").size() if merged_locator != null else 0
	var unit_button_id_stable: bool = unit_button != null and merged_locator_instance_id == unit_button.get_instance_id()
	var unrelated_buttons_stable: bool = baseline_buttons_survived_new_combat_key and _button_for_key(game, site_alert_key) != null and _button_for_key(game, site_alert_key).get_instance_id() == site_button_id and _button_for_key(game, training_alert_key) != null and _button_for_key(game, training_alert_key).get_instance_id() == training_button_id
	var repeated_controls_stable: bool = active_alert_row_count <= 4 and locator_signal_connections == 1 and unit_button_id_stable and unrelated_buttons_stable
	report["production_villager_hit"] = true
	report["building_alert_and_locator"] = building_alert_shows_kind
	report["villager_alert_and_locator"] = unit_alert_shows_side
	report["location_only_no_target_node"] = alerts_are_location_only
	report["locator_moves_camera_only_on_press"] = first_located and pivot_before.distance_to((game.get("cam_pivot") as Node3D).position) > 0.1
	report["merged_same_region_hit_count"] = int(merged_event.get("count", 0))
	report["sound_throttled_during_repeat"] = sound_rate_limited
	report["headless_audio_request_count"] = int(game.get("_combat_alert_audio_requests"))
	report["repeated_alert_row_and_signal_cleanup"] = repeated_controls_stable
	report["active_alert_rows"] = active_alert_row_count
	report["locator_pressed_signal_connections"] = locator_signal_connections
	report["same_region_button_instance_stable"] = unit_button_id_stable
	report["construction_and_training_buttons_stable_during_hits"] = unrelated_buttons_stable
	report["merged_latest_position_located"] = latest_position_located
	report["terminal_before_combat_refresh"] = panel_before_locate
	report["unit_alert_debug"] = {"unit_text":_combat_text(game, unit_event),"event_key":unit_event.get("key"),"button_key":unit_button.get_meta("alert_location_key", "missing") if unit_button != null else "no_button","button_pos":unit_button.get_meta("alert_location", null) if unit_button != null else null,"event_pos":unit_event_pos,"target_meta":unit_button.get_meta("operational_alert_target", "missing") if unit_button != null else "no_button","first_distance":(game.get("cam_pivot") as Node3D).position.distance_to(unit_event_pos),"button_id":unit_button.get_instance_id() if unit_button != null else 0,"merged_button_id":merged_locator_instance_id,"unit_map_keys":(game.get("hud").get("_operational_button_by_key") as Dictionary).keys()}
	if not unit_alert_shows_side or not alerts_are_location_only or not first_located or not latest_position_located or not sound_rate_limited or not repeated_controls_stable:
		_finish(false, "combat_alert_copy_location_or_throttle_check_failed")
		return

	# Paused save/load clears the transient attack alert state. The combat unit
	# attack orders themselves remain ordinary saved production state.
	game.call("_set_pause_menu_open", true)
	var paused_alert_visible := get_tree().paused and _has_combat_alert(game)
	var save_ok: bool = bool(game.call("_save_match"))
	if not save_ok:
		_finish(false, "save_during_attack_alert_failed")
		return
	game.call("_continue_saved_match")
	if not await _wait_until(func() -> bool: return not bool(game.get("_start_operation_busy")), 30000):
		_finish(false, "paused_continue_load_timeout")
		return
	await _wait_seconds(0.1)
	var restored_alerts_cleared := Dictionary(game.get("_combat_damage_alerts")).is_empty() and not _has_combat_alert(game)
	var still_paused := get_tree().paused and bool(game.get("_pause_menu_open"))
	report["paused_alert_visible_before_save"] = paused_alert_visible
	report["post_load_combat_event_count"] = Dictionary(game.get("_combat_damage_alerts")).size()
	report["post_load_visible_alert_text"] = _combat_alert_labels(game)
	report["post_load_tree_paused"] = get_tree().paused
	report["post_load_pause_menu_open"] = bool(game.get("_pause_menu_open"))
	report["save_load_clears_transient_alert_and_refs"] = save_ok and restored_alerts_cleared and still_paused
	if not save_ok or not restored_alerts_cleared or not still_paused:
		_finish(false, "stale_combat_alert_survived_save_load")
		return
	game.call("_resume_from_pause")
	await _wait_seconds(0.2)
	var restored_worker: Node3D = _nearest_living_villager(last_worker_pos)
	var restored_zombie: Node3D = _nearest_enemy_zombie(last_worker_pos)
	if restored_worker == null or restored_zombie == null:
		_finish(false, "attack_order_targets_missing_after_restore")
		return
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie) and zombie != restored_zombie:
			zombie.queue_free()
	_set_attack(restored_zombie, restored_worker)
	var restored_worker_hp := float(restored_worker.get("hp"))
	if not await _wait_until(func() -> bool: return float(restored_worker.get("hp")) < restored_worker_hp, 4000):
		_finish(false, "post_restore_production_attack_did_not_resume")
		return
	var alert_event_after_restore := _event_for_category(game, "economy_unit")
	if alert_event_after_restore.is_empty():
		_finish(false, "post_restore_villager_alert_missing")
		return

	# Keep native zombie damage and attack cadence; allow the production melee
	# loop to kill the village worker, then locate only the saved coordinate.
	var death_pos: Vector3 = restored_worker.global_position
	var death_timeout_msec := Time.get_ticks_msec() + 30000
	while bool(restored_worker.get("alive")) and Time.get_ticks_msec() < death_timeout_msec:
		await get_tree().process_frame
	var worker_died_in_combat := not bool(restored_worker.get("alive"))
	if not worker_died_in_combat:
		_finish(false, "production_attack_did_not_kill_villager_in_window")
		return
	restored_zombie.queue_free()
	await _wait_seconds(2.6)
	var worker_node_freed := not is_instance_valid(restored_worker)
	var dead_worker_event := _event_for_category(game, "economy_unit")
	var dead_worker_button := _location_button_for_key(game, "economy_unit")
	var event_contains_node := _dictionary_contains_node(dead_worker_event)
	var death_alert_safe: bool = dead_worker_event.size() > 0 and dead_worker_button != null and (not dead_worker_button.has_meta("operational_alert_target") or dead_worker_button.get_meta("operational_alert_target") == null) and dead_worker_button.has_meta("alert_location") and dead_worker_button.get_meta("alert_location") is Vector3 and not event_contains_node
	var death_last_known_pos: Vector3 = dead_worker_event.get("position", death_pos)
	(game.get("cam_pivot") as Node3D).position = Vector3.ZERO
	if dead_worker_button != null:
		dead_worker_button.emit_signal("pressed")
	var dead_worker_located := (game.get("cam_pivot") as Node3D).position.distance_to(death_last_known_pos) < 0.1
	report["worker_died_from_production_attack"] = worker_died_in_combat
	report["dead_target_freed_but_location_alert_safe"] = worker_node_freed and death_alert_safe and dead_worker_located
	report["death_last_known_position"] = [death_last_known_pos.x, death_last_known_pos.y, death_last_known_pos.z]
	if not worker_node_freed or not death_alert_safe or not dead_worker_located:
		_finish(false, "dead_target_location_retained_invalid_node_or_button_missing")
		return
	var expired_incident_key: String = str(dead_worker_event.get("key", ""))
	if not await _wait_until(func() -> bool: return not Dictionary(game.get("_combat_damage_alerts")).has(expired_incident_key), 15000):
		_finish(false, "combat_alert_did_not_expire")
		return
	await _wait_seconds(0.1)
	var expired_row_removed: bool = not Dictionary(game.get("hud").get("_operational_button_by_key")).has("combat:%s" % expired_incident_key)
	report["expired_incident_button_removed"] = expired_row_removed
	if not expired_row_removed:
		_finish(false, "expired_combat_alert_row_still_present")
		return

	# A terminal panel remains the same node and visible after combat-alert
	# refreshes; returning to the real start screen discards the prior incident.
	var old_hud: CanvasLayer = game.get("hud")
	old_hud.call("show_defeat", "测试终局面板", "告警刷新回归检查")
	var terminal_before: Dictionary = _terminal_state(old_hud)
	game.call("_refresh_operational_alerts")
	var terminal_after: Dictionary = _terminal_state(old_hud)
	var terminal_stable: bool = terminal_before.get("id") == terminal_after.get("id") and bool(terminal_after.get("visible"))
	var old_game_instance_id: int = game.get_instance_id()
	game.call("_on_defeat_to_start")
	if not await _wait_until(func() -> bool: return _main_game() != null and _main_game().get_instance_id() != old_game_instance_id and not bool(_main_game().get("_match_started")), 30000):
		_finish(false, "return_to_start_menu_timeout")
		return
	var menu_game := _main_game()
	var fresh_menu_empty := Dictionary(menu_game.get("_combat_damage_alerts")).is_empty()
	menu_game.get("_seed_edit").text = "43"
	(menu_game.get("_start_begin_button") as Button).emit_signal("pressed")
	if not await _wait_until(func() -> bool: return _main_game() != null and bool(_main_game().get("_match_started")), 90000):
		_finish(false, "fresh_match_after_alert_timeout")
		return
	var fresh_game := _main_game()
	var fresh_match_empty := Dictionary(fresh_game.get("_combat_damage_alerts")).is_empty() and not _has_combat_alert(fresh_game)
	report["terminal_panel_stable"] = terminal_stable
	report["return_to_menu_clears_alerts"] = fresh_menu_empty
	report["fresh_match_starts_without_old_alerts"] = fresh_match_empty and int(fresh_game.get("map_seed")) == 43
	report["alert_cap"] = 4
	if not terminal_stable or not fresh_menu_empty or not fresh_match_empty:
		_finish(false, "terminal_or_fresh_match_cleanup_failed")
		return
	_finish(true, "controlled_production_attack_warnings_locate_restore_death_cleanup_passed")

func _spawn_soldier(game: Node, team: String, zombie: bool, pos: Vector3) -> Node3D:
	var soldier: Node3D = SoldierScript.new()
	soldier.call("setup", pos, team, zombie)
	(game.get("world") as Node).add_child(soldier)
	return soldier

func _set_attack(attacker: Node3D, target: Node3D) -> void:
	attacker.set("attack_target", target)
	attacker.set("state", 3) # Soldier3D.State.ATTACK

func _main_game() -> Node:
	return get_tree().get_first_node_in_group("main_game")

func _living_team(group_name: String, team: String) -> Array:
	return get_tree().get_nodes_in_group(group_name).filter(func(node: Node) -> bool: return is_instance_valid(node) and bool(node.get("alive")) and str(node.get("team")) == team)

func _find_building(kind: int) -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and int(building.get("kind")) == kind:
			return building as Node3D
	return null

func _nearest_living_villager(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for villager in _living_team("villagers", "player"):
		var distance: float = (villager as Node3D).global_position.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = villager as Node3D
	return best

func _nearest_enemy_zombie(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie) and bool(zombie.get("alive")) and str(zombie.get("team")) == "enemy":
			var distance: float = (zombie as Node3D).global_position.distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = zombie as Node3D
	return best

func _event_for_category(game: Node, category: String) -> Dictionary:
	for event in Dictionary(game.get("_combat_damage_alerts")).values():
		if str(event.get("category", "")) == category:
			return event
	return {}

func _combat_text(game: Node, event: Dictionary) -> String:
	for row in game.call("_active_combat_alert_rows", Time.get_ticks_msec()):
		if str(row.get("key", "")) == "combat:%s" % str(event.get("key", "")):
			return str(row.get("text", ""))
	return ""

func _location_button(game: Node) -> Button:
	return _location_button_for_key(game, "")

func _location_button_for_key(game: Node, category: String) -> Button:
	var rows: VBoxContainer = game.get("hud").get("_operational_rows")
	for row in rows.get_children():
		for button in row.find_children("*", "Button", true, false):
			if not button.disabled and button.has_meta("alert_location") and button.get_meta("alert_location") is Vector3:
				if category.is_empty() or "经济单位遇袭" in str((row.get_child(0) as Label).text):
					return button as Button
	return null

func _unit_alert_button(game: Node) -> Button:
	var event: Dictionary = _event_for_category(game, "economy_unit")
	return _button_for_key(game, "combat:%s" % str(event.get("key", "")))

func _button_for_key(game: Node, alert_key: String) -> Button:
	var button_map: Dictionary = game.get("hud").get("_operational_button_by_key")
	var button: Variant = button_map.get(alert_key)
	return button as Button if is_instance_valid(button) else null

func _has_combat_alert(game: Node) -> bool:
	for row in game.get("hud").get("_operational_rows").get_children():
		if row.get_child_count() > 0 and row.get_child(0) is Label and str(row.get_child(0).text).contains("遇袭"):
			return true
	return false

func _combat_alert_labels(game: Node) -> Array:
	var labels: Array = []
	for row in game.get("hud").get("_operational_rows").get_children():
		if row.get_child_count() > 0 and row.get_child(0) is Label and "遇袭" in str(row.get_child(0).text):
			labels.append(str(row.get_child(0).text))
	return labels

func _event_location(event: Dictionary) -> Array:
	var value: Variant = event.get("position", Vector3.ZERO)
	return [value.x,value.y,value.z] if value is Vector3 else []

func _dictionary_contains_node(value: Variant) -> bool:
	if value is Node:
		return true
	if value is Dictionary:
		for key in value:
			if _dictionary_contains_node(value[key]):
				return true
	if value is Array:
		for item in value:
			if _dictionary_contains_node(item):
				return true
	return false

func _terminal_state(hud: Node) -> Dictionary:
	var panels := hud.find_children("DefeatBanner", "Panel", true, false)
	return {"id": panels[0].get_instance_id() if panels.size() == 1 else 0, "visible": panels.size() == 1 and (panels[0] as Control).visible}

func _wait_for_damage(target: Node, hp_before: float, timeout_msec: int) -> bool:
	return await _wait_until(func() -> bool: return is_instance_valid(target) and float(target.get("hp")) < hp_before, timeout_msec)

func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var until := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()

func _wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _finish(passed: bool, reason: String) -> void:
	if bool(report.get("finished", false)):
		return
	report["passed"] = passed
	report["reason"] = reason
	report["completed_utc"] = Time.get_datetime_string_from_system(true, true)
	report["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open("user://incoming_attack_alert_probe.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[incoming-attack-alert] ", JSON.stringify({"passed":passed,"reason":reason,"report":"user://incoming_attack_alert_probe.json"}))
	get_tree().quit(0 if passed else 1)





