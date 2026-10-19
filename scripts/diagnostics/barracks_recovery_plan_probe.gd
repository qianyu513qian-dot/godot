extends SceneTree
## Bounded check for recovery ordering against real catalog prices.
const Controller := preload("res://scripts/diagnostics/controlled_endless_defense.gd")

func _initialize() -> void:
	var controller: Node = Controller.new()
	var cases: Array[Dictionary] = [
		{"name":"224 wood cannot build barracks and reserve farm", "wood":224, "food":245, "farm_missing":true, "can_build":true, "preserve_farm":false, "recruit":true, "full":false},
		{"name":"225 wood can build barracks and reserve farm but not first soldier", "wood":225, "food":60, "farm_missing":true, "can_build":true, "preserve_farm":true, "recruit":true, "full":false},
		{"name":"244 wood is one short of full rebuild reserve", "wood":244, "food":60, "farm_missing":true, "can_build":true, "preserve_farm":true, "recruit":true, "full":false},
		{"name":"245 wood covers barracks farm and first soldier", "wood":245, "food":60, "farm_missing":true, "can_build":true, "preserve_farm":true, "recruit":true, "full":true},
		{"name":"food 59 cannot recruit first soldier", "wood":245, "food":59, "farm_missing":true, "can_build":true, "preserve_farm":true, "recruit":false, "full":false},
		{"name":"food 60 pays first soldier", "wood":245, "food":60, "farm_missing":true, "can_build":true, "preserve_farm":true, "recruit":true, "full":true},
		{"name":"active farm permits 170 wood and 60 food", "wood":170, "food":60, "farm_missing":false, "can_build":true, "preserve_farm":true, "recruit":true, "full":true},
		{"name":"active farm but only 169 wood cannot reserve first soldier", "wood":169, "food":60, "farm_missing":false, "can_build":true, "preserve_farm":true, "recruit":false, "full":false},
		{"name":"150 wood builds barracks but leaves no recruit cost", "wood":150, "food":60, "farm_missing":false, "can_build":true, "preserve_farm":true, "recruit":false, "full":false},
		{"name":"149 wood cannot build barracks", "wood":149, "food":60, "farm_missing":false, "can_build":false, "preserve_farm":true, "recruit":false, "full":false},
		{"name":"zero workers requires TC 50 plus soldier 60 food and two pop slots", "wood":245, "food":110, "farm_missing":true, "living_workers":0, "pop_room":2, "can_build":true, "preserve_farm":true, "recruit":true, "full":false},
		{"name":"zero workers with only 109 food cannot reserve both normal payments", "wood":245, "food":109, "farm_missing":true, "living_workers":0, "pop_room":2, "can_build":true, "preserve_farm":true, "recruit":true, "full":false},
		{"name":"zero workers with one population slot cannot fit TC villager and first soldier", "wood":245, "food":110, "farm_missing":true, "living_workers":0, "pop_room":1, "can_build":true, "preserve_farm":true, "recruit":true, "full":false},
	]
	var passed := true
	for test_case in cases:
		var result: Dictionary = controller.call("_barracks_recovery_plan", int(test_case.wood), int(test_case.food), bool(test_case.farm_missing), int(test_case.get("living_workers",1)), int(test_case.get("pop_room",99)))
		var case_passed := bool(result.get("can_build_barracks", false)) == bool(test_case.can_build)
		case_passed = case_passed and bool(result.get("can_preserve_farm", false)) == bool(test_case.preserve_farm)
		case_passed = case_passed and bool(result.get("can_rebuild_and_recruit", false)) == bool(test_case.recruit)
		case_passed = case_passed and bool(result.get("can_complete_recovery_plan", false)) == bool(test_case.full)
		case_passed = case_passed and bool(result.get("rebuild_first", false)) == bool(test_case.full)
		passed = passed and case_passed
		print("[barracks_recovery_plan_probe] ", JSON.stringify({"case":test_case.name,"expected":test_case,"plan":result,"passed":case_passed}))
	var target_cases: Array[Dictionary] = [
		{"mode":1,"wave":1,"expected":5}, {"mode":1,"wave":2,"expected":6}, {"mode":1,"wave":3,"expected":7}, {"mode":1,"wave":4,"expected":8}, {"mode":1,"wave":5,"expected":10},
		{"mode":0,"wave":5,"expected":5}, {"mode":0,"wave":6,"expected":6}, {"mode":0,"wave":10,"expected":7}, {"mode":0,"wave":14,"expected":8}, {"mode":0,"wave":18,"expected":9}, {"mode":0,"wave":22,"expected":10},
	]
	for target_case in target_cases:
		var actual_target: int = int(controller.call("_army_target_for_mode_wave", int(target_case.mode), int(target_case.wave)))
		var target_passed := actual_target == int(target_case.expected)
		passed = passed and target_passed
		print("[barracks_recovery_plan_probe] ", JSON.stringify({"strategy_case":target_case,"actual_target":actual_target,"passed":target_passed}))
	controller.free()
	print("[barracks_recovery_plan_probe] ", JSON.stringify({"passed":passed,"recovery_cost_cases":cases.size(),"wave_target_cases":target_cases.size()}))
	quit(0 if passed else 1)
