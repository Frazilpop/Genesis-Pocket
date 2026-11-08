// The cartridge slot as an Analogizer sees it (pocket_analogizer.sv): two SNAC pads of
// a kind answering its latch and clock, the template's tie-offs counted while it is off,
// and the pins at every clk_sys edge into a file for sim/top/anz.py.
//
// The pins, as RndMnkIII's module drives them: bank3 {R[5:0], hsync, vsync},
// bank2 {B[0], /blank, G[5:0]}, bank1 {latch, clock, the DAC's clock, B[5:1]}; a pad's
// data comes back on bank0[4] (pad 1) and bank0[5] (pad 2), and DB15's on pin31 too.

// ---- the pads ----
// anz_pad: 0 none, 1 SNES, 2 NES, 3 DB15. anz_held: the buttons each pad has down, by
// the place each takes in its shift register (SNES B, Y, Select, Start, Up, Down, Left,
// Right, A, X, L, R; NES A, B, Select, Start, Up, Down, Left, Right); DB15's two 74HC165s
// are one chain of 24, both pads' buttons in it (anz_held[0])
int          anz_pad = 0;
logic [23:0] anz_held [0:1] = '{24'd0, 24'd0};
int          anz_idx = 0;
bit          anz_clk_was = 0;
logic [7:4]  anz_b0_in = 4'hf;
logic        anz_p31_in = 1'b1;
assign tb0  = tb0d  ? 4'hz : anz_b0_in;
assign tp31 = tp31d ? 1'bz : anz_p31_in;

function automatic bit anz_bit(input int pad, input int i);   // 0 pressed, 1 released
    if (anz_pad == 3) return !(i < 24 && anz_held[0][i]);
    if (i >= 16) return 0;                                    // low after the sixteenth, as a pad is
    return !(i < 12 && anz_held[pad][i]);
endfunction

always @(posedge ic.clk_sys) begin
    automatic bit lat = tb1[7], clk = tb1[6];
    automatic bit load = anz_pad == 3 ? !lat : lat;           // DB15's load on a low latch
    if (load) anz_idx = 0;
    else if (clk && !anz_clk_was) anz_idx++;
    anz_clk_was = clk;
    anz_b0_in = {2'b11, anz_pad == 3 ? 1'b1 : anz_bit(1, anz_idx), anz_bit(0, anz_idx)};
    anz_p31_in = anz_pad == 3 ? anz_bit(0, anz_idx) : 1'b1;
end

// ---- off: the template's tie-offs on every edge (banks 1-3 inputs, bank0 an output at
// F, pin30 driven low with its direction the hardware's, pwroff low, pin31 an input) ----
// (anz_on: what the bench last wrote, cleared only once the module has had time to take it)
bit     anz_on = 0;
longint anz_off_edges = 0, anz_idle_bad = 0;
always @(posedge ic.clk_sys) if (!anz_on) begin
    anz_off_edges++;
    if (tb3d || tb2d || tb1d || !tb0d || tb0 !== 4'hf || tp30 !== 1'b0 || tp30r || tp31d) begin
        anz_idle_bad++;
        if (anz_idle_bad < 4) $display("Analogizer off, the slot not idle at %0d ps: %b%b%b%b %h %b %b %b", $time,
                                       tb3d, tb2d, tb1d, tb0d, tb0, tp30, tp30r, tp31d);
    end
end

// ---- the pins, every clk_sys edge while anz_fd is open, for sim/top/anz.py: four bytes
// an edge, bank3, bank2, bank1 and whether all three are outputs ----
int     anz_fd = 0;
longint anz_samples = 0;
time    anz_t0 = 0, anz_t1 = 0;
always @(posedge ic.clk_sys) if (anz_fd != 0) begin
    $fwrite(anz_fd, "%c%c%c%c", tb3, tb2, tb1, {7'd0, tb3d & tb2d & tb1d});
    if (anz_samples == 0) anz_t0 = $time;
    anz_t1 = $time;
    anz_samples++;
end

// the file's word as the Pocket writes it: slot 330's four bytes, little-endian, onto a
// big-endian bridge. The Pocket loads it as a game starts (start_game, anz_start_word);
// later, as here, it stands for the next start's file.
task automatic anz_file(input [31:0] w);
    if (w[5]) anz_on = 1;
    bwr(32'hF7000000, {w[7:0], w[15:8], w[23:16], w[31:24]}, 41);
    tick(200);
    anz_on = w[5];
endtask

function automatic [31:0] anz_word(input int snac = 0, input bit on = 1, input int assign_ = 0,
                                   input int video = 0, input bit pocket_off = 0);
    anz_word = 32'(snac) | 32'(on) << 5 | 32'(assign_) << 6 | 32'(video) << 10 | 32'(pocket_off) << 14;
endfunction
