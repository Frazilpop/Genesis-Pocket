#!/bin/bash
# The 68000's refresh wait against BlastEm, on tools/refreshrom.py's loops: from the ROM,
# from work RAM, and from work RAM with a read and a write a pass. Each new colour has to
# come on BlastEm's frame, within 1, and drift from BlastEm with no wait, so the run shows
# the wait is there. After any change to the wait or the 68000's bus.
#   bash tools/refresh-test.sh [frames]   (300; a colour about every 5 frames; 1.6% is 5 frames by the end)
#   NO_BUILD=1 to run on the sim that's built. Out in build/refresh_test.
set -uo pipefail
cd "$(dirname "$0")/.."
R=$PWD; O=build/refresh_test; N=${1:-300}; fail=0; mkdir -p "$O"
[ -n "${NO_BUILD:-}" ] || bash tools/sim.sh --frames 1 --every 0 > /dev/null || exit 1
i=0
for t in "rom:" "ram:--ram" "data:--ram --data"; do
  i=$((i + 1)); name=${t%%:*}; flags=${t#*:}
  python3 -I tools/refreshrom.py "$O/$name.bin" $flags
  bash tools/blastem-frames.sh "$O/$name.bin" "$N" --out "$O/$name-wait" > /dev/null || fail=1
  bash tools/blastem-frames.sh "$O/$name.bin" "$N" --out "$O/$name-none" --no-refresh > /dev/null || fail=1
  mkdir -p "$O/$name-sim"
  ( cd src/fpga/core/rtl/FX68K && "$R/build/sim/obj/Vsystem" "$R/$O/$name.bin" --out "$R/$O/$name-sim" --frames "$N" --every 0 > /dev/null 2>&1 )
  python3 -I - "$O/$name-sim/frames.txt" "$O/$name-wait/frames.txt" "$O/$name-none/frames.txt" "$name" <<'PY' || fail=1
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'sim/genesis')
import lag
a, b, c = (lag.read(p) for p in sys.argv[1:4])
# (a colour comes on in the middle of a frame, and that frame's picture wants the very line, so
# only the whole frames after each are looked for; the wait shows as the drift without it)
wait = [(n, d) for n, d in lag.lag(a, b) if n > 10]
none = [d for n, d in lag.lag(a, c) if n > 10 and d is not None]
got = [d for n, d in wait if d is not None]
drift = max(none) - min(none)
good = len(got) >= len(wait) // 5 and all(abs(d) <= 1 for d in got) and drift >= len(a) // 100
print('%-5s %d whole colours found of %d pictures, against BlastEm %d to %d; against BlastEm with no wait %d to %d: %s' % (
    sys.argv[4], len(got), len(wait), min(got), max(got), min(none), max(none), 'ok' if good else 'FAIL'))
sys.exit(0 if good else 1)
PY
  echo "$i of 3 loops"
done
[ $fail = 0 ] && echo "all ok" || { echo "something failed"; exit 1; }
