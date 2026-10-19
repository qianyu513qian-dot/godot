extends Node
## Bounded Continue identity test against a copied production Challenge 5 save.
const REPORT_PATH := "user://enemy_ledger_continue_probe.json"
const ControllerScript := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const SoldierScript := preload("res://scripts/soldier.gd")

var report: Dictionary = {"passed":false,"steps":[],"r25_source":"R25 Challenge 5 wave 1 raw result + copied save","restores_requested":2}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var menu := await _wait_menu(20.0)
	if menu == null:
		_finish("initial_menu_missing")
		return
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_finish("copied_r25_save_continue_unavailable")
		return
	var old_id := menu.get_instance_id()
	continue_button.pressed.emit()
	var game := await _wait_game(old_id, 35.0)
	if game == null:
		_finish("initial_production_continue_failed")
		return
	var save_data := _saved_payload()
	if save_data.is_empty():
		_finish("continued_match_payload_missing")
		return
	var payload_units: Dictionary = {}
	for row in save_data.get("entities", {}).get("soldiers", []):
		if bool(row.get("is_zombie", false)) and int(row.get("horde_wave_id", 0)) == 1:
			payload_units[str(row.get("id", ""))] = row
	var saved_dead := payload_units.values().filter(func(row): return not bool(row.get("alive", false))).size()
	var saved_alive := payload_units.values().filter(func(row): return bool(row.get("alive", false))).size()
	var initial_payload_audit := {"wave1_zombie_rows":payload_units.size(),"dead":saved_dead,"alive":saved_alive,"ids":payload_units.keys().duplicate()}
	if payload_units.size() != 4 or saved_dead != 1 or saved_alive != 3:
		report["payload_audit"] = {"wave1_zombie_rows":payload_units.size(),"dead":saved_dead,"alive":saved_alive,"ids":payload_units.keys()}
		_finish("r25_payload_entity_fixture_mismatch")
		return

	# R25's raw wave-1 ledger preserves six pre-Continue unique identities.
	# Four mapped identities were serialized; two already-deleted corpses survive
	# only as historical death records and must not be invented or discarded.
	var ledger: Node = ControllerScript.new()
	ledger.set_process(false)
	ledger.set_physics_process(false)
	get_tree().root.add_child(ledger)
	await get_tree().process_frame
	ledger.wave_ledger = {"1":{"wave_id":1,"expected_count":6,"spawned":{},"killed":{},"last_alive":{},"samples":0}}
	ledger.events = []
	ledger.runtime_enemy_stable_key = {
		"2070392346759":"entity_48",
		"2070979544522":"entity_49",
		"2072086845855":"entity_50",
		"2072422389840":"entity_51"
	}
	var row: Dictionary = ledger.wave_ledger["1"]
	var spawned: Dictionary = row["spawned"]
	for old_runtime_id in ["2070392346759","2070979544522","2071315093596","2071650637914","2072086845855","2072422389840"]:
		spawned[old_runtime_id] = {"stable_or_runtime_id":old_runtime_id,"runtime_instance_id":old_runtime_id,"first_game_time":210.0}
	row["spawned"] = spawned
	row["killed"] = {
		"2070392346759":{"game_time":229.27,"runtime_instance_id":"2070392346759"},
		"2071315093596":{"game_time":217.49,"runtime_instance_id":"2071315093596"},
		"2071650637914":{"game_time":222.83,"runtime_instance_id":"2071650637914"}
	}
	row["last_alive"] = {
		"2070979544522":{"game_time":230.0,"hp":48.0},
		"2072086845855":{"game_time":230.0,"hp":48.0},
		"2072422389840":{"game_time":230.0,"hp":48.0}
	}
	ledger.wave_ledger["1"] = row
	ledger._normalize_enemy_ledger_ids()
	var seeded_counts := _counts(ledger)
	if seeded_counts != {"spawned":6,"killed":3,"last_alive":3}:
		_finish("r25_pre_continue_ledger_seed_not_6_3_3")
		return

	var restore_audits: Array[Dictionary] = []
	for restore_index in 3:
		if restore_index > 0:
			var started_id := game.get_instance_id()
			if not bool(game.call("_save_match")):
				_finish("production_save_before_repeated_continue_failed")
				return
			var return_button := _find_button(game.get("_pause_layer"), "返回主菜单")
			if return_button == null:
				_finish("production_pause_return_to_start_button_missing")
				return
			return_button.pressed.emit()
			menu = await _wait_new_menu(started_id, 25.0)
			if menu == null:
				_finish("production_return_to_start_failed")
				return
			continue_button = menu.get("_start_continue_button") as Button
			if continue_button == null or continue_button.disabled:
				_finish("production_continue_button_missing_on_repeat")
				return
			old_id = menu.get_instance_id()
			continue_button.pressed.emit()
			game = await _wait_game(old_id, 35.0)
			if game == null:
				_finish("production_continue_repeat_%d_failed" % restore_index)
				return
			payload_units = _wave1_zombie_payload(_saved_payload())
		game.call("_set_pause_menu_open", true)
		var node_map: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_map", {})
		var runtime_map: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_runtime_ids", {})
		var ledger_id_map: Dictionary = Engine.get_meta("aoelite_challenge5_restore_entity_ledger_ids", {})
		var map_rows: Array[Dictionary] = []
		var map_ok := true
		for entity_id in payload_units.keys():
			var saved_row: Dictionary = payload_units[entity_id]
			var runtime_id := str(runtime_map.get(str(entity_id), ""))
			var ledger_entity_id := str(ledger_id_map.get(str(entity_id), saved_row.get("challenge_ledger_entity_id", entity_id)))
			var restored_node: Variant = node_map.get(str(entity_id))
			if runtime_id.is_empty():
				map_ok = false
			if bool(saved_row.get("alive", false)) and (not is_instance_valid(restored_node) or not bool(restored_node.get("is_zombie"))):
				map_ok = false
			if not runtime_id.is_empty():
				ledger.runtime_enemy_stable_key[runtime_id] = ledger_entity_id
			map_rows.append({"serialized_entity_id":str(entity_id),"ledger_entity_id":ledger_entity_id,"serialized_alive":bool(saved_row.get("alive", false)),"node_valid":is_instance_valid(restored_node),"restored_runtime_id":runtime_id})
		ledger._normalize_enemy_ledger_ids()
		ledger._track_runtime(game)
		var counts := _counts(ledger)
		var exact_ids: bool = _entity_spawn_ids(ledger).size() == 4 and ledger.wave_ledger["1"].spawned.has("2071315093596") and ledger.wave_ledger["1"].spawned.has("2071650637914")
		var pass_this_restore: bool = map_ok and exact_ids and counts == {"spawned":6,"killed":3,"last_alive":3}
		restore_audits.append({"restore_index":restore_index,"serialized_enemy_rows":payload_units.size(),"restored_id_maps":map_rows,"runtime_to_serialized_mapping_count":runtime_map.size(),"counts":counts,"exact_four_serialized_plus_two_history_ids":exact_ids,"passed":pass_this_restore})
		if not pass_this_restore:
			report["restore_audits"] = restore_audits
			_finish("ledger_counts_or_identity_changed_during_continue_%d" % restore_index)
			return

	# Add a real Soldier3D zombie to the restored scene and run the same observer
	# path as the natural tracker. It must be retained as enemy seven and emit an
	# expected-count audit failure; the expectation must never cap observations.
	var seventh: Variant = SoldierScript.new()
	seventh.setup(Vector3(0.0, 0.0, 0.0), "zombie", true)
	seventh.horde_wave_id = 1
	game.get("world").add_child(seventh)
	await get_tree().process_frame
	ledger._track_runtime(game)
	var after_seventh := _counts(ledger)
	var seventh_key: String = ledger.runtime_id_to_stable_key(str(seventh.get_instance_id()))
	var seven_retained: bool = ledger.wave_ledger["1"].spawned.has(seventh_key) and after_seventh.spawned == 7
	var expected_alarm: bool = ledger.events.any(func(event): return str(event.get("action")) == "wave_enemy_count_exceeds_expected_audit" and str(event.get("stable_key")) == seventh_key and bool(event.get("counted_in_spawn_ledger", false)) and str(event.get("acceptance_status")) == "explicit_failure_expected_count_audit")
	report["payload_audit"] = initial_payload_audit
	report["final_payload_audit"] = {"wave1_zombie_rows":payload_units.size(),"ids":payload_units.keys().duplicate(),"ledger_entity_ids":payload_units.values().map(func(saved_row): return str(saved_row.get("challenge_ledger_entity_id", saved_row.get("id", ""))))}
	report["initial_ledger_reconciled"] = seeded_counts
	report["restore_audits"] = restore_audits
	report["seventh_enemy"] = {"runtime_id":str(seventh.get_instance_id()),"ledger_key":seventh_key,"spawned_after":after_seventh.spawned,"killed_after":after_seventh.killed,"last_alive_after":after_seventh.last_alive,"retained_as_unique":seven_retained,"expected_count_alarm_emitted":expected_alarm,"expected_count":6,"observed_count":after_seventh.spawned}
	if not seven_retained or not expected_alarm:
		_finish("distinct_seventh_enemy_not_retained_or_alarm_missing")
		return
	report["passed"] = true
	_finish("")

