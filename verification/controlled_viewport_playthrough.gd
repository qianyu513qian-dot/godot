extends Node
## Production menu and gameplay exercise through Godot's normal Viewport input routing.
## This runner observes game state but never calls a gameplay command or edits game data.

const RESULT_PATH := "user://controlled_viewport_playthrough.json"
const Catalog := preload("res://scripts/building_catalog.gd")
var phase := "menu_seed"
var phase_time := 0.0
var total_time := 0.0
var records: Array[Dictionary] = []
var events: Array[Dictionary] = []
var done := false
var failed := false
var last_state: Node = null
var save_snapshot: Dictionary = {}
var house: Node3D = null
var checkpoint_seq := 0
var _persist_t := 0.0
var action_busy := false
var pre_restore_scene_id := 0

func _process(delta: float) -> void:
	total_time += delta
	phase_time += delta
	_persist_t += delta
	var game := get_tree().get_first_node_in_group("main_game")
	if game != null:
		last_state = game
	if _persist_t >= 0.5:
		_persist_t = 0.0
		_persist()
	if done:
		return
	if action_busy:
		return
	if total_time > 720.0:
		_finish(false, "bounded_12_minute_timeout")
		return
	match phase:
		"menu_seed":
			if game != null and game.get("_start_layer") != null:
				action_busy = true
				phase = "menu_seed_busy"
				await _run_menu_seed(game, false)
		"wait_start":
			if game != null and bool(game.get("_match_started")):
				_checkpoint("match_started", game)
				phase = "select_workers"
				phase_time = 0.0
		"select_workers":
			if phase_time > 0.4:
				action_busy = true
				await _send_key(KEY_F3)
				phase = "gather_mode"
				phase_time = 0.0
				action_busy = false
		"gather_mode":
			if phase_time > 0.4 and game != null:
				var trees := _wood_nodes(game)
				if trees.is_empty():
					_finish(false, "seed42_no_wood_nodes")
					return
				action_busy = true
				await _send_key(KEY_G)
				var target: Node3D = trees[0]
				var screen: Vector2 = game.get("camera").unproject_position(target.global_position + Vector3(0, 0.6, 0))
				await _click(screen, "wood node %s" % target.name, null)
				events.append({"action":"gather_order", "selected_count": game.get("selected").size(), "target":target.name,"world_position":_v3(target.global_position),"wood_before":game.get("wood"),"game_time":game.get("_game_time")})
				_checkpoint("natural_gather_order", game)
				phase = "wait_wood"
				phase_time = 0.0
				action_busy = false
		"wait_wood":
			if game != null and int(game.get("wood")) >= 50:
				action_busy = true
				events.append({"action":"natural_wood_deposited", "wood":game.get("wood"),"game_time":game.get("_game_time"),"villagers":_villager_count(game)})
				_checkpoint("wood_50_deposited", game)
				await _send_key(KEY_B)
				phase = "house_button"
				phase_time = 0.0
				action_busy = false
			elif phase_time > 110.0:
				_finish(false, "natural_wood_not_deposited_before_timeout")
		"house_button":
			if phase_time > 0.4 and game != null:
				var btn := _find_button(game.get("hud"), "房屋")
				if btn == null:
					btn = _find_button(game.get("hud"), "房子")
				if btn == null:
					_finish(false, "actual_house_build_button_not_found")
					return
				action_busy = true
				var house_btn_path := str(btn.get_path())
				var house_btn_rect := _rect(btn)
				await _click_control(btn)
				events.append({"action":"house_build_button_click", "control":house_btn_path,"rect":house_btn_rect,"wood_before":game.get("wood")})
				phase = "place_house"
				phase_time = 0.0
				action_busy = false
		"place_house":
			if phase_time > 0.35 and game != null:
				action_busy = true
				var p := Vector3(12.0, 0.0, 0.0)
				var screen: Vector2 = game.get("camera").unproject_position(p)
				var before := int(game.get("wood"))
				await _click(screen, "house placement at %s" % str(p), null)
				var candidates := get_tree().get_nodes_in_group("buildings")
				for b in candidates:
					if int(b.get("kind")) == Catalog.HOUSE and not bool(b.get("is_complete")):
						house = b as Node3D
				events.append({"action":"house_placement", "world_position":_v3(p),"wood_before":before,"wood_after":game.get("wood"),"foundation_found":is_instance_valid(house),"placed_kind":game.get("place_kind")})
				_checkpoint("house_foundation", game)
				if not is_instance_valid(house):
					_finish(false, "production_house_placement_not_confirmed")
					return
				phase = "wait_house"
				phase_time = 0.0
				action_busy = false
		"wait_house":
			if is_instance_valid(house) and bool(house.get("is_complete")):
				events.append({"action":"house_completed", "build_progress":house.get("build_progress"),"game_time":game.get("_game_time")})
				_checkpoint("house_completed", game)
				action_busy = true
				await _send_key(KEY_F3)
				phase = "select_tc"
				phase_time = 0.0
				action_busy = false
			elif phase_time > 90.0:
				_finish(false, "house_completion_timeout")
		"select_tc":
			if phase_time > 0.45 and game != null:
				var tc: Node3D = null
				for b in get_tree().get_nodes_in_group("buildings"):
					if int(b.get("kind")) == Catalog.TOWN_CENTER:
						tc = b as Node3D
						break
				if tc == null:
					_finish(false, "town_center_missing")
					return
				action_busy = true
				await _click(game.get("camera").unproject_position(tc.global_position + Vector3(0, 4, 0)), "Town Center selection", null)
				phase = "train_button"
				phase_time = 0.0
				action_busy = false
		"train_button":
			if phase_time > 0.6 and game != null:
				var commands: Dictionary = game.get("hud").get("_cmd_btns")
				var btn: Button = commands.get("train") as Button
				if btn == null:
					_finish(false, "actual_train_button_not_available_after_tc_selection")
					return
				action_busy = true
				var meat0 := int(game.get("meat"))
				var train_path := str(btn.get_path())
				var train_rect := _rect(btn)
				await _click_control(btn)
				events.append({"action":"train_villager_button_click", "control":train_path,"rect":train_rect,"meat_before":meat0,"meat_after":game.get("meat")})
				phase = "wait_train"
				phase_time = 0.0
				action_busy = false
		"wait_train":
			if game != null and _villager_count(game) >= 6:
				action_busy = true
				events.append({"action":"trained_villager_spawned", "villagers":_villager_count(game),"meat_after":game.get("meat"),"game_time":game.get("_game_time")})
				_checkpoint("trained_villager_spawned", game)
				await _send_key(KEY_F5)
				if game != null:
					save_snapshot = _snapshot(game)
					pre_restore_scene_id = game.get_instance_id()
					_checkpoint("f5_saved_live_match", game)
				await _send_key(KEY_F9)
				phase = "wait_restore"
				phase_time = 0.0
				action_busy = false
			elif phase_time > 40.0:
				_finish(false, "trained_villager_not_spawned")
		"wait_restore":
			if game != null and game.get_instance_id() != pre_restore_scene_id:
				var restored := _snapshot(game)
				var comparison := _compare_core_snapshot(save_snapshot, restored)
				var match_ok := bool(comparison.get("all_match", false))
				events.append({"action":"f9_restored_match", "fields_match":match_ok,"field_comparison":comparison,"saved":save_snapshot,"restored":restored,"game_time_after_live_continue":game.get("_game_time")})
				_checkpoint("f9_restored_and_continued", game)
				if not match_ok:
					_finish(false, "f9_restore_snapshot_mismatch")
					return
				phase = "verify_live_restore"
				phase_time = 0.0
			elif phase_time > 20.0:
				_finish(false, "f9_restore_timeout")
		"verify_live_restore":
			if phase_time >= 1.0 and game != null:
				events.append({"action":"post_f9_live_process","game_time":game.get("_game_time"),"scene_id":game.get_instance_id(),"simulation_advanced":float(game.get("_game_time")) > float(save_snapshot.get("game_time",0.0))})
				_checkpoint("post_restore_live_simulation", game)
				phase = "wait_wave"
				phase_time = 0.0
		"wait_wave":
			if game != null and int(game.get("_horde_wave")) >= 1:
				_checkpoint("first_wave_spawned", game)
				phase = "observe_wave"
				phase_time = 0.0
			elif phase_time > 270.0:
				_finish(false, "first_wave_not_reached_within_270_seconds")
		"observe_wave":
			if (not bool(game.get("_horde_active")) and int(game.get("_horde_spawn_queue").size()) == 0) or bool(game.get("_defeated")):
				var resolved := not bool(game.get("_horde_active")) and int(game.get("_horde_spawn_queue").size()) == 0
				var result_name := "first_wave_cleared" if resolved and int(game.get("_horde_wave")) == 1 else "first_wave_unresolved_then_wave%d_defeat" % int(game.get("_horde_wave")) if bool(game.get("_defeated")) else "later_wave_%d_cleared" % int(game.get("_horde_wave"))
				var player_army := 0
				for unit in get_tree().get_nodes_in_group("military"):
					if is_instance_valid(unit) and str(unit.get("team")) == "player" and bool(unit.get("alive")):
						player_army += 1
				events.append({"action":result_name, "wave":game.get("_horde_wave"),"active":game.get("_horde_active"),"alive_hostiles":game.get("_horde_alive_cache"),"spawn_queue":game.get("_horde_spawn_queue").size(),"defeated":game.get("_defeated"),"victorious":game.get("_victorious"),"game_time":game.get("_game_time"),"clock_minutes":game.get("_clock_minutes"),"player_villagers":_villager_count(game),"player_military":player_army})
				_checkpoint(result_name, game)
				phase = "pause_return_button"
				phase_time = 0.0
			elif phase_time >= 45.0 and not records.any(func(r): return r.name == "first_wave_still_active"):
				_checkpoint("first_wave_still_active", game)
			elif phase_time >= 150.0:
				_finish(false, "first_wave_unresolved_after_150_seconds")
				return
			if phase == "pause_return_button":
				action_busy = true
				await _send_key(KEY_ESCAPE)
				phase_time = 0.0
				action_busy = false
		"pause_return_button":
			if phase_time > 8.0:
				_finish(false, "production_return_to_menu_button_timeout")
				return
			if phase_time > 0.7 and game != null:
				var button_root: Node = game.get("hud").get("_defeat_panel") if bool(game.get("_defeated")) and game.get("hud") != null else game.get("_pause_layer")
				var btn := _find_button(button_root, "返回开局") if bool(game.get("_defeated")) else _find_button(button_root, "返回主菜单")
				if btn != null:
					action_busy = true
					var return_path := str(btn.get_path())
					var return_rect := _rect(btn)
					await _click_control(btn)
					events.append({"action":"return_to_menu_button_click","control":return_path,"rect":return_rect})
					phase = "wait_menu_return"
					phase_time = 0.0
					action_busy = false
		"wait_menu_return":
			if game != null and game.get("_start_layer") != null:
				_checkpoint("returned_to_production_menu", game)
				action_busy = true
				phase = "menu_seed_busy"
				await _run_menu_seed(game, true)
		"wait_restart":
			if game != null and bool(game.get("_match_started")):
				_checkpoint("restart_from_menu_seed42", game)
				_finish(true, "completed_menu_gameplay_wave_save_restore_return_restart")

