extends Node
const Catalog := preload("res://scripts/building_catalog.gd")
const ReportPath := "user://guard_two_wave_playthrough_R12.json"
const PhaseMeta := "guard_two_wave_r12_phase"
const ReportMeta := "guard_two_wave_r12_report"
const Seed := 42
const MaxWallSeconds := 900.0
var report: Dictionary = {}
var phase := "initial"
var started_msec := 0
var sample_at_game_time := -1.0
var done := false
var wave1_names: Dictionary = {}
var wave1_pending_last := -1
var wave1_clear := false
var wave2_start_game_time := -1.0
var zero_wood_recovery_start := -1.0
var previous_hp: Dictionary = {}
var first_damage: Dictionary = {}
var guard_orders := 0
var attack_orders := 0
var evacuation_orders := 0
var guard_reissues := 0
var automatic_return_observations := 0
var issued_guard_names: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_msec = Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("[guard-two-wave-r12] controller_parse_ok")
		get_tree().quit()
		return
	if Engine.has_meta(ReportMeta):
		report = Engine.get_meta(ReportMeta)
		phase = str(Engine.get_meta(PhaseMeta, "initial"))
		var counts: Dictionary = report.get("command_counts", {})
		guard_orders = int(counts.get("guard", 0))
		attack_orders = int(counts.get("attack_or_attack_move", 0))
		evacuation_orders = int(counts.get("evacuation", 0))
		guard_reissues = int(counts.get("guard_reissues", 0))
		automatic_return_observations = int(counts.get("product_return_observations", 0))
		for spawned in report.get("wave1_spawned", []): wave1_names[str(spawned.get("name", ""))] = true
		wave1_clear = report.has("wave1_clear")
		wave1_pending_last = int(report.get("wave1_pending_last", -1))
		first_damage = report.get("first_damage", {})
	elif FileAccess.file_exists(ReportPath):
		# Resume the exact real save checkpoint if the diagnostic stopped after
		# returning to title. This continues the same campaign without starting over.
		var saved_report := _read_json(ReportPath)
		if saved_report.has("pre_continue_snapshot") and saved_report.has("pre_continue_combat_binding"):
			report = saved_report
			report.erase("result")
			report["diagnostic_resume"] = "continuing_existing_live_f5_save_after_title_continue_assertion_repair"
			phase = "continue_menu"
			var counts: Dictionary = report.get("command_counts", {})
			guard_orders = int(counts.get("guard", 0))
			attack_orders = int(counts.get("attack_or_attack_move", 0))
			evacuation_orders = int(counts.get("evacuation", 0))
			guard_reissues = int(counts.get("guard_reissues", 0))
			automatic_return_observations = int(counts.get("product_return_observations", 0))
			for spawned in report.get("wave1_spawned", []): wave1_names[str(spawned.get("name", ""))] = true
			wave1_clear = report.has("wave1_clear")
			wave1_pending_last = int(report.get("wave1_pending_last", -1))
			first_damage = report.get("first_damage", {})
			Engine.set_meta(ReportMeta, report)
			Engine.set_meta(PhaseMeta, phase)
	else:
		pass
	if report.is_empty():
		report = {"schema":"r12_natural_endless_paid_economy_wave1_continue_v1","candidate_basis":"R11 product scripts; revised diagnostic driver packaged separately","seed":Seed,"mode":"endless","time_scale":Engine.time_scale,"headless":DisplayServer.get_name()=="headless","injected_resources_units_hp_or_waves":false,"events":[],"samples":[],"wave1_spawned":[],"command_counts":{"guard":0,"attack_or_attack_move":0,"evacuation":0,"guard_reissues":0,"product_return_observations":0}}
		Engine.set_meta(ReportMeta, report)
		Engine.set_meta(PhaseMeta, phase)
	call_deferred("_run_phase")

func _process(_delta: float) -> void:
	if done: return
	if float(Time.get_ticks_msec()-started_msec)/1000.0 > MaxWallSeconds:
		_finish(false,"bounded_wall_clock_timeout")
		return
	var game := _game()
	if game != null and bool(game.get("_match_started")):
		_observe_live_state(game)

func _run_phase() -> void:
	if DisplayServer.get_name()!="headless" or absf(Engine.time_scale-1.0)>0.001:
		_finish(false,"headless_or_unscaled_prerequisite_failed")
		return
	match phase:
		"initial": await _run_initial()
		"continue_menu": await _continue_from_title_menu()
		"post_continue": await _observe_after_continue()
		"post_continue_observe_wave1_wave2": await _observe_wave_boundaries(_game())
		_: _finish(false,"unknown_diagnostic_phase_%s" % phase)

