extends RefCounted
class_name SimplePathfind
## Coarse grid A* around solid building/resource footprints.

const CELL: float = 1.5
const HALF: float = 48.0
const MAX_EXPAND: int = 4500

static var _dirty: bool = true
static var navigation_revision: int = 0
static var search_count: int = 0
static var last_path_report: Dictionary = {}
static var search_durations_usec: Array[int] = []

static func diagnostic_snapshot() -> Dictionary:
	return {
		"dirty": _dirty,
		"navigation_revision": navigation_revision,
		"blocked_cells": _blocked.size(),
		"dimensions": _dim,
		"search_count": search_count,
		"search_duration_samples": search_durations_usec.size(),
	}
static var _search_started_usec: int = 0
static var _blocked: Dictionary = {}  # "ix,iz" -> true
static var _dim: int = 0

static func reset_measurements() -> void:
	search_count = 0
	search_durations_usec.clear()
	last_path_report.clear()

static func invalidate() -> void:
	_dirty = true
	navigation_revision += 1

static func _key(ix: int, iz: int) -> String:
	return "%d,%d" % [ix, iz]

static func world_to_cell(p: Vector3) -> Vector2i:
	var ix: int = int(floor((p.x + HALF) / CELL))
	var iz: int = int(floor((p.z + HALF) / CELL))
	return Vector2i(ix, iz)

static func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(-HALF + (float(c.x) + 0.5) * CELL, 0.0, -HALF + (float(c.y) + 0.5) * CELL)

static func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _dim and c.y < _dim

static func rebuild(tree: SceneTree) -> void:
	_dim = int(ceil((HALF * 2.0) / CELL))
	_blocked.clear()
	if tree == null:
		_dirty = false
		return
	var solids: Array = []
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		# Incomplete foundations still block
		if b.get("blocks_path") == false and b.get("is_wall") != true and b.get("is_gate") != true and b.get("is_tower") != true:
			continue
		solids.append(b)
	for r in tree.get_nodes_in_group("resources"):
		if not is_instance_valid(r):
			continue
		if r.is_in_group("buildings") or r.is_in_group("farms"):
			continue
		if r.has_method("blocks_unit_at"):
			solids.append(r)
	for s in solids:
		_stamp_solid(s)
	_dilate_blocked(1)
	# Dilate seals doorways — punch unlocked-gate corridors back open for A*
	_punch_open_gate_passages(tree)
	_dirty = false

static func _stamp_solid(node: Node) -> void:
	var pos: Vector3 = node.global_position
	var hx: float = 2.0
	var hz: float = 2.0
	var fp = node.get("footprint")
	if fp != null:
		hx = maxf(float(fp.x) * 0.55, 1.0)
		hz = maxf(float(fp.z) * 0.55, 1.0)
	elif node.get("block_radius") != null:
		var br: float = float(node.get("block_radius"))
		hx = maxf(br, 1.0)
		hz = hx
	# Expand for unit radius + clearance so paths don't skim walls
	hx += 0.9
	hz += 0.9
	var min_c: Vector2i = world_to_cell(Vector3(pos.x - hx, 0, pos.z - hz))
	var max_c: Vector2i = world_to_cell(Vector3(pos.x + hx, 0, pos.z + hz))
	for ix in range(min_c.x, max_c.x + 1):
		for iz in range(min_c.y, max_c.y + 1):
			var c := Vector2i(ix, iz)
			if not _in_bounds(c):
				continue
			var w: Vector3 = cell_to_world(c)
			var blocked: bool = false
			if node.has_method("blocks_unit_at"):
				# buildings: (pos, team, radius); resources: (pos, radius)
				if node.is_in_group("buildings"):
					blocked = (node.call("blocks_unit_at", w, "player", 0.45) == true)
				else:
					blocked = (node.call("blocks_unit_at", w, 0.45) == true)
			else:
				blocked = absf(w.x - pos.x) <= hx and absf(w.z - pos.z) <= hz
			if blocked:
				_blocked[_key(ix, iz)] = true

