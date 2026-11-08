#!/bin/sh
# Genesis for Analogue Pocket: build the bitstream.
#
#   tools/build.sh           compile src/fpga/ap_core and package the bitstream
#   tools/build.sh --clean   empty db/ and incremental_db/ first, so Quartus's
#                            smart recompilation cannot skip a stage
#
# Runs Quartus Prime Lite 21.1 in Docker (raetro/quartus:21.1, linux/amd64)
# under Colima, as Kaneko16-Pocket's pocket/build.sh does. The project was
# last saved by 21.1.1 (ap_core.qsf's LAST_QUARTUS_VERSION). The repo is
# mounted whole; Colima shares $HOME only.
#
# Generated files stay under build/: db/, incremental_db/ and output_files/ in
# src/fpga are symlinks into build/quartus/, made here on first use. Analogue's
# pre-flow script rewrites apf/build_id.mif with the date on every compile; it
# is ignored, so a build leaves the tree clean.
#
# Afterwards the fit and the worst slack per clock are printed. Only when every
# clock meets timing is the bit-reversed bitstream the Pocket loads written to
# dist/Cores/frazilpop.Genesis/bitstream.rbf_r; otherwise the script fails,
# leaves dist alone and keeps the bitstream as build/quartus/bitstream.rbf_r.failed.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
fpga=$repo/src/fpga
qb=$repo/build/quartus
dist=$repo/dist/Cores/frazilpop.Genesis
image=raetro/quartus:21.1

clean=0
for arg in "$@"; do
    case "$arg" in
        --clean) clean=1 ;;
        -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
        *) echo "build.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

case "$repo" in
    "$HOME"/*) ;;
    *) echo "build.sh: the repository must be under \$HOME ($HOME); Colima shares nothing else." >&2
       exit 1 ;;
esac

# ------------------------------------------------------------ one at a time
# Two Quartus runs in one project write the same db/ and neither finishes
# cleanly. Two callers can start this script at once, so it takes
# a lock (mkdir is atomic); a lock left by a killed build is cleared once its
# pid is gone.
lock=$repo/build/build.lock
mkdir -p "$repo/build"
if ! mkdir "$lock" 2>/dev/null; then
    other=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
        echo "build.sh: another build is running (pid $other); not starting a second." >&2
        exit 1
    fi
    rm -rf "$lock"; mkdir "$lock"
fi
echo $$ > "$lock/pid"
trap 'rm -rf "$lock"' EXIT INT TERM

# ---------------------------------------------------- generated -> build/
mkdir -p "$qb/db" "$qb/incremental_db" "$qb/output_files"
for d in db incremental_db output_files; do
    if [ -L "$fpga/$d" ]; then
        :
    elif [ -e "$fpga/$d" ]; then
        echo "build.sh: $fpga/$d is a real directory; move it aside so it can be a link into build/." >&2
        exit 1
    else
        # relative, so it resolves the same inside the container
        ln -s "../../build/quartus/$d" "$fpga/$d"
    fi
done

if [ "$clean" = 1 ]; then
    echo "== clean: emptying $qb/db and $qb/incremental_db"
    find "$qb/db" "$qb/incremental_db" -mindepth 1 -delete
fi

# ------------------------------------------------------------- Colima
# Colima holds all the memory it was given while it is up. A build starts it
# when it is down and leaves a note that it did, so whatever looks after the
# machine can stop it after the last build. One started by hand has no note.
if ! colima status >/dev/null 2>&1; then
    echo "== starting Colima"
    colima start
    touch "$HOME/.colima/started-for-build"
fi

log=$qb/compile.log
echo "== Quartus 21.1 ($image)"
echo "   log: $log"
start=$(date +%s)
if ! docker run --rm --platform linux/amd64 \
        -v "$repo":/build -w /build/src/fpga \
        "$image" quartus_sh --flow compile ap_core > "$log" 2>&1; then
    echo "== COMPILE FAILED"
    grep -E "^Error|^ *Error \(" "$log" | head -40
    exit 1
fi
echo "   compiled in $(( $(date +%s) - start )) s"

crit=$(grep -c "^Critical Warning" "$log" || true)
if [ "$crit" != "0" ]; then
    echo "== $crit critical warning(s):"
    grep "^Critical Warning" "$log" | sort -u | head -20
fi

# ------------------------------------------------------------- bitstream
rbf=$qb/output_files/ap_core.rbf
[ -f "$rbf" ] || { echo "build.sh: no $rbf" >&2; exit 1; }
rbf_r=$qb/bitstream.rbf_r.new
python3 -I - "$rbf" "$rbf_r" <<'EOF'
import sys
# APF wants every byte of the .rbf bit-reversed (Analogue: Packaging a Core).
src, dst = sys.argv[1], sys.argv[2]
table = bytes(int(f"{b:08b}"[::-1], 2) for b in range(256))
data = open(src, "rb").read()
open(dst, "wb").write(data.translate(table))
print(f"== bitstream: {len(data)} bytes")
EOF

# ------------------------------------------------------------- reports
status=0
python3 -I - "$qb/output_files" <<'EOF' || status=$?
import os, re, sys
out = sys.argv[1]

fit = open(os.path.join(out, "ap_core.fit.summary")).read()
print("== fit (5CEBA4F23C8)")
for key in ("Logic utilization (in ALMs)", "Total registers", "Total pins",
            "Total block memory bits", "Total RAM Blocks", "Total DSP Blocks",
            "Total PLLs"):
    m = re.search(re.escape(key) + r"\s*:\s*(.+)", fit)
    if m:
        print(f"   {key:<28} {m.group(1).strip()}")

sta = open(os.path.join(out, "ap_core.sta.summary")).read()
worst = {}
for typ, slack in re.findall(r"Type\s*:\s*(.+?)\nSlack\s*:\s*(-?[\d.]+)", sta):
    m = re.match(r"(.+?) Model (Setup|Hold|Recovery|Removal|Minimum Pulse Width) '(.+)'", typ)
    if not m:
        continue
    corner, kind, clk = m.groups()
    k = (clk, kind)
    s = float(slack)
    if k not in worst or s < worst[k][0]:
        worst[k] = (s, corner)

# mf_pllbase's outputs (core_top.sv): the system clock, the SDRAM's, and the
# video clocks for the two horizontal resolutions
names = {
    "general[0]": "clk_sys 53.69",
    "general[1]": "clk_ram 107.39",
    "general[2]": "video 6.71 (H40)",
    "general[3]": "video 6.71/90",
    "general[4]": "video 5.37 (H32)",
    "general[5]": "video 5.37/90",
}
def label(clk):
    for k, v in names.items():
        if k in clk:
            return v
    return clk

print("== timing: worst slack per clock over all corners (ns)")
fail = False
for clk in sorted({c for c, _ in worst}, key=label):
    row = []
    for kind in ("Setup", "Hold", "Recovery", "Removal"):
        if (clk, kind) in worst:
            s, corner = worst[(clk, kind)]
            row.append(f"{kind.lower()} {s:+.3f}")
            if s < 0:
                fail = True
    print(f"   {label(clk):<22} " + "  ".join(row))
if fail:
    print("== NEGATIVE SLACK: timing is not met")
    sys.exit(1)
print("== timing met")
EOF

# ------------------------------------------------------------- dist
if [ "$status" != 0 ]; then
    mv "$rbf_r" "$qb/bitstream.rbf_r.failed"
    echo "== bitstream NOT written to dist" >&2
    exit 1
fi
mkdir -p "$dist"
mv "$rbf_r" "$dist/bitstream.rbf_r"
echo "== written: $dist/bitstream.rbf_r"
