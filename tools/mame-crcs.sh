#!/bin/bash
# MAME's frames as a frames.txt beside the sim's and BlastEm's: every frame's
# CRC, so sim/genesis/lag.py can say how far apart the runs are.
#   bash tools/mame-crcs.sh rom frames outdir [--japan|--europe]
# Numbered as tools/mame-frames.sh files them (MAME's N - 1 is the sim's N), and
# each colour taken to the nearest of core_top.sv's levels first (MAME's table
# differs in two), so the CRC is the sim's for the same picture.
set -euo pipefail
cd "$(dirname "$0")/.."
ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); N=$2; OUT=$3; SYS=genesis
[ "${4:-}" = --japan ] && SYS=megadrij
[ "${4:-}" = --europe ] && SYS=megadriv
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
ln -s "$ROM" "$TMP/$(basename "$ROM")"
mkdir -p "$TMP/md_rom_svp"; head -c 2048 /dev/zero | LC_ALL=C tr '\0' '\377' > "$TMP/md_rom_svp/svp.bin"
mkfifo "$TMP/px"
cat > "$TMP/px.lua" <<LUA
local n, f = 0, io.open("$TMP/px", "wb")
local s = manager.machine.screens[":megadriv"]
emu.register_frame_done(function()
  n = n + 1
  local p, w, h = s:pixels()
  f:write(string.pack("<III", n + 1, w, h)); f:write(p); f:flush()
  if n >= $N then f:close(); manager.machine:exit() end
end)
LUA
python3 -I sim/genesis/mame_crcs.py "$TMP/px" "$OUT/frames.txt" &
PY=$!
mame $SYS -cart "$TMP/$(basename "$ROM")" -rompath "$TMP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$TMP/cfg" -nvram_directory "$TMP/nvram" -autoboot_script "$TMP/px.lua" > "$OUT/mame.log" 2>&1 || true
wait $PY
wc -l "$OUT/frames.txt"
