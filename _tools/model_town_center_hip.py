# -*- coding: utf-8 -*-
"""Town Center — triangular HIPPED pitched roofs (clear slope to ridge), moderate eave tips."""
import bpy, bmesh, math, random
from mathutils import Vector

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 100
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1400
sc.render.resolution_y = 1100
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.52, 0.60, 0.70, 1); bg.inputs[1].default_value = 0.4
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(name, col, rough=0.42, coat=0.35, coat_r=0.22, metal=0.0, sss=0.1):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial"); b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = coat_r
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
    links.new(b.outputs[0], out.inputs[0]); return m

M_WALL=mat("Wall",(0.95,0.92,0.86),0.52,0.2,0.35,sss=0.14)
M_WOOD=mat("Wood",(0.14,0.07,0.035),0.58,0.12,0.4,sss=0.04)
M_BLUE=mat("Cobalt",(0.08,0.28,0.78),0.35,0.4,0.18,sss=0.08)
M_SKY=mat("Sky",(0.22,0.48,0.88),0.38,0.35,0.2,sss=0.08)
M_LAV=mat("Lav",(0.35,0.32,0.78),0.4,0.32,0.22,sss=0.08)
M_PINK=mat("Salmon",(0.90,0.36,0.40),0.35,0.38,0.18,sss=0.1)
M_GOLD=mat("Gold",(0.96,0.80,0.28),0.25,0.55,0.12,metal=0.55,sss=0.03)
M_STONE=mat("Stone",(0.76,0.66,0.52),0.68,0.08,0.45,sss=0.08)
M_DOOR=mat("Door",(0.88,0.1,0.08),0.38,0.3,0.22,sss=0.08)
M_BASE=mat("Base",(0.82,0.72,0.56),0.52,0.12,0.35,sss=0.1)
M_GRND=mat("Ground",(0.48,0.52,0.58),0.9,0.0,0.5,sss=0.0)

