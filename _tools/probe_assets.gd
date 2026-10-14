extends SceneTree
func _init():
	var Assets = load("res://scripts/asset_kit.gd")
	var keys = ["town_center","house","barracks","arrow_tower","wall","gate","candy_tree","relay","garrison","scout_camp"]
	var root = Node3D.new()
	root.name = "Probe"
	var ok = true
	var lines = []
	for k in keys:
		var n = Assets.attach(root, k, Vector3(6,5,6) if k != "wall" else Vector3(6,3.2,1.2))
		var line = "%s -> %s children=%d" % [k, "OK" if n != null else "FAIL", (n.get_child_count() if n else 0)]
		lines.append(line)
		print("[AssetProbe] ", line)
		if n == null:
			ok = false
	var fl = FileAccess.open("C:/Users/cc/Documents/GodotProjects/AoELite3D/_fantastic_asset_probe.txt", FileAccess.WRITE)
	if fl:
		fl.store_string("ok=%s\n%s\n" % ["true" if ok else "false", "\n".join(lines)])
		fl.close()
	quit(0 if ok else 1)
