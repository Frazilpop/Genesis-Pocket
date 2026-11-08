"""A save state as text, field by field, or two side by side.

    python3 -I tools/state-dump.py STATE [OTHER]

The small state field by field, then for each memory how many bytes differ
(with OTHER) or are not zero. With OTHER, only what differs is printed.
"""
import sys

def words(b, off, n):
    return [b[off + 2 * i] << 8 | b[off + 2 * i + 1] for i in range(n)]

def fields(b):
    f = {}
    w = lambda o: words(b, o, 1)[0]
    f['magic'] = b[0:4].decode('latin1')
    f['version'] = w(4)
    f['flags'] = '%04x' % w(6)
    f['size'] = '%x' % (w(8) << 16 | w(10))
    f['rom size'] = w(0xC) << 16 | w(0xE)
    f['serial'] = b[0x10:0x20].decode('latin1')
    f['frame'] = w(0x24) << 16 | w(0x26)
    c = words(b, 0x40, 12)
    f['bank regs'] = ' '.join('%02x %02x' % (x >> 8, x & 0xFF) for x in c[0:4])
    f['bank rom/sram, z80 busrq_n/reset_n'] = '{:04b}'.format(c[4])
    f['BAR'] = '%06x' % (c[5] << 15)
    f['IPL_N old_as scnt'] = '%d %d %d' % (c[6] >> 3, c[6] >> 2 & 1, c[6] & 3)
    f['open bus'] = '%04x' % c[7]
    pos = (c[8] << 16) | c[9]
    f['position: field line dot pixdiv'] = '%d %03x %03x %d' % (pos >> 22, pos >> 13 & 0x1FF, pos >> 4 & 0x1FF, pos & 15)
    f['dividers V Z F P'] = '%d %d %d %d' % (c[10] >> 12, c[10] >> 8 & 15, c[10] >> 4 & 15, c[10] & 15)
    f['VCLKMAX MID'] = '%d %d' % (c[11] >> 4, c[11] & 15)
    i = words(b, 0x58, 4)
    f['save chip: read map, SCL, SDA'] = '{:03b}'.format(i[0] & 7)
    f['save chip: old SCL SDA, state, bit, rnw, block'] = '%d %d %d %d %d %d' % (i[1] >> 15, i[1] >> 14 & 1, i[1] >> 11 & 7, i[1] >> 7 & 15, i[1] >> 6 & 1, i[1] >> 3 & 7)
    f['save chip: address, buffer'] = '%04x %02x' % (i[2], i[3])
    r = words(b, 0x60, 1)[0]
    f['refresh: pending, timer'] = '%d %03x' % (r >> 10 & 1, r & 0x3FF)
    m = words(b, 0x80, 0x2A)
    names = ['D%d' % i for i in range(8)] + ['A%d' % i for i in range(7)] + ['USP', 'SSP']
    for i, n in enumerate(names):
        f['68000 ' + n] = '%08x' % (m[2 * i] << 16 | m[2 * i + 1])
    f['68000 PC'] = '%08x' % (m[0x22] << 16 | m[0x23])
    f['68000 SR'] = '%04x' % m[0x24]
    x = m[0x25]
    f['68000 latches (T I Ill Pr LA LF Rst Be Ae Sp Av)'] = '{:011b}'.format(x >> 5)
    f['68000 inl intPend prevNmi'] = '%d %d %d' % (x >> 2 & 7, x >> 1 & 1, x & 1)
    f['68000 latches at the dispatch'] = '{:011b}'.format(m[0x26] & 0x7FF)
    k = m[0x27]
    f['68000 Tpend rVma tState eCntr'] = '%d %d %d %d' % (k >> 8 & 1, k >> 7 & 1, k >> 4 & 7, k & 15)
    f['68000 in STOP'] = m[0x28] & 1
    f['68000 microaddress'] = '%03x' % m[0x29]   # (where it parked; STOP's is 3a2)
    z = words(b, 0x100, 16)
    reg = 0
    for i in range(14):
        reg = reg << 16 | z[i]
    zn = ['A', 'F', "A'", "F'", 'I', 'R']
    for i, n in enumerate(zn):
        f['Z80 ' + n] = '%02x' % (reg >> (8 * i) & 0xFF)
    f['Z80 SP'] = '%04x' % (reg >> 48 & 0xFFFF)
    f['Z80 PC'] = '%04x' % (reg >> 64 & 0xFFFF)
    for i, n in enumerate(['BC', 'DE', 'HL', 'IX', "BC'", "DE'", "HL'", 'IY']):
        f['Z80 ' + n] = '%04x' % (reg >> (80 + 16 * i) & 0xFFFF)
    f['Z80 IM IFF1 IFF2'] = '%d %d %d' % (reg >> 208 & 3, reg >> 210 & 1, reg >> 211 & 1)
    f['Z80 WZ'] = '%04x' % z[14]
    f['Z80 BusReq_s BusAck Halt'] = '%d %d %d' % (z[15] >> 2 & 1, z[15] >> 1 & 1, z[15] & 1)
    f['Z80 (at the point: BUSAK InstEnd)'] = '%d %d' % (z[15] >> 4 & 1, z[15] >> 3 & 1)
    v = words(b, 0x140, 0x22)
    f['VDP registers'] = ' '.join('%02x' % (x & 0xFF) for x in v[0:24])
    f['VDP ADDR'] = '%05x' % ((v[25] >> 8 & 1) << 16 | v[24])
    f['VDP PENDING CODE'] = '%d %02x' % (v[25] >> 7 & 1, v[25] & 0x3F)
    f['VDP DBG'] = '%04x' % v[26]
    f['VDP FIFO'] = ' '.join('%04x' % x for x in v[27:31]) + '  rd %d wr %d' % (v[31] >> 2 & 3, v[31] & 3)
    f['VDP snapshot HV'] = '%04x' % v[32]
    f['VDP snapshot (VP HP EP VF HF EF SOVR SCOL)'] = '{:08b}'.format(v[33] & 0xFF)
    f['PSG'] = ' '.join('%04x' % x for x in words(b, 0x240, 10))
    f['pads'] = ' '.join('%04x' % x for x in words(b, 0x280, 12))
    f['YM2612 chain'] = b[0x300:0x300 + 76].hex()
    f['YM2612 loops'] = b[0x400:0x400 + 576].hex()
    if f['version'] == 2:
        s = words(b, 0x1000, 63)
        f['SSP PC'] = '%04x' % s[0]
        f['SSP A'] = '%04x%04x' % (s[1], s[2])
        f['SSP X Y'] = '%04x %04x' % (s[3], s[4])
        f['SSP N OV Z L, IMM16 IND, MACS OP IE ST6 ST5 RB RPL'] = '{:04b} {:02b} {:010b}'.format(s[5] >> 12, s[5] >> 10 & 3, s[5] & 0x3FF)
        f['SSP stack'] = ' '.join('%04x' % x for x in s[6:12])
        f['SSP r0-r7'] = ' '.join('%04x' % x for x in s[12:16])
        f['SSP IR_SAVED IND_ADDR'] = '%04x %04x' % (s[16], s[17])
        m = s[18]
        f['SVP stack pos HALT CA SA PMC_SEL PMAR_SET PMAR_NUM'] = '%d %d %d %d %d %d %d' % (m >> 9 & 7, m >> 8 & 1, m >> 7 & 1, m >> 6 & 1, m >> 5 & 1, m >> 4 & 1, m & 15)
        f['SVP PMC'] = '%04x%04x' % (s[19], s[20])
        f['SVP XST ROM_DATA'] = '%04x %04x' % (s[21], s[22])
        for i, n in enumerate([0, 1, 2, 3, 4, 8, 9, 10, 11, 12]):
            p = s[23 + 4 * i:27 + 4 * i]
            f['SVP PMAR %d MA DATA CD' % n] = '%04x%04x %04x %04x' % tuple(p)
    return f

