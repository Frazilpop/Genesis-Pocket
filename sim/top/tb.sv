// core_top.sv on its own: the Pocket on one side (a bridge's writes and reads, the
// host's commands, the pads) and the console on the other (system_stub.sv, or the
// real one with CONSOLE), with the real loaders, FIFOs and memory controller between.
//
// Two things come out. Its own checks: does a ROM reach the SDRAM and read back, a save
// round trip, every setting and pad reach its port? And a hash per clock domain of
// every port the file drives, as a line every so many clocks, so two versions of
// core_top.sv can be held against each other clock for clock (tools/top-test.sh).
`timescale 1ps/1ps
`include "settings.vh"
module tb;
    typedef struct packed {
        logic reset_n; logic [1:0] lpf; logic fm, psg, loading, pal, pal_says, export_, fifo, sram00;
        logic [2:0] emap, echip; logic noram, pier, svp, fmbusy, schan; logic [1:0] turbo; logic j3;
        logic [11:0] joy1, joy2, joy3, joy4; logic [2:0] multitap; logic gun, guntype; logic [24:1] romsz;
        logic hifi, ladder, sprites, pause;
    } seen_t;
    seen_t s;

    reg clk_74a = 0;
    initial begin #1; forever #6734 clk_74a = ~clk_74a; end

    // ---- what the console's stand-in takes from here ----
    reg  [1:0] video_mode = 2'b01;
    reg        interlaced = 0, transparent = 0, rom_readers = 0;
    reg        pll_busy = 0;
    reg [31:0] pll_k = 0;
    int        pll_starts = 0, state_written = 0;
    bit        console_loading = 0;   // the stand-in: a state's file going in, the console stopped till it is let go

    // ---- the Pocket's pins ----
    reg  [31:0] bridge_addr = 0, bridge_wr_data = 0;
    reg         bridge_rd = 0, bridge_wr = 0;
    wire [31:0] bridge_rd_data;
    wire        bridge_endian_little;
    reg  [15:0] cont1_key = 0, cont2_key = 0, cont3_key = 0, cont4_key = 0;
    reg  [31:0] cont1_joy = 32'h80808080;
    reg  [15:0] cont1_trig = 0;

    wire [12:0] dram_a;
    wire  [1:0] dram_ba, dram_dqm;
    wire [15:0] dram_dq;
    wire        dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;
    wire [23:0] video_rgb;
    wire        video_rgb_clock, video_rgb_clock_90, video_de, video_skip, video_vs, video_hs;
    wire        audio_mclk, audio_dac, audio_lrck;

    sdram_chip chip (.clk(dram_clk), .a(dram_a), .ba(dram_ba), .dq(dram_dq), .dqm(dram_dqm),
                     .ras_n(dram_ras_n), .cas_n(dram_cas_n), .we_n(dram_we_n));

    wire [7:0] tb2, tb1, tb3; wire [7:4] tb0; wire tp30, tp31, tsi, tso, tsck, tsd, sda;
    wire tb2d, tb3d, tb1d, tb0d, tp30d, tp31d, tp30r;
    wire [15:0] c0dq, c1dq, sdq;

    core_top ic (
        .clk_74a(clk_74a), .clk_74b(clk_74a),
        .cart_tran_bank2(tb2), .cart_tran_bank2_dir(tb2d), .cart_tran_bank3(tb3), .cart_tran_bank3_dir(tb3d),
        .cart_tran_bank1(tb1), .cart_tran_bank1_dir(tb1d), .cart_tran_bank0(tb0), .cart_tran_bank0_dir(tb0d),
        .cart_tran_pin30(tp30), .cart_tran_pin30_dir(tp30d), .cart_pin30_pwroff_reset(tp30r),
        .cart_tran_pin31(tp31), .cart_tran_pin31_dir(tp31d),
        .port_ir_rx(1'b0), .port_ir_tx(), .port_ir_rx_disable(),
        .port_tran_si(tsi), .port_tran_si_dir(), .port_tran_so(tso), .port_tran_so_dir(),
        .port_tran_sck(tsck), .port_tran_sck_dir(), .port_tran_sd(tsd), .port_tran_sd_dir(),
        .cram0_a(), .cram0_dq(c0dq), .cram0_wait(1'b0), .cram0_clk(), .cram0_adv_n(), .cram0_cre(), .cram0_ce0_n(),
        .cram0_ce1_n(), .cram0_oe_n(), .cram0_we_n(), .cram0_ub_n(), .cram0_lb_n(),
        .cram1_a(), .cram1_dq(c1dq), .cram1_wait(1'b0), .cram1_clk(), .cram1_adv_n(), .cram1_cre(), .cram1_ce0_n(),
        .cram1_ce1_n(), .cram1_oe_n(), .cram1_we_n(), .cram1_ub_n(), .cram1_lb_n(),
        .dram_a(dram_a), .dram_ba(dram_ba), .dram_dq(dram_dq), .dram_dqm(dram_dqm), .dram_clk(dram_clk), .dram_cke(dram_cke),
        .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n),
        .sram_a(), .sram_dq(sdq), .sram_oe_n(), .sram_we_n(), .sram_ub_n(), .sram_lb_n(),
        .vblank(1'b0), .dbg_tx(), .dbg_rx(1'b0), .user1(), .user2(1'b0), .aux_sda(sda), .aux_scl(), .vpll_feed(),
        .video_rgb(video_rgb), .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90),
        .video_de(video_de), .video_skip(video_skip), .video_vs(video_vs), .video_hs(video_hs),
        .audio_mclk(audio_mclk), .audio_adc(1'b0), .audio_dac(audio_dac), .audio_lrck(audio_lrck),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr), .bridge_rd(bridge_rd),
        .bridge_rd_data(bridge_rd_data), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .cont1_key(cont1_key), .cont2_key(cont2_key), .cont3_key(cont3_key), .cont4_key(cont4_key),
        .cont1_joy(cont1_joy), .cont2_joy(32'h80808080), .cont3_joy(32'h80808080), .cont4_joy(32'h80808080),
        .cont1_trig(16'h0), .cont2_trig(16'h0), .cont3_trig(16'h0), .cont4_trig(16'h0)
    );

    // ---- the hashes: every port the file drives, on the clock it belongs to ----
    longint h[0:5];
    int     h_n[0:5];
    int     log_fd = 0;
    longint win_from = -1, win_to = -1;
    string  gname[0:5] = '{"console", "dram", "video", "audio", "bridge", "pins"};
    initial for (int i = 0; i < 6; i++) begin h[i] = 64'hCBF29CE484222325; h_n[i] = 0; end

    function automatic void note(input int g, input logic [420:0] v);
        longint x = h[g];
        for (int i = 0; i < 421; i += 32) x = (x ^ longint'(v[i +: 32])) * 64'h100000001B3;
        h[g] = x;
        h_n[g]++;
        if (log_fd != 0) begin
            if ((h_n[g] & 16'hFFFF) == 0) $fdisplay(log_fd, "%0d %s %0d %h", $time, gname[g], h_n[g], x);
            if (win_from >= 0 && $time >= win_from && $time <= win_to) $fdisplay(log_fd, "W %0d %s %h", $time, gname[g], v);
        end
    endfunction

    always @(posedge ic.clk_ram) note(1, {dram_a, dram_ba, dram_dqm, dram_cke, dram_ras_n, dram_cas_n, dram_we_n, dram_dq});
    always @(posedge video_rgb_clock) note(2, {video_rgb, video_de, video_skip, video_vs, video_hs});
    always @(negedge video_rgb_clock_90) note(2, {video_rgb, video_de, video_skip, video_vs, video_hs, 1'b1});
    always @(posedge clk_74a) note(3, {audio_mclk, audio_dac, audio_lrck});
    always @(posedge clk_74a) note(4, {bridge_rd_data, bridge_endian_little});
    wire [57:0] pins = {tb2d, tb3d, tb1d, tb0d, tp30d, tp31d, tp30r,
                        tb2, tb1, tb3, tb0, tp30, tp31, tsi, tso, tsck, tsd, sda, c0dq, sdq[0]};
    always @(posedge clk_74a) note(5, pins);

    `include "anz.svh"

    // ---- checks ----
    int checks = 0, failed = 0;
    // a game never runs while the clock is being changed: in reset, or stopped by a load
    // that hasn't been let go (a state made at the other timing, state_bridge.sv)
    always @(negedge clk_74a) if (pll_busy && s.reset_n && !console_loading) begin failed++; if (failed < 40) $display("FAILED at %0d ps: the console out of reset with the clock changing", $time); end
    task automatic ok(input bit cond, input string what);
        checks++;
        if (!cond) begin failed++; if (failed < 40) $display("FAILED at %0d ps: %s", $time, what); end
    endtask

    // ---- the bridge, as the Pocket drives it: a word at a time, with room between ----
    task automatic tick(input int n); repeat (n) @(negedge clk_74a); endtask
    task automatic bwr(input [31:0] a, input [31:0] d, input int gap = 8);
        @(negedge clk_74a); bridge_addr = a; bridge_wr_data = d; bridge_wr = 1;
        @(negedge clk_74a); bridge_wr = 0;
        tick(gap);
    endtask
    task automatic brd(input [31:0] a, output [31:0] d, input int gap = 8);
        @(negedge clk_74a); bridge_addr = a; bridge_rd = 1;
        @(negedge clk_74a); bridge_rd = 0;
        tick(gap);
        d = bridge_rd_data;
    endtask
    logic [31:0] host_44, host_48;
    task automatic host(input [15:0] cmd, input [31:0] p0, input [31:0] p1, output [15:0] code);
        logic [31:0] r;
        int tries = 0;
        bwr(32'hF8000020, p0); bwr(32'hF8000024, p1);
        bwr(32'hF8000000, {16'h434D, cmd});
        do begin brd(32'hF8000000, r); tries++; end while (r[31:16] != 16'h4F4B && tries < 20000);
        ok(r[31:16] == 16'h4F4B, $sformatf("host command %h finished", cmd));
        code = r[15:0];
        brd(32'hF8000044, host_44); brd(32'hF8000048, host_48);
    endtask

    // ---- a game ----
    reg [7:0] rom [0:(1 << 21) - 1];
    int       rom_size = 0;
    function automatic [7:0] rom_byte(input int a);
        rom_byte = 8'(a ^ (a >> 8) ^ (a >> 3));
    endfunction
    task automatic make_rom(input string serial, input string regions, input int size,
                            input int ra = -1, input int first = 0, input int last = 0,
                            input int sp = -1, input int checksum = -1);
        rom_size = size;
        for (int i = 0; i < size; i++) rom[i] = rom_byte(i);
        for (int i = 'h180; i < 'h200; i++) rom[i] = 8'h20;
        for (int i = 0; i < 8 && i < serial.len(); i++) rom['h183 + i] = serial[i];
        for (int i = 0; i < regions.len() && i < 3; i++) rom['h1F0 + i] = regions[i];
        if (sp != -1) for (int i = 0; i < 4; i++) rom[i] = 8'(sp >> ((3 - i) * 8));
        if (checksum >= 0) begin rom['h18E] = 8'(checksum >> 8); rom['h18F] = 8'(checksum); end
        if (ra >= 0) begin
            rom['h1B0] = "R"; rom['h1B1] = "A"; rom['h1B2] = 8'(ra); rom['h1B3] = 8'h40;
            for (int i = 0; i < 4; i++) begin
                rom['h1B4 + i] = 8'(first >> ((3 - i) * 8));
                rom['h1B8 + i] = 8'(last >> ((3 - i) * 8));
            end
        end
    endtask

    int rom_words_seen[0:1], rom_words_bad[0:1];
    function automatic void rom_word(input logic [24:1] a, input logic [15:0] d, input int ch);
        if (!rom_readers || rom_size == 0) return;
        rom_words_seen[ch]++;
        if (d != {rom[{a[20:1], 1'b0}], rom[{a[20:1], 1'b1}]}) begin
            rom_words_bad[ch]++;
            if (rom_words_bad[ch] < 5) $display("ROM word at %h on channel %0d: %h, wanted %h%h", {a, 1'b0}, ch, d, rom[{a[20:1], 1'b0}], rom[{a[20:1], 1'b1}]);
        end
    endfunction
    function automatic logic [24:1] rom_next(input logic [24:1] a);
        rom_next = (int'(a) + 1) * 2 >= rom_size ? 24'd0 : a + 1'd1;
    endfunction

    task automatic write_rom();
        for (int i = 0; i < rom_size; i += 4)
            bwr(32'h10000000 + i, {rom[i], rom[i + 1], rom[i + 2], rom[i + 3]}, 41);
    endtask

    // The Pocket's start of a game: into reset, the table, the ROM, the save, out. Analogue's
    // documents have a saved setting written just before Reset Exit, with the core just
    // loaded and its registers as they start; row_before_exit is the region's rows that way.
    // row_before_load the rows already written as the game comes in. no_reset_enter a game
    // loaded with the core left running. The rows as one number: Region, and 4 for PAL 60 Hz.
    int row_before_exit = -1, row_before_load = -1;
    bit no_reset_enter = 0;
    longint anz_start_word = -1;   // analogizer.bin, loaded after the save as the Pocket does (anz.svh)
    task automatic rows_write(input int row, input int gap = 20);
        bwr(`A_REGION, row & 3, gap);
        bwr(`A_PAL_60, row >> 2 & 1, gap);
    endtask
    task automatic start_game(input int sav_size = 0);
        logic [15:0] code;
        logic [31:0] r;
        if (!no_reset_enter) host(16'h0010, 0, 0, code);
        if (row_before_exit >= 0) rows_write(0);
        if (row_before_load >= 0) rows_write(row_before_load);
        bwr(32'hF8002000, 32'd0); bwr(32'hF8002004, rom_size); bwr(32'hF8002008, 32'd10);
        host(16'h0082, 32'd0, rom_size, code);
        ok(code == 0, "the ROM's slot is granted");
        write_rom();
        tick(200);
        if (sav_size != 0) begin
            host(16'h0082, 32'd10, sav_size, code);
            ok(code == 0, "the save's slot is granted");
            for (int i = 0; i < sav_size; i += 4) begin
                automatic int w = i / 2;
                bwr(32'h60000000 + i, {8'(w), 8'(w >> 8), 8'(w + 2), 8'((w + 2) >> 8)}, 41);
            end
            tick(200);
        end
        if (anz_start_word >= 0) begin
            host(16'h0082, 32'd330, 32'd4, code);
            ok(code == 0, "analogizer.bin's slot is granted");
            anz_file(32'(anz_start_word));
        end
        host(16'h008F, 0, 0, code);
        if (row_before_exit >= 0) rows_write(row_before_exit);
        else wait_pal_settled();
        host(16'h0011, 0, 0, code);
        tick(2000);
        `ifndef CONSOLE
        ok(s.romsz == rom_size / 2, $sformatf("the game's size reaches the console: %h", s.romsz));
        `endif
    endtask

    task automatic wait_pal_settled();
        int starts;
        tick(100);
        // a change of clock takes the console out of reset only when it is over
        while (pll_busy) tick(100);
        tick(200);
    endtask

task automatic boot();
    logic [15:0] code;
    logic [31:0] r;
    wait (!pll_busy && ic.pll_core_locked); tick(100);
    // the target's "ready to run", answered
    do brd(32'hF8001000, r); while (r != 32'h636D0140);
    bwr(32'hF8001000, 32'h6F6B0000);
    host(16'h0000, 0, 0, code);
    ok(code == 3, "status: idle once booted");
    host(16'h00A0, 0, 0, code);
    ok(host_44 == 32'h40000000, "the state window's address");
    ok(host_48 == 32'h00044000, "before a game, the longer file");
    host(16'h00A4, 0, 0, code);
    ok(host_48 == 32'h00044000, "the most a load can be");
endtask

    `ifdef CONSOLE
    `include "console_run.svh"
    `else
    `include "scenario.svh"
    `endif

    // ---- the run ----
    initial begin
        string path;
        if ($value$plusargs("log=%s", path)) log_fd = $fopen(path, "w");
        void'($value$plusargs("from=%d", win_from));
        void'($value$plusargs("to=%d", win_to));
        run();
        if (log_fd != 0) begin
            for (int g = 0; g < 6; g++) $fdisplay(log_fd, "%0d %s %0d %h", $time, gname[g], h_n[g], h[g]);
            $fclose(log_fd);
        end
        $display("top-test: %0d checks, %0d failed", checks, failed);
        if (failed != 0) $fatal(1, "failed");
        $finish;
    end
endmodule
