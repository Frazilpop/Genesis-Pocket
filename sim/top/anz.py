"""The Analogizer's pins (tools/top-test.sh --console ROM --anz ...) against the Pocket's frames.

    python3 -I sim/top/anz.py build/top-sim/console-new

For each anz_vNN.raw (the cartridge pins at every clk_sys edge over two frames, anz.svh)
it finds a whole frame and holds it against the Pocket's own frames of the same run
(f_NNNNN.hex), by the mode the run had on:

  0 RGBS, 1 RGsB  csync (active low) on the sync pin the mode uses, the other pin high;
                  each line's picture where /blank is high, a dot every 8 clocks (H40) or
                  10 (H32), the frame's colours at 6 bits; nothing lit in the blanking
  2 YPbPr         Y, Pb and Pr against vga_out's arithmetic on the same frame, csync on
                  the sync pin
  3, 4 Y/C        the luma against yc_out's sum on the same frame; the colour burst on
                  every line, its frequency (NTSC's 3.579545 or PAL's 4.43361875 MHz,
                  timed by the run's own clock) and where it lies, between hsync's end
                  and the picture's start
  5-9 the scandoubler  hsync at twice the line's rate, every line of the frame twice at
                  half a dot, one of the two dimmed by the scanlines' factor (0, 25, 50,
                  75 %; 9 as 5)

Prints a line a mode and exits non-zero if any check fails.
"""
import glob, math, os, re, sys

D = sys.argv[1]
fail = 0


def bad(msg):
    global fail
    fail += 1
    print('  FAILED:', msg)


frames = {}
for f in glob.glob(D + '/f_*.hex'):
    t = open(f).read().split()
    w, h = int(t[0]), int(t[1])
    frames[int(os.path.basename(f)[2:7])] = (w, h, [int(x, 16) for x in t[2:2 + w * h]])


def pins(path):
    raw = open(path, 'rb').read()
    b3, b2, b1, misc = raw[0::4], raw[1::4], raw[2::4], raw[3::4]
    return {'r': [x >> 2 for x in b3], 'hs': [x >> 1 & 1 for x in b3], 'vs': [x & 1 for x in b3],
            'g': [x & 63 for x in b2], 'blank': [x >> 6 & 1 for x in b2],
            'b': [(x & 31) << 1 | y >> 7 for x, y in zip(b1, b2)], 'out': list(misc), 'n': len(b3)}


def runs(bits, val=1):
    """(start, length) of each run of val"""
    out, i, n = [], 0, len(bits)
    while i < n:
        if bits[i] == val:
            j = i
            while j < n and bits[j] == val:
                j += 1
            out.append((i, j - i))
            i = j
        else:
            i += 1
    return out


def frame_lines(starts, line):
    """the lines of the first whole frame: a run of starts a line apart, after a gap"""
    groups, cur = [], []
    for s in starts:
        if cur and s - cur[-1] > line * 3 // 2:
            groups.append(cur)
            cur = []
        cur.append(s)
    groups.append(cur)
    whole = [g for g in groups[1:-1]] or groups[1:] or groups
    return max(whole, key=len) if whole else []


_conv = {}


def conv_rows(conv):
    """every Pocket frame as rows of what conv makes of its pixels, once"""
    if conv not in _conv:
        _conv[conv] = {n: [tuple(conv(px[y * fw + x]) for x in range(fw)) for y in range(fh)]
                       for n, (fw, fh, px) in frames.items()}
    return _conv[conv]


def best_frame(rows, w, conv):
    """the Pocket frame these rows of dots are, and how many dots differ"""
    best = None
    rows = [tuple(r) for r in rows]
    for n, want in sorted(conv_rows(conv).items()):
        if len(want[0]) != w or len(want) != len(rows):
            continue
        d = 0
        for got, wr in zip(rows, want):
            if got != wr:
                d += sum(a != b for a, b in zip(got, wr))
                if best is not None and d >= best[1]:
                    break
        if best is None or d < best[1]:
            best = (n, d)
        if d == 0:
            break
    return best


