extends Node
## Bounded UI follow-up starting from a real F5 save created by the production playthrough.
## All controls are clicked through Viewport input routing; game state is read only.

const RESULT_PATH := "user://controlled_resume_return.json"
const Catalog := preload("res://scripts/building_catalog.gd")
var phase := "continue_from_menu"
var elapsed := 0.0
var phase_elapsed := 0.0
var busy := false
var done := false
var events: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var old_scene_id := 0

func _process(delta: float) -> void:
	elapsed += delta
	phase_elapsed += delta
	var game := get_tree().get_first_node_in_group("main_game")
	_persist()
	if done or busy:
		return
	if elapsed > 120.0:
		await _finish(false, "resume_return_120_second_timeout")
		return
	match phase:
		"continue_from_menu":
			if game != null and game.get("_start_layer") != null:
				var btn := _find_button(game.get("_start_layer"), "继续上次对局")
				if btn == null or btn.disabled:
					await _finish(false, "production_continue_save_button_unavailable")
					return
				busy = true
				old_scene_id = game.get_instance_id()
				var path := str(btn.get_path())
				var rect := _rect(btn)
				await _click_control(btn)
				events.append({"action":"continue_saved_match_button_click","control":path,"rect":rect,"old_scene_id":old_scene_id})
				phase = "wait_restore"
				phase_elapsed = 0.0
				busy = false
		"wait_restore":
			if game != null and game.get_instance_id() != old_scene_id and bool(game.get("_match_started")):
				var snap := _snapshot(game)
				var accepted: bool = int(snap.get("map_seed", 0)) == 42 and int(snap.get("mode", -1)) == 0 and int(snap.get("villagers", 0)) == 6 and int(snap.get("wave", -1)) == 0 and snap.get("resources", {}) == {"wood":0,"meat":0,"stone":0,"gold":0} and snap.get("building_kinds", []) == [Catalog.TOWN_CENTER, Catalog.HOUSE]
				events.append({"action":"production_continue_restore","restored_scene_id":game.get_instance_id(),"old_scene_id":old_scene_id,"fields_match_expected_f5_state":accepted,"snapshot":snap})
				_checkpoint("continue_saved_match_restored", snap)
				if not accepted:
					await _finish(false, "production_continue_loaded_unexpected_snapshot")
					return
				busy = true
				await _send_key(KEY_ESCAPE)
				phase = "pause_menu"
				phase_elapsed = 0.0
				busy = false
			elif phase_elapsed > 20.0:
				await _finish(false, "production_continue_restore_timeout")
		"pause_menu":
			if game != null and game.get("_pause_layer") != null:
				var btn := _find_button(game.get("_pause_layer"), "返回主菜单")
				if btn == null:
					await _finish(false, "pause_menu_return_button_unavailable")
					return
				busy = true
				var path := str(btn.get_path())
				var rect := _rect(btn)
				await _click_control(btn)
				events.append({"action":"pause_return_to_menu_button_click","control":path,"rect":rect})
				phase = "wait_menu"
				phase_elapsed = 0.0
				busy = false
			elif phase_elapsed > 8.0:
				await _finish(false, "pause_menu_not_opened")
		"wait_menu":
			if game != null and game.get("_start_layer") != null:
				_checkpoint("production_return_to_start_menu", _snapshot(game))
				busy = true
				await _start_seed42(game)
				phase = "wait_restart"
				phase_elapsed = 0.0
		"wait_restart":
			if game != null and bool(game.get("_match_started")) and game.get("_start_layer") == null:
				var snap := _snapshot(game)
				var is_new_match := int(snap.get("map_seed", 0)) == 42 and float(snap.get("game_time", 1000.0)) < 5.0 and int(snap.get("wave", -1)) == 0 and int(snap.get("villagers", 0)) == 5
				events.append({"action":"menu_seed42_restart","new_match_confirmed":is_new_match,"snapshot":snap})
				_checkpoint("menu_restart_new_seed42_match", snap)
				await _finish(is_new_match, "return_menu_then_restart_seed42" if is_new_match else "restart_snapshot_unexpected")
			elif phase_elapsed > 20.0:
				await _finish(false, "restart_from_start_menu_timeout")

func _start_seed42(game: Node) -> void:
	var field: LineEdit = game.get("_seed_edit") as LineEdit
	var mode: OptionButton = game.get("_start_mode_select") as OptionButton
	if field == null or mode == null or mode.get_selected_id() != 0:
		await _finish(false, "restart_menu_default_endless_controls_missing")
		return
	var start := _find_button(game.get("_start_layer"), "开始游戏")
	if start == null:
		await _finish(false, "restart_menu_start_button_missing")
		return
	await _click_control(field)
	await get_tree().create_timer(0.15).timeout
	await _send_key(KEY_4, 52)
	await _send_key(KEY_2, 50)
	if field.text != "42":
		await _finish(false, "restart_menu_seed_input_mismatch")
		return
	var start_path := str(start.get_path())
	var start_rect := _rect(start)
	await _click_control(start)
	events.append({"action":"restart_start_button_click","control":start_path,"rect":start_rect,"seed":"42","mode_id":0})
	busy = false

func _snapshot(game: Node) -> Dictionary:
	var kinds: Array[int] = []
	for b in get_tree().get_nodes_in_group("buildings"):
		kinds.append(int(b.get("kind")))
	kinds.sort()
	var resources := {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}
	return {"map_seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"resources":resources,"villagers":get_tree().get_nodes_in_group("villagers").filter(func(v): return is_instance_valid(v) and bool(v.get("alive"))).size(),"building_kinds":kinds}

func _find_button(root: Node, contains: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var b := child as Button
		if b.is_visible_in_tree() and b.text.contains(contains):
			return b
	return null

func _send_key(code: int, unicode_value := 0) -> void:
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
	await _click(rect.get_center(), str(control.get_path()), control)

func _click(pos: Vector2, target: String, control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hover := get_viewport().gui_get_hovered_control()
	var down := InputEventMouseButton.new()
	down.position = pos
	down.global_position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame
	events.append({"input":"mouse_click","target":target,"target_control":str(control.get_path()) if control and is_instance_valid(control) else "world","hovered_control":str(hover.get_path()) if hover else "","gui_hit_matches_target":bool(control and hover == control),"position":[pos.x,pos.y],"route":"Viewport.push_input GUI hit-test"})

func _rect(c: Control) -> Array:
	var r := c.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func _checkpoint(name: String, snap: Dictionary) -> void:
	checkpoints.append({"name":name,"real_elapsed_seconds":elapsed,"snapshot":snap,"ordinary_os_input_verified":false})
	_persist()

func _finish(ok: bool, reason: String) -> void:
	done = true
	events.append({"action":"finish","success":ok,"reason":reason,"real_elapsed_seconds":elapsed})
	_persist()
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()

func _persist() -> void:
	var result := {"schema":1,"mode":"production_saved_match_return_restart","done":done,"success":done and not events.is_empty() and bool(events.back().get("success", false)),"phase":phase,"real_elapsed_seconds":elapsed,"ordinary_os_input_verified":false,"events":events,"checkpoints":checkpoints}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result,"\t"))
		f.close()