MEMS = [('CRAM', 0xA00, 128), ('VSRAM', 0xA80, 80), ('sprite cache', 0xB00, 320), ('Z80 RAM', 0x2000, 0x2000),
        ('68000 RAM', 0x4000, 0x10000), ('VRAM', 0x14000, 0x10000), ('save RAM', 0x24000, 0x10000)]
SVP_MEMS = [('SVP RAM A', 0x1200, 512), ('SVP RAM B', 0x1400, 512), ('SVP IRAM', 0x1800, 2048),
            ('SVP DRAM (save RAM\'s place, low byte first)', 0x24000, 0x20000)]

def main():
    a = open(sys.argv[1], 'rb').read()
    b = open(sys.argv[2], 'rb').read() if len(sys.argv) > 2 else None
    fa = fields(a)
    mems = MEMS[:-1] + SVP_MEMS if fa['version'] == 2 else MEMS
    fb = fields(b) if b else None
    DIAG = ('frame', 'Z80 (at the point: BUSAK InstEnd)')   # differ on a state read again, by design
    for k, v in fa.items():
        if fb is not None and k in DIAG:
            continue
        if fb is None:
            s = str(v)
            print('%-48s %s' % (k, s if len(s) < 100 else s[:96] + '...'))
        elif fb[k] != v:
            print('%-48s %s\n%-48s %s' % (k, v, '', fb[k]))
    for n, o, l in mems:
        if b is None:
            print('%-48s %d of %d bytes not 0' % (n, sum(1 for x in a[o:o + l] if x), l))
        else:
            d = [i for i in range(l) if a[o + i] != b[o + i]]
            if d:
                print('%-48s %d bytes differ, the first at %x' % (n, len(d), d[0]))
    if b is not None:
        diag = set(range(0x24, 0x28)) | {0x11E}
        other = [i for i in range(len(a)) if a[i] != b[i] and i not in diag and not (i == 0x11F and (a[i] ^ b[i]) & 7 == 0)
                 and not any(o <= i < o + l for _, o, l in mems)]
        print('%d bytes differ outside the memories' % len(other))

main()
