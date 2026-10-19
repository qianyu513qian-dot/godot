extends Node
## Normal-input endless defense: economy, fortification, army commands, wave accounting and real retry UI.
const RESULT_PATH := "user://controlled_endless_defense.json"
const OBSERVER_PATH := "user://controlled_endless_defense_observer.jsonl"
const Catalog := preload("res://scripts/building_catalog.gd")
const Pathfind := preload("res://scripts/pathfind.gd")
const WOOD_PLAN := 75
const FIRST_TOWER_WOOD := 100
const FIRST_TOWER_STONE := 50
const SECOND_FARM_WOOD_RESERVE := 75
const TARGET_VILLAGERS := 5
const TARGET_ARMY := 5
const ECONOMY_GUARD_COUNT := 3
const MIN_ASSAULT_GROUP_SIZE := 3
const ECONOMY_GUARD_ANCHOR := Vector3(-3.0, 0.0, -7.5)
const ECONOMY_RALLY_ANCHOR := Vector3(-3.0, 0.0, -7.5)
const FIRST_WAVE := 1
var phase := "menu"
var phase_time := 0.0
var elapsed := 0.0
var persist_clock := 0.0
var sample_clock := 0.0
var observer_clock := 0.0
var campaign_observer_samples := 0
var last_observer_signature := ""
var campaign_command_reason := "campaign setup"
var last_observed_army_count := -1
var busy := false
var done := false
var events: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var combat_samples: Array[Dictionary] = []
var wave_ledger: Dictionary = {}
var last_game: Node
var old_game_id := 0
var original_seed := 42
var start_game_time := 0.0
var farm: Node3D
var farm2: Node3D
var house: Node3D
var barracks: Node3D
var tower: Node3D
var tower2: Node3D
var tower3: Node3D
var tower4: Node3D
var tower5: Node3D
var last_target: Node3D
var last_target_hp := -1.0
var last_target_progress_at := 0.0
var last_command_at := -999.0
var last_busy_combat_order_at := -999.0
var last_reinforce_at := -999.0
var last_food_order_at := -999.0
var last_wood_order_at := -999.0
var last_tower_material_order_at := -999.0
var last_worker_group_living_count := -1
var army_seen: Dictionary = {}
var building_first_hp: Dictionary = {}
var defeat_seed := 0
var terminal_snapshot: Dictionary = {}
var terminal_wave_ledger: Dictionary = {}
var terminal_combat_summary: Dictionary = {}
var contact_checkpointed: Dictionary = {}
var wave6_checkpointed := false
var army_group_checked := false
var third_tower_attempted := false
var fourth_tower_attempted := false
var fifth_tower_attempted := false
var pre_wave_tower_attempted := false
var last_tower2_attempt_at := -999.0
var last_farm_placement_attempt_game_time := -999.0
var last_backup_house_attempt_game_time := -999.0
var backup_house_attempt_in_progress := false
var attack_move_wave_sent: Dictionary = {}
var initial_guard_orders_issued := false
var guard_ordered_runtime_ids: Dictionary = {}
var guard_unavailable_logged_runtime_ids: Dictionary = {}
var economy_guard_runtime_ids: Dictionary = {}
var evacuated_worker_ids: Dictionary = {}
var worker_resume_audits: Dictionary = {}
var next_worker_resume_audit_id := 1
var last_protection_sweep_game_time := -999.0
var last_assault_wait_signature := ""
var checkpoint_continue_done := false
var checkpoint_continue_busy := false
var checkpoint_entity_map: Dictionary = {}
var checkpoint_payload: Dictionary = {}
var checkpoint_runtime_id_to_entity_id: Dictionary = {}
var continue_pre_wave_audit: Dictionary = {}
var runtime_enemy_seen: Dictionary = {}
var runtime_enemy_stable_key: Dictionary = {}
var stable_enemy_ids: Dictionary = {}
var villager_training_pending := false
var villager_count_at_last_queue := -1
var last_villager_queue_attempt_game_time := -999.0
var last_army_queue_attempt_game_time := -999.0
var last_soldier_queue_block_signature := ""
var tracked_training_barracks_id := 0
var tracked_training_queue: Array = []
var tracked_training_paid := false
var tracked_training_paused := false
var tracked_training_army_names: Array[String] = []
var tracked_training_resources: Dictionary = {}
var post_challenge_endless_followup := false
var endless_wave6_started_at := -1.0
var last_wave_economy_plan_logged := -1
var enemy_progress_watch: Dictionary = {}
var enemy_watch_last_sample := 0.0
var _last_shift_click: Dictionary = {}
var run_id := ""
var started_at_utc := ""
var trace_until_game_time := -1.0
var enable_pending_worker_reroutes := true
var fixture_trace: Array = []
const WORKER_REROUTE_MAX: int = 3
const WORKER_REROUTE_COOLDOWN: float = 2.0
var wall_started_msec := 0
var wall_limit_msec := 1800000
var last_recovery_wait_logged_game_time := -999.0
var last_recovery_wait_state_signature := ""
var last_villager_reserve_signature := ""
var wave4_budget_checkpoint_times: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var user_args := OS.get_cmdline_user_args()
	for index in user_args.size():
		var arg := str(user_args[index])
		if arg.begins_with("--run-id="):
			run_id = arg.get_slice("=", 1)
			if run_id.is_empty() and index + 1 < user_args.size(): run_id = str(user_args[index + 1])
		elif arg == "--run-id" and index + 1 < user_args.size():
			run_id = str(user_args[index + 1])
		if str(arg).begins_with("--trace-until="):
			trace_until_game_time = float(str(arg).get_slice("=", 1))
	started_at_utc = Time.get_datetime_string_from_system(true, true)
	wall_started_msec = Time.get_ticks_msec()
	if run_id.is_empty():
		run_id = "challenge5_%d_%d" % [Time.get_ticks_usec(), OS.get_process_id()]
	print("[controlled_endless_defense_runtime] ", JSON.stringify(_runtime_metadata()))

func initialize_from_resumed_match(game: Node) -> bool:
	if not is_instance_valid(game) or not game.is_inside_tree() or not bool(game.get("_match_started")) or int(game.get("map_seed")) != 42 or int(game.get("_horde_mode")) != 1:
		return false
	phase = "defend"
	phase_time = 0.0
	old_game_id = int(game.get_instance_id())
	original_seed = 42
	start_game_time = float(game.get("_game_time"))
	last_game = game
	checkpoint_continue_done = true
	last_wave_economy_plan_logged = int(game.get("_horde_wave"))
	var live_farms: Array[Node3D] = []
	var live_towers: Array[Node3D] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not bool(building.get("alive")) or str(building.get("team")) != "player":
			continue
		match int(building.get("kind")):
			Catalog.FARM: live_farms.append(building as Node3D)
			Catalog.HOUSE: house = building as Node3D
			Catalog.BARRACKS: barracks = building as Node3D
			Catalog.ARROW_TOWER: live_towers.append(building as Node3D)
	if not live_farms.is_empty():
		live_farms.sort_custom(func(a: Node3D, b: Node3D) -> bool: return int(a.get("meat_stock")) > int(b.get("meat_stock")))
		farm = live_farms[0]
		if live_farms.size() > 1: farm2 = live_farms[1]
	if not live_towers.is_empty():
		live_towers.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(Vector3.ZERO) < b.global_position.distance_squared_to(Vector3.ZERO))
		tower = live_towers[0]
		if live_towers.size() > 1: tower2 = live_towers[1]
		if live_towers.size() > 2: tower3 = live_towers[2]
		if live_towers.size() > 3: tower4 = live_towers[3]
		if live_towers.size() > 4: tower5 = live_towers[4]
	last_worker_group_living_count = -1
	tracked_training_barracks_id = 0
	_seed_restored_enemy_identities(game)
	events.append({"action":"controller_attached_to_saved_challenge_match","game_time":start_game_time,"seed":42,"mode":int(game.get("_horde_mode")),"wave":int(game.get("_horde_wave")),"workers":_living_villagers().size(),"army":_player_military().size(),"live_farms":live_farms.size(),"live_towers":live_towers.size(),"scope":"resume from saved match; opening economy is not rerun"})
	return true

func _seed_restored_enemy_identities(game: Node) -> void:
	var restored_map: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_map", {})
	var runtime_ids: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_runtime_ids", {})
	var ledger_ids: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_ledger_ids", {})
	var seeded: Array[Dictionary] = []
	for raw_entity_id in runtime_ids.keys():
		var entity_id := str(raw_entity_id)
		var restored: Variant = restored_map.get(entity_id)
		if not is_instance_valid(restored) or not bool(restored.get("is_zombie")):
			continue
		var runtime_id := str(runtime_ids.get(entity_id, ""))
		var ledger_id := str(ledger_ids.get(entity_id, entity_id))
		if runtime_id.is_empty() or ledger_id.is_empty():
			continue
		var wave_id := int(restored.get("horde_wave_id"))
		if wave_id <= 0:
			continue
		runtime_enemy_seen[runtime_id] = true
		runtime_enemy_stable_key[runtime_id] = ledger_id
		checkpoint_entity_map[entity_id] = {"entity_id":entity_id,"ledger_entity_id":ledger_id,"runtime_id":runtime_id,"wave_id":wave_id,"alive":bool(restored.get("alive"))}
		seeded.append({"entity_id":entity_id,"ledger_entity_id":ledger_id,"runtime_id":runtime_id,"wave_id":wave_id,"alive":bool(restored.get("alive"))})
	if not seeded.is_empty():
		events.append({"action":"restored_enemy_identity_seeded","game_time":float(game.get("_game_time")),"entities":seeded,"count":seeded.size(),"source":"Main restore entity/runtime/ledger metadata; does not infer pre-save deaths"})

func record_resume_bootstrap(event: Dictionary) -> void:
	events.append(event)

func _observe_campaign_state(game: Node, delta: float) -> void:
	# Independent, synchronous observer: runs before busy/await controller gates.
	observer_clock += delta
	if phase == "defend" and int(game.get("_horde_wave")) == 4:
		for marker in [435, 460, 478, 480, 500, 510]:
			var marker_key := str(marker)
			if float(game.get("_game_time")) >= float(marker) and not wave4_budget_checkpoint_times.has(marker_key):
				wave4_budget_checkpoint_times[marker_key] = true
				_checkpoint("wave4_budget_game_time_%d" % marker, game)
	var farms: Array[Dictionary] = []
	for f in get_tree().get_nodes_in_group("farms"):
		if not is_instance_valid(f) or str(f.get("team")) != "player": continue
		farms.append({"id":str(f.get_instance_id()),"name":str(f.name),"alive":bool(f.get("alive")),"complete":bool(f.get("is_complete")),"hp":float(f.get("hp")),"stock":int(f.get("meat_stock")),"arid":bool(f.get("is_arid")),"pos":[f.global_position.x,f.global_position.y,f.global_position.z]})
	var workers: Array[Dictionary] = []
	for w in _living_villagers():
		var gather: Variant = w.get("gather_target")
		var site: Variant = w.get("build_site")
		workers.append({"id":str(w.get_instance_id()),"name":str(w.name),"state":int(w.get("state")),"hp":float(w.get("hp")),"max_hp":float(w.get("max_hp")),"pos":[w.global_position.x,w.global_position.y,w.global_position.z],"move_goal":[w.get("_goal_final").x,w.get("_goal_final").y,w.get("_goal_final").z] if w.get("_goal_final") is Vector3 else [],"gather_target":str(gather.name) if is_instance_valid(gather) else "","gather_kind":str(gather.call("res_key")) if is_instance_valid(gather) and gather.has_method("res_key") else "farm" if is_instance_valid(gather) and gather.is_in_group("farms") else "","resume_key":str(w.get("resume_key")),"build_site":str(site.name) if is_instance_valid(site) else "","carry_key":str(w.get("carry_key")),"carry":int(w.get("carry_amount"))})
	var army: Array[Dictionary] = []
	for u in _player_military():
		var target: Variant = u.get("attack_target")
		var goal: Variant = u.get("_goal_final")
		army.append({"id":str(u.get_instance_id()),"name":str(u.name),"hp":float(u.get("hp")),"max_hp":float(u.get("max_hp")),"pos":[u.global_position.x,u.global_position.y,u.global_position.z],"move_goal":[goal.x,goal.y,goal.z] if goal is Vector3 else [],"state":int(u.get("state")),"guard":bool(u.get("guard_active")),"guard_anchor":[u.get("guard_resolved_anchor").x,u.get("guard_resolved_anchor").y,u.get("guard_resolved_anchor").z] if u.get("guard_resolved_anchor") is Vector3 else [],"target":str(target.name) if is_instance_valid(target) else "","target_pos":[target.global_position.x,target.global_position.y,target.global_position.z] if is_instance_valid(target) and target is Node3D else []})
	var enemies: Array[Dictionary] = []
	for enemy in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(enemy) or not bool(enemy.get("alive")): continue
		var target: Variant = enemy.get("attack_target")
		enemies.append({"id":str(enemy.get_instance_id()),"name":str(enemy.name),"wave":int(enemy.get("horde_wave_id")),"hp":float(enemy.get("hp")),"max_hp":float(enemy.get("max_hp")),"pos":[enemy.global_position.x,enemy.global_position.y,enemy.global_position.z],"state":int(enemy.get("state")),"target":str(target.name) if is_instance_valid(target) else "","target_pos":[target.global_position.x,target.global_position.y,target.global_position.z] if is_instance_valid(target) and target is Node3D else []})
	var buildings: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player" or not bool(building.get("alive")): continue
		var tower_state: Dictionary = building.call("get_tower_ui_state") if bool(building.get("is_tower")) and building.has_method("get_tower_ui_state") else {}
		buildings.append({"id":str(building.get_instance_id()),"name":str(building.name),"kind":int(building.get("kind")),"hp":float(building.get("hp")),"max_hp":float(building.get("max_hp")),"pos":[building.global_position.x,building.global_position.y,building.global_position.z],"complete":bool(building.get("is_complete")),"build_progress":float(building.get("build_progress")),"tower":bool(building.get("is_tower")),"tower_range":float(building.get("attack_range")),"tower_cd":float(building.get("_tower_cd")),"tower_state":tower_state})
	var arrows: Array[Dictionary] = []
	for arrow in get_tree().get_nodes_in_group("arrows"):
		if not is_instance_valid(arrow): continue
		var attacker: Variant = arrow.get("_attacker")
		var target: Variant = arrow.get("_target")
		arrows.append({"id":str(arrow.get_instance_id()),"attacker":str(attacker.name) if is_instance_valid(attacker) else "","target":str(target.name) if is_instance_valid(target) else "","pos":[arrow.global_position.x,arrow.global_position.y,arrow.global_position.z]})
	var queue: Array = _train_queue(barracks) if is_instance_valid(barracks) else []
	var row := {"elapsed":elapsed,"game_time":float(game.get("_game_time")),"phase":phase,"sample_phase":"post_cutoff_close_delay" if done else "bounded_trace","busy":busy,"command_reason":campaign_command_reason,"wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"resources":{"wood":int(game.get("wood")),"food":int(game.get("meat")),"stone":int(game.get("stone"))},"farms":farms,"workers":workers,"army":army,"enemies":enemies,"buildings":buildings,"arrows":arrows,"barracks":{"id":str(barracks.get_instance_id()) if is_instance_valid(barracks) else "","queue":queue,"paid":bool(barracks.get("train_paid")) if is_instance_valid(barracks) else false,"paused":bool(barracks.get("train_paused")) if is_instance_valid(barracks) else false,"timer":float(barracks.get("train_timer")) if is_instance_valid(barracks) else 0.0},"pending_enemy_spawns":Array(game.get("_horde_spawn_queue")).size(),"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious"))}
	# Rich traces include moving positions, so a change-signature sampler would
	# write once per frame. Keep this diagnostic observer bounded at 2 Hz.
	if observer_clock < 0.5: return
	observer_clock = 0.0
	var observer_file: FileAccess
	if not FileAccess.file_exists(OBSERVER_PATH):
		observer_file = FileAccess.open(OBSERVER_PATH, FileAccess.WRITE)
		if observer_file != null: observer_file.close()
	observer_file = FileAccess.open(OBSERVER_PATH, FileAccess.READ_WRITE)
	if observer_file != null:
		observer_file.seek_end()
		observer_file.store_line(JSON.stringify(row))
		observer_file.close()
		campaign_observer_samples += 1

func _process(delta: float) -> void:
	if done:
		persist_clock += delta
		var closed_game := get_tree().get_first_node_in_group("main_game")
		if closed_game != null and is_instance_valid(closed_game):
			_observe_campaign_state(closed_game, delta)
		if persist_clock >= 10.0:
			persist_clock = 0.0
			_persist()
		return
	elapsed += delta
	phase_time += delta
	persist_clock += delta
	var game := get_tree().get_first_node_in_group("main_game")
	if game != null:
		last_game = game
		var belongs_to_original_match := old_game_id == 0 or (game.get_instance_id() == old_game_id and int(game.get("map_seed")) == original_seed)
		if belongs_to_original_match and terminal_snapshot.is_empty():
			_observe_campaign_state(game, delta)
			if trace_until_game_time > 0.0 and float(game.get("_game_time")) >= trace_until_game_time:
				terminal_snapshot = _build_bounded_trace_snapshot(game)
				terminal_snapshot["bounded_cutoff_game_time"] = float(game.get("_game_time"))
				terminal_snapshot["cutoff_target_game_time"] = trace_until_game_time
				terminal_snapshot["controller_frozen_before_maintenance"] = true
				get_tree().paused = true
				_finish(false, "bounded_combat_trace_reached_game_time_%d" % int(trace_until_game_time))
				return
			if phase == "defend" and bool(game.get("_horde_active")):
				_maintain_threat_response_plan(game)
			if ["prepare_army", "defend"].has(phase) and (int(game.get("stone")) >= 50 or int(game.get("meat")) < 60 or _live_player_farms().is_empty()):
				_release_excess_stone_workers(game, "stone reserve capped at 50 or farm/soldier reserve needs protection")
			_track_runtime(game)
			_track_soldier_training(game)
	if persist_clock >= 10.0:
		persist_clock = 0.0
		_persist()
	if done:
		return
	if wall_started_msec > 0 and Time.get_ticks_msec() - wall_started_msec >= wall_limit_msec:
		_finish(false, "wall_clock_limit_30_minutes")
		return
	# The controlled F5 -> title -> Continue sequence intentionally replaces
	# the Main scene. Keep the identity guard strict during ordinary play, but
	# let that explicitly bounded transaction verify the restored scene itself.
	var expected_continue_scene_swap := checkpoint_continue_busy and phase == "defend"
	if ["prepare_army", "wait_first_wave", "defend"].has(phase) and old_game_id != 0 and not expected_continue_scene_swap and (game == null or int(game.get_instance_id()) != old_game_id):
		_finish(false, "original_match_scene_identity_lost")
		return
	if busy:
		if game != null:
			await _service_combat_while_busy(game)
		return
	if trace_until_game_time > 0.0 and game != null and old_game_id != 0 and game.get_instance_id() == old_game_id and float(game.get("_game_time")) >= trace_until_game_time:
		_finish(false, "bounded_combat_trace_reached_game_time_%d" % int(trace_until_game_time))
		return
	if elapsed > 1800.0:
		_finish(false, "bounded_30_minute_run_no_real_end_panel")
		return
	if game != null and bool(game.get("_defeated")) and phase != "defeat_panel" and phase != "wait_retry":
		_freeze_terminal_state(game)
		if terminal_snapshot.is_empty():
			_finish(false, "terminal_snapshot_missing_at_defeat")
			return
		_checkpoint("real_defeat_panel", game)
		phase = "defeat_panel"
		phase_time = 0.0
	if game != null and bool(game.get("_victorious")) and phase != "victory_panel":
		_freeze_terminal_state(game)
		if terminal_snapshot.is_empty():
			_finish(false, "terminal_snapshot_missing_at_victory")
			return
		_checkpoint("real_victory_panel", game)
		phase = "victory_panel"
		phase_time = 0.0
	if game != null and ["prepare_army", "wait_first_wave", "defend"].has(phase):
		_issue_guards_for_new_soldiers(game)
	match phase:
		"menu":
			if game != null and game.get("_start_layer") != null:
				busy = true
				if DisplayServer.get_name() == "headless":
					var challenge_run := Engine.has_meta("aoelite_challenge5_run")
					var expected_mode := 1 if challenge_run else 0
					var mode: OptionButton = game.get("_start_mode_select") as OptionButton
					var seed_field: LineEdit = game.get("_seed_edit") as LineEdit
					var start_button: Button = game.get("_start_begin_button") as Button
					if mode == null or seed_field == null or start_button == null:
						_finish(false, "start_menu_controls_missing")
						return
					mode.select(expected_mode)
					mode.item_selected.emit(expected_mode)
					seed_field.text = "42"
					phase = "start_wait"
					phase_time = 0.0
					events.append({"action":"headless_start_menu_signals","seed":42,"mode":"challenge5" if challenge_run else "endless","mode_id":mode.get_selected_id(),"route":"OptionButton.item_selected and production Start button pressed signal","ordinary_menu_input_verified":true})
					start_button.pressed.emit()
				else:
					await _start_endless_seed42(game)
				busy = false
		"start_wait":
			if game != null and bool(game.get("_match_started")):
				old_game_id = game.get_instance_id()
				original_seed = int(game.get("map_seed"))
				start_game_time = float(game.get("_game_time"))
				_checkpoint("challenge5_victory_followed_by_endless_seed42_match_started" if post_challenge_endless_followup else "endless_seed42_match_started", game)
				if Engine.has_meta("aoelite_worker_economy_probe"):
					Engine.remove_meta("aoelite_worker_economy_probe")
					busy = true
					await _run_worker_economy_probe(game)
					busy = false
					return
				phase = "gather_wood"
				phase_time = 0.0
				busy = true
				var groups_ok: bool = await _establish_worker_groups(game)
				if not groups_ok:
					_finish(false, "worker_group_partition_failed")
					return
				await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "opening 4-worker wood assignment for the first farm")
				await _order_nearest_resource(game, ResourceNode3D.Kind.STONE, "opening 1-worker stone assignment for tower materials")
				busy = false
			elif phase_time > 15.0:
				_finish(false, "endless_seed42_start_failed")
		"gather_wood":
			if game != null and int(game.get("wood")) >= WOOD_PLAN:
				_checkpoint("first_paid_farm_75_wood_reached", game)
				phase = "opening_economy_and_first_tower"
				phase_time = 0.0
				busy = true
				await _prepare_fortifications(game)
				busy = false
				if phase == "gather_wood":
					_finish(false, "pre_wave_build_plan_failed")
			elif phase_time > 210.0:
				_finish(false, "wood_plan_not_reached")
		"wait_food_stone":
			if game != null and int(game.get("stone")) >= FIRST_TOWER_STONE and int(game.get("wood")) >= FIRST_TOWER_WOOD:
				phase = "build_tower"
				phase_time = 0.0
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(-6, 0, -5), Vector3(-8, 0, -6), Vector3(-5, 0, -8), Vector3(-10, 0, -4)])
				if not is_instance_valid(tower):
					_finish(false, "tower_not_placed")
					return
				_checkpoint("arrow_tower_complete", game)
				await _queue_available_soldiers(game)
				if DisplayServer.get_name() == "headless":
					_split_material_worker_groups(game)
					await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "wood for ongoing army reinforcements")
					await _order_nearest_resource(game, ResourceNode3D.Kind.STONE, "stone for additional arrow towers")
				else:
					await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "wood for ongoing army reinforcements")
				phase = "prepare_army"
				phase_time = 0.0
				busy = false
			elif phase_time > 240.0:
				_finish(false, "first_tower_budget_not_gathered")
		"prepare_army":
			var game_time := float(game.get("_game_time")) if game != null else 0.0
			if game != null and _live_player_farms().is_empty() and not _living_villagers().is_empty() and int(game.get("wood")) >= 75 and _farm_build_retry_ready(game) and not busy:
				campaign_command_reason = "farm recovery before additional towers or army expansion"
				busy = true
				await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -12), Vector3(14, 0, 6), Vector3(-12, 0, 12)])
				if not _live_player_farms().is_empty():
					_checkpoint("farm_rebuilt_after_all_farms_lost", game)
					await _gather_farm_food(game)
				busy = false
				return
			var remaining_food_stock := 0
			for live_farm in _live_player_farms(): remaining_food_stock += int(live_farm.get("meat_stock"))
			if game != null and _farm_is_live(farm) and not _farm_is_live(farm2) and remaining_food_stock <= 180 and int(game.get("wood")) >= 75 and _farm_build_retry_ready(game) and not busy:
				busy = true
				await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -12), Vector3(14, 0, 6), Vector3(-12, 0, 12)])
				if _farm_is_live(farm2):
					_checkpoint("second_farm_built_before_first_source_dried", game)
					await _gather_farm_food(game)
				busy = false
				return
			if game != null and not busy and is_instance_valid(barracks) and _player_military().size() + _queued_player_soldiers() < _army_target_for_wave(game) and game_time - last_army_queue_attempt_game_time >= 5.0:
				busy = true
				await _queue_available_soldiers(game)
				busy = false
			if game != null and not pre_wave_tower_attempted and not _farm_is_live(tower2) and _extra_tower_budget_ready(game) and _can_build_optional_tower(game):
				pre_wave_tower_attempted = true
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(6, 0, 0), Vector3(8, 0, -6), Vector3(5, 0, 5)])
				if _farm_is_live(tower2):
					_checkpoint("pre_wave_second_arrow_tower_complete", game)
					if DisplayServer.get_name() == "headless":
						await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "wood reserve after pre-wave tower")
						await _order_nearest_resource(game, ResourceNode3D.Kind.STONE, "stone reserve after pre-wave tower")
				busy = false
			elif game != null and (_player_military().size() >= 3 or game_time >= float(game.get("_horde_next_at")) - 18.0):
				if not army_group_checked and not _player_military().is_empty():
					busy = true
					await _verify_army_control_group(game)
					busy = false
				_checkpoint("army_ready_before_first_wave", game)
				phase = "wait_first_wave"
				phase_time = 0.0
			elif game != null and phase_time > 90.0:
				_checkpoint("army_preparation_limited_by_economy", game)
				phase = "wait_first_wave"
				phase_time = 0.0
		"wait_first_wave":
			if game != null and int(game.get("_horde_wave")) >= FIRST_WAVE:
				_checkpoint("wave1_spawned_live", game)
				phase = "defend"
				phase_time = 0.0
		"defend":
			if game == null:
				return
			_record_wave_economy_plan(game)
			if not checkpoint_continue_done and not checkpoint_continue_busy and int(game.get("_horde_wave")) == 1 and float(game.get("_game_time")) >= 230.0:
				busy = true
				checkpoint_continue_busy = true
				await _save_return_continue(game)
				checkpoint_continue_busy = false
				busy = false
				return
			_sample_combat(game)
			await _maintain_villager_population(game)
			if _living_villagers().is_empty():
				var tc := _player_tc()
				if bool(game.get("_horde_active")) and _player_military().size() < _army_target_for_wave(game) and _queued_player_soldiers() == 0 and float(game.get("_game_time")) - last_army_queue_attempt_game_time >= 5.0:
					busy = true
					await _queue_one_reinforcement(game)
					busy = false
				var wait_time := float(game.get("_game_time"))
				var villager_queue := _train_queue(tc) if is_instance_valid(tc) else []
				var villager_paid := bool(tc.get("train_paid")) if is_instance_valid(tc) else false
				var wait_signature := "%s:%s:%s:%d:%d:%d:%d" % [str(is_instance_valid(tc)), str(villager_queue), str(villager_paid), int(game.get("population")), int(game.call("_queued_pop")), int(game.get("pop_cap")), int(game.get("meat")) / 50]
				if wait_signature != last_recovery_wait_state_signature or wait_time - last_recovery_wait_logged_game_time >= 5.0:
					events.append({"action":"recovery_waiting_for_tc_recruited_builder","game_time":wait_time,"elapsed":elapsed,"reason":"no living builder; await ordinary TC queue pay-on-start and actual villager spawn","town_center_alive":is_instance_valid(tc),"food":int(game.get("meat")),"villager_queue":villager_queue,"villager_paid":villager_paid,"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap")),"army":_player_military().size(),"army_target":_army_target_for_wave(game)})
					last_recovery_wait_logged_game_time = wait_time
					last_recovery_wait_state_signature = wait_signature
				return
			last_recovery_wait_logged_game_time = -999.0
			last_recovery_wait_state_signature = ""
			var no_live_farm := _live_player_farms().is_empty()
			var recovery_plan := _barracks_recovery_plan(int(game.get("wood")), int(game.get("meat")), no_live_farm)
			var barracks_cost := int(recovery_plan.get("barracks_wood_cost", 150))
			if is_instance_valid(_player_tc()) and not _living_villagers().is_empty() and not is_instance_valid(barracks) and bool(recovery_plan.get("rebuild_first", false)) and not busy:
				campaign_command_reason = "restore lost barracks before farm when both real costs are funded and food can support one soldier"
				busy = true
				events.append({"action":"barracks_rebuild_started","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"wood_before":int(game.get("wood")),"wood_cost":barracks_cost,"farm_cost_reserved":int(recovery_plan.get("farm_wood_reserved", 0)),"food":int(game.get("meat")),"minimum_food_for_one_soldier":int(recovery_plan.get("food_minimum", 60)),"army":_player_military().size(),"worker_count":_living_villagers().size(),"farm_missing":no_live_farm})
				await _build_at(game, Catalog.BARRACKS, "兵营", [Vector3(-12, 0, 0), Vector3(-14, 0, 8), Vector3(14, 0, 4), Vector3(14, 0, -6)])
				if is_instance_valid(barracks):
					_checkpoint("barracks_rebuilt_after_loss", game)
					await _queue_available_soldiers(game)
					busy = false
					return
				busy = false
			var tc_for_backup := _player_tc()
			var tc_backup_threshold := is_instance_valid(tc_for_backup) and float(tc_for_backup.get("hp")) <= float(tc_for_backup.get("max_hp")) * 0.5
			var tc_capacity_lost := not is_instance_valid(tc_for_backup) or int(game.get("pop_cap")) <= 0
			if (tc_backup_threshold or tc_capacity_lost) and _live_player_houses().is_empty() and _backup_house_cooldown_ready(game):
				campaign_command_reason = "build backup population capacity before or after town center loss"
				busy = true
				_reserve_backup_house_attempt(game)
				events.append({"action":"emergency_population_capacity_build_started","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"town_center_alive":is_instance_valid(tc_for_backup),"town_center_hp":float(tc_for_backup.get("hp")) if is_instance_valid(tc_for_backup) else 0.0,"town_center_backup_threshold_hp":float(tc_for_backup.get("max_hp")) * 0.5 if is_instance_valid(tc_for_backup) else 0.0,"living_villagers":_living_villagers().size(),"pop_cap":int(game.get("pop_cap")),"wood_before":int(game.get("wood")),"wood_cost":int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 50))})
				await _build_at(game, Catalog.HOUSE, "房屋", _backup_house_candidates(game))
				if not _live_player_houses().is_empty():
					_checkpoint("backup_population_capacity_restored_while_tc_threatened_or_lost", game)
				else:
					events.append({"action":"emergency_population_capacity_build_failed","game_time":float(game.get("_game_time")),"wood":int(game.get("wood")),"reason":"all candidate locations rejected or no eligible builder"})
				backup_house_attempt_in_progress = false
				busy = false
				return
			if _live_player_farms().is_empty() and not _living_villagers().is_empty() and int(game.get("wood")) >= 75 and _farm_build_retry_ready(game) and not busy:
				campaign_command_reason = "farm recovery before additional towers or army expansion"
				busy = true
				await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -12), Vector3(14, 0, 6), Vector3(-12, 0, 12)])
				if not _live_player_farms().is_empty():
					_checkpoint("farm_rebuilt_after_all_farms_lost", game)
					await _gather_farm_food(game)
				busy = false
				return
			var target_army := _army_target_for_wave(game)
			var target_workers := _villager_target_for_wave(game)
			var current_villager_commitment := _living_villagers().size() + _queued_player_villagers()
			if target_workers > int(game.get("pop_cap")) and current_villager_commitment < target_workers and _backup_house_cooldown_ready(game):
				campaign_command_reason = "add real population capacity for the worker target only"
				busy = true
				_reserve_backup_house_attempt(game)
				events.append({"action":"population_capacity_build_started","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"army_target_does_not_consume_civilian_capacity":target_army,"workers_target":target_workers,"living_villagers":_living_villagers().size(),"queued_villagers":_queued_player_villagers(),"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap")),"wood_before":int(game.get("wood")),"wood_cost":int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 50))})
				await _build_at(game, Catalog.HOUSE, "房屋", [Vector3(0, 0, 16), Vector3(10, 0, 10), Vector3(-10, 0, 12), Vector3(8, 0, 16)])
				backup_house_attempt_in_progress = false
				busy = false
				return
			if _check_enemy_progress_stall(game):
				return
			var wave_one := _wave_counts("1")
			if bool(wave_one.get("complete", false)) and not bool(wave_one.get("completion_checkpoint", false)):
				var wave_one_record: Dictionary = wave_ledger.get("1", {})
				wave_one_record["completion_checkpoint"] = true
				wave_ledger["1"] = wave_one_record
				_checkpoint("wave1_fully_cleared", game)
			var remaining_food_stock := 0
			for live_farm in _live_player_farms(): remaining_food_stock += int(live_farm.get("meat_stock"))
			if not _farm_is_live(farm2) and remaining_food_stock <= 180 and int(game.get("wood")) >= 75 and _farm_build_retry_ready(game) and not busy and not _living_villagers().is_empty():
				busy = true
				await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -12), Vector3(14, 0, 6), Vector3(-12, 0, 12)])
				if _farm_is_live(farm2):
					_checkpoint("second_farm_built_before_first_source_dried", game)
					await _gather_farm_food(game)
				busy = false
				return
			if not busy:
				busy = true
				await _service_tower_materials(game)
				busy = false
			if bool(wave_one.get("complete", false)) and not _farm_is_live(tower2) and elapsed - last_tower2_attempt_at >= 25.0 and not _living_villagers().is_empty() and not busy and _extra_tower_budget_ready(game) and _can_build_optional_tower(game):
				last_tower2_attempt_at = elapsed
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(0, 0, -10), Vector3(3, 0, -12), Vector3(4, 0, -10), Vector3(0, 0, -12)])
				if _farm_is_live(tower2):
					_checkpoint("second_arrow_tower_complete", game)
				busy = false
			if int(game.get("_horde_wave")) >= 2 and not third_tower_attempted and not _living_villagers().is_empty() and not busy and _extra_tower_budget_ready(game) and _can_build_optional_tower(game):
				third_tower_attempted = true
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(-6, 0, -10), Vector3(-5, 0, -8), Vector3(6, 0, -3), Vector3(12, 0, -7), Vector3(13, 0, -7)])
				if _farm_is_live(tower3): _checkpoint("third_arrow_tower_complete", game)
				else: events.append({"action":"third_arrow_tower_unavailable","wood":game.get("wood"),"stone":game.get("stone")})
				busy = false
			if int(game.get("_horde_wave")) >= 2 and not fourth_tower_attempted and not _living_villagers().is_empty() and not busy and _extra_tower_budget_ready(game) and _can_build_optional_tower(game):
				fourth_tower_attempted = true
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(-8, 0, -10), Vector3(-8, 0, -6), Vector3(-6, 0, -14), Vector3(0, 0, -20)])
				if _farm_is_live(tower4): _checkpoint("fourth_arrow_tower_complete", game)
				else: events.append({"action":"fourth_tower_unavailable","wood":game.get("wood"),"stone":game.get("stone")})
				busy = false
			if int(game.get("_horde_wave")) >= 3 and not fifth_tower_attempted and not _living_villagers().is_empty() and not busy and _extra_tower_budget_ready(game) and _can_build_optional_tower(game):
				fifth_tower_attempted = true
				busy = true
				await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(7, 0, 2), Vector3(6, 0, 6), Vector3(-6, 0, 4), Vector3(-10, 0, -10)])
				if _farm_is_live(tower5): _checkpoint("fifth_arrow_tower_complete", game)
				else: events.append({"action":"fifth_tower_unavailable","wood":game.get("wood"),"stone":game.get("stone")})
				busy = false
			var target_stalled := is_instance_valid(last_target) and bool(last_target.get("alive")) and float(game.get("_game_time")) - last_target_progress_at >= 7.0
			if (not _has_active_player_order() or target_stalled) and not _living_zombies().is_empty():
				campaign_command_reason = "retarget active wave after no target or stalled target HP"
				busy = true
				await _issue_next_visible_attack(game, "no_active_combat_target" if not _has_active_player_order() else "previous_target_hp_stalled_for_7_game_seconds")
				busy = false
			if int(game.get("_horde_wave")) >= 1 and _player_military().size() < _army_target_for_wave(game) and _queued_player_soldiers() == 0 and float(game.get("_game_time")) - last_army_queue_attempt_game_time >= 5.0 and not busy:
				campaign_command_reason = "replace lost soldier after live army loss / wave pressure"
				busy = true
				await _queue_one_reinforcement(game)
				busy = false
			if not busy and _food_service_needed(game) and elapsed - last_food_order_at > 10.0:
				busy = true
				await _maintain_food_supply(game)
				busy = false
			if not busy and not _living_villagers().is_empty() and int(game.get("meat")) >= 240 and elapsed - last_wood_order_at > 18.0 and not _villagers_gathering_wood() and not _evacuated_workers_pending():
				busy = true
				last_wood_order_at = elapsed
				await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "wood income while food reserve is stable")
				busy = false
			if int(game.get("_horde_wave")) >= 6 and not wave6_checkpointed:
				wave6_checkpointed = true
				endless_wave6_started_at = float(game.get("_game_time"))
				_checkpoint("endless_wave6_reached_after_challenge5_victory" if post_challenge_endless_followup else "endless_wave6_plus_reached_continue_run", game)
			if post_challenge_endless_followup and wave6_checkpointed and endless_wave6_started_at >= 0.0 and float(game.get("_game_time")) >= endless_wave6_started_at + 45.0:
				_checkpoint("endless_wave6_plus_45_game_seconds_after_challenge5_victory", game)
				events.append({"action":"challenge5_victory_and_endless_continuation_verified","challenge5_terminal_snapshot_preserved_in_events":true,"endless_seed":int(game.get("map_seed")),"endless_wave":int(game.get("_horde_wave")),"wave6_started_game_time":endless_wave6_started_at,"wave6_plus_45_game_seconds":float(game.get("_game_time"))})
				_finish(true, "challenge5_natural_victory_then_endless_wave6_plus_45_game_seconds")
		"defeat_panel":
			if game != null and _defeat_panel_ready(game):
				_checkpoint("defeat_panel_visible_confirmed", game)
				if Engine.has_meta("aoelite_challenge5_run"):
					_checkpoint("challenge5_failed_before_victory", game)
					await _return_from_terminal_to_start(game, false)
					return
				busy = true
				defeat_seed = int(game.get("map_seed"))
				var retry: Button = _button(game.get("hud"), "再来一局")
				if retry == null:
					_finish(false, "real_defeat_panel_retry_button_missing")
					return
				await get_tree().process_frame
				await get_tree().process_frame
				if DisplayServer.get_name() == "headless":
					# Emit the real Button signal so the HUD's original connection invokes
					# _on_defeat_retry and _restart_match_new_map without viewport geometry.
					retry.pressed.emit()
					events.append({"action":"retry_button_pressed_signal_emitted","target":retry.name,"callback_connections":retry.pressed.get_connections().size()})
				else:
					await _click_control(retry)
					if not str(_last_click.get("hovered_control", "")).ends_with("BtnRetry"):
						events.append({"action":"retry_button_first_click_missed","hovered_control":_last_click.get("hovered_control"),"target":retry.name,"position":_last_click.get("position")})
						await get_tree().process_frame
						await _click_control(retry)
				phase = "wait_retry"
				phase_time = 0.0
				busy = false
			elif phase_time > 15.0:
				_finish(false, "defeat_state_without_visible_end_panel")
		"wait_retry":
			if game != null and (game.get_instance_id() != old_game_id or int(game.get("map_seed")) != defeat_seed) and bool(game.get("_match_started")):
				busy = true
				await get_tree().create_timer(1.0).timeout
				var check := _retry_snapshot(game)
				events.append({"action":"retry_button_new_match_verified","elapsed":elapsed,"old_seed":defeat_seed,"new_seed":game.get("map_seed"),"state":check,"retry_ok":bool(check.get("valid", false))})
				_checkpoint("retry_new_random_map_running", game)
				busy = false
				_finish(bool(check.get("valid", false)), "real_defeat_retry_opened_new_match")
			elif phase_time > 20.0:
				_finish(false, "retry_did_not_open_new_match")
		"victory_panel":
			if game != null and _defeat_panel_ready(game):
				_checkpoint("challenge_victory_panel_visible", game)
				await _return_from_terminal_to_start(game, true)

