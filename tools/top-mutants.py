#!/usr/bin/env python3
"""Is sim/top's bench looking? Each of these small mistakes in core_top.sv has to fail it.

    python3 -I tools/top-mutants.py [word]     after tools/top-test.sh --against, whose old hashes it compares with;
                                               a word in their names runs only those; MUT_FROM=N from the Nth

Each mutant is built and run in build/top-sim/mut/N, four at a time (MUT_JOBS=N for another number). A mutant passes the
bench's checks and its hashes match the unchanged file's only if the bench can't see it.
"""
import concurrent.futures, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = 'src/fpga/core'
MUTANTS = [
    ('a setting at the wrong address', "SET_SPRITES    = 32'h0000_0308", "SET_SPRITES    = 32'h0000_030C"),
    ('ROM bytes swapped', '.din0({ioctl_data[7:0], ioctl_data[15:8]})', '.din0(ioctl_data)'),
    ('Save size half', '32\'d131072', '32\'d65536'),
    ('A and B swapped', 'face[5:3], k[14], k[15], face[2:0]', 'face[5:3], k[14], k[15], face[0], face[1], face[2]'),
    ('Start and Mode swapped', 'face[5:3], k[14], k[15]', 'face[5:3], k[15], k[14]'),
    ('pad 3 from pad 2', 'console_pad(keys_3)', 'console_pad(keys_2)'),
    ('gun leaves Start on', "& ~{4'd0, lightgun_enabled, 7'd0}", ''),
    ('Europe auto never PAL', "(region_start == 2'd0 && region_only_europe)", "1'b0"),
    ('PAL 60 Hz ignored', "(says_pal && !pal_60_start)", "says_pal"),
    ('PAL 60 Hz reads NTSC', ".PAL_SAYS(says_pal)", ".PAL_SAYS(pal)"),
    ('PAL 60 Hz follows in play', "(says_pal && !pal_60_start)", "(says_pal && !cfg_pal_60)"),
    ('PAL 60 Hz at the wrong address', "SET_PAL_60     = 32'h0000_0114", "SET_PAL_60     = 32'h0000_0118"),
    ('row Japan as USA', "region_start == 2'd3 ? 2'd0 : region_req", "region_start == 2'd3 ? 2'd1 : region_req"),
    ('row of one bit', 'cfg_region          <= bridge_wr_data[1:0]', "cfg_region          <= {1'b0, bridge_wr_data[0]}"),
    ('region follows in play', 'always @(posedge clk_74a) if (!reset_n || slots_loading) {pal_60_start', 'always @(posedge clk_74a) {pal_60_start'),
    ('saved value missed before Reset Exit', 'if (!reset_n || slots_loading) {pal_60_start', 'if (slots_loading) {pal_60_start'),
    ('row missed by a load out of reset', 'if (!reset_n || slots_loading) {pal_60_start', 'if (!reset_n) {pal_60_start'),
    ('240 lines left at 60 Hz', "else if (&v30_time) pal_frame <= 1;", "else if (1'b0) pal_frame <= 1;"),
    ('240 lines for a moment', "else if (&v30_time) pal_frame <= 1;", "else if (v30_time[4]) pal_frame <= 1;"),
    ('240 lines kept for the next game', "\tif (cart_download) pal_frame <= 0;\n", ""),
    ('240 lines tells the game PAL', "wire says_pal = region_start", "wire says_pal = pal_frame || region_start"),
    ("a Memory's timing ignored", "\tif (ss_pal_take) {mem_pal_on, mem_pal} <= {1'b1, ss_pal_file};\n", ""),
    ("a Memory's timing kept past Reset Core", "cart_download || reset_core_s || &v30_time", "cart_download || &v30_time"),
    ("a Memory's timing kept for the next game", "cart_download || reset_core_s || &v30_time", "reset_core_s || &v30_time"),
    ("a load let go with the clock changing", ".pal_hold(pal_hold),", ".pal_hold(1'b0),"),
    ('reset ignores PAL hold', ' | region_set | pal_hold_s;', ' | region_set;'),
    ('load not held by save state', '| ss_hold_reset),', '),'),
    ('state size wrong', "32'h0003_4000", "32'h0003_8000"),
    ('long file not following', 'ss_long_file <= svp_quirk;', ''),
    ('H40 on a narrower slot', "{9'd0, mode[1], mode[0]}", "!mode[0] ? {9'd0, mode} : (mode[1] ? 11'd5 : 11'd4)"),
    ("the gun's d-pad step not 4", "dpad_aim_speed      = 8'd4", "dpad_aim_speed      = 8'd5"),
    ('slot 2 as 0', "{9'd0, mode[1], mode[0]}", "{9'd0, mode[1] & mode[0], mode[0]}"),
    ('H32 240 on H40\'s clock', "!resolution[0] ? clk_vid_256 : clk_vid_320", "resolution == 2'b00 ? clk_vid_256 : clk_vid_320"),
    ('HiFi PCM on at the start', 'reg        cfg_hifi_pcm        = 0;', 'reg        cfg_hifi_pcm        = 1;'),
    ('the 68000 sped up', ".TURBO(2'd0),", ".TURBO(2'd1),"),
    ('the YM2612 muted', ".ENABLE_FM(1'b1),", ".ENABLE_FM(1'b0),"),
    ('the PSG muted', ".ENABLE_PSG(1'b1),", ".ENABLE_PSG(1'b0),"),
    ('crosshair with the gun off', 'wire show_mark = lg_target_h != 0 && lightgun_enabled;', 'wire show_mark = lg_target_h != 0;'),
    ('crosshair never drawn', 'wire show_mark = lg_target_h != 0 && lightgun_enabled;', "wire show_mark = 1'b0;"),
    ('pads on another layout', 'face_buttons = {k[9], k[6], k[8], k[4], k[5], k[7]};', 'face_buttons = {k[10], k[7], k[6], k[11], k[5], k[4]};'),
    ('sprite limit on at the start', 'reg        cfg_many_sprites    = 0;', 'reg        cfg_many_sprites    = 1;'),
    ('crosshair blue on red', '{{8{lg_target_h[0]}}, {8{lg_target_h[1]}}, {8{lg_target_h[2]}}}', '{{8{lg_target_h[2]}}, {8{lg_target_h[1]}}, {8{lg_target_h[0]}}}'),
    ('black load not black', "ss_load_blank || anz_pocket_off ? 24'd0 : {red, green, blue}", "anz_pocket_off ? 24'd0 : {red, green, blue}"),
    ('FM chip not inverted', '.LADDER(~cfg_ym3438)', '.LADDER(cfg_ym3438)'),
    ('filter one bit', 'cfg_filter          <= bridge_wr_data[1:0]', 'cfg_filter          <= bridge_wr_data[0]'),
    ('reset free in menu', 'if (!osnotify_inmenu && reset_delay != 0)', 'if (reset_delay != 0)'),
    ('menu pause through a save', ' & ~ss_pause_lift', ''),
    ('game window not checked', "slots_loading && bridge_addr[31:28] == 4'h1", 'slots_loading'),
    ('reads from the wrong window', "32'h6xxxxxxx: bridge_rd_data <= save_read_data", "32'h6xxxxxxx: bridge_rd_data <= state_read_data"),
    ('DQM swapped', '.SDRAM_DQML(dram_dqm[0])', '.SDRAM_DQML(dram_dqm[1])'),
    ('the SVP on the 68000\'s data', '.dout2(rom_data2)', '.dout2()'),
    ('SNAC pads never reach the console', '{cont1_joy[15:0], key4, key3, key2, key1}',
     '{cont1_joy[15:0], cont4_key[15:0], cont3_key[15:0], cont2_key[15:0], cont1_key[15:0]}'),
    ('SNAC players 3 and 4 swapped', '.key3(key3),\n\t.key4(key4),', '.key3(key4),\n\t.key4(key3),'),
    ('the Pocket\'s screen not blacked for the Analogizer', 'ss_load_blank || anz_pocket_off ? 24\'d0', 'ss_load_blank ? 24\'d0'),
    ('the Analogizer told NTSC\'s clock always', '.pal(pal_s),', '.pal(1\'b0),'),
    ('the Analogizer told H32 always', '.h40(resolution[0]),', '.h40(1\'b0),'),
]

