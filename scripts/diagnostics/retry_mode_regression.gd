## Controlled branch regression: real start menu, terminal UI, scene reload and return flow.
extends Node

const RESULT_PATH := "user://retry_mode_regression.json"
const VICTORY_WAVE := 5
const Catalog := preload("res://scripts/building_catalog.gd")
const ENDLESS_MODE := 0
const CHALLENGE5_MODE := 1
var run_id := ""
var expected_mode := 0
var phase := "wait_initial_menu"
var elapsed := 0.0
var started_msec := 0
var busy := false
var done := false
var events: Array[Dictionary] = []
var last_game_id := 0
var old_seed := -1
var retry_seed := -1
var old_entity_ids: Dictionary = {}
var paid_research_seen := false
var current_game: Node
var started_at_utc := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--run-id="):
			run_id = str(arg).get_slice("=", 1)
			break
	if run_id.is_empty():
		run_id = "retry_mode_%d_%d" % [Time.get_ticks_usec(), OS.get_process_id()]
	started_at_utc = Time.get_datetime_string_from_system(true, true)
	var main := get_tree().get_first_node_in_group("main_game")
	expected_mode = int(main.get("_horde_mode")) if main != null else -1
	print("[retry_mode_regression_runtime] ", JSON.stringify(_runtime_metadata()))