static func _dilate_blocked(rings: int = 1) -> void:
	## Extra clearance ring so A* keeps units off solid edges.
	if rings <= 0:
		return
	var add: Dictionary = {}
	for k in _blocked.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		var ix: int = int(parts[0])
		var iz: int = int(parts[1])
		for dx in range(-rings, rings + 1):
			for dz in range(-rings, rings + 1):
				var c := Vector2i(ix + dx, iz + dz)
				if _in_bounds(c):
					add[_key(c.x, c.y)] = true
	for k2 in add.keys():
		_blocked[k2] = true

static func _punch_open_gate_passages(tree: SceneTree) -> void:
	## After dilate, clear UNLOCKED gate doorway cells so A* routes through
	## even while the door is currently closed (unit proximity still opens it).
	## Locked gates stay solid — do not punch.
	if tree == null:
		return
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.get("is_gate") != true:
			continue
		# Locked gates stay solid — do not punch corridor
		if b.get("gate_locked") == true:
			continue
		var pos: Vector3 = b.global_position
		var fp = b.get("footprint")
		var gate_w: float = 5.5
		var gate_d: float = 2.4
		if fp != null:
			gate_w = float(fp.x)
			gate_d = float(fp.z)
		var half_open: float = maxf(gate_w * 0.26, 1.4)
		var depth: float = gate_d * 1.0 + 2.5
		var yaw: float = b.rotation.y
		var cos_y: float = cos(yaw)
		var sin_y: float = sin(yaw)
		# Scan a generous world AABB around the gate
		var scan: float = maxf(gate_w, depth) + 3.0
		var min_c: Vector2i = world_to_cell(Vector3(pos.x - scan, 0, pos.z - scan))
		var max_c: Vector2i = world_to_cell(Vector3(pos.x + scan, 0, pos.z + scan))
		for ix in range(min_c.x, max_c.x + 1):
			for iz in range(min_c.y, max_c.y + 1):
				var c := Vector2i(ix, iz)
				if not _in_bounds(c):
					continue
				var w: Vector3 = cell_to_world(c)
				var dx: float = w.x - pos.x
				var dz: float = w.z - pos.z
				var lx: float = dx * cos_y + dz * sin_y
				var lz: float = -dx * sin_y + dz * cos_y
				if absf(lx) <= half_open and absf(lz) <= depth:
					_blocked.erase(_key(ix, iz))

static func is_blocked_cell(c: Vector2i) -> bool:
	if not _in_bounds(c):
		return true
	return _blocked.has(_key(c.x, c.y))

static func is_blocked_world(p: Vector3) -> bool:
	return is_blocked_cell(world_to_cell(p))

static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: float = float(absi(a.x - b.x))
	var dz: float = float(absi(a.y - b.y))
	return (dx + dz) + 0.414 * minf(dx, dz)  # octile

static func _record_path(path: Array, report: Dictionary) -> Array:
	var duration_usec: int = maxi(0, int(Time.get_ticks_usec() - _search_started_usec))
	report["duration_usec"] = duration_usec
	if search_durations_usec.size() < 100000:
		search_durations_usec.append(duration_usec)
	if not path.is_empty():
		var route_end: Vector3 = path[path.size() - 1]
		var resolved_goal: Vector3 = report.get("resolved_goal", Vector3.ZERO)
		report["route_end"] = route_end
		report["route_distance_to_resolved_goal"] = route_end.distance_to(resolved_goal)
	last_path_report = report.duplicate(true)
	return path

