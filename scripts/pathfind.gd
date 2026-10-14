extends RefCounted
class_name SimplePathfind
## Coarse grid A* around solid building/resource footprints.

const CELL: float = 1.5
const HALF: float = 48.0
const MAX_EXPAND: int = 4500

static var _dirty: bool = true
static var _blocked: Dictionary = {}  # "ix,iz" -> true
static var _dim: int = 0

static func invalidate() -> void:
	_dirty = true

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

static func find_path(from: Vector3, to: Vector3, tree: SceneTree) -> Array:
	## Returns waypoints from near-from to to (may be empty → go straight).
	if _dirty:
		rebuild(tree)
	var start: Vector2i = world_to_cell(from)
	var goal: Vector2i = world_to_cell(to)
	if not _in_bounds(start) or not _in_bounds(goal):
		return [Vector3(to.x, 0, to.z)]
	# If start blocked, nudge to nearest free
	start = _nearest_free(start)
	goal = _nearest_free(goal)
	if start == goal:
		return [Vector3(to.x, 0, to.z)]
	# Direct LOS → single waypoint
	if _line_free(start, goal):
		return [Vector3(to.x, 0, to.z)]
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
	# Final exact goal
	if wps.is_empty() or wps[wps.size() - 1].distance_to(Vector3(to.x, 0, to.z)) > 0.4:
		wps.append(Vector3(to.x, 0.0, to.z))
	return wps

static func _nearest_free(c: Vector2i) -> Vector2i:
	if not is_blocked_cell(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var n := Vector2i(c.x + dx, c.y + dz)
				if _in_bounds(n) and not is_blocked_cell(n):
					return n
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
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
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
