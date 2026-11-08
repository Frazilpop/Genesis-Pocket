#!/usr/bin/env python3
"""A ROM that shows how many sprites the VDP draws on a line.

    python3 -I tools/spriterom.py out.bin [--h32] [--wide] [--v30]
    python3 -I tools/spriterom.py --count frame.png    # the sprites drawn in each row

Rows of 8 x 8 sprites, side by side, a row's sprites each a different colour by
palette line and tile: 10, 14, 20 and 36 in H40 (80, the frame's limit), 8, 12, 16
and 28 in H32 (64). A real console draws the first 20 of a row in H40, 16 in H32.
--wide: 16 x 8 sprites in the rows of 10, 14 and 20, so a line's 320 sprite dots
are reached too. tools/sprite-test.sh counts what comes out.
--v30: 240 lines, in a ROM for Europe alone, as a PAL console is what has them.
"""
import struct
import sys
import zlib

if '--count' in sys.argv:
    # a row's sprites each start with a dark column, so a lit run is a sprite
    d = open(sys.argv[sys.argv.index('--count') + 1], 'rb').read()
    i, idat = 8, b''
    while i < len(d):
        n, t = struct.unpack('>I4s', d[i:i + 8])
        if t == b'IHDR':
            w, h, _, ctype = struct.unpack('>IIBB', d[i + 8:i + 18])
        elif t == b'IDAT':
            idat += d[i + 8:i + 8 + n]
        i += 12 + n
    bpp = {2: 3, 6: 4}[ctype]
    raw, stride = zlib.decompress(idat), w * bpp
    prev, rows = bytearray(stride), []
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
        rows.append(row)
        prev = row
    out = []
    for top in (40, 72, 104, 136):
        lit = [any(rows[top + 2][x * bpp:x * bpp + 3]) for x in range(w)]
        out.append(sum(1 for x in range(1, w) if lit[x] and not lit[x - 1]))
    print(out)
    sys.exit()

H32 = '--h32' in sys.argv
WIDE = '--wide' in sys.argv
V30 = 8 if '--v30' in sys.argv else 0
ROWS = [8, 12, 16, 28] if H32 else [10, 14, 20, 36]
TOPS = [40, 72, 104, 136]          # each row's line on the screen
ROM_SIZE = 0x8000


def w(*ws):
    return b''.join(struct.pack('>H', x & 0xFFFF) for x in ws)


def l(*ls):
    return b''.join(struct.pack('>I', x & 0xFFFFFFFF) for x in ls)


VDP_DATA, VDP_CTRL = 0xC00000, 0xC00004
regs = [0x8004, 0x8134 | V30, 0x8230, 0x8407, 0x8578, 0x8700, 0x8AFF, 0x8B00, 0x8C00 if H32 else 0x8C81,
        0x8D3F, 0x8F02, 0x9001, 0x9100, 0x9200]
SAT = 0xF000
sprites = []
n = 0
total = sum(ROWS)
for r, (count, top) in enumerate(zip(ROWS, TOPS)):
    for i in range(count):
        size = 0x4 if (WIDE and count <= 20) else 0x0     # 2 x 1 cells
        step = 16 if size else 8
        x = 8 + (i * step) % 304
        n += 1
        link = n if n < total else 0
        tile = 1 + (i % 2)
        sprites.append((128 + top, size, link, tile | (r << 13), 128 + x))

code = bytearray()
code += w(0x46FC, 0x2700)                            # move.w #$2700,sr
code += w(0x1039) + l(0xA10001) + w(0x0200, 0x000F)  # move.b $A10001,d0; andi.b #$F,d0
code += w(0x6700 | 0x0A)                             # beq.s +10
code += w(0x23FC) + l(0x53454741) + l(0xA14000)      # move.l #'SEGA',$A14000
code += w(0x43F9) + l(VDP_CTRL) + w(0x41F9) + l(VDP_DATA)   # lea ctrl,a1; lea data,a0
code += w(0x3211 | 0)                                # move.w (a1),d1


def set_reg(v):
    return w(0x32BC, v)                              # move.w #v,(a1)


for v in regs:
    code += set_reg(v)


def vram(addr):
    return 0x40000000 | (addr & 0x3FFF) << 16 | addr >> 14


def put_l(addr_word):
    return w(0x22BC) + l(addr_word)                  # move.l #x,(a1)


def put_w(v):
    return w(0x30BC, v)                              # move.w #v,(a0)


# the palette: backdrop black; lines 0 to 3 two colours each
code += put_l(0xC0000000)
for line in ((0x000, 0x00E, 0x0E0), (0x000, 0xE00, 0x0EE), (0x000, 0xEE0, 0xE0E), (0x000, 0xEEE, 0x888)):
    for i in range(16):
        code += put_w(line[i] if i < 3 else 0)
# blank tile 0, tiles 1 and 2 solid colours 1 and 2 with a dark column at the left
code += put_l(vram(0))
for _ in range(16):
    code += put_w(0)
for c in (1, 2):
    for _ in range(8):
        code += put_w(0x0000 | c << 8 | c << 4 | c)
        code += put_w(c << 12 | c << 8 | c << 4 | c)
# the sprite table
code += put_l(vram(SAT))
for y, size, link, tile, x in sprites:
    code += put_w(y) + put_w(size << 8 | link) + put_w(tile) + put_w(x)
code += set_reg(0x8174 | V30)                               # display on
code += w(0x60FE)                                     # bra.s self
rom = bytearray(ROM_SIZE)
for i, v in enumerate([0x00FFFE00, 0x200] + [0x200] * 62):
    rom[i * 4:i * 4 + 4] = l(v)
rom[0x100:0x110] = b'SEGA MEGA DRIVE '
rom[0x120:0x138] = b'GENESIS POCKET SPRITES  '
rom[0x150:0x168] = b'GENESIS POCKET SPRITES  '
rom[0x180:0x18E] = b'GM 00000000-00'
rom[0x1A0:0x1A8] = l(0, ROM_SIZE - 1)
rom[0x1A8:0x1B0] = l(0xFF0000, 0xFFFFFF)
rom[0x1F0:0x1F3] = b'E  ' if V30 else b'JUE'
rom[0x200:0x200 + len(code)] = code
assert 0x200 + len(code) < ROM_SIZE
rom[0x18E:0x190] = w(sum(struct.unpack('>%dH' % ((ROM_SIZE - 0x200) // 2), rom[0x200:])) & 0xFFFF)
open([a for a in sys.argv[1:] if not a.startswith('--')][0], 'wb').write(rom)