if len(sys.argv) > 1:
    MUTANTS = [m for m in MUTANTS if sys.argv[1] in m[0]]
FIRST = int(os.environ.get('MUT_FROM', '1'))
ALL = len(MUTANTS)
MUTANTS = MUTANTS[FIRST - 1:]   # MUT_FROM=N: from the Nth on, to finish a run cut short
src = open(os.path.join(ROOT, CORE, 'core_top.sv'), encoding='latin-1').read()
gone = [what for what, a, _ in MUTANTS if a not in src]   # a mistake whose line has since changed: say so before an hour's run
if gone:
    sys.exit('top-mutants.py: not in core_top.sv any more: ' + '; '.join(gone))
good = sorted(open(os.path.join(ROOT, 'build/top-sim/new/hash.log')).read().split('\n'))  # (order within a moment: the model's)
files = ['core_bridge_cmd.v', 'data_loader.sv', 'data_unloader.sv', 'sound_i2s.sv', 'sync_fifo.sv', 'save_layout.sv',
         'state_bridge.sv', 'video_hold.sv', 'pal_clock.sv', 'rtl/sdram.sv', 'rtl/cofi.sv', 'rtl/lightgun.sv',
         'pocket_analogizer.sv'] + ['../analogizer/' + f for f in (
             'openFPGA_Pocket_Analogizer.v', 'openFPGA_Pocket_Analogizer_SNAC.sv', 'vga_out_sw.v', 'clock_divider_fract.v',
             'pcengine_gc.v', 'pcengine_game_controller_multitap.v', 'yc_out.sv')] + [
         '../../../build/top-sim/anz/scandoubler_sim.v', '../../../build/top-sim/anz/serlatch_gc_sim.v']  # top-test.sh's copies
