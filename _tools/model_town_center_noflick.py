# -*- coding: utf-8 -*-
"""Town Center — almost-flat chunky toy roofs; NO temple corner curls."""
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
sc.render.resolution_y = 1000
sc.render.filepath = OUT_PNG
sc.render.image_settings.file_format = "PNG"

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree; nt.nodes.clear()
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.56, 0.62, 0.70, 1); bg.inputs[1].default_value = 0.45
nt.links.new(bg.outputs[0], nt.nodes.new("ShaderNodeOutputWorld").inputs[0])

def mat(name, col, rough=0.5, coat=0.22, coat_r=0.35, metal=0.0, sss=0.1):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links; nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial"); b = nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = coat_r
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
    links.new(b.outputs[0], out.inputs[0]); return m

M_WALL=mat("Wall",(0.95,0.92,0.86),0.55,0.15,0.4,sss=0.14)
M_WOOD=mat("Wood",(0.15,0.075,0.04),0.62,0.1,0.45,sss=0.04)
M_BLUE=mat("Cobalt",(0.10,0.32,0.80),0.42,0.28,0.3,sss=0.1)
M_CYAN=mat("Cyan",(0.28,0.55,0.88),0.45,0.25,0.32,sss=0.1)
M_PINK=mat("Salmon",(0.91,0.38,0.40),0.4,0.25,0.28,sss=0.12)
M_GOLD=mat("Gold",(0.96,0.80,0.28),0.28,0.48,0.15,metal=0.55,sss=0.04)
M_STONE=mat("Stone",(0.76,0.66,0.52),0.7,0.08,0.5,sss=0.08)
M_DOOR=mat("Door",(0.9,0.1,0.08),0.4,0.25,0.28,sss=0.08)
M_BASE=mat("Base",(0.82,0.72,0.56),0.55,0.1,0.4,sss=0.1)
M_GRND=mat("Ground",(0.5,0.54,0.6),0.9,0.0,0.5,sss=0.0)

