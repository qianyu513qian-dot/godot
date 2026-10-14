"""Town center v3 — solid roofs via grid+displace+solidify; reliable materials; framed camera."""
import bpy
import bmesh
import math

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
scene.render.resolution_x = 1280
scene.render.resolution_y = 1280
scene.render.filepath = OUT_PNG
scene.render.image_settings.file_format = "PNG"

world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
nt = world.node_tree
nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (1.0, 0.82, 0.58, 1.0)
bg.inputs[1].default_value = 0.7
wo = nt.nodes.new("ShaderNodeOutputWorld")
nt.links.new(bg.outputs[0], wo.inputs[0])


def mat(name, col, rough=0.25, coat=0.85):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    l = m.node_tree.links
    n.clear()
    o = n.new("ShaderNodeOutputMaterial")
    b = n.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.08
    l.new(b.outputs[0], o.inputs[0])
    return m


M_WALL = mat("Wall", (0.96, 0.94, 0.90), 0.4, 0.35)
M_WOOD = mat("Wood", (0.50, 0.32, 0.16), 0.45, 0.25)
M_RED = mat("Red", (0.85, 0.08, 0.05), 0.16, 1.0)
M_BLUE = mat("Blue", (0.08, 0.30, 0.82), 0.16, 1.0)
M_GOLD = mat("Gold", (0.92, 0.72, 0.18), 0.2, 0.7)
M_STONE = mat("Stone", (0.60, 0.54, 0.45), 0.55, 0.15)
M_DOOR = mat("Door", (0.25, 0.14, 0.08), 0.4, 0.2)
M_GRASS = mat("Grass", (0.30, 0.55, 0.24), 0.8, 0.05)
M_DIRT = mat("Dirt", (0.68, 0.52, 0.35), 0.7, 0.05)


def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


def do_bevel(o, w=0.05, s=4):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("B", "BEVEL")
    md.width = w
    md.segments = s
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(25)
    bpy.ops.object.modifier_apply(modifier=md.name)


def make_box(name, loc, sx, sy, sz, material, bw=0.045):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_mat(o, material)
    do_bevel(o, bw, 4)
    return o


