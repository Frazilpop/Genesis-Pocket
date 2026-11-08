"""A Genesis test ROM for the simulation (tools/sim.sh).

    python3 -I tools/testrom.py build/sim/testrom.bin

Made here, a few hundred bytes of 68000 code written out by hand, so the sim
has a game to run that can be committed (the games never are).
It touches each part of the system, and what it sees shows on the screen:

- the 68000 runs from the ROM (the reset vector, the header with the region
  'JUE', so the core's Auto picks USA) and passes TMSS;
- the VDP is set up (H40, V28, planes A and B, sprites, scroll), its palette
  and the plane's map written by the CPU, the tiles by a DMA from the ROM;
- the vertical blank's interrupt, each frame: plane A scrolls a pixel left,
  the sprite (a white 16 x 16 square) a pixel right;
- the Z80 is loaded with a loop that HALTs, and on each of its vertical
  interrupts (IM 1) counts at its 0x1000; the top band is green while the
  count moves from one frame to the next, red if not;
- the pad, read as a 6-button one (TH toggled three times, its counter
  stepping): the second band is white while Start is held, grey otherwise;
- the main loop waits in STOP for the interrupts;
- an H interrupt every 64 lines changes the backdrop's colour, so the black
  columns of the stripes come in bands;
- the sound: the PSG's first channel at about 440 Hz, and the YM2612's
  channel 1 at about 660 Hz (algorithm 7: the fourth operator, and the
  first quieter with feedback), held, from the start, so the WAV shows each
  chip by its own pitch;
- the region, as a game's lockout reads it: the version register's PAL bit
  against the VDP status's, each frame. The white sprite and the white of the
  tiles (colour 15) stay white on NTSC, cyan on PAL, red if the two disagree.

What the save states' proofs need the games may not show reliably
(tools/state-test.sh): a 68000 in STOP, a halted Z80, a held FM
note with feedback, the 6-button counter, an H interrupt.

Below the bands, diagonal stripes of colours 1 to 12, each tile with a black
column at its left, so the scroll can be seen.
"""
import struct
import sys

ROM_SIZE = 0x10000
CODE = 0x200


class Asm:
    def __init__(self, org):
        self.org, self.b, self.labels, self.fix = org, bytearray(), {}, []

    def pc(self):
        return self.org + len(self.b)

    def w(self, *ws):
        for x in ws:
            self.b += struct.pack('>H', x & 0xFFFF)

    def l(self, *ls):
        for x in ls:
            self.b += struct.pack('>I', x & 0xFFFFFFFF)

    def label(self, n):
        self.labels[n] = self.pc()

    # branches: a short one (Bcc.s) or dbra's 16-bit displacement, fixed up after
    def bs(self, op, n):  # op: 0x60 bra, 0x66 bne, 0x67 beq
        self.fix.append(('s', len(self.b), n))
        self.w(op << 8)

    def dbra(self, d, n):
        self.w(0x51C8 | d)
        self.fix.append(('w', len(self.b), n))
        self.w(0)

    def abs_label(self, n):  # a 32-bit address of a label
        self.fix.append(('l', len(self.b), n))
        self.l(0)

    def done(self):
        for kind, at, n in self.fix:
            t = self.labels[n]
            if kind == 's':
                d = t - (self.org + at + 2)
                assert -128 <= d <= 127 and d != 0, n
                self.b[at + 1] = d & 0xFF
            elif kind == 'w':
                d = t - (self.org + at)
                self.b[at:at + 2] = struct.pack('>h', d)
            else:
                self.b[at:at + 4] = struct.pack('>I', t)
        return bytes(self.b)


VDP_DATA, VDP_CTRL = 0xC00000, 0xC00004
PSG = 0xC00011
Z80_RAM, YM, BUSREQ, Z80_RESET = 0xA00000, 0xA04000, 0xA11100, 0xA11200
PAD1, PAD1_CTRL = 0xA10003, 0xA10009
VARS = 0xFF0000  # .w frame count, .b the Z80's count last frame, (+4) .w the H interrupts' colour

