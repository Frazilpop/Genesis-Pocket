"""tools/mame-crcs.sh's other end: frames from MAME's Lua, a frames.txt out."""
import struct
import sys
import zlib

LUT = [0, 27, 49, 71, 87, 103, 119, 130, 146, 157, 174, 190, 206, 228, 255, 255]
NEAR = bytes(min(LUT, key=lambda v: abs(v - i)) for i in range(256))

with open(sys.argv[1], 'rb') as f, open(sys.argv[2], 'w') as out:
    while True:
        head = f.read(12)
        if len(head) < 12:
            break
        n, w, h = struct.unpack('<III', head)
        p = bytearray(f.read(w * h * 4).translate(NEAR))
        p[3::4] = bytes(w * h)
        out.write(f'{n} {w}x{h} {zlib.crc32(bytes(p)):08x}\n')
        out.flush()