static func find_path(from: Vector3, to: Vector3, tree: SceneTree) -> Array:
	## Returns waypoints from near-from to to (may be empty → go straight).
	search_count += 1
	_search_started_usec = Time.get_ticks_usec()
	if _dirty:
		rebuild(tree)
	var start: Vector2i = world_to_cell(from)
	var goal: Vector2i = world_to_cell(to)
	var start_outside: bool = not _in_bounds(start)
	var goal_outside: bool = not _in_bounds(goal)
	var requested_start: Vector2i = start
	var requested_goal: Vector2i = goal
	# Horde units spawn just beyond the coarse map boundary. Clamp their search
	# anchor to the nearest edge cell, then keep that anchor as an explicit first
	# waypoint so the live segment from the spawn position is checked as well.
	start = Vector2i(clampi(start.x, 0, _dim - 1), clampi(start.y, 0, _dim - 1))
	# Orders outside the map stop at the nearest map edge instead of becoming a
	# direct off-grid walk or a stationary unit.
	goal = Vector2i(clampi(goal.x, 0, _dim - 1), clampi(goal.y, 0, _dim - 1))
	# The coarse grid expands solid footprints for clearance, so a safe stand
	# position can land in a blocked cell. Only treat the actual target as
	# blocked when the collision geometry also rejects it.
	var physical_blockers: Array[Dictionary] = _world_blockers_at(to, tree)
	var target_blocked: bool = goal_outside or not physical_blockers.is_empty()
	var target_grid_blocked: bool = is_blocked_cell(goal)
	# If start blocked, nudge to nearest free
	start = _nearest_free(start)
	goal = _nearest_free(goal)
	var resolved_goal: Vector3 = cell_to_world(goal) if target_blocked else Vector3(to.x, 0.0, to.z)
	var report: Dictionary = {
		"requested_from": from,
		"requested_goal": Vector3(to.x, 0.0, to.z),
		"requested_start_cell": [requested_start.x, requested_start.y],
		"requested_goal_cell": [requested_goal.x, requested_goal.y],
		"start_outside_map": start_outside,
		"goal_outside_map": goal_outside,
		"start_cell_blocked_before_projection": is_blocked_cell(requested_start),
		"goal_cell_blocked_before_projection": target_grid_blocked,
		"physical_goal_blocked": not physical_blockers.is_empty(),
		"physical_blockers": physical_blockers,
		"projected_goal_cell": [goal.x, goal.y],
		"resolved_goal": resolved_goal,
		"navigation_revision": navigation_revision,
		"grid_dimensions": [_dim, _dim],
		"grid_cell_count": _dim * _dim,
		"max_expand_limit": MAX_EXPAND,
		"search_reason": "not_started",
		"expanded_nodes": 0,
		"remaining_open_nodes": 0,
		"search_reached_goal": false,
	}
	var start_anchor: Vector3 = cell_to_world(start)
	var start_anchor_clear: bool = not start_outside or _world_segment_clear(from, start_anchor, tree)
	if start_outside and not start_anchor_clear:
		for radius in range(1, _dim + 1):
			var entry := start
			var best_distance: float = INF
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					if absi(dx) != radius and absi(dz) != radius:
						continue
					var candidate := Vector2i(start.x + dx, start.y + dz)
					if not _in_bounds(candidate) or is_blocked_cell(candidate):
						continue
					var candidate_pos: Vector3 = cell_to_world(candidate)
					if not _world_segment_clear(from, candidate_pos, tree):
						continue
					var distance: float = from.distance_squared_to(candidate_pos)
					if distance < best_distance:
						entry = candidate
						best_distance = distance
			if best_distance < INF:
				start = entry
				start_anchor = cell_to_world(start)
				start_anchor_clear = true
				break
	if start_outside and not start_anchor_clear:
		report["search_reason"] = "outside_start_has_no_clear_entry"
		return _record_path([Vector3(from.x, 0.0, from.z)], report)
	if start == goal:
		if not start_outside and not target_blocked and _world_segment_clear(cell_to_world(goal), to, tree):
			report["search_reason"] = "same_cell_reaches_requested_goal"
			report["search_reached_goal"] = true
			return _record_path([Vector3(to.x, 0, to.z)], report)
		report["search_reason"] = "same_cell_uses_legal_projection" if target_blocked else "same_cell_route"
		report["search_reached_goal"] = true
		return _record_path([start_anchor if start_outside else cell_to_world(goal)], report)
	# Direct LOS → single waypoint
	if not start_outside and _line_free(start, goal):
		if not target_blocked and (not is_blocked_cell(world_to_cell(to)) or _world_segment_clear(cell_to_world(goal), to, tree)):
			report["search_reason"] = "direct_grid_line"
			report["search_reached_goal"] = true
			return _record_path([Vector3(to.x, 0, to.z)], report)
		if start_outside:
			report["search_reason"] = "direct_line_to_legal_projection" if target_blocked else "direct_line_to_goal_cell"
			report["search_reached_goal"] = true
			return _record_path([start_anchor, cell_to_world(goal)], report)
		report["search_reason"] = "direct_line_to_legal_projection" if target_blocked else "direct_line_to_goal_cell"
		report["search_reached_goal"] = true
		return _record_path([cell_to_world(goal)], report)
	var open: Array = []  # {c, f, g}
	var came: Dictionary = {}
	var gscore: Dictionary = {}
	var sk: String = _key(start.x, start.y)
	gscore[sk] = 0.0
	open.append({"c": start, "f": _heuristic(start, goal), "g": 0.0})
	var closed: Dictionary = {}
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var found: bool = false
	var expand: int = 0
	while not open.is_empty() and expand < MAX_EXPAND:
		expand += 1
		# pop lowest f
		var bi: int = 0
		var bf: float = float(open[0]["f"])
		for i in range(1, open.size()):
			var cf: float = float(open[i]["f"])
			if cf < bf:
				bf = cf
				bi = i
		var cur: Dictionary = open[bi]
		open.remove_at(bi)
		var cc: Vector2i = cur["c"]
		var ck: String = _key(cc.x, cc.y)
		if closed.has(ck):
			continue
		closed[ck] = true
		if cc == goal:
			found = true
			break
		for d in dirs:
			var nc: Vector2i = cc + d
			if not _in_bounds(nc) or is_blocked_cell(nc):
				continue
			# No corner cut through blocked diagonals
			if d.x != 0 and d.y != 0:
				if is_blocked_cell(Vector2i(cc.x + d.x, cc.y)) or is_blocked_cell(Vector2i(cc.x, cc.y + d.y)):
					continue
			var nk: String = _key(nc.x, nc.y)
			if closed.has(nk):
				continue
			var step_cost: float = 1.414 if (d.x != 0 and d.y != 0) else 1.0
			var ng: float = float(cur["g"]) + step_cost
			if gscore.has(nk) and ng >= float(gscore[nk]):
				continue
			gscore[nk] = ng
			came[nk] = cc
			var nf: float = ng + _heuristic(nc, goal)
			open.append({"c": nc, "f": nf, "g": ng})
	if not found:
		# Partial: closest explored to goal
		var best_c: Vector2i = start
		var best_h: float = _heuristic(start, goal)
		for k in closed.keys():
			var parts: PackedStringArray = str(k).split(",")
			if parts.size() < 2:
				continue
			var pc := Vector2i(int(parts[0]), int(parts[1]))
			var h: float = _heuristic(pc, goal)
			if h < best_h:
				best_h = h
				best_c = pc
		goal = best_c
	report["expanded_nodes"] = expand
	report["remaining_open_nodes"] = open.size()
	report["search_reached_goal"] = found
	report["search_reason"] = "goal_cell_reached" if found else ("expand_budget_exhausted" if expand >= MAX_EXPAND else "open_set_exhausted")
	if found:
		report["reached_goal_cell"] = [goal.x, goal.y]
	else:
		report["partial_endpoint_cell"] = [goal.x, goal.y]
	# Reconstruct
	var cells: Array = []
	var cur2: Vector2i = goal
	var guard: int = 0
	while guard < 2000:
		guard += 1
		cells.push_front(cur2)
		var k2: String = _key(cur2.x, cur2.y)
		if cur2 == start or not came.has(k2):
			break
		cur2 = came[k2]
	cells = _simplify(cells)
	var wps: Array = []
	for i in range(1, cells.size()):  # skip start cell
		wps.append(cell_to_world(cells[i]))
	if start_outside and start_anchor_clear:
		wps.push_front(start_anchor)
	# Append the requested coordinate only when the search actually reached
	# its cell and the requested cell itself is free. A blocked destination or
	# a partial route must terminate at the last reachable free cell.
	if wps.is_empty():
		wps.append(cell_to_world(goal))
	elif found and not target_blocked and _world_segment_clear(wps[wps.size() - 1], to, tree) and wps[wps.size() - 1].distance_to(Vector3(to.x, 0, to.z)) > 0.4:
		wps.append(Vector3(to.x, 0.0, to.z))
	return _record_path(wps, report)

