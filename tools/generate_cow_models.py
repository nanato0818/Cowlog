"""Generate shared low-poly cow geometry, GLB and transparent software renders.
Install tools/cow-model-requirements.txt. No Blender or GPU required.
Coordinates: Y up, +Z forward; origin at hoof contact center.
"""
from pathlib import Path
import json
import numpy as np
import trimesh
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / 'apps/mobile/cowlog_flutter/assets/models'
OUT.mkdir(parents=True, exist_ok=True)
parts = []
implicit = []
def ell(name, center, scale, material='coat', tilt=0):
    m = trimesh.creation.icosphere(subdivisions=3 if name in ['ribcage', 'skull', 'rump'] else 2)
    m.apply_scale(scale)
    if tilt:
        m.apply_transform(trimesh.transformations.rotation_matrix(tilt, [1,0,0]))
    m.apply_translation(center)
    parts.append((name,m,material))
    if material == 'coat': implicit.append(('ell', np.array(center), np.array(scale), tilt))
def link(name,a,b,r1,r2,material='coat'):
    a,b=np.array(a),np.array(b)
    if material == 'coat': implicit.append(('link', a, b, r1, r2))
    d=b-a
    # Smooth tapered limb between anatomical joints.
    n=16
    verts=[]
    z=d/np.linalg.norm(d)
    x=np.cross(z,[0,0,1] if abs(z[2])<.9 else [1,0,0]); x/=np.linalg.norm(x)
    y=np.cross(z,x)
    for t,r in [(0,r1),(.12,r1),(.86,r2),(1,r2)]:
        for angle in np.arange(n)*2*np.pi/n:
            verts.append(a+t*d+r*(np.cos(angle)*x+np.sin(angle)*y))
    faces=[]
    for row in range(3):
        for i in range(n):
            j=(i+1)%n; q=row*n
            faces.extend([[q+i,q+j,q+n+j],[q+i,q+n+j,q+n+i]])
    faces += [[0,i+1,i] for i in range(1,n-1)]
    faces += [[3*n,3*n+i,3*n+i+1] for i in range(1,n-1)]
    parts.append((name,trimesh.Trimesh(verts,faces,process=True),material))
# Anatomical lofts: (axis position, first center, second center, radii).
# Rounded rectangular ribs preserve a level spine instead of stacked spheres.
def loft(name, axis, sections, power=2.4):
    implicit.append(('loft', axis, np.array(sections), power))

loft('trunk',2,[(-.94,0,1.22,.02,.04),(-.86,0,1.22,.22,.29),
    (-.68,0,1.22,.29,.32),(-.43,0,1.19,.31,.35),
    (-.10,0,1.19,.32,.35),(.22,0,1.23,.27,.31),
    (.40,0,1.24,.22,.28),(.49,0,1.25,.08,.18)])
# A wedge rising from brisket to poll; blends into shoulders and jaw.
loft('neck',1,[(.99,0,.39,.08,.12),(1.08,0,.43,.14,.13),
    (1.27,0,.54,.19,.23),(1.44,0,.65,.15,.19),
    (1.58,0,.72,.12,.13),(1.65,0,.74,.07,.07)],2.2)
# Broad forehead, subtle cheek narrowing, widening nose. Straight sloped bridge.
loft('head',1,[(1.105,0,1.10,.10,.07),(1.16,0,1.09,.132,.10),
    (1.25,0,1.00,.113,.12),(1.36,0,.91,.128,.14),
    (1.49,0,.82,.161,.145),(1.59,0,.77,.151,.12),
    (1.64,0,.75,.11,.08),(1.66,0,.74,.02,.025)],2.7)
