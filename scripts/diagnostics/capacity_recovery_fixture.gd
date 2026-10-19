extends Node
## Short, isolated production-route fixture for capacity and paid barracks recovery.

const ControllerScript := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const Catalog := preload("res://scripts/building_catalog.gd")
const SAVE_PATH := "user://aoelite3d_save.json"
const RESULT_PATH := "user://capacity_recovery_fixture.json"
const WALL_LIMIT_MSEC := 180000

var started_at := 0
var events: Array[Dictionary] = []
var run_id := ""
var controller: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		var arg := str(args[index])
		if arg.begins_with("--run-id="):
			run_id = arg.get_slice("=", 1)
			if run_id.is_empty() and index + 1 < args.size(): run_id = str(args[index + 1])
		elif arg == "--run-id" and index + 1 < args.size(): run_id = str(args[index + 1])
	if run_id.is_empty(): run_id = "capacity_fixture_%d_%d" % [Time.get_ticks_usec(), OS.get_process_id()]
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_finish(false, "saved_challenge_checkpoint_missing")
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not saved is Dictionary or int(saved.get("map_seed", -1)) != 42 or int(saved.get("horde_mode", -1)) != 1:
		_finish(false, "saved_checkpoint_not_challenge5_seed42")
		return
	var menu := _main_game()
	if menu == null or menu.get("_start_layer") == null:
		_finish(false, "production_start_menu_missing")
		return
	var menu_id := int(menu.get_instance_id())
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish(false, "production_continue_unavailable")
		return
	continue_button.pressed.emit()
	var game: Node
	while _within_limit():
		await get_tree().process_frame
		game = _main_game()
		if game != null and int(game.get_instance_id()) != menu_id and bool(game.get("_match_started")) and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 1:
			break
	if not is_instance_valid(game) or int(game.get_instance_id()) == menu_id:
		_finish(false, "production_continue_restore_timeout")
		return
	var game_id := int(game.get_instance_id())
	controller = ControllerScript.new()
	controller.name = "CapacityRecoveryFixtureController"
	controller.process_mode = Node.PROCESS_MODE_ALWAYS
	controller.set_process(false)
	get_tree().root.add_child(controller)
	if not bool(controller.call("initialize_from_resumed_match", game)):
		_finish(false, "controller_rejected_production_restore")
		return
	controller.set("run_id", run_id)
	var start_state := _fixture_state(game)
	events.append({"action":"production_continue_restored","game_time":float(game.get("_game_time")),"save_sha256":FileAccess.get_sha256(SAVE_PATH),"scene_instance_id":game_id,"state":start_state})

	# Reproduce the R32 root cause: seed overlapping old group memberships, then
	# invoke the production controller's normal material partition.
	var living := _living_villagers()
	if living.size() < 3:
		_finish(false, "fixture_requires_three_living_builders")
		return
	var overlap_seed := _seed_overlapping_groups(game, living)
	controller.call("_split_material_worker_groups", game)
	var groups: Array = game.get("_control_groups")
	var group_sets := []
	for group_index in [2, 3, 4]:
		var ids: Array[String] = []
		for unit in groups[group_index]:
			if is_instance_valid(unit): ids.append(str(unit.get_instance_id()))
		group_sets.append(ids)
	var group_overlap := _overlap_ids(group_sets)
	events.append({"action":"disjoint_material_groups_verified","fixture_injection":{"overlapping_old_groups":overlap_seed},"groups_2_3_4":group_sets,"overlap_after":group_overlap,"controller_audit":controller.events.filter(func(row): return str(row.get("action")) == "post_farm_worker_groups_split").back()})
	if not group_overlap.is_empty():
		_finish(false, "material_control_groups_remain_overlapped")
		return
	if not _same_game(game, game_id):
		_finish(false, "main_scene_changed_during_fixture")
		return

	# Failure matrix is intentional and fully restored before the paid success case.
	var original_wood := int(game.get("wood"))
	var original_meat := int(game.get("meat"))
	var one_house_candidate: Array[Vector3] = [Vector3(0, 0, 16)]
	game.set("wood", 0)
	await controller.call("_build_at_headless", game, Catalog.HOUSE, "fixture insufficient wood", one_house_candidate)
	var low_wood_preserved := int(game.get("wood")) == 0
	events.append({"action":"insufficient_wood_rejected_without_payment","injection":{"wood":0,"original_wood":original_wood},"wood_after":int(game.get("wood")),"verified":low_wood_preserved})
	if not low_wood_preserved:
		_finish(false, "insufficient_wood_path_spent_resources")
		return
	game.set("wood", 1000)
	var before_invalid := int(game.get("wood"))
	var invalid_house_candidates: Array[Vector3] = [Vector3(200, 0, 200)]
	await controller.call("_build_at_headless", game, Catalog.HOUSE, "fixture invalid site", invalid_house_candidates)
	var invalid_preserved := int(game.get("wood")) == before_invalid
	events.append({"action":"invalid_site_rejected_without_payment","injection":{"candidate":[200,0,200],"wood":before_invalid},"wood_after":int(game.get("wood")),"verified":invalid_preserved})
	if not invalid_preserved:
		_finish(false, "invalid_site_path_spent_resources")
		return
	var alive_before := []
	for worker in living:
		alive_before.append(bool(worker.get("alive")))
		worker.set("alive", false)
	var no_builder_before := int(game.get("wood"))
	await controller.call("_build_at_headless", game, Catalog.HOUSE, "fixture no builder", one_house_candidate)
	for index in living.size(): living[index].set("alive", alive_before[index])
	var no_builder_preserved := int(game.get("wood")) == no_builder_before
	events.append({"action":"no_builder_rejected_without_payment","injection":{"all_fixture_villagers_alive":false,"wood":no_builder_before},"wood_after":int(game.get("wood")),"verified":no_builder_preserved})
	if not no_builder_preserved:
		_finish(false, "no_builder_path_spent_resources")
		return

	var tc := _player_tc()
	if not is_instance_valid(tc):
		_finish(false, "town_center_missing_from_checkpoint")
		return
	var original_tc_hp := float(tc.get("hp"))
	tc.set("hp", float(tc.get("max_hp")) * 0.5)
	game.set("wood", maxi(original_wood, 300))
	game.set("meat", maxi(original_meat, 600))
	var original_backup_attempt_time := float(controller.get("last_backup_house_attempt_game_time"))
	var policy_time := float(game.get("_game_time"))
	var policy_ready := bool(controller.call("_backup_house_cooldown_ready", game))
	controller.call("_reserve_backup_house_attempt", game)
	var same_frame_suppressed := not bool(controller.call("_backup_house_cooldown_ready", game))
	controller.set("backup_house_attempt_in_progress", false)
	controller.set("last_backup_house_attempt_game_time", policy_time - 24.9)
	var twenty_four_nine_suppressed := not bool(controller.call("_backup_house_cooldown_ready", game))
	controller.set("last_backup_house_attempt_game_time", policy_time - 25.1)
	var twenty_five_one_ready := bool(controller.call("_backup_house_cooldown_ready", game))
	tc.set("alive", false)
	var after_town_center_destroyed_ready := bool(controller.call("_backup_house_cooldown_ready", game))
	tc.set("alive", true)
	controller.set("last_backup_house_attempt_game_time", original_backup_attempt_time)
	events.append({"action":"backup_house_policy_cooldown_verified","injection":{"town_center_hp":float(tc.get("hp")),"wood":int(game.get("wood")),"town_center_destroyed_probe":true},"ready_at_half_health":policy_ready,"same_frame_duplicate_suppressed":same_frame_suppressed,"suppressed_at_24_9_seconds":twenty_four_nine_suppressed,"ready_after_25_1_seconds":twenty_five_one_ready,"ready_with_town_center_destroyed_and_builder_alive":after_town_center_destroyed_ready,"verified":policy_ready and same_frame_suppressed and twenty_four_nine_suppressed and twenty_five_one_ready and after_town_center_destroyed_ready})
	if not (policy_ready and same_frame_suppressed and twenty_four_nine_suppressed and twenty_five_one_ready and after_town_center_destroyed_ready):
		tc.set("hp", original_tc_hp)
		_finish(false, "backup_house_policy_cooldown_assertion_failed")
		return
	var house_cost := int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 50))
	var wood_before_house := int(game.get("wood"))
	var candidate_points: Array[Vector3] = controller.call("_backup_house_candidates", game)
	if candidate_points.is_empty():
		tc.set("hp", original_tc_hp)
		_finish(false, "no_legal_house_candidate_from_live_hub")
		return
	await controller.call("_build_at_headless", game, Catalog.HOUSE, "fixture half-health TC capacity house", candidate_points)
	var houses := _live_houses()
	var placement_event: Dictionary = {}
	for row in controller.get("events"):
		if str(row.get("action")) == "building_placed" and int(row.get("kind", -1)) == Catalog.HOUSE and str(row.get("label")) == "fixture half-health TC capacity house":
			placement_event = row
	var placed_resources: Dictionary = placement_event.get("resources_after_payment", {})
	var paid_house := int(placed_resources.get("wood", -1)) == wood_before_house - house_cost and not houses.is_empty()
	var house: Node3D = houses.back() if not houses.is_empty() else null
	var house_deadline := Time.get_ticks_msec() + 50000
	while paid_house and is_instance_valid(house) and not bool(house.get("is_complete")) and _within_limit() and Time.get_ticks_msec() < house_deadline:
		await get_tree().process_frame
	var house_complete := is_instance_valid(house) and bool(house.get("is_complete")) and float(house.get("build_progress")) >= float(house.get("build_time"))
	events.append({"action":"paid_backup_house_completed","fixture_injection":{"town_center_hp":float(tc.get("hp")),"town_center_max_hp":float(tc.get("max_hp")),"wood":wood_before_house,"meat":int(game.get("meat"))},"wood_after":int(game.get("wood")),"resources_at_placement":placed_resources,"cost":house_cost,"position":_v3(house.global_position) if is_instance_valid(house) else [],"build_progress":float(house.get("build_progress")) if is_instance_valid(house) else -1,"build_time":float(house.get("build_time")) if is_instance_valid(house) else -1,"is_complete":house_complete,"verified_paid_and_complete":paid_house and house_complete,"route":"normal Main selection + paid _try_place via controller headless fixture"})
	tc.set("hp", original_tc_hp)
	if not paid_house or not house_complete:
		_finish(false, "paid_house_not_placed_or_completed")
		return

	# Build and train through the ordinary Main routes. Corrupted group 2 is
	# absent after the disjoint partition above, so the builder cannot be stolen
	# by an earlier resource assignment.
	game.set("wood", maxi(int(game.get("wood")), 1000))
	game.set("meat", maxi(int(game.get("meat")), 1000))
	var barracks_candidates: Array[Vector3] = [Vector3(-12,0,0), Vector3(-14,0,8), Vector3(14,0,4), Vector3(14,0,-6)]
	await controller.call("_build_at_headless", game, Catalog.BARRACKS, "fixture paid barracks after group repair", barracks_candidates)
	var barracks: Node3D = controller.get("barracks")	
	var barracks_complete := is_instance_valid(barracks) and bool(barracks.get("is_complete")) and float(barracks.get("build_progress")) >= float(barracks.get("build_time"))
	events.append({"action":"paid_barracks_completed","wood":int(game.get("wood")),"barracks":str(barracks.name) if is_instance_valid(barracks) else "","builder_groups_disjoint":group_overlap.is_empty(),"build_progress":float(barracks.get("build_progress")) if is_instance_valid(barracks) else -1,"build_time":float(barracks.get("build_time")) if is_instance_valid(barracks) else -1,"complete":barracks_complete})
	if not barracks_complete:
		_finish(false, "barracks_builder_progress_or_completion_failed")
		return
	var soldiers_before := _player_soldier_count()
	game.call("_clear_selection")
	game.call("_add_to_selection", barracks)
	game.call("_on_train_soldier")
	var queue_accepted := _train_queue(barracks).has("soldier")
	var unit_deadline := Time.get_ticks_msec() + 45000
	while queue_accepted and _player_soldier_count() <= soldiers_before and _within_limit() and Time.get_ticks_msec() < unit_deadline:
		await get_tree().process_frame
	var soldier_spawned := _player_soldier_count() > soldiers_before
	events.append({"action":"paid_soldier_queued_and_spawned","accepted_queue":queue_accepted,"soldiers_before":soldiers_before,"soldiers_after":_player_soldier_count(),"spawned":soldier_spawned,"resources_after":{"wood":int(game.get("wood")),"meat":int(game.get("meat"))},"route":"Main._on_train_soldier -> production barracks queue -> train_finished"})
	_finish(soldier_spawned, "paid_house_barracks_soldier_recovery_verified" if soldier_spawned else "soldier_enqueue_or_spawn_failed")

