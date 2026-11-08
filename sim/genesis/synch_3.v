// common.v's synch_3 alone, for the bridge's model (apf/common.v has the rest)
module synch_3 #(parameter WIDTH = 1) (
   input  wire [WIDTH-1:0] i,
   output reg  [WIDTH-1:0] o,
   input  wire             clk,
   output wire             rise,
   output wire             fall
);
reg [WIDTH-1:0] stage_1;
reg [WIDTH-1:0] stage_2;
reg [WIDTH-1:0] stage_3;
assign rise = (WIDTH == 1) ? (o & ~stage_3) : 1'b0;
assign fall = (WIDTH == 1) ? (~o & stage_3) : 1'b0;
always @(posedge clk) {stage_3, o, stage_2, stage_1} <= {o, stage_2, stage_1, i};
endmodule