func _return_from_terminal_to_start(game: Node, victory: bool) -> void:
	var old_game_id := int(game.get_instance_id())
	var hud: Node = game.get("hud")
	var to_start := _button(hud, "返回开局")
	if to_start == null:
		events.append({"action":"terminal_return_failed","reason":"actual return-to-start button missing","victory":victory})
		_finish(false, "terminal_return_button_missing")
		return
	if DisplayServer.get_name() == "headless":
		to_start.pressed.emit()
	else:
		await _click_control(to_start)
	events.append({"action":"real_terminal_return_pressed","victory":victory,"button":to_start.name,"route":"terminal result panel Return to Start Button.pressed"})
	var menu: Node = null
	for _frame in 1800:
		await get_tree().process_frame
		menu = get_tree().get_first_node_in_group("main_game")
		if menu != null and int(menu.get_instance_id()) != old_game_id and menu.get("_start_layer") != null:
			break
	var mode_select: OptionButton = menu.get("_start_mode_select") as OptionButton if menu != null else null
	var mode_id := mode_select.get_selected_id() if mode_select != null else -1
	var returned := menu != null and int(menu.get_instance_id()) != old_game_id and menu.get("_start_layer") != null and mode_id == 1
	events.append({"action":"terminal_return_menu_verified","victory":victory,"returned_to_new_start_screen":returned,"mode_id":mode_id,"expected_mode_id":1,"seed_field":str((menu.get("_seed_edit") as LineEdit).text) if menu != null and menu.get("_seed_edit") is LineEdit else ""})
	if victory and returned and Engine.has_meta("aoelite_challenge5_run"):
		events.append({"action":"challenge5_victory_terminal_snapshot_archived_before_endless","terminal_snapshot":terminal_snapshot.duplicate(true),"terminal_combat_summary":terminal_combat_summary.duplicate(true),"terminal_wave_ledger":terminal_wave_ledger.duplicate(true)})
		Engine.remove_meta("aoelite_challenge5_run")
		post_challenge_endless_followup = true
		farm = null
		farm2 = null
		house = null
		barracks = null
		tower = null
		tower2 = null
		tower3 = null
		tower4 = null
		tower5 = null
		last_target = null
		last_target_hp = -1.0
		last_target_progress_at = 0.0
		last_command_at = -999.0
		last_reinforce_at = -999.0
		last_food_order_at = -999.0
		last_wood_order_at = -999.0
		last_tower_material_order_at = -999.0
		last_worker_group_living_count = -1
		army_seen.clear()
		defeat_seed = 0
		contact_checkpointed.clear()
		wave6_checkpointed = false
		army_group_checked = false
		third_tower_attempted = false
		fourth_tower_attempted = false
		fifth_tower_attempted = false
		pre_wave_tower_attempted = false
		last_tower2_attempt_at = -999.0
		attack_move_wave_sent.clear()
		initial_guard_orders_issued = false
		guard_ordered_runtime_ids.clear()
		guard_unavailable_logged_runtime_ids.clear()
		villager_training_pending = false
		villager_count_at_last_queue = -1
		last_villager_queue_attempt_game_time = -999.0
		last_army_queue_attempt_game_time = -999.0
		last_soldier_queue_block_signature = ""
		tracked_training_barracks_id = 0
		tracked_training_queue.clear()
		tracked_training_paid = false
		tracked_training_paused = false
		tracked_training_army_names.clear()
		tracked_training_resources.clear()
		enemy_progress_watch.clear()
		enemy_watch_last_sample = 0.0
		runtime_enemy_seen.clear()
		runtime_enemy_stable_key.clear()
		stable_enemy_ids.clear()
		checkpoint_continue_done = false
		checkpoint_continue_busy = false
		_last_shift_click.clear()
		terminal_snapshot = {}
		terminal_wave_ledger = {}
		terminal_combat_summary = {}
		wave_ledger.clear()
		combat_samples.clear()
		building_first_hp.clear()
		contact_checkpointed.clear()
		wave6_checkpointed = false
		endless_wave6_started_at = -1.0
		old_game_id = int(menu.get_instance_id())
		last_game = menu
		busy = true
		await _start_endless_seed42(menu)
		busy = false
		return
	_finish(victory and returned, "challenge5_victory_returned_to_mode_menu" if victory and returned else "challenge5_natural_defeat_returned_to_mode_menu" if returned else "terminal_return_menu_or_mode_mismatch")

func _start_endless_seed42(game: Node) -> void:
	var mode: OptionButton = game.get("_start_mode_select") as OptionButton
	var seed: LineEdit = game.get("_seed_edit") as LineEdit
	var start: Button = _button(game.get("_start_layer"), "开始")
	if mode == null or seed == null or start == null:
		_finish(false, "start_menu_controls_missing")
		return
	var challenge_run := Engine.has_meta("aoelite_challenge5_run")
	var expected_mode := 1 if challenge_run else 0
	var mode_id_before := mode.get_selected_id()
	if mode_id_before != expected_mode:
		# Drive the same OptionButton selection signal as a menu item click. PopupMenu
		# is a separate Window, so root-viewport mouse injection does not reach it.
		mode.select(expected_mode)
		mode.item_selected.emit(expected_mode)
		await get_tree().process_frame
	await _click_control(seed)
	await _send_key(KEY_4, 52)
	await _send_key(KEY_2, 50)
	var seed_value := str(seed.text)
	var mode_id := mode.get_selected_id()
	events.append({"action":"actual_start_menu_input","mode_id_before":mode_id_before,"mode_id_after":mode_id,"expected_mode":expected_mode,"seed_text":seed_value,"route":"OptionButton item_selected, GUI seed entry, and start button"})
	if mode_id != expected_mode or seed_value != "42":
		_finish(false, "requested_mode_or_seed_menu_input_not_accepted")
		return
	await _click_control(start)
	phase = "start_wait"
	phase_time = 0.0
	busy = false

func _prepare_fortifications(game: Node) -> void:
	# Pay for the food source first. Forestry is paid before tower wood is reserved;
	# once the 100-wood tower budget is reached, no optional order spends it.
	await _build_at(game, Catalog.FARM, "农田", [Vector3(12, 0, 0), Vector3(14, 0, -6)])
	if not is_instance_valid(farm): return
	_checkpoint("first_farm_complete", game)
	await _set_opening_worker_roles(game)
	await _pay_forestry_research(game)
	if int(game.get("stone")) < FIRST_TOWER_STONE:
		await _wait_for_stock(game, "stone", FIRST_TOWER_STONE, 120.0)
	if int(game.get("stone")) < FIRST_TOWER_STONE:
		_finish(false, "first_tower_stone_budget_not_gathered")
		return
	await _move_surplus_stone_workers_to_wood(game)
	if int(game.get("wood")) < FIRST_TOWER_WOOD:
		await _wait_for_stock(game, "wood", FIRST_TOWER_WOOD, 150.0)
	if int(game.get("wood")) < FIRST_TOWER_WOOD or int(game.get("stone")) < FIRST_TOWER_STONE:
		_finish(false, "first_tower_budget_not_gathered")
		return
	events.append({"action":"first_tower_full_budget_reserved","wood":int(game.get("wood")),"wood_cost":FIRST_TOWER_WOOD,"stone":int(game.get("stone")),"stone_cost":FIRST_TOWER_STONE,"food":int(game.get("meat")),"optional_orders_blocked_until_tower_paid":["villager","soldier","house"],"time_scale":Engine.time_scale})
	await _build_at(game, Catalog.ARROW_TOWER, "箭塔", [Vector3(-6, 0, -5), Vector3(-8, 0, -6), Vector3(-5, 0, -8), Vector3(-10, 0, -4)])
	if not is_instance_valid(tower):
		_finish(false, "tower_not_placed_after_full_budget_precheck")
		return
	_checkpoint("first_arrow_tower_paid_and_complete", game)
	await _split_material_worker_groups(game, false)
	await _order_group_roles(game, "food and wood assignments after first tower payment")
	await _wait_for_opening_barracks_budget(game)
	if done or int(game.get("wood")) < int(Catalog.get_def(Catalog.BARRACKS).get("cost_wood", 0)):
		_finish(false, "barracks_budget_not_gathered_after_tower")
		return
	await _build_at(game, Catalog.BARRACKS, "兵营", [Vector3(-12, 0, 0), Vector3(-14, 0, 8)])
	if not is_instance_valid(barracks):
		_finish(false, "barracks_not_placed_after_full_budget_precheck")
		return
	_checkpoint("barracks_complete", game)
	phase = "prepare_army"
	phase_time = 0.0
	await _queue_available_soldiers(game)
	if _population_pressure_requires_house(game):
		await _build_house_for_actual_population_need(game)

func _set_opening_worker_roles(game: Node) -> void:
	var living := _living_villagers()
	var stone_workers := _control_group_units(game, 4).filter(func(w): return living.has(w))
	if stone_workers.is_empty() and not living.is_empty(): stone_workers = [living.back()]
	var wood_candidates := living.filter(func(w): return not stone_workers.has(w))
	if wood_candidates.size() < 2: return
	var food_workers: Array = [wood_candidates[0]]
	var wood_workers: Array = wood_candidates.slice(1)
	_select_units(game, food_workers)
	game.call("_assign_control_group", 3)
	_select_units(game, wood_workers)
	game.call("_assign_control_group", 2)
	_select_units(game, stone_workers)
	game.call("_assign_control_group", 4)
	var food_source: Node3D = farm
	var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
	var stone_node := _nearest_resource(ResourceNode3D.Kind.STONE)
	if wood_node != null: _issue_gather_order(game, wood_workers, wood_node, "opening: three workers gather wood after first farm")
	if stone_node != null: _issue_gather_order(game, stone_workers, stone_node, "opening: collect exactly the first tower stone reserve")
	if is_instance_valid(food_source): _issue_gather_order(game, food_workers, food_source, "opening: keep one food worker active while funding the first tower")
	_select_units(game, living)
	last_worker_group_living_count = living.size()
	events.append({"action":"opening_budget_worker_roles","food_workers":_villager_ids(food_workers),"wood_workers":_villager_ids(wood_workers),"stone_workers":_villager_ids(stone_workers),"targets":{"food":1,"wood":3,"stone":1},"first_tower_wood_reserve":FIRST_TOWER_WOOD,"first_tower_stone_target":FIRST_TOWER_STONE})

func _pay_forestry_research(game: Node) -> void:
	var research: Node = game.get("research")
	if research == null or research.call("has_technology", Research.TECH_FORESTRY): return
	var cost: Dictionary = Research.TECH_COSTS[Research.TECH_FORESTRY]
	var start_time := float(game.get("_game_time"))
	while not done and float(game.get("_game_time")) - start_time < 90.0 and (int(game.get("wood")) < int(cost.get("wood", 0)) or int(game.get("meat")) < int(cost.get("meat", 0))):
		await get_tree().create_timer(0.25).timeout
	if int(game.get("wood")) < int(cost.get("wood", 0)) or int(game.get("meat")) < int(cost.get("meat", 0)):
		events.append({"action":"forestry_research_deferred","reason":"normal 10-wood / 25-food cost not yet available","wood":int(game.get("wood")),"food":int(game.get("meat"))})
		return
	var tc := _player_tc()
	if tc == null:
		events.append({"action":"forestry_research_deferred","reason":"town center unavailable"})
		return
	var wood_before := int(game.get("wood"))
	var food_before := int(game.get("meat"))
	_select_units(game, [tc])
	game.call("_on_research_forestry")
	var completed: bool = research.call("has_technology", Research.TECH_FORESTRY)
	events.append({"action":"forestry_research_paid_before_tower_reserve","completed":completed,"wood_before":wood_before,"wood_after":int(game.get("wood")),"wood_cost":int(cost.get("wood",0)),"food_before":food_before,"food_after":int(game.get("meat")),"food_cost":int(cost.get("meat",0)),"route":"selected production TC -> Main._on_research_forestry"})

func _move_surplus_stone_workers_to_wood(game: Node) -> void:
	if int(game.get("stone")) < FIRST_TOWER_STONE: return
	var stone_workers := _control_group_units(game, 4)
	var wood_workers := _control_group_units(game, 2)
	if stone_workers.is_empty(): return
	_select_units(game, wood_workers + stone_workers)
	game.call("_assign_control_group", 2)
	_select_units(game, [])
	game.call("_assign_control_group", 4)
	var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
	if wood_node != null:
		_issue_gather_order(game, stone_workers, wood_node, "stone reserve reached 50; redirect surplus stone worker to first-tower wood budget")
	last_worker_group_living_count = _living_villagers().size()
	events.append({"action":"stone_target_reached_worker_reassigned","stone":int(game.get("stone")),"target":FIRST_TOWER_STONE,"reassigned_workers":_villager_ids(stone_workers),"to":"wood","wood":int(game.get("wood"))})

func _order_group_roles(game: Node, reason: String) -> void:
	var farm_source: Node3D = farm2 if _farm_is_live(farm2) else farm
	var food_workers := _control_group_units(game, 3)
	var wood_workers := _control_group_units(game, 2)
	var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
	if _farm_is_live(farm_source): _issue_gather_order(game, food_workers, farm_source, reason)
	if wood_node != null: _issue_gather_order(game, wood_workers, wood_node, reason)

func _wait_for_opening_barracks_budget(game: Node) -> void:
	var required_wood := int(Catalog.get_def(Catalog.BARRACKS).get("cost_wood", 0))
	var start_time := float(game.get("_game_time"))
	while not done and float(game.get("_game_time")) - start_time < 210.0:
		var food_stock := int(farm.get("meat_stock")) if _farm_is_live(farm) else 0
		if not _farm_is_live(farm2) and food_stock <= 180 and int(game.get("wood")) >= WOOD_PLAN and _farm_build_retry_ready(game):
			await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -12), Vector3(14, 0, 6), Vector3(-12, 0, 12)])
			if _farm_is_live(farm2):
				_checkpoint("second_farm_built_before_barracks_budget", game)
				await _gather_farm_food(game)
		if int(game.get("wood")) >= required_wood:
			events.append({"action":"opening_barracks_budget_ready_after_tower","wood":int(game.get("wood")),"cost":required_wood,"game_time":float(game.get("_game_time")),"tower_already_paid":_farm_is_live(tower),"farm_stock":int(farm.get("meat_stock")) if _farm_is_live(farm) else 0,"second_farm_live":_farm_is_live(farm2)})
			return
		await get_tree().create_timer(0.25).timeout
	events.append({"action":"opening_barracks_budget_timeout","wood":int(game.get("wood")),"cost":required_wood,"game_time":float(game.get("_game_time"))})

func _population_pressure_requires_house(game: Node) -> bool:
	var worker_target := _villager_target_for_wave(game)
	var committed_villagers := _living_villagers().size() + _queued_player_villagers()
	return worker_target > int(game.get("pop_cap")) and committed_villagers < worker_target

