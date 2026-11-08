#!/bin/bash
# The save path in Verilator (sim/save): each .sav loaded through the core's
# data_loader and save_layout, then read back as the Pocket reads it on quit.
#   bash tools/save-test.sh [.sav or folder ...]   (default: the card's Genesis saves)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/save-sim
CORE=src/fpga/core
mkdir -p "$OUT"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb -Mdir "$OUT/obj" \
  sim/save/tb.sv sim/save/dcfifo.sv $CORE/data_loader.sv $CORE/data_unloader.sv $CORE/save_layout.sv \
  > "$OUT/verilator.log" 2>&1 || { tail -30 "$OUT/verilator.log"; exit 1; }

[ $# -eq 0 ] && set -- "/Volumes/Untitled/Saves/genesis/common"
files=()
for a in "$@"; do
  if [ -d "$a" ]; then
    # subfolders too: the card's games are in folders such as To Test; ._ files are macOS's
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$a" -type f -name '*.sav' ! -name '._*' -print0 | sort -z)
  else files+=("$a"); fi
done
n=${#files[@]}; i=0; bad=0
for f in "${files[@]}"; do
  i=$((i+1)); echo "$i of $n"
  python3 -I sim/save/check.py "$OUT/obj/Vtb" "$OUT/scratch" "$f" || bad=$((bad+1))
done
echo "$((n-bad)) of $n saves ok"
[ $bad -eq 0 ]
