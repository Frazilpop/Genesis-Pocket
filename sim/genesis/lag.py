"""How many frames one run's pictures come after another's, from frames.txt.

    python3 -I sim/genesis/lag.py SIM/frames.txt REF/frames.txt [--every N] [--list]

Each file a line a frame, as sim/genesis/main.cpp writes it: number, WxH, CRC of
the picture. Every picture that is new in SIM (its CRC differs from the frame
before) is looked for in REF from the last match on: lag = its frame in SIM minus
the frame in REF where that picture also first came. A picture never in REF is
counted as no match, and matching goes on from the last that did. So a positive
lag is SIM later than REF; a run the same frame for frame gives 0 throughout.
"""
import sys


def read(p):
    out = []
    for l in open(p):
        f = l.split()
        if len(f) >= 3 and len(f[2]) == 8:   # (a run still going may end in half a line)
            out.append((int(f[0]), f[1], f[2]))
    return out


def lag(a, b, reach=400):
    res, j, prev = [], 0, None
    first = {}
    for k, (n, _, c) in enumerate(b):
        first.setdefault(c, []).append(k)
    for n, _, c in a:
        if c == prev:
            continue
        prev = c
        m = next((k for k in first.get(c, []) if j <= k <= j + reach), None)
        if m is None:
            res.append((n, None))
        else:
            res.append((n, n - b[m][0]))
            j = m
    return res


def main():
    args = [x for x in sys.argv[1:] if not x.startswith('--')]
    every = int(sys.argv[sys.argv.index('--every') + 1]) if '--every' in sys.argv else 60
    if '--every' in sys.argv:
        args = [x for x in args if x != str(every)]
    a, b = read(args[0]), read(args[1])
    res = lag(a, b)
    if '--list' in sys.argv:
        for n, d in res:
            print(n, d if d is not None else '-')
    last = a[-1][0]
    hit = [d for _, d in res if d is not None]
    print(f'{len(res)} new pictures in {last} frames, {len(res) - len(hit)} with no match'
          + (f'; lag {min(hit)} to {max(hit)}' if hit else ''))
    for start in range(0, last, every):
        w = [d for n, d in res if start < n <= start + every and d is not None]
        miss = sum(1 for n, d in res if start < n <= start + every and d is None)
        if w or miss:
            print(f'  frames {start + 1:5d}-{start + every:5d}: lag {min(w) if w else "-":>4} to {max(w) if w else "-":>4}, {len(w):3d} pictures' + (f', {miss} no match' if miss else ''))


if __name__ == '__main__':
    main()
