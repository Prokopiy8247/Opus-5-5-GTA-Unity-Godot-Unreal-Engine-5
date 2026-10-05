import bpy, bmesh, math, random, os
from mathutils import Vector as V, Matrix as M
D=bpy.data; SC=bpy.context.scene; VL=bpy.context.view_layer
assert D.filepath.endswith("UnityOpus5.5GTA.blend")
PROJECT_ROOT=os.path.dirname(D.filepath)
OUT=os.path.join(PROJECT_ROOT, "Assets", "GTA", "Generated", "Models")
def lin(h):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(((x+0.055)/1.055)**2.4 if x>0.04045 else x/12.92 for x in c)
def coll(path):
    par=SC.collection
    for p in path.split('/'):
        c=D.collections.get(p) or D.collections.new(p)
        if p not in par.children: par.children.link(c)
        par=c
    return par
def mat(n,h,me=0.0,ro=0.6,em=0.0):
    m=D.materials.get(n) or D.materials.new(n)
    if m.node_tree is None:
        try: m.use_nodes=True
        except Exception: pass
    c=lin(h); b=None
    if m.node_tree:
        for x in m.node_tree.nodes:
            if x.type=='BSDF_PRINCIPLED': b=x
    if b:
        for k,v in (('Base Color',(c[0],c[1],c[2],1)),('Metallic',me),('Roughness',ro),('Emission Color',(c[0],c[1],c[2],1)),('Emission Strength',em)):
            for i in b.inputs:
                if i.identifier==k: i.default_value=v
    m.diffuse_color=(c[0],c[1],c[2],1); m.metallic=me; m.roughness=ro
    return m
def NB(): return {'bm':bmesh.new(),'mats':[]}
def mi(b,m):
    if m not in b['mats']: b['mats'].append(m)
    return b['mats'].index(m)
def tag(b,vs,m):
    i=mi(b,m)
    for f in {f for v in vs for f in v.link_faces}: f.material_index=i
def box(b,c,sz,m,rx=0,ry=0,rz=0):
    T=M.Translation(c)@M.Rotation(math.radians(rz),4,'Z')@M.Rotation(math.radians(ry),4,'Y')@M.Rotation(math.radians(rx),4,'X')@M.Diagonal((sz[0],sz[1],sz[2],1))
    vs=bmesh.ops.create_cube(b['bm'],size=1.0,matrix=T)['verts']; tag(b,vs,m); return vs
def boxr(b,x0,x1,y0,y1,z0,z1,m): return box(b,((x0+x1)/2,(y0+y1)/2,(z0+z1)/2),(abs(x1-x0),abs(y1-y0),abs(z1-z0)),m)
def cyl(b,c,r,h,m,ax='Z',seg=10,r2=None):
    R=M.Identity(4)
    if ax=='X': R=M.Rotation(math.pi/2,4,'Y')
    if ax=='Y': R=M.Rotation(math.pi/2,4,'X')
    vs=bmesh.ops.create_cone(b['bm'],cap_ends=True,cap_tris=False,segments=seg,radius1=r,radius2=(r if r2 is None else r2),depth=h,matrix=M.Translation(c)@R)['verts']
    tag(b,vs,m); return vs
def done(b,name,cl,parent=None,loc=(0,0,0)):
    bm=b['bm']; bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    uv=bm.loops.layers.uv.verify()
    for f in bm.faces:
        nn=f.normal; ax=0
        if abs(nn[1])>abs(nn[ax]): ax=1
        if abs(nn[2])>abs(nn[ax]): ax=2
        for l in f.loops:
            co=l.vert.co
            u=((co.y,co.z) if ax==0 else ((co.x,co.z) if ax==1 else (co.x,co.y)))
            l[uv].uv=(u[0]*0.25,u[1]*0.25)
    me=D.meshes.new(name); bm.to_mesh(me); bm.free()
    for mn in b['mats']: me.materials.append(D.materials[mn])
    o=D.objects.new(name,me); cl.objects.link(o)
    if parent: o.parent=parent
    o.location=loc
    return o
def emp(name,cl,parent,loc,sz=1.0):
    e=D.objects.new(name,None); e.empty_display_size=sz; cl.objects.link(e); e.parent=parent; e.location=loc; return e