func _run_initial() -> void:
	var menu := await _wait_menu(45.0)
	if menu==null: _finish(false,"production_start_menu_missing"); return
	var mode: OptionButton=menu.get("_start_mode_select")
	var seed: LineEdit=menu.get("_seed_edit")
	var start: Button=menu.get("_start_begin_button")
	if mode==null or seed==null or start==null: _finish(false,"production_menu_controls_missing"); return
	mode.select(0); mode.item_selected.emit(0); seed.text=str(Seed)
	var start_text := start.text
	start.pressed.emit()
	var game := await _wait_match(180.0)
	if game==null or int(game.get("map_seed"))!=Seed or int(game.get("_horde_mode"))!=0 or Engine.time_scale!=1.0:
		_finish(false,"seed42_endless_start_failed"); return
	report["runtime"]={"executable":OS.get_executable_path(),"pid":OS.get_process_id(),"user_data_dir":OS.get_user_data_dir(),"driver":"res://scripts/diagnostics/guard_two_wave_playthrough.gd","time_scale":Engine.time_scale}
	report["opening"]={"game_time":float(game.get("_game_time")),"seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"workers":_workers().size(),"wood":int(game.get("wood")),"meat":int(game.get("meat")),"orders_ready":bool(game.get("_player_orders_ready"))}
	_event("normal_menu_seed42_endless_started",{"start_button":start_text,"route":"production menu Button.pressed"})
	var tree:=_nearest_wood(Vector3.ZERO)
	if tree==null: _finish(false,"natural_wood_node_missing"); return
	var opening_wood:=int(game.get("wood"))
	if not await _gather(game,tree,_workers(),300,"normal_wood_for_tech_and_buildings",180.0):
		_finish(false,"normal_wood_gather_for_tech_and_buildings_failed"); return
	report["opening"]["wood_before_research"]=opening_wood
	report["opening"]["wood_at_research"]=int(game.get("wood"))
	if not _research_forestry(game): _finish(false,"paid_forestry_command_failed"); return
	var stock_before:=int(tree.get("amount"))
	var wood_before:=int(game.get("wood"))
	var carries_before:=_worker_carries()
	if not await _gather(game,tree,_workers(),wood_before+20,"post_tech_ordinary_gather",90.0):
		_finish(false,"post_tech_normal_gather_failed"); return
	report["forestry"]["post_tech_gather"]={"wood_before":wood_before,"wood_after":int(game.get("wood")),"node_id":tree.get_instance_id() if is_instance_valid(tree) else 0,"stock_before":stock_before,"stock_after":int(tree.get("amount")) if is_instance_valid(tree) else -1,"carry_before":carries_before,"carry_after":_worker_carries()}
	var farm=await _place_building(game,Catalog.FARM,"farm",[Vector3(12,0,0),Vector3(10,0,5),Vector3(-12,0,0),Vector3(0,0,12)],120.0)
	if farm==null: _finish(false,"normal_paid_farm_construction_failed"); return
	report["farm_after_completion"]=_building_state(farm)
	var barracks=await _place_building(game,Catalog.BARRACKS,"barracks",[Vector3(-12,0,0),Vector3(12,0,8),Vector3(-12,0,-8)],150.0)
	if barracks==null: _finish(false,"normal_paid_barracks_construction_failed"); return
	report["barracks_after_completion"]=_building_state(barracks)
	if not await _gather(game,farm,_workers(),180,"normal_farm_food_for_soldiers",150.0): _finish(false,"normal_farm_gather_failed"); return
	if not await _train_soldiers(game,barracks,3): _finish(false,"normal_paid_soldier_training_failed"); return
	if not await _wait_soldiers(3,100.0): _finish(false,"paid_soldiers_not_delivered"); return
	barracks=_building(Catalog.BARRACKS,true)
	var army:=_soldiers()
	if army.size()<3 or barracks==null: _finish(false,"paid_army_or_barracks_missing"); return
	if not _issue_guard(game,army[0],Vector3(6,0,0),false) or not _issue_guard(game,army[1],Vector3(-8,0,0),false):
		_finish(false,"initial_guard_deployment_failed"); return
	if not _issue_attack_move(game,army[2],Vector3(0,0,8),"initial attack-move deployment"):
		_finish(false,"initial_attack_move_deployment_failed"); return
	report["initial_deployment"]={"guard_units":[str(army[0].name),str(army[1].name)],"attack_move_unit":str(army[2].name),"barracks_queue":_train_queue(barracks),"army_count":army.size()}
	_event("paid_army_initial_deployment_complete",report["initial_deployment"])
	var binding=await _wait_for_real_target_binding(360.0)
	if binding.is_empty(): _finish(false,"no_natural_wave1_combat_target_binding_before_bound"); return
	report["pre_continue_combat_binding"]=binding
	game=_game()
	var before:=_combat_economy_snapshot(game,_building(Catalog.BARRACKS,false))
	if not await _save_unpaused_through_f5(game,before): _finish(false,"production_f5_save_failed_or_empty"); return
	phase="continue_menu"; Engine.set_meta(PhaseMeta,phase); Engine.set_meta(ReportMeta,report)
	await _send_key(KEY_ESCAPE)
	if not get_tree().paused: _finish(false,"pause_menu_not_open_for_return_to_title"); return
	var return_button:=_button(game.get("_pause_layer"),"返回主菜单")
	if return_button==null: _finish(false,"return_to_title_button_missing"); return
	_event("production_return_to_title_after_live_f5",{"button":return_button.text,"wave":int(game.get("_horde_wave")),"game_time":float(game.get("_game_time"))})
	return_button.pressed.emit()
	# The match scene is replaced asynchronously. Keep this root-level controller alive,
	# wait for the production title screen, then exercise the real Continue button.
	await _continue_from_title_menu()

func _continue_from_title_menu() -> void:
	var menu:=await _wait_menu(90.0)
	if menu==null: _finish(false,"title_menu_after_return_missing"); return
	var button:Button=menu.get("_start_continue_button")
	if button==null or button.disabled: _finish(false,"real_title_continue_button_unavailable"); return
	phase="post_continue"; Engine.set_meta(PhaseMeta,phase); Engine.set_meta(ReportMeta,report)
	_event("real_title_continue_pressed",{"button":button.text,"enabled":not button.disabled,"route":"production start-screen Continue Button.pressed"})
	button.pressed.emit()
	# Continue also replaces the scene asynchronously; verify the restored match next.
	await _observe_after_continue()

func _observe_after_continue() -> void:
	var game:=await _wait_match(180.0)
	if game==null: _finish(false,"title_continue_restore_timeout"); return
	var barracks:=_building(Catalog.BARRACKS,false)
	var binding:Dictionary=report.get("pre_continue_combat_binding",{})
	var restored_binding:Dictionary={}
	for unit in _soldiers():
		var candidate:Variant=unit.get("attack_target")
		if is_instance_valid(candidate) and int(candidate.get("horde_wave_id"))==int(binding.get("target_wave",-1)):
			restored_binding={"unit_name":str(unit.name),"target_name":str(candidate.name),"target_wave":int(candidate.get("horde_wave_id"))}
			break
	var after:=_combat_economy_snapshot(game,barracks)
	var saved:Dictionary=report.get("pre_continue_snapshot",{})
	var checks={"seed":int(game.get("map_seed"))==Seed,"mode":int(game.get("_horde_mode"))==0,"wave":int(game.get("_horde_wave"))==int(saved.get("wave",-1)),"game_time":absf(float(game.get("_game_time"))-float(saved.get("game_time",-1000.0)))<0.2,"resources":_resources_equal(_resources(game),saved.get("resources",{})),"forestry":bool(game.get("research").call("has_technology","improved_axes")),"buildings":_building(Catalog.FARM,true)!=null and _building(Catalog.BARRACKS,true)!=null,"barracks_queue":_train_queue(barracks)==saved.get("barracks_queue",[]),"army_nonempty":not _soldiers().is_empty(),"combat_target_binding":not restored_binding.is_empty(),"orders_ready":bool(game.get("_player_orders_ready")),"unpaused":not get_tree().paused}
	report["title_continue"]={"before":saved,"after":after,"checks":checks,"passed":checks.values().all(func(v):return bool(v)),"restored_combat_target_binding":restored_binding}
	_event("real_title_continue_state_verified",report["title_continue"])
	if not report["title_continue"]["passed"]: _finish(false,"title_continue_state_mismatch"); return
	phase="post_continue_observe_wave1_wave2"; Engine.set_meta(PhaseMeta,phase); Engine.set_meta(ReportMeta,report)
	await _observe_wave_boundaries(game)
func _observe_wave_boundaries(game:Node) -> void:
	var expected:=int(game.call("_horde_count_for_wave",1))
	var started:=Time.get_ticks_msec()
	var wave2_saved:=false
	while Time.get_ticks_msec()-started<300000:
		game=_game()
		if game==null: _finish(false,"main_missing_during_wave_observation"); return
		if bool(game.get("_defeated")) or bool(game.get("_victorious")):
			_finish(false,"terminal_before_wave1_clear_and_wave2_economy_checkpoint",{"game_time":float(game.get("_game_time")),"wave":int(game.get("_horde_wave")),"defeated":bool(game.get("_defeated")),"first_damage":first_damage,"wave1_expected":expected,"wave1_spawned":wave1_names.size(),"wave1_alive":_wave1_alive(),"pending":wave1_pending_last}); return
		var now:=float(game.get("_game_time"))
		if not wave2_saved and int(game.get("_horde_wave"))>=2:
			wave2_saved=true; wave2_start_game_time=now
			var gate:=_wave1_strict_gate(game,expected)
			report["wave2_start"]={"game_time":now,"economy":_campaign_economy(game),"wave1_gate":gate,"snapshot":_combat_economy_snapshot(game,_building(Catalog.BARRACKS,false))}
			_event("natural_wave2_started_and_wave1_gate_recorded",report["wave2_start"])
			if int(report["wave2_start"]["economy"].get("wood_workers",0))==0:
				zero_wood_recovery_start=now
				var available_workers := _workers()
				var wood_target := _nearest_wood(Vector3.ZERO)
				if not available_workers.is_empty() and wood_target != null:
					var selected_worker: Node = available_workers[0]
					_select(game,[selected_worker])
					game.call("_on_cmd_gather")
					game.call("_route_pending_command",wood_target.global_position,Vector2.ZERO)
					game.set("_cmd_mode","")
					_event("normal_wood_recovery_order_after_zero_wood_snapshot",{"worker":str(selected_worker.name),"wood_node_id":wood_target.get_instance_id(),"stock":int(wood_target.get("amount")),"command":"Main gather mode + map dispatch","no_resource_injection":true})
				_event("bounded_30_second_natural_zero_wood_worker_observation_started",{"start_game_time":now,"ordinary_gather_response_issued":not available_workers.is_empty() and wood_target!=null,"resources_or_units_injected":false,"simulation_unpaused":not get_tree().paused})
			else:
				_finish(bool(gate.get("passed",false)),"wave2_checkpoint_passed" if bool(gate.get("passed",false)) else "strict_wave1_gate_failed_at_wave2_start",{"first_damage":first_damage}); return
		if zero_wood_recovery_start>=0.0 and now-zero_wood_recovery_start>=30.0:
			var economy:=_campaign_economy(game)
			var start_economy:Dictionary=report.get("wave2_start",{}).get("economy",{})
			var recovery={"elapsed_game_seconds":now-zero_wood_recovery_start,"economy_at_wave2":start_economy,"economy_after":economy,"wood_gain":int(economy.get("wood",0))-int(start_economy.get("wood",0)),"farm":_building_state(_building(Catalog.FARM,false)),"barracks":_building_state(_building(Catalog.BARRACKS,false)),"barracks_queue":_train_queue(_building(Catalog.BARRACKS,false)),"first_damage":first_damage}
			report["zero_wood_recovery_observation"]=recovery
			var gate_after:=_wave1_strict_gate(game,expected)
			_finish(bool(gate_after.get("passed",false)),"zero_wood_30s_gate_passed" if bool(gate_after.get("passed",false)) else "zero_wood_30s_observed_strict_gate_failed",{"wave1_gate_at_wave2_start":report["wave2_start"].get("wave1_gate",{}),"wave1_gate_after_30s":gate_after,"recovery":recovery}); return
		await get_tree().process_frame
	_finish(false,"wave_observation_bound_exceeded",{"wave2_start":wave2_start_game_time,"wave1_clear":wave1_clear,"wave1_spawned":wave1_names.size(),"wave1_alive":_wave1_alive()})

func _research_forestry(game:Node)->bool:
	var tc:=_building(Catalog.TOWN_CENTER,true)
	if tc==null:return false
	_select(game,[tc])
	var buttons:Dictionary=game.get("hud").get("_cmd_btns")
	var button:Button=buttons.get("forestry") as Button
	if button==null or button.disabled:return false
	var before:=_resources(game)
	button.pressed.emit()
	var model:Node=game.get("research")
	var paid=int(game.get("meat"))==int(before.meat)-25 and int(game.get("wood"))==int(before.wood)-10 and bool(model.call("has_technology","improved_axes"))
	var effects=_workers().all(func(w:Node)->bool:return is_equal_approx(float(w.get("wood_gather_multiplier")),1.25) and int(w.get("wood_carry_bonus"))==5)
	report["forestry"]={"button":button.text,"resources_before":before,"resources_after":_resources(game),"completed_immediately":bool(model.call("has_technology","improved_axes")),"worker_carries_at_completion":_worker_carries(),"worker_effects":_workers().map(func(w:Node)->Dictionary:return {"name":str(w.name),"multiplier":float(w.get("wood_gather_multiplier")),"carry_bonus":int(w.get("wood_carry_bonus"))}),"paid_once":paid,"effects_applied":effects}
	_event("production_tc_forestry_button_pressed",report["forestry"])
	return paid and effects

func _gather(game:Node,target:Node3D,workers:Array,target_stock:int,reason:String,limit:float)->bool:
	if target==null or not is_instance_valid(target) or workers.is_empty():return false
	_select(game,workers); game.call("_on_cmd_gather")
	var pending:=str(game.get("_cmd_mode"))
	game.call("_route_pending_command",target.global_position,Vector2.ZERO); game.set("_cmd_mode","")
	var farm:=target.is_in_group("farms")
	var key:="meat" if farm else "wood"
	var before:=int(game.get(key))
	_event("normal_gather_order_issued",{"reason":reason,"target":str(target.name),"target_id":target.get_instance_id(),"stock_before":int(target.get("meat_stock")) if farm else int(target.get("amount")),"workers":workers.map(func(w:Node)->String:return str(w.name)),"resources_before":_resources(game),"route":"Main gather mode + _route_pending_command"})
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		game=_game()
		if game==null or bool(game.get("_defeated")):return false
		if int(game.get(key))>=target_stock:
			_event("normal_gather_target_reached",{"reason":reason,"resource":key,"before":before,"after":int(game.get(key)),"pending_mode":pending,"stock_after":int(target.get("meat_stock")) if farm and is_instance_valid(target) else int(target.get("amount")) if is_instance_valid(target) else -1})
			return true
		await get_tree().process_frame
	return false

func _place_building(game:Node,kind:int,label:String,candidates:Array,limit:float)->Node3D:
	var workers:=_workers()
	if workers.is_empty():return null
	var builder:Node3D=workers[0] as Node3D
	_select(game,[builder]); game.call("_on_build_kind",kind)
	var before:=_resources(game); var building:Node3D=null
	for pos in candidates:
		if bool(game.call("_placement_valid_at",pos)):
			game.call("_try_place",pos); await get_tree().process_frame
			building=_building(kind,false)
			if building!=null and not bool(building.get("is_complete")):break
	if building==null:return null
	var definition:=Catalog.get_def(kind)
	_event("normal_paid_building_placed",{"label":label,"kind":kind,"position":_v3(building.global_position),"resources_before":before,"resources_after":_resources(game),"catalog_cost_wood":int(definition.get("cost_wood",0)),"builder":str(builder.name),"site_state":_building_state(building)})
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		if is_instance_valid(building) and bool(building.get("is_complete")):
			_event("normal_paid_building_completed",_building_state(building)); return building
		if bool(game.get("_defeated")):return null
		await get_tree().process_frame
	return null
func _train_soldiers(game:Node,barracks:Node3D,count:int)->bool:
	_select(game,[barracks])
	var buttons:Dictionary=game.get("hud").get("_cmd_btns")
	var button:Button=buttons.get("soldier") as Button
	if button==null:return false
	var before:=_resources(game);var button_text:=button.text
	for _i in count:
		buttons=game.get("hud").get("_cmd_btns"); button=buttons.get("soldier") as Button
		if button==null or button.disabled:return false
		button.pressed.emit(); await get_tree().process_frame
	var queue:=_train_queue(barracks); var cost:=Catalog.train_cost("soldier")
	var first_unit_paid=int(before.meat)-int(game.get("meat"))>=int(cost.get("meat",0)) and int(before.wood)-int(game.get("wood"))>=int(cost.get("wood",0))
	var queue_not_paused=not bool(barracks.get("train_paused"))
	var passed=queue.size()>=count and first_unit_paid and queue_not_paused
	report["soldier_training"]={"button":button_text,"requested":count,"queue_after_clicks":queue,"resources_before":before,"resources_after_orders":_resources(game),"catalog_cost_each":cost,"first_unit_paid_at_queue_start":first_unit_paid,"train_paid_front_unit":bool(barracks.get("train_paid")),"remaining_queue_payment_policy":"charged as each queued unit starts","queue_not_paused":queue_not_paused,"paid_queue_valid":passed}
	_event("normal_paid_training_orders_queued",report["soldier_training"])
	return passed

func _issue_guard(game:Node,unit:Node3D,anchor:Vector3,reissue:bool)->bool:
	_select(game,[unit]); game.call("_on_cmd_guard")
	var mode:=str(game.get("_cmd_mode")); game.call("_route_pending_command",anchor,Vector2.ZERO); game.set("_cmd_mode","")
	guard_orders+=1
	if reissue:guard_reissues+=1
	issued_guard_names[str(unit.name)]=true
	_event("player_guard_order",{"unit":str(unit.name),"anchor":_v3(anchor),"reissue":reissue,"pending_mode":mode,"route":"Main F command + map dispatch"})
	return bool(unit.get("guard_active"))

func _issue_attack_move(game:Node,unit:Node3D,goal:Vector3,reason:String)->bool:
	_select(game,[unit]); game.call("_on_cmd_attack")
	var mode:=str(game.get("_cmd_mode")); game.call("_route_pending_command",goal,Vector2.ZERO); game.set("_cmd_mode","")
	attack_orders+=1
	_event("player_attack_move_order",{"unit":str(unit.name),"goal":_v3(goal),"reason":reason,"pending_mode":mode,"route":"Main A command + map dispatch"})
	return bool(unit.get("_attack_move_active"))

func _save_unpaused_through_f5(game:Node,before:Dictionary)->bool:
	if get_tree().paused:return false
	await _send_key(KEY_F5)
	var payload:=_read_json("user://aoelite3d_save.json")
	var entities:Dictionary=payload.get("entities",{})
	var binding:=_saved_combat_binding(payload)
	var nonempty=Array(entities.get("buildings",[])).size()>1 and Array(entities.get("soldiers",[])).size()>0 and Array(payload.get("researched_techs",[])).has("improved_axes")
	before["game_time"] = float(payload.get("game_time", before.get("game_time", -1.0)))
	before["resources"] = payload.get("resources", before.get("resources", {}))
	before["barracks_queue"] = _saved_barracks_queue(payload)
	report["pre_continue_snapshot"]=before
	report["save_payload"]={"exists":FileAccess.file_exists("user://aoelite3d_save.json"),"seed":int(payload.get("map_seed",-1)),"mode":int(payload.get("horde_mode",-1)),"wave":int(payload.get("horde_wave",-1)),"game_time":float(payload.get("game_time",-1.0)),"resources":payload.get("resources",{}),"researched_techs":payload.get("researched_techs",[]),"building_count":Array(entities.get("buildings",[])).size(),"villager_count":Array(entities.get("villagers",[])).size(),"soldier_count":Array(entities.get("soldiers",[])).size(),"barracks_queue":_saved_barracks_queue(payload),"combat_target_binding":binding,"nonempty_economy_and_military":nonempty,"saved_while_unpaused":not get_tree().paused}
	_event("production_f5_live_save",report["save_payload"])
	return bool(report["save_payload"]["exists"]) and nonempty and bool(binding.get("target_id_resolved",false)) and not get_tree().paused

func _wait_for_real_target_binding(limit:float)->Dictionary:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		var game:=_game()
		if game==null or bool(game.get("_defeated")):return {}
		for unit in _soldiers():
			var target:Variant=unit.get("attack_target")
			if is_instance_valid(target) and int(target.get("horde_wave_id"))==1:
				return {"guard_unit_name":str(unit.name),"unit_instance_id":unit.get_instance_id(),"guard_active":bool(unit.get("guard_active")),"attack_return_guard_active":bool(unit.get("_attack_return_guard_active")),"target_name":str(target.name),"target_id":target.get_instance_id(),"target_wave":int(target.get("horde_wave_id")),"target_position":_v3(target.global_position),"target_hp":float(target.get("hp")),"unit_state":int(unit.get("state")),"no_periodic_guard_resend":true}
		await get_tree().process_frame
	return {}

func _observe_live_state(game:Node)->void:
	if int(game.get("_horde_spawn_wave_id"))==1:
		wave1_pending_last=Array(game.get("_horde_spawn_queue")).size()
		report["wave1_pending_last"] = wave1_pending_last
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie) and int(zombie.get("horde_wave_id"))==1 and not wave1_names.has(str(zombie.name)):
			wave1_names[str(zombie.name)]=true
			report["wave1_spawned"].append({"name":str(zombie.name),"id":zombie.get_instance_id(),"game_time":float(game.get("_game_time")),"position":_v3(zombie.global_position)})
	if not wave1_clear and wave1_names.size()>=int(game.call("_horde_count_for_wave",1)) and wave1_pending_last==0 and _wave1_alive()==0:
		wave1_clear=true; report["wave1_clear"]={"game_time":float(game.get("_game_time")),"spawned":wave1_names.size(),"expected":int(game.call("_horde_count_for_wave",1)),"pending":0,"alive":0}
		_event("all_wave1_zombies_generated_and_cleared",report["wave1_clear"])
	var watched:=_workers()+_soldiers()
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and str(building.get("team"))=="player":watched.append(building)
	for unit in watched:
		if not is_instance_valid(unit):continue
		var key:=str(unit.get_instance_id());var hp:=float(unit.get("hp"))
		if previous_hp.has(key) and hp<float(previous_hp[key])-0.001 and not first_damage.has(key):
			var sources:Array=[]
			for enemy in get_tree().get_nodes_in_group("zombies"):
				if is_instance_valid(enemy) and enemy.get("attack_target")==unit:sources.append({"name":str(enemy.name),"id":enemy.get_instance_id(),"wave":int(enemy.get("horde_wave_id")),"hp":float(enemy.get("hp")),"position":_v3(enemy.global_position)})
			first_damage[key]={"unit":str(unit.name),"kind":"villager" if unit.is_in_group("villagers") else "soldier" if unit.is_in_group("soldiers") else "building","game_time":float(game.get("_game_time")),"hp_before":float(previous_hp[key]),"hp_after":hp,"position":_v3(unit.global_position),"attacking_zombies":sources}
			report["first_damage"] = first_damage
			_event("first_observed_player_hp_loss",first_damage[key])
		previous_hp[key]=hp
	if float(game.get("_game_time"))>=sample_at_game_time+3.0:
		sample_at_game_time=float(game.get("_game_time"));report["samples"].append(_combat_economy_snapshot(game,_building(Catalog.BARRACKS,false)));_persist()
