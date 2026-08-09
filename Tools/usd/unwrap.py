#!/usr/bin/env python3
"""Generates UV coordinates for a skinned USD cat, changing nothing else.

The mesh arrived with no `st` primvar, which meant it could only ever be a flat
colour: every pattern, marking and material map in this game is painted into a
texture and applied through UVs. This adds the missing coordinates and touches
nothing else — the same points, the same normals, the same triangles, in the same
order.

## Why per-bone, and not one cylinder

The coat texture has a fixed convention, set by `MeshBuilder.loft` and relied on
by `TextureFactory.drawCoat`:

    u  runs once around the part.  u = 0.25 is the spine, u = 0.75 is the belly.
    v  runs along the part, advancing by 1.0 per torso length.

A mackerel tabby's stripes are therefore bands of constant v — rings around the
body — and the belly gradient is a vertical band at u = 0.75.

Wrapping the whole cat in a single cylinder about its long axis satisfies that for
the torso and ruins everything else. The legs hang *below* the body, so relative
to one central axis every point on all four of them sits at roughly u = 0.75: the
legs would collapse into a sliver of belly colour, stretched the length of the
texture.

The procedural cat never had this problem because it is built as a dozen separate
lofts, each with its own axis. So this does the same thing, using the skeleton the
file already carries: each vertex is unwrapped around the bone that owns it. That
is the same construction, arrived at from the other direction.

## v is continuous along the skeleton

`v` accumulates down the bone chain rather than restarting per bone, so stripes
run unbroken from shoulder to hip instead of resetting at every joint — and carry
on down the legs and out along the tail, which is what a real tabby does.

    Tools/usd/unwrap.py <in.usdz|in.usdc> <out.json>
"""
import json
import math
import sys
import zipfile
import tempfile
import os

from pxr import Usd, UsdGeom, UsdSkel, Gf


def load_stage(path):
    """USDZ is a zip; the payload inside is what pxr wants to open."""
    if path.endswith('.usdz'):
        with zipfile.ZipFile(path) as z:
            inner = [n for n in z.namelist() if n.endswith(('.usdc', '.usda', '.usd'))]
            if not inner:
                raise SystemExit('no usd payload inside the usdz')
            tmp = tempfile.mkdtemp()
            path = z.extract(inner[0], tmp)
    return Usd.Stage.Open(path)


def first_of_type(stage, type_name):
    for p in stage.Traverse():
        if p.GetTypeName() == type_name:
            return p
    return None


def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def mul(a, k): return (a[0]*k, a[1]*k, a[2]*k)
def dot(a, b): return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def norm(a):
    l = math.sqrt(dot(a, a))
    return (a[0]/l, a[1]/l, a[2]/l) if l > 1e-12 else (0.0, 1.0, 0.0)


