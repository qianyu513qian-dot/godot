extends Node
## Full military production + first contact using ordinary Viewport input only.
const RESULT_PATH := "user://controlled_military_playthrough.json"
const Catalog := preload("res://scripts/building_catalog.gd")
var phase := "menu"
var phase_time := 0.0
var elapsed := 0.0
var busy := false
var done := false
var events: Array[Dictionary] = []
var records: Array[Dictionary] = []
var last_game: Node
var checkpoint_seq := 0
var persist_clock := 0.0
var sample_clock := 0.0
var samples: Array[Dictionary] = []
var farm: Node3D
var barracks: Node3D
var saved_game_id := 0
var queue_snapshot: Array = []
var reload_checked := false
var queue_saved := false
var attack_order_issued := false
var _tracked_barracks_id := 0
var _last_tracked_queue: Array = []
var _last_tracked_train_paid := false
var _last_tracked_army: Array[String] = []
var _last_click_data: Dictionary = {}
var _diagnostic_button_press_count := 0
var _diagnostic_train_signal_count := 0
var _diagnostic_signal_hud_id := 0

func _process(delta: float) -> void:
	elapsed += delta
	phase_time += delta
	persist_clock += delta
	var game := get_tree().get_first_node_in_group("main_game")
	if game != null:
		last_game = game
		_track_military(game)
	if persist_clock >= 0.5:
		persist_clock = 0.0
		_persist()
	if done or busy:
		return
	if elapsed > 720.0:
		_finish(false, "bounded_timeout")
		return
	match phase:
		"menu":
			if game != null and game.get("_start_layer") != null:
				busy = true
				await _start_seed42(game)
		"start_wait":
			if game != null and bool(game.get("_match_started")):
				_checkpoint("seed42_endless_match_started", game)
				phase = "wood_order"
				phase_time = 0.0
		"wood_order":
			if phase_time > 1.0 and game != null:
				var trees := _wood_nodes()
				if trees.is_empty():
					_finish(false, "no_wood_nodes")
					return
				busy = true
				await _send_key(KEY_F3)
				await _send_key(KEY_G)
				var target: Node3D = trees[0]
				await _click_world(game, target.global_position + Vector3(0, 0.6, 0), "natural wood tree")
				events.append({"action":"wood_gather_order","selected":game.get("selected").size(),"target":target.name,"wood":game.get("wood"),"game_time":game.get("_game_time")})
				phase = "wait_wood"
				phase_time = 0.0
				busy = false
		"wait_wood":
			if game != null and int(game.get("wood")) >= 285:
				busy = true
				events.append({"action":"wood_target_reached","wood":game.get("wood"),"game_time":game.get("_game_time"),"villagers":_count_group("villagers")})
				_checkpoint("wood_for_farm_barracks_three_soldiers", game)
				await _send_key(KEY_S)
				await _send_key(KEY_B)
				phase = "farm_button"
				phase_time = 0.0
				busy = false
			elif phase_time > 125.0:
				_finish(false, "wood_285_not_gathered")
		"farm_button":
			if phase_time > 0.5 and game != null:
				var btn := _button(game.get("hud"), "农田")
				if btn == null:
					_finish(false, "farm_button_missing")
					return
				busy = true
				await _click_control(btn)
				events.append({"action":"farm_build_button_clicked","path":str(btn.get_path()),"wood_after":game.get("wood")})
				phase = "farm_place"
				phase_time = 0.0
				busy = false
		"farm_place":
			if phase_time > 0.4 and game != null:
				busy = true
				var p := Vector3(12, 0, 0)
				await _click_world(game, p, "farm placement")
				farm = _building(Catalog.FARM, false)
				events.append({"action":"farm_placement","position":_v3(p),"wood":game.get("wood"),"foundation":farm != null,"placement_mode":game.get("place_kind")})
				if farm == null:
					_finish(false, "farm_foundation_not_placed")
					return
				phase = "farm_build_wait"
				phase_time = 0.0
				busy = false
		"farm_build_wait":
			if is_instance_valid(farm) and bool(farm.get("is_complete")):
				_checkpoint("farm_complete", game)
				busy = true
				await _send_key(KEY_S)
				await _send_key(KEY_B)
				phase = "barracks_button"
				phase_time = 0.0
				busy = false
			elif phase_time > 50.0:
				_finish(false, "farm_build_timeout")
		"barracks_button":
			if phase_time > 0.5 and game != null:
				var btn := _button(game.get("hud"), "兵营")
				if btn == null:
					_finish(false, "barracks_button_missing")
					return
				busy = true
				await _click_control(btn)
				events.append({"action":"barracks_build_button_clicked","path":str(btn.get_path()),"wood_after":game.get("wood")})
				phase = "barracks_place"
				phase_time = 0.0
				busy = false
		"barracks_place":
			if phase_time > 0.4 and game != null:
				busy = true
				var p := Vector3(-12, 0, 0)
				await _click_world(game, p, "barracks placement")
				barracks = _building(Catalog.BARRACKS, false)
				events.append({"action":"barracks_placement","position":_v3(p),"wood":game.get("wood"),"foundation":barracks != null,"placement_mode":game.get("place_kind")})
				if barracks == null:
					_finish(false, "barracks_foundation_not_placed")
					return
				phase = "barracks_build_wait"
				phase_time = 0.0
				busy = false
		"barracks_build_wait":
			if is_instance_valid(barracks) and bool(barracks.get("is_complete")):
				_checkpoint("barracks_complete", game)
				busy = true
				await _send_key(KEY_F3)
				await _send_key(KEY_G)
				var farm_screen: Vector2 = game.get("camera").unproject_position(farm.global_position)
				var ground_hit: Variant = game.call("_ray_ground", farm_screen)
				var nearby_resources: Array = []
				for r in get_tree().get_nodes_in_group("resources"):
					if is_instance_valid(r):
						nearby_resources.append({"name":r.name,"kind":r.get("kind"),"pos":_v3(r.global_position),"distance":Vector2(r.global_position.x - (ground_hit.x if ground_hit is Vector3 else 0.0),r.global_position.z - (ground_hit.z if ground_hit is Vector3 else 0.0)).length()})
				await _click(farm_screen, "completed farm meat source")
				events.append({"action":"farm_meat_gather_order","selected":game.get("selected").size(),"command_mode_after_g":game.get("_cmd_mode"),"ground_hit":_v3(ground_hit) if ground_hit is Vector3 else str(ground_hit),"nearby_resources":nearby_resources,"farm_name":farm.name,"farm_group_resources":farm.is_in_group("resources"),"farm_meat_stock":farm.get("meat_stock"),"villagers":_villager_debug(),"meat_before":game.get("meat"),"game_time":game.get("_game_time")})
				phase = "wait_meat"
				phase_time = 0.0
				busy = false
			elif phase_time > 65.0:
				_finish(false, "barracks_build_timeout")
		"wait_meat":
			if game != null and int(game.get("meat")) >= 180:
				busy = true
				events.append({"action":"meat_target_reached","meat":game.get("meat"),"wood":game.get("wood"),"game_time":game.get("_game_time")})
				_checkpoint("meat_for_three_soldiers", game)
				await _send_key(KEY_S)
				await _click_world(game, barracks.global_position + Vector3(0, 4, 0), "barracks selection")
				phase = "soldier_buttons"
				phase_time = 0.0
				busy = false
			elif phase_time > 80.0:
				_finish(false, "farm_meat_180_not_gathered")
		"soldier_buttons":
			if phase_time > 0.5 and game != null:
				var btns: Dictionary = game.get("hud").get("_cmd_btns")
				var btn: Button = btns.get("soldier") as Button
				if btn == null or not btn.is_visible_in_tree():
					_finish(false, "soldier_train_button_missing_after_barracks_selection")
					return
				busy = true
				var click_data: Array = []
				var hud: Node = game.get("hud")
				if hud != null and hud.get_instance_id() != _diagnostic_signal_hud_id:
					_diagnostic_signal_hud_id = hud.get_instance_id()
					if hud.has_signal("train_soldier_pressed"):
						hud.connect("train_soldier_pressed", _on_diagnostic_train_signal)
				for i in 3:
					btns = game.get("hud").get("_cmd_btns")
					btn = btns.get("soldier") as Button
					if btn == null:
						click_data.append({"attempt":i + 1,"button_missing":true,"game_time":game.get("_game_time"),"queue":_train_queue(barracks)})
						break
					var before := _military_click_state(game, barracks, btn)
					var path := str(btn.get_path())
					_diagnostic_button_press_count = 0
					btn.pressed.connect(_on_diagnostic_button_press, CONNECT_ONE_SHOT)
					var train_signals_before := _diagnostic_train_signal_count
					await _click_control(btn)
					var click_probe := _last_click_data.duplicate(true)
					await get_tree().create_timer(0.25).timeout
					var after := _military_click_state(game, barracks, btns.get("soldier") as Button)
					var rect: Rect2 = Rect2(before.button_rect[0], before.button_rect[1], before.button_rect[2], before.button_rect[3])
					var click_point := Vector2(click_probe.position[0], click_probe.position[1])
					click_data.append({"attempt":i + 1,"control":path,"before":before,"after":after,"input":click_probe,"clicked_inside_button_rect":rect.has_point(click_point),"button_pressed_signal_count":_diagnostic_button_press_count,"hud_train_signal_delta":_diagnostic_train_signal_count - train_signals_before,"message_after_click":after.get("hud_message", "")})
				events.append({"action":"soldier_train_button_clicks","clicks":click_data,"queued":_train_queue(barracks),"meat":game.get("meat"),"wood":game.get("wood"),"population":game.get("population"),"queued_pop":game.call("_queued_pop"),"pop_cap":game.get("pop_cap"),"selected":game.get("selected").size()})
				queue_snapshot = _train_queue(barracks).duplicate()
				if queue_snapshot.is_empty():
					_finish(false, "soldier_queue_empty_after_visible_button_clicks")
					return
				queue_saved = true
				saved_game_id = game.get_instance_id()
				_checkpoint("nonempty_soldier_queue_before_save", game)
				await _send_key(KEY_F5)
				await _send_key(KEY_F9)
				phase = "wait_reload"
				phase_time = 0.0
				busy = false
		"wait_reload":
			if game != null and game.get_instance_id() != saved_game_id:
				barracks = _building(Catalog.BARRACKS, true)
				farm = _building(Catalog.FARM, true)
				var restored_queue := _train_queue(barracks)
				reload_checked = restored_queue == queue_snapshot
				events.append({"action":"f5_f9_nonempty_military_queue_restore","saved_queue":queue_snapshot,"restored_queue":restored_queue,"fields_match":reload_checked,"game_time":game.get("_game_time"),"meat":game.get("meat"),"wood":game.get("wood")})
				_checkpoint("military_queue_restored", game)
				if not reload_checked:
					_finish(false, "f9_military_queue_mismatch")
					return
				phase = "wait_soldiers"
				phase_time = 0.0
			elif phase_time > 20.0:
				_finish(false, "military_f9_reload_timeout")
		"wait_soldiers":
			if game != null and _player_military().size() >= 2:
				_checkpoint("two_player_soldiers_spawned", game)
				phase = "wait_wave"
				phase_time = 0.0
			elif phase_time > 110.0:
				_finish(false, "two_soldiers_not_spawned")
		"wait_wave":
			if game != null and int(game.get("_horde_wave")) >= 1:
				_checkpoint("wave_one_visible", game)
				phase = "combat"
				phase_time = 0.0
				sample_clock = 0.0
			elif phase_time > 250.0:
				_finish(false, "wave_one_not_reached")
		"combat":
			if game == null:
				return
			_sample(game)
			if not attack_order_issued:
				var enemies := _living_zombies()
				if not enemies.is_empty():
					var target: Node3D = enemies[0]
					var screen: Vector2 = game.get("camera").unproject_position(target.global_position + Vector3(0, 0.7, 0))
					var size := get_viewport().get_visible_rect().size
					if screen.x >= 0 and screen.x < size.x and screen.y >= 0 and screen.y < size.y:
						busy = true
						await _send_key(KEY_F2)
						var selected_player_military: int = game.get("selected").filter(func(u): return is_instance_valid(u) and str(u.get("team")) == "player" and u.is_in_group("military")).size()
						await _send_key(KEY_A)
						await _click(screen, "visible zombie %s" % target.name)
						attack_order_issued = true
						events.append({"action":"visible_enemy_attack_order","target":target.name,"target_position":_v3(target.global_position),"screen_position":[screen.x,screen.y],"selected_player_military_before_order":selected_player_military,"target_alive":target.get("alive"),"player_selected_after_order":game.get("selected").filter(func(u): return is_instance_valid(u) and str(u.get("team")) == "player" and u.is_in_group("military")).size()})
						_checkpoint("attack_order_issued_to_visible_zombie", game)
						busy = false
			if bool(game.get("_defeated")) or bool(game.get("_victorious")) or (not bool(game.get("_horde_active")) and int(game.get("_horde_wave")) >= 1 and game.get("_horde_spawn_queue").is_empty()):
				_checkpoint("wave_outcome", game)
				_finish(true, "combat_observation_completed")
			elif phase_time > 110.0:
				_finish(true, "bounded_combat_observation_completed")

