# SEGA Genesis in Verilator

MiSTer's `system.sv` as the core has it (FX68K, T80, the VDP, jt12, jt89, the
SVP), a ROM where the Pocket's SDRAM would be, and out come the frames as PNGs
and the sound as a WAV. A change is shown here before a bitstream goes to
the Pocket.

```sh
bash tools/sim.sh                                  # the test ROM, 600 frames, a PNG every 60th
bash tools/sim.sh path/to/game.md --frames 900 --every 30
bash tools/sim.sh game.md --save 300,301 --press 400:start --press 700:a+right:120
bash tools/sim.sh game.md --region europe           # auto (the header, as the core) by default
bash tools/sim.sh game.md --pal60                   # NTSC's timing, the game still told PAL if it would be at 50 Hz, as the PAL 60 Hz row
SIM_TRACE=20000 bash tools/sim.sh game.md            # the 68000's address every 20000 clocks
SIM_ROM_LATENCY=8 bash tools/sim.sh game.md          # the ROM's ack 8 clocks after the request (4)
SIM_LPF=3 SIM_HIFI=1 bash tools/sim.sh game.md       # a setting changed: SIM_LPF, SIM_HIFI, SIM_LADDER, SIM_J3BUT, SIM_HIGH_SPRITES
                                                    # (Core Settings' rows), SIM_FM, SIM_PSG, SIM_TURBO (system.sv's own, not
                                                    # in the menu); core_top.sv's settings otherwise
bash tools/sim.sh game.md --fm-log $PWD/build/jt12_writes/game.log   # the YM2612's writes, for sim/jt12
```

`--fm-log FILE` writes the YM2612's inputs as it takes them, a line a
change, timed in MCLK from its first clock enable: `W t addr data` a write
held from `t`, `E t` where it ends, `R t 1/0` the Z80's reset (the
YM2612's). `public.vlt` makes those few signals of `system.sv` readable from
`main.cpp`. The jt12 bench (`tools/jt12-scan-test.sh`) plays them back.

**Save states**, through `system.sv`'s state window as `core_top.sv`
drives it:

```sh
bash tools/state-test.sh                      # the test ROM saved at frame 60, loaded, 600 frames compared
bash tools/state-test.sh roms/sonic3c.md --at 300 --frames 600
bash tools/state-test.sh --at 120 --delay 40000 --name in_stop   # asked 0.75 ms into the frame: the 68000 in STOP
python3 -I tools/state-dump.py STATE [OTHER]  # a state field by field, or what differs between two
bash tools/state-test.sh --pocket             # both runs through core/state_bridge.sv, as the Pocket drives it
bash tools/state-test.sh roms/mrnutz.md --at 100 --frames 200 --pocket --load-opt --pal60   # made at 50 Hz, loaded into a start at 60
```

