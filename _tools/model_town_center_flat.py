# -*- coding: utf-8 -*-
"""Town Center — flatter chunky toy roofs (gentle stubby eaves, NOT temple curl)."""
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
sc.render.resolution_y = 1050
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.55, 0.62, 0.70, 1)
bg.inputs[1].default_value = 0.42
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])


def mat(name, col, rough=0.5, coat=0.25, coat_r=0.32, metal=0.0, sss=0.1):
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
        b.inputs["Specular IOR Level"].default_value = 0.32
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
    links.new(b.outputs[0], out.inputs[0])
    return m

M_WALL  = mat("Wall", (0.95, 0.92, 0.86), 0.55, 0.18, 0.4, sss=0.14)
M_WOOD  = mat("Wood", (0.16, 0.08, 0.045), 0.62, 0.1, 0.45, sss=0.04)
M_BLUE  = mat("Cobalt", (0.11, 0.34, 0.82), 0.42, 0.3, 0.28, sss=0.1)
M_CYAN  = mat("CyanEdge", (0.25, 0.55, 0.88), 0.45, 0.28, 0.3, sss=0.1)
M_PINK  = mat("Salmon", (0.92, 0.40, 0.42), 0.4, 0.28, 0.25, sss=0.12)
M_GOLD  = mat("Gold", (0.96, 0.80, 0.28), 0.28, 0.5, 0.15, metal=0.55, sss=0.04)
M_STONE = mat("Stone", (0.76, 0.66, 0.52), 0.7, 0.08, 0.5, sss=0.08)
M_DOOR  = mat("Door", (0.9, 0.1, 0.08), 0.4, 0.28, 0.25, sss=0.08)
M_BASE  = mat("Base", (0.82, 0.72, 0.56), 0.55, 0.12, 0.4, sss=0.1)
M_GRND  = mat("Ground", (0.5, 0.54, 0.6), 0.9, 0.0, 0.5, sss=0.0)


def setm(o, m):
    o.data.materials.clear(); o.data.materials.append(m)

def sel(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True); bpy.context.view_layer.objects.active = o

def bevel(o, width=0.05, seg=4):
    sel(o)
    md = o.modifiers.new("Bev", "BEVEL")
    md.width = width; md.segments = seg
    md.limit_method = "ANGLE"; md.angle_limit = math.radians(22)
    bpy.ops.object.modifier_apply(modifier=md.name)

def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()