def make_roof(name, z0, size, rise, material, curl=0.5, segs=32):
    """Create hip roof: grid plane, sculpt Z, solidify, shade smooth."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=size, location=(0, 0, z0))
    o = bpy.context.active_object
    o.name = name
    # edit verts
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    hw = size * 0.5
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        t = max(abs(x), abs(y)) / hw  # 0 center .. 1 edge
        t = min(1.0, t)
        base = rise * (1.0 - 0.82 * t)
        edge = max(0.0, (t - 0.5) / 0.5)
        up = rise * curl * (edge ** 2.0)
        # gentle tile corrugation
        wave = 0.03 * math.sin((x / hw) * math.pi * 10) * (0.3 + 0.7 * t)
        v.co.z = base + up + wave
    bmesh.update_edit_mesh(o.data)
    bpy.ops.object.mode_set(mode="OBJECT")

    # solidify for thickness
    md = o.modifiers.new("Solid", "SOLIDIFY")
    md.thickness = max(0.08, rise * 0.14)
    md.offset = -1.0
    bpy.ops.object.modifier_apply(modifier=md.name)

    # slight smooth
    md = o.modifiers.new("Smooth", "SMOOTH")
    md.factor = 0.5
    md.iterations = 2
    bpy.ops.object.modifier_apply(modifier=md.name)

    set_mat(o, material)
    bpy.ops.object.shade_smooth()
    do_bevel(o, 0.02, 2)

    # tile ridge bars on top surface
    extras = []
    n_tiles = 14
    for i in range(1, n_tiles):
        # ridges parallel to X across Y
        yy = -hw + size * (i / n_tiles)
        t = abs(yy) / hw
        zz = z0 + rise * (1.0 - 0.82 * t) + rise * curl * (max(0, (t - 0.5) / 0.5) ** 2) + 0.04
        span = size * (0.92 - 0.1 * t)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=0.03, depth=span,
            location=(0, yy, zz), rotation=(0, math.pi / 2, 0),
        )
        c = bpy.context.active_object
        set_mat(c, material)
        extras.append(c)

    # corner curls spheres (gold)
    for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        x, y = sx * hw * 0.95, sy * hw * 0.95
        t = 0.95
        zz = z0 + rise * (1.0 - 0.82 * t) + rise * curl * ((t - 0.5) / 0.5) ** 2 + 0.06
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(x, y, zz), segments=12, ring_count=8)
        tip = bpy.context.active_object
        set_mat(tip, M_GOLD)
        extras.append(tip)

    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for e in extras:
        e.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    return o


# === Build ===
make_box("Plinth", (0, 0, 0.12), 3.6, 3.6, 0.24, M_STONE, 0.05)
make_box("Steps", (0, -1.95, 0.1), 1.4, 0.5, 0.2, M_STONE, 0.03)
make_box("Wall1", (0, 0, 0.95), 2.85, 2.85, 1.45, M_WALL, 0.06)
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    make_box(f"Post1_{sx}_{sy}", (sx * 1.32, sy * 1.32, 0.95), 0.24, 0.24, 1.5, M_WOOD, 0.045)
make_box("BeamF", (0, -1.32, 1.55), 2.85, 0.18, 0.18, M_WOOD, 0.03)
make_box("BeamB", (0, 1.32, 1.55), 2.85, 0.18, 0.18, M_WOOD, 0.03)
make_box("BeamL", (-1.32, 0, 1.55), 0.18, 2.85, 0.18, M_WOOD, 0.03)
make_box("BeamR", (1.32, 0, 1.55), 0.18, 2.85, 0.18, M_WOOD, 0.03)
make_box("Door", (0, -1.45, 0.7), 0.65, 0.08, 1.0, M_DOOR, 0.02)

# Tier 1 roof RED
make_roof("Roof1", 1.75, 4.0, 0.75, M_RED, curl=0.7, segs=36)

# Mid walls
make_box("Wall2", (0, 0, 2.7), 2.0, 2.0, 0.95, M_WALL, 0.05)
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    make_box(f"Post2_{sx}_{sy}", (sx * 0.92, sy * 0.92, 2.7), 0.18, 0.18, 1.0, M_WOOD, 0.035)

# Tier 2 BLUE
make_roof("Roof2", 3.25, 2.9, 0.62, M_BLUE, curl=0.75, segs=30)

# Top
make_box("Wall3", (0, 0, 4.0), 1.1, 1.1, 0.65, M_WALL, 0.04)
for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
    make_box(f"Post3_{sx}_{sy}", (sx * 0.5, sy * 0.5, 4.0), 0.12, 0.12, 0.7, M_WOOD, 0.025)

# Tier 3 RED
make_roof("Roof3", 4.4, 1.75, 0.48, M_RED, curl=0.8, segs=24)

# Apex gold
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, 0, 5.0), segments=20, ring_count=12)
set_mat(bpy.context.active_object, M_GOLD)
bpy.ops.mesh.primitive_cone_add(radius1=0.1, depth=0.25, location=(0, 0, 5.2))
set_mat(bpy.context.active_object, M_GOLD)

# Lanterns
for sx in (-1.25, 1.25):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.065, depth=0.13, location=(sx, -1.5, 1.95))
    set_mat(bpy.context.active_object, M_GOLD)

# Ground
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
g = bpy.context.active_object
g.name = "GrassPlane"
set_mat(g, M_GRASS)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=3.3, depth=0.04, location=(0, 0, 0.02))
set_mat(bpy.context.active_object, M_DIRT)

# Camera framed on full building (center of mass ~ z=2.5)
bpy.ops.object.camera_add(location=(6.5, -7.2, 4.2), rotation=(math.radians(62), 0, math.radians(42)))
cam = bpy.context.active_object
cam.data.lens = 55
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = 10.5
cam.data.dof.aperture_fstop = 2.8
scene.camera = cam

bpy.ops.object.light_add(type="SUN", location=(5, -3, 9))
sun = bpy.context.active_object
sun.data.energy = 4.8
sun.data.color = (1.0, 0.88, 0.58)
sun.rotation_euler = (math.radians(38), math.radians(8), math.radians(-28))
sun.data.angle = math.radians(5)

bpy.ops.object.light_add(type="AREA", location=(-3.5, 2.5, 3.5))
fill = bpy.context.active_object
fill.data.energy = 90
fill.data.color = (0.55, 0.68, 1.0)
fill.data.size = 4.5

bpy.ops.object.light_add(type="AREA", location=(2.5, -4.5, 2.2))
rim = bpy.context.active_object
rim.data.energy = 50
rim.data.color = (1.0, 0.55, 0.3)
rim.data.size = 2.2

scene.view_settings.view_transform = "Filmic"
scene.view_settings.look = "Medium High Contrast"
scene.view_settings.exposure = 0.15

try:
    p = bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type = "CUDA"
    for d in p.devices:
        d.use = True
except Exception:
    pass

# Verify roof materials
for o in bpy.data.objects:
    if o.type == "MESH" and o.name.startswith("Roof"):
        print("ROOF", o.name, "mats", [m.name for m in o.data.materials], "verts", len(o.data.vertices))

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("SAVED_BLEND")
bpy.ops.render.render(write_still=True)
print("SAVED_PNG")

# GLB: building only
for o in bpy.context.scene.objects:
    o.select_set(o.type == "MESH" and o.name != "GrassPlane" and max(o.dimensions) < 12)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True)
print("SAVED_GLB")
print("DONE")
