#!/usr/bin/env python3
"""YM2612 writes for the jt12 bench (sim/jt12, tools/jt12-scan-test.sh).

  jt12-writes.py OUT.log          the bench's own driver's writes, every feature in turn
  jt12-writes.py --features LOG   what a log's writes use (a game's from
                                  sim/genesis --fm-log, or the driver's)

The log is sim/genesis/main.cpp's --fm-log: "W t addr data" a write held
from MCLK cycle t, "E t" where it ends, "R t 1/0" the reset. A register is
two writes, its number to address 0 (part I) or 2 (part II), then its value
to 1 or 3, a cycle each, as the Z80 makes them.
"""
import math
import sys

MCLK = 53693181
CH = [0, 1, 2, 4, 5, 6]          # the key-on register's channel numbers


class Driver:
    def __init__(self):
        self.t = 0
        self.lines = ["R 0 1"]
        self.t = 3000
        self.lines.append(f"R {self.t} 0")
        self.t += 3000

    def reg(self, part, r, v, gap=300):
        for a, d in ((2 * part, r), (2 * part + 1, v & 0xFF)):
            self.lines.append(f"W {self.t} {a} {d:02x}")
            self.lines.append(f"E {self.t + 1}")
            self.t += gap // 2

    def wait(self, seconds):
        self.t += int(seconds * MCLK)

    def ch(self, c, r, v):       # a channel register, c 0 to 5
        self.reg(c // 3, r + c % 3, v)

    def op(self, c, o, r, v):    # an operator register, o 0 to 3 (S1 S3 S2 S4)
        self.reg(c // 3, r + 4 * o + c % 3, v)

    def freq(self, c, block, fnum):
        self.ch(c, 0xA4, block << 3 | fnum >> 8)
        self.ch(c, 0xA0, fnum)

    def key(self, c, ops=0xF):
        self.reg(0, 0x28, ops << 4 | CH[c])

    def voice(self, c, alg, fb, ar=31, d1=8, d2=4, sl=3, rr=6, tl=(30, 20, 25, 0), mul=(1, 2, 1, 1), am=0, ssg=0):
        self.ch(c, 0xB0, fb << 3 | alg)
        for o in range(4):
            self.op(c, o, 0x30, (o & 3) << 4 | mul[o])        # detune and multiple
            self.op(c, o, 0x40, tl[o])
            self.op(c, o, 0x50, (o % 4) << 6 | ar)            # key scale and attack
            self.op(c, o, 0x60, am << 7 | d1)
            self.op(c, o, 0x70, d2)
            self.op(c, o, 0x80, sl << 4 | rr)
            self.op(c, o, 0x90, ssg)


def make(path):
    d = Driver()
    d.reg(0, 0x22, 0)                       # LFO off
    d.reg(0, 0x27, 0)                       # timers off, normal CH3
    d.reg(0, 0x2B, 0)                       # DAC off
    for c in range(6):
        d.ch(c, 0xB4, 0xC0)                 # both sides, no AMS/PMS
    # 1: the eight algorithms with feedback, a chord held and let go
    for alg in range(8):
        c = alg % 6
        d.voice(c, alg, (alg * 3) % 8, tl=(28 + alg, 18, 24, 2))
        d.freq(c, 4, 500 + 37 * alg)
        d.key(c)
        d.wait(0.12)
        if alg >= 5:
            d.key(alg - 5, 0)
    for c in range(6):
        d.key(c, 0)
    d.wait(0.3)
    # 2: the LFO, AMS and PMS on every channel, vibrato and tremolo
    d.reg(0, 0x22, 0x08 | 5)
    for c in range(6):
        d.voice(c, c, 6, am=1, tl=(30, 25, 22, 4))
        d.ch(c, 0xB4, 0xC0 | (c % 4) << 4 | (c + 2) % 8)
        d.freq(c, 3 + c % 3, 600 + 50 * c)
        d.key(c)
    d.wait(0.4)
    d.reg(0, 0x22, 0x08 | 7)
    d.wait(0.2)
    for c in range(6):
        d.key(c, 0)
    d.wait(0.2)
    d.reg(0, 0x22, 0)
    # 3: SSG-EG, the eight shapes on held notes with fast decays
    for i, c in enumerate((0, 1, 3, 4)):
        d.voice(c, 7, 0, d1=20, d2=18, sl=6, rr=8, ssg=0x08 | (2 * i))
        d.ch(c, 0xB4, 0xC0)
        d.freq(c, 4, 650 + 40 * i)
        d.key(c)
    d.wait(0.35)
    for i, c in enumerate((0, 1, 3, 4)):
        for o in range(4):
            d.op(c, o, 0x90, 0x08 | (2 * i + 1))
    d.wait(0.35)
    for c in (0, 1, 3, 4):
        d.key(c, 0)
    d.wait(0.15)
    # 4: CH3 special mode, each operator its own frequency, and CSM mode
    #    keyed by timer A
    d.voice(2, 7, 0, tl=(20, 20, 20, 20))
    d.reg(0, 0x27, 0x40)
    for r_hi, r_lo, fn in ((0xAD, 0xA9, 400), (0xAC, 0xA8, 520), (0xAE, 0xAA, 610)):
        d.reg(0, r_hi, 4 << 3 | fn >> 8)
        d.reg(0, r_lo, fn)
    d.freq(2, 4, 700)
    d.key(2)
    d.wait(0.3)
    d.key(2, 0)
    d.reg(0, 0x24, 0xF0)                    # timer A
    d.reg(0, 0x25, 0x02)
    d.reg(0, 0x26, 0xC0)                    # timer B
    d.reg(0, 0x27, 0x80 | 0x3F)             # CSM, both timers loaded, enabled, flags reset
    d.wait(0.3)
    d.reg(0, 0x27, 0x40 | 0x15)             # back to special mode, flags kept
    d.wait(0.1)
    d.reg(0, 0x27, 0x0F)                    # normal, timers running
    # 5: the DAC, a sample stream on channel 6 at 16 kHz, with the test bit
    d.reg(0, 0x2B, 0x80)
    d.reg(0, 0x2C, 0x08)
    step = MCLK // 16000
    for n in range(int(0.3 * 16000)):
        v = int(128 + 100 * math.sin(n * 2 * math.pi * 330 / 16000) + 20 * ((n * 7) % 13 - 6))
        d.reg(0, 0x2A, max(0, min(255, v)), gap=4)
        d.t += step - 4
    d.reg(0, 0x2C, 0x00)
    d.reg(0, 0x2B, 0x00)
    # 6: all of it at once, changing under held notes
    d.reg(0, 0x22, 0x08 | 3)
    for c in range(5):
        d.voice(c, (c * 3) % 8, 7 - c, am=c & 1, ssg=(0x08 | c) if c in (1, 3) else 0)
        d.ch(c, 0xB4, 0x40 << (c & 1) | 0x13)
        d.freq(c, 4, 450 + 70 * c)
        d.key(c)
    d.reg(0, 0x2B, 0x80)
    for n in range(int(0.3 * 8000)):
        d.reg(0, 0x2A, (n * 37) & 0xFF, gap=4)
        if n % 400 == 0:
            c = (n // 400) % 5
            d.key(c, 0)
            d.ch(c, 0xB0, ((n // 400) % 8) << 3 | (n // 400) % 8)
            d.freq(c, 3 + n // 400 % 3, 300 + n // 4)
            d.key(c)
        d.t += MCLK // 8000
    for c in range(5):
        d.key(c, 0)
    d.reg(0, 0x2B, 0)
    d.wait(0.2)
    open(path, "w").write("C 0\n" + "\n".join(d.lines) + "\n")


def features(path):
    n = {k: 0 for k in ("writes", "key-ons", "feedback", "LFO", "AMS/PMS", "SSG-EG", "CH3 special", "CSM", "timers", "DAC on", "DAC samples")}
    algs = set()
    sel = [0, 0]
    for line in open(path):
        if not line.startswith("W "):
            continue
        _, t, a, v = line.split()
        a, v = int(a), int(v, 16)
        part = a >> 1
        if not a & 1:
            sel[part] = v
            continue
        r = sel[part]
        n["writes"] += 1
        if part == 0 and r == 0x28 and v & 0xF0:
            n["key-ons"] += 1
        elif part == 0 and r == 0x22 and v & 8:
            n["LFO"] += 1
        elif part == 0 and r == 0x27:
            n["CH3 special"] += (v >> 6) == 1
            n["CSM"] += (v >> 6) == 2
            n["timers"] += bool(v & 3)
        elif part == 0 and r == 0x2B and v & 0x80:
            n["DAC on"] += 1
        elif part == 0 and r == 0x2A:
            n["DAC samples"] += 1
        elif 0xB0 <= r <= 0xB2:
            n["feedback"] += bool(v & 0x38)
            algs.add(v & 7)
        elif 0xB4 <= r <= 0xB6:
            n["AMS/PMS"] += bool(v & 0x37)
        elif 0x90 <= r <= 0x9F and (r & 3) != 3:
            n["SSG-EG"] += bool(v & 8)
    print(f"{path}: " + ", ".join(f"{k} {v}" for k, v in n.items()) + f", algorithms {sorted(algs)}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--features":
        features(sys.argv[2])
    elif len(sys.argv) == 2:
        make(sys.argv[1])
    else:
        sys.exit(__doc__)
