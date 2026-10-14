# -*- coding: utf-8 -*-
"""Town Center — STEEP triangular hip roofs (clear A-frame pitch to ridge)."""
import bpy, bmesh, math, random
from mathutils import Vector

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 96
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1400
sc.render.resolution_y = 1200
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.5, 0.58, 0.68, 1); bg.inputs[1].default_value = 0.42
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(name, col, rough=0.4, coat=0.38, coat_r=0.2, metal=0.0, sss=0.1):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial"); b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat; b.inputs["Coat Roughness"].default_value = coat_r
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
    links.new(b.outputs[0], out.inputs[0]); return m

M_WALL=mat("Wall",(0.95,0.92,0.86),0.5,0.2,0.35,sss=0.14)
M_WOOD=mat("Wood",(0.14,0.07,0.035),0.58,0.12,0.4,sss=0.04)
M_BLUE=mat("Cobalt",(0.07,0.26,0.76),0.32,0.42,0.16,sss=0.08)
M_SKY=mat("Sky",(0.2,0.5,0.9),0.35,0.38,0.18,sss=0.08)
M_LAV=mat("Lav",(0.38,0.3,0.8),0.38,0.35,0.2,sss=0.08)
M_PINK=mat("Salmon",(0.9,0.34,0.38),0.32,0.4,0.16,sss=0.1)
M_GOLD=mat("Gold",(0.96,0.8,0.28),0.24,0.55,0.12,metal=0.55,sss=0.03)
M_STONE=mat("Stone",(0.76,0.66,0.52),0.68,0.08,0.45,sss=0.08)
M_DOOR=mat("Door",(0.88,0.1,0.08),0.38,0.3,0.22,sss=0.08)
M_BASE=mat("Base",(0.82,0.72,0.56),0.52,0.12,0.35,sss=0.1)
M_GRND=mat("Ground",(0.48,0.52,0.58),0.9,0.0,0.5,sss=0.0)