func _counts(ledger: Node) -> Dictionary:
	var rec: Dictionary = ledger.wave_ledger.get("1", {})
	return {"spawned":(rec.get("spawned", {}) as Dictionary).size(),"killed":(rec.get("killed", {}) as Dictionary).size(),"last_alive":(rec.get("last_alive", {}) as Dictionary).size()}

func _entity_spawn_ids(ledger: Node) -> Array:
	var out: Array = []
	for key in (ledger.wave_ledger["1"].get("spawned", {}) as Dictionary).keys():
		if str(key).begins_with("entity_"): out.append(str(key))
	return out

func _saved_payload() -> Dictionary:
	var path := "user://aoelite3d_save.json"
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _wave1_zombie_payload(data: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	for row in data.get("entities", {}).get("soldiers", []):
		if bool(row.get("is_zombie", false)) and int(row.get("horde_wave_id", 0)) == 1:
			rows[str(row.get("id", ""))] = row
	return rows

func _wait_menu(seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get("_start_layer") != null: return current
	return null

func _wait_new_menu(old_id: int, seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get_instance_id() != old_id and current.get("_start_layer") != null: return current
	return null

func _wait_game(old_id: int, seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().root.get_node_or_null("Main")
		if current != null and current.get_instance_id() != old_id and bool(current.get("_match_started")): return current
	return null

func _find_button(root: Node, text: String) -> Button:
	if root == null: return null
	for item in root.find_children("*", "Button", true, false):
		var button := item as Button
		if button != null and button.text == text: return button
	return null

func _finish(error_text: String) -> void:
	if not error_text.is_empty(): report["error"] = error_text
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[enemy_ledger_continue_probe] ", JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("passed", false)) else 1)