func _start_seed42(game: Node) -> void:
	var field: LineEdit = game.get("_seed_edit") as LineEdit
	var mode: OptionButton = game.get("_start_mode_select") as OptionButton
	if field == null or mode == null or mode.get_selected_id() != 0:
		_finish(false, "endless_start_menu_controls_unavailable")
		return
	await _click_control(field)
	await _send_key(KEY_4, 52)
	await _send_key(KEY_2, 50)
	var start := _button(game.get("_start_layer"), "开始游戏")
	if start == null:
		_finish(false, "start_game_button_missing")
		return
	var seed_text := field.text
	var mode_id := mode.get_selected_id()
	if seed_text != "42":
		_finish(false, "seed42_viewport_input_failed")
		return
	await _click_control(start)
	events.append({"action":"start_menu_seed_input","seed":seed_text,"mode":mode_id,"route":"Viewport.push_input"})
	phase = "start_wait"
	phase_time = 0.0
	busy = false

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

func _click_control(control: Control) -> void:
	var p := control.get_global_rect().get_center()
	await _click(p, str(control.get_path()))

func _on_diagnostic_button_press() -> void:
	_diagnostic_button_press_count += 1

func _on_diagnostic_train_signal() -> void:
	_diagnostic_train_signal_count += 1

func _click_world(game: Node, world: Vector3, label: String) -> void:
	await _click(game.get("camera").unproject_position(world), label)

