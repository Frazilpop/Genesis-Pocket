#!/bin/bash
# The SVP beside MAME's, an instruction at a time, for when Virtua Racing goes
# wrong: the 68000's writes to the SVP and the VDP's control port, then the SSP's
# registers from the 68000's first job, and the first place the two part.
#   bash tools/svp-trace.sh [rom] [--frames N]   (roms/virtuaracing.md, 35)
# MAME goes through its debugger, so the SSP's trace is its own; out in
# build/svp_trace. A clean SSP here found GHDL's NEG (tools/sim.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v mame >/dev/null || { echo "MAME is not on this Mac: brew install mame"; exit 1; }
ROM=roms/virtuaracing.md; FRAMES=35
while [ $# -gt 0 ]; do case "$1" in --frames) FRAMES=$2; shift 2;; *) ROM=$1; shift;; esac; done
ROM=$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")
OUT=$PWD/build/svp_trace; rm -rf "$OUT"; mkdir -p "$OUT/sim"

echo "1 of 3: the simulation"
SIM_BUSLOG=$OUT/bus_sim.txt SIM_SSPLOG=$OUT/ssp_sim.txt bash tools/sim.sh "$ROM" --frames "$FRAMES" --every 1000 --out "$OUT/sim" | tail -1

echo "2 of 3: MAME"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/md_rom_svp"; head -c 2048 /dev/zero | LC_ALL=C tr '\0' '\377' > "$TMP/md_rom_svp/svp.bin"   # as tools/mame-frames.sh
ln -s "$ROM" "$TMP/$(basename "$ROM")"
echo go > "$TMP/go.dbg"
cat > "$TMP/trace.lua" <<EOF
local n, started, after = 0, false, 0
local f = io.open("$OUT/bus_mame.txt", "w")
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local dbg = manager.machine.debugger
local function w(o, d) f:write(string.format("%d W %06x %04x\n", n, o & 0xfffffe, d)); return d end
local function job(o, d)
  w(o, d)
  if d == 5 and not started then
    started = true
    dbg:command("focus :mdslot:rom_svp:svp")
    dbg:command('trace $OUT/ssp_mame.txt,:mdslot:rom_svp:svp,noloop,{tracelog "%X %X %X ",a,x,y}')
    dbg:command("go")
  end
end
TAPS = {sp:install_write_tap(0xa15000, 0xa1500f, "w1", w), sp:install_write_tap(0xc00004, 0xc00007, "w2", w),
        sp:install_write_tap(0x30fe00, 0x30fe07, "w3", w), sp:install_write_tap(0x30fe08, 0x30fe09, "w4", job),
        sp:install_write_tap(0x30fe0a, 0x30fe0f, "w5", w)}
emu.register_frame_done(function()
  n = n + 1
  if started then after = after + 1 end
  if after >= 2 and n >= $FRAMES then dbg:command("trace off"); f:close(); manager.machine:exit() end
end)
EOF
(cd "$TMP" && mame genesis -cart "$TMP/$(basename "$ROM")" -rompath "$TMP" -video none -sound none -nothrottle -skip_gameinfo -window \
  -debug -debugger none -debugscript "$TMP/go.dbg" -cfg_directory "$TMP/cfg" -nvram_directory "$TMP/nvram" -autoboot_script "$TMP/trace.lua" > "$TMP/mame.log" 2>&1) \
  || { tail -5 "$TMP/mame.log"; exit 1; }

echo "3 of 3: the two compared"
python3 -I sim/genesis/svp_compare.py "$OUT"
