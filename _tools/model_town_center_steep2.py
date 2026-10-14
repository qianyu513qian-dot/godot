# -*- coding: utf-8 -*-
"""Town Center — steep hip, NO flatten-smooth; low face-on camera."""
import bpy, bmesh, math, random
from mathutils import Vector

OUT_BLEND = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center.blend"
OUT_PNG   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\_tools\town_center_preview.png"
OUT_GLB   = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\models\town_center.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 90
sc.cycles.use_denoising = True
sc.cycles.device = "GPU"
sc.render.resolution_x = 1280
sc.render.resolution_y = 1100
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.48, 0.56, 0.66, 1); bg.inputs[1].default_value = 0.4
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(name, col, rough=0.36, coat=0.4, coat_r=0.16, metal=0.0, sss=0.1):
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

M_WALL=mat("Wall",(0.95,0.92,0.86),0.5,0.18,0.35,sss=0.12)
M_WOOD=mat("Wood",(0.14,0.07,0.035),0.55,0.1,0.4,sss=0.04)
M_BLUE=mat("Cobalt",(0.06,0.24,0.74),0.28,0.45,0.14,sss=0.08)
M_SKY=mat("Sky",(0.2,0.48,0.9),0.3,0.4,0.15,sss=0.08)
M_LAV=mat("Lav",(0.38,0.3,0.8),0.32,0.38,0.16,sss=0.08)
M_PINK=mat("Salmon",(0.9,0.32,0.36),0.28,0.42,0.14,sss=0.1)
M_GOLD=mat("Gold",(0.96,0.8,0.28),0.22,0.55,0.12,metal=0.55,sss=0.03)
M_STONE=mat("Stone",(0.76,0.66,0.52),0.65,0.08,0.45,sss=0.08)
M_DOOR=mat("Door",(0.88,0.1,0.08),0.35,0.28,0.22,sss=0.08)
M_BASE=mat("Base",(0.82,0.72,0.56),0.5,0.1,0.35,sss=0.1)
M_GRND=mat("Ground",(0.48,0.52,0.58),0.9,0.0,0.5,sss=0.0)

