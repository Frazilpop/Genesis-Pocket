// What core_top.sv stands on that only exists in Quartus, for sim/top's bench.
`timescale 1ps/1ps

// The PLL: every clock on one 107 MHz grid as the fit has them, and the video clocks
// a little behind clk_sys, as the mux in front of them puts them on the Pocket
// (sim/video/tb.sv). Locked some time after power-on, and dropped while pll_cfg works.
module mf_pllbase (
    input  wire        refclk,
    input  wire        rst,
    output reg         outclk_0 = 0,
    output reg         outclk_1 = 0,
    output reg         outclk_2 = 0,
    output reg         outclk_3 = 0,
    output reg         outclk_4 = 0,
    output reg         outclk_5 = 0,
    output wire        locked,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll
);
    assign reconfig_from_pll = 0;
    localparam T_RAM = 9312, SKEW = 1500;
    initial forever #(T_RAM / 2) outclk_1 = ~outclk_1;
    initial forever #(T_RAM)     outclk_0 = ~outclk_0;
    initial begin #SKEW;                forever #(T_RAM * 8)  outclk_2 = ~outclk_2; end     // clk_sys / 8
    initial begin #(SKEW + T_RAM * 4);  forever #(T_RAM * 8)  outclk_3 = ~outclk_3; end
    initial begin #SKEW;                forever #(T_RAM * 10) outclk_4 = ~outclk_4; end     // clk_sys / 10
    initial begin #(SKEW + T_RAM * 5);  forever #(T_RAM * 10) outclk_5 = ~outclk_5; end
    reg up = 0;
    initial #200000000 up = 1;      // 200 us
    assign locked = up & ~tb.pll_busy;
endmodule

// Intel's reconfig core: its Avalon side, K noted, busy for a while after the start
module pll_cfg (
    input  wire        mgmt_clk,
    input  wire        mgmt_reset,
    output wire        mgmt_waitrequest,
    input  wire        mgmt_read,
    output wire [31:0] mgmt_readdata,
    input  wire        mgmt_write,
    input  wire [5:0]  mgmt_address,
    input  wire [31:0] mgmt_writedata,
    output wire [63:0] reconfig_to_pll,
    input  wire [63:0] reconfig_from_pll
);
    assign mgmt_readdata = 0;
    assign reconfig_to_pll = 0;
    reg [15:0] busy = 0;
    assign mgmt_waitrequest = busy != 0;
    always @(posedge mgmt_clk) begin
        if (busy != 0) busy <= busy - 1'd1;
        if (mgmt_write) begin
            if (mgmt_address == 6'd7) tb.pll_k <= mgmt_writedata;
            if (mgmt_address == 6'd2) begin busy <= 16'd3000; tb.pll_starts <= tb.pll_starts + 1; if ($test$plusargs("pll")) $display("%0d start, K %h pal %0d", $time, tb.pll_k, tb.s.pal); end
        end
    end
    always @* tb.pll_busy = busy != 0;
endmodule

// The bridge's data table
module mf_datatable (
    input  wire [9:0]  address_a, address_b,
    input  wire        clock_a, clock_b,
    input  wire [31:0] data_a, data_b,
    input  wire        wren_a, wren_b,
    output reg  [31:0] q_a, q_b
);
    reg [31:0] mem [0:1023];
    initial for (int i = 0; i < 1024; i++) mem[i] = 0;
    always @(posedge clock_a) begin if (wren_a) mem[address_a] <= data_a; q_a <= wren_a ? data_a : mem[address_a]; end
    always @(posedge clock_b) begin if (wren_b) mem[address_b] <= data_b; q_b <= wren_b ? data_b : mem[address_b]; end
endmodule

// The SDRAM's clock pin: high on the low half of clk
module altddio_out #(
    parameter extend_oe_disable = "OFF", intended_device_family = "Cyclone V", invert_output = "OFF",
    lpm_hint = "UNUSED", lpm_type = "altddio_out", oe_reg = "UNREGISTERED", power_up_high = "OFF", width = 1
) (
    input  wire [width-1:0] datain_h, datain_l,
    input  wire             outclock,
    output wire [width-1:0] dataout,
    input  wire             aclr, aset, oe, outclocken, sclr, sset
);
    assign dataout = outclock ? datain_h : datain_l;
endmodule

// The SDRAM chip, CAS latency 2: a row opened, a word read or written with its byte
// masks, on the edge of its own clock. A megabyte or two is all a test ROM wants. A word
// read stays out a clock later than the data sheet's edges, standing for the pins' delays
// that have the controller take it half a clock after the chip's second edge.
module sdram_chip (
    input  wire        clk,
    input  wire [12:0] a,
    input  wire [1:0]  ba,
    inout  wire [15:0] dq,
    input  wire [1:0]  dqm,
    input  wire        ras_n, cas_n, we_n
);
    reg [15:0] mem [0:(1 << 21) - 1];
    reg [12:0] row [0:3];
    reg [15:0] out1 = 0, out2 = 0, out3 = 0;
    reg        oe1 = 0, oe2 = 0, oe3 = 0;
    assign dq = oe3 ? out3 : 16'hzzzz;
    wire [20:0] where = {a[7:0], row[ba]};   // sdram.sv: the row is the address's low bits
    initial for (int i = 0; i < (1 << 21); i++) mem[i] = 16'hA5A5;
    always @(posedge clk) begin
        oe1 <= 0; oe2 <= oe1; out2 <= out1; oe3 <= oe2; out3 <= out2;
        case ({ras_n, cas_n, we_n})
            3'b011: row[ba] <= a;
            3'b101: begin out1 <= mem[where]; oe1 <= 1; end
            3'b100: begin
                if (!dqm[0]) mem[where][7:0]  <= dq[7:0];
                if (!dqm[1]) mem[where][15:8] <= dq[15:8];
            end
            default: ;
        endcase
    end
endmodule
