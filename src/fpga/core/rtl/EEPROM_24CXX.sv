// The serial (I2C) save chips on Sega's, EA's, Acclaim's and Codemasters' carts:
// X24C01 and X24C02 (one address byte, or the address in the start byte) and the
// 24Cxx. Not MiSTer's: written for this core. The
// contents live in the save RAM through port A, as EEPROM_STM95.sv has Pier
// Solar's, so the .sav carries them. A byte goes in as the 68000 raises the clock
// on the ACK; the real chip's page buffer and busy time are not modelled, as a
// game only sees them by polling, and an ACK ends that at once.

module EEPROM_24CXX
(
	input             clk,
	input             reset,
	input       [2:0] chip,    // below
	input             scl,     // the lines as the game last wrote them
	input             sda,
	output            sda_o,   // what SDA reads back
	// the save RAM: q follows addr one clock later, and a read takes many thousand
	output     [12:0] ram_addr,
	input       [7:0] ram_q,
	output      [7:0] ram_di,
	output            ram_we,
	// save states: three words, written while the console is stopped
	input       [1:0] ss_a,
	input             ss_we,
	input      [15:0] ss_di,
	output reg [15:0] ss_do
);

// address bytes after the start byte: 0 (the address is in it), 1 or 2; the size
// and the page a write wraps in. Genesis Plus GX's i2c_specs, in the same order.
reg  [1:0] mode;
reg [12:0] mask;
reg  [5:0] page;
always_comb case (chip)
	0: begin mode = 0; mask = 13'h007F; page = 6'h03; end  // X24C01
	1: begin mode = 1; mask = 13'h00FF; page = 6'h03; end  // X24C02
	2: begin mode = 1; mask = 13'h00FF; page = 6'h07; end  // 24C02
	3: begin mode = 1; mask = 13'h01FF; page = 6'h0F; end  // 24C04
	4: begin mode = 1; mask = 13'h03FF; page = 6'h0F; end  // 24C08
	5: begin mode = 1; mask = 13'h07FF; page = 6'h0F; end  // 24C16
	default: begin mode = 2; mask = 13'h1FFF; page = 6'h3F; end  // 24C65
endcase

localparam STANDBY = 0, WAIT_STOP = 1, DEVICE = 2, ADDR7 = 3, WORD_HIGH = 4, WORD_LOW = 5, WRITE = 6, READ = 7;

reg        old_scl, old_sda;
reg  [2:0] state;
reg  [3:0] bitn;     // 0 at a start; 1 to 8 a byte's bits (the clock low), 9 its ACK
reg        rnw;
reg  [2:0] block;    // the start byte's three: the top of the address, up to a 24C16
reg [12:0] word;
reg  [7:0] buffer;

wire rise  = ~old_scl &  scl;
wire fall  =  old_scl & ~scl;
wire start =  old_scl &  scl &  old_sda & ~sda;
wire stop  =  old_scl &  scl & ~old_sda &  sda;

assign ram_addr = (mode == 1 ? {2'b00, block | word[10:8], word[7:0]} : word) & mask;
assign ram_di   = buffer;
assign ram_we   = rise && state == WRITE && bitn == 9;

// a byte's bits while it reads, the ACK low; otherwise the line as the game holds it
assign sda_o = (state == READ && bitn < 9) ? ram_q[4'd8 - bitn] :
               (state != READ && bitn == 9) ? 1'b0 : sda;

always_comb case (ss_a)
	0:       ss_do = {old_scl, old_sda, state, bitn, rnw, block, 3'd0};
	1:       ss_do = {3'd0, word};
	default: ss_do = {8'd0, buffer};
endcase

always_ff @(posedge clk) begin
	if (reset) begin
		old_scl <= 1;
		old_sda <= 1;
		state <= STANDBY;
		bitn <= 0;
		rnw <= 0;
		block <= 0;
		word <= 0;
		buffer <= 0;
	end
	else if (ss_we) case (ss_a)
		0:       {old_scl, old_sda, state, bitn, rnw, block} <= ss_di[15:3];
		1:       word <= ss_di[12:0];
		default: buffer <= ss_di[7:0];
	endcase
	else begin
		old_scl <= scl;
		old_sda <= sda;

		if (fall && state >= DEVICE) begin
			if (bitn < 9) bitn <= bitn + 1'd1;
			else begin
				bitn <= 1;
				case (state)
					DEVICE:    if (rnw) state <= READ;
					           else begin word <= 0; state <= mode == 2 ? WORD_HIGH : WORD_LOW; end
					ADDR7:     state <= rnw ? READ : WRITE;
					WORD_HIGH: state <= WORD_LOW;
					WORD_LOW:  state <= WRITE;
					default: ;
				endcase
			end
		end

		if (rise) case (state)
			DEVICE: begin
				if (bitn >= 5 && bitn < 8) block <= {block[1:0], sda};
				if (bitn == 8) rnw <= sda;
			end
			ADDR7: begin
				if (bitn < 8) word[6:0] <= {word[5:0], sda};
				if (bitn == 8) rnw <= sda;
			end
			WORD_HIGH: if (bitn < 9) word[12:8] <= {word[11:8], sda};
			WORD_LOW:  if (bitn < 9) word[7:0] <= {word[6:0], sda};
			WRITE: begin
				if (bitn < 9) buffer <= {buffer[6:0], sda};
				else word <= (word & ~{7'd0, page}) | ((word + 1'd1) & {7'd0, page});
			end
			READ: if (bitn == 9) begin
				if (sda) state <= WAIT_STOP;
				else word <= (word + 1'd1) & mask;
			end
			default: ;
		endcase

		if (start && state != WAIT_STOP) begin
			bitn <= 0;
			if (mode == 0) begin word <= 0; state <= ADDR7; end
			else begin block <= 0; state <= DEVICE; end
		end
		if (stop && state != STANDBY) state <= STANDBY;
	end
end

endmodule