def build(path_in):
    stage = load_stage(path_in)
    scale = UsdGeom.GetStageMetersPerUnit(stage) or 1.0

    mesh_prim = first_of_type(stage, 'Mesh')
    skel_prim = first_of_type(stage, 'Skeleton')
    if mesh_prim is None:
        raise SystemExit('no Mesh in the stage')
    mesh = UsdGeom.Mesh(mesh_prim)

    points = [tuple(p) for p in mesh.GetPointsAttr().Get()]
    counts = list(mesh.GetFaceVertexCountsAttr().Get())
    indices = list(mesh.GetFaceVertexIndicesAttr().Get())
    normals = mesh.GetNormalsAttr().Get()
    normals = [tuple(n) for n in normals] if normals else None

    # Triangulate by fanning. Everything here is already triangles, but a quad
    # would otherwise be dropped silently.
    tris, at = [], 0
    for c in counts:
        for k in range(1, c - 1):
            tris.append((indices[at], indices[at + k], indices[at + k + 1]))
        at += c

    # --- Skeleton: world rest positions, parents, and a direction per bone.
    api = UsdGeom.PrimvarsAPI(mesh_prim)
    ji = api.GetPrimvar('skel:jointIndices')
    jw = api.GetPrimvar('skel:jointWeights')
    skel = UsdSkel.Skeleton(skel_prim) if skel_prim else None

    joint_pos, parent = [], []
    if skel:
        paths = [str(j) for j in (skel.GetJointsAttr().Get() or [])]
        binds = skel.GetBindTransformsAttr().Get() or []
        joint_pos = [tuple(b.ExtractTranslation()) for b in binds]
        index_of = {p: i for i, p in enumerate(paths)}
        for p in paths:
            cut = p.rfind('/')
            parent.append(index_of.get(p[:cut], -1) if cut >= 0 else -1)

    children = [[] for _ in joint_pos]
    for i, p in enumerate(parent):
        if p >= 0:
            children[p].append(i)

    # A bone points at its child. A leaf keeps its parent's direction, which is
    # what makes a toe or a tail tip continue the limb rather than pick an
    # arbitrary axis.
    direction, length = [None] * len(joint_pos), [0.0] * len(joint_pos)
    order = sorted(range(len(joint_pos)), key=lambda i: 0 if parent[i] < 0 else 1)
    for i in sorted(range(len(joint_pos)), key=lambda i: _depth(i, parent)):
        kids = children[i]
        if kids:
            # The longest child is the continuation of the limb; the others are
            # branches off it.
            best = max(kids, key=lambda k: dot(sub(joint_pos[k], joint_pos[i]),
                                               sub(joint_pos[k], joint_pos[i])))
            d = sub(joint_pos[best], joint_pos[i])
            length[i] = math.sqrt(dot(d, d))
            direction[i] = norm(d)
        else:
            direction[i] = direction[parent[i]] if parent[i] >= 0 else (1.0, 0.0, 0.0)
            length[i] = length[parent[i]] * 0.5 if parent[i] >= 0 else 1.0

    # Distance from the root along the chain, so v is continuous down the body.
    chain = [0.0] * len(joint_pos)
    for i in sorted(range(len(joint_pos)), key=lambda i: _depth(i, parent)):
        if parent[i] >= 0:
            chain[i] = chain[parent[i]] + length[parent[i]]

    return dict(points=points, tris=tris, normals=normals, scale=scale,
                joint_pos=joint_pos, parent=parent, direction=direction,
                length=length, chain=chain,
                ji=list(ji.Get()) if ji else None, ji_n=ji.GetElementSize() if ji else 0,
                jw=list(jw.Get()) if jw else None)


def _depth(i, parent, _cache={}):
    d, seen = 0, i
    while parent[seen] >= 0:
        seen = parent[seen]
        d += 1
        if d > 256:
            break
    return d


def unwrap(model, v_per_metre):
    """Assigns (u, v) to every vertex. Returns per-vertex uvs in the mesh's own
    indexing — seam duplication happens afterwards, on triangles."""
    pts, scale = model['points'], model['scale']
    ji, jw, n = model['ji'], model['jw'], model['ji_n']
    jp, dr, ch = model['joint_pos'], model['direction'], model['chain']

    uvs = []
    for vi, p in enumerate(pts):
        j = 0
        if ji and jw:
            best = -1.0
            for k in range(n):
                w = jw[vi * n + k]
                if w > best:
                    best, j = w, ji[vi * n + k]
        origin, axis = jp[j], dr[j]

        local = sub(p, origin)
        along = dot(local, axis)
        radial = sub(local, mul(axis, along))

        # A stable frame around the bone. World up, made perpendicular to the
        # bone, plays the loft's local +Y — which is the axis the coat texture
        # calls the spine at u = 0.25. Bones that are themselves vertical (none
        # here, but a leg could be) fall back to +Z so the frame never collapses.
        up = sub((0.0, 1.0, 0.0), mul(axis, dot((0.0, 1.0, 0.0), axis)))
        if dot(up, up) < 1e-8:
            up = sub((0.0, 0.0, 1.0), mul(axis, dot((0.0, 0.0, 1.0), axis)))
        up = norm(up)
        side = norm(cross(axis, up))

        theta = math.atan2(dot(radial, up), dot(radial, side))
        u = (theta / (2 * math.pi)) % 1.0
        v = (ch[j] + along) * scale * v_per_metre
        uvs.append((u, v))
    return uvs


