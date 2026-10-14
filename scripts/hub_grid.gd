extends RefCounted
class_name HubGrid
## Town Center / Relay hub coverage (ported from FirstGame).

static var _dirty: bool = true
static var _hubs: Array = []  # {pos: Vector3, range: float}

static func invalidate() -> void:
	_dirty = true

static func _rebuild(tree: SceneTree) -> void:
	_hubs.clear()
	if tree == null:
		return
	for b in tree.get_nodes_in_group("buildings"):
		if b.get("is_complete") == false:
			continue
		if b.get("is_hub") == true and b.get("in_hub_range") != false:
			var r: float = float(b.get("hub_range"))
			if r > 0.0:
				_hubs.append({"pos": b.global_position, "range": r})
	_dirty = false

static func is_in_hub(world_pos: Vector3, tree: SceneTree) -> bool:
	if _dirty:
		_rebuild(tree)
	for h in _hubs:
		var d := Vector2(world_pos.x - h.pos.x, world_pos.z - h.pos.z).length()
		if d <= float(h.range):
			return true
	return false

static func refresh_all(tree: SceneTree) -> void:
	_rebuild(tree)
	for b in tree.get_nodes_in_group("buildings"):
		if b.get("needs_hub") == true:
			var ok: bool = is_in_hub(b.global_position, tree)
			b.set("in_hub_range", ok)
			b.set("powered", ok)
