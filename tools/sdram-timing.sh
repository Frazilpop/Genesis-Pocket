#!/bin/bash
# The SDRAM's answer against the time it really has. A read taken from idle acks on
# the clk_ram edge halfway through clk_sys, so a word has one clk_ram period, 9.312 ns,
# whatever the .sdc lets the timing report allow.
# saves_ack is the save logic's own look at ack1, through ss_okB: nothing toggles the ack
# while the rest of that condition holds, so it may read short and it means nothing.
#   bash tools/sdram-timing.sh     after a build; reads build/quartus's db, out in build/sdram_timing
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/sdram_timing; rm -rf "$OUT"; mkdir -p "$OUT"
cat > "$OUT/paths.tcl" <<'EOF'
project_open ap_core
create_timing_netlist
read_sdc
foreach_in_collection op [get_available_operating_conditions] {
  set_operating_conditions $op
  update_timing_netlist
  set c [get_operating_conditions_info $op -name]
  foreach {name from to} {
    68000_word {*|sdram:sdram|dout*} {*|system:system|data* *|system:system|NO_DATA*}
    68000_ack  {*|sdram:sdram|ack1*} {*|system:system|data* *|system:system|NO_DATA* *|system:system|ROM_REQ* *|system:system|mstate*}
    saves_ack  {*|sdram:sdram|ack1*} {*|system:system|ss_* *|system:system|lp_* *|system:system|ch_pos* *|system:system|svp_pos*}
    svp_word   {*|sdram:sdram|dout*} {*|SVP:svp|*}
    svp_ack    {*|sdram:sdram|ack2*} {*|SVP:svp|*}
  } {
    report_timing -setup -npaths 1 -detail path_only -from [get_keepers $from] -to [get_keepers $to] -file /build/build/sdram_timing/$name-$c.txt
  }
}
project_close
EOF
docker run --rm --platform linux/amd64 -v "$PWD":/build -w /build/src/fpga raetro/quartus:21.1 quartus_sta -t /build/build/sdram_timing/paths.tcl > "$OUT/sta.log" 2>&1 \
  || { tail -5 "$OUT/sta.log"; exit 1; }
python3 -I - "$OUT" <<'EOF'
import glob, os, re, sys
# Quartus's slack, moved from the edges its relation uses to the one clk_ram period
print(f"{'path':<12} {'corner':<22} {'to spare in 9.312 ns':>21}")
for f in sorted(glob.glob(sys.argv[1] + '/*-*.txt')):
    name, corner = os.path.basename(f)[:-4].split('-', 1)
    t = open(f).read()
    slack = re.search(r'; Slack\s*;\s*(-?[\d.]+)', t)
    launch = re.search(r';\s*([\d.]+)\s*;\s*[\d.]+\s*;[^\n]*; launch edge time', t)
    latch = re.search(r';\s*([\d.]+)\s*;\s*[\d.]+\s*;[^\n]*; latch edge time', t)
    if slack and launch and latch:
        spare = float(slack.group(1)) - (float(latch.group(1)) - float(launch.group(1)) - 9.312)
        print(f"{name:<12} {corner:<22} {spare:+21.3f}" + ('' if spare >= 0 else '  short'))
EOF
