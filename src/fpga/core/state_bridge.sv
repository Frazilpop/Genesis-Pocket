// Save states between the Pocket's bridge and system.sv's state window.
//
// Saving: Savestate Start asks system.sv for its clean point; ok once frozen.
// The Pocket then reads the file from the 0x4 window. The bridge gives back
// what the read before it fetched (apf/io_bridge_peripheral.v) and reads every
// 88 clocks of clk_74a at the fastest, so its reads are answered from a pair of
// words held ready: each read takes the pair fetched ahead and starts the next
// (a word is 24 clocks of clk_sys, in the file's order: the YM2612's scan moves
// as it is read). The same address read again, as the Pocket does (agg23's NES
// core found the same), is answered from the pair it had, with no new word
// fetched. After the last pair, or when the reads stop, the game goes on.
//
// Loading: the file comes before Savestate Load. The first 16 words are checked
// against the ROM loaded; if they match, the console stops and the words go into
// the chips as they come. Savestate Load then lets it go. A file that does not
// match leaves the game running, and Savestate Load answers with an error.
//
// A state keeps its own timing. One made at 50 Hz loaded into a game started at
// 60, or the other way, is taken: once the file is in, `pal_take` asks core_top.sv
// for the file's clock (`pal_file`), and the console, stopped and kept out of
// reset by `hold_reset`, is let go only when pal_clock.sv has it.
//
// Words are big-endian in the file. The bridge's words are as data_loader's and
// data_unloader's are with bridge_endian_little 0: {first word, second word}.

module state_bridge (
    input  wire        clk_74a,
    input  wire        clk_sys,

    input  wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output reg  [31:0] bridge_rd_data = 0,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,

    input  wire        savestate_start,
    output wire        savestate_start_ack,
    output wire        savestate_start_busy,
    output wire        savestate_start_ok,
    output wire        savestate_start_err,

    input  wire        savestate_load,
    output wire        savestate_load_ack,
    output wire        savestate_load_busy,
    output wire        savestate_load_ok,
    output wire        savestate_load_err,

    input  wire        reset_n,             // clk_74a: the Pocket's reset of the core
    input  wire        pal,                 // clk_74a: what the chips are told (pal_clock.sv)
    input  wire        pal_hold,            // clk_74a: pal_clock.sv changing the clock
    input  wire        svp,                 // a game with the SVP: the format's version 2, the longer file

    // the ROM as it loads, for the header's cartridge part (clk_sys)
    input  wire        cart_download,
    input  wire        ioctl_wr,
    input  wire [24:0] ioctl_addr,
    input  wire [15:0] ioctl_data,
    input  wire [31:0] rom_size,

    // system.sv's state window (clk_sys)
    output reg         ss_save = 0,
    output reg         ss_load = 0,
    output reg         ss_go = 0,
    input  wire  [1:0] ss_status,
    output reg  [17:0] ss_addr = 0,
    output reg         ss_rd = 0,
    input  wire [15:0] ss_do,
    output reg         ss_wr = 0,
    output reg  [15:0] ss_di = 0,

    output wire        pause_lift,          // a save or a load under way: the menu's pause lifted
    output reg         hold_reset = 0,      // a load under way: the console kept out of the Pocket's reset
    output wire        load_blank,          // the chips filling, from the header's match until the load lets go
    output reg         pal_take = 0,        // a clock: the file is in, run on its timing from now on
    output reg         pal_file = 0         // that timing: 1 PAL
);

wire [16:0] PAIRS = svp ? 17'h11000 : 17'hD000;    // the file, 0x44000 or 0x34000 bytes, in the bridge's words
wire [17:0] LAST  = svp ? 18'h21FFF : 18'h19FFF;   // its last word
localparam [28:0] CLK_2S   = 29'd107386364;
localparam [28:0] CLK_5S   = 29'd268465909;
localparam [24:0] CLK_QS   = 25'd13423295;     // a quarter of a second

// ---- the commands, from clk_74a ----

reg ack_start = 0, ack_load = 0;
reg start_busy = 0, start_ok = 0, start_err = 0;
reg load_busy = 0, load_ok = 0, load_err = 0;