static func _world_position_blocked(p: Vector3, tree: SceneTree) -> bool:
	return not _world_blockers_at(p, tree).is_empty()

static func _world_blockers_at(p: Vector3, tree: SceneTree) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	if tree == null:
		return blockers
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.get("blocks_path") == false and b.get("is_wall") != true and b.get("is_gate") != true and b.get("is_tower") != true:
			continue
		if b.has_method("blocks_unit_at") and b.call("blocks_unit_at", p, "player", 0.45) == true:
			blockers.append(_describe_blocker(b, "building"))
	for r in tree.get_nodes_in_group("resources"):
		if not is_instance_valid(r) or r.is_in_group("buildings") or r.is_in_group("farms"):
			continue
		if r.has_method("blocks_unit_at") and r.call("blocks_unit_at", p, 0.45) == true:
			blockers.append(_describe_blocker(r, "resource"))
	return blockers

static func _describe_blocker(node: Node, category: String) -> Dictionary:
	var result: Dictionary = {"category": category, "name": node.name, "class": node.get_class(), "position": node.global_position}
	var script: Script = node.get_script() as Script
	if script != null:
		result["script"] = script.resource_path
	var footprint: Variant = node.get("footprint")
	if footprint is Vector3:
		result["footprint"] = footprint
	var block_radius: Variant = node.get("block_radius")
	if block_radius != null:
		result["block_radius"] = float(block_radius)
	var bounds: Variant = node.get("bounds")
	if bounds is Vector3:
		result["bounds"] = bounds
	if category == "resource" and node.has_method("res_key"):
		result["resource_key"] = node.call("res_key")
	return result