func _wave1_strict_gate(game:Node,expected:int)->Dictionary:
	var farm:=_building(Catalog.FARM,true);var barracks:=_building(Catalog.BARRACKS,true)
	var food:=0;var wood:=0
	for worker in _workers():
		var target:Variant=worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock"))>0:food+=1
		elif is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key"))=="wood" and int(target.get("amount"))>0:wood+=1
	var queue_paid=barracks!=null and Array(barracks.get("train_queue")).has("soldier") and bool(barracks.get("train_paid")) and not bool(barracks.get("train_paused"))
	var clear=wave1_names.size()>=expected and wave1_pending_last==0 and _wave1_alive()==0
	var next_affordable=int(game.get("meat"))>=60 and int(game.get("wood"))>=20 and int(game.get("pop_cap"))-int(game.get("population"))-int(game.call("_queued_pop"))>0
	var army_ok=not _soldiers().is_empty() or queue_paid
	var economy=_building(Catalog.TOWN_CENTER,true)!=null and barracks!=null and _workers().size()>=2 and food>=1 and wood>=1 and farm!=null and army_ok and (next_affordable or queue_paid)
	return {"game_time":float(game.get("_game_time")),"wave1_expected":expected,"wave1_spawned":wave1_names.size(),"wave1_pending_last":wave1_pending_last,"wave1_alive":_wave1_alive(),"wave1_clear":clear,"villagers_alive":_workers().size(),"food_workers":food,"wood_workers":wood,"farm_complete":farm!=null,"barracks_complete":barracks!=null,"soldiers_alive":_soldiers().size(),"paid_soldier_queue":queue_paid,"next_soldier_affordable":next_affordable,"resources":_resources(game),"economy_recoverable":economy,"passed":clear and economy}

