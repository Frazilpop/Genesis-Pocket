// RndMnkIII's Analogizer in the cartridge slot: the console's picture out of the
// adapter's VGA connector (RGBS, RGsB, YPbPr, Y/C NTSC and PAL, or the scandoubler's
// 31 kHz), and SNAC controllers in for any of the four players, through his
// openFPGA_Pocket_Analogizer (src/fpga/analogizer/).
//
// CLOCK. Everything here is on clk_sys, the console's master clock, as the picture is:
// the VDP's dot is ce_pix, one clk_sys in 8 in H40 and one in 10 in H32, and the colours
// and syncs change on it. The module's DAC clock (the cartridge pin bank1[5]) is clk_sys
// too, 53.69 MHz, or 53.20 once a PAL game has the clock (pal_clock.sv), so no picture
// crosses a clock. The scandoubler takes a sample every 8 or 10 clocks from where hsync
// ends (its divider, one less, follows H40) and gives each twice as fast.
//
// Y/C. yc_out's colour subcarrier is a step of a 40-bit phase per clock,
// f * 2^40 / clk_sys, so it follows the clock the console is on: four steps, NTSC's
// 3.579545 MHz or PAL's 4.43361875 MHz on either clock. Its burst starts 60 clocks after
// hsync ends and runs to 173 (PAL) or 186 (NTSC), 1.1 to 3.5 us, which its own table
// picks for a clock of this speed; the console's picture starts 50 dots after hsync
// ends in H40 and 40 in H32 (400 clocks either way), so the burst is clear of it and
// the console's hsync goes to the adapter as it is.
//
// SETTINGS come from analogizer.bin, the file the Analogizer's configurators write to
// Assets/analogizer/common/ and every Analogizer core that reads it shares: data slot
// 330 (data.json), platform index 1 (core.json's second platform id, "analogizer"),
// loaded to 0xF7000000. It is one 32-bit word, little-endian; the bridge is big-endian
// here (bridge_endian_little = 0), so the file's first byte arrives in [31:24] and the
// bytes are turned back round:
//
//   [4:0]   SNAC controller: 0 none, 1 DB15, 2 NES, 3 SNES, 4 PC Engine 2-button,
//           5 6-button, 6 multitap, 9 DB15 fast, 0xB SNES with A,B and X,Y swapped
//           (the ones taken here; the PS/2 and PlayStation types and JVS are not, and
//           leave the Pocket's controls in place)
//   [5]     Analogizer on
//   [9:6]   SNAC assignment: 0 SNAC 1 -> player 1, 1 SNAC 1 -> player 2,
//           2 SNAC 1, 2 -> players 1, 2, 3 SNAC 1, 2 -> players 2, 1,
//           4 SNAC 1, 2 -> players 3, 4, 5 SNAC 1-4 -> players 1-4 (3 and 4 only from
//           the PC Engine multitap; with any other controller they stay the Pocket's)
//   [13:10] video: 0 RGBS, 1 RGsB, 2 YPbPr, 3 Y/C NTSC, 4 Y/C PAL, 5-8 the scandoubler
//           (31 kHz RGBHV) with scanlines of 0, 25, 50 and 75 %, 9 HQ2x, which this
//           module has not got: the scandoubler without scanlines. The module's own
//           codes are older (5-7 the scandoubler, its scanlines on fx; 8-F the same
//           modes with the Pocket's screen off), so the file's are turned into them.
//   [14]    the Pocket's own screen black
//   [15]    OSD on the adapter's output, [19:16] region: nothing here uses them
//
// No file, or [5] clear, is the Analogizer off: the module holds the pins idle, which is
// the template's tie-off for every pin but pin30 (the module lets it float as an input,
// the template drives it low and leaves its direction to the hardware), so pin30 is
// driven as the template has it here. A Pocket with no adapter, or no file, sees the
// slot as before, and the players' controls are the Pocket's.
//
// SNAC words come out in the Pocket's controller order (key[15:0]: up, down, left,
// right, A, B, X, Y, L1, R1, L2, R2, L3, R3, select, start), so they stand in for
// cont1_key to cont4_key as they are, and the console's pads are made from them as
// from the Pocket's (core_top.sv, Controls). key1 to key4 are each a player's.