func _click(p: Vector2, label: String) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hover := get_viewport().gui_get_hovered_control()
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
	_last_click_data = {"input":"Viewport.push_input mouse","target":label,"position":[p.x,p.y],"hovered_control":str(hover.get_path()) if hover else "","hit_world":hover == null}
	events.append(_last_click_data.duplicate(true))

func _button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text.contains(text):
			return b
	return null

func _wood_nodes() -> Array:
	return get_tree().get_nodes_in_group("resources").filter(func(n): return is_instance_valid(n) and int(n.get("kind")) == 0)

func _building(kind: int, complete: bool) -> Node3D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.get("kind")) == kind and (not complete or bool(b.get("is_complete"))):
			return b as Node3D
	return null

func _train_queue(b: Variant) -> Array:
	if not is_instance_valid(b): return []
	var q: Variant = b.get("train_queue")
	return q.duplicate() if q is Array else []

func _count_group(group: String) -> int:
	return get_tree().get_nodes_in_group(group).filter(func(n): return is_instance_valid(n) and bool(n.get("alive")) and str(n.get("team")) == "player").size()

func _player_military() -> Array:
	return get_tree().get_nodes_in_group("military").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")) and str(n.get("team")) == "player")

func _military_click_state(game: Node, training_building: Variant, button: Button) -> Dictionary:
	var hud: Node = game.get("hud")
	var selected: Array = game.get("selected")
	var selected_names: Array[String] = []
	for item in selected:
		if is_instance_valid(item): selected_names.append(str(item.name))
	var rect := button.get_global_rect() if is_instance_valid(button) else Rect2()
	var msg := ""
	if hud != null:
		var label: Variant = hud.get("_msg_l")
		if label is Label: msg = str(label.text)
	return {
		"real_elapsed":elapsed,"game_time":game.get("_game_time"),"meat":game.get("meat"),"wood":game.get("wood"),"gold":game.get("gold"),
		"population":game.get("population"),"queued_pop":game.call("_queued_pop"),"pop_cap":game.get("pop_cap"),
		"selected":selected_names,"barracks_selected":selected.any(func(n): return is_instance_valid(n) and n == training_building),
		"queue":_train_queue(training_building),"train_paid":training_building.get("train_paid") if is_instance_valid(training_building) else null,
		"train_paused":training_building.get("train_paused") if is_instance_valid(training_building) else null,
		"train_timer":training_building.get("train_timer") if is_instance_valid(training_building) else null,
		"button_exists":is_instance_valid(button),"button_visible":button.is_visible_in_tree() if is_instance_valid(button) else false,
		"button_disabled":button.disabled if is_instance_valid(button) else null,"button_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],
		"button_hovered":button.is_hovered() if is_instance_valid(button) else false,"hud_message":msg
	}

