# Save states

The Pocket's Memories and its Sleep are save states, and this core has them.
The console is stopped at a clean point in vertical blank, both CPUs between
instructions, and read out to the Pocket; a loaded state goes on as the run
that saved it, frame for frame and clock for clock. Virtua Racing's SVP is
saved too. This is how: where the console is stopped, what each chip gives up
and takes back, the file, the Pocket's side, and how the simulation proves it.

The decisions in short:

- **A clean point in vertical blank.** Both CPUs between instructions, the
  VDP's FIFO empty and no DMA, inside a vertical blank after the Z80's
  interrupt pulse. Then only what a program can see needs saving, plus a
  handful of the VDP's flags, and the VDP's renderer holds nothing the next
  frame needs.
- **Each CPU is parked by its own wait mechanism.** The 68000 by the wait
  state FX68K already has (`wClk`), at an instruction boundary; the Z80 by its
  own bus request, where an instruction ends with nothing left over. Nothing
  is frozen mid-instruction.
- **The 68000 comes back through its reset.** Its registers are written while
  it is held in reset; on release, the reset's vector reads are answered with
  the state's stack pointer and PC, so it fetches its own prefetch and parks
  again at its first dispatch. No microcode state is saved or forced.
- **The VDP never stops.** The picture stays on the screen while a state is
  read out. Its counters are never written: a resume or a load waits for the
  raster to come round to the saved position and lets go there.
- **The YM2612 is read by a scan.** jt12 has no readback; in a scan mode its
  24-slot loops rotate without being updated, their taps read (or written)
  16 bits at a time as each operator comes round, and after 24 steps they
  are back as they were; all the rest of it is one chain of 603 bits, read
  and written a bit at a time.
- **Streamed, never buffered.** Every memory is read and written through a
  port that is idle at the clean point. No block RAM is added.
- **One file, 212,992 bytes**, at fixed offsets, the memories in the 68000's
  byte order. The cartridge's save RAM is in it. A game with the SVP (Virtua
  Racing) has a longer one, 278,528 bytes, the format's version 2 (The SVP).
- **The SVP is stopped by its clock enable, wherever it is.** Its memory
  machine finishes the access it is on and nothing then moves; all of what it
  goes on from is saved, so no point in its program is needed.

## The Pocket's side

As MIRLO64 does it (`github.com/tortugaveloz/MIRLO64`, its documentation's
"Save states"), with the bridge's commands in `core_bridge_cmd.v`:

| | value |
|---|---|
| `core.json` | `sleep_supported`: true. The Pocket offers neither Memories nor Sleep without it |
| `savestate_supported` | 1 |
| `savestate_addr` | `0x4000_0000` (the bridge's 0x1 is the cartridge, 0x6 the save, 0xF8 the commands) |
| `savestate_size` | `0x0003_4000` (212,992); `0x0004_4000` (278,528) with the SVP, and until a ROM has said which |
| `savestate_maxloadsize` | `0x0004_4000` |

All of it is `src/fpga/core/state_bridge.sv`, between the bridge and
`system.sv`'s window.

**Saving** (a Memory, or Sleep). The Pocket sends Savestate Start (0x00A0).
The core acknowledges it, reports busy while it seeks its clean point, and
reports ok once the console is stopped there; if no clean point comes within
2 seconds it reports an error and the game goes on. The Pocket then reads the
block through the bridge on the 0x4 window (The bridge's reads, below). When
the block's last word has been read, or 2 seconds after the last read (5
before the first), the game goes on from where it stopped (a Memory); for
Sleep the Pocket powers off first.

**Loading** (a Memory chosen, or the wake from Sleep). The Pocket starts the
core as for any launch – the ROM, then the `.sav` into the save RAM – and the
game boots. It then writes the file to the 0x4 window and sends Savestate Load
(0x00A4); the data arrives before the command. So the core acts on the first
word written:

1. The header is checked: the magic, the format's version, and the
   cartridge's serial, checksum and ROM size against the ROM loaded (captured
   from its header as it loads, beside the region bytes `core_top.sv` reads
   already).
2. If it matches, the console stops at once: the 68000, the Z80, the YM2612
   and the PSG are held in reset, the VDP is reset (its DMA and FIFO with it),
   the screen goes black (`load_blank`, in `core_top.sv`: without it the VDP
   draws the chips as they fill, a frame or two of noise) and the sound
   silent. Every word that follows goes straight into its chip.
3. Savestate Load: acknowledged, busy through the restore (The order of a
   load, below: at most three frames), then ok.

A header that does not match leaves the game running and the rest of the
stream ignored, and Savestate Load answers with an error.

The Pocket's reset is kept off the console from the header's match until the
load has let go and the Pocket's reset is off (`hold_reset`): a wake's file may
come before Reset Exit, and a reset would lose it. Which the Pocket does isn't
known; the simulation runs it both ways.

