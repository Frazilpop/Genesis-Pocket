// The YM2612's scan, proved on jt12 alone.
// tools/jt12-scan-test.sh builds and runs it.
//
//   Vbench <writes.log> [--saves K] [--out DIR] [--seed S] [--until SECONDS]
//          [--spoil chain:K|lane:L:S:B]
//
// Three copies of jt12 (bench.sv) on the same clock. A and B take the
// writes in the log (sim/genesis's --fm-log, or tools/jt12-writes.py's), C
// other, random writes, so it is nothing like them. At each of K points the
// three are frozen together at a slot boundary halfway through a sample (the
// FM clock enable held low, the writes held back): A is scanned out, its
// chain and its loops, and what comes out goes into C as it goes, and C is
// read back at once, which must give the same; B is only frozen, as long. Then all three go on with the log's writes, and from the
// first clock they must give the same sound, bit for bit, the same busy
// flag, timer flags and interrupt. Before C goes back to random writes, all
// three are frozen and scanned out again, and the three states must be the
// same (A's is written to DIR as ym2612_K.bin: the 256 bytes the format has
// for the YM2612's globals, the chain, then its 1,536, the loops' taps lane
// by lane). The chain's length is measured first, on C.
//
// Out: a line a save point, "K of N" as it goes, and the last line
// "N of N saves ok"; the exit code is 0 only then.

#include "Vbench.h"
#include "verilated.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static Vbench *top;
static uint64_t clocks = 0;

static void tick() {
  top->clk = 1; top->eval();
  top->clk = 0; top->eval();
  clocks++;
}

// ---- each copy's inputs ----
struct Feed { int rst = 1, wr = 0, addr = 0, din = 0; };
static Feed in[3];
static int ss_scan[3], ss_step[3], ss_lane[3], ss_load[3], ss_wd[3], ss_gsh[3], ss_gi[3];
static bool frozen = false;
static long t = 0;  // the chips' time: MCLK cycles from the log's first FM clock enable

static void drive() {
  int rst = 0, cen = 0, wr_n = 0, addr = 0, din = 0, scan = 0, step = 0, lane = 0, load = 0, gsh = 0, gi = 0;
  uint64_t wd = 0;
  for (int i = 0; i < 3; i++) {
    rst |= in[i].rst << i;
    cen |= (!frozen && t % 7 == 0) << i;
    wr_n |= !(in[i].wr && !frozen) << i;
    addr |= in[i].addr << (2 * i);
    din |= in[i].din << (8 * i);
    scan |= ss_scan[i] << i; step |= ss_step[i] << i; load |= ss_load[i] << i;
    lane |= ss_lane[i] << (4 * i); wd |= (uint64_t)ss_wd[i] << (16 * i);
    gsh |= ss_gsh[i] << i; gi |= ss_gi[i] << i;
  }
  top->rst = rst; top->cen = cen; top->wr_n = wr_n; top->addr = addr; top->din = din;
  top->ss_scan = scan; top->ss_step = step; top->ss_lane = lane; top->ss_load = load;
  top->ss_wd = wd; top->ss_gsh = gsh; top->ss_gi = gi;
  top->eval();
}
static int go(int i) { return top->ss_go >> i & 1; }
static int tap(int i) { return top->ss_tap >> (16 * i) & 0xFFFF; }
static int slot(int i) { return top->slot >> (5 * i) & 31; }

// ---- the log ----
struct Ev { long t; char k; int a, d; };
static std::vector<Ev> evs;
static size_t ev_i = 0;
static Feed logfeed;

static void play_log() {  // the log's changes at time t
  while (ev_i < evs.size() && evs[ev_i].t <= t) {
    const Ev &e = evs[ev_i++];
    if (e.k == 'W') { logfeed.wr = 1; logfeed.addr = e.a; logfeed.din = e.d; }
    else if (e.k == 'E') logfeed.wr = 0;
    else if (e.k == 'R') logfeed.rst = e.a;
  }
}

