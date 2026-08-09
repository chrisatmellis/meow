#!/usr/bin/env python3
"""Turns a skinned USD cat into the binary the game loads, UVs and all.

Runs `unwrap.py`'s logic for texture coordinates, then adds the two things the
game needs to animate the result: the skeleton, and which bone is which.

## The joints have no names

The FBX to USD conversion stripped them — all thirty-six are called `n8` through
`n49`. So the roles are worked out from the rest pose, which is unambiguous once
you look at it: the cat faces +X, up is +Y, and the skeleton is a textbook
quadruped. The root is the pelvis; the chain running backwards and down is the
tail; the two chains that descend to y ~= 0.013 behind the root are the hind legs,
the two in front of it the forelegs, split left and right by the sign of z; the
chain running forward along y ~= 0.2 is the spine, ending at the neck and skull;
above the skull sit two symmetric leaves, which are ears; below and forward of it
a short chain, which is the jaw.

Inferred rather than hard-coded so that swapping the model for another one does
not silently produce a cat whose head is its left hind foot — and then checked
against what the shape of the skeleton says it must be, so a bad inference fails
here rather than on device.

    Tools/usd/export-cat.py <in.usdz> <out.catmesh>
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unwrap import build, unwrap, split_seam, report, dot, sub, cross  # noqa: E402

MAGIC = b'MEOWCAT2'

# The roles the game's rig knows how to drive. Anything not named here is still
# carried and still skinned — it simply follows its parent.
ROLES = ['hips', 'spineBase', 'spineMid', 'chest', 'neck', 'head', 'jaw',
         'earL', 'earR', 'tail0', 'tail1', 'tail2', 'tail3']
for side in ('L', 'R'):
    for limb in ('fore', 'hind'):
        for seg in ('Hip', 'Knee', 'Ankle', 'Paw'):
            ROLES.append(f'{limb}{seg}{side}')


def infer_roles(pos, parent, children):
    """Maps joint index -> role name, from the rest pose alone."""
    n = len(pos)
    root = next(i for i in range(n) if parent[i] < 0)

    def chain_from(i):
        out = [i]
        while children[out[-1]]:
            out.append(max(children[out[-1]],
                           key=lambda k: _sq(sub(pos[k], pos[out[-1]]))))
        return out

    def descends(i):
        """A limb: its chain ends near the floor."""
        return pos[chain_from(i)[-1]][1] < pos[root][1] * 0.35

    roles = {}
    roles[root] = 'hips'

    # The tail leaves the root going backwards (-x) and never approaches the floor.
    tail = None
    for k in children[root]:
        c = chain_from(k)
        if pos[c[-1]][0] < pos[root][0] and not descends(k):
            tail = c
    if tail:
        for i, j in enumerate(tail[:4]):
            roles[j] = f'tail{i}'

    # The spine is the other child of the root, and runs forward.
    spine_root = next((k for k in children[root] if k not in (tail[0] if tail else -1,)), None)
    if spine_root is None:
        raise SystemExit('no spine leaving the root')
    roles[spine_root] = 'spineBase'

    # Legs come in symmetric pairs offset to either side; the spine itself runs
    # down the middle at z ~= 0. That is what separates a limb from the next
    # vertebra, and it is worth stating because the obvious test does not work:
    # "its chain reaches the floor" is true of the spine too, since following the
    # longest child from any vertebra eventually walks out along a leg.
    span = max(abs(p[2]) for p in pos) or 1.0
    legs = [j for j in range(n)
            if parent[j] >= 0 and j not in roles
            and abs(pos[j][2]) > span * 0.25 and descends(j)]
    # Group by attachment point; the more rearward group is the hind pair.
    by_parent = {}
    for j in legs:
        by_parent.setdefault(parent[j], []).append(j)
    # Only the roots of each limb, not every joint down it.
    by_parent = {k: v for k, v in by_parent.items() if k not in legs}
    groups = sorted(by_parent.items(), key=lambda kv: pos[kv[0]][0])
    if len(groups) != 2:
        raise SystemExit(f'expected two pairs of legs, found {len(groups)}')
    for limb, (attach, js) in zip(('hind', 'fore'), groups):
        if len(js) != 2:
            raise SystemExit(f'{limb} legs: expected 2, found {len(js)}')
        for j in js:
            # +z is the cat's right, facing +x with +y up.
            side = 'R' if pos[j][2] > 0 else 'L'
            for seg, k in zip(('Hip', 'Knee', 'Ankle', 'Paw'), chain_from(j)):
                roles[k] = f'{limb}{seg}{side}'

    # Walk the midline forward from the pelvis to the skull.
    #
    # The skull is where the spine stops being a chain and fans out — into ears,
    # a jaw, and a nose. Legs fan out too, at the shoulder, which is why the
    # branches already claimed as limbs do not count: the first joint with two or
    # more *unclaimed* children is the head, and the joint before it is the neck.
    #
    # Taking "the forward-most joint that has children" instead gets you the
    # middle of the jaw, which is forward of the skull and still has a chin
    # hanging off it. That was the first attempt and it put the head inside the
    # mouth.
    node, spine_chain = spine_root, []
    skull = None
    for _ in range(n):
        spine_chain.append(node)
        free = [k for k in children[node] if k not in roles]
        if len(free) >= 2:
            skull = node
            break
        if not free:
            break
        node = free[0]
    if skull is None:
        raise SystemExit('never found a skull walking forward from the pelvis')

    roles[skull] = 'head'
    neck = parent[skull]
    if neck >= 0 and neck not in roles:
        roles[neck] = 'neck'

    # Whatever vertebrae are left between the pelvis and the neck.
    mid = [j for j in spine_chain if j not in roles]
    if mid:
        roles[mid[len(mid) // 2]] = 'spineMid'
    if len(mid) > 1:
        roles[mid[-1]] = 'chest'

    # Ears sit above the skull and come as a symmetric pair; the jaw is the
    # branch below it that is itself a chain rather than a single leaf.
    kids = [k for k in children[skull] if k not in roles]
    above = sorted([k for k in kids if pos[k][1] > pos[skull][1]], key=lambda k: pos[k][2])
    if len(above) == 2:
        roles[above[0]] = 'earL'
        roles[above[1]] = 'earR'
    below = [k for k in kids if k not in roles and children[k]]
    if below:
        roles[max(below, key=lambda k: len(chain_from(k)))] = 'jaw'
    return roles


def _sq(v):
    return dot(v, v)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, dst = sys.argv[1], sys.argv[2]
    model = build(src)
    scale = model['scale']

    torso = max(model['chain']) if model['chain'] else 1.0
    v_per_metre = 1.0 / max(1e-6, torso * scale)

    uvs = unwrap(model, v_per_metre)
    pts, nrm, tris, uvs = split_seam(model['points'], model['normals'],
                                     model['tris'], uvs)

    jp, par = model['joint_pos'], model['parent']
    children = [[] for _ in jp]
    for i, p in enumerate(par):
        if p >= 0:
            children[p].append(i)
    roles = infer_roles(jp, par, children)

    # The seam duplicates inherit their original's skin weights, or half the cat
    # would come unstuck from the skeleton down one line.
    n_inf = model['ji_n']
    ji, jw = list(model['ji']), list(model['jw'])
    original_count = len(model['points'])
    for i in range(original_count, len(pts)):
        src_i = _origin_of(pts[i], model['points'])
        ji.extend(model['ji'][src_i * n_inf:(src_i + 1) * n_inf])
        jw.extend(model['jw'][src_i * n_inf:(src_i + 1) * n_inf])

    blob = bytearray()
    blob += MAGIC
    blob += struct.pack('<IIII', len(pts), len(tris) * 3, len(jp), n_inf)
    for p in pts:
        blob += struct.pack('<3f', *(c * scale for c in p))
    for v in (nrm or [(0.0, 1.0, 0.0)] * len(pts)):
        blob += struct.pack('<3f', *v)
    for u, v in uvs:
        blob += struct.pack('<2f', u, v)
    for t in tris:
        blob += struct.pack('<3I', *t)
    for i in range(len(pts) * n_inf):
        blob += struct.pack('<H', ji[i])
    for i in range(len(pts) * n_inf):
        blob += struct.pack('<f', jw[i])
    for i in range(len(jp)):
        blob += struct.pack('<h', par[i])
        # The full world bind matrix, column-major, with the translation scaled
        # into metres. Positions alone are not enough: this skeleton's bind pose
        # has rotation in it.
        m = list(model['bind'][i])
        m[12] *= scale
        m[13] *= scale
        m[14] *= scale
        blob += struct.pack('<16f', *m)
    # Roles, as a fixed-order table of joint indices; -1 for a role this skeleton
    # does not have.
    inv = {r: -1 for r in ROLES}
    for j, r in roles.items():
        inv[r] = j
    blob += struct.pack('<I', len(ROLES))
    for r in ROLES:
        blob += struct.pack('<h', inv[r])

    with open(dst, 'wb') as f:
        f.write(blob)

    stats = report(pts, tris, uvs, scale)
    print(f'  wrote {dst}  ({len(blob)} bytes)')
    print(f'  vertices {len(model["points"])} -> {len(pts)}  triangles {len(tris)}  joints {len(jp)}')
    print(f'  texel density p10/median/p90: {stats["texels_per_metre_p10"]}'
          f' / {stats["texels_per_metre_median"]} / {stats["texels_per_metre_p90"]}')
    missing = [r for r in ROLES if inv[r] < 0]
    print(f'  roles resolved: {len(ROLES) - len(missing)}/{len(ROLES)}'
          + (f'   missing: {", ".join(missing)}' if missing else ''))
    for r in ROLES:
        j = inv[r]
        if j >= 0:
            p = [round(c * scale, 3) for c in jp[j]]
            print(f'     {r:<12} -> joint {j:>2}   at {p}')
    return 0


def _origin_of(point, originals):
    for i, o in enumerate(originals):
        if o == point:
            return i
    raise SystemExit('seam duplicate has no original')


if __name__ == '__main__':
    sys.exit(main())
