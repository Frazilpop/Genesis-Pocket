// rtl/bram.vhd's dpram and dpram_dif as SystemVerilog, for the RAMs system.sv
// itself holds (VRAM, the 68000's and the Z80's RAM, the save RAM), for
// tools/sim.sh. Behaved as the core's altsyncram is set: the
// address registered and the output not, so a word comes a clock after its
// address; a port reading where it writes gets the new data. dpram_dif's two
// ports may differ in width (the save RAM: bytes on the 68000's side, words
// on the bridge's), as altsyncram's do: the wide port's word holds the narrow
// port's at its lower addresses in its low bits.

module dpram_dif #(
	parameter addr_width_a  = 8,
	parameter data_width_a  = 8,
	parameter addr_width_b  = 8,
	parameter data_width_b  = 8,
	parameter mem_init_file = " "
) (
	input  logic                    clock,
	input  logic [addr_width_a-1:0] address_a,
	input  logic [data_width_a-1:0] data_a = '0,
	input  logic                    enable_a = 1'b1,
	input  logic                    wren_a = 1'b0,
	output logic [data_width_a-1:0] q_a,
	input  logic                    cs_a = 1'b1,
	input  logic [addr_width_b-1:0] address_b = '0,
	input  logic [data_width_b-1:0] data_b = '0,
	input  logic                    enable_b = 1'b1,
	input  logic                    wren_b = 1'b0,
	output logic [data_width_b-1:0] q_b,
	input  logic                    cs_b = 1'b1
);
	// held as the narrower port's words
	localparam W  = data_width_a < data_width_b ? data_width_a : data_width_b;
	localparam RA = data_width_a / W, RB = data_width_b / W;
	localparam N  = (2 ** addr_width_a) * RA;

	logic [W-1:0] mem [0:N-1];
	logic [data_width_a-1:0] q0;
	logic [data_width_b-1:0] q1;

	assign q_a = cs_a ? q0 : '1;
	assign q_b = cs_b ? q1 : '1;

	always_ff @(posedge clock) begin
		if (enable_a) begin
			if (wren_a & cs_a) begin
				for (int i = 0; i < RA; i++) mem[address_a * RA + i] <= data_a[i*W +: W];
				q0 <= data_a;
			end else
				for (int i = 0; i < RA; i++) q0[i*W +: W] <= mem[address_a * RA + i];
		end
		if (enable_b) begin
			if (wren_b & cs_b) begin
				for (int i = 0; i < RB; i++) mem[address_b * RB + i] <= data_b[i*W +: W];
				q1 <= data_b;
			end else
				for (int i = 0; i < RB; i++) q1[i*W +: W] <= mem[address_b * RB + i];
		end
	end
endmodule

module dpram #(
	parameter addr_width    = 8,
	parameter data_width    = 8,
	parameter mem_init_file = " "
) (
	input  logic                  clock,
	input  logic [addr_width-1:0] address_a,
	input  logic [data_width-1:0] data_a = '0,
	input  logic                  enable_a = 1'b1,
	input  logic                  wren_a = 1'b0,
	output logic [data_width-1:0] q_a,
	input  logic                  cs_a = 1'b1,
	input  logic [addr_width-1:0] address_b = '0,
	input  logic [data_width-1:0] data_b = '0,
	input  logic                  enable_b = 1'b1,
	input  logic                  wren_b = 1'b0,
	output logic [data_width-1:0] q_b,
	input  logic                  cs_b = 1'b1
);
	dpram_dif #(addr_width, data_width, addr_width, data_width, mem_init_file) ram (.*);
endmodule
