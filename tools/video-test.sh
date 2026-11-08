#!/bin/bash
# The picture onto the video clock, in Verilator (sim/video): every phase a VDP's
# line can lie at against the clock, straight into the video registers with the
# fit's delays, and through video_hold.sv.
#   bash tools/video-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/video-sim
mkdir -p "$OUT"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb -Mdir "$OUT/obj" \
  sim/video/tb.sv src/fpga/core/video_hold.sv > "$OUT/verilator.log" 2>&1 || { tail -30 "$OUT/verilator.log"; exit 1; }
"$OUT/obj/Vtb" | grep -v '^- '