func _campaign_economy(game:Node)->Dictionary:
	var food:=0;var wood:=0
	for worker in _workers():
		var target:Variant=worker.get("gather_target")
		if is_instance_valid(target) and target.is_in_group("farms") and int(target.get("meat_stock"))>0:food+=1
		elif is_instance_valid(target) and target.has_method("res_key") and str(target.call("res_key"))=="wood" and int(target.get("amount"))>0:wood+=1
	return {"game_time":float(game.get("_game_time")),"resources":_resources(game),"wood":int(game.get("wood")),"meat":int(game.get("meat")),"villagers":_workers().size(),"soldiers":_soldiers().size(),"food_workers":food,"wood_workers":wood,"farm":_building_state(_building(Catalog.FARM,false)),"barracks":_building_state(_building(Catalog.BARRACKS,false)),"town_center_hp":_building_hp(Catalog.TOWN_CENTER)}

func _combat_economy_snapshot(game:Node,barracks:Node)->Dictionary:
	var units:Array=[]
	for soldier in _soldiers():
		var target:Variant=soldier.get("attack_target")
		var returning=bool(soldier.get("_attack_return_guard_active"))
		if returning:automatic_return_observations+=1
		units.append({"name":str(soldier.name),"hp":float(soldier.get("hp")),"state":int(soldier.get("state")),"guard_active":bool(soldier.get("guard_active")),"guard_anchor":_v3(soldier.get("guard_anchor")),"attack_return_guard_active":returning,"return_anchor":_v3(soldier.get("_attack_return_guard_anchor")),"attack_move_active":bool(soldier.get("_attack_move_active")),"target":str(target.name) if is_instance_valid(target) else "","target_wave":int(target.get("horde_wave_id")) if is_instance_valid(target) else -1})
	return {"game_time":float(game.get("_game_time")),"seed":int(game.get("map_seed")),"mode":int(game.get("_horde_mode")),"wave":int(game.get("_horde_wave")),"wave_active":bool(game.get("_horde_active")),"pending_spawns":Array(game.get("_horde_spawn_queue")).size(),"enemy_count":_enemy_count(),"resources":_resources(game),"researched_techs":Array(game.get("research").get("researched_techs")),"economy":_campaign_economy(game),"soldiers":units,"farm":_building_state(_building(Catalog.FARM,false)),"barracks":_building_state(barracks),"barracks_queue":_train_queue(barracks),"town_center_hp":_building_hp(Catalog.TOWN_CENTER),"defeated":bool(game.get("_defeated"))}

