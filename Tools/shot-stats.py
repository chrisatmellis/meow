#!/usr/bin/env python3
"""Pixel statistics for the simulator screenshots.

Looking at a screenshot and calling it "blown out" is unreliable — a window at
luma 230 next to a dark wall reads as pure white when nothing is clipping at
all. This measures instead. No PIL on the runner, so it decodes 8-bit
non-interlaced PNG directly.

    shot-stats.py stats screenshots/*.png     mean luma, clipped/bright/dark %
    shot-stats.py map screenshots/05-night.png   coarse luma map of the frame

`stats` is for comparing one commit against another: if a lighting change is
supposed to have brought midday down, the mean and bright% should say so.

`map` is for locating a bright region once you know there is one. It prints the
frame as characters, so a bright patch can be read off against the geometry —
which is how the open half of the window was identified as the thing glowing at
night, rather than the shoji next to it.
"""
import struct
import sys
import zlib


def decode(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
    pos = 8
    idat = b''
    w = h = depth = ctype = None
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        ctag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctag == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and interlace == 0, f'unsupported {depth} {interlace}'
        elif ctag == b'IDAT':
            idat += body
        elif ctag == b'IEND':
            break
        pos += 12 + length

    nch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(w * h * nch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, nch, out


def stats(path, top_frac, bottom_frac):
    w, h, nch, px = decode(path)
    y0, y1 = int(h * top_frac), int(h * bottom_frac)
    stride = w * nch
    tot = 0
    clipped = 0        # every channel >= 250
    bright = 0         # luma >= 235
    dark = 0           # luma <= 20
    lsum = 0
    for y in range(y0, y1, 3):          # every 3rd row is plenty
        base = y * stride
        for x in range(0, w, 3):
            i = base + x * nch
            r, g, b = px[i], px[i + 1], px[i + 2]
            luma = (r * 299 + g * 587 + b * 114) // 1000
            tot += 1
            lsum += luma
            if r >= 250 and g >= 250 and b >= 250:
                clipped += 1
            if luma >= 235:
                bright += 1
            if luma <= 20:
                dark += 1
    return {
        'mean': lsum / tot,
        'clipped%': 100 * clipped / tot,
        'bright%': 100 * bright / tot,
        'dark%': 100 * dark / tot,
    }


def luma_map(path, top_frac=0.20, bottom_frac=0.55, cols=40):
    """Coarse picture of the frame's brightness, for locating a bright region."""
    w, h, nch, px = decode(path)
    ramp = ' .:-=+*#%@'
    print(f"== {path.rsplit('/', 1)[-1]} == columns 0..1 across")
    for i in range(int((bottom_frac - top_frac) * 100) // 2 + 1):
        fy = top_frac + i * 0.02
        if fy > bottom_frac:
            break
        y = int(h * fy)
        row = ''
        for c in range(cols):
            x = min(w - 1, int(w * c / cols))
            j = y * w * nch + x * nch
            luma = (px[j] * 299 + px[j + 1] * 587 + px[j + 2] * 114) // 1000
            row += ramp[min(len(ramp) - 1, luma * len(ramp) // 256)]
        print(f'{fy:5.2f} {row}')


def main():
    args = sys.argv[1:]
    mode = 'stats'
    if args and args[0] in ('stats', 'map'):
        mode, args = args[0], args[1:]
    if not args:
        print(__doc__.strip())
        return 1

    if mode == 'map':
        for path in args:
            luma_map(path)
            print()
        return 0

    # Rows between the needs panel and the status pill: the room itself.
    print(f"{'shot':<22} {'mean':>6} {'clip%':>7} {'bright%':>8} {'dark%':>7}")
    for path in args:
        s = stats(path, 0.30, 0.78)
        name = path.rsplit('/', 1)[-1]
        print(f"{name:<22} {s['mean']:6.1f} {s['clipped%']:7.2f} "
              f"{s['bright%']:8.2f} {s['dark%']:7.2f}")
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except BrokenPipeError:
        # Piping into `head` is the normal way to read the map.
        sys.exit(0)
