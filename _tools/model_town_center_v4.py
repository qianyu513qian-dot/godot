"""Town center v4 — camera shows full 3-tier; stronger eave curl; clearer cobalt mid roof."""
import bpy, bmesh, math

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 80
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1200
sc.render.resolution_y = 1400
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (1.0, 0.80, 0.55, 1)
bg.inputs[1].default_value = 0.75
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(n, c, r=0.22, coat=0.9):
    m = bpy.data.materials.new(n); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    o = nodes.new("ShaderNodeOutputMaterial"); b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*c, 1); b.inputs["Roughness"].default_value = r
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.07
    links.new(b.outputs[0], o.inputs[0]); return m

MW = mat("Wall", (0.97, 0.95, 0.91), 0.4, 0.35)
MD = mat("Wood", (0.48, 0.30, 0.15), 0.45, 0.3)
MR = mat("Red", (0.88, 0.07, 0.05), 0.14, 1.0)
MB = mat("Blue", (0.06, 0.28, 0.85), 0.14, 1.0)
MG = mat("Gold", (0.95, 0.74, 0.18), 0.2, 0.75)
MS = mat("Stone", (0.58, 0.52, 0.43), 0.55, 0.15)
MDoor = mat("Door", (0.22, 0.12, 0.07), 0.4, 0.2)
MGrass = mat("Grass", (0.28, 0.52, 0.22), 0.8, 0.05)
MDirt = mat("Dirt", (0.66, 0.50, 0.34), 0.7, 0.05)

def setm(o, m):
    o.data.materials.clear(); o.data.materials.append(m)

def bevel(o, w=0.045, s=4):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("B", "BEVEL"); md.width = w; md.segments = s
    md.limit_method = "ANGLE"; md.angle_limit = math.radians(22)
    bpy.ops.object.modifier_apply(modifier=md.name)

def box(name, loc, sx, sy, sz, m, bw=0.045):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = (sx, sy, sz); bpy.ops.object.transform_apply(scale=True)
    setm(o, m); bevel(o, bw, 4); return o

def roof(name, z0, size, rise, m, curl=0.95, segs=40):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=size, location=(0, 0, z0))
    o = bpy.context.active_object; o.name = name
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data); hw = size * 0.5
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        # radial + diamond hybrid for nicer hip
        t_d = max(abs(x), abs(y)) / hw
        t_r = math.sqrt(x*x + y*y) / (hw * math.sqrt(2))
        t = 0.65 * t_d + 0.35 * min(1.0, t_r)
        t = min(1.0, t)
        base = rise * (1.0 - 0.75 * t)
        # strong upturned eaves: kicks up hard in outer 40%
        e = max(0.0, (t - 0.45) / 0.55)
        up = rise * curl * (e ** 1.35)
        wave = 0.035 * math.sin((x / hw) * math.pi * 12) * (0.25 + 0.75 * t)
        v.co.z = base + up + wave
    bmesh.update_edit_mesh(o.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    md = o.modifiers.new("S", "SOLIDIFY"); md.thickness = max(0.1, rise * 0.16); md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(o, m); bpy.ops.object.shade_smooth(); bevel(o, 0.018, 2)

    extras = []
    n = 16
    for i in range(1, n):
        yy = -hw + size * (i / n)
        t = abs(yy) / hw
        e = max(0.0, (t - 0.45) / 0.55)
        zz = z0 + rise * (1.0 - 0.75 * t) + rise * curl * (e ** 1.35) + 0.05
        span = size * (0.94 - 0.12 * t)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.028, depth=span,
            location=(0, yy, zz), rotation=(0, math.pi/2, 0))
        c = bpy.context.active_object; setm(c, m); extras.append(c)
    # corner tips ON the upturned eave tips
    for sx, sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x, y = sx * hw * 0.92, sy * hw * 0.92
        t = 0.92; e = max(0.0, (t - 0.45) / 0.55)
        zz = z0 + rise * (1.0 - 0.75 * t) + rise * curl * (e ** 1.35) + 0.08
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.075, location=(x, y, zz), segments=14, ring_count=8)
        tip = bpy.context.active_object; setm(tip, MG); extras.append(tip)

    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    for e in extras: e.select_set(True)
    bpy.context.view_layer.objects.active = o; bpy.ops.object.join()
    return o

