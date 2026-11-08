"""The picture off the Pocket's video pins (tools/top-test.sh --console) against tools/sim.sh's.

    python3 -I sim/top/frames.py build/top-sim/console-new build/sim_genesis

For each of the sim's f_NNNNN.png, which of the bench's frames is the same picture. The two
start at different moments (the bench loads through the bridge first), so it looks at all
of them. Prints the frame found, or the nearest and how many pixels differ.
"""
import glob, importlib.util, os, sys

sys.dont_write_bytecode = True

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('compare', os.path.join(here, '..', 'genesis', 'compare.py'))
compare = importlib.util.module_from_spec(spec)
sys.argv, argv = sys.argv[:1], sys.argv
spec.loader.exec_module(compare)
sys.argv = argv
from pathlib import Path

pocket = {}
for f in sorted(glob.glob(sys.argv[1] + '/f_*.hex')):
    lines = open(f).read().split()
    w, h = int(lines[0]), int(lines[1])
    pocket[int(os.path.basename(f)[2:7])] = (w, h, [bytes(compare.LEVEL[b] for b in bytes.fromhex(x)) for x in lines[2:]])

bad = 0
for f in sorted(glob.glob(sys.argv[2] + '/f_*.png')):
    w, h, rows = compare.load(Path(f))      # colour levels, as the two tables differ by none here
    flat = b''.join(rows)
    want = [flat[i:i + 3] for i in range(0, w * h * 3, 3)]
    best = None
    for n, (ow, oh, px) in pocket.items():
        if (ow, oh) != (w, h):
            continue
        d = sum(a != b for a, b in zip(want, px))
        if best is None or d < best[1]:
            best = (n, d)
            if d == 0:
                break
    print(f'{os.path.basename(f)}: {w}x{h}: ' + (f'frame {best[0]}, {best[1]} pixels differ' if best else 'no frame of that size'))
    bad += not best or best[1] != 0
print('every picture found' if not bad else f'{bad} not found')
sys.exit(1 if bad else 0)
