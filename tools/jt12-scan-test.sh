#!/bin/bash
# The YM2612's scan, proved on jt12 alone (sim/jt12):
# three copies on the same writes, one scanned out into a fresh one, one only
# frozen; from then on the three must sound the same, bit for bit.
#   bash tools/jt12-scan-test.sh [writes.log ...] [--saves K]
# With no log: the bench's own driver's (tools/jt12-writes.py: every feature, made each
# run) and the games' in build/jt12_writes (sim/genesis's --fm-log).
set -euo pipefail
cd "$(dirname "$0")/.."
RTL=src/fpga/core/rtl
B=build/jt12_scan
mkdir -p "$B"
verilator --cc --exe --build -j 0 -O3 --x-assign fast --x-initial fast --noassert \
  -Wno-fatal -Wno-lint -Wno-style --top-module bench -Mdir "$B/obj" \
  -y $RTL/jt12 -y $RTL/jt12/adpcm sim/jt12/bench.sv "$PWD/sim/jt12/main.cpp" \
  > "$B/verilator.log" 2>&1 || { grep -E '%Error' "$B/verilator.log" | head -30; exit 1; }

logs=(); args=()
while [ $# -gt 0 ]; do
  case "$1" in --*) args+=("$1" "$2"); shift 2 ;; *) logs+=("$1"); shift ;; esac
done
if [ ${#logs[@]} -eq 0 ]; then
  python3 -I tools/jt12-writes.py "$B/driver.log"
  logs=("$B/driver.log")
  for f in build/jt12_writes/*.log; do [ -s "$f" ] && logs+=("$f"); done
fi
bad=0
for log in "${logs[@]}"; do
  name=$(basename "$log" .log)
  mkdir -p "$B/$name"
  python3 -I tools/jt12-writes.py --features "$log"
  "$B/obj/Vbench" "$log" --out "$B/$name" ${args[@]+"${args[@]}"} || bad=$((bad+1))
done
echo "$(( ${#logs[@]} - bad )) of ${#logs[@]} logs ok"
[ $bad -eq 0 ]
