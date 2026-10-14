import bpy, os
from mathutils import Vector
from math import radians

BLEND = r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\FANTASTIC_-_Village_Pack-52529a12\blender\fantastic_village_pack_blend.blend"
OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village"

def bbox_world(obj):
    mats = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs=[v.x for v in mats]; ys=[v.y for v in mats]; zs=[v.z for v in mats]
    return Vector((min(xs),min(ys),min(zs))), Vector((max(xs),max(ys),max(zs)))

def export_wall():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    o=bpy.data.objects.get("SM_PROP_wall_wood")
    o.hide_set(False)
    d=o.copy(); d.data=o.data.copy()
    bpy.context.scene.collection.objects.link(d)
    d.parent=None; d.matrix_world=o.matrix_world.copy()
    bpy.ops.object.select_all(action='DESELECT')
    d.select_set(True); bpy.context.view_layer.objects.active=d
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    d.location=(0,0,0); d.rotation_euler=(0,0,0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    d.rotation_euler[0]=radians(-90)
    bpy.ops.object.transform_apply(rotation=True)
    d.rotation_euler[2]=radians(90)
    bpy.ops.object.transform_apply(rotation=True)
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    mn,mx=bbox_world(d); c=(mn+mx)*0.5
    d.location=(-c.x,-c.y,-mn.z)
    bpy.ops.object.transform_apply(location=True)
    mn,mx=bbox_world(d); dims=mx-mn
    print(f"wall BL=({dims.x:.2f},{dims.y:.2f},{dims.z:.2f}) GD~=({dims.x:.2f},{dims.z:.2f},{dims.y:.2f})")
    d.name="wall"
    bpy.ops.object.select_all(action='DESELECT'); d.select_set(True); bpy.context.view_layer.objects.active=d
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,"wall.glb"), export_format='GLB', use_selection=True, export_apply=True,
        export_texcoords=True, export_normals=True, export_materials='EXPORT', export_image_format='AUTO', export_yup=True)

def export_gate():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    o=bpy.data.objects.get("SM_PROP_wall_wood_gate_frame_01")
    o.hide_set(False)
    d=o.copy(); d.data=o.data.copy()
    bpy.context.scene.collection.objects.link(d)
    d.parent=None; d.matrix_world=o.matrix_world.copy()
    bpy.ops.object.select_all(action='DESELECT')
    d.select_set(True); bpy.context.view_layer.objects.active=d
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    d.location=(0,0,0); d.rotation_euler=(0,0,0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    d.rotation_euler[2]=radians(-90)
    bpy.ops.object.transform_apply(rotation=True)
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    mn,mx=bbox_world(d); c=(mn+mx)*0.5
    d.location=(-c.x,-c.y,-mn.z)
    bpy.ops.object.transform_apply(location=True)
    mn,mx=bbox_world(d); dims=mx-mn
    print(f"gate BL=({dims.x:.2f},{dims.y:.2f},{dims.z:.2f}) GD~=({dims.x:.2f},{dims.z:.2f},{dims.y:.2f})")
    d.name="gate"
    bpy.ops.object.select_all(action='DESELECT'); d.select_set(True); bpy.context.view_layer.objects.active=d
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,"gate.glb"), export_format='GLB', use_selection=True, export_apply=True,
        export_texcoords=True, export_normals=True, export_materials='EXPORT', export_image_format='AUTO', export_yup=True)

export_wall()
export_gate()
print("OK")
