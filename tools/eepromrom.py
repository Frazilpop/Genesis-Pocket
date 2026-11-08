"""A test ROM for the serial save chips (tools/eeprom-test.sh): 68000 code written
out by hand, the same way as tools/testrom.py, that speaks to the chip through its
mapper's pins, as a game does.

    python3 -I tools/eepromrom.py OUT.bin SERIAL MAP CHIP EXPECT.bin

It writes bytes, wraps a page write, crosses the chip's end on a read, reads at an
address, reads on from there, and checks each byte and each ACK as it goes. At the
end it writes A5 at the marker, or 5A if anything was wrong. EXPECT is the chip as
it should be left: the marker and everything the test wrote, in the RAM's order.
The mappers and chips are core_top.sv's numbers, from Genesis Plus GX.
EEPROM_FOR_MAME=1 is the same test without what MAME has differently, to run it there too.
"""
import os
import struct
import sys

SEGA, EA, ACCLAIM16, ACCLAIM32, CODEMASTERS = 1, 2, 3, 4, 5
# (address bytes after the start byte, size, page)
CHIPS = [(0, 0x80, 4), (1, 0x100, 4), (1, 0x100, 8), (1, 0x200, 16), (1, 0x400, 16), (1, 0x800, 16), (2, 0x2000, 64)]
CODE = 0x200
MARKER_BYTE = 0x5C    # (a place nothing else in the test writes)
MAME = 'EEPROM_FOR_MAME' in os.environ   # leaves out what MAME's own chips and Acclaim's 32M do differently