func _army_target_for_wave(game: Node) -> int:
	return _army_target_for_mode_wave(int(game.get("_horde_mode")), int(game.get("_horde_wave")))

func _army_target_for_mode_wave(mode: int, wave: int) -> int:
	if mode == 1:
		match wave:
			1: return 5
			2: return 6
			3: return 7
			4: return 8
			5: return 10
			_: return 10
	# Preserve the existing Endless progression after the Challenge-specific plan.
	if wave < 6: return 5
	if wave < 10: return 6
	if wave < 14: return 7
	if wave < 18: return 8
	if wave < 22: return 9
	return 10

func _villager_target_for_wave(game: Node) -> int:
	if int(game.get("_horde_mode")) != 1: return TARGET_VILLAGERS
	match int(game.get("_horde_wave")):
		1, 2: return 5
		3, 4: return 6
		5: return 7
		_: return 7

func _record_wave_economy_plan(game: Node) -> void:
	var wave := int(game.get("_horde_wave"))
	if wave < 1 or wave == last_wave_economy_plan_logged: return
	last_wave_economy_plan_logged = wave
	var army_target := _army_target_for_wave(game)
	var worker_target := _villager_target_for_wave(game)
	var army_count := _player_military().size()
	var queued := _queued_player_soldiers()
	var deficit := maxi(0, army_target - army_count - queued)
	var pop_room := maxi(0, int(game.get("pop_cap")) - int(game.get("population")) - int(game.call("_queued_pop")))
	var combined_population_target := army_target + worker_target
	var enemies: Dictionary = _wave_counts(str(wave))
	var food_workers_planned := clampi(1 + int((wave - 1) / 2), 1, 3)
	events.append({"action":"wave_economy_plan","game_time":float(game.get("_game_time")),"elapsed":elapsed,"wave":wave,"expected_enemies":int(enemies.get("expected",0)),"army_target":army_target,"army_current":army_count,"army_queued":queued,"unfilled_slots":deficit,"wood_needed_for_slots":deficit * int(Catalog.train_cost("soldier").get("wood",20)),"food_needed_for_slots":deficit * int(Catalog.train_cost("soldier").get("meat",60)),"population_room":pop_room,"combined_population_target":combined_population_target,"population_capacity_needed":maxi(0,combined_population_target-int(game.get("population"))-int(game.call("_queued_pop"))),"workers_target":worker_target,"workers_current":_living_villagers().size(),"food_workers_planned":food_workers_planned,"note":"Orders use the ordinary queue only with normal prices and population room; each house costs 50 wood and adds 10 capacity."})

func _barracks_recovery_plan(wood: int, food: int, farm_missing: bool, living_workers: int = 1, pop_room: int = 99) -> Dictionary:
	var barracks_wood_cost := int(Catalog.get_def(Catalog.BARRACKS).get("cost_wood", 150))
	var farm_wood_cost := int(Catalog.get_def(Catalog.FARM).get("cost_wood", 75))
	var food_minimum := int(Catalog.train_cost("soldier").get("meat", 60))
	var soldier_wood_cost := int(Catalog.train_cost("soldier").get("wood", 20))
	var needs_tc_recruit := living_workers <= 0
	var tc_recruit_food_cost := int(Catalog.train_cost("villager").get("meat", 50)) if needs_tc_recruit else 0
	var food_required_total := food_minimum + tc_recruit_food_cost
	var required_pop_room := 2 if needs_tc_recruit else 1
	var farm_wood_reserved := farm_wood_cost if farm_missing else 0
	var can_build_barracks := wood >= barracks_wood_cost
	var can_rebuild_and_recruit := wood >= barracks_wood_cost + soldier_wood_cost and food >= food_minimum
	var can_preserve_farm := not farm_missing or wood >= barracks_wood_cost + farm_wood_cost
	var full_recovery_wood_cost := barracks_wood_cost + soldier_wood_cost + farm_wood_reserved
	var has_required_pop_room := pop_room >= required_pop_room
	var worker_available := not needs_tc_recruit
	var can_complete_recovery_plan := worker_available and has_required_pop_room and wood >= full_recovery_wood_cost and food >= food_required_total
	return {"rebuild_first":can_complete_recovery_plan,"can_build_barracks":can_build_barracks,"can_rebuild_and_recruit":can_rebuild_and_recruit,"can_preserve_farm":can_preserve_farm,"can_complete_recovery_plan":can_complete_recovery_plan,"worker_available":worker_available,"needs_tc_recruit":needs_tc_recruit,"tc_recruit_food_cost":tc_recruit_food_cost,"food_required_total":food_required_total,"pop_room":pop_room,"required_pop_room":required_pop_room,"has_required_pop_room":has_required_pop_room,"barracks_wood_cost":barracks_wood_cost,"soldier_wood_cost":soldier_wood_cost,"farm_wood_reserved":farm_wood_reserved,"food_minimum":food_minimum,"full_recovery_wood_cost":full_recovery_wood_cost,"wood_after_barracks":wood-barracks_wood_cost}

func _build_house_for_actual_population_need(game: Node) -> void:
	var cost := int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 0))
	if int(game.get("wood")) < cost:
		await _wait_for_stock(game, "wood", cost, 90.0)
	if int(game.get("wood")) >= cost and _population_pressure_requires_house(game):
		events.append({"action":"house_ordered_for_actual_population_cap_pressure","population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap")),"wood_before":int(game.get("wood")),"cost":cost})
		await _build_at(game, Catalog.HOUSE, "房屋", [Vector3(0, 0, 16), Vector3(10, 0, 10), Vector3(-10, 0, 12)])
		if is_instance_valid(house): _checkpoint("house_built_for_actual_population_cap_pressure", game)

func _wait_for_stock(game: Node, resource_key: String, required: int, timeout: float) -> bool:
	var started := float(game.get("_game_time"))
	while not done and is_instance_valid(game) and float(game.get("_game_time")) - started < timeout:
		if int(game.get(resource_key)) >= required:
			events.append({"action":"opening_resource_threshold_reached","resource":resource_key,"required":required,"actual":int(game.get(resource_key)),"game_time":float(game.get("_game_time"))})
			return true
		await get_tree().create_timer(0.25).timeout
	return false

func _queue_one_villager(game: Node, reason: String) -> bool:
	var tc := _player_tc()
	if tc == null or int(game.get("meat")) < 50 or int(game.get("population")) + int(game.call("_queued_pop")) >= int(game.get("pop_cap")):
		events.append({"action":"opening_villager_training_deferred","reason":reason,"town_center_alive":tc != null,"meat":int(game.get("meat")),"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap"))})
		return false
	_select_units(game, [tc])
	var before_queue := _train_queue(tc).size()
	var before_meat := int(game.get("meat"))
	game.call("_on_train_villager")
	var accepted := _train_queue(tc).size() > before_queue
	if accepted:
		villager_training_pending = true
		villager_count_at_last_queue = _living_villagers().size()
	events.append({"action":"opening_villager_training_order","reason":reason,"route":"Main._on_train_villager -> normal TC queue/payment","queue_before":before_queue,"queue_after":_train_queue(tc).size(),"meat_before":before_meat,"meat_after":int(game.get("meat")),"accepted":accepted})
	return accepted

func _maintain_villager_population(game: Node) -> void:
	var living := _living_villagers().size()
	var tc := _player_tc()
	var queue_has_villager := tc != null and _train_queue(tc).has("villager")
	if villager_training_pending and living > villager_count_at_last_queue:
		villager_training_pending = false
		events.append({"action":"paid_villager_joined_workforce","villagers":living,"game_time":float(game.get("_game_time"))})
	elif villager_training_pending and not queue_has_villager and living <= villager_count_at_last_queue:
		villager_training_pending = false
	if living >= _villager_target_for_wave(game) or villager_training_pending or queue_has_villager or tc == null:
		return
	var army_deficit_during_wave := bool(game.get("_horde_active")) and _player_military().size() + _queued_player_soldiers() < _army_target_for_wave(game)
	if army_deficit_during_wave:
		var soldier_food := int(Catalog.train_cost("soldier").get("meat", 60))
		var villager_food := int(Catalog.train_cost("villager").get("meat", 50))
		var soldier_wood := int(Catalog.train_cost("soldier").get("wood", 20))
		if int(game.get("meat")) - villager_food < soldier_food:
			var reserve_signature := "%d:%d:%d:%d" % [int(game.get("_horde_wave")), _player_military().size(), int(game.get("meat")), int(game.get("wood"))]
			if reserve_signature != last_villager_reserve_signature:
				events.append({"action":"villager_training_deferred_for_active_army_reserve","game_time":float(game.get("_game_time")),"army":_player_military().size(),"army_target":_army_target_for_wave(game),"wood":int(game.get("wood")),"food":int(game.get("meat")),"reserved_soldier_cost":{"wood":soldier_wood,"meat":soldier_food},"villager_cost":{"meat":villager_food},"reason":"do not spend the only soldier food reserve on a new villager during active combat"})
				last_villager_reserve_signature = reserve_signature
			return
	last_villager_reserve_signature = ""
	if int(game.get("meat")) < 50 or int(game.get("population")) + int(game.call("_queued_pop")) >= int(game.get("pop_cap")):
		return
	var now := float(game.get("_game_time"))
	if now - last_villager_queue_attempt_game_time < 5.0: return
	last_villager_queue_attempt_game_time = now
	await _queue_one_villager(game, "replace observed worker loss / restore five-worker operating minimum")