def find_frame(row_at, h, w, conv):
    """the Pocket frame whose every row is row_at(y), y from 0 to h, or None"""
    first = tuple(row_at(0))
    for n, want in sorted(conv_rows(conv).items()):
        if len(want) == h and len(want[0]) == w and want[0] == first and \
                all(tuple(row_at(y)) == want[y] for y in range(1, h)):
            return n
    return None


def c6(p):
    return (p >> 18 & 63, p >> 10 & 63, p >> 2 & 63)


def ypbpr(p):
    r, g, b = p >> 16 & 255, p >> 8 & 255, p & 255
    def lim(v):
        return 0 if v & (1 << 18) else 255 if v & (1 << 16) else v >> 8 & 255
    y = lim(77 * r + 150 * g + 29 * b)
    pb = lim((32768 - 42 * r - 85 * g + 128 * b) & 0x7FFFF)
    pr = lim((32768 + 128 * r - 106 * g - 21 * b) & 0x7FFFF)
    return (pr >> 2, y >> 2, pb >> 2)


def luma(p):
    r, g, b = p >> 16 & 255, p >> 8 & 255, p & 255
    return ((306 * r + 601 * g + 117 * b) >> 10 & 255) >> 2


report = {}
H = max(set(fh for _, fh, _ in frames.values()), key=lambda h: sum(1 for _, x, _ in frames.values() if x == h))
for txt in sorted(glob.glob(D + '/anz_v*.txt')):
    m = re.match(r'video (\d+) frames (\d+) (\d+) samples (\d+) ps (\d+) (\d+) h40 (\d) pal (\d)', open(txt).read())
    v, f0, f1, n, t0, t1, h40, pal = map(int, m.groups())
    clk = (t1 - t0) / (n - 1) * 1e-12          # seconds a clock, as the bench runs it
    # The bench's PLL keeps NTSC's period whatever K is written (sim/top/models.sv), so on
    # PAL's clock a burst is timed by the clock the hardware then runs at, 53.203424 MHz.
    if pal:
        clk = 1 / 53.203424e6
    dot = 8 if h40 else 10
    line = 3420
    p = pins(txt[:-4] + '.raw')
    name = {0: 'RGBS', 1: 'RGsB', 2: 'YPbPr', 3: 'Y/C NTSC', 4: 'Y/C PAL'}.get(v, f'scandoubler {v}')
    print(f'video {v} ({name}), {"H40" if h40 else "H32"}, {"PAL" if pal else "NTSC"} clock '
          f'{1 / clk / 1e6:.6f} MHz{" (the hardware\'s; the bench runs NTSC\'s period)" if pal else ""}, {n} clocks')
    if sum(p['out']) != n:
        bad('the video pins not outputs on every clock')

    if v in (0, 1, 2):
        sync = p['hs'] if v == 0 else p['vs']
        other = p['vs'] if v == 0 else p['hs']
        if any(x != 1 for x in other):
            bad('the other sync pin not held high')
        falls = [s for s, _ in runs(sync, 0)]
        gaps = [b - a for a, b in zip(falls, falls[1:])]
        lines_ok = sum(1 for g in gaps if g == line)
        print(f'  csync: {len(falls)} pulses, {lines_ok} a line apart, widths {sorted(set(l for _, l in runs(sync, 0)))[:4]}')
        if lines_ok < 400:
            bad('csync not a pulse a line')
        if v in (0, 1):
            pic = runs(p['blank'], 1)
            widths = sorted(set(l for _, l in pic))
            if widths != [(320 if h40 else 256) * dot]:
                bad(f'picture runs of {widths} clocks')
            lit_blank = sum(1 for i in range(n) if not p['blank'][i] and (p['r'][i] or p['g'][i] or p['b'][i]))
            if lit_blank:
                bad(f'{lit_blank} clocks lit in the blanking')
            starts = frame_lines([s for s, _ in pic], line)
            rows = [[(p['r'][s + k * dot + dot // 2], p['g'][s + k * dot + dot // 2], p['b'][s + k * dot + dot // 2])
                     for k in range(320 if h40 else 256)] for s in starts]
            # hsync's end to the picture's start, for Y/C below
            ends = [s + l for s, l in runs(sync, 0) if l < 400]
            porch = [s - max(e for e in ends if e <= s) for s in starts[:50] if any(e <= s for e in ends)]
            report['porch'] = min(porch) if porch else None
            report['porch_line'] = (starts[0] if starts else 0)
            best = best_frame(rows, 320 if h40 else 256, c6)
            print(f'  picture: {len(rows)} lines, frame {best[0] if best else "-"}, '
                  f'{best[1] if best else "-"} dots differ; hsync\'s end to the picture {report["porch"]} clocks')
            if not best or best[1]:
                bad('the picture is not the Pocket\'s frame')
        else:
            # YPbPr: no /blank to go by (held high), so the lines are found from RGBS's
            # geometry: the picture starts the same clocks after csync's rise, give or take
            # the arithmetic's three
            ends = [s + l for s, l in runs(sync, 0) if l < 400]
            porch = report.get('porch')
            W = 320 if h40 else 256
            found = None
            for e in ends:
                for delay in range(0, 8):
                    s0 = e + porch + delay
                    if s0 + H * line >= n:
                        break
                    row_at = lambda y, s0=s0: [(p['r'][s0 + y * line + k * dot + dot // 2], p['g'][s0 + y * line + k * dot + dot // 2],
                                                p['b'][s0 + y * line + k * dot + dot // 2]) for k in range(W)]
                    f = find_frame(row_at, H, W, ypbpr)
                    if f is not None:
                        found = (delay, f)
                        break
                if found:
                    break
            print(f'  Y, Pb, Pr: ' + (f'frame {found[1]}, every dot as vga_out makes it, {found[0]} clocks behind RGBS'
                                      if found else 'no frame matched'))
            if not found:
                bad('YPbPr is not the frame through vga_out')

    elif v in (3, 4):
        sync = p['hs']
        if any(x != 1 for x in p['vs']):
            bad('the other sync pin not held high')
        sync_runs = [(s, l) for s, l in runs(sync, 0) if l < 400]
        fsc = 4.43361875e6 if v == 4 else 3.579545e6
        freqs, spans = [], []
        for j, (s, l) in enumerate(sync_runs[20:-2]):
            e = s + l
            c = [p['r'][i] - 32 for i in range(e, e + 600)]
            on = [i for i, x in enumerate(c) if abs(x) >= 3]
            if not on:
                continue
            a, b = on[0], on[-1]
            if b > 500:   # chroma of the picture: not the burst
                b = max(i for i in on if i < 400)
            spans.append((a, b))
            # the frequency that best fits the line's burst: the peak of its spectrum near fsc,
            # found on a grid and refined (the burst's ends left out, where it ramps)
            seg = c[a + 4:b - 3]
            if len(seg) < 40 or j % 8:    # (the fit on every eighth line, for time)
                continue
            mean = sum(seg) / len(seg)
            seg = [x - mean for x in seg]
            def power(fr):
                re_ = sum(x * math.cos(2 * math.pi * fr * i * clk) for i, x in enumerate(seg))
                im_ = sum(x * math.sin(2 * math.pi * fr * i * clk) for i, x in enumerate(seg))
                return re_ * re_ + im_ * im_
            grid = [fsc * (0.9 + 0.002 * k) for k in range(101)]
            k = max(range(101), key=lambda k: power(grid[k]))
            lo, hi = grid[max(k - 1, 0)], grid[min(k + 1, 100)]
            for _ in range(30):   # golden-section on the peak
                m1, m2 = hi - (hi - lo) * 0.618, lo + (hi - lo) * 0.618
                if power(m1) < power(m2):
                    lo = m1
                else:
                    hi = m2
            freqs.append((lo + hi) / 2)
        porch = report.get('porch')
        last = max(b for _, b in spans) if spans else None
        f = sorted(freqs)[len(freqs) // 2] if freqs else 0
        print(f'  burst on {len(spans)} lines, {f / 1e6:.4f} MHz on {len(freqs)} of them (wanted {fsc / 1e6:.6f}), '
              f'clocks {min(a for a, _ in spans) if spans else "-"} to {last} after hsync ends, the picture at {porch}')
        if abs(f - fsc) / fsc > 0.002 or len(spans) < 400:
            bad('the burst is not the subcarrier on every line')
        if porch is None or last is None or last + 5 >= porch:
            bad('the burst runs into the picture')
        # luma: the frame's lines a line apart, from the first csync end with the picture
        ends = [s + l for s, l in sync_runs]
        W = 320 if h40 else 256
        found = None
        for e in ends:
            for delay in range(0, 16):
                s0 = e + porch + delay
                if s0 + H * line >= n:
                    break
                f = find_frame(lambda y, s0=s0: [p['g'][s0 + y * line + k * dot + dot // 2] for k in range(W)], H, W, luma)
                if f is not None:
                    found = (delay, f)
                    break
            if found:
                break
        print('  luma: ' + (f'frame {found[1]}, every dot as yc_out sums it, {found[0]} clocks behind' if found else 'no frame matched'))
        if not found:
            bad('the luma is not the frame through yc_out')

    else:
        lines = {5: 0, 6: 1, 7: 2, 8: 3, 9: 0}[v]
        coeff = [0x40, 0x3a, 0x2e, 0x1a][lines]
        hs = runs(p['hs'], 0)
        hs2 = runs(p['hs'], 1)
        pulses = hs if len(hs) > len(hs2) and min(l for _, l in hs) < 400 else hs2
        starts = [s for s, _ in pulses]
        gaps = sorted(set(b - a for a, b in zip(starts, starts[1:])))
        half = sum(1 for a, b in zip(starts, starts[1:]) if b - a in (line // 2 - 1, line // 2, line // 2 + 1))
        print(f'  hsync: {len(starts)} pulses, {half} half a line apart ({line // 2} clocks, '
              f'{1 / (line / 2 * clk) / 1e3:.2f} kHz)')
        if half < 800:
            bad('hsync not at twice the line rate')
        # every output line's dots at half a dot, from its hsync; then the frame's lines twice
        hd = dot // 2
        out_rows = []
        for s in starts[:-1]:
            seg = range(s, s + line // 2)
            first = next((i for i in seg if p['r'][i] or p['g'][i] or p['b'][i]), None)
            out_rows.append((s, first))
        # where the picture starts in an output line: found by taking a line with something
        # lit in it at every offset until it is one of a frame's rows, as it is or dimmed
        found = None
        w = 320 if h40 else 256
        sample = lambda s, o: tuple((p['r'][s + o + k * hd], p['g'][s + o + k * hd], p['b'][s + o + k * hd])
                                    for k in range(w))
        known = {}
        for f, want in sorted(conv_rows(c6).items()):
            if len(want[0]) == w:
                for row in want:
                    if len(set(row)) > 1:
                        known.setdefault(row, f)
                        known.setdefault(tuple(tuple(c * coeff >> 6 for c in t) for t in row), f)
        lit_line = next((s for s, f in out_rows if f is not None), None)
        offs = [o for o in range(0, line // 2 - w * hd) if lit_line is not None and sample(lit_line, o) in known]
        for off in offs[:3]:
            rows = [sample(s, off) for s, _ in out_rows]
            # pairs: a frame whose every line is two output lines in a row, one of them dimmed
            for f, want in sorted(conv_rows(c6).items()):
                if len(want[0]) != w:
                    continue
                fh = len(want)
                dim = [tuple(tuple(c * coeff >> 6 for c in t) for t in row) for row in want]
                for i in range(len(rows) - 2 * fh + 1):
                    if rows[i] != want[0] and rows[i] != dim[0]:
                        continue
                    if all({(rows[i + 2 * y], rows[i + 2 * y + 1])} & {(want[y], dim[y]), (dim[y], want[y])}
                           for y in range(fh)):
                        found = (f, i, off)
                        break
                if found:
                    break
            if found:
                break
        print('  picture: ' + (f'frame {found[0]}, every line twice at half a dot, one of each pair at {coeff}/64'
                              if found else 'no frame matched'))
        if not found:
            bad('the scandoubler\'s lines are not the frame\'s, each twice')

print('every mode right' if not fail else f'{fail} checks failed')
sys.exit(1 if fail else 0)
