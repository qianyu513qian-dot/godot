extends RefCounted
class_name Fortify
## Auto-connect walls / gates / towers (8 dirs). Seamless beams — no rotate-induced gaps.

const LINK_DIST: float = 11.0  # wall↔gate at ~7.5–9
const DIRS8: Array = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
]

static func is_fort(b: Node) -> bool:
	return bool(b.get("is_wall")) or bool(b.get("is_gate")) or bool(b.get("is_tower"))

static func footprint_overlap(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3, pad: float = 0.35) -> bool:
	return footprint_overlap_yaw(a_pos, a_size, 0.0, b_pos, b_size, 0.0, pad)

static func _obb_half_xz(size: Vector3, yaw: float) -> Vector2:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var c: float = absf(cos(yaw))
	var s: float = absf(sin(yaw))
	return Vector2(c * hx + s * hz, s * hx + c * hz)

static func footprint_overlap_yaw(a_pos: Vector3, a_size: Vector3, a_yaw: float, b_pos: Vector3, b_size: Vector3, b_yaw: float, pad: float = 0.35) -> bool:
	var ae: Vector2 = _obb_half_xz(a_size, a_yaw) + Vector2(pad, pad)
	var be: Vector2 = _obb_half_xz(b_size, b_yaw) + Vector2(pad, pad)
	return absf(a_pos.x - b_pos.x) < (ae.x + be.x) and absf(a_pos.z - b_pos.z) < (ae.y + be.y)

static func refresh_all(tree: SceneTree) -> void:
	if tree == null:
		return
	var forts: Array = []
	for b in tree.get_nodes_in_group("buildings"):
		if is_fort(b):
			forts.append(b)
	for b in forts:
		if b.has_method("clear_wall_links"):
			b.clear_wall_links()
	# Phase 1 skipped: respect placement yaw (R / mouse wheel). Connectors are world-space.
	for i in forts.size():
		var fa: Node3D = forts[i]
		for j in range(i + 1, forts.size()):
			var fb: Node3D = forts[j]
			var d2: Vector2 = Vector2(fa.global_position.x - fb.global_position.x, fa.global_position.z - fb.global_position.z)
			if d2.length() <= LINK_DIST:
				_link_seamless(fa, fb)

static func _link_seamless(a: Node3D, b: Node3D) -> void:
	var delta: Vector3 = b.global_position - a.global_position
	delta.y = 0.0
	if delta.length_squared() < 0.01:
		return
	var nd: Vector3 = delta.normalized()
	var best_dot: float = -999.0
	for d in DIRS8:
		var dd: Vector2 = (d as Vector2).normalized()
		best_dot = maxf(best_dot, Vector2(nd.x, nd.z).dot(dd))
	if best_dot < 0.55:
		return
	if a.has_method("add_wall_link"):
		a.add_wall_link(b)
	if b.has_method("add_wall_link"):
		b.add_wall_link(a)
