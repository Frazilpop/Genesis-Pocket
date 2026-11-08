#!/bin/bash
# How many sprites the VDP draws on a line, against BlastEm: a ROM's rows
# (tools/spriterom.py) in H40, H32 and with 16-wide sprites. High Sprite Limit off,
# the picture must be BlastEm's to the pixel; on, the longest row is drawn whole.
# After any change to the VDP's sprites, or to how the sim translates it (a latch
# once froze the limit at 16, whatever the mode).
#   NO_BUILD=1 bash tools/sprite-test.sh   (on the sim that's built)
set -euo pipefail
cd "$(dirname "$0")/.."
R=$PWD; O=build/sprite_test; mkdir -p "$O"
[ -n "${NO_BUILD:-}" ] || bash tools/sim.sh --frames 1 --every 0 > /dev/null
fail=0
check() {  # name, flags, what the longest row should draw with the limit high
  local name=$1 flags=$2 high=$3
  python3 -I tools/spriterom.py "$O/$name.bin" $flags
  bash tools/blastem-frames.sh "$O/$name.bin" 4 --out "$O/$name-blastem" > /dev/null
  for hi in 0 1; do
    mkdir -p "$O/$name-$hi"
    ( cd src/fpga/core/rtl/FX68K && SIM_HIGH_SPRITES=$hi "$R/build/sim/obj/Vsystem" "$R/$O/$name.bin" --out "$R/$O/$name-$hi" --frames 4 --every 4 > /dev/null 2>&1 )
  done
  local a b c rows
  a=$(awk '$1==4 {print $3}' "$O/$name-0/frames.txt"); b=$(awk '$1==4 {print $3}' "$O/$name-blastem/frames.txt")
  rows=$(python3 -I tools/spriterom.py --count "$O/$name-1/f_00004.png")
  if [ "$a" = "$b" ]; then echo "ok    $name: limit off, BlastEm's picture ($a)"; else echo "FAIL  $name: limit off $a, BlastEm's $b"; fail=1; fi
  c=${rows##*,}; c=${c%]}; c=${c// /}
  if [ "$c" = "$high" ]; then echo "ok    $name: limit on, rows $rows"; else echo "FAIL  $name: limit on, rows $rows, the last should be $high"; fail=1; fi
}
check h40 "" 36
check h32 --h32 28
check wide --wide 36
[ $fail = 0 ] && echo "all ok" || { echo "something failed"; exit 1; }