static func _world_segment_clear(a: Vector3, b: Vector3, tree: SceneTree) -> bool:
	var distance: float = Vector2(b.x - a.x, b.z - a.z).length()
	var steps: int = maxi(1, ceili(distance / 0.2))
	for i in range(steps + 1):
		if _world_position_blocked(a.lerp(b, float(i) / float(steps)), tree):
			return false
	return true

static func _nearest_free(c: Vector2i) -> Vector2i:
	if not is_blocked_cell(c):
		return c
	for r in range(1, _dim + 1):
		var best: Vector2i = c
		var best_distance: float = INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var n := Vector2i(c.x + dx, c.y + dz)
				if _in_bounds(n) and not is_blocked_cell(n):
					var distance: float = float(dx * dx + dz * dz)
					if distance < best_distance:
						best = n
						best_distance = distance
		if best_distance < INF:
			return best
	return c

static func _line_free(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = absi(b.x - a.x)
	var dz: int = absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sz: int = 1 if a.y < b.y else -1
	var err: int = dx - dz
	var x: int = a.x
	var z: int = a.y
	while true:
		if is_blocked_cell(Vector2i(x, z)):
			return false
		if x == b.x and z == b.y:
			break
		var e2: int = 2 * err
		var next_x: int = x
		var next_z: int = z
		if e2 > -dz:
			err -= dz
			next_x += sx
		if e2 < dx:
			err += dx
			next_z += sz
		# A diagonal LOS step must not squeeze through the corner of two
		# blocked cells. A* already enforces this for grid neighbors; keep the
		# direct-path shortcut and waypoint simplifier under the same rule.
		if next_x != x and next_z != z:
			if is_blocked_cell(Vector2i(next_x, z)) or is_blocked_cell(Vector2i(x, next_z)):
				return false
		x = next_x
		z = next_z
	return true

static func _simplify(cells: Array) -> Array:
	if cells.size() <= 2:
		return cells
	var out: Array = [cells[0]]
	var i: int = 0
	while i < cells.size() - 1:
		var j: int = cells.size() - 1
		while j > i + 1:
			if _line_free(cells[i], cells[j]):
				break
			j -= 1
		out.append(cells[j])
		i = j
	return out
