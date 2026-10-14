import bpy
import os
from mathutils import Vector
from math import radians

BLEND = r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\FANTASTIC_-_Village_Pack-52529a12\blender\fantastic_village_pack_blend.blend"
OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village"

def bbox_world(obj):
    mats = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs=[v.x for v in mats]; ys=[v.y for v in mats]; zs=[v.z for v in mats]
    return Vector((min(xs),min(ys),min(zs))), Vector((max(xs),max(ys),max(zs)))

def prep_and_export(key, names, rotations):
    """rotations: list of (axis, degrees) applied in order, axis in XYZ"""
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    dups=[]
    for n in names:
        o=bpy.data.objects.get(n)
        if not o:
            print("MISSING",n); return
        o.hide_set(False); o.hide_viewport=False; o.hide_render=False
        d=o.copy(); d.data=o.data.copy()
        bpy.context.scene.collection.objects.link(d)
        d.parent=None; d.matrix_world=o.matrix_world.copy()
        dups.append(d)
    bpy.ops.object.select_all(action='DESELECT')
    for d in dups: d.select_set(True)
    bpy.context.view_layer.objects.active=dups[0]
    for axis, deg in rotations:
        bpy.ops.transform.rotate(value=radians(deg), orient_axis=axis, orient_type='GLOBAL', constraint_axis=(axis=='X',axis=='Y',axis=='Z'))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if len(dups)>1:
        bpy.ops.object.join()
    joined=bpy.context.view_layer.objects.active
    joined.name=key
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    mn,mx=bbox_world(joined)
    c=(mn+mx)*0.5
    joined.location.x-=c.x; joined.location.y-=c.y; joined.location.z-=mn.z
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn,mx=bbox_world(joined); dims=mx-mn
    print(f"{key} blender_dims XYZ=({dims.x:.2f},{dims.y:.2f},{dims.z:.2f}) -> godot approx (x={dims.x:.2f}, y={dims.z:.2f}, z={dims.y:.2f})")
    bpy.ops.object.select_all(action='DESELECT')
    joined.select_set(True)
    bpy.context.view_layer.objects.active=joined
    path=os.path.join(OUT,f"{key}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
        export_texcoords=True, export_normals=True, export_materials='EXPORT', export_image_format='AUTO', export_yup=True)
    print("WROTE",path,os.path.getsize(path))

# Want Blender X=length, Y=thickness, Z=height so Godot (Y-up): X=length, Y=height, Z=thickness
# Original wall: X=thick~3.6, Y=height~6.26, Z=length~10.3
# Rotate +90 around Y: X<-Z length, Y height, Z<-X?  R_y(90): (x,y,z)->(z,y,-x) => (length, height, -thick) good if we then fix
prep_and_export("wall", ["SM_PROP_wall_wood"], [('Y', 90)])
# Gate frame: X=1.53 thick, Y=6.48 length, Z=7.47 height -> want X=length, Y=thick, Z=height
# R_z(-90): (x,y,z)->(y,-x,z) => (length, -thick, height) then maybe ok
prep_and_export("gate", ["SM_PROP_wall_wood_gate_frame_01"], [('Z', -90)])
print("REORIENT_DONE")
