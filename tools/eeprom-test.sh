#!/bin/bash
# The serial save chips in the whole console's simulation, with a test ROM for them
# (tools/eepromrom.py): each mapper and chip in core_top.sv's table. The chip, as the
# .sav has it, must be what the ROM wrote, with its A5 at the end. No game needed.
#   bash tools/eeprom-test.sh     (after any change to EEPROM_24CXX.sv or its mappers)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$PWD/build/eeprom_test
mkdir -p "$OUT"
if [ -z "${NO_BUILD:-}" ]; then bash tools/sim.sh --frames 1 > /dev/null; fi
# serial, its mapper and chip as core_top.sv's table has them, what it is
CASES=(
  "G-4060  |1|0|Sega, X24C01"
  "T-50396 |2|0|EA, X24C01"
  "T-081326|3|1|Acclaim 16M, X24C02"
  "T-081276|4|2|Acclaim 32M, 24C02"
  "T-81406 |4|3|Acclaim 32M, 24C04"
  "T-081586|4|5|Acclaim 32M, 24C16"
  "T-81476 |4|6|Acclaim 32M, 24C65"
  "T-120106|5|4|Codemasters, 24C08"
  "T-120096|5|5|Codemasters, 24C16"
  "T-120146|5|6|Codemasters, 24C65"
  "XX-00000|1|0|not in the table: the header's E8, Sega's"
)
n=${#CASES[@]}; i=0; bad=0
for c in "${CASES[@]}"; do
  IFS='|' read -r serial map chip what <<< "$c"
  i=$((i+1)); echo "$i of $n"
  d="$OUT/$map-$chip-${serial// /_}"; mkdir -p "$d"
  python3 -I tools/eepromrom.py "$d/rom.bin" "$serial" "$map" "$chip" "$d/expect.bin" > /dev/null
  (cd src/fpga/core/rtl/FX68K && "$OLDPWD/build/sim/obj/Vsystem" "$d/rom.bin" --out "$d" --frames ${EEPROM_FRAMES:-8} --every 0 --sav-out "$d/out.sav" > "$d/run.txt")
  if python3 -I - "$d" "$map" "$chip" "$what" <<'PY'
import re, sys
d, want_map, want_chip, what = sys.argv[1:]
run = open(d + '/run.txt').read()
got = re.search(r'eeprom:(\d):(\d)', run)
if not got or got.groups() != (want_map, want_chip):
    print(f'FAILED {what}: the table gives {got.group(0) if got else "no chip"}')
    sys.exit(1)
want = open(d + '/expect.bin', 'rb').read()
sav = open(d + '/out.sav', 'rb').read()
ram = sav[1::2]   # a RAM byte is a file word's odd byte (save_layout.sv)
ok = ram[:len(want)] == want and all(x == 0xFF for x in ram[len(want):])
print(f'{"good  " if ok else "FAILED"} {what}: marker {ram[0x5C]:02x}')
if not ok:
    for a, (x, y) in enumerate(zip(ram, want)):
        if x != y:
            print(f'  first difference at {a:04x}: {x:02x}, wanted {y:02x}')
            break
sys.exit(0 if ok else 1)
PY
  then :; else bad=$((bad+1)); fi
done
echo "$((n-bad)) of $n good"
[ $bad -eq 0 ]
