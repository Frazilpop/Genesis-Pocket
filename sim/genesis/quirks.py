"""core_top.sv's quirks table, by cartridge serial, as C for sim/genesis/main.cpp.

    python3 -I quirks.py src/fpga/core/core_top.sv > quirks.inc

Read from core_top.sv each build, so the sim sets the quirks the core does. The
EP_ and C_ names are core_top.sv's localparams, also written out here.
"""
import re
import sys

src = open(sys.argv[1]).read()
for m in re.finditer(r'localparam \[2:0\] (.*?);', src):
    for name, value in re.findall(r'(\w+) = (\d+)', m[1]):
        print(f'#define {name} {value}')
for serial, name in re.findall(r'cart_id\s*==\s*"(.{8})"\s*\)\s*(\w+?)_quirk\s*<=\s*1', src):
    print(f'{{"{serial.replace("?", "\\?")}", "{name}", 0, 0}},')
# the serial save chips: a serial of seven is any eighth character
for m in re.finditer(r'cart_id(?:\[63:8\])?\s*==\s*"(.+?)"\s*\)\s*\{eeprom_map, eeprom_chip\}\s*<=\s*\{(EP_\w+),\s*(C_\w+)\s*\}', src):
    print(f'{{"{m[1]}", "eeprom", {m[2]}, {m[3]}}},')