def setm(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
def sel(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
def bevel(o,w=0.045,s=4):
    sel(o); md=o.modifiers.new("B","BEVEL"); md.width=w; md.segments=s
    md.limit_method="ANGLE"; md.angle_limit=math.radians(22)
    bpy.ops.object.modifier_apply(modifier=md.name)
def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()
def box(name,loc,sx,sy,sz,m,bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.active_object; o.name=name; o.scale=(sx,sy,sz)
    bpy.ops.object.transform_apply(scale=True); setm(o,m); bevel(o,bw,5); return o
def cyl(name,loc,r,depth,m,verts=16,rot=(0,0,0),bw=0.012):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc,rotation=rot)
    o=bpy.context.active_object; o.name=name; setm(o,m); bevel(o,bw,3); smooth(o); return o
def sph(name,loc,r,m,seg=14):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=seg,ring_count=max(8,seg//2))
    o=bpy.context.active_object; o.name=name; setm(o,m); smooth(o); return o
def join(objs,name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join(); objs[0].name=name; return objs[0]

def hip_z(x, y, hx, hy, rise, tip=0.12):
    """True hipped roof: steep triangular pitch to ridge. Moderate corner tip only."""
    # normalize to unit square
    tx = abs(x) / max(hx, 1e-6)
    ty = abs(y) / max(hy, 1e-6)
    # classic hip: height falls with max(tx,ty) — creates triangular faces
    t = max(tx, ty)
    t = min(1.0, t)
    # steep slope: at center (t=0) z=rise, at eave (t=1) z ~ 0.08*rise
    z = rise * (1.0 - 0.88 * t)
    # moderate rounded corner tip (only when BOTH near edge)
    cx = max(0.0, (tx - 0.78) / 0.22)
    cy = max(0.0, (ty - 0.78) / 0.22)
    corner = cx * cy
    z += tip * (corner ** 0.85)
    return z

def make_hip_roof(name, z0, sx, sy, rise, tip=0.14, tile_r=0.08, n_along=14):
    """Hipped roof with clear triangular pitch + tubular tiles running DOWN the slope."""
    hx, hy = sx * 0.5, sy * 0.5
    segs = 40

    # Solid hip shell
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=1, location=(0,0,0))
    shell = bpy.context.active_object
    shell.name = name + "_shell"
    shell.scale = (sx * 1.02, sy * 1.02, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(shell.data)
    for v in bm.verts:
        v.co.z = hip_z(v.co.x, v.co.y, hx, hy, rise, tip)
    bmesh.update_edit_mesh(shell.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    shell.location.z = z0
    bpy.ops.object.transform_apply(location=True)

    md = shell.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.18; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    md = shell.modifiers.new("Sm", "SMOOTH")
    md.factor = 0.4; md.iterations = 2
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell, M_BLUE); smooth(shell); bevel(shell, 0.025, 3)
    parts = [shell]

    mats_tile = [M_BLUE, M_SKY, M_LAV, M_BLUE, M_SKY]

    # Tubular tiles: on FRONT and BACK faces — cylinders run along X (horizontal rows)
    # but placed following the slope so they read as tile courses going down the pitch
    n_rows = max(5, int(n_along * 0.55))
    for face_y in (-1, 1):
        for j in range(1, n_rows):
            # from near ridge (small |y|) toward eave
            ty = j / n_rows  # 0 near center-ish ... 1 at eave
            # on hip, front face is where |y| dominates: y from 0 to hy
            yy = face_y * hy * (0.12 + 0.82 * ty)
            # only where this is the front/back face (not side hip)
            # tile span shrinks toward corners via hip
            zz = z0 + hip_z(0, yy, hx, hy, rise, tip) + tile_r * 0.55
            # width of front face at this y: where |x|/hx < |y|/hy roughly
            # simple: span decreases as we go out
            span = sx * (0.9 - 0.35 * ty)
            m = mats_tile[j % len(mats_tile)]
            parts.append(cyl(f"{name}_tf{face_y}_{j}", (0, yy, zz), tile_r, span, m, 12, rot=(0, math.pi/2, 0)))

    # Side faces: tiles run along Y
    for face_x in (-1, 1):
        for j in range(1, n_rows):
            tx = j / n_rows
            xx = face_x * hx * (0.12 + 0.82 * tx)
            zz = z0 + hip_z(xx, 0, hx, hy, rise, tip) + tile_r * 0.55
            span = sy * (0.9 - 0.35 * tx)
            m = mats_tile[(j + 1) % len(mats_tile)]
            parts.append(cyl(f"{name}_ts{face_x}_{j}", (xx, 0, zz), tile_r * 0.95, span, m, 12, rot=(math.pi/2, 0, 0)))

    # Salmon ridge along X (main ridge if sx>=sy) and short Y ridge for hip peak look
    # For square-ish hip, cross ridges meet at peak
    z_peak = z0 + rise + 0.1
    # Longer ridge along the longer axis
    if sx >= sy:
        parts.append(cyl(f"{name}_ridgeX", (0, 0, z_peak), 0.1, sx * 0.22, M_PINK, 14, rot=(0, math.pi/2, 0)))
        parts.append(cyl(f"{name}_ridgeY", (0, 0, z_peak), 0.095, sy * 0.18, M_PINK, 14, rot=(math.pi/2, 0, 0)))
    else:
        parts.append(cyl(f"{name}_ridgeY", (0, 0, z_peak), 0.1, sy * 0.22, M_PINK, 14, rot=(math.pi/2, 0, 0)))
        parts.append(cyl(f"{name}_ridgeX", (0, 0, z_peak), 0.095, sx * 0.18, M_PINK, 14, rot=(0, math.pi/2, 0)))

    # Hip ridges: peak to each corner (salmon)
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x0, y0 = sx_ * hx * 0.05, sy_ * hy * 0.05
        x1, y1 = sx_ * hx * 0.92, sy_ * hy * 0.92
        z0h = z0 + hip_z(x0, y0, hx, hy, rise, tip) + 0.1
        z1h = z0 + hip_z(x1, y1, hx, hy, rise, tip) + 0.1
        d = Vector((x1 - x0, y1 - y0, z1h - z0h))
        mid = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0h + z1h) / 2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.09, depth=d.length, location=mid)
        hip = bpy.context.active_object
        hip.rotation_mode = "QUATERNION"
        hip.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
        setm(hip, M_PINK); smooth(hip)
        parts.append(hip)

    # Eave rim — follows pitched eave edge (low), continuous salmon
    curve = bpy.data.curves.new(name + "_rim", "CURVE")
    curve.dimensions = "3D"; curve.fill_mode = "FULL"
    curve.bevel_depth = 0.11; curve.bevel_resolution = 4; curve.resolution_u = 6
    sp = curve.splines.new("NURBS"); N = 48; samples = []
    for i in range(N):
        u = i / N; side = int(u * 4) % 4; f = (u * 4) % 1.0
        if side == 0: x, y = -hx + sx * f, -hy
        elif side == 1: x, y = hx, -hy + sy * f
        elif side == 2: x, y = hx - sx * f, hy
        else: x, y = -hx, hy - sy * f
        z = z0 + hip_z(x * 0.98, y * 0.98, hx, hy, rise, tip) + 0.07
        samples.append((x * 1.01, y * 1.01, z))
    sp.points.add(len(samples) - 1)
    for i, (x, y, z) in enumerate(samples):
        sp.points[i].co = (x, y, z, 1)
    sp.use_cyclic_u = True; sp.order_u = 4
    eave = bpy.data.objects.new(name + "_eave", curve)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave = bpy.context.active_object
    setm(eave, M_PINK); smooth(eave); bevel(eave, 0.015, 2)
    parts.append(eave)

    # Moderate bulbous corner tips (salmon) — NOT huge temple curls
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx_ * hx * 0.96, sy_ * hy * 0.96
        z = z0 + hip_z(sx_ * hx * 0.9, sy_ * hy * 0.9, hx, hy, rise, tip) + 0.12 + tip * 0.6
        tip_s = sph(f"{name}_tip", (x, y, z), 0.13, M_PINK, 14)
        tip_s.scale = (1.25, 1.25, 0.9)
        bpy.ops.object.transform_apply(scale=True)
        parts.append(tip_s)
        parts.append(sph(f"{name}_tg", (x, y, z + 0.08), 0.05, M_GOLD, 10))

    return join(parts, name)

def pillar(name, x, y, z0, h):
    base = sph(f"{name}_b", (x, y, z0 + 0.09), 0.15, M_BASE, 12)
    base.scale = (1.2, 1.2, 0.55); bpy.ops.object.transform_apply(scale=True)
    post = cyl(f"{name}_p", (x, y, z0 + h * 0.5 + 0.08), 0.08, h, M_WOOD, 14)
    extras = [base, post]
    for k in range(4):
        ang = k * math.pi / 2
        extras.append(cyl(f"{name}_g{k}", (x + math.cos(ang) * 0.072, y + math.sin(ang) * 0.072, z0 + h * 0.5 + 0.08), 0.01, h * 0.85, M_WOOD, 8, bw=0.003))
    return join(extras, name)

def door(name, x, y, z):
    d = box(f"{name}_d", (x, y, z + 0.28), 0.38, 0.06, 0.55, M_DOOR, 0.035)
    a = sph(f"{name}_a", (x, y, z + 0.58), 0.19, M_DOOR, 12)
    a.scale = (1.05, 0.28, 0.48); bpy.ops.object.transform_apply(scale=True)
    steps = [box(f"{name}_s{i}", (x, y - 0.18 - i * 0.08, 0.03 + i * 0.05), 0.45 - i * 0.06, 0.15, 0.055, M_STONE, 0.02) for i in range(3)]
    return join([d, a] + steps, name)

def foundation():
    rng = random.Random(9)
    pad = cyl("Pad", (0, 0, 0.045), 2.85, 0.1, M_STONE, 48)
    pebs = [pad]
    for i in range(50):
        ang = rng.random() * math.tau; rr = 2.0 + rng.random() * 1.0; s = 0.1 + rng.random() * 0.16
        p = sph(f"Pe{i}", (math.cos(ang) * rr, math.sin(ang) * rr, 0.06), s, M_STONE, 10)
        p.scale = (0.9 + rng.random() * 0.4, 0.9 + rng.random() * 0.4, 0.4 + rng.random() * 0.35)
        bpy.ops.object.transform_apply(scale=True); pebs.append(p)
    return join(pebs, "Foundation")

# ===== BUILD =====
foundation()
box("Center", (0, 0, 0.72), 2.5, 2.15, 1.1, M_WALL, 0.06)
box("WingL", (-2.6, 0.0, 0.5), 2.4, 1.9, 0.72, M_WALL, 0.055)
box("WingR", (2.6, 0.0, 0.5), 2.4, 1.9, 0.72, M_WALL, 0.055)
box("LintC", (0, -1.12, 1.2), 2.5, 0.12, 0.12, M_WOOD, 0.025)
box("LintL", (-2.6, -0.98, 0.82), 2.4, 0.1, 0.1, M_WOOD, 0.02)
box("LintR", (2.6, -0.98, 0.82), 2.4, 0.1, 0.1, M_WOOD, 0.02)
for sx in (-1.1, 1.1):
    for sy in (-1.0, 1.0):
        pillar(f"PC{sx}{sy}", sx, sy, 0.1, 1.1)
for wx in (-3.5, -1.75, 1.75, 3.5):
    for sy in (-0.85, 0.85):
        pillar(f"PW{wx}{sy}", wx, sy, 0.08, 0.82)
door("DC", 0, -1.12, 0.14); door("DL", -2.6, -0.98, 0.1); door("DR", 2.6, -0.98, 0.1)

# HIPPED pitched roofs — clear triangular slope (rise is significant vs footprint)
make_hip_roof("Roof1", 1.3, 7.6, 3.8, rise=0.85, tip=0.16, tile_r=0.085, n_along=16)

box("Mid", (0, 0, 2.55), 1.85, 1.65, 0.8, M_WALL, 0.05)
for sx, sy in ((-0.78, -0.68), (-0.78, 0.68), (0.78, -0.68), (0.78, 0.68)):
    pillar(f"PM{sx}{sy}", sx, sy, 2.15, 0.8)
box("WinL", (-0.48, -0.85, 2.55), 0.22, 0.04, 0.26, M_WOOD, 0.015)
box("WinR", (0.48, -0.85, 2.55), 0.22, 0.04, 0.26, M_WOOD, 0.015)

make_hip_roof("Roof2", 3.05, 3.05, 2.7, rise=0.7, tip=0.14, tile_r=0.07, n_along=12)

box("Top", (0, 0, 4.05), 1.1, 1.0, 0.6, M_WALL, 0.04)
for sx, sy in ((-0.45, -0.4), (-0.45, 0.4), (0.45, -0.4), (0.45, 0.4)):
    pillar(f"PT{sx}{sy}", sx, sy, 3.75, 0.6)

make_hip_roof("Roof3", 4.45, 1.8, 1.6, rise=0.55, tip=0.12, tile_r=0.055, n_along=8)

sph("Fin", (0, 0, 5.15), 0.15, M_GOLD, 18)
cyl("FinStem", (0, 0, 4.98), 0.04, 0.14, M_GOLD, 10, bw=0.006)
sph("Fin2", (0, 0, 5.28), 0.08, M_GOLD, 14)
sph("FinL", (-2.6, 0, 2.25), 0.09, M_GOLD, 12)
sph("FinR", (2.6, 0, 2.25), 0.09, M_GOLD, 12)

bpy.ops.mesh.primitive_plane_add(size=28, location=(0, 0, 0))
gp = bpy.context.active_object; gp.name = "Ground"; setm(gp, M_GRND)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 2.4))
tgt = bpy.context.active_object
# Slightly low 3/4 to show triangular pitch clearly
bpy.ops.object.camera_add(location=(9.0, -10.2, 4.5))
cam = bpy.context.active_object
cam.data.lens = 55
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
cam.data.dof.aperture_fstop = 2.8
c = cam.constraints.new("TRACK_TO"); c.target = tgt
c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="AREA", location=(5.5, -3.5, 6.5))
key = bpy.context.active_object
key.data.energy = 380; key.data.color = (1.0, 0.92, 0.8); key.data.size = 5.5
bpy.ops.object.light_add(type="AREA", location=(-5, 2.5, 3.5))
fill = bpy.context.active_object
fill.data.energy = 130; fill.data.color = (0.65, 0.75, 1.0); fill.data.size = 5
bpy.ops.object.light_add(type="SUN", location=(3, -2, 8))
sun = bpy.context.active_object
sun.data.energy = 1.4; sun.data.color = (1.0, 0.95, 0.88)
sun.rotation_euler = (math.radians(40), math.radians(5), math.radians(-20))
sun.data.angle = math.radians(8)

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium Contrast"
sc.view_settings.exposure = 0.28

try:
    p = bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type = "CUDA"
    for d in p.devices: d.use = True
except Exception:
    pass

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND); print("SAVED_BLEND")
bpy.ops.render.render(write_still=True); print("SAVED_PNG")
for o in sc.objects:
    o.select_set(o.type == "MESH" and o.name != "Ground" and max(o.dimensions) < 28)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB"); print("DONE")
