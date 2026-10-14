# -*- coding: utf-8 -*-
"""Town Center — TRUE hip mesh (ridge + 4 triangular faces), low camera."""
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
bg.inputs[0].default_value = (0.5, 0.58, 0.68, 1); bg.inputs[1].default_value = 0.4
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(name, col, rough=0.38, coat=0.4, coat_r=0.18, metal=0.0, sss=0.1):
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
M_WOOD=mat("Wood",(0.14,0.07,0.035),0.55,0.12,0.4,sss=0.04)
M_BLUE=mat("Cobalt",(0.07,0.26,0.76),0.3,0.45,0.15,sss=0.08)
M_SKY=mat("Sky",(0.22,0.5,0.9),0.32,0.4,0.16,sss=0.08)
M_LAV=mat("Lav",(0.4,0.32,0.82),0.35,0.38,0.18,sss=0.08)
M_PINK=mat("Salmon",(0.9,0.34,0.38),0.3,0.42,0.15,sss=0.1)
M_GOLD=mat("Gold",(0.96,0.8,0.28),0.22,0.55,0.12,metal=0.55,sss=0.03)
M_STONE=mat("Stone",(0.76,0.66,0.52),0.65,0.08,0.45,sss=0.08)
M_DOOR=mat("Door",(0.88,0.1,0.08),0.35,0.3,0.22,sss=0.08)
M_BASE=mat("Base",(0.82,0.72,0.56),0.5,0.12,0.35,sss=0.1)
M_GRND=mat("Ground",(0.48,0.52,0.58),0.9,0.0,0.5,sss=0.0)

