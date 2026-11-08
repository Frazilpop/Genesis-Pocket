#!/usr/bin/env python3
"""sim/top's settings.vh and games.svh, from a core_top.sv and its interact.json.

    python3 -I tools/top-settings.py core_top.sv interact.json DIR

The bench writes a setting where the Core Settings menu would, so a setting that
reaches the wrong address fails. Menu Pause isn't in the menu, so its address is
read from the file. games.svh loads every serial in the file's table.
"""
import json, re, sys

core, interact, out = sys.argv[1:4]
src = open(core, encoding='latin-1').read()
# (Quartus takes a comma before a concatenation's end; Verilator doesn't. The copy is the build's.)
fixed = re.sub(r',([ \t]*(?://[^\n]*)?\n\s*\};)', r' \1', src)
# (an output tied to a constant: Quartus lets it go)
fixed = re.sub(r"\.SDRAM_nCS\(1'b0\)", '.SDRAM_nCS()', fixed)
if fixed != src:
    open(core, 'w', encoding='latin-1').write(fixed)
names = {'Reset Core': 'RESET', 'Region': 'REGION', 'PAL 60 Hz': 'PAL_60', 'Multitap': 'MULTITAP',
         'Lightgun': 'LIGHTGUN', 'Controller': 'BUTTONS', 'Composite Blend': 'COMPOSITE',
         'High Sprite Limit': 'SPRITES', 'HiFi PCM': 'HIFI', 'Audio Filter': 'FILTER', 'FM Chip': 'FMCHIP'}
# Addresses no row uses: the bench writes to them and checks nothing answers
unused = [0x10C, 0x208, 0x210, 0x214, 0x300, 0x400, 0x404]
variables = json.load(open(interact))['interact']['variables']
with open(out + '/settings.vh', 'w') as f:
    seen = set()
    for v in variables:
        if v['name'] not in names:
            sys.exit(f"interact.json's {v['name']} isn't known to the bench")
        if int(v['address'], 16) in unused:
            sys.exit(f"interact.json's {v['name']} is at an address the bench keeps unused")
        f.write(f"`define A_{names[v['name']]} 32'h{int(v['address'], 16):08X}\n")
        seen.add(names[v['name']])
    for a in unused:
        f.write(f"`define A_UNUSED_{a:03X} 32'h{a:08X}\n")
    missing = set(names.values()) - seen
    if missing:
        sys.exit(f'interact.json has no {missing}')
    m = re.search(r"32'h([0-9A-Fa-f]{8})\s*:\s*\w*menu_pause\w*\s*<=", src) or re.search(r"SET_MENU_PAUSE\s*=\s*32'h([0-9A-Fa-f_]{9})", src)
    f.write(f"`define A_MENU_PAUSE 32'h{m[1]}\n")
with open(out + '/games.svh', 'w') as f:
    serials = set(re.findall(r'cart_id(?:\[63:8\])?\s*==\s*"(.+?)"', src))
    for s in sorted(serials):
        f.write(f'    game("{s.replace(chr(92), "").ljust(8)}");\n')
    # a save RAM in the header against a serial chip's few bytes, and a hack of a table game's
    f.write('    game("G-4060  ", 8\'hF8, 32\'h200001, 32\'h203FFF);\n')
    f.write('    game("T-NONE00", 8\'hE8, 32\'h200001, 32\'h203FFF);\n')
    f.write('    game("T-NONE01", 8\'hF8, 32\'h200001, 32\'h200001);\n')
    f.write('    game("T-NONE02", 8\'hF8, 32\'h200001, 32\'h203FFF);\n')
print(len(serials), 'serials')