func _track_military(game: Node) -> void:
	var b := _building(Catalog.BARRACKS, true)
	if not is_instance_valid(b): return
	var bid := b.get_instance_id()
	var queue := _train_queue(b)
	var paid := bool(b.get("train_paid"))
	var army: Array[String] = []
	for unit in _player_military(): army.append(str(unit.name))
	if bid != _tracked_barracks_id:
		_tracked_barracks_id = bid
		_last_tracked_queue = queue.duplicate()
		_last_tracked_train_paid = paid
		_last_tracked_army = army.duplicate()
		return
	if queue != _last_tracked_queue or paid != _last_tracked_train_paid or army != _last_tracked_army:
		var army_state: Array[Dictionary] = []
		for unit in _player_military(): army_state.append({"name":unit.name,"hp":unit.get("hp"),"pos":_v3(unit.global_position)})
		events.append({"action":"military_runtime_transition","real_elapsed":elapsed,"game_time":game.get("_game_time"),"queue_before":_last_tracked_queue,"queue_after":queue,"train_paid":paid,"train_paused":b.get("train_paused"),"train_timer":b.get("train_timer"),"resources":{"meat":game.get("meat"),"wood":game.get("wood"),"gold":game.get("gold")},"population":game.get("population"),"queued_pop":game.call("_queued_pop"),"pop_cap":game.get("pop_cap"),"army_names":army,"army":army_state})
		_last_tracked_queue = queue.duplicate()
		_last_tracked_train_paid = paid
		_last_tracked_army = army.duplicate()

