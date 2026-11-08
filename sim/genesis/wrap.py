"""A wrapper round a chip GHDL translated to Verilog, so system.sv can use it.

    python3 -I wrap.py <ghdl.v> <entity.vhd> <module> <system.sv> [param=value ...]

GHDL names the translated top module as the VHDL entity and its ports as
the entity spells them; VHDL ignores case, so system.sv's instance may spell
them otherwise (the VDP's RST_N is system.sv's RST_n), and the ports' VHDL
defaults are gone, which system.sv relies on where it leaves a pin out (the
Z80's NMI_n). This renames the translated module <module>_ghdl in place and
prints a module <module> in front of it: its ports spelled as system.sv's
instance spells them, each VHDL default an SV input default. A generic GHDL
was given (-gT2Write=1) is fixed in the translation, so the wrapper takes it
as a parameter of that value only (system.sv's #(.T2Write(1))).
"""
import re
import sys


def header(v, name):
    m = re.search(r'^module\s+' + re.escape(name) + r'\s*\((.*?)\);', v, re.S | re.M)
    if not m:
        sys.exit(f'wrap.py: no module {name} in the translation')
    return m, [(d, (w or '').strip(), n) for d, w, n in
               re.findall(r'\b(input|output|inout)\s+(\[[^\]]+\]\s*)?(\w+)', m.group(1))]


def vhdl_defaults(src):
    src = re.sub(r'--[^\n]*', '', src)
    ent = re.search(r'\bentity\s+\w+\s+is.*?\bport\s*\((.*?)\)\s*;\s*end\b', src, re.S | re.I)
    out = {}
    if not ent:
        return out
    for decl in ent.group(1).split(';'):
        m = re.match(r'\s*([\w\s,]+?)\s*:\s*in\s+[^:]*?:=\s*(.+?)\s*$', decl, re.S | re.I)
        if not m:
            continue
        val = m.group(2)
        if re.fullmatch(r"'[01]'", val):
            sv = f"1'b{val[1]}"
        elif re.fullmatch(r"\(\s*others\s*=>\s*'[01]'\s*\)", val, re.I):
            sv = "'1" if "'1'" in val else "'0"
        elif re.fullmatch(r'"[01]+"', val):
            sv = f"{len(val) - 2}'b{val[1:-1]}"
        else:
            continue
        for n in m.group(1).split(','):
            out[n.strip().lower()] = sv
    return out


def spelling(system, module):
    s = re.sub(r'//[^\n]*', '', system)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    m = re.search(r'^\s*' + re.escape(module) + r'\s*(?:#\s*\([^;]*?\))?\s*\w+\s*\((.*?)\);', s, re.S | re.M)
    return {p.lower(): p for p in re.findall(r'\.(\w+)\s*\(', m.group(1))} if m else {}


def main():
    vfile, vhd, module, system, *params = sys.argv[1:]
    v = open(vfile).read()
    m, ports = header(v, module)
    defaults = vhdl_defaults(open(vhd).read())
    spell = spelling(open(system).read(), module)
    v = v[:m.start()] + re.sub(r'^module\s+' + re.escape(module) + r'\b', f'module {module}_ghdl', m.group(0)) + v[m.end():]

    ps = [p.split('=', 1) for p in params]
    lines = []
    for d, w, n in ports:
        dflt = defaults.get(n.lower()) if d == 'input' else None
        lines.append(f'\t{d} logic {w + " " if w else ""}{spell.get(n.lower(), n)}{" = " + dflt if dflt else ""}')
    out = [f'// {module}: GHDL\'s translation of the VHDL, below, as system.sv instantiates it (sim/genesis/wrap.py)',
           f'module {module}' + (' #(' + ', '.join(f'parameter {k} = {val}' for k, val in ps) + ')' if ps else '') + ' (',
           ',\n'.join(lines), ');']
    for k, val in ps:
        out.append(f'\tinitial if ({k} != {val}) $fatal(1, "{module}: translated with {k} = {val} only");')
    out.append(f'\t{module}_ghdl chip (' + ', '.join(f'.{n}({spell.get(n.lower(), n)})' for _, _, n in ports) + ');')
    out.append('endmodule\n')
    sys.stdout.write('\n'.join(out) + '\n' + v)


main()