def wipe(name):
    o=D.objects.get(name)
    if not o: return
    for c in [o]+list(o.children_recursive):
        d=c.data; D.objects.remove(c,do_unlink=True)
        if d is not None and d.users==0 and isinstance(d,bpy.types.Mesh): D.meshes.remove(d)
def export(root,path):
    hidden=[o for o in [root]+list(root.children_recursive) if o.hide_get()]
    for o in hidden: o.hide_set(False)
    old=root.location.copy(); root.location=(0,0,0); VL.update()
    for o in VL.objects: o.select_set(False)
    for o in [root]+list(root.children_recursive): o.select_set(True)
    VL.objects.active=root
    r=bpy.ops.export_scene.fbx(filepath=path,use_selection=True,object_types={'EMPTY','MESH','ARMATURE'},apply_unit_scale=True,apply_scale_options='FBX_SCALE_ALL',
        axis_forward='Z',axis_up='Y',use_mesh_modifiers=True,mesh_smooth_type='FACE',use_triangles=True,add_leaf_bones=False,bake_anim=False,use_armature_deform_only=True)
    root.location=old
    for o in hidden: o.hide_set(True)
    for o in VL.objects: o.select_set(False)
    return r
def text_obj(name,txt,size,mname,cl,parent,loc):
    cu=D.curves.new(name+'_cu','FONT'); cu.body=txt; cu.size=size; cu.extrude=0.04; cu.align_x='CENTER'; cu.align_y='CENTER'
    ob=D.objects.new(name+'_tmp',cu); SC.collection.objects.link(ob)
    dg=bpy.context.evaluated_depsgraph_get(); me=D.meshes.new_from_object(ob.evaluated_get(dg))
    D.objects.remove(ob,do_unlink=True); D.curves.remove(cu)
    me.transform(M.Rotation(math.pi/2,4,'X')); me.materials.clear(); me.materials.append(D.materials[mname]); me.name=name
    o=D.objects.new(name,me); cl.objects.link(o); o.parent=parent; o.location=loc; return o
for a in (("M_GlassCurtain","#a8ccdd",0.6,0.08),("M_WallAirport","#dfe3e6",0.0,0.7),("M_WallPale","#f0ece2",0.0,0.75),
          ("M_LighthouseRed","#c0392b",0.0,0.6),("M_LighthouseWhite","#f2efe6",0.0,0.6),("M_ShowroomGlass","#8fb9cc",0.2,0.06),
          ("M_ShowroomFloor","#4a4d52",0.0,0.5),("M_LightBeacon","#ffe08a",0.0,0.2,4.0)):
    mat(a[0],a[1],a[2],a[3],a[4] if len(a)>4 else 0.0)
BL=coll("GTA_UNITY/Buildings")
rng=random.Random(53)
def col(name,cl,root,x0,x1,y0,y1,z0,z1):
    k=NB(); boxr(k,x0,x1,y0,y1,z0,z1,'M_Concrete'); o=done(k,name,cl,root); o.display_type='WIRE'; o.hide_set(True); return o
# ---------------------------------------------------------------- airfield
wipe('BLD_Terminal'); r=emp('BLD_Terminal',BL,None,(0,820,0),3); b=NB()
w,d,H=54.0,22.0,10.5
boxr(b,-w/2,w/2,-d/2,d/2,0,H,'M_WallAirport')
bm=b['bm']
A=[bm.verts.new(p) for p in ((-w/2-0.6,-d/2-0.6,H),(w/2+0.6,-d/2-0.6,H),(w/2+0.6,d/2+0.6,H),(-w/2-0.6,d/2+0.6,H))]
r0=bm.verts.new((-w/2-0.6,0,H+1.2)); r1=bm.verts.new((w/2+0.6,0,H+1.2))
f=bm.faces.new((A[0],A[1],r0)); f.material_index=mi(b,'M_SteelBlue')
f=bm.faces.new((A[2],A[3],r1)); f.material_index=mi(b,'M_SteelBlue')
for q in ((A[0],r0,r1,A[3]),(A[1],A[2],r1,r0),(A[0],A[3],A[2],A[1])):
    f=bm.faces.new(q); f.material_index=mi(b,'M_SteelBlue')