ell('muzzle',(0,1.145,1.13),(.143,.073,.085),'muzzle')
ell('lip',(0,1.098,1.125),(.122,.018,.069),'lip')
for side in [-1,1]:
    # Thin leaf ears with tips tapering, not round discs.
    loft('ear',0,[(side*.115,1.565,.76,.025,.035),
        (side*.22,1.57,.755,.043,.074),
        (side*.32,1.58,.74,.029,.053),
        (side*.385,1.59,.73,.002,.006)],2)
    ell('inner_ear',(side*.257,1.585,.784),(.091,.014,.040),'inner')
    ell('eyelid',(side*.140,1.486,.923),(.014,.017,.014),'lid')
    ell('eye',(side*.144,1.486,.934),(.010,.009,.008),'eye')
    ell('nostril',(side*.086,1.164,1.199),(.025,.014,.010),'eye',tilt=side*.2)
    for front in [True,False]:
        z=.27 if front else -.70
        # Hip/shoulder -> knee/hock -> fetlock; long slender cannon bones.
        sections=([(.085,side*.225,z+.04,.035,.043),
            (.15,side*.225,z+.015,.041,.046),
            (.43,side*.22,z-.005,.034,.038),
            (.58,side*.215,z+.015,.049,.054),
            (.84,side*.215,z,.067,.075),
            (1.17,side*.20,z,.105,.135)] if front else
            [(.085,side*.235,z+.07,.035,.044),
            (.16,side*.235,z+.045,.041,.045),
            (.46,side*.23,z-.095,.040,.046),
            (.56,side*.225,z-.10,.052,.06),
            (.80,side*.215,z+.045,.073,.105),
            (1.21,side*.20,z,.13,.17)])
        loft('leg',1,sections,2.2)
        ell('hoof',(side*(.225 if front else .235),.049,z+(.052 if front else .082)),(.046,.049,.067),'hoof')
        ell('hoof_split',(side*(.225 if front else .235),.038,z+(.116 if front else .146)),(.003,.025,.004),'eye')
tag=trimesh.creation.box(extents=[.045,.064,.008])
tag.apply_translation([.285,1.535,.814])
parts.append(('ear_tag',tag,'tag'))
# Fine hanging tail, small switch and dairy udder.
link('tail',(0,1.46,-.87),(.025,.88,-.99),.019,.012)
link('tail_lower',(.025,.88,-.99),(.07,.44,-1.02),.012,.009)
ell('tail_switch',(.07,.38,-1.02),(.029,.09,.027),'hoof')
ell('udder',(0,.865,-.57),(.15,.115,.18),'muzzle')
for x in [-.075,.075]:
    for z in [-.49,-.65]: link('teat',(x,.80,z),(x,.735,z),.015,.010,'muzzle')
# Belt is sampled from the very same neck loft, with only 2 mm clearance.
n=64
v=[]
for yy in [1.312,1.342]:
    t=(yy-1.27)/(.17)
    cz=.54+t*.11; rx=.19-t*.04; rz=.23-t*.04
    for angle in np.arange(n)*2*np.pi/n:
        c,d=np.cos(angle),np.sin(angle)
        v.append([(rx+.002)*np.sign(c)*abs(c)**(2/2.2), yy,
                  cz+(rz+.002)*np.sign(d)*abs(d)**(2/2.2)])
f=[]
for i in range(n):
    j=(i+1)%n; f.extend([[i,j,n+j],[i,n+j,n+i]])
parts.append(('gps_belt',trimesh.Trimesh(v,f,process=False),'collar'))
box=trimesh.creation.box(extents=[.050,.045,.027]);box.apply_translation([0,1.311,.805])
parts.append(('gps_device',box,'collar'))

