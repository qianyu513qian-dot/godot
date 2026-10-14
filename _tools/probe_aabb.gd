extends SceneTree
func _init():
	var keys = [
		"res://assets/fantastic_village/pieces/SM_PROP_stone_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_stone_02.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_stone_03.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_hay_03.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_fence_v01_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_well.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_cart_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_market_v04_01.glb",
		"res://assets/fantastic_village/pieces/SM_BLD_body_v01_01.glb",
		"res://assets/fantastic_village/pieces/SM_BLD_body_v02_01.glb",
		"res://assets/fantastic_village/pieces/SM_BLD_body_v03_02.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_watchtower_wood_01.glb",
		"res://assets/fantastic_village/pieces/SM_PROP_wall_wood.glb",
		"res://assets/fantastic_village/town_center.glb",
		"res://assets/fantastic_village/house.glb",
	]
	var out = ""
	for p in keys:
		if not ResourceLoader.exists(p):
			out += "MISSING %s\n" % p
			continue
		var ps = load(p)
		var n = ps.instantiate()
		var aabb = AABB()
		var first = true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var a = mi.global_transform * mi.get_aabb()
			if first:
				aabb = a
				first = false
			else:
				aabb = aabb.merge(a)
		out += "%s size=(%.2f, %.2f, %.2f) y0=%.2f\n" % [p.get_file(), aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.y]
		n.free()
	var f = FileAccess.open("res://_asset_aabb_probe.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print(out)
	quit()
