# -*- coding: utf-8 -*-
"""Town Center v2 — continuous clay roofs (solid cobalt deck + continuous salmon eave solids)."""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 110
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1400
sc.render.resolution_y = 1100
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.58, 0.64, 0.72, 1)
bg.inputs[1].default_value = 0.4
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])


def mat(name, col, rough=0.48, coat=0.28, coat_r=0.3, metal=0.0, sss=0.12):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = coat_r
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.35
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
    links.new(b.outputs[0], out.inputs[0])
    return m

M_WALL  = mat("Wall", (0.94, 0.91, 0.85), 0.58, 0.18, 0.4, sss=0.15)
M_WOOD  = mat("Wood", (0.18, 0.09, 0.05), 0.62, 0.12, 0.45, sss=0.05)
M_BLUE  = mat("Cobalt", (0.10, 0.30, 0.78), 0.45, 0.32, 0.25, sss=0.1)
M_PINK  = mat("Salmon", (0.90, 0.36, 0.40), 0.4, 0.3, 0.22, sss=0.12)
M_GOLD  = mat("Gold", (0.95, 0.78, 0.25), 0.3, 0.5, 0.18, metal=0.5, sss=0.05)
M_STONE = mat("Stone", (0.74, 0.64, 0.50), 0.72, 0.08, 0.5, sss=0.08)
M_DOOR  = mat("Door", (0.88, 0.10, 0.08), 0.42, 0.3, 0.25, sss=0.08)
M_BASE  = mat("Base", (0.80, 0.70, 0.55), 0.58, 0.12, 0.4, sss=0.1)
M_GRND  = mat("Ground", (0.52, 0.55, 0.60), 0.9, 0.0, 0.5, sss=0.0)


def setm(o, m):
    o.data.materials.clear(); o.data.materials.append(m)

def select_only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o

def bevel(o, width=0.05, seg=4):
    select_only(o)
    md = o.modifiers.new("Bev", "BEVEL")
    md.width = width; md.segments = seg
    md.limit_method = "ANGLE"; md.angle_limit = math.radians(22)
    bpy.ops.object.modifier_apply(modifier=md.name)

def smooth(o):
    select_only(o)
    bpy.ops.object.shade_smooth()