boxr(b,-w/2-0.8,w/2+0.8,-d/2-0.8,d/2+0.8,H-0.5,H,'M_Trim')
for k in range(17): boxr(b,-w/2+1.0+k*3.1-1.4,-w/2+1.0+k*3.1+1.4,-d/2-0.08,-d/2+0.06,1.0,9.2,'M_GlassCurtain')
boxr(b,-w/2-0.2,w/2+0.2,-d/2-0.25,-d/2,0,1.0,'M_Concrete')
boxr(b,-3.0,3.0,-d/2-0.35,-d/2+0.1,0,3.4,'M_MetalDoor')
boxr(b,-4.0,4.0,-d/2-1.6,-d/2-0.3,9.2,9.5,'M_SteelBlue')
text_obj('BLD_Terminal__SIGN','PORT HALCYON AIRFIELD',1.1,'M_SignGlow',BL,r,(0,-d/2-1.8,9.0))
for k in range(14): boxr(b,-w/2+2.0+k*3.8-0.4,-w/2+2.0+k*3.8+0.4,d/2+0.02,d/2+0.14,1.0,9.5,'M_SteelCorrugated')
boxr(b,-w/2,w/2,d/2+0.6,d/2+1.2,4.6,4.9,'M_SteelBlue')
done(b,'BLD_Terminal__BODY',BL,r)
col('BLD_Terminal__COL_Main',BL,r,-w/2,w/2,-d/2,d/2,0,H)
export(r,OUT+"\\Buildings\\BLD_Terminal.fbx")
wipe('BLD_ControlTower'); r=emp('BLD_ControlTower',BL,None,(0,820,0),2); b=NB()
boxr(b,-3.0,3.0,-3.0,3.0,0,3.0,'M_WallAirport')
for k in range(18): boxr(b,3.0*math.cos(k*math.pi/9),3.0*math.cos(k*math.pi/9)+0.5,3.0*math.sin(k*math.pi/9)-0.2,3.0*math.sin(k*math.pi/9)+0.2,0,3.0,'M_Trim')
cyl(b,(0,0,9.5),2.0,10.0,'M_WallAirport','Z',14)
cyl(b,(0,0,4.2),2.6,0.4,'M_Trim','Z',14); cyl(b,(0,0,14.2),2.6,0.4,'M_Trim','Z',14)
for k in range(3):
    boxr(b,-0.5,0.5,-3.5,3.5,10.0+k*2.0,10.4+k*2.0,'M_Trim')
boxr(b,-2.2,2.2,-3.6,3.6,14.6,18.4,'M_GlassCurtain')
boxr(b,-2.4,2.4,3.3,3.7,14.6,18.4,'M_Trim'); boxr(b,-2.4,2.4,-3.7,-3.3,14.6,18.4,'M_Trim')
boxr(b,-2.4,-2.0,-3.7,3.7,14.6,18.4,'M_Trim'); boxr(b,2.0,2.4,-3.7,3.7,14.6,18.4,'M_Trim')
boxr(b,-2.6,2.6,-4.0,4.0,18.4,19.0,'M_SteelBlue'); boxr(b,-4.3,4.3,-3.2,3.2,19.0,19.5,'M_SteelBlue')
boxr(b,-0.35,0.35,-0.35,0.35,19.5,21.5,'M_MetalDark')
cyl(b,(0,0,21.7),0.35,0.4,'M_LightBeacon','Z',10)
done(b,'BLD_ControlTower__BODY',BL,r)
col('BLD_ControlTower__COL_Main',BL,r,-2.2,2.2,-2.2,2.2,0,19.5)
export(r,OUT+"\\Buildings\\BLD_ControlTower.fbx")
for nm,at in (('BLD_Hangar',(50,820,0)),('BLD_Hangar2',(105,820,0))):
    wipe(nm); r=emp(nm,BL,None,at,3); b=NB()
    w,d,H=30.0,26.0,10.0
    boxr(b,-w/2,w/2,-d/2,d/2,0,H*0.55,'M_SteelCorrugated')
    bmw=b['bm']
    A=[bmw.verts.new(p) for p in ((-w/2-0.5,-d/2-0.5,H*0.55),(w/2+0.5,-d/2-0.5,H*0.55),(w/2+0.5,d/2+0.5,H*0.55),(-w/2-0.5,d/2+0.5,H*0.55))]
    r0=bmw.verts.new((-w/2-0.5,0,H*0.55+4.6)); r1=bmw.verts.new((w/2+0.5,0,H*0.55+4.6))
    f=bmw.faces.new((A[0],A[1],r0)); f.material_index=mi(b,'M_SteelBlue')
    f=bmw.faces.new((A[2],A[3],r1)); f.material_index=mi(b,'M_SteelBlue')
    for q in ((A[0],r0,r1,A[3]),(A[1],A[2],r1,r0),(A[0],A[3],A[2],A[1])):
        f=bmw.faces.new(q); f.material_index=mi(b,'M_SteelBlue')
    for sx in (1,-1): boxr(b,sx*w/2-0.3,sx*w/2+0.3,-d/2-0.5,d/2+0.5,H*0.55,H*0.55+0.4,'M_SteelBlue')
    yf=-d/2
    boxr(b,-9.0,9.0,yf-0.3,yf+0.3,0,H*0.55,'M_SteelBlue')
    for k in range(13): boxr(b,-8.6+k*1.42,-8.3+k*1.42,yf-0.35,yf-0.25,0,H*0.55,'M_SteelCorrugated')
    boxr(b,-9.4,-9.0,yf-0.4,yf-0.2,0,H*0.6,'M_Trim'); boxr(b,9.0,9.4,yf-0.4,yf-0.2,0,H*0.6,'M_Trim')
    text_obj(nm+'__SIGN','HALCYON AIR',0.42,'M_SignGlow',BL,r,(0,yf-0.45,H*0.55+2.6))
    done(b,nm+'__BODY',BL,r)
    col(nm+'__COL_Main',BL,r,-w/2,w/2,-d/2,d/2,0,H*0.55+4.6)
    export(r,OUT+"\\Buildings\\BLD_Hangar.fbx" if nm=='BLD_Hangar' else OUT+"\\Buildings\\BLD_Hangar2.fbx")