`default_nettype none

module pocket_analogizer (
    input  wire        clk_74a,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,

    input  wire        clk_sys,
    input  wire        pal,                 // clk_sys: the console is on PAL's clock
    input  wire        h40,                 // clk_sys: a dot is 8 clocks, not 10
    input  wire        ce_pix,
    input  wire        hs, vs,              // active high
    input  wire        hblank, vblank,
    input  wire [7:0]  r, g, b,
    output wire        pocket_off,          // clk_sys: the Pocket's own screen to black

    input  wire [15:0] cont1_key, cont2_key, cont3_key, cont4_key, // the Pocket's (clk_74a)
    output wire [15:0] key1, key2, key3, key4,                     // the players'

    inout  wire [7:0]  cart_tran_bank2,
    output wire        cart_tran_bank2_dir,
    inout  wire [7:0]  cart_tran_bank3,
    output wire        cart_tran_bank3_dir,
    inout  wire [7:0]  cart_tran_bank1,
    output wire        cart_tran_bank1_dir,
    inout  wire [7:4]  cart_tran_bank0,
    output wire        cart_tran_bank0_dir,
    inout  wire        cart_tran_pin30,
    output wire        cart_tran_pin30_dir,
    output wire        cart_pin30_pwroff_reset,
    inout  wire        cart_tran_pin31,
    output wire        cart_tran_pin31_dir
);

    // ------------------------------------------------------- the settings
    reg  [15:0] cfg_74 = 16'd0;
    always @(posedge clk_74a)
        if (bridge_wr && bridge_addr == 32'hF7000000)
            cfg_74 <= {bridge_wr_data[23:16], bridge_wr_data[31:24]};

    // (a word the Pocket writes once as a game comes in, held long after)
    wire [15:0] cfg;
    synch_3 #(.WIDTH(16)) cfg_s (cfg_74, cfg, clk_sys);

    wire        on      = cfg[5];
    wire [4:0]  ctype   = cfg[4:0];
    wire [3:0]  assign_ = cfg[9:6];
    wire [3:0]  vtype   = cfg[13:10];
    assign pocket_off = on & cfg[14];

    reg  [3:0]  m_vtype = 4'd0;             // the module's video code
    reg  [1:0]  m_lines = 2'd0;             // its scanlines (fx[1:0])
    reg         snac_ok = 1'b0;
    reg  [2:0]  sel1 = 3'd0, sel2 = 3'd0,   // each player's: 0 the Pocket's controls,
                sel3 = 3'd0, sel4 = 3'd0;   //   1 to 4 SNAC 1 to 4
    always @(posedge clk_sys) begin
        m_vtype <= (vtype <= 4'd4) ? vtype : (vtype <= 4'd9) ? 4'd5 : 4'd0;
        m_lines <= (vtype >= 4'd5 && vtype <= 4'd8) ? vtype[1:0] - 2'd1 : 2'd0;
        case (ctype)
        5'h01, 5'h02, 5'h03, 5'h04, 5'h05, 5'h06, 5'h09, 5'h0B: snac_ok <= on;
        default:                                               snac_ok <= 1'b0;
        endcase
        sel1 <= !snac_ok ? 3'd0 :
                (assign_ == 4'd0 || assign_ == 4'd2 || assign_ == 4'd5) ? 3'd1 :
                (assign_ == 4'd3) ? 3'd2 : 3'd0;
        sel2 <= !snac_ok ? 3'd0 :
                (assign_ == 4'd1 || assign_ == 4'd3) ? 3'd1 :
                (assign_ == 4'd2 || assign_ == 4'd5) ? 3'd2 : 3'd0;
        sel3 <= !snac_ok ? 3'd0 :
                (assign_ == 4'd4) ? 3'd1 :
                (assign_ == 4'd5 && ctype == 5'h06) ? 3'd3 : 3'd0;
        sel4 <= !snac_ok ? 3'd0 :
                (assign_ == 4'd4) ? 3'd2 :
                (assign_ == 4'd5 && ctype == 5'h06) ? 3'd4 : 3'd0;
    end

    wire [15:0] snac1, snac2, snac3, snac4;
    function automatic [15:0] pick(input [2:0] sel, input [15:0] pocket,
                                   input [15:0] s1, input [15:0] s2, input [15:0] s3, input [15:0] s4);
        case (sel)
        3'd1:    pick = s1;
        3'd2:    pick = s2;
        3'd3:    pick = s3;
        3'd4:    pick = s4;
        default: pick = pocket;
        endcase
    endfunction
    assign key1 = pick(sel1, cont1_key, snac1, snac2, snac3, snac4);
    assign key2 = pick(sel2, cont2_key, snac1, snac2, snac3, snac4);
    assign key3 = pick(sel3, cont3_key, snac1, snac2, snac3, snac4);
    assign key4 = pick(sel4, cont4_key, snac1, snac2, snac3, snac4);

    // Y/C: f * 2^40 / clk_sys for 53.693175 and 53.203424 MHz (pal_clock.sv's K)
    wire        yc_pal = (m_vtype == 4'd4);
    reg  [39:0] phase_inc = 40'd0;
    always @(posedge clk_sys)
        phase_inc <= yc_pal ? (pal ? 40'd91625970704 : 40'd90790223688)
                            : (pal ? 40'd73975527396 : 40'd73300775186);

    // ----------------------------------------------------------- the dot
    // Registered once, so only registers drive the module's paths to the pins. A line's
    // vblank is taken where its picture starts (hblank's end): the scandoubler notes
    // where in a line vblank changed and replays it there in both lines it makes, so it
    // must change inside the line, and the VDP's moves a few dots before a picture ends.
    reg  [7:0]  vr = 8'd0, vg = 8'd0, vb = 8'd0;
    reg         vhs = 1'b0, vvs = 1'b0, vhb = 1'b1, vvb = 1'b1;
    reg         hb_was = 1'b1;
    always @(posedge clk_sys) begin
        {vr, vg, vb} <= {r, g, b};
        {vhs, vvs, vhb} <= {hs, vs, hblank};
        hb_was <= hblank;
        if (hb_was && !hblank) vvb <= vblank;
    end
    wire        vde = ~(vhb | vvb);

    // --------------------------------------------------------- the module
    wire        m_pin30, m_pin30_dir;

    openFPGA_Pocket_Analogizer #(
        .MASTER_CLK_FREQ (53_693_175),
        .LINE_LENGTH     (420)              // dots a line in H40 (the module doesn't use it)
    ) u_anz (
        .i_clk            (clk_sys),
        .i_rst            (1'b0),
        .i_ena            (on),
        .video_clk        (clk_sys),
        .analog_video_type(m_vtype),
        .R (vr), .G (vg), .B (vb),
        .Hblank (vhb),    .Vblank (vvb),    .BLANKn (vde),
        .Hsync  (vhs),    .Vsync  (vvs),
        .Csync  (~(vhs ^ vvs)),             // active low, serrated in vsync
        .CHROMA_PHASE_INC (phase_inc),
        .PALFLAG          (yc_pal),
        .ce_pix           (ce_pix),
        .scandoubler      (1'b1),
        .sd_ce_divider    (h40 ? 4'd7 : 4'd9),
        .fx               ({1'b0, m_lines}),
        .conf_AB          (1'b0),
        .game_cont_type   (snac_ok ? ctype : 5'd0),
        .p1_btn_state     (snac1), .p1_joy_state (),
        .p2_btn_state     (snac2), .p2_joy_state (),
        .p3_btn_state     (snac3), .p4_btn_state (snac4),
        .i_VIB_SW1 (2'b00), .i_VIB_DAT1 (8'h00), .i_VIB_SW2 (2'b00), .i_VIB_DAT2 (8'h00),
        .busy             (),
        .cart_tran_bank2  (cart_tran_bank2), .cart_tran_bank2_dir (cart_tran_bank2_dir),
        .cart_tran_bank3  (cart_tran_bank3), .cart_tran_bank3_dir (cart_tran_bank3_dir),
        .cart_tran_bank1  (cart_tran_bank1), .cart_tran_bank1_dir (cart_tran_bank1_dir),
        .cart_tran_bank0  (cart_tran_bank0), .cart_tran_bank0_dir (cart_tran_bank0_dir),
        .cart_tran_pin30  (m_pin30),         .cart_tran_pin30_dir (m_pin30_dir),
        .cart_pin30_pwroff_reset (cart_pin30_pwroff_reset),
        .cart_tran_pin31  (cart_tran_pin31), .cart_tran_pin31_dir (cart_tran_pin31_dir),
        .DBG_TX (), .o_stb ()
    );

    // pin30 is only ever an output with the adapter (its SNAC clock 2)
    assign cart_tran_pin30     = on ? m_pin30     : 1'b0;
    assign cart_tran_pin30_dir = on ? m_pin30_dir : 1'bz;

endmodule

`default_nettype wire
