#!/usr/bin/env python3
"""Rescale the baked cat artifacts in place.

    ./rescale-baked.py FACTOR cat.catmesh [cat-walk.catanim ...]

Exists because the exporters derive their metres-per-unit from the USD stage
(`UsdGeom.GetStageMetersPerUnit`), and a stage that declares 1.0 while carrying
centimetre geometry produces a cat a hundred times too large. That is what
happened to the re-export in 33cfcdd: a 30-metre cat, clipping through the
ceiling of a room 2.4 metres tall.

The honest fix is to re-export from the source .blend with the stage metadata
correct. This is the other half of it — the source is not in the repository and
Blender is not available everywhere the game is built, so the committed
artifacts have to be repairable on their own.

Only lengths are touched: vertex positions, the translation column of each bind
matrix, and the per-frame joint translations. Normals and quaternions are
directions and are already unit-length; UVs are in texture space; weights and
indices are not lengths at all. Scaling any of those would be the classic way to
turn a scale bug into a shading bug.
"""
import struct
import sys


def rescale_mesh(blob, k):
    """MEOWCAT2: positions, then the bind matrices' translation column."""
    out = bytearray(blob)
    off = 8
    nv, ni, nj, ninf = struct.unpack_from('<IIII', out, off)
    off += 16

    for i in range(nv * 3):
        v, = struct.unpack_from('<f', out, off + i * 4)
        struct.pack_into('<f', out, off + i * 4, v * k)
    off += nv * 3 * 4

    off += nv * 3 * 4        # normals — unit directions
    off += nv * 2 * 4        # uvs — texture space
    off += ni * 4            # triangle indices
    off += nv * ninf * 2     # joint indices
    off += nv * ninf * 4     # joint weights

    for _ in range(nj):
        off += 2             # parent
        # Column-major 4x4; the translation is elements 12..14.
        for e in (12, 13, 14):
            v, = struct.unpack_from('<f', out, off + e * 4)
            struct.pack_into('<f', out, off + e * 4, v * k)
        off += 64

    nroles, = struct.unpack_from('<I', out, off)
    off += 4 + nroles * 2
    if off != len(out):
        raise SystemExit(f'mesh: parsed {off} bytes of {len(out)} — format mismatch')
    return out, f'{nv} vertices, {nj} bind matrices'


def rescale_anim(blob, k):
    """MEOWANM1: the translation triple of every joint of every frame."""
    out = bytearray(blob)
    off = 8
    nj, nframes, fps, ndriven = struct.unpack_from('<IIfI', out, off)
    off += 16 + ndriven * 2

    for _ in range(nframes):
        for _ in range(ndriven):
            # Seven floats per joint: xyzw of the delta quaternion, then xyz of
            # the translation. Only the last three are lengths.
            for e in (4, 5, 6):
                v, = struct.unpack_from('<f', out, off + e * 4)
                struct.pack_into('<f', out, off + e * 4, v * k)
            off += 28

    if off != len(out):
        raise SystemExit(f'anim: parsed {off} bytes of {len(out)} — format mismatch')
    return out, f'{nframes} frames x {ndriven} joints'


KINDS = {b'MEOWCAT2': rescale_mesh, b'MEOWANM1': rescale_anim}


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    k = float(sys.argv[1])

    for path in sys.argv[2:]:
        with open(path, 'rb') as f:
            blob = f.read()
        fn = KINDS.get(blob[:8])
        if fn is None:
            raise SystemExit(f'{path}: not a baked cat artifact (magic {blob[:8]!r})')
        out, what = fn(blob, k)
        if len(out) != len(blob):
            raise SystemExit(f'{path}: length changed, refusing to write')
        with open(path, 'wb') as f:
            f.write(out)
        print(f'  {path}: scaled {what} by {k}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
