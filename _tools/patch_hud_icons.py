from pathlib import Path
hud_path = Path(r"C:\Users\cc\Documents\GodotProjects\AoELite3D\scripts\ui\rts_hud.gd")
hud = hud_path.read_text(encoding="utf-8")
start = hud.find("func _mk_icon_res(")
end = hud.find("\nfunc ", start + 1)
if start < 0 or end < 0:
    raise SystemExit("mk_icon_res not found")
new = '''func _mk_icon_res(parent: HBoxContainer, icon_col: Color, tip: String) -> Label:
\tvar wrap := HBoxContainer.new()
\twrap.add_theme_constant_override("separation", 4)
\tparent.add_child(wrap)
\tvar icon := TextureRect.new()
\ticon.custom_minimum_size = Vector2(22, 22)
\ticon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\ticon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\ticon.tooltip_text = tip
\tvar key := "meat"
\tif tip == "木":
\t\tkey = "wood"
\telif tip == "石":
\t\tkey = "stone"
\telif tip == "金":
\t\tkey = "gold"
\telif tip == "人":
\t\tkey = "pop"
\tvar ipath := "res://assets/icons/%s.png" % key
\tif ResourceLoader.exists(ipath):
\t\ticon.texture = load(ipath) as Texture2D
\t\twrap.add_child(icon)
\telse:
\t\tvar cr := ColorRect.new()
\t\tcr.custom_minimum_size = Vector2(22, 22)
\t\tcr.color = icon_col
\t\twrap.add_child(cr)
\tvar l := Label.new()
\tl.text = "0"
\tl.add_theme_font_size_override("font_size", 15)
\tl.add_theme_color_override("font_color", Color(0.35, 0.22, 0.10))
\twrap.add_child(l)
\treturn l

'''
hud = hud[:start] + new + hud[end+1:]
hud_path.write_text(hud, encoding="utf-8", newline="\n")
print("HUD patched")

rn = Path(r"C:\Users\cc\Documents\GodotProjects\AoELite3D\scripts\resource_node.gd").read_text(encoding="utf-8")
# ensure label block ok
if "\t\t_label = Label3D" in rn:
    rn = rn.replace("\t\t_label = Label3D.new()", "\t_label = Label3D.new()")
    Path(r"C:\Users\cc\Documents\GodotProjects\AoELite3D\scripts\resource_node.gd").write_text(rn, encoding="utf-8", newline="\n")
    print("fixed label indent")
i = rn.find("func _build_visual")
print(rn[i:i+500])