func _living_zombies() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(n): return is_instance_valid(n) and bool(n.get("alive")))

func _sample(game: Node) -> void:
	sample_clock += get_process_delta_time()
	if sample_clock < 0.5: return
	sample_clock = 0.0
	var army: Array = []
	for u in _player_military():
		army.append({"name":u.name,"pos":_v3(u.global_position),"hp":u.get("hp"),"state":u.get("state"),"target":str(u.get("attack_target").name) if u.get("attack_target") != null and is_instance_valid(u.get("attack_target")) else "","alive":u.get("alive")})
	var foes: Array = []
	for z in _living_zombies():
		foes.append({"name":z.name,"pos":_v3(z.global_position),"hp":z.get("hp"),"state":z.get("state"),"target":str(z.get("attack_target").name) if z.get("attack_target") != null and is_instance_valid(z.get("attack_target")) else "","alive":z.get("alive")})
	var buildings: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and str(b.get("team")) == "player":
			buildings.append({"name":b.name,"kind":b.get("kind"),"hp":b.get("hp"),"pos":_v3(b.global_position),"complete":b.get("is_complete")})
	samples.append({"real_elapsed":elapsed,"game_time":game.get("_game_time"),"wave":game.get("_horde_wave"),"active":game.get("_horde_active"),"player_military":army,"zombies":foes,"buildings":buildings,"defeated":game.get("_defeated")})
	if samples.size() % 20 == 0:
		_persist()