def setm(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
def sel(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
def bevel(o,w=0.04,s=4):
    sel(o); md=o.modifiers.new("B","BEVEL"); md.width=w; md.segments=s
    md.limit_method="ANGLE"; md.angle_limit=math.radians(20)
    bpy.ops.object.modifier_apply(modifier=md.name)
def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()
def box(name,loc,sx,sy,sz,m,bw=0.045):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.active_object; o.name=name; o.scale=(sx,sy,sz)
    bpy.ops.object.transform_apply(scale=True); setm(o,m); bevel(o,bw,4); return o
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
def orient(obj, direction):
    obj.rotation_mode="QUATERNION"
    obj.rotation_quaternion=direction.normalized().to_track_quat("Z","Y")

def true_hip_shell(name, z0, sx, sy, rise):
    """Classical rectangular hip: ridge along X, 4 sloping faces. Clear triangle silhouette."""
    hx, hy = sx * 0.5, sy * 0.5
    # ridge length: for hip, ridge = sx - sy (if sx>sy), else small
    if sx >= sy:
        rl = max(0.15, (sx - sy) * 0.5)  # half ridge length from center
        # ridge endpoints
        r0 = (-rl, 0.0, rise)
        r1 = (rl, 0.0, rise)
    else:
        rl = max(0.15, (sy - sx) * 0.5)
        r0 = (0.0, -rl, rise)
        r1 = (0.0, rl, rise)
    # four eave corners (with tiny tip lift)
    tip = rise * 0.06
    c00 = (-hx, -hy, tip * 0.3)
    c10 = (hx, -hy, tip * 0.3)
    c11 = (hx, hy, tip * 0.3)
    c01 = (-hx, hy, tip * 0.3)

    mesh = bpy.data.meshes.new(name + "_m")
    obj = bpy.data.objects.new(name + "_shell", mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    # verts
    if sx >= sy:
        v_r0 = bm.verts.new(r0); v_r1 = bm.verts.new(r1)
        v00 = bm.verts.new(c00); v10 = bm.verts.new(c10)
        v11 = bm.verts.new(c11); v01 = bm.verts.new(c01)
        bm.verts.ensure_lookup_table()
        # front trapezoid: r0,r1,c10,c00
        bm.faces.new((v_r0, v_r1, v10, v00))
        # back: r1,r0,c01,c11
        bm.faces.new((v_r1, v_r0, v01, v11))
        # left triangle-ish: r0,c00,c01
        bm.faces.new((v_r0, v00, v01))
        # right: r1,c11,c10
        bm.faces.new((v_r1, v11, v10))
    else:
        v_r0 = bm.verts.new(r0); v_r1 = bm.verts.new(r1)
        v00 = bm.verts.new(c00); v10 = bm.verts.new(c10)
        v11 = bm.verts.new(c11); v01 = bm.verts.new(c01)
        bm.verts.ensure_lookup_table()
        bm.faces.new((v_r0, v_r1, v01, v00))  # left
        bm.faces.new((v_r1, v_r0, v10, v11))  # right
        bm.faces.new((v_r0, v00, v10))  # front
        bm.faces.new((v_r1, v11, v01))  # back

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # subdivide for smoother clay look
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
    # slight corner tip: push corner verts up a bit
    for v in bm.verts:
        if abs(abs(v.co.x) - hx) < 0.05 and abs(abs(v.co.y) - hy) < 0.05:
            v.co.z += tip
    bm.to_mesh(mesh); bm.free()
    obj.location = (0, 0, z0)
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True)

    md = obj.modifiers.new("Sol", "SOLIDIFY"); md.thickness = 0.14; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    md = obj.modifiers.new("Sm", "SMOOTH"); md.factor = 0.35; md.iterations = 2
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(obj, M_BLUE); smooth(obj); bevel(obj, 0.02, 2)
    return obj, (hx, hy, rise, rl if sx >= sy else 0, sx >= sy)

def make_hip_roof(name, z0, sx, sy, rise, tile_r=0.07, n=10):
    shell, meta = true_hip_shell(name, z0, sx, sy, rise)
    hx, hy, rise, rl, along_x = meta
    parts = [shell]
    mats = [M_BLUE, M_SKY, M_LAV, M_BLUE, M_SKY]

    # Tiles running DOWN the front face (toward -Y), arrayed across X
    for i in range(n):
        u = (i + 0.5) / n
        xx = -hx * 0.8 + (sx * 0.8) * u
        # front face: from near ridge line to eave
        if along_x:
            # ridge is at y=0, z=rise for |x|<rl; outside ridge, peak drops
            y0 = -hy * 0.05
            y1 = -hy * 0.92
            # height along face: linear from rise (at ridge y) to tip at eave
            # approximate sample
            def z_at(x, y):
                # same as hip: max(|x|/hx, |y|/hy)
                t = max(abs(x)/hx, abs(y)/hy)
                return z0 + rise * (1.0 - 0.92 * t)
            z0t = z_at(xx, y0) + tile_r * 0.45
            z1t = z_at(xx, y1) + tile_r * 0.45
            d = Vector((0, y1 - y0, z1t - z0t))
            mid = Vector((xx, (y0+y1)/2, (z0t+z1t)/2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r, depth=d.length*0.92, location=mid)
            t = bpy.context.active_object; orient(t, d); setm(t, mats[i%len(mats)]); smooth(t)
            parts.append(t)
            # back face
            y0b = hy * 0.05; y1b = hy * 0.92
            z0b = z_at(xx, y0b) + tile_r * 0.45
            z1b = z_at(xx, y1b) + tile_r * 0.45
            db = Vector((0, y1b - y0b, z1b - z0b))
            midb = Vector((xx, (y0b+y1b)/2, (z0b+z1b)/2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r, depth=db.length*0.92, location=midb)
            tb = bpy.context.active_object; orient(tb, db); setm(tb, mats[(i+1)%len(mats)]); smooth(tb)
            parts.append(tb)

    # Side face tiles (fewer)
    n_side = max(4, n // 2)
    for i in range(n_side):
        u = (i + 0.5) / n_side
        yy = -hy * 0.65 + sy * 0.65 * u
        for face in (-1, 1):
            x0 = face * hx * 0.08; x1 = face * hx * 0.9
            def z_at(x, y):
                t = max(abs(x)/hx, abs(y)/hy)
                return z0 + rise * (1.0 - 0.92 * t)
            za = z_at(x0, yy) + tile_r * 0.4
            zb = z_at(x1, yy) + tile_r * 0.4
            d = Vector((x1-x0, 0, zb-za))
            mid = Vector(((x0+x1)/2, yy, (za+zb)/2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r*0.9, depth=d.length*0.9, location=mid)
            t = bpy.context.active_object; orient(t, d); setm(t, mats[i%len(mats)]); smooth(t)
            parts.append(t)

    # Salmon ridge beam(s)
    z_peak = z0 + rise + 0.07
    if along_x:
        parts.append(cyl(f"{name}_ridge", (0, 0, z_peak), 0.1, max(0.4, rl * 2 + 0.3), M_PINK, 12, rot=(0, math.pi/2, 0)))
    else:
        parts.append(cyl(f"{name}_ridge", (0, 0, z_peak), 0.1, max(0.4, rl * 2 + 0.3), M_PINK, 12, rot=(math.pi/2, 0, 0)))

    # Hip corner ridges
    for sx_, sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        # from near ridge end to corner
        if along_x:
            x0 = sx_ * rl * 0.9; y0 = 0.0
        else:
            x0 = 0.0; y0 = sy_ * rl * 0.9
        x1, y1 = sx_ * hx * 0.92, sy_ * hy * 0.92
        def z_at(x, y):
            t = max(abs(x)/hx, abs(y)/hy)
            return z0 + rise * (1.0 - 0.92 * t)
        za = z_at(x0, y0) + 0.08; zb = z_at(x1, y1) + 0.08
        d = Vector((x1-x0, y1-y0, zb-za)); mid = Vector(((x0+x1)/2,(y0+y1)/2,(za+zb)/2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.085, depth=d.length, location=mid)
        hip = bpy.context.active_object; orient(hip, d); setm(hip, M_PINK); smooth(hip)
        parts.append(hip)

    # Eave rim
    curve = bpy.data.curves.new(name+"_rim","CURVE")
    curve.dimensions="3D"; curve.fill_mode="FULL"
    curve.bevel_depth=0.095; curve.bevel_resolution=4
    sp = curve.splines.new("NURBS"); N=36; samples=[]
    for i in range(N):
        u=i/N; side=int(u*4)%4; f=(u*4)%1.0
        if side==0: x,y=-hx+sx*f,-hy
        elif side==1: x,y=hx,-hy+sy*f
        elif side==2: x,y=hx-sx*f,hy
        else: x,y=-hx,hy-sy*f
        t=max(abs(x)/hx, abs(y)/hy)
        z=z0+rise*(1.0-0.92*min(1.0,t))+0.05
        # moderate corner tip
        cx=max(0,(abs(x)/hx-0.82)/0.18); cy=max(0,(abs(y)/hy-0.82)/0.18)
        z += rise*0.05*(cx*cy)
        samples.append((x*1.01,y*1.01,z))
    sp.points.add(len(samples)-1)
    for i,(x,y,z) in enumerate(samples): sp.points[i].co=(x,y,z,1)
    sp.use_cyclic_u=True; sp.order_u=4
    eave=bpy.data.objects.new(name+"_eave",curve)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave=bpy.context.active_object; setm(eave,M_PINK); smooth(eave)
    parts.append(eave)

    # Moderate corner tips
    for sx_,sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x,y=sx_*hx*0.95, sy_*hy*0.95
        t=max(abs(x)/hx,abs(y)/hy)
        z=z0+rise*(1.0-0.92*t)+0.12
        tip=sph(f"{name}_tip",(x,y,z),0.11,M_PINK,12)
        tip.scale=(1.15,1.15,0.9); bpy.ops.object.transform_apply(scale=True)
        parts.append(tip)
        parts.append(sph(f"{name}_g",(x,y,z+0.06),0.04,M_GOLD,10))

    return join(parts, name)

def pillar(name,x,y,z0,h):
    base=sph(f"{name}_b",(x,y,z0+0.08),0.14,M_BASE,12)
    base.scale=(1.2,1.2,0.55); bpy.ops.object.transform_apply(scale=True)
    post=cyl(f"{name}_p",(x,y,z0+h*0.5+0.07),0.078,h,M_WOOD,14)
    return join([base,post],name)

def door(name,x,y,z):
    d=box(f"{name}_d",(x,y,z+0.26),0.36,0.06,0.52,M_DOOR,0.03)
    a=sph(f"{name}_a",(x,y,z+0.54),0.18,M_DOOR,12)
    a.scale=(1.05,0.28,0.48); bpy.ops.object.transform_apply(scale=True)
    steps=[box(f"{name}_s{i}",(x,y-0.16-i*0.07,0.025+i*0.045),0.42-i*0.05,0.14,0.05,M_STONE,0.02) for i in range(3)]
    return join([d,a]+steps,name)

def foundation():
    rng=random.Random(13)
    pad=cyl("Pad",(0,0,0.04),2.75,0.09,M_STONE,48)
    pebs=[pad]
    for i in range(40):
        ang=rng.random()*math.tau; rr=1.95+rng.random()*0.95; s=0.1+rng.random()*0.14
        p=sph(f"Pe{i}",(math.cos(ang)*rr,math.sin(ang)*rr,0.05),s,M_STONE,10)
        p.scale=(0.9+rng.random()*0.4,0.9+rng.random()*0.4,0.4+rng.random()*0.3)
        bpy.ops.object.transform_apply(scale=True); pebs.append(p)
    return join(pebs,"Foundation")

foundation()
box("Center",(0,0,0.68),2.35,2.05,1.0,M_WALL,0.05)
box("WingL",(-2.45,0,0.46),2.25,1.8,0.68,M_WALL,0.05)
box("WingR",(2.45,0,0.46),2.25,1.8,0.68,M_WALL,0.05)
box("LintC",(0,-1.08,1.1),2.35,0.11,0.11,M_WOOD,0.02)
for sx in (-1.0,1.0):
    for sy in (-0.92,0.92):
        pillar(f"PC{sx}{sy}",sx,sy,0.08,1.0)
for wx in (-3.25,-1.65,1.65,3.25):
    for sy in (-0.78,0.78):
        pillar(f"PW{wx}{sy}",wx,sy,0.06,0.75)
door("DC",0,-1.08,0.12); door("DL",-2.45,-0.95,0.08); door("DR",2.45,-0.95,0.08)

# Steep true hips — rise high enough that front face is clearly triangular
# Roof1: depth 3.5 → half 1.75, rise 1.55 → ~42°
make_hip_roof("Roof1", 1.2, 7.2, 3.5, rise=1.55, tile_r=0.075, n=12)
print("R1 angle", round(math.degrees(math.atan(1.55/1.75)),1))

box("Mid",(0,0,3.2),1.75,1.55,0.7,M_WALL,0.045)
for sx,sy in ((-0.72,-0.62),(-0.72,0.62),(0.72,-0.62),(0.72,0.62)):
    pillar(f"PM{sx}{sy}",sx,sy,2.85,0.7)
box("WinL",(-0.42,-0.8,3.2),0.2,0.04,0.22,M_WOOD,0.015)
box("WinR",(0.42,-0.8,3.2),0.2,0.04,0.22,M_WOOD,0.015)

make_hip_roof("Roof2", 3.6, 2.85, 2.5, rise=1.15, tile_r=0.06, n=8)
print("R2 angle", round(math.degrees(math.atan(1.15/1.25)),1))

box("Top",(0,0,5.1),1.0,0.9,0.5,M_WALL,0.035)
for sx,sy in ((-0.4,-0.35),(-0.4,0.35),(0.4,-0.35),(0.4,0.35)):
    pillar(f"PT{sx}{sy}",sx,sy,4.85,0.5)

make_hip_roof("Roof3", 5.4, 1.65, 1.45, rise=0.8, tile_r=0.048, n=5)

sph("Fin",(0,0,6.35),0.13,M_GOLD,16)
cyl("FinStem",(0,0,6.2),0.035,0.12,M_GOLD,10,bw=0.005)
sph("Fin2",(0,0,6.46),0.07,M_GOLD,12)

bpy.ops.mesh.primitive_plane_add(size=28,location=(0,0,0))
gp=bpy.context.active_object; gp.name="Ground"; setm(gp,M_GRND)

# LOW side-ish camera so triangular pitch is obvious (like crop ref)
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, -0.5, 3.2))
tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(7.5, -9.5, 3.2))
cam=bpy.context.active_object
cam.data.lens=55
cam.data.dof.use_dof=True; cam.data.dof.focus_object=tgt; cam.data.dof.aperture_fstop=2.6
c=cam.constraints.new("TRACK_TO"); c.target=tgt
c.track_axis="TRACK_NEGATIVE_Z"; c.up_axis="UP_Y"
sc.camera=cam

bpy.ops.object.light_add(type="AREA",location=(5,-3,6))
key=bpy.context.active_object; key.data.energy=400; key.data.color=(1.0,0.92,0.8); key.data.size=5
bpy.ops.object.light_add(type="AREA",location=(-4,2,3.5))
fill=bpy.context.active_object; fill.data.energy=140; fill.data.color=(0.65,0.75,1.0); fill.data.size=4.5
bpy.ops.object.light_add(type="SUN",location=(3,-2,8))
sun=bpy.context.active_object; sun.data.energy=1.5; sun.data.color=(1.0,0.95,0.88)
sun.rotation_euler=(math.radians(35),math.radians(5),math.radians(-25)); sun.data.angle=math.radians(6)

sc.view_settings.view_transform="Filmic"; sc.view_settings.look="Medium Contrast"; sc.view_settings.exposure=0.3
try:
    p=bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type="CUDA"
    for d in p.devices: d.use=True
except Exception: pass

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND); print("SAVED_BLEND")
bpy.ops.render.render(write_still=True); print("SAVED_PNG")
for o in sc.objects:
    o.select_set(o.type=="MESH" and o.name!="Ground" and max(o.dimensions)<28)
bpy.ops.export_scene.gltf(filepath=OUT_GLB,export_format="GLB",use_selection=True,export_apply=True)
print("SAVED_GLB"); print("DONE")