// ---- C's own writes: random registers, notes, the DAC ----
static uint64_t rng = 1;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)rng; }
static long scr_next = 0, scr_rst_end = 0;
static int scr_reg = -1, scr_part = 0;
static void scramble_start() { scr_rst_end = t + 300; scr_next = t + 400; scr_reg = -1; }
static void scramble() {
  Feed &f = in[2];
  f.wr = 0;
  f.rst = t < scr_rst_end;
  if (f.rst || t < scr_next) return;
  if (scr_reg < 0) {
    static const int regs[] = {0x22, 0x24, 0x25, 0x26, 0x27, 0x28, 0x28, 0x2A, 0x2A, 0x2B};
    int r = rnd() % 4 ? 0x30 + rnd() % (0xB7 - 0x30) : regs[rnd() % 10];
    scr_part = r < 0x30 ? 0 : rnd() & 1;
    scr_reg = r;
    f.wr = 1; f.addr = scr_part * 2; f.din = r;
  } else {
    int d = rnd() & 0xFF;
    if (scr_reg == 0x27) d &= 0xCF;  // no timer resets that would wait for nothing
    f.wr = 1; f.addr = scr_part * 2 + 1; f.din = d;
    scr_reg = -1;
  }
  scr_next = t + 60 + rnd() % 300;
}

// ---- the freeze and the scan ----
static int CHAIN = 0;
static bool twice_a = false;
static int gaps = 0, gap_chain = 1, gap_loop = 1, gap_at = -1;  // (--gap-at K: one gap only, after chain move K)  // (--gaps-in chain|loop|both)       // --gaps N: N idle clocks in scan mode after every 16 chain moves and every step, as the console's stream has  // --twice: A read out twice at each save point
// --spoil: one bit put wrong into C, to see the check fail (chain bit K, or
// lane L's word at step S, its bit B)
static int spoil_bit = -1, spoil_lane = -1, spoil_step = 0, spoil_mask = 1;
struct State { std::vector<int> bits, words; };

// The freeze comes at the slot boundary halfway through a sample: three
// clocks after A's clock enable has moved its slot counter to op 2, ch 0
// (slot 12 of 24), the prescaler quiet again, and no write being made.
static const int FREEZE_SLOT = 2 << 3 | 0;

static void scan_out(int src, int dst, State &st, bool also[3]) {
  // src is read; dst (or -1) takes what comes out; copies in also[] are
  // read too, each rotating its own (for the twice-over comparison)
  for (int i = 0; i < 3; i++) ss_scan[i] = also[i] || i == src || i == dst;
  drive(); for (int k = 0; k < 4; k++) tick();
  std::vector<State> own(3);
  for (int k = 0; k < CHAIN; k++) {
    for (int i = 0; i < 3; i++) if (ss_scan[i]) { ss_gsh[i] = 1; ss_gi[i] = go(i); }
    if (dst >= 0) ss_gi[dst] = go(src) ^ (k == spoil_bit);
    for (int i = 0; i < 3; i++) if (also[i] || i == src) own[i].bits.push_back(go(i));
    drive(); tick();
    if (gaps && gap_chain && (gap_at >= 0 ? k == gap_at : k % 16 == 15)) {
      for (int i = 0; i < 3; i++) { ss_gsh[i] = 0; ss_gi[i] = 0; }
      drive(); for (int g = 0; g < gaps; g++) tick();
    }
  }
  for (int i = 0; i < 3; i++) { ss_gsh[i] = 0; ss_gi[i] = 0; }
  drive(); tick();
  for (int lane = 0; lane < 12; lane++)
    for (int s = 0; s < 24; s++) {
      for (int i = 0; i < 3; i++) ss_lane[i] = lane;
      drive();
      for (int i = 0; i < 3; i++) if (also[i] || i == src) own[i].words.push_back(tap(i));
      if (dst >= 0) { ss_load[dst] = 1; ss_wd[dst] = tap(src) ^ (lane == spoil_lane && s == spoil_step ? spoil_mask : 0); }
      for (int i = 0; i < 3; i++) if (ss_scan[i]) ss_step[i] = 1;
      drive(); tick();
      for (int i = 0; i < 3; i++) { ss_step[i] = 0; ss_load[i] = 0; }
      if (gaps && gap_loop) { drive(); for (int g = 0; g < gaps; g++) tick(); }
    }
  drive(); tick(); tick();
  for (int i = 0; i < 3; i++) ss_scan[i] = 0;
  drive(); tick(); tick();
  st = own[src];
  if (also[0] || also[1] || also[2]) {
    for (int i = 0; i < 3; i++) if (also[i] && i != src && (own[i].bits != st.bits || own[i].words != st.words)) {
      size_t k = 0;
      while (k < st.bits.size() && own[i].bits[k] == st.bits[k]) k++;
      if (k < st.bits.size()) printf("   copy %c's chain differs from %c's at bit %zu\n", 'A' + i, 'A' + src, k);
      else {
        k = 0;
        while (k < st.words.size() && own[i].words[k] == st.words[k]) k++;
        printf("   copy %c's loops differ from %c's at lane %zu step %zu: %04x against %04x\n", 'A' + i, 'A' + src,
               k / 24, k % 24, own[i].words[k], st.words[k]);
      }
      st.bits.clear();  // marks the failure
    }
  }
}

