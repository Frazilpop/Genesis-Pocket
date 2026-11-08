// The save file between the Pocket's bridge loaders and the save RAM.
//
// The file is laid out as Spiritualized's core lays it out, so the same .sav
// works in both: the 128 KB the save RAM spans in the 68000's map
// (0x200000-0x21FFFF), each byte at its own address. The RAM here (system.sv)
// is a byte per 68000 word, 64 KB, so a RAM byte is the odd byte of a file
// word, the one a game reads. It goes back out on both bytes of its word, as
// a read here returns it.
//
// A file of 64 KB or less is the older layout other Pocket cores wrote: the
// RAM's bytes back to back. It is read as it is, and written back in
// Spiritualized's, 128 KB (the size core_top puts in the data table).

module save_layout #(
    parameter [15:0] SLOT_ID = 16'd10
) (
    input  wire        clk_74a,
    input  wire        clk_sys,

    // the Pocket says the file's size as it asks to write the slot
    input  wire        dataslot_requestwrite,
    input  wire [15:0] dataslot_requestwrite_id,
    input  wire [31:0] dataslot_requestwrite_size,

    // data_loader: the file's bytes at wr_addr and +1, the first in [7:0]
    input  wire        wr,
    input  wire [16:0] wr_addr,
    input  wire [15:0] wr_data,

    // data_unloader, the same way round
    input  wire [16:0] rd_addr,
    output wire [15:0] rd_data,

    // the RAM's port B: a word is RAM bytes 2n in [7:0] and 2n+1 in [15:8]
    output wire        ram_we,
    output wire [14:0] ram_addr,
    output wire [15:0] ram_di,
    input  wire [15:0] ram_do
);

reg back_to_back_74 = 0;
always @(posedge clk_74a) begin
    if (dataslot_requestwrite && dataslot_requestwrite_id == SLOT_ID)
        back_to_back_74 <= dataslot_requestwrite_size != 0 && dataslot_requestwrite_size <= 32'd65536;
end

// set before the file's first byte comes, and steady while it loads
reg [1:0] back_to_back_s = 0;
always @(posedge clk_sys) back_to_back_s <= {back_to_back_s[0], back_to_back_74};
wire back_to_back = back_to_back_s[1];

// Spiritualized's: a RAM word is the odd bytes of two file words, so the
// first is held until the second comes
reg [7:0] wr_lo = 0;
always @(posedge clk_sys) if (wr & ~wr_addr[1]) wr_lo <= wr_data[15:8];

assign ram_we   = wr & (back_to_back | wr_addr[1]);
assign ram_di   = back_to_back ? wr_data : {wr_data[15:8], wr_lo};
assign ram_addr = ~ram_we ? rd_addr[16:2] :
                  back_to_back ? wr_addr[15:1] : wr_addr[16:2];

assign rd_data  = rd_addr[1] ? {2{ram_do[15:8]}} : {2{ram_do[7:0]}};

endmodule