# ---------------------------------------------------------------- landmark
wipe('BLD_Lighthouse'); r=emp('BLD_Lighthouse',BL,None,(0,820,0),2); b=NB()
cyl(b,(0,0,0.6),3.4,1.2,'M_Concrete','Z',16); cyl(b,(0,0,2.0),2.3,2.0,'M_Concrete','Z',16)
for k in range(8):
    z0=3.0+k*1.5
    if z0>15.0: break
    rr=2.05-k*0.16
    cyl(b,(0,0,z0),rr,1.5,'M_LighthouseRed' if k%2==0 else 'M_LighthouseWhite','Z',14,r2=rr-0.13)
cyl(b,(0,0,15.6),1.05,1.4,'M_LighthouseWhite','Z',14,r2=0.95)
cyl(b,(0,0,17.2),1.3,0.3,'M_Trim','Z',14)
cyl(b,(0,0,18.2),1.15,1.8,'M_GlassCurtain','Z',12)
cyl(b,(0,0,19.2),1.45,0.25,'M_Trim','Z',12); cyl(b,(0,0,19.7),1.1,0.9,'M_LighthouseRed','Z',12,r2=0.3)
cyl(b,(0,0,20.3),0.18,0.5,'M_MetalDark','Z',8); cyl(b,(0,0,20.7),0.42,0.35,'M_LightBeacon','Z',10)
boxr(b,-0.5,0.5,-1.4,-1.2,16.0,19.0,'M_Trim')
boxr(b,-1.4,1.4,-1.3,-1.1,3.0,6.0,'M_Trim')
boxr(b,-1.1,1.1,-1.25,-1.1,3.0,4.0,'M_Glass')
boxr(b,-2.6,2.6,-2.4,-2.0,15.9,16.3,'M_MetalDark')
done(b,'BLD_Lighthouse__BODY',BL,r)
col('BLD_Lighthouse__COL_Main',BL,r,-3.4,3.4,-3.4,3.4,0,21.0)
export(r,OUT+"\\Buildings\\BLD_Lighthouse.fbx")
# ---------------------------------------------------------------- showroom & parking garage
wipe('BLD_Showroom'); r=emp('BLD_Showroom',BL,None,(0,820,0),3); b=NB()
w,d,H=30.0,20.0,5.6
boxr(b,-w/2,w/2,-d/2,d/2,0.0,H,'M_ShowroomFloor')
boxr(b,-w/2,w/2,-d/2,d/2,H,H+0.5,'M_Trim')
for (ax,c,a0,a1,out) in ((0,-d/2,-w/2,w/2,-1),(1,-w/2,-d/2,d/2,-1),(1,w/2,-d/2,d/2,1)):
    t=a0+2.6
    while t<a1-1.2:
        if ax==0: boxr(b,t-1.2,t+1.2,c-0.06,c+0.06,0.1,H-0.5,'M_ShowroomGlass')
        else: boxr(b,c-0.06,c+0.06,t-1.2,t+1.2,0.1,H-0.5,'M_ShowroomGlass')
        t+=2.6