def setm(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
def sel(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
def bevel(o,w=0.04,s=3):
    sel(o); md=o.modifiers.new("B","BEVEL"); md.width=w; md.segments=s
    md.limit_method="ANGLE"; md.angle_limit=math.radians(30)
    bpy.ops.object.modifier_apply(modifier=md.name)
def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()
def box(name,loc,sx,sy,sz,m,bw=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.active_object; o.name=name; o.scale=(sx,sy,sz)
    bpy.ops.object.transform_apply(scale=True); setm(o,m); bevel(o,bw,4); return o
def cyl(name,loc,r,depth,m,verts=12,rot=(0,0,0),bw=0.008):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc,rotation=rot)
    o=bpy.context.active_object; o.name=name; setm(o,m); bevel(o,bw,2); smooth(o); return o
def sph(name,loc,r,m,seg=12):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=seg,ring_count=max(8,seg//2))
    o=bpy.context.active_object; o.name=name; setm(o,m); smooth(o); return o
def join(objs,name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join(); objs[0].name=name; return objs[0]
def orient(obj,d):
    obj.rotation_mode="QUATERNION"; obj.rotation_quaternion=d.normalized().to_track_quat("Z","Y")

def hip_z(x,y,hx,hy,rise):
    t=min(1.0, max(abs(x)/hx, abs(y)/hy))
    return rise*(1.0-0.95*t)

def make_hip_roof(name, z0, sx, sy, rise, tile_r=0.07, n=11):
    """Build pitched roof from subdivided plane with HARD displace — no smooth mod."""
    hx, hy = sx*0.5, sy*0.5
    segs = 24
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs, y_subdivisions=segs, size=1, location=(0,0,0))
    shell = bpy.context.active_object
    shell.scale = (sx, sy, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(shell.data)
    for v in bm.verts:
        v.co.z = hip_z(v.co.x, v.co.y, hx, hy, rise)
        # moderate tip only at extreme corners
        cx = max(0.0, (abs(v.co.x)/hx - 0.85)/0.15)
        cy = max(0.0, (abs(v.co.y)/hy - 0.85)/0.15)
        v.co.z += rise * 0.08 * (cx * cy)
    bmesh.update_edit_mesh(shell.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    shell.location.z = z0
    bpy.ops.object.transform_apply(location=True)

    # thickness ONLY — no smooth (smooth was killing the pitch)
    md = shell.modifiers.new("Sol", "SOLIDIFY")
    md.thickness = 0.12; md.offset = -1
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell, M_BLUE)
    # flat shade on faces so pitch edges read
    sel(shell); bpy.ops.object.shade_flat()
    bevel(shell, 0.015, 2)
    parts = [shell]
    mats = [M_BLUE, M_SKY, M_LAV, M_BLUE, M_SKY]

    # Tiles DOWN front slope
    for i in range(n):
        u = (i+0.5)/n
        xx = -hx*0.82 + sx*0.82*u
        for face, y0f, y1f in ((-1, -0.06, -0.92), (1, 0.06, 0.92)):
            y0, y1 = face*abs(y0f)*hy if False else (hy*y0f, hy*y1f)
            # fix: use signed
            pass
        for y0s, y1s in ((-0.08, -0.92), (0.08, 0.92)):
            y0, y1 = hy*y0s, hy*y1s
            z0t = z0 + hip_z(xx, y0, hx, hy, rise) + tile_r*0.4
            z1t = z0 + hip_z(xx, y1, hx, hy, rise) + tile_r*0.4
            d = Vector((0, y1-y0, z1t-z0t))
            if d.length < 0.05: continue
            mid = Vector((xx, (y0+y1)/2, (z0t+z1t)/2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=tile_r, depth=d.length*0.9, location=mid)
            t=bpy.context.active_object; orient(t,d); setm(t, mats[i%len(mats)]); smooth(t)
            parts.append(t)

    # Side tiles
    for i in range(max(4, n//2)):
        u=(i+0.5)/max(4,n//2)
        yy=-hy*0.7+sy*0.7*u
        for x0s,x1s in ((-0.08,-0.92),(0.08,0.92)):
            x0,x1=hx*x0s, hx*x1s
            za=z0+hip_z(x0,yy,hx,hy,rise)+tile_r*0.35
            zb=z0+hip_z(x1,yy,hx,hy,rise)+tile_r*0.35
            d=Vector((x1-x0,0,zb-za))
            mid=Vector(((x0+x1)/2,yy,(za+zb)/2))
            bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=tile_r*0.9,depth=d.length*0.9,location=mid)
            t=bpy.context.active_object; orient(t,d); setm(t,mats[i%len(mats)]); smooth(t)
            parts.append(t)

    # Salmon ridges — peak cross + hips
    zpk = z0 + rise + 0.06
    parts.append(cyl(f"{name}_rx",(0,0,zpk),0.095,sx*0.2,M_PINK,12,rot=(0,math.pi/2,0)))
    parts.append(cyl(f"{name}_ry",(0,0,zpk),0.09,sy*0.18,M_PINK,12,rot=(math.pi/2,0,0)))
    for sx_,sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x0,y0=sx_*hx*0.05, sy_*hy*0.05
        x1,y1=sx_*hx*0.9, sy_*hy*0.9
        za=z0+hip_z(x0,y0,hx,hy,rise)+0.07
        zb=z0+hip_z(x1,y1,hx,hy,rise)+0.07
        d=Vector((x1-x0,y1-y0,zb-za)); mid=Vector(((x0+x1)/2,(y0+y1)/2,(za+zb)/2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=0.08,depth=d.length,location=mid)
        h=bpy.context.active_object; orient(h,d); setm(h,M_PINK); smooth(h); parts.append(h)

    # Eave rim at LOW eave
    curve=bpy.data.curves.new(name+"_rim","CURVE")
    curve.dimensions="3D"; curve.fill_mode="FULL"
    curve.bevel_depth=0.09; curve.bevel_resolution=3
    sp=curve.splines.new("NURBS"); N=32; samples=[]
    for i in range(N):
        u=i/N; side=int(u*4)%4; f=(u*4)%1.0
        if side==0: x,y=-hx+sx*f,-hy
        elif side==1: x,y=hx,-hy+sy*f
        elif side==2: x,y=hx-sx*f,hy
        else: x,y=-hx,hy-sy*f
        z=z0+hip_z(x,y,hx,hy,rise)+0.05
        cx=max(0,(abs(x)/hx-0.85)/0.15); cy=max(0,(abs(y)/hy-0.85)/0.15)
        z+=rise*0.06*(cx*cy)
        samples.append((x*1.01,y*1.01,z))
    sp.points.add(len(samples)-1)
    for i,(x,y,z) in enumerate(samples): sp.points[i].co=(x,y,z,1)
    sp.use_cyclic_u=True; sp.order_u=4
    eave=bpy.data.objects.new(name+"_eave",curve)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave=bpy.context.active_object; setm(eave,M_PINK); smooth(eave); parts.append(eave)

    for sx_,sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x,y=sx_*hx*0.94, sy_*hy*0.94
        z=z0+hip_z(x*0.95,y*0.95,hx,hy,rise)+0.1
        tip=sph(f"{name}_t",(x,y,z),0.1,M_PINK,12)
        tip.scale=(1.15,1.15,0.85); bpy.ops.object.transform_apply(scale=True)
        parts.append(tip); parts.append(sph(f"{name}_g",(x,y,z+0.05),0.038,M_GOLD,10))

    return join(parts, name)

def pillar(name,x,y,z0,h):
    base=sph(f"{name}_b",(x,y,z0+0.07),0.13,M_BASE,12)
    base.scale=(1.15,1.15,0.5); bpy.ops.object.transform_apply(scale=True)
    post=cyl(f"{name}_p",(x,y,z0+h*0.5+0.06),0.075,h,M_WOOD,12)
    return join([base,post],name)

def door(name,x,y,z):
    d=box(f"{name}_d",(x,y,z+0.24),0.34,0.055,0.48,M_DOOR,0.03)
    a=sph(f"{name}_a",(x,y,z+0.5),0.17,M_DOOR,12)
    a.scale=(1.0,0.28,0.45); bpy.ops.object.transform_apply(scale=True)
    steps=[box(f"{name}_s{i}",(x,y-0.15-i*0.06,0.02+i*0.04),0.4-i*0.05,0.12,0.045,M_STONE,0.02) for i in range(3)]
    return join([d,a]+steps,name)

def foundation():
    rng=random.Random(17)
    pad=cyl("Pad",(0,0,0.035),2.7,0.08,M_STONE,40)
    pebs=[pad]
    for i in range(35):
        ang=rng.random()*math.tau; rr=1.9+rng.random()*0.9; s=0.09+rng.random()*0.13
        p=sph(f"Pe{i}",(math.cos(ang)*rr,math.sin(ang)*rr,0.045),s,M_STONE,8)
        p.scale=(0.9+rng.random()*0.35,0.9+rng.random()*0.35,0.4+rng.random()*0.3)
        bpy.ops.object.transform_apply(scale=True); pebs.append(p)
    return join(pebs,"Foundation")

foundation()
box("Center",(0,0,0.65),2.3,2.0,0.95,M_WALL,0.05)
box("WingL",(-2.4,0,0.44),2.2,1.75,0.65,M_WALL,0.045)
box("WingR",(2.4,0,0.44),2.2,1.75,0.65,M_WALL,0.045)
for sx in (-0.95,0.95):
    for sy in (-0.9,0.9):
        pillar(f"PC{sx}{sy}",sx,sy,0.07,0.95)
for wx in (-3.15,-1.6,1.6,3.15):
    for sy in (-0.75,0.75):
        pillar(f"PW{wx}{sy}",wx,sy,0.05,0.72)
door("DC",0,-1.05,0.1); door("DL",-2.4,-0.92,0.07); door("DR",2.4,-0.92,0.07)

# VERY steep: rise ~= half-depth → ~45°
make_hip_roof("Roof1", 1.15, 7.0, 3.4, rise=1.7, tile_r=0.072, n=11)
print("R1", round(math.degrees(math.atan(1.7/1.7)),1), "deg")

box("Mid",(0,0,3.35),1.7,1.5,0.65,M_WALL,0.04)
for sx,sy in ((-0.7,-0.6),(-0.7,0.6),(0.7,-0.6),(0.7,0.6)):
    pillar(f"PM{sx}{sy}",sx,sy,3.0,0.65)
box("WinL",(-0.4,-0.78,3.35),0.18,0.035,0.2,M_WOOD,0.012)
box("WinR",(0.4,-0.78,3.35),0.18,0.035,0.2,M_WOOD,0.012)

make_hip_roof("Roof2", 3.7, 2.75, 2.4, rise=1.2, tile_r=0.058, n=8)
print("R2", round(math.degrees(math.atan(1.2/1.2)),1), "deg")

box("Top",(0,0,5.25),0.95,0.85,0.45,M_WALL,0.03)
for sx,sy in ((-0.38,-0.32),(-0.38,0.32),(0.38,-0.32),(0.38,0.32)):
    pillar(f"PT{sx}{sy}",sx,sy,5.0,0.45)

make_hip_roof("Roof3", 5.5, 1.55, 1.35, rise=0.85, tile_r=0.045, n=5)
print("R3", round(math.degrees(math.atan(0.85/0.675)),1), "deg")

sph("Fin",(0,0,6.5),0.12,M_GOLD,14)
cyl("FinStem",(0,0,6.35),0.03,0.1,M_GOLD,8,bw=0.004)
sph("Fin2",(0,0,6.58),0.065,M_GOLD,12)

bpy.ops.mesh.primitive_plane_add(size=26,location=(0,0,0))
gp=bpy.context.active_object; gp.name="Ground"; setm(gp,M_GRND)

# Camera: LOW, looking slightly UP at roof faces (like crop)
bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 3.5))
tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(6.5, -8.0, 2.8))
cam=bpy.context.active_object
cam.data.lens=50
cam.data.dof.use_dof=True; cam.data.dof.focus_object=tgt; cam.data.dof.aperture_fstop=2.8
c=cam.constraints.new("TRACK_TO"); c.target=tgt
c.track_axis="TRACK_NEGATIVE_Z"; c.up_axis="UP_Y"
sc.camera=cam

bpy.ops.object.light_add(type="AREA",location=(5,-3,6))
key=bpy.context.active_object; key.data.energy=420; key.data.color=(1.0,0.92,0.8); key.data.size=5
bpy.ops.object.light_add(type="AREA",location=(-4,2,3))
fill=bpy.context.active_object; fill.data.energy=150; fill.data.color=(0.65,0.75,1.0); fill.data.size=4
bpy.ops.object.light_add(type="SUN",location=(3,-2,8))
sun=bpy.context.active_object; sun.data.energy=1.6; sun.data.color=(1.0,0.95,0.88)
sun.rotation_euler=(math.radians(32),math.radians(5),math.radians(-28)); sun.data.angle=math.radians(5)

sc.view_settings.view_transform="Filmic"; sc.view_settings.look="Medium Contrast"; sc.view_settings.exposure=0.32
try:
    p=bpy.context.preferences.addons["cycles"].preferences
    p.compute_device_type="CUDA"
    for d in p.devices: d.use=True
except Exception: pass

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND); print("SAVED_BLEND")
bpy.ops.render.render(write_still=True); print("SAVED_PNG")
for o in sc.objects:
    o.select_set(o.type=="MESH" and o.name!="Ground" and max(o.dimensions)<26)
bpy.ops.export_scene.gltf(filepath=OUT_GLB,export_format="GLB",use_selection=True,export_apply=True)
print("SAVED_GLB"); print("DONE")
