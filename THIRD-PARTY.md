# Third-party code and licences

This core is **GPL-3.0-only** as a whole (`LICENSE`). This file lists each
part, whose it is and what its licence asks for. The notices that have to go
with the bitstream are in `dist/Cores/frazilpop.Genesis/licences.txt`, beside
it in the core's folder and in every release zip.

Most of the console's files say GPL version 3 "or (at your option) any later
version", and so does FX68K. The whole is version 3 alone because the files
from MiSTer's core with no header of their own (the SVP, `cofi.sv`,
`cheatcodes.sv`, `EEPROM_STM95.sv`, `lightgun.sv`, `bram.vhd`, `mlab.vhd`)
come under that repository's `LICENSE`, which is version 3 and offers no later
one.

The source of every release is its tag, complete: the bitstream in the zip
builds from it with `tools/build.sh`.

## The console: MiSTer's Genesis core

`src/fpga/core/rtl/` is the `rtl/` of
[MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
at `433f71a` (Aug 2022), GPL-3.0: only the files this core uses, imported as
they were in the history's first commit, so every change since shows against
it. MiSTer's core is the work of Alexey Melnikov (Sorgelig) and its
contributors, among them Kitrinx, Sergey Dvodnenko (srg320), Gregory Hogan,
Shane Lynch, GreyRogue, Jose Tejada, Till Harbaum and György Szombathelyi. It
is built from the parts below.

### fpgagen – BSD-style
Gregory Estrade's [fpgagen](https://github.com/Torlus/fpgagen) (2010), the
first Genesis in an FPGA: the VDP (`vdp.vhd`, `vdp_common.vhd`), the glue
between the chips (`system.sv`) and the pads (`gen_io.sv`), with Till Harbaum's,
Alexey Melnikov's and György Szombathelyi's work since. Sorgelig's
`fourway.v`, `multitap.sv` and `teamplayer.sv` are under the same terms. The
licence asks for its notice to go with the bitstream, so it is in
`licences.txt`.

### FX68K – GPL-3.0-or-later
`rtl/FX68K/`, the 68000, by Jorge Cwik (© 2018), exact to the clock cycle and
built from the real chip's microcode (`microrom.mem`, `nanorom.mem`). The
source files carry only the copyright line; the licence is in `fx68k.txt`
beside them, the author's own notes, kept as MiSTer has them.

### T80 – BSD-style
`rtl/T80/`, the Z80: Daniel Wallner's T80 (© 2001–2002), with MikeJ's,
TobiFlex's and Sorgelig's work since, as the file headers record. Its notice
is in `licences.txt`.

### jt12 and jt89 – GPL-3.0-or-later
`rtl/jt12/` (the YM2612) and `rtl/jt89/` (the SN76489 PSG), by Jose Tejada
(jotego). jt12's `LICENSE` is kept beside it.

### The SVP – GPL-3.0
`rtl/SVP/`, the Samsung SSP1601 in Virtua Racing's cartridge, by Sergey
Dvodnenko (srg320) and Sorgelig for MiSTer. No headers; MiSTer's licence.

### The rest of MiSTer's files
- `sdram.sv`, the memory controller: Sorgelig, GPL-3.0-or-later.
- `lightgun.sv`: Shane Lynch's Menacer and Justifier for MiSTer, GPL-3.0, with
  his later aim from the stick and d-pad.
- `cofi.sv` (composite blending), `cheatcodes.sv` and `EEPROM_STM95.sv` (Pier
  Solar's save chip): Kitrinx, GPL-3.0.
- `audio_iir_filter.v` and `genesis_lpf.v`, the sound's filters: Gregory Hogan
  (Soltan_G42), MIT; the notice is in `licences.txt`.
- `miracle.sv`, the Miracle Piano: GreyRogue, with Minimig's UART by Dennis van
  Weeren, GPL-3.0-or-later.
- `bram.vhd`, `mlab.vhd`: Sorgelig, GPL-3.0.

### Changed for this core
Since October 2026 these differ from MiSTer's files, each change marked in the
file where it is made:

- **Save states** (SAVE-STATES.md): `fx68k.sv`, `fx68kAlu.sv`, `T80.vhd`,
  `T80s.vhd`, `vdp.vhd`, `system.sv`, `gen_io.sv`, `multitap.sv`, `fourway.v`,
  `SVP.vhd`, `SSP160x.vhd`, `jt89.v` and its parts, and the jt12 files its scan
  runs through.
- **`system.sv`** also: the 68000's refresh wait, the serial save chips'
  mappers and the SVP's ROM.
- **`jt12_acc.v`**: a channel muted by its pan is silent at YM2612, with no
  one-bit copy of its releasing note.
- **`lightgun.sv`**: the gun's d-pad aim reaches the whole picture.

`EEPROM_24CXX.sv`, beside them, was written for this core.

## The Pocket

### Analogue openFPGA core template – Analogue's APF Software License Agreement
`src/fpga/apf/`, `core_bridge_cmd.v` and the Quartus project files
(`ap_core.qpf`, `ap_core.qsf`, `core_constraints.sdc`) start from
[Analogue's core template](https://github.com/open-fpga/core-template), under
the licence in their headers (with Analogue's Pocket EULA), which yields to
the MIT or GNU licence wherever the two disagree. `core_top.sv` was written
from the template's, with MiSTer's `Genesis.sv` (GPL-3.0) for the cartridge's
header, the region and the per-game table. `sim/genesis/synch_3.v` is `common.v`'s `synch_3` alone,
for the simulation. The Quartus megafunction output (`mf_pllbase`,
`pin_ddio_clk`, `mf_datatable`, `mf_ddio_bidir_12`) and `pll_cfg/`, Intel's
PLL reconfiguration core generated for PAL's clock, are Intel's generated
code, and `build_id_gen.tcl` is Altera's reference design (Altera Reference
Design License), trimmed by Analogue.

### analogue-pocket-utils – MIT
© 2022 Adam Gastineau
([agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)).
`data_loader.sv`, `sound_i2s.sv` and `sync_fifo.sv` are used as they are;
`data_unloader.sv` has one change, a wait so that it no longer reads its FIFO
before the data is in. The
notice is in `licences.txt`.

### RndMnkIII's Analogizer module – MIT, with GPL parts
`src/fpga/analogizer/` is the adapter module of RndMnkIII's
[Analogizer](https://github.com/RndMnkIII/Analogizer) (`analogizer/` at
`4b35f83`, © 2024 RndMnkIII, MIT), only the files it uses, as
`analogizer.qip` lists them. Three of them carry their own licences:
`yc_out.sv` (Mike Simone, GPL-2.0-or-later), `scandoubler.v` (Till Harbaum,
from MiST, GPL-3.0-or-later) and `vga_out_sw.v` (MiSTer's `vga_out`, by
Sorgelig, GPL). The changes, marked "Genesis" in the files: the
scandoubler's divider an input of the module and four bits wide, for the
console's dot of 8 or 10 clocks, and the PlayStation pad reader left out, as
its `dualshock_controller.v` is free for non-commercial use only, which the
GPL does not allow. The notice is in `licences.txt`.

## Written for this core

Everything else in `src/` – `core_top.sv`, `save_layout.sv`,
`state_bridge.sv`, `video_hold.sv`, `pal_clock.sv`, `pocket_analogizer.sv`,
`EEPROM_24CXX.sv` and the changes above – and everything in `sim/`, `tools/`
and `dist/` but the platform image is GPL-3.0-or-later.

The serial save chips' table – which game has which chip, its size and pages,
and the lines each cartridge's mapper uses (`core_top.sv`, `EEPROM_24CXX.sv`,
`system.sv`) – records facts about the cartridges as
[Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX)'s
`eeprom_i2c.c` and MAME list them, written out afresh. No code of either
emulator is in the core.

`art/genesis-banner.png` and `dist/Platforms/_images/genesis.bin`, the
platform image, were made for this core. The Sega and Genesis names, the logo
and the console's design are Sega's.

## Tools the tests use

None of these is in the core or the repo; the scripts fetch or call them.

| Tool | Licence | Used for |
|---|---|---|
| Intel Quartus Prime Lite 21.1, in Docker (`raetro/quartus:21.1`, Marcus Andrade's image) | Intel's | Building the bitstream (`tools/build.sh`) |
| [Verilator](https://www.veripool.org/verilator/) | LGPL-3.0-only or Artistic-2.0 | Every simulation |
| [GHDL](https://github.com/ghdl/ghdl) | GPL-2.0-or-later | The VDP, T80 and SVP from VHDL to Verilog for the simulation (`tools/get-ghdl.sh`) |
| [BlastEm](https://www.retrodev.com/blastem/) 1.0.0, © Michael Pavone | GPL-3.0 | The reference for timing; `sim/genesis/blastem-dump.patch`, a frame dump, is a change to its source under its licence |
| [MAME](https://github.com/mamedev/mame) | GPL-2.0-or-later | The reference for pictures, the SVP and the serial save chips |

## Credits

This core was guided by Eric Lewis's (ericlewis)
[openFPGA-Genesis](https://github.com/opengateware/openFPGA-Genesis), the
first Genesis core for the Pocket, and by work contributed to it: Shane Lynch's Reset Core and
light guns, Marcus Andrade's choice of the scaler's mode by the picture's
size, and Thomas Watson's vertical blank taken at horizontal sync. It also
follows two forks: RndMnkIII's, which fixed how the game is held in memory and
how it is loaded into it, and Franco Arza's arzacore, which made Multitap a
list with J-Cart.

## ROMs

No ROM images, or anything taken from them, are ever committed or distributed.
They're loaded at runtime, and tools that read them write only to `build/`.
