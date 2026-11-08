"""The simulation's frames beside MAME's (tools/mame-frames.sh).

    python3 -I sim/genesis/compare.py [build/sim_genesis] [build/mame_genesis] [window]

For each of the sim's f_NNNNN.png, MAME's frames N - 2 to N + 2 (or that window)
that are there (N itself should match; the others show one a frame or two out), each
pixel compared by colour level: both are taken to the nearest of core_top.sv's
16 levels first, since MAME's table differs from the core's in
two of them (level 8: 144 against 146, level 10: 172 against 174). Prints the
best match for each frame and how many pixels differ in it.
"""
import struct
import sys
import zlib
from pathlib import Path

LUT = [0, 27, 49, 71, 87, 103, 119, 130, 146, 157, 174, 190, 206, 228, 255, 255]
LEVEL = [min(range(16), key=lambda i: abs(LUT[i] - v)) for v in range(256)]


def load(p):
    d = p.read_bytes()
    i, idat = 8, b''
    while i < len(d):
        n, t = struct.unpack('>I4s', d[i:i + 8])
        c = d[i + 8:i + 8 + n]
        i += 12 + n
        if t == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', c[:10])
        elif t == b'IDAT':
            idat += c
    bpp = {2: 3, 6: 4}[ctype]
    raw, stride = zlib.decompress(idat), w * bpp
    out, prev = [], bytearray(stride)
    for y in range(h):
        f, row = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = row[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1: row[x] = (row[x] + a) & 255
            elif f == 2: row[x] = (row[x] + b) & 255
            elif f == 3: row[x] = (row[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                row[x] = (row[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out.append(bytes(LEVEL[row[x * bpp + k]] for x in range(w) for k in range(3)))
        prev = row
    return w, h, out


def diff(a, b):
    if a[:2] != b[:2]:
        return None
    return sum(sum(1 for x in range(0, len(ra), 3) if ra[x:x + 3] != rb[x:x + 3]) for ra, rb in zip(a[2], b[2]))


def main():
    sim = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/sim_genesis')
    ref = Path(sys.argv[2] if len(sys.argv) > 2 else 'build/mame_genesis')
    window = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    bad = 0
    for f in sorted(sim.glob('f_*.png')):
        n = int(f.stem[2:])
        s = load(f)
        best = None
        for m in range(n - window, n + window + 1):
            p = ref / f'f_{m:05d}.png'
            if p.exists():
                d = diff(s, load(p))
                if d is not None and (best is None or d < best[1]):
                    best = (m, d)
        if best is None:
            print(f'frame {n}: no MAME frame of its size near it')
            bad += 1
        else:
            print(f'frame {n}: MAME\'s {best[0]}, {best[1]} pixels differ' + (' – the same' if best[1] == 0 else ''))
            bad += best[1] != 0
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
