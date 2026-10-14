extends Node
class_name Research
## Ages stub (ported from FirstGame).

signal age_changed(age: int)

var age: int = 1  # 1..4
var age_names := ["", "黑暗时代", "封建时代", "城堡时代", "帝王时代"]

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