flags = ('--binary --timing -j 2 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-COMBDLY '
         '-Wno-LATCH -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-PROCASSWIRE -Wno-TIMESCALEMOD -Wno-SYMRSVDWORD -CFLAGS -O1 --top-module tb').split()
if 'pocket_analogizer' in src:
    flags.append('-DANZ')   # the bench's Analogizer part, as top-test.sh builds it


def one(args):
    n, (what, a, b) = args
    assert a in src, what
    d = os.path.join(ROOT, 'build/top-sim/mut', str(n))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    open(d + '/core_top.sv', 'w', encoding='latin-1').write(src.replace(a, b))
    subprocess.run(['python3', '-I', 'tools/top-settings.py', d + '/core_top.sv', 'dist/Cores/frazilpop.Genesis/interact.json', d],
                   cwd=ROOT, check=True, capture_output=True)
    r = subprocess.run(['verilator', *flags, '-Mdir', d + '/obj', '-I' + d, '-Isim/top', '-Isrc/fpga/core', 'sim/top/tb.sv',
                        'sim/top/models.sv', 'sim/top/system_stub.sv', d + '/core_top.sv'] +
                       [f'{CORE}/{f}' for f in files] + ['sim/save/dcfifo.sv', 'sim/genesis/synch_3.v'],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        return what, 'did not build', r.stdout[-300:]
    r = subprocess.run([d + '/obj/Vtb', f'+log={d}/hash.log'], cwd=ROOT, capture_output=True, text=True)
    fails = re.findall(r'^FAILED at \d+ ps: (.*)$', r.stdout, re.M)
    same = sorted(open(d + '/hash.log').read().split('\n')) == good if os.path.exists(d + '/hash.log') else False
    return what, 'SEEN' if fails or not same else 'NOT SEEN', (fails[0] if fails else 'hashes differ' if not same else '')


with concurrent.futures.ThreadPoolExecutor(int(os.environ.get("MUT_JOBS", "4"))) as ex:
    missed = 0
    for i, (what, verdict, note) in enumerate(ex.map(one, enumerate(MUTANTS)), 1):
        print(f'{i + FIRST - 1} of {ALL}  {verdict:<9} {what}: {note[:90]}', flush=True)
        missed += verdict != 'SEEN'
print(f'{len(MUTANTS) - missed} of {len(MUTANTS)} seen')
sys.exit(1 if missed else 0)
