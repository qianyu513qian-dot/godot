extends Node3D
class_name VillageDayLayout
## Spawns Fantastic Village Pack pieces to approximate UE map_village_day layout.

const LAYOUT_PATH := "res://assets/fantastic_village/env/village_day_layout.json"
const PIECES_ROOT := "res://assets/fantastic_village/pieces/"
const FALLBACK := {
	"SM_BLD_body_v01_01": "res://assets/fantastic_village/town_center.glb",
	"SM_BLD_body_v02_01": "res://assets/fantastic_village/house.glb",
	"SM_BLD_body_v02_02": "res://assets/fantastic_village/house.glb",
	"SM_BLD_body_v03_02": "res://assets/fantastic_village/house.glb",
	"SM_BLD_body_v04_01": "res://assets/fantastic_village/garrison.glb",
	"SM_BLD_body_v05_01": "res://assets/fantastic_village/barracks.glb",
	"SM_BLD_body_v06_01": "res://assets/fantastic_village/house.glb",
	"SM_BLD_body_v07_01": "res://assets/fantastic_village/house.glb",
	"SM_BLD_base_v05_01": "res://assets/fantastic_village/house.glb",
	"SM_PROP_watchtower_wood_01": "res://assets/fantastic_village/arrow_tower.glb",
	"SM_PROP_watchtower_wood_02": "res://assets/fantastic_village/arrow_tower.glb",
	"SM_PROP_wall_wood": "res://assets/fantastic_village/wall.glb",
	"SM_ENV_TREE_village_LOD0": "res://assets/fantastic_village/candy_tree.glb",
}

var _cache: Dictionary = {}
var spawned: int = 0
var missing: int = 0
var layout_meta: Dictionary = {}

func build() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("VillageDayLayout missing JSON")
		return {"ok": false, "spawned": 0}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "spawned": 0}
	layout_meta = data
	var fit: float = float(data.get("scale_fit", 1.0))
	if fit > 0.01 and absf(fit - 1.0) > 0.001:
		scale = Vector3(fit, fit, fit)
	var actors: Array = data.get("actors", [])
	for a in actors:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var mesh_name: String = str(a.get("mesh", ""))
		var ps: PackedScene = _load_piece(mesh_name)
		if ps == null:
			missing += 1
			continue
		var inst: Node3D = ps.instantiate() as Node3D
		if inst == null:
			missing += 1
			continue
		inst.name = mesh_name + "_%d" % spawned
		var pos_a: Array = a.get("pos", [0, 0, 0])
		inst.position = Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
		# Flatten tiny height noise so gameplay ground stays walkable; keep >0.4m relative
		if absf(inst.position.y) < 0.35:
			inst.position.y = 0.0
		var yaw: float = float(a.get("yaw", 0.0))
		# UE Z-up yaw -> Godot Y-up (left-handed to right-handed: negate)
		inst.rotation_degrees = Vector3(0.0, -yaw, 0.0)
		var sc: Array = a.get("ue_scale", [1, 1, 1])
		# Uniform-ish; UE scale XYZ maps after axis swap approximately
		inst.scale = Vector3(float(sc[0]), float(sc[2]), float(sc[1]))
		add_child(inst)
		spawned += 1
	return {"ok": true, "spawned": spawned, "missing": missing, "scale_fit": data.get("scale_fit", 1.0)}

func _load_piece(mesh_name: String) -> PackedScene:
	if _cache.has(mesh_name):
		return _cache[mesh_name]
	var path := PIECES_ROOT + mesh_name + ".glb"
	if not ResourceLoader.exists(path):
		if FALLBACK.has(mesh_name):
			path = str(FALLBACK[mesh_name])
		else:
			_cache[mesh_name] = null
			return null
	if not ResourceLoader.exists(path):
		_cache[mesh_name] = null
		return null
	var res = load(path)
	if res is PackedScene:
		_cache[mesh_name] = res
		return res
	_cache[mesh_name] = null
	return null

