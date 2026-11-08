// The picture onto the video clock, on every phase the two can lie at
// (src/fpga/core/video_hold.sv): a VDP's line as cofi gives it, H40 or H32, its
// start moved by a clock of clk_sys each time, taken as core_top.sv takes it.
//
// The delays are a fit's, as the timing report gave them: at the edge the video
// clock shares with clk_sys it comes 2.9 ns late, through the mode's mux, and
// the colours are there before it, while blanking is on the edge: here, just
// after it, which is one of the two ways that can go. So "direct" is the path
// without video_hold and "held" the path through it.

`timescale 1ps/1ps

module tb;

localparam T_SYS = 18624;           // clk_sys, 53.69 MHz, in ps
localparam CLK_LATE = 2900;         // the video clock behind clk_sys
localparam DE_PATH = 3000;          // blanking to its register
localparam RGB_PATH = 1700;         // the colours to theirs
localparam LINES = 40;

reg  clk_sys = 0;
always #(T_SYS / 2) clk_sys = ~clk_sys;

integer h40 = 1, phase = 0, div = 8;
integer div_c = 0, hc = 0, slot = 0, slot_c = 0;
reg clk_pix = 0;
reg clk_pix_d = 0;
always @(clk_pix) clk_pix_d <= #CLK_LATE clk_pix;

// the source: pixels numbered from 1 along the line, in clk_sys's domain
reg        src_hbl = 1;
reg [23:0] src_rgb = 0;
function automatic integer slot_len(input integer s);
    // H40's line is 28*10 + 4*9 + 388*8 = 3,420 MCLK, H32's 342*10
    if (!h40) slot_len = 10;
    else if (s >= 388 && s < 416) slot_len = 10;
    else if (s >= 416) slot_len = 9;
    else slot_len = 8;
endfunction
integer width;
always @* width = h40 ? 320 : 256;
integer slots;
always @* slots = h40 ? 420 : 342;

reg running = 0;
always @(posedge clk_sys) begin
    div_c <= div_c == div - 1 ? 0 : div_c + 1;
    clk_pix <= div_c < div / 2;
    if (running) begin
        if (slot_c == slot_len(slot) - 1) begin
            slot_c <= 0;
            slot <= slot == slots - 1 ? 0 : slot + 1;
            src_hbl <= slot >= width;
            src_rgb <= slot < width ? slot + 1 : 0;
        end
        else slot_c <= slot_c + 1;
    end
end

// the direct path
reg hbl_a = 1; reg [23:0] rgb_a = 0;
always @(src_hbl) hbl_a <= #DE_PATH src_hbl;
always @(src_rgb) rgb_a <= #RGB_PATH src_rgb;

// the held one
wire [24:0] held;
video_hold #(.WIDTH(25)) hold (.clk_sys(clk_sys), .clk_pix(clk_pix_d), .d({src_hbl, src_rgb}), .q(held));
reg hbl_b = 1; reg [23:0] rgb_b = 0;
always @(held) begin
    hbl_b <= #DE_PATH held[24];
    rgb_b <= #RGB_PATH held[23:0];
end

// as core_top.sv's video block, a checker on each
integer bad_a = 0, bad_b = 0, n_a = 0, n_b = 0, x_a = 0, x_b = 0, lines_a = 0, lines_b = 0;
reg de_a = 0, de_b = 0; reg [23:0] out_a = 0, out_b = 0;
reg ok_a = 1, ok_b = 1;
always @(posedge clk_pix_d) begin
    de_a <= ~hbl_a; if (~hbl_a) out_a <= rgb_a;
    de_b <= ~hbl_b; if (~hbl_b) out_b <= rgb_b;

    if (de_a) begin
        n_a <= n_a + 1;
        if (out_a != n_a + 1) ok_a <= 0;
    end
    else if (n_a != 0) begin
        lines_a <= lines_a + 1;
        if (!ok_a || n_a != width) bad_a <= bad_a + 1;
        n_a <= 0; ok_a <= 1;
    end

    if (de_b) begin
        n_b <= n_b + 1;
        if (out_b != n_b + 1) ok_b <= 0;
    end
    else if (n_b != 0) begin
        lines_b <= lines_b + 1;
        if (!ok_b || n_b != width) bad_b <= bad_b + 1;
        n_b <= 0; ok_b <= 1;
    end
end

integer total_a = 0, total_b = 0, total_lines = 0, phases_a = 0, phases_bad_b = 0, m, step = 0, steps = 18;
initial begin
    for (m = 1; m >= 0; m = m - 1) begin
        h40 = m; div = m ? 8 : 10;
        for (phase = 0; phase < div; phase = phase + 1) begin
            running = 0; slot = 0; slot_c = 0;
            div_c = 0;
            bad_a = 0; bad_b = 0; lines_a = 0; lines_b = 0;
            repeat (3) @(posedge clk_sys);
            repeat (phase) @(posedge clk_sys);
            running = 1;
            repeat (LINES * 3420) @(posedge clk_sys);
            running = 0;
            @(posedge clk_sys);
            step = step + 1;
            $display("%0d of %0d  %s, phase %0d: %0d lines; direct %0d off, held %0d off",
                     step, steps, m ? "H40" : "H32", phase, lines_b, bad_a, bad_b);
            total_a = total_a + bad_a; total_b = total_b + bad_b; total_lines = total_lines + lines_b;
            if (bad_a) phases_a = phases_a + 1;
            if (bad_b) phases_bad_b = phases_bad_b + 1;
        end
    end
    $display("direct: %0d lines off, in %0d of %0d phases", total_a, phases_a, steps);
    $display("held:   %0d lines off of %0d", total_b, total_lines);
    if (total_b != 0 || total_a == 0) begin $display("FAILED"); $fatal(1); end
    $display("ok");
    $finish;
end

endmodule
