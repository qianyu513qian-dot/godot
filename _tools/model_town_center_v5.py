"""Town center v5 — Track-To camera; dramatic eave curl; cobalt mid clearly visible."""
import bpy, bmesh, math
from mathutils import Vector, Matrix

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 96
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1100
sc.render.resolution_y = 1300
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (1.0, 0.78, 0.52, 1); bg.inputs[1].default_value = 0.7
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(n, c, r=0.2, coat=0.95, metal=0.0):
    m = bpy.data.materials.new(n); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    o = nodes.new("ShaderNodeOutputMaterial"); b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Roughness"].default_value = r
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.06
    links.new(b.outputs[0], o.inputs[0]); return m

MW = mat("Wall", (0.97, 0.95, 0.92), 0.38, 0.4)
MD = mat("Wood", (0.52, 0.33, 0.16), 0.42, 0.3)
MR = mat("Red", (0.90, 0.06, 0.04), 0.12, 1.0)
MB = mat("Blue", (0.05, 0.26, 0.88), 0.12, 1.0)
MG = mat("Gold", (0.95, 0.75, 0.2), 0.18, 0.8, 0.35)
MS = mat("Stone", (0.6, 0.54, 0.45), 0.55, 0.12)
MDoor = mat("Door", (0.2, 0.1, 0.06), 0.4, 0.2)
MGrass = mat("Grass", (0.26, 0.5, 0.2), 0.85, 0.05)
MDirt = mat("Dirt", (0.68, 0.52, 0.35), 0.7, 0.05)

def setm(o, m):
    o.data.materials.clear(); o.data.materials.append(m)

def bevel(o, width=0.045, seg=4):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("B", "BEVEL"); md.width = width; md.segments = seg
    md.limit_method = "ANGLE"; md.angle_limit = math.radians(20)
    bpy.ops.object.modifier_apply(modifier=md.name)

def box(name, loc, sx, sy, sz, m, bw=0.045):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = (sx, sy, sz); bpy.ops.object.transform_apply(scale=True)
    setm(o, m); bevel(o, bw, 4); return o