static void write_state(const std::string &path, const State &st) {
  std::vector<uint8_t> f(256 + 1536, 0);
  for (size_t k = 0; k < st.bits.size() && k < 256 * 8; k++)
    if (st.bits[k]) f[k / 8] |= 0x80 >> (k % 8);
  for (size_t k = 0; k < st.words.size() && k < 768; k++) {
    f[256 + 2 * k] = st.words[k] >> 8;
    f[256 + 2 * k + 1] = st.words[k] & 0xFF;
  }
  FILE *o = fopen(path.c_str(), "wb");
  if (o) { fwrite(f.data(), 1, f.size(), o); fclose(o); }
}

// the chain's length: a pattern shifted through C, frozen
static int measure_chain() {
  std::vector<int> sent, got;
  ss_scan[2] = 1; drive(); tick(); tick();
  for (int k = 0; k < 2000; k++) {
    int b = rnd() & 1;
    got.push_back(go(2)); sent.push_back(b);
    ss_gsh[2] = 1; ss_gi[2] = b; drive(); tick();
  }
  ss_gsh[2] = 0; ss_scan[2] = 0; drive(); tick();
  for (int d = 1; d < 1500; d++) {
    bool ok = true;
    for (int k = d; k < 2000 && ok; k++) ok = got[k] == sent[k - d];
    if (ok) return d;
  }
  return 0;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  std::string log, out = ".";
  int saves = 6;
  double until = 0;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--saves" && i + 1 < argc) saves = atoi(argv[++i]);
    else if (a == "--out" && i + 1 < argc) out = argv[++i];
    else if (a == "--twice" && i + 1 < argc) twice_a = atoi(argv[++i]);
    else if (a == "--gaps" && i + 1 < argc) gaps = atoi(argv[++i]);
    else if (a == "--gap-at" && i + 1 < argc) gap_at = atoi(argv[++i]);
    else if (a == "--gaps-in" && i + 1 < argc) { std::string v = argv[++i]; gap_chain = v != "loop"; gap_loop = v != "chain"; }
    else if (a == "--until" && i + 1 < argc) until = atof(argv[++i]);
    else if (a == "--seed" && i + 1 < argc) rng = strtoull(argv[++i], nullptr, 10) | 1;
    else if (a == "--spoil" && i + 1 < argc) {
      std::string v = argv[++i];
      if (v.rfind("chain:", 0) == 0) spoil_bit = atoi(v.c_str() + 6);
      else if (sscanf(v.c_str(), "lane:%d:%d:%d", &spoil_lane, &spoil_step, &spoil_mask) == 3) spoil_mask = 1 << spoil_mask;
      else { fprintf(stderr, "--spoil chain:K or lane:L:S:B\n"); return 2; }
    }
    else if (a[0] == '+') continue;
    else log = a;
  }
  if (log.empty()) { fprintf(stderr, "usage: Vbench <writes.log> [--saves K] [--out DIR] [--seed S]\n"); return 2; }
  FILE *f = fopen(log.c_str(), "r");
  if (!f) { fprintf(stderr, "cannot open %s\n", log.c_str()); return 1; }
  char line[128];
  while (fgets(line, sizeof line, f)) {
    Ev e{0, line[0], 0, 0};
    if (e.k == 'W') sscanf(line + 2, "%ld %d %x", &e.t, &e.a, &e.d);
    else if (e.k == 'E') sscanf(line + 2, "%ld", &e.t);
    else if (e.k == 'R') sscanf(line + 2, "%ld %d", &e.t, &e.a);
    else continue;
    evs.push_back(e);
  }
  fclose(f);
  if (evs.empty()) { fprintf(stderr, "%s: no writes\n", log.c_str()); return 1; }
  long nwrites = 0;
  for (auto &e : evs) nwrites += e.k == 'W';