def split_seam(points, normals, tris, uvs):
    """Duplicates vertices where u wraps, so no triangle runs backwards across
    the whole texture.

    A cylindrical unwrap has to have a seam: somewhere the angle passes 2*pi and
    starts again at 0. A triangle straddling it would interpolate u from 0.98 to
    0.02 the long way round, smearing the entire texture across one facet — the
    classic band down the side of an unwrapped model. Splitting keeps the surface
    identical: the duplicate sits at exactly the same place with exactly the same
    normal, and only its texture coordinate differs.
    """
    out_p, out_n, out_uv = list(points), list(normals or []), list(uvs)
    made = {}
    out_tris = []
    for tri in tris:
        us = [uvs[i][0] for i in tri]
        wrapped = max(us) - min(us) > 0.5
        new = []
        for i in tri:
            u, v = uvs[i]
            if wrapped and u < 0.5:
                key = (i, 1)
                if key not in made:
                    made[key] = len(out_p)
                    out_p.append(points[i])
                    if normals:
                        out_n.append(normals[i])
                    out_uv.append((u + 1.0, v))
                new.append(made[key])
            else:
                new.append(i)
        out_tris.append(tuple(new))
    return out_p, (out_n if normals else None), out_tris, out_uv


def report(points, tris, uvs, scale):
    """Stretch and sanity, because an unwrap that looks plausible in a list of
    numbers can still be unusable."""
    ratios, degenerate = [], 0
    for (a, b, c) in tris:
        p = [mul(points[i], scale) for i in (a, b, c)]
        e1, e2 = sub(p[1], p[0]), sub(p[2], p[0])
        area3 = 0.5 * math.sqrt(max(0.0, dot(cross(e1, e2), cross(e1, e2))))
        ua = [uvs[i] for i in (a, b, c)]
        area2 = 0.5 * abs((ua[1][0]-ua[0][0]) * (ua[2][1]-ua[0][1])
                          - (ua[2][0]-ua[0][0]) * (ua[1][1]-ua[0][1]))
        if area2 < 1e-12 or area3 < 1e-12:
            degenerate += 1
            continue
        ratios.append(math.sqrt(area2 / area3))
    ratios.sort()
    def pct(q): return ratios[min(len(ratios) - 1, int(q * len(ratios)))]
    return dict(triangles=len(tris), degenerate=degenerate,
                texels_per_metre_p10=round(pct(0.10), 2),
                texels_per_metre_median=round(pct(0.50), 2),
                texels_per_metre_p90=round(pct(0.90), 2),
                stretch_p90_over_p10=round(pct(0.90) / max(1e-9, pct(0.10)), 2))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, dst = sys.argv[1], sys.argv[2]
    model = build(src)

    # One texture repeat per torso length, matching `CatRig.vSpan`, which divides
    # a part's length by the torso's. The torso here is the chain from the hips to
    # the head, measured off the skeleton rather than guessed.
    torso = max(model['chain']) if model['chain'] else 1.0
    body_m = max(1e-6, torso * model['scale'])
    v_per_metre = 1.0 / body_m

    uvs = unwrap(model, v_per_metre)
    pts, nrm, tris, uvs = split_seam(model['points'], model['normals'], model['tris'], uvs)

    stats = report(pts, tris, uvs, model['scale'])
    stats.update(source=os.path.basename(src),
                 vertices_in=len(model['points']), vertices_out=len(pts),
                 seam_duplicates=len(pts) - len(model['points']),
                 joints=len(model['joint_pos']),
                 metres_per_unit=model['scale'],
                 v_per_metre=round(v_per_metre, 3))

    out = dict(stats=stats,
               positions=[[round(c * model['scale'], 6) for c in p] for p in pts],
               normals=[[round(c, 6) for c in n] for n in nrm] if nrm else None,
               uvs=[[round(u, 6), round(v, 6)] for (u, v) in uvs],
               indices=[i for t in tris for i in t])
    with open(dst, 'w') as f:
        json.dump(out, f)
    for k, v in stats.items():
        print(f'  {k}: {v}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
