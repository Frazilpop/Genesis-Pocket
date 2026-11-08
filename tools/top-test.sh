#!/bin/bash
# core_top.sv on its own in Verilator (sim/top): a fake Pocket on one side, the console's
# stand-in on the other, its checks and a hash of every port, clock by clock.
#   bash tools/top-test.sh [rev]         this tree's core_top.sv (or a revision's), with that revision's interact.json
#   bash tools/top-test.sh --against rev this tree's and rev's, the same to the clock or it fails
#   bash tools/top-test.sh --console [--against rev] ROM [--frames N] [--every K] [--press F] [--rows N] [--composite N]
#        [--anz V,V,... [--anz-at F]]
#        (--rows: Region's value as the game starts, and 4 for PAL 60 Hz; --composite: Composite Blend's;
#         --anz: the Analogizer in each video mode in turn from frame F, then python3 -I sim/top/anz.py)
#                                        the real console behind it: a game whole, its frames off the video pins,
#                                        in build/top-sim/console-NAME (bash tools/sim.sh first: its VHDL translation)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/top-sim
CORE=src/fpga/core
# the Analogizer: this tree's module and RndMnkIII's (an older core_top.sv leaves them unused)
A=src/fpga/analogizer
mkdir -p "$OUT/anz"
# Two of its files as Verilator needs them, as the other cores' benches have them:
# scandoubler.v's colour-depth branch for a remainder it never has here selects zero
# bits, which Quartus passes over and Verilator refuses, so the width is held at one;
# serlatch_gc.v reads a seventeenth bit from NES and SNES pads into bit 16 of a 16-bit
# register, a write that does nothing in Quartus and that Verilator wraps onto bit 0,
# the pads' first button
sed 's/ -:n\]/ -:(n>0?n:1)]/g' "$A/scandoubler.v" > "$OUT/anz/scandoubler_sim.v"
sed 's/^\( *\)\(p[12]b_r\[((counter>>1)-1)\] <= i_dat[12];\)/\1if (((counter>>1)-1) < 6'"'"'d16) \2/' \
  "$A/serlatch_gc.v" > "$OUT/anz/serlatch_gc_sim.v"
cmp -s "$A/serlatch_gc.v" "$OUT/anz/serlatch_gc_sim.v" && { echo "serlatch_gc.v: the bench's change no longer applies" >&2; exit 1; }
ANZ=($CORE/pocket_analogizer.sv $A/openFPGA_Pocket_Analogizer.v $A/openFPGA_Pocket_Analogizer_SNAC.sv
     $A/vga_out_sw.v $A/clock_divider_fract.v $A/pcengine_gc.v $A/pcengine_game_controller_multitap.v $A/yc_out.sv
     "$OUT/anz/scandoubler_sim.v" "$OUT/anz/serlatch_gc_sim.v")

build() {  # name, revision or ""
  local name=$1 rev=$2
  local d="$OUT/$name"
  mkdir -p "$d"
  if [ -n "$rev" ]; then
    git show "$rev:$CORE/core_top.sv" > "$d/core_top.sv"
    git show "$rev:dist/Cores/frazilpop.Genesis/interact.json" > "$d/interact.json"
  else
    cp "$CORE/core_top.sv" "$d/core_top.sv"
    cp dist/Cores/frazilpop.Genesis/interact.json "$d/interact.json"
  fi
  python3 -I tools/top-settings.py "$d/core_top.sv" "$d/interact.json" "$d"
  local D=""; grep -q pocket_analogizer "$d/core_top.sv" && D=-DANZ
  local F="-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-LATCH -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-PROCASSWIRE -Wno-TIMESCALEMOD -Wno-SYMRSVDWORD"
  echo "Building $name"
  verilator --binary --timing -j 0 -O3 --x-assign 0 --x-initial 0 $F $D -CFLAGS -O1 --top-module tb -Mdir "$d/obj" \
    -I"$d" -Isim/top -Isrc/fpga/core \
    sim/top/tb.sv sim/top/models.sv sim/top/system_stub.sv "$d/core_top.sv" \
    $CORE/core_bridge_cmd.v $CORE/data_loader.sv $CORE/data_unloader.sv $CORE/sound_i2s.sv $CORE/sync_fifo.sv \
    $CORE/save_layout.sv $CORE/state_bridge.sv $CORE/video_hold.sv $CORE/pal_clock.sv \
    $CORE/rtl/sdram.sv $CORE/rtl/cofi.sv $CORE/rtl/lightgun.sv "${ANZ[@]}" \
    sim/save/dcfifo.sv sim/genesis/synch_3.v > "$d/verilator.log" 2>&1 \
    || { grep -E '%Error' "$d/verilator.log" | head -30; tail -5 "$d/verilator.log"; exit 1; }
}

run() {  # name, then plusargs
  local name=$1; shift
  echo "Running $name"
  "$OUT/$name/obj/Vtb" "+log=$PWD/$OUT/$name/hash.log" "$@" | grep -v '^- '
}