def box(name, loc, sx, sy, sz, m, bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = (sx, sy, sz); bpy.ops.object.transform_apply(scale=True)
    setm(o, m); bevel(o, bw, 5); return o

def cyl(name, loc, r, depth, m, verts=24, rot=(0,0,0), bw=0.02):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name
    setm(o, m); bevel(o, bw, 3); smooth(o); return o

def sph(name, loc, r, m, seg=18):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=max(8, seg//2))
    o = bpy.context.active_object; o.name = name
    setm(o, m); smooth(o); return o

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def roof_height(x, y, hx, hy, z0, rise, curl):
    tx = abs(x) / max(hx, 1e-6)
    ty = abs(y) / max(hy, 1e-6)
    t = min(1.0, max(tx, ty))
    # round the corners a bit for organic hip
    tr = math.sqrt(min(1.0, (tx*tx + ty*ty) * 0.5))
    t = 0.7 * t + 0.3 * tr
    if t < 0.62:
        u = t / 0.62
        return z0 + rise * (1.0 - 0.82 * u)
    u = (t - 0.62) / 0.38
    return z0 + rise * 0.18 + curl * (u ** 1.05)


def make_roof(name, z0, sx, sy, rise, curl, n_tiles=10):
    """Continuous blue solid roof + continuous salmon eave rim + embedded tile rolls."""
    hx, hy = sx * 0.5, sy * 0.5
    segs = 48

    # BLUE shell
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=1, location=(0,0,0))
    shell = bpy.context.active_object
    shell.name = name + "_shell"
    shell.scale = (sx, sy, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(shell.data)
    for v in bm.verts:
        v.co.z = roof_height(v.co.x, v.co.y, hx, hy, 0, rise, curl)
    bmesh.update_edit_mesh(shell.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    shell.location.z = z0
    bpy.ops.object.transform_apply(location=True)

    md = shell.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.16; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    # mild smooth
    md = shell.modifiers.new("Sm", "SMOOTH")
    md.factor = 0.6; md.iterations = 4
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell, M_BLUE); smooth(shell); bevel(shell, 0.025, 3)

    parts = [shell]

    # Embedded tile rolls (fewer, thicker, flush — clay cylinders)
    for j in range(1, n_tiles):
        yy = -hy + sy * (j / n_tiles)
        t = abs(yy) / hy
        if t > 0.82:
            continue
        zz = roof_height(0, yy, hx, hy, z0, rise, curl) + 0.045
        span = sx * (0.78 - 0.15 * t)
        tbar = cyl(f"{name}_t{j}", (0, yy, zz), 0.07, span, M_BLUE, 16, rot=(0, math.pi/2, 0), bw=0.015)
        parts.append(tbar)

    # CONTINUOUS salmon eave rim: curve path around perimeter, bevel it
    # Build poly curve following roof edge with upsweep
    curve_data = bpy.data.curves.new(name + "_eave_crv", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.fill_mode = "FULL"
    curve_data.bevel_depth = 0.11
    curve_data.bevel_resolution = 4
    curve_data.resolution_u = 8
    spline = curve_data.splines.new("NURBS")
    # sample perimeter
    samples = []
    N = 64
    for i in range(N):
        u = i / N
        # rounded rectangle perimeter
        # map u to rectangle with rounded corners
        # 4 sides
        side = int(u * 4) % 4
        f = (u * 4) % 1.0
        # push corners outward slightly for sweep silhouette
        if side == 0:
            x = -hx + sx * f; y = -hy
        elif side == 1:
            x = hx; y = -hy + sy * f
        elif side == 2:
            x = hx - sx * f; y = hy
        else:
            x = -hx; y = hy - sy * f
        # corner boost: near corners move out a bit and up more
        tx, ty = abs(x)/hx, abs(y)/hy
        corner = max(0.0, (tx + ty) - 1.15)  # near corners both large
        # better: distance to nearest corner
        cd = min(
            math.hypot(x - (-hx), y - (-hy)),
            math.hypot(x - (-hx), y - hy),
            math.hypot(x - hx, y - (-hy)),
            math.hypot(x - hx, y - hy),
        )
        near_c = max(0.0, 1.0 - cd / (min(hx, hy) * 0.55))
        # outward flare
        x *= 1.0 + 0.06 * near_c
        y *= 1.0 + 0.06 * near_c
        z = roof_height(x * 0.98, y * 0.98, hx, hy, z0, rise, curl) + 0.08 + 0.12 * (near_c ** 1.2)
        samples.append((x, y, z))

    spline.points.add(len(samples) - 1)
    for i, (x, y, z) in enumerate(samples):
        spline.points[i].co = (x, y, z, 1)
    spline.use_cyclic_u = True
    spline.order_u = 4

    eave_obj = bpy.data.objects.new(name + "_eave", curve_data)
    bpy.context.collection.objects.link(eave_obj)
    # convert curve to mesh
    select_only(eave_obj)
    bpy.ops.object.convert(target="MESH")
    eave_mesh = bpy.context.active_object
    setm(eave_mesh, M_PINK)
    smooth(eave_mesh)
    bevel(eave_mesh, 0.02, 2)
    parts.append(eave_mesh)

    # Hip ridges (salmon) — continuous cylinders center→corners
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x0, y0 = sx_ * hx * 0.08, sy_ * hy * 0.08
        x1, y1 = sx_ * hx * 0.93, sy_ * hy * 0.93
        z0h = roof_height(x0, y0, hx, hy, z0, rise, curl) + 0.09
        z1h = roof_height(x1, y1, hx, hy, z0, rise, curl) + 0.1
        mx, my, mz = (x0+x1)/2, (y0+y1)/2, (z0h+z1h)/2
        d = Vector((x1-x0, y1-y0, z1h-z0h))
        length = d.length
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.085, depth=length, location=(mx, my, mz))
        hip = bpy.context.active_object
        hip.rotation_mode = "QUATERNION"
        hip.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
        setm(hip, M_PINK); smooth(hip)
        parts.append(hip)

    # Center ridge
    zc = z0 + rise + 0.1
    ridge = cyl(f"{name}_ridge", (0, 0, zc), 0.1, min(sx, sy) * 0.35, M_PINK, 16, rot=(0, math.pi/2, 0), bw=0.02)
    parts.append(ridge)

    # Blunt swept eave tips (large salmon blobs + gold)
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx_ * hx * 1.02, sy_ * hy * 1.02
        z = roof_height(sx_ * hx * 0.95, sy_ * hy * 0.95, hx, hy, z0, rise, curl) + 0.18
        tip = sph(f"{name}_tip", (x, y, z), 0.16, M_PINK, 18)
        tip.scale = (1.4, 1.4, 0.9)
        bpy.ops.object.transform_apply(scale=True)
        g = sph(f"{name}_tg", (x, y, z + 0.12), 0.07, M_GOLD, 14)
        parts.append(tip); parts.append(g)

    return join(parts, name)


def pillar(name, x, y, z0, h):
    base = sph(f"{name}_b", (x, y, z0 + 0.1), 0.17, M_BASE, 14)
    base.scale = (1.2, 1.2, 0.65); bpy.ops.object.transform_apply(scale=True)
    post = cyl(f"{name}_p", (x, y, z0 + h*0.5 + 0.12), 0.085, h, M_WOOD, 18, bw=0.02)
    # grooves
    extras = [base, post]
    for k in range(4):
        ang = k * math.pi / 2
        gx = x + math.cos(ang) * 0.08
        gy = y + math.sin(ang) * 0.08
        extras.append(cyl(f"{name}_g{k}", (gx, gy, z0 + h*0.5 + 0.12), 0.012, h*0.9, M_WOOD, 8, bw=0.005))
    return join(extras, name)


def door(name, x, y, z):
    d = box(f"{name}_d", (x, y, z+0.32), 0.42, 0.07, 0.65, M_DOOR, 0.04)
    a = sph(f"{name}_a", (x, y, z+0.68), 0.22, M_DOOR, 14)
    a.scale = (1.05, 0.32, 0.5); bpy.ops.object.transform_apply(scale=True)
    steps = []
    for i in range(3):
        steps.append(box(f"{name}_s{i}", (x, y - 0.22 - i*0.1, 0.04 + i*0.06), 0.5 - i*0.08, 0.18, 0.07, M_STONE, 0.03))
    return join([d, a] + steps, name)


def foundation():
    rng = random.Random(7)
    pad = cyl("Pad", (0, 0, 0.06), 3.0, 0.14, M_STONE, 48, bw=0.03)
    pebs = [pad]
    for i in range(70):
        ang = rng.random() * math.tau
        rr = 2.2 + rng.random() * 1.1
        px, py = math.cos(ang)*rr, math.sin(ang)*rr
        s = 0.1 + rng.random()*0.2
        p = sph(f"Pe{i}", (px, py, 0.08), s, M_STONE, 10)
        p.scale = (0.9+rng.random()*0.5, 0.9+rng.random()*0.5, 0.45+rng.random()*0.4)
        bpy.ops.object.transform_apply(scale=True)
        pebs.append(p)
    for i in range(25):
        px, py = rng.uniform(-1.8, 1.8), rng.uniform(-1.5, 1.5)
        p = sph(f"Pi{i}", (px, py, 0.07), 0.1+rng.random()*0.15, M_STONE, 8)
        pebs.append(p)
    return join(pebs, "Foundation")


# ===== ASSEMBLE =====
foundation()

# Walls: center + wings
box("Center", (0, 0, 0.8), 2.3, 2.0, 1.25, M_WALL, 0.06)
box("WingL", (-2.4, 0.05, 0.52), 2.1, 1.7, 0.8, M_WALL, 0.055)
box("WingR", (2.4, 0.05, 0.52), 2.1, 1.7, 0.8, M_WALL, 0.055)

# Wood lintels
box("LintC", (0, -1.05, 1.35), 2.3, 0.13, 0.13, M_WOOD, 0.025)
box("LintL", (-2.4, -0.9, 0.9), 2.1, 0.11, 0.11, M_WOOD, 0.02)
box("LintR", (2.4, -0.9, 0.9), 2.1, 0.11, 0.11, M_WOOD, 0.02)

# Pillars
for sx in (-1.0, 1.0):
    for sy in (-0.95, 0.95):
        pillar(f"PC{sx}{sy}", sx, sy, 0.12, 1.25)
for wx in (-3.2, -1.6, 1.6, 3.2):
    for sy in (-0.75, 0.75):
        pillar(f"PW{wx}{sy}", wx, sy, 0.1, 0.9)

door("DC", 0, -1.05, 0.18)
door("DL", -2.4, -0.9, 0.12)
door("DR", 2.4, -0.9, 0.12)

# Roofs — blue tiles + salmon eaves
make_roof("Roof1", 1.45, 7.2, 3.5, rise=0.5, curl=0.85, n_tiles=11)

box("Mid", (0, 0, 2.5), 1.65, 1.5, 0.9, M_WALL, 0.05)
for sx, sy in ((-0.7,-0.6),(-0.7,0.6),(0.7,-0.6),(0.7,0.6)):
    pillar(f"PM{sx}{sy}", sx, sy, 2.05, 0.9)

make_roof("Roof2", 3.05, 2.95, 2.65, rise=0.45, curl=0.75, n_tiles=8)

box("Top", (0, 0, 3.9), 0.95, 0.9, 0.65, M_WALL, 0.04)
for sx, sy in ((-0.4,-0.35),(-0.4,0.35),(0.4,-0.35),(0.4,0.35)):
    pillar(f"PT{sx}{sy}", sx, sy, 3.55, 0.65)

make_roof("Roof3", 4.3, 1.65, 1.5, rise=0.36, curl=0.65, n_tiles=6)

sph("Fin", (0, 0, 4.9), 0.17, M_GOLD, 20)
cyl("FinStem", (0, 0, 4.72), 0.045, 0.18, M_GOLD, 12, bw=0.01)
sph("Fin2", (0, 0, 5.08), 0.1, M_GOLD, 16)
sph("FinL", (-2.5, 0, 2.2), 0.1, M_GOLD, 14)
sph("FinR", (2.5, 0, 2.2), 0.1, M_GOLD, 14)

bpy.ops.mesh.primitive_plane_add(size=28, location=(0,0,0))
gp = bpy.context.active_object; gp.name = "Ground"; setm(gp, M_GRND)

# Camera low 3/4 like ref
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 2.0))
tgt = bpy.context.active_object
bpy.ops.object.camera_add(location=(9.2, -10.0, 4.2))
cam = bpy.context.active_object
cam.data.lens = 58
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
cam.data.dof.aperture_fstop = 2.6
c = cam.constraints.new("TRACK_TO"); c.target = tgt
c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="AREA", location=(5.5, -3.5, 6.5))
key = bpy.context.active_object
key.data.energy = 400; key.data.color = (1.0, 0.93, 0.8); key.data.size = 5.5
key.rotation_euler = (math.radians(48), 0, math.radians(-30))

bpy.ops.object.light_add(type="AREA", location=(-5, 2.5, 3.5))
fill = bpy.context.active_object
fill.data.energy = 140; fill.data.color = (0.65, 0.75, 1.0); fill.data.size = 5

bpy.ops.object.light_add(type="AREA", location=(1.5, -7, 1.8))
rim = bpy.context.active_object
rim.data.energy = 90; rim.data.color = (1.0, 0.65, 0.5); rim.data.size = 3

bpy.ops.object.light_add(type="SUN", location=(3, -2, 8))
sun = bpy.context.active_object
sun.data.energy = 1.4; sun.data.color = (1.0, 0.96, 0.88)
sun.rotation_euler = (math.radians(42), math.radians(5), math.radians(-18))
sun.data.angle = math.radians(10)

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium Contrast"
sc.view_settings.exposure = 0.3

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
    o.select_set(o.type=="MESH" and o.name!="Ground" and max(o.dimensions)<26)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB"); print("DONE")