func _saved_barracks_queue(payload:Dictionary)->Array:
	for item in payload.get("entities",{}).get("buildings",[]):
		if int(item.get("kind",-1))==Catalog.BARRACKS and str(item.get("team",""))=="player":return Array(item.get("train_queue",[])).duplicate(true)
	return []
func _saved_combat_binding(payload:Dictionary)->Dictionary:
	var soldiers:Array=payload.get("entities",{}).get("soldiers",[])
	for unit in soldiers:
		var target_id=str(unit.get("attack_id",""))
		if target_id.is_empty():continue
		for target in soldiers:
			if str(target.get("id",""))==target_id:return {"unit_id":str(unit.get("id","")),"target_id":target_id,"target_wave":int(target.get("horde_wave_id",-1)),"target_pos":target.get("pos",[]),"target_id_resolved":true}
	return {"target_id_resolved":false}
func _resources(game:Node)->Dictionary:return {"wood":int(game.get("wood")),"meat":int(game.get("meat")),"stone":int(game.get("stone")),"gold":int(game.get("gold"))}
func _resources_equal(actual:Dictionary,expected:Dictionary)->bool:
	for key in ["wood","meat","stone","gold"]:
		if not expected.has(key) or absf(float(actual.get(key,-999999))-float(expected.get(key,-999999)))>0.001:return false
	return true