# ---- the real console behind core_top.sv ----
build_console() {  # name, revision or ""
  local name=$1 rev=$2
  local d="$OUT/console-$name" RTL=$CORE/rtl B=build/sim
  mkdir -p "$d"
  if [ -n "$rev" ]; then
    git show "$rev:$CORE/core_top.sv" > "$d/core_top.sv"
    git show "$rev:dist/Cores/frazilpop.Genesis/interact.json" > "$d/interact.json"
  else
    cp "$CORE/core_top.sv" "$d/core_top.sv"
    cp dist/Cores/frazilpop.Genesis/interact.json "$d/interact.json"
  fi
  python3 -I tools/top-settings.py "$d/core_top.sv" "$d/interact.json" "$d" > /dev/null
  echo "Building the console around $name (some minutes)"
  verilator --binary --timing -j 0 -O3 --x-assign fast --x-initial fast --noassert -DCONSOLE \
    -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-LATCH -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-PROCASSWIRE -Wno-TIMESCALEMOD -Wno-SYMRSVDWORD \
    -CFLAGS -O1 --top-module tb -Mdir "$d/obj" -I"$d" -Isim/top -Isrc/fpga/core \
    -y $RTL/jt12 -y $RTL/jt12/mixer -y $RTL/jt12/adpcm \
    sim/top/tb.sv sim/top/models.sv "$d/core_top.sv" \
    $CORE/core_bridge_cmd.v $CORE/data_loader.sv $CORE/data_unloader.sv $CORE/sound_i2s.sv $CORE/sync_fifo.sv \
    $CORE/save_layout.sv $CORE/state_bridge.sv $CORE/video_hold.sv $CORE/pal_clock.sv \
    $RTL/sdram.sv $RTL/cofi.sv $RTL/lightgun.sv "${ANZ[@]}" sim/save/dcfifo.sv sim/genesis/synch_3.v \
    $RTL/system.sv $RTL/gen_io.sv $RTL/multitap.sv $RTL/teamplayer.sv $RTL/fourway.v \
    $RTL/EEPROM_STM95.sv $RTL/EEPROM_24CXX.sv $RTL/cheatcodes.sv $RTL/genesis_lpf.v $RTL/audio_iir_filter.v \
    $B/fx68k.sv $RTL/FX68K/fx68kAlu.sv $RTL/FX68K/uaddrPla.sv \
    $RTL/jt89/jt89.v $RTL/jt89/jt89_mixer.v $RTL/jt89/jt89_noise.v $RTL/jt89/jt89_tone.v $RTL/jt89/jt89_vol.v \
    sim/genesis/bram.sv $B/gen/vdp.sv $B/gen/t80s.sv $B/gen/svp.sv > "$d/verilator.log" 2>&1 \
    || { grep -E '%Error' "$d/verilator.log" | head -30; tail -5 "$d/verilator.log"; exit 1; }
}

run_console() {  # name, rom, then the plusargs
  local name=$1 rom=$2
  shift 2
  local top="$PWD/$OUT/console-$name"
  rm -f "$top"/f_*.hex "$top"/frames.txt "$top"/anz_v*
  # (the 68000's microcode is read from where it runs)
  ( cd $CORE/rtl/FX68K && "$top/obj/Vtb" "+rom=$rom" "+out=$top" "$@" | grep -v '^- ' )
}

if [ "${1:-}" = "--console" ]; then
  shift
  against=""
  if [ "${1:-}" = "--against" ]; then against=$2; shift 2; fi
  ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
  args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --frames) args+=("+frames=$2"); shift 2 ;;
      --every)  args+=("+every=$2"); shift 2 ;;
      --press)  args+=("+press=$2"); shift 2 ;;
      --rows)   args+=("+rows=$2"); shift 2 ;;
      --composite) args+=("+composite=$2"); shift 2 ;;
      --anz)    args+=("+anz=$2"); shift 2 ;;
      --anz-at) args+=("+anz_at=$2"); shift 2 ;;
      *) echo "top-test.sh: unknown $1" >&2; exit 2 ;;
    esac
  done
  build_console new ""
  run_console new "$ROM" "${args[@]}"
  if [ -n "$against" ]; then
    build_console old "$against"
    run_console old "$ROM" "${args[@]}"
    cmp "$OUT/console-old/frames.txt" "$OUT/console-new/frames.txt" \
      && echo "core_top.sv against $against: every frame the same, $(wc -l < "$OUT/console-new/frames.txt" | tr -d ' ') frames"
  fi
  exit 0
fi

if [ "${1:-}" = "--against" ]; then
  [ $# -ge 2 ] || { echo "--against wants a revision" >&2; exit 2; }
  build old "$2" & build new "" & wait
  # (an older core_top.sv with no Analogizer: its part of the session left out of both)
  extra=(); grep -q pocket_analogizer "$OUT/old/core_top.sv" || extra=(+no_anz)
  # (the checks are this tree's, so a revision that does otherwise on purpose fails them: the hashes say where)
  run old ${extra[@]+"${extra[@]}"} || true
  run new ${extra[@]+"${extra[@]}"}
  # (sorted: two domains' lines at the same moment come in the order the model runs them)
  if cmp -s <(sort "$OUT/old/hash.log") <(sort "$OUT/new/hash.log"); then
    echo "core_top.sv against $2: the same on every port, $(wc -l < "$OUT/new/hash.log" | tr -d ' ') hashes"
  else
    python3 -I - "$OUT/old/hash.log" "$OUT/new/hash.log" <<'PY'
import sys
a, b = [sorted(open(p).read().split('\n'), key=lambda l: (int(l.split()[0]) if l.split() and l.split()[0].isdigit() else -1, l)) for p in sys.argv[1:3]]
for x, y in zip(a, b):
    if x != y:
        print('First difference:\n  old', x, '\n  new', y)
        break
PY
    exit 1
  fi
else
  build one "${1:-}"
  run one
fi
