extends Node
## Resume an existing Challenge 5 save through Continue, then attach the defense controller.

const ControllerScript := preload("res://scripts/diagnostics/controlled_endless_defense.gd")
const SAVE_PATH := "user://aoelite3d_save.json"
const WALL_LIMIT_MSEC := 1200000

var started_at_msec := 0
var menu_instance_id := 0
var run_id := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at_msec = Time.get_ticks_msec()
	var user_args := OS.get_cmdline_user_args()
	for index in user_args.size():
		var arg := str(user_args[index])
		if arg.begins_with("--run-id="):
			run_id = arg.get_slice("=", 1)
			if run_id.is_empty() and index + 1 < user_args.size():
				run_id = str(user_args[index + 1])
		elif arg == "--run-id" and index + 1 < user_args.size():
			run_id = str(user_args[index + 1])
	if run_id.is_empty():
		run_id = "challenge5_resume_%d_%d" % [Time.get_ticks_usec(), OS.get_process_id()]
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_fail("production_challenge5_save_missing")
		return
	var save_text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(save_text)
	if not parsed is Dictionary or int(parsed.get("map_seed", -1)) != 42 or int(parsed.get("horde_mode", -1)) != 1:
		_fail("production_save_not_challenge5_seed42")
		return
	var saved_time := float(parsed.get("game_time", -1.0))
	if saved_time < 220.0 or saved_time >= 285.0:
		_fail("saved_checkpoint_outside_wave2_preparation_window")
		return
	var menu := _main_game()
	if menu == null or menu.get("_start_layer") == null:
		_fail("production_start_menu_missing")
		return
	menu_instance_id = int(menu.get_instance_id())
	var continue_button: Button = menu.get("_start_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_fail("production_continue_button_unavailable")
		return
	continue_button.pressed.emit()
	print("[challenge5_resume_defense] production Continue emitted; saved_game_time=", saved_time)
	var game: Node
	while _within_wall_limit():
		await get_tree().process_frame
		game = _main_game()
		if game != null and int(game.get_instance_id()) != menu_instance_id and bool(game.get("_match_started")) and int(game.get("map_seed")) == 42 and int(game.get("_horde_mode")) == 1 and float(game.get("_game_time")) >= saved_time - 0.1:
			break
	if not _within_wall_limit():
		_fail("wall_clock_limit_waiting_for_production_continue")
		return
	if game == null or not is_instance_valid(game) or int(game.get_instance_id()) == menu_instance_id:
		_fail("production_continue_did_not_replace_start_scene")
		return
	var loaded_time := float(game.get("_game_time"))
	var controller: Node = ControllerScript.new()
	controller.name = "ControlledEndlessDefense"
	controller.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(controller)
	if not bool(controller.call("initialize_from_resumed_match", game)):
		_fail("controller_rejected_restored_match")
		return
	controller.set("run_id", run_id)
	controller.call("record_resume_bootstrap", {"action":"production_continue_restore_verified","saved_game_time":saved_time,"loaded_game_time":loaded_time,"save_sha256":FileAccess.get_sha256(SAVE_PATH),"seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"main_scene_instance_changed":true,"strategy_hypothesis":"preserve civilian capacity when it fits; add backup population capacity before town center collapse; preserve soldier food during active army deficit; train during build awaits; restore gathering for rejoined workers","wall_started_msec":started_at_msec})
	print("[challenge5_resume_defense] controller attached at game_time=", loaded_time, " wave=", int(game.get("_horde_wave")), " pid=", OS.get_process_id())
	queue_free()

func _main_game() -> Node:
	return get_tree().get_first_node_in_group("main_game")

func _within_wall_limit() -> bool:
	return Time.get_ticks_msec() - started_at_msec < WALL_LIMIT_MSEC

func _fail(reason: String) -> void:
	var payload := {"success":false,"reason":reason,"wall_elapsed_msec":Time.get_ticks_msec()-started_at_msec,"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"user_data_dir":OS.get_user_data_dir()}
	var file := FileAccess.open("user://challenge5_resume_bootstrap.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t"))
		file.close()
	push_error("[challenge5_resume_defense] " + reason)
	get_tree().quit(1)
