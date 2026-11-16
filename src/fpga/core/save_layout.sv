// The save file between the Pocket's bridge loaders and the save RAM.
//
// The file is laid out as Spiritualized's core lays it out, so the same .sav
// works in both: the 128 KB the save RAM spans in the 68000's map
// (0x200000-0x21FFFF), each byte at its own address. The RAM here (system.sv)
// is a byte per 68000 word, 64 KB, so a RAM byte is the odd byte of a file
// word, the one a game reads. It goes back out on both bytes of its word, as
// a read here returns it.
//
// A file of 64 KB or less is one of two things, told apart by what is in it:
//
// - The older layout other Pocket cores wrote: the RAM's bytes back to back.
// - An emulator's: a byte at each address as above, but cut short. Genesis
//   Plus GX ends the file after its last byte that isn't FF, so a game with
//   its RAM on odd bytes (Phantasy Star IV, 8 KB) leaves a file of 16 KB or
//   less, every even byte FF.
//
// Both go into the RAM as they come. A file whose even bytes are all the same
// value is the second kind: once the slots are all in, its odd bytes are
// moved down into place, the rest of the RAM set to FF, with the console held
// in reset (busy) from the file's first word until that is done. Back to back,
// the even bytes are the save's own and never all alike, bar a save of one
// byte, which reads the same either way. A save is written back in
// Spiritualized's layout, 128 KB (the size core_top puts in the data table).

module save_layout #(
    parameter [15:0] SLOT_ID = 16'd10
) (
    input  wire        clk_74a,
    input  wire        clk_sys,

    // the Pocket says the file's size as it asks to write the slot
    input  wire        dataslot_requestwrite,
    input  wire [15:0] dataslot_requestwrite_id,
    input  wire [31:0] dataslot_requestwrite_size,

    // clk_74a: the slots are all in (Data slot access all complete)
    input  wire        slots_done,
    // clk_sys: the game coming in, so a repack is only ever at a game's start
    input  wire        game_loading,
    // clk_sys: the RAM is being repacked; the console is to stay in reset
    output wire        busy,

    // data_loader: the file's bytes at wr_addr and +1, the first in [7:0]
    input  wire        wr,
    input  wire [16:0] wr_addr,
    input  wire [15:0] wr_data,

    // data_unloader, the same way round
    input  wire [16:0] rd_addr,
    output wire [15:0] rd_data,

    // the RAM's port B: a word is RAM bytes 2n in [7:0] and 2n+1 in [15:8],
    // its read a clock after its address
    output wire        ram_we,
    output wire [14:0] ram_addr,
    output wire [15:0] ram_di,
    input  wire [15:0] ram_do
);

reg        back_to_back_74 = 0;
reg [16:0] size_74 = 0;
always @(posedge clk_74a) begin
    if (dataslot_requestwrite && dataslot_requestwrite_id == SLOT_ID) begin
        back_to_back_74 <= dataslot_requestwrite_size != 0 && dataslot_requestwrite_size <= 32'd65536;
        size_74         <= dataslot_requestwrite_size[16:0];
    end
end

// set before the file's first byte comes, and steady while it loads
reg [1:0]  back_to_back_s = 0;
reg [16:0] size_s [0:1];
initial begin size_s[0] = 0; size_s[1] = 0; end
always @(posedge clk_sys) begin
    back_to_back_s <= {back_to_back_s[0], back_to_back_74};
    size_s[0] <= size_74;
    size_s[1] <= size_s[0];
end
wire        back_to_back = back_to_back_s[1];
wire [16:0] size = size_s[1];

wire done_s;
synch_3 done_sync (slots_done, done_s, clk_sys);

// Spiritualized's: a RAM word is the odd bytes of two file words, so the
// first is held until the second comes
reg [7:0] wr_lo = 0;
always @(posedge clk_sys) if (wr & ~wr_addr[1]) wr_lo <= wr_data[15:8];

// What the file is, as it comes. A repack can be asked once a game has come
// in (armed), by a short file's first word (pending), and is let go by any
// even byte of the file unlike the first (a word past the file's end, the
// last bridge word's padding, doesn't count).
reg        armed = 0, pending = 0;
reg [7:0]  even0 = 0;
reg [6:0]  quiet = 0;        // clocks since the file's last word, to its end
reg        packing = 0;
reg [15:0] pk_w = 0;         // the RAM word being written, 0 to 32767, then done
reg [1:0]  pk_t = 0;         // its four clocks: the lower source, the upper, write
reg [7:0]  pk_lo = 0;
reg [14:0] pk_addr = 0;
reg [15:0] pk_di = 0;
reg        pk_we = 0;

// the source bytes of RAM word w: file bytes 4w+1 and 4w+3, which are the
// upper bytes of RAM words 2w and 2w+1; FF past the file's end
wire [16:0] src_lo = {pk_w[14:0], 2'b01};
wire [16:0] src_hi = {pk_w[14:0], 2'b11};

always @(posedge clk_sys) begin
    pk_we <= 0;
    if (game_loading) armed <= 1;

    if (wr) quiet <= 0;
    else if (~&quiet) quiet <= quiet + 1'd1;

    if (wr & back_to_back & armed & wr_addr < size) begin
        if (wr_addr == 0) begin
            pending <= 1;
            even0   <= wr_data[7:0];
        end else if (wr_data[7:0] != even0)
            pending <= 0;
    end

    if (game_loading) pending <= 0;

    // the slots are all in, and nothing has come for a while
    if (armed & done_s & &quiet & ~packing & ~game_loading) begin
        armed <= 0;
        if (pending) begin
            packing <= 1;
            pk_w    <= 0;
            pk_t    <= 0;
        end
    end

    if (packing) begin
        pk_t <= pk_t + 1'd1;
        case (pk_t)
            2'd0: pk_addr <= {pk_w[13:0], 1'b0};
            2'd1: pk_addr <= {pk_w[13:0], 1'b1};
            2'd2: pk_lo   <= src_lo < size ? ram_do[15:8] : 8'hFF;
            2'd3: begin
                pk_addr <= pk_w[14:0];
                pk_di   <= pk_w[14] ? 16'hFFFF :
                           {src_hi < size ? ram_do[15:8] : 8'hFF, pk_lo};
                pk_we   <= 1;
                pk_w    <= pk_w + 1'd1;
                if (pk_w == 16'd32767) begin
                    packing <= 0;
                    pending <= 0;
                end
            end
        endcase
    end
end

// port B is the repack's until its last word is written, the clock after it
// ends; the console waits from a short file's first word until then
wire pk_port = packing | pk_we;
assign busy = pending | pk_we;

assign ram_we   = pk_port ? pk_we : wr & (back_to_back | wr_addr[1]);
assign ram_di   = pk_port ? pk_di :
                  back_to_back ? wr_data : {wr_data[15:8], wr_lo};
assign ram_addr = pk_port ? pk_addr :
                  ~ram_we ? rd_addr[16:2] :
                  back_to_back ? wr_addr[15:1] : wr_addr[16:2];

assign rd_data  = rd_addr[1] ? {2{ram_do[15:8]}} : {2{ram_do[7:0]}};

endmodule
