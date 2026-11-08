// The console's clock for PAL: the same PLL with its fraction changed, as MiSTer
// does it, so MCLK and the SDRAM's and video's clocks move together and stay in
// their ratios.
//
// A real PAL console runs from 53.203424 MHz and an NTSC one from 53.693175. On
// the NTSC clock a PAL frame is 50.16 Hz against the real 49.70, and the music
// about 16 cents sharp. Only K changes, M, N and the counters stay, so the clocks
// go on running through it: nothing has to survive a stop, and 1% slower is well
// inside what the fit met at NTSC's rate.
//
// A game's region is known from its header, 0x200 words into a load. The change
// waits for the load to end, so the SDRAM's writes aren't under way through it;
// `hold` keeps the console in reset from the moment PAL is wanted until the clock
// has settled, so a game never starts on the wrong clock. That also covers the
// setting changed in play: the game restarts on the other clock.

module pal_clock (
    input  wire        clk_74a,
    input  wire        want_pal,      // any domain: steady while it matters
    input  wire        loading,       // clk_74a: a ROM or a save coming in
    input  wire        pll_locked,

    output reg         pal = 0,       // what the chips are told, changed in reset
    output wire        hold,          // clk_74a: keep the console in reset

    output wire [63:0] reconfig_to_pll,
    input  wire [63:0] reconfig_from_pll
);

localparam [31:0] K_NTSC = 32'd2910634261,  // 74.25 x 8.677685 / 12 = 53.693175 MHz
                  K_PAL  = 32'd2570680398;  // 74.25 x 8.598533 / 12 = 53.203424 MHz

reg [1:0] want_s = 0;
always @(posedge clk_74a) want_s <= {want_s[0], want_pal};
wire want = want_s[1];

wire        waitrequest;
reg         write = 0;
reg  [5:0]  address = 0;
reg  [31:0] writedata = 0;

pll_cfg pll_cfg (
    .mgmt_clk(clk_74a),
    .mgmt_reset(1'b0),
    .mgmt_waitrequest(waitrequest),
    .mgmt_read(1'b0),
    .mgmt_readdata(),
    .mgmt_write(write),
    .mgmt_address(address),
    .mgmt_writedata(writedata),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);

// the writes as MiSTer's Genesis.sv makes them: the mode (wait for lock), K, start
reg [2:0] state = 0;
always @(posedge clk_74a) begin
    write <= 0;
    if (state == 0 && want != pal && !loading) begin
        pal <= want;
        state <= 1;
    end
    if (!waitrequest) begin
        if (state != 0) state <= state + 1'd1;
        case (state)
            1: begin address <= 6'd0; writedata <= 0; write <= 1; end
            5: begin address <= 6'd7; writedata <= pal ? K_PAL : K_NTSC; write <= 1; end
            7: begin address <= 6'd2; writedata <= 0; write <= 1; end
            default: ;
        endcase
    end
end

// waitrequest stays up from the start until the PLL has locked again
assign hold = (want != pal) | (state != 0) | write | waitrequest | ~pll_locked;

endmodule