**The bridge's reads.** Not `data_unloader`, which `SS_CLOCKS` overruns:
`apf/io_bridge_peripheral.v` gives back what the read before fetched, 4 clocks
of `clk_74a` into each word, and a word can come every 88 clocks (1,180 ns; 75
by agg23's measure of the writes). `data_unloader` at 24 clocks a 16-bit word
is 28 clocks of `clk_sys` a word, 1,043 ns a pair before its FIFOs' latency.
So each read takes a pair fetched ahead and starts the next (48 clocks of
`clk_sys`, 894 ns) and the answer is on the bus before the next word. The
Pocket also reads an address again (agg23's NES core has "used for duplicate
reads"; the last read of one transfer is the first of the next): the same
address is answered from the pair it had, so no word of the YM2612's scan
moves twice. A read past the file's end does nothing. MIRLO64 measures some
11 s for 4 MB, so this file's read-out should take the order of 0.6 s.

**The .sav beside a Memory.** A Memory on the card is a `.sta` and a `.sav`:
the Pocket moves the save slot around a state too, order not known. So the
save RAM's port B is the state's only for the word it is on (`ss_bram`, not
`ss_mem`), and the `.sav` reads right between the state's words.

**The pause behind the menu.** `PAUSE_EN` stops the CPUs wherever they are,
so while it holds the clean point would never come. While a save looks for
it, the pause is lifted (the game runs, at most a frame, behind the menu);
after the read-out, the game goes back into the pause.

**What the Pocket makes of it**: a Memory's `.sta` is its header of 596
bytes, the state and a thumbnail; `System/user_sleepstate.sta` is the header
and the state. Virtua Racing's is 0x44000 of state in the same wrapping,
331,888 bytes against 266,352. The header names the state's size, and another
game's Memory is 0x34000 beside it, so the Pocket reads `savestate_size` once
the ROM is in, not once before it.

**The battery save.** The cartridge's RAM is part of a state, as on every
emulator: loading a Memory puts the game's battery save back to that moment
too, and the Pocket writes that back to the `.sav` on quitting. So a game save
made after a Memory is gone once that Memory is loaded, on purpose.

## The clean point

The window opens every frame when the Z80's interrupt pulse ends
(`VINT_T80`, 2,422 MCLK after the vertical interrupt) and closes at the start
of line 0x1FE: about 36 lines, 2.3 ms in NTSC 224-line mode, longer in PAL. A
save asked inside one starts there; otherwise it waits for the next. By then
the VDP's sprite passes are done until line 0x1FF prepares line 0; nothing in
its line buffers is used again.

Within the window:

1. **The 68000 is parked** at its next instruction boundary and waits there
   until its bus is idle (below), unless the game holds the Z80's bus with
   the Z80 stopped mid-instruction: then it goes on until it lets go.
2. **The Z80 is parked** at its next instruction end, or found already
   stopped at one, or in reset (below).
3. **The rest is waited for**: the VDP's FIFO empty, no DMA running or
   pending (`DMAC` idle, no fill waiting for its data word), no data-port
   read in progress, its bus request released; `system.sv`'s 68000 bus and
   Z80 bus machines idle (`mstate`, `zstate`), the Z80 not holding the
   68000's bus (`Z80_BR_N`, `Z80_BGACK_N` released).
4. **The freeze**: at the YM2612's mid-sample slot boundary (at most 1,008
   MCLK; The YM2612), the clock enables of the 68000, the Z80, the YM2612 and
   the PSG stop together, and their dividers hold. The VDP runs on.

If the 68000 has been parked for 64 µs and the rest has not come, it is let go
for one instruction and parked at the next boundary. If the window closes
first, the CPUs are let go and the next frame tries again; after 120 frames
(2 s), an error. In the simulation the point comes in 0.06 to 0.08 ms.

**What the freeze records**, beside the chips' state: the VDP's position at
that clock (`FIELD`, `HV_VCNT`, `HV_HCNT`, `HV_PIXDIV`). The dividers
(`VCLKCNT`, `ZCLKCNT`, `FCLKCNT`, `PCLKCNT`) hold while frozen, so they keep
their phase; a frame (896,040 MCLK in NTSC) is not a whole number of 68000
clocks, so the file has them, for a load.

**Letting go** – after a save's read-out, and at the end of a load alike – is
done at the clock when the VDP is back at the recorded position and field,
two frames or more later: the VDP's drifting flags are put back (below), and
the clock enables, both parks and the YM2612's scan mode released in the same
clock. A Memory therefore costs the game nothing but the wait: it goes
on from the same raster position, as if the console had paused there.

**What it changes.** Parking one CPU while the other reaches its boundary
delays the first by a few microseconds (at most a Z80 instruction, 23 Z80
clocks; or a DMA's end), as a bus wait would. A run that saved and went on is
therefore not quite the run that never saved. What the state must reproduce
exactly is the run that saved and went on (The proofs, below).

**When the Z80's bus is held.** A game often holds the Z80's bus in its
vertical interrupt to talk to its sound driver. The Z80 then stopped at the
end of a machine cycle, which is the end of its instruction only sometimes.
If it is mid-instruction, the point is not taken and the 68000 goes on, until
it lets the bus go. A Z80 the game holds at an instruction's end is taken as
it is. (A game that holds the bus mid-instruction for good, one that never
uses the Z80 but leaves its bus taken, finds no point: letting the Z80 finish
its instruction under the request would cover it, and is not built; none of
the games tried needs it.)

### The 68000 (FX68K)

**Where it parks.** FX68K's microcode overlaps: the microword latched at a
T3 does its T4, then its T1, T2 and T3 in the next microcycle, where the next
microword is latched. So the dispatch microword (`microLatch[1]` 0,
`microLatch[3:2]` 1: the `a1` branch, or the group 1 exception it finds) has
not finished the instruction when it is latched: its own T1 to T3 (a last
register write, the prefetch's start, `au2Pc`) are still to come. The park is
one microword later: `ssStart` is set at a dispatch's T1 and marks the
microword latched after it as an instruction's first (or an exception's); with
`ssPark` high, a term in `wClk` stops the sequencer after that microword's
T4, before its T1 (`ssAtStart`). The instruction before is then complete,
and the next has done nothing but latch its first microword and its T4.
The 68000 is parked when, besides, its bus is idle (`ssBusIdle`: `busPhase`
idle, no `bcPend`, `ASn` high).

**Its bus waits too.** `busControl` starts a bus cycle at any phi1 where the
latched microword's `permStart` is set and the bus is free, not only at its
T1, as nothing else ever holds the sequencer before a T1 with the bus free.
Parked, the latched microword's bus cycle would start on its own, again and
again (a read repeated, or a write). So while `wClk`'s park term holds,
`canStart` takes no `permStart` (`ssHold`); its cycle starts at the phi1 that
is its T1, as it does unparked.

**STOP** waits by dispatching itself again and again: its first microword
(0x3A2 in MiSTer's microcode) and 0x327 in turn, so a park at a boundary takes
it there too, with no term of its own. Its PC there is 6 past its opcode, not
2 (the microaddress is in the file, and tells a load).

**Saved** (128 bytes at 0x0080): D0–D7, A0–A6, USP, SSP through a port on the
register file (`ssRegA`, `ssRegQ`); the PC (`PcH`/`PcL`); the SR (`psw`);
`ssMisc`: the group 1 and group 0 exception latches as they are at the park
(`rTrace`, `rInterrupt`, `rIllegal`, `rPriv`, `rLineA`, `rLineF`, `rExcRst`,
`rExcBusErr`, `rExcAdrErr`, `rSpurious`, `rAutovec`), `inl`, `intPend`,
`prevNmi`; `ssGrpDisp`: the same latches as they were at the dispatch before
(a copy taken at every dispatch's T1, 11 flip-flops: what decided the entry);
`ssClk`: `Tpend`, `rVma`, `tState` (T4 or T0, the half of the wait it froze
in), `eCntr` (the E clock's count); and the microaddress parked at.

**Putting it back.** A load holds the 68000 in `extReset` (not `pwrUp`,
which clears the register file) and, before anything is written, runs its
clock enables alone for 56 clocks, the rest frozen, as a real reset runs the
clock: FX68K clears its bus cycle's latches (`wendReg`, `bcPend`) only on a
phi2 in reset, and the nanocode controls it latched for the microword the
reset cut short write a register on the first T3 (without this, Gunstar
Heroes' A6 reads back 0). Then its registers go in through the port. At the
end the reset is let go. Its microcode reads the vectors: `system.sv` answers
those four reads, and only those, with the state's SSP and its PC less 2 (less
6 in STOP); the reset's own prefetch moves the PC on by 2, as at any boundary.
It is parked at the reset's last microword, the dispatch (`ssParkDisp`), and
frozen; there the exception latches are set to `ssGrpDisp` and the SR to the
state's (the reset set S and I = 7). Let go to the boundary, it takes the same
entry as the saved one did and parks there (in STOP, round its loop until the
PC is the saved one). Frozen again, the SR, the latches as at the park,
`inl`, `intPend`, `prevNmi`, `Tpend`, `tState`, `eCntr` and `rVma` are
loaded, and the dividers set: the CPU is then the saved one in everything that
is read again (the prefetch is fetched again rather than saved; the
microcode's temporaries are written before they are read, as the restore's
runs show).

**Changes to `fx68k.sv`**: the ports above, the park term in `wClk` and the
dispatch copy, the register file's port, the loads (into `tState`, the PSW,
`eCntr`/`E`/`rVma`, `inl`, `intPend`/`prevNmi`, the sequencer's latches),
`busControl`'s idle and `ssHold`; `tState`'s enumeration given a name
(`tstate_t`) so it can be loaded; `fx68kAlu.sv`: the CCR's load.

### The Z80 (T80)

**Where it parks.** The T80 finishes an instruction's last register write in
the next M1's first T-state (`Read_To_Reg_r`, `Save_ALU_r`: the real Z80's
fetch and execute overlap), so the end of an instruction is clean only where
nothing is left for that T-state. A new input `SS_Park` stops the T80 as a bus
request does (`BusAck` at `T_Res`), but only where the new output `InstEnd`
says the machine cycle ending ends an instruction with nothing left: the
instruction's last cycle (`MCycle = MCycles`, `No_BTR`, DJNZ's exit; not an
XY fetch), no prefix in effect or being taken (`ISet`, `XY_State`,
`Prefix` 0), no register write-back, ALU result or block-instruction flags due
(`Read_To_Reg`, `Read_To_Acc`, `Save_ALU`, `I_BT`, `I_BC`, `I_BTR` 0), and not
HALT itself (a halted Z80 parks at the end of one of its NOP cycles). It holds
while `SS_Park` is high, and lets go on the first clock enable after. Most
instructions qualify (loads to memory, jumps, calls, returns, OUT, NOP, EI,
DI, EXX, HALT's cycles); ALU instructions and loads into registers do not, and
the next end that does comes within a few instructions.

**Saved** (64 bytes at 0x0100): `REG`, 212 bits, and `REGX`, what `DIR`
leaves out: `WZ` (MEMPTR, seen in BIT n,(HL)'s flags), `Halt_FF`,
`BusAck`, `BusReq_s`.

**Putting it back.** The Z80 is held in reset through the load; then, frozen,
its reset is let go with `DIRSet` in the same clock: the registers from
`DIR`, and `WZ`, `Halt_FF`, `BusAck` and `BusReq_s` from `DIRX`. A Z80 so
restored (M1, T-state 0, `BusAck` set) and the parked one (the last cycle's
`T_Res`, `BusAck` set) both begin their next M1's T1 at the first clock enable
after letting go, and the interrupt check the parked one makes there finds
the INT line high (the pulse is over). A halted Z80 comes back halted. If the
game held the Z80's bus at the point, `BusReq_s` holds the restored one as it
held the saved one, until the game lets go.

**What the game sees.** `CTRL_F` reads `BUSAK` as granted while a save's
park holds the Z80 only if the game asked for the bus.

**Changes to `T80.vhd`**: `SS_Park`, `InstEnd`, `REGX`, `DIRX`; the bus
request's hold and grant take `SS_Park` at an `InstEnd`. **`T80s.vhd`**: `REG`,
`DIRSet`, `DIR` (T80's own, which `T80s` did not bring out before) and the four
new ports, through. GHDL translates them as plain vectors; `sim/genesis/wrap.py`
picks the new ports up from the translation.

### The VDP (vdp.vhd)

At the clean point the VDP's CPU side is idle (`SS_IDLE`: the FIFO empty, the
transfer and DMA machines idle, no DMA set up or fill waiting, no data-port
read, the 68000's bus not taken, no VRAM access in flight) and its renderer is
in vertical blank. It is not stopped: it goes on showing the frozen picture.

**The state port** (`SS_EN`, `SS_ADDR`, `SS_DI`, `SS_DO`, `SS_WE`; a word
port, `SS_DO` three clocks after its address), in the file at 0x0140 a word
each: 000–017 `REG` 0–23 (the low byte), 018 `ADDR` 15:0, 019 `ADDR`'s bit
16 (bit 8), `PENDING` (bit 7) and `CODE`, 01A `DBG`, 01B–01E `FIFO_DATA`
0–3, 01F `FIFO_RD_POS` and `FIFO_WR_POS` (empty, the FIFO's last words still
show in the unused bits of CRAM, VSRAM and 8-bit VRAM reads), 020 the
snapshot's `HV`, 021 its flags. The port writes in the CPU process (the
owner of those registers); the memories through it: CRAM (64 words, as the
68000 writes them) and VSRAM (40 words) by port A's address, data and write
enable, in the file at 0x0A00 and 0x0A80; the sprite cache (80 entries, Y then
size and link) by its write port and, for reading, its one read port, at
0x0B00.

**The snapshot**, taken at the freeze (`SS_SNAP`) and written back at the
letting go (`SS_REST`), a save's and a load's alike: the three interrupt
pendings, the three interrupt outputs (`VINT_TG68_FF`, `HINT_FF`, `EXINT_FF`:
the IPL lines read them a clock later), `SOVR`, `SCOL` and the HV latch.
They change while the CPUs are frozen and the VDP runs on.

**Not saved**: the counters (waited for); `FIELD`, which turns every frame, not
only in interlace, so the letting go waits for it too (two frames or more
after the freeze); `HINT_COUNT`, reloaded from register 10 on every line of
vertical blank; `OBJ_DOT_OVERFLOW` and the line buffers, made again by the
frozen frame from the same VRAM; the window and VSRAM latches; the VRAM
access toggles, which pair up after a reset as before.

**The sprite cache's read port** is the sprite engines' too, busy from line
0x1FE to the end of the active lines (`SS_SPR`). A read through it then takes
the port from them for a clock: the letting go waits until a whole frame's
sprite work after the last such read has been their own. A read-out in the
vertical blank after the freeze (the simulation's) never meets it.

**Changes to `vdp.vhd`**: the ports above, the port's branch at the end of the
CPU process and of the sprite-cache writer, its read process, the snapshot's
write-backs in the interrupt and flag processes and the counter process
(`HV`), the cache's read address mux. All plain `std_logic_vector`s; nothing
of the state machines' types out but `SS_IDLE`.

### The YM2612 (jt12)

Proved first on jt12 alone: `src/fpga/core/rtl/jt12`, the bench `sim/jt12`,
`tools/jt12-scan-test.sh`.

jt12 has no way to read anything back (`dout` is busy and the two timer
flags), and its state is spread through about 3,350 flip-flops, some 2,500
of them in shift registers that carry the 24 operators round, one slot every
42 MCLK, a sample every 24 slots (1,008 MCLK). Replaying its registers alone
drops held notes, so this core scans it.

**The freeze** comes at a slot boundary halfway through the sample: three
MCLK after the clock enable that moves the slot counter to slot 12 (op 2,
ch 0), the prescaler quiet again (its clock enable and the register before
it 0, the next FM clock enable not yet come), and no write being made. The
FM clock enable is then held low (PAUSE_EN's path) for as long as the save or
load takes; nothing else in jt12 moves while the bus is quiet.

**The ports** (`jt12_top.v`, through `jt12.v`): `ss_scan` (scan mode),
`ss_step`, `ss_lane`, `ss_load`, `ss_wd`, `ss_tap`; `ss_gsh`, `ss_gi`,
`ss_go`. In scan mode the chip's clock enable is `ss_step` alone and
everything that runs on the plain clock holds (the PCM interpolator and its
divider, the timers' flags and load edge, the busy counter).

**The loops** turn. A step in scan mode is a slot with nothing updated: each
loop's input takes its own output, so it is a plain rotation, and 24 steps
bring every loop back; the slot counter moves on with them and comes back
too. The loops and their taps, 180 bits:

| loop | stages | bits | tap |
|---|---|---|---|
| the operator registers, `jt12_csr` ×2 | 24 | 44 | `u_csr1`'s out, written into `u_csr0` (`u_csr1` passes) |
| the channel registers `u_regch` | 6 | 25 | its out |
| RL `u_regch_rl` | 6 | 2 | its out |
| key-on, `u_konch0` to `3` | 24 | 1 | `u_konch3`'s out (the others pass) |
| phase `u_phsh` | 24 | 20 | its out |
| the phase's pad `u_pad` | 6 | 10 | its out |
| attenuation `u_egsh` and `eg_in_II` to `_IV` | 24 | 10 | `eg_in_III`, written into `eg_in_IV` (`_II`, `_III` pass) |
| SSG inversion `u_ssg_inv` and `ssg_inv_II` to `_IV` | 24 | 1 | `ssg_inv_in_I`, written into `ssg_inv_II` |
| envelope state `u_egstate`, previous key-on `u_konsh`, counter bit `u_cntsh` | 24 | 3+1+1 | their outs |
| the envelope's pad `u_egpad` | 4 | 10 | its out |
| feedback memories `prev1`, `prevprev1`, `prev2` | 6 | 3×14 | their outs |
| phase modulation's delay `phasemod_sh` | 6 | 10 | its out |

The taps are put together as 12 lanes of 16 bits; `ss_lane` picks the lane
`ss_tap` shows and `ss_load` writes from `ss_wd`. A save reads lane by lane,
24 steps each (12 × 24 = 288 steps, the loops back where they were after
each lane); a load writes the same way. A loop of 6 or 4 stages goes round
4 or 6 times in a lane's 24 steps, so its words repeat and only the last
turn's count on a load. Only the loops' inputs are muxed, so the ones
Quartus puts in RAM blocks (`altshift_taps`: the key-on, the channel ring,
the phase's pad, the phase modulation's delay) stay there.

**Everything else holds and is on one chain**, 603 bits, read and written a
bit at a time: each `ss_gsh` moves it on, in at `ss_gi`, out at `ss_go`
(a save feeds `ss_go` back to `ss_gi`, so after 603 moves it is as it was).
It runs through the prescaler's counters (15 bits), the registers' block
(the address latch and part, the pending write `up_*` and `din_copy`, the
timers' values, bits and loads, the LFO's, CH3 special mode's frequencies,
the DAC, `busy` and its counter: 131), the slot counter with `fb_II` and
`ch6op` (10), the key-on's latches (15), the timers' counters and flags
(26), the LFO's counter and value (14), the phase's stage II (28), the
envelope's stages II to V (27) and its counter (17), the operator's stage I
and stages VIII to XIII (81), the six accumulators in use (6 × 23) and the
PCM interpolator with its divider (101). The accumulators' `left` and
`right` are not on it: they follow from `snd` and `rl_old` at every step, so
they run in scan mode and come right on the first step after a load.

**The operator's two tables** (`jt12_logsin`, `jt12_exprom`) are RAM blocks,
their registers out of the chain's reach. Each keeps a copy of the address
it last took (8 bits each, on the chain); at every step of the chain it is
read again at the address the copy takes, so after a load each holds what
its copy says. Stage VIII can't be rebuilt while the loops turn, from the
pads' delays: a delay line holds what it will give next, not what it gave
before the freeze. So it is on the chain.

**The order**: a save reads the chain and then the loops; a load writes the
chain first, then the loops (the accumulators' outputs need the chain's
values by the last step). About 900 MCLK each, 17 µs.

**In the file** (The format): 0x0300, 256 bytes: the chain, its first bit
out the top bit of the first byte (76 bytes used). 0x0400, 1,536 bytes: the
loops, lane by lane, each lane's 24 words in step order (576 bytes used).

**The proof** (`tools/jt12-scan-test.sh`, `sim/jt12`): three copies of jt12
on one clock. A and B take a log's writes; C random ones, so it is nothing
like them. At each save point the three are frozen together; A is scanned
out and what comes out goes into C as it goes; C is read back at once and
must give the same, bit for bit; B is only frozen, as long. Then all three
take the log's writes again and must give the same sound (`snd_left`,
`snd_right`), sample flag, busy and timer flags and interrupt on every clock;
at the end of the window the three are frozen and read out again and their
states must be the same. The logs: a driver written for the test
(`tools/jt12-writes.py`: the eight algorithms with feedback, the LFO with AMS
and PMS, SSG-EG's shapes, CH3 special mode, CSM mode and the timers, the DAC
with HiFi PCM's interpolation, then all of it at once), the test ROM's note,
and games' writes taken through the whole console (`tools/sim.sh`'s
`--fm-log`). `--spoil` puts one bit wrong into C to see the check fail.

**Area** (`tools/jt12-alms.sh`: jt12 alone, fitted with the core's
settings): 945 ALMs without the scan, 1,292 with it, 347 added; no RAM block;
the worst setup slack at 53.69 MHz +3.853 ns (+4.819 without).

**Changes**: `jt12.v`, `jt12_top.v`, `jt12_mmr.v`, `jt12_div.v`,
`jt12_reg.v`, `jt12_csr.v`, `jt12_kon.v`, `jt12_pg.v`, `jt12_eg.v`,
`jt12_eg_cnt.v`, `jt12_op.v`, `jt12_acc.v`, `jt12_single_acc.v`,
`jt12_timers.v`, `jt12_lfo.v`, `jt12_pcm_interpol.v` and
`adpcm/jt10_adpcm_div.v`. jt12 here is MiSTer's own variant (seven
accumulators, a deferred key-on), the same files as MiSTer's before these
changes. The scan is the YM2612's only (`use_pcm` 1, `use_adpcm` 0); the
YM2203 and YM2610 parts of jt12 pass the chain by, and their own accumulators
(`jt03_acc`, `jt10_acc`) and the ADPCM-B interpolator, which jt12 here never
builds, leave the new ports of `jt12_single_acc` and `jt10_adpcm_div`
unconnected.

**In the console.** jt12 gives `ss_slot` (`cur_op`, `cur_ch`) and `ss_cen`
(its clock enable) for the freeze: the save logic sees the clock enable at
slot 12 and freezes three clocks later, as the bench does. It stays in scan
mode from four clocks after the freeze to the letting go, a save's and a
load's, so nothing in it runs while frozen, its plain-clock parts included. A
load does not reset it: the chain and the loops are all of it, and its reset
(the Z80's, the game's) is ignored from the load's start to the letting go.
The console's stream moves the chain 16 bits a word with clocks between the
words. jt12_lfo cleared its counter on any clock with the LFO off
(`rst || !lfo_en`), which would clear the chain's bits that sit in it between
two words, so that clear is not made in scan mode; the bench takes `--gaps N`
(N idle clocks after every 16 moves and every step) and `--twice 1` (copy A
read twice at once) to cover it.

### The PSG (jt89)

156 bits, read and written as ten words (0x0240) through a port on `jt89.v`
(`ss_idx`, `ss_q`, `ss_we`, `ss_wd`; a word written goes into the whole
vector as it is): the tone periods, the volumes, the noise control, the
latched register, the divider and its two enables, the write edge, and each
tone's counter, output and volume stage, the noise's shift register, counter
and volume stage. `jt89_tone.v`, `jt89_noise.v`, `jt89_vol.v` take their parts.
The mixer's sum is made again every clock.

### The rest of the console (system.sv)

At 0x0040, a word each: 00–03 `BANK_REG` 0–7 (two a word), 04 `BANK_ROM`,
`BANK_SRAM`, the game's `Z80_BUSRQ_N` and `Z80_RESET_N`, 05 `BAR`, 06
`M68K_IPL_N` with `old_as` and `scnt`, 07 the open bus (`NO_DATA`, the last
word the 68000 read: some reads' unused bits; set at a load's end, after the
68000's own prefetch), 08–09 the position at the freeze (field, line, dot,
pixel divider), 0A the dividers' counts (`VCLKCNT`, `ZCLKCNT`, `FCLKCNT`,
`PCLKCNT`), 0B `VCLKMAX` and `VCLKMID`. The dividers hold while the console is
frozen, so they come back where they were by themselves after a save; a load
sets them.

The 68000's refresh wait, at 0x0060: `refresh_timer` and `rfs_pend`, in one
word, in space the format otherwise leaves zero, so its version doesn't
change and a state without it loads with the timer at 0 and nothing pending,
at most 2 clocks of the 68000's difference. The timer holds in `ss_freeze`, as
the dividers do, and nothing takes the flag while frozen, as a load's 68000
fetches through the same state of the bus machine. So it is written straight
in, with no staging. Its count, `rfs_cnt`, needs no place: it only runs in
`MBUS_FINISH`, and `ss_okB` has `mstate` idle at the clean point. `ss_ok68`
is unchanged, as a wait is only a late DTACK. It matters: Sonic 3 Complete's
state of frame 300 with this word wiped loads and plays with every picture
the same, and the sound differs in 25 of 153 frames from the third. States
whose word is 0 load all the same (two games' Memories, in the simulation).

The pads, at 0x0280: `gen_io`'s 16 registers (eight words) and each of the
two pads' TH, 6-button counter `JCNT`, its timeout `JTMR`, the float timer
`FLTMR`, `THd` and the latched `di` (two words each), through a port on
`gen_io.sv` and `pad_io` (through `multitap.sv`; `fourway.v`'s and the J-Cart's
pads tie it off: 4-Way Play and the J-Cart are not saved).

A serial save chip (`EEPROM_24CXX.sv`), at 0x0058: a game bit-bangs it for
frames on end, so the clean point can land in the middle of a byte, and the
chip's state goes in the file. It is in four words the format otherwise
leaves zero, so its version doesn't change: a state without them has the chip
idle with its lines low, which the game's next write puts right. The lines
come first in the file: writing them can look to the chip like an edge, and
its own words, written after, put that right. The contents come last, in the
save RAM, over anything that edge wrote.

Not saved: the light guns' and the mouse's state, the cheats, Pier Solar's
EEPROM machine (its contents are in the save RAM), the audio filters after
the chips (`genesis_lpf`, `genesis_fm_lpf`, `jt12_genmix`: the console's output
stage; the proofs compare the chips' own sound before them).

### The SVP (Virtua Racing)

Its own clock enable, `SVP_CLKEN`, is held by `ss_freeze`, as the CPUs'
dividers are; `PAUSE_EN` doesn't stop it, and needn't. No boundary in its
program is needed (such as the idle loop at 0x425 or the wait at 0x2789), nor
a job finished: the SSP moves only on `EN`, a job half done is only registers
and RAM, and all of them are saved. What can't be stopped dead is the memory
machine (`MAS`), which runs on every clock and has the SDRAM's answer to wait
for. It needs no clock enable: with `EN` low it finishes the access it is on
and its next fetch, and `SS_QUIET` comes up (`MAS_IDLE`, `SSP_ACTIVE` and
`PMAR_ACTIVE` low, no 68000 access, the ROM's request answered). The state is
reported ok only then. The SSP may be stopped between the two words of an
instruction, so `IMM16_EXT_CYCLE`, `IND_EXT_CYCLE`, `IR_SAVED` and `IND_ADDR`
are saved.

**A chain, as the YM2612's.** About 1,000 flip-flops in a word-wide chain cost
a 2:1 mux each and nothing to read: no 63-way read mux, no address decode. A
word is read off the head and fed back to the tail, so a read rotates it. It
reads and writes in order only, `svp_pos` checks that (out of order is an
error) and `SS_UNSCAN` brings it round if the reads stop early, all as the
YM2612's is. Every word goes through every place, so all are 16 bits: the odd
bits share a word, filled by four flip-flops of `SS_PAD`.

Not saved, because at quiet they are what the next access sets before using
them: `MAS`, `MEM_WAIT`, `SSP_ACTIVE`, `PMAR_ACTIVE` (quiet, always the same),
`MEM_ADDR`, `ROM_ADDR`, `DRAM_ADDR`, `DRAM_GEN_*`, `BUS_DO`, `DTACK_N`;
`MA_ROM_REQ` (a toggle matched to the SDRAM's own ack, which is this
power-on's). `P` is `X * Y` by wire, `SP` the stack by wire.

**The memories.** The two 256-word RAMs (MLABs) and the IRAM (one M10K port,
shared with its fetch) are the save logic's through their address and data
muxes once quiet (`SS_EN`), the 128 KB DRAM through the save RAM's port B,
which is its port anyway. The IRAM's output is the instruction when the SSP
runs from it: its address goes back to the fetch when `ss_mem` falls, well
before the let go.

**A load** resets the SVP with `system.sv`'s bus machines (`ss_sysrst`): a
68000 access to the DRAM cut off by the stop would otherwise leave
`DRAM_GEN_REQ` up for good. It fetches from its reset PC and goes quiet, and
the file is written over that (`SS_LSTOP` waits for it). With the SVP the
`.sav`'s writes don't reach port B (they would go to wherever the DRAM's
address was): the Pocket moves a Memory's `.sav` around the state, in an
order not known.

## The format

212,992 bytes (0x34000), version 1, every byte at a fixed offset; unused
bytes are 0. With the SVP, version 2, 278,528 bytes (0x44000): the same, with
its registers and small RAMs in space version 1 leaves 0, and its 128 KB DRAM
in the save RAM's place, running on past where that ends. Other games' files
are version 1. Words are big-endian, the memories bytes in the 68000's order
(as MAME's and BlastEm's memory views show them), so a state can be read and
compared by a script.

| offset | size | what |
|---|---|---|
| 0x00000 | 64 | the header |
| 0x00040 | 64 | the console: mapper, Z80 control, IPL, the freeze's position and dividers |
| 0x00080 | 128 | the 68000 |
| 0x00100 | 64 | the Z80 |
| 0x00140 | 256 | the VDP's registers and port state, and the snapshot |
| 0x00240 | 64 | the PSG |
| 0x00280 | 64 | the controllers |
| 0x00300 | 256 | the YM2612's chain: 603 bits, its first bit out the top bit of the first byte |
| 0x00400 | 1,536 | the YM2612's loops: 12 lanes of 24 words (576 bytes) |
| 0x00A00 | 128 | CRAM: 64 words as the 68000 writes them (`0000 BBB0 GGG0 RRR0`) |
| 0x00A80 | 128 | VSRAM: 40 words (11 bits), then 0 |
| 0x00B00 | 320 | the sprite cache: 80 entries of 4 bytes (Y, size and link, as in VRAM) |
| 0x01000 | 126 | version 2: the SVP's chain, 63 words (below) |
| 0x01200 | 512 | version 2: the SSP's RAM A |
| 0x01400 | 512 | version 2: the SSP's RAM B |
| 0x01800 | 2 KB | version 2: the SVP's IRAM |
| 0x02000 | 8 KB | Z80 RAM |
| 0x04000 | 64 KB | 68000 RAM (0xFF0000–0xFFFFFF) |
| 0x14000 | 64 KB | VRAM |
| 0x24000 | 64 KB | the cartridge's save RAM, its bytes in order (the RAM's own layout, not the `.sav`'s) |
| 0x24000 | 128 KB | version 2, in its place: the SVP's DRAM, each word low byte first (port B's words, through the save RAM's byte swap) |

**The header**:

| offset | size | what |
|---|---|---|
| 0x00 | 4 | `GPSS` |
| 0x04 | 2 | the format's version: 1, or 2 with the SVP |
| 0x06 | 2 | flags: PAL, the region in effect, `SVP_QUIRK` and the other quirk bits |
| 0x08 | 4 | the size, 0x34000, or 0x44000 with the SVP |
| 0x0C | 4 | the ROM's size in bytes |
| 0x10 | 16 | the cartridge header's 0x180–0x18F: the serial and its checksum |
| 0x20 | 4 | the core's version when the format was made, a byte each for major, minor and patch, then 0: `00 06 00 00`, the same in every state |
| 0x24 | 4 | the frame number since power-on (for the simulation's comparisons) |

A load refuses another version or another ROM (size, serial, checksum); a
state from another core version of the same format is taken. A state made at
the other of PAL and NTSC is taken too, and runs on its own timing: once the
file is in, `state_bridge.sv` asks `core_top.sv` for the file's clock
(`pal_take`, `pal_file`), and with the console still stopped and kept out of
reset (`hold_reset`) `pal_clock.sv` writes the PLL's K; the load lets go only
when the timing is the file's and the clock's hold has been down 64 clocks.
The game stays on that clock until it starts afresh: Reset Core or a new game
goes back to what the Region and PAL 60 Hz settings say, and 240 lines at
60 Hz still restart it at 50. What a game reads (`PAL_SAYS`, `EXPORT`) isn't
saved and stays as this start's settings make it.

The flags, from bit 0: PAL, the region (`EXPORT`), `SVP_QUIRK`, a serial save
chip on Acclaim's 32M board, `SRAM00_QUIRK`, any other serial save chip,
`NORAM_QUIRK`, `PIER_QUIRK`, `FMBUSY_QUIRK`, `SCHAN_QUIRK`, `FAST_FIFO`.

**The small blocks**, as built (`tools/state-dump.py` prints a state field by
field, or what differs between two):

| offset | what |
|---|---|
| 0x0040–0x0057 | the console (The rest of the console) |
| 0x0058–0x005F | a serial save chip, four words: Acclaim's read map, SCL and SDA; then `EEPROM_24CXX.sv`'s own (the last lines, its state, the bit, read or write, the block; the address; the byte coming in). Its contents are in the save RAM |
| 0x0060 | the refresh wait: `rfs_pend` (bit 10), `refresh_timer` (bits 9–0) |
| 0x0080–0x00C3 | D0–D7, A0–A6, USP, SSP, 4 bytes each |
| 0x00C4 | the PC (4); 0x00C8 the SR; 0x00CA the exception latches at the park (11 bits, `rTrace` first), `inl`, `intPend`, `prevNmi`; 0x00CC the latches at the dispatch before; 0x00CE `Tpend` (bit 8), `rVma`, `tState`, `eCntr`; 0x00D0 STOP (bit 0); 0x00D2 the microaddress parked at (to read; not loaded) |
| 0x0100–0x011B | the Z80's `REG`, 212 bits, from its top (IFF2, IFF1, IM ... A) in 14 words, the first holding 4 |
| 0x011C | `WZ`; 0x011E `BusReq_s`, `BusAck`, `Halt_FF` (bits 2–0; bits 4–3 what the park saw, to read) |
| 0x0140–0x0183 | the VDP's port (The VDP) |
| 0x0240–0x0253 | the PSG's ten words |
| 0x0280–0x0297 | the pads' twelve words |
| 0x1000–0x1023 | the SSP: PC; A high, low; X; Y; a word of N, OV, Z, L, `IMM16_EXT_CYCLE`, `IND_EXT_CYCLE`, MACS, OP, IE, ST6, ST5, RB, RPL; the stack's six; r0–r7 in four words; `IR_SAVED`; `IND_ADDR` |
| 0x1024–0x102D | the SVP: a word of 4 unused bits, the stack's position, `HALT`, `CA`, `SA`, `PMC_SEL`, `PMAR_SET`, `PMAR_NUM`; `PMC` high, low; `XST`; `ROM_DATA` |
| 0x102E–0x107D | the PMARs 0–4 and 8–12, four words each: `MA` high, low, `DATA`, `CD` |

## The stream

**system.sv's state window**, which `state_bridge.sv` drives (the reads as
above; the writes from `data_loader`, paced at 24 clocks):

| port | what |
|---|---|
| `SS_SAVE` | a pulse: find the clean point and freeze (Savestate Start) |
| `SS_LOAD` | a pulse: a state for this ROM is coming (its header checked): stop the console |
| `SS_GO` | a pulse: the read-out is over (a save), or the last word is in (Savestate Load) |
| `SS_STATUS` | 0 idle, 1 busy, 2 ok (frozen and readable, or restored), 3 error |
| `SS_ADDR` | the word: its byte offset / 2, 18 bits |
| `SS_RD`, `SS_DO` | a read: `SS_DO` holds the word from `SS_CLOCKS` (24) clocks after |
| `SS_WR`, `SS_DI` | a write; the next no sooner than 24 clocks after |

The words go in the file's order, one at a time (the YM2612's chain and loops
check it: out of order is an error). The header's cartridge part (0x0C the
ROM's size is system.sv's; 0x10–0x1F the serial and checksum) is
`core_top.sv`'s, as is the check of a load's header; system.sv ignores a
load's header words.

Each word's source is decoded from its offset:

| memory | port used | that port's ordinary user | why it is free |
|---|---|---|---|
| 68000 RAM | B of `ram68k_u`/`_l` | the clearing at `LOADING` (write only) | only used while loading |
| Z80 RAM | B of `ramZ80` (two bytes a word) | none | unused |
| VRAM | A of `vram_l1` … `vram_u2` | the VDP's CPU side and DMA | idle at the clean point; reset on a load |
| save RAM | B of `sram` | the `.sav`'s load and unload (`BRAM_*`) | the Pocket does not move the `.sav` during a state |
| the SVP's DRAM | B of `sram` | the SVP | stopped |
| the SSP's RAMs, the IRAM | their one address, muxed | the SSP's own | stopped, and quiet |
| CRAM, VSRAM, sprite cache, registers | the VDP's state port | the VDP's CPU side | idle |
| the 68000's registers | its register file's port | – | parked, or in reset |
| YM2612 | its scan: the chain 16 moves a word (11 for the last), the loops a step a word | – | frozen, in scan mode |
| the SVP's registers | its chain: a move a word | – | stopped, and quiet |

**Staging**, the only state held outside the chips: the Z80's 212 + 19 bits
for `DIR` and `DIRX`; the 68000's PC, SR, latches and clock state, its SSP for
the vector (16 + 16 × 5 + 32); a register's high word; the open bus; the
dividers; the position. About 450 flip-flops, no RAM block.

## The order of a save

1. `SS_SAVE` (Savestate Start, synchronised to `clk_sys`): busy. The window
   (now or the next).
2. Park the 68000 and the Z80; wait for the rest; let the 68000 go an
   instruction after 64 µs; wait for the next frame if the window closes.
3. Freeze three clocks after the YM2612's clock enable at slot 12; record the
   position; the VDP's snapshot. Four clocks later the YM2612's scan mode.
   The SVP's clock enable is held with the rest; report ok once it is quiet too.
4. The words read out, in order.
5. `SS_GO` (after the last word, or 2 s without a read, 5 s before the first): the YM2612's chain
   and loops, and the SVP's chain, brought round to where they started; wait
   for the recorded position and field (two frames or more); the snapshot
   back, and the clock enables, both parks and the scan mode released in one
   clock. Idle.

## The order of a load

1. The header checked (`core_top.sv`): `SS_LOAD`. The 68000 and the Z80 held
   in reset, the bus machines and `system.sv`'s registers reset for 16 clocks,
   the VDP and the SVP reset; everything frozen, bar the 68000's clock run
   alone in its reset for 56 clocks; the YM2612 out of its reset (the game's
   is ignored now) in scan mode. Busy.
2. Each word as it comes, into its chip or its staging.
3. `SS_GO` (Savestate Load): the Z80's reset let go with `DIRSet` (frozen
   still). The 68000's reset let go (its clock was run in it at step 1), the
   vectors answered; parked at the dispatch and frozen: the latches
   as at the saved dispatch, the SR; let go to the boundary (round STOP's loop
   to the saved PC): frozen, the SR, the latches as at the park, `inl`,
   `intPend`, `prevNmi`, `Tpend`, `tState`, `eCntr`, `rVma`, the dividers, the
   open bus. Report ok (restored).
4. Wait a whole frame (the raster settles under the restored registers),
   then for the recorded position and field; let go as a save's step 5.
   Idle.

A save asked while a load waits to let go (step 4) reads the state as it was
written, without a clean point of its own: the proofs' twice over.

## The proofs (in the simulation)

Every part of this is shown in the simulation before it goes on the Pocket.
`sim/genesis/main.cpp` drives the state window as `core_top.sv` does
(`--state-save F FILE`, `--state-load FILE`, `--resave FILE`, `--save-delay`),
and `tools/state-test.sh` makes the two runs and compares them. With
`--pocket` both runs go through `state_bridge.sv` itself, on its two clocks,
with the bridge's reads and writes and the commands as the Pocket gives them.

- **The YM2612 alone**: the three-copy test (The YM2612 (jt12), The proof);
  again with the console's gaps and A read twice (`--gaps 8 --twice 1`): 42 of
  42 saves good on the seven logs.
- **A loaded run is the saving run going on**, from the clock each lets go:
  the picture's CRC every frame and a CRC of `FM_left`, `FM_right` and
  `PSG_SND` on every clock, for 605 frames: the same throughout for the test
  ROM saved at frame 60 (in its vertical interrupt's handler) and at frame 120
  (in STOP), and Sonic 3 Complete, Gunstar Heroes, Castle of Illusion and
  Shining Force each saved at frame 300 with no input. The four games again
  saved at frame 600, 305 frames compared: the same. Every point was found
  0.06 to 0.08 ms after the save was asked. The games ran with no input, their
  titles and attract modes; states made in play were tried on the Pocket.
- **Twice over**: a state loaded and, before it lets go, read straight back:
  the same file bar the header's frame number, in every run above. This is
  the check that caught the Z80 RAM read's second byte from the wrong
  address, the YM2612's LFO clearing chain bits, and Gunstar Heroes' A6
  cleared by the 68000's reset.
- **Against the run that never saved**: the saving run's frames before the
  save are those of the build without the save logic, frame for frame (the
  test ROM's 59, and the games' 299); after it they are the never-saved run's
  exactly, 4 frames later (the pause: read-out and the wait for the
  position): the test ROM's 604 frames, the games' 299 that their old runs
  reach. The park's few microseconds changed no picture. The sound was not
  compared there (the never-saved runs give no chips' CRC).
- **The test ROM** (`tools/testrom.py`) has what the games may not show: its
  main loop waits in STOP, its Z80 HALTs between interrupts, its FM note
  is held with feedback, its pad is read as a 6-button one, an H interrupt
  every 64 lines changes the backdrop. Saved at frame 60 the 68000 is in the
  vertical interrupt's handler and the Z80 just taken its interrupt (PC
  0x0038, IM 1); saved 0.75 ms into frame 120 the 68000 is in STOP.
- **Virtua Racing** (version 2; each read straight back the same, bar the
  frame number, and the loaded run the saving run going on, picture and
  sound). From power-on, no load anywhere: frame 40, `HALT` on (43 frames
  compared); frame 250, the logo's polygons, the SSP in a job from its IRAM at
  0x02A3, `HALT` off (63); frame 2050, in the race just after GO! with the
  clock running and cars passing (203). Through `state_bridge.sv`: frame 40
  (31), the same with the Pocket's reset still on as the file comes (31), and
  frame 270, in a job at 0x02AA (61). A race's countdown, the saving run itself
  started from a state (`--from`): frame 750 at 0x0010 (203), and through the
  bridge at 0x0167 (201). In the race the car never moved: `--hold` had the
  gas down before GO! and the game gave it a pit start, so driving was tried
  on the Pocket, where a Memory in a race loads back to its moment and the
  race drives on, and a wake from Sleep goes back to the race. A wrong serial
  (`SIM_POCKET_BADHDR=1`): an error from Savestate Load, the game going on.
  `tools/svp-trace.sh`: all 175,598 SSP instructions MAME's. Other games: the
  test ROM, direct and through the bridge, Sonic 3 Complete and Gunstar Heroes
  the same, their files version 1; the test ROM's file at 0x44000 bytes
  (`SIM_POCKET_LONG=1`) reads back and loads, its frames the same one later,
  the harness starting its log after the read's end.
- **A serial save chip**. Wily Wars, saved at frame 158 with the chip in
  `WRITE` at bit 4, address 0x1D, a byte half clocked in: read straight back
  the same, the loaded run the saving run going on (66 frames, picture and
  sound), the chip at the end the same in both and MAME's byte for byte.
  Through `state_bridge.sv` the same (64). That the chip's words matter: the
  same state with them wiped has two bytes wrong against MAME (0x1E and 0x1F)
  and one frame's picture different. At frames 150 and 152 with the chip
  reading, 165 writing and 172 in the address: the same. Games without a
  chip: Virtua Racing at frame 250 (63), the test ROM direct and through the
  bridge (126, 124), Sonic 3 Complete through the bridge (64).
- **Against Verilator's own** (`--savable`): not made. A model so saved at
  the clean point and restored is the saving run going on, clock for clock
  (the simulation is deterministic: the saving run before the save is the
  build before it, frame for frame), so it is the first proof's comparison
  over again.

## Another fork's save states

thefriendlyhedgehog's `savestates-wip` was read as a map of where to tap the
chips, not as code: its port lists on `fx68k.sv`, `T80s.vhd`, `vdp.vhd` and
jt12 point at the same places. Where this design differs: that one freezes
the 68000 wherever it is and saves part of its microcode state, so the
restore must force the micro-sequencer; this one waits for the dispatch and
lets the reset microcode build the rest. That one keeps shadow copies of CRAM
and VSRAM because the VDP's renderer owns one port; this one uses the
CPU-side port, idle at the clean point, and needs none. That one replays the
YM2612's registers; this one scans its operators. That one waits for DMA but
not for the FIFO, the raster, the interrupts; this one makes all of them part
of the point.

## MiSTer's files this changes

`fx68k.sv` and `fx68kAlu.sv`, `T80.vhd` and `T80s.vhd`, `vdp.vhd`, jt12 (the
files above), `jt89.v` and its parts, `gen_io.sv`, `multitap.sv`, `fourway.v`,
`system.sv`, `SVP.vhd`, `SSP160x.vhd`, each change with its reason in its
commit. The VHDL changes go through GHDL's translation for the simulation, so
they stay in what GHDL's synthesis takes: no new records, no exported
enumerations, no state in process variables.

## Appendix: where the state is

Where each chip's state lives in `src/fpga/core/rtl/`, as MiSTer's files have
it. Line numbers are those of the files before the save states went in.

**FX68K** (`FX68K/fx68k.sv`): `tState` and the enables `enT1`–`enT4`, `wClk`
(166–185, 455); `microLatch`/`nanoLatch` latched at T3 (247–270); the IR
forwarding (299–307); `intPend` and `inl` (406–450); `eCntr` and VMA
(458–478); the sequencer's dispatch (`case microLatch[3:2]`, 1 = `a1` or
`grp1Nma`, ~1970) and the group-1 latches (`grp1LatchEn`, `rInterrupt`,
2083–2150); `regs68L`/`regs68H`, `REG_USP` 15, `REG_SSP` 16, `REG_DT` 17
(1154–1180), `PcL`/`PcH` (1189); `busArbiter` (2164) and `busControl`
(2248: `busPhase` on `enPhi1`, `bcPend`, `SIDLE`).

**T80** (`T80/T80.vhd`): `REG` and `DIR` (121–124, 261), `DIRSet` into the
registers (407–417) and into `IntE_FF1`/`IntE_FF2` (1079–1081), `ClkEn <= CEN
and not BusAck` (358), the bus request and the machine-cycle transition
(1089–1160). `system.sv` instantiates `T80s` with `T2Write` 1 and `CEN` on
`Z80_CLKENn` (1197–1214); the bus request and reset registers (1218–1231).

**system.sv**: the clock dividers under `PAUSE_EN` (141–216); `M68K_IPL_N`
(235–252); VRAM, four `dpram #(14)` (346–396); the save RAM `sram` (644–658)
and the SVP's DRAM on its port B; 68000 RAM `ram68k_u`/`_l` (733–757); the bus
machine `mstate` with `BANK_REG` and `cycle_cnt` (778–1180); `ramZ80`
(1266–1273) and `zstate` (1275–1360); `BAR` (1367–1376); jt12 (1393), jt89
(484).

**vdp.vhd**: `REG` (164), `PENDING` (166), `CODE` (167), `DBG` (268), `ADDR`
(342), `DMAC` (301); the RAMs `cram` (824), `vsram0` (843), `vsram1` (861),
`obj_cache` (777; written by the SAT caching process at 1705); the 32-bit VRAM
arbiter (966–1040); `STATUS` (932); the counter process with `HV_PIXDIV`,
`HV_HCNT`, `HV_VCNT`, `FIELD`, `HINT_COUNT`, `VINT_T80_WAIT` (2302–2523; the
Z80 pulse at 2464–2469); the sprite passes' triggers under `PRE_V_ACTIVE`
(2528–2537); the CPU, transfer and DMA process (2864–3578; `FIFO_EMPTY`,
`FIFO_FULL` at 2861); the interrupt pendings and acknowledge (3585);
`SOVR`/`SCOL` (3676–3701). State in process variables, out of a state port's
reach: `hscroll_mask`/`vscroll_mask`, the pixel process's `x`, `V30prev`,
`VS_START_DELAY`, `VS_END_DELAY`, `VS_DELAY_ACTIVE` – none needed at the clean
point. The RAMs are `altsyncram` through `bram.vhd` (`DualPortRAM`,
`obj_cache`), which the simulation replaces with `sim/genesis/bram_sim.vhd`.

**jt12** (`jt12/`; `jt12.v` wraps `jt12_top` with `use_lfo` 1, `use_ssg` 0,
`use_pcm` 1, `use_adpcm` 0, `mask_div` 1, so the prescaler is fixed at /6):

| what | where |
|---|---|
| slot counter `cur_op`, `cur_ch` (0, 1, 2, 4, 5, 6), `zero` | `jt12_reg.v` 50–63, 213–218 |
| operator registers, two rings of 44 × 12 | `jt12_reg.v` 259, 282; layout `jt12_csr.v` 47, 68–80 |
| channel registers `u_regch` 25 × 6, `u_regch_rl` 2 × 6 | `jt12_reg.v` 346, 359 |
| phase `u_phsh` 20 × 24, `u_pad` 10 × 6, `keycode_II`, `detune_mod_II`, `phinc_II` | `jt12_pg.v` 96, 104, 66–70 |
| envelope `u_egsh` 10 × 21 and `eg_in_II`–`_IV`, `u_egstate` 3 × 24, `u_ssg_inv`, `u_konsh`, `u_cntsh`; pipeline 142–161 | `jt12_eg.v` 170, 83, 178, 186, 194, 163 |
| `u_egpad` 10 × 6 | `jt12_top.v` 548 |
| key-on rings `u_konch0`–`3`, `keyon_I`, CSM, the deferred key-on | `jt12_kon.v` 48–120 |
| `prev1`, `prevprev1`, `prev2` 14 × 6, `phasemod_sh` 10 × 6; stages II–XII | `jt12_op.v` 86–108, 173, 62–269 |
| registered ROMs `logsin`, `exp` | `jt12_logsin.v` 295, `jt12_exprom.v` 298 |
| accumulators, seven `jt12_acc` | `jt12_top.v` 638; `jt12_acc.v` 69–129, `jt12_single_acc.v` 43–59 |
| PCM interpolation | `jt12_pcm_interpol.v` 34–94 |
| address latch, timers' values and bits, CH3 frequencies, DAC, busy, the pending write | `jt12_mmr.v` 43–58, 144–199, 414 |
| timer counters | `jt12_timers.v` 104–128 |
| LFO `cnt`, `lfo_mod` | `jt12_lfo.v` 72–75 |
| envelope counter `eg_cnt`, `eg_cnt_base` | `jt12_eg_cnt.v` 27–30 |
| prescaler | `jt12_div.v` 37–91 |

Things that run on every clock, not only on `cen`, so a freeze must also
keep the bus quiet (it does: the CPUs are parked): the write path and
`busy`'s setting, the timers' flag clearing and reload edge, `dout`, the PCM
interpolator's edge detection and divider. `jt12_sh` rings without a reset
may be mapped into RAM by Quartus (`altshift_taps`); the scan only muxes their
inputs, which a RAM-based shift register keeps.

**jt89** (`jt89/`): `tone0`–`2`, `vol0`–`3`, `ctrl3`, `regn`, `clk_div`,
`cen_16`, `cen_4`, `clr_noise`, `last_wr` (`jt89.v` 48–87); each tone's `cnt`
and `out` (`jt89_tone.v` 32–35); the noise's `shift` and `cnt`
(`jt89_noise.v` 36–37); `jt89_vol.v`'s `snd`, `jt89_mixer.v`'s `fresh`.

**The SVP** (`SVP/`): `SVP.vhd` 55–100 (PMARs, `PMC`, `XST`, the memory
machine `MAS`), its IRAM `spram(10,16)` (515); `SSP160x.vhd` 43–74 (the
registers), `RAMA`/`RAMB` `mlab(8,16)` (697, 710); `SSP160x_PKG.vhd` 70–71
(the stack, `PREG`).