def box(name, loc, sx, sy, sz, m, bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = (sx, sy, sz); bpy.ops.object.transform_apply(scale=True)
    setm(o, m); bevel(o, bw, 5); return o

def cyl(name, loc, r, depth, m, verts=20, rot=(0,0,0), bw=0.015):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name
    setm(o, m); bevel(o, bw, 3); smooth(o); return o

def sph(name, loc, r, m, seg=16):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=max(8, seg//2))
    o = bpy.context.active_object; o.name = name
    setm(o, m); smooth(o); return o

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join(); objs[0].name = name
    return objs[0]


def roof_z(x, y, hx, hy, rise, stub):
    """Gentle hip slope. Tiny stubby lift ONLY near corners (not whole eave)."""
    tx = abs(x) / max(hx, 1e-6)
    ty = abs(y) / max(hy, 1e-6)
    # diamond hip
    t = max(tx, ty)
    t = min(1.0, t)
    # mostly flat-ish descent — chunky toy, not temple
    z = rise * (1.0 - 0.55 * t)  # gentle slope only
    # corner stub: thick sausage tip bent up a little
    # near corner when BOTH axes are high
    corner = max(0.0, (tx - 0.72) / 0.28) * max(0.0, (ty - 0.72) / 0.28)
    z += stub * (corner ** 0.9)
    return z


def make_roof(name, z0, sx, sy, rise, stub, tile_rows=9, tile_r=0.085):
    hx, hy = sx * 0.5, sy * 0.5
    segs = 40

    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=1, location=(0, 0, 0))
    shell = bpy.context.active_object
    shell.name = name + "_shell"
    shell.scale = (sx * 1.02, sy * 1.02, 1)
    bpy.ops.object.transform_apply(scale=True)

    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(shell.data)
    for v in bm.verts:
        v.co.z = roof_z(v.co.x, v.co.y, hx, hy, rise, stub)
    bmesh.update_edit_mesh(shell.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    shell.location.z = z0
    bpy.ops.object.transform_apply(location=True)

    md = shell.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.2; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    md = shell.modifiers.new("Sm", "SMOOTH")
    md.factor = 0.5; md.iterations = 3
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell, M_BLUE); smooth(shell); bevel(shell, 0.03, 3)

    parts = [shell]

    # Dense CHUNKY cobalt tile rolls across the deck
    for j in range(1, tile_rows):
        yy = -hy + sy * (j / tile_rows)
        t = abs(yy) / hy
        if t > 0.9:
            continue
        zz = z0 + roof_z(0, yy, hx, hy, rise, stub) + tile_r * 0.55
        span = sx * (0.86 - 0.1 * t)
        # main thick tile
        parts.append(cyl(f"{name}_ty{j}", (0, yy, zz), tile_r, span, M_BLUE, 14, rot=(0, math.pi/2, 0)))
        # staggered second row for density
        if j < tile_rows - 1:
            yy2 = yy + sy / tile_rows * 0.45
            t2 = abs(yy2) / hy
            if t2 < 0.88:
                zz2 = z0 + roof_z(0, yy2, hx, hy, rise, stub) + tile_r * 0.4
                parts.append(cyl(f"{name}_tyb{j}", (0, yy2, zz2), tile_r * 0.85, span * 0.92, M_CYAN, 12, rot=(0, math.pi/2, 0)))

    # Salmon perimeter rim — thick tube, gentle, continuous
    curve_data = bpy.data.curves.new(name + "_rim", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.fill_mode = "FULL"
    curve_data.bevel_depth = 0.13
    curve_data.bevel_resolution = 5
    curve_data.resolution_u = 6
    spline = curve_data.splines.new("NURBS")
    N = 48
    samples = []
    for i in range(N):
        u = i / N
        side = int(u * 4) % 4
        f = (u * 4) % 1.0
        if side == 0:
            x, y = -hx + sx * f, -hy
        elif side == 1:
            x, y = hx, -hy + sy * f
        elif side == 2:
            x, y = hx - sx * f, hy
        else:
            x, y = -hx, hy - sy * f
        # slight outward only at corners
        tx, ty = abs(x) / hx, abs(y) / hy
        corner = max(0.0, (tx - 0.75) / 0.25) * max(0.0, (ty - 0.75) / 0.25)
        x *= 1.0 + 0.04 * corner
        y *= 1.0 + 0.04 * corner
        z = z0 + roof_z(x * 0.98, y * 0.98, hx, hy, rise, stub) + 0.1 + stub * 0.35 * corner
        samples.append((x, y, z))
    spline.points.add(len(samples) - 1)
    for i, (x, y, z) in enumerate(samples):
        spline.points[i].co = (x, y, z, 1)
    spline.use_cyclic_u = True
    spline.order_u = 4
    eave = bpy.data.objects.new(name + "_eave", curve_data)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave = bpy.context.active_object
    setm(eave, M_PINK); smooth(eave); bevel(eave, 0.02, 2)
    parts.append(eave)

    # Hip ridges salmon (center to corners) — thick doughy
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x0, y0 = sx_ * hx * 0.1, sy_ * hy * 0.1
        x1, y1 = sx_ * hx * 0.9, sy_ * hy * 0.9
        z0h = z0 + roof_z(x0, y0, hx, hy, rise, stub) + 0.12
        z1h = z0 + roof_z(x1, y1, hx, hy, rise, stub) + 0.12
        d = Vector((x1 - x0, y1 - y0, z1h - z0h))
        mid = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0h + z1h) / 2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.1, depth=d.length, location=mid)
        hip = bpy.context.active_object
        hip.rotation_mode = "QUATERNION"
        hip.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
        setm(hip, M_PINK); smooth(hip)
        parts.append(hip)

    # Center ridge
    parts.append(cyl(f"{name}_cr", (0, 0, z0 + rise + 0.12), 0.11, min(sx, sy) * 0.4, M_PINK, 16, rot=(0, math.pi/2, 0)))

    # Stubby corner tips — blunt sausage ends, NOT sharp
    for sx_, sy_ in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx_ * hx * 0.98, sy_ * hy * 0.98
        z = z0 + roof_z(sx_ * hx * 0.92, sy_ * hy * 0.92, hx, hy, rise, stub) + 0.14 + stub * 0.5
        tip = sph(f"{name}_tip", (x, y, z), 0.18, M_PINK, 16)
        tip.scale = (1.35, 1.35, 0.85)
        bpy.ops.object.transform_apply(scale=True)
        parts.append(tip)
        parts.append(sph(f"{name}_tg", (x, y, z + 0.1), 0.065, M_GOLD, 12))

    return join(parts, name)