func _process(delta: float) -> void:
	elapsed += delta
	var game := get_tree().get_first_node_in_group("main_game")
	if game != null:
		current_game = game
	if done or busy:
		return
	if Time.get_ticks_msec() - started_msec > 180000:
		_finish(false, "bounded_timeout_at_%s" % phase)
		return
	match phase:
		"wait_initial_menu":
			if game != null and game.get("_start_mode_select") != null and game.get("_start_begin_button") != null:
				await _start_from_menu(game, expected_mode, 42001)
		"wait_initial_match":
			if _match_ready(game) and int(game.get("_horde_mode")) == expected_mode:
				var initial := _initial_snapshot(game)
				if not bool(initial.get("valid", false)):
					_finish(false, "initial_match_bad_state")
					return
				events.append({"action":"initial_mode_started","state":initial,"fixture":false})
				busy = true
				var boundaries := await _exercise_wave_terminal_boundaries(game)
				events.append({"action":"wave_terminal_boundary_regression","result":boundaries,"fixture":true,"natural_wave_victory_claimed":false})
				if not bool(boundaries.get("valid", false)):
					busy = false
					_finish(false, "wave_terminal_boundary_regression_failed")
					return
				var researched_state := await _prepare_researched_retry_state(game)
				if not bool(researched_state.get("valid", false)):
					events.append({"action":"paid_researched_old_state_setup_failed","state":researched_state,"fixture":false})
					busy = false
					_finish(false, "paid_research_old_state_setup_failed")
					return
				events.append({"action":"paid_researched_old_state_ready_for_retry","state":researched_state,"fixture":false})
				old_seed = int(game.get("map_seed"))
				old_entity_ids = _world_ids()
				await _trigger_controlled_defeat(game, "retry")
				busy = false
				phase = "wait_retry_match"
		"wait_retry_match":
			if _match_ready(game) and game.get_instance_id() != last_game_id:
				var snap := _initial_snapshot(game)
				snap["mode"] = int(game.get("_horde_mode"))
				snap["new_seed"] = int(game.get("map_seed"))
				snap["old_scene_replaced"] = game.get_instance_id() != last_game_id
				var current_ids := _world_ids()
				var old_units_gone := true
				for id in old_entity_ids.keys():
					if current_ids.has(id): old_units_gone = false
				snap["old_units_gone"] = old_units_gone
				snap["old_researched_state_cleared"] = paid_research_seen and not bool(snap.get("researched_forestry", true))
				snap["valid"] = bool(snap.get("valid", false)) and bool(snap.get("old_researched_state_cleared", false)) and int(game.get("_horde_mode")) == expected_mode and int(game.get("map_seed")) != old_seed and game.get("_horde_wave") == 0 and not bool(game.get("_horde_active")) and game.get("_horde_spawn_queue").is_empty() and old_units_gone
				events.append({"action":"actual_retry_reload_verified","state":snap})
				if not bool(snap.get("valid", false)):
					_finish(false, "retry_reload_state_invalid")
					return
				busy = true
				var return_route_researched_state := await _prepare_researched_retry_state(game)
				if not bool(return_route_researched_state.get("valid", false)):
					events.append({"action":"paid_researched_old_state_setup_failed_before_return","state":return_route_researched_state,"fixture":false})
					busy = false
					_finish(false, "paid_research_return_setup_failed")
					return
				events.append({"action":"paid_researched_old_state_ready_for_return_to_start","state":return_route_researched_state,"fixture":false})
				old_entity_ids = _world_ids()
				await _trigger_controlled_defeat(game, "to_start")
				busy = false
				phase = "wait_start_menu"
		"wait_start_menu":
			if game != null and game.get("_start_mode_select") != null:
				var selected := int(game.get("_start_mode_select").get_selected_id())
				events.append({"action":"return_to_start_menu_verified","selected_mode":selected,"expected_mode":expected_mode})
				if selected != expected_mode:
					_finish(false, "return_to_start_menu_lost_mode")
					return
				await _start_from_menu(game, CHALLENGE5_MODE, 42002, "wait_challenge_match")
		"wait_challenge_match":
			if _match_ready(game) and int(game.get("map_seed")) == 42002:
				var challenge := _initial_snapshot(game)
				var current_ids := _world_ids()
				var old_world_gone := true
				for id in old_entity_ids.keys():
					if current_ids.has(id): old_world_gone = false
				challenge["old_researched_state_cleared"] = paid_research_seen and not bool(challenge.get("researched_forestry", true))
				challenge["old_world_entities_gone"] = old_world_gone
				challenge["new_world_entity_count"] = current_ids.size()
				challenge["valid"] = bool(challenge.get("valid", false)) and bool(challenge.get("old_researched_state_cleared", false)) and old_world_gone and int(game.get("_horde_mode")) == CHALLENGE5_MODE
				events.append({"action":"challenge5_new_game_verified","state":challenge,"fixture":false})
				if not bool(challenge.get("valid", false)):
					_finish(false, "challenge5_new_game_not_clean")
					return
				busy = true
				await _trigger_controlled_defeat(game, "retry")
				busy = false
				phase = "wait_challenge_retry_match"
		"wait_challenge_retry_match":
			if _match_ready(game) and game.get_instance_id() != last_game_id:
				var challenge_retry := _initial_snapshot(game)
				var retry_world_ids := _world_ids()
				var retry_old_world_gone := true
				for id in old_entity_ids.keys():
					if retry_world_ids.has(id): retry_old_world_gone = false
				challenge_retry["new_seed"] = int(game.get("map_seed"))
				challenge_retry["old_scene_replaced"] = game.get_instance_id() != last_game_id
				challenge_retry["old_world_entities_gone"] = retry_old_world_gone
				challenge_retry["valid"] = bool(challenge_retry.get("valid", false)) and retry_old_world_gone and int(game.get("_horde_mode")) == CHALLENGE5_MODE and int(game.get("map_seed")) != 42002
				events.append({"action":"challenge5_retry_mode_and_state_verified","state":challenge_retry,"fixture":false})
				if not bool(challenge_retry.get("valid", false)):
					_finish(false, "challenge5_retry_state_invalid")
					return
				busy = true
				await _trigger_controlled_defeat(game, "to_start")
				busy = false
				phase = "wait_challenge_menu"
		"wait_challenge_menu":
			if game != null and game.get("_start_mode_select") != null:
				var selected := int(game.get("_start_mode_select").get_selected_id())
				events.append({"action":"challenge5_return_menu_selection_verified","selected_mode":selected,"expected_mode":CHALLENGE5_MODE})
				if selected != CHALLENGE5_MODE:
					_finish(false, "challenge5_return_menu_lost_mode")
					return
				await _start_from_menu(game, ENDLESS_MODE, 42003, "wait_final_match")
		"wait_final_match":
			if _match_ready(game) and int(game.get("map_seed")) == 42003:
				var snap := _initial_snapshot(game)
				snap["mode"] = int(game.get("_horde_mode"))
				snap["seed"] = int(game.get("map_seed"))
				snap["valid"] = bool(snap.get("valid", false)) and int(game.get("_horde_mode")) == ENDLESS_MODE and int(game.get("map_seed")) == 42003 and int(game.get("_horde_wave")) == 0
				events.append({"action":"endless_after_challenge_switch_verified","state":snap,"fixture":false})
				_finish(bool(snap.get("valid", false)), "paid_research_retry_and_endless_challenge5_isolation_verified")

