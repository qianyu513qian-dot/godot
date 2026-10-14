import bpy
import os

BLEND = r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\FANTASTIC_-_Village_Pack-52529a12\blender\fantastic_village_pack_blend.blend"
OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village\pieces"
LIST = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village\env\meshes_to_export.txt"
os.makedirs(OUT, exist_ok=True)

names = [ln.strip() for ln in open(LIST, encoding="utf-8") if ln.strip()]
print("loading blend...", BLEND)
bpy.ops.wm.open_mainfile(filepath=BLEND)
print("objects", len(bpy.data.objects))

ok = 0
missing = []
for name in names:
    obj = bpy.data.objects.get(name)
    if obj is None:
        # try without suffix variants
        missing.append(name)
        print("MISSING", name)
        continue
    # unhide
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    bpy.ops.object.select_all(action='DESELECT')
    # export duplicate at origin with world transform baked? Keep object transform zeroed for export of mesh data only
    # Best: export with object world matrix applied so mesh verts match UE local space with identity transform.
    dup = obj.copy()
    if obj.data:
        dup.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(dup)
    # Bake world transform into mesh, then move to origin
    mw = obj.matrix_world.copy()
    dup.matrix_world = mw
    bpy.context.view_layer.objects.active = dup
    dup.select_set(True)
    # Apply transforms so local = world geometry, then clear location to 0 keeping rotation/scale applied
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # After apply, object at baked verts with loc 0 - but we applied location which shifted verts by world loc.
    # Undo location bake: we want mesh in local space as authored for UE (component local), NOT world.
    # Recreate properly:
    bpy.data.objects.remove(dup, do_unlink=True)
    dup = obj.copy()
    if obj.data:
        dup.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(dup)
    dup.parent = None
    dup.location = (0, 0, 0)
    dup.rotation_euler = (0, 0, 0)
    dup.scale = (1, 1, 1)
    # Use original data which is already in local space
    bpy.ops.object.select_all(action='DESELECT')
    dup.select_set(True)
    bpy.context.view_layer.objects.active = dup
    out_path = os.path.join(OUT, name + ".glb")
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
    print("WROTE", name, os.path.getsize(out_path))
    bpy.data.objects.remove(dup, do_unlink=True)
    ok += 1

print("DONE ok", ok, "missing", len(missing))
open(os.path.join(OUT, "_export_report.txt"), "w").write("ok=%d missing=%d\n%s\n" % (ok, len(missing), "\n".join(missing)))