for k in range(13): boxr(b,-w/2+1.0+k*2.4-0.14,-w/2+1.0+k*2.4+0.14,-d/2-0.12,-d/2+0.12,0,H,'M_Trim')
boxr(b,-w/2-0.3,w/2+0.3,-d/2-0.3,d/2+0.3,H+0.5,H+0.9,'M_ShowroomFloor')
boxr(b,-4.0,4.0,-d/2+0.1,-d/2+0.25,0,2.6,'M_GlassDoor')
boxr(b,-w/2,w/2,d/2-0.2,d/2,0,H,'M_WallPale')
text_obj('BLD_Showroom__SIGN','COASTLINE MOTORS',1.2,'M_SignGlow',BL,r,(0,-d/2-0.35,H+0.75))
done(b,'BLD_Showroom__BODY',BL,r)
col('BLD_Showroom__COL_Main',BL,r,-w/2,w/2,-d/2,d/2,0,H+0.9)
export(r,OUT+"\\Buildings\\BLD_Showroom.fbx")
wipe('BLD_ParkingGarage'); r=emp('BLD_ParkingGarage',BL,None,(0,820,0),3); b=NB()
w,d=26.0,34.0; fl=3.25; nf=3
boxr(b,-w/2,w/2,-d/2,d/2,0,fl*nf+0.4,'M_Concrete')
for lv in range(nf):
    z0=fl*lv
    for k in range(11): boxr(b,-w/2+0.6+k*2.3-0.55,-w/2+0.6+k*2.3+0.55,-d/2-0.05,-d/2+0.05,z0+0.7,z0+fl-0.35,'M_Window')
    for k in range(14): boxr(b,-w/2-0.05,-w/2+0.05,-d/2+0.8+k*2.3-0.55,-d/2+0.8+k*2.3+0.55,z0+0.7,z0+fl-0.35,'M_Window')
    for k in range(14): boxr(b,w/2-0.05,w/2+0.05,-d/2+0.8+k*2.3-0.55,-d/2+0.8+k*2.3+0.55,z0+0.7,z0+fl-0.35,'M_Window')
    boxr(b,-w/2-0.3,w/2+0.3,-d/2-0.3,d/2+0.3,z0+fl-0.45,z0+fl,'M_Trim')
boxr(b,-w/2-0.4,w/2+0.4,-d/2-0.4,d/2+0.4,fl*nf,fl*nf+0.5,'M_Trim')
boxr(b,-3.6,3.6,-d/2-0.1,-d/2+0.2,0,2.9,'M_MetalDoor')
boxr(b,-4.2,4.2,-d/2-0.8,-d/2-0.2,2.9,3.3,'M_Trim')
for lv in range(nf):
    z0=fl*lv+0.02
    for k in range(4):
        boxr(b,-w/2+2.0+k*5.0-1.4,-w/2+2.0+k*5.0+1.4,-d/2+1.2,-d/2+6.0,z0,z0+0.06,'M_Trim')
        boxr(b,-w/2+2.0+k*5.0-0.06,-w/2+2.0+k*5.0+0.06,-d/2+1.2,-d/2+6.0,z0,z0+0.06,'M_Trim')
boxr(b,-2.0,2.0,d/2-3.0,d/2-0.6,0,fl*nf,'M_Concrete')
for lv in range(nf-1): boxr(b,-2.0,2.0,d/2-3.0,d/2-0.6,fl*(lv+1),fl*(lv+1)+0.06,'M_Trim')
text_obj('BLD_ParkingGarage__SIGN','PARK',0.9,'M_SignGlow',BL,r,(0,-d/2-0.95,3.5))
done(b,'BLD_ParkingGarage__BODY',BL,r)
col('BLD_ParkingGarage__COL_Main',BL,r,-w/2,w/2,-d/2,d/2,0,fl*nf+0.5)
export(r,OUT+"\\Buildings\\BLD_ParkingGarage.fbx")
print('airfield+landmarks done')
print('save',bpy.ops.wm.save_mainfile())