def pillar(name, x, y, z0, h):
    base = sph(f"{name}_b", (x, y, z0 + 0.1), 0.16, M_BASE, 14)
    base.scale = (1.25, 1.25, 0.6); bpy.ops.object.transform_apply(scale=True)
    post = cyl(f"{name}_p", (x, y, z0 + h * 0.5 + 0.1), 0.08, h, M_WOOD, 16)
    extras = [base, post]
    for k in range(4):
        ang = k * math.pi / 2
        extras.append(cyl(f"{name}_g{k}", (x + math.cos(ang) * 0.075, y + math.sin(ang) * 0.075, z0 + h * 0.5 + 0.1), 0.011, h * 0.88, M_WOOD, 8, bw=0.004))
    return join(extras, name)


def door(name, x, y, z):
    d = box(f"{name}_d", (x, y, z + 0.3), 0.4, 0.07, 0.6, M_DOOR, 0.04)
    a = sph(f"{name}_a", (x, y, z + 0.62), 0.2, M_DOOR, 12)
    a.scale = (1.05, 0.3, 0.5); bpy.ops.object.transform_apply(scale=True)
    steps = [box(f"{name}_s{i}", (x, y - 0.2 - i * 0.09, 0.035 + i * 0.055), 0.48 - i * 0.07, 0.16, 0.06, M_STONE, 0.025) for i in range(3)]
    return join([d, a] + steps, name)


def foundation():
    rng = random.Random(3)
    pad = cyl("Pad", (0, 0, 0.05), 2.85, 0.12, M_STONE, 48)
    pebs = [pad]
    for i in range(60):
        ang = rng.random() * math.tau
        rr = 2.0 + rng.random() * 1.05
        s = 0.11 + rng.random() * 0.18
        p = sph(f"Pe{i}", (math.cos(ang) * rr, math.sin(ang) * rr, 0.07), s, M_STONE, 10)
        p.scale = (0.9 + rng.random() * 0.5, 0.9 + rng.random() * 0.5, 0.45 + rng.random() * 0.35)
        bpy.ops.object.transform_apply(scale=True)
        pebs.append(p)
    for i in range(18):
        pebs.append(sph(f"Pi{i}", (rng.uniform(-1.6, 1.6), rng.uniform(-1.3, 1.3), 0.06), 0.1 + rng.random() * 0.12, M_STONE, 8))
    return join(pebs, "Foundation")


# ===== MASSING (match MJ: wide base wings, taller center stack) =====
foundation()

# Ground floor center — wider
box("Center", (0, 0, 0.75), 2.5, 2.15, 1.15, M_WALL, 0.06)
# Side wings — lower, attached, substantial
box("WingL", (-2.55, 0.0, 0.5), 2.3, 1.85, 0.75, M_WALL, 0.055)
box("WingR", (2.55, 0.0, 0.5), 2.3, 1.85, 0.75, M_WALL, 0.055)

box("LintC", (0, -1.12, 1.25), 2.5, 0.12, 0.12, M_WOOD, 0.025)
box("LintL", (-2.55, -0.95, 0.85), 2.3, 0.11, 0.11, M_WOOD, 0.02)
box("LintR", (2.55, -0.95, 0.85), 2.3, 0.11, 0.11, M_WOOD, 0.02)

for sx in (-1.1, 1.1):
    for sy in (-1.0, 1.0):
        pillar(f"PC{sx}{sy}", sx, sy, 0.1, 1.15)