func _start_from_menu(game: Node, mode: int, seed_value: int, next_phase: String = "") -> void:
	var picker: OptionButton = game.get("_start_mode_select") as OptionButton
	var seed: LineEdit = game.get("_seed_edit") as LineEdit
	var begin: Button = game.get("_start_begin_button") as Button
	if picker == null or seed == null or begin == null:
		_finish(false, "start_menu_controls_missing")
		return
	busy = true
	picker.select(mode)
	picker.item_selected.emit(mode)
	seed.text = str(seed_value)
	last_game_id = game.get_instance_id()
	events.append({"action":"start_menu_real_controls_activated","mode":picker.get_selected_id(),"seed":seed_value,"button":begin.name})
	begin.pressed.emit()
	phase = next_phase if not next_phase.is_empty() else "wait_initial_match" if phase == "wait_initial_menu" else "wait_final_match"
	busy = false

func _match_ready(game: Node) -> bool:
	return game != null and bool(game.get("_match_started")) and game.get("_horde_spawn_queue") is Array

func _resources(game: Node) -> Dictionary:
	return {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}

func _workers() -> Array:
	return get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))

func _building(kind: int) -> Node3D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.get("kind")) == kind and str(b.get("team")) == "player" and bool(b.get("alive")):
			return b as Node3D
	return null

func _select(game: Node, units: Array) -> void:
	game.call("_clear_selection")
	for unit in units:
		if is_instance_valid(unit): game.call("_add_to_selection", unit)
	game.call("_refresh_selection_hud")

func _nearest_wood() -> Node3D:
	var nearest: Node3D
	var best := INF
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and int(node.get("kind")) == 0 and int(node.get("amount")) > 0:
			var d: float = node.global_position.length_squared()
			if d < best: best = d; nearest = node as Node3D
	return nearest

func _forestry_effects() -> bool:
	var workers := _workers()
	return workers.size() == 5 and workers.all(func(v): return is_equal_approx(float(v.get("wood_gather_multiplier")), 1.25) and int(v.get("wood_carry_bonus")) == 5)

func _worker_effect_snapshot() -> Array:
	return _workers().map(func(v): return {"name":str(v.name),"multiplier":float(v.get("wood_gather_multiplier")),"carry_bonus":int(v.get("wood_carry_bonus")),"gather_target":str(v.get("gather_target").name) if is_instance_valid(v.get("gather_target")) else ""})

func _train_queue(building: Variant) -> Array:
	if not is_instance_valid(building): return []
	var queue: Variant = building.get("train_queue")
	return queue.duplicate(true) if queue is Array else []