# Build with clearer vertical gaps so mid blue shows
box("Plinth", (0,0,0.12), 3.5, 3.5, 0.24, MS, 0.05)
box("Steps", (0,-1.9,0.1), 1.35, 0.48, 0.2, MS, 0.03)
box("Wall1", (0,0,0.9), 2.7, 2.7, 1.35, MW, 0.06)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P1{sx}{sy}", (sx*1.25, sy*1.25, 0.9), 0.22, 0.22, 1.4, MD, 0.04)
box("BF", (0,-1.25,1.45), 2.7, 0.16, 0.16, MD, 0.025)
box("BB", (0,1.25,1.45), 2.7, 0.16, 0.16, MD, 0.025)
box("Door", (0,-1.38,0.65), 0.6, 0.08, 0.95, MDoor, 0.02)

roof("Roof1", 1.65, 3.85, 0.7, MR, curl=1.05, segs=42)

# taller mid reveal
box("Wall2", (0,0,2.75), 1.95, 1.95, 1.15, MW, 0.05)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P2{sx}{sy}", (sx*0.9, sy*0.9, 2.75), 0.17, 0.17, 1.2, MD, 0.035)
box("B2", (0,-0.9,3.2), 1.95, 0.14, 0.14, MD, 0.02)

roof("Roof2", 3.4, 2.85, 0.65, MB, curl=1.15, segs=36)

box("Wall3", (0,0,4.25), 1.05, 1.05, 0.75, MW, 0.04)
for sx,sy in ((-1,-1),(-1,1),(1,-1),(1,1)):
    box(f"P3{sx}{sy}", (sx*0.48, sy*0.48, 4.25), 0.12, 0.12, 0.8, MD, 0.025)

roof("Roof3", 4.7, 1.7, 0.5, MR, curl=1.2, segs=28)

bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(0,0,5.35), segments=20, ring_count=12)
setm(bpy.context.active_object, MG)
bpy.ops.mesh.primitive_cone_add(radius1=0.1, depth=0.28, location=(0,0,5.55))
setm(bpy.context.active_object, MG)

for sx in (-1.2, 1.2):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.06, depth=0.12, location=(sx, -1.45, 1.85))
    setm(bpy.context.active_object, MG)

bpy.ops.mesh.primitive_plane_add(size=22, location=(0,0,0))
g = bpy.context.active_object; g.name = "GrassPlane"; setm(g, MGrass)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=3.2, depth=0.04, location=(0,0,0.02))
setm(bpy.context.active_object, MDirt)

# HIGH camera so all 3 roofs visible — look at mid building
bpy.ops.object.camera_add(location=(8.5, -9.5, 7.2), rotation=(math.radians(48), 0, math.radians(40)))
cam = bpy.context.active_object
cam.data.lens = 50
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = 13.5
cam.data.dof.aperture_fstop = 3.5
sc.camera = cam

bpy.ops.object.light_add(type="SUN", location=(6,-4,10))
sun = bpy.context.active_object
sun.data.energy = 5.2; sun.data.color = (1.0, 0.88, 0.58)
sun.rotation_euler = (math.radians(35), math.radians(10), math.radians(-25))
sun.data.angle = math.radians(4)

bpy.ops.object.light_add(type="AREA", location=(-4, 3, 4))
f = bpy.context.active_object; f.data.energy = 100; f.data.color = (0.5, 0.65, 1); f.data.size = 5

bpy.ops.object.light_add(type="AREA", location=(3, -5, 2.5))
r = bpy.context.active_object; r.data.energy = 55; r.data.color = (1.0, 0.5, 0.28); r.data.size = 2.5

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium High Contrast"
sc.view_settings.exposure = 0.18

try:
    p = bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type = "CUDA"
    for d in p.devices: d.use = True
except Exception:
    pass

for o in bpy.data.objects:
    if o.name.startswith("Roof"):
        print("ROOF", o.name, [m.name for m in o.data.materials], "z", round(o.location.z,2), "dim", [round(x,2) for x in o.dimensions])

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED_BLEND")
bpy.ops.render.render(write_still=True)
print("SAVED_PNG")
for o in sc.objects:
    o.select_set(o.type == "MESH" and o.name != "GrassPlane" and max(o.dimensions) < 12)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB"); print("DONE")
