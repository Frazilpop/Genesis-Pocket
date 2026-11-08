// The whole Genesis in Verilator: MiSTer's system.sv (FX68K, the Z80, the
// VDP, jt12, jt89, the SVP) with a game's ROM where the Pocket's SDRAM is.
// tools/sim.sh builds and runs it; see sim/genesis/README.md.
//
//   Vsystem <rom> [--frames N] [--out DIR] [--every K] [--save 100,200]
//           [--press F:buttons[:N] ...] [--region auto|usa|europe|japan] [--pal60]
//           [--fm-log FILE]
//
// The system is set as core_top.sv sets it with the Core Settings at their
// defaults: the region from the header (or --region), the quirks by the
// cartridge's serial from core_top.sv's own table (quirks.inc, made from it
// by sim/genesis/quirks.py), the pads 6-button, the FM chip the YM2612.
// The ROM is served as the SDRAM serves it, a word a request, the ack a few
// clocks after, one access at a time and the 68000's channel before the SVP's
// (the controller's own timing is not modelled: sdram.sv is not in the sim).
//
// Out, in DIR: f_NNNNN.png for each frame saved (the picture as core_top.sv
// gives it to the Pocket: its lines, its colours), frames.txt (every frame: its number,
// size and a hash of its pixels), audio.wav (the DAC's 16-bit stereo at
// 48 kHz) and run.json. A frame is counted as its last line ends; frame N is
// MAME's N - 1 from power-on, which tools/mame-frames.sh files as N.
//
// --fm-log FILE writes the YM2612's inputs as it sees them, for the jt12
// bench (sim/jt12, tools/jt12-scan-test.sh): a line for each change, the
// clock it takes effect on (counted from the first FM clock enable, a
// multiple of 7 from then), "W c addr data" for a write held from clock c,
// "E c" where it ends, "R c 1/0" the reset (the Z80's) going on and off.
//
// Save states, through system.sv's state
// window as core_top.sv drives it (16-bit words, a word's byte offset / 2,
// SS_CLOCKS clocks a word):
//   --state-save F FILE   at frame F find the clean point, read the state out
//                         into FILE (the header's cartridge part filled in as
//                         core_top.sv will) and go on
//   --state-load FILE     at frame --load-at (30) write FILE in and let it go
//   --resave FILE         with --state-load: before the load lets go, read
//                         the state straight back out into FILE
//   --pocket              both through core/state_bridge.sv, the bridge's clock
//                         and commands as the Pocket gives them (Vbridge, a
//                         model of its own beside this one): the file read a
//                         32-bit word every SIM_POCKET_PERIOD clocks of clk_74a
//                         (88), SIM_POCKET_CHUNK bytes (4096) then a wait of
//                         SIM_POCKET_STALL clocks (40000), each chunk's first
//                         word read again as the Pocket does. SIM_POCKET_RESET=1:
//                         a load's file comes with the Pocket's reset still on.
//                         SIM_POCKET_LONG=1: the file 0x44000 bytes whatever the game, as
//                         it is if the Pocket asks its size before a ROM (core_top.sv).
//                         SIM_POCKET_PAUSE=N: the menu's pause on for N frames
//                         before the save. SIM_POCKET_BADHDR=1: a wrong serial.
//                         A state made at the other timing: core_top.sv's clock
//                         changed as pal_clock.sv changes it, pal a few clocks
//                         after the bridge's pal_take and its hold up for
//                         SIM_POCKET_RETUNE clocks (30000).
//                         Without --pocket, the state's PAL is the console's as
//                         it is written in.
//   --sav FILE            the save RAM from a .sav (128 KB, Spiritualized's
//                         layout) as the Pocket loads it, with the reset on
//   --sav-out FILE        at the end, the save RAM as the Pocket writes the .sav
//   --i2c-log FILE        the serial save chip: a line each time SCL or SDA or
//                         what SDA reads changes (frame scl sda out), and W addr
//                         data for each byte it keeps
// From the clock the console is let go, after.txt gets a line a frame: its
// number since then, its size, the picture's CRC and a CRC of the chips' own
// sound every clock (FM_left, FM_right, PSG_SND, before the filters). Two runs
// are the same from there if their after.txt are.

#include "Vsystem.h"
#include "Vbridge.h"
#include "Vsystem___024root.h"
#include "verilated.h"
#include <zlib.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <algorithm>

static const double MCLK_HZ = 53693181.0;  // the PLL's clk_sys (mf_pllbase)
static const int AUDIO_HZ = 48000;
static int ROM_LATENCY = 4;                 // MCLK cycles from request to ack (SIM_ROM_LATENCY)

struct Quirk { const char *id, *name; int map, chip; };
static const Quirk QUIRKS[] = {
#include "quirks.inc"
};

// ---- PNG and WAV ----
static void put32(std::vector<uint8_t> &v, uint32_t x) { for (int i = 3; i >= 0; i--) v.push_back(x >> (i * 8)); }
static void chunk(FILE *f, const char *type, const std::vector<uint8_t> &data) {
  std::vector<uint8_t> c; put32(c, data.size());
  c.insert(c.end(), type, type + 4); c.insert(c.end(), data.begin(), data.end());
  put32(c, crc32(0, c.data() + 4, c.size() - 4));
  fwrite(c.data(), 1, c.size(), f);
}
static bool write_png(const std::string &path, int w, int h, const std::vector<uint32_t> &px) {
  FILE *f = fopen(path.c_str(), "wb");
  if (!f) return false;
  static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  fwrite(sig, 1, 8, f);
  std::vector<uint8_t> ihdr; put32(ihdr, w); put32(ihdr, h);
  ihdr.insert(ihdr.end(), {8, 2, 0, 0, 0});
  chunk(f, "IHDR", ihdr);
  std::vector<uint8_t> raw;
  for (int y = 0; y < h; y++) {
    raw.push_back(0);
    for (int x = 0; x < w; x++) { uint32_t p = px[y * w + x]; raw.push_back(p >> 16); raw.push_back(p >> 8); raw.push_back(p); }
  }
  uLongf n = compressBound(raw.size());
  std::vector<uint8_t> z(n);
  compress2(z.data(), &n, raw.data(), raw.size(), 6);
  z.resize(n);
  chunk(f, "IDAT", z);
  chunk(f, "IEND", {});
  fclose(f);
  return true;
}
static void write_wav(const std::string &path, const std::vector<int16_t> &s) {
  FILE *f = fopen(path.c_str(), "wb");
  if (!f) return;
  auto u32 = [&](uint32_t x) { fwrite(&x, 4, 1, f); };
  auto u16 = [&](uint16_t x) { fwrite(&x, 2, 1, f); };
  uint32_t bytes = s.size() * 2;
  fwrite("RIFF", 1, 4, f); u32(36 + bytes); fwrite("WAVEfmt ", 1, 8, f);
  u32(16); u16(1); u16(2); u32(AUDIO_HZ); u32(AUDIO_HZ * 4); u16(4); u16(16);
  fwrite("data", 1, 4, f); u32(bytes);
  fwrite(s.data(), 2, s.size(), f);
  fclose(f);
}

