#!/usr/bin/env python3
"""The platform banner: art/genesis-banner.png into dist/Platforms/_images/genesis.bin.

The PNG is the natural picture, 521 x 165, 8-bit greyscale, made from the
artwork outside the repo; never edit it by hand. The Pocket shows the image the
right way round only inverted, and wants it turned 90 degrees counter-clockwise,
as 16-bit words with the brightness in the first byte.
"""
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PNG = os.path.join(HERE, "..", "art", "genesis-banner.png")
BIN = os.path.join(HERE, "..", "dist", "Platforms", "_images", "genesis.bin")
W, H = 521, 165


def read_png(path):
    """Rows of brightness bytes from an 8-bit greyscale, non-interlaced PNG."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path}: not a PNG")
    pos, idat, w, h = 8, b"", 0, 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, colour, interlace) != (8, 0, 0):
                sys.exit(f"{path}: must be 8-bit greyscale, not interlaced")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    if (w, h) != (W, H):
        sys.exit(f"{path}: must be {W} x {H}, not {w} x {h}")
    raw = zlib.decompress(idat)
    rows, prev = [], bytes(w)
    for y in range(h):
        filt, line = raw[y * (w + 1)], bytearray(raw[y * (w + 1) + 1:(y + 1) * (w + 1)])
        for x in range(w):
            a = line[x - 1] if x else 0
            b, c = prev[x], prev[x - 1] if x else 0
            if filt == 1:
                line[x] = (line[x] + a) & 0xFF
            elif filt == 2:
                line[x] = (line[x] + b) & 0xFF
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        rows.append(line)
        prev = line
    return rows


def main():
    rows = read_png(PNG)
    out = bytearray()
    for x in range(W - 1, -1, -1):      # stored row r = original column W-1-r
        for y in range(H):              # stored column = original row
            out += bytes((0xFF - rows[y][x], 0))
    os.makedirs(os.path.dirname(BIN), exist_ok=True)
    with open(BIN, "wb") as f:
        f.write(out)
    print(f"{os.path.relpath(BIN)}: {W}x{H}, {len(out)} bytes")


if __name__ == "__main__":
    main()
