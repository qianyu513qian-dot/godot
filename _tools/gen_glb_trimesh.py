#!/usr/bin/env python3
"""Generate stylized toy/clay East-Asian RTS GLB assets with trimesh (real .glb files)."""
from __future__ import annotations
import math
import os
from pathlib import Path
import numpy as np
import trimesh
from trimesh.creation import box, cylinder, icosphere

def capsule(radius=0.5, height=2.0):
    # trimesh capsule height is cylinder portion + caps; approx total height
    cyl_h = max(height - 2*radius, 0.05)
    return __import__('trimesh').creation.capsule(height=cyl_h, radius=radius, count=[12, 12])

OUT = Path(os.environ.get("AOE_GLB_OUT", r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models"))
OUT.mkdir(parents=True, exist_ok=True)

def rgba(c, a=255):
    r, g, b = c
    return np.array([int(r*255), int(g*255), int(b*255), a], dtype=np.uint8)

def paint(mesh: trimesh.Trimesh, color) -> trimesh.Trimesh:
    mesh = mesh.copy()
    mesh.visual.vertex_colors = rgba(color)
    return mesh

def bevel_box(extents, bevel=None, pitch=0.08):
    """Rounded box via sphere-swept approximation: box inflated + smoothed subdiv."""
    mesh = box(extents=extents)
    if bevel is None:
        bevel = min(extents) * 0.22
    # Subdivide then push vertices near edges outward (soft round)
    for _ in range(2):
        mesh = mesh.subdivide()
    v = mesh.vertices.copy()
    hx, hy, hz = np.array(extents) * 0.5
    # Soften: move vertices toward inscribed rounded cube
    # Clamp to rounded box SDF-ish remapping
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    # shrink flat region
    ix, iy, iz = max(hx - bevel, 0.01), max(hy - bevel, 0.01), max(hz - bevel, 0.01)
    # For each axis, if beyond inner, treat as sphere/cyl corner
    ax = np.clip(np.abs(x), 0, ix)
    ay = np.clip(np.abs(y), 0, iy)
    az = np.clip(np.abs(z), 0, iz)
    # excess toward corner
    ex = np.abs(x) - ix
    ey = np.abs(y) - iy
    ez = np.abs(z) - iz
    ex = np.maximum(ex, 0)
    ey = np.maximum(ey, 0)
    ez = np.maximum(ez, 0)
    # reproject excess onto sphere of radius bevel
    elen = np.sqrt(ex*ex + ey*ey + ez*ez) + 1e-9
    scale = np.where(elen > 1e-8, bevel / elen, 1.0)
    # only round where at least one excess
    mask = (ex + ey + ez) > 1e-8
    nx = np.sign(x) * (ix + ex * scale)
    ny = np.sign(y) * (iy + ey * scale)
    nz = np.sign(z) * (iz + ez * scale)
    v2 = v.copy()
    v2[mask, 0] = nx[mask]
    v2[mask, 1] = ny[mask]
    v2[mask, 2] = nz[mask]
    mesh.vertices = v2
    try:
        mesh.update_faces(mesh.unique_faces())
    except Exception:
        pass
    mesh.remove_unreferenced_vertices()
    try:
        trimesh.smoothing.filter_taubin(mesh, iterations=5)
    except Exception:
        pass
    return mesh

def soft_sphere(radius, subdiv=3, noise=0.14, seed=1):
    mesh = icosphere(subdivisions=subdiv, radius=radius)
    v = mesh.vertices.copy()
    rng = np.random.default_rng(seed)
    # smooth noise via sin fields (deterministic)
    nse = (
        np.sin(v[:, 0] * 3.1 + seed) * np.cos(v[:, 1] * 2.7 + seed * 0.5) * np.sin(v[:, 2] * 2.3)
        + 0.35 * np.sin(v[:, 1] * 5.2 - v[:, 2] * 3.1)
    )
    n = mesh.vertex_normals
    mesh.vertices = v + n * (nse[:, None] * noise * radius)
    try:
        trimesh.smoothing.filter_taubin(mesh, iterations=3)
    except Exception:
        pass
    return mesh

def taper_cyl(r_bot, r_top, height, sections=24):
    mesh = cylinder(radius=r_bot, height=height, sections=sections)
    # scale top ring
    v = mesh.vertices
    z = v[:, 2]
    zmax, zmin = z.max(), z.min()
    t = (z - zmin) / max(zmax - zmin, 1e-9)
    scale = r_bot + (r_top - r_bot) * t
    # current radius in xy
    rad = np.sqrt(v[:, 0]**2 + v[:, 1]**2) + 1e-9
    factor = scale / np.maximum(rad, 1e-6)
    # only scale side verts (not exactly on axis)
    v2 = v.copy()
    v2[:, 0] *= factor
    v2[:, 1] *= factor
    mesh.vertices = v2
    return mesh

def pagoda_roof(width, depth, height, curl=0.45, ridges=10, color=(0.14, 0.38, 0.95)):
    """Curved hip roof + cylindrical tile rows — real multi-part mesh."""
    parts = []
    # base mass (beveled thin box as fill)
    mass = bevel_box((width * 0.92, depth * 0.92, height * 0.28), bevel=min(width, depth) * 0.06)
    mass.apply_translation([0, 0, height * 0.12])
    parts.append(paint(mass, color))
    # tile cylinders
    for side in (-1.0, 1.0):
        for i in range(ridges):
            t = (i + 0.5) / ridges
            z = height * (1.0 - t * 0.82) + curl * max(0.0, t - 0.65) ** 2
            y = side * (depth * 0.48 * t)
            x_span = width * (0.5 + 0.48 * t)
            tile = cylinder(radius=height * 0.065, height=x_span, sections=12)
            # rotate to lie along X
            T = trimesh.transformations.rotation_matrix(math.pi / 2, [0, 1, 0])
            tile.apply_transform(T)
            tip = math.radians(14 * max(0.0, t - 0.55) / 0.45)
            T2 = trimesh.transformations.rotation_matrix(-side * tip, [1, 0, 0])
            tile.apply_transform(T2)
            tile.apply_translation([0, y, z])
            parts.append(paint(tile, color))
    # ridge
    ridge = cylinder(radius=height * 0.08, height=width * 0.55, sections=14)
    ridge.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [0, 1, 0]))
    ridge.apply_translation([0, 0, height * 0.92])
    parts.append(paint(ridge, (0.95, 0.78, 0.28)))
    # finial
    fin = soft_sphere(height * 0.12, 2, 0.05, 9)
    fin.apply_translation([0, 0, height * 1.02])
    parts.append(paint(fin, (0.95, 0.78, 0.28)))
    roof = trimesh.util.concatenate(parts)
    # eave upturn sculpt
    v = roof.vertices.copy()
    ax = np.abs(v[:, 0]) / max(width * 0.5, 1e-3)
    ay = np.abs(v[:, 1]) / max(depth * 0.5, 1e-3)
    edge = np.maximum(ax, ay)
    lift = np.where((edge > 0.72) & (v[:, 2] > height * 0.15),
                    curl * ((edge - 0.72) / 0.28) ** 2, 0.0)
    v[:, 2] += lift
    roof.vertices = v
    return roof