func _snapshot(game: Node) -> Dictionary:
	return {"game_time":game.get("_game_time"),"wave":game.get("_horde_wave"),"wood":game.get("wood"),"meat":game.get("meat"),"military":_player_military().size(),"zombies":_living_zombies().size(),"villagers":_villager_debug(),"farm_complete":is_instance_valid(farm) and bool(farm.get("is_complete")),"farm_stock":farm.get("meat_stock") if is_instance_valid(farm) else -1,"barracks_complete":is_instance_valid(barracks) and bool(barracks.get("is_complete")),"soldier_queue":_train_queue(barracks)}

func _villager_debug() -> Array:
	var result: Array = []
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and bool(v.get("alive")):
			var target: Variant = v.get("gather_target")
			result.append({"name":v.name,"pos":_v3(v.global_position),"state":v.get("state"),"gather_target":str(target.name) if target != null and is_instance_valid(target) else "","resume_key":v.get("resume_key"),"carry_key":v.get("carry_key"),"carry_amount":v.get("carry_amount")})
	return result

func _checkpoint(label: String, game: Node) -> void:
	checkpoint_seq += 1
	records.append({"seq":checkpoint_seq,"name":label,"elapsed":elapsed,"snapshot":_snapshot(game)})
	_persist()

func _v3(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _finish(ok: bool, reason: String) -> void:
	done = true
	events.append({"action":"finish","success":ok,"reason":reason,"elapsed":elapsed,"samples":samples.size(),"combat_observation":_combat_summary()})
	_persist()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _combat_summary() -> Dictionary:
	if samples.is_empty(): return {"available":false,"reason":"no_combat_samples"}
	var first: Dictionary = samples.front()
	var last: Dictionary = samples.back()
	var initial_army: Dictionary = {}
	var final_army: Dictionary = {}
	var initial_foes: Dictionary = {}
	var final_foes: Dictionary = {}
	for unit in first.get("player_military",[]): initial_army[str(unit.get("name"))] = float(unit.get("hp",0.0))
	for unit in last.get("player_military",[]): final_army[str(unit.get("name"))] = float(unit.get("hp",0.0))
	for foe in first.get("zombies",[]): initial_foes[str(foe.get("name"))] = float(foe.get("hp",0.0))
	for foe in last.get("zombies",[]): final_foes[str(foe.get("name"))] = float(foe.get("hp",0.0))
	var shared_army_loss := 0.0
	for name in initial_army:
		if final_army.has(name): shared_army_loss += maxf(0.0, initial_army[name] - final_army[name])
	var shared_foe_loss := 0.0
	for name in initial_foes:
		if final_foes.has(name): shared_foe_loss += maxf(0.0, initial_foes[name] - final_foes[name])
	return {"available":true,"sample_count":samples.size(),"first_real_elapsed":first.get("real_elapsed"),"last_real_elapsed":last.get("real_elapsed"),"first_game_time":first.get("game_time"),"last_game_time":last.get("game_time"),"army_count_start":first.get("player_military",[]).size(),"army_count_end":last.get("player_military",[]).size(),"army_names_start":initial_army.keys(),"army_names_end":final_army.keys(),"army_hp_loss_for_survivors":shared_army_loss,"army_units_lost_since_first_sample":initial_army.keys().filter(func(n): return not final_army.has(n)),"zombie_count_start":first.get("zombies",[]).size(),"zombie_count_end":last.get("zombies",[]).size(),"zombie_hp_loss_for_survivors":shared_foe_loss,"zombies_absent_at_end_from_first_sample":initial_foes.keys().filter(func(n): return not final_foes.has(n))}

func _persist() -> void:
	var data := {"schema":1,"mode":"seed42_natural_military_and_combat_viewport","ordinary_os_input_verified":false,"done":done,"success":done and bool(events.back().get("success",false)),"phase":phase,"elapsed":elapsed,"events":events,"checkpoints":records,"continuous_combat_samples":samples,"last_snapshot":_snapshot(last_game) if is_instance_valid(last_game) else {},"save_restore_nonempty_queue":queue_saved and reload_checked}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data,"\t"))
		f.close()