func _training_queues() -> Dictionary:
	var result := {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and str(b.get("team")) == "player": result[str(b.name)] = _train_queue(b)
	return result

func _active_player_targets() -> Array:
	var result: Array = []
	for v in _workers():
		for key in ["gather_target","drop_target","build_site"]:
			var target: Variant = v.get(key)
			if is_instance_valid(target): result.append({"unit":str(v.name),"key":key,"target_id":target.get_instance_id()})
	for unit in get_tree().get_nodes_in_group("military"):
		if is_instance_valid(unit) and str(unit.get("team")) == "player":
			var target: Variant = unit.get("attack_target")
			if is_instance_valid(target): result.append({"unit":str(unit.name),"key":"attack_target","target_id":target.get_instance_id()})
	return result

func _world_ids() -> Dictionary:
	var ids := {}
	for group in ["buildings","resources","villagers","military","zombies"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): ids[node.get_instance_id()] = true
	return ids

func _initial_snapshot(game: Node) -> Dictionary:
	var buildings: Array = get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and str(b.get("team")) == "player" and bool(b.get("alive")))
	var tcs: Array = buildings.filter(func(b): return int(b.get("kind")) == 0)
	var villagers: Array = get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and str(v.get("team")) == "player" and bool(v.get("alive")))
	var enemies: int = get_tree().get_nodes_in_group("zombies").filter(func(z): return is_instance_valid(z) and bool(z.get("alive"))).size()
	var with_orders := villagers.filter(func(v): return not (v.get("order_queue") as Array).is_empty() or int(v.get("state")) != 0).size()
	var research: Node = game.get("research")
	var forestry_researched := bool(research.call("has_technology", "improved_axes")) if research != null else true
	var forestry_effects_clear := villagers.all(func(v): return is_equal_approx(float(v.get("wood_gather_multiplier")), 1.0) and int(v.get("wood_carry_bonus")) == 0)
	var active_targets := _active_player_targets().size()
	var queues := _training_queues()
	var queues_empty := queues.values().all(func(q): return q.is_empty())
	var snapshot := {"mode":int(game.get("_horde_mode")),"seed":int(game.get("map_seed")),"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold")),"researched_forestry":forestry_researched,"villager_wood_effects_clear":forestry_effects_clear,"active_player_targets":active_targets,"training_queues":queues,"training_queues_empty":queues_empty,"villagers":villagers.size(),"villagers_with_orders":with_orders,"town_centers":tcs.size(),"town_center_hp":float(tcs[0].get("hp")) if not tcs.is_empty() else 0.0,"army":game.call("_get_player_military_units").size(),"wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"pending_spawns":game.get("_horde_spawn_queue").size(),"zombies":enemies}
	snapshot["valid"] = snapshot["wood"] == 0 and snapshot["meat"] == 50 and snapshot["stone"] == 0 and snapshot["gold"] == 0 and not forestry_researched and forestry_effects_clear and active_targets == 0 and queues_empty and snapshot["villagers"] == 5 and snapshot["villagers_with_orders"] == 0 and snapshot["town_centers"] == 1 and snapshot["army"] == 0 and snapshot["wave"] == 0 and not snapshot["wave_active"] and snapshot["pending_spawns"] == 0 and enemies == 0
	return snapshot

func _prepare_researched_retry_state(game: Node) -> Dictionary:
	var tree := _nearest_wood()
	var workers := _workers()
	if tree == null or workers.is_empty() or not await _gather_target(game, tree, workers, "wood", 85, "paid_research_setup_wood", 60.0):
		return {"valid":false,"step":"normal_wood_gather"}
	var tc := _building(Catalog.TOWN_CENTER)
	if tc == null:
		return {"valid":false,"step":"town_center_missing"}
	_select(game,[tc])
	var buttons: Dictionary = game.get("hud").get("_cmd_btns")
	var forestry: Button = buttons.get("forestry") as Button
	if forestry == null or forestry.disabled:
		return {"valid":false,"step":"real_forestry_button_unavailable"}
	var forestry_button_text := forestry.text
	var research_before := _resources(game)
	forestry.pressed.emit()
	await get_tree().process_frame
	var research: Node = game.get("research")
	var research_after := _resources(game)
	var research_paid := int(research_after.meat) == int(research_before.meat) - 25 and int(research_after.wood) == int(research_before.wood) - 10
	var researched := bool(research.call("has_technology", "improved_axes"))
	var effects_after_research := _forestry_effects()
	if not research_paid or not researched or not effects_after_research:
		return {"valid":false,"step":"paid_forestry_or_worker_effect_failed","resources_before":research_before,"resources_after":research_after,"researched":researched,"effects":effects_after_research}
	var farm := await _place_building(game, Catalog.FARM, [Vector3(12,0,0),Vector3(10,0,5),Vector3(-12,0,0)], 45.0)
	if farm == null:
		return {"valid":false,"step":"normal_paid_farm_construction_failed"}
	workers = _workers()
	var food_ready := await _gather_target(game, farm, workers, "meat", 75, "normal_farm_food_for_training", 60.0)
	if not food_ready:
		var gather_state: Array = workers.map(func(v): return {"name":str(v.name),"state":int(v.get("state")),"gather_target":str(v.get("gather_target").name) if is_instance_valid(v.get("gather_target")) else "","carry_key":str(v.get("carry_key")),"carry_amount":int(v.get("carry_amount"))})
		var failed := {"valid":false,"step":"normal_farm_gather_failed","resources":_resources(game),"farm_meat_stock":int(farm.get("meat_stock")),"farm_complete":bool(farm.get("is_complete")),"workers":gather_state,"game_time":float(game.get("_game_time"))}
		events.append({"action":"researched_setup_food_gather_failed","details":failed})
		return failed
	workers = _workers()
	var farm_target_active := workers.any(func(v): return v.get("gather_target") == farm)
	tc = _building(Catalog.TOWN_CENTER)
	if tc == null:
		return {"valid":false,"step":"town_center_missing_before_training"}
	_select(game,[tc])
	buttons = game.get("hud").get("_cmd_btns")
	var villager_button: Button = buttons.get("train") as Button
	if villager_button == null or villager_button.disabled:
		return {"valid":false,"step":"real_villager_training_button_unavailable","resources":_resources(game),"button_keys":buttons.keys(),"button_disabled":villager_button.disabled if villager_button != null else true,"town_center_queue":_train_queue(tc),"population":int(game.get("population")),"pop_cap":int(game.get("pop_cap")),"forestry_researched":bool(game.get("research").call("has_technology","improved_axes"))}
	var villager_button_text := villager_button.text
	var training_before := _resources(game)
	villager_button.pressed.emit()
	await get_tree().process_frame
	var queue: Array = _train_queue(tc)
	var paid_queue := queue.has("villager") and bool(tc.get("train_paid")) and not bool(tc.get("train_paused"))
	var training_paid := int(training_before.meat) - int(game.get("meat")) == 50
	var effects := _forestry_effects()
	var changed := _resources(game) != {"wood":0,"meat":50,"stone":0,"gold":0}
	var result := {"resources_before_research":research_before,"resources_after_research":research_after,"research_button":forestry_button_text,"research_paid_once":research_paid,"forestry_researched":researched,"villager_effects_after_research":_worker_effect_snapshot(),"farm_complete":bool(farm.get("is_complete")),"farm_target_active_before_retry":farm_target_active,"training_button":villager_button_text,"training_resources_before":training_before,"training_resources_after":_resources(game),"training_queue":queue,"training_paid":training_paid,"paid_nonempty_training_queue":paid_queue,"villager_effects_before_retry":_worker_effect_snapshot(),"resources_changed":changed}
	result["valid"] = research_paid and researched and effects_after_research and farm_target_active and training_paid and paid_queue and effects and changed
	paid_research_seen = bool(result["valid"])
	return result