def ground_z0(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    mesh = mesh.copy()
    mesh.apply_translation([0, 0, -mesh.bounds[0, 2]])
    # center xz
    c = mesh.centroid
    mesh.apply_translation([-c[0], -c[1], 0])
    return mesh

def export(name: str, mesh: trimesh.Trimesh):
    mesh = ground_z0(mesh)
    path = OUT / f"{name}.glb"
    mesh.export(path, file_type="glb")
    print("Wrote", path, "verts", len(mesh.vertices), "faces", len(mesh.faces))

def town_center():
    plaster = (0.96, 0.94, 0.90)
    wood = (0.78, 0.52, 0.30)
    stone = (0.82, 0.76, 0.64)
    blue = (0.14, 0.38, 0.95)
    red = (0.95, 0.14, 0.12)
    parts = []
    p = taper_cyl(3.4, 3.2, 0.55, 32); p.apply_translation([0, 0, 0.28]); parts.append(paint(p, stone))
    p = taper_cyl(3.0, 2.9, 0.32, 28); p.apply_translation([0, 0, 0.70]); parts.append(paint(p, wood))
    p = bevel_box((4.4, 3.2, 2.8), 0.2); p.apply_translation([0, 0, 2.2]); parts.append(paint(p, plaster))
    p = bevel_box((4.7, 3.5, 0.28), 0.08); p.apply_translation([0, 0, 1.0]); parts.append(paint(p, wood))
    p = bevel_box((4.7, 3.5, 0.24), 0.08); p.apply_translation([0, 0, 3.4]); parts.append(paint(p, wood))
    for x in (-1.4, 1.4):
        for y in (-1.0, 1.0):
            c = taper_cyl(0.32, 0.28, 2.6, 16); c.apply_translation([x, y, 2.1]); parts.append(paint(c, wood))
    p = bevel_box((1.8, 2.6, 1.8), 0.14); p.apply_translation([-3.0, 0, 1.8]); parts.append(paint(p, plaster))
    p = bevel_box((1.8, 2.6, 1.8), 0.14); p.apply_translation([3.0, 0, 1.8]); parts.append(paint(p, plaster))
    r = pagoda_roof(7.2, 5.4, 1.9, 0.55, 10, blue); r.apply_translation([0, 0, 3.55]); parts.append(r)
    r = pagoda_roof(4.8, 3.5, 1.35, 0.42, 8, red); r.apply_translation([0, 0, 5.05]); parts.append(r)
    r = pagoda_roof(2.7, 3.3, 0.9, 0.3, 6, blue); r.apply_translation([-3.0, 0, 2.85]); parts.append(r)
    r = pagoda_roof(2.7, 3.3, 0.9, 0.3, 6, red); r.apply_translation([3.0, 0, 2.85]); parts.append(r)
    export("town_center", trimesh.util.concatenate(parts))

def house():
    plaster, wood = (0.97, 0.95, 0.91), (0.72, 0.48, 0.28)
    red, blue = (0.95, 0.16, 0.12), (0.14, 0.38, 0.95)
    parts = []
    p = taper_cyl(2.3, 2.2, 0.28, 28); p.apply_translation([0, 0, 0.14]); parts.append(paint(p, (0.8, 0.74, 0.62)))
    p = bevel_box((3.6, 3.2, 2.2), 0.16); p.apply_translation([0, 0, 1.3]); parts.append(paint(p, plaster))
    p = bevel_box((3.8, 3.4, 0.2), 0.06); p.apply_translation([0, 0, 0.45]); parts.append(paint(p, wood))
    p = bevel_box((3.8, 3.4, 0.18), 0.06); p.apply_translation([0, 0, 2.2]); parts.append(paint(p, wood))
    p = bevel_box((0.7, 0.15, 1.2), 0.05); p.apply_translation([0, 1.55, 0.9]); parts.append(paint(p, wood))
    r = pagoda_roof(4.8, 4.3, 1.6, 0.48, 9, red); r.apply_translation([0, 0, 2.45]); parts.append(r)
    r = pagoda_roof(2.9, 2.7, 0.75, 0.24, 5, blue); r.apply_translation([0, 0, 3.65]); parts.append(r)
    export("house", trimesh.util.concatenate(parts))

def arrow_tower():
    plaster, wood, blue = (0.95, 0.93, 0.88), (0.7, 0.46, 0.28), (0.14, 0.38, 0.95)
    parts = []
    p = taper_cyl(1.65, 1.55, 0.35, 24); p.apply_translation([0, 0, 0.18]); parts.append(paint(p, (0.8, 0.75, 0.65)))
    p = taper_cyl(1.25, 1.15, 3.8, 24); p.apply_translation([0, 0, 2.2]); parts.append(paint(p, plaster))
    p = bevel_box((2.6, 2.6, 0.25), 0.08); p.apply_translation([0, 0, 4.2]); parts.append(paint(p, wood))
    for x in (-0.9, 0.0, 0.9):
        for y in (-0.9, 0.9):
            if abs(x) < 0.05 and abs(y) < 0.05: continue
            c = taper_cyl(0.2, 0.18, 0.55, 12); c.apply_translation([x, y, 4.5]); parts.append(paint(c, wood))
    r = pagoda_roof(2.9, 2.9, 1.15, 0.36, 7, blue); r.apply_translation([0, 0, 4.85]); parts.append(r)
    export("arrow_tower", trimesh.util.concatenate(parts))

def barracks():
    plaster, wood, red = (0.96, 0.90, 0.84), (0.68, 0.42, 0.24), (0.93, 0.14, 0.12)
    parts = []
    p = taper_cyl(2.7, 2.6, 0.28, 28); p.apply_translation([0, 0, 0.14]); parts.append(paint(p, (0.76, 0.68, 0.56)))
    p = bevel_box((4.4, 4.0, 2.4), 0.16); p.apply_translation([0, 0, 1.4]); parts.append(paint(p, plaster))
    p = bevel_box((0.7, 2.2, 1.8), 0.08); p.apply_translation([-2.0, 0, 1.2]); parts.append(paint(p, wood))
    r = pagoda_roof(5.5, 5.1, 1.7, 0.45, 9, red); r.apply_translation([0, 0, 2.7]); parts.append(r)
    export("barracks", trimesh.util.concatenate(parts))

def gate():
    plaster, stone, wood, red = (0.95, 0.93, 0.88), (0.82, 0.76, 0.66), (0.92, 0.55, 0.24), (0.93, 0.16, 0.12)
    parts = []
    for x in (-2.0, 2.0):
        p = bevel_box((1.4, 2.0, 4.0), 0.14); p.apply_translation([x, 0, 2.0]); parts.append(paint(p, plaster))
        c = taper_cyl(0.95, 0.85, 4.0, 20); c.apply_translation([x, 0, 2.0]); parts.append(paint(c, stone))
    p = bevel_box((2.8, 1.6, 1.0), 0.1); p.apply_translation([0, 0, 3.5]); parts.append(paint(p, wood))
    p = bevel_box((1.1, 0.35, 2.6), 0.08); p.apply_translation([-0.55, 0, 1.5]); parts.append(paint(p, wood))
    p = bevel_box((1.1, 0.35, 2.6), 0.08); p.apply_translation([0.55, 0, 1.5]); parts.append(paint(p, wood))
    r = pagoda_roof(5.3, 2.9, 1.05, 0.34, 7, red); r.apply_translation([0, 0, 4.3]); parts.append(r)
    export("gate", trimesh.util.concatenate(parts))

def wall():
    plaster, stone = (0.94, 0.92, 0.88), (0.84, 0.8, 0.72)
    parts = []
    p = bevel_box((5.8, 1.0, 2.6), 0.12); p.apply_translation([0, 0, 1.3]); parts.append(paint(p, plaster))
    p = bevel_box((6.0, 1.15, 0.3), 0.08); p.apply_translation([0, 0, 0.2]); parts.append(paint(p, stone))
    for i in range(4):
        x = -2.2 + i * 1.45
        c = taper_cyl(0.3, 0.28, 0.7, 12); c.apply_translation([x, 0, 2.9]); parts.append(paint(c, stone))
    export("wall", trimesh.util.concatenate(parts))

def relay():
    wood, cloth, stone = (0.72, 0.5, 0.3), (0.96, 0.58, 0.24), (0.8, 0.74, 0.6)
    parts = []
    p = taper_cyl(1.8, 1.7, 0.22, 24); p.apply_translation([0, 0, 0.11]); parts.append(paint(p, stone))
    p = taper_cyl(0.38, 0.32, 3.0, 16); p.apply_translation([0, 0, 1.6]); parts.append(paint(p, wood))
    p = taper_cyl(1.35, 1.3, 0.22, 20); p.apply_translation([0, 0, 2.0]); parts.append(paint(p, wood))
    p = taper_cyl(0.22, 0.38, 0.55, 16); p.apply_translation([0, 0, 3.0]); parts.append(paint(p, cloth))
    s = soft_sphere(0.35, 2, 0.04, 1); s.apply_translation([0, 0, 3.45]); parts.append(paint(s, (1.0, 0.9, 0.38)))
    export("relay", trimesh.util.concatenate(parts))

def candy_tree():
    trunk = (0.72, 0.48, 0.28)
    parts = []
    p = taper_cyl(0.48, 0.28, 3.0, 20); p.apply_translation([0, 0, 1.5]); parts.append(paint(p, trunk))
    p = taper_cyl(0.55, 0.4, 0.45, 18); p.apply_translation([0, 0, 0.25]); parts.append(paint(p, trunk))
    colors = [(0.96,0.42,0.72),(0.70,0.40,0.96),(1.0,0.55,0.26),(0.98,0.62,0.80),(0.55,0.78,0.38),(0.92,0.35,0.55)]
    offsets = [(0,0,4.1),(0.95,0.4,3.5),(-0.9,-0.35,3.55),(0.25,0.95,3.25),(-0.4,0.75,3.8),(0.55,-0.7,3.6)]
    radii = [1.9, 1.4, 1.35, 1.2, 1.25, 1.15]
    for i,(c,o,r) in enumerate(zip(colors, offsets, radii)):
        s = soft_sphere(r, 3, 0.18, i+2); s.apply_translation(list(o)); parts.append(paint(s, c))
    export("candy_tree", trimesh.util.concatenate(parts))

def gold():
    g = (1.0, 0.82, 0.22)
    parts = []
    s = soft_sphere(1.1, 3, 0.08, 1); s.apply_translation([0,0,0.9]); parts.append(paint(s, g))
    s = soft_sphere(0.6, 2, 0.06, 2); s.apply_translation([0.75,-0.3,0.5]); parts.append(paint(s, g))
    export("gold", trimesh.util.concatenate(parts))

def stone():
    col = (0.72, 0.70, 0.68)
    parts = []
    s = soft_sphere(1.15, 3, 0.12, 3); s.apply_translation([0,0,0.9]); parts.append(paint(s, col))
    s = soft_sphere(0.7, 2, 0.1, 4); s.apply_translation([0.85,0.3,0.55]); parts.append(paint(s, col))
    export("stone", trimesh.util.concatenate(parts))

def villager():
    cloth, skin, pants, hatc = (0.28,0.58,0.95), (0.97,0.80,0.64), (0.38,0.40,0.50), (0.96,0.74,0.30)
    parts = []
    for x in (-0.13, 0.13):
        p = capsule(radius=0.11, height=0.48); p.apply_translation([x, 0, 0.26]); parts.append(paint(p, pants))
    p = capsule(radius=0.30, height=0.72); p.apply_translation([0, 0, 0.78]); parts.append(paint(p, cloth))
    for x in (-0.34, 0.34):
        p = capsule(radius=0.08, height=0.40); p.apply_translation([x, 0, 0.78]); parts.append(paint(p, cloth))
    s = soft_sphere(0.24, 2, 0.02, 1); s.apply_translation([0,0,1.30]); parts.append(paint(s, skin))
    p = taper_cyl(0.40, 0.04, 0.18, 16); p.apply_translation([0,0,1.52]); parts.append(paint(p, hatc))
    export("villager", trimesh.util.concatenate(parts))

def soldier(kind="soldier"):
    if kind == "zombie":
        body_c, helm_c, name = (0.45,0.75,0.38), (0.58,0.65,0.40), "zombie"
    elif kind == "enemy":
        body_c, helm_c, name = (1.0,0.28,0.90), (1.0,0.90,0.28), "enemy"
    else:
        body_c, helm_c, name = (0.90,0.28,0.22), (0.78,0.82,0.90), "soldier"
    h = 1.35
    parts = []
    p = capsule(radius=0.40, height=h); p.apply_translation([0,0,h*0.5]); parts.append(paint(p, body_c))
    s = soft_sphere(0.32, 2, 0.03, 5); s.apply_translation([0,0,h+0.1]); parts.append(paint(s, helm_c))
    export(name, trimesh.util.concatenate(parts))

def garrison():
    stone, wood, blue = (0.80,0.82,0.88), (0.64,0.44,0.26), (0.14,0.38,0.95)
    parts = []
    p = taper_cyl(2.8, 2.7, 0.32, 28); p.apply_translation([0,0,0.16]); parts.append(paint(p, (0.72,0.68,0.58)))
    p = bevel_box((4.2, 4.2, 3.0), 0.16); p.apply_translation([0,0,1.7]); parts.append(paint(p, stone))
    for x in (-1.6, 1.6):
        for y in (-1.6, 1.6):
            c = taper_cyl(0.6, 0.55, 3.2, 16); c.apply_translation([x,y,1.8]); parts.append(paint(c, stone))
    r = pagoda_roof(5.2, 5.2, 1.4, 0.4, 8, blue); r.apply_translation([0,0,3.5]); parts.append(r)
    export("garrison", trimesh.util.concatenate(parts))

def scout_camp():
    canvas, wood = (0.96,0.80,0.45), (0.70,0.46,0.28)
    parts = []
    p = taper_cyl(2.0, 1.9, 0.18, 24); p.apply_translation([0,0,0.09]); parts.append(paint(p, (0.76,0.60,0.40)))
    p = bevel_box((2.8, 2.5, 1.4), 0.14); p.apply_translation([0,0,0.9]); parts.append(paint(p, canvas))
    r = pagoda_roof(3.6, 3.3, 1.3, 0.35, 6, (0.94,0.58,0.24)); r.apply_translation([0,0,1.7]); parts.append(r)
    for x in (-1.1, 1.1):
        c = taper_cyl(0.1, 0.09, 2.4, 10); c.apply_translation([x, 0.9, 1.2]); parts.append(paint(c, wood))
    export("scout_camp", trimesh.util.concatenate(parts))

def main():
    print("OUT", OUT)
    town_center(); house(); arrow_tower(); barracks(); gate(); wall(); relay()
    garrison(); scout_camp()
    candy_tree(); gold(); stone()
    villager(); soldier("soldier"); soldier("enemy"); soldier("zombie")
    print("ALL GLB DONE", list(OUT.glob('*.glb')))

if __name__ == "__main__":
    main()
