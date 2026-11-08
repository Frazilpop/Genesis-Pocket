// The picture from clk_sys, held steady for the Pocket's video clock.
//
// The video clock is MCLK/8 in H40 and a line 3,420 MCLK: 427.5 of its periods,
// so a pixel's edge against the clock moves 4 MCLK every line. Where the two
// lie depends on when the VDP last left its reset, a fresh chance at each launch
// and each load of a state. In one case in four, on every second line, a pixel
// changes on the clock's own edge: each bit then gets its new value or its old
// by its own route on the chip, and a line whose blanking is caught apart from
// its colours sits a pixel along from the lines beside it.
//
// So everything sampled on the video clock changes together, here, 2 or 3 MCLK
// after that clock's rising edge, as far as can be from the next. It is taken
// once a video clock's period, as often as the pixels come while one is shown,
// so each pixel of a line is taken once.

module video_hold #(
    parameter WIDTH = 1
) (
    input  wire             clk_sys,
    input  wire             clk_pix,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q = 0
);

reg pix_t = 0;
always @(posedge clk_pix) pix_t <= ~pix_t;

reg [2:0] pix_s = 0;
always @(posedge clk_sys) begin
    pix_s <= {pix_s[1:0], pix_t};
    if (pix_s[2] != pix_s[1]) q <= d;
end

endmodule
