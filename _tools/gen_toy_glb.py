"""
Blender headless: generate stylized toy/clay East-Asian RTS assets as GLB.
Run: blender --background --python gen_toy_glb.py -- <out_dir>
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGV[0] if ARGV else os.path.join(os.path.dirname(__file__), "glb")
os.makedirs(OUT, exist_ok=True)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # ensure object mode clean
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

def mat(name, color, rough=0.28, clearcoat=0.45, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metallic
        # Blender 4.x: Coat
        if "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = clearcoat
            bsdf.inputs["Coat Roughness"].default_value = 0.22
        elif "Clearcoat" in bsdf.inputs:
            bsdf.inputs["Clearcoat"].default_value = clearcoat
            bsdf.inputs["Clearcoat Roughness"].default_value = 0.22
    return m

def link(obj):
    if obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(obj)

def bevel_obj(obj, width=0.08, segments=3):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(30)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)

def shade_smooth(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.select_set(False)

def add_box(size, loc, material, name="Box", bevel=0.1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if material:
        obj.data.materials.append(material)
    if bevel > 0:
        bevel_obj(obj, bevel, 4)
    shade_smooth(obj)
    return obj

def add_cyl(r_top, r_bot, depth, loc, material, name="Cyl", verts=24):
    bpy.ops.mesh.primitive_cone_add(radius1=r_bot, radius2=r_top, depth=depth, location=loc, vertices=verts)
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    bevel_obj(obj, min(r_bot, r_top) * 0.15, 3)
    shade_smooth(obj)
    return obj

def add_uv_sphere(radius, loc, material, name="Sph", segments=32, rings=16, displace=0.0, seed=1):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=segments, ring_count=rings)
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    if displace > 0:
        # displace via bmesh noise-ish
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for v in bm.verts:
            n = v.normal
            # deterministic-ish noise
            f = math.sin(v.co.x * 3.1 + seed) * math.cos(v.co.y * 2.7 + seed * 0.5) * math.sin(v.co.z * 2.3)
            v.co += n * (f * displace * radius)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    shade_smooth(obj)
    return obj

def add_capsule(radius, height, loc, material, name="Cap"):
    # approximate: cylinder + two spheres
    objs = []
    cyl_h = max(height - 2 * radius, 0.05)
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=cyl_h, location=(loc[0], loc[1], loc[2]), vertices=20)
    c = bpy.context.active_object
    c.name = name + "_body"
    if material:
        c.data.materials.append(material)
    shade_smooth(c)
    objs.append(c)
    for zsgn, sname in ((1, "_head"), (-1, "_foot")):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(loc[0], loc[1], loc[2] + zsgn * cyl_h * 0.5), segments=20, ring_count=10)
        s = bpy.context.active_object
        s.name = name + sname
        if material:
            s.data.materials.append(material)
        shade_smooth(s)
        objs.append(s)
    # join
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    bevel_obj(joined, radius * 0.08, 2)
    return joined

def make_pagoda_roof(width, depth, height, curl, color, name, tile_rows=8):
    """Build curved hip roof with visible rounded tile ridges via curve loft + tiles."""
    m_roof = mat(name + "_mat", color, rough=0.24, clearcoat=0.5)
    # Base soft box for mass
    roof = add_box((width, depth, height * 0.35), (0, 0, height * 0.15), m_roof, name + "_mass", bevel=min(width, depth) * 0.08)
    # Tile rows: cylinders along X, scaled, on both slopes
    tiles = []
    for side in (-1, 1):
        for i in range(tile_rows):
            t = (i + 0.5) / tile_rows
            # slope from ridge to eave
            z = height * (1.0 - t * 0.85) + (curl * max(0, t - 0.7) ** 2)
            y = side * (depth * 0.5 * t * 0.95)
            x_span = width * (0.55 + 0.45 * t)
            bpy.ops.mesh.primitive_cylinder_add(
                radius=height * 0.07,
                depth=x_span,
                location=(0, y, z),
                vertices=12,
            )
            tile = bpy.context.active_object
            tile.name = f"{name}_tile_{side}_{i}"
            tile.rotation_euler = (0, math.radians(90), 0)
            # tip up at eaves
            tip = math.radians(12 * max(0, t - 0.55) / 0.45)
            tile.rotation_euler[0] = -side * tip
            tile.data.materials.append(m_roof)
            shade_smooth(tile)
            tiles.append(tile)
    # Ridge beam
    bpy.ops.mesh.primitive_cylinder_add(radius=height * 0.09, depth=width * 0.55, location=(0, 0, height * 0.95), vertices=14)
    ridge = bpy.context.active_object
    ridge.name = name + "_ridge"
    ridge.rotation_euler = (0, math.radians(90), 0)
    ridge.data.materials.append(mat(name + "_gold", (0.95, 0.78, 0.28), 0.22, 0.55))
    shade_smooth(ridge)
    tiles.append(ridge)
    # Join all roof parts
    bpy.ops.object.select_all(action="DESELECT")
    roof.select_set(True)
    for o in tiles:
        o.select_set(True)
    bpy.context.view_layer.objects.active = roof
    bpy.ops.object.join()
    roof.name = name
    # Lattice-ish upward eave: proportional edit via bmesh on outer verts
    bm = bmesh.new()
    bm.from_mesh(roof.data)
    for v in bm.verts:
        # lift corners (upturned eaves)
        ax = abs(v.co.x) / max(width * 0.5, 1e-3)
        ay = abs(v.co.y) / max(depth * 0.5, 1e-3)
        edge = max(ax, ay)
        if edge > 0.75 and v.co.z > height * 0.2:
            v.co.z += curl * ((edge - 0.75) / 0.25) ** 2
    bm.to_mesh(roof.data)
    bm.free()
    roof.data.update()
    shade_smooth(roof)
    return roof

def export_glb(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        if o and o.name in bpy.data.objects:
            bpy.data.objects[o.name].select_set(True)
            bpy.context.view_layer.objects.active = bpy.data.objects[o.name]
    # If joined already, select by name list of Object/str
    names = []
    for o in objects:
        names.append(o if isinstance(o, str) else o.name)
    bpy.ops.object.select_all(action="DESELECT")
    for n in names:
        if n in bpy.data.objects:
            bpy.data.objects[n].select_set(True)
            bpy.context.view_layer.objects.active = bpy.data.objects[n]
    bpy.ops.export_scene.gltf(
        filepath=path,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    print("EXPORT", path)

def build_town_center():
    reset()
    plaster = mat("plaster", (0.96, 0.94, 0.90), 0.32, 0.35)
    wood = mat("wood", (0.78, 0.52, 0.30), 0.40, 0.25)
    stone = mat("stone", (0.82, 0.76, 0.64), 0.45, 0.2)
    blue = (0.14, 0.38, 0.95)
    red = (0.95, 0.14, 0.12)
    # podium
    add_cyl(3.2, 3.4, 0.55, (0, 0, 0.28), stone, "podium", 32)
    add_cyl(2.9, 3.0, 0.32, (0, 0, 0.70), wood, "podium2", 28)
    # hall
    hall = add_box((4.4, 3.2, 2.8), (0, 0, 2.2), plaster, "hall", bevel=0.18)
    # beams
    add_box((4.7, 3.5, 0.28), (0, 0, 1.0), wood, "beam_lo", 0.08)
    add_box((4.7, 3.5, 0.24), (0, 0, 3.4), wood, "beam_hi", 0.08)
    # columns
    for x in (-1.4, 1.4):
        for y in (-1.0, 1.0):
            add_cyl(0.28, 0.32, 2.6, (x, y, 2.1), wood, f"col_{x}_{y}", 16)
    # wings
    add_box((1.8, 2.6, 1.8), (-3.0, 0, 1.8), plaster, "wing_l", 0.14)
    add_box((1.8, 2.6, 1.8), (3.0, 0, 1.8), plaster, "wing_r", 0.14)
    # roofs
    r1 = make_pagoda_roof(7.2, 5.4, 1.8, 0.55, blue, "roof_blue", tile_rows=9)
    r1.location.z = 3.6
    r2 = make_pagoda_roof(4.6, 3.4, 1.2, 0.4, red, "roof_red", tile_rows=7)
    r2.location.z = 5.0
    r3 = make_pagoda_roof(2.6, 3.2, 0.85, 0.28, blue, "roof_wing_l", 5)
    r3.location = (-3.0, 0, 2.9)
    r4 = make_pagoda_roof(2.6, 3.2, 0.85, 0.28, red, "roof_wing_r", 5)
    r4.location = (3.0, 0, 2.9)
    # join everything into one TC
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    tc = bpy.context.active_object
    tc.name = "TownCenter"
    # normalize: bottom at z=0, center xz
    bbox = [tc.matrix_world @ Vector(c) for c in tc.bound_box]
    min_z = min(v.z for v in bbox)
    cx = sum(v.x for v in bbox) / 8
    cy = sum(v.y for v in bbox) / 8
    tc.location.z -= min_z
    tc.location.x -= cx
    tc.location.y -= cy
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    export_glb(os.path.join(OUT, "town_center.glb"), [tc])

def build_house():
    reset()
    plaster = mat("plaster", (0.97, 0.95, 0.91), 0.3, 0.35)
    wood = mat("wood", (0.72, 0.48, 0.28), 0.4, 0.25)
    red = (0.95, 0.16, 0.12)
    blue = (0.14, 0.38, 0.95)
    add_cyl(2.2, 2.3, 0.28, (0, 0, 0.14), mat("stone", (0.8, 0.74, 0.62)), "base", 28)
    add_box((3.6, 3.2, 2.2), (0, 0, 1.3), plaster, "body", 0.16)
    add_box((3.8, 3.4, 0.2), (0, 0, 0.45), wood, "beam1", 0.06)
    add_box((3.8, 3.4, 0.18), (0, 0, 2.2), wood, "beam2", 0.06)
    add_box((0.7, 0.15, 1.2), (0, 1.55, 0.9), wood, "door", 0.05)
    r1 = make_pagoda_roof(4.6, 4.2, 1.5, 0.45, red, "hroof", 8)
    r1.location.z = 2.5
    r2 = make_pagoda_roof(2.8, 2.6, 0.7, 0.22, blue, "hroof2", 5)
    r2.location.z = 3.6
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "House"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "house.glb"), [o])

def build_tower():
    reset()
    plaster = mat("plaster", (0.95, 0.93, 0.88), 0.32, 0.3)
    wood = mat("wood", (0.7, 0.46, 0.28), 0.4, 0.25)
    blue = (0.14, 0.38, 0.95)
    add_cyl(1.55, 1.65, 0.35, (0, 0, 0.18), mat("stone", (0.8, 0.75, 0.65)), "base", 24)
    add_cyl(1.15, 1.25, 3.8, (0, 0, 2.2), plaster, "shaft", 24)
    add_box((2.6, 2.6, 0.25), (0, 0, 4.2), wood, "deck", 0.08)
    for x in (-0.9, 0, 0.9):
        for y in (-0.9, 0.9):
            if abs(x) < 0.1 and abs(y) < 0.1:
                continue
            add_cyl(0.18, 0.2, 0.55, (x, y, 4.5), wood, f"bat_{x}_{y}", 12)
    r = make_pagoda_roof(2.8, 2.8, 1.1, 0.35, blue, "troof", 6)
    r.location.z = 4.85
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "ArrowTower"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "arrow_tower.glb"), [o])

def build_barracks():
    reset()
    plaster = mat("plaster", (0.96, 0.90, 0.84), 0.3, 0.35)
    wood = mat("wood", (0.68, 0.42, 0.24), 0.4, 0.25)
    red = (0.93, 0.14, 0.12)
    add_cyl(2.6, 2.7, 0.28, (0, 0, 0.14), mat("stone", (0.76, 0.68, 0.56)), "base", 28)
    add_box((4.4, 4.0, 2.4), (0, 0, 1.4), plaster, "body", 0.16)
    add_box((0.7, 2.2, 1.8), (-2.0, 0, 1.2), wood, "rack", 0.08)
    r = make_pagoda_roof(5.4, 5.0, 1.6, 0.42, red, "broof", 8)
    r.location.z = 2.75
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Barracks"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "barracks.glb"), [o])

def build_gate():
    reset()
    plaster = mat("plaster", (0.95, 0.93, 0.88), 0.32, 0.3)
    stone = mat("stone", (0.82, 0.76, 0.66), 0.42, 0.2)
    wood = mat("wood", (0.92, 0.55, 0.24), 0.3, 0.35)
    red = (0.93, 0.16, 0.12)
    add_box((1.4, 2.0, 4.0), (-2.0, 0, 2.0), plaster, "tl", 0.14)
    add_box((1.4, 2.0, 4.0), (2.0, 0, 2.0), plaster, "tr", 0.14)
    add_cyl(0.85, 0.95, 4.0, (-2.0, 0, 2.0), stone, "tcl", 20)
    add_cyl(0.85, 0.95, 4.0, (2.0, 0, 2.0), stone, "tcr", 20)
    add_box((2.8, 1.6, 1.0), (0, 0, 3.5), wood, "lintel", 0.1)
    add_box((1.1, 0.35, 2.6), (-0.55, 0, 1.5), wood, "door_l", 0.08)
    add_box((1.1, 0.35, 2.6), (0.55, 0, 1.5), wood, "door_r", 0.08)
    r = make_pagoda_roof(5.2, 2.8, 1.0, 0.32, red, "groof", 6)
    r.location.z = 4.3
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Gate"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "gate.glb"), [o])

def build_wall():
    reset()
    plaster = mat("plaster", (0.94, 0.92, 0.88), 0.35, 0.25)
    stone = mat("stone", (0.84, 0.8, 0.72), 0.45, 0.2)
    add_box((5.8, 1.0, 2.6), (0, 0, 1.3), plaster, "wall", 0.12)
    add_box((6.0, 1.15, 0.3), (0, 0, 0.2), stone, "base", 0.08)
    for i in range(4):
        x = -2.2 + i * 1.45
        add_cyl(0.28, 0.3, 0.7, (x, 0, 2.9), stone, f"merlon_{i}", 12)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Wall"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "wall.glb"), [o])

def build_candy_tree():
    reset()
    trunk_m = mat("trunk", (0.72, 0.48, 0.28), 0.45, 0.2)
    add_cyl(0.28, 0.48, 3.0, (0, 0, 1.5), trunk_m, "trunk", 20)
    add_cyl(0.4, 0.55, 0.45, (0, 0, 0.25), trunk_m, "flare", 18)
    colors = [
        (0.96, 0.42, 0.72),
        (0.70, 0.40, 0.96),
        (1.0, 0.55, 0.26),
        (0.98, 0.62, 0.80),
        (0.55, 0.78, 0.38),
        (0.92, 0.35, 0.55),
    ]
    offsets = [
        (0, 0, 4.1), (0.95, 0.4, 3.5), (-0.9, -0.35, 3.55),
        (0.25, 0.95, 3.25), (-0.4, 0.75, 3.8), (0.55, -0.7, 3.6),
    ]
    radii = [1.85, 1.35, 1.3, 1.15, 1.2, 1.1]
    for i, (col, off, rad) in enumerate(zip(colors, offsets, radii)):
        cm = mat(f"candy_{i}", col, 0.30, 0.45)
        add_uv_sphere(rad, off, cm, f"canopy_{i}", 28, 14, displace=0.18, seed=i + 2)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "CandyTree"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "candy_tree.glb"), [o])

def build_gold():
    reset()
    g = mat("gold", (1.0, 0.82, 0.22), 0.22, 0.5, metallic=0.4)
    add_uv_sphere(1.1, (0, 0, 0.9), g, "g1", 24, 12, 0.08, 1)
    add_uv_sphere(0.6, (0.75, -0.3, 0.5), g, "g2", 18, 10, 0.06, 2)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Gold"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "gold.glb"), [o])

def build_stone():
    reset()
    s = mat("stone", (0.72, 0.70, 0.68), 0.4, 0.2)
    add_uv_sphere(1.15, (0, 0, 0.9), s, "s1", 22, 12, 0.12, 3)
    add_uv_sphere(0.7, (0.85, 0.3, 0.55), s, "s2", 16, 10, 0.1, 4)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Stone"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "stone.glb"), [o])

def build_villager():
    reset()
    cloth = mat("cloth", (0.28, 0.58, 0.95), 0.28, 0.4)
    skin = mat("skin", (0.97, 0.80, 0.64), 0.35, 0.25)
    pants = mat("pants", (0.38, 0.40, 0.50), 0.35, 0.25)
    hat = mat("hat", (0.96, 0.74, 0.30), 0.28, 0.4)
    # Blender Z-up: characters standing on Z
    add_capsule(0.11, 0.48, (-0.13, 0, 0.26), pants, "leg_l")
    add_capsule(0.11, 0.48, (0.13, 0, 0.26), pants, "leg_r")
    add_capsule(0.30, 0.72, (0, 0, 0.78), cloth, "torso")
    add_capsule(0.08, 0.40, (-0.34, 0, 0.78), cloth, "arm_l")
    add_capsule(0.08, 0.40, (0.34, 0, 0.78), cloth, "arm_r")
    add_uv_sphere(0.24, (0, 0, 1.30), skin, "head", 20, 12, 0.02, 1)
    add_cyl(0.04, 0.40, 0.18, (0, 0, 1.52), hat, "hat", 16)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Villager"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "villager.glb"), [o])

def build_soldier(kind="player"):
    reset()
    if kind == "zombie":
        body_c, helm_c = (0.45, 0.75, 0.38), (0.58, 0.65, 0.40)
        name = "Zombie"
    elif kind == "enemy":
        body_c, helm_c = (1.0, 0.28, 0.90), (1.0, 0.90, 0.28)
        name = "Enemy"
    else:
        body_c, helm_c = (0.90, 0.28, 0.22), (0.78, 0.82, 0.90)
        name = "Soldier"
    body = mat("body", body_c, 0.28, 0.4)
    helm = mat("helm", helm_c, 0.28, 0.4)
    h = 1.3
    add_capsule(0.40, h, (0, 0, h * 0.5), body, "body")
    add_uv_sphere(0.32, (0, 0, h + 0.1), helm, "helm", 20, 12, 0.03, 5)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, f"{name.lower()}.glb"), [o])

def build_relay():
    reset()
    wood = mat("wood", (0.72, 0.5, 0.3), 0.4, 0.25)
    cloth = mat("cloth", (0.96, 0.58, 0.24), 0.3, 0.4)
    stone = mat("stone", (0.8, 0.74, 0.6), 0.45, 0.2)
    add_cyl(1.7, 1.8, 0.22, (0, 0, 0.11), stone, "base", 24)
    add_cyl(0.32, 0.38, 3.0, (0, 0, 1.6), wood, "pole", 16)
    add_cyl(1.3, 1.35, 0.22, (0, 0, 2.0), wood, "plat", 20)
    add_cyl(0.38, 0.22, 0.55, (0, 0, 3.0), cloth, "lamp", 16)
    add_uv_sphere(0.35, (0, 0, 3.45), mat("glow", (1.0, 0.9, 0.38), 0.2, 0.55), "bulb", 16, 10, 0.02, 1)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Relay"
    bbox = [o.matrix_world @ Vector(c) for c in o.bound_box]
    o.location.z -= min(v.z for v in bbox)
    bpy.ops.object.transform_apply(location=True)
    export_glb(os.path.join(OUT, "relay.glb"), [o])

def main():
    print("OUTDIR", OUT)
    build_town_center()
    build_house()
    build_tower()
    build_barracks()
    build_gate()
    build_wall()
    build_relay()
    build_candy_tree()
    build_gold()
    build_stone()
    build_villager()
    build_soldier("player")
    build_soldier("enemy")
    build_soldier("zombie")
    print("ALL GLB DONE")

if __name__ == "__main__":
    main()
