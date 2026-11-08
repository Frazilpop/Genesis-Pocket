// A session on the Pocket, in the order the Pocket does things.
task automatic set(input [31:0] a, input [31:0] v); bwr(a, v, 20); tick(40); endtask

task automatic set_defaults();
    set(`A_REGION, 0); set(`A_PAL_60, 0); set(`A_UNUSED_10C, 0); set(`A_MULTITAP, 0); set(`A_LIGHTGUN, 0); set(`A_UNUSED_210, 1);
    set(`A_UNUSED_214, 3); set(`A_BUTTONS, 0); set(`A_UNUSED_208, 0); set(`A_UNUSED_300, 0); set(`A_COMPOSITE, 0);
    set(`A_SPRITES, 0); set(`A_UNUSED_400, 1); set(`A_UNUSED_404, 1); set(`A_HIFI, 0); set(`A_FILTER, 0); set(`A_FMCHIP, 0);
endtask

task automatic test_rom_reads(input string what);
    int w0 = rom_words_seen[0], w1 = rom_words_seen[1];
    rom_words_bad[0] = 0; rom_words_bad[1] = 0;
    rom_readers = 1;
    tick(30000);
    rom_readers = 0;
    tick(400);
    ok(rom_words_seen[0] > w0 + 50, {what, ": the 68000's channel answers"});
    ok(rom_words_seen[1] > w1 + 50, {what, ": the SVP's channel answers"});
    ok(rom_words_bad[0] == 0, {what, ": the 68000's channel reads the ROM"});
    ok(rom_words_bad[1] == 0, {what, ": the SVP's channel reads the ROM"});
endtask

task automatic test_settings();
    logic [31:0] r;
    // addresses no row uses answer nothing
    set(`A_UNUSED_10C, 2); ok(s.turbo == 0, "an unused address: the 68000 at its own speed");
    for (int i = 0; i < 5; i++) begin set(`A_MULTITAP, i); ok(s.multitap == i, "Multitap"); end
    set(`A_MULTITAP, 0);
    set(`A_UNUSED_400, 0); ok(s.fm, "an unused address: the YM2612 stays on");
    set(`A_UNUSED_404, 0); ok(s.psg, "an unused address: the PSG stays on");
    set(`A_HIFI, 1); ok(s.hifi, "HiFi PCM on"); set(`A_HIFI, 0); ok(!s.hifi, "HiFi PCM off");
    for (int i = 0; i < 4; i++) begin set(`A_FILTER, i); ok(s.lpf == i, "Audio Filter"); end
    set(`A_FILTER, 0);
    set(`A_FMCHIP, 0); ok(s.ladder, "YM2612, the ladder"); set(`A_FMCHIP, 1); ok(!s.ladder, "YM3438, none"); set(`A_FMCHIP, 0);
    set(`A_SPRITES, 1); ok(s.sprites, "High Sprite Limit on"); set(`A_SPRITES, 0); ok(!s.sprites, "High Sprite Limit off");
    set(`A_BUTTONS, 1); ok(s.j3, "3 Buttons"); set(`A_BUTTONS, 0); ok(!s.j3, "6 Buttons");
    set(`A_LIGHTGUN, 1); ok(s.gun, "Lightgun on"); set(`A_LIGHTGUN, 0); ok(!s.gun, "Lightgun off");
endtask

// {Z, Y, X, Mode, Start, B, C, A, Up, Down, Left, Right} from the Pocket's bits, on each pad
task automatic test_pads();
    // bit of cont_key for each bit of a JOY port, on the Pocket's own layout (input.json)
    int layout0[12] = '{3, 2, 1, 0, 7, 5, 4, 15, 14, 8, 6, 9};
    for (int p = 0; p < 4; p++)
        for (int b = 0; b < 12; b++) begin
            automatic logic [15:0] k = 16'(1) << layout0[b];
            automatic logic [11:0] want = 12'(1) << b;
            automatic logic [11:0] got;
            cont1_key = p == 0 ? k : 16'd0; cont2_key = p == 1 ? k : 16'd0; cont3_key = p == 2 ? k : 16'd0; cont4_key = p == 3 ? k : 16'd0;
            tick(30);
            got = p == 0 ? s.joy1 : p == 1 ? s.joy2 : p == 2 ? s.joy3 : s.joy4;
            ok(got == want, $sformatf("pad %0d, button %0d of the port: %h, wanted %h", p + 1, b, got, want));
        end
    cont1_key = 0; cont2_key = 0; cont3_key = 0; cont4_key = 0; tick(30);
    // an unused address leaves the Pocket's own layout
    set(`A_UNUSED_208, 2); cont1_key = 16'h0010; tick(30); ok(s.joy1 == 12'h040, "an unused address: face A is still B");
    cont1_key = 16'h0800; tick(30); ok(s.joy1 == 12'h000, "an unused address: R2 is nothing");
    cont1_key = 0; set(`A_UNUSED_208, 0); tick(30);
endtask

// a frame of the stand-in's picture is at most this many clocks of clk_74a (24 lines of H32)
task automatic frames(input int n); tick(n * 120000); endtask

task automatic test_video();
    for (int m = 0; m < 4; m++)
        for (int ar = 0; ar < 2; ar++) begin
            video_mode = 2'(m);
            set(`A_UNUSED_300, ar);
            frames(1);
        end
    video_mode = 2'b01; set(`A_UNUSED_300, 0);
    interlaced = 1; frames(2); interlaced = 0;
    // Composite Blend: off, full, adaptive with and without transparency seen
    set(`A_COMPOSITE, 1); frames(1);
    set(`A_COMPOSITE, 2); transparent = 1; frames(1); transparent = 0; frames(1);
    set(`A_COMPOSITE, 0);
    // the gun's crosshair over the picture, aimed from the stick and the d-pad: full red
    begin
        automatic int on_px, kept_px, off_px;
        set(`A_LIGHTGUN, 1); set(`A_UNUSED_214, 5);
        cont1_joy = 32'h80801230; frames(3);
        count_red(120000, on_px);
        cont1_key = 16'h0009; frames(2);
        cont1_key = 16'h0006; frames(2);
        cont1_key = 16'h8000; frames(1);
        cont1_key = 16'h0090; frames(1);
        cont1_key = 0;
        cont1_joy = 32'h80801232; frames(3);
        // a 0 at an unused address leaves the crosshair; the gun off takes it away
        set(`A_UNUSED_210, 0); frames(1);
        count_red(120000, kept_px);
        set(`A_LIGHTGUN, 0); frames(1);
        count_red(120000, off_px);
        ok(on_px > off_px + 20, $sformatf("the crosshair is drawn: %0d red pixels on, %0d with the gun off", on_px, off_px));
        ok(kept_px > off_px + 20, $sformatf("an unused address: %0d red pixels after a 0 there", kept_px));
        set(`A_UNUSED_214, 3);
    end
    // the d-pad walks the aim across a 320-wide picture a step at a time, to where the stick's
    // far right and bottom put it (lightgun.sv's lg_x, lg_y)
    begin
        automatic int last, big = 0, stick_x, stick_y;
        video_mode = 2'b01;
        set(`A_LIGHTGUN, 1); set(`A_UNUSED_214, 5);
        cont1_joy = 32'h8080FFFF; frames(3);
        stick_x = ic.lightgun.lg_x; stick_y = ic.lightgun.lg_y;
        cont1_joy = 32'h80801200; frames(3);
        last = ic.lightgun.lg_x;
        cont1_key = 16'h0008;
        for (int f = 0; f < 400; f++) begin   // (64 steps of 4 and some to spare)
            tick(20000);   // (less than a frame of the stand-in's, so one step at most between looks)
            if (ic.lightgun.lg_x - last > big) big = ic.lightgun.lg_x - last;
            last = ic.lightgun.lg_x;
        end
        cont1_key = 16'h0002; frames(70);
        cont1_key = 0;
        ok(last == stick_x, $sformatf("the d-pad reaches the right edge: x %0d, the stick's %0d", last, stick_x));
        ok(big <= 7, $sformatf("the d-pad walks the aim right a step at a time: %0d pixels at most", big));
        // the d-pad's step stays at 4 whatever an unused address is given
        ok(ic.lightgun.DPAD_AIM_SPEED == 4, $sformatf("the d-pad's step %0d after a 5 at an unused address", ic.lightgun.DPAD_AIM_SPEED));
        set(`A_UNUSED_214, 1); tick(30);
        ok(ic.lightgun.DPAD_AIM_SPEED == 4, $sformatf("the d-pad's step %0d after a 1 at an unused address", ic.lightgun.DPAD_AIM_SPEED));
        ok(ic.lightgun.lg_y == stick_y, $sformatf("the d-pad reaches the bottom: line %0d, the stick's %0d", ic.lightgun.lg_y, stick_y));
        set(`A_UNUSED_214, 3); set(`A_LIGHTGUN, 0);
    end
    cont1_joy = 32'h80808080;
endtask

task automatic count_red(input int ticks, output int n);
    n = 0;
    repeat (ticks) begin
        @(posedge clk_74a);
        if (video_de && video_rgb == 24'hFF0000) n++;
    end
endtask

// What the Pocket's scaler is told, on a blank line (Analogue's docs: bits 23:13 the slot)
task automatic test_scaler_slots();
    for (int m = 0; m < 4; m++)
        for (int ar = 0; ar < 2; ar++) begin
            automatic logic [10:0] got = 11'h7FF;
            automatic int seen = 0;
            video_mode = 2'(m);
            set(`A_UNUSED_300, ar);
            tick(8000);
            // the slot is on the bus when the data enable is low
            repeat (1500) begin
                @(posedge video_rgb_clock);
                if (!video_de) begin got = video_rgb[23:13]; seen++; end
            end
            // (a 1 at an unused address leaves H40 in the console's shape)
            ok(seen > 0 && int'(got) == m, $sformatf("the scaler's slot, mode %0d, %0d at an unused address: %0d", m, ar, got));
        end
    // and a line as wide as that slot, on the clock for its width, at either height
    for (int m = 0; m < 4; m++) begin
        automatic int px = 0, widest = 0;
        video_mode = 2'(m);
        tick(8000);
        repeat (6000) begin
            @(posedge video_rgb_clock);
            if (video_hs) px = 0;
            else if (video_de) begin px++; if (px > widest) widest = px; end
        end
        ok(widest == (m[0] ? 320 : 256), $sformatf("a line's width, mode %0d: %0d", m, widest));
    end
    video_mode = 2'b01; set(`A_UNUSED_300, 0);
endtask

task automatic test_save_128k();
    logic [31:0] r;
    logic [15:0] code;
    int bad = 0;
    // the file as start_game wrote it: bytes 2n the low byte of word n, odd bytes the high
    for (int i = 0; i < 32768; i++) begin
        automatic logic [7:0] lo = 8'((i * 2) >> 8);
        automatic logic [7:0] hi = 8'(((i * 2) + 2) >> 8);
        if (ic.system.bram[i] != {hi, lo}) begin
            bad++;
            if (bad < 4) $display("save RAM %0d: %h, wanted %h%h", i, ic.system.bram[i], hi, lo);
        end
    end
    ok(bad == 0, $sformatf("a 128 KB save reaches the save RAM (%0d words wrong)", bad));
    // the game writes: what it writes is what comes back
    for (int i = 0; i < 32768; i++) ic.system.bram[i] = 16'(i * 16'd40503);
    bad = 0;
    host(16'h0080, 32'd10, 0, code);
    ok(code == 0, "the save's slot read is granted");
    for (int i = 0; i < 131072; i += 4) begin
        automatic logic [15:0] ram = ic.system.bram[i / 4];
        brd(32'h60000000 + i, r, 60);
        if (r != {{2{ram[7:0]}}, {2{ram[15:8]}}}) begin bad++; if (bad < 4) $display("save out at %h: %h, wanted %h", i, r, {{2{ram[7:0]}}, {2{ram[15:8]}}}); end
    end
    ok(bad == 0, $sformatf("the save RAM comes back as 128 KB, each byte on its pair of words (%0d wrong)", bad));
    // the size the Pocket writes it at
    brd(32'hF800200C, r); brd(32'hF800200C, r);
    ok(r == 32'd131072, $sformatf("the data table says 128 KB for the save: %0d", r));
endtask

task automatic test_save_64k();
    logic [15:0] code;
    int bad = 0;
    host(16'h0010, 0, 0, code);
    host(16'h0082, 32'd10, 65536, code);
    for (int i = 0; i < 65536; i += 4)
        bwr(32'h60000000 + i, {8'(i), 8'(i >> 8), 8'(i + 3), 8'((i + 3) >> 8)}, 41);
    tick(200);
    host(16'h008F, 0, 0, code);
    host(16'h0011, 0, 0, code);
    tick(1000);
    // the older 64 KB layout: the RAM's bytes back to back, the first low
    for (int i = 0; i < 16384; i++) begin
        automatic int a = (i & ~1) * 2;
        automatic logic [15:0] want = i[0] ? {8'((a + 3) >> 8), 8'(a + 3)} : {8'(a >> 8), 8'(a)};
        if (ic.system.bram[i] != want) begin bad++; if (bad < 4) $display("64 KB save, word %0d: %h, wanted %h", i, ic.system.bram[i], want); end
    end
    ok(bad == 0, $sformatf("a 64 KB save goes in back to back (%0d wrong)", bad));
endtask

task automatic test_reset_action();
    // (its length is Shane Lynch's varying one, as short as 15 clocks, so looked at at once)
    bwr(`A_RESET, 1, 2);
    ok(!s.reset_n, "Reset Core puts the console in reset");
    begin
        automatic int n = 0;
        while (!s.reset_n && n < 2000000) begin tick(16); n += 16; end
        ok(s.reset_n, "and lets go of it");
    end
endtask

task automatic test_menu();
    logic [15:0] code;
    host(16'h00B0, 1, 0, code); tick(30);
    ok(!s.pause, "the menu doesn't pause with the setting off");
    bwr(`A_MENU_PAUSE, 1); tick(30);
    ok(s.pause, "the menu pauses with it on");
    host(16'h00B0, 0, 0, code); tick(30);
    ok(!s.pause, "and goes on when the menu closes");
    bwr(`A_MENU_PAUSE, 0); tick(30);
    // Reset Core waits for the menu to close
    host(16'h00B0, 1, 0, code); tick(30);
    set(`A_RESET, 1); tick(3000);
    ok(!s.reset_n, "Reset Core chosen in the menu");
    host(16'h00B0, 0, 0, code);
    begin
        automatic int n = 0;
        while (!s.reset_n && n < 2000000) begin tick(16); n += 16; end
        ok(s.reset_n, "it lets go once the menu has closed");
    end
endtask

logic [31:0] state_file [0:69631];
task automatic test_state(input int size);
    logic [15:0] code;
    logic [31:0] r;
    int tries = 0, bad = 0;
    host(16'h00A0, 0, 0, code);
    ok(host_48 == size, $sformatf("Savestate Start's size: %h, wanted %h", host_48, size));
    host(16'h00A0, 1, 0, code);
    do begin
        host(16'h00A0, 0, 0, code); tries++;
    end while (code == 1 && tries < 1000);
    ok(code == 2, $sformatf("Savestate Start ends ok: %0d", code));
    for (int i = 0; i < size; i += 4) begin
        brd(32'h40000000 + i, r, 88);
        state_file[i / 4] = r;
    end
    tick(2000);
    ok(state_file[0] != 0, "the file comes out");
    // and back in
    state_written = 0;
    for (int i = 0; i < size; i += 4) begin
        automatic logic [31:0] w = state_file[i / 4];
        bwr(32'h40000000 + i, w, 86);
    end
    tick(400);
    ok(!s.pause, "the console isn't paused for a state");
    tries = 0;
    host(16'h00A4, 1, 0, code);
    do begin
        host(16'h00A4, 0, 0, code); tries++;
    end while (code == 1 && tries < 1000);
    ok(code == 2, $sformatf("Savestate Load ends ok: %0d", code));
    ok(state_written > size / 2 - 40, $sformatf("the words reach the chips: %0d", state_written));
    tick(4000);
endtask

// the Pocket's menu is open as a Memory is made or chosen: the pause is lifted for it, and
// a load started with the core in the Pocket's reset, as a wake from Sleep can, runs regardless
task automatic test_state_with_menu(input int size);
    logic [15:0] code;
    logic [31:0] r;
    int tries = 0;
    bwr(`A_MENU_PAUSE, 1); host(16'h00B0, 1, 0, code); tick(30);
    ok(s.pause, "paused in the menu");
    host(16'h00A0, 1, 0, code);
    tick(30);
    ok(!s.pause, "the pause lifts for a save");
    do begin host(16'h00A0, 0, 0, code); tries++; end while (code == 1 && tries < 1000);
    for (int i = 0; i < 64; i += 4) brd(32'h40000000 + i, r, 88);
    host(16'h00A0, 0, 0, code);
    tick(100);
    // the reads have stopped: 2 s of clk_sys and it goes on by itself, which is more than
    // this bench wants to run, so the whole file is read
    for (int i = 64; i < size; i += 4) brd(32'h40000000 + i, r, 88);
    tick(2000);
    ok(s.pause, "and comes back when it's over");
    host(16'h00B0, 0, 0, code); bwr(`A_MENU_PAUSE, 0); tick(30);

    host(16'h0010, 0, 0, code);
    tick(30);
    ok(!s.reset_n, "the Pocket's reset reaches the console");
    for (int i = 0; i < 64; i += 4) begin automatic logic [31:0] w = state_file[i / 4]; bwr(32'h40000000 + i, w, 86); end
    tick(200);
    ok(s.reset_n, "a load's file out of the Pocket's reset, once its header matches");
    for (int i = 64; i < size; i += 4) begin automatic logic [31:0] w = state_file[i / 4]; bwr(32'h40000000 + i, w, 86); end
    tick(400);
    tries = 0;
    host(16'h00A4, 1, 0, code);
    do begin host(16'h00A4, 0, 0, code); tries++; end while (code == 1 && tries < 1000);
    ok(code == 2, $sformatf("that load ends ok: %0d", code));
    host(16'h0011, 0, 0, code);
    tick(1000);
    ok(s.reset_n, "and the console runs on");
endtask

task automatic test_state_refused();
    logic [15:0] code;
    int tries = 0;
    // not this game's: the game goes on and the load says so
    for (int i = 0; i < 256; i += 4) bwr(32'h40000000 + i, 32'hDEADBEEF, 60);
    tick(400);
    host(16'h00A4, 1, 0, code);
    do begin host(16'h00A4, 0, 0, code); tries++; end while (code == 1 && tries < 1000);
    ok(code == 3, $sformatf("a file from another game is refused: %0d", code));
endtask

// A state keeps its own timing (state_bridge.sv, core_top.sv's mem_pal): one made at 50 Hz
// loads into the game started at 60 and runs at 50, the clock changed with the console
// stopped and let go only after; and the other way. Reset Core and a new game go back to
// what the rows say.
task automatic state_out(input int size);
    logic [15:0] code;
    logic [31:0] r;
    int tries = 0;
    host(16'h00A0, 1, 0, code);
    do begin host(16'h00A0, 0, 0, code); tries++; end while (code == 1 && tries < 1000);
    ok(code == 2, $sformatf("Savestate Start ends ok: %0d", code));
    for (int i = 0; i < size; i += 4) begin brd(32'h40000000 + i, r, 88); state_file[i / 4] = r; end
    tick(2000);
endtask
task automatic state_in(input int size, output logic [15:0] code);
    int tries = 0;
    for (int i = 0; i < size; i += 4) begin automatic logic [31:0] w = state_file[i / 4]; bwr(32'h40000000 + i, w, 86); end
    tick(400);
    host(16'h00A4, 1, 0, code);
    do begin host(16'h00A4, 0, 0, code); tries++; end while (code == 1 && tries < 1000);
endtask
task automatic test_state_timing();
    logic [15:0] code;
    automatic int was;
    make_rom("T-TEST00", "E", 2048);
    set(`A_REGION, 0); set(`A_PAL_60, 0);
    start_game(); region_settled();
    ok(s.pal, "state timing: Europe alone at 50 Hz");
    state_out(32'h00034000);
    ok(state_file[1][15:0] == 16'h0001, $sformatf("the state made at 50 Hz says PAL: %h", state_file[1]));
    set(`A_PAL_60, 1);
    start_game(); region_settled();
    ok(!s.pal, "state timing: on PAL 60 Hz at 60");
    was = pll_starts;
    state_in(32'h00034000, code);
    ok(code == 2, $sformatf("a state made at 50 Hz loads at 60: %0d", code));
    ok(pll_starts == was + 1, $sformatf("the clock changes once for it: %0d", pll_starts - was));
    ok(s.pal, "and the game runs at 50 Hz");
    if (pll_starts != 0) ok(pll_k == 32'd2570680398, $sformatf("on PAL's K: %0d", pll_k));
    tick(4000);
    ok(s.reset_n && !pll_busy, "the game goes on");
    state_out(32'h00034000);
    ok(state_file[1][15:0] == 16'h0001, "a save after it is at 50 Hz");
    was = pll_starts;
    state_in(32'h00034000, code);
    ok(code == 2 && pll_starts == was, "a state at the timing it runs at leaves the clock");
    tick(4000);
    test_reset_action();
    region_settled();
    ok(!s.pal, "Reset Core: the rows again, 60 Hz");
    // the other way
    state_out(32'h00034000);
    ok(state_file[1][15:0] == 16'h0000, "a state made at 60 Hz says NTSC");
    set(`A_PAL_60, 0);
    start_game(); region_settled();
    ok(s.pal, "state timing: PAL 60 Hz off, 50 Hz");
    was = pll_starts;
    state_in(32'h00034000, code);
    ok(code == 2, $sformatf("a state made at 60 Hz loads at 50: %0d", code));
    ok(pll_starts == was + 1 && !s.pal, "on NTSC's clock");
    if (pll_starts != 0) ok(pll_k == 32'd2910634261, $sformatf("on NTSC's K: %0d", pll_k));
    tick(4000);
    ok(s.reset_n && !pll_busy, "the game goes on");
    start_game(); region_settled();
    ok(s.pal, "a new game: the rows again, 50 Hz");
endtask

// Region: what the header says, the rows as the game started, what the console and the clock
// make of it. row: Region's value, and 4 for PAL 60 Hz. want_auto_read: the header's 0 Japan,
// 1 USA, 2 Europe.
task automatic region_is(input int row, input bit want_auto_pal, input int want_auto_read, input string what);
    automatic int region = row & 3;
    automatic bit want_says = region == 2 || (region == 0 && want_auto_pal);
    automatic bit want_pal = want_says && !(row >> 2 & 1);
    automatic bit want_export = region == 3 ? 0 : region == 1 || region == 2 ? 1 : want_auto_read != 0;
    ok(s.pal == want_pal, $sformatf("%s, row %0d: PAL %0d", what, row, s.pal));
    ok(s.pal_says == want_says, $sformatf("%s, row %0d: a game reads PAL %0d", what, row, s.pal_says));
    ok(s.export_ == want_export, $sformatf("%s, row %0d: export %0d", what, row, s.export_));
    if (pll_starts != 0) ok(pll_k == (want_pal ? 32'd2570680398 : 32'd2910634261), $sformatf("%s, row %0d: K %0d", what, row, pll_k));
endtask

task automatic region_settled();
    automatic int n = 0;
    while ((pll_busy || !s.reset_n) && n < 200000) begin tick(100); n++; end
    tick(200);
    ok(s.reset_n, "the console lets go after the start");
endtask

task automatic test_region(input string regions, input bit want_auto_pal, input int want_auto_read);
    automatic int rows[8] = '{0, 4, 1, 2, 3, 6, 5, 7};
    automatic string name = $sformatf("header %s", regions);
    make_rom("T-TEST00", regions, 2048);
    foreach (rows[i]) begin
        // written just before Reset Exit, on a core just loaded
        row_before_exit = rows[i];
        start_game();
        row_before_exit = -1;
        region_settled();
        region_is(rows[i], want_auto_pal, want_auto_read, {name, ", saved"});
        // written before the game came in
        row_before_load = rows[i];
        start_game();
        row_before_load = -1;
        region_settled();
        region_is(rows[i], want_auto_pal, want_auto_read, {name, ", before the load"});
        // changed in play, to each of the others: nothing moves, and Reset Core doesn't read it
        foreach (rows[j]) if (j != i) begin
            automatic int was = pll_starts;
            rows_write(rows[j]);
            tick(400);
            ok(s.reset_n, $sformatf("%s, row %0d to %0d in play: no restart", name, rows[i], rows[j]));
            ok(pll_starts == was, $sformatf("%s, row %0d to %0d in play: the clock stays", name, rows[i], rows[j]));
            region_is(rows[i], want_auto_pal, want_auto_read, {name, ", in play"});
        end
        begin
            automatic int was = pll_starts;
            test_reset_action();
            tick(200);
            ok(pll_starts == was, $sformatf("%s, row %0d: Reset Core keeps the clock", name, rows[i]));
            region_is(rows[i], want_auto_pal, want_auto_read, {name, ", after Reset Core"});
        end
        // and the next start reads the last it was set to, even with no Reset Enter
        begin
            automatic int next = rows[(i + 1) % 8];
            rows_write(next);
            no_reset_enter = 1;
            start_game();
            no_reset_enter = 0;
            region_settled();
            region_is(next, want_auto_pal, want_auto_read, {name, ", a load out of reset"});
        end
    end
    set(`A_REGION, 0); set(`A_PAL_60, 0);
    start_game();
    region_settled();
endtask

// Every serial in the table, through a load of the first few KB
task automatic test_games();
    `include "games.svh"
endtask

task automatic game(input string serial, input int ra = -1, input int first = 0, input int last = 0);
    logic [15:0] code;
    make_rom(serial, "U", 1024, ra, first, last);
    start_game();
    tick(50);
endtask

task automatic run();
    make_rom("T-TEST00", "U", 'h10000);
    boot();
    ok(!s.sprites, "High Sprite Limit starts off, as the menu has it");
    ok(!s.hifi, "HiFi PCM starts off, as the menu has it");
    set_defaults();
    $display("Boot done, %0d ps", $time);

    start_game(131072);
    ok(s.reset_n, "the game runs");
    ok(!s.pal && s.export_, "USA: 60 Hz, export");
    test_rom_reads("first game");
    test_save_128k();
    $display("Game and save done, %0d ps", $time);

    test_settings();
    test_pads();
    $display("Settings and pads done, %0d ps", $time);
    test_video();
    test_scaler_slots();
    $display("Picture done, %0d ps", $time);
    test_reset_action();
    test_menu();
    $display("Reset and menu done, %0d ps", $time);

    test_state(32'h00034000);
    test_state_with_menu(32'h00034000);
    test_state_refused();
    $display("Save state done, %0d ps", $time);

    test_save_64k();
    $display("64 KB save done, %0d ps", $time);

    // the SVP's game: the longer file, read as the ROM goes in
    make_rom("MK-1229 ", "E", 'h4000);
    start_game();
    host_state_size(32'h00044000, "Virtua Racing");
    ok(s.svp, "Virtua Racing's quirk");
    ok(s.pal, "Europe alone: PAL by itself");
    while (pll_busy || !s.reset_n) tick(100);


    make_rom("T-TEST00", "U", 'h1000);
    start_game();
    host_state_size(32'h00034000, "and an ordinary game again");
    test_games();
    $display("Games done, %0d ps", $time);

    // last, as they differ from any revision that changed the region in play
    test_region("U",   0, 1);
    test_region("J",   0, 0);
    test_region("E",   1, 2);
    test_region("JE",  0, 2);
    test_region("JUE", 0, 1);
    test_region("4",   0, 1);
    test_region("8",   1, 2);
    test_region("1",   0, 0);
    test_region("F",   0, 1);
    test_240_lines("E", 4, 1, "240 lines, Europe alone on PAL 60 Hz");
    test_240_lines("U", 1, 1, "240 lines, United States");
    test_240_lines("JUE", 6, 1, "240 lines, Europe on PAL 60 Hz");
    test_240_lines("E", 0, 0, "240 lines, Europe alone at 50 Hz");
    $display("Regions done, %0d ps", $time);
    test_state_timing();
    set(`A_REGION, 0); set(`A_PAL_60, 0);
    $display("State timing done, %0d ps", $time);
    // last, as a revision with no Analogizer has none of it (top-test.sh --against: +no_anz)
    `ifdef ANZ
    if (!$test$plusargs("no_anz")) begin
        test_analogizer();
        $display("Analogizer done, %0d ps", $time);
    end
    `endif
endtask

// A game that turns on 240 lines at 60 Hz goes to 50 Hz, on any rows (core_top.sv's pal_frame):
// a moment of it doesn't, the clock changes with the console held, it reads what it read,
// Reset Core keeps it and the next game is as its rows say. At 50 Hz already nothing moves.
task automatic v30_held(input int clocks);
    for (int i = 0; i < clocks / 1000; i++) begin video_mode = 2'b11; tick(1000); end
    video_mode = 2'b01;
endtask
task automatic test_240_lines(input string regions, input int row, input bit at_60, input string what);
    automatic int was;
    make_rom("T-TEST00", regions, 2048);
    row_before_exit = row;
    start_game();
    row_before_exit = -1;
    region_settled();
    ok(s.pal == !at_60, $sformatf("%s: PAL %0d at the start", what, s.pal));
    begin
        automatic bit says = s.pal_says, export_ = s.export_;
        // as long as a frame of 240 lines at 60 Hz: nothing
        was = pll_starts;
        v30_held(2_400_000);
        tick(2000);
        ok(pll_starts == was && s.reset_n, $sformatf("%s: a frame of 240 lines leaves the clock", what));
        // turned on and left on
        v30_held(3_200_000);
        if (at_60) begin
            ok(pll_starts > was, $sformatf("%s: the clock changes", what));
            region_settled();
            ok(s.pal, $sformatf("%s: at 50 Hz", what));
            if (pll_starts != 0) ok(pll_k == 32'd2570680398, $sformatf("%s: K %0d", what, pll_k));
            ok(s.pal_says == says && s.export_ == export_, $sformatf("%s: the game reads what it read", what));
            test_reset_action();
            tick(200);
            ok(s.pal, $sformatf("%s: Reset Core keeps 50 Hz", what));
        end else
            ok(pll_starts == was && s.pal, $sformatf("%s: at 50 Hz already, nothing moves", what));
    end
    set(`A_REGION, 0); set(`A_PAL_60, 0);
    make_rom("T-TEST00", "U", 2048);
    start_game();
    region_settled();
    ok(!s.pal, {what, ": the next game is at 60 Hz"});
endtask

task automatic host_state_size(input int want, input string what);
    logic [15:0] code;
    tick(200);
    host(16'h00A0, 0, 0, code);
    ok(host_48 == want, $sformatf("%s: Savestate's size %h, wanted %h", what, host_48, want));
endtask

// ---- the Analogizer (pocket_analogizer.sv, anz.svh); ANZ when core_top.sv has it ----
`ifdef ANZ
// A JOY port's value from a word of the Pocket's controls (test_pads's layout)
function automatic [11:0] port_of(input [15:0] k);
    int layout0[12] = '{3, 2, 1, 0, 7, 5, 4, 15, 14, 8, 6, 9};
    port_of = 0;
    for (int b = 0; b < 12; b++) port_of[b] = k[layout0[b]];
endfunction

// the Pocket's own controls while SNAC stands in for some players, each told apart
localparam logic [15:0] CONT [0:3] = '{16'h0001, 16'h0002, 16'h0004, 16'h0008};

task automatic players_are(input [15:0] want [0:3], input string what);
    logic [11:0] got [0:3];
    tick(100000);  // a few of the pads' polls (SNES's 2,800 a second), and the synchronisers
    got = '{s.joy1, s.joy2, s.joy3, s.joy4};
    for (int p = 0; p < 4; p++)
        ok(got[p] == port_of(want[p]), $sformatf("%s: player %0d %h, wanted %h", what, p + 1, got[p], port_of(want[p])));
endtask

// press one button on each pad: n on pad 1 and n2 on pad 2 (-1 none), by their places in
// the pad's shift register; returns the words each pad stands for, in the Pocket's order
task automatic snac_press(input int n, input int n2, output logic [15:0] k1, output logic [15:0] k2);
    // each button's bit in the Pocket's order, by its place in the pad's shift register
    int snes[12] = '{5, 7, 14, 15, 0, 1, 2, 3, 4, 6, 8, 9};
    int nes[8]   = '{4, 5, 14, 15, 0, 1, 2, 3};
    int db15[12] = '{7, 6, 5, 4, 3, 2, 1, 0, 8, 9, 14, 15};            // D C B A Right Left Down Up E F Select Start
    int db15_p1[12] = '{0, 1, 2, 3, 4, 5, 6, 7, 13, 12, 14, 15};       // their places in the chain, pad 1
    int db15_p2[12] = '{20, 21, 22, 23, 8, 9, 10, 11, 17, 16, 18, 19}; // and pad 2
    k1 = 0; k2 = 0;
    anz_held = '{24'd0, 24'd0};
    if (anz_pad == 3) begin
        if (n >= 0)  begin anz_held[0][db15_p1[n]] = 1;  k1 = 16'(1) << db15[n];  end
        if (n2 >= 0) begin anz_held[0][db15_p2[n2]] = 1; k2 = 16'(1) << db15[n2]; end
    end else begin
        if (n >= 0)  begin anz_held[0][n] = 1;  k1 = 16'(1) << (anz_pad == 1 ? snes[n] : nes[n]);  end
        if (n2 >= 0) begin anz_held[1][n2] = 1; k2 = 16'(1) << (anz_pad == 1 ? snes[n2] : nes[n2]); end
    end
endtask

task automatic test_analogizer();
    logic [15:0] k1, k2;
    string kind [1:3] = '{"SNES", "NES", "DB15"};
    int    type_of [1:3] = '{3, 2, 1};
    int    buttons [1:3] = '{12, 8, 12};
    int    lit;
    // no file so far, the whole session: the slot the template's on every clock
    ok(anz_off_edges > 64'd10000000 && anz_idle_bad == 0,
       $sformatf("no analogizer.bin: the slot idle on all %0d clocks (%0d not)", anz_off_edges, anz_idle_bad));

    // a game started with a file, as the Pocket loads it, its save beside it: in, and on
    make_rom("T-TEST00", "U", 'h10000);
    anz_start_word = anz_word(3, 1, 2, 0);
    start_game(131072);
    anz_start_word = -1;
    ok(s.reset_n, "a game with analogizer.bin runs");
    ok(ic.analogizer.cfg == 16'(anz_word(3, 1, 2, 0)), $sformatf("analogizer.bin's word reaches the module: %h", ic.analogizer.cfg));
    ok(tb3d && tb2d && tb1d, "the Analogizer on: its video pins are outputs");
    test_save_128k();

    // the video codes, as the module takes them: 0-4 as they are, 5-8 its scandoubler with
    // scanlines 0-3, 9 (HQ2x, which it has not got) the scandoubler, the rest RGBS
    for (int v = 0; v < 16; v++) begin
        automatic int mv = v <= 4 ? v : v <= 9 ? 5 : 0, ml = v >= 5 && v <= 8 ? v - 5 : 0;
        anz_file(anz_word(0, 1, 0, v));
        ok(ic.analogizer.m_vtype == mv && ic.analogizer.m_lines == ml,
           $sformatf("video %0d: the module's %0d, scanlines %0d", v, ic.analogizer.m_vtype, ic.analogizer.m_lines));
        ok(ic.analogizer.phase_inc == (v == 4 ? 40'd90790223688 : 40'd73300775186),
           $sformatf("video %0d: the colour's step for NTSC's clock", v));
        ok(!ic.pal_s, "(on NTSC's clock)");
    end

    // the Pocket's own screen black on [14], with the adapter's picture going on
    anz_file(anz_word(0, 1, 0, 0, 1)); frames(1);
    count_lit(120000, lit);
    ok(lit == 0, $sformatf("the Pocket's screen off: %0d pixels lit", lit));
    count_adapter_lit(120000, lit);
    ok(lit > 1000, $sformatf("the Pocket's screen off: the adapter's picture on, %0d", lit));
    anz_file(anz_word(0, 1, 0, 0, 0)); frames(1);
    count_lit(120000, lit);
    ok(lit > 1000, $sformatf("the Pocket's screen on again: %0d pixels lit", lit));
    // [14] with the Analogizer off is nothing
    anz_file(anz_word(0, 0, 0, 0, 1)); frames(1);
    count_lit(120000, lit);
    ok(lit > 1000, $sformatf("[14] with the Analogizer off: the Pocket's screen on, %0d", lit));

    // SNAC pads, each kind: every button on pad 1 (and the next on pad 2) under SNAC 1, 2 to
    // players 1, 2, then one button each under every assignment
    {cont1_key, cont2_key, cont3_key, cont4_key} = {CONT[0], CONT[1], CONT[2], CONT[3]};
    for (int t = 1; t <= 3; t++) begin
        anz_pad = t;
        anz_file(anz_word(type_of[t], 1, 2, 0));
        for (int n = 0; n <= buttons[t]; n++) begin
            automatic int n2 = n < buttons[t] ? (n + 1) % buttons[t] : -1;
            snac_press(n < buttons[t] ? n : -1, n2, k1, k2);
            players_are('{k1, k2, CONT[2], CONT[3]}, $sformatf("%s, button %0d", kind[t], n));
        end
        snac_press(3, 1, k1, k2);   // Start, and the next pad's second
        for (int a = 0; a < 7; a++) begin
            automatic logic [15:0] want [0:3];
            anz_file(anz_word(type_of[t], 1, a, 0));
            case (a)
            0: want = '{k1, CONT[1], CONT[2], CONT[3]};
            1: want = '{CONT[0], k1, CONT[2], CONT[3]};
            2: want = '{k1, k2, CONT[2], CONT[3]};
            3: want = '{k2, k1, CONT[2], CONT[3]};
            4: want = '{CONT[0], CONT[1], k1, k2};
            5: want = '{k1, k2, CONT[2], CONT[3]};      // 3 and 4 only from the multitap
            default: want = '{CONT[0], CONT[1], CONT[2], CONT[3]};
            endcase
            players_are(want, $sformatf("%s, assignment %0d", kind[t], a));
        end
    end
    // a type not taken here (PlayStation) and SNAC with the Analogizer off: the Pocket's
    anz_pad = 1; snac_press(3, 1, k1, k2);
    anz_file(anz_word(5'h13, 1, 2, 0));
    players_are('{CONT[0], CONT[1], CONT[2], CONT[3]}, "PlayStation, not taken");
    anz_file(anz_word(3, 0, 2, 0));
    players_are('{CONT[0], CONT[1], CONT[2], CONT[3]}, "SNES with the Analogizer off");

    // a save state with SNAC pads in play: saved and loaded, and the pads are still theirs
    anz_file(anz_word(3, 1, 2, 0));
    players_are('{k1, k2, CONT[2], CONT[3]}, "SNES before a save state");
    test_state(32'h00034000);
    players_are('{k1, k2, CONT[2], CONT[3]}, "SNES after a save state and its load");

    // a game for Europe alone: PAL's clock, and the colour's step for it, either standard
    anz_held = '{24'd0, 24'd0}; anz_pad = 0;
    make_rom("T-TEST00", "E", 'h1000);
    anz_start_word = anz_word(0, 1, 0, 4);
    start_game();
    anz_start_word = -1;
    while (pll_busy || !s.reset_n) tick(100);
    tick(200);
    ok(ic.pal_s && ic.analogizer.phase_inc == 40'd91625970704, "Y/C PAL on PAL's clock: the colour's step for it");
    anz_file(anz_word(0, 1, 0, 3));
    ok(ic.analogizer.phase_inc == 40'd73975527396, "Y/C NTSC on PAL's clock: the colour's step for it");

    // off again: the Pocket's controls, and the slot idle from then on
    anz_held = '{24'd0, 24'd0}; anz_pad = 0;
    anz_file(anz_word(0, 0, 0, 0));
    begin
        automatic longint bad = anz_idle_bad, edges = anz_off_edges;
        frames(3);
        ok(anz_idle_bad == bad && anz_off_edges > edges + 100000, "analogizer.bin off: the slot idle again");
    end
    {cont1_key, cont2_key, cont3_key, cont4_key} = 64'd0;
endtask

task automatic count_lit(input int ticks, output int n);
    n = 0;
    repeat (ticks) begin
        @(posedge clk_74a);
        if (video_de && video_rgb != 0) n++;
    end
endtask

task automatic count_adapter_lit(input int ticks, output int n);
    n = 0;
    repeat (ticks) begin
        @(posedge clk_74a);
        if (tb3[7:2] != 0 || tb2[5:0] != 0) n++;
    end
endtask
`endif
