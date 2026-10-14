from pathlib import Path
ROOT = Path(r"C:\Users\cc\Documents\GodotProjects\AoELite3D\scripts")

# --- building.gd: prefer AssetKit, fallback MeshKit ---
bp = ROOT / "building.gd"
b = bp.read_text(encoding="utf-8")
if "AssetKit" not in b:
    b = b.replace(
        'const Kit := preload("res://scripts/mesh_kit.gd")',
        'const Kit := preload("res://scripts/mesh_kit.gd")\nconst Assets := preload("res://scripts/asset_kit.gd")',
    )

old_match = '''\tmatch kind:
\t\tCatalog.TOWN_CENTER:
\t\t\tKit.build_town_center(self, size)
\t\tCatalog.HOUSE:
\t\t\tKit.build_house(self, size)
\t\tCatalog.RELAY:
\t\t\tKit.build_relay(self, size)
\t\tCatalog.WALL:
\t\t\tKit.build_wall_segment(self, size)
\t\tCatalog.GATE:
\t\t\tKit.build_gate(self, size)
\t\t\t_cache_gate_doors()
\t\tCatalog.ARROW_TOWER:
\t\t\tKit.build_arrow_tower(self, size)
\t\tCatalog.SCOUT_CAMP:
\t\t\tKit.build_scout_camp(self, size)
\t\tCatalog.ATTACK_BARRACKS:
\t\t\tKit.build_attack_barracks(self, size)
\t\tCatalog.DEFEND_GARRISON:
\t\t\tKit.build_defend_garrison(self, size)
\t\tCatalog.FARM:
\t\t\t_build_farm(size, col)
\t\t_:'''

new_match = '''\tmatch kind:
\t\tCatalog.TOWN_CENTER:
\t\t\tif Assets.attach(self, "town_center", size) == null:
\t\t\t\tKit.build_town_center(self, size)
\t\tCatalog.HOUSE:
\t\t\tif Assets.attach(self, "house", size) == null:
\t\t\t\tKit.build_house(self, size)
\t\tCatalog.RELAY:
\t\t\tif Assets.attach(self, "relay", size) == null:
\t\t\t\tKit.build_relay(self, size)
\t\tCatalog.WALL:
\t\t\tif Assets.attach(self, "wall", size) == null:
\t\t\t\tKit.build_wall_segment(self, size)
\t\tCatalog.GATE:
\t\t\t# GLB body + procedural hinged doors for open/close anim
\t\t\tAssets.attach(self, "gate", size)
\t\t\tKit.build_gate(self, size)
\t\t\t_cache_gate_doors()
\t\t\t# Hide non-door kit meshes to avoid double geometry
\t\t\tfor c in get_children():
\t\t\t\tif c is MeshInstance3D and not str(c.name).begins_with("Gate") and c.get_parent() == self:
\t\t\t\t\tif str(c.name) in ["GateTowerL", "GateTowerR"]:
\t\t\t\t\t\tc.visible = false
\t\tCatalog.ARROW_TOWER:
\t\t\tif Assets.attach(self, "arrow_tower", size) == null:
\t\t\t\tKit.build_arrow_tower(self, size)
\t\tCatalog.SCOUT_CAMP:
\t\t\tif Assets.attach(self, "scout_camp", size) == null:
\t\t\t\tKit.build_scout_camp(self, size)
\t\tCatalog.ATTACK_BARRACKS:
\t\t\tif Assets.attach(self, "barracks", size) == null:
\t\t\t\tKit.build_attack_barracks(self, size)
\t\tCatalog.DEFEND_GARRISON:
\t\t\tif Assets.attach(self, "garrison", size) == null:
\t\t\t\tKit.build_defend_garrison(self, size)
\t\tCatalog.FARM:
\t\t\t_build_farm(size, col)
\t\t_:'''

if old_match not in b:
    raise SystemExit("building match block not found")
b = b.replace(old_match, new_match)
bp.write_text(b, encoding="utf-8", newline="\n")
print("building OK")

# --- resource_node ---
rn = (ROOT / "resource_node.gd").read_text(encoding="utf-8")
if "asset_kit" not in rn:
    rn = rn.replace(
        'extends Node3D\nclass_name ResourceNode3D\n',
        'extends Node3D\nclass_name ResourceNode3D\nconst Assets := preload("res://scripts/asset_kit.gd")\n',
    )
# replace visual body
import re
rn2, n = re.subn(
    r"func _build_visual\(\) -> void:.*?(\t_label = Label3D\.new\(\))",
    r'''func _build_visual() -> void:
\tmatch kind:
\t\tKind.WOOD:
\t\t\tif Assets.attach(self, "candy_tree", Vector3(2.8, 5.0, 2.8)) == null:
\t\t\t\tconst Kit := preload("res://scripts/mesh_kit.gd")
\t\t\t\tKit.build_candy_tree(self)
\t\t\t_mesh = MeshInstance3D.new()
\t\t\t_mesh.visible = false
\t\t\tadd_child(_mesh)
\t\tKind.STONE:
\t\t\tif Assets.attach(self, "stone", Vector3(2.4, 1.6, 2.2)) == null:
\t\t\t\tpass
\t\t\t_mesh = MeshInstance3D.new()
\t\t\t_mesh.visible = false
\t\t\tadd_child(_mesh)
\t\tKind.GOLD:
\t\t\tif Assets.attach(self, "gold", Vector3(2.2, 1.5, 2.0)) == null:
\t\t\t\tpass
\t\t\t_mesh = MeshInstance3D.new()
\t\t\t_mesh.visible = false
\t\t\tadd_child(_mesh)
\1''',
    rn,
    count=1,
    flags=re.S,
)
print("resource replace", n)
(ROOT / "resource_node.gd").write_text(rn2, encoding="utf-8", newline="\n")