# the YM2612: timers and LFO off, channel 1's four operators (only the fourth
# heard: TL 0, the others 127), algorithm 7, both sides, block 4 fnum $658
# (about 660 Hz, apart from the PSG's 440), and the key on
ym = [(0x22, 0x00), (0x27, 0x00), (0x28, 0x00), (0x2B, 0x00)]
for op in (0x0, 0x4, 0x8, 0xC):
    tl = {0x0: 0x18, 0xC: 0x00}.get(op, 0x7F)            # the first operator quieter, with feedback
    ym += [(0x30 + op, 0x01), (0x40 + op, tl), (0x50 + op, 0x1F),
           (0x60 + op, 0x00), (0x70 + op, 0x00), (0x80 + op, 0x0F), (0x90 + op, 0x00)]
ym += [(0xB0, 0x37), (0xB4, 0xC0), (0xA4, 0x26), (0xA0, 0x58), (0x28, 0xF0)]   # feedback 6, algorithm 7

# the Z80's program
Z80 = bytes([0xF3,                # di
             0x31, 0x00, 0x20,    # ld sp,$2000
             0xED, 0x56,          # im 1
             0x21, 0x00, 0x10,    # ld hl,$1000
             0xFB,                # ei
             0x76,                # loop: halt
             0x34,                # inc (hl)
             0x18, 0xFC])         # jr loop
Z80 = Z80.ljust(0x38, b'\0') + bytes([0xFB, 0xED, 0x4D])   # $38, the interrupt: ei; reti
Z80_LEN = len(Z80)

a = Asm(CODE)
# ---- reset ----
a.label('reset')
a.w(0x46FC, 0x2700)                                   # move.w #$2700,sr
a.w(0x1039); a.l(0xA10001)                            # move.b $A10001,d0
a.w(0x0200, 0x000F)                                   # andi.b #$0F,d0
a.bs(0x67, 'no_tmss')
a.w(0x23FC); a.l(0x53454741); a.l(0xA14000)           # move.l #'SEGA',$A14000
a.label('no_tmss')
a.w(0x43F9); a.l(VDP_CTRL)                            # lea VDP_CTRL,a1
a.w(0x41F9); a.l(VDP_DATA)                            # lea VDP_DATA,a0
a.w(0x3239); a.l(VDP_CTRL)                            # move.w (VDP_CTRL),d1 – clears a pending write
a.w(0x45F9); a.abs_label('regs')                      # lea regs,a2
a.w(0x7200 | 0x12)                                    # moveq #18,d1 (19 registers)
a.label('reg_loop')
a.w(0x329A)                                           # move.w (a2)+,(a1)
a.dbra(1, 'reg_loop')

# the palette, by the CPU
a.w(0x22BC); a.l(0xC0000000)                          # move.l #CRAM 0,(a1)
a.w(0x45F9); a.abs_label('palette')
a.w(0x7200 | 15)
a.label('pal_loop')
a.w(0x309A)                                           # move.w (a2)+,(a0)
a.dbra(1, 'pal_loop')

# the tiles, by a DMA from the ROM to VRAM $0020
a.w(0x22BC); a.l(0x40200080)                          # move.l #VRAM $20 write + DMA,(a1)

# plane A's map at $C000, by the CPU
a.w(0x22BC); a.l(0x40000003)                          # move.l #VRAM $C000 write,(a1)
a.w(0x45F9); a.abs_label('plane')
a.w(0x323C, 64 * 32 - 1)                              # move.w #2047,d1
a.label('map_loop')
a.w(0x309A)
a.dbra(1, 'map_loop')

# the sprite table at $F000: one sprite, 2 x 2 tiles of white
a.w(0x22BC); a.l(0x70000003)                          # move.l #VRAM $F000 write,(a1)
for x in (128 + 104, 0x0500, 0x800F, 128):
    a.w(0x30BC, x)                                    # move.w #x,(a0)

