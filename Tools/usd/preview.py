"""Renders an unwrapped mesh with two test textures, so the UVs can be judged by
eye rather than by a table of numbers.

    checker  square-ness shows stretch; the blue line is u = 0.25 (the spine) and
             the orange line is u = 0.75 (the belly), so the coat texture's own
             convention is visible on the model.
    tabby    bands of constant v, which is what a mackerel tabby is. If these do
             not ring the body, the unwrap is wrong however good its statistics.

    Tools/usd/preview.py            reads ./cat-uv.json, writes uv-*.png
"""
import json, math, struct, zlib

d = json.load(open('cat-uv.json'))
P = d['positions']; N = d['normals']; UV = d['uvs']; I = d['indices']
tris = [tuple(I[i:i+3]) for i in range(0, len(I), 3)]

def checker(u, v):
    c = (int(math.floor(u*16)) + int(math.floor(v*16))) & 1
    # tint the u=0.25 (spine) and u=0.75 (belly) lines so the convention is visible
    if abs((u % 1.0) - 0.25) < 0.012: return (90, 200, 255)
    if abs((u % 1.0) - 0.75) < 0.012: return (255, 170, 90)
    return (235, 235, 235) if c else (120, 120, 128)

def tabby(u, v):
    base = (196, 170, 128)
    mark = (92, 70, 48)
    belly = 1 - min(1.0, abs(((u % 1.0) - 0.75)) / 0.22)
    stripes = 13
    band = (v * stripes) % 1.0
    w = 0.34 * (1 - belly * 0.85)
    col = mark if band < w else base
    if belly > 0:
        col = tuple(int(c * (1 - belly * 0.55) + 232 * belly * 0.55) for c in col)
    return col

def render(path, tex, eye, target, up=(0,1,0), W=560, H=560, fov=32.0):
    def sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
    def cr(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    def dt(a,b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
    def nm(a):
        l=math.sqrt(dt(a,a)) or 1; return (a[0]/l,a[1]/l,a[2]/l)
    fwd=nm(sub(target,eye)); right=nm(cr(fwd,up)); upv=cr(right,fwd)
    f=1.0/math.tan(math.radians(fov)/2)
    zb=[1e9]*(W*H); img=[(14,14,18)]*(W*H); light=nm((0.45,0.8,0.6))
    for t in tris:
        wp=[P[i] for i in t]
        n=nm(cr(sub(wp[1],wp[0]),sub(wp[2],wp[0])))
        sh=0.30+0.70*max(0.0,dt(n,light))
        sp=[]
        for p in wp:
            dd=sub(p,eye); cam=(dt(dd,right),dt(dd,upv),dt(dd,fwd))
            if cam[2]<=0.001: sp=None;break
            sp.append(((cam[0]/cam[2])*f,(cam[1]/cam[2])*f,cam[2]))
        if not sp: continue
        px=[((0.5+s[0]*0.5)*W,(0.5-s[1]*0.5)*H,s[2]) for s in sp]
        (x0,y0,z0),(x1,y1,z1),(x2,y2,z2)=px
        area=(x1-x0)*(y2-y0)-(x2-x0)*(y1-y0)
        if abs(area)<1e-9: continue
        for y in range(max(0,int(min(p[1] for p in px))), min(H-1,int(max(p[1] for p in px))+1)+1):
            for x in range(max(0,int(min(p[0] for p in px))), min(W-1,int(max(p[0] for p in px))+1)+1):
                cx,cy=x+0.5,y+0.5
                w0=((x1-cx)*(y2-cy)-(x2-cx)*(y1-cy))/area
                w1=((x2-cx)*(y0-cy)-(x0-cx)*(y2-cy))/area
                w2=1-w0-w1
                if w0<0 or w1<0 or w2<0: continue
                z=w0*z0+w1*z1+w2*z2; i=y*W+x
                if z<zb[i]:
                    zb[i]=z
                    u=w0*UV[t[0]][0]+w1*UV[t[1]][0]+w2*UV[t[2]][0]
                    v=w0*UV[t[0]][1]+w1*UV[t[1]][1]+w2*UV[t[2]][1]
                    c=tex(u,v)
                    img[i]=tuple(min(255,int(ch*sh)) for ch in c)
    raw=b''.join(b'\x00'+b''.join(bytes(img[y*W+x]) for x in range(W)) for y in range(H))
    ck=lambda t,dd:struct.pack('>I',len(dd))+t+dd+struct.pack('>I',zlib.crc32(t+dd))
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ck(b'IHDR',struct.pack('>IIBBBBB',W,H,8,2,0,0,0))+ck(b'IDAT',zlib.compress(raw,6))+ck(b'IEND',b''))
    print('wrote',path)

xs=[p[0] for p in P]; ys=[p[1] for p in P]; zs=[p[2] for p in P]
c=((min(xs)+max(xs))/2,(min(ys)+max(ys))/2,(min(zs)+max(zs))/2)
r=max(max(xs)-min(xs),max(ys)-min(ys),max(zs)-min(zs))
render('uv-checker.png', checker, (c[0]-r*0.55,c[1]+r*0.45,c[2]+r*1.6), c)
render('uv-tabby.png',   tabby,   (c[0]-r*0.55,c[1]+r*0.45,c[2]+r*1.6), c)
render('uv-tabby-front.png', tabby, (c[0]+r*1.7,c[1]+r*0.35,c[2]+r*0.5), c)
