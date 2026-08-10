#!/usr/bin/env python3
"""Reads a .blend file without Blender: what is in it, and how good is it.

.blend is a memory dump plus a schema. The DNA1 block describes every struct
the file was written with, so once that's parsed every other block can be
decoded by name.
"""
import struct
import sys
from collections import Counter, defaultdict


class Blend:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        if self.d[:7] != b'BLENDER':
            raise SystemExit('not a .blend (compressed? try gzip/zstd)')
        self.ptr = 8 if self.d[7:8] == b'-' else 4
        self.end = '<' if self.d[8:9] == b'v' else '>'
        self.version = self.d[9:12].decode()
        self.blocks = []
        self.by_addr = {}
        self._scan()
        self._dna()

    def _scan(self):
        at = 12
        while at < len(self.d):
            code = self.d[at:at + 4].rstrip(b'\0')
            size, = struct.unpack_from(self.end + 'I', self.d, at + 4)
            addr, = struct.unpack_from(self.end + ('Q' if self.ptr == 8 else 'I'),
                                       self.d, at + 8)
            sdna, count = struct.unpack_from(self.end + 'II', self.d,
                                             at + 8 + self.ptr)
            body = at + 16 + self.ptr
            b = dict(code=code, size=size, addr=addr, sdna=sdna,
                     count=count, at=body)
            self.blocks.append(b)
            if addr:
                self.by_addr[addr] = b
            if code == b'ENDB':
                break
            at = body + size

    def _dna(self):
        blk = next(b for b in self.blocks if b['code'] == b'DNA1')
        at = blk['at'] + 4  # 'SDNA'

        def section(tag):
            nonlocal at
            assert self.d[at:at + 4] == tag, (self.d[at:at + 4], tag)
            at += 4
            n, = struct.unpack_from(self.end + 'I', self.d, at)
            at += 4
            return n

        n = section(b'NAME')
        self.names = []
        for _ in range(n):
            e = self.d.index(b'\0', at)
            self.names.append(self.d[at:e].decode())
            at = e + 1
        at = (at + 3) & ~3

        n = section(b'TYPE')
        self.types = []
        for _ in range(n):
            e = self.d.index(b'\0', at)
            self.types.append(self.d[at:e].decode())
            at = e + 1
        at = (at + 3) & ~3

        assert self.d[at:at + 4] == b'TLEN'
        at += 4
        self.tlen = list(struct.unpack_from(self.end + f'{len(self.types)}H',
                                            self.d, at))
        at += 2 * len(self.types)
        at = (at + 3) & ~3

        n = section(b'STRC')
        self.structs = []          # (type_index, [(type_index, name_index)])
        self.struct_of_type = {}
        for i in range(n):
            t, nf = struct.unpack_from(self.end + 'HH', self.d, at)
            at += 4
            fields = []
            for _ in range(nf):
                ft, fn = struct.unpack_from(self.end + 'HH', self.d, at)
                at += 4
                fields.append((ft, fn))
            self.structs.append((t, fields))
            self.struct_of_type[self.types[t]] = i

    def field_size(self, ftype, fname):
        if fname.startswith('*') or fname.startswith('**'):
            size = self.ptr
        else:
            size = self.tlen[ftype]
        n = 1
        while '[' in fname:
            lo = fname.index('[')
            hi = fname.index(']')
            n *= int(fname[lo + 1:hi])
            fname = fname[hi + 1:]
        return size * n

    def layout(self, sdna):
        """[(name, type_name, offset, size)] for a struct index."""
        _, fields = self.structs[sdna]
        out, off = [], 0
        for ft, fn in fields:
            name, tname = self.names[fn], self.types[ft]
            sz = self.field_size(ft, name)
            out.append((name, tname, off, sz))
            off += sz
        return out

    def read(self, block, *want, index=0):
        """Pull named fields out of one struct instance in a block."""
        lay = self.layout(block['sdna'])
        stride = sum(s for _, _, _, s in lay)
        base = block['at'] + index * stride
        got = {}
        for name, tname, off, sz in lay:
            key = name.lstrip('*').split('[')[0]
            if key not in want:
                continue
            a = base + off
            if name.startswith('*'):
                got[key], = struct.unpack_from(
                    self.end + ('Q' if self.ptr == 8 else 'I'), self.d, a)
            elif tname == 'int':
                got[key], = struct.unpack_from(self.end + 'i', self.d, a)
            elif tname == 'short':
                got[key], = struct.unpack_from(self.end + 'h', self.d, a)
            elif tname == 'float':
                got[key], = struct.unpack_from(self.end + 'f', self.d, a)
            elif tname == 'char' and '[' in name:
                raw = self.d[a:a + sz]
                got[key] = raw.split(b'\0')[0].decode('utf8', 'replace')
            else:
                got[key] = self.d[a:a + sz]
        return got

    def id_name(self, block):
        """Every ID block starts with an ID struct whose name is 2-char type
        code + the user-visible name."""
        raw = self.d[block['at'] + self.ptr * 2 + 8:][:66]
        s = raw.split(b'\0')[0].decode('utf8', 'replace')
        return s[2:] if len(s) > 2 else s