# the pad: TH an output
a.w(0x13FC, 0x0040); a.l(PAD1_CTRL)                   # move.b #$40,PAD1_CTRL
a.w(0x13FC, 0x0040); a.l(PAD1)                        # move.b #$40,PAD1

# the PSG: channel 0 at 3579545 / (32 x 254) Hz, loud; the others silent
for byte in (0x8E, 0x0F, 0x90, 0xBF, 0xDF, 0xFF):
    a.w(0x13FC, byte); a.l(PSG)

# the Z80: the bus taken (the grant comes only with the Z80 out of reset),
# its program put in, a reset to start it from 0 – which resets the YM2612 too,
# as on the console – then the bus taken again to set the YM2612
def take_bus(n):
    a.w(0x33FC, 0x0100); a.l(BUSREQ)                  # move.w #$100,BUSREQ
    a.label(n)
    a.w(0x0839, 0x0000); a.l(BUSREQ)                  # btst #0,BUSREQ
    a.bs(0x66, n)


a.w(0x33FC, 0x0100); a.l(Z80_RESET)                   # move.w #$100,Z80_RESET – out of reset
take_bus('bus_wait')
a.w(0x45F9); a.abs_label('z80prog')
a.w(0x47F9); a.l(Z80_RAM)                             # lea Z80_RAM,a3
a.w(0x7200 | (Z80_LEN - 1))                           # moveq #n-1,d1 (the program's bytes)
a.label('z80_loop')
a.w(0x16DA)                                           # move.b (a2)+,(a3)+
a.dbra(1, 'z80_loop')
a.w(0x33FC, 0x0000); a.l(Z80_RESET)                   # reset on
a.w(0x33FC, 0x0000); a.l(BUSREQ)                      # the bus given back
a.w(0x4E71, 0x4E71, 0x4E71, 0x4E71)                   # nop x 4
a.w(0x33FC, 0x0100); a.l(Z80_RESET)                   # reset off: the Z80 runs its loop
take_bus('bus_wait1')
a.w(0x45F9); a.abs_label('ymtab')
a.w(0x47F9); a.l(YM)                                  # lea YM,a3
a.w(0x7800 | len(ym) - 1)                             # moveq #n-1,d4 (the pairs)
a.label('ym_loop')
a.w(0x101A)                                           # move.b (a2)+,d0
a.w(0x141A)                                           # move.b (a2)+,d2
a.label('ym_busy1')
a.w(0x0813, 0x0007)                                   # btst #7,(a3)
a.bs(0x66, 'ym_busy1')
a.w(0x1680)                                           # move.b d0,(a3)
a.label('ym_busy2')
a.w(0x0813, 0x0007)
a.bs(0x66, 'ym_busy2')
a.w(0x1742, 0x0001)                                   # move.b d2,1(a3)
a.dbra(4, 'ym_loop')
a.w(0x33FC, 0x0000); a.l(BUSREQ)                      # and the bus given back

a.w(0x42B9); a.l(VARS)                                # clr.l VARS
a.w(0x42B9); a.l(VARS + 4)                            # clr.l VARS+4
a.w(0x46FC, 0x2000)                                   # move.w #$2000,sr – the interrupts on
a.label('idle')
a.w(0x4E72, 0x2000)                                   # stop #$2000: wait for an interrupt
a.bs(0x60, 'idle')