def setm(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
def sel(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
def bevel(o,w=0.05,s=4):
    sel(o); md=o.modifiers.new("B","BEVEL"); md.width=w; md.segments=s
    md.limit_method="ANGLE"; md.angle_limit=math.radians(22); bpy.ops.object.modifier_apply(modifier=md.name)
def smooth(o):
    sel(o); bpy.ops.object.shade_smooth()
def box(name,loc,sx,sy,sz,m,bw=0.05):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.active_object; o.name=name; o.scale=(sx,sy,sz)
    bpy.ops.object.transform_apply(scale=True); setm(o,m); bevel(o,bw,5); return o
def cyl(name,loc,r,depth,m,verts=18,rot=(0,0,0),bw=0.012):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc,rotation=rot)
    o=bpy.context.active_object; o.name=name; setm(o,m); bevel(o,bw,3); smooth(o); return o
def sph(name,loc,r,m,seg=14):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=seg,ring_count=max(8,seg//2))
    o=bpy.context.active_object; o.name=name; setm(o,m); smooth(o); return o
def join(objs,name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join(); objs[0].name=name; return objs[0]

def roof_z(x,y,hx,hy,rise):
    """Almost flat hip — soft dough slope, ZERO corner lift."""
    tx=abs(x)/max(hx,1e-6); ty=abs(y)/max(hy,1e-6)
    t=min(1.0, max(tx,ty))
    # very gentle: center high, edge only slightly lower
    return rise * (1.0 - 0.35 * t)

def make_roof(name, z0, sx, sy, rise, tile_rows=10, tile_r=0.095):
    hx, hy = sx*0.5, sy*0.5
    segs=36
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=segs,y_subdivisions=segs,size=1,location=(0,0,0))
    shell=bpy.context.active_object; shell.name=name+"_shell"
    shell.scale=(sx*1.01, sy*1.01, 1); bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm=bmesh.from_edit_mesh(shell.data)
    for v in bm.verts:
        v.co.z = roof_z(v.co.x, v.co.y, hx, hy, rise)
    bmesh.update_edit_mesh(shell.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    shell.location.z=z0; bpy.ops.object.transform_apply(location=True)
    md=shell.modifiers.new("Sol","SOLIDIFY"); md.thickness=0.22; md.offset=-1
    bpy.ops.object.modifier_apply(modifier=md.name)
    md=shell.modifiers.new("Sm","SMOOTH"); md.factor=0.55; md.iterations=4
    bpy.ops.object.modifier_apply(modifier=md.name)
    setm(shell,M_BLUE); smooth(shell); bevel(shell,0.035,3)
    parts=[shell]

    # Dense horizontal tile sausages — main visual of roof
    for j in range(tile_rows):
        yy = -hy*0.88 + (sy*0.88) * (j / max(1, tile_rows-1))
        zz = z0 + roof_z(0, yy, hx, hy, rise) + tile_r*0.5
        span = sx * (0.88 - 0.06*(abs(yy)/hy))
        parts.append(cyl(f"{name}_t{j}", (0,yy,zz), tile_r, span, M_BLUE if j%2==0 else M_CYAN, 14, rot=(0,math.pi/2,0)))

    # Salmon rim: low, thick, almost level — slight outward only, NO upward curl
    curve=bpy.data.curves.new(name+"_rim","CURVE")
    curve.dimensions="3D"; curve.fill_mode="FULL"
    curve.bevel_depth=0.14; curve.bevel_resolution=5; curve.resolution_u=6
    sp=curve.splines.new("NURBS"); N=40; samples=[]
    for i in range(N):
        u=i/N; side=int(u*4)%4; f=(u*4)%1.0
        if side==0: x,y=-hx+sx*f, -hy
        elif side==1: x,y=hx, -hy+sy*f
        elif side==2: x,y=hx-sx*f, hy
        else: x,y=-hx, hy-sy*f
        # keep rim ON the eave edge height — flat
        z = z0 + roof_z(x*0.99, y*0.99, hx, hy, rise) + 0.08
        samples.append((x*1.01, y*1.01, z))
    sp.points.add(len(samples)-1)
    for i,(x,y,z) in enumerate(samples):
        sp.points[i].co=(x,y,z,1)
    sp.use_cyclic_u=True; sp.order_u=4
    eave=bpy.data.objects.new(name+"_eave", curve)
    bpy.context.collection.objects.link(eave)
    sel(eave); bpy.ops.object.convert(target="MESH")
    eave=bpy.context.active_object
    setm(eave,M_PINK); smooth(eave); bevel(eave,0.02,2)
    parts.append(eave)

    # Hip ridges — low doughy salmon tubes
    for sx_,sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x0,y0=sx_*hx*0.12, sy_*hy*0.12
        x1,y1=sx_*hx*0.88, sy_*hy*0.88
        z0h=z0+roof_z(x0,y0,hx,hy,rise)+0.11
        z1h=z0+roof_z(x1,y1,hx,hy,rise)+0.1
        d=Vector((x1-x0,y1-y0,z1h-z0h)); mid=Vector(((x0+x1)/2,(y0+y1)/2,(z0h+z1h)/2))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=0.1,depth=d.length,location=mid)
        hip=bpy.context.active_object
        hip.rotation_mode="QUATERNION"; hip.rotation_quaternion=d.normalized().to_track_quat("Z","Y")
        setm(hip,M_PINK); smooth(hip); parts.append(hip)

    # Center ridge
    parts.append(cyl(f"{name}_cr",(0,0,z0+rise+0.1),0.11,min(sx,sy)*0.42,M_PINK,14,rot=(0,math.pi/2,0)))

    # Corner: SMALL rounded pads flush with rim — NOT lifted balls
    for sx_,sy_ in ((-1,-1),(-1,1),(1,-1),(1,1)):
        x,y=sx_*hx*0.95, sy_*hy*0.95
        z=z0+roof_z(x,y,hx,hy,rise)+0.1
        pad=sph(f"{name}_c",(x,y,z),0.12,M_PINK,12)
        pad.scale=(1.2,1.2,0.7); bpy.ops.object.transform_apply(scale=True)
        parts.append(pad)

    return join(parts, name)

def pillar(name,x,y,z0,h):
    base=sph(f"{name}_b",(x,y,z0+0.09),0.15,M_BASE,12)
    base.scale=(1.2,1.2,0.55); bpy.ops.object.transform_apply(scale=True)
    post=cyl(f"{name}_p",(x,y,z0+h*0.5+0.08),0.075,h,M_WOOD,14)
    extras=[base,post]
    for k in range(4):
        ang=k*math.pi/2
        extras.append(cyl(f"{name}_g{k}",(x+math.cos(ang)*0.07,y+math.sin(ang)*0.07,z0+h*0.5+0.08),0.01,h*0.85,M_WOOD,8,bw=0.003))
    return join(extras,name)

def door(name,x,y,z):
    d=box(f"{name}_d",(x,y,z+0.28),0.38,0.06,0.55,M_DOOR,0.035)
    a=sph(f"{name}_a",(x,y,z+0.58),0.19,M_DOOR,12); a.scale=(1.05,0.28,0.48); bpy.ops.object.transform_apply(scale=True)
    steps=[box(f"{name}_s{i}",(x,y-0.18-i*0.08,0.03+i*0.05),0.45-i*0.06,0.15,0.055,M_STONE,0.02) for i in range(3)]
    return join([d,a]+steps,name)

def foundation():
    rng=random.Random(5)
    pad=cyl("Pad",(0,0,0.045),2.9,0.1,M_STONE,48)
    pebs=[pad]
    for i in range(55):
        ang=rng.random()*math.tau; rr=2.05+rng.random()*1.0; s=0.1+rng.random()*0.17
        p=sph(f"Pe{i}",(math.cos(ang)*rr,math.sin(ang)*rr,0.06),s,M_STONE,10)
        p.scale=(0.9+rng.random()*0.45,0.9+rng.random()*0.45,0.4+rng.random()*0.35)
        bpy.ops.object.transform_apply(scale=True); pebs.append(p)
    return join(pebs,"Foundation")

foundation()
# Massing: broad wings, moderate center (less vertical temple)
box("Center",(0,0,0.7),2.6,2.2,1.05,M_WALL,0.06)
box("WingL",(-2.7,0.05,0.48),2.5,2.0,0.7,M_WALL,0.055)
box("WingR",(2.7,0.05,0.48),2.5,2.0,0.7,M_WALL,0.055)
box("LintC",(0,-1.15,1.15),2.6,0.12,0.12,M_WOOD,0.025)
box("LintL",(-2.7,-1.05,0.8),2.5,0.1,0.1,M_WOOD,0.02)
box("LintR",(2.7,-1.05,0.8),2.5,0.1,0.1,M_WOOD,0.02)
for sx in (-1.15,1.15):
    for sy in (-1.05,1.05):
        pillar(f"PC{sx}{sy}",sx,sy,0.08,1.05)
for wx in (-3.6,-1.8,1.8,3.6):
    for sy in (-0.9,0.9):
        pillar(f"PW{wx}{sy}",wx,sy,0.06,0.8)
door("DC",0,-1.15,0.12); door("DL",-2.7,-1.05,0.08); door("DR",2.7,-1.05,0.08)

# FLAT roofs
make_roof("Roof1",1.2,8.0,4.0,rise=0.28,tile_rows=12,tile_r=0.1)

box("Mid",(0,0,2.05),1.9,1.7,0.75,M_WALL,0.05)
for sx,sy in ((-0.8,-0.7),(-0.8,0.7),(0.8,-0.7),(0.8,0.7)):
    pillar(f"PM{sx}{sy}",sx,sy,1.7,0.75)
box("WinL",(-0.5,-0.88,2.1),0.22,0.04,0.25,M_WOOD,0.015)
box("WinR",(0.5,-0.88,2.1),0.22,0.04,0.25,M_WOOD,0.015)

make_roof("Roof2",2.5,3.2,2.85,rise=0.24,tile_rows=8,tile_r=0.08)

box("Top",(0,0,3.2),1.15,1.05,0.55,M_WALL,0.04)
for sx,sy in ((-0.48,-0.42),(-0.48,0.42),(0.48,-0.42),(0.48,0.42)):
    pillar(f"PT{sx}{sy}",sx,sy,2.95,0.55)

make_roof("Roof3",3.55,1.85,1.65,rise=0.2,tile_rows=5,tile_r=0.065)

sph("Fin",(0,0,4.0),0.15,M_GOLD,18)
cyl("FinStem",(0,0,3.85),0.04,0.14,M_GOLD,10,bw=0.006)
sph("Fin2",(0,0,4.14),0.085,M_GOLD,14)
sph("FinL",(-2.7,0,1.65),0.095,M_GOLD,12)
sph("FinR",(2.7,0,1.65),0.095,M_GOLD,12)

bpy.ops.mesh.primitive_plane_add(size=28,location=(0,0,0))
gp=bpy.context.active_object; gp.name="Ground"; setm(gp,M_GRND)

bpy.ops.object.empty_add(type="PLAIN_AXES",location=(0,0,1.7))
tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(10.0,-11.0,3.8))
cam=bpy.context.active_object; cam.data.lens=52
cam.data.dof.use_dof=True; cam.data.dof.focus_object=tgt; cam.data.dof.aperture_fstop=2.8
c=cam.constraints.new("TRACK_TO"); c.target=tgt; c.track_axis="TRACK_NEGATIVE_Z"; c.up_axis="UP_Y"
sc.camera=cam

bpy.ops.object.light_add(type="AREA",location=(5.5,-3.5,5.8))
key=bpy.context.active_object; key.data.energy=360; key.data.color=(1.0,0.93,0.82); key.data.size=5.5
bpy.ops.object.light_add(type="AREA",location=(-5,2.5,3.2))
fill=bpy.context.active_object; fill.data.energy=120; fill.data.color=(0.65,0.75,1.0); fill.data.size=5
bpy.ops.object.light_add(type="SUN",location=(3,-2,8))
sun=bpy.context.active_object; sun.data.energy=1.2; sun.data.color=(1.0,0.96,0.9)
sun.rotation_euler=(math.radians(38),math.radians(5),math.radians(-18)); sun.data.angle=math.radians(10)

sc.view_settings.view_transform="Filmic"; sc.view_settings.look="Medium Contrast"; sc.view_settings.exposure=0.28
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