wire start_s, load_s, reset_n_s, pal_s, pal_hold_s;
synch_3 #(.WIDTH(5)) cmd_s ({savestate_start, savestate_load, reset_n, pal, pal_hold}, {start_s, load_s, reset_n_s, pal_s, pal_hold_s}, clk_sys);
synch_3 #(.WIDTH(8)) flags_s (
    {ack_start, start_busy, start_ok, start_err, ack_load, load_busy, load_ok, load_err},
    {savestate_start_ack, savestate_start_busy, savestate_start_ok, savestate_start_err,
     savestate_load_ack, savestate_load_busy, savestate_load_ok, savestate_load_err},
    clk_74a
);

// ---- the reads, from clk_74a ----

reg        rd_d = 0, kick_t = 0;
reg [16:0] kick_a = 0;
reg        kick_in = 0;
always @(posedge clk_74a) begin
    rd_d <= bridge_rd;
    if (bridge_rd & ~rd_d && bridge_addr[31:28] == 4'h4) begin
        kick_a  <= bridge_addr[18:2];
        kick_in <= bridge_addr[27:19] == 0 && bridge_addr[18:2] < PAIRS;
        kick_t  <= ~kick_t;
    end
end

// the pair on the bus: steady from bus_t's change until the next read
reg  [31:0] bus_d = 0;
reg         bus_t = 0, bus_t_d = 0;
wire        bus_t_s;
synch_3 bus_s (bus_t, bus_t_s, clk_74a);
always @(posedge clk_74a) begin
    bus_t_d <= bus_t_s;
    if (bus_t_s != bus_t_d)
        bridge_rd_data <= bridge_endian_little ?
            {bus_d[7:0], bus_d[15:8], bus_d[23:16], bus_d[31:24]} : bus_d;
end

wire kick_s;
reg  kick_d = 0;
synch_3 kick_sync (kick_t, kick_s, clk_sys);
wire kick = kick_s != kick_d;

// ---- the writes ----

wire        ld_we;
wire [18:0] ld_addr;
wire [15:0] ld_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4(4'h4),
    .ADDRESS_SIZE(19),
    .WRITE_MEM_CLOCK_DELAY(24),
    .OUTPUT_WORD_SIZE(2)
) state_loader (
    .clk_74a(clk_74a),
    .clk_memory(clk_sys),

    .bridge_wr(bridge_wr),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data),

    .write_en(ld_we),
    .write_addr(ld_addr),
    .write_data(ld_data)
);

wire [17:0] ld_w = ld_addr[18:1];
wire [15:0] ld_d = {ld_data[7:0], ld_data[15:8]};   // the file's first byte is data_loader's [7:0]

// ---- the header's cartridge part: 0x180-0x18F of the ROM ----

reg [15:0] cart_hdr [0:7];

reg ld_match;
always @* begin
    case (ld_w[3:0])
        4'd0:    ld_match = ld_d == 16'h4750;       // GPSS
        4'd1:    ld_match = ld_d == 16'h5353;
        4'd2:    ld_match = ld_d == (svp ? 16'h0002 : 16'h0001);   // the format's version
        4'd3:    ld_match = 1'b1;                   // the flags: PAL is taken from them (pal_file)
        4'd4:    ld_match = ld_d == (svp ? 16'h0004 : 16'h0003);   // its size
        4'd5:    ld_match = ld_d == 16'h4000;
        4'd6:    ld_match = ld_d == {7'd0, rom_size[24:16]};
        4'd7:    ld_match = ld_d == {rom_size[15:1], 1'b0};
        default: ld_match = ld_d == cart_hdr[ld_w[2:0]];
    endcase
end

// ---- the machine ----

localparam B_IDLE = 0, B_SEEK = 1, B_READ = 2, B_UNWIND = 3, B_LOADING = 4, B_LGO = 5, B_LRUN = 6, B_LCLK = 7;
reg   [2:0] st = B_IDLE;
reg         start_d = 0, load_d = 0;
reg   [2:0] ack_dly_s = 0, ack_dly_l = 0;
reg  [28:0] tmr = 0;
reg         rd_any = 0, all_read = 0;

// the words: a pair being fetched, the pair fetched ahead, the pair on the bus
reg         eng_busy = 0, eng_half = 0;
reg   [4:0] eng_cnt = 0;
reg  [16:0] eng_a = 0;
reg  [15:0] eng_w0 = 0;
reg         nxt_ok = 0, cur_ok = 0, want = 0;
reg  [16:0] nxt_a = 0, cur_a = 0, want_a = 0;
reg  [31:0] nxt_d = 0, cur_d = 0;

