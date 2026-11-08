#!/bin/bash
# Save states in the simulation, proved: a
# save at frame F and the run going on; the state loaded into a fresh run and,
# before it lets go, read straight back out; then from the clock each lets go,
# the two compared frame by frame (picture, and the chips' sound every clock)
# for N frames, and a serial save chip's contents at the end. Out in build/state_test/NAME.
#   bash tools/state-test.sh [rom] [--at F] [--frames N] [--delay CLOCKS] [--name NAME] [--pocket] [--press F:BUTTONS[:N]]... [--hold F:BUTTONS] [--from STATE] [--save-opt OPT]... [--load-opt OPT]...
# --press: as tools/sim.sh's, in the saving run only, so before F. --hold: held from
# frame F of the saving run on, and all through the loaded run: driving in a race.
# --from: the saving run starts by loading STATE, a quick way to a point deep in a game.
# --shots F,F: PNGs of those frames from the saving run, in its out directory.
# --pocket: both runs through core/state_bridge.sv, as the Pocket reads and
# writes it (sim/genesis/main.cpp's --pocket says how, and its SIM_POCKET_*).
# --save-opt, --load-opt: an option of the simulation's for one run alone, as
# --load-opt --pal60: a state made at 50 Hz loaded into a game started at 60.
# With no ROM, the test ROM. Runs the simulation tools/sim.sh builds;
# NO_BUILD=1 to run more than one at once on that build.
set -uo pipefail
cd "$(dirname "$0")/.."
ROM=""; F=60; N=600; DELAY=0; NAME=""; POCKET=""; PRESS=(); LOADPRESS=(); FROM=(); SAVEOPT=(); LOADOPT=()
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then ROM=$1; shift; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --at) F=$2; shift 2 ;; --frames) N=$2; shift 2 ;; --delay) DELAY=$2; shift 2 ;; --name) NAME=$2; shift 2 ;; --pocket) POCKET=--pocket; shift ;;
    --from) FROM=(--state-load "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")" --load-at 2); shift 2 ;;
    --press) PRESS+=(--press "$2"); shift 2 ;;
    --save-opt) SAVEOPT+=("$2"); shift 2 ;;
    --load-opt) LOADOPT+=("$2"); shift 2 ;;
    --shots) PRESS+=(--save "$2"); shift 2 ;;
    --hold) PRESS+=(--press "$2:9999999"); LOADPRESS+=(--press "0:${2#*:}:9999999"); shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
# the build, as sim.sh makes it (NO_BUILD=1 when several of these run at once)
[ -n "${NO_BUILD:-}" ] || bash tools/sim.sh --frames 1 > /dev/null || exit 1
if [ -z "$ROM" ]; then ROM=build/sim/testrom.bin; fi
ROM=$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")
[ -n "$NAME" ] || NAME=$(basename "$ROM" | sed 's/\.[^.]*$//')_$F
D=$PWD/build/state_test/$NAME
rm -rf "$D"; mkdir -p "$D/save" "$D/load"
SIM=$PWD/build/sim/obj/Vsystem
cd src/fpga/core/rtl/FX68K                                     # FX68K reads its microcode from here
echo "1 of 2 runs: saved at frame $F"
"$SIM" "$ROM" --out "$D/save" --every 0 --frames $((F + 10 + N)) --state-save $F "$D/state" --save-delay $DELAY --sav-out "$D/save.sav" $POCKET ${FROM[@]+"${FROM[@]}"} ${PRESS[@]+"${PRESS[@]}"} ${SAVEOPT[@]+"${SAVEOPT[@]}"} > "$D/save.log" 2>&1
echo "2 of 2 runs: loaded"
"$SIM" "$ROM" --out "$D/load" --every 0 --frames $((30 + N)) --state-load "$D/state" --load-at 2 --resave "$D/resave" --sav-out "$D/load.sav" $POCKET ${LOADPRESS[@]+"${LOADPRESS[@]}"} ${LOADOPT[@]+"${LOADOPT[@]}"} > "$D/load.log" 2>&1
cd - > /dev/null
grep -h "^state: \(frozen\|black\|let go\|an error\|the file's timing\)" "$D/save.log" "$D/load.log"
ok=1
if [ ! -s "$D/resave" ]; then echo "no state read back"; ok=0
else
  r=$(python3 -I tools/state-dump.py "$D/state" "$D/resave")
  if [ "$r" = "0 bytes differ outside the memories" ]; then echo "read back at once: the same, bar the frame number"
  else echo "read back at once: NOT the same"; echo "$r"; ok=0; fi
fi
n=$(wc -l < "$D/load/after.txt" | tr -d ' '); m=$(wc -l < "$D/save/after.txt" | tr -d ' ')
[ "$m" -lt "$n" ] && n=$m
paste -d' ' <(head -n "$n" "$D/save/after.txt") <(head -n "$n" "$D/load/after.txt") > "$D/compare.txt"
read p snd first <<< "$(awk '{ if ($3==$7) p++; if ($4==$8) s++; if (!f && ($3!=$7 || $4!=$8)) f=$1 } END { print p+0, s+0, (f ? f : "-") }' "$D/compare.txt")"
echo "after letting go: $n frames, the picture the same in $p, the sound in $snd (the first that differs: $first)"
[ "$n" -ge "$N" ] && [ "$p" -eq "$n" ] && [ "$snd" -eq "$n" ] || ok=0
# a game with a serial save chip: what it had written by the end of each run
if grep -q 'quirks:.*eeprom:' "$D/save.log"; then
  if cmp -s "$D/save.sav" "$D/load.sav"; then echo "the save chip at the end: the same"
  else echo "the save chip at the end: NOT the same"; ok=0; fi
fi
[ $ok -eq 1 ] && echo "$NAME: ok" || echo "$NAME: FAILED"