func _run_menu_seed(game: Node, restarting: bool) -> void:
	var field: LineEdit = game.get("_seed_edit") as LineEdit
	var mode: OptionButton = game.get("_start_mode_select") as OptionButton
	if field == null or mode == null:
		_finish(false, "production_start_menu_controls_missing")
		return
	if mode.get_selected_id() != 0:
		_finish(false, "default_endless_mode_not_selected")
		return
	await _click_control(field)
	await get_tree().create_timer(0.15).timeout
	await _send_key(KEY_4, 52)
	await _send_key(KEY_2, 50)
	var start := _find_button(game.get("_start_layer"), "开始游戏")
	if start == null:
		start = _find_button(game.get("_start_layer"), "开始")
	if start == null:
		_finish(false, "production_start_button_missing")
		return
	events.append({"action":"menu_seed_input","seed_field":str(field.get_path()),"focus_owner":str(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "","seed_text":field.text,"mode_selected_id":mode.get_selected_id()})
	if field.text != "42":
		_finish(false, "viewport_key_input_did_not_enter_seed42")
		return
	var start_path := str(start.get_path())
	var start_rect := _rect(start)
	var entered_seed := field.text
	await _click_control(start)
	events.append({"action":"menu_start_button_click","control":start_path,"rect":start_rect,"hovered":str(get_viewport().gui_get_hovered_control().get_path()) if get_viewport().gui_get_hovered_control() else "","seed":entered_seed})
	phase = "wait_restart" if restarting else "wait_start"
	phase_time = 0.0
	action_busy = false

func _send_key(code: int, unicode_value: int = 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode_value
	e.pressed = true
	get_viewport().push_input(e)
	await get_tree().process_frame
	e = e.duplicate() as InputEventKey
	e.pressed = false
	get_viewport().push_input(e)
	await get_tree().process_frame
	events.append({"input":"key","keycode":code,"unicode":unicode_value,"route":"Viewport.push_input"})

func _click_control(control: Control) -> void:
	var rect := control.get_global_rect()
	var p := rect.get_center()
	await _click(p, str(control.get_path()), control)

func _click(p: Vector2, target: String, control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hovered_before_press := get_viewport().gui_get_hovered_control()
	var down := InputEventMouseButton.new()
	down.position = p
	down.global_position = p
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame
	events.append({"input":"mouse_click","target":target,"position":[p.x,p.y],"target_control":str(control.get_path()) if control and is_instance_valid(control) else "world","hovered_control":str(hovered_before_press.get_path()) if hovered_before_press else "","gui_hit_matches_target":bool(control and hovered_before_press == control),"route":"Viewport.push_input GUI hit-test then normal unhandled input"})

func _find_button(root: Node, text_fragment: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button.is_visible_in_tree() and button.text.contains(text_fragment):
			return button
	return null

func _wood_nodes(game: Node) -> Array:
	var result: Array = []
	for n in get_tree().get_nodes_in_group("resources"):
		if int(n.get("kind")) == 0:
			result.append(n)
	return result

func _villager_count(game: Node) -> int:
	return get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and bool(v.get("alive"))).size()

func _snapshot(game: Node) -> Dictionary:
	var houses: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		houses.append({"kind":int(b.get("kind")),"complete":bool(b.get("is_complete")),"progress":float(b.get("build_progress")),"position":_v3(b.global_position)})
	var tc: Dictionary = {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if int(b.get("kind")) == Catalog.TOWN_CENTER:
			tc = {"queue":b.get("train_queue").duplicate(),"timer":float(b.get("train_timer")),"paid":bool(b.get("train_paid"))}
	return {"map_seed":game.get("map_seed"),"mode":game.get("_horde_mode"),"resources":{"wood":game.get("wood"),"meat":game.get("meat"),"stone":game.get("stone"),"gold":game.get("gold")},"game_time":game.get("_game_time"),"clock_minutes":game.get("_clock_minutes"),"wave":game.get("_horde_wave"),"next_at":game.get("_horde_next_at"),"villagers":_villager_count(game),"buildings":houses,"town_center_queue":tc}

func _compare_core_snapshot(a: Dictionary, b: Dictionary) -> Dictionary:
	var checks := {
		"map_seed": int(a.get("map_seed", -1)) == int(b.get("map_seed", -2)),
		"mode": int(a.get("mode", -1)) == int(b.get("mode", -2)),
		"resources": a.get("resources", {}) == b.get("resources", {}),
		"wave": int(a.get("wave", -1)) == int(b.get("wave", -2)),
		"villagers": int(a.get("villagers", -1)) == int(b.get("villagers", -2)),
		"game_time_within_2s": absf(float(a.get("game_time", 0.0)) - float(b.get("game_time", 0.0))) < 2.0,
		"buildings": _building_snapshot_match(a.get("buildings", []), b.get("buildings", [])),
		"town_center_queue": _training_snapshot_match(a.get("town_center_queue", {}), b.get("town_center_queue", {})),
	}
	var all_match := true
	for value in checks.values():
		all_match = all_match and bool(value)
	checks["all_match"] = all_match
	return checks

func _building_snapshot_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var left: Dictionary = a[i]
		var right: Dictionary = b[i]
		if int(left.get("kind", -1)) != int(right.get("kind", -2)) or bool(left.get("complete", false)) != bool(right.get("complete", true)):
			return false
		if absf(float(left.get("progress", 0.0)) - float(right.get("progress", 0.0))) > 0.1:
			return false
		var lp: Array = left.get("position", [])
		var rp: Array = right.get("position", [])
		if lp.size() != 3 or rp.size() != 3:
			return false
		for axis in 3:
			if absf(float(lp[axis]) - float(rp[axis])) > 0.05:
				return false
	return true

func _training_snapshot_match(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return a.get("queue", []) == b.get("queue", []) and bool(a.get("paid", false)) == bool(b.get("paid", true)) and absf(float(a.get("timer", 0.0)) - float(b.get("timer", 0.0))) < 0.2

func _checkpoint(name: String, game: Node) -> void:
	checkpoint_seq += 1
	records.append({"seq":checkpoint_seq,"name":name,"real_elapsed_seconds":total_time,"phase_elapsed_seconds":phase_time,"snapshot":_snapshot(game),"ordinary_os_input_verified":false})
	_persist()

func _rect(control: Control) -> Array:
	var r := control.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func _v3(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _finish(ok: bool, reason: String) -> void:
	done = true
	failed = not ok
	events.append({"action":"finish","success":ok,"reason":reason,"real_elapsed_seconds":total_time})
	_persist()
	# Leave the final game state visible until the isolated capture harness has
	# written and hashed the final result screenshots.
	await get_tree().create_timer(8.0).timeout
	get_tree().quit()

func _persist() -> void:
	var result := {"schema":1,"mode":"production_viewport_input_playthrough","ordinary_os_input_verified":false,"success":done and not failed,"done":done,"phase":phase,"failure":events.back().get("reason","") if done and failed and not events.is_empty() else "","real_elapsed_seconds":total_time,"events":events,"checkpoints":records,"last_snapshot":_snapshot(last_state) if is_instance_valid(last_state) else {}}
	var file := FileAccess.open(RESULT_PATH,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
