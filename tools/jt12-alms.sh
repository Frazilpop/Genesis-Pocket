#!/bin/sh
# What the YM2612's scan costs: jt12 alone through Quartus 21.1 (in Docker,
# as tools/build.sh runs it), fitted twice on the Pocket's 5CEBA4F23C8 with
# the core's own synthesis and fitter settings and every pin virtual: as
# rtl/jt12 is at a git revision (HEAD by default) and as it is now.
#   sh tools/jt12-alms.sh [rev]
# Prints the ALMs, registers, RAM blocks and clk's slack at 53.69 MHz for each.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
rev=${1:-HEAD}
out=$repo/build/jt12_alms
image=raetro/quartus:21.1
rm -rf "$out"; mkdir -p "$out/before" "$out/now"
(cd "$repo" && git archive "$rev" src/fpga/core/rtl/jt12) | tar x -C "$out/before" --strip-components 4
cp -R "$repo/src/fpga/core/rtl/jt12" "$out/now/"

for v in before now; do
    d=$out/$v
    {
        echo 'set_global_assignment -name FAMILY "Cyclone V"'
        echo 'set_global_assignment -name DEVICE 5CEBA4F23C8'
        echo 'set_global_assignment -name TOP_LEVEL_ENTITY jt12'
        echo 'set_global_assignment -name QIP_FILE jt12/jt12.qip'
        echo 'set_global_assignment -name SDC_FILE jt12.sdc'
        echo 'set_instance_assignment -name VIRTUAL_PIN ON -to *'
        # the core's own (src/fpga/ap_core.qsf)
        grep -E 'OPTIMIZATION_MODE|ADV_NETLIST_OPT_SYNTH_WYSIWYG_REMAP|SYNTH_PROTECT_SDC|PRE_MAPPING_RESYNTHESIS|OPTIMIZATION_TECHNIQUE|PHYSICAL_SYNTHESIS|FITTER_EFFORT|ROUTER_LCELL|ROUTER_TIMING_OPTIMIZATION|FITTER_AGGRESSIVE' \
            "$repo/src/fpga/ap_core.qsf" | grep -v '^#'
    } > "$d/jt12.qsf"
    echo 'create_clock -name clk -period 18.624 [get_ports clk]' > "$d/jt12.sdc"
    : > "$d/jt12.qpf"
done

if ! colima status >/dev/null 2>&1; then
    echo "== starting Colima"
    colima start
    touch "$HOME/.colima/started-for-build"
fi
n=0
for v in before now; do
    n=$((n+1)); echo "$n of 2: jt12 $v"
    docker run --rm --platform linux/amd64 -v "$out/$v":/build -w /build "$image" \
        sh -c 'quartus_map jt12 && quartus_fit jt12 && quartus_sta jt12' > "$out/$v/quartus.log" 2>&1 \
        || { grep -E "^Error" "$out/$v/quartus.log" | head -20; exit 1; }
done
python3 -I - "$out" <<'EOF'
import re, sys, os
out = sys.argv[1]
rows = {}
for v in ("before", "now"):
    fit = open(os.path.join(out, v, "output_files" if os.path.isdir(os.path.join(out, v, "output_files")) else "", "jt12.fit.summary")).read()
    sta = open(os.path.join(out, v, "output_files" if os.path.isdir(os.path.join(out, v, "output_files")) else "", "jt12.sta.summary")).read()
    get = lambda k: re.search(re.escape(k) + r"\s*:\s*([\d,]+)", fit).group(1).replace(",", "")
    slacks = [float(s) for typ, s in re.findall(r"Type\s*:\s*(.+?)\nSlack\s*:\s*(-?[\d.]+)", sta) if "Setup" in typ]
    rows[v] = (int(get("Logic utilization (in ALMs)")), int(get("Total registers")), int(get("Total RAM Blocks")), min(slacks))
for v, (a, r, m, s) in rows.items():
    print(f"   {v:<7} {a:5} ALMs  {r:5} registers  {m:3} RAM blocks  worst setup slack {s:+.3f} ns")
a0, a1 = rows["before"][0], rows["now"][0]
print(f"== the scan adds {a1 - a0} ALMs, {rows['now'][1] - rows['before'][1]} registers, {rows['now'][2] - rows['before'][2]} RAM blocks")
EOF
