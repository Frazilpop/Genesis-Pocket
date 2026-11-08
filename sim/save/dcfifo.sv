// A stand-in for Intel's dcfifo, for the testbench only: two clocks, no
// showahead, rdempty straight from the pointers.
module dcfifo #(
    parameter clocks_are_synchronized = "FALSE",
    parameter intended_device_family = "Cyclone V",
    parameter lpm_numwords = 4,
    parameter lpm_showahead = "OFF",
    parameter lpm_type = "dcfifo",
    parameter lpm_width = 8,
    parameter lpm_widthu = 2,
    parameter overflow_checking = "OFF",
    parameter rdsync_delaypipe = 5,
    parameter underflow_checking = "OFF",
    parameter use_eab = "OFF",
    parameter wrsync_delaypipe = 5
) (
    input  wire [lpm_width-1:0] data,
    input  wire                 rdclk,
    input  wire                 rdreq,
    input  wire                 wrclk,
    input  wire                 wrreq,
    output reg  [lpm_width-1:0] q,
    output wire                 rdempty,
    // (sync_fifo.sv names these, and leaves them open)
    input  wire                 aclr,
    output wire                 eccstatus,
    output wire                 rdfull,
    output wire [lpm_widthu-1:0] rdusedw,
    output wire                 wrempty,
    output wire                 wrfull,
    output wire [lpm_widthu-1:0] wrusedw
);
  reg [lpm_width-1:0] mem [0:15];
  reg [4:0] wp = 0, rp = 0;
  assign rdempty = wp == rp;
  always @(posedge wrclk) if (wrreq) begin mem[wp[3:0]] <= data; wp <= wp + 1; end
  always @(posedge rdclk) if (rdreq && !rdempty) begin q <= mem[rp[3:0]]; rp <= rp + 1; end
endmodule