# ---- the vertical blank ----
a.label('vint')
a.w(0x48E7, 0xFFFE)                                   # movem.l d0-d7/a0-a6,-(sp)
a.w(0x5279); a.l(VARS)                                # addq.w #1,VARS
a.w(0x3E39); a.l(VARS)                                # move.w VARS,d7
a.w(0x43F9); a.l(VDP_CTRL)
a.w(0x41F9); a.l(VDP_DATA)
a.w(0x22BC); a.l(0x7C000003)                          # VRAM $FC00: the horizontal scroll
a.w(0x3007, 0x4440, 0x3080)                           # move.w d7,d0; neg.w d0; move.w d0,(a0)
a.w(0x30BC, 0x0000)                                   # plane B's, 0
a.w(0x22BC); a.l(0x70060003)                          # VRAM $F006: the sprite's x
a.w(0x3007, 0x0240, 0x00FF, 0x0640, 0x0080, 0x3080)   # move.w d7,d0; andi.w #$FF; addi.w #128; move.w d0,(a0)
# the Z80's count against last frame's: colour 14 green or red
take_bus('bus_wait2')
a.w(0x1439); a.l(Z80_RAM + 0x1000)                    # move.b $A01000,d2
a.w(0x33FC, 0x0000); a.l(BUSREQ)
a.w(0x1639); a.l(VARS + 2)                            # move.b VARS+2,d3
a.w(0x13C2); a.l(VARS + 2)                            # move.b d2,VARS+2
a.w(0x22BC); a.l(0xC01C0000)                          # CRAM 14
a.w(0xB403)                                           # cmp.b d3,d2
a.bs(0x67, 'z80_still')
a.w(0x30BC, 0x00E0)                                   # green
a.bs(0x60, 'z80_done')
a.label('z80_still')
a.w(0x30BC, 0x000E)                                   # red
a.label('z80_done')
a.w(0x4279); a.l(VARS + 4)                            # clr.w VARS+4: the H interrupts' colour from the top
# PAL as a game's lockout reads it: colour 15 white, cyan, or red if they differ
a.w(0x1039); a.l(0xA10001)                            # move.b $A10001,d0
a.w(0x3211)                                           # move.w (a1),d1 – the VDP's status
a.w(0x22BC); a.l(0xC01E0000)                          # CRAM 15
a.w(0x0800, 0x0006)                                   # btst #6,d0
a.bs(0x66, 'ver_pal')
a.w(0x0801, 0x0000)                                   # btst #0,d1
a.bs(0x66, 'pal_differ')
a.w(0x30BC, 0x0EEE)                                   # white
a.bs(0x60, 'pal_done')
a.label('ver_pal')
a.w(0x0801, 0x0000)                                   # btst #0,d1
a.bs(0x67, 'pal_differ')
a.w(0x30BC, 0x0EE0)                                   # cyan
a.bs(0x60, 'pal_done')
a.label('pal_differ')
a.w(0x30BC, 0x000E)                                   # red
a.label('pal_done')
# the pad, as a 6-button one: TH low, high, low, high, low (its counter
# stepping); Start read at the first low (bit 5, 0 when held) – colour 13
# white or grey
a.w(0x13FC, 0x0000); a.l(PAD1)
a.w(0x4E71, 0x4E71)                                   # nop; nop
a.w(0x1039); a.l(PAD1)                                # move.b PAD1,d0
for th in (0x40, 0x00, 0x40, 0x00, 0x40):
    a.w(0x13FC, th); a.l(PAD1)
    a.w(0x4E71, 0x4E71)
    a.w(0x1239); a.l(PAD1)                            # move.b PAD1,d1 (the other words, unused)
a.w(0x22BC); a.l(0xC01A0000)                          # CRAM 13
a.w(0x0800, 0x0005)                                   # btst #5,d0
a.bs(0x66, 'start_up')
a.w(0x30BC, 0x0EEE)
a.bs(0x60, 'pad_done')
a.label('start_up')
a.w(0x30BC, 0x0444)
a.label('pad_done')
a.w(0x4CDF, 0x7FFF)                                   # movem.l (sp)+,d0-d7/a0-a6
a.w(0x4E73)                                           # rte