`--pocket` builds `state_bridge.sv` as a second model (`Vbridge`) beside
`Vsystem`, on the two clocks, with `main.cpp` as the Pocket: Savestate Start,
Load, a word every `SIM_POCKET_PERIOD` clocks of `clk_74a` (88), the bus read
before each read starts, `SIM_POCKET_CHUNK` bytes (4096) then a wait of
`SIM_POCKET_STALL` clocks (40000), each chunk's first word read again.
`SIM_POCKET_RESET=1` brings a load's file with the Pocket's reset still on,
`SIM_POCKET_LONG=1` reads and writes 0x44000 bytes whatever the game (what happens if
the Pocket asks the file's size before a ROM is in),
`SIM_POCKET_PAUSE=N` puts the menu's pause on N frames before the save,
`SIM_POCKET_BADHDR=1` spoils the serial (the game runs on and Load answers an
error). `--sav FILE` starts from a 128 KB `.sav` in the save RAM. A state made at
the other timing has the clock changed as `core_top.sv` and `pal_clock.sv` change
it: `pal` a few clocks after the bridge's `pal_take`, the clock's hold up for
`SIM_POCKET_RETUNE` clocks (30000); without `--pocket` the console takes the
file's PAL as it is written in. `--save-opt` and `--load-opt` give one run alone
an option, `--pal60` say.

`state-test.sh` makes two runs: one saves at frame F (`--state-save F
FILE`; `--save-delay CLOCKS` asks that many clocks into the frame) and goes
on; a fresh one loads the file at frame 2 (`--state-load FILE`, `--load-at`)
and, before it lets go, reads the state straight back out (`--resave FILE`).
Each writes `after.txt` from the clock it lets go: a line a frame, the
picture's CRC and a CRC of the chips' own sound on every clock (`FM_left`,
`FM_right`, `PSG_SND`, before the filters). It passes when the state read back
is the file bar its frame number and the two `after.txt` are the same for N
frames; out in `build/state_test/NAME` (`compare.txt` side by side).
`NO_BUILD=1` runs several at once on one build. `SIM_SSDBG=1` prints the
save logic's states, the clean point's conditions while it looks, the
68000's restore microword by microword with its registers, and both CPUs' PC
after letting go; `SIM_UTRACE=CYCLE` the 68000's microaddresses for 20,000
clocks from CYCLE.

**The SVP** (`roms/virtuaracing.md`):

```sh
bash tools/svp-trace.sh                       # the 68000's writes, then the SSP a register at a time, beside MAME's
python3 -I sim/genesis/compare.py build/sim_genesis build/mame_genesis 40   # a frame's match within 40 of its number
bash tools/state-test.sh roms/virtuaracing.md --at 250 --frames 60             # a save with the SSP in a job (version 2 of the format)
```

`state-test.sh` takes `--press F:BUTTONS[:N]` (the saving run only, so before the save), `--hold F:BUTTONS` (from
F on, and all through the loaded run), `--shots F,F` (PNGs from the saving run) and `--from STATE` (the saving run
starts by loading STATE: a quick way deep into a game, but then both runs have been through a load, so
something a load resets the same in each won't show; prove from power-on too). Into a race from power-on: Start at
300, 400 ... 1000, C at 1100; the race's GO! is at about frame 1950. On the course screen C starts, B
goes back.

`svp-trace.sh` sets `SIM_BUSLOG` and `SIM_SSPLOG`, and takes MAME's through its debugger, and
names the first instruction where A, X or Y differs. The loops where the SSP waits for the 68000
are left out, as they run as long as the 68000 takes. `SIM_TRACE` also gives the SSP's PC.

**A serial save chip** (`rtl/EEPROM_24CXX.sv`):

```sh
bash tools/sim.sh roms/wilywars.md --frames 240 --sav-out $PWD/out.sav   # the chip, as the Pocket writes the .sav (a RAM byte is a file word's odd byte)
bash tools/sim.sh roms/wilywars.md --sav $PWD/out.sav                    # a restart with it
bash tools/sim.sh roms/wilywars.md --i2c-log $PWD/i2c.log                # a line each time SCL, SDA or what SDA reads changes, W addr data each byte kept
bash tools/eeprom-test.sh                                                # every mapper and chip, on a test ROM for it (tools/eepromrom.py)
```

The sim sets a game's chip by core_top.sv's table, as it does the quirks.

`--press F:buttons[:N]` holds buttons on pad 1 from frame F for N frames
(4 by default): `up down left right a b c start x y z mode`, joined with `+`.

Out, in `build/sim_genesis/`:

| file | what |
|---|---|
| `f_NNNNN.png` | the frames asked for: the picture as `core_top.sv` gives it to the Pocket, its lines (VBL taken at HSYNC) and its colours (`color_lut`) |
| `frames.txt` | every frame: its number, size and a CRC of its pixels, for comparing two runs |
| `audio.wav` | the DAC (`DAC_LDATA`, `DAC_RDATA`), 16-bit stereo at 48 kHz |
| `run.json` | the ROM, its serial, region and quirks, the frames, the time, the speed |

**The reference is MAME's Genesis** (`brew install mame`):

```sh
bash tools/mame-frames.sh game.md 300 600 900   # MAME's frames into build/mame_genesis
python3 -I sim/genesis/compare.py               # each sim frame beside MAME's, pixels that differ
```

The sim's frame N is MAME's N − 1 from power-on, so `mame-frames.sh` files
it as N and the names pair up. The
comparison is by colour level, as MAME's table differs from `core_top.sv`'s
in two levels (8: 144 against 146; 10: 172 against 174). `MAME_OUT=dir` puts
MAME's frames somewhere else. MAME judges the picture and the SVP; it does not
judge the timing, which is BlastEm's:

**The reference for timing is BlastEm**, cycle-exact where MAME's Genesis is not:

```sh
bash tools/blastem-frames.sh game.md 900 --out build/x/blastem               # every frame's CRC, in a frames.txt as the sim's
bash tools/blastem-frames.sh game.md 900 --out build/x/none --no-refresh     # without the 68000's refresh wait, to see what it does
bash tools/blastem-frames.sh game.md 620 --keep 480,540                      # PNGs of those frames (or all) for compare.py; --vram F the VDP's memory
bash tools/mame-crcs.sh game.md 900 build/x/mame                             # MAME's frames as the same CRCs
bash tools/sim.sh game.md --frames 900 --every 0                             # the sim, with a console's sprite limit as the two have (SIM_HIGH_SPRITES=1 for the setting on)
python3 -I sim/genesis/lag.py build/sim_genesis/frames.txt build/x/none/frames.txt   # each new picture's frame against the other run's
bash tools/sprite-test.sh                                                    # the sprites on a line against BlastEm, on a ROM for it (tools/spriterom.py)
bash tools/refresh-test.sh                                                   # the 68000's speed against BlastEm's, from the ROM and from work RAM (tools/refreshrom.py)
```

BlastEm has no frame dump, so `blastem-frames.sh` fetches its source (pinned),
puts `blastem-dump.patch` on it and builds it into `build/tools/blastem`, with
Homebrew's glew, sdl2-compat and pkgconf, the first time. On arm64 that is its
interpreted 68000; its x86 JIT under Rosetta, tried by hand, gave
the same lags. It can't run Virtua Racing (no SVP: it stops within 12 frames).

Its frame N is filed as N + 1, as MAME's, and the pictures compare by CRC. Over 900
frames, no input, of Castle of Illusion, Gunstar Heroes, Shining Force and Sonic 3
Complete, every picture in the sim is one BlastEm shows, bar the first frame, on the
same frame or now and then within 1. Against MAME they run -1 to +3 frames, MAME
the odd one out. The test ROM: 96 of 130 frames BlastEm's exactly, the rest 2 or 3 pixels on
the lines where its H interrupt writes a colour and a few at its start. MAME's differ from both by 120
pixels on lines 63, 127 and 191, where it takes that colour a line later.

The ROMs are never committed; `roms/` (ignored by git) holds the ones the
sim is run on. `tools/testrom.py` makes one to commit, `build/sim/testrom.bin`:
68000 code written out by hand that touches each part of the system and shows
it. The top band is green while the Z80 counts, the second white while Start
is held, plane A scrolls and a sprite moves on the vertical interrupt, the
tiles come by a DMA from the ROM, the PSG sounds at 440 Hz and the YM2612 at
660 Hz.

## How it is built

`tools/sim.sh` does it all, again only for what changed (build in `build/sim`):

1. **GHDL** (`tools/get-ghdl.sh`): its macOS release, pinned by checksum,
   into `build/tools/ghdl` the first time. Homebrew's cask is disabled.
2. **The VHDL chips in Verilog.** GHDL's `--synth` translates the VDP
   (`vdp.vhd`, `vdp_common.vhd`), the Z80 (`T80s`, with `T2Write` 1 as
   `system.sv` sets it) and the SVP. `bram_sim.vhd` stands in for
   `bram.vhd`/`mlab.vhd`, whose Altera RAMs GHDL cannot read: the same
   entities, behaved as the core sets altsyncram (the address registered, the
   output not; mlab's read not registered at all). Two of Quartus's
   allowances are written out in build's copies (rtl/ is untouched): `u :
   work.e` gets the word `entity`, and the T80's `ioq and x"7"` (a 9-bit value
   masked with 4 bits) becomes the 9-bit mask Quartus takes it as. GHDL's synthesis
   writes the SSP's `0-signed(A)` as `A - 0`, so that is written `-signed(A)`.
   The VDP's `OBJ_MAX_LINE`, a `when`/`else` chain with no last `else`, becomes a
   latch GHDL writes as `always @(enable)`; its enable never changes, so it kept its
   first value, and the sim drew 16 sprites a line in every mode
   (Castle of Illusion's ONCE UPON A MOUSE... lost its last four letters). The last
   `when` goes in build's copy, and `sim.sh` stops if the translation has another.
   `wrap.py` puts a module in front of each translation, its ports spelled as
   `system.sv` spells them (VHDL ignores case, Verilog does not: the VDP's
   `RST_N` is `system.sv`'s `RST_n`), with each VHDL port default as an SV
   input default (the Z80's `NMI_n`, which `system.sv` leaves out).
3. **Verilator** over `system.sv` and its Verilog parts, `bram.sv` (the
   `dpram`/`dpram_dif` `system.sv` holds itself, the save RAM's mixed widths
   included) and `main.cpp`. FX68K's structs are written `packed` in build's
   copy: Verilator takes no unpacked variable assigned both continuously and
   in a clocked block, as FX68K's `Nanod` is. `quirks.py` reads `core_top.sv`'s
   table of quirks by serial each build, so the sim sets the ones the core's table
   names; it does not run `core_top.sv`'s own block (`tools/quirk-test.sh` does).
4. **The run**, from `rtl/FX68K` (FX68K reads its microcode from where it runs).

## What the harness does and does not model

- The Core Settings at their defaults, as `core_top.sv` sets `system.sv`:
  6-button pads, the YM2612 (its DAC's ladder effect on), the high sprite limit off as `core_top.sv`
  starts it, a console's limit, which is what BlastEm and MAME draw (`SIM_HIGH_SPRITES=1` for on),
  hi-fi PCM, no turbo, no multitap. `PAL` as `core_top.sv`'s `want_pal`: `--region
  europe`, or a header for Europe alone, unless `--pal60`; and a game that holds 240 lines on at
  60 Hz started again at 50 Hz, as `core_top.sv`'s `pal_frame`. Only the VDP's and the version register's
  side of it: a frame is a frame here, so the clock's 1% doesn't appear.
- The ROM is served a word a request, the ack 4 MCLK clocks after it (about
  what `sdram.sv` takes at 107 MHz; `SIM_ROM_LATENCY` changes it). 1, 4, 6 and 7 run Sonic 3
  Complete alike, frame for frame, 8 slows it, 6 frames in 360 – the 68000 waits for the ROM
  past 7, which is where `sdram.sv` is slowest. `sdram.sv` itself and its refresh are not in
  the sim. Writes to the ROM's space (the SSF2 mapper's) land.
- The 68000's refresh wait is `system.sv`'s, as on the core: 2 of its clocks every
  896 MCLK, on its next access, wherever that is, as BlastEm charges it (`tools/refresh-test.sh`).
- The SVP's ROM port is served from the same ROM, as `sdram.sv`'s third channel: one
  access at a time, the 68000's first, one output for both. The ack's clocks are
  `SIM_ROM_LATENCY`'s, the Pocket's lying between 4 and 7 for this game.
- No save RAM loaded or written out yet, no lightgun, no cheats.
- Speed: 0.3 to 0.8 MHz of the 53.69 MHz clock on an Apple silicon MacBook, so a
  second to three a frame, depending on what else the Mac is doing.
  `--threads` made it ten times slower; most of the time is in GHDL's
  netlists of the Z80 and the VDP and in jt12, which all evaluate every clock.

One Verilator trap: an input port's default (`bram.sv`'s, the wrappers') is
run at time 0, and where Verilator has inlined the module, on the net the port
is wired to – it set `system.sv`'s `LOADING` to 0 before the first clock. So
`main.cpp` evaluates once before it sets the inputs.