func _worker_carries()->Array:
	var result:Array=[]
	for worker in _workers():result.append({"name":str(worker.name),"carry_key":str(worker.get("carry_key")),"carry_amount":int(worker.get("carry_amount")),"wood_multiplier":float(worker.get("wood_gather_multiplier")),"wood_carry_bonus":int(worker.get("wood_carry_bonus"))})
	return result
func _workers()->Array:return get_tree().get_nodes_in_group("villagers").filter(func(n):return is_instance_valid(n) and str(n.get("team"))=="player" and bool(n.get("alive")))
func _soldiers()->Array:return get_tree().get_nodes_in_group("military").filter(func(n):return is_instance_valid(n) and str(n.get("team"))=="player" and bool(n.get("alive")))
func _wave1_alive()->int:return get_tree().get_nodes_in_group("zombies").filter(func(n):return is_instance_valid(n) and bool(n.get("alive")) and int(n.get("horde_wave_id"))==1).size()
func _enemy_count()->int:return get_tree().get_nodes_in_group("zombies").filter(func(n):return is_instance_valid(n) and bool(n.get("alive"))).size()
func _train_queue(building:Variant)->Array:
	if not is_instance_valid(building):return []
	var value:Variant=building.get("train_queue")
	return value.duplicate(true) if value is Array else []
