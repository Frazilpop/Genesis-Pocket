#!/bin/bash
# The clock's change for PAL in Verilator (sim/pal): src/fpga/core/pal_clock.sv
# with Intel's reconfig core, a model of the PLL on its far side.
#   bash tools/pal-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/pal-sim
CFG=src/fpga/core/pll_cfg
mkdir -p "$OUT"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb -Mdir "$OUT/obj" \
  sim/pal/tb.sv src/fpga/core/pal_clock.sv $CFG/pll_cfg.v \
  $CFG/submodules/altera_pll_reconfig_top.v $CFG/submodules/altera_pll_reconfig_core.v $CFG/submodules/altera_std_synchronizer.v \
  > "$OUT/verilator.log" 2>&1 || { grep -E '%Error' "$OUT/verilator.log" | head -30; tail -5 "$OUT/verilator.log"; exit 1; }
"$OUT/obj/Vtb"