long end = evs.back().t + 53693181 / 4;  // a quarter of a second after the last write
  if (until > 0 && until * 53693181 < end) end = (long)(until * 53693181);

  top = new Vbench;
  for (int i = 0; i < 3; i++) in[i] = Feed();
  drive();
  for (int k = 0; k < 100; k++) { drive(); tick(); }
  // out of reset and frozen, as at a save
  in[2].rst = 0; frozen = true;
  for (int k = 0; k < 100; k++) { drive(); tick(); }
  CHAIN = measure_chain();
  frozen = false; in[2].rst = 1;
  printf("%s: %ld writes, %.1f s; the chain is %d bits\n", log.c_str(), nwrites, end / 53693181.0, CHAIN);
  fflush(stdout);
  if (!CHAIN) { printf("0 of %d saves ok (no chain)\n", saves); return 1; }

  enum { SCRAMBLED, SYNCED } c_mode = SCRAMBLED;
  enum { NONE, SAVE, AGAIN } want = NONE;
  scramble_start();
  int done = 0, ok = 0, k_save = 0, countdown = -1;
  long next_save = end / (saves + 1), window_end = -1;
  long samples = 0, compared = 0, save_at = 0;
  bool c_bad = false, ab_bad = false, freeze_bad = false, c_said = false, ab_said = false;

  while (t < end || want != NONE) {
    play_log();
    in[0] = in[1] = logfeed;
    if (c_mode == SYNCED) in[2] = logfeed; else scramble();
    drive();
    int pre = top->clk_en & 1, old_sample = top->snd_sample & 1;
    tick(); t++;
    if ((top->snd_sample & 1) && !old_sample) samples++;

    // A and B always, C once it is loaded
    uint64_t L = top->snd_left, R = top->snd_right;
    auto same = [&](int i, int j) {
      return (L >> 16 * i & 0xFFFF) == (L >> 16 * j & 0xFFFF) && (R >> 16 * i & 0xFFFF) == (R >> 16 * j & 0xFFFF)
          && (top->dout >> 8 * i & 0xFF) == (top->dout >> 8 * j & 0xFF)
          && (top->irq_n >> i & 1) == (top->irq_n >> j & 1) && (top->snd_sample >> i & 1) == (top->snd_sample >> j & 1);
    };
    bool ab = same(0, 1), ac = c_mode != SYNCED || same(0, 2);
    if (c_mode == SYNCED) compared++;
    if ((!ab && !ab_said) || (!ac && !c_said))
{
      printf("   differs at sample %ld (time %ld):", samples, t);
      for (int i = 0; i < 3; i++)
        printf("%s %c sound %04x/%04x dout %02x irq_n %d sample %d%s", i ? "," : "", 'A' + i,
               (int)(L >> 16 * i & 0xFFFF), (int)(R >> 16 * i & 0xFFFF), (int)(top->dout >> 8 * i & 0xFF),
               (int)(top->irq_n >> i & 1), (int)(top->snd_sample >> i & 1), i == 2 ? "\n" : "");
    }
    if (!ab) ab_bad = ab_said = true;
    if (!ac) c_bad = c_said = true;

    if (want == NONE && c_mode == SCRAMBLED && k_save < saves && t >= next_save && !logfeed.rst) want = SAVE;
    if (want == NONE && c_mode == SYNCED && t >= window_end) want = AGAIN;
    if (want == NONE) continue;
    if (countdown < 0) { if (pre && slot(0) == FREEZE_SLOT) countdown = 3; continue; }
    if (--countdown > 0) continue;
    countdown = -1;
    if (in[0].wr || in[2].wr || logfeed.wr) continue;  // a write under way: the next sample's
    if ((top->pre_clk_en | top->clk_en) & 7) freeze_bad = true;

    frozen = true;
    State st;
    if (want == SAVE) {
      // A out and into C, B frozen as long
bool none[3] = {false, false, false};
      scan_out(0, 2, st, none);
      // (a second read of A at once, as a save then a load's own read do)
      if (twice_a) {
        State again;
        scan_out(0, -1, again, none);
        size_t nb = 0;
        for (size_t k = 0; k < st.bits.size(); k++) nb += again.bits[k] != st.bits[k];
        printf("   A read twice: %zu chain bits differ%s\n", nb, again.words != st.words ? ", and loop words" : "");
        if (nb) { printf("   at"); for (size_t k = 0; k < st.bits.size(); k++) if (again.bits[k] != st.bits[k]) printf(" %zu", k); printf("\n"); }
      }
      // at once, C read back: what went in must come out, bit for bit
      State back;
      scan_out(2, -1, back, none);
      if (back.bits != st.bits || back.words != st.words) {
        size_t nb = 0, nw = 0;
        for (size_t k = 0; k < st.bits.size(); k++) nb += back.bits[k] != st.bits[k];
        for (size_t k = 0; k < st.words.size(); k++) nw += back.words[k] != st.words[k];
        printf("   read back from C at once: %zu chain bits and %zu loop words differ\n", nb, nw);
        c_bad = true;
      }
      c_mode = SYNCED; compared = 0; save_at = samples;
      window_end = std::min(t + (end - t) / (saves - k_save + 1) * 2 / 3, end - 1);
      printf("save %d at sample %ld: A scanned out and into C, B frozen as long\n", k_save + 1, samples);
    } else {
      // twice over: the three read again, each going round its own
      bool all3[3] = {true, true, true};
      scan_out(0, -1, st, all3);
      bool same_state = !st.bits.empty();
      char name[64]; snprintf(name, sizeof name, "/ym2612_%d.bin", k_save + 1);
      write_state(out + name, st);
      k_save++; done++;
      bool pass = !c_bad && !ab_bad && same_state && !freeze_bad;
      ok += pass;
      printf("   %s: %ld samples (%.2f s) with A, B and C %s; read again, the three states %s\n",
             pass ? "ok" : "FAILED", samples - save_at, compared / 53693181.0, c_bad || ab_bad ? "NOT the same" : "the same",
             same_state ? "the same" : "NOT the same");
      if (freeze_bad) printf("   the prescaler was not quiet at a freeze\n");
      printf("%d of %d\n", done, saves);
      c_mode = SCRAMBLED; c_bad = c_said = false;
      scramble_start();
      next_save = t + (end - t) / (saves - k_save + 1) / 3;
    }
    fflush(stdout);
    frozen = false;
    want = NONE;
  }
  printf("%d of %d saves ok\n", ok, saves);
  top->final();
  delete top;
  return ok == saves && done == saves ? 0 : 1;
}
