#!/bin/bash
# The whole Genesis in Verilator (sim/genesis): a ROM in, frames as PNGs and
# the sound as a WAV out, in build/sim_genesis (sim/genesis/README.md).
#   bash tools/sim.sh [rom] [--frames N] [--every K] [--save F,F] [--press F:buttons[:N]] [--region R] [--fm-log FILE]
# With no ROM, the test ROM tools/testrom.py makes (build/sim/testrom.bin).
# The build is kept in build/sim and made again only when a source changes.
set -euo pipefail
cd "$(dirname "$0")/.."
RTL=src/fpga/core/rtl
SIM=sim/genesis
B=build/sim
OUT=build/sim_genesis
mkdir -p "$B/gen" "$OUT"

# 1 of 4: GHDL, fetched once
bash tools/get-ghdl.sh
GHDL="$PWD/build/tools/ghdl/bin/ghdl"

# 2 of 4: the VHDL chips in Verilog, again when one of them changes
VHDL=($SIM/bram_sim.vhd $RTL/vdp_common.vhd $RTL/vdp.vhd
      $RTL/T80/T80_Reg.vhd $RTL/T80/T80_MCode.vhd $RTL/T80/T80_ALU.vhd $RTL/T80/T80.vhd $RTL/T80/T80s.vhd
      $RTL/SVP/SSP160x_PKG.vhd $RTL/SVP/SSP160x.vhd $RTL/SVP/SVP.vhd)