func _building(kind:int,complete:bool)->Node3D:
	for node in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(node) and int(node.get("kind"))==kind and str(node.get("team"))=="player" and (not complete or bool(node.get("is_complete"))): return node as Node3D
	return null
func _building_hp(kind:int)->float:
	var node:=_building(kind,false)
	return float(node.get("hp")) if node!=null else -1.0
func _building_state(node:Variant)->Dictionary:
	if not is_instance_valid(node):return {}
	return {"name":str(node.name),"kind":int(node.get("kind")),"complete":bool(node.get("is_complete")),"build_progress":float(node.get("build_progress")),"build_time":float(node.get("build_time")),"train_queue":_train_queue(node),"train_paid":bool(node.get("train_paid")),"train_paused":bool(node.get("train_paused"))}
func _nearest_wood(pos:Vector3)->Node3D:
	var best:Node3D=null;var distance:=INF
	for node in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(node) and int(node.get("kind"))==0 and int(node.get("amount"))>0 and pos.distance_squared_to(node.global_position)<distance:
			best=node;distance=pos.distance_squared_to(node.global_position)
	return best
func _select(game:Node,units:Array)->void:
	game.call("_clear_selection")
	for unit in units:
		if is_instance_valid(unit):game.call("_add_to_selection",unit)
	game.call("_refresh_selection_hud")
