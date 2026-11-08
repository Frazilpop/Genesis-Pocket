#!/usr/bin/env python3
"""A ROM that shows how fast the 68000 runs, for its refresh wait.

    python3 -I tools/refreshrom.py out.bin [--ram] [--data]

A loop of 65536 taken DBRAs, nothing else on the bus but its fetches, then the
backdrop's next colour, for ever. So the frame each new colour comes on says how
far the 68000 has got. The loop runs from the ROM, or with --ram from work RAM.
--data adds a read and a write of work RAM to each pass, so the bus isn't
all fetches. tools/refresh-test.sh holds it against BlastEm.
"""
import struct
import sys

ROM_SIZE = 0x10000
VDP_DATA, VDP_CTRL = 0xC00000, 0xC00004
RAM_CODE = 0xFF0000
RAM = '--ram' in sys.argv
DATA = '--data' in sys.argv


def w(*ws):
    return b''.join(struct.pack('>H', x & 0xFFFF) for x in ws)


def l(*ls):
    return b''.join(struct.pack('>I', x) for x in ls)


# the part that runs, in the ROM or copied to work RAM: a0 VDP data, a1 VDP control
loop = w(0x5242)                                      # next: addq.w #1,d2
loop += w(0x0242, 0x0EEE)                             # andi.w #$EEE,d2 (the colours a VDP has)
loop += w(0x22BC) + l(0xC0000000)                     # move.l #CRAM 0,(a1)
loop += w(0x3082)                                     # move.w d2,(a0)
loop += w(0x70FF)                                     # moveq #-1,d0
if DATA:
    # wait: move.w $FF8000,d1 ; move.w d1,$FF8000 ; dbra d0,wait
    loop += w(0x3239) + l(0xFF8000) + w(0x33C1) + l(0xFF8000) + w(0x51C8, 0x10000 - 14)
else:
    loop += w(0x51C8, 0xFFFE)                         # wait: dbra d0,wait
loop += w(0x0642, 0x0001)                             # addi.w #1,d2 (so the mask moves on)
back = len(loop)
loop += w(0x6000, 0x10000 - back - 2)                 # bra next

code = w(0x46FC, 0x2700)                              # move #$2700,sr
code += w(0x1039) + l(0xA10001) + w(0x0200, 0x000F)   # move.b $A10001,d0; andi.b #$F,d0
code += w(0x6700 | 0x0A)                              # beq.s +10
code += w(0x23FC) + l(0x53454741) + l(0xA14000)       # move.l #'SEGA',$A14000
code += w(0x43F9) + l(VDP_CTRL) + w(0x41F9) + l(VDP_DATA)   # lea ctrl,a1; lea data,a0
code += w(0x3211)                                     # move.w (a1),d1
for v in (0x8004, 0x8144, 0x8C81, 0x8F02, 0x9011, 0x8700):
    code += w(0x32BC, v)                              # move.w #v,(a1)
code += w(0x7400)                                     # moveq #0,d2
if RAM:
    code += w(0x45FA, 24)                              # lea loop(pc),a2 (below)
    code += w(0x47F9) + l(RAM_CODE)                   # lea RAM_CODE,a3
    code += w(0x363C, len(loop) // 2 - 1)             # move.w #n,d3
    code += w(0x36DA)                                 # copy: move.w (a2)+,(a3)+
    code += w(0x51CB, 0xFFFC)                         # dbra d3,copy
    code += w(0x4EF9) + l(RAM_CODE)                   # jmp RAM_CODE
code += loop

rom = bytearray(ROM_SIZE)
for i, v in enumerate([0x00FFFE00, 0x200] + [0x200] * 62):
    rom[i * 4:i * 4 + 4] = l(v)
rom[0x100:0x110] = b'SEGA MEGA DRIVE '
rom[0x120:0x138] = b'GENESIS POCKET REFRESH  '
rom[0x150:0x168] = b'GENESIS POCKET REFRESH  '
rom[0x180:0x18E] = b'GM 00000000-00'
rom[0x1A0:0x1A8] = l(0, ROM_SIZE - 1)
rom[0x1A8:0x1B0] = l(0xFF0000, 0xFFFFFF)
rom[0x1F0:0x1F3] = b'JUE'
rom[0x200:0x200 + len(code)] = code
rom[0x18E:0x190] = w(sum(struct.unpack('>%dH' % ((ROM_SIZE - 0x200) // 2), rom[0x200:])) & 0xFFFF)
open([a for a in sys.argv[1:] if not a.startswith('--')][0], 'wb').write(rom)
