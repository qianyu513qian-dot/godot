extends RefCounted
class_name CombatUtil
## Shared combat helpers for AoELite3D first combat slice.

const MELEE_RANGE: float = 1.35
const ACQUIRE_RANGE: float = 5.0
const VILL_ACQUIRE: float = 3.5
const CORPSE_LIFE: float = 2.2

static func melee_damage(atk: float, target_melee_armor: int) -> float:
	return maxf(1.0, atk - float(target_melee_armor))

static func pierce_damage(atk: float, target_pierce_armor: int) -> float:
	return maxf(1.0, atk - float(target_pierce_armor))

static func is_alive(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.get("alive") == false:
		return false
	var hp = n.get("hp")
	if hp != null and float(hp) <= 0.0:
		return false
	return true

static func team_of(n: Node) -> String:
	if n == null:
		return ""
	var t = n.get("team")
	return str(t) if t != null else ""

static func is_hostile(a: Node, b: Node) -> bool:
	if not is_alive(a) or not is_alive(b):
		return false
	var ta: String = team_of(a)
	var tb: String = team_of(b)
	return ta != "" and tb != "" and ta != tb

static func xz_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()

static func find_nearest_enemy(from: Node3D, my_team: String, radius: float) -> Node3D:
	if from == null or from.get_tree() == null:
		return null
	var best: Node3D = null
	var best_d: float = radius
	var tree: SceneTree = from.get_tree()
	var groups: Array = ["player_units", "enemy_units"]
	for g in groups:
		for u in tree.get_nodes_in_group(g):
			if u == from or not (u is Node3D):
				continue
			if not is_alive(u):
				continue
			if team_of(u) == my_team or team_of(u) == "":
				continue
			var d: float = xz_dist(from, u)
			if d < best_d:
				best_d = d
				best = u
	# Hostile buildings, including unfinished foundations. Foundations stay
	# attackable so the last surviving construction site cannot soft-lock a match.
	for b in tree.get_nodes_in_group("buildings"):
		if not (b is Node3D) or not is_alive(b):
			continue
		if team_of(b) == my_team or team_of(b) == "":
			continue
		var d2: float = xz_dist(from, b)
		if d2 < best_d:
			best_d = d2
			best = b
	return best
