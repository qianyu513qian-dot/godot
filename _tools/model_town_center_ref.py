# -*- coding: utf-8 -*-
"""Town Center remodel matching Midjourney ref:
   cobalt tile fields + salmon ridge/eaves, side wings, clay (not glass).
"""
import bpy, bmesh, math
from mathutils import Vector

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"
REF       = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\ref\town_center_ref.png"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 96
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1280
sc.render.resolution_y = 1100
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

# Soft studio world (cool grey like ref background)
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.62, 0.68, 0.75, 1)  # soft blue-grey
bg.inputs[1].default_value = 0.45
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])


def mat(name, col, rough=0.45, coat=0.35, coat_r=0.25, metal=0.0, sat_boost=False):
    """Clay / soft plastic — matte-to-soft clearcoat, NOT glassy."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = coat_r
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.4
    # slight subsurface for clay feel
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = 0.08
        if "Subsurface Radius" in b.inputs:
            b.inputs["Subsurface Radius"].default_value = (1.0, 0.4, 0.2)
    links.new(b.outputs[0], out.inputs[0])
    return m


M_WALL  = mat("WallCream", (0.93, 0.90, 0.84), rough=0.55, coat=0.2, coat_r=0.35)
M_WOOD  = mat("WoodDark", (0.22, 0.12, 0.07), rough=0.6, coat=0.15, coat_r=0.4)
M_BLUE  = mat("TileCobalt", (0.12, 0.32, 0.78), rough=0.42, coat=0.45, coat_r=0.22)  # clay blue
M_PINK  = mat("RidgeSalmon", (0.92, 0.38, 0.42), rough=0.38, coat=0.4, coat_r=0.2)   # salmon eaves
M_GOLD  = mat("GoldFinial", (0.95, 0.78, 0.28), rough=0.28, coat=0.55, coat_r=0.15, metal=0.45)
M_STONE = mat("StoneTan", (0.72, 0.62, 0.48), rough=0.7, coat=0.1, coat_r=0.5)
M_DOOR  = mat("DoorRed", (0.85, 0.12, 0.10), rough=0.4, coat=0.35, coat_r=0.25)
M_BASE  = mat("PillarBase", (0.78, 0.68, 0.52), rough=0.55, coat=0.15, coat_r=0.4)


def setm(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


def bevel(o, width=0.05, seg=4):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("Bev", "BEVEL")
    md.width = width
    md.segments = seg
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(25)
    bpy.ops.object.modifier_apply(modifier=md.name)


def box(name, loc, sx, sy, sz, m, bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    setm(o, m)
    bevel(o, bw, 4)
    return o


def cyl(name, loc, r, depth, m, verts=24, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    setm(o, m)
    bevel(o, min(0.03, r * 0.25), 3)
    return o


def sphere(name, loc, r, m, seg=16):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    o = bpy.context.active_object
    o.name = name
    setm(o, m)
    return o


def join_selected(active):
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    return active


def pillar(name, x, y, z0, height, wood=M_WOOD):
    """Dark wood post with grooved look (thin cylinders) + bulbous tan base."""
    base = sphere(f"{name}_base", (x, y, z0 + 0.12), 0.18, M_BASE, 14)
    base.scale = (1.15, 1.15, 0.7)
    bpy.ops.object.transform_apply(scale=True)
    post = cyl(f"{name}_post", (x, y, z0 + height * 0.5 + 0.15), 0.09, height, wood, 16)
    # groove strips
    extras = [base, post]
    for ang in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        gx = x + math.cos(ang) * 0.085
        gy = y + math.sin(ang) * 0.085
        g = cyl(f"{name}_g", (gx, gy, z0 + height * 0.5 + 0.15), 0.012, height * 0.92, wood, 8)
        extras.append(g)
    bpy.ops.object.select_all(action="DESELECT")
    for e in extras:
        e.select_set(True)
    return join_selected(post)


def pebble_foundation(cx, cy, cz, radius=2.8, count=48):
    """Chunky tan pebble ring / pad under building."""
    parts = []
    # main pad
    pad = cyl("FoundPad", (cx, cy, cz), radius, 0.18, M_STONE, 48)
    parts.append(pad)
    import random
    rng = random.Random(42)
    for i in range(count):
        ang = (i / count) * math.tau + rng.uniform(-0.05, 0.05)
        rr = radius * rng.uniform(0.75, 1.05)
        px = cx + math.cos(ang) * rr
        py = cy + math.sin(ang) * rr
        s = rng.uniform(0.12, 0.28)
        p = sphere(f"Peb{i}", (px, py, cz + 0.08), s, M_STONE, 10)
        p.scale = (rng.uniform(0.8, 1.3), rng.uniform(0.8, 1.3), rng.uniform(0.5, 0.9))
        bpy.ops.object.transform_apply(scale=True)
        parts.append(p)
    # inner fill pebbles
    for i in range(20):
        px = cx + rng.uniform(-radius * 0.5, radius * 0.5)
        py = cy + rng.uniform(-radius * 0.5, radius * 0.5)
        s = rng.uniform(0.1, 0.22)
        p = sphere(f"PebIn{i}", (px, py, cz + 0.06), s, M_STONE, 8)
        parts.append(p)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    return join_selected(pad)


def arched_door(name, x, y, z, facing=+1):
    """Bright red door with soft arch + 3 rounded steps."""
    # door slab
    door = box(f"{name}_door", (x, y, z + 0.35), 0.45, 0.08, 0.7, M_DOOR, 0.04)
    # arch top (half-ish via scaled sphere cut feel — use elongated sphere)
    arch = sphere(f"{name}_arch", (x, y, z + 0.72), 0.24, M_DOOR, 14)
    arch.scale = (1.0, 0.35, 0.55)
    bpy.ops.object.transform_apply(scale=True)
    steps = []
    for i, (sy, sz, zz) in enumerate([(0.55, 0.08, 0.04), (0.45, 0.08, 0.10), (0.35, 0.08, 0.16)]):
        st = box(f"{name}_st{i}", (x, y - facing * (0.25 + i * 0.1), zz), sy, 0.2, sz, M_STONE, 0.03)
        steps.append(st)
    bpy.ops.object.select_all(action="DESELECT")
    door.select_set(True)
    arch.select_set(True)
    for s in steps:
        s.select_set(True)
    return join_selected(door)


def roof_deck(name, z0, size_x, size_y, rise, curl, tile_mat, ridge_mat, tiles_x=12, tiles_y=10):
    """Blue clay tile field + salmon ridges/eaves with strong upsweep.
    Tiles = large rounded cylinders lying on the surface.
    """
    # --- base shell (blue) via grid ---
    segs = 36
    bpy.ops.mesh.primitive_grid_add(
        x_subdivisions=segs, y_subdivisions=segs,
        size=1, location=(0, 0, z0)
    )
    o = bpy.context.active_object
    o.name = name + "_shell"
    o.scale = (size_x, size_y, 1)
    bpy.ops.object.transform_apply(scale=True)

    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    hx, hy = size_x * 0.5, size_y * 0.5
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        tx = abs(x) / max(hx, 1e-6)
        ty = abs(y) / max(hy, 1e-6)
        t = max(tx, ty)
        t = min(1.0, t)
        # descend then strong curl
        if t < 0.68:
            u = t / 0.68
            z = rise * (1.0 - 0.85 * u)
        else:
            u = (t - 0.68) / 0.32
            valley = rise * 0.15
            z = valley + curl * (u ** 1.15)
        v.co.z = z
    bmesh.update_edit_mesh(o.data)
    bpy.ops.object.mode_set(mode="OBJECT")

    md = o.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.14
    md.offset = -1.0
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(o, tile_mat)
    bpy.ops.object.shade_smooth()
    bevel(o, 0.02, 2)

    parts = [o]

    def height_at(x, y):
        tx = abs(x) / max(hx, 1e-6)
        ty = abs(y) / max(hy, 1e-6)
        t = min(1.0, max(tx, ty))
        if t < 0.68:
            u = t / 0.68
            return z0 + rise * (1.0 - 0.85 * u)
        u = (t - 0.68) / 0.32
        return z0 + rise * 0.15 + curl * (u ** 1.15)

    # --- large cylindrical clay TILES (rows along X) ---
    for j in range(1, tiles_y):
        yy = -hy + size_y * (j / tiles_y)
        # skip extreme eave band (pink ridge owns that)
        t = abs(yy) / hy
        if t > 0.88:
            continue
        zz = height_at(0, yy) + 0.06
        span = size_x * (0.88 - 0.12 * t)
        # one long rounded tile bar
        tbar = cyl(f"{name}_tileY{j}", (0, yy, zz), 0.055, span, tile_mat, 12, rot=(0, math.pi / 2, 0))
        parts.append(tbar)
        # secondary thinner tile for density
        if j % 2 == 0:
            t2 = cyl(f"{name}_tileYb{j}", (0, yy + size_y * 0.02, zz + 0.02), 0.04, span * 0.95, tile_mat, 10, rot=(0, math.pi / 2, 0))
            parts.append(t2)

    # cross tiles near sides for chunky clay look
    for i in range(2, tiles_x - 1, 2):
        xx = -hx + size_x * (i / tiles_x)
        for ysign in (-0.75, 0.75):
            yy = ysign * hy * 0.55
            zz = height_at(xx, yy) + 0.05
            tbar = cyl(f"{name}_tileX{i}_{ysign}", (xx, yy, zz), 0.045, hy * 0.55, tile_mat, 10, rot=(math.pi / 2, 0, 0))
            parts.append(tbar)

    # --- SALMON ridge: center ridge along X ---
    zz_ridge = z0 + rise + 0.08
    ridge = cyl(f"{name}_ridge", (0, 0, zz_ridge), 0.09, size_x * 0.55, ridge_mat, 16, rot=(0, math.pi / 2, 0))
    parts.append(ridge)
    # hip ridges to corners
    for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        # diagonal approximate with cylinder from near center to eave
        x0, y0 = sx * hx * 0.15, sy * hy * 0.15
        x1, y1 = sx * hx * 0.92, sy * hy * 0.92
        mx, my = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        z0h = height_at(x0, y0) + 0.07
        z1h = height_at(x1, y1) + 0.07
        mz = (z0h + z1h) * 0.5
        dx, dy, dz = x1 - x0, y1 - y0, z1h - z0h
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.07, depth=length, location=(mx, my, mz))
        hip = bpy.context.active_object
        # orient cylinder to direction
        direction = Vector((dx, dy, dz)).normalized()
        hip.rotation_mode = "QUATERNION"
        hip.rotation_quaternion = direction.to_track_quat("Z", "Y")
        setm(hip, ridge_mat)
        parts.append(hip)

    # --- SALMON eave tubes along perimeter with upsweep ---
    for edge in range(4):
        n = 14
        for i in range(n + 1):
            u = i / n
            if edge == 0:
                x, y = -hx + size_x * u, -hy * 0.98
            elif edge == 1:
                x, y = -hx + size_x * u, hy * 0.98
            elif edge == 2:
                x, y = -hx * 0.98, -hy + size_y * u
            else:
                x, y = hx * 0.98, -hy + size_y * u
            zz = height_at(x, y) + 0.05
            # thicker near corners
            corner = min(u, 1 - u)
            rad = 0.07 if corner < 0.15 else 0.055
            tip = sphere(f"{name}_eave{edge}_{i}", (x, y, zz), rad, ridge_mat, 10)
            parts.append(tip)

    # big blunt eave tips (salmon) at 4 corners — signature swept-up look
    for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx * hx * 0.97, sy * hy * 0.97
        zz = height_at(x, y) + 0.1
        tip = sphere(f"{name}_tip", (x, y, zz), 0.14, ridge_mat, 14)
        tip.scale = (1.3, 1.3, 0.85)
        bpy.ops.object.transform_apply(scale=True)
        # small gold accent on tip
        g = sphere(f"{name}_tipg", (x, y, zz + 0.12), 0.06, M_GOLD, 12)
        parts.append(tip)
        parts.append(g)

    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    joined = join_selected(o)
    joined.name = name
    return joined


# ===================== BUILD =====================
# Foundation
pebble_foundation(0, 0, 0.05, radius=3.1, count=56)

# Central hall
box("CenterWall", (0, 0, 0.85), 2.4, 2.2, 1.35, M_WALL, 0.06)
# Side wings (lower)
box("WingL", (-2.35, 0, 0.55), 2.0, 1.8, 0.85, M_WALL, 0.055)
box("WingR", (2.35, 0, 0.55), 2.0, 1.8, 0.85, M_WALL, 0.055)
# Connecting beams under eaves (dark wood horizontals)
box("LintC", (0, -1.15, 1.4), 2.4, 0.14, 0.14, M_WOOD, 0.03)
box("LintL", (-2.35, -0.95, 0.95), 2.0, 0.12, 0.12, M_WOOD, 0.025)
box("LintR", (2.35, -0.95, 0.95), 2.0, 0.12, 0.12, M_WOOD, 0.025)

# Pillars under main eaves
for sx in (-1.05, 1.05):
    for sy in (-1.0, 1.0):
        pillar(f"PC_{sx}_{sy}", sx, sy, 0.15, 1.35)
# Wing pillars
for wx in (-3.1, -1.6, 1.6, 3.1):
    for sy in (-0.8, 0.8):
        pillar(f"PW_{wx}_{sy}", wx, sy, 0.12, 0.95)

# Doors
arched_door("DoorC", 0, -1.15, 0.2, facing=+1)
arched_door("DoorL", -2.35, -0.95, 0.15, facing=+1)
arched_door("DoorR", 2.35, -0.95, 0.15, facing=+1)

# ---- Roof tier 1: wide over center+wings, COBALT tiles + SALMON ridges ----
roof_deck("Roof1", 1.55, 7.0, 3.4, rise=0.55, curl=0.7, tile_mat=M_BLUE, ridge_mat=M_PINK, tiles_x=16, tiles_y=12)

# Mid tower
box("MidWall", (0, 0, 2.55), 1.7, 1.55, 0.95, M_WALL, 0.05)
for sx, sy in ((-0.75, -0.65), (-0.75, 0.65), (0.75, -0.65), (0.75, 0.65)):
    pillar(f"PM_{sx}_{sy}", sx, sy, 2.1, 0.95)

roof_deck("Roof2", 3.1, 2.9, 2.6, rise=0.48, curl=0.62, tile_mat=M_BLUE, ridge_mat=M_PINK, tiles_x=12, tiles_y=10)

# Top lantern
box("TopWall", (0, 0, 3.95), 1.0, 0.95, 0.7, M_WALL, 0.04)
for sx, sy in ((-0.42, -0.38), (-0.42, 0.38), (0.42, -0.38), (0.42, 0.38)):
    pillar(f"PT_{sx}_{sy}", sx, sy, 3.6, 0.7)

roof_deck("Roof3", 4.4, 1.7, 1.55, rise=0.38, curl=0.52, tile_mat=M_BLUE, ridge_mat=M_PINK, tiles_x=8, tiles_y=8)

# Gold peak finial (large sphere + ornament)
sphere("Finial", (0, 0, 5.0), 0.18, M_GOLD, 20)
cyl("FinialStem", (0, 0, 4.82), 0.05, 0.2, M_GOLD, 12)
sphere("FinialTop", (0, 0, 5.18), 0.1, M_GOLD, 14)

# Small gold finials on wing roof peaks (approx at wing centers on Roof1)
sphere("FinL", (-2.4, 0, 2.25), 0.1, M_GOLD, 14)
sphere("FinR", (2.4, 0, 2.25), 0.1, M_GOLD, 14)

# Ground plane (subtle)
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
gp = bpy.context.active_object
gp.name = "Ground"
setm(gp, mat("GroundGrey", (0.55, 0.58, 0.62), rough=0.85, coat=0.05))

# Camera — low 3/4 beauty like reference
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 2.2))
target = bpy.context.active_object
target.name = "LookAt"

bpy.ops.object.camera_add(location=(8.5, -9.5, 4.8))
cam = bpy.context.active_object
cam.data.lens = 55
cam.data.dof.use_dof = True
cam.data.dof.focus_object = target
cam.data.dof.aperture_fstop = 2.8
con = cam.constraints.new("TRACK_TO")
con.target = target
con.track_axis = "TRACK_NEGATIVE_Z"
con.up_axis = "UP_Y"
sc.camera = cam

# Soft studio lights (warm key, cool fill)
bpy.ops.object.light_add(type="AREA", location=(6, -4, 7))
key = bpy.context.active_object
key.data.energy = 350
key.data.color = (1.0, 0.92, 0.78)
key.data.size = 6
key.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))

bpy.ops.object.light_add(type="AREA", location=(-5, 3, 4))
fill = bpy.context.active_object
fill.data.energy = 120
fill.data.color = (0.7, 0.8, 1.0)
fill.data.size = 5

bpy.ops.object.light_add(type="AREA", location=(2, -6, 2))
rim = bpy.context.active_object
rim.data.energy = 80
rim.data.color = (1.0, 0.7, 0.55)
rim.data.size = 3

bpy.ops.object.light_add(type="SUN", location=(4, -2, 10))
sun = bpy.context.active_object
sun.data.energy = 1.8
sun.data.color = (1.0, 0.95, 0.85)
sun.rotation_euler = (math.radians(45), math.radians(5), math.radians(-20))
sun.data.angle = math.radians(8)

sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium Contrast"
sc.view_settings.exposure = 0.25

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    for d in prefs.devices:
        d.use = True
except Exception:
    pass

# Reference image as empty (optional, if file exists)
import os
if os.path.exists(REF):
    bpy.ops.object.empty_add(type="IMAGE", location=(-6, 0, 3))
    img_empty = bpy.context.active_object
    img_empty.name = "RefImage"
    try:
        img = bpy.data.images.load(REF)
        img_empty.data = img
        img_empty.empty_display_size = 4
        img_empty.rotation_euler = (math.radians(90), 0, math.radians(90))
    except Exception as e:
        print("REF_LOAD_FAIL", e)

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED_BLEND")
bpy.ops.render.render(write_still=True)
print("SAVED_PNG", OUT_PNG)

# Export GLB without ground
for o in sc.objects:
    o.select_set(o.type == "MESH" and o.name != "Ground" and max(o.dimensions) < 25)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB", OUT_GLB)
print("DONE")