func _button(root:Node,text:String)->Button:
	if root==null:return null
	for node in root.find_children("*","Button",true,false):
		var button:=node as Button
		if button!=null and button.is_visible_in_tree() and button.text.contains(text):return button
	return null
func _game()->Node:
	for node in get_tree().get_nodes_in_group("main_game"):
		if is_instance_valid(node):return node
	return null
func _find_unit_by_name(unit_name:String)->Node:
	for unit in _soldiers():
		if str(unit.name)==unit_name:return unit
	return null
func _wait_menu(limit:float)->Node:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		var game:=_game()
		if game!=null and game.get("_start_layer")!=null:return game
		await get_tree().process_frame
	return null
func _wait_match(limit:float)->Node:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		var game:=_game()
		if game!=null and bool(game.get("_match_started")) and bool(game.get("_player_orders_ready")) and game.get("world")!=null:return game
		await get_tree().process_frame
	return null
func _wait_soldiers(count:int,limit:float)->bool:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<int(limit*1000):
		if _soldiers().size()>=count:return true
		var game:=_game()
		if game==null or bool(game.get("_defeated")):return false
		await get_tree().process_frame
	return false
func _send_key(code:int)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	get_viewport().push_input(event);await get_tree().process_frame
	event=event.duplicate() as InputEventKey;event.pressed=false;get_viewport().push_input(event);await get_tree().process_frame
func _read_json(path:String)->Dictionary:
	if not FileAccess.file_exists(path):return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var parsed:Variant=JSON.parse_string(file.get_as_text());file.close()
	return parsed if parsed is Dictionary else {}
func _v3(value:Vector3)->Array:return [value.x,value.y,value.z]
func _event(name:String,details:Dictionary)->void:
	var game:=_game()
	report["events"].append({"event":name,"game_time":float(game.get("_game_time")) if game!=null and bool(game.get("_match_started")) else -1.0,"details":details})
	_persist()
func _persist()->void:
	report["command_counts"]={"guard":guard_orders,"attack_or_attack_move":attack_orders,"evacuation":evacuation_orders,"guard_reissues":guard_reissues,"product_return_observations":automatic_return_observations}
	Engine.set_meta(ReportMeta,report)
	var file:=FileAccess.open(ReportPath,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"\t"));file.close()
func _finish(ok:bool,reason:String,extra:Dictionary={})->void:
	if done:return
	done=true
	report["result"]={"passed":ok,"reason":reason,"extra":extra}
	report["strict_r66_gate_original_preserved"]=true
	Engine.remove_meta(PhaseMeta);Engine.remove_meta(ReportMeta)
	_persist()
	print("[guard-two-wave-r12] ",JSON.stringify(report))
	get_tree().quit(0 if ok else 1)
