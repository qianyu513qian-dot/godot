extends SceneTree
func _init():
	var keys = [
		"res://assets/fantastic_village/pieces/SM_PROP_wall_stone_small_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_wall_stone_small_02.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_wall_stone_small_03.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_barrel_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_crate_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_sack_11.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_box_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_hay_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_hay_06.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_market_v01_01.glb",
		"res://assets/fantastic_village/pieces/SM_BLD_body_v04_01.glb",
		"res://assets/fantastic_village/pieces/SM_BLD_body_v05_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_watchtower_wood_02.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_wall_wood_gate_frame_01.glb",
		"res://assets/models/villager.glb",
		"res://assets/models/soldier.glb",
		"res://assets/models/gold.glb",
		"res://assets/models/stone.glb",
	]
	var out = ""
	for p in keys:
		if not ResourceLoader.exists(p):
			out += "MISSING %s\n" % p
			continue
		var ps = load(p) as PackedScene
		var root = Node3D.new()
		root.add_child(ps.instantiate())
		# use mesh aabb in local space
		var aabb = AABB()
		var first = true
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var local = mi.transform * mi.get_aabb()
			if first:
				aabb = local
				first = false
			else:
				aabb = aabb.merge(local)
		out += "%s size=(%.2f, %.2f, %.2f)\n" % [p.get_file(), aabb.size.x, aabb.size.y, aabb.size.z]
		root.free()
	var f = FileAccess.open("res://_asset_aabb_probe2.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print(out)
	quit()
