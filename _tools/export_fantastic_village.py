import bpy
import os
from mathutils import Vector, Matrix
from math import radians

BLEND = r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\FANTASTIC_-_Village_Pack-52529a12\blender\fantastic_village_pack_blend.blend"
OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village"

# key -> (object names to join, extra euler_xyz degrees before recenter)
# Wall in pack: height along Y, length along Z — rotate so Z-up height, X length, Y thickness
EXPORTS = {
    "town_center": (["SM_BLD_body_v01_01"], (0, 0, 0)),
    "house": (["SM_BLD_body_v03_01"], (0, 0, 0)),
    "barracks": (["SM_BLD_body_v02_01"], (0, 0, 0)),
    "garrison": (["SM_BLD_body_v04_01"], (0, 0, 0)),
    "relay": (["SM_PROP_market_v04_01"], (0, 0, 0)),
    "scout_camp": (["SM_PROP_market_v01_01"], (0, 0, 0)),
    "arrow_tower": (["SM_PROP_watchtower_wood_01"], (0, 0, 0)),
    "wall": (["SM_PROP_wall_wood"], (90, 0, 0)),  # Y-up height -> Z-up
    "gate": (["SM_PROP_wall_wood_gate_frame_01", "SM_PROP_wall_wood_gate_door_L_01", "SM_PROP_wall_wood_gate_door_R_01"], (0, 0, 0)),
    "candy_tree": (["SM_ENV_TREE_village_LOD0"], (0, 0, 0)),
}

def clear_scene_selection():
    bpy.ops.object.select_all(action='DESELECT')

def bbox_world(obj):
    mats = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [v.x for v in mats]; ys = [v.y for v in mats]; zs = [v.z for v in mats]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))

def export_one(key, names, euler_deg):
    # Fresh load each time to avoid mutation issues
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    objs = []
    for n in names:
        o = bpy.data.objects.get(n)
        if o is None:
            print("MISSING", n, "for", key)
            return False
        objs.append(o)

    # Duplicate into a temp collection
    clear_scene_selection()
    dups = []
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False
        dup = o.copy()
        if o.data:
            dup.data = o.data.copy()
        bpy.context.scene.collection.objects.link(dup)
        # clear parenting transform bake
        dup.parent = None
        dup.matrix_world = o.matrix_world.copy()
        dups.append(dup)
        dup.select_set(True)

    bpy.context.view_layer.objects.active = dups[0]
    # Apply rotation offset if needed (wall)
    ex, ey, ez = euler_deg
    if ex or ey or ez:
        for d in dups:
            d.rotation_euler.rotate_axis('X', radians(ex))
            if ey: d.rotation_euler.rotate_axis('Y', radians(ey))
            if ez: d.rotation_euler.rotate_axis('Z', radians(ez))
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Join if multiple
    if len(dups) > 1:
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
    else:
        joined = dups[0]
    joined.name = key

    # Recenter: bottom on Z=0, XZ centered (Blender Z-up)
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    mn, mx = bbox_world(joined)
    center = (mn + mx) * 0.5
    joined.location.x -= center.x
    joined.location.y -= center.y
    joined.location.z -= mn.z
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = bbox_world(joined)
    dims = mx - mn
    print(f"EXPORT {key} dims=({dims.x:.3f},{dims.y:.3f},{dims.z:.3f}) z0={mn.z:.3f}")

    # Select only this
    clear_scene_selection()
    joined.select_set(True)
    bpy.context.view_layer.objects.active = joined
    out_path = os.path.join(OUT, f"{key}.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_yup=True,
    )
    print("WROTE", out_path, os.path.getsize(out_path))
    return True

os.makedirs(OUT, exist_ok=True)
results = {}
for key, (names, eul) in EXPORTS.items():
    try:
        ok = export_one(key, names, eul)
        results[key] = ok
    except Exception as e:
        print("FAIL", key, e)
        results[key] = False

print("DONE", results)
