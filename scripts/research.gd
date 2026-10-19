extends Node
class_name Research
## Match ages and compact, production-focused technologies.

signal age_changed(age: int)

var age: int = 1  # 1..4
var age_names := ["", "黑暗时代", "封建时代", "城堡时代", "帝王时代"]

const TECH_FORESTRY := "improved_axes"
const TECH_WHEELBARROW := "wheelbarrow"
const TECH_BRONZE_WEAPONS := "bronze_weapons"
const TECH_COSTS := {
	TECH_FORESTRY: {"meat": 25, "wood": 10},
	TECH_WHEELBARROW: {"meat": 75, "wood": 50},
	TECH_BRONZE_WEAPONS: {"meat": 75, "wood": 25, "gold": 25},
}
const TECH_REQUIRED_AGE := {
	TECH_FORESTRY: 1,
	TECH_WHEELBARROW: 2,
	TECH_BRONZE_WEAPONS: 2,
}
var researched_techs: Array[String] = []

func has_technology(id: String) -> bool:
	return researched_techs.has(id)

func technology_cost(id: String) -> Dictionary:
	return (TECH_COSTS.get(id, {}) as Dictionary).duplicate()

func try_research(id: String, res: Dictionary) -> Dictionary:
	if not TECH_COSTS.has(id) or has_technology(id):
		return {"ok": false}
	if age < int(TECH_REQUIRED_AGE.get(id, 1)):
		return {"ok": false, "reason": "prerequisite"}
	var cost: Dictionary = TECH_COSTS[id]
	for key in ["meat", "wood", "stone", "gold"]:
		if int(res.get(key, 0)) < int(cost.get(key, 0)):
			return {"ok": false, "reason": "resources"}
	researched_techs.append(id)
	return {"ok": true, "cost": cost.duplicate()}

func restore_research(saved_techs: Array, legacy_active_id: String = "") -> void:
	researched_techs.clear()
	for tech_id in saved_techs:
		if TECH_COSTS.has(str(tech_id)) and not researched_techs.has(str(tech_id)):
			researched_techs.append(str(tech_id))
	# R10 trial saves had already deducted the cost when research began. Promote
	# that paid legacy state to completed without charging or refunding again.
	if TECH_COSTS.has(legacy_active_id) and not researched_techs.has(legacy_active_id):
		researched_techs.append(legacy_active_id)

## Costs to advance TO the next age (index = current age).
var age_up_cost := {
	1: {"meat": 500, "gold": 200},
	2: {"meat": 800, "gold": 400, "stone": 200},
	3: {"meat": 1000, "gold": 800, "stone": 400},
}

func can_age_up(meat: int, wood: int, stone: int, gold: int) -> bool:
	if age >= 4:
		return false
	var c: Dictionary = age_up_cost.get(age, {})
	if meat < int(c.get("meat", 0)): return false
	if wood < int(c.get("wood", 0)): return false
	if stone < int(c.get("stone", 0)): return false
	if gold < int(c.get("gold", 0)): return false
	return true

func try_age_up(res: Dictionary) -> Dictionary:
	## Returns {ok, cost} — caller deducts.
	if age >= 4:
		return {"ok": false}
	var c: Dictionary = age_up_cost.get(age, {}).duplicate()
	if int(res.get("meat", 0)) < int(c.get("meat", 0)): return {"ok": false}
	if int(res.get("wood", 0)) < int(c.get("wood", 0)): return {"ok": false}
	if int(res.get("stone", 0)) < int(c.get("stone", 0)): return {"ok": false}
	if int(res.get("gold", 0)) < int(c.get("gold", 0)): return {"ok": false}
	age += 1
	age_changed.emit(age)
	return {"ok": true, "cost": c}

func age_label() -> String:
	return age_names[age] if age < age_names.size() else "时代%d" % age