func _seed_overlapping_groups(game: Node, living: Array) -> Array:
	var groups: Array = game.get("_control_groups")
	var seeds := [living.slice(0, 2), living.slice(1, 3), living.slice(0, 1)]
	for group_index in [2, 3, 4]:
		game.call("_clear_selection")
		for worker in seeds[[2,3,4].find(group_index)]: game.call("_add_to_selection", worker)
		game.call("_assign_control_group", group_index)
	return [
		{"group":2,"ids":_ids(groups[2])},
		{"group":3,"ids":_ids(groups[3])},
		{"group":4,"ids":_ids(groups[4])},
	]

func _ids(units: Array) -> Array[String]:
	var result: Array[String] = []
	for unit in units:
		if is_instance_valid(unit): result.append(str(unit.get_instance_id()))
	return result

func _overlap_ids(group_sets: Array) -> Array[String]:
	var counts: Dictionary = {}
	for group in group_sets:
		for id in group: counts[str(id)] = int(counts.get(str(id), 0)) + 1
	var overlap: Array[String] = []
	for id in counts:
		if int(counts[id]) > 1: overlap.append(str(id))
	overlap.sort()
	return overlap

func _main_game() -> Node:
	return get_tree().get_first_node_in_group("main_game")

func _same_game(game: Node, game_id: int) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and int(game.get_instance_id()) == game_id and bool(game.get("_match_started")) and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 1

