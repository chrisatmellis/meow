#!/usr/bin/env python3
"""Unpacks a .catmesh back into an OBJ, for use as a retopology reference.

The source USDZ the cat was built from is not in this repository — only the
derived `cat.catmesh`. That file still carries everything needed to reconstruct
the surface: positions, normals, UVs and triangles, plus the skeleton. This
turns it back into something Blender can open, so the existing cat can be used
as a shrinkwrap target for building clean topology over it.

Writes up to three files next to the output path:

    <out>.obj          the surface, with normals and the generated UVs
    <out>-skel.obj     the skeleton as a line per bone, to check the joints
    <out>-skel.json    joint parents, rest positions and role names

The OBJ is triangles, because that is what the file holds. That is the whole
problem being solved — see Tools/usd/ASSETS.md.

    Tools/usd/catmesh-to-obj.py MeowRoom/Resources/cat.catmesh /tmp/cat
"""
import json
import struct
import sys

# Must match CatMeshAsset.Role.allCases, in order.
ROLES = [
    'hips', 'spineBase', 'spineMid', 'chest', 'neck', 'head', 'jaw', 'earL', 'earR',
    'tail0', 'tail1', 'tail2', 'tail3',
    'shoulderL', 'upperArmL', 'lowerArmL', 'pawL',
    'shoulderR', 'upperArmR', 'lowerArmR', 'pawR',
    'hipL', 'upperLegL', 'lowerLegL', 'footL',
    'hipR', 'upperLegR', 'lowerLegR', 'footR',
]


class Reader:
    def __init__(self, data):
        self.d, self.at = data, 0

    def take(self, n):
        if self.at + n > len(self.d):
            raise SystemExit(f'truncated at byte {self.at}')
        chunk = self.d[self.at:self.at + n]
        self.at += n
        return chunk

    def u32(self):
        return struct.unpack('<I', self.take(4))[0]

    def i16(self):
        return struct.unpack('<h', self.take(2))[0]

    def u16(self):
        return struct.unpack('<H', self.take(2))[0]

    def f32n(self, n):
        return struct.unpack(f'<{n}f', self.take(4 * n))


def load(path):
    r = Reader(open(path, 'rb').read())
    if r.take(8) != b'MEOWCAT2':
        raise SystemExit('not a MEOWCAT2 file')

    nv, ni, nj, influences = r.u32(), r.u32(), r.u32(), r.u32()

    positions = [r.f32n(3) for _ in range(nv)]
    normals = [r.f32n(3) for _ in range(nv)]
    uvs = [r.f32n(2) for _ in range(nv)]
    indices = [r.u32() for _ in range(ni)]

    joint_indices = [r.u16() for _ in range(nv * influences)]
    joint_weights = [r.f32n(1)[0] for _ in range(nv * influences)]

    parents, binds = [], []
    for _ in range(nj):
        parents.append(r.i16())
        # Four columns of four, column-major, as CatMeshAsset writes them.
        binds.append([r.f32n(4) for _ in range(4)])

    role_count = r.u32()
    roles = [r.i16() for _ in range(role_count)]

    if r.at != len(r.d):
        print(f'note: {len(r.d) - r.at} trailing bytes ignored', file=sys.stderr)

    return dict(nv=nv, ni=ni, nj=nj, influences=influences,
                positions=positions, normals=normals, uvs=uvs, indices=indices,
                joint_indices=joint_indices, joint_weights=joint_weights,
                parents=parents, binds=binds, roles=roles)


def write_obj(m, path):
    with open(path, 'w') as f:
        f.write('# unpacked from cat.catmesh by Tools/usd/catmesh-to-obj.py\n')
        f.write(f'# {m["nv"]} vertices, {m["ni"] // 3} triangles\n')
        f.write('o cat\n')
        for p in m['positions']:
            f.write(f'v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n')
        for t in m['uvs']:
            f.write(f'vt {t[0]:.6f} {t[1]:.6f}\n')
        for n in m['normals']:
            f.write(f'vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n')
        idx = m['indices']
        for i in range(0, len(idx), 3):
            a, b, c = idx[i] + 1, idx[i + 1] + 1, idx[i + 2] + 1
            f.write(f'f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n')


def joint_positions(m):
    """Translation column of each bind matrix — where the joint rests."""
    return [(b[3][0], b[3][1], b[3][2]) for b in m['binds']]


def write_skeleton(m, obj_path, json_path):
    pos = joint_positions(m)
    with open(obj_path, 'w') as f:
        f.write('# skeleton: one line segment per bone\n')
        f.write('o skeleton\n')
        for p in pos:
            f.write(f'v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n')
        for i, parent in enumerate(m['parents']):
            if parent >= 0:
                f.write(f'l {parent + 1} {i + 1}\n')

    named = {}
    for role_index, joint in enumerate(m['roles']):
        if 0 <= role_index < len(ROLES) and joint >= 0:
            named[ROLES[role_index]] = joint

    with open(json_path, 'w') as f:
        json.dump(dict(
            jointCount=m['nj'],
            influencesPerVertex=m['influences'],
            parents=m['parents'],
            restPositions=[list(p) for p in pos],
            roles=named,
            unroled=sorted(set(range(m['nj'])) - set(named.values())),
        ), f, indent=2)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__.strip().splitlines()[-1].strip())
    src, stem = sys.argv[1], sys.argv[2]
    m = load(src)

    write_obj(m, f'{stem}.obj')
    write_skeleton(m, f'{stem}-skel.obj', f'{stem}-skel.json')

    tris = m['ni'] // 3
    print(f'{src}: {m["nv"]} vertices, {tris} triangles, {m["nj"]} joints, '
          f'{m["influences"]} influences')
    print(f'wrote {stem}.obj, {stem}-skel.obj, {stem}-skel.json')


if __name__ == '__main__':
    main()