func _gather_target(game: Node, target: Node3D, workers: Array, resource_key: String, target_stock: int, reason: String, wall_limit: float) -> bool:
	if target == null or workers.is_empty(): return false
	_select(game, workers)
	game.call("_on_cmd_gather")
	game.call("_route_pending_command", target.global_position, Vector2.ZERO)
	game.set("_cmd_mode", "")
	events.append({"action":"normal_gather_order","reason":reason,"target_instance_id":target.get_instance_id(),"worker_count":workers.size(),"route":"Main gather command + map dispatch"})
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(wall_limit * 1000.0):
		if int(game.get(resource_key)) >= target_stock: return true
		if bool(game.get("_defeated")): return false
		await get_tree().process_frame
	return false

func _place_building(game: Node, kind: int, candidates: Array, wall_limit: float) -> Node3D:
	var workers := _workers()
	if workers.is_empty(): return null
	var builder: Node3D = workers[0]
	_select(game,[builder])
	game.call("_on_build_kind",kind)
	var before := _resources(game)
	var site: Node3D
	for pos in candidates:
		if bool(game.call("_placement_valid_at",pos)):
			game.call("_try_place",pos)
			await get_tree().process_frame
			site = _building(kind)
			if site != null: break
	if site == null: return null
	events.append({"action":"normal_paid_building_placed","kind":kind,"builder":str(builder.name),"cost_resources_before":before,"cost_resources_after":_resources(game)})
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(wall_limit * 1000.0):
		if is_instance_valid(site) and bool(site.get("is_complete")): return site
		if bool(game.get("_defeated")): return null
		await get_tree().process_frame
	return null