KEY=$(cat "${VHDL[@]}" $SIM/wrap.py $RTL/system.sv tools/sim.sh | shasum | cut -c1-16)
if [ "$(cat "$B/gen/key" 2>/dev/null)" != "$KEY" ]; then
  echo "Translating the VDP, the Z80 and the SVP from VHDL"
  rm -rf "$B/gen"; mkdir -p "$B/gen/work" "$B/gen/vhd"
  # Quartus takes "u : work.e" without the word entity, and the T80's
  # undocumented-I/O parity masks a 9-bit value with x"7"; GHDL wants both
  # written out (the same meaning). GHDL's synthesis turns the SSP's 0-signed(A)
  # into A - 0, so its NEG and ABS do nothing and Virtua Racing draws no polygon:
  # that one as -signed(A). The VDP's OBJ_MAX_LINE, a when/else chain with no last
  # else, becomes a latch GHDL writes as always @(enable), and as the enable never
  # changes it keeps its first value, 16 sprites a line in every mode; Quartus
  # makes it plain logic, so the last when goes. The copies are build's; rtl/ is untouched.
  for f in "${VHDL[@]}"; do
    sed -E 's/:[[:space:]]*work\./: entity work./; s/\(ioq and x"7"\)/(ioq and "000000111")/; s/0-signed\(A\)/-signed(A)/; s/(OBJ_MAX_LINE_H32_HIGH, 6\)) when H40 = .0. and OBJ_LIMIT_HIGH_EN = .1.;/\1;/' "$f" > "$B/gen/vhd/$(basename "$f")"
    "$GHDL" -a --std=08 -frelaxed -fsynopsys --workdir="$B/gen/work" "$B/gen/vhd/$(basename "$f")" 2>> "$B/gen/ghdl.log" \
      || { tail -20 "$B/gen/ghdl.log"; exit 1; }
  done
  synth() {  # entity, file, generics...
    local e=$1 out=$2; shift 2
    "$GHDL" --synth --latches --std=08 -frelaxed -fsynopsys --workdir="$B/gen/work" --out=verilog "$@" "$e" \
      > "$B/gen/$out.raw.v" 2>> "$B/gen/ghdl.log" || { grep -i error "$B/gen/ghdl.log" | tail -20; exit 1; }
  }
  synth vdp vdp
  synth t80s t80s -gT2Write=1
  synth svp svp
  # (a latch GHDL writes as always @(enable) never follows its input: see above)
  if grep -nE 'always @\(n[0-9]+\)' "$B"/gen/*.raw.v; then echo "A latch in the translation that won't work in Verilator: rewrite it as above"; exit 1; fi
  python3 -I $SIM/wrap.py "$B/gen/vdp.raw.v" $RTL/vdp.vhd vdp $RTL/system.sv > "$B/gen/vdp.sv"
  python3 -I $SIM/wrap.py "$B/gen/t80s.raw.v" $RTL/T80/T80s.vhd T80s $RTL/system.sv T2Write=1 > "$B/gen/t80s.sv"
  python3 -I $SIM/wrap.py "$B/gen/svp.raw.v" $RTL/SVP/SVP.vhd SVP $RTL/system.sv > "$B/gen/svp.sv"
  echo "$KEY" > "$B/gen/key"
fi

# 3 of 4: Verilator, again when a source changes (its make does the rest)
python3 -I $SIM/quirks.py src/fpga/core/core_top.sv > "$B/quirks.inc"
# FX68K's structs written packed: Verilator takes no unpacked variable that is
# assigned both continuously and in a clocked block, as FX68K's Nanod is; the
# members, and what they do, are the same (the copy is build's)
sed 's/^typedef struct {/typedef struct packed {/' $RTL/FX68K/fx68k.sv > "$B/fx68k.sv.new"
cmp -s "$B/fx68k.sv.new" "$B/fx68k.sv" && rm "$B/fx68k.sv.new" || mv "$B/fx68k.sv.new" "$B/fx68k.sv"
SRC=($RTL/system.sv $RTL/gen_io.sv $RTL/multitap.sv $RTL/teamplayer.sv $RTL/lightgun.sv $RTL/fourway.v
     $RTL/EEPROM_STM95.sv $RTL/EEPROM_24CXX.sv $RTL/cheatcodes.sv $RTL/genesis_lpf.v $RTL/audio_iir_filter.v
     "$B/fx68k.sv" $RTL/FX68K/fx68kAlu.sv $RTL/FX68K/uaddrPla.sv
     $RTL/jt89/jt89.v $RTL/jt89/jt89_mixer.v $RTL/jt89/jt89_noise.v $RTL/jt89/jt89_tone.v $RTL/jt89/jt89_vol.v
     $SIM/bram.sv "$B/gen/vdp.sv" "$B/gen/t80s.sv" "$B/gen/svp.sv" $SIM/public.vlt)
# the Pocket's side of the save states, a model of its own (main.cpp's --pocket)
verilator --cc --build -j 0 -O3 --x-assign fast --x-initial fast --noassert \
  -Wno-fatal -Wno-lint -Wno-style --prefix Vbridge --top-module state_bridge -Mdir "$B/bridge" \
  -CFLAGS -O2 src/fpga/core/state_bridge.sv src/fpga/core/data_loader.sv sim/save/dcfifo.sv $SIM/synch_3.v \
  > "$B/verilator-bridge.log" 2>&1 || { grep -E '%Error' "$B/verilator-bridge.log" | head -30; tail -5 "$B/verilator-bridge.log"; exit 1; }
echo "Building the simulation (Verilator; a few minutes the first time)"
verilator --cc --exe --build -j 0 -O3 --x-assign fast --x-initial fast --noassert \
  -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-LATCH -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-PROCASSWIRE \
  --top-module system -Mdir "$B/obj" ${SIM_VFLAGS:-} \
  -y $RTL/jt12 -y $RTL/jt12/mixer -y $RTL/jt12/adpcm \
  -CFLAGS "-O2 -I$PWD/$B -I$PWD/$B/bridge" -LDFLAGS "-lz $PWD/$B/bridge/Vbridge__ALL.a" -MAKEFLAGS OPT_FAST=-O3 \
  "${SRC[@]}" "$PWD/$SIM/main.cpp" > "$B/verilator.log" 2>&1 || { grep -E '%Error' "$B/verilator.log" | head -30; tail -5 "$B/verilator.log"; exit 1; }

# 4 of 4: the run. The 68000's microcode is read from where it runs.
ROM=""
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then ROM=$1; shift; fi
if [ -z "$ROM" ]; then python3 -I tools/testrom.py "$B/testrom.bin"; ROM=$B/testrom.bin; fi
ROM=$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")
rm -f "$OUT"/f_*.png "$OUT"/frames.txt "$OUT"/audio.wav "$OUT"/run.json
OUT_ABS="$PWD/$OUT"
cd $RTL/FX68K
"$OLDPWD/$B/obj/Vsystem" "$ROM" --out "$OUT_ABS" "$@"