wire [15:0] eng_word = (ss_addr[17:4] == 0 && ss_addr[3]) ? cart_hdr[ss_addr[2:0]] : ss_do;
wire [16:0] fetch_a  = cur_ok ? cur_a + 1'd1 : 17'd0;
wire        reading  = st == B_READ || st == B_UNWIND;

// the load's file
reg         ld_bad = 1, ld_last = 0, load_pend = 0;
reg  [24:0] clk_wait = 0;
reg   [5:0] ld_quiet = 0;

assign pause_lift = st != B_IDLE;
assign load_blank = st == B_LOADING || st == B_LCLK || st == B_LGO || st == B_LRUN;

always @(posedge clk_sys) begin
    ss_save <= 0; ss_load <= 0; ss_go <= 0; ss_rd <= 0; ss_wr <= 0; pal_take <= 0;
    start_d <= start_s; load_d <= load_s; kick_d <= kick_s;

    if (cart_download & ioctl_wr && ioctl_addr[24:4] == 21'h18)
        cart_hdr[ioctl_addr[3:1]] <= {ioctl_data[7:0], ioctl_data[15:8]};

    // an ack a few clocks after busy and the old answers are gone, so the
    // command's own result code is the new one; it goes when the command does
    if (ack_dly_s) ack_dly_s <= ack_dly_s - 1'd1;
    if (ack_dly_s == 1) ack_start <= 1;
    if (~start_s) ack_start <= 0;
    if (ack_dly_l) ack_dly_l <= ack_dly_l - 1'd1;
    if (ack_dly_l == 1) ack_load <= 1;
    if (~load_s) ack_load <= 0;

    tmr <= tmr + 1'd1;

    // ---- Savestate Start ----
    if (start_s & ~start_d) begin
        ack_dly_s <= 3'd4;
        start_ok <= 0; start_err <= 0; load_ok <= 0; load_err <= 0;
        if ((st == B_IDLE && (ss_status == 2'd0 || ss_status == 2'd3)) || (st == B_LRUN && ss_status == 2'd2)) begin
            start_busy <= 1;
            ss_save <= 1;
            tmr <= 0;
            rd_any <= 0; all_read <= 0; want <= 0; nxt_ok <= 0; cur_ok <= 0;
            st <= B_SEEK;
        end
        else start_err <= 1;
    end

    // ---- Savestate Load ----
    if (load_s & ~load_d) begin
        ack_dly_l <= 3'd4;
        start_ok <= 0; start_err <= 0; load_ok <= 0; load_err <= 0;
        if (st == B_LOADING) begin
            load_busy <= 1;
            load_pend <= 1;
        end
        else load_err <= 1;
    end

    // ---- the file coming in ----
    if (&ld_quiet == 0) ld_quiet <= ld_quiet + 1'd1;
    if (ld_we) begin
        ld_quiet <= 0;
        if (ld_w == 0) begin ld_bad <= ~ld_match; ld_last <= 0; end
        else if (ld_w < 17'd15) begin
            if (~ld_match) ld_bad <= 1;
            if (ld_w == 17'd3 && st == B_IDLE) pal_file <= ld_d[0];
        end
        else if (ld_w == 17'd15) begin
            // the whole header seen: stop the console for the state
            if (~ld_bad && ld_match && st == B_IDLE && (ss_status == 2'd0 || ss_status == 2'd3)) begin
                ss_load <= 1;
                hold_reset <= 1;
                st <= B_LOADING;
            end
        end
        else if (st == B_LOADING && ld_w <= LAST) begin
            ss_addr <= ld_w;
            ss_di <= ld_d;
            ss_wr <= 1;
            if (ld_w == LAST) ld_last <= 1;
        end
    end

    // ---- the words going out ----
    if (kick) begin
        tmr <= 0;
        if (reading) begin
            rd_any <= 1;
            if (kick_in) begin want <= 1; want_a <= kick_a; end
        end
    end

    if (eng_busy) begin
        eng_cnt <= eng_cnt + 1'd1;
        if (eng_cnt == 5'd23) begin
            eng_cnt <= 0;
            if (~eng_half) begin
                eng_w0 <= eng_word;
                eng_half <= 1;
                ss_addr <= ss_addr + 1'd1;
                ss_rd <= 1;
            end
            else begin
                nxt_d <= {eng_w0, eng_word};
                nxt_a <= eng_a;
                nxt_ok <= 1;
                eng_busy <= 0;
            end
        end
    end

    if (want && reading) begin
        if (cur_ok && want_a == cur_a) begin
            bus_d <= cur_d;
            bus_t <= ~bus_t;
            want <= 0;
        end
        else if (nxt_ok && want_a == nxt_a) begin
            cur_a <= nxt_a;
            cur_d <= nxt_d;
            cur_ok <= 1;
            nxt_ok <= 0;
            bus_d <= nxt_d;
            bus_t <= ~bus_t;
            want <= 0;
            if (nxt_a == PAIRS - 1'd1) all_read <= 1;
        end
        else if (~eng_busy) begin
            // not the word expected: read from where it asks
            nxt_ok <= 0;
            eng_a <= want_a; eng_half <= 0; eng_cnt <= 0; eng_busy <= 1;
            ss_addr <= {want_a, 1'b0};
            ss_rd <= 1;
        end
    end
    else if (st == B_READ && ~eng_busy && ~nxt_ok && fetch_a != PAIRS) begin
        eng_a <= fetch_a; eng_half <= 0; eng_cnt <= 0; eng_busy <= 1;
        ss_addr <= {fetch_a, 1'b0};
        ss_rd <= 1;
    end

    // ---- where it is ----
    case (st)
    B_SEEK:
        if (tmr >= 29'd4) begin
            if (ss_status == 2'd2) begin
                start_busy <= 0; start_ok <= 1;
                tmr <= 0;
                st <= B_READ;
            end
            else if (ss_status == 2'd3) begin
                start_busy <= 0; start_err <= 1;
                st <= B_IDLE;
            end
        end

    B_READ:
        // the last word read, or the reads stopped: the game goes on
        if (~eng_busy && (all_read || tmr >= (rd_any ? CLK_2S : CLK_5S))) begin
            ss_go <= 1;
            tmr <= 0;
            st <= B_UNWIND;
        end

    B_UNWIND:
        if (tmr >= 29'd4 && (ss_status == 2'd0 || ss_status == 2'd3)) st <= B_IDLE;

    B_LOADING:
        if (load_pend && &ld_quiet) begin
            // the file is in: its timing from now on, and if that is a change of
            // clock, the console stays stopped until the clock has settled
            load_pend <= 0;
            pal_take <= 1;
            tmr <= 0;
            clk_wait <= 0;
            if (pal_file == pal_s) begin
                ss_go <= 1;
                st <= B_LGO;
            end
            else st <= B_LCLK;
        end

    B_LCLK:
        // pal changes as pal_clock.sv starts, with its hold already up; let go once
        // both have been steady a while, the hold down and the timing the file's.
        // A clock that never comes (the PLL locks again in far less) mustn't hang
        // the Pocket's load: after a quarter of a second the game goes on regardless.
        begin
            clk_wait <= clk_wait + 1'd1;
            if (pal_file != pal_s || pal_hold_s) tmr <= 0;
            if ((tmr >= 29'd64 && pal_file == pal_s && !pal_hold_s) || clk_wait == CLK_QS) begin
                ss_go <= 1;
                tmr <= 0;
                st <= B_LGO;
            end
        end

    B_LGO:
        if (tmr >= 29'd4) begin
            if (ss_status == 2'd3 || (ss_status != 2'd1 && ~ld_last)) begin
                load_busy <= 0; load_err <= 1;
                st <= ss_status == 2'd3 ? B_IDLE : B_LRUN;
            end
            else if (ss_status != 2'd1) begin
                load_busy <= 0; load_ok <= 1;
                st <= B_LRUN;
            end
        end

    B_LRUN:
        if (ss_status == 2'd0 || ss_status == 2'd3) st <= B_IDLE;

    default: ;
    endcase

    if (hold_reset && st == B_IDLE && reset_n_s) hold_reset <= 0;

    // a new ROM: back to the start (system.sv's save logic resets with it)
    if (cart_download) begin
        st <= B_IDLE;
        hold_reset <= 0;
        ld_bad <= 1; ld_last <= 0; load_pend <= 0;
        want <= 0; eng_busy <= 0; nxt_ok <= 0; cur_ok <= 0;
        start_busy <= 0; load_busy <= 0;
    end
end

endmodule