func _within_limit() -> bool:
	return Time.get_ticks_msec() - started_at < WALL_LIMIT_MSEC

func _living_villagers() -> Array:
	return get_tree().get_nodes_in_group("villagers").filter(func(unit): return is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("alive")) and float(unit.get("hp")) > 0.0)

func _player_tc() -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.TOWN_CENTER and bool(building.get("alive")): return building as Node3D
	return null

func _live_houses() -> Array:
	return get_tree().get_nodes_in_group("buildings").filter(func(building): return is_instance_valid(building) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.HOUSE and bool(building.get("alive")))

func _player_soldier_count() -> int:
	return get_tree().get_nodes_in_group("soldiers").filter(func(unit): return is_instance_valid(unit) and str(unit.get("team")) == "player" and not bool(unit.get("is_zombie")) and bool(unit.get("alive"))).size()

func _train_queue(building: Variant) -> Array:
	return building.get("train_queue") if is_instance_valid(building) else []

func _fixture_state(game: Node) -> Dictionary:
	return {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"population":int(game.get("population")),"pop_cap":int(game.get("pop_cap")),"living_villagers":_living_villagers().size(),"living_soldiers":_player_soldier_count(),"wave":int(game.get("_horde_wave")),"game_time":float(game.get("_game_time"))}

func _v3(pos: Vector3) -> Array[float]:
	return [pos.x, pos.y, pos.z]

func _finish(ok: bool, reason: String) -> void:
	var payload := {"schema":1,"run_id":run_id,"success":ok,"reason":reason,"wall_elapsed_msec":Time.get_ticks_msec()-started_at,"events":events,"controller_events":controller.get("events") if is_instance_valid(controller) else [],"runtime":{"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_data_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name()=="headless"}}
	var output := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(payload, "\t")); output.close()
	print("[capacity_recovery_fixture] ", JSON.stringify({"success":ok,"reason":reason,"run_id":run_id,"wall_elapsed_msec":payload.wall_elapsed_msec,"result":RESULT_PATH}))
	get_tree().quit(0 if ok else 1)
