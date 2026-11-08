// pal_clock.sv in Verilator with Intel's own reconfig core, and a model of the PLL
// on its far side: the registers its bus writes, and locked falling for a while
// after a new K. What the PLL does with the K only the Pocket can show; this shows
// the right K getting to it at the right moments, and the console held in reset.
`timescale 1ns/1ps

// the one primitive the reconfig core wants, a look-up table as its two uses set
// it: only Cyclone V's is used, Verilator wants the rest to exist
module cyclonev_lcell_comb #(parameter lut_mask = 64'hAAAAAAAAAAAAAAAA, parameter dont_touch = "on") (
    input dataa, input datab, input datac, input datad, input datae, input dataf, input datag,
    output combout, output sumout
);
    assign combout = lut_mask[0] == 1'b0 && lut_mask[2] == 1'b1 ? datab : dataa;
    assign sumout = 0;
endmodule
module stratixv_lcell_comb #(parameter lut_mask = 64'hAAAAAAAAAAAAAAAA, parameter dont_touch = "on") (
    input dataa, input datab, input datac, input datad, input datae, input dataf, input datag,
    output combout, output sumout
);
    assign combout = lut_mask[0] == 1'b0 && lut_mask[2] == 1'b1 ? datab : dataa;
    assign sumout = 0;
endmodule
module arriav_lcell_comb #(parameter lut_mask = 64'hAAAAAAAAAAAAAAAA, parameter dont_touch = "on") (
    input dataa, input datab, input datac, input datad, input datae, input dataf, input datag,
    output combout, output sumout
);
    assign combout = lut_mask[0] == 1'b0 && lut_mask[2] == 1'b1 ? datab : dataa;
    assign sumout = 0;
endmodule
module arriavgz_lcell_comb #(parameter lut_mask = 64'hAAAAAAAAAAAAAAAA, parameter dont_touch = "on") (
    input dataa, input datab, input datac, input datad, input datae, input dataf, input datag,
    output combout, output sumout
);
    assign combout = lut_mask[0] == 1'b0 && lut_mask[2] == 1'b1 ? datab : dataa;
    assign sumout = 0;
endmodule

module tb;
    localparam [31:0] K_NTSC = 32'd2910634261, K_PAL = 32'd2570680398;
    localparam LOCK_GAP = 74250;  // a millisecond of clk_74a without lock

    reg clk = 0;
    always #6.734 clk = ~clk;

    reg want = 0, loading = 0;
    wire pal, hold;
    wire [63:0] to_pll;
    reg  [63:0] from_pll = 0;

    // ---- the PLL ----
    reg [15:0] regs [0:63];
    reg [31:0] k;
    int since_k = -1, starts = 0;
    reg locked = 0;
    int boot = 2000;
    reg ready_d = 0;
    wire        d_clk   = to_pll[0];
    wire        d_write = to_pll[2];
    wire        d_read  = to_pll[3];
    wire [5:0]  d_addr  = to_pll[9:4];
    wire [15:0] d_wdata = to_pll[25:10];
    initial begin
        for (int i = 0; i < 64; i++) regs[i] = 0;
        k = K_NTSC; regs['h18] = K_NTSC[15:0]; regs['h19] = K_NTSC[31:16];
    end
    always @(posedge d_clk) begin
        if (d_write) begin
            if (d_addr == 'h18 || d_addr == 'h19 || d_addr == 'h17) regs[d_addr] <= d_wdata;
            // K taken as the ready bit goes up
            if (d_addr == 'h17 && d_wdata[11]) begin
                k <= {regs['h19], regs['h18]};
                starts <= starts + 1;
                since_k <= LOCK_GAP;
                locked <= 0;
            end
        end
        if (boot > 0) begin boot <= boot - 1; if (boot == 1) locked <= 1; end
        if (since_k > 0) begin since_k <= since_k - 1; if (since_k == 1) locked <= 1; end
        from_pll[15:0] <= regs[d_addr];
    end
    always @* begin from_pll[16] = locked; from_pll[17] = 1'b1; end

    pal_clock dut (
        .clk_74a(clk),
        .want_pal(want),
        .loading(loading),
        .pll_locked(locked),
        .pal(pal),
        .hold(hold),
        .reconfig_to_pll(to_pll),
        .reconfig_from_pll(from_pll)
    );

    // ---- the checks ----
    int good = 0, bad = 0;
    task check(input bit ok, input string what);
        if (ok) good++; else begin bad++; $display("FAIL: %s", what); end
    endtask

    // the console must be held from the clock after PAL is wanted until lock is back
    reg want_d = 0, pal_d = 0;
    int unheld = 0, pal_out_of_reset = 0;
    always @(posedge clk) begin
        want_d <= want; pal_d <= pal;
        if (pal != pal_d && !hold) pal_out_of_reset++;
        if (!locked && !hold) unheld++;
    end

    task settle(input int n); repeat (n) @(posedge clk); endtask
    task wait_free; automatic int n = 0; while (hold && n < 400000) begin @(posedge clk); n++; end check(!hold, "hold never fell"); settle(5); endtask

    task change(input string what, input bit w, input [31:0] wanted_k, input bit during_load);
        automatic int starts0 = starts;
        if (during_load) begin
            loading = 1; settle(1000);
            want = w; settle(10);
            check(hold, {what, ": held as soon as it is wanted"});
            check(pal != w, {what, ": chips not told during the load"});
            settle(200000);
            check(starts == starts0, {what, ": K left alone during the load"});
            check(hold, {what, ": still held at the end of the load"});
            loading = 0;
        end else begin
            want = w; settle(10);
            check(hold, {what, ": held as soon as it is wanted"});
        end
        settle(5);
        check(pal == w, {what, ": chips told"});
        wait_free();
        check(starts == starts0 + 1, {what, ": K written once"});
        check(k == wanted_k, $sformatf("%s: K %0d, wanted %0d", what, k, wanted_k));
        check(pal == w, {what, ": chips still told"});
        check(!hold, {what, ": let go"});
    endtask

    initial begin
        settle(10);
        check(hold, "power-on: held until the first lock");
        wait_free();
        check(pal == 0 && k == K_NTSC && starts == 0, "power-on: NTSC, nothing written");

        change("a PAL game loads", 1, K_PAL, 1);
        change("an NTSC game loads after it", 0, K_NTSC, 1);
        change("the setting changed in play to Europe", 1, K_PAL, 0);
        change("the setting changed back in play", 0, K_NTSC, 0);

        // the same region again: no change at all
        begin
            automatic int starts0 = starts;
            loading = 1; settle(1000); loading = 0; settle(1000);
            check(starts == starts0 && !hold, "another NTSC game: nothing written, not held");
        end

        // changed again while the first change is still locking
        want = 1; settle(5000);
        check(hold && !locked, "changed twice: first still locking");
        want = 0; settle(10);
        check(hold, "changed twice: held");
        wait_free(); settle(5);
        wait_free();
        check(pal == 0 && k == K_NTSC, $sformatf("changed twice: ends on NTSC (pal %0d, K %0d)", pal, k));

        check(unheld == 0, $sformatf("the console was out of reset on %0d clocks without lock", unheld));
        check(pal_out_of_reset == 0, "PAL changed with the console out of reset");
        $display("%0d of %0d checks good", good, good + bad);
        if (bad != 0) begin $display("FAILED"); $fatal; end
        $finish;
    end
endmodule
