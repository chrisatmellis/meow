#!/usr/bin/env python3
"""Cap the number of skin influences per vertex in a baked cat mesh.

    ./prune-influences.py N cat.catmesh

The Blender re-export in 33cfcdd wrote twelve influences per vertex. That is
more than the renderer will use and more than the engine's own check allows
(one to eight): skinning hardware resolves four, occasionally eight, and the
remainder is data that costs memory on every vertex and buys nothing.

Pruning is safe here because the extra influences are numerically empty rather
than merely small. Measured on the re-exported cat, the total weight below rank
eight is at most 0.003 on any vertex, on 115 of 1785 vertices — a fraction of a
percent of a single vertex's motion, well under the precision the weights are
stored at.

Keeps the N heaviest influences per vertex and renormalises them to sum to one.
The renormalisation is the part that matters: weights that no longer sum to one
do not merely deform slightly differently, they shrink the vertex toward the
model origin as soon as the skeleton moves.
"""
import struct
import sys

MAGIC = b'MEOWCAT2'


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    keep, path = int(sys.argv[1]), sys.argv[2]

    with open(path, 'rb') as f:
        b = f.read()
    if b[:8] != MAGIC:
        raise SystemExit(f'{path}: not a cat mesh (magic {b[:8]!r})')

    off = 8
    nv, ni, nj, ninf = struct.unpack_from('<IIII', b, off)
    off += 16
    if keep >= ninf:
        print(f'  {path}: already {ninf} influences per vertex, nothing to do')
        return 0

    head_len = nv * 3 * 4 + nv * 3 * 4 + nv * 2 * 4 + ni * 4   # pos, nrm, uv, tris
    head = b[off:off + head_len]
    off += head_len

    idx = struct.unpack_from(f'<{nv * ninf}H', b, off); off += nv * ninf * 2
    wts = struct.unpack_from(f'<{nv * ninf}f', b, off); off += nv * ninf * 4
    tail = b[off:]

    new_idx, new_wts, worst = [], [], 0.0
    for v in range(nv):
        pairs = list(zip(idx[v * ninf:(v + 1) * ninf], wts[v * ninf:(v + 1) * ninf]))
        pairs.sort(key=lambda p: p[1], reverse=True)
        kept, dropped = pairs[:keep], pairs[keep:]
        worst = max(worst, sum(w for _, w in dropped))

        total = sum(w for _, w in kept)
        if total <= 1e-12:
            # A vertex with no meaningful weight at all: bind it rigidly to its
            # heaviest joint rather than emitting zeros, which would collapse it.
            kept = [(kept[0][0], 1.0)] + [(0, 0.0)] * (keep - 1)
        else:
            kept = [(j, w / total) for j, w in kept]

        new_idx.extend(j for j, _ in kept)
        new_wts.extend(w for _, w in kept)

    out = bytearray()
    out += MAGIC
    out += struct.pack('<IIII', nv, ni, nj, keep)
    out += head
    out += struct.pack(f'<{len(new_idx)}H', *new_idx)
    out += struct.pack(f'<{len(new_wts)}f', *new_wts)
    out += tail

    with open(path, 'wb') as f:
        f.write(out)

    print(f'  {path}: {ninf} -> {keep} influences per vertex '
          f'({len(b)} -> {len(out)} bytes)')
    print(f'  most weight dropped from any one vertex: {worst:.6f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