for wx in (-3.4, -1.7, 1.7, 3.4):
    for sy in (-0.8, 0.8):
        pillar(f"PW{wx}{sy}", wx, sy, 0.08, 0.85)

door("DC", 0, -1.12, 0.15)
door("DL", -2.55, -0.95, 0.1)
door("DR", 2.55, -0.95, 0.1)

# Roof1 — wide over wings+center, FLAT gentle, tiny stub corners
# rise small, stub tiny
make_roof("Roof1", 1.3, 7.6, 3.7, rise=0.38, stub=0.18, tile_rows=11, tile_r=0.09)

# Mid tower
box("Mid", (0, 0, 2.25), 1.85, 1.65, 0.85, M_WALL, 0.05)
for sx, sy in ((-0.78, -0.68), (-0.78, 0.68), (0.78, -0.68), (0.78, 0.68)):
    pillar(f"PM{sx}{sy}", sx, sy, 1.85, 0.85)
# tiny windows
box("WinL", (-0.5, -0.85, 2.3), 0.25, 0.05, 0.28, M_WOOD, 0.02)
box("WinR", (0.5, -0.85, 2.3), 0.25, 0.05, 0.28, M_WOOD, 0.02)

make_roof("Roof2", 2.75, 3.1, 2.75, rise=0.32, stub=0.15, tile_rows=8, tile_r=0.075)

# Top
box("Top", (0, 0, 3.5), 1.1, 1.0, 0.6, M_WALL, 0.04)
for sx, sy in ((-0.45, -0.4), (-0.45, 0.4), (0.45, -0.4), (0.45, 0.4)):
    pillar(f"PT{sx}{sy}", sx, sy, 3.2, 0.6)

make_roof("Roof3", 3.9, 1.8, 1.6, rise=0.26, stub=0.12, tile_rows=6, tile_r=0.06)

# Gold finials — prominent on peaks
sph("Fin", (0, 0, 4.4), 0.16, M_GOLD, 20)
cyl("FinStem", (0, 0, 4.22), 0.04, 0.16, M_GOLD, 12, bw=0.008)
sph("Fin2", (0, 0, 4.55), 0.09, M_GOLD, 14)
sph("FinL", (-2.6, 0, 1.85), 0.1, M_GOLD, 14)
sph("FinR", (2.6, 0, 1.85), 0.1, M_GOLD, 14)

bpy.ops.mesh.primitive_plane_add(size=28, location=(0, 0, 0))
gp = bpy.context.active_object; gp.name = "Ground"; setm(gp, M_GRND)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 1.9))
tgt = bpy.context.active_object
bpy.ops.object.camera_add(location=(9.5, -10.5, 4.0))
cam = bpy.context.active_object
cam.data.lens = 55
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
cam.data.dof.aperture_fstop = 2.8
c = cam.constraints.new("TRACK_TO"); c.target = tgt
c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
sc.camera = cam

bpy.ops.object.light_add(type="AREA", location=(5.5, -3.5, 6))
key = bpy.context.active_object
key.data.energy = 380; key.data.color = (1.0, 0.93, 0.82); key.data.size = 5.5

bpy.ops.object.light_add(type="AREA", location=(-5, 2.5, 3.5))
fill = bpy.context.active_object
fill.data.energy = 130; fill.data.color = (0.65, 0.75, 1.0); fill.data.size = 5

bpy.ops.object.light_add(type="AREA", location=(2, -7, 1.8))
rim = bpy.context.active_object
rim.data.energy = 85; rim.data.color = (1.0, 0.7, 0.55); rim.data.size = 3

bpy.ops.object.light_add(type="SUN", location=(3, -2, 8))
sun = bpy.context.active_object
sun.data.energy = 1.3; sun.data.color = (1.0, 0.96, 0.9)
sun.rotation_euler = (math.radians(40), math.radians(5), math.radians(-20))
sun.data.angle = math.radians(10)

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium Contrast"
sc.view_settings.exposure = 0.28

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
    o.select_set(o.type == "MESH" and o.name != "Ground" and max(o.dimensions) < 26)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB"); print("DONE")
