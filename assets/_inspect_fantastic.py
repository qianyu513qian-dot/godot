import bpy
import json
from pathlib import Path

out = Path(r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_pack_inventory.json")
out.parent.mkdir(parents=True, exist_ok=True)

data = {
    "filepath": bpy.data.filepath,
    "objects": [],
    "materials": [],
    "images": [],
    "lights": [],
    "worlds": [],
    "collections": [],
    "scenes": [],
}

for o in bpy.data.objects:
    entry = {
        "name": o.name,
        "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "location": [round(v, 3) for v in o.location],
        "hide_viewport": bool(o.hide_viewport),
        "materials": [s.material.name for s in getattr(o, "material_slots", []) if s.material],
    }
    if o.type == "MESH" and o.data:
        entry["verts"] = len(o.data.vertices)
        entry["polys"] = len(o.data.polygons)
    data["objects"].append(entry)

for m in bpy.data.materials:
    mats = {"name": m.name, "use_nodes": m.use_nodes, "textures": []}
    if m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                mats["textures"].append({"node": n.name, "image": n.image.name, "filepath": n.image.filepath})
            if n.type == "BSDF_PRINCIPLED":
                mats["principled"] = True
    data["materials"].append(mats)

for img in bpy.data.images:
    data["images"].append({
        "name": img.name,
        "filepath": img.filepath,
        "size": list(img.size) if img.size else None,
        "packed": bool(img.packed_file),
        "colorspace": img.colorspace_settings.name if img.colorspace_settings else None,
    })

for o in bpy.data.objects:
    if o.type == "LIGHT":
        data["lights"].append({
            "name": o.name,
            "light_type": o.data.type,
            "energy": getattr(o.data, "energy", None),
            "color": list(o.data.color) if hasattr(o.data, "color") else None,
            "location": [round(v, 3) for v in o.location],
        })

for w in bpy.data.worlds:
    winfo = {"name": w.name, "use_nodes": w.use_nodes, "nodes": []}
    if w.use_nodes and w.node_tree:
        for n in w.node_tree.nodes:
            node = {"type": n.type, "name": n.name}
            if n.type == "TEX_ENVIRONMENT" and getattr(n, "image", None):
                node["image"] = n.image.name
                node["filepath"] = n.image.filepath
            if n.type == "BACKGROUND":
                try:
                    node["strength"] = n.inputs["Strength"].default_value
                    node["color"] = list(n.inputs["Color"].default_value)
                except Exception:
                    pass
            if n.type == "SKY_TEXTURE":
                node["sky_type"] = getattr(n, "sky_type", None)
            winfo["nodes"].append(node)
    data["worlds"].append(winfo)

for c in bpy.data.collections:
    data["collections"].append({"name": c.name, "objects": [o.name for o in c.objects]})

for s in bpy.data.scenes:
    data["scenes"].append({
        "name": s.name,
        "world": s.world.name if s.world else None,
        "eevee": True,
        "view_settings": s.view_settings.view_transform if s.view_settings else None,
    })

# Keyword filters for report
keywords = ("ground", "grass", "path", "road", "dirt", "soil", "terrain", "land", "floor", "mud", "stone_path", "pavement", "rock", "cliff", "water", "sky", "light", "sun", "hdri", "env")
def match(name):
    n = name.lower()
    return [k for k in keywords if k in n]

data["ground_like_objects"] = [o["name"] for o in data["objects"] if match(o["name"])]
data["ground_like_materials"] = [m["name"] for m in data["materials"] if match(m["name"])]
data["ground_like_images"] = [i["name"] for i in data["images"] if match(i["name"])]

out.write_text(json.dumps(data, indent=2), encoding="utf-8")
print("WROTE", out)
print("OBJECTS", len(data["objects"]))
print("MATERIALS", len(data["materials"]))
print("IMAGES", len(data["images"]))
print("LIGHTS", len(data["lights"]))
print("WORLDS", len(data["worlds"]))
print("GROUND_OBJ", data["ground_like_objects"])
print("GROUND_MAT", data["ground_like_materials"])
print("GROUND_IMG", data["ground_like_images"])
print("LIGHT_NAMES", [l["name"] for l in data["lights"]])
print("WORLD_NAMES", [w["name"] for w in data["worlds"]])
