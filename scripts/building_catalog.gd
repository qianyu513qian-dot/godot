extends RefCounted
class_name BuildingCatalog3D
## Slim AoE4-ish catalog: TC, House, Farm, Relay, Wall, Gate(selftest), Tower, Barracks.

const TOWN_CENTER := 0
const HOUSE := 1
const FARM := 2
const LUMBER_CAMP := 3  # legacy id kept; not buildable
const RELAY := 4
const RESEARCH_LAB := 5
const QUARRY := 6
const WAREHOUSE := 7
const WALL := 8
const GATE := 9
const ARROW_TOWER := 10
const SCOUT_CAMP := 11
const ATTACK_BARRACKS := 12  # Barracks
const DEFEND_GARRISON := 13
const BARRACKS := 12

static func get_def(kind: int) -> Dictionary:
	match kind:
		TOWN_CENTER:
			return {
				"id": TOWN_CENTER, "name": "城镇中心",
				"hp": 5000.0, "radius": 4.2, "pop_bonus": 10,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": true, "hub_range": 18.0, "needs_hub": false,
				"is_dropoff": true, "dropoff_keys": ["wood", "meat", "stone", "gold"],
				"cost_wood": 0, "cost_meat": 0, "cost_stone": 0,
				"build_time": 0.0,
				"mesh": "tc", "color": Color(0.72, 0.55, 0.32),
				"size": Vector3(6.5, 5.5, 6.5),
			}
		HOUSE:
			return {
				"id": HOUSE, "name": "房屋",
				"hp": 500.0, "radius": 2.0, "pop_bonus": 10,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": true,
				"is_dropoff": false, "dropoff_keys": [],
				"cost_wood": 50, "cost_meat": 0, "cost_stone": 0,
				"build_time": 15.0,
				"mesh": "house", "color": Color(0.65, 0.5, 0.35),
				"size": Vector3(4.2, 3.0, 4.0),
			}
		FARM:
			return {
				"id": FARM, "name": "农田",
				"hp": 300.0, "radius": 2.6, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": true,
				"is_dropoff": false, "dropoff_keys": [],
				"is_meat_source": true, "meat_stock": 300,
				"cost_wood": 75, "cost_meat": 0, "cost_stone": 0,
				"build_time": 12.0,
				"mesh": "farm", "color": Color(0.48, 0.36, 0.22),
				"size": Vector3(5.5, 0.1, 5.5),
				"blocks_path": false,
			}
		RELAY:
			return {
				"id": RELAY, "name": "中继站",
				"hp": 750.0, "radius": 1.8, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": true, "hub_range": 14.0, "needs_hub": true,
				"is_dropoff": true, "dropoff_keys": ["wood", "stone", "gold"],
				"cost_wood": 100, "cost_meat": 0, "cost_stone": 50,
				"build_time": 20.0,
				"mesh": "relay", "color": Color(0.55, 0.48, 0.35),
				"size": Vector3(3.2, 3.6, 3.2),
			}
		WALL:
			return {
				"id": WALL, "name": "石墙",
				"hp": 1250.0, "radius": 1.2, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": false,
				"is_dropoff": false, "dropoff_keys": [],
				"is_wall": true,
				"cost_wood": 0, "cost_meat": 0, "cost_stone": 25,
				"build_time": 8.0,
				"mesh": "wall", "color": Color(0.55, 0.52, 0.48),
				"size": Vector3(6.0, 3.2, 1.2),
			}
		GATE:
			return {
				"id": GATE, "name": "城门",
				"hp": 1500.0, "radius": 2.0, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": false,
				"is_dropoff": false, "dropoff_keys": [],
				"is_gate": true,
				"cost_wood": 40, "cost_meat": 0, "cost_stone": 60,
				"build_time": 20.0,
				"mesh": "gate", "color": Color(0.5, 0.45, 0.4),
				"size": Vector3(5.5, 4.2, 2.4),
			}
		ARROW_TOWER:
			return {
				"id": ARROW_TOWER, "name": "箭塔",
				"hp": 750.0, "radius": 1.6, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": true,
				"is_dropoff": false, "dropoff_keys": [],
				"is_tower": true, "attack_range": 6.5, "attack_damage": 10.0, "attack_interval": 1.75,
				"cost_wood": 100, "cost_meat": 0, "cost_stone": 50,
				"build_time": 25.0,
				"mesh": "tower", "color": Color(0.5, 0.48, 0.45),
				"size": Vector3(2.8, 5.5, 2.8),
			}
		ATTACK_BARRACKS:
			return {
				"id": ATTACK_BARRACKS, "name": "兵营",
				"hp": 1200.0, "radius": 2.3, "pop_bonus": 0,
				"armor_melee": 0, "armor_pierce": 0,
				"is_hub": false, "hub_range": 0.0, "needs_hub": true,
				"is_dropoff": false, "dropoff_keys": [],
				"military_role": "attack",
				"cost_wood": 150, "cost_meat": 0, "cost_stone": 0,
				"build_time": 30.0,
				"mesh": "barracks", "color": Color(0.55, 0.4, 0.32),
				"size": Vector3(5.0, 3.5, 5.0),
			}
		# Legacy stubs (not in build menu)
		LUMBER_CAMP:
			return {"id": LUMBER_CAMP, "name": "伐木场", "hp": 250.0, "radius": 2.2, "pop_bonus": 0,
				"cost_wood": 50, "cost_meat": 0, "cost_stone": 0, "size": Vector3(4, 2.4, 4), "color": Color(0.45, 0.32, 0.18), "mesh": "lumber",
				"needs_hub": true, "build_time": 15.0, "armor_melee": 0, "armor_pierce": 0}
		_:
			return {}

static func buildable_kinds() -> Array:
	return [HOUSE, FARM, RELAY, WALL, GATE, ARROW_TOWER, ATTACK_BARRACKS]

static func train_cost(unit_type: String) -> Dictionary:
	match unit_type:
		"villager":
			return {"meat": 50, "wood": 0, "gold": 0, "time": 20.0, "name": "农民"}
		"soldier":
			return {"meat": 60, "wood": 20, "gold": 0, "time": 15.0, "name": "矛兵"}
		_:
			return {"meat": 0, "wood": 0, "gold": 0, "time": 5.0, "name": unit_type}

static func cost_text_cn(d: Dictionary) -> String:
	## e.g. "粮50 木20" for command card / tooltips.
	var parts: PackedStringArray = PackedStringArray()
	var meat_c: int = int(d.get("meat", d.get("cost_meat", 0)))
	var wood_c: int = int(d.get("wood", d.get("cost_wood", 0)))
	var stone_c: int = int(d.get("stone", d.get("cost_stone", 0)))
	var gold_c: int = int(d.get("gold", d.get("cost_gold", 0)))
	if meat_c > 0:
		parts.append("粮%d" % meat_c)
	if wood_c > 0:
		parts.append("木%d" % wood_c)
	if stone_c > 0:
		parts.append("石%d" % stone_c)
	if gold_c > 0:
		parts.append("金%d" % gold_c)
	return " ".join(parts)

static func building_cost_text(kind: int) -> String:
	return cost_text_cn(get_def(kind))