# Blend the anatomical volumes into a continuous skin, then reduce the mesh.
# This removes the separate-primitive seams without increasing the mobile budget.
from skimage.measure import marching_cubes
step = .012
origin = np.array([-.43, -.04, -1.15])
axes = [np.arange(origin[i], end, step) for i, end in enumerate([.43, 1.74, 1.28])]
xyz = np.stack(np.meshgrid(*axes, indexing='ij'), axis=-1)
field = np.full(xyz.shape[:-1], 100.)
for item in implicit:
    if item[0] == 'loft':
        _, axis, sections, power = item
        sections=sections[np.argsort(sections[:,0])]
        along=xyz[...,axis]
        other=[i for i in range(3) if i!=axis]
        values=[np.interp(along,sections[:,0],sections[:,i]) for i in range(1,5)]
        c1,c2,r1,r2=values
        q=(abs((xyz[...,other[0]]-c1)/r1)**power+abs((xyz[...,other[1]]-c2)/r2)**power)**(1/power)
        distance=(q-1)*np.minimum(r1,r2)
        distance=np.maximum(distance,np.maximum(sections[0,0]-along,along-sections[-1,0]))
    elif item[0] == 'ell':
        _, center, radii, tilt = item
        local = xyz - center
        if tilt:
            rot = trimesh.transformations.rotation_matrix(tilt, [1,0,0])[:3,:3]
            local = local @ rot
        q = local / radii
        # First-order ellipsoid signed distance, exact at the surface.
        k0 = np.linalg.norm(q, axis=-1)
        k1 = np.linalg.norm(q / radii, axis=-1)
        distance = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    else:
        _, a, b, r1, r2 = item
        delta = b-a
        t = np.clip(np.sum((xyz-a)*delta, axis=-1)/np.dot(delta,delta),0,1)
        distance = np.linalg.norm(xyz-a-t[...,None]*delta,axis=-1)-(r1+(r2-r1)*t)
    k = .027
    h = np.maximum(k - np.abs(field-distance), 0) / k
    field = np.minimum(field,distance) - h*h*k*.25
verts, faces, _, _ = marching_cubes(field, level=0, spacing=(step,step,step), allow_degenerate=False)
skin = trimesh.Trimesh(verts+origin,faces,process=True)
skin.update_faces(skin.nondegenerate_faces())
skin.update_faces(skin.unique_faces())
skin.remove_unreferenced_vertices()
skin = max(skin.split(only_watertight=False), key=lambda mesh: len(mesh.faces))
skin.fix_normals()
# Smooth the sampled surface before reduction so grid-scale creases do not
# become long sliver triangles in the mobile mesh.
trimesh.smoothing.filter_taubin(skin, lamb=.5, nu=.5, iterations=18)
skin = skin.simplify_quadric_decimation(face_count=12000, aggression=4)
skin.update_faces(skin.nondegenerate_faces())
skin.remove_unreferenced_vertices()
trimesh.smoothing.filter_taubin(skin, lamb=.45, nu=.5, iterations=6)
skin.fix_normals()
parts = [(name,m,mat) for name,m,mat in parts if mat != 'coat']
parts.insert(0, ('continuous_skin',skin,'coat'))

# Deterministic organic patches shared by both flanks, no external textures.
def coat_color(p,style):
    if style=='unknown': return np.tile([.74,.75,.75],(len(p),1))
    if style=='brown':
        shade=.025*np.sin(p[:,2]*7+p[:,1]*4)
        base = np.array([.62,.40,.23])[None,:]+shade[:,None]
        face = np.clip((p[:,2]-.72)/.28,0,1)*.32
        return base*(1-face[:,None])+np.array([.79,.64,.44])*face[:,None]
    x,y,z=p.T
    field=np.sin(5*z+.7*np.sin(8*y))+.65*np.cos(8*y+.8*np.cos(7*z))+.25*np.sin(12*z-6*y)
    patch=(field>.25)&(y>.62)
    # White belly and lower legs; broad irregular flank islands.
    patch &= ~((y<.99)&(abs(x)<.17))
    face=(z>.82)&(y>1.12)
    blaze=.042+.023*np.clip((y-1.23)/.35,0,1)+.006*np.sin(y*34)
    patch=np.where(face,abs(x)>blaze,patch)
    patch=np.where((y>1.50)&(z>.64),abs(x)>.065,patch)
    return np.where(patch[:,None],[.032,.038,.035],[.89,.88,.84])