def setm(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
def sel(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
def bevel(o,w=0.04,s=4):
    sel(o); md=o.modifiers.new("B","BEVEL"); md.width=w; md.segments=s
    md.limit_method="ANGLE"; md.angle_limit=math.radians(22)
    bpy.ops.object.modifier_apply(modifier=md.name)
def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()
def box(name,loc,sx,sy,sz,m,bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.active_object; o.name=name; o.scale=(sx,sy,sz)
    bpy.ops.object.transform_apply(scale=True); setm(o,m); bevel(o,bw,5); return o
def cyl(name,loc,r,depth,m,verts=14,rot=(0,0,0),bw=0.01):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc,rotation=rot)
    o=bpy.context.active_object; o.name=name; setm(o,m); bevel(o,bw,2); smooth(o); return o
def sph(name,loc,r,m,seg=14):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=seg,ring_count=max(8,seg//2))
    o=bpy.context.active_object; o.name=name; setm(o,m); smooth(o); return o
def join(objs,name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join(); objs[0].name=name; return objs[0]

def hip_z(x, y, hx, hy, rise, tip=0.1):
    """Steep hip: clear triangular faces to peak."""
    tx = abs(x) / max(hx, 1e-6)
    ty = abs(y) / max(hy, 1e-6)
    t = min(1.0, max(tx, ty))
    z = rise * (1.0 - 0.92 * t)  # eave nearly at base of roof volume
    cx = max(0.0, (tx - 0.8) / 0.2)
    cy = max(0.0, (ty - 0.8) / 0.2)
    z += tip * (cx * cy) ** 0.9
    return max(0.0, z)

def orient_cyl(obj, direction):
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.normalized().to_track_quat("Z", "Y")

def make_hip_roof(name, z0, sx, sy, rise, tip=0.12, tile_r=0.075, n_tiles=11):
    hx, hy = sx * 0.5, sy * 0.5
    segs = 36
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=1, location=(0,0,0))
    shell = bpy.context.active_object
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
    md = shell.modifiers.new("Sol", "SOLIDIFY"); md.thickness = 0.16; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell, M_BLUE); smooth(shell); bevel(shell, 0.02, 2)
    parts = [shell]
    mats = [M_BLUE, M_SKY, M_LAV, M_BLUE, M_SKY]

    # Tiles DOWN the slope on front/back: cylinders oriented along slope (Y-Z diagonal)
    # Use many short tubes along X rows, but each row at decreasing height — visual pitch courses
    # Better: on each face, place cylinders that run from ridge toward eave (downslope direction)
    n_across = n_tiles
    n_down = max(4, n_tiles // 2)

    # FRONT (+/- Y faces): tiles run downslope (mixed Y and -Z), arrayed across X
    for face in (-1, 1):
        for i in range(n_across):
            u = (i + 0.5) / n_across
            xx = -hx * 0.85 + sx * 0.85 * u
            # only on front face region: |x| < something related to face
            # skip near side hips
            if abs(xx) > hx * 0.82:
                continue
            # tile from near ridge to eave along Y
            y0 = face * hy * 0.08
            y1 = face * hy * 0.9
            z0t = z0 + hip_z(xx, y0, hx, hy, rise, tip) + tile_r * 0.5
            z1t = z0 + hip_z(xx, y1, hx, hy, rise, tip) + tile_r * 0.5
            d = Vector((0, y1 - y0, z1t - z0t))
            mid = Vector((xx, (y0 + y1) / 2, (z0t + z1t) / 2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r, depth=d.length * 0.95, location=mid)
            t = bpy.context.active_object
            orient_cyl(t, d)
            setm(t, mats[i % len(mats)]); smooth(t)
            parts.append(t)

    # SIDE (+/- X faces): tiles run downslope along X
    for face in (-1, 1):
        for i in range(max(4, n_across // 2)):
            u = (i + 0.5) / max(4, n_across // 2)
            yy = -hy * 0.7 + sy * 0.7 * u
            if abs(yy) > hy * 0.75:
                continue
            x0 = face * hx * 0.08
            x1 = face * hx * 0.9
            z0t = z0 + hip_z(x0, yy, hx, hy, rise, tip) + tile_r * 0.5
            z1t = z0 + hip_z(x1, yy, hx, hy, rise, tip) + tile_r * 0.5
            d = Vector((x1 - x0, 0, z1t - z0t))
            mid = Vector(((x0 + x1) / 2, yy, (z0t + z1t) / 2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r * 0.92, depth=d.length * 0.95, location=mid)
            t = bpy.context.active_object
            orient_cyl(t, d)
            setm(t, mats[(i + 2) % len(mats)]); smooth(t)
            parts.append(t)

    # Peak cross ridges (salmon)
    z_peak = z0 + rise + 0.08
    parts.append(cyl(f"{name}_rx", (0, 0, z_peak), 0.1, max(sx, sy) * 0.18, M_PINK, 12, rot=(0, math.pi/2, 0)))
    parts.append(cyl(f"{name}_ry", (0, 0, z_peak), 0.095, min(sx, sy) * 0.16, M_PINK, 12, rot=(math.pi/2, 0, 0)))

    # Hip ridges peak→corner
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x0, y0 = sx_ * hx * 0.04, sy_ * hy * 0.04
        x1, y1 = sx_ * hx * 0.9, sy_ * hy * 0.9
        za = z0 + hip_z(x0, y0, hx, hy, rise, tip) + 0.09
        zb = z0 + hip_z(x1, y1, hx, hy, rise, tip) + 0.09
        d = Vector((x1 - x0, y1 - y0, zb - za))
        mid = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (za + zb) / 2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.085, depth=d.length, location=mid)
        hip = bpy.context.active_object
        orient_cyl(hip, d); setm(hip, M_PINK); smooth(hip)
        parts.append(hip)

    # Eave rim at low eave height
    curve = bpy.data.curves.new(name + "_rim", "CURVE")
    curve.dimensions = "3D"; curve.fill_mode = "FULL"
    curve.bevel_depth = 0.1; curve.bevel_resolution = 4; curve.resolution_u = 5
    sp = curve.splines.new("NURBS"); N = 40; samples = []
    for i in range(N):
        u = i / N; side = int(u * 4) % 4; f = (u * 4) % 1.0
        if side == 0: x, y = -hx + sx * f, -hy
        elif side == 1: x, y = hx, -hy + sy * f
        elif side == 2: x, y = hx - sx * f, hy
        else: x, y = -hx, hy - sy * f
        z = z0 + hip_z(x * 0.98, y * 0.98, hx, hy, rise, tip) + 0.06
        samples.append((x * 1.01, y * 1.01, z))
    sp.points.add(len(samples) - 1)
    for i, (x, y, z) in enumerate(samples):
        sp.points[i].co = (x, y, z, 1)
    sp.use_cyclic_u = True; sp.order_u = 4
    eave = bpy.data.objects.new(name + "_eave", curve)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave = bpy.context.active_object
    setm(eave, M_PINK); smooth(eave)
    parts.append(eave)

    # Moderate corner tips
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx_ * hx * 0.95, sy_ * hy * 0.95
        z = z0 + hip_z(sx_ * hx * 0.88, sy_ * hy * 0.88, hx, hy, rise, tip) + 0.1 + tip * 0.5
        tip_o = sph(f"{name}_tip", (x, y, z), 0.12, M_PINK, 12)
        tip_o.scale = (1.2, 1.2, 0.9); bpy.ops.object.transform_apply(scale=True)
        parts.append(tip_o)
        parts.append(sph(f"{name}_g", (x, y, z + 0.07), 0.045, M_GOLD, 10))

    return join(parts, name)

def pillar(name, x, y, z0, h):
    base = sph(f"{name}_b", (x, y, z0 + 0.08), 0.14, M_BASE, 12)
    base.scale = (1.2, 1.2, 0.55); bpy.ops.object.transform_apply(scale=True)
    post = cyl(f"{name}_p", (x, y, z0 + h * 0.5 + 0.07), 0.078, h, M_WOOD, 14)
    return join([base, post], name)

def door(name, x, y, z):
    d = box(f"{name}_d", (x, y, z + 0.26), 0.36, 0.06, 0.52, M_DOOR, 0.03)
    a = sph(f"{name}_a", (x, y, z + 0.54), 0.18, M_DOOR, 12)
    a.scale = (1.05, 0.28, 0.48); bpy.ops.object.transform_apply(scale=True)
    steps = [box(f"{name}_s{i}", (x, y - 0.16 - i * 0.07, 0.025 + i * 0.045), 0.42 - i * 0.05, 0.14, 0.05, M_STONE, 0.02) for i in range(3)]
    return join([d, a] + steps, name)

def foundation():
    rng = random.Random(11)
    pad = cyl("Pad", (0, 0, 0.04), 2.8, 0.09, M_STONE, 48)
    pebs = [pad]
    for i in range(45):
        ang = rng.random() * math.tau; rr = 2.0 + rng.random() * 0.95; s = 0.1 + rng.random() * 0.15
        p = sph(f"Pe{i}", (math.cos(ang) * rr, math.sin(ang) * rr, 0.05), s, M_STONE, 10)
        p.scale = (0.9 + rng.random() * 0.4, 0.9 + rng.random() * 0.4, 0.4 + rng.random() * 0.3)
        bpy.ops.object.transform_apply(scale=True); pebs.append(p)
    return join(pebs, "Foundation")

foundation()
box("Center", (0, 0, 0.7), 2.4, 2.1, 1.05, M_WALL, 0.055)
box("WingL", (-2.5, 0, 0.48), 2.3, 1.85, 0.7, M_WALL, 0.05)
box("WingR", (2.5, 0, 0.48), 2.3, 1.85, 0.7, M_WALL, 0.05)
box("LintC", (0, -1.1, 1.15), 2.4, 0.11, 0.11, M_WOOD, 0.02)
for sx in (-1.05, 1.05):
    for sy in (-0.95, 0.95):
        pillar(f"PC{sx}{sy}", sx, sy, 0.08, 1.05)
for wx in (-3.35, -1.7, 1.7, 3.35):
    for sy in (-0.8, 0.8):
        pillar(f"PW{wx}{sy}", wx, sy, 0.06, 0.78)
door("DC", 0, -1.1, 0.12); door("DL", -2.5, -0.95, 0.08); door("DR", 2.5, -0.95, 0.08)

# STEEP hips: rise ≈ 0.75 * half_depth for ~37° pitch
# Roof1: hy=1.85 → rise ~1.4
make_hip_roof("Roof1", 1.25, 7.4, 3.7, rise=1.45, tip=0.14, tile_r=0.08, n_tiles=13)
print("Roof1 pitch_deg~", round(math.degrees(math.atan(1.45 * 0.92 / 1.85)), 1))

box("Mid", (0, 0, 3.15), 1.8, 1.6, 0.75, M_WALL, 0.045)
for sx, sy in ((-0.75, -0.65), (-0.75, 0.65), (0.75, -0.65), (0.75, 0.65)):
    pillar(f"PM{sx}{sy}", sx, sy, 2.75, 0.75)
box("WinL", (-0.45, -0.82, 3.15), 0.2, 0.04, 0.24, M_WOOD, 0.015)
box("WinR", (0.45, -0.82, 3.15), 0.2, 0.04, 0.24, M_WOOD, 0.015)

make_hip_roof("Roof2", 3.6, 2.95, 2.6, rise=1.05, tip=0.12, tile_r=0.065, n_tiles=9)
print("Roof2 pitch_deg~", round(math.degrees(math.atan(1.05 * 0.92 / 1.3)), 1))

box("Top", (0, 0, 5.0), 1.05, 0.95, 0.55, M_WALL, 0.035)
for sx, sy in ((-0.42, -0.38), (-0.42, 0.38), (0.42, -0.38), (0.42, 0.38)):
    pillar(f"PT{sx}{sy}", sx, sy, 4.7, 0.55)

make_hip_roof("Roof3", 5.35, 1.7, 1.5, rise=0.75, tip=0.1, tile_r=0.05, n_tiles=6)

sph("Fin", (0, 0, 6.25), 0.14, M_GOLD, 16)
cyl("FinStem", (0, 0, 6.1), 0.035, 0.12, M_GOLD, 10, bw=0.005)
sph("Fin2", (0, 0, 6.36), 0.075, M_GOLD, 12)

bpy.ops.mesh.primitive_plane_add(size=28, location=(0, 0, 0))
gp = bpy.context.active_object; gp.name = "Ground"; setm(gp, M_GRND)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 3.0))
tgt = bpy.context.active_object
# Lower camera to emphasize triangular silhouette
bpy.ops.object.camera_add(location=(10.5, -11.5, 4.2))
cam = bpy.context.active_object
cam.data.lens = 50
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
cam.data.dof.aperture_fstop = 2.8
c = cam.constraints.new("TRACK_TO"); c.target = tgt
c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="AREA", location=(6, -4, 7))
key = bpy.context.active_object
key.data.energy = 400; key.data.color = (1.0, 0.92, 0.8); key.data.size = 5.5
bpy.ops.object.light_add(type="AREA", location=(-5, 3, 4))
fill = bpy.context.active_object
fill.data.energy = 140; fill.data.color = (0.65, 0.75, 1.0); fill.data.size = 5
bpy.ops.object.light_add(type="SUN", location=(4, -2, 9))
sun = bpy.context.active_object
sun.data.energy = 1.5; sun.data.color = (1.0, 0.95, 0.88)
sun.rotation_euler = (math.radians(38), math.radians(8), math.radians(-22))
sun.data.angle = math.radians(7)

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium Contrast"
sc.view_settings.exposure = 0.3

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