func _exercise_wave_terminal_boundaries(game: Node) -> Dictionary:
	var old_mode := int(game.get("_horde_mode"))
	var old_wave := int(game.get("_horde_wave"))
	var old_active := bool(game.get("_horde_active"))
	var old_enabled := bool(game.get("_horde_enabled"))
	var old_next := float(game.get("_horde_next_at"))
	var old_game_time := float(game.get("_game_time"))
	var terminal_hud: Node = game.get("hud")
	var terminal_before := _terminal_panel_state(terminal_hud)
	terminal_hud.call("set_operational_alerts", [{"key":"r69_panel_probe","text":"测试告警","action":"定位","target":game}])
	var terminal_after_alert := _terminal_panel_state(terminal_hud)
	terminal_hud.call("set_operational_alerts", [])
	var terminal_after_clear := _terminal_panel_state(terminal_hud)
	var result := {"mode":expected_mode,"last_enemy_alive_blocks_victory":false,"pending_spawn_blocks_victory":false,"challenge_clear_victory":false,"challenge_no_sixth":false,"endless_reaches_wave_six":false,"terminal_panel_initialized":int(terminal_before.get("count", 0)) == 1 and int(terminal_before.get("id", 0)) > 0,"terminal_panel_stable_after_alert_changes":terminal_before.get("id") == terminal_after_alert.get("id") and terminal_before.get("id") == terminal_after_clear.get("id") and int(terminal_after_alert.get("count", 0)) == 1 and int(terminal_after_clear.get("count", 0)) == 1,"terminal_buttons_connected":int(terminal_before.get("retry_connections", 0)) == 1 and int(terminal_before.get("start_connections", 0)) == 1}
	game.set("_horde_enabled", true)
	game.set("_horde_wave", VICTORY_WAVE)
	game.set("_horde_active", true)
	game.set("_horde_next_at", old_game_time + 10000.0)
	game.set("_horde_spawn_cd", 100.0)
	game.set("_horde_alive_cache_t", 0.0)
	var enemy = game.call("_spawn_horde_wave", VICTORY_WAVE, 1)[0]
	game.set("_horde_mode", 1)
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	result["last_enemy_alive_blocks_victory"] = not bool(game.get("_victorious")) and bool(game.get("_horde_enabled"))
	game.get("_horde_spawn_queue").append(Vector3(3,0,3))
	game.set("_horde_spawn_cd", 100.0)
	if is_instance_valid(enemy): enemy.set("alive", false)
	game.set("_horde_alive_cache_t", 0.0)
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	result["pending_spawn_blocks_victory"] = not bool(game.get("_victorious")) and bool(game.get("_horde_enabled"))
	game.get("_horde_spawn_queue").clear()
	game.set("_horde_alive_cache_t", 0.0)
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	result["challenge_clear_victory"] = bool(game.get("_victorious")) and not bool(game.get("_horde_enabled")) and game.get("_horde_wave") == VICTORY_WAVE
	result["challenge_no_sixth"] = game.get("_horde_wave") == VICTORY_WAVE and game.get("_horde_spawn_queue").is_empty()
	var panel: Control = game.get("hud").get("_defeat_panel") as Control
	if panel != null: panel.hide()
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie): zombie.free()
	game.set("_horde_spawn_queue", [])
	game.set("_horde_mode", 0)
	game.set("_victorious", false)
	game.set("_horde_enabled", true)
	game.set("_horde_wave", VICTORY_WAVE)
	game.set("_horde_active", false)
	game.set("_horde_next_at", float(game.get("_game_time")))
	game.set("_horde_alive_cache_t", 0.0)
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	result["endless_reaches_wave_six"] = game.get("_horde_wave") == 6 and (_alive_zombies().size() + game.get("_horde_spawn_queue").size()) >= int(game.call("_horde_count_for_wave", 6))
	for zombie2 in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie2): zombie2.free()
	game.get("_horde_spawn_queue").clear()
	game.set("_horde_mode", old_mode)
	game.set("_horde_wave", old_wave)
	game.set("_horde_active", old_active)
	game.set("_horde_enabled", old_enabled)
	game.set("_horde_next_at", old_next)
	game.set("_game_time", old_game_time)
	game.set("_horde_alive_cache_t", 0.0)
	return {"valid":bool(result["last_enemy_alive_blocks_victory"]) and bool(result["pending_spawn_blocks_victory"]) and bool(result["challenge_clear_victory"]) and bool(result["challenge_no_sixth"]) and bool(result["endless_reaches_wave_six"]) and bool(result["terminal_panel_initialized"]) and bool(result["terminal_panel_stable_after_alert_changes"]) and bool(result["terminal_buttons_connected"]),"checks":result}