palette={'tag':[.93,.67,.10],'lip':[.28,.22,.21],'lid':[.055,.055,.048],'glint':[.65,.66,.63],'muzzle':[.68,.51,.47],'inner':[.64,.48,.41],'eye':[.018,.021,.02],'hoof':[.10,.105,.09],'horn':[.65,.59,.44],'collar':[.19,.21,.22],'collar_led':[.29,.63,.43]}

def render(scene,path,style,avatar=False):
    # Orthographic right-front camera; smooth interpolated normals and z-buffer.
    camera=np.array([1.45,1.60,4.8]) if avatar else np.array([3.5,1.95,2.9]); target=np.array([0,1.43,.83]) if avatar else np.array([0,.85,.03])
    forward=(camera-target); forward/=np.linalg.norm(forward)
    right=np.cross([0,1,0],forward); right/=np.linalg.norm(right)
    up=np.cross(forward,right)
    rot=np.array([right,up,forward]).T
    s=1536
    depth=np.full((s,s),-np.inf); rgb=np.zeros((s,s,4),dtype=np.uint8)
    light=np.array([.6,1,.8]);light/=np.linalg.norm(light)
    for source in scene.geometry.values():
        mesh=source
        if avatar:
            mesh=trimesh.intersections.slice_mesh_plane(mesh,[0,0,1],[0,0,.32],cap=False)
            mesh=trimesh.intersections.slice_mesh_plane(mesh,[0,1,0],[0,.85,0],cap=False)
            if not len(mesh.faces): continue
            from scipy.spatial import cKDTree
            nearest=cKDTree(source.vertices).query(mesh.vertices)[1]
            mesh.vertex_normals=source.vertex_normals[nearest]
            mesh.visual=trimesh.visual.ColorVisuals(mesh=mesh,vertex_colors=np.tile(source.visual.vertex_colors[0],(len(mesh.vertices),1)))
        pos=(mesh.vertices-target)@rot
        if avatar:
            pos[:,:2]*=2.65
        px=pos[:,:2]*s*.42+np.array([s/2,s/2]);px[:,1]=s-px[:,1]
        mesh.metadata['coat']=source.metadata.get('coat',False)
        norm=mesh.vertex_normals
        colors=mesh.visual.vertex_colors[:,:3]/255
        lighting=.48+.52*np.maximum(norm@light,0)
        colors=np.clip(colors*lighting[:,None],0,1)
        for tri in mesh.faces:
            pts=px[tri]; lo=np.maximum(np.floor(pts.min(axis=0)).astype(int),0);hi=np.minimum(np.ceil(pts.max(axis=0)).astype(int),s-1)
            if np.any(lo>hi):continue
            xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
            a,b,c=pts; den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-8:continue
            u=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
            v=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
            w=1-u-v
            d=u*pos[tri[0],2]+v*pos[tri[1],2]+w*pos[tri[2],2]
            region=depth[lo[1]:hi[1]+1,lo[0]:hi[0]+1]
            mask=(u>=0)&(v>=0)&(w>=0)&(d>region)
            region[mask]=d[mask]
            col=u[:,:,None]*colors[tri[0]]+v[:,:,None]*colors[tri[1]]+w[:,:,None]*colors[tri[2]]
            if mesh.metadata.get('coat'):
                world=u[:,:,None]*mesh.vertices[tri[0]]+v[:,:,None]*mesh.vertices[tri[1]]+w[:,:,None]*mesh.vertices[tri[2]]
                base=coat_color(world.reshape(-1,3),style).reshape(*u.shape,3)
                shade=u*lighting[tri[0]]+v*lighting[tri[1]]+w*lighting[tri[2]]
                col=base*shade[:,:,None]
            dest=rgb[lo[1]:hi[1]+1,lo[0]:hi[0]+1];dest[mask,:3]=(col[mask]*255).astype(np.uint8);dest[mask,3]=255
    Image.fromarray(rgb).resize((1024,1024),Image.Resampling.LANCZOS).save(path)