def main():
    b = Blend(sys.argv[1])
    print(f'Blender {b.version[0]}.{b.version[1:]}   '
          f'{len(b.blocks)} blocks   {len(b.d)/1e6:.1f} MB\n')

    counts = Counter(x['code'].decode('latin1') for x in b.blocks)
    interesting = {
        'OB': 'objects', 'ME': 'meshes', 'AR': 'armatures', 'KE': 'shape keys',
        'AC': 'actions', 'MA': 'materials', 'IM': 'images', 'TE': 'textures',
        'SC': 'scenes', 'BR': 'brushes', 'CA': 'cameras', 'LA': 'lamps',
        'NT': 'node trees', 'GR': 'collections', 'TX': 'texts',
    }
    print('datablocks:')
    for code, label in interesting.items():
        if counts.get(code):
            print(f'  {label:<14} {counts[code]}')
    print()

    # --- Objects
    obs = [x for x in b.blocks if x['code'] == b'OB']
    types = {0: 'Empty', 1: 'Mesh', 2: 'Curve', 3: 'Surface', 4: 'Text',
             5: 'Metaball', 10: 'Lamp', 11: 'Camera', 25: 'Armature'}
    print(f'objects ({len(obs)}):')
    for o in obs:
        f = b.read(o, 'type', 'parent', 'data')
        print(f'  {b.id_name(o):<34} {types.get(f.get("type"), f.get("type"))}')
    print()

    # --- Meshes
    mes = [x for x in b.blocks if x['code'] == b'ME']
    print(f'meshes ({len(mes)}):')
    total_v = total_p = 0
    for m in mes:
        f = b.read(m, 'totvert', 'totedge', 'totpoly', 'totloop', 'totface', 'key')
        v, p, l = f.get('totvert', 0), f.get('totpoly', 0), f.get('totloop', 0)
        total_v += v
        total_p += p
        avg = (l / p) if p else 0
        shape = ' +shapekeys' if f.get('key') else ''
        print(f'  {b.id_name(m):<34} {v:>7} verts  {p:>7} faces  '
              f'{avg:.2f} verts/face{shape}')
    print(f'  {"TOTAL":<34} {total_v:>7} verts  {total_p:>7} faces\n')

    # --- Armatures
    ars = [x for x in b.blocks if x['code'] == b'AR']
    if ars:
        print(f'armatures ({len(ars)}):')
        for a in ars:
            print(f'  {b.id_name(a)}')
        # Bone blocks are DATA blocks of struct Bone.
        bone_sdna = b.struct_of_type.get('Bone')
        bones = [x for x in b.blocks
                 if x['sdna'] == bone_sdna and x['code'] == b'DATA']
        print(f'  {sum(x["count"] for x in bones)} bones total')
        names = []
        for x in bones:
            lay = b.layout(x['sdna'])
            stride = sum(s for _, _, _, s in lay)
            for i in range(x['count']):
                names.append(b.read(x, 'name', index=i).get('name', '?'))
        for n in names[:80]:
            print(f'    {n}')
        if len(names) > 80:
            print(f'    ... and {len(names)-80} more')
        print()

    # --- Shape keys
    kes = [x for x in b.blocks if x['code'] == b'KE']
    if kes:
        print(f'shape key sets ({len(kes)}):')
        kb_sdna = b.struct_of_type.get('KeyBlock')
        kbs = [x for x in b.blocks
               if x['sdna'] == kb_sdna and x['code'] == b'DATA']
        for x in kbs:
            for i in range(x['count']):
                print('    ' + b.read(x, 'name', index=i).get('name', '?'))
        print()

    # --- Images
    ims = [x for x in b.blocks if x['code'] == b'IM']
    if ims:
        print(f'images ({len(ims)}):')
        for x in ims:
            f = b.read(x, 'name', 'filepath')
            print(f'  {b.id_name(x):<34} {f.get("name","")}')
        print()

    # --- Actions (animation)
    acs = [x for x in b.blocks if x['code'] == b'AC']
    if acs:
        print(f'actions / animations ({len(acs)}):')
        for x in acs:
            print(f'  {b.id_name(x)}')
        print()

    # --- Materials
    mas = [x for x in b.blocks if x['code'] == b'MA']
    if mas:
        print(f'materials ({len(mas)}):')
        for x in mas:
            print(f'  {b.id_name(x)}')
        print()


if __name__ == '__main__':
    main()
