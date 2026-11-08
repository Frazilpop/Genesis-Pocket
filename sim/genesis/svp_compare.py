"""The SVP in the simulation beside MAME's (tools/svp-trace.sh).

    python3 -I sim/genesis/svp_compare.py OUT

From OUT: bus_sim.txt and bus_mame.txt, the 68000's writes to the SVP and the
VDP's control port in order; ssp_sim.txt and ssp_mame.txt, the SSP's registers
an instruction from the 68000's first job. Prints how far each agrees and, at
the first difference, the instructions round it. Exits 1 on a difference.
"""
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
ok = True

# the bus: the writes in order, whatever frame each falls in
writes = lambda p: [l.split() for l in p.read_text().splitlines() if ' W ' in l]
m, s = writes(out / 'bus_mame.txt'), writes(out / 'bus_sim.txt')
n = min(len(m), len(s))
at = next((i for i in range(n) if m[i][1:] != s[i][1:]), None)
if at is None:
    print(f"68000's writes: the same for the {n} both have (frame {s[n-1][0]} here, {m[n-1][0]} in MAME)")
else:
    ok = False
    print(f"68000's writes: differ at {at} of {n}: MAME {m[at]}, sim {s[at]}")

# the SSP: MAME's line is "A X Y PC: instruction", registers before it runs. The
# sim's is "IR PC A X Y", its PC the instruction's last word. The loops where it
# waits for the 68000 take as long as the 68000 does, so they are left out of both.
idle = lambda pc: 0x425 <= pc < 0x44E or 0x2784 <= pc < 0x2799
line = re.compile(r'^\s*([0-9A-F]+) ([0-9A-F]+) ([0-9A-F]+) ([0-9A-F]{4}): (.*)$')
mame = [(int(g[0], 16), int(g[1], 16), int(g[2], 16), int(g[3], 16), g[4])
        for g in (line.match(l).groups() for l in (out / 'ssp_mame.txt').read_text().splitlines() if line.match(l))]
sim = [[int(f, 16) for f in l.split()] for l in (out / 'ssp_sim.txt').read_text().splitlines()]
mame = [r for r in mame if not idle(r[3])]
sim = [r for r in sim if not idle(r[1])]
n = min(len(mame), len(sim))
at = next((k for k in range(n) if tuple(sim[k][2:]) != mame[k][:3]), None)
if at is None:
    print(f"the SSP: A, X and Y the same for all {n} instructions outside its waits")
else:
    ok = False
    print(f"the SSP: differs at instruction {at} of {n} outside its waits")
    for k in range(max(0, at - 10), min(n, at + 3)):
        a, b = mame[k], sim[k]
        print(f"  {a[3]:04X} {a[4]:24.24} MAME A={a[0]:08X} X={a[1]:04X} Y={a[2]:04X}   sim A={b[2]:08X} X={b[3]:04X} Y={b[4]:04X} ir={b[0]:04X}")
sys.exit(0 if ok else 1)