# ---- the H interrupt: the backdrop's colour moved on ----
a.label('hint')
a.w(0x0679, 0x0222); a.l(VARS + 4)                    # addi.w #$222,VARS+4
a.w(0x23FC); a.l(0xC0000000); a.l(VDP_CTRL)           # move.l #CRAM 0,VDP_CTRL
a.w(0x33F9); a.l(VARS + 4); a.l(VDP_DATA)             # move.w VARS+4,VDP_DATA
a.w(0x4E73)                                           # rte
a.label('trap')
a.bs(0x60, 'trap')

# ---- data ----
TILES = 18
a.label('regs')
for r in (0x8014, 0x8174, 0x8230, 0x8407, 0x8578, 0x8700, 0x8A3F, 0x8B00, 0x8C81, 0x8D3F, 0x8F02,
          0x9001, 0x9100, 0x9200,
          0x9300 | (TILES * 16) & 0xFF, 0x9400 | (TILES * 16) >> 8):   # the DMA's length in words
    a.w(r)
a.label('dma_src_regs')   # the DMA's source, filled below once the tiles' address is known
a.w(0x9500, 0x9600, 0x9700)

a.label('palette')
# 0 black (the backdrop), 1-12 a rainbow, 13 the pad, 14 the Z80, 15 white
for c in (0x000, 0x00E, 0x04E, 0x08E, 0x0CE, 0x0E8, 0x0E0, 0x4E0, 0xEE0, 0xE80, 0xE04, 0xE0A, 0x80E, 0x444, 0x000, 0xEEE):
    a.w(c)

a.label('z80prog')
a.b += Z80

a.label('ymtab')
for r, v in ym:
    a.b += bytes([r, v])

if len(a.b) & 1:
    a.b += b'\0'
a.label('plane')
for y in range(32):
    for x in range(64):
        a.w(14 if y == 0 else 13 if y == 1 else 1 + (x + y) % 12)

while a.pc() % 32:
    a.b += b'\0'
a.label('tiles')
for t in range(1, TILES + 1):
    c = t if t < 15 else 15
    for row in range(8):
        px = [c] * 8
        if t < 15:
            px[0] = 0
        a.w((px[0] << 12) | (px[1] << 8) | (px[2] << 4) | px[3], (px[4] << 12) | (px[5] << 8) | (px[6] << 4) | px[7])

code = bytearray(a.done())
src = a.labels['tiles'] >> 1
at = a.labels['dma_src_regs'] - CODE
code[at:at + 6] = struct.pack('>HHH', 0x9500 | src & 0xFF, 0x9600 | (src >> 8) & 0xFF, 0x9700 | (src >> 16) & 0x7F)

rom = bytearray(ROM_SIZE)
vec = [0x00FFFE00, a.labels['reset']] + [a.labels['trap']] * 62
vec[28] = a.labels['hint']   # level 4: the horizontal interrupt
vec[30] = a.labels['vint']   # level 6: the vertical
for i, v in enumerate(vec):
    rom[i * 4:i * 4 + 4] = struct.pack('>I', v)


def text(at, s, n):
    rom[at:at + n] = s.ljust(n).encode('ascii')


text(0x100, 'SEGA MEGA DRIVE', 16)
text(0x110, '(C)FRAZ 2026.OCT', 16)
text(0x120, 'GENESIS POCKET SIM TEST', 48)
text(0x150, 'GENESIS POCKET SIM TEST', 48)
text(0x180, 'GM 00000000-00', 14)
text(0x190, 'J6', 16)
rom[0x1A0:0x1A8] = struct.pack('>II', 0, ROM_SIZE - 1)
rom[0x1A8:0x1B0] = struct.pack('>II', 0xFF0000, 0xFFFFFF)
text(0x1F0, 'JUE', 16)
assert CODE + len(code) <= ROM_SIZE
rom[CODE:CODE + len(code)] = code
rom[0x18E:0x190] = struct.pack('>H', sum(struct.unpack('>%dH' % ((ROM_SIZE - 0x200) // 2), rom[0x200:])) & 0xFFFF)
open(sys.argv[1], 'wb').write(rom)
