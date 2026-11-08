#!/bin/sh
# Several fitter seeds at once, each on its own copy of src/fpga, to find one that meets
# timing at a full fit; nothing goes to dist.
#
#   tools/seeds.sh 1 2 5      the seeds, compiled side by side in Docker (Colima holds three
#                             quartus_fit at once, counting any other build that is running)
#
# Each runs in build/seeds/sN (a copy of src/fpga with ap_core.qsf's SEED changed), its log
# build/seeds/sN.log; at the end a line a seed: the ALMs, RAM blocks, and the worst setup and
# hold of clk_sys and clk_ram over all corners. To take one, set SEED in ap_core.qsf and run
# tools/build.sh: the same source and seed give the same fit.
#
# A build this long belongs detached, as tools/build.sh does (the Air sleeps, background
# tasks end at two hours): perl -MPOSIX -e 'setsid; exec @ARGV' nohup sh tools/seeds.sh ...

set -eu
[ $# -gt 0 ] || { sed -n '2,14p' "$0"; exit 2; }
repo=$(cd "$(dirname "$0")/.." && pwd)
out=$repo/build/seeds
image=raetro/quartus:21.1
mkdir -p "$out"
colima status >/dev/null 2>&1 || { colima start; touch "$HOME/.colima/started-for-build"; }

for s in "$@"; do
    d=$out/s$s
    rm -rf "$d"
    mkdir -p "$d"
    rsync -a --exclude db --exclude incremental_db --exclude output_files "$repo/src/fpga/" "$d/"
    sed -i '' "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED $s/" "$d/ap_core.qsf"
    grep -q "^set_global_assignment -name SEED $s" "$d/ap_core.qsf"
    echo "seed $s: building in $d"
    docker run --rm --platform linux/amd64 -v "$repo":/build -w "/build/build/seeds/s$s" \
        "$image" quartus_sh --flow compile ap_core > "$out/s$s.log" 2>&1 &
done
wait

for s in "$@"; do
    python3 -I - "$out/s$s/output_files" "$s" <<'EOF'
import os, re, sys
out, seed = sys.argv[1], sys.argv[2]
try:
    fit = open(os.path.join(out, "ap_core.fit.summary")).read()
    sta = open(os.path.join(out, "ap_core.sta.summary")).read()
except OSError:
    print(f"seed {seed}: no reports (see build/seeds/s{seed}.log)")
    sys.exit(0)
alms = re.search(r"Logic utilization \(in ALMs\)\s*:\s*(.+)", fit).group(1).strip()
ram = re.search(r"Total RAM Blocks\s*:\s*(.+)", fit).group(1).strip()
worst = {}
for typ, slack in re.findall(r"Type\s*:\s*(.+?)\nSlack\s*:\s*(-?[\d.]+)", sta):
    m = re.match(r"(.+?) Model (Setup|Hold) '(.+)'", typ)
    if m:
        k = (m.group(3), m.group(2))
        worst[k] = min(worst.get(k, 99.0), float(slack))
def w(n, kind):
    v = [s for (c, k), s in worst.items() if k == kind and f"counter[{n}]" in c]
    return f"{min(v):+.3f}" if v else "-"
met = all(s >= 0 for s in worst.values())
print(f"seed {seed}: {alms}, RAM {ram}; clk_sys setup {w(0, 'Setup')} hold {w(0, 'Hold')}, "
      f"clk_ram setup {w(1, 'Setup')} hold {w(1, 'Hold')}; " + ("timing met" if met else "NOT met"))
EOF
done
