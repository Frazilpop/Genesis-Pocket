#!/bin/bash
# core_top.sv's quirks and pad layouts in Verilator (sim/quirks): every game in the
# table loaded as the Pocket loads it. tools/sim.sh sets the quirks by the serial
# itself and never runs this code, so only this shows them surviving a load.
#   bash tools/quirk-test.sh           this tree's core_top.sv
#   bash tools/quirk-test.sh --wiped   the same with the quirks cleared on every word
#                                      of a load, not once at the header: it must fail
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/quirk-sim
CORE=src/fpga/core/core_top.sv
mkdir -p "$OUT"
cp "$CORE" "$OUT/core_top.sv"
if [ "${1:-}" = --wiped ]; then
  grep -q "if(ioctl_addr == 'h180) begin" "$OUT/core_top.sv" || { echo "--wiped: the header's clear isn't there to change" >&2; exit 1; }
  perl -pi -e "s/if\(ioctl_addr == 'h180\) begin/begin/" "$OUT/core_top.sv"
fi
python3 -I - "$OUT" <<'PY'
import re, sys
out = sys.argv[1]
s = open(out + '/core_top.sv').read()
a = s.index('reg [2:0] eeprom_map = 0;')
b = s.index('// Controls', a)
block = s[a:s.rindex('\n', a, s.rindex('////', a, b))]
if 'reg svp_quirk' not in block: block = 'reg svp_quirk = 0;\n' + block   # (declared up with the state's wires)
pads = re.search(r'function automatic \[5:0\] face_buttons.*?endfunction\n', s, re.S)
open(out + '/block.inc', 'w').write(block + '\n' + (pads.group(0) if pads else ''))
open(out + '/defs.vh', 'w').write('')
with open(out + '/cases.inc', 'w') as f:
    games = re.findall(r'cart_id\s*==\s*"(.{8})"\s*\)\s*(\w+?)_quirk\s*<=\s*1', s)
    for serial, name in games:
        f.write(f'    expect_game("{serial}", " {name}");\n')
    # the serial save chips: a seven-character serial is any eighth
    num = {n: v for m in re.findall(r'localparam \[2:0\] (.*?);', s) for n, v in re.findall(r'(\w+) = (\d+)', m)}
    chips = re.findall(r'cart_id(?:\[63:8\])?\s*==\s*"(.+?)"\s*\)\s*\{eeprom_map, eeprom_chip\}\s*<=\s*\{(EP_\w+),\s*(C_\w+)\s*\}', s)
    for serial, m, c in chips:
        f.write(f'    expect_game("{serial:<8}", " eeprom {num[m]}:{num[c]}");\n')
print(len(games) + len(chips), 'games in the table')
PY
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb -Mdir "$OUT/obj" -I"$OUT" \
  "$OUT/defs.vh" sim/quirks/tb.sv > "$OUT/verilator.log" 2>&1 || { tail -30 "$OUT/verilator.log"; exit 1; }
"$OUT/obj/Vtb" | grep -v '^- '