class Test:
    def __init__(self, mapper, chip):
        self.m, self.mode, self.size, self.page = mapper, *CHIPS[chip]
        self.b = bytearray()
        self.fails = []
        self.scl = self.sda = 1
        self.mem = bytearray(b'\xFF' * self.size)
        self.word = 0
        self.fresh = True

    def w(self, *ws):
        for x in ws:
            self.b += struct.pack('>H', x & 0xFFFF)

    def l(self, x):
        self.b += struct.pack('>I', x)

    def move_b(self, imm, addr):
        self.w(0x13FC, imm & 0xFF)
        self.l(addr)

    def move_w(self, imm, addr):
        self.w(0x33FC, imm)
        self.l(addr)

    def lines(self, scl, sda):
        if self.m == SEGA:
            self.move_b(scl << 1 | sda, 0x200001)
        elif self.m == EA:
            self.move_b(sda << 7 | scl << 6, 0x200001)
        elif self.m == ACCLAIM16:
            self.move_w(scl << 1 | sda, 0x200000)
        elif self.m == ACCLAIM32:
            # the low strobe alone is SDA, the high alone SCL: one at a time
            if sda != self.sda and scl == self.scl:
                self.move_b(sda, 0x200001)
            elif scl != self.scl and sda == self.sda:
                self.move_b(scl, 0x200000)
            elif scl != self.scl or sda != self.sda:
                self.move_b(sda, 0x200001)
                self.move_b(scl, 0x200000)
        else:
            self.move_w(scl << 1 | sda, 0x300000)
        self.scl, self.sda = scl, sda

    def read_bit(self):
        """SDA into the bottom of D1, the rest shifted up."""
        addr, mask = {SEGA: (0x200001, 1), EA: (0x200001, 0x80), ACCLAIM16: (0x200001, 2),
                      ACCLAIM32: (0x200001, 1), CODEMASTERS: (0x380001, 0x80)}[self.m]
        self.w(0xE309)                # lsl.b #1,d1
        self.w(0x1039)                # move.b addr,d0
        self.l(addr)
        self.w(0x0200, mask)          # andi.b #mask,d0
        self.w(0x6702, 0x5201)        # beq.s +2; addq.b #1,d1

    def fail_unless_d1(self, value):
        self.w(0x0C01, value)         # cmpi.b #value,d1
        self.w(0x6706, 0x4EF9)        # beq.s +6; jmp fail
        self.fails.append(len(self.b))
        self.l(0)

    def start(self):
        self.lines(self.scl, 1)
        self.lines(1, 1)
        self.lines(1, 0)
        self.lines(0, 0)

    def stop(self):
        self.lines(0, 0)
        self.lines(1, 0)
        self.lines(1, 1)

    def send(self, byte):
        for i in range(7, -1, -1):
            bit = byte >> i & 1
            self.lines(0, bit)
            self.lines(1, bit)
            self.lines(0, bit)
        # the chip's ACK: let go of SDA, it reads low
        self.lines(0, 1)
        self.lines(1, 1)
        self.w(0x7200)                # moveq #0,d1
        self.read_bit()
        self.fail_unless_d1(0)
        self.lines(0, 1)

    def recv(self, value, last):
        self.lines(0, 1)
        self.w(0x7200)                # moveq #0,d1
        for _ in range(8):
            self.lines(1, 1)
            self.read_bit()
            self.lines(0, 1)
        self.fail_unless_d1(value)
        ack = 1 if last else 0
        self.lines(0, ack)
        self.lines(1, ack)
        self.lines(0, ack)

    def address(self, addr, rw):
        if self.mode == 0:
            self.send((addr & 0x7F) << 1 | rw)
        elif self.mode == 1:
            self.send(0xA0 | (addr >> 8 & 7) << 1 | rw)
            if rw == 0:
                self.send(addr & 0xFF)
        else:
            self.send(0xA0 | rw)
            if rw == 0:
                self.send(addr >> 8)
                self.send(addr & 0xFF)

    def write(self, addr, data):
        """A page write, wrapping in its page, as the model has it."""
        self.start()
        self.address(addr, 0)
        self.word = addr
        for d in data:
            self.send(d)
            self.mem[self.word] = d
            self.word = (self.word & ~(self.page - 1)) | ((self.word + 1) & (self.page - 1))
        self.stop()

    def set_read_address(self, addr):
        """Where the X24C01 starts every read; the others by a write of the address."""
        self.start()
        if self.mode == 0:
            self.address(addr, 1)
        else:
            self.address(addr, 0)
            self.start()              # a repeated start
            self.address(addr, 1)
        self.word = addr

    def read_on(self, n):
        for i in range(n):
            self.recv(self.mem[self.word], i == n - 1)
            self.word = (self.word + 1) & (self.size - 1)
        self.stop()

    def read(self, addr, n):
        self.set_read_address(addr)
        self.read_on(n)

    def read_current(self, n):
        self.start()
        if self.mode == 0:
            self.address(self.word, 1)
        else:
            self.send(0xA0 | (self.word >> 8 & 7) << 1 | 1 if self.mode == 1 else 0xA1)
        self.read_on(n)

    def run(self):
        s, p = self.size, self.page
        self.scl = self.sda = 0       # (the lines high, as a game first sets them: all written)
        self.lines(1, 1)
        self.write(0x10, [0x11, 0x22, 0x33])
        self.read(0x10, 3)
        # a page write that goes round its page
        if MAME:
            self.write(p * 2, [0xA0 + i for i in range(p)])   # (MAME's chips don't go round a page)
        else:
            self.write(p * 3 - 2, [0xA0 + i for i in range(p + 3)])
        self.read(p * 2, p + 1)
        self.read_current(1)          # the next byte: still blank
        # the chip's last bytes, a read over its end and round to its start
        self.write(s - 2, [0xC1, 0xC2])
        self.read(s - 2, 3)
        # a start with no more to it, and a stop, change nothing
        self.start()
        self.stop()
        self.read(s - 1, 1)
        if self.m == ACCLAIM32 and not MAME:   # (MAME's chip is always there)
            # reads: back to the ROM, its marker word at 0x200000, then the chip again
            self.move_w(1, 0x200000)
            self.w(0x3039)            # move.w $200000,d0
            self.l(0x200000)
            self.w(0x0C40, 0x1234)    # cmpi.w #$1234,d0
            self.w(0x6706, 0x4EF9)
            self.fails.append(len(self.b))
            self.l(0)
            self.move_w(0, 0x200000)
            self.read(0x10, 1)

    def finish(self):
        self.write(MARKER_BYTE, [0xA5])
        self.w(0x60FE)                # the end: bra self
        fail = CODE + len(self.b)
        final = bytes(self.mem)
        self.write(MARKER_BYTE, [0x5A])
        self.w(0x60FE)
        for at in self.fails:
            self.b[at:at + 4] = struct.pack('>I', fail)
        return final


def main():
    out, serial, mapper, chip, expect = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    t = Test(mapper, chip)
    if mapper == ACCLAIM32 and not MAME:
        t.move_w(0, 0x200000)         # the chip to read
    t.run()
    final = t.finish()
    size = 0x400000 if mapper == ACCLAIM32 else 0x20000
    rom = bytearray(b'\xFF' * size)
    rom[0:8] = struct.pack('>II', 0x00FF8000, CODE)
    for v in range(2, 64):            # every other vector: a loop at the end of the code
        rom[v * 4:v * 4 + 4] = struct.pack('>I', CODE)
    rom[0x100:0x110] = b'SEGA GENESIS    '
    rom[0x120:0x150] = b'EEPROM TEST'.ljust(48)
    rom[0x180:0x18E] = b'GM ' + serial.encode().ljust(8) + b'-00'
    rom[0x1A0:0x1A8] = struct.pack('>II', 0, size - 1)
    rom[0x1B0:0x1BC] = b'RA\xE8\x40' + struct.pack('>II', 0x200001, 0x200001)
    rom[0x1F0:0x1F3] = b'UE '
    rom[CODE:CODE + len(t.b)] = t.b
    assert CODE + len(t.b) < 0x20000, len(t.b)
    if mapper == ACCLAIM32:
        rom[0x200000:0x200002] = b'\x12\x34'
    open(out, 'wb').write(rom)
    open(expect, 'wb').write(final)
    print(f'{serial}: {len(t.b)} bytes of code')


main()