def pagoda_roof(name, z0, size, rise, m, curl_h=0.55, segs=48):
    """Hip roof: center high, mid low, eaves curl UP by curl_h above the low point."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=size, location=(0, 0, z0))
    o = bpy.context.active_object; o.name = name
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    hw = size * 0.5
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        t = max(abs(x), abs(y)) / hw  # 0..1
        t = min(1.0, max(0.0, t))
        # classic: high at 0, drops to valley near 0.75, then curls up to edge
        # use smoothstep pieces
        if t < 0.72:
            # descending from rise to valley
            u = t / 0.72
            z = rise * (1.0 - 0.88 * u)  # valley ~ 0.12*rise
        else:
            u = (t - 0.72) / 0.28  # 0..1 outer band
            valley = rise * 0.12
            z = valley + curl_h * (u ** 1.2)  # curl up
        # tile ridges wave
        z += 0.04 * math.sin((x / hw) * math.pi * 14) * (0.2 + 0.8 * t)
        v.co.z = z
    bmesh.update_edit_mesh(o.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    md = o.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.12
    md.offset = -1.0
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(o, m)
    bpy.ops.object.shade_smooth()
    bevel(o, 0.015, 2)

    # dense tile bars
    extras = []
    for i in range(1, 18):
        yy = -hw + size * (i / 18.0)
        t = abs(yy) / hw
        if t < 0.72:
            u = t / 0.72
            z = z0 + rise * (1.0 - 0.88 * u)
        else:
            u = (t - 0.72) / 0.28
            z = z0 + rise * 0.12 + curl_h * (u ** 1.2)
        z += 0.055
        span = size * (0.95 - 0.1 * t)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.03, depth=span,
            location=(0, yy, z), rotation=(0, math.pi/2, 0))
        c = bpy.context.active_object; setm(c, m); extras.append(c)

    # gold corner finials at eave tips (highest outer corners)
    for sx, sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x, y = sx * hw * 0.96, sy * hw * 0.96
        z = z0 + rise * 0.12 + curl_h + 0.08
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(x, y, z), segments=14, ring_count=8)
        tip = bpy.context.active_object; setm(tip, MG); extras.append(tip)

    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for e in extras: e.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    print(f"{name} bbox_z={o.dimensions.z:.2f} curl={curl_h}")
    return o

# ---- assemble (compact footprint, clear tier gaps) ----
box("Plinth", (0,0,0.1), 3.2, 3.2, 0.2, MS, 0.04)
box("Steps", (0,-1.75,0.08), 1.2, 0.45, 0.16, MS, 0.025)
box("Wall1", (0,0,0.8), 2.5, 2.5, 1.2, MW, 0.055)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P1_{sx}_{sy}", (sx*1.15, sy*1.15, 0.8), 0.2, 0.2, 1.25, MD, 0.04)
box("BeamF", (0,-1.15,1.3), 2.5, 0.15, 0.15, MD, 0.025)
box("Door", (0,-1.28,0.55), 0.55, 0.07, 0.85, MDoor, 0.02)

# Roof1 crimson — big overhang + strong curl
pagoda_roof("Roof1", 1.45, 3.6, 0.65, MR, curl_h=0.55, segs=48)

# Mid story taller so blue roof sits clear above
box("Wall2", (0,0,2.55), 1.8, 1.8, 1.05, MW, 0.045)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P2_{sx}_{sy}", (sx*0.82, sy*0.82, 2.55), 0.16, 0.16, 1.1, MD, 0.03)
box("Beam2", (0,-0.82,2.95), 1.8, 0.12, 0.12, MD, 0.02)

# Roof2 COBALT — prominent
pagoda_roof("Roof2", 3.15, 2.7, 0.55, MB, curl_h=0.5, segs=40)

# Top lantern story
box("Wall3", (0,0,3.95), 1.0, 1.0, 0.65, MW, 0.035)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P3_{sx}_{sy}", (sx*0.45, sy*0.45, 3.95), 0.11, 0.11, 0.7, MD, 0.02)

pagoda_roof("Roof3", 4.35, 1.55, 0.42, MR, curl_h=0.42, segs=32)

bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=(0,0,4.95), segments=18, ring_count=10)
setm(bpy.context.active_object, MG)
bpy.ops.mesh.primitive_cone_add(radius1=0.09, depth=0.24, location=(0,0,5.15))
setm(bpy.context.active_object, MG)

for sx in (-1.1, 1.1):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.055, depth=0.11, location=(sx, -1.35, 1.65))
    setm(bpy.context.active_object, MG)

bpy.ops.mesh.primitive_plane_add(size=18, location=(0,0,0))
gp = bpy.context.active_object; gp.name = "GrassPlane"; setm(gp, MGrass)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=2.9, depth=0.035, location=(0,0,0.018))
setm(bpy.context.active_object, MDirt)

# Aim target at visual center of building
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 2.6))
target = bpy.context.active_object; target.name = "LookAt"

# Camera: 3/4 view, high enough to see all tiers
bpy.ops.object.camera_add(location=(7.2, -8.0, 5.5))
cam = bpy.context.active_object; cam.name = "BeautyCam"
cam.data.lens = 60
cam.data.clip_start = 0.1
cam.data.dof.use_dof = True
cam.data.dof.focus_object = target
cam.data.dof.aperture_fstop = 3.2
# Track To
con = cam.constraints.new("TRACK_TO")
con.target = target
con.track_axis = "TRACK_NEGATIVE_Z"
con.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="SUN", location=(5,-3,9))
sun = bpy.context.active_object
sun.data.energy = 5.0; sun.data.color = (1.0, 0.86, 0.55)
sun.rotation_euler = (math.radians(40), math.radians(12), math.radians(-30))
sun.data.angle = math.radians(4)

bpy.ops.object.light_add(type="AREA", location=(-3.5, 2, 3.5))
f = bpy.context.active_object; f.data.energy = 95; f.data.color=(0.5,0.66,1); f.data.size=4.5

bpy.ops.object.light_add(type="AREA", location=(2.5,-4.5,2))
r = bpy.context.active_object; r.data.energy=50; r.data.color=(1.0,0.5,0.28); r.data.size=2.2

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium High Contrast"
sc.view_settings.exposure = 0.2

try:
    p = bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type = "CUDA"
    for d in p.devices: d.use = True
except Exception:
    pass

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED_BLEND")
bpy.ops.render.render(write_still=True)
print("SAVED_PNG")
for o in sc.objects:
    o.select_set(o.type=="MESH" and o.name!="GrassPlane" and max(o.dimensions)<12)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB"); print("DONE")