// ---- the pads ----
struct Press { long from, to; int bits; };
static int button_bits(const std::string &s) {
  // system.sv's JOY_n, each name the Genesis pad's button it reaches (P1_A, P1_B, P1_C)
  static const char *names[12] = {"right", "left", "down", "up", "a", "b", "c", "start", "mode", "x", "y", "z"};
  int bits = 0;
  size_t i = 0;
  while (i <= s.size()) {
    size_t j = s.find('+', i); if (j == std::string::npos) j = s.size();
    std::string b = s.substr(i, j - i);
    int k = 0;
    for (; k < 12; k++) if (b == names[k]) break;
    if (k == 12) { fprintf(stderr, "unknown button '%s' (right left down up a b c start mode x y z)\n", b.c_str()); exit(2); }
    bits |= 1 << k;
    i = j + 1;
  }
  return bits;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  std::string rom_path, out = "build/sim_genesis", region = "auto", saves, fm_log;
  bool pal60 = false;   // the PAL 60 Hz row
  std::string st_save, st_load, st_resave, st_twice, sav_path, sav_out, i2c_log;
  bool pocket = false;
  long frames = 600, every = 60, st_save_at = -1, st_load_at = 30, save_delay = 0;
  std::vector<Press> presses;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> std::string { if (i + 1 >= argc) { fprintf(stderr, "%s needs a value\n", a.c_str()); exit(2); } return argv[++i]; };
    if (a == "--frames") frames = atol(next().c_str());
    else if (a == "--out") out = next();
    else if (a == "--every") every = atol(next().c_str());
    else if (a == "--save") saves = "," + next() + ",";
    else if (a == "--pal60") pal60 = true;
    else if (a == "--region") region = next();
    else if (a == "--fm-log") fm_log = next();
    else if (a == "--state-save") { st_save_at = atol(next().c_str()); st_save = next(); }
    else if (a == "--state-load") st_load = next();
    else if (a == "--load-at") st_load_at = atol(next().c_str());
    else if (a == "--save-delay") save_delay = atol(next().c_str());   // clocks into frame F before the save is asked
    else if (a == "--resave") st_resave = next();
    else if (a == "--twice") st_twice = next();   // (a save read out a second time, before it goes on)
    else if (a == "--pocket") pocket = true;
    else if (a == "--sav") sav_path = next();
    else if (a == "--sav-out") sav_out = next();
    else if (a == "--i2c-log") i2c_log = next();
    else if (a == "--press") {
      std::string p = next();
      size_t c1 = p.find(':'), c2 = p.find(':', c1 + 1);
      if (c1 == std::string::npos) { fprintf(stderr, "--press F:buttons[:N]\n"); return 2; }
      long f = atol(p.substr(0, c1).c_str()), n = c2 == std::string::npos ? 4 : atol(p.substr(c2 + 1).c_str());
      presses.push_back({f, f + n, button_bits(p.substr(c1 + 1, c2 == std::string::npos ? std::string::npos : c2 - c1 - 1))});
    }
    else if (a[0] == '+') continue;  // Verilator's own
    else if (a[0] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); return 2; }
    else rom_path = a;
  }
  if (rom_path.empty()) { fprintf(stderr, "usage: Vsystem <rom> [--frames N] [--out DIR] [--every K] [--save F,F] [--press F:buttons[:N]] [--region auto|usa|europe|japan] [--pal60] [--fm-log FILE]\n"); return 2; }

  // the ROM, big-endian words as the loader writes them to the SDRAM; the
  // whole 32 MB the Pocket's SDRAM has, as system.sv also writes there
  FILE *rf = fopen(rom_path.c_str(), "rb");
  if (!rf) { fprintf(stderr, "cannot open %s\n", rom_path.c_str()); return 1; }
  std::vector<uint8_t> bytes;
  { uint8_t buf[65536]; size_t n; while ((n = fread(buf, 1, sizeof buf, rf)) > 0) bytes.insert(bytes.end(), buf, buf + n); }
  fclose(rf);
  if (bytes.size() < 0x200) { fprintf(stderr, "%s is too small for a Genesis ROM\n", rom_path.c_str()); return 1; }
  if (bytes.size() & 1) bytes.push_back(0);
  std::vector<uint16_t> sdram(1 << 24, 0);
  for (size_t i = 0; i + 1 < bytes.size() && i / 2 < sdram.size(); i += 2) sdram[i / 2] = bytes[i] << 8 | bytes[i + 1];

  // the header as core_top.sv reads it: the serial for the quirks, the region
  char cart_id[9] = {0};
  memcpy(cart_id, &bytes[0x183], 8);
  std::vector<std::string> quirks;
  int ep_map = 0, ep_chip = 0;
  for (const Quirk &q : QUIRKS) if (!memcmp(cart_id, q.id, strlen(q.id))) {
    if (q.map) { if (!ep_map) { ep_map = q.map; ep_chip = q.chip; } }
    else quirks.push_back(q.name);
  }
  // the header's save memory, as core_top.sv reads it
  bool hdr_ra = bytes[0x1B0] == 'R' && bytes[0x1B1] == 'A';
  bool hdr_short = !memcmp(&bytes[0x1B5], &bytes[0x1B9], 2) && (bytes[0x1B7] >> 2) == (bytes[0x1BB] >> 2);
  bool hackable = !memcmp(cart_id, "G-4060 ", 7) || !memcmp(cart_id, "T-12046", 7) || !memcmp(cart_id, "T-12053", 7);
  if (hackable && hdr_ra && !hdr_short) ep_map = 0;
  else if (!ep_map && hdr_ra && (bytes[0x1B2] == 0xE8 || hdr_short)
           && std::find(quirks.begin(), quirks.end(), "pier") == quirks.end()
           && std::find(quirks.begin(), quirks.end(), "sram00") == quirks.end()) { ep_map = EP_SEGA; ep_chip = C_X24C01; }
  if (ep_map) quirks.push_back("eeprom:" + std::to_string(ep_map) + ":" + std::to_string(ep_chip));
  auto hdr = [&](uint8_t c, bool &j, bool &u, bool &e) {
    if (c == 'J') j = true; else if (c == 'U') u = true; else if (c == 'E') e = true;
  };
  bool hj = false, hu = false, he = false;
  uint8_t r0 = bytes[0x1F0];
  if (r0 == 'J' || r0 == 'U' || r0 == 'E') hdr(r0, hj, hu, he);
  else if (r0 >= '0' && r0 <= '9') { he = r0 & 8; hu = r0 & 4; hj = r0 & 1; }
  else if (r0 >= 'A' && r0 <= 'F') { uint8_t h = (r0 - 7) & 15; he = h & 8; hu = h & 4; hj = h & 1; }
  hdr(bytes[0x1F2], hj, hu, he);
  hdr(bytes[0x1F1], hj, hu, he);
  int reg = hu ? 1 : he ? 2 : hj ? 0 : 1;  // 0 Japan, 1 USA, 2 Europe
  if (region == "usa") reg = 1; else if (region == "europe") reg = 2; else if (region == "japan") reg = 0;
  else if (region == "auto60") { region = "auto"; pal60 = true; }   // (the one row's Auto (60 Hz), before PAL 60 Hz)
  else if (region != "auto") { fprintf(stderr, "--region auto, usa, europe or japan\n"); return 2; }
  static const char *REGION[3] = {"Japan", "USA", "Europe"};

  Vsystem *top = new Vsystem;
  // one eval before the inputs are set: Verilator runs the port defaults
  // (sim/genesis/bram.sv's, the wrappers') at time 0, and where it has inlined
  // a module, on the net the port is wired to – system.sv's LOADING among them
  top->MCLK = 0;
  top->eval();
  auto has = [&](const char *q) { for (auto &s : quirks) if (s == q) return true; return false; };
  top->RESET_N = 1;
  top->LOADING = 1;
  top->PAL_SAYS = region == "europe" || (region == "auto" && he && !hu && !hj);   // as core_top.sv's says_pal
  top->PAL = top->PAL_SAYS && !pal60;                                              // and want_pal
  top->EXPORT = reg != 0;
  // the settings system.sv reads, as core_top.sv sets them (the menu's defaults); SIM_* to change one
  { const char *e = getenv("SIM_LPF"); top->LPF_MODE = e ? atoi(e) : 0; }
  { const char *e = getenv("SIM_FM"); top->ENABLE_FM = e ? atoi(e) : 1; }
  { const char *e = getenv("SIM_PSG"); top->ENABLE_PSG = e ? atoi(e) : 1; }
  { const char *e = getenv("SIM_HIFI"); top->EN_HIFI_PCM = e ? atoi(e) : 0; }
  { const char *e = getenv("SIM_LADDER"); top->LADDER = e ? atoi(e) : 1; }
  { const char *e = getenv("SIM_HIGH_SPRITES"); top->OBJ_LIMIT_HIGH = e ? atoi(e) : 0; }   // the Core Setting
  top->FAST_FIFO = has("fifo");
  top->SRAM00_QUIRK = has("sram00");
  top->EEPROM_MAP = ep_map;
  top->EEPROM_CHIP = ep_chip;
  top->NORAM_QUIRK = has("noram");
  top->PIER_QUIRK = has("pier");
  top->SVP_QUIRK = has("svp");
  top->FMBUSY_QUIRK = has("fmbusy");
  top->SCHAN_QUIRK = has("schan");
  { const char *e = getenv("SIM_TURBO"); top->TURBO = e ? atoi(e) : 0; }
  { const char *e = getenv("SIM_J3BUT"); top->J3BUT = e ? atoi(e) : 0; }
  top->MULTITAP = 0;
  top->BGA_EN = 1; top->BGB_EN = 1; top->SPR_EN = 1;
  top->PAUSE_EN = 0;
  top->BORDER = 0; top->CRAM_DOTS = 0;
  top->ROMSZ = bytes.size() / 2;
  top->ROM_ACK2 = 0; top->ROM_DATA2 = 0;
  top->SS_SAVE = 0; top->SS_LOAD = 0; top->SS_GO = 0; top->SS_RD = 0; top->SS_WR = 0; top->SS_ADDR = 0; top->SS_DI = 0;

  std::vector<uint32_t> line, frame;
  std::vector<std::vector<uint32_t>> lines;
  std::vector<int16_t> audio;
  FILE *ft = fopen((out + "/frames.txt").c_str(), "w");
  if (!ft) { fprintf(stderr, "cannot write in %s\n", out.c_str()); return 1; }
  long nframe = 0, saved = 0;
  bool old_hbl = true, old_vbl = true, old_hs = false, vblank_line = true;
  int rom_wait = 0, rom_ch = 0;
  uint8_t rom_ack = 0, rom_ack2 = 0;
  double audio_acc = 0;
  const double audio_step = MCLK_HZ / AUDIO_HZ;
  const long load_cycles = 70000;  // system.sv clears its RAMs while LOADING (ram_rst_a, 64 K words)
  uint64_t cycle = 0;
  // SIM_TRACE=n: the 68000's address every n clocks
  if (getenv("SIM_ROM_LATENCY")) ROM_LATENCY = atoi(getenv("SIM_ROM_LATENCY"));
  const uint64_t trace = getenv("SIM_TRACE") ? strtoull(getenv("SIM_TRACE"), nullptr, 10) : 0;
  auto t0 = std::chrono::steady_clock::now();
  // the serial save chip (--i2c-log)
  FILE *fi = i2c_log.empty() ? nullptr : fopen(i2c_log.c_str(), "w");
  if (!i2c_log.empty() && !fi) { fprintf(stderr, "cannot write %s\n", i2c_log.c_str()); return 1; }
  int i2c_was = -1;
  // the YM2612's inputs (--fm-log), as its next rising edge will take them
  FILE *fl = fm_log.empty() ? nullptr : fopen(fm_log.c_str(), "w");
  if (!fm_log.empty() && !fl) { fprintf(stderr, "cannot write %s\n", fm_log.c_str()); return 1; }
  uint64_t fm_c0 = 0;
  int fm_wr = 0, fm_rst = -1, fm_a = -1, fm_d = -1;

  // ---- save states: the harness's side of the state window ----
  const int SS_CLOCKS = 24, SS_WORDS = top->SVP_QUIRK ? 0x22000 : 0x1A000;   // 0x44000 or 0x34000 bytes
  enum { H_IDLE, H_SEEK, H_READ, H_LWRITE, H_LGO, H_WAITGO, H_DONE } hs = H_IDLE;
  std::vector<uint16_t> st(SS_WORDS, 0);
  std::string st_out;                  // the file being read out
  bool resaving = false;
  long hw = 0; int hwait = 0;
  uint64_t t_cmd = 0;
  std::vector<uint8_t> loaded;
  if (!st_load.empty()) {
    FILE *f = fopen(st_load.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", st_load.c_str()); return 1; }
    loaded.resize(SS_WORDS * 2);
    if (fread(loaded.data(), 1, loaded.size(), f) != loaded.size()) { fprintf(stderr, "%s is not a whole state\n", st_load.c_str()); return 1; }
    fclose(f);
    // the header, as core_top.sv checks it: the magic, the version, this ROM
    uint32_t rsz = loaded[0x0C] << 24 | loaded[0x0D] << 16 | loaded[0x0E] << 8 | loaded[0x0F];
    if (memcmp(loaded.data(), "GPSS", 4) || loaded[4] || loaded[5] != (top->SVP_QUIRK ? 2 : 1) || rsz != bytes.size() || memcmp(&loaded[0x10], &bytes[0x180], 16)) {
      fprintf(stderr, "%s is not a state of this ROM\n", st_load.c_str()); return 1;
    }
  }
  // ---- --pocket: the bridge's side, a clock of clk_74a at a time ----
  Vbridge *b = pocket ? new Vbridge : nullptr;
  const int P_PERIOD = getenv("SIM_POCKET_PERIOD") ? atoi(getenv("SIM_POCKET_PERIOD")) : 88;
  const int P_CHUNK = getenv("SIM_POCKET_CHUNK") ? atoi(getenv("SIM_POCKET_CHUNK")) : 4096;
  const int P_STALL = getenv("SIM_POCKET_STALL") ? atoi(getenv("SIM_POCKET_STALL")) : 40000;
  const bool P_RESET = getenv("SIM_POCKET_RESET") != nullptr;
  const long P_PAUSE = getenv("SIM_POCKET_PAUSE") ? atol(getenv("SIM_POCKET_PAUSE")) : 0;
  if (getenv("SIM_POCKET_BADHDR") && !loaded.empty()) loaded[0x11] ^= 1;
  enum { P_IDLE, P_ACK, P_POLL, P_DELAY, P_READ, P_STALLING, P_WRITE, P_LRESET, P_LACK, P_LPOLL, P_WAITGO, P_DONE } ps = P_IDLE;
  const int FILE_BYTES = getenv("SIM_POCKET_LONG") ? 0x44000 : SS_WORDS * 2;
  if (!loaded.empty() && (int)loaded.size() < FILE_BYTES) loaded.resize(FILE_BYTES, 0);
  std::vector<uint8_t> pfile;
  long pa = 0, pchunk_end = 0, pt = 0;
  bool pfirst = true, phost_reset_n = true, pmenu = false, psaving = false, pread_done = false;
  double pphase = 0;
  int pre_status = 0, pre_do = 0;
  uint16_t bram_seen[256]; int bram_i = -1, bram_t = 0;
  if (b) { b->clk_74a = 0; b->clk_sys = 0; b->bridge_endian_little = 0; b->reset_n = 1; b->pal = top->PAL; b->pal_hold = 0; b->svp = top->SVP_QUIRK; b->rom_size = bytes.size(); b->eval(); }
  // pal_clock.sv as core_top.sv drives it for a loaded state: pal changes, its hold up meanwhile
  const long P_RETUNE = getenv("SIM_POCKET_RETUNE") ? atol(getenv("SIM_POCKET_RETUNE")) : 30000;
  uint64_t pclk_pal_at = 0, pclk_hold_to = 0;
  int pclk_pal = 0;
  auto p_write_file = [&]() {
    FILE *f = fopen(st_out.c_str(), "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", st_out.c_str()); exit(1); }
    fwrite(pfile.data(), 1, pfile.size(), f);
    fclose(f);
  };
  auto p_start_save = [&](const std::string &file) {
    st_out = file; b->savestate_start = 1; ps = P_ACK; psaving = true; pread_done = false; t_cmd = cycle;
  };
  // the .sav (--sav)
  std::vector<uint8_t> sav;
  if (!sav_path.empty()) {
    FILE *f = fopen(sav_path.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", sav_path.c_str()); return 1; }
    sav.resize(131072);
    if (fread(sav.data(), 1, sav.size(), f) != sav.size()) { fprintf(stderr, "%s is not 128 KB\n", sav_path.c_str()); return 1; }
    fclose(f);
  }
  const long sav_cycles = sav.empty() ? 0 : 40000;
  bool released = false;
  int blank_d = 0;
  long rel_frame = 0;
  uint32_t snd_crc = 0;
  FILE *fa = nullptr;
  const bool ssdbg = getenv("SIM_SSDBG") != nullptr;
  auto ss_report = [&](const char *what) {
    printf("state: %s at cycle %llu, frame %ld (status %d)\n", what, (unsigned long long)cycle, nframe, top->SS_STATUS);
    fflush(stdout);
  };


  printf("%s: serial '%s', %zu KB, region %s%s%s\n", rom_path.c_str(), cart_id, bytes.size() / 1024, REGION[reg],
         quirks.empty() ? "" : ", quirks:", [&] { std::string s; for (auto &q : quirks) s += " " + q; return s; }().c_str());
  fflush(stdout);

  long v30_time = 0, v30_reset = 0;
  while (nframe < frames && !Verilated::gotFinish()) {
    if (b) { pre_status = top->SS_STATUS; pre_do = top->SS_DO; }
    // the picture black while a load fills the chips (core_top.sv, from the bridge)
    if (b && b->load_blank != blank_d) { blank_d = b->load_blank; ss_report(blank_d ? "black from" : "black to"); }
    top->MCLK = 1;
    top->eval();
    cycle++;
    if (cycle == load_cycles) top->LOADING = 0;
    // the .sav, as the Pocket loads it: after the RAM is cleared, the reset on
    if (!sav.empty() && cycle >= load_cycles && cycle < load_cycles + sav_cycles) {
      long n = cycle - load_cycles;
      top->BRAM_WE = 0;
      if (n / 2 < 32768) {   // a word every other clock, 32 K words is the RAM
        top->BRAM_A = n / 2;
        top->BRAM_DI = sav[(n / 2) * 4 + 1] | sav[(n / 2) * 4 + 3] << 8;
        top->BRAM_WE = !(n & 1);
      }
      top->RESET_N = 0;
    }
    else if (!sav.empty() && cycle == load_cycles + sav_cycles) { top->RESET_N = 1; top->BRAM_WE = 0; }

    // core_top.sv's pal_frame: 240 lines held at 60 Hz longer than such a frame, and the
    // game is started again at 50 Hz (the clock's change itself is pal-test.sh's)
    if (!top->PAL && cycle > load_cycles && (top->RESOLUTION & 2)) {
      if (++v30_time == 1 << 21) {
        top->PAL = 1; top->RESET_N = 0; v30_reset = cycle + 1000;
        printf("240 lines at 60 Hz: started again at 50 Hz at frame %ld\n", nframe); fflush(stdout);
      }
    } else v30_time = 0;
    if (v30_reset && cycle == v30_reset) { top->RESET_N = 1; v30_reset = 0; }

    // the ROM: a request is a REQ toggled away from its ack. As in sdram.sv one
    // access at a time, the 68000's channel before the SVP's, and one output
    // for both
    if (!rom_ch) rom_ch = top->ROM_REQ != rom_ack ? 1 : top->ROM_REQ2 != rom_ack2 ? 2 : 0;
    if (rom_ch && ++rom_wait >= ROM_LATENCY) {
      if (rom_ch == 1) {
        uint32_t a = top->ROM_ADDR & 0xFFFFFF;
        if (top->ROM_WE) {
          uint16_t w = sdram[a], d = top->ROM_WDATA;
          if (top->ROM_BE & 1) w = (w & 0xFF00) | (d & 0x00FF);
          if (top->ROM_BE & 2) w = (w & 0x00FF) | (d & 0xFF00);
          sdram[a] = w;
        }
        top->ROM_DATA = top->ROM_DATA2 = sdram[a];
        rom_ack = top->ROM_REQ;
        top->ROM_ACK = rom_ack;
      } else {
        top->ROM_DATA = top->ROM_DATA2 = sdram[top->ROM_ADDR2 & 0xFFFFF];   // the SVP drives 20 bits
        rom_ack2 = top->ROM_REQ2;
        top->ROM_ACK2 = rom_ack2;
      }
      rom_wait = 0; rom_ch = 0;
    }

    if (fi) {
      auto *r = top->rootp;
      int now = r->system__DOT__i2c_scl << 2 | r->system__DOT__i2c_sda << 1 | r->system__DOT__i2c_o;
      if (now != i2c_was) { fprintf(fi, "%ld %d %d %d\n", nframe, now >> 2, now >> 1 & 1, now & 1); i2c_was = now; }
      if (r->system__DOT__i2c_we) fprintf(fi, "W %x %02x\n", r->system__DOT__i2c_addr, r->system__DOT__i2c_di);
    }

    // the pads, by the frame
    int joy = 0;
    for (auto &p : presses) if (nframe >= p.from && nframe < p.to) joy |= p.bits;
    top->JOY_1 = joy;

    // the picture as core_top.sv sends it to the Pocket: a line is shown or
    // not by VBL's value as its HSYNC starts (VBL changes before the line's
    // end), each pixel the VDP gives outside HBL, through core_top's colours
    if (top->HS && !old_hs) vblank_line = top->VBL;
    old_hs = top->HS;
    if (top->CE_PIX && !top->HBL && !vblank_line) {
      static const uint8_t LUT[16] = {0, 27, 49, 71, 87, 103, 119, 130, 146, 157, 174, 190, 206, 228, 255, 255};
      line.push_back((uint32_t)LUT[top->RED & 15] << 16 | LUT[top->GREEN & 15] << 8 | LUT[top->BLUE & 15]);
    }
    if (top->HBL && !old_hbl && !line.empty()) { lines.push_back(line); line.clear(); }
    old_hbl = top->HBL;
    // (a blank with no lines in it, as can end the loading, is not a frame)
    if (vblank_line && !old_vbl && cycle > load_cycles && (!lines.empty() || !line.empty())) {
      if (!line.empty()) { lines.push_back(line); line.clear(); }
      nframe++;
      int w = 0, h = lines.size();
      for (auto &l : lines) if ((int)l.size() > w) w = l.size();
      frame.assign((size_t)w * h, 0);
      for (int y = 0; y < h; y++) std::copy(lines[y].begin(), lines[y].end(), frame.begin() + (size_t)y * w);
      uint32_t hash = crc32(0, (const Bytef *)frame.data(), frame.size() * 4);
      fprintf(ft, "%ld %dx%d %08x\n", nframe, w, h, hash);
      if (fa) { fprintf(fa, "%ld %dx%d %08x %08x\n", rel_frame++, w, h, hash, snd_crc); fflush(fa); snd_crc = 0; }
      bool save = (every > 0 && nframe % every == 0) || nframe == frames
                  || saves.find("," + std::to_string(nframe) + ",") != std::string::npos;
      if (save && w && h) {
        char name[32]; snprintf(name, sizeof name, "/f_%05ld.png", nframe);
        write_png(out + name, w, h, frame);
        saved++;
      }
      lines.clear();
      double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
      printf("%ld of %ld frames  (%dx%d, %.2f s a frame)\n", nframe, frames, w, h, s / nframe);
      fflush(stdout);
    }
    old_vbl = vblank_line;

    // the sound, at 48 kHz
    if (cycle > load_cycles && (audio_acc += 1) >= audio_step) {
      audio_acc -= audio_step;
      audio.push_back((int16_t)top->DAC_LDATA);
      audio.push_back((int16_t)top->DAC_RDATA);
    }

    // ---- save states: the state window, a clock at a time ----
    top->SS_SAVE = 0; top->SS_LOAD = 0; top->SS_GO = 0; top->SS_RD = 0; top->SS_WR = 0;
    if (!pocket && top->SS_STATUS == 3 && hs != H_DONE && hs != H_IDLE) { ss_report("an error"); hs = H_DONE; }
    if (b) {
      // what system.sv's outputs were before this clock's edge, its inputs after
      b->cart_download = top->LOADING;
      b->ss_status = pre_status; b->ss_do = pre_do;
      // the ROM's header going by as the ROM loads
      long hn = (long)cycle - 2000;
      b->ioctl_wr = hn >= 0 && hn < 8 * 16 && !(hn & 15);
      if (hn >= 0 && hn < 8 * 16) {
        int i = hn / 16;
        b->ioctl_addr = 0x180 + 2 * i;
        b->ioctl_data = bytes[0x180 + 2 * i] | bytes[0x181 + 2 * i] << 8;
      }
      b->clk_sys = 1; b->eval();
      if (b->pal_take && b->pal_file != top->PAL) {
        pclk_pal = b->pal_file; pclk_pal_at = cycle + 40; pclk_hold_to = cycle + P_RETUNE;
        printf("state: the file's timing, %s, the clock changing at cycle %llu\n", pclk_pal ? "PAL" : "NTSC", (unsigned long long)cycle); fflush(stdout);
      }
      if (pclk_pal_at && cycle == pclk_pal_at) { top->PAL = pclk_pal; b->pal = pclk_pal; pclk_pal_at = 0; }
      b->pal_hold = cycle < pclk_hold_to;
      top->SS_SAVE = b->ss_save; top->SS_LOAD = b->ss_load; top->SS_GO = b->ss_go;
      top->SS_RD = b->ss_rd; top->SS_WR = b->ss_wr; top->SS_ADDR = b->ss_addr; top->SS_DI = b->ss_di;
      top->RESET_N = phost_reset_n || b->hold_reset;
      top->PAUSE_EN = pmenu && !b->pause_lift;
      b->clk_sys = 0; b->eval();
      // the menu's pause on before the save, off once it is read out
      if (P_PAUSE && st_save_at >= 0 && nframe >= st_save_at - P_PAUSE && !pread_done) pmenu = true; else pmenu = false;
      // the .sav's port between the state's words: read at the freeze, compared at the end
      if (bram_i >= 0 && bram_i < 256 && ps == P_DELAY) {
        if (bram_t == 0) top->BRAM_A = bram_i * 127;
        if (bram_t == 4) { bram_seen[bram_i] = top->BRAM_DO; bram_i++; bram_t = -1; }
        bram_t++;
      }
      // saved or loaded, and now let go
      if (psaving && pread_done && top->SS_STATUS == 0 && !released) {
        ss_report("let go"); released = true; rel_frame = 0; snd_crc = 0;
        if (fa) fclose(fa); fa = fopen((out + "/after.txt").c_str(), "w");
        psaving = false; ps = P_DONE;
      }
      if (ps == P_WAITGO && top->SS_STATUS == 0 && !released) {
        ss_report("let go"); released = true; rel_frame = 0; snd_crc = 0;
        if (fa) fclose(fa); fa = fopen((out + "/after.txt").c_str(), "w");
        ps = st_save_at >= 0 && st_out.empty() ? P_IDLE : P_DONE;
        if (ps == P_IDLE) { released = false; hwait = 0; loaded.clear(); }
      }
    }
    if (!pocket) switch (hs) {
    case H_IDLE:
      if (st_save_at >= 0 && nframe == st_save_at && st_out.empty() && hwait < save_delay) hwait++;
      else if (st_save_at >= 0 && nframe == st_save_at && st_out.empty()) {
        top->SS_SAVE = 1; st_out = st_save; hs = H_SEEK; hwait = 4; t_cmd = cycle; ss_report("save asked");
      } else if (!loaded.empty() && nframe == st_load_at) {
        top->SS_LOAD = 1; hs = H_LWRITE; hw = 0; hwait = 40; ss_report("load begun");
      }
      break;
    case H_SEEK:
      if (hwait) { hwait--; break; }
      if (top->SS_STATUS == 2) {
        ss_report(resaving ? "restored state readable" : "frozen at its point");
        printf("state: %.2f ms to the point\n", (cycle - t_cmd) / MCLK_HZ * 1000);
        hs = H_READ; hw = 0; hwait = 0;
      }
      break;
    case H_READ:
      if (hwait == 0) { top->SS_ADDR = hw; top->SS_RD = 1; hwait = SS_CLOCKS + 1; break; }
      if (--hwait == 1) {
        st[hw] = top->SS_DO;
        if (++hw == SS_WORDS) {
          // the header's cartridge part, as core_top.sv will fill it in
          for (int i = 0; i < 8; i++) st[8 + i] = bytes[0x180 + 2 * i] << 8 | bytes[0x181 + 2 * i];
          FILE *f = fopen(st_out.c_str(), "wb");
          if (!f) { fprintf(stderr, "cannot write %s\n", st_out.c_str()); return 1; }
          for (uint16_t w : st) { fputc(w >> 8, f); fputc(w & 0xFF, f); }
          fclose(f);
          ss_report("read out");
          printf("state: written %s\n", st_out.c_str());
          if (!st_twice.empty() && st_out != st_twice) { st_out = st_twice; hw = 0; hwait = 0; ss_report("read again"); break; }
          hs = H_WAITGO; hwait = 2;
        }
      }
      break;
    case H_WAITGO:
      if (hwait == 2) { top->SS_GO = 1; hwait = 1; break; }
      if (top->SS_STATUS == 0) {
        ss_report("let go"); released = true; rel_frame = 0; snd_crc = 0;
        if (fa) fclose(fa); fa = fopen((out + "/after.txt").c_str(), "w");
        hs = H_DONE;
      }
      break;
    case H_LWRITE:
      if (hwait) { hwait--; break; }
      if (hw == SS_WORDS) { top->PAL = loaded[7] & 1; top->SS_GO = 1; ss_report("written in"); hs = H_LGO; hwait = 16; break; }
      top->SS_ADDR = hw; top->SS_DI = loaded[2 * hw] << 8 | loaded[2 * hw + 1]; top->SS_WR = 1;
      hw++; hwait = SS_CLOCKS;
      break;
    case H_LGO:
      if (hwait) { hwait--; break; }
      if (!st_resave.empty() && !resaving && top->SS_STATUS == 2) {
        ss_report("restored"); resaving = true; top->SS_SAVE = 1; st_out = st_resave; hs = H_SEEK; hwait = 8; t_cmd = cycle;
        break;
      }
      if (top->SS_STATUS == 0) {
        ss_report("let go"); released = true; rel_frame = 0; snd_crc = 0;
        if (fa) fclose(fa); fa = fopen((out + "/after.txt").c_str(), "w");
        hs = st_save_at >= 0 && st_out.empty() ? H_IDLE : H_DONE;   // (--state-load and --state-save: the second from the first)
        hwait = 0; loaded.clear();
      }
      break;
    default: break;
    }
    if (ssdbg) {
      auto *r = top->rootp;
      static int last_st = -1; static unsigned last_ua = 0xFFFF;
      int stn = r->system__DOT__ss_st;
      if (stn != last_st) { printf("ss: state %d at cycle %llu, PC %08x uaddr %03x\n", stn, (unsigned long long)cycle, r->system__DOT__fx_pc, r->system__DOT__fx_uaddr); last_st = stn; }
      if (stn == 1 && r->system__DOT__ss_win && cycle % 2000 == 0)
        printf("ss:   seek: tries %d park %d hold %d ok68 %d (atstart %d idle %d) okZ %d okV %d okB %d uaddr %03x PC %08x\n", r->system__DOT__ss_tries,
               r->system__DOT__ss_park68, r->system__DOT__ss_hold68, r->system__DOT__ss_ok68, r->system__DOT__fx_atstart,
               r->system__DOT__fx_busidle, r->system__DOT__ss_okZ, r->system__DOT__ss_okV, r->system__DOT__ss_okB, r->system__DOT__fx_uaddr, r->system__DOT__fx_pc);
      if (stn == 10 && cycle % 50000 == 0)
        printf("ss:   wait: atstart %d atdisp %d busidle %d AS %d mstate %d uaddr %03x\n", r->system__DOT__fx_atstart, r->system__DOT__fx_atdisp,
               r->system__DOT__fx_busidle, r->system__DOT__M68K_AS_N, r->system__DOT__mstate, r->system__DOT__fx_uaddr);
      if (stn >= 7 && stn <= 10 && r->system__DOT__fx_uaddr != last_ua) {
        last_ua = r->system__DOT__fx_uaddr;
        printf("ss:   uaddr %03x PC %08x A %06x  regs:", last_ua, r->system__DOT__fx_pc, top->DBG_M68K_A);
        for (int k = 0; k < 17; k++) printf(" %04x%04x", r->system__DOT__M68K__DOT__excUnit__DOT__regs68H[k], r->system__DOT__M68K__DOT__excUnit__DOT__regs68L[k]);
        printf("\n");
      }
    }
    if (getenv("SIM_UTRACE")) {
      static uint64_t u0 = strtoull(getenv("SIM_UTRACE"), nullptr, 10); static unsigned lu = 0xFFFF;
      auto *r = top->rootp;
      if (cycle >= u0 && cycle < u0 + 20000 && r->system__DOT__fx_uaddr != lu) {
        lu = r->system__DOT__fx_uaddr;
        printf("u %llu %03x PC %06x atstart %d\n", (unsigned long long)cycle, lu, r->system__DOT__fx_pc, r->system__DOT__fx_atstart);
      }
    }
    if (released && ssdbg) {
      static uint64_t rel_c = 0; if (!rel_c) rel_c = cycle;
      auto *r = top->rootp;
      if ((cycle - rel_c) % 997 == 0 && cycle - rel_c < 2000000)
        printf("ss: +%llu Z80 PC %04x reset_n %d busak_n %d  68000 PC %06x\n", (unsigned long long)(cycle - rel_c), r->system__DOT__z80_pc,
               r->system__DOT__Z80_RESET_N, r->system__DOT__Z80_BUSAK_N, r->system__DOT__fx_pc);
    }
    if (released) {
      auto *r = top->rootp;
      uint8_t b[6] = {(uint8_t)(r->system__DOT__FM_left >> 8), (uint8_t)r->system__DOT__FM_left,
                      (uint8_t)(r->system__DOT__FM_right >> 8), (uint8_t)r->system__DOT__FM_right,
                      (uint8_t)(r->system__DOT__PSG_SND >> 8), (uint8_t)r->system__DOT__PSG_SND};
      snd_crc = crc32(snd_crc, b, 6);
    }

    // SIM_BUSLOG=FILE: the 68000's bus cycles on the SVP's registers, the VDP's
    // control port and the SVP's mailbox. SIM_SSPLOG=FILE: the SSP's registers an
    // instruction, for 3 frames from the 68000's first job for it. tools/svp-trace.sh
    // sets both beside MAME's.
    {
      static FILE *bl = getenv("SIM_BUSLOG") ? fopen(getenv("SIM_BUSLOG"), "w") : nullptr;
      static FILE *sl = getenv("SIM_SSPLOG") ? fopen(getenv("SIM_SSPLOG"), "w") : nullptr;
      static bool old_ds = true;
      static long sl_from = -1;
      if (bl || sl) {
        auto *r = top->rootp;
        bool ds = r->system__DOT__M68K_UDS_N && r->system__DOT__M68K_LDS_N;
        bool rd = r->system__DOT__M68K_RNW;
        uint32_t a = (r->system__DOT__M68K_A & 0x7FFFFF) << 1;
        bool edge = !ds && old_ds;   // the data strobes coming on: a write's data is out
        bool end = ds && !old_ds;    // going off: a read's data is in
        if (bl && ((edge && !rd) || (end && rd)) && ((a >= 0xA15000 && a < 0xA15010) || a == 0xC00004 || a == 0xC00006 || (a >= 0x30FE00 && a < 0x30FE10)))
          fprintf(bl, "%ld %c %06x %04x\n", nframe, rd ? 'R' : 'W', a, rd ? r->system__DOT__M68K_MBUS_D : r->system__DOT__M68K_DO);
        if (sl && sl_from < 0 && edge && !rd && a == 0x30FE08 && r->system__DOT__M68K_DO == 5) sl_from = nframe;
        if (sl && sl_from >= 0 && nframe < sl_from + 3) {
          #define SSP(n) r->system__DOT__svp__DOT__chip__DOT__ssp160x__DOT__##n
          if (SSP(last_cycle)) fprintf(sl, "%04x %04x %08x %04x %04x\n", SSP(ir), SSP(pc), SSP(a), SSP(x), SSP(y));
        }
        old_ds = ds;
      }
    }

    if (trace && cycle % trace == 0) printf("cycle %llu  68000 at %06x PC %06x  ROM %06x req %d  VBUS %06x  SSP %04x ROM2 %05x req %d halt %d mas %d xst %04x\n", (unsigned long long)cycle,
                                            top->DBG_M68K_A, top->rootp->system__DOT__fx_pc, top->ROM_ADDR << 1, top->ROM_REQ, top->DBG_VBUS_A,
                                            top->rootp->system__DOT__svp__DOT__chip__DOT__ssp_pa, top->ROM_ADDR2, top->ROM_REQ2,
                                            top->rootp->system__DOT__svp__DOT__chip__DOT__halt, top->rootp->system__DOT__svp__DOT__chip__DOT__mas,
                                            top->rootp->system__DOT__svp__DOT__chip__DOT__xst);
    top->MCLK = 0;
    top->eval();

    // the Pocket, on clk_74a
    if (b) for (pphase += 74.25e6 / MCLK_HZ; pphase >= 1; pphase -= 1) {
      b->bridge_rd = 0; b->bridge_wr = 0;
      switch (ps) {
      case P_IDLE:
        if (st_save_at >= 0 && nframe == st_save_at && st_out.empty() && !psaving) {
          if (hwait < save_delay) hwait++;
          else { p_start_save(st_save); ss_report("save asked"); }
        }
        else if (!loaded.empty() && nframe == st_load_at) {
          ss_report("load begun");
          pa = 0; pt = 0; pchunk_end = P_CHUNK;
          if (P_RESET) { phost_reset_n = false; b->reset_n = 0; }
          ps = P_WRITE;
        }
        break;
      case P_ACK:
        if (b->savestate_start_ack) { b->savestate_start = 0; ps = P_POLL; }
        break;
      case P_POLL:
        if (b->savestate_start_err) { ss_report("an error"); psaving = false; ps = P_DONE; }
        else if (b->savestate_start_ok) {
          ss_report(st_resave.empty() || st_out != st_resave ? "frozen at its point" : "restored state readable");
          printf("state: %.2f ms to the point\n", (cycle - t_cmd) / MCLK_HZ * 1000);
          pfile.assign(FILE_BYTES, 0); pa = 0; pt = 0; pfirst = true; pchunk_end = P_CHUNK; bram_i = 0; bram_t = 0;
          ps = P_DELAY;
        }
        break;
      case P_DELAY:
        if (++pt == 20000) { pt = 0; ps = P_READ; }
        break;
      case P_READ:
        // a word: its address, the bus's value a few clocks on (what the read
        // before fetched), then this read starts
        if (pt == 0) b->bridge_addr = 0x40000000 + pa;
        if (pt == 4 && !pfirst) {
          uint32_t d = b->bridge_rd_data; long o = pa - 4;
          pfile[o] = d >> 24; pfile[o + 1] = d >> 16; pfile[o + 2] = d >> 8; pfile[o + 3] = d;
        }
        if (pt == 5) b->bridge_rd = 1;
        if (++pt == P_PERIOD) {
          pt = 0; pfirst = false;
          if (pa >= FILE_BYTES) {
            // the file's end: the cartridge's part is the bridge's, all of it is here
            p_write_file();
            ss_report("read out");
            printf("state: written %s\n", st_out.c_str());
            int same = 0;
            for (int i = 0; i < 256; i++) {
              long o = 0x24000 + 2 * (i * 127);
              if (bram_seen[i] == (pfile[o] | pfile[o + 1] << 8) || bram_seen[i] == (pfile[o + 1] | pfile[o] << 8)) same++;
            }
            printf("state: the .sav's port at the freeze: %d of 256 words as the state's\n", same);
            pread_done = true;
            ps = st_resave.empty() || st_out != st_resave ? P_DONE : P_WAITGO;
          }
          else if (pa == pchunk_end) { ps = P_STALLING; pt = 0; }
          else pa += 4;
        }
        break;
      case P_STALLING:
        // a chunk gone to the card: the next starts with the word just read again
        if (++pt >= P_STALL) { pt = 0; pfirst = true; pchunk_end += P_CHUNK; ps = P_READ; }
        break;
      case P_WRITE:
        if (pt == 0) {
          b->bridge_addr = 0x40000000 + pa;
          b->bridge_wr_data = (uint32_t)loaded[pa] << 24 | loaded[pa + 1] << 16 | loaded[pa + 2] << 8 | loaded[pa + 3];
        }
        if (pt == 5) b->bridge_wr = 1;
        if (++pt == P_PERIOD) {
          pt = 0; pa += 4;
          if (pa == FILE_BYTES) { ss_report("written in"); ps = P_RESET ? P_LRESET : P_LACK; b->savestate_load = P_RESET ? 0 : 1; }
          else if (pa == pchunk_end) { pchunk_end += P_CHUNK; pt = -P_STALL; }
        }
        break;
      case P_LRESET:
        // the Pocket's reset let go before Savestate Load
        if (++pt == 2000) { phost_reset_n = true; b->reset_n = 1; }
        if (pt == 4000) { pt = 0; b->savestate_load = 1; ps = P_LACK; }
        break;
      case P_LACK:
        if (b->savestate_load_ack) { b->savestate_load = 0; ps = P_LPOLL; }
        break;
      case P_LPOLL:
        if (b->savestate_load_err) { ss_report("an error (Savestate Load)"); ps = P_DONE; }
        else if (b->savestate_load_ok) {
          ss_report("restored");
          if (!st_resave.empty()) p_start_save(st_resave);
          else ps = P_WAITGO;
        }
        break;
      default: break;
      }
      b->clk_74a = 1; b->eval();
      b->clk_74a = 0; b->eval();
    }

    if (fl) {
      auto *r = top->rootp;
      uint64_t c = cycle + 1;  // the edge that takes these
      if (!fm_c0 && r->system__DOT__FM_CLKEN) { fm_c0 = c; fprintf(fl, "C %llu\n", (unsigned long long)c); }
      if (fm_c0) {
        if (r->system__DOT__FM_CLKEN && (c - fm_c0) % 7) { fprintf(stderr, "the FM clock enable left its 7\n"); return 1; }
        long t = (long)(c - fm_c0);
        int rst = !r->system__DOT__Z80_RESET_N;
        if (rst != fm_rst) { fprintf(fl, "R %ld %d\n", t, rst); fm_rst = rst; }
        int wr = (r->system__DOT__ZBUS_A >> 13 & 3) == 2 && r->system__DOT__ZBUS_WE;
        int a = r->system__DOT__ZBUS_A & 3, d = r->system__DOT__ZBUS_DO;
        if (wr && (!fm_wr || a != fm_a || d != fm_d)) { fprintf(fl, "W %ld %d %02x\n", t, a, d); fm_a = a; fm_d = d; }
        if (!wr && fm_wr) fprintf(fl, "E %ld\n", t);
        fm_wr = wr;
      }
    }
  }
  if (fl) fclose(fl);
  if (fa) fclose(fa);
  if (fi) fclose(fi);
  fclose(ft);
  if (!sav_out.empty()) {
    FILE *f = fopen(sav_out.c_str(), "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", sav_out.c_str()); return 1; }
    for (int n = 0; n < 32768; n++) {
      top->BRAM_A = n;
      for (int i = 0; i < 4; i++) { top->MCLK = !top->MCLK; top->eval(); }
      uint8_t lo = top->BRAM_DO, hi = top->BRAM_DO >> 8, w[4] = {lo, lo, hi, hi};
      fwrite(w, 1, 4, f);
    }
    fclose(f);
  }
  write_wav(out + "/audio.wav", audio);
  double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  int peak = 0;
  for (int16_t s : audio) if (abs(s) > peak) peak = abs(s);
  FILE *fj = fopen((out + "/run.json").c_str(), "w");
  if (fj) {
    fprintf(fj, "{\"rom\": \"%s\", \"serial\": \"%s\", \"region\": \"%s\", \"quirks\": [", rom_path.c_str(), cart_id, REGION[reg]);
    for (size_t i = 0; i < quirks.size(); i++) fprintf(fj, "%s\"%s\"", i ? ", " : "", quirks[i].c_str());
    fprintf(fj, "], \"frames\": %ld, \"saved\": %ld, \"seconds\": %.1f, \"mhz\": %.3f, \"audio_peak\": %d}\n",
            nframe, saved, secs, cycle / secs / 1e6, peak);
    fclose(fj);
  }
  printf("%ld frames in %.1f s (%.2f MHz of 53.69, %.1f%% of real time), %ld saved; sound peak %d\n",
         nframe, secs, cycle / secs / 1e6, 100.0 * cycle / MCLK_HZ / secs, saved, peak);
  top->final();
  delete top;
  if (b) { b->final(); delete b; }
  return 0;
}