func _terminal_panel_state(hud: Node) -> Dictionary:
	if hud == null: return {"id":0,"count":0,"retry_connections":0,"start_connections":0,"visible":false}
	var panel: Control = hud.get("_defeat_panel") as Control
	var retry: Button = panel.get_node_or_null("VBoxContainer/HBoxContainer/BtnRetry") as Button if panel != null else null
	var start: Button = panel.get_node_or_null("VBoxContainer/HBoxContainer/BtnToStart") as Button if panel != null else null
	if panel != null:
		for child in panel.find_children("*", "Button", true, false):
			var button := child as Button
			if button.name == "BtnRetry": retry = button
			if button.name == "BtnToStart": start = button
	return {"id":panel.get_instance_id() if panel != null else 0,"count":hud.find_children("DefeatBanner", "Panel", true, false).size(),"retry_connections":retry.pressed.get_connections().size() if retry != null else 0,"start_connections":start.pressed.get_connections().size() if start != null else 0,"visible":panel.visible if panel != null else false}

func _alive_zombies() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z): return is_instance_valid(z) and bool(z.get("alive")))

func _current_unit_ids() -> Dictionary:
	var ids: Dictionary = {}
	for group in ["villagers", "military", "zombies"]:
		for unit in get_tree().get_nodes_in_group(group):
			if is_instance_valid(unit): ids[unit.get_instance_id()] = true
	return ids

func _trigger_controlled_defeat(game: Node, button_kind: String) -> void:
	## Explicit terminal fixture: remove player structures, then let the ordinary defeat tick expose the production panel.
	game.set("_defeated", false)
	game.set("_victorious", false)
	if button_kind == "retry": old_entity_ids = _world_ids()
	var buildings: Array = get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and str(b.get("team")) == "player")
	for building in buildings: building.free()
	game.set("_defeat_check_t", 0.0)
	await get_tree().create_timer(0.5).timeout
	var hud: Node = game.get("hud")
	var terminal_state := _terminal_panel_state(hud)
	events.append({"action":"controlled_defeat_panel_ready","defeated":bool(game.get("_defeated")),"terminal_panel":terminal_state})
	if not bool(game.get("_defeated")) or not _defeat_panel_visible(game):
		events.append({"action":"controlled_defeat_fixture_diagnostic","defeated":bool(game.get("_defeated")),"panel_visible":_defeat_panel_visible(game),"player_buildings":game.call("_player_building_count"),"match_started":bool(game.get("_match_started")),"verify":bool(game.get("_verify")),"shot_mode":bool(game.call("_any_shot_mode")),"defeat_check_t":float(game.get("_defeat_check_t"))})
		_finish(false, "controlled_terminal_panel_missing_after_live_process_tick")
		return
	var text_match := "再来一局" if button_kind == "retry" else "返回开局"
	var button: Button = _find_button(game.get("hud"), text_match)
	if button == null:
		_finish(false, "terminal_button_missing_%s" % button_kind)
		return
	if button_kind == "retry":
		old_seed = int(game.get("map_seed"))
	last_game_id = game.get_instance_id()
	events.append({"action":"real_terminal_button_pressed","button":button.name,"text":button.text,"fixture":"controlled destruction followed by production _tick_defeat"})
	button.pressed.emit()

func _defeat_panel_visible(game: Node) -> bool:
	var hud: Node = game.get("hud")
	var panel: Control = hud.get("_defeat_panel") as Control if hud != null else null
	return panel != null and panel.visible

func _find_button(root: Node, phrase: String) -> Button:
	if root == null: return null
	for candidate in root.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button.is_visible_in_tree() and button.text.contains(phrase): return button
	return null

func _runtime_metadata() -> Dictionary:
	return {"run_id":run_id,"started_at_utc":started_at_utc,"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_data_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name() == "headless","time_scale":Engine.time_scale,"expected_mode":expected_mode}

func _finish(ok: bool, reason: String) -> void:
	if done: return
	done = true
	phase = "done"
	var report := {"schema":1,"run_id":run_id,"success":ok,"reason":reason,"elapsed":elapsed,"runtime":_runtime_metadata(),"events":events}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[retry_mode_regression_result] ", JSON.stringify(report))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if ok else 1)