# --- villager ---
vg = (ROOT / "villager.gd").read_text(encoding="utf-8")
if "asset_kit" not in vg:
    vg = vg.replace(
        'const Combat := preload("res://scripts/combat.gd")\n',
        'const Combat := preload("res://scripts/combat.gd")\nconst Assets := preload("res://scripts/asset_kit.gd")\n',
    )
s = vg.find("func _build_visual() -> void:")
e = vg.find("_carry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED")
if s < 0 or e < 0:
    raise SystemExit("villager markers")
new_vg = '''func _build_visual() -> void:
\tif Assets.attach(self, "villager", Vector3(0.9, 1.7, 0.7)) == null:
\t\tconst Kit := preload("res://scripts/mesh_kit.gd")
\t\tKit.build_toy_villager(self)
\t_body = MeshInstance3D.new()
\t_body.visible = false
\tadd_child(_body)

\t_select = MeshInstance3D.new()
\tvar tor := TorusMesh.new()
\ttor.inner_radius = 0.35
\ttor.outer_radius = 0.48
\t_select.mesh = tor
\t_select.position.y = 0.04
\tvar sm := StandardMaterial3D.new()
\tsm.albedo_color = Color(0.2, 0.9, 0.3, 0.9)
\tsm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\tsm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
\tsm.render_priority = -4
\tsm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
\t_select.material_override = sm
\t_select.visible = false
\t_select.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
\tadd_child(_select)

\t_carry_label = Label3D.new()
\t_carry_label.position = Vector3(0, 1.95, 0)
\t_carry_label.font_size = 36
\t_carry_label.modulate = Color(1, 0.9, 0.3)
\t_carry_label.outline_size = 8
\t'''
vg = vg[:s] + new_vg + vg[e:]
(ROOT / "villager.gd").write_text(vg, encoding="utf-8", newline="\n")
print("villager OK")

# --- soldier ---
sd = (ROOT / "soldier.gd").read_text(encoding="utf-8")
if "asset_kit" not in sd:
    sd = sd.replace(
        'const Combat := preload("res://scripts/combat.gd")\n',
        'const Combat := preload("res://scripts/combat.gd")\nconst Assets := preload("res://scripts/asset_kit.gd")\n',
    )
s = sd.find("func _build_visual() -> void:")
marker = "\tadd_child(_select)\n\tif team == \"enemy\":"
e = sd.find(marker, s)
if s < 0 or e < 0:
    raise SystemExit("soldier markers")
new_sd = '''func _build_visual() -> void:
\tvar key := "zombie" if is_zombie else ("enemy" if team == "enemy" else "soldier")
\tif Assets.attach(self, key, Vector3(0.95, 1.7, 0.95)) == null:
\t\tconst Kit := preload("res://scripts/mesh_kit.gd")
\t\tKit.build_toy_soldier(self, team, is_zombie)
\t_body = MeshInstance3D.new()
\t_body.visible = false
\tvar mat := StandardMaterial3D.new()
\tif is_zombie:
\t\tmat.albedo_color = Color(0.45, 0.75, 0.38)
\telif team == "enemy":
\t\tmat.albedo_color = Color(1.0, 0.28, 0.90)
\telse:
\t\tmat.albedo_color = Color(0.90, 0.28, 0.22)
\t_body.material_override = mat
\tadd_child(_body)
\t_select = MeshInstance3D.new()
\tvar tor := TorusMesh.new()
\ttor.inner_radius = 0.55
\ttor.outer_radius = 0.85 if team == "enemy" else 0.72
\ttor.rings = 6
\ttor.ring_segments = 20
\t_select.mesh = tor
\t_select.position.y = 0.04
\tvar sm := StandardMaterial3D.new()
\tif is_zombie:
\t\tsm.albedo_color = Color(0.4, 0.9, 0.25, 0.9)
\telif team == "enemy":
\t\tsm.albedo_color = Color(1.0, 0.2, 0.95, 0.95)
\telse:
\t\tsm.albedo_color = Color(0.2, 1.0, 0.35, 0.9)
\tsm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\tsm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
\tsm.render_priority = -4
\tsm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
\t_select.material_override = sm
\t_select.visible = (team == "enemy")
\t_select.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
'''
sd = sd[:s] + new_sd + sd[e:]
while "\tadd_child(_select)\n\tadd_child(_select)\n" in sd:
    sd = sd.replace("\tadd_child(_select)\n\tadd_child(_select)\n", "\tadd_child(_select)\n")
(ROOT / "soldier.gd").write_text(sd, encoding="utf-8", newline="\n")
print("soldier OK")
print("WIRE DONE")