func _build_at(game: Node, kind: int, label: String, candidates: Array[Vector3]) -> void:
	if done: return
	if kind == Catalog.FARM and float(game.get("_game_time")) - last_farm_placement_attempt_game_time < 25.0: return
	if kind == Catalog.FARM: last_farm_placement_attempt_game_time = float(game.get("_game_time"))
	campaign_command_reason = "build request: " + label
	events.append({"action":"player_build_command_issued","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"kind":kind,"label":label,"target_positions":candidates.map(func(p): return _v3(p)),"resources_before":_training_resource_snapshot(game),"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap"))})
	if not await _wait_for_build_funds(game, kind, label): return
	if DisplayServer.get_name() == "headless":
		await _build_at_headless(game, kind, label, candidates)
		return
	if _living_villagers().is_empty():
		events.append({"action":"building_unavailable_without_living_villagers","kind":kind,"label":label,"wood":game.get("wood"),"stone":game.get("stone")})
		return
	await _ensure_villager_selection(game)
	await _send_key(KEY_S)
	await _send_key(KEY_B)
	var hud: Node = game.get("hud")
	var build_grid: Node = hud.get("_build_grid") if hud != null else null
	var btn: Button = null
	for _attempt in 10:
		await get_tree().create_timer(0.1).timeout
		btn = _button(build_grid, label)
		if btn != null: break
	if btn == null:
		events.append({"action":"build_command_missing","kind":kind,"label":label,"wood":game.get("wood"),"stone":game.get("stone"),"living_villagers":_living_villagers().size(),"build_grid_visible":build_grid.visible if build_grid is Control else false,"selection_count":game.get("selected").size()})
		return
	await _click_control(btn)
	var chosen: Node3D
	var attempts: Array[Dictionary] = []
	for p in candidates:
		var previous_ids := _building_ids(kind)
		await _click_world(game, p + Vector3(0, 2.0, 0), "%s placement" % label)
		await get_tree().create_timer(0.25).timeout
		chosen = _new_building(kind, previous_ids)
		attempts.append({"position":_v3(p),"placed":chosen != null,"remaining_wood":game.get("wood"),"remaining_stone":game.get("stone"),"message":_hud_message(hud)})
		if chosen != null: break
	if chosen == null:
		events.append({"action":"building_placement_failed","kind":kind,"label":label,"attempts":attempts,"camera":_v3(game.get("cam_pivot").position)})
		return
	match kind:
		Catalog.HOUSE: house = chosen
		Catalog.FARM:
			if not _farm_is_live(farm): farm = chosen
			elif not _farm_is_live(farm2): farm2 = chosen
			else: farm2 = chosen
		Catalog.BARRACKS: barracks = chosen
		Catalog.ARROW_TOWER:
			if not _farm_is_live(tower): tower = chosen
			elif not _farm_is_live(tower2): tower2 = chosen
			elif not _farm_is_live(tower3): tower3 = chosen
			elif not _farm_is_live(tower4): tower4 = chosen
			else: tower5 = chosen
	events.append({"action":"building_placed","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"kind":kind,"label":label,"position":_v3(chosen.global_position),"attempts":attempts,"selected_villagers":game.get("selected").size(),"resources_after_payment":_training_resource_snapshot(game),"accepted":true})
	var build_started_msec := Time.get_ticks_msec()
	while is_instance_valid(chosen) and not bool(chosen.get("is_complete")) and Time.get_ticks_msec() - build_started_msec < 45000 and not done:
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(chosen) or not bool(chosen.get("is_complete")):
		events.append({"action":"building_build_timeout","kind":kind,"label":label,"progress":chosen.get("build_progress") if is_instance_valid(chosen) else -1,"builder_count":int(game.get("selected").size()),"game_time":float(game.get("_game_time"))})

func _wait_for_build_funds(game: Node, kind: int, label: String) -> bool:
	var definition: Dictionary = Catalog.get_def(kind)
	if definition.is_empty():
		events.append({"action":"building_budget_precheck_failed","label":label,"kind":kind,"reason":"catalog definition missing"})
		return false
	var wood_cost := int(definition.get("cost_wood", 0))
	var stone_cost := int(definition.get("cost_stone", 0))
	var food_cost := int(definition.get("cost_meat", 0))
	var start_time := float(game.get("_game_time"))
	var reported_wait := false
	while not done and float(game.get("_game_time")) - start_time < 240.0:
		var wood_now := int(game.get("wood"))
		var stone_now := int(game.get("stone"))
		var food_now := int(game.get("meat"))
		if wood_now >= wood_cost and stone_now >= stone_cost and food_now >= food_cost:
			events.append({"action":"building_budget_precheck_passed","kind":kind,"label":label,"wood":wood_now,"wood_cost":wood_cost,"stone":stone_now,"stone_cost":stone_cost,"food":food_now,"food_cost":food_cost,"game_time":float(game.get("_game_time"))})
			return true
		if not reported_wait:
			reported_wait = true
			events.append({"action":"building_waiting_for_actual_budget","kind":kind,"label":label,"wood":wood_now,"wood_cost":wood_cost,"stone":stone_now,"stone_cost":stone_cost,"food":food_now,"food_cost":food_cost,"reason":"remain in natural gather-and-wait stage; do not test candidate positions until full cost is available"})
		await get_tree().create_timer(0.25).timeout
	events.append({"action":"building_budget_wait_timeout","kind":kind,"label":label,"wood":int(game.get("wood")),"wood_cost":wood_cost,"stone":int(game.get("stone")),"stone_cost":stone_cost,"food":int(game.get("meat")),"food_cost":food_cost,"game_time":float(game.get("_game_time"))})
	return false

func _build_at_headless(game: Node, kind: int, label: String, candidates: Array[Vector3]) -> void:
	var definition: Dictionary = Catalog.get_def(kind)
	var wood_cost := int(definition.get("cost_wood", 0))
	var stone_cost := int(definition.get("cost_stone", 0))
	var food_cost := int(definition.get("cost_meat", 0))
	if int(game.get("wood")) < wood_cost or int(game.get("stone")) < stone_cost or int(game.get("meat")) < food_cost:
		events.append({"action":"building_placement_skipped_unaffordable","kind":kind,"label":label,"wood":int(game.get("wood")),"wood_cost":wood_cost,"stone":int(game.get("stone")),"stone_cost":stone_cost,"food":int(game.get("meat")),"food_cost":food_cost,"reason":"do not classify insufficient funds as rejected building sites"})
		return
	var workers := _control_group_units(game, 2)
	if workers.is_empty(): workers = _living_villagers()
	if workers.is_empty():
		events.append({"action":"player_build_command_rejected","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"kind":kind,"label":label,"accepted":false,"failure":"no_living_builder","resources":_training_resource_snapshot(game)})
		return
	var builder: Node3D = workers[0] as Node3D
	workers = [builder]
	_select_units(game, workers)
	game.call("_on_build_kind", kind)
	var chosen: Node3D
	var attempts: Array[Dictionary] = []
	for p in candidates:
		var previous_ids := _building_ids(kind)
		var valid := bool(game.call("_placement_valid_at", p))
		if valid:
			game.call("_try_place", p)
		chosen = _new_building(kind, previous_ids)
		attempts.append({"position":_v3(p),"placement_valid":valid,"placed":chosen != null,"remaining_wood":game.get("wood"),"remaining_stone":game.get("stone")})
		if chosen != null: break
	if chosen == null:
		events.append({"action":"building_placement_failed","kind":kind,"label":label,"attempts":attempts,"route":"headless logical production placement methods"})
		return
	match kind:
		Catalog.HOUSE: house = chosen
		Catalog.FARM:
			if not _farm_is_live(farm): farm = chosen
			elif not _farm_is_live(farm2): farm2 = chosen
			else: farm2 = chosen
		Catalog.BARRACKS: barracks = chosen
		Catalog.ARROW_TOWER:
			if not _farm_is_live(tower): tower = chosen
			elif not _farm_is_live(tower2): tower2 = chosen
			elif not _farm_is_live(tower3): tower3 = chosen
			elif not _farm_is_live(tower4): tower4 = chosen
			else: tower5 = chosen
	events.append({"action":"building_placed","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"kind":kind,"label":label,"position":_v3(chosen.global_position),"attempts":attempts,"selected_villagers":workers.size(),"builder":_villager_ids(workers),"resources_after_payment":_training_resource_snapshot(game),"accepted":true,"route":"Main build selection + paid Main._try_place; one worker builds while other roles continue"})
	var build_started_msec := Time.get_ticks_msec()
	while is_instance_valid(chosen) and not bool(chosen.get("is_complete")) and Time.get_ticks_msec() - build_started_msec < 45000 and not done:
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(chosen) or not bool(chosen.get("is_complete")):
		events.append({"action":"building_build_timeout","kind":kind,"label":label,"progress":chosen.get("build_progress") if is_instance_valid(chosen) else -1,"builder":_villager_ids([builder]),"game_time":float(game.get("_game_time"))})

func _gather_farm_food(game: Node) -> void:
	var food_source: Node3D = farm2 if _farm_is_live(farm2) and int(farm2.get("meat_stock")) > 0 else farm
	if DisplayServer.get_name() == "headless":
		if not _farm_is_live(food_source):
			events.append({"action":"food_assignment_deferred","reason":"no_completed_farm_yet","wood":game.get("wood"),"meat":game.get("meat")})
			return
		_split_material_worker_groups(game)
		var food_workers := _control_group_units(game, 3)
		var wood_workers := _control_group_units(game, 2)
		var stone_workers := _control_group_units(game, 4)
		_issue_gather_order(game, food_workers, food_source, "keep two workers on live farm food")
		var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
		var stone_node := _nearest_resource(ResourceNode3D.Kind.STONE)
		if wood_node != null: _issue_gather_order(game, wood_workers, wood_node, "keep wood income active")
		if stone_node != null: _issue_gather_order(game, stone_workers, stone_node, "keep tower stone income active")
		events.append({"action":"opening_workforce_kept_active_after_farm","food_workers":_villager_ids(food_workers),"wood_workers":_villager_ids(wood_workers),"stone_workers":_villager_ids(stone_workers),"farm_stock":food_source.get("meat_stock"),"route":"Main gather mode + pending map command"})
		return
	await _ensure_villager_selection(game)
	await _send_key(KEY_G)
	if _farm_is_live(food_source):
		await _click_world(game, food_source.global_position + Vector3(0, 2, 0), "farm food supply")
		var food_start := int(game.get("meat"))
		var food_started_at := elapsed
		while int(game.get("meat")) < 300 and elapsed < food_started_at + 60.0 and not done:
			await get_tree().create_timer(0.5).timeout
		events.append({"action":"farm_food_gathered_before_stone","farm":food_source.name,"selected":game.get("selected").size(),"meat_start":food_start,"meat_after":game.get("meat"),"food_target":300,"elapsed_gathering":elapsed-food_started_at,"stock":food_source.get("meat_stock")})
		if int(game.get("meat")) < 300:
			_finish(false, "farm_food_target_not_reached_before_stone")
			return
		# Keep one villager on the protected inner farm while the remaining four
		# return to wood and stone gathering for later rebuilding and reinforcements.
		await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "wood reserve after first farm harvest")
		await _send_key(KEY_3)
		await _send_key(KEY_G)
		var safe_farm := _safest_live_farm()
		if safe_farm != null:
			await _click_world(game, safe_farm.global_position + Vector3(0, 2.0, 0), "keep one villager harvesting the protected farm")
			events.append({"action":"one_worker_left_on_food","worker_group":3,"farm":safe_farm.name,"food":game.get("meat")})

func _issue_gather_order(game: Node, workers: Array, target: Node3D, reason: String) -> bool:
	return _issue_gather_order_authorized(game, workers, target, reason, "campaign_controller", "")

func _issue_gather_order_authorized(game: Node, requested_workers: Array, target: Node3D, reason: String, issuer: String, authorized_evacuated_runtime_id: String) -> bool:
	var requested_ids := _villager_ids(requested_workers)
	var workers: Array = []
	var blocked_ids: Array[String] = []
	for worker in requested_workers:
		if not is_instance_valid(worker):
			continue
		var runtime_id := str(worker.get_instance_id())
		if evacuated_worker_ids.has(runtime_id) and runtime_id != authorized_evacuated_runtime_id:
			blocked_ids.append(runtime_id + ":" + str(worker.name))
			continue
		workers.append(worker)
	if workers.is_empty():
		events.append({"action":"gather_order_blocked_by_evacuation","game_time":float(game.get("_game_time")),"reason":reason,"issuer":issuer,"requested_workers":requested_ids,"blocked_workers":blocked_ids,"accepted":false})
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		events.append({"action":"gather_order_rejected_invalid_target","game_time":float(game.get("_game_time")),"reason":reason,"issuer":issuer,"requested_workers":requested_ids,"eligible_workers":_villager_ids(workers),"target_valid":is_instance_valid(target),"target_in_tree":is_instance_valid(target) and target.is_inside_tree(),"accepted":false})
		return false
	campaign_command_reason = "gather order: " + reason
	_select_units(game, workers)
	game.call("_on_cmd_gather")
	game.call("_route_pending_command", target.global_position)
	var accepted_count := 0
	for worker in workers:
		if is_instance_valid(worker) and worker.get("gather_target") == target:
			accepted_count += 1
		elif is_instance_valid(worker) and target.has_method("res_key") and str(worker.get("resume_key")) == str(target.call("res_key")):
			accepted_count += 1
	var accepted := accepted_count == workers.size()
	var resource_stock := 0
	if target.has_method("res_key"):
		var raw_amount: Variant = target.get("amount")
		resource_stock = int(raw_amount) if raw_amount != null else 0
	else:
		var raw_meat_stock: Variant = target.get("meat_stock")
		resource_stock = int(raw_meat_stock) if raw_meat_stock != null else 0
	events.append({"action":"main_gather_order","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":reason,"issuer":issuer,"requested_workers":requested_ids,"workers":_villager_ids(workers),"target":str(target.name),"target_key":str(target.call("res_key")) if target.has_method("res_key") else "food","resource_stock":resource_stock,"accepted":accepted,"evacuation_authorization_runtime_id":authorized_evacuated_runtime_id,"route":"Main._on_cmd_gather + Main._route_pending_command"})
	return accepted

func _villagers_gathering_farm() -> bool:
	for villager in _living_villagers():
		var target = villager.get("gather_target")
		if target != null and is_instance_valid(target) and target.is_inside_tree() and target.is_in_group("farms") and target.get("is_complete") == true and target.get("is_meat_source") == true and int(target.get("meat_stock")) > 0:
			return true
	return false

func _villagers_gathering_wood() -> bool:
	for villager in _living_villagers():
		var target = villager.get("gather_target")
		if target != null and is_instance_valid(target) and target.is_inside_tree() and target.has_method("res_key") and str(target.call("res_key")) == "wood":
			return true
	return false

func _food_service_needed(game: Node) -> bool:
	var farms := _live_player_farms()
	if farms.is_empty(): return true
	var stock_total := 0
	for candidate in farms: stock_total += int(candidate.get("meat_stock"))
	return stock_total <= 0 or (int(game.get("meat")) < 180 and not _villagers_gathering_farm())

func _farm_is_live(candidate: Variant) -> bool:
	if not is_instance_valid(candidate): return false
	var node := candidate as Node
	return node != null and node.is_inside_tree() and node.get("alive") == true

func _farm_build_retry_ready(game: Node) -> bool:
	return float(game.get("_game_time")) - last_farm_placement_attempt_game_time >= 25.0

func _live_player_houses() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(candidate) or not candidate.is_inside_tree(): continue
		if int(candidate.get("kind")) == Catalog.HOUSE and str(candidate.get("team")) == "player" and bool(candidate.get("alive")):
			result.append(candidate as Node3D)
	return result

func _backup_house_candidates(game: Node) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	var hubs: Array[Vector3] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not building.is_inside_tree() or str(building.get("team")) != "player" or not bool(building.get("alive")):
			continue
		var definition: Dictionary = Catalog.get_def(int(building.get("kind")))
		if bool(definition.get("is_hub", false)):
			hubs.append((building as Node3D).global_position)
	for center in hubs:
		for offset in [Vector3(-12, 0, 8), Vector3(12, 0, 8), Vector3(-12, 0, -8), Vector3(12, 0, -8), Vector3(0, 0, 14), Vector3(0, 0, -14), Vector3(14, 0, 0), Vector3(-14, 0, 0), Vector3(-8, 0, 12), Vector3(8, 0, 12), Vector3(-8, 0, -12), Vector3(8, 0, -12)]:
			var candidate: Vector3 = center + offset
			if bool(game.call("_placement_valid_at", candidate)):
				candidates.append(candidate)
	if candidates.is_empty():
		candidates = [Vector3(0, 0, 16), Vector3(10, 0, 10), Vector3(-10, 0, 12), Vector3(8, 0, 16)]
	return candidates

func _backup_house_cooldown_ready(game: Node) -> bool:
	var house_cost := int(Catalog.get_def(Catalog.HOUSE).get("cost_wood", 50))
	return not busy and not backup_house_attempt_in_progress and float(game.get("_game_time")) - last_backup_house_attempt_game_time >= 25.0 and not _living_villagers().is_empty() and int(game.get("wood")) >= house_cost

func _reserve_backup_house_attempt(game: Node) -> void:
	last_backup_house_attempt_game_time = float(game.get("_game_time"))
	backup_house_attempt_in_progress = true

func _live_player_farms() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("farms"):
		if _farm_is_live(candidate) and candidate.get("is_complete") == true and str(candidate.get("team")) == "player":
			result.append(candidate as Node3D)
	return result

func _extra_tower_budget_ready(game: Node) -> bool:
	# Arrow tower 100/50 is permitted only when payment leaves 75 for a farm
	# recovery and 20/60 for one soldier; a live farm is required first.
	return not _live_player_farms().is_empty() and int(game.get("wood")) >= 195 and int(game.get("stone")) >= 50 and int(game.get("meat")) >= 60

func _can_build_optional_tower(game: Node) -> bool:
	# Do not tie up the only builder or expose an unfinished tower during combat.
	return not bool(game.get("_horde_active")) and _living_zombies().is_empty() and float(game.get("_game_time")) + 30.0 < float(game.get("_horde_next_at"))

func _player_tc() -> Node3D:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and bool(building.get("alive")) and str(building.get("team")) == "player" and int(building.get("kind")) == Catalog.TOWN_CENTER:
			return building as Node3D
	return null

func _safest_live_farm() -> Node3D:
	var best: Node3D = null
	var best_stock := -1
	var best_distance := INF
	for candidate in _live_player_farms():
		var stock := int(candidate.get("meat_stock"))
		var distance := candidate.global_position.length_squared()
		if stock > best_stock or (stock == best_stock and distance < best_distance):
			best = candidate
			best_stock = stock
			best_distance = distance
	return best

func _establish_worker_groups(game: Node) -> bool:
	await _ensure_villager_selection(game)
	var workers := _living_villagers()
	var all_ids := _villager_ids(workers)
	if workers.size() < 2:
		events.append({"action":"worker_group_partition_failed","reason":"fewer_than_two_living_workers","all_villagers":all_ids})
		return false
	if DisplayServer.get_name() == "headless":
		var food_workers: Array = []
		var lumber_workers: Array = workers.slice(0, 4)
		var stone_workers: Array = workers.slice(4)
		_select_units(game, food_workers)
		game.call("_assign_control_group", 3)
		_select_units(game, lumber_workers)
		game.call("_assign_control_group", 2)
		if not stone_workers.is_empty():
			_select_units(game, stone_workers)
			game.call("_assign_control_group", 4)
		var verified_food := _control_group_villager_ids(game.get("_control_groups"), 3)
		var verified_lumber := _control_group_villager_ids(game.get("_control_groups"), 2)
		var verified_stone := _control_group_villager_ids(game.get("_control_groups"), 4)
		_select_units(game, workers)
		var direct_ok := verified_food.is_empty() and verified_lumber.size() == 4 and verified_stone.size() == 1 and verified_food.size() + verified_lumber.size() + verified_stone.size() == workers.size()
		last_worker_group_living_count = workers.size()
		events.append({"action":"opening_worker_partition_verified","success":direct_ok,"plan":"4 wood / 1 stone; food group empty until first farm completes","all_living_villagers":all_ids,"food_group_ids":verified_food,"lumber_group_ids":verified_lumber,"stone_group_ids":verified_stone,"intersection":[],"union_ids":all_ids,"route":"Main control-group selection"})
		return direct_ok

	var farmer: Node3D = workers[0] as Node3D
	await _click_world(game, farmer.global_position + Vector3(0, 0.9, 0), "select dedicated food villager")
	var expected_food_ids := _villager_ids([farmer])
	var selected_ids := _villager_ids(game.get("selected"))
	if selected_ids != expected_food_ids:
		events.append({"action":"worker_group_partition_failed","reason":"single_worker_viewport_click_missed_or_multiselected","expected_food_ids":expected_food_ids,"selected_ids":selected_ids,"all_villagers":all_ids,"input":_last_click.duplicate(true)})
		return false
	await _send_key(KEY_3, 0, true)
	await _send_key(KEY_3)
	var control_groups: Array = game.get("_control_groups")
	var food_group_ids := _control_group_villager_ids(control_groups, 3)
	await _send_key(KEY_3)
	var recalled_food_ids := _villager_ids(game.get("selected"))
	if food_group_ids != expected_food_ids or recalled_food_ids != expected_food_ids:
		events.append({"action":"worker_group_partition_failed","reason":"food_group_assignment_or_recall_mismatch","expected_food_ids":expected_food_ids,"food_group_ids":food_group_ids,"recalled_food_ids":recalled_food_ids,"all_villagers":all_ids})
		return false
	await _send_key(KEY_F3)
	var selected: Array = game.get("selected")
	var expected_lumber_ids := all_ids.filter(func(uid): return not expected_food_ids.has(uid))
	var ordinary_shift_click_ok := true
	if farmer in selected:
		await _shift_click_world(game, farmer.global_position + Vector3(0, 0.9, 0), "remove dedicated farmer from lumber group")
	selected = game.get("selected")
	var selected_after_shift_ids := _villager_ids(selected)
	if selected_after_shift_ids != expected_lumber_ids:
		ordinary_shift_click_ok = false
		# The isolated viewport click does not reliably preserve Shift. For this
		# diagnostic only, populate the selection through the game's own selection
		# handlers, then verify the resulting saved group. This does not validate
		# ordinary mouse Shift-selection in the live game.
		game.call("_clear_selection")
		for worker in workers:
			if worker != farmer:
				game.call("_add_to_selection", worker)
		game.call("_refresh_selection_hud")
		selected = game.get("selected")
		events.append({"action":"isolated_selection_handler_fallback","worker_id":str(farmer.get_instance_id()),"worker_name":farmer.name,"selection_ids":_villager_ids(selected),"ordinary_shift_click_verified":false,"shift_click_input":_last_shift_click.duplicate(true),"scope":"isolated worker-group probe only"})
	var lumber_selection_ids := _villager_ids(selected)
	if lumber_selection_ids != expected_lumber_ids:
		events.append({"action":"worker_group_partition_failed","reason":"lumber_selection_not_exact","expected_lumber_ids":expected_lumber_ids,"lumber_selection_ids":lumber_selection_ids,"all_villagers":all_ids})
		return false
	await _send_key(KEY_2, 0, true)
	await _send_key(KEY_2)
	control_groups = game.get("_control_groups")
	var lumber_group_ids := _control_group_villager_ids(control_groups, 2)
	await _send_key(KEY_2)
	var recalled_lumber_ids := _villager_ids(game.get("selected"))
	var intersection: Array = food_group_ids.filter(func(uid): return lumber_group_ids.has(uid))
	var union_ids: Array = food_group_ids.duplicate()
	for uid in lumber_group_ids:
		if not union_ids.has(uid): union_ids.append(uid)
	union_ids.sort()
	var partition_ok := food_group_ids == expected_food_ids and lumber_group_ids == expected_lumber_ids and recalled_food_ids == expected_food_ids and recalled_lumber_ids == expected_lumber_ids and intersection.is_empty() and union_ids == all_ids
	events.append({"action":"worker_group_partition_verified" if partition_ok else "worker_group_partition_failed","success":partition_ok,"all_living_villagers":all_ids,"food_group_ids":food_group_ids,"food_recalled_ids":recalled_food_ids,"lumber_group_ids":lumber_group_ids,"lumber_recalled_ids":recalled_lumber_ids,"intersection":intersection,"union_ids":union_ids,"ordinary_shift_click_verified":ordinary_shift_click_ok,"selection_fallback_scope":"isolated worker-group probe only" if not ordinary_shift_click_ok else "none"})
	return partition_ok

func _split_material_worker_groups(game: Node, keep_stone_worker: bool = true) -> void:
	var living := _living_villagers()
	if living.size() < 3: return
	var food_workers: Array = []
	var lumber_workers: Array = []
	var stone_workers: Array = []
	for worker in _control_group_units(game, 4):
		if living.has(worker): stone_workers.append(worker)
	if keep_stone_worker and stone_workers.is_empty(): stone_workers.append(living.back())
	for worker in living:
		if stone_workers.has(worker): continue
		if food_workers.size() < 2: food_workers.append(worker)
		else: lumber_workers.append(worker)
	var overlap_before := _material_group_overlap(game)
	_clear_material_control_groups(game)
	_select_units(game, food_workers)
	game.call("_assign_control_group", 3)
	_select_units(game, lumber_workers)
	game.call("_assign_control_group", 2)
	_select_units(game, stone_workers)
	game.call("_assign_control_group", 4)
	_select_units(game, living)
	last_worker_group_living_count = living.size()
	events.append({"action":"post_farm_worker_groups_split","food_group":_villager_ids(food_workers),"wood_group":_villager_ids(lumber_workers),"stone_group":_villager_ids(stone_workers),"keep_stone_worker":keep_stone_worker,"overlap_before":overlap_before,"overlap_after":_material_group_overlap(game),"route":"clear groups 2/3/4, then assign a disjoint Main control-group partition; gather orders remain independent"})

func _rebalance_live_worker_groups(game: Node, living: Array) -> void:
	var food_workers := _control_group_units(game, 3)
	if food_workers.is_empty(): food_workers = [living[0]]
	var resource_workers: Array = []
	for worker in living:
		if not food_workers.has(worker): resource_workers.append(worker)
	var wood_workers: Array = []
	var stone_workers: Array = []
	if resource_workers.size() >= 2:
		var wood_count := int(ceil(float(resource_workers.size()) * 0.5))
		wood_workers = resource_workers.slice(0, wood_count)
		stone_workers = resource_workers.slice(wood_count)
	else:
		wood_workers = resource_workers
	_clear_material_control_groups(game)
	_select_units(game, food_workers)
	game.call("_assign_control_group", 3)
	_select_units(game, wood_workers)
	game.call("_assign_control_group", 2)
	_select_units(game, stone_workers)
	game.call("_assign_control_group", 4)
	_select_units(game, living)
	last_worker_group_living_count = living.size()
	events.append({"action":"worker_groups_rebalanced_after_losses","living_villagers":_villager_ids(living),"food_group":_villager_ids(food_workers),"wood_group":_villager_ids(wood_workers),"stone_group":_villager_ids(stone_workers),"route":"headless logical production selection/group methods"})
	var food_source := _safest_live_farm()
	if not food_workers.is_empty() and is_instance_valid(food_source) and int(food_source.get("meat_stock")) > 0 and not _villagers_gathering_farm():
		_issue_gather_order(game, food_workers, food_source, "restore food gathering for rejoined workers")
	var army_deficit := bool(game.get("_horde_active")) and _player_military().size() + _queued_player_soldiers() < _army_target_for_wave(game)
	var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
	if not wood_workers.is_empty() and wood_node != null and not _villagers_gathering_wood() and (int(game.get("wood")) < 75 or army_deficit):
		_issue_gather_order(game, wood_workers, wood_node, "restore wood gathering for reinforcement budget")

func _clear_material_control_groups(game: Node) -> void:
	for group_index in [2, 3, 4]:
		_select_units(game, [])
		game.call("_assign_control_group", group_index)

func _material_group_overlap(game: Node) -> Array[String]:
	var memberships: Dictionary = {}
	for group_index in [2, 3, 4]:
		for worker in _control_group_units(game, group_index):
			var worker_id := str(worker.get_instance_id())
			memberships[worker_id] = int(memberships.get(worker_id, 0)) + 1
	var overlapping: Array[String] = []
	for worker_id in memberships:
		if int(memberships[worker_id]) > 1: overlapping.append(str(worker_id))
	overlapping.sort()
	return overlapping

func _villager_ids(units: Array) -> Array[String]:
	var ids: Array[String] = []
	for unit in units:
		if is_instance_valid(unit) and unit.is_inside_tree() and unit.is_in_group("villagers") and str(unit.get("team")) == "player" and bool(unit.get("alive")) and float(unit.get("hp")) > 0.0:
			ids.append("%s:%s" % [str(unit.get_instance_id()), str(unit.name)])
	ids.sort()
	return ids

func _control_group_villager_ids(groups: Array, group_index: int) -> Array[String]:
	if group_index < 0 or group_index >= groups.size(): return []
	var group := groups[group_index] as Array
	return _villager_ids(group)

func _run_worker_economy_probe(game: Node) -> void:
	phase = "worker_economy_probe"
	var groups_ok: bool = await _establish_worker_groups(game)
	if not groups_ok:
		_finish(false, "worker_group_partition_failed")
		return
	await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "worker probe lumber group wood order")
	var initial_lumber_selected_ids := _villager_ids(game.get("selected"))
	var verified_lumber_ids := _control_group_villager_ids(game.get("_control_groups"), 2)
	if initial_lumber_selected_ids != verified_lumber_ids:
		events.append({"action":"worker_group_action_mismatch","group":2,"expected_ids":verified_lumber_ids,"selected_ids":initial_lumber_selected_ids,"stage":"initial_wood_delivery"})
		_finish(false, "initial_lumber_group_recall_did_not_match")
		return
	var wood_start := int(game.get("wood"))
	var wood_deadline := elapsed + 150.0
	while int(game.get("wood")) < wood_start + 75 and elapsed < wood_deadline and not done:
		await get_tree().create_timer(0.5).timeout
	if int(game.get("wood")) < wood_start + 75:
		events.append({"action":"worker_economy_delivery_failed","resource":"wood","before":wood_start,"after":game.get("wood"),"required_increase":75})
		_finish(false, "lumber_group_did_not_deliver_build_cost")
		return
	await _build_at(game, Catalog.FARM, "农田", [Vector3(12, 0, 0), Vector3(10, 0, 0), Vector3(12, 0, 6)])
	if not _farm_is_live(farm):
		_finish(false, "worker_probe_farm_build_failed")
		return
	var build_deadline := elapsed + 45.0
	while is_instance_valid(farm) and not bool(farm.get("is_complete")) and elapsed < build_deadline:
		await get_tree().create_timer(0.5).timeout
	if not _farm_is_live(farm) or not bool(farm.get("is_complete")):
		_finish(false, "worker_probe_farm_did_not_complete")
		return
	var farm_stock_before := int(farm.get("meat_stock"))
	var food_before := int(game.get("meat"))
	var wood_before := int(game.get("wood"))
	await _send_key(KEY_3)
	var selected_food_ids := _villager_ids(game.get("selected"))
	var expected_food_ids := _control_group_villager_ids(game.get("_control_groups"), 3)
	if selected_food_ids != expected_food_ids:
		events.append({"action":"worker_group_action_mismatch","group":3,"expected_ids":expected_food_ids,"selected_ids":selected_food_ids})
		_finish(false, "food_group_recall_did_not_match_verified_group")
		return
	await _send_key(KEY_G)
	await _click_world(game, farm.global_position, "worker probe food group farm order")
	var food_click := _last_click.duplicate(true)
	var food_group: Array = (game.get("_control_groups") as Array)[3]
	var food_farmer: Node3D = food_group[0] as Node3D
	var click_position: Array = food_click.get("position", [])
	var click_world_hit: Variant = game.call("_ray_ground", Vector2(float(click_position[0]), float(click_position[1]))) if click_position.size() >= 2 else null
	var food_command_state := {"farmer_id":str(food_farmer.get_instance_id()),"farmer_name":str(food_farmer.name),"state":str(food_farmer.get("state")),"gather_target_id":str((food_farmer.get("gather_target") as Node).get_instance_id()) if is_instance_valid(food_farmer.get("gather_target")) else "","farm_id":str(farm.get_instance_id()),"farm_path":str(farm.get_path()),"is_resource":farm.is_in_group("resources"),"click_world_hit":_v3(click_world_hit) if click_world_hit is Vector3 else []}
	food_command_state["gather_target_matches_farm"] = food_command_state["gather_target_id"] == food_command_state["farm_id"]
	if not bool(food_command_state["gather_target_matches_farm"]):
		events.append({"action":"food_gather_command_missed_farm","command_state":food_command_state,"input":food_click})
		_finish(false, "food_gather_click_did_not_target_farm")
		return
	await _order_nearest_resource(game, ResourceNode3D.Kind.WOOD, "worker probe lumber group continue wood order")
	var lumber_selected_ids := _villager_ids(game.get("selected"))
	var expected_lumber_ids := _control_group_villager_ids(game.get("_control_groups"), 2)
	if lumber_selected_ids != expected_lumber_ids:
		events.append({"action":"worker_group_action_mismatch","group":2,"expected_ids":expected_lumber_ids,"selected_ids":lumber_selected_ids})
		_finish(false, "lumber_group_recall_did_not_match_verified_group")
		return
	var delivery_deadline := elapsed + 90.0
	while elapsed < delivery_deadline and not done:
		if int(game.get("meat")) >= food_before + 20 and int(game.get("wood")) >= wood_before + 20:
			var delivery := {"food_before":food_before,"food_after":game.get("meat"),"farm_stock_before":farm_stock_before,"farm_stock_after":farm.get("meat_stock"),"wood_before":wood_before,"wood_after":game.get("wood"),"food_group_ids":expected_food_ids,"lumber_group_ids":expected_lumber_ids,"farm_click":food_click,"food_command_state":food_command_state,"wood_selected_ids":lumber_selected_ids,"success":true}
			events.append({"action":"worker_economy_deliveries_verified","delivery":delivery})
			_finish(true, "exclusive_worker_groups_delivered_food_and_wood")
			return
		await get_tree().create_timer(0.5).timeout
	events.append({"action":"worker_economy_delivery_failed","food_before":food_before,"food_after":game.get("meat"),"farm_stock_before":farm_stock_before,"farm_stock_after":farm.get("meat_stock") if is_instance_valid(farm) else -1,"wood_before":wood_before,"wood_after":game.get("wood"),"food_group_ids":expected_food_ids,"lumber_group_ids":expected_lumber_ids,"farm_click":food_click,"food_command_state":food_command_state})
	_finish(false, "exclusive_worker_groups_did_not_deliver_both_resources")

func _maintain_food_supply(game: Node) -> void:
	last_food_order_at = elapsed
	if _living_villagers().is_empty():
		events.append({"action":"food_service_unavailable","reason":"no_living_villagers","meat":game.get("meat"),"wood":game.get("wood")})
		return
	var farms := _live_player_farms()
	if farms.is_empty() and int(game.get("wood")) >= 75:
		await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -4), Vector3(12, 0, 2), Vector3(7, 0, -8)])
		farms = _live_player_farms()
	if farms.is_empty():
		events.append({"action":"food_rebuild_unavailable","meat":game.get("meat"),"wood":game.get("wood"),"reason":"no_living_farm_or_75_wood"})
		return
	var stock_total := 0
	for candidate in farms:
		stock_total += int(candidate.get("meat_stock"))
	if stock_total <= 0:
		var reseeded := await _reseed_dry_farm(game)
		if is_instance_valid(reseeded):
			farms = _live_player_farms()
			stock_total = 0
			for candidate in farms: stock_total += int(candidate.get("meat_stock"))
	if stock_total <= 0:
		if int(game.get("wood")) >= 75 and farms.size() < 2:
			await _build_at(game, Catalog.FARM, "农田", [Vector3(10, 0, -4), Vector3(12, 0, 2), Vector3(7, 0, -8)])
			farms = _live_player_farms()
		if farms.is_empty() or int(game.get("wood")) < 25:
			events.append({"action":"food_rebuild_unavailable","meat":game.get("meat"),"wood":game.get("wood"),"living_farms":farms.size(),"reason":"dry_farms_and_rebuild_unaffordable"})
			return
	if _villagers_gathering_farm():
		return
	await _assign_workers_to_food(game)

func _assign_workers_to_food(game: Node) -> void:
	var safe_workers := _living_villagers().filter(func(worker: Node3D) -> bool: return not evacuated_worker_ids.has(str(worker.get_instance_id())))
	if safe_workers.is_empty():
		events.append({"action":"food_assignment_skipped","reason":"no_living_villagers"})
		return
	var best_farm: Node3D
	var best_stock := -1
	for candidate in _live_player_farms():
		if int(candidate.get("meat_stock")) > best_stock:
			best_stock = int(candidate.get("meat_stock"))
			best_farm = candidate
	if best_stock <= 0:
		best_farm = await _reseed_dry_farm(game)
		best_stock = int(best_farm.get("meat_stock")) if is_instance_valid(best_farm) else 0
	if best_farm == null or best_stock <= 0:
		events.append({"action":"reinforcement_food_unavailable","meat":game.get("meat"),"farms":[farm.get("meat_stock") if is_instance_valid(farm) else 0,farm2.get("meat_stock") if is_instance_valid(farm2) else 0]})
		return
	if DisplayServer.get_name() == "headless":
		var food_workers := _control_group_units(game, 3)
		food_workers = food_workers.filter(func(worker: Node3D) -> bool: return not evacuated_worker_ids.has(str(worker.get_instance_id())))
		if food_workers.is_empty() and not safe_workers.is_empty():
			food_workers = [safe_workers[0]]
			_select_units(game, food_workers)
			game.call("_assign_control_group", 3)
		_issue_gather_order(game, food_workers, best_farm, "fresh food alert or food reserve needs workers")
		events.append({"action":"villagers_reassigned_to_food_for_reinforcements","farm":best_farm.name,"selected":food_workers.size(),"food_worker_group":_villager_ids(food_workers),"meat":game.get("meat"),"farm_stock":best_farm.get("meat_stock"),"route":"Main gather mode + pending map command"})
		return
		
	await _send_key(KEY_3)
	await _send_key(KEY_G)
	await _click_world(game, best_farm.global_position + Vector3(0, 2.0, 0), "reassign villagers to food for reinforcements")
	events.append({"action":"villagers_reassigned_to_food_for_reinforcements","farm":best_farm.name,"selected":game.get("selected").size(),"meat":game.get("meat"),"farm_stock":best_farm.get("meat_stock")})

func _reseed_dry_farm(game: Node) -> Node3D:
	if int(game.get("wood")) < 25: return null
	for candidate in _live_player_farms():
		if not bool(candidate.get("is_arid")): continue
		var wood_before := int(game.get("wood"))
		if DisplayServer.get_name() == "headless":
			game.call("_refresh_operational_alerts")
			var hud: Node = game.get("hud")
			var locator := _alert_button_for_target(hud, candidate)
			if locator == null:
				events.append({"action":"farm_alert_locator_unavailable","farm":candidate.name,"wood":wood_before})
				continue
			locator.pressed.emit()
			await get_tree().process_frame
			var selected_by_alert: bool = candidate in game.get("selected")
			var reseed_key := InputEventKey.new()
			reseed_key.pressed = true
			reseed_key.keycode = KEY_R
			game.call("_unhandled_input", reseed_key)
			var headless_ok := selected_by_alert and int(candidate.get("meat_stock")) > 0 and int(game.get("wood")) == wood_before - 25
			events.append({"action":"farm_reseeded_through_operational_alert_R","farm":candidate.name,"alert_locator_selected_target":selected_by_alert,"wood_before":wood_before,"wood_after":game.get("wood"),"wood_cost":25,"stock_after":candidate.get("meat_stock"),"verified":headless_ok,"route":"operational alert Button pressed signal then production R hotkey"})
			if headless_ok: return candidate
			continue
		await _click_world(game, candidate.global_position + Vector3(0, 2.0, 0), "select dry farm for reseeding")
		await get_tree().create_timer(0.15).timeout
		var hud: Node = game.get("hud")
		var buttons: Dictionary = hud.get("_cmd_btns") if hud != null else {}
		var reseed_button := buttons.get("reseed") as Button
		if reseed_button == null or not is_instance_valid(reseed_button) or not reseed_button.is_inside_tree():
			events.append({"action":"farm_reseed_skipped","farm":candidate.name,"reason":"reseed_control_unavailable","wood":wood_before})
			continue
		await _click_control(reseed_button)
		await get_tree().create_timer(0.15).timeout
		if not _game_still_active(game): return null
		if not is_instance_valid(candidate) or not candidate.is_inside_tree():
			events.append({"action":"farm_reseed_skipped","farm_name":candidate.name if is_instance_valid(candidate) else "freed","reason":"farm_left_scene_tree_during_reseed"})
			continue
		var succeeded := int(candidate.get("meat_stock")) > 0 and int(game.get("wood")) == wood_before - 25
		events.append({"action":"farm_reseeded_through_hud","farm":candidate.name,"wood_before":wood_before,"wood_after":game.get("wood"),"wood_cost":25,"stock_after":candidate.get("meat_stock"),"verified":succeeded})
		if succeeded: return candidate
	return null

func _verify_army_control_group(game: Node) -> void:
	army_group_checked = true
	if DisplayServer.get_name() == "headless":
		var army := _player_military()
		_select_units(game, army)
		game.call("_assign_control_group", 1)
		var recalled := _control_group_units(game, 1)
		var ok := not army.is_empty() and recalled.size() == army.size()
		events.append({"action":"army_control_group_1_assign_and_recall","assigned_names":army.map(func(u): return str(u.name)),"recalled_names":recalled.map(func(u): return str(u.name)),"group_size":recalled.size(),"verified":ok,"route":"headless logical production selection/group methods"})
		_checkpoint("army_control_group_recalled", game)
		return
	await _send_key(KEY_F2)
	var army_before: Array[String] = []
	for unit in game.get("selected"):
		if is_instance_valid(unit) and unit.is_in_group("military") and str(unit.get("team")) == "player": army_before.append(str(unit.name))
	await _send_key(KEY_1, 0, true)
	await _send_key(KEY_1)
	var army_after: Array[String] = []
	for unit in game.get("selected"):
		if is_instance_valid(unit) and unit.is_in_group("military") and str(unit.get("team")) == "player": army_after.append(str(unit.name))
	var control_groups: Array = game.get("_control_groups")
	var group_rows: Array = control_groups[1] if control_groups.size() > 1 else []
	var ok := not army_before.is_empty() and army_after.size() == army_before.size() and group_rows.size() == army_before.size()
	var occluded_units: Array[Dictionary] = []
	var visible_markers := 0
	for unit in game.get("selected"):
		if not is_instance_valid(unit) or not unit.is_in_group("military") or str(unit.get("team")) != "player": continue
		var marker: Label3D = unit.get_node_or_null("SelectedUnitMarker") as Label3D
		if marker != null and marker.visible and marker.no_depth_test: visible_markers += 1
		var blocker := _estimated_roof_occluder(game, unit)
		if not blocker.is_empty(): occluded_units.append({"unit":str(unit.name),"building":blocker,"pos":_v3(unit.global_position)})
	var marker_ok := visible_markers == army_after.size()
	events.append({"action":"army_control_group_1_assign_and_recall","assigned_names":army_before,"recalled_names":army_after,"group_size":group_rows.size(),"verified":ok,"input":"Ctrl+1 assign, 1 recall","selected_markers_visible_through_roof":visible_markers,"marker_count_matches_selection":marker_ok,"estimated_roof_occluded_units":occluded_units})
	_checkpoint("army_control_group_recalled", game)
	if not occluded_units.is_empty():
		_checkpoint("army_roof_occlusion_selection_markers", game)

func _estimated_roof_occluder(game: Node, unit: Node3D) -> String:
	var cam := game.get("camera") as Camera3D
	if cam == null: return ""
	var from := cam.global_position
	var target := unit.global_position + Vector3(0, 1.1, 0)
	var ray := target - from
	var distance := ray.length()
	if distance <= 0.1: return ""
	var direction := ray / distance
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player": continue
		var footprint: Vector3 = building.get("footprint")
		var hx := maxf(float(footprint.x) * 0.62, 1.2)
		var hz := maxf(float(footprint.z) * 0.62, 1.2)
		var height := maxf(float(footprint.y) * 1.45, 4.0)
		var bounds := AABB(building.global_position + Vector3(-hx, 0.0, -hz), Vector3(hx * 2.0, height, hz * 2.0))
		var hit: Variant = bounds.intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) < distance - 0.6:
			return str(building.name)
	return ""

func _queued_player_soldiers() -> int:
	var queued := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player": continue
		for unit_type in _train_queue(building):
			if str(unit_type) == "soldier": queued += 1
	return queued

func _soldier_wood_reserve(game: Node) -> int:
	if not _farm_is_live(farm2) and _farm_is_live(farm) and int(farm.get("meat_stock")) <= 180:
		return SECOND_FARM_WOOD_RESERVE
	return 0

func _queue_available_soldiers(game: Node, max_to_queue: int = TARGET_ARMY) -> bool:
	if not is_instance_valid(barracks): return false
	campaign_command_reason = "normal barracks queue soldier; limit=%d" % max_to_queue
	last_army_queue_attempt_game_time = float(game.get("_game_time"))
	var soldier_cost: Dictionary = Catalog.train_cost("soldier")
	var meat_cost := int(soldier_cost.get("meat", 60))
	var wood_cost := int(soldier_cost.get("wood", 20))
	var army_target := _army_target_for_wave(game)
	var desired := maxi(0, army_target - _player_military().size() - _queued_player_soldiers())
	var pop_room := maxi(0, int(game.get("pop_cap")) - int(game.get("population")) - int(game.call("_queued_pop")))
	var wood_reserve := _soldier_wood_reserve(game)
	var existing_queue := _train_queue(barracks)
	var already_paid_front := 1 if bool(barracks.get("train_paid")) and not existing_queue.is_empty() else 0
	var unpaid_queued_units := maxi(0, existing_queue.size() - already_paid_front)
	var food_reserved_for_existing_queue := unpaid_queued_units * meat_cost
	var wood_reserved_for_existing_queue := unpaid_queued_units * wood_cost
	var food_available_for_new_orders := maxi(0, int(game.get("meat")) - food_reserved_for_existing_queue)
	var wood_available_for_new_orders := maxi(0, int(game.get("wood")) - wood_reserve - wood_reserved_for_existing_queue)
	var affordable_food := food_available_for_new_orders / maxi(1, meat_cost)
	var affordable_wood := wood_available_for_new_orders / maxi(1, wood_cost)
	var planned := mini(max_to_queue, mini(desired, mini(pop_room, mini(affordable_food, affordable_wood))))
	if planned <= 0:
		var signature := "%d:%d:%d:%d:%d:%d:%d:%d" % [desired, pop_room, int(game.get("meat")), int(game.get("wood")), wood_reserve, unpaid_queued_units, food_reserved_for_existing_queue, wood_reserved_for_existing_queue]
		if signature != last_soldier_queue_block_signature:
			last_soldier_queue_block_signature = signature
		events.append({"action":"soldier_enqueue_waits_for_budget_population_or_existing_queue","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"army_target":army_target,"desired":desired,"population_room":pop_room,"food":int(game.get("meat")),"wood":int(game.get("wood")),"food_per_soldier":meat_cost,"wood_per_soldier":wood_cost,"second_farm_reserve":wood_reserve,"unpaid_existing_queue_slots":unpaid_queued_units,"food_reserved_for_existing_queue":food_reserved_for_existing_queue,"wood_reserved_for_existing_queue":wood_reserved_for_existing_queue,"army":_player_military().size(),"queued_soldiers":_queued_player_soldiers(),"route":"normal barracks queue deferred until real resources and pop room are available"})
		return false
	last_soldier_queue_block_signature = ""
	if DisplayServer.get_name() == "headless":
		var enqueues: Array[Dictionary] = []
		_select_units(game, [barracks])
		for _i in planned:
			var queue_before := _train_queue(barracks).size()
			var queue_items_before := _train_queue(barracks).duplicate()
			var resources_before := _training_resource_snapshot(game)
			game.call("_on_train_soldier")
			var queue_after := _train_queue(barracks).duplicate()
			var resources_after := _training_resource_snapshot(game)
			var accepted := queue_after.size() > queue_before
			enqueues.append({"queue_before":queue_items_before,"queue_after":queue_after,"accepted":accepted,"resources_before_enqueue":resources_before,"resources_after_enqueue":resources_after,"enqueue_resource_delta":_resource_delta(resources_before, resources_after),"resource_payment_asserted_at_enqueue":false,"population":int(game.get("population")),"queued_pop":int(game.call("_queued_pop")),"pop_cap":int(game.get("pop_cap"))})
			if not accepted: break
		events.append({"action":"natural_soldier_enqueue_requests","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"army_target":army_target,"desired":desired,"planned":planned,"second_farm_wood_reserve":wood_reserve,"unpaid_existing_queue_slots_reserved":unpaid_queued_units,"enqueues":enqueues,"final_queue":_train_queue(barracks),"army":_player_military().size(),"accepted":enqueues.any(func(row): return bool(row.get("accepted", false))),"selected_entity":str(barracks.name),"route":"Main._on_train_soldier -> normal barracks queue; acceptance, payment, and spawn audited separately"})
		return enqueues.any(func(row): return bool(row.get("accepted", false)))
	var enqueues: Array[Dictionary] = []
	await _click_world(game, barracks.global_position + Vector3(0, 3.0, 0), "select barracks for natural soldier production")
	await get_tree().create_timer(0.2).timeout
	var hud: Node = game.get("hud")
	for _i in planned:
		var btns: Dictionary = hud.get("_cmd_btns")
		var btn: Button = btns.get("soldier") as Button
		if btn == null or not is_instance_valid(btn) or not btn.is_inside_tree():
			enqueues.append({"queue_before":_train_queue(barracks).duplicate(),"queue_after":_train_queue(barracks).duplicate(),"accepted":false,"click_skipped":"soldier_button_not_in_scene_tree"})
			break
		var q_before := _train_queue(barracks).duplicate()
		var resources_before := _training_resource_snapshot(game)
		await _click_control(btn)
		await get_tree().create_timer(0.2).timeout
		var q_after := _train_queue(barracks).duplicate()
		var resources_after := _training_resource_snapshot(game)
		var accepted := q_after.size() > q_before.size()
		enqueues.append({"queue_before":q_before,"queue_after":q_after,"accepted":accepted,"resources_before_enqueue":resources_before,"resources_after_enqueue":resources_after,"enqueue_resource_delta":_resource_delta(resources_before, resources_after),"resource_payment_asserted_at_enqueue":false,"population":game.get("population"),"queued_pop":game.call("_queued_pop"),"pop_cap":game.get("pop_cap")})
		if not accepted: break
	events.append({"action":"natural_soldier_enqueue_requests","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":campaign_command_reason,"army_target":army_target,"desired":desired,"planned":planned,"second_farm_wood_reserve":wood_reserve,"unpaid_existing_queue_slots_reserved":unpaid_queued_units,"enqueues":enqueues,"final_queue":_train_queue(barracks),"accepted":enqueues.any(func(row): return bool(row.get("accepted", false))),"selected_entity":str(barracks.name),"route":"visible Soldier HUD button -> Main._on_train_soldier; acceptance, payment, and spawn audited separately"})
	return enqueues.any(func(row): return bool(row.get("accepted", false)))

func _training_resource_snapshot(game: Node) -> Dictionary:
	return {"meat":int(game.get("meat")),"wood":int(game.get("wood")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}

func _resource_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta := {}
	for key in ["meat", "wood", "stone", "gold"]:
		delta[key] = int(before.get(key, 0)) - int(after.get(key, 0))
	return delta

func _tracked_player_army_names() -> Array[String]:
	var names: Array[String] = []
	for unit in _player_military(): names.append(str(unit.name))
	return names

func _maintain_threat_response_plan(game: Node) -> void:
	var now := float(game.get("_game_time"))
	if now - last_protection_sweep_game_time < 0.5:
		return
	last_protection_sweep_game_time = now
	_maintain_economy_guard_pair(game)
	_evacuate_targeted_workers(game)
	_reroute_unsafe_evacuated_workers(game)
	_resume_safe_evacuated_workers(game)
	_verify_evacuated_worker_progress(game)

func _maintain_economy_guard_pair(game: Node) -> void:
	for runtime_id in economy_guard_runtime_ids.keys():
		var unit := instance_from_id(int(runtime_id)) as Node3D
		if not is_instance_valid(unit) or not bool(unit.get("alive")):
			economy_guard_runtime_ids.erase(runtime_id)
	var army := _player_military()
	var desired := mini(ECONOMY_GUARD_COUNT, maxi(0, army.size() - 1))
	if economy_guard_runtime_ids.size() >= desired:
		return
	var candidates := army.filter(func(unit: Node3D) -> bool: return not economy_guard_runtime_ids.has(str(unit.get_instance_id())))
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(ECONOMY_GUARD_ANCHOR) < b.global_position.distance_squared_to(ECONOMY_GUARD_ANCHOR))
	var hud: Node = game.get("hud")
	var buttons: Dictionary = hud.get("_cmd_btns") if hud != null else {}
	var guard_button := buttons.get("guard") as Button
	if guard_button == null or not guard_button.visible:
		return
	while economy_guard_runtime_ids.size() < desired and not candidates.is_empty():
		var soldier: Node3D = candidates.pop_front()
		_select_units(game, [soldier])
		guard_button.pressed.emit()
		game.call("_route_pending_command", ECONOMY_GUARD_ANCHOR)
		var accepted := bool(soldier.get("guard_active")) and (soldier.get("guard_anchor") as Vector3).distance_to(ECONOMY_GUARD_ANCHOR) < 0.1
		if accepted:
			economy_guard_runtime_ids[str(soldier.get_instance_id())] = true
		events.append({"action":"economy_protection_guard_order","game_time":float(game.get("_game_time")),"soldier":str(soldier.name),"runtime_id":str(soldier.get_instance_id()),"anchor":_v3(ECONOMY_GUARD_ANCHOR),"accepted":accepted,"state_after":int(soldier.get("state")),"resolved_anchor":_v3(soldier.get("guard_resolved_anchor")),"route":"production HUD Guard button + Main pending map command","reason":"keep three soldiers near the existing tower and barracks coverage while the assault group intercepts attackers"})

func _evacuate_targeted_workers(game: Node) -> void:
	var threatened: Array = []
	var attackers := _living_zombies()
	for worker in _living_villagers():
		var runtime_id := str(worker.get_instance_id())
		if evacuated_worker_ids.has(runtime_id):
			continue
		var targeted := false
		for enemy in attackers:
			if enemy.get("attack_target") == worker:
				targeted = true
				break
		if targeted:
			threatened.append(worker)
	if threatened.is_empty():
		return
	var before_rows: Array[Dictionary] = []
	var accepted_rows: Array[Dictionary] = []
	for worker in threatened:
		var pursuers: Array = attackers.filter(func(enemy: Node3D) -> bool: return enemy.get("attack_target") == worker)
		var rally := _economy_rally_point_for_worker(worker, pursuers)
		var resume_runtime_id := str(worker.get_instance_id())
		_retire_worker_resume_audits(resume_runtime_id, float(game.get("_game_time")), "new_enemy_threat_before_prior_deposit")
		var resume_key_before_move := str(worker.get("resume_key"))
		if resume_key_before_move.is_empty() and is_instance_valid(worker.get("gather_target")):
			resume_key_before_move = _worker_resource_key(worker.get("gather_target"))
		before_rows.append({"id":str(worker.get_instance_id()),"name":str(worker.name),"hp":float(worker.get("hp")),"resume_key":resume_key_before_move,"gather_target":str(worker.get("gather_target").name) if is_instance_valid(worker.get("gather_target")) else "","carry":int(worker.get("carry_amount"))})
		_select_units(game, [worker])
		game.call("_on_cmd_move")
		game.call("_route_pending_command", rally)
		var goal: Variant = worker.get("_goal_final")
		var accepted: bool = int(worker.get("state")) == 1 and goal is Vector3 and (goal as Vector3).distance_to(rally) < 0.2
		if accepted:
			evacuated_worker_ids[str(worker.get_instance_id())] = {"name":str(worker.name),"resume_key":resume_key_before_move,"issued_game_time":float(game.get("_game_time")),"issued_hp":float(worker.get("hp")),"issued_carry":int(worker.get("carry_amount")),"gather_started":false,"resume_attempts":0,"retry_after_game_time":float(game.get("_game_time")),"current_rally":_v3(rally),"move_history":[{"game_time":float(game.get("_game_time")),"kind":"initial_evacuate","destination":_v3(rally),"accepted":accepted}],"reroute_count":0,"reroute_attempts":0,"last_reroute_game_time":-999.0,"unsafe_since_game_time":float(game.get("_game_time")),"first_threat":pursuers.map(func(enemy: Node3D) -> Dictionary: return {"runtime_id":str(enemy.get_instance_id()),"name":str(enemy.name),"position":_v3(enemy.global_position)})}
		accepted_rows.append({"name":str(worker.name),"id":str(worker.get_instance_id()),"accepted":accepted,"state":int(worker.get("state")),"goal":_v3(goal) if goal is Vector3 else [],"rally":_v3(rally),"hp_after":float(worker.get("hp")),"pursuers":pursuers.map(func(enemy: Node3D) -> Dictionary: return {"name":str(enemy.name),"hp":float(enemy.get("hp")),"pos":_v3(enemy.global_position)})})
	events.append({"action":"targeted_workers_withdrawn_to_tower_coverage","game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"before":before_rows,"after":accepted_rows,"all_accepted":accepted_rows.size() == threatened.size() and accepted_rows.all(func(row): return bool(row.get("accepted"))),"enemy_targets":accepted_rows.map(func(row: Dictionary) -> Dictionary: return {"worker":row.get("name"),"pursuers":row.get("pursuers"),"rally":row.get("rally")}),"route":"Main Move button + pending map command","reason":"withdraw exposed gatherers along the safest available direction while remaining inside an existing arrow tower's coverage; no unit stats or resources changed"})

func _economy_rally_point_for_worker(worker: Node3D, pursuers: Array) -> Vector3:
	var candidates: Array[Vector3] = [ECONOMY_GUARD_ANCHOR]
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 4.5), Vector3(0, 0, -4.5), Vector3(4.5, 0, 0), Vector3(-4.5, 0, 0)]
	var towers: Array[Node3D] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player" or not bool(building.get("alive")) or not bool(building.get("is_tower")) or not bool(building.get("is_complete")):
			continue
		towers.append(building as Node3D)
		for offset in offsets:
			candidates.append((building as Node3D).global_position + offset)
	var best := ECONOMY_GUARD_ANCHOR
	var best_score := -INF
	var map_half := 55.0
	for candidate in candidates:
		if absf(candidate.x) > map_half - 2.0 or absf(candidate.z) > map_half - 2.0:
			continue
		var covered := false
		for tower in towers:
			var radius := float(tower.get("attack_range"))
			if tower.global_position.distance_to(candidate) <= maxf(0.0, radius - 0.5):
				covered = true
				break
		if not covered:
			continue
		var route: Array = Pathfind.find_path(worker.global_position, candidate, get_tree())
		var path_report := Pathfind.last_path_report.duplicate(true)
		var route_end: Vector3 = route.back() if not route.is_empty() else worker.global_position
		if not bool(path_report.get("search_reached_goal", false)) or route_end.distance_to(candidate) > 0.4:
			continue
		var nearest_pursuer := INF
		for enemy in pursuers:
			if is_instance_valid(enemy) and bool(enemy.get("alive")):
				nearest_pursuer = minf(nearest_pursuer, enemy.global_position.distance_to(candidate))
		var score := nearest_pursuer - worker.global_position.distance_to(candidate) * 0.2
		if score > best_score:
			best_score = score
			best = candidate
	return Vector3(best.x, 0.0, best.z)

func _reroute_unsafe_evacuated_workers(game: Node) -> void:
	if not enable_pending_worker_reroutes:
		return
	var now := float(game.get("_game_time"))
	for raw_id in evacuated_worker_ids.keys().duplicate():
		var runtime_id := str(raw_id)
		var record: Dictionary = evacuated_worker_ids[runtime_id]
		var worker := instance_from_id(int(runtime_id)) as Node3D
		if not is_instance_valid(worker) or not bool(worker.get("alive")):
			continue
		var pursuers := _living_zombies().filter(func(enemy: Node3D) -> bool: return enemy.get("attack_target") == worker or enemy.global_position.distance_to(worker.global_position) < 14.0)
		if pursuers.is_empty():
			continue
		var nearest_distance := INF
		var nearest: Node3D
		for enemy in pursuers:
			var distance: float = enemy.global_position.distance_to(worker.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = enemy
		var actual_goal: Variant = worker.get("_goal_final")
		var destination := actual_goal as Vector3 if actual_goal is Vector3 else worker.global_position
		var old_order_overridden := is_instance_valid(worker.get("gather_target")) or is_instance_valid(worker.get("drop_target")) or int(worker.get("state")) != 1
		var current_destination_unsafe := nearest != null and nearest.global_position.distance_to(destination) < 14.0
		var unsafe_duration := now - float(record.get("unsafe_since_game_time", now))
		if not old_order_overridden and not current_destination_unsafe and unsafe_duration < 4.0:
			continue
		if int(record.get("reroute_attempts", 0)) >= WORKER_REROUTE_MAX:
			if not bool(record.get("reroute_limit_logged", false)):
				record["reroute_limit_logged"] = true
				events.append({"action":"withdrawn_worker_reroute_limit_reached","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"pursuer":str(nearest.name) if is_instance_valid(nearest) else "","nearest_distance":nearest_distance,"reroute_attempts":record.get("reroute_attempts"),"guard_or_tower_must_intercept":true})
			continue
		if now - float(record.get("last_reroute_game_time", -999.0)) < WORKER_REROUTE_COOLDOWN:
			continue
		var evaluation := _safer_reachable_worker_rally(worker, pursuers, record, destination)
		if not bool(evaluation.get("found", false)):
			record["last_reroute_game_time"] = now
			record["reroute_attempts"] = int(record.get("reroute_attempts", 0)) + 1
			events.append({"action":"withdrawn_worker_no_safer_reachable_point","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"pursuer":str(nearest.name) if is_instance_valid(nearest) else "","nearest_distance":nearest_distance,"unsafe_duration":unsafe_duration,"old_order_overridden":old_order_overridden,"attempt":record.get("reroute_attempts"),"candidates":evaluation.get("candidates",[]),"guard_or_tower_must_intercept":true})
			continue
		var point: Vector3 = evaluation["point"]
		record["reroute_attempts"] = int(record.get("reroute_attempts", 0)) + 1
		var preserved_key := str(record.get("resume_key", ""))
		_select_units(game, [worker])
		game.call("_on_cmd_move")
		game.call("_route_pending_command", point)
		var goal_after: Variant = worker.get("_goal_final")
		var accepted := int(worker.get("state")) == 1 and goal_after is Vector3 and (goal_after as Vector3).distance_to(point) < 0.4 and not is_instance_valid(worker.get("gather_target"))
		record["last_reroute_game_time"] = now
		record["reroute_count"] = int(record.get("reroute_count", 0)) + 1 if accepted else int(record.get("reroute_count", 0))
		record["current_rally"] = _v3(point) if accepted else record.get("current_rally", [])
		record["resume_key"] = preserved_key
		var history: Array = record.get("move_history", [])
		history.append({"game_time":now,"kind":"throttled_reroute","destination":_v3(point),"accepted":accepted,"goal_after":_v3(goal_after) if goal_after is Vector3 else [],"gather_target_after":str(worker.get("gather_target").name) if is_instance_valid(worker.get("gather_target")) else "","drop_target_after":str(worker.get("drop_target").name) if is_instance_valid(worker.get("drop_target")) else "","state_after":int(worker.get("state"))})
		record["move_history"] = history
		events.append({"action":"withdrawn_worker_reroute_issued","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"resume_key_preserved":preserved_key,"pursuer":str(nearest.name) if is_instance_valid(nearest) else "","nearest_distance":nearest_distance,"unsafe_duration":unsafe_duration,"old_order_overridden":old_order_overridden,"destination":_v3(point),"accepted":accepted,"goal_after":_v3(goal_after) if goal_after is Vector3 else [],"candidate_audit":evaluation.get("candidates",[]),"reroute_count":record.get("reroute_count"),"max_reroutes":WORKER_REROUTE_MAX})

func _safer_reachable_worker_rally(worker: Node3D, pursuers: Array, record: Dictionary, current_destination: Vector3) -> Dictionary:
	var candidates: Array[Vector3] = [ECONOMY_GUARD_ANCHOR]
	var offsets: Array[Vector3] = [Vector3.ZERO,Vector3(0,0,4.5),Vector3(0,0,-4.5),Vector3(4.5,0,0),Vector3(-4.5,0,0)]
	var towers: Array[Node3D] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player" and bool(building.get("alive")) and bool(building.get("is_tower")) and bool(building.get("is_complete")):
			towers.append(building as Node3D)
			for offset in offsets: candidates.append((building as Node3D).global_position + offset)
	var old_dest := current_destination
	var history: Array = record.get("move_history", [])
	var used: Array = []
	for move in history:
		if move is Dictionary and move.get("destination") is Array: used.append(move.destination)
	var audit: Array[Dictionary] = []
	var best_point := Vector3.ZERO
	var best_score := -INF
	for candidate in candidates:
		var rejection := ""
		if absf(candidate.x) > 53.0 or absf(candidate.z) > 53.0:
			rejection = "outside_map_margin"
		var coverage := ""
		if rejection.is_empty():
			for tower in towers:
				if tower.global_position.distance_to(candidate) <= maxf(0.0,float(tower.get("attack_range"))-0.5): coverage = str(tower.name); break
			if coverage.is_empty():
				for unit in get_tree().get_nodes_in_group("military"):
					if is_instance_valid(unit) and bool(unit.get("alive")) and bool(unit.get("guard_active")) and unit.global_position.distance_to(candidate) <= 8.0:
						coverage = "guard:%s" % unit.name; break
			if coverage.is_empty(): rejection = "outside_live_tower_and_guard_coverage"
		var route: Array = []
		var path_report: Dictionary = {}
		if rejection.is_empty():
			route = Pathfind.find_path(worker.global_position,candidate,get_tree())
			path_report = Pathfind.last_path_report.duplicate(true)
			var route_end: Vector3 = route.back() if not route.is_empty() else worker.global_position
			if not bool(path_report.get("search_reached_goal",false)) or route_end.distance_to(candidate) > 0.4: rejection = "path_not_reached_goal"
		var nearest_old := INF
		var nearest_new := INF
		for enemy in pursuers:
			if is_instance_valid(enemy) and bool(enemy.get("alive")):
				nearest_old = minf(nearest_old,enemy.global_position.distance_to(old_dest))
				nearest_new = minf(nearest_new,enemy.global_position.distance_to(candidate))
		if rejection.is_empty() and used.has(_v3(candidate)): rejection = "destination_already_used"
		if rejection.is_empty() and nearest_new < nearest_old + Pathfind.CELL: rejection = "not_safer_by_one_nav_cell"
		audit.append({"point":_v3(candidate),"coverage":coverage,"nearest_distance_old":nearest_old,"nearest_distance_candidate":nearest_new,"path_report":path_report,"route_end":_v3(route.back()) if not route.is_empty() else [],"rejection":rejection})
		if rejection.is_empty() and nearest_new > best_score:
			best_score = nearest_new; best_point = candidate
	return {"found":best_score > -INF,"point":best_point,"candidates":audit}

func _resume_safe_evacuated_workers(game: Node) -> void:
	var attackers := _living_zombies()
	for runtime_id in evacuated_worker_ids.keys().duplicate():
		var worker := instance_from_id(int(runtime_id)) as Node3D
		if not is_instance_valid(worker) or not bool(worker.get("alive")):
			events.append({"action":"withdrawn_worker_lost_before_safe_resume","game_time":float(game.get("_game_time")),"worker":evacuated_worker_ids[runtime_id].get("name"),"issued_game_time":evacuated_worker_ids[runtime_id].get("issued_game_time")})
			evacuated_worker_ids.erase(runtime_id)
			continue
		var unsafe := false
		for enemy in attackers:
			if enemy.get("attack_target") == worker or enemy.global_position.distance_to(worker.global_position) < 14.0:
				unsafe = true
				break
		if unsafe:
			var pending: Dictionary = evacuated_worker_ids[runtime_id]
			pending["last_unsafe_game_time"] = float(game.get("_game_time"))
			continue
		var record: Dictionary = evacuated_worker_ids[runtime_id]
		var now := float(game.get("_game_time"))
		if now < float(record.get("retry_after_game_time", -INF)):
			continue
		var key := str(record.get("resume_key", ""))
		var target: Node3D
		match key:
			"meat":
				var farms := _live_player_farms()
				farms.sort_custom(func(a: Node3D, b: Node3D) -> bool: return int(a.get("meat_stock")) > int(b.get("meat_stock")))
				if not farms.is_empty(): target = farms[0]
			"stone": target = _nearest_resource(ResourceNode3D.Kind.STONE)
			"wood": target = _nearest_resource(ResourceNode3D.Kind.WOOD)
		if not is_instance_valid(target) or not target.is_inside_tree():
			record["resume_attempts"] = int(record.get("resume_attempts", 0)) + 1
			record["retry_after_game_time"] = now + 2.0
			events.append({"action":"withdrawn_worker_gather_resume_deferred","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"resume_key":key,"attempt":int(record.get("resume_attempts", 0)),"retry_after_game_time":record.get("retry_after_game_time"),"reason":"no valid live resource target; evacuation protection remains active"})
			continue
		var issuer := "_resume_safe_evacuated_workers"
		var accepted := _issue_gather_order_authorized(game, [worker], target, "resume evacuated worker after nearby enemies leave the tower coverage area", issuer, runtime_id)
		if not accepted:
			record["resume_attempts"] = int(record.get("resume_attempts", 0)) + 1
			record["retry_after_game_time"] = now + 2.0
			events.append({"action":"withdrawn_worker_gather_resume_rejected","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"resume_key":key,"target":str(target.name),"attempt":int(record.get("resume_attempts", 0)),"retry_after_game_time":record.get("retry_after_game_time"),"evacuation_protection_retained":evacuated_worker_ids.has(runtime_id)})
			continue
		var audit_id := "%s:%d" % [runtime_id, next_worker_resume_audit_id]
		next_worker_resume_audit_id += 1
		var audit := {"audit_id":audit_id,"worker":str(worker.name),"worker_runtime_id":runtime_id,"resume_key":key,"target":str(target.name),"target_runtime_id":str(target.get_instance_id()),"issued_game_time":now,"retreat_game_time":record.get("issued_game_time"),"carry_at_resume":int(worker.get("carry_amount")),"harvested_after_resume":0,"gather_progress_observed":false,"deposit_received":false,"inventory_before_resume":_resource_amount(game,key)}
		worker_resume_audits[audit_id] = audit
		_connect_evacuated_worker_audit_signals(worker, audit_id)
		evacuated_worker_ids.erase(runtime_id)
		events.append({"action":"withdrawn_worker_safely_returned_to_gathering","game_time":now,"worker":str(worker.name),"worker_runtime_id":runtime_id,"resume_key":key,"target":str(target.name),"accepted":accepted,"issuer":issuer,"audit_id":audit_id,"hp":float(worker.get("hp")),"issued_game_time":record.get("issued_game_time"),"carry_at_resume":int(worker.get("carry_amount")),"pending_evacuation_removed":not evacuated_worker_ids.has(runtime_id)})

func _verify_evacuated_worker_progress(game: Node) -> void:
	for audit_id in worker_resume_audits.keys():
		var record: Dictionary = worker_resume_audits[audit_id]
		var worker := instance_from_id(int(record.get("worker_runtime_id", 0))) as Node3D
		if is_instance_valid(worker) and bool(worker.get("alive")):
			record["last_alive_observation_game_time"] = float(game.get("_game_time"))

func _connect_evacuated_worker_audit_signals(worker: Node3D, audit_id: String) -> void:
	var deposit_callable := Callable(self, "_on_evacuated_worker_deposited").bind(str(worker.get_instance_id()), audit_id)
	if worker.has_signal("deposited") and not worker.is_connected("deposited", deposit_callable):
		worker.connect("deposited", deposit_callable)
	var harvest_callable := Callable(self, "_on_evacuated_worker_harvested").bind(audit_id)
	if worker.has_signal("diagnostic_harvested") and not worker.is_connected("diagnostic_harvested", harvest_callable):
		worker.connect("diagnostic_harvested", harvest_callable)
	worker_resume_audits[audit_id]["deposit_callable"] = deposit_callable
	worker_resume_audits[audit_id]["harvest_callable"] = harvest_callable

func _on_evacuated_worker_harvested(worker_id: int, source_id: int, resource_key: String, amount: int, carry_before: int, carry_after: int, source_stock_before: int, source_stock_after: int, audit_id: String) -> void:
	if not worker_resume_audits.has(audit_id):
		return
	var audit: Dictionary = worker_resume_audits[audit_id]
	if str(worker_id) != str(audit.get("worker_runtime_id", "")):
		return
	if not is_instance_valid(last_game) or float(audit.get("issued_game_time", INF)) > float(last_game.get("_game_time")):
		return
	audit["harvested_after_resume"] = int(audit.get("harvested_after_resume", 0)) + amount
	audit["last_harvest_game_time"] = float(last_game.get("_game_time")) if is_instance_valid(last_game) else -1.0
	var matches_resume_key := resource_key == str(audit.get("resume_key", ""))
	if matches_resume_key:
		audit["gather_progress_observed"] = true
	events.append({"action":"withdrawn_worker_production_harvest_receipt","game_time":audit.get("last_harvest_game_time"),"audit_id":audit_id,"worker":audit.get("worker"),"worker_runtime_id":str(worker_id),"resource_key":resource_key,"amount":amount,"matches_resume_key":matches_resume_key,"carry_before":carry_before,"carry_after":carry_after,"source_runtime_id":str(source_id),"source_stock_before":source_stock_before,"source_stock_after":source_stock_after,"claim":"production harvest signal only; not an inventory deposit"})

func _on_evacuated_worker_deposited(resource_key: String, amount: int, worker_runtime_id: String, audit_id: String) -> void:
	if not worker_resume_audits.has(audit_id):
		return
	var audit: Dictionary = worker_resume_audits[audit_id]
	if str(audit.get("worker_runtime_id", "")) != worker_runtime_id:
		return
	var game := get_tree().get_first_node_in_group("main_game")
	var amount_after := _resource_amount(game, resource_key) if game != null else -1
	audit["deposit_received"] = true
	audit["deposit_game_time"] = float(game.get("_game_time")) if game != null else -1.0
	audit["deposit_resource_key"] = resource_key
	audit["deposit_amount"] = amount
	audit["inventory_after_deposit"] = amount_after
	audit["inventory_delta_since_resume"] = amount_after - int(audit.get("inventory_before_resume", amount_after))
	audit["receipt_has_post_resume_harvest"] = int(audit.get("harvested_after_resume", 0)) > 0 and resource_key == str(audit.get("resume_key", ""))
	events.append({"action":"withdrawn_worker_production_deposit_receipt","game_time":audit["deposit_game_time"],"audit_id":audit_id,"worker":audit.get("worker"),"worker_runtime_id":worker_runtime_id,"resource_key":resource_key,"deposit_amount":amount,"post_resume_harvest_amount":int(audit.get("harvested_after_resume", 0)),"receipt_has_post_resume_harvest":audit["receipt_has_post_resume_harvest"],"inventory_before_resume":audit.get("inventory_before_resume"),"inventory_after_deposit":amount_after,"inventory_delta_since_resume":audit["inventory_delta_since_resume"],"receipt_source":"Villager.deposited signal bound to this runtime id"})
	var worker := instance_from_id(int(worker_runtime_id)) as Node3D
	if is_instance_valid(worker):
		var deposit_callable: Variant = audit.get("deposit_callable")
		if deposit_callable is Callable and worker.is_connected("deposited", deposit_callable): worker.disconnect("deposited", deposit_callable)
		var harvest_callable: Variant = audit.get("harvest_callable")
		if harvest_callable is Callable and worker.is_connected("diagnostic_harvested", harvest_callable): worker.disconnect("diagnostic_harvested", harvest_callable)

func _resource_amount(game: Node, key: String) -> int:
	if game == null:
		return -1
	match key:
		"wood": return int(game.get("wood"))
		"meat": return int(game.get("meat"))
		"stone": return int(game.get("stone"))
		"gold": return int(game.get("gold"))
	return -1

func _worker_resource_key(target: Node) -> String:
	if not is_instance_valid(target):
		return ""
	if target.is_in_group("farms") or target.has_method("harvest_meat"):
		return "meat"
	if target.has_method("res_key"):
		return str(target.call("res_key"))
	return ""

func _retire_worker_resume_audits(runtime_id: String, game_time: float, reason: String) -> void:
	for audit_id in worker_resume_audits.keys():
		var audit: Dictionary = worker_resume_audits[audit_id]
		if str(audit.get("worker_runtime_id", "")) != runtime_id or bool(audit.get("deposit_received", false)) or bool(audit.get("retired", false)):
			continue
		var worker := instance_from_id(int(runtime_id)) as Node3D
		if is_instance_valid(worker):
			var deposit_callable: Variant = audit.get("deposit_callable")
			if deposit_callable is Callable and worker.is_connected("deposited", deposit_callable): worker.disconnect("deposited", deposit_callable)
			var harvest_callable: Variant = audit.get("harvest_callable")
			if harvest_callable is Callable and worker.is_connected("diagnostic_harvested", harvest_callable): worker.disconnect("diagnostic_harvested", harvest_callable)
		audit["retired"] = true
		audit["retired_game_time"] = game_time
		audit["retired_reason"] = reason
		events.append({"action":"withdrawn_worker_resume_audit_retired","game_time":game_time,"audit_id":audit_id,"worker":audit.get("worker"),"worker_runtime_id":runtime_id,"reason":reason,"harvested_after_resume":int(audit.get("harvested_after_resume", 0)),"deposit_received":bool(audit.get("deposit_received", false))})

func _evacuated_workers_pending() -> bool:
	return not evacuated_worker_ids.is_empty()

func _track_soldier_training(game: Node) -> void:
	if not is_instance_valid(barracks): return
	var barracks_id := int(barracks.get_instance_id())
	var queue := _train_queue(barracks).duplicate()
	var paid := bool(barracks.get("train_paid"))
	var paused := bool(barracks.get("train_paused"))
	var army_names := _tracked_player_army_names()
	var resources := _training_resource_snapshot(game)
	if barracks_id != tracked_training_barracks_id:
		tracked_training_barracks_id = barracks_id
		tracked_training_queue = queue.duplicate()
		tracked_training_paid = paid
		tracked_training_paused = paused
		tracked_training_army_names = army_names.duplicate()
		tracked_training_resources = resources.duplicate(true)
		return
	if queue == tracked_training_queue and paid == tracked_training_paid and paused == tracked_training_paused and army_names == tracked_training_army_names and resources == tracked_training_resources:
		return
	var training_started := not tracked_training_paid and paid
	var spawned_count := maxi(0, army_names.size() - tracked_training_army_names.size())
	var expected_cost: Dictionary = Catalog.train_cost("soldier")
	events.append({"action":"soldier_training_lifecycle_transition","game_time":float(game.get("_game_time")),"queue_before":tracked_training_queue.duplicate(),"queue_after":queue,"queue_acceptance_changed":queue.size() > tracked_training_queue.size(),"train_paid_before":tracked_training_paid,"train_paid_after":paid,"training_started":training_started,"training_start_confirmation":"Building._try_start_front -> Main.try_pay_train returned true" if training_started else "no new pay-on-start transition","train_paused_before":tracked_training_paused,"train_paused_after":paused,"training_timer":float(barracks.get("train_timer")),"resource_snapshot_before":tracked_training_resources.duplicate(true),"resource_snapshot_after":resources,"observed_resource_delta_since_prior_frame":_resource_delta(tracked_training_resources, resources),"expected_cost_for_started_slot":expected_cost if training_started else {},"completed_soldiers_spawned":spawned_count,"army_before":tracked_training_army_names.duplicate(),"army_after":army_names,"payment_inferred_from_enqueue":false})
	tracked_training_queue = queue.duplicate()
	tracked_training_paid = paid
	tracked_training_paused = paused
	tracked_training_army_names = army_names.duplicate()
	tracked_training_resources = resources.duplicate(true)

func _queue_one_reinforcement(game: Node) -> void:
	if not is_instance_valid(barracks) or _player_military().size() + _queued_player_soldiers() >= _army_target_for_wave(game):
		return
	last_reinforce_at = elapsed
	var queued_before := _queued_player_soldiers()
	var enqueue_accepted := await _queue_available_soldiers(game, 1)
	if enqueue_accepted:
		events.append({"action":"reinforcement_enqueue_accepted_during_defense","reason":"army below five; current resources cover the next unpaid queue slots and population room","elapsed":elapsed,"game_time":game.get("_game_time"),"queued_before":queued_before,"queued_after":_queued_player_soldiers(),"food":int(game.get("meat")),"wood":int(game.get("wood")),"army":_player_military().size(),"payment_state":"enqueue accepted; actual payment recorded separately on train_paid false-to-true transition","route":"Main._on_train_soldier / HUD Soldier button"})

func _issue_guards_for_new_soldiers(game: Node) -> void:
	var unassigned: Array = []
	var west_count := 0
	var east_count := 0
	for soldier in _player_military():
		var runtime_id := str(soldier.get_instance_id())
		if guard_ordered_runtime_ids.has(runtime_id) or guard_unavailable_logged_runtime_ids.has(runtime_id): continue
		if bool(soldier.get("guard_active")):
			guard_ordered_runtime_ids[runtime_id] = true
			if (soldier.get("guard_anchor") as Vector3).x < 0.0: west_count += 1
			else: east_count += 1
			continue
		if is_instance_valid(soldier.get("attack_target")) and bool(soldier.get("attack_target").get("alive")):
			continue
		unassigned.append(soldier)
	if unassigned.is_empty(): return
	# A newly trained soldier receives one real Guard post. The chosen side is
	# based on the current live distribution; existing guards are never refreshed.
	for soldier in unassigned:
		var runtime_id := str(soldier.get_instance_id())
		var anchor := Vector3(-8.0, 0.0, -3.0) if west_count <= east_count else Vector3(6.0, 0.0, 0.0)
		var side := "west_south" if anchor.x < 0.0 else "east_town_center"
		var hud: Node = game.get("hud")
		var command_buttons: Dictionary = hud.get("_cmd_btns") if hud != null else {}
		var guard_button: Button = command_buttons.get("guard") as Button
		if guard_button == null or not guard_button.visible:
			guard_unavailable_logged_runtime_ids[runtime_id] = true
			events.append({"action":"guard_order_not_issued","reason":"new_player_soldier_post_unavailable","soldier":str(soldier.name),"side":side})
			continue
		var before := {"state":int(soldier.get("state")),"guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor")),"target":str(soldier.get("attack_target").name) if is_instance_valid(soldier.get("attack_target")) else ""}
		_select_units(game, [soldier])
		guard_button.pressed.emit()
		game.call("_route_pending_command", anchor)
		var accepted := bool(soldier.get("guard_active")) and (soldier.get("guard_anchor") as Vector3).distance_to(anchor) < 0.1
		if accepted:
			guard_ordered_runtime_ids[str(soldier.get_instance_id())] = true
			if side == "west_south": west_count += 1
			else: east_count += 1
		events.append({"action":"one_time_guard_deployment","reason":"new soldier joined the natural defense roster","side":side,"soldier":str(soldier.name),"runtime_id":str(soldier.get_instance_id()),"before":before,"after":{"guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor")),"state":int(soldier.get("state"))},"route":"production HUD Guard button + Main pending map command","accepted":accepted,"guard_reissues":0})

func _save_return_continue(game: Node) -> void:
	var old_main_id := int(game.get_instance_id())
	var saved_game_time := float(game.get("_game_time"))
	var saved_wave := int(game.get("_horde_wave"))
	var saved_mode := int(game.get("_horde_mode"))
	var saved_seed := int(game.get("map_seed"))
	var saved_live_enemies := _living_zombies()
	await _send_key(KEY_F5)
	var save_text := FileAccess.get_file_as_string("user://aoelite3d_save.json") if FileAccess.file_exists("user://aoelite3d_save.json") else ""
	var parsed: Variant = JSON.parse_string(save_text) if not save_text.is_empty() else null
	if not parsed is Dictionary:
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"F5 did not produce a readable production save","game_time":saved_game_time,"wave":saved_wave})
		_finish(false, "production_f5_save_missing_or_invalid")
		return
	checkpoint_payload = parsed
	var entities: Dictionary = checkpoint_payload.get("entities", {})
	var soldiers_data: Array = entities.get("soldiers", [])
	var runtime_to_entity: Dictionary = _runtime_entity_id_map()
	checkpoint_entity_map.clear()
	checkpoint_runtime_id_to_entity_id.clear()
	# Build the checkpoint side from the serialized payload first. Dead corpses
	# are valid saved entities even when their old runtime nodes are no longer
	# present in the scene tree.
	for serialized_unit in soldiers_data:
		if not bool(serialized_unit.get("is_zombie", false)) or int(serialized_unit.get("horde_wave_id", 0)) <= 0:
			continue
		var entity_id := str(serialized_unit.get("id", ""))
		if entity_id.is_empty():
			continue
		var ledger_entity_id := str(serialized_unit.get("challenge_ledger_entity_id", entity_id))
		checkpoint_entity_map[entity_id] = {"wave_id":int(serialized_unit.get("horde_wave_id", 0)),"alive":bool(serialized_unit.get("alive", false)),"hp":float(serialized_unit.get("hp", 0.0)),"position":serialized_unit.get("pos", []),"ledger_entity_id":ledger_entity_id,"serialized":true}
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(unit) or not bool(unit.get("is_zombie")) or int(unit.get("horde_wave_id")) <= 0:
			continue
		var runtime_id := str(unit.get_instance_id())
		var entity_id := str(runtime_to_entity.get(runtime_id, ""))
		if entity_id.is_empty():
			events.append({"action":"stable_enemy_map_missing_before_save","runtime_id":runtime_id,"unit_name":str(unit.name),"wave":int(unit.get("horde_wave_id"))})
			continue
		var payload_unit: Dictionary = {}
		for row in soldiers_data:
			if str(row.get("id", "")) == entity_id:
				payload_unit = row
				break
		if payload_unit.is_empty() or int(payload_unit.get("horde_wave_id", -1)) != int(unit.get("horde_wave_id")):
			events.append({"action":"stable_enemy_save_payload_mismatch","runtime_id":runtime_id,"entity_id":entity_id,"wave":int(unit.get("horde_wave_id"))})
			continue
		var checkpoint_row: Dictionary = checkpoint_entity_map.get(entity_id, {})
		checkpoint_row["runtime_id_before_save"] = runtime_id
		checkpoint_row["unit_name_before_save"] = str(unit.name)
		checkpoint_entity_map[entity_id] = checkpoint_row
		checkpoint_runtime_id_to_entity_id[runtime_id] = entity_id
		var ledger_entity_id := str(checkpoint_row.get("ledger_entity_id", entity_id))
		stable_enemy_ids[ledger_entity_id] = true
		var wave_key := str(int(unit.get("horde_wave_id")))
		var rec: Dictionary = wave_ledger.get(wave_key, {})
		runtime_enemy_stable_key[runtime_id] = ledger_entity_id
		_normalize_enemy_ledger_ids()
	continue_pre_wave_audit.clear()
	for wave_key in wave_ledger.keys():
		var audit_rec: Dictionary = wave_ledger[wave_key]
		continue_pre_wave_audit[wave_key] = {"spawned_ids":(audit_rec.get("spawned", {}) as Dictionary).keys(),"killed_ids":(audit_rec.get("killed", {}) as Dictionary).keys(),"entity_ids":checkpoint_entity_map.keys()}
	events.append({"action":"stable_checkpoint_entity_mapping_saved","checkpoint_game_time":saved_game_time,"wave":saved_wave,"mode":saved_mode,"seed":saved_seed,"live_natural_enemies":saved_live_enemies.size(),"mapped_runtime_enemy_ids":checkpoint_runtime_id_to_entity_id.size(),"serialized_enemy_entities":checkpoint_entity_map.size(),"serialized_enemy_ids":checkpoint_entity_map.keys(),"first_wave_spawned_unique_before_continue":_wave_counts("1").get("spawned",0),"spawn_queue":Array(game.get("_horde_spawn_queue")).size()})
	if saved_mode != 1 or saved_seed != 42 or int(checkpoint_payload.get("horde_mode", -1)) != 1 or int(checkpoint_payload.get("map_seed", -1)) != 42:
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"saved payload mode or seed is not Challenge 5 seed 42","save_mode":checkpoint_payload.get("horde_mode"),"save_seed":checkpoint_payload.get("map_seed")})
		_finish(false, "checkpoint_payload_challenge5_seed_mismatch")
		return
	await _send_key(KEY_ESCAPE)
	if not bool(game.get("_pause_menu_open")):
		await _send_key(KEY_ESCAPE)
	var return_button := _button(game.get("_pause_layer"), "返回主菜单")
	if return_button == null or not bool(game.get("_pause_menu_open")):
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"production pause menu or Return to Start button missing","pause_open":bool(game.get("_pause_menu_open"))})
		_finish(false, "production_pause_return_button_missing")
		return
	return_button.pressed.emit()
	events.append({"action":"real_f5_pause_return_to_start","save_game_time":saved_game_time,"wave":saved_wave,"route":"F5 key input -> production pause menu -> Return to Start Button.pressed"})
	var menu: Node = null
	for _frame in 1800:
		await get_tree().process_frame
		menu = get_tree().get_first_node_in_group("main_game")
		if menu != null and int(menu.get_instance_id()) != old_main_id and menu.get("_start_layer") != null:
			break
	if menu == null or int(menu.get_instance_id()) == old_main_id or menu.get("_start_layer") == null:
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"Return to Start did not rebuild the production menu"})
		_finish(false, "production_return_to_start_timeout")
		return
	var mode_select: OptionButton = menu.get("_start_mode_select") as OptionButton
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if mode_select == null or mode_select.get_selected_id() != 1 or continue_button == null or continue_button.disabled:
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"Challenge 5 mode or Continue button was not available at title","mode_id":mode_select.get_selected_id() if mode_select != null else -1,"continue_disabled":continue_button.disabled if continue_button != null else true})
		_finish(false, "challenge5_title_continue_unavailable")
		return
	var menu_instance_id := int(menu.get_instance_id())
	Engine.remove_meta("aoelite_challenge5_restore_entity_map")
	continue_button.pressed.emit()
	var resumed: Node = null
	for _frame in 3600:
		await get_tree().process_frame
		resumed = get_tree().get_first_node_in_group("main_game")
		if resumed != null and int(resumed.get_instance_id()) != menu_instance_id and bool(resumed.get("_match_started")) and float(resumed.get("_game_time")) >= saved_game_time:
			break
	if resumed == null or not bool(resumed.get("_match_started")) or int(resumed.get("map_seed")) != 42 or int(resumed.get("_horde_mode")) != 1:
		events.append({"action":"checkpoint_save_continue_failed","first_causal_split":"production Continue did not restore the same Challenge 5 match","resumed_game_time":resumed.get("_game_time") if resumed != null else -1,"seed":resumed.get("map_seed") if resumed != null else -1,"mode":resumed.get("_horde_mode") if resumed != null else -1})
		_finish(false, "production_continue_same_match_restore_failed")
		return
	var restored_id_map: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_map", {})
	var restored_runtime_ids: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_runtime_ids", {})
	var restored_ledger_ids: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_ledger_ids", {})
	# Rebind operational handles too. A Continue replaces every node; keeping the
	# pre-save barracks reference silently disables all later reinforcement orders.
	var rebound_buildings: Array[Dictionary] = []
	var saved_buildings: Array = checkpoint_payload.get("entities", {}).get("buildings", [])
	var farm_index := 0
	var tower_index := 0
	for saved_building in saved_buildings:
		var entity_id := str(saved_building.get("id", ""))
		var restored_building: Variant = restored_id_map.get(entity_id)
		if not is_instance_valid(restored_building) or not bool(restored_building.get("alive")):
			continue
		var kind := int(saved_building.get("kind", -1))
		match kind:
			Catalog.FARM:
				farm_index += 1
				if farm_index == 1: farm = restored_building
				elif farm_index == 2: farm2 = restored_building
			Catalog.HOUSE:
				house = restored_building
			Catalog.BARRACKS:
				barracks = restored_building
			Catalog.ARROW_TOWER:
				tower_index += 1
				match tower_index:
					1: tower = restored_building
					2: tower2 = restored_building
					3: tower3 = restored_building
					4: tower4 = restored_building
					5: tower5 = restored_building
		rebound_buildings.append({"entity_id":entity_id,"kind":kind,"runtime_id":str(restored_building.get_instance_id()),"alive":true})
	if not is_instance_valid(barracks): tracked_training_barracks_id = 0
	else: tracked_training_barracks_id = 0 # force a fresh post-Continue queue baseline
	var id_map_records: Array[Dictionary] = []
	var exact_enemy_rebind := true
	for entity_id in checkpoint_entity_map:
		var expected: Dictionary = checkpoint_entity_map[entity_id]
		var rebound: Variant = restored_id_map.get(str(entity_id))
		var restored_runtime_id := str(restored_runtime_ids.get(str(entity_id), ""))
		var ledger_entity_id := str(restored_ledger_ids.get(str(entity_id), expected.get("ledger_entity_id", entity_id)))
		if not restored_runtime_id.is_empty():
			runtime_enemy_seen[restored_runtime_id] = true
			runtime_enemy_stable_key[restored_runtime_id] = ledger_entity_id
		if not is_instance_valid(rebound):
			# The runtime ID map is captured at creation time, so a dead soldier
			# freed immediately after load can still be reconciled exactly.
			if not restored_runtime_id.is_empty() and not bool(expected.get("alive", false)):
				id_map_records.append({"entity_id":str(entity_id),"rebound":false,"runtime_id_after_continue":restored_runtime_id,"serialized_dead_entity_retained_by_runtime_map":true})
				continue
			exact_enemy_rebind = false
			id_map_records.append({"entity_id":str(entity_id),"rebound":false,"expected_wave":int(expected.get("wave_id",-1))})
			continue
		if not bool(rebound.get("is_zombie")) or int(rebound.get("horde_wave_id")) != int(expected.get("wave_id",-1)):
			exact_enemy_rebind = false
		id_map_records.append({"entity_id":str(entity_id),"ledger_entity_id":ledger_entity_id,"rebound":true,"runtime_id_after_continue":str(rebound.get_instance_id()),"unit_name_after_continue":str(rebound.name),"wave_id":int(rebound.get("horde_wave_id")),"alive":bool(rebound.get("alive")),"hp":float(rebound.get("hp"))})
		restored_runtime_id = str(rebound.get_instance_id())
		runtime_enemy_seen[restored_runtime_id] = true
		runtime_enemy_stable_key[restored_runtime_id] = ledger_entity_id
		var unit_wave_key := str(int(rebound.get("horde_wave_id")))
		var unit_rec: Dictionary = wave_ledger.get(unit_wave_key, {})
		var unit_spawned: Dictionary = unit_rec.get("spawned", {})
		if unit_spawned.has(ledger_entity_id):
			var restored_spawn: Dictionary = unit_spawned[ledger_entity_id]
			restored_spawn["runtime_instance_id_after_continue"] = restored_runtime_id
			unit_spawned[ledger_entity_id] = restored_spawn
			unit_rec["spawned"] = unit_spawned
			wave_ledger[unit_wave_key] = unit_rec
	if restored_id_map.is_empty() or not exact_enemy_rebind:
		events.append({"action":"stable_entity_rebind_problem","id_map_size":restored_id_map.size(),"exact_enemy_rebind":exact_enemy_rebind,"mapped_enemies":id_map_records})
	_normalize_enemy_ledger_ids()
	var continue_wave_audit: Dictionary = {}
	var continue_wave_audit_exact := true
	for wave_key in continue_pre_wave_audit.keys():
		var live_rec: Dictionary = wave_ledger.get(wave_key, {})
		var before_audit: Dictionary = continue_pre_wave_audit[wave_key]
		var spawn_ids: Array = (live_rec.get("spawned", {}) as Dictionary).keys()
		var killed_ids: Array = (live_rec.get("killed", {}) as Dictionary).keys()
		var pre_spawn_ids: Array = Array(before_audit.get("spawned_ids", []))
		var pre_killed_ids: Array = Array(before_audit.get("killed_ids", []))
		var missing_spawn_ids: Array = pre_spawn_ids.filter(func(id): return not spawn_ids.has(id))
		var missing_killed_ids: Array = pre_killed_ids.filter(func(id): return not killed_ids.has(id))
		var new_spawn_ids: Array = spawn_ids.filter(func(id): return not pre_spawn_ids.has(id))
		var new_killed_ids: Array = killed_ids.filter(func(id): return not pre_killed_ids.has(id))
		var spawn_ids_preserved := missing_spawn_ids.is_empty()
		var pre_continue_deaths_preserved := missing_killed_ids.is_empty()
		continue_wave_audit_exact = continue_wave_audit_exact and spawn_ids_preserved and pre_continue_deaths_preserved
		var expected_count := int(live_rec.get("expected_count",0))
		continue_wave_audit[wave_key] = {"spawned_before":pre_spawn_ids.size(),"spawned_after_unique":spawn_ids.size(),"killed_before":pre_killed_ids.size(),"killed_after":killed_ids.size(),"pre_continue_spawn_ids_preserved":spawn_ids_preserved,"pre_continue_deaths_preserved":pre_continue_deaths_preserved,"missing_spawn_ids":missing_spawn_ids,"missing_killed_ids":missing_killed_ids,"new_spawn_ids":new_spawn_ids,"new_killed_ids":new_killed_ids,"expected":expected_count,"expected_count_mismatch":spawn_ids.size() != expected_count}
	var villager_ref_checks: Array[Dictionary] = []
	for saved_worker in Array(checkpoint_payload.get("entities", {}).get("villagers", [])):
		var restored_worker: Variant = restored_id_map.get(str(saved_worker.get("id", "")))
		if not is_instance_valid(restored_worker): continue
		var gather_id := str(saved_worker.get("gather_id", ""))
		var build_id := str(saved_worker.get("build_id", ""))
		var gather_ok: bool = gather_id.is_empty() or restored_worker.get("gather_target") == restored_id_map.get(gather_id)
		var build_ok: bool = build_id.is_empty() or restored_worker.get("build_site") == restored_id_map.get(build_id)
		villager_ref_checks.append({"entity_id":str(saved_worker.get("id")),"gather_id":gather_id,"gather_reference_rebound":gather_ok,"build_id":build_id,"build_reference_rebound":build_ok,"state":int(restored_worker.get("state")),"resume_key":str(restored_worker.get("resume_key"))})
	var soldier_guard_checks: Array[Dictionary] = []
	for saved_unit in soldiers_data:
		if str(saved_unit.get("team", "")) != "player" or bool(saved_unit.get("is_zombie", false)): continue
		var restored_soldier: Variant = restored_id_map.get(str(saved_unit.get("id", "")))
		if not is_instance_valid(restored_soldier): continue
		guard_ordered_runtime_ids[str(restored_soldier.get_instance_id())] = true
		soldier_guard_checks.append({"entity_id":str(saved_unit.get("id")),"guard_saved":bool(saved_unit.get("guard_active",false)),"guard_restored":bool(restored_soldier.get("guard_active")),"saved_anchor":saved_unit.get("guard_anchor",[]),"restored_anchor":_v3(restored_soldier.get("guard_anchor")),"attack_saved":str(saved_unit.get("attack_id","")),"attack_rebound":str(saved_unit.get("attack_id","" )).is_empty() or restored_soldier.get("attack_target") == restored_id_map.get(str(saved_unit.get("attack_id","")))})
	old_game_id = resumed.get_instance_id()
	last_game = resumed
	_checkpoint("same_match_production_continue_completed", resumed)
	_rebuild_worker_groups_from_live_orders(resumed)
	checkpoint_continue_done = true
	events.append({"action":"same_match_continue_reconciled","saved_game_time":saved_game_time,"resumed_game_time":float(resumed.get("_game_time")),"time_delta":float(resumed.get("_game_time"))-saved_game_time,"wave":int(resumed.get("_horde_wave")),"mode":int(resumed.get("_horde_mode")),"seed":int(resumed.get("map_seed")),"stable_enemy_ids":checkpoint_entity_map.keys(),"restored_id_map_size":restored_id_map.size(),"enemy_id_rebind_exact":exact_enemy_rebind,"enemy_rebind_records":id_map_records,"wave_ledger_continue_audit":continue_wave_audit,"wave_ledger_ids_and_pre_continue_deaths_preserved":continue_wave_audit_exact,"villager_target_reference_checks":villager_ref_checks,"soldier_guard_attack_restore_checks":soldier_guard_checks,"restored_wave1_spawned_count_after_id_merge":_wave_counts("1").get("spawned",0),"rebound_player_building_handles":rebound_buildings,"barracks_handle_rebound":is_instance_valid(barracks),"route":"production title Continue Button.pressed"})

func _runtime_entity_id_map() -> Dictionary:
	var ids: Dictionary = {}
	var entity_index := 0
	for group in ["buildings", "resources", "villagers", "soldiers"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node): continue
			var runtime_id := str(node.get_instance_id())
			if ids.has(runtime_id): continue
			ids[runtime_id] = "entity_%d" % entity_index
			entity_index += 1
	return ids

func _rebuild_worker_groups_from_live_orders(game: Node) -> void:
	var food: Array = []
	var wood: Array = []
	var stone: Array = []
	var idle: Array = []
	for worker in _living_villagers():
		var target: Variant = worker.get("gather_target")
		var key := str(worker.get("resume_key"))
		if (is_instance_valid(target) and target.is_in_group("farms")) or key == "meat": food.append(worker)
		elif (is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key")) == "stone") or key == "stone": stone.append(worker)
		elif (is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key")) == "wood") or key == "wood": wood.append(worker)
		else: idle.append(worker)
	wood.append_array(idle)
	_clear_material_control_groups(game)
	_select_units(game, food)
	game.call("_assign_control_group", 3)
	_select_units(game, wood)
	game.call("_assign_control_group", 2)
	_select_units(game, stone)
	game.call("_assign_control_group", 4)
	_select_units(game, [])
	last_worker_group_living_count = _living_villagers().size()
	events.append({"action":"continue_worker_groups_rebuilt_without_order_changes","food_workers":_villager_ids(food),"wood_workers_including_idle":_villager_ids(wood),"stone_workers":_villager_ids(stone),"route":"Main control groups reconstructed from restored live targets; no unit command"})

func _issue_next_visible_attack(game: Node, reason: String = "visible_enemy_response") -> void:
	var enemies := _living_zombies()
	var army := _player_military().filter(func(unit: Node3D) -> bool: return not economy_guard_runtime_ids.has(str(unit.get_instance_id())))
	if enemies.is_empty() or army.is_empty(): return
	if army.size() < MIN_ASSAULT_GROUP_SIZE:
		var waiting_ids := _villager_ids(army)
		var signature := "%d:%s" % [int(game.get("_horde_wave")), ",".join(waiting_ids)]
		if signature != last_assault_wait_signature:
			last_assault_wait_signature = signature
			events.append({"action":"assault_waiting_for_group_assembly","game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"available_assault_units":army.size(),"minimum_group_size":MIN_ASSAULT_GROUP_SIZE,"soldiers":army.map(func(unit: Node3D) -> Dictionary: return {"name":str(unit.name),"hp":float(unit.get("hp")),"pos":_v3(unit.global_position),"guard":bool(unit.get("guard_active")),"target":str(unit.get("attack_target").name) if is_instance_valid(unit.get("attack_target")) else ""}),"live_enemies":enemies.size(),"attack_issued":false,"reason":"do not send a single paid reinforcement into a live horde; retain it near the defensive post until a three-unit assault can be issued"})
		return
	last_assault_wait_signature = ""
	campaign_command_reason = "attack order: " + reason
	var center := Vector3.ZERO
	for u in army: center += u.global_position
	center /= float(army.size())
	enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var a_priority := _enemy_threat_priority(a.get("attack_target"))
		var b_priority := _enemy_threat_priority(b.get("attack_target"))
		if a_priority != b_priority: return a_priority < b_priority
		return center.distance_squared_to(a.global_position) < center.distance_squared_to(b.global_position))
	var target: Node3D = enemies[0]
	var now := float(game.get("_game_time"))
	var last_alive := is_instance_valid(last_target) and bool(last_target.get("alive")) and float(last_target.get("hp")) > 0.0
	if last_alive and _has_active_player_order() and now - last_command_at < 12.0:
		if float(last_target.get("hp")) < last_target_hp:
			last_target_hp = float(last_target.get("hp"))
			last_target_progress_at = now
		if now - last_target_progress_at < 7.0: return
	if last_alive and target == last_target and enemies.size() > 1:
		target = enemies[1]
	var target_wave := int(target.get("horde_wave_id"))
	var target_priority := _enemy_threat_priority(target.get("attack_target"))
	if DisplayServer.get_name() == "headless":
		var hud: Node = game.get("hud")
		var command_buttons: Dictionary = hud.get("_cmd_btns") if hud != null else {}
		var attack_button: Button = command_buttons.get("attack") as Button
		# The production HUD exposes Attack only for a military selection. Refresh
		# the selection before checking the button's visibility.
		_select_units(game, army)
		if attack_button == null or not attack_button.visible:
			events.append({"action":"player_attack_command","game_time":now,"elapsed":elapsed,"reason":reason,"wave_id":target_wave,"target":str(target.name),"enemy_priority":target_priority,"enemy_attack_target":str(target.get("attack_target").name) if is_instance_valid(target.get("attack_target")) else "","army":_villager_ids(army),"excluded_economy_guard_ids":economy_guard_runtime_ids.keys(),"accepted":false,"failure":"production_hud_attack_button_unavailable"})
			return
		attack_button.pressed.emit()
		game.call("_route_pending_command", target.global_position)
		last_target = target
		last_target_hp = float(target.get("hp"))
		last_target_progress_at = float(game.get("_game_time"))
		last_command_at = float(game.get("_game_time"))
		events.append({"action":"army_attack_order","game_time":float(game.get("_game_time")),"elapsed":elapsed,"reason":reason,"wave_id":target_wave,"enemy":str(target.name),"enemy_hp":float(target.get("hp")),"enemy_position":_v3(target.global_position),"enemy_priority":target_priority,"enemy_attack_target":str(target.get("attack_target").name) if is_instance_valid(target.get("attack_target")) else "","selected_player_army":army.map(func(u): return str(u.name)),"excluded_economy_guard_ids":economy_guard_runtime_ids.keys(),"unit_targets_after_command":army.map(func(u): return str(u.get("attack_target").name) if u.get("attack_target") != null and is_instance_valid(u.get("attack_target")) else ""),"accepted":army.any(func(u): return is_instance_valid(u) and is_instance_valid(u.get("attack_target")) and u.get("attack_target") == target),"route":"production HUD Attack button + Main pending map command; assigned economy guards excluded"})
		_checkpoint("army_attack_order_wave_%d" % target_wave, game)
		return
	await _focus_world_point(game, target.global_position)
	if not _game_still_active(game) or not is_instance_valid(target) or not target.is_inside_tree() or not bool(target.get("alive")):
		events.append({"action":"attack_target_invalid_after_camera_wait","wave_id":target_wave})
		return
	var screen: Vector2 = game.get("camera").unproject_position(target.global_position + Vector3(0, 0.8, 0))
	var size := get_viewport().get_visible_rect().size
	if screen.x < 10 or screen.x >= size.x - 10 or screen.y < 50 or screen.y >= 700:
		events.append({"action":"enemy_not_clickable_on_current_camera","wave_id":target.get("horde_wave_id"),"enemy":target.name,"screen":[screen.x,screen.y],"camera_pivot":_v3(game.get("cam_pivot").position)})
		return
	await _send_key(KEY_F2)
	if not _game_still_active(game) or not is_instance_valid(target) or not target.is_inside_tree() or not bool(target.get("alive")):
		events.append({"action":"attack_target_invalid_after_selection_wait","wave_id":target_wave})
		return
	_checkpoint("army_selected_for_live_wave_command", game)
	var selected_before: Array = game.get("selected")
	var selected_names: Array[String] = []
	for u in selected_before:
		if is_instance_valid(u) and u.is_in_group("military") and str(u.get("team")) == "player": selected_names.append(str(u.name))
	await _send_key(KEY_A)
	if not _game_still_active(game) or not is_instance_valid(target) or not target.is_inside_tree() or not bool(target.get("alive")):
		events.append({"action":"attack_target_invalid_before_click","wave_id":target_wave})
		return
	var cmd_mode := str(game.get("_cmd_mode"))
	var target_name := str(target.name)
	await _click(screen, "live-wave zombie %s" % target_name)
	if not _game_still_active(game):
		events.append({"action":"game_changed_after_attack_click","wave_id":target_wave,"enemy":target_name})
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		events.append({"action":"attack_target_left_scene_tree_during_click","wave_id":target_wave,"enemy":target_name})
		return
	var targets_after: Array[String] = []
	for u in _player_military():
		var t = u.get("attack_target")
		if t != null and is_instance_valid(t): targets_after.append(str(t.name))
	last_target = target
	last_target_hp = float(target.get("hp"))
	last_target_progress_at = now
	last_command_at = now
	events.append({"action":"army_attack_order","elapsed":elapsed,"game_time":now,"wave_id":int(target.get("horde_wave_id")),"enemy":target.name,"enemy_hp":target.get("hp"),"enemy_position":_v3(target.global_position),"screen_position":[screen.x,screen.y],"selected_player_army":selected_names,"selection_count":selected_names.size(),"command_mode_before_click":cmd_mode,"viewport_input":_last_click,"unit_targets_after_click":targets_after,"clicked_inside_world_view":screen.y < 720.0})
	_checkpoint("army_attack_order_wave_%d" % int(target.get("horde_wave_id")), game)

func _enemy_threat_priority(target: Variant) -> int:
	if not is_instance_valid(target):
		return 3
	if target.is_in_group("villagers"):
		return 0
	if target.is_in_group("buildings"):
		if int(target.get("kind")) == Catalog.BARRACKS or not bool(target.get("is_complete")):
			return 1
		return 2
	return 3

func _service_combat_while_busy(game: Node) -> void:
	if phase != "defend" or bool(game.get("_defeated")) or bool(game.get("_victorious")):
		return
	if bool(game.get("_horde_active")) and _player_military().size() + _queued_player_soldiers() < _army_target_for_wave(game) and _queued_player_soldiers() == 0 and float(game.get("_game_time")) - last_army_queue_attempt_game_time >= 5.0:
		await _queue_one_reinforcement(game)
	var army := _player_military()
	var enemies := _living_zombies()
	if army.is_empty() or enemies.is_empty() or _has_active_player_order():
		return
	var now := float(game.get("_game_time"))
	if now - last_busy_combat_order_at < 3.0:
		return
	last_busy_combat_order_at = now
	events.append({"action":"busy_wave_combat_interruption","game_time":now,"elapsed":elapsed,"busy_reason":campaign_command_reason,"player_army":army.size(),"live_enemies":enemies.size(),"reason":"restore a real production attack order while a longer construction or economy action is awaiting"})
	await _issue_next_visible_attack(game, "busy_wave_no_active_player_target")

func _issue_attack_move(game: Node) -> bool:
	var enemies := _living_zombies()
	var army := _player_military()
	if enemies.is_empty() or army.is_empty():
		events.append({"action":"attack_move_deferred_no_live_target_or_army","wave_id":int(game.get("_horde_wave")),"live_enemies":enemies.size(),"player_army":army.size()})
		return false
	var target: Node3D = enemies[0]
	var target_wave := int(target.get("horde_wave_id"))
	var world_target := target.global_position + Vector3(0, 0, 7)
	if DisplayServer.get_name() == "headless":
		var before := _player_military()
		var before_names: Array[String] = before.map(func(u): return str(u.name))
		var reachability: Array[Dictionary] = []
		for unit in before:
			if unit.has_method("command_attack_move"):
				unit.call("command_attack_move", world_target)
				var route: Array = unit.get("_waypoints") if unit.get("_waypoints") is Array else []
				reachability.append({"unit":str(unit.name),"command_accepted":int(unit.get("state")) == 2,"state":int(unit.get("state")),"goal":_v3(unit.get("_goal_final")),"waypoint_count":route.size(),"position":_v3(unit.global_position),"target_distance":unit.global_position.distance_to(world_target)})
		var path_ok := reachability.filter(func(r): return bool(r.get("command_accepted")) and (int(r.get("waypoint_count")) > 0 or float(r.get("target_distance")) < 1.5)).size()
		events.append({"action":"army_attack_move_order","route":"headless logical command_attack_move","wave_id":target_wave,"selected_player_army":before_names,"world_position":_v3(world_target),"units_with_movement_order":reachability.filter(func(r): return bool(r.get("command_accepted"))).map(func(r): return r.get("unit")),"reachability_sample":reachability,"path_reachable_count":path_ok,"enemy_target":str(target.name),"enemy_position":_v3(target.global_position),"enemy_path_distance":target.global_position.distance_to(world_target)})
		_checkpoint("army_attack_move_wave_%d" % target_wave, game)
		return true
	await _focus_world_point(game, world_target)
	if not _game_still_active(game): return false
	var screen: Vector2 = game.get("camera").unproject_position(world_target)
	if screen.y < 50 or screen.y >= 700 or screen.x < 8 or screen.x >= 1592:
		events.append({"action":"attack_move_ground_not_visible","wave_id":target_wave,"world":_v3(world_target),"screen":[screen.x,screen.y]})
		return false
	await _send_key(KEY_F2)
	if not _game_still_active(game): return false
	var names: Array[String] = []
	for unit in game.get("selected"):
		if is_instance_valid(unit) and unit.is_in_group("military") and str(unit.get("team")) == "player": names.append(str(unit.name))
	await _send_key(KEY_A)
	if not _game_still_active(game): return false
	var command_mode := str(game.get("_cmd_mode"))
	await _click(screen, "attack-move ground near wave %d" % target_wave)
	if not _game_still_active(game): return false
	var move_orders: Array[String] = []
	for unit in _player_military():
		if int(unit.get("state")) == 1 or int(unit.get("state")) == 2: move_orders.append(str(unit.name))
	events.append({"action":"army_attack_move_order","wave_id":target_wave,"selected_player_army":names,"screen_position":[screen.x,screen.y],"world_position":_v3(world_target),"command_mode_before_click":command_mode,"units_with_movement_order":move_orders,"selection_count":names.size()})
	_checkpoint("army_attack_move_wave_%d" % target_wave, game)
	return true

func _focus_world_point(game: Node, world: Vector3) -> void:
	if not _game_still_active(game): return
	var cam := game.get("camera") as Camera3D
	var p := cam.unproject_position(world + Vector3(0, 0.8, 0))
	var size := get_viewport().get_visible_rect().size
	if p.x >= 8 and p.x < size.x - 8 and p.y >= 50 and p.y < 700: return
	var hud: Node = game.get("hud")
	var mini: Control = hud.get("_minimap") as Control
	if mini == null: return
	var local: Vector2 = hud.call("_world_to_mini", world, mini.size)
	await _click(mini.get_global_rect().position + local, "minimap focus on wave unit")
	await get_tree().process_frame
	if not _game_still_active(game): return
	cam = game.get("camera") as Camera3D
	if cam == null: return
	var p_after := cam.unproject_position(world + Vector3(0, 0.8, 0))
	events.append({"action":"camera_panned_to_wave_unit_by_minimap","world":_v3(world),"camera_pivot":_v3(game.get("cam_pivot").position),"screen_after":[p_after.x,p_after.y]})

func _track_runtime(game: Node) -> void:
	_normalize_enemy_ledger_ids()
	var wave := int(game.get("_horde_wave"))
	var wave_key := str(wave)
	if wave > 0 and not wave_ledger.has(wave_key):
		var live_at_entry := _living_zombies()
		var prior_wave_alive := live_at_entry.filter(func(z): return int(z.get("horde_wave_id")) < wave).size()
		var current_wave_alive := live_at_entry.filter(func(z): return int(z.get("horde_wave_id")) == wave).size()
		var pending_at_entry := int(game.get("_horde_spawn_queue").size())
		wave_ledger[wave_key] = {"wave_id":wave,"first_observed_game_time":float(game.get("_game_time")),"expected_count":int(game.call("_horde_count_for_wave", wave)),"old_wave_alive_at_entry":prior_wave_alive,"new_wave_spawned_at_first_observation":current_wave_alive,"pending_at_first_observation":pending_at_entry,"spawned":{},"killed":{},"last_alive":{},"samples":0}
		events.append({"action":"horde_wave_began","wave_id":wave,"game_time":game.get("_game_time"),"expected":int(game.call("_horde_count_for_wave", wave)),"old_wave_alive_at_entry":prior_wave_alive,"new_wave_spawned_at_first_observation":current_wave_alive,"pending_spawn_queue":pending_at_entry})
	for unit in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(unit) or not bool(unit.get("is_zombie")): continue
		var wid := str(int(unit.get("horde_wave_id")))
		var rec: Dictionary = wave_ledger.get(wid, {"wave_id":int(unit.get("horde_wave_id")),"first_observed_game_time":float(game.get("_game_time")),"expected_count":0,"spawned":{},"killed":{},"last_alive":{},"samples":0})
		var runtime_id := str(unit.get_instance_id())
		var uname := str(runtime_id_to_stable_key(runtime_id))
		var spawned: Dictionary = rec.get("spawned", {})
		var expected_for_wave := int(rec.get("expected_count", 0))
		if expected_for_wave <= 0: expected_for_wave = int(game.call("_horde_count_for_wave", int(unit.get("horde_wave_id"))))
		_record_spawn_observation(rec, uname, runtime_id, str(unit.name), float(game.get("_game_time")), float(unit.get("max_hp")), int(unit.get("horde_wave_id")), expected_for_wave)
		rec["spawned"] = spawned
		var killed: Dictionary = rec.get("killed", {})
		if not bool(unit.get("alive")) and not killed.has(uname) and spawned.has(uname):
				killed[uname] = {"game_time":float(game.get("_game_time")),"last_hp":float(unit.get("hp")),"runtime_instance_id":runtime_id}
		rec["killed"] = killed
		if bool(unit.get("alive")):
			var alive_rows: Dictionary = rec.get("last_alive", {})
			alive_rows[uname] = {"game_time":float(game.get("_game_time")),"hp":float(unit.get("hp")),"pos":_v3(unit.global_position),"target":str(unit.get("attack_target").name) if unit.get("attack_target") != null and is_instance_valid(unit.get("attack_target")) else ""}
			rec["last_alive"] = alive_rows
		wave_ledger[wid] = rec
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and str(b.get("team")) == "player":
			var key := str(b.name)
			if not building_first_hp.has(key): building_first_hp[key] = {"kind":int(b.get("kind")),"initial_hp":float(b.get("hp")),"position":_v3(b.global_position)}
	_update_wave_complete_flags(game)

func runtime_id_to_stable_key(runtime_id: String) -> String:
	return str(runtime_enemy_stable_key.get(runtime_id, runtime_id))

func _record_spawn_observation(rec: Dictionary, stable_key: String, runtime_id: String, unit_name: String, game_time: float, initial_hp: float, wave_id: int, expected_count: int) -> void:
	var spawned: Dictionary = rec.get("spawned", {})
	rec["expected_count"] = expected_count
	if spawned.has(stable_key):
		return
	spawned[stable_key] = {"stable_or_runtime_id":stable_key,"runtime_instance_id":runtime_id,"unit_name":unit_name,"first_game_time":game_time,"initial_hp":initial_hp,"checkpoint_entity_id":str(runtime_enemy_stable_key.get(runtime_id,""))}
	rec["spawned"] = spawned
	if spawned.size() > expected_count:
		events.append({"action":"wave_enemy_count_exceeds_expected_audit","wave_id":wave_id,"expected_count":expected_count,"observed_unique_count":spawned.size(),"runtime_id":runtime_id,"stable_key":stable_key,"checkpoint_entity_id":str(runtime_enemy_stable_key.get(runtime_id,"")),"game_time":game_time,"counted_in_spawn_ledger":true,"acceptance_status":"explicit_failure_expected_count_audit"})

func _normalize_enemy_ledger_ids() -> void:
	var moved := 0
	var merged := 0
	for wave_key in wave_ledger.keys():
		var rec: Dictionary = wave_ledger[wave_key]
		for field in ["spawned", "killed", "last_alive"]:
			var old_rows: Dictionary = rec.get(field, {})
			var normalized: Dictionary = {}
			for old_key in old_rows.keys():
				var stable_key := runtime_id_to_stable_key(str(old_key))
				if stable_key != str(old_key): moved += 1
				var value: Dictionary = old_rows[old_key]
				if not normalized.has(stable_key):
					normalized[stable_key] = value
				else:
					merged += 1
					var kept: Dictionary = normalized[stable_key]
					if field == "spawned":
						if float(value.get("first_game_time", INF)) < float(kept.get("first_game_time", INF)):
							var runtime_after: Variant = kept.get("runtime_instance_id_after_continue", "")
							kept = value.duplicate(true)
							if not str(runtime_after).is_empty(): kept["runtime_instance_id_after_continue"] = runtime_after
					elif field == "killed":
						# Preserve the first observed genuine death if aliases collapse.
						if float(value.get("game_time", INF)) < float(kept.get("game_time", INF)): kept = value.duplicate(true)
					elif field == "last_alive":
						if float(value.get("game_time", -INF)) > float(kept.get("game_time", -INF)): kept = value.duplicate(true)
					normalized[stable_key] = kept
			rec[field] = normalized
		wave_ledger[wave_key] = rec
	if moved > 0 or merged > 0:
		var wave_counts_after_normalization := {}
		for normalized_wave in wave_ledger.keys():
			var normalized_rec: Dictionary = wave_ledger[normalized_wave]
			wave_counts_after_normalization[str(normalized_wave)] = {"spawned":(normalized_rec.get("spawned", {}) as Dictionary).size(),"killed":(normalized_rec.get("killed", {}) as Dictionary).size()}
		events.append({"action":"wave_ledger_runtime_ids_normalized_to_serialized_ids","moved_key_occurrences":moved,"merged_key_occurrences":merged,"wave_spawn_kill_counts":wave_counts_after_normalization,"deaths_preserved":true,"restore_removals_counted_as_deaths":false})

func _update_wave_complete_flags(game: Node) -> void:
	for key in wave_ledger.keys():
		var rec: Dictionary = wave_ledger[key]
		var alive_n := 0
		var spawned: Dictionary = rec.get("spawned", {})
		var killed: Dictionary = rec.get("killed", {})
		for row in get_tree().get_nodes_in_group("zombies"):
			if is_instance_valid(row) and int(row.get("horde_wave_id")) == int(key) and bool(row.get("alive")):
				alive_n += 1
		var pending := 0
		if int(game.get("_horde_wave")) == int(key): pending = game.get("_horde_spawn_queue").size()
		rec["alive_count"] = alive_n
		rec["pending_count"] = pending
		rec["killed_count"] = killed.size()
		rec["spawned_count"] = spawned.size()
		rec["complete"] = spawned.size() >= int(rec.get("expected_count", 0)) and alive_n == 0 and pending == 0
		wave_ledger[key] = rec

func _freeze_terminal_state(game: Node) -> void:
	if not terminal_snapshot.is_empty(): return
	var captured := _snapshot(game)
	var required_fields := ["game_time", "map_seed", "army", "zombies", "buildings", "wave_records"]
	for field in required_fields:
		if not captured.has(field):
			events.append({"action":"terminal_snapshot_validation_failed","missing_field":field,"game_time":float(game.get("_game_time"))})
			return
	if not (captured.get("wave_records") is Dictionary) or not (captured.get("army") is Array) or not (captured.get("zombies") is Array):
		events.append({"action":"terminal_snapshot_validation_failed","reason":"invalid_terminal_collection_type","game_time":float(game.get("_game_time"))})
		return
	terminal_snapshot = captured
	terminal_wave_ledger = terminal_snapshot.get("wave_records", {}).duplicate(true)
	terminal_combat_summary = _combat_summary(terminal_snapshot)
	events.append({"action":"terminal_battle_state_frozen","map_seed":int(game.get("map_seed")),"game_time":float(game.get("_game_time")),"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious")),"live_enemies":terminal_snapshot.get("zombies", []).size(),"wave_records":terminal_wave_ledger.duplicate(true)})

func _sample_combat(game: Node) -> void:
	sample_clock += get_process_delta_time()
	if sample_clock < 0.5: return
	sample_clock = 0.0
	var army: Array[Dictionary] = []
	for u in _player_military(): army.append({"name":u.name,"hp":float(u.get("hp")),"max_hp":float(u.get("max_hp")),"pos":_v3(u.global_position),"state":int(u.get("state")),"target":str(u.get("attack_target").name) if u.get("attack_target") != null and is_instance_valid(u.get("attack_target")) else ""})
	var enemies: Array[Dictionary] = []
	for z in _living_zombies():
		var wave_key := str(int(z.get("horde_wave_id")))
		if float(z.get("hp")) < float(z.get("max_hp")) and not contact_checkpointed.has(wave_key):
			contact_checkpointed[wave_key] = true
			_checkpoint("live_combat_contact_wave_%s" % wave_key, game)
		enemies.append({"name":z.name,"wave_id":int(z.get("horde_wave_id")),"hp":float(z.get("hp")),"max_hp":float(z.get("max_hp")),"pos":_v3(z.global_position),"target":str(z.get("attack_target").name) if z.get("attack_target") != null and is_instance_valid(z.get("attack_target")) else ""})
	var buildings: Array[Dictionary] = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and str(b.get("team")) == "player": buildings.append({"name":b.name,"kind":int(b.get("kind")),"hp":float(b.get("hp")),"max_hp":float(b.get("max_hp")),"complete":bool(b.get("is_complete")),"pos":_v3(b.global_position)})
	combat_samples.append({"elapsed":elapsed,"game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"pending":game.get("_horde_spawn_queue").size(),"army":army,"enemies":enemies,"buildings":buildings,"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious"))})
	if combat_samples.size() % 40 == 0: _persist()

func _combat_summary(final_snapshot: Dictionary = {}) -> Dictionary:
	if combat_samples.is_empty(): return {"available":false}
	var first: Dictionary = combat_samples.front()
	var last: Dictionary = combat_samples.back()
	var final_army: Array = final_snapshot.get("army", last.get("army", []))
	var final_buildings: Array = final_snapshot.get("buildings", last.get("buildings", []))
	var final_enemies: Array = final_snapshot.get("zombies", last.get("enemies", []))
	var start_hp := {}
	var end_hp := {}
	for u in first.get("army",[]): start_hp[str(u.get("name"))] = float(u.get("hp"))
	for u in final_army: end_hp[str(u.get("name"))] = float(u.get("hp"))
	var survivor_loss := 0.0
	for name in start_hp:
		if end_hp.has(name): survivor_loss += maxf(0.0, start_hp[name] - end_hp[name])
	return {"samples":combat_samples.size(),"sampling_interval_seconds":0.5,"game_time_start":first.get("game_time"),"game_time_end":final_snapshot.get("game_time", last.get("game_time")),"army_start":start_hp.size(),"army_end":end_hp.size(),"army_hp_loss_for_survivors":survivor_loss,"army_names_lost":start_hp.keys().filter(func(n): return not end_hp.has(n)),"wave_records":terminal_wave_ledger if not terminal_wave_ledger.is_empty() else wave_ledger,"buildings_initial_hp":building_first_hp.duplicate(true),"buildings_end":final_buildings,"enemies_end":final_enemies,"defeated":final_snapshot.get("defeated", last.get("defeated")),"victorious":final_snapshot.get("victorious", last.get("victorious")),"result_snapshot_frozen":not final_snapshot.is_empty()}

func _order_nearest_resource(game: Node, kind: int, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		var workers: Array = _control_group_units(game, 2) if kind == ResourceNode3D.Kind.WOOD else _control_group_units(game, 4) if kind == ResourceNode3D.Kind.STONE else _living_villagers()
		workers = workers.filter(func(worker: Node3D) -> bool: return not evacuated_worker_ids.has(str(worker.get_instance_id())))
		if workers.is_empty() and kind == ResourceNode3D.Kind.STONE:
			var wood_group := _control_group_units(game, 2).filter(func(worker: Node3D) -> bool: return not evacuated_worker_ids.has(str(worker.get_instance_id())))
			if not wood_group.is_empty(): workers = [wood_group.back()]
		if workers.is_empty() and kind != ResourceNode3D.Kind.STONE: workers = _living_villagers()
		if workers.is_empty() and kind == ResourceNode3D.Kind.STONE:
			events.append({"action":"resource_gather_order_deferred_no_stone_role","kind":kind,"label":label,"reason":"no stone-group worker; preserve food and tower-wood assignments"})
			return
		var target := _nearest_resource(kind)
		if target == null:
			_finish(false, "resource_node_missing_%d" % kind)
			return
		_issue_gather_order(game, workers, target, label)
		return
	if kind == ResourceNode3D.Kind.WOOD and _living_villagers().size() >= 2:
		await _send_key(KEY_2)
	else:
		await _ensure_villager_selection(game)
	await _send_key(KEY_G)
	var node := _nearest_resource(kind)
	if node == null:
		_finish(false, "resource_node_missing_%d" % kind)
		return
	await _click_world(game, node.global_position + Vector3(0, 0.7, 0), label)
	events.append({"action":"resource_gather_order","kind":kind,"resource":node.name,"position":_v3(node.global_position),"selected_villagers":game.get("selected").size(),"population":game.get("population"),"pop_cap":game.get("pop_cap")})

func _service_tower_materials(game: Node) -> void:
	var living := _living_villagers()
	if living.is_empty():
		return
	if DisplayServer.get_name() == "headless" and living.size() != last_worker_group_living_count:
		_rebalance_live_worker_groups(game, living)
	if living.size() < 2:
		return
	var wave := int(game.get("_horde_wave"))
	var tower_needed := (bool(_wave_counts("1").get("complete", false)) and not _farm_is_live(tower2)) or (wave >= 2 and (not _farm_is_live(tower3) or not _farm_is_live(tower4))) or (wave >= 3 and not _farm_is_live(tower5))
	if not tower_needed or _live_player_farms().is_empty() or int(game.get("meat")) < 60:
		_release_excess_stone_workers(game, "no eligible extra-tower budget; protect farm and soldier reserves")
		return
	if DisplayServer.get_name() == "headless":
		var wood_workers := _control_group_units(game, 2)
		var stone_workers := _control_group_units(game, 4)
		var need_wood := int(game.get("wood")) < 195
		var need_stone := int(game.get("stone")) < 50
		if need_wood and need_stone and (wood_workers.is_empty() or stone_workers.is_empty()):
			var wood_ratio := float(game.get("wood")) / 100.0
			var stone_ratio := float(game.get("stone")) / 50.0
			if stone_ratio <= wood_ratio: need_wood = false
			else: need_stone = false
		if need_wood and not wood_workers.is_empty() and not _group_gathering_resource(wood_workers, "wood"):
			var wood_node := _nearest_resource(ResourceNode3D.Kind.WOOD)
			if wood_node != null:
				for worker in wood_workers:
					if worker.has_method("command_gather"): worker.call("command_gather", wood_node)
				events.append({"action":"tower_material_gather_order","wave":wave,"resource":"wood","group":2,"selected_villagers":wood_workers.size(),"wood":game.get("wood"),"stone":game.get("stone"),"target":wood_node.name,"headless_direct_unit_commands":true})
		if need_stone:
			var actual_stone_workers := stone_workers if not stone_workers.is_empty() else wood_workers
			var stone_group_index := 4 if not stone_workers.is_empty() else 2
			if not actual_stone_workers.is_empty() and not _group_gathering_resource(actual_stone_workers, "stone"):
				var stone_node := _nearest_resource(ResourceNode3D.Kind.STONE)
				if stone_node != null:
					for worker in actual_stone_workers:
						if worker.has_method("command_gather"): worker.call("command_gather", stone_node)
					events.append({"action":"tower_material_gather_order","wave":wave,"resource":"stone","group":stone_group_index,"selected_villagers":actual_stone_workers.size(),"wood":game.get("wood"),"stone":game.get("stone"),"target":stone_node.name,"reason":"one planned extra tower; stop at 50 stone","headless_direct_unit_commands":true})
		else:
			_release_excess_stone_workers(game, "50 stone reached for one planned extra tower")
		return
	if elapsed - last_tower_material_order_at < 12.0:
		return
	if int(game.get("wood")) >= 100 and int(game.get("stone")) >= 50:
		return
	var resource_kind := ResourceNode3D.Kind.WOOD if int(game.get("wood")) < 100 else ResourceNode3D.Kind.STONE
	var resource := _nearest_resource(resource_kind)
	if resource == null:
		return
	var resource_name := "wood" if resource_kind == ResourceNode3D.Kind.WOOD else "stone"
	if _group_gathering_resource(_control_group_units(game, 2), resource_name):
		return
	await _send_key(KEY_2)
	if game.get("selected").is_empty():
		return
	await _send_key(KEY_G)
	await _click_world(game, resource.global_position + Vector3(0, 0.7, 0), "tower material reserve")
	last_tower_material_order_at = elapsed
	events.append({"action":"tower_material_gather_order","wave":wave,"resource":"wood" if resource_kind == ResourceNode3D.Kind.WOOD else "stone","group":2,"selected_villagers":game.get("selected").size(),"wood":game.get("wood"),"stone":game.get("stone"),"target":resource.name})

func _release_excess_stone_workers(game: Node, reason: String) -> void:
	var stone_workers := _control_group_units(game, 4)
	if stone_workers.is_empty(): return
	var farms := _live_player_farms()
	var destination: Node3D = _safest_live_farm() if not farms.is_empty() and int(game.get("meat")) < 60 else _nearest_resource(ResourceNode3D.Kind.WOOD)
	var destination_kind := "food" if not farms.is_empty() and int(game.get("meat")) < 60 else "wood"
	if destination == null: return
	var changed: Array[String] = []
	for worker in stone_workers:
		var current: Variant = worker.get("gather_target")
		if is_instance_valid(current) and current == destination: continue
		if worker.has_method("command_gather"):
			worker.call("command_gather", destination)
			changed.append(str(worker.name))
	if not changed.is_empty():
		campaign_command_reason = reason
		events.append({"action":"excess_stone_workers_reassigned","reason":reason,"destination":destination_kind,"workers":changed,"stone":int(game.get("stone")),"wood":int(game.get("wood")),"meat":int(game.get("meat"))})

func _ensure_villager_selection(game: Node) -> void:
	var living := _living_villagers()
	if DisplayServer.get_name() == "headless":
		_select_units(game, living)
		return
	var selected: Array = game.get("selected")
	var n := selected.filter(func(v): return is_instance_valid(v) and v.is_in_group("villagers") and str(v.get("team")) == "player").size()
	if n >= living.size(): return
	await _send_key(KEY_2)
	selected = game.get("selected")
	n = selected.filter(func(v): return is_instance_valid(v) and v.is_in_group("villagers") and str(v.get("team")) == "player").size()
	if n >= living.size(): return
	await _send_key(KEY_F3)
	selected = game.get("selected")
	n = selected.filter(func(v): return is_instance_valid(v) and v.is_in_group("villagers") and str(v.get("team")) == "player").size()
	if n < living.size(): await _drag_select_villagers(game)
	selected = game.get("selected")
	n = selected.filter(func(v): return is_instance_valid(v) and v.is_in_group("villagers") and str(v.get("team")) == "player").size()
	events.append({"action":"villager_selection_for_order","selected":n,"living":living.size(),"route":"F3 plus visible drag selection if needed"})

func _select_units(game: Node, units: Array) -> void:
	game.call("_clear_selection")
	for unit in units:
		if is_instance_valid(unit) and unit.is_inside_tree(): game.call("_add_to_selection", unit)
	game.call("_refresh_selection_hud")

func _control_group_units(game: Node, index: int) -> Array:
	var groups: Array = game.get("_control_groups")
	if index < 0 or index >= groups.size(): return []
	var result: Array = []
	for unit in groups[index]:
		if is_instance_valid(unit) and unit.is_inside_tree() and bool(unit.get("alive")): result.append(unit)
	return result

func _group_gathering_resource(units: Array, resource_key: String) -> bool:
	if units.is_empty(): return false
	for unit in units:
		var target = unit.get("gather_target")
		if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.has_method("res_key") or str(target.call("res_key")) != resource_key:
			return false
	return true

func _drag_select_villagers(game: Node) -> void:
	var cam := game.get("camera") as Camera3D
	var pts: Array[Vector2] = []
	for v in _living_villagers():
		var p := cam.unproject_position(v.global_position + Vector3(0, 0.9, 0))
		if p.x >= 0 and p.x < 1600 and p.y >= 0 and p.y < 715: pts.append(p)
	if pts.size() < 2: return
	var lo := Vector2(1600, 715)
	var hi := Vector2.ZERO
	for p in pts:
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.y)
	lo = (lo - Vector2(18, 18)).clamp(Vector2.ZERO, Vector2(1599, 714))
	hi = (hi + Vector2(18, 18)).clamp(Vector2.ZERO, Vector2(1599, 714))
	await _drag(lo, hi, "visible villagers selection box")

func _nearest_resource(kind: int) -> Node3D:
	var best: Node3D
	var distance := INF
	for r in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(r) or r.is_in_group("buildings") or int(r.get("kind")) != kind or int(r.get("amount")) <= 0: continue
		var d := Vector2(r.global_position.x, r.global_position.z).length()
		if d < distance: distance = d; best = r as Node3D
	return best

func _new_building(kind: int, old_ids: Dictionary) -> Node3D:
	var best: Node3D
	var nearest := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.get("kind")) != kind or old_ids.has(str(b.get_instance_id())): continue
		var d := Vector2(b.global_position.x, b.global_position.z).length()
		if d < nearest: nearest = d; best = b as Node3D
	return best

func _building_ids(kind: int) -> Dictionary:
	var ids := {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.get("kind")) == kind: ids[str(b.get_instance_id())] = true
	return ids

func _button(root: Node, text: String) -> Button:
	if root == null: return null
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text.contains(text): return b
	return null

func _living_villagers() -> Array:
	return get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and v.is_inside_tree() and v.get("alive") == true and float(v.get("hp")) > 0.0 and str(v.get("team")) == "player")

func _player_military() -> Array:
	return get_tree().get_nodes_in_group("military").filter(func(u): return is_instance_valid(u) and bool(u.get("alive")) and str(u.get("team")) == "player")

func _living_zombies() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z): return is_instance_valid(z) and bool(z.get("alive")) and float(z.get("hp")) > 0.0)

func _check_enemy_progress_stall(game: Node) -> bool:
	if elapsed - enemy_watch_last_sample < 5.0: return false
	enemy_watch_last_sample = elapsed
	var live_ids: Dictionary = {}
	var stalled: Array[Dictionary] = []
	for enemy in _living_zombies():
		var key := str(enemy.get_instance_id())
		live_ids[key] = true
		var target = enemy.get("attack_target")
		var target_id := ""
		var target_hp := -1.0
		if target != null and is_instance_valid(target) and target.is_inside_tree() and str(target.get("team")) == "player" and target.get("alive") != false and (target.get("hp") == null or float(target.get("hp")) > 0.0):
			target_id = str(target.get_instance_id())
			if target.get("hp") != null: target_hp = float(target.get("hp"))
		var position: Vector3 = enemy.global_position
		if not enemy_progress_watch.has(key):
			enemy_progress_watch[key] = {"position":position,"target_id":target_id,"target_hp":target_hp,"since":elapsed}
			continue
		var previous: Dictionary = enemy_progress_watch[key]
		var previous_position: Vector3 = previous.get("position", position)
		var moved := position.distance_to(previous_position) >= 0.35
		var damaged_target := target_id != "" and target_id == str(previous.get("target_id", "")) and target_hp >= 0.0 and target_hp < float(previous.get("target_hp", target_hp)) - 0.1
		var changed_target := target_id != str(previous.get("target_id", ""))
		if moved or damaged_target or changed_target:
			enemy_progress_watch[key] = {"position":position,"target_id":target_id,"target_hp":target_hp,"since":elapsed}
			continue
		previous["position"] = position
		if target_hp >= 0.0: previous["target_hp"] = target_hp
		if elapsed - float(previous.get("since", elapsed)) >= 45.0:
			stalled.append({"enemy":str(enemy.name),"wave":int(enemy.get("horde_wave_id")),"position":_v3(position),"target":target_id,"target_hp":target_hp,"stalled_seconds":elapsed-float(previous.get("since", elapsed))})
	for key in enemy_progress_watch.keys():
		if not live_ids.has(key): enemy_progress_watch.erase(key)
	if stalled.is_empty(): return false
	events.append({"action":"enemy_ai_stall_detected","game_time":float(game.get("_game_time")),"elapsed":elapsed,"stalled_enemies":stalled.size(),"samples":stalled.slice(0, 8),"player_buildings":_player_building_snapshot()})
	# Treat this as an observation, not a terminal result. Some enemies stop at
	# building contact while the player army is still engaging them; ending here
	# hid the real wave outcome in the controlled run. Reset the watch window and
	# let the ordinary attack and defense loop continue.
	for sample in stalled:
		var key := str(sample.get("enemy", ""))
		for enemy in _living_zombies():
			if str(enemy.name) == key:
				enemy_progress_watch[str(enemy.get_instance_id())]["since"] = elapsed
				break
	return false

func _player_building_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team")) == "player":
			result.append({"name":str(building.name),"kind":building.get("kind"),"alive":building.get("alive"),"complete":building.get("is_complete"),"hp":building.get("hp"),"position":_v3(building.global_position)})
	return result

func _train_queue(building: Node) -> Array:
	return Array(building.get("train_queue")) if is_instance_valid(building) else []

func _queued_player_villagers() -> int:
	var queued := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or str(building.get("team")) != "player":
			continue
		for unit_type in _train_queue(building):
			if str(unit_type) == "villager": queued += 1
	return queued

func _has_active_player_order() -> bool:
	for u in _player_military():
		var target = u.get("attack_target")
		if target != null and is_instance_valid(target) and bool(target.get("alive")) and float(target.get("hp")) > 0.0: return true
	return false

func _wave_counts(key: String) -> Dictionary:
	var rec: Dictionary = wave_ledger.get(key, {})
	var spawned: Dictionary = rec.get("spawned", {})
	var killed: Dictionary = rec.get("killed", {})
	return {"wave_id":int(key),"old_wave_alive_at_entry":int(rec.get("old_wave_alive_at_entry", 0)),"new_wave_spawned_at_first_observation":int(rec.get("new_wave_spawned_at_first_observation", 0)),"pending_at_first_observation":int(rec.get("pending_at_first_observation", 0)),"spawned":spawned.size(),"killed":killed.size(),"alive":int(rec.get("alive_count", 0)),"pending":int(rec.get("pending_count", 0)),"expected":int(rec.get("expected_count", 0)),"complete":bool(rec.get("complete", false)),"completion_checkpoint":bool(rec.get("completion_checkpoint", false))}

func _alert_button_for_target(hud: Node, target: Node3D) -> Button:
	if hud == null or not is_instance_valid(target): return null
	var rows: VBoxContainer = hud.get("_operational_rows") as VBoxContainer
	if rows == null: return null
	for row in rows.get_children():
		if row.get_child_count() < 2: continue
		var button := row.get_child(1) as Button
		# Some operational rows are location-only and intentionally have no target
		# metadata. Skip them before reading the target metadata key.
		if button != null and button.has_meta("operational_alert_target") and button.get_meta("operational_alert_target") == target: return button
	return null

func _defeat_panel_ready(game: Node) -> bool:
	var hud: Node = game.get("hud")
	var panel: Control = hud.get("_defeat_panel") as Control if hud != null else null
	return panel != null and panel.visible

func _retry_snapshot(game: Node) -> Dictionary:
	var buildings: Array = get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and str(b.get("team")) == "player" and bool(b.get("alive")))
	var tc := buildings.filter(func(b): return int(b.get("kind")) == Catalog.TOWN_CENTER)
	var zombies := _living_zombies()
	var frozen_old_match := not terminal_snapshot.is_empty() and int(terminal_snapshot.get("map_seed", -1)) == defeat_seed and not terminal_wave_ledger.is_empty()
	var valid := frozen_old_match and bool(game.get("_match_started")) and not bool(game.get("_defeated")) and int(game.get("map_seed")) != defeat_seed and int(game.get("wood")) == 0 and int(game.get("meat")) == 50 and _living_villagers().size() == 5 and tc.size() == 1 and zombies.is_empty()
	return {"valid":valid,"old_match_snapshot_frozen":frozen_old_match,"match_started":game.get("_match_started"),"defeated":game.get("_defeated"),"new_seed":game.get("map_seed"),"wood":game.get("wood"),"meat":game.get("meat"),"villagers":_living_villagers().size(),"town_center_count":tc.size(),"town_center_hp":float(tc[0].get("hp")) if not tc.is_empty() else 0.0,"zombies":zombies.size(),"mode":game.get("_horde_mode"),"wave":game.get("_horde_wave")}

func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _checkpoint(label: String, game: Node) -> void:
	var seq := checkpoints.size() + 1
	var snapshot := _snapshot(game)
	var snapshot_valid := snapshot.has("game_time") and snapshot.has("map_seed") and snapshot.has("army") and snapshot.has("zombies") and snapshot.has("buildings") and snapshot.has("wave_records")
	if not snapshot_valid:
		events.append({"action":"checkpoint_snapshot_validation_failed","checkpoint":label,"seq":seq})
	checkpoints.append({"seq":seq,"name":label,"elapsed":elapsed,"snapshot_valid":snapshot_valid,"snapshot":snapshot})
	_persist()

func _snapshot(game: Node) -> Dictionary:
	var pbuildings: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and str(b.get("team")) == "player": pbuildings.append({"name":b.name,"kind":int(b.get("kind")),"hp":float(b.get("hp")),"max_hp":float(b.get("max_hp")),"complete":bool(b.get("is_complete")),"pos":_v3(b.global_position)})
	var live_zombies: Array[Dictionary] = []
	for z in _living_zombies():
		live_zombies.append({"name":str(z.name),"wave_id":int(z.get("horde_wave_id")),"hp":float(z.get("hp")),"pos":_v3(z.global_position),"target":str(z.get("attack_target").name) if z.get("attack_target") != null and is_instance_valid(z.get("attack_target")) else ""})
	var wave_records: Dictionary = {}
	for raw_key in wave_ledger.keys():
		var key := str(raw_key)
		var record: Dictionary = (wave_ledger[raw_key] as Dictionary).duplicate(true)
		var spawned: Dictionary = record.get("spawned", {})
		var live_count := live_zombies.filter(func(z): return int(z.get("wave_id")) == int(key)).size()
		var pending := int(game.get("_horde_spawn_queue").size()) if int(game.get("_horde_wave")) == int(key) else 0
		var killed_count := maxi(int(record.get("killed_count", 0)), maxi(0, spawned.size() - live_count))
		record["spawned_count"] = spawned.size()
		record["killed_count"] = killed_count
		record["alive_count"] = live_count
		record["pending_count"] = pending
		record["complete"] = spawned.size() >= int(record.get("expected_count", 0)) and live_count == 0 and pending == 0
		wave_records[key] = record
	var player_army: Array = _player_military().map(func(u): return {"name":u.name,"hp":float(u.get("hp")),"pos":_v3(u.global_position),"state":int(u.get("state")),"target":str(u.get("attack_target").name) if u.get("attack_target") != null and is_instance_valid(u.get("attack_target")) else ""})
	return {"game_time":game.get("_game_time"),"clock_minutes":game.get("_clock_minutes"),"map_seed":game.get("map_seed"),"mode":game.get("_horde_mode"),"wave":game.get("_horde_wave"),"wave_active":game.get("_horde_active"),"pending_spawns":game.get("_horde_spawn_queue").size(),"wave_counts":_wave_counts("1"),"wave_records":wave_records,"wood":game.get("wood"),"meat":game.get("meat"),"stone":game.get("stone"),"population":game.get("population"),"queued_pop":game.call("_queued_pop"),"pop_cap":game.get("pop_cap"),"villagers":_living_villagers().size(),"army":player_army,"zombies":live_zombies,"buildings":pbuildings,"defeated":game.get("_defeated"),"victorious":game.get("_victorious"),"defeat_panel_visible":_defeat_panel_ready(game)}

func _hud_message(hud: Node) -> String:
	if hud == null: return ""
	var label: Variant = hud.get("_msg_l")
	return str(label.text) if label is Label else ""

var _last_click: Dictionary = {}

func _click_control(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		events.append({"action":"control_click_skipped","reason":"target_not_in_scene_tree"})
		return
	await get_tree().process_frame
	if not is_instance_valid(control) or not control.is_inside_tree():
		events.append({"action":"control_click_skipped","reason":"target_left_scene_tree_during_wait"})
		return
	var control_path := str(control.get_path())
	var click_position := control.get_global_rect().get_center()
	await _click(click_position, control_path)

func _click_world(game: Node, world: Vector3, label: String) -> void:
	if not _game_still_active(game): return
	await _focus_world_point(game, world)
	if not _game_still_active(game): return
	var cam := game.get("camera") as Camera3D
	if cam == null: return
	await _click(cam.unproject_position(world), label)

func _shift_click_world(game: Node, world: Vector3, label: String) -> void:
	if not _game_still_active(game): return
	await _focus_world_point(game, world)
	var cam := game.get("camera") as Camera3D
	if cam == null: return
	var point := cam.unproject_position(world)
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.physical_keycode = KEY_SHIFT
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hover := get_viewport().gui_get_hovered_control()
	var hover_path := str(hover.get_path()) if is_instance_valid(hover) and hover.is_inside_tree() else ""
	var selected_before := _villager_ids(game.get("selected"))
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.shift_pressed = true
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame
	_last_shift_click = {"route":"Viewport.push_input mouse","target":label,"position":[point.x,point.y],"hovered_control":hover_path,"selected_before":selected_before,"selected_after":_villager_ids(game.get("selected"))}
	events.append({"action":"shift_click_world"}.merged(_last_shift_click))
	key = key.duplicate() as InputEventKey
	key.pressed = false
	get_viewport().push_input(key)
	await get_tree().process_frame

func _game_still_active(game: Node) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and get_tree().get_first_node_in_group("main_game") == game

func _click(p: Vector2, label: String) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = p; motion.global_position = p
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hover := get_viewport().gui_get_hovered_control()
	var hover_path := ""
	if is_instance_valid(hover) and hover.is_inside_tree(): hover_path = str(hover.get_path())
	var down := InputEventMouseButton.new(); down.position = p; down.global_position = p; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton; up.pressed = false; get_viewport().push_input(up)
	await get_tree().process_frame
	_last_click = {"route":"Viewport.push_input mouse","target":label,"position":[p.x,p.y],"hovered_control":hover_path}
	events.append(_last_click.duplicate(true))

func _drag(a: Vector2, b: Vector2, label: String) -> void:
	var m0 := InputEventMouseMotion.new(); m0.position = a; m0.global_position = a; get_viewport().push_input(m0)
	await get_tree().process_frame
	var down := InputEventMouseButton.new(); down.position = a; down.global_position = a; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; get_viewport().push_input(down)
	await get_tree().process_frame
	var move := InputEventMouseMotion.new(); move.position = b; move.global_position = b; move.button_mask = MOUSE_BUTTON_MASK_LEFT; get_viewport().push_input(move)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton; up.position = b; up.global_position = b; up.pressed = false; get_viewport().push_input(up)
	await get_tree().process_frame
	events.append({"action":"viewport_drag_selection","label":label,"from":[a.x,a.y],"to":[b.x,b.y]})

func _send_key(code: int, unicode_value: int = 0, control: bool = false) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.unicode = unicode_value; e.ctrl_pressed = control; e.pressed = true
	get_viewport().push_input(e); await get_tree().process_frame
	e = e.duplicate() as InputEventKey; e.pressed = false; get_viewport().push_input(e); await get_tree().process_frame

func _build_bounded_trace_snapshot(game: Node) -> Dictionary:
	var workers: Array[Dictionary] = []
	for worker in _living_villagers():
		var goal: Variant = worker.get("_goal_final")
		var target: Variant = worker.get("gather_target")
		workers.append({"name":str(worker.name),"runtime_id":str(worker.get_instance_id()),"hp":float(worker.get("hp")),"position":_v3(worker.global_position),"state":int(worker.get("state")),"goal":_v3(goal) if goal is Vector3 else [],"gather_target":str(target.name) if is_instance_valid(target) else "","resume_key":str(worker.get("resume_key")),"carry_key":str(worker.get("carry_key")),"carry":int(worker.get("carry_amount"))})
	var enemies: Array[Dictionary] = []
	for enemy in _living_zombies():
		var target: Variant = enemy.get("attack_target")
		enemies.append({"name":str(enemy.name),"runtime_id":str(enemy.get_instance_id()),"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position),"target":str(target.name) if is_instance_valid(target) else "","target_runtime_id":str(target.get_instance_id()) if is_instance_valid(target) else ""})
	var guards: Array[Dictionary] = []
	for unit in get_tree().get_nodes_in_group("military"):
		if is_instance_valid(unit) and bool(unit.get("alive")):
			var target: Variant = unit.get("attack_target")
			guards.append({"name":str(unit.name),"runtime_id":str(unit.get_instance_id()),"position":_v3(unit.global_position),"state":int(unit.get("state")),"guard_active":bool(unit.get("guard_active")),"target":str(target.name) if is_instance_valid(target) else ""})
	return {"game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"resources":{"wood":int(game.get("wood")),"food":int(game.get("meat")),"stone":int(game.get("stone"))},"workers":workers,"enemies":enemies,"army":guards,"pending_evacuees":evacuated_worker_ids.duplicate(true),"defeated":bool(game.get("_defeated")),"victorious":bool(game.get("_victorious"))}

func _persist() -> void:
	var mode_id := int(terminal_snapshot.get("mode", last_game.get("_horde_mode") if is_instance_valid(last_game) else -1))
	var mode_label := "challenge5" if mode_id == 1 else "endless" if mode_id == 0 else "unknown"
	var data := {"schema":8,"run_id":run_id,"runtime":_runtime_metadata(),"mode":mode_label,"mode_id":mode_id,"done":done,"success":done and bool(events.back().get("success", false)),"phase":phase,"elapsed":elapsed,"events":events,"checkpoints":checkpoints,"wave_ledger":terminal_wave_ledger if not terminal_wave_ledger.is_empty() else wave_ledger,"wave_ledger_live":wave_ledger if terminal_snapshot.is_empty() else {},"terminal_snapshot":terminal_snapshot,"bounded_cutoff_snapshot":terminal_snapshot if terminal_snapshot.has("bounded_cutoff_game_time") else {},"combat_sample_count":combat_samples.size(),"campaign_observer_file":OBSERVER_PATH,"campaign_observer_samples":campaign_observer_samples,"combat_summary":terminal_combat_summary if not terminal_combat_summary.is_empty() else _combat_summary(),"save_state":"user-driven production rules; no injected resources, units, damage, or enemy removals"}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(data, "\t")); f.close()

func _runtime_metadata() -> Dictionary:
	return {"run_id":run_id,"started_at_utc":started_at_utc,"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_data_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name() == "headless","time_scale":Engine.time_scale,"expected_seed":42,"expected_mode_id":1 if Engine.has_meta("aoelite_challenge5_run") else 0,"post_challenge_endless_followup":post_challenge_endless_followup}

func _finish(ok: bool, reason: String) -> void:
	if done: return
	done = true
	events.append({"action":"finish","success":ok,"reason":reason,"elapsed":elapsed,"wave_ledger":terminal_wave_ledger if not terminal_wave_ledger.is_empty() else wave_ledger,"terminal_snapshot":terminal_snapshot,"combat_summary":terminal_combat_summary if not terminal_combat_summary.is_empty() else _combat_summary()})
	_persist()
	# Keep the result panel visible long enough for the external isolated-window
	# harness to capture and hash the final checkpoints before the process exits.
	await get_tree().create_timer(8.0).timeout
	get_tree().quit()
