"""Blender town-center beauty model — East Asian toy/clay pagoda matching reference."""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"

# --- reset ---
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.render.resolution_x = 1280
scene.render.resolution_y = 960
scene.render.filepath = OUT_PNG
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
# world
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
nt = world.node_tree
nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (1.0, 0.72, 0.45, 1.0)  # warm golden sky
bg.inputs[1].default_value = 0.55
out = nt.nodes.new("ShaderNodeOutputWorld")
nt.links.new(bg.outputs[0], out.inputs[0])


def mat_plastic(name, color, roughness=0.28, clearcoat=0.85, clearcoat_rough=0.12, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    # Blender 4.x: Coat
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = clearcoat
        bsdf.inputs["Coat Roughness"].default_value = clearcoat_rough
    elif "Clearcoat" in bsdf.inputs:
        bsdf.inputs["Clearcoat"].default_value = clearcoat
        bsdf.inputs["Clearcoat Roughness"].default_value = clearcoat_rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.55
    links.new(bsdf.outputs[0], out.inputs[0])
    return m


MAT_WALL = mat_plastic("WallPlaster", (0.96, 0.94, 0.90), roughness=0.35, clearcoat=0.45)
MAT_WOOD = mat_plastic("WoodBeam", (0.45, 0.28, 0.14), roughness=0.42, clearcoat=0.35)
MAT_ROOF_RED = mat_plastic("RoofCrimson", (0.78, 0.12, 0.08), roughness=0.22, clearcoat=0.95, clearcoat_rough=0.08)
MAT_ROOF_BLUE = mat_plastic("RoofCobalt", (0.12, 0.28, 0.72), roughness=0.22, clearcoat=0.95, clearcoat_rough=0.08)
MAT_TRIM = mat_plastic("GoldTrim", (0.85, 0.65, 0.18), roughness=0.25, clearcoat=0.7, metallic=0.35)
MAT_STONE = mat_plastic("StoneBase", (0.55, 0.50, 0.42), roughness=0.55, clearcoat=0.2)
MAT_DOOR = mat_plastic("DoorDark", (0.25, 0.15, 0.08), roughness=0.4, clearcoat=0.3)


def apply_mat(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def bevel_obj(obj, width=0.04, segments=3):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(25)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def subdivide_smooth(obj, levels=1):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    bpy.ops.object.modifier_apply(modifier=mod.name)


def make_box(name, loc, size, mat, bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    apply_mat(obj, mat)
    bevel_obj(obj, width=bevel, segments=3)
    return obj


def make_cylinder(name, loc, radius, depth, mat, verts=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    apply_mat(obj, mat)
    bevel_obj(obj, width=0.02, segments=2)
    return obj


def curved_roof_slab(name, center, width, depth, height, mat, curve=0.18, tile_rows=10, tile_cols=14):
    """Pagoda-style hip roof with upturned eaves and visible tile ridges."""
    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    # Build roof as lofted profile with upturned corners
    # Base footprint slightly larger than walls; ridge along X
    hw, hd = width * 0.5, depth * 0.5
    # Vertical layers for thickness + curve
    # Profile along Y from eave to ridge: y goes -hd..hd, z rises to center then down, with eave tip up
    rows = tile_rows
    cols = tile_cols
    verts_grid = []
    for j in range(rows + 1):
        v = j / rows  # 0 at -Y eave, 1 at +Y eave
        y = -hd + depth * v
        # distance from ridge (center Y)
        dy = abs(y) / max(hd, 1e-6)
        # classic hip: high at center, low at eaves, but tip curls UP
        z_base = height * (1.0 - dy * 0.92)
        # upturned eave near dy~1
        curl = curve * max(0.0, (dy - 0.72) / 0.28) ** 2
        z = z_base + curl * height
        row = []
        for i in range(cols + 1):
            u = i / cols
            x = -hw + width * u
            dx = abs(x) / max(hw, 1e-6)
            # hip corners: pull Z down toward corners then curl
            corner = max(dx, dy)
            zc = height * (1.0 - corner * 0.88)
            curl_c = curve * max(0.0, (corner - 0.7) / 0.3) ** 2
            zz = zc + curl_c * height
            # slight tile ridge undulation along X
            ridge = 0.012 * math.sin(u * math.pi * cols * 0.5)
            row.append(bm.verts.new((center[0] + x, center[1] + y, center[2] + zz + ridge)))
        verts_grid.append(row)
    bm.verts.ensure_lookup_table()

    # top faces
    for j in range(rows):
        for i in range(cols):
            v0 = verts_grid[j][i]
            v1 = verts_grid[j][i + 1]
            v2 = verts_grid[j + 1][i + 1]
            v3 = verts_grid[j + 1][i]
            try:
                bm.faces.new((v0, v1, v2, v3))
            except ValueError:
                pass

    # underside (thin shell)
    thickness = 0.08
    under = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            v = verts_grid[j][i]
            row.append(bm.verts.new((v.co.x, v.co.y, v.co.z - thickness)))
        under.append(row)
    bm.verts.ensure_lookup_table()
    for j in range(rows):
        for i in range(cols):
            v0 = under[j][i]
            v1 = under[j + 1][i]
            v2 = under[j + 1][i + 1]
            v3 = under[j][i + 1]
            try:
                bm.faces.new((v0, v1, v2, v3))
            except ValueError:
                pass
    # side skirts
    for j in range(rows):
        for edge_i, (a, b) in ((0, (0, 0)), (cols, (cols, cols))):
            pass
    # perimeter
    for i in range(cols):
        # -Y
        try:
            bm.faces.new((verts_grid[0][i], under[0][i], under[0][i + 1], verts_grid[0][i + 1]))
        except ValueError:
            pass
        # +Y
        try:
            bm.faces.new((verts_grid[rows][i + 1], under[rows][i + 1], under[rows][i], verts_grid[rows][i]))
        except ValueError:
            pass
    for j in range(rows):
        try:
            bm.faces.new((verts_grid[j][0], verts_grid[j + 1][0], under[j + 1][0], under[j][0]))
        except ValueError:
            pass
        try:
            bm.faces.new((verts_grid[j][cols], under[j][cols], under[j + 1][cols], verts_grid[j + 1][cols]))
        except ValueError:
            pass

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    apply_mat(obj, mat)

    # Tile ridge cylinders for visible rows
    ridge_objs = []
    for j in range(1, rows):
        v = j / rows
        y = -hd + depth * v
        dy = abs(y) / max(hd, 1e-6)
        z_base = height * (1.0 - dy * 0.92)
        curl = curve * max(0.0, (dy - 0.72) / 0.28) ** 2
        z = center[2] + z_base + curl * height + 0.02
        # length shrinks toward ridge? keep full width with hip taper
        span = width * (0.92 - 0.15 * dy)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=0.028, depth=span,
            location=(center[0], center[1] + y, z),
            rotation=(0, math.pi / 2, 0),
        )
        cyl = bpy.context.active_object
        cyl.name = f"{name}_tile_{j}"
        apply_mat(cyl, mat)
        ridge_objs.append(cyl)

    # Corner finials / eave tips accent
    for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        ex = center[0] + sx * hw * 0.98
        ey = center[1] + sy * hd * 0.98
        ez = center[2] + height * 0.22 + curve * height
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(ex, ey, ez), segments=16, ring_count=8)
        tip = bpy.context.active_object
        tip.name = f"{name}_eave"
        apply_mat(tip, MAT_TRIM)
        ridge_objs.append(tip)

    # Join ridges into roof for single object
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    for r in ridge_objs:
        r.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    bevel_obj(obj, width=0.015, segments=2)
    return obj


def roof_cap_ornament(loc, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=loc, segments=20, ring_count=12)
    s = bpy.context.active_object
    apply_mat(s, mat)
    bpy.ops.mesh.primitive_cone_add(radius1=0.08, depth=0.2, location=(loc[0], loc[1], loc[2] + 0.14))
    c = bpy.context.active_object
    apply_mat(c, mat)
    bpy.ops.object.select_all(action="DESELECT")
    s.select_set(True)
    c.select_set(True)
    bpy.context.view_layer.objects.active = s
    bpy.ops.object.join()
    return s


# ========== BUILD TOWN CENTER ==========
# Scale: ~toy diorama, total height ~4.5 units
parts = []

# Stone plinth
parts.append(make_box("Plinth", (0, 0, 0.12), (3.6, 3.6, 0.24), MAT_STONE, bevel=0.05))
# Steps
parts.append(make_box("Steps", (0, -1.95, 0.1), (1.4, 0.5, 0.2), MAT_STONE, bevel=0.03))

# Ground floor walls (white plaster)
parts.append(make_box("WallL1", (0, 0, 0.95), (2.9, 2.9, 1.5), MAT_WALL, bevel=0.06))
# Wood frame posts at corners
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    parts.append(make_box(f"Post1_{sx}_{sy}", (sx * 1.35, sy * 1.35, 0.95), (0.22, 0.22, 1.55), MAT_WOOD, bevel=0.04))
# Horizontal beams
parts.append(make_box("Beam1X", (0, 1.35, 1.55), (2.9, 0.18, 0.18), MAT_WOOD, bevel=0.03))
parts.append(make_box("Beam1X2", (0, -1.35, 1.55), (2.9, 0.18, 0.18), MAT_WOOD, bevel=0.03))
parts.append(make_box("Beam1Y", (1.35, 0, 1.55), (0.18, 2.9, 0.18), MAT_WOOD, bevel=0.03))
parts.append(make_box("Beam1Y2", (-1.35, 0, 1.55), (0.18, 2.9, 0.18), MAT_WOOD, bevel=0.03))
# Door
parts.append(make_box("Door", (0, -1.48, 0.75), (0.7, 0.08, 1.1), MAT_DOOR, bevel=0.02))

# Tier 1 roof — CRIMSON, wide
r1 = curved_roof_slab("Roof1", (0, 0, 1.72), width=3.8, depth=3.8, height=0.75, mat=MAT_ROOF_RED, curve=0.28, tile_rows=12, tile_cols=16)
parts.append(r1)

# Mid story
parts.append(make_box("WallL2", (0, 0, 2.55), (2.1, 2.1, 1.0), MAT_WALL, bevel=0.05))
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    parts.append(make_box(f"Post2_{sx}_{sy}", (sx * 0.95, sy * 0.95, 2.55), (0.18, 0.18, 1.05), MAT_WOOD, bevel=0.03))
parts.append(make_box("Beam2X", (0, 0.95, 2.95), (2.1, 0.14, 0.14), MAT_WOOD, bevel=0.025))
parts.append(make_box("Beam2X2", (0, -0.95, 2.95), (2.1, 0.14, 0.14), MAT_WOOD, bevel=0.025))

# Tier 2 roof — COBALT
r2 = curved_roof_slab("Roof2", (0, 0, 3.08), width=2.85, depth=2.85, height=0.62, mat=MAT_ROOF_BLUE, curve=0.32, tile_rows=10, tile_cols=14)
parts.append(r2)

# Top lantern / pavilion
parts.append(make_box("WallL3", (0, 0, 3.75), (1.15, 1.15, 0.7), MAT_WALL, bevel=0.04))
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    parts.append(make_box(f"Post3_{sx}_{sy}", (sx * 0.52, sy * 0.52, 3.75), (0.12, 0.12, 0.72), MAT_WOOD, bevel=0.02))

# Tier 3 roof — CRIMSON small
r3 = curved_roof_slab("Roof3", (0, 0, 4.12), width=1.7, depth=1.7, height=0.48, mat=MAT_ROOF_RED, curve=0.35, tile_rows=8, tile_cols=10)
parts.append(r3)

# Apex ornament gold
parts.append(roof_cap_ornament((0, 0, 4.62), MAT_TRIM))

# Small lanterns under eaves
for sx in (-1.2, 1.2):
    make_cylinder("Lantern", (sx, -1.5, 1.85), 0.06, 0.12, MAT_TRIM, verts=12)

# Join all into one TownCenter for export convenience (keep separate for render quality — actually keep separate)
# Parent empty
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
root = bpy.context.active_object
root.name = "TownCenter"
for o in list(bpy.context.scene.objects):
    if o != root and o.type == "MESH":
        o.parent = root

# --- Camera: 50-degree-ish beauty angle ---
bpy.ops.object.camera_add(location=(6.2, -6.8, 4.8), rotation=(math.radians(58), 0, math.radians(42)))
cam = bpy.context.active_object
cam.name = "BeautyCam"
cam.data.lens = 50
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = 9.5
cam.data.dof.aperture_fstop = 2.8
scene.camera = cam

# --- Lights: golden hour ---
bpy.ops.object.light_add(type="SUN", location=(5, -3, 8))
sun = bpy.context.active_object
sun.data.energy = 4.5
sun.data.color = (1.0, 0.85, 0.55)
sun.rotation_euler = (math.radians(42), math.radians(15), math.radians(-35))
sun.data.angle = math.radians(5)

bpy.ops.object.light_add(type="AREA", location=(-3, 2, 3.5))
fill = bpy.context.active_object
fill.data.energy = 80
fill.data.color = (0.55, 0.7, 1.0)
fill.data.size = 4
fill.rotation_euler = (math.radians(70), 0, math.radians(40))

bpy.ops.object.light_add(type="AREA", location=(2, -4, 2))
rim = bpy.context.active_object
rim.data.energy = 40
rim.data.color = (1.0, 0.55, 0.3)
rim.data.size = 2

# Ground plane soft
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
apply_mat(ground, mat_plastic("Grass", (0.35, 0.62, 0.28), roughness=0.7, clearcoat=0.15))

# Dirt disc under building
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=3.2, depth=0.04, location=(0, 0, 0.02))
dirt = bpy.context.active_object
apply_mat(dirt, mat_plastic("Dirt", (0.62, 0.48, 0.32), roughness=0.65, clearcoat=0.1))

# Color management
scene.view_settings.view_transform = "Filmic"
scene.view_settings.look = "Medium High Contrast"
scene.view_settings.exposure = 0.15

# Prefer GPU if available
prefs = bpy.context.preferences.addons.get("cycles")
if prefs:
    cprefs = prefs.preferences
    try:
        cprefs.compute_device_type = "CUDA"
        for d in cprefs.devices:
            d.use = True
    except Exception:
        pass
scene.cycles.device = "GPU"

# Save blend
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED_BLEND", OUT_BLEND)

# Render
bpy.ops.render.render(write_still=True)
print("SAVED_PNG", OUT_PNG)
print("DONE")
