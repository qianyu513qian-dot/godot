import unreal
import json
import os

OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village\env\map_village_day_actors.json"
MAP_PATH = "/Game/Fantastic_Village_Pack/maps/map_village_day"

# Load level
ok = unreal.EditorLevelLibrary.load_level(MAP_PATH)
unreal.log("load_level %s -> %s" % (MAP_PATH, ok))

actors = unreal.EditorLevelLibrary.get_all_level_actors()
rows = []
lights = []
for a in actors:
    try:
        name = a.get_name()
        cls = a.get_class().get_name()
        t = a.get_actor_transform()
        loc = t.translation
        rot = t.rotation.rotator()
        scale = t.scale3d
        mesh_path = ""
        # Static mesh
        if hasattr(a, "static_mesh_component") or cls in ("StaticMeshActor", "StaticMeshActor"):
            try:
                smc = a.static_mesh_component
                if smc and smc.static_mesh:
                    mesh_path = smc.static_mesh.get_path_name()
            except Exception:
                pass
        # Try generic get_component_by_class
        if not mesh_path:
            try:
                smc = a.get_component_by_class(unreal.StaticMeshComponent)
                if smc and smc.static_mesh:
                    mesh_path = smc.static_mesh.get_path_name()
            except Exception:
                pass
        row = {
            "name": name,
            "class": cls,
            "mesh": mesh_path,
            "loc": [loc.x, loc.y, loc.z],
            "rot": [rot.pitch, rot.yaw, rot.roll],
            "scale": [scale.x, scale.y, scale.z],
        }
        rows.append(row)
        if "Light" in cls or "Sky" in cls or "Exponential" in cls or "Directional" in cls or "SkyAtmosphere" in cls or "SkyLight" in cls or "HeightFog" in cls:
            info = dict(row)
            try:
                if isinstance(a, unreal.DirectionalLight):
                    c = a.get_component_by_class(unreal.DirectionalLightComponent)
                    if c:
                        info["intensity"] = float(c.intensity)
                        info["light_color"] = [c.light_color.r, c.light_color.g, c.light_color.b, c.light_color.a]
                        info["temperature"] = float(getattr(c, "temperature", 0) or 0)
                        info["cast_shadows"] = bool(c.cast_shadows)
                elif isinstance(a, unreal.SkyLight):
                    c = a.get_component_by_class(unreal.SkyLightComponent)
                    if c:
                        info["intensity"] = float(c.intensity)
                        info["light_color"] = [c.light_color.r, c.light_color.g, c.light_color.b, c.light_color.a]
                elif isinstance(a, unreal.ExponentialHeightFog):
                    c = a.get_component_by_class(unreal.ExponentialHeightFogComponent)
                    if c:
                        info["fog_density"] = float(c.fog_density)
                        info["fog_height_falloff"] = float(c.fog_height_falloff)
                        info["fog_inscattering"] = [c.fog_inscattering_color.r, c.fog_inscattering_color.g, c.fog_inscattering_color.b, c.fog_inscattering_color.a]
            except Exception as e:
                info["light_err"] = str(e)
            lights.append(info)
    except Exception as e:
        rows.append({"error": str(e), "name": str(a)})

# mesh usage counts
from collections import Counter
mc = Counter()
for r in rows:
    m = r.get("mesh") or ""
    if m:
        mc[m.split(".")[-1] if "." in m else m] += 1

payload = {
    "map": MAP_PATH,
    "actor_count": len(rows),
    "actors": rows,
    "lights": lights,
    "mesh_counts": mc.most_common(80),
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=1)
unreal.log("WROTE %s actors=%d lights=%d" % (OUT, len(rows), len(lights)))
with open(OUT.replace(".json", "_done.txt"), "w") as f:
    f.write("ok actors=%d lights=%d\n" % (len(rows), len(lights)))
