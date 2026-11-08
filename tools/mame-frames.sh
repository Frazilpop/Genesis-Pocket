#!/bin/bash
# The reference for the simulation: MAME's Genesis on the same ROM, its frames
# snapshotted into build/mame_genesis/f_NNNNN.png, to set beside tools/sim.sh's
# with sim/genesis/compare.py.
#   bash tools/mame-frames.sh [rom] <frame> [frame ...] [--japan|--europe]
# With no ROM, the test ROM (tools/testrom.py). MAME's genesis is the American
# console (NTSC, export), as the core runs a USA game; --japan takes megadrij
# for a Japanese one, --europe megadriv for a European one (PAL, export). The sim's frame N is MAME's N - 1
# from power-on (the sim starts a little into MAME's first frame), so MAME's
# N - 1 is filed as f_N: the test ROM's frames were the sim's pixel for pixel
# but for two levels of core_top.sv's colour table.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: bash tools/mame-frames.sh [rom] <frame> [frame ...] [--japan|--europe]"; exit 2; }
command -v mame >/dev/null || { echo "MAME is not on this Mac: brew install mame"; exit 1; }
if [[ "$1" =~ ^[0-9]+$ ]]; then mkdir -p build/sim; python3 -I tools/testrom.py build/sim/testrom.bin; ROM=$PWD/build/sim/testrom.bin
else ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift; fi
SYS=genesis; FRAMES=()
for a in "$@"; do if [ "$a" = --japan ]; then SYS=megadrij; elif [ "$a" = --europe ]; then SYS=megadriv; else FRAMES+=("$a"); fi; done
# MAME's first frame done is its 1, the sim's 2, so there is no MAME frame for the sim's 1, and a snapshot
# asked for and never taken would file every later one a frame early
for f in "${FRAMES[@]}"; do [ "$f" -ge 2 ] || { echo "mame-frames.sh: frame $f: the first MAME has is 2" >&2; exit 2; }; done
OUT=${MAME_OUT:-build/mame_genesis}   # MAME_OUT: somewhere else (a game's own folder)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$OUT"; mkdir -p "$OUT"
SORTED=$(printf '%s\n' "${FRAMES[@]}" | sort -n | tr '\n' ' ')
LAST=$(printf '%s\n' "${FRAMES[@]}" | sort -n | tail -1)
cat > "$TMP/snap.lua" <<EOF
local want, n = {}, 0
for f in string.gmatch("$SORTED", "%d+") do want[tonumber(f) - 1] = true end
emu.register_frame_done(function()
  n = n + 1
  if want[n] then manager.machine.video:snapshot() end
  if n >= $LAST then manager.machine:exit() end
end)
EOF
# MAME wants the ROM in a folder of its own; a link to it
ln -s "$ROM" "$TMP/$(basename "$ROM")"
# An SVP game (Virtua Racing): MAME wants the chip's internal ROM, which no
# one has dumped. It warns on the checksum and goes on with this empty one, the
# game starts at 0x400 and doesn't call it, and the core has none either.
mkdir -p "$TMP/md_rom_svp"; head -c 2048 /dev/zero | LC_ALL=C tr '\0' '\377' > "$TMP/md_rom_svp/svp.bin"
# (its cfg and nvram, which it writes where it runs, kept in the temp folder too)
mame $SYS -cart "$TMP/$(basename "$ROM")" -rompath "$TMP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -cfg_directory "$TMP/cfg" -nvram_directory "$TMP/nvram" -snapshot_directory "$TMP/snap" -snapname 's/%i' -autoboot_script "$TMP/snap.lua" > "$TMP/mame.log" 2>&1 \
  || { tail -5 "$TMP/mame.log"; exit 1; }
i=0
for f in $SORTED; do
  printf -v src "$TMP/snap/s/%04d.png" $i
  printf -v dst "$OUT/f_%05d.png" "$f"
  [ -f "$src" ] && mv "$src" "$dst"
  i=$((i+1))
done
ls "$OUT" | wc -l | tr -d ' ' | xargs -I{} echo "{} frames from MAME's $SYS in $OUT"