# Planar UVs shared by both flanks: continuous, crisp texture boundaries.
from functools import lru_cache
def coat_uv(p):
    face=(p[:,2]>.82)&(p[:,1]>1.12)
    if len(p)%3==0:
        centers=p.reshape(-1,3,3).mean(axis=1)
        face=np.repeat((centers[:,2]>.82)&(centers[:,1]>1.12),3)
    u=np.where(face,.76+(p[:,0]+.44)/.88*.23,(p[:,2]+1.15)/2.5*.73)
    return np.column_stack([u,(p[:,1]+.05)/1.80])

@lru_cache(maxsize=3)
def coat_texture(style):
    u,v=np.meshgrid(np.linspace(0,1,1024),np.linspace(1,0,1024))
    face=u.ravel()>=.75
    points=np.column_stack([np.where(face,(u.ravel()-.76)/.23*.88-.44,0),
        v.ravel()*1.80-.05,np.where(face,1.,u.ravel()/.73*2.5-1.15)])
    return Image.fromarray((np.clip(coat_color(points,style),0,1)*255).astype(np.uint8).reshape(1024,1024,3))

# Portraits crop the exact full-body geometry, including its fitted collar.

report={}
for style in ['holstein','brown','unknown']:
    scene=trimesh.Scene()
    for i,(name,source,mat) in enumerate(parts):
        mesh=source.copy()
        if mat=='coat':
            mesh=trimesh.Trimesh(vertices=source.vertices[source.faces].reshape(-1,3),faces=np.arange(len(source.faces)*3).reshape(-1,3),vertex_normals=source.vertex_normals[source.faces].reshape(-1,3),process=False)
        color=np.ones((len(mesh.vertices),3)) if mat=='coat' else np.tile(palette[mat],(len(mesh.vertices),1))
        if style=='brown' and mat=='muzzle':
            color=np.tile([.32,.30,.26],(len(mesh.vertices),1))
        if style=='unknown' and mat in ['muzzle','inner','horn','hoof','lip','lid']:
            color=np.tile([.62,.68,.65],(len(mesh.vertices),1))
        rgba=np.column_stack([np.clip(color*255,0,255).astype(np.uint8),np.full(len(color),255,dtype=np.uint8)])
        mesh.visual=trimesh.visual.ColorVisuals(mesh=mesh,vertex_colors=rgba)
        # PBR coat texture; vertex colors for the anatomical details.
        visual=trimesh.visual.texture.TextureVisuals(uv=coat_uv(mesh.vertices) if mat=='coat' else None,material=trimesh.visual.material.PBRMaterial(name=mat,baseColorTexture=coat_texture(style) if mat=='coat' else None,baseColorFactor=[255]*4,metallicFactor=0,roughnessFactor=.88))
        visual.vertex_attributes['color']=rgba
        mesh.visual=visual
        mesh.metadata['coat']=mat=='coat'
        scene.add_geometry(mesh,node_name=f'{name}_{i}',geom_name=f'{name}_{i}')
    count=sum(len(m.faces) for m in scene.geometry.values())
    assert count<=20000,count
    (OUT/f'cow_{style}.glb').write_bytes(scene.export(file_type='glb', include_normals=True))
    # Rendering uses the same geometry, coat texture and detail colors.
    for mesh in scene.geometry.values():
        rgba=mesh.visual.vertex_attributes['color'];mesh.visual=trimesh.visual.ColorVisuals(mesh=mesh,vertex_colors=rgba)
    render(scene,OUT/f'cow_{style}.png',style)
    render(scene,OUT/f'cow_{style}_avatar.png',style,True)
    report[style]={'triangles':count,'bounds':scene.bounds.tolist(),'avatar_source_triangles':count,'portrait_crop':{'min_y':.85,'min_z':.32},'image_size':[1024,1024]}
(OUT/'model_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
