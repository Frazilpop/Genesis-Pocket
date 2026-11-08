//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// the cartridge slot is the Analogizer's (pocket_analogizer.sv, with the picture), idle
// as the template leaves it when there is no adapter or no analogizer.bin

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


///////////////////////////////////////////////////////////////////////////////
// The bridge's map
//
//   0x0xxxxxxx   the settings below, written by Core Settings (interact.json)
//   0x1xxxxxxx   the game, data slot 0
//   0x4xxxxxxx   save states
//   0x6xxxxxxx   the game's own save, data slot 10
//   0xF8xxxxxx   the host's commands and the data table
///////////////////////////////////////////////////////////////////////////////

// Nothing answers an address not listed here.
localparam [31:0] SET_RESET      = 32'h0000_0100,
                  SET_REGION     = 32'h0000_0108,
                  SET_MENU_PAUSE = 32'h0000_0110,   // not offered in interact.json
                  SET_PAL_60     = 32'h0000_0114,
                  SET_BUTTONS    = 32'h0000_0200,
                  SET_MULTITAP   = 32'h0000_0204,
                  SET_GUN        = 32'h0000_020C,
                  SET_COMPOSITE  = 32'h0000_0304,
                  SET_SPRITES    = 32'h0000_0308,
                  SET_HIFI_PCM   = 32'h0000_0408,
                  SET_FILTER     = 32'h0000_040C,
                  SET_FM_CHIP    = 32'h0000_0410;

// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h4xxxxxxx: bridge_rd_data <= state_read_data;
    32'h6xxxxxxx: bridge_rd_data <= save_read_data;
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked; 
    wire            status_setup_done = pll_core_locked; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_allcomplete;

    wire            savestate_supported = 1;
    wire    [31:0]  savestate_addr = 32'h4000_0000;
    // A game with the SVP has the longer file. It is the longer one until a ROM says otherwise,
    // in case the Pocket asks before a game is in: a shorter game's file then has a tail nothing
    // reads, which a load ignores. A load takes either.
    reg             ss_long_file = 1;
    reg             svp_quirk = 0;
    wire    [31:0]  savestate_size = ss_long_file ? 32'h0004_4000 : 32'h0003_4000;
    wire    [31:0]  savestate_maxloadsize = 32'h0004_4000;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);


///////////////////////////////////////////////////////////////////////////////
// Clocks
///////////////////////////////////////////////////////////////////////////////

    wire    clk_sys;                // the console's master clock
    wire    clk_ram;                // twice it, for the SDRAM
    wire    clk_vid_320;            // a pixel clock for each width
    wire    clk_vid_320_90deg;
    wire    clk_vid_256;
    wire    clk_vid_256_90deg;

    // Locked the first time, and it stays: a change of clock for PAL can drop the PLL's
    // locked for a moment, which must not look to the Pocket or the SDRAM like starting over.
    wire    pll_raw_locked;
    reg     pll_locked_once = 0;
    always @(posedge clk_74a) if (pll_raw_locked) pll_locked_once <= 1;
    wire    pll_core_locked = pll_locked_once;

    wire    [63:0]  reconfig_to_pll, reconfig_from_pll;

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),

    .outclk_0       ( clk_sys ),
    .outclk_1       ( clk_ram ),
    .outclk_2       ( clk_vid_320 ),
    .outclk_3       ( clk_vid_320_90deg ),
    .outclk_4       ( clk_vid_256 ),
    .outclk_5       ( clk_vid_256_90deg ),

    .locked         ( pll_raw_locked ),
    .reconfig_to_pll    ( reconfig_to_pll ),
    .reconfig_from_pll  ( reconfig_from_pll )
);


///////////////////////////////////////////////////////////////////////////////
// Core Settings: each a register the menu writes, starting where the console starts
///////////////////////////////////////////////////////////////////////////////

reg  [1:0] cfg_region          = 0;     // 0 Auto, 1 USA, 2 Europe, 3 Japan
reg        cfg_pal_60          = 0;     // a game that would run at 50 Hz runs at 60
reg        cfg_menu_pause      = 0;
reg        cfg_3_buttons       = 0;
reg  [2:0] cfg_multitap        = 0;
reg        cfg_blend           = 0;
reg        cfg_blend_auto      = 0;
reg        cfg_many_sprites    = 0;
reg        cfg_hifi_pcm        = 0;     // the DAC's samples as a console plays them, not smoothed
reg  [1:0] cfg_filter          = 0;
reg        cfg_ym3438          = 0;

// Reset Core, Shane Lynch's: a reset of a varying length, held while the menu is open.
// Lightgun settings, his too.
reg [11:0] reset_counter       = 1;
reg [15:0] reset_delay         = 0;
reg lightgun_enabled           = 0;
wire [7:0] dpad_aim_speed      = 8'd4;   // the d-pad's step a frame, about a second across

always @(posedge clk_74a) begin
    reset_counter <= reset_counter + 1'd1;
    if (!osnotify_inmenu && reset_delay != 0) reset_delay <= reset_delay - 1'd1;

    if (bridge_wr)
        case (bridge_addr)
            SET_RESET:      if (bridge_wr_data != 0) reset_delay <= {reset_counter, 4'b1111};
            SET_REGION:     cfg_region          <= bridge_wr_data[1:0];
            SET_PAL_60:     cfg_pal_60          <= bridge_wr_data[0];
            SET_MENU_PAUSE: cfg_menu_pause      <= bridge_wr_data[0];
            SET_BUTTONS:    cfg_3_buttons       <= bridge_wr_data[0];
            SET_MULTITAP:   cfg_multitap        <= bridge_wr_data[2:0];
            SET_GUN:        lightgun_enabled    <= bridge_wr_data[0];
            SET_COMPOSITE:  {cfg_blend_auto, cfg_blend} <= bridge_wr_data[1:0];
            SET_SPRITES:    cfg_many_sprites    <= bridge_wr_data[0];
            SET_HIFI_PCM:   cfg_hifi_pcm        <= bridge_wr_data[0];
            SET_FILTER:     cfg_filter          <= bridge_wr_data[1:0];
            SET_FM_CHIP:    cfg_ym3438          <= bridge_wr_data[0];
            default: ;
        endcase
end


///////////////////////////////////////////////////////////////////////////////
// The data table: two words of it, on the core's port, in turn. Word 1 is the size
// of the game the Pocket has put in slot 0. Word 3 is the size the core asks the save
// back at, and the Pocket fills the table in as it starts a game, so it is written
// again all the time.
///////////////////////////////////////////////////////////////////////////////

reg  [1:0]  table_turn = 0;
reg  [31:0] game_bytes = 0;

assign datatable_wren = table_turn == 2'd0;
assign datatable_addr = datatable_wren ? 10'd3 : 10'd1;
assign datatable_data = 32'd131072;

always @(posedge clk_74a) begin
    table_turn <= table_turn + 1'd1;
    if (table_turn == 2'd3) game_bytes <= datatable_q;
end


///////////////////////////////////////////////////////////////////////////////
// The game's own save, between the bridge and the save RAM. The file is in
// Spiritualized's layout, so a .sav works in both cores (save_layout.sv)
///////////////////////////////////////////////////////////////////////////////

wire [31:0] save_read_data;

wire        save_wr;
wire [16:0] save_wr_addr;
wire [15:0] save_wr_data;
wire [16:0] save_rd_addr;
wire [15:0] save_rd_data;

wire        bram_we;
wire [14:0] bram_addr;
wire [15:0] bram_to_ram;
wire [15:0] bram_from_ram;

data_loader #(
    .ADDRESS_MASK_UPPER_4(4'h6),
    .ADDRESS_SIZE(17),
    .WRITE_MEM_CLOCK_DELAY(7),
    .OUTPUT_WORD_SIZE(2)
) save_in (
    .clk_74a(clk_74a),
    .clk_memory(clk_sys),

    .bridge_wr(bridge_wr),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data),

    .write_en(save_wr),
    .write_addr(save_wr_addr),
    .write_data(save_wr_data)
);

data_unloader #(
    .ADDRESS_MASK_UPPER_4(4'h6),
    .ADDRESS_SIZE(17),
    .READ_MEM_CLOCK_DELAY(7),
    .INPUT_WORD_SIZE(2)
) save_out (
    .clk_74a(clk_74a),
    .clk_memory(clk_sys),

    .bridge_rd(bridge_rd),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),
    .bridge_rd_data(save_read_data),

    .read_en(),
    .read_addr(save_rd_addr),
    .read_data(save_rd_data)
);

save_layout save_layout (
    .clk_74a(clk_74a),
    .clk_sys(clk_sys),

    .dataslot_requestwrite(dataslot_requestwrite),
    .dataslot_requestwrite_id(dataslot_requestwrite_id),
    .dataslot_requestwrite_size(dataslot_requestwrite_size),

    .wr(save_wr),
    .wr_addr(save_wr_addr),
    .wr_data(save_wr_data),

    .rd_addr(save_rd_addr),
    .rd_data(save_rd_data),

    .ram_we(bram_we),
    .ram_addr(bram_addr),
    .ram_di(bram_to_ram),
    .ram_do(bram_from_ram)
);


///////////////////////////////////////////////////////////////////////////////
// The game coming in: from the first slot asked for to the Pocket saying it is all
// done; a game only while the bridge is in its window, as a load's moments away
// from the ROM mustn't look like a word of it
///////////////////////////////////////////////////////////////////////////////

reg  slots_loading = 0;
always @(posedge clk_74a)
    slots_loading <= dataslot_requestwrite | (slots_loading & ~dataslot_allcomplete);

wire cart_download;
synch_3 cart_download_s (slots_loading && bridge_addr[31:28] == 4'h1, cart_download, clk_sys);

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4(4'h1),
    .ADDRESS_SIZE(25),
    .WRITE_MEM_CLOCK_DELAY(12),
    .WRITE_MEM_EN_CYCLE_LENGTH(4),
    .OUTPUT_WORD_SIZE(2)
) game_in (
    .clk_74a(clk_74a),
    .clk_memory(clk_sys),

    .bridge_wr(bridge_wr),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data),

    .write_en(ioctl_wr),
    .write_addr(ioctl_addr),
    .write_data(ioctl_data)
);


///////////////////////////////////////////////////////////////////////////////
// The region, as MiSTer's Genesis.sv reads it from the header, and the Region row
// on top of that
///////////////////////////////////////////////////////////////////////////////

reg  [1:0] region_req;
reg        region_set = 0;
reg        region_only_europe = 0;
reg        pal_frame = 0;         // clk_sys: this game turned on PAL's 240 lines at 60 Hz (below)
reg        mem_pal_on = 0;        // clk_sys: a loaded state's timing (mem_pal) holds, whatever the rows (below)
reg        mem_pal = 0;
always @(posedge clk_sys) begin
	reg old_ready = 0;

	old_ready <= cart_hdr_ready;
	if(~old_ready & cart_hdr_ready) begin
		region_set <= 1;
		if(hdr_u) region_req <= 1;
		else if(hdr_e) region_req <= 2;
		else if(hdr_j) region_req <= 0;
		else region_req <= 1;
		region_only_europe <= hdr_e & ~hdr_u & ~hdr_j;
	end

	if(old_ready & ~cart_hdr_ready) region_set <= 0;
end

// The rows as this game started. A game reads the region once, on its cold start, and
// that is a new start and nothing else, so nothing changes under a running game. The
// copies follow the rows while the core is held in reset, as the Pocket writes a saved
// value just before Reset Exit, and while a game comes in; then they stay.
reg [1:0] region_start = 0;
reg       pal_60_start = 0;
always @(posedge clk_74a) if (!reset_n || slots_loading) {pal_60_start, region_start} <= {cfg_pal_60, cfg_region};

// 0 Japan, 1 USA, 2 Europe
wire [1:0] region_now = region_start == 2'd1 ? 2'd1 :
                        region_start == 2'd2 ? 2'd2 :
                        region_start == 2'd3 ? 2'd0 : region_req;

// PAL on Europe chosen, or on Auto for a game made for Europe alone. Europe and Japan
// together (Alien Soldier's header) stays at 60 Hz: such a game was made for it.
wire says_pal = region_start == 2'd2 || (region_start == 2'd0 && region_only_europe);

// PAL 60 Hz: such a game on NTSC's timing, still reading PAL, or most made for Europe
// alone stop on a screen saying they are for PAL consoles. A game that turns on 240 lines goes to 50 Hz whatever the rows say. A
// loaded state runs on the timing it was made at until the game starts afresh.
wire want_pal = mem_pal_on ? mem_pal : pal_frame || (says_pal && !pal_60_start);

wire pal, pal_hold;

pal_clock pal_clock (
    .clk_74a(clk_74a),
    .want_pal(want_pal),
    .loading(slots_loading),
    .pll_locked(pll_raw_locked),
    .pal(pal),
    .hold(pal_hold),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);

wire [3:0] hrgn = ioctl_data[3:0] - 4'd7;

reg cart_hdr_ready = 0;
reg hdr_j=0,hdr_u=0,hdr_e=0;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= cart_download;

	if(~old_download && cart_download) {hdr_j,hdr_u,hdr_e} <= 0;
	if(old_download && ~cart_download) cart_hdr_ready <= 0;
	if(old_download && ~cart_download) ss_long_file <= svp_quirk;

	if(ioctl_wr & cart_download) begin
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
			else if(ioctl_data[7:0] >= "0" && ioctl_data[7:0] <= "9") {hdr_e, hdr_u, hdr_j} <= {ioctl_data[3], ioctl_data[2], ioctl_data[0]};
			else if(ioctl_data[7:0] >= "A" && ioctl_data[7:0] <= "F") {hdr_e, hdr_u, hdr_j} <= {      hrgn[3],       hrgn[2],       hrgn[0]};
		end
		if(ioctl_addr == 'h1F2) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[15:8] == "J") hdr_j <= 1;
			else if(ioctl_data[15:8] == "U") hdr_u <= 1;
			else if(ioctl_data[15:8] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h200) cart_hdr_ready <= 1;
	end
end


///////////////////////////////////////////////////////////////////////////////
// The SDRAM: the game going in on channel 0, the console on 1, the SVP on 2
///////////////////////////////////////////////////////////////////////////////

wire [24:1] rom_addr, rom_addr2;
wire [15:0] rom_data, rom_data2, rom_wdata;
wire  [1:0] rom_be;
wire rom_req, rom_rdack, rom_rd2, rom_rdack2, rom_we;

sdram sdram
(
	.init(~pll_core_locked),
	.clk(clk_ram),

	.addr0(ioctl_addr[24:1]),
	.din0({ioctl_data[7:0], ioctl_data[15:8]}),
	.dout0(),
	.wrl0(1),
	.wrh0(1),
	.req0(ioctl_wr),
	.ack0(),

	.addr1(rom_addr),
	.din1(rom_wdata),
	.dout1(rom_data),
	.wrl1(rom_we & rom_be[0]),
	.wrh1(rom_we & rom_be[1]),
	.req1(rom_req),
	.ack1(rom_rdack),

	.addr2(rom_addr2),
	.din2(0),
	.dout2(rom_data2),
	.wrl2(0),
	.wrh2(0),
	.req2(rom_rd2),
	.ack2(rom_rdack2),

	.SDRAM_DQ(dram_dq),
	.SDRAM_A(dram_a),
	.SDRAM_DQML(dram_dqm[0]),
	.SDRAM_DQMH(dram_dqm[1]),
	.SDRAM_BA(dram_ba),
	.SDRAM_nCS(),
	.SDRAM_nWE(dram_we_n),
	.SDRAM_nRAS(dram_ras_n),
	.SDRAM_nCAS(dram_cas_n),
	.SDRAM_CLK(dram_clk),
	.SDRAM_CKE(dram_cke)
);


///////////////////////////////////////////////////////////////////////////////
// What's particular to a game, by its serial: MiSTer's table, Shane Lynch's lightguns,
// the serial save chips
///////////////////////////////////////////////////////////////////////////////

reg [2:0] eeprom_map = 0;
reg [2:0] eeprom_chip = 0;
reg sram00_quirk = 0;
reg fifo_quirk = 0;
reg noram_quirk = 0;
reg pier_quirk = 0;
reg fmbusy_quirk = 0;
reg schan_quirk = 0;
reg lightgun_type = 0;
reg [7:0] lightgun_sensor_delay = 8'd44;

// The serial save chips, a game's mapper and chip (system.sv, EEPROM_24CXX.sv):
// Genesis Plus GX's table (core/cart_hw/eeprom_i2c.c), MiSTer's serials beside it.
localparam [2:0] EP_SEGA = 1, EP_EA = 2, EP_ACCLAIM16 = 3, EP_ACCLAIM32 = 4, EP_CODEMASTERS = 5;
localparam [2:0] C_X24C01 = 0, C_X24C02 = 1, C_24C02 = 2, C_24C04 = 3, C_24C08 = 4, C_24C16 = 5, C_24C65 = 6;
reg eeprom_hackable = 0;     // a hack of this one exists with a save RAM in its header in place of the chip
reg header_ra = 0, header_e8 = 0, header_dnld = 0;
reg [21:0] header_ram_start = 0;
reg  [7:0] header_ram_end = 0;

always @(posedge clk_sys) begin
	reg [63:0] cart_id;
	
	if(ioctl_wr & cart_download) begin
		// Cleared at the header's first word, ahead of the serial. Not all
		// through cart_download, which would take them off again on the next clock,
		// nor at its rising edge, as it drops when bridge_addr leaves the ROM.
		if(ioctl_addr == 'h180) begin
			fifo_quirk <= 0;
			eeprom_map <= 0;
			eeprom_chip <= 0;
			eeprom_hackable <= 0;
			sram00_quirk <= 0;
			noram_quirk <= 0;
			pier_quirk <= 0;
			svp_quirk <= 0;
			fmbusy_quirk <= 0;
			schan_quirk <= 0;
		end
		if(ioctl_addr == 'h0) header_dnld <= ioctl_data == 16'h4E44;   // 'DN', a Codemasters stack pointer
		if(ioctl_addr == 'h182) cart_id[63:56] <= ioctl_data[15:8];
		if(ioctl_addr == 'h184) cart_id[55:40] <= {ioctl_data[7:0],ioctl_data[15:8]};
		if(ioctl_addr == 'h186) cart_id[39:24] <= {ioctl_data[7:0],ioctl_data[15:8]};
		if(ioctl_addr == 'h188) cart_id[23:08] <= {ioctl_data[7:0],ioctl_data[15:8]};
		if(ioctl_addr == 'h18A) cart_id[07:00] <= ioctl_data[7:0];
		if(ioctl_addr == 'h18C) begin
			if     (cart_id[63:8] == "T-50176" ) {eeprom_map, eeprom_chip} <= {EP_EA,        C_X24C01}; // Rings of Power
			else if(cart_id[63:8] == "T-50396" ) {eeprom_map, eeprom_chip} <= {EP_EA,        C_X24C01}; // NHLPA Hockey 93
			else if(cart_id[63:8] == "T-50446" ) {eeprom_map, eeprom_chip} <= {EP_EA,        C_X24C01}; // John Madden Football 93
			else if(cart_id[63:8] == "T-50516" ) {eeprom_map, eeprom_chip} <= {EP_EA,        C_X24C01}; // John Madden Football 93 Championship Edition
			else if(cart_id[63:8] == "T-50606" ) {eeprom_map, eeprom_chip} <= {EP_EA,        C_X24C01}; // Bill Walsh College Football
			else if(cart_id[63:8] == "MK-1215" ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Evander Real Deal Holyfield's Boxing
			else if(cart_id[63:8] == "MK-1228" ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Greatest Heavyweights
			else if(cart_id[63:8] == "G-5538 " ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Greatest Heavyweights JP
			else if(cart_id[63:8] == "PR-1993" ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Greatest Heavyweights prototype
			else if(cart_id[63:8] == "G-4060 " ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Wonder Boy in Monster World
			else if(cart_id       == "00001211") {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Sports Talk Baseball
			else if(cart_id       == "00004076") {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Honoo no Toukyuuji Dodge Danpei
			else if(cart_id[63:8] == "T-12046" ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Mega Man - The Wily Wars
			else if(cart_id[63:8] == "T-12053" ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Rockman Mega World
			else if(cart_id[63:8] == "G-4524 " ) {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Ninja Burai Densetsu
			else if(cart_id       == "00054503") {eeprom_map, eeprom_chip} <= {EP_SEGA,      C_X24C01}; // Game Toshokan
			else if(cart_id[63:8] == "T-81033" ) {eeprom_map, eeprom_chip} <= {EP_ACCLAIM16, C_X24C02}; // NBA Jam JP
			else if(cart_id       == "T-081326") {eeprom_map, eeprom_chip} <= {EP_ACCLAIM16, C_X24C02}; // NBA Jam
			else if(cart_id       == "T-081276") {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C02 }; // NFL Quarterback Club
			else if(cart_id[63:8] == "T-81406" ) {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C04 }; // NBA Jam TE
			else if(cart_id       == "T-081586") {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C16 }; // NFL Quarterback Club '96
			else if(cart_id[63:8] == "T-81476" ) {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C65 }; // Frank Thomas Big Hurt Baseball
			else if(cart_id[63:8] == "T-81576" ) {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C65 }; // College Slam
			else if(cart_id       == "T-081576") {eeprom_map, eeprom_chip} <= {EP_ACCLAIM32, C_24C65 }; // College Slam, as MAME has it
			else if(cart_id       == "T-120106") {eeprom_map, eeprom_chip} <= {EP_CODEMASTERS, C_24C08}; // Brian Lara Cricket
			else if(cart_id       == "T-120096") {eeprom_map, eeprom_chip} <= {EP_CODEMASTERS, C_24C16}; // Micro Machines 2
			else if(cart_id       == "T-120146") {eeprom_map, eeprom_chip} <= {EP_CODEMASTERS, C_24C65}; // Brian Lara Cricket 96, Shane Warne Cricket
			eeprom_hackable <= cart_id[63:8] == "G-4060 " || cart_id[63:8] == "T-12046" || cart_id[63:8] == "T-12053";

			if(cart_id == "T-113016") noram_quirk  <= 1; // Puggsy fake ram check
			else if(cart_id == "T-89016 ") fifo_quirk   <= 1; // Clue
			else if(cart_id == "T-574023") pier_quirk   <= 1; // Pier Solar Reprint
			else if(cart_id == "T-574013") pier_quirk   <= 1; // Pier Solar 1st Edition
			else if(cart_id == "MK-1229 ") svp_quirk    <= 1; // Virtua Racing EU/US
			else if(cart_id == "G-7001  ") svp_quirk    <= 1; // Virtua Racing JP
			else if(cart_id == "T-35036 ") fmbusy_quirk <= 1; // Hellfire US
			else if(cart_id == "T-25073 ") fmbusy_quirk <= 1; // Hellfire JP
			else if(cart_id == "MK-1137-") fmbusy_quirk <= 1; // Hellfire EU
			else if(cart_id == "T-68???-") schan_quirk  <= 1; // Game no Kanzume Otokuyou
			else if(cart_id == " GM 0000") sram00_quirk <= 1; // Sonic 1 Remastered

			// Lightgun device and timing offsets
			if(cart_id == "MK-1533 ") begin						  // Body Count
				lightgun_type  <= 0;
				lightgun_sensor_delay <= 8'd100;
			end
			else if(cart_id == "T-95096-") begin				  // Lethal Enforcers
				lightgun_type  <= 1;
				lightgun_sensor_delay <= 8'd52;
			end
			else if(cart_id == "T-95136-") begin				  // Lethal Enforcers II
				lightgun_type  <= 1;
				lightgun_sensor_delay <= 8'd30;
			end
			else if(cart_id == "MK-1658 ") begin				  // Menacer 6-in-1
				lightgun_type  <= 0;
				lightgun_sensor_delay <= 8'd120;
			end
			else if(cart_id == "T-081156") begin				  // T2: The Arcade Game
				lightgun_type  <= 0;
				lightgun_sensor_delay <= 8'd126;
			end
			else begin
				lightgun_type  <= 0;
				lightgun_sensor_delay <= 8'd44;
			end
		end

		// Two of Codemasters' have no serial: their stack pointer and checksum
		if(ioctl_addr == 'h18E && cart_id == "00000000" && header_dnld) begin
			if({ioctl_data[7:0], ioctl_data[15:8]} == 16'h168B) {eeprom_map, eeprom_chip} <= {EP_CODEMASTERS, C_24C08}; // Micro Machines Military
			if({ioctl_data[7:0], ioctl_data[15:8]} == 16'h165E) {eeprom_map, eeprom_chip} <= {EP_CODEMASTERS, C_24C16}; // Micro Machines 96
		end

		// The header's save memory: 'RA', a byte that says what, its first and last
		// address. A range of a few bytes, or the byte E8, is a serial chip, Sega's
		// pins if the table above doesn't know it. A hack with the save RAM patched
		// in says so with a long range, and stays a RAM.
		if(ioctl_addr == 'h1B0) header_ra <= ioctl_data == {"A", "R"};
		if(ioctl_addr == 'h1B2) header_e8 <= ioctl_data[7:0] == 8'hE8;
		if(ioctl_addr == 'h1B4) header_ram_start[21:14] <= ioctl_data[15:8];
		if(ioctl_addr == 'h1B6) header_ram_start[13:0] <= {ioctl_data[7:0], ioctl_data[15:10]};
		if(ioctl_addr == 'h1BA) begin
			if(eeprom_hackable && header_ra && header_ram_start != {header_ram_end, ioctl_data[7:0], ioctl_data[15:10]})
				eeprom_map <= 0;
			else if(!eeprom_map && header_ra && !pier_quirk && !sram00_quirk &&
			        (header_e8 || header_ram_start == {header_ram_end, ioctl_data[7:0], ioctl_data[15:10]})) begin
				eeprom_map <= EP_SEGA;
				eeprom_chip <= C_X24C01;
			end
		end
		if(ioctl_addr == 'h1B8) header_ram_end <= ioctl_data[15:8];
	end
end



///////////////////////////////////////////////////////////////////////////////
// Controls
///////////////////////////////////////////////////////////////////////////////

// The six face buttons from a pad's key bits, {Z, Y, X, B, C, A}, on the Pocket's own
// layout (input.json). A pad that sends its buttons otherwise, an 8BitDo M30 among them,
// is put right by the Pocket's own controller remapping.
function automatic [5:0] face_buttons(input [31:0] k);
    face_buttons = {k[9], k[6], k[8], k[4], k[5], k[7]};
endfunction

// A pad as the console's port wants it: {Z, Y, X, Mode, Start, B, C, A, Up, Down, Left, Right}
function automatic [11:0] console_pad(input [15:0] k);
    reg [5:0] face;
    begin
        face = face_buttons({16'd0, k});
        console_pad = {face[5:3], k[14], k[15], face[2:0], k[0], k[1], k[2], k[3]};
    end
endfunction

// Each player's controls: the Pocket's, or an Analogizer's SNAC controller where
// analogizer.bin gives it that player (pocket_analogizer.sv), in the same order
wire [15:0] key1, key2, key3, key4;
wire [15:0] keys_1, keys_2, keys_3, keys_4;
wire [15:0] aim_1;
synch_3 #(.WIDTH(80)) pads_s (
    {cont1_joy[15:0], key4, key3, key2, key1},
    {aim_1, keys_4, keys_3, keys_2, keys_1},
    clk_sys
);

// (with the gun on, its trigger's Start is what the first pad's Start gives)
wire [11:0] pad_1 = console_pad(keys_1) & ~{4'd0, lightgun_enabled, 7'd0};
wire [11:0] pad_2 = console_pad(keys_2);
wire [11:0] pad_3 = console_pad(keys_3);
wire [11:0] pad_4 = console_pad(keys_4);

///////////////////////////////////////////////
// Lightguns (Shane Lynch)
///////////////////////////////////////////////
wire [2:0] lg_target;
wire       lg_sensor;
wire       lg_a;
wire       lg_b;
wire       lg_c;
wire       lg_start;

lightgun lightgun
(
    .CLK(clk_sys),
    .RESET(reset),

    .JOY_X(aim_1[7:0]),
    .JOY_Y(aim_1[15:8]),
    .JOY(key1),

    .UP(key1[0]),
    .DOWN(key1[1]),
    .LEFT(key1[2]),
    .RIGHT(key1[3]),
    .DPAD_AIM_SPEED(dpad_aim_speed),

    .RELOAD(lightgun_type),

    .HDE(~hblank_c),
    .VDE(~vblank_c),
    .CE_PIX(ce_pix),
    .H40(resolution[0]),

    .BTN_MODE(0),
    .SENSOR_DELAY(lightgun_sensor_delay),

    .TARGET(lg_target),
    .SENSOR(lg_sensor),
    .BTN_A(lg_a),
    .BTN_B(lg_b),
    .BTN_C(lg_c),
    .BTN_START(lg_start)
);


///////////////////////////////////////////////////////////////////////////////
// The console
///////////////////////////////////////////////////////////////////////////////

wire in_menu, pal_hold_s, reset_core_s;
synch_3 #(.WIDTH(3)) console_s ({osnotify_inmenu, pal_hold, reset_delay != 0}, {in_menu, pal_hold_s, reset_core_s}, clk_sys);

wire reset = ~reset_n | cart_download | region_set | pal_hold_s;

// A game that turns on PAL's 240 lines at 60 Hz. The VDP's line counter never reloads then,
// as on a real NTSC console, so a frame is 512 lines, 30.85 a second, and the Pocket shows
// a black screen. Held longer than such a frame, the game is started again at 50 Hz, its
// clock changed with the console in reset (pal_clock.sv), and it reads the region it read
// before. A game turns it on as it starts, so nothing is lost. The next game starts as
// the rows say.
wire [1:0] resolution;       // the VDP's V30, H40
wire       pal_s;
reg [20:0] v30_time = 0;
synch_3 pal_sync (pal, pal_s, clk_sys);
always @(posedge clk_sys) begin
	if (cart_download) pal_frame <= 0;
	if (reset || pal_s || !resolution[1]) v30_time <= 0;
	else if (&v30_time) pal_frame <= 1;
	else v30_time <= v30_time + 1'd1;
end

// A state loaded runs on the clock it was made at (state_bridge.sv), so a Memory made at
// 50 Hz loads into a game started at 60, and the other way. That holds until the game
// starts afresh: Reset Core or a new game goes back to what the rows say, and 240 lines
// turned on at 60 Hz restart it at 50 as above.
wire ss_pal_take, ss_pal_file;
always @(posedge clk_sys) begin
	if (ss_pal_take) {mem_pal_on, mem_pal} <= {1'b1, ss_pal_file};
	if (cart_download || reset_core_s || &v30_time) mem_pal_on <= 0;
end

wire [31:0] state_read_data;
wire        ss_save, ss_load, ss_go, ss_rd, ss_wr;
wire  [1:0] ss_status;
wire [17:0] ss_addr;
wire [15:0] ss_do, ss_di;
wire        ss_pause_lift, ss_hold_reset, ss_load_blank;

wire [15:0] AUDIO_L;
wire [15:0] AUDIO_R;
wire TRANSP_DETECT;

wire [3:0] r, g, b;
wire vs, hs;
wire ce_pix;
wire hblank, vblank_console;

system system
(
	.RESET_N((~reset && !reset_delay) | ss_hold_reset),
	.MCLK(clk_sys),

	.LOADING(cart_download),
	.EXPORT(|region_now),
	.PAL(pal),
	.PAL_SAYS(says_pal),
	.SRAM00_QUIRK(sram00_quirk),
	.EEPROM_MAP(eeprom_map),
	.EEPROM_CHIP(eeprom_chip),
	.NORAM_QUIRK(noram_quirk),
	.PIER_QUIRK(pier_quirk),
	.FMBUSY_QUIRK(fmbusy_quirk),

	.DAC_LDATA(AUDIO_L),
	.DAC_RDATA(AUDIO_R),

	.TURBO(2'd0),

	.RED(r),
	.GREEN(g),
	.BLUE(b),
	.VS(vs),
	.HS(hs),
	.HBL(hblank),
	.VBL(vblank_console),
	.BORDER(1'b0),
	.CRAM_DOTS(1'b0),
	.CE_PIX(ce_pix),
	.RESOLUTION(resolution),
	.FAST_FIFO(fifo_quirk),
	.SVP_QUIRK(svp_quirk),
	.SCHAN_QUIRK(schan_quirk),

	.J3BUT(cfg_3_buttons),
	.JOY_1(pad_1),
	.JOY_2(pad_2),
	.JOY_3(pad_3),
	.JOY_4(pad_4),
	.MULTITAP(cfg_multitap),

	.GUN_OPT(lightgun_enabled),
	.GUN_TYPE(lightgun_type),
	.GUN_SENSOR(lg_sensor),
	.GUN_A(lg_a),
	.GUN_B(lg_b),
	.GUN_C(lg_c),
	.GUN_START(lg_start),

	.ENABLE_FM(1'b1),
	.ENABLE_PSG(1'b1),
	.EN_HIFI_PCM(cfg_hifi_pcm),
	.LADDER(~cfg_ym3438),
	.LPF_MODE(cfg_filter),

	.OBJ_LIMIT_HIGH(cfg_many_sprites),

	.BRAM_A(bram_addr),
	.BRAM_DI(bram_to_ram),
	.BRAM_DO(bram_from_ram),
	.BRAM_WE(bram_we),

	.ROMSZ(game_bytes[24:1]),
	.ROM_ADDR(rom_addr),
	.ROM_DATA(rom_data),
	.ROM_WDATA(rom_wdata),
	.ROM_WE(rom_we),
	.ROM_BE(rom_be),
	.ROM_REQ(rom_req),
	.ROM_ACK(rom_rdack),

	.ROM_ADDR2(rom_addr2),
	.ROM_DATA2(rom_data2),
	.ROM_REQ2(rom_rd2),
	.ROM_ACK2(rom_rdack2),

	.TRANSP_DETECT(TRANSP_DETECT),

	.PAUSE_EN(cfg_menu_pause & in_menu & ~ss_pause_lift),
	.BGA_EN(1'b1),
	.BGB_EN(1'b1),
	.SPR_EN(1'b1),

	.SS_SAVE(ss_save),
	.SS_LOAD(ss_load),
	.SS_GO(ss_go),
	.SS_STATUS(ss_status),
	.SS_ADDR(ss_addr),
	.SS_RD(ss_rd),
	.SS_DO(ss_do),
	.SS_WR(ss_wr),
	.SS_DI(ss_di)
);


///////////////////////////////////////////////////////////////////////////////
// Save states, between the bridge and the console's window (state_bridge.sv)
///////////////////////////////////////////////////////////////////////////////

state_bridge state_bridge (
    .clk_74a(clk_74a),
    .clk_sys(clk_sys),

    .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),
    .bridge_rd(bridge_rd),
    .bridge_rd_data(state_read_data),
    .bridge_wr(bridge_wr),
    .bridge_wr_data(bridge_wr_data),

    .savestate_start(savestate_start),
    .savestate_start_ack(savestate_start_ack),
    .savestate_start_busy(savestate_start_busy),
    .savestate_start_ok(savestate_start_ok),
    .savestate_start_err(savestate_start_err),

    .savestate_load(savestate_load),
    .savestate_load_ack(savestate_load_ack),
    .savestate_load_busy(savestate_load_busy),
    .savestate_load_ok(savestate_load_ok),
    .savestate_load_err(savestate_load_err),

    .reset_n(reset_n),
    .pal(pal),
    .pal_hold(pal_hold),

    .cart_download(cart_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_data(ioctl_data),
    .rom_size(game_bytes),

    .svp(svp_quirk),
    .ss_save(ss_save),
    .ss_load(ss_load),
    .ss_go(ss_go),
    .ss_status(ss_status),
    .ss_addr(ss_addr),
    .ss_rd(ss_rd),
    .ss_do(ss_do),
    .ss_wr(ss_wr),
    .ss_di(ss_di),

    .pause_lift(ss_pause_lift),
    .hold_reset(ss_hold_reset),
    .load_blank(ss_load_blank),
    .pal_take(ss_pal_take),
    .pal_file(ss_pal_file)
);


///////////////////////////////////////////////////////////////////////////////
// Sound
///////////////////////////////////////////////////////////////////////////////

sound_i2s #(
    .CHANNEL_WIDTH(16),
    .SIGNED_INPUT (1)
) sound_i2s (
    .clk_74a(clk_74a),
    .clk_audio(clk_sys),

    .audio_l(AUDIO_L),
    .audio_r(AUDIO_R),

    .audio_mclk(audio_mclk),
    .audio_lrck(audio_lrck),
    .audio_dac(audio_dac)
);


///////////////////////////////////////////////////////////////////////////////
// The picture. The Pocket takes a line at a time on a pixel clock of its own: colours
// while data enable is high, and while it is low, the scaler's slot from video.json.
///////////////////////////////////////////////////////////////////////////////

wire [7:0] color_lut[16] = '{
	8'd0,   8'd27,  8'd49,  8'd71,
	8'd87,  8'd103, 8'd119, 8'd130,
	8'd146, 8'd157, 8'd174, 8'd190,
	8'd206, 8'd228, 8'd255, 8'd255
};

wire cofi_enable = cfg_blend || (cfg_blend_auto && TRANSP_DETECT);
wire hs_c, vs_c, hblank_c, vblank_c;
wire [7:0] red, green, blue;

cofi coffee (
	.clk(clk_sys),
	.pix_ce(ce_pix),
	.enable(cofi_enable),

	.hblank(hblank),
	.vblank(vblank_console),
	.hs(hs),
	.vs(vs),
	.red(color_lut[r]),
	.green(color_lut[g]),
	.blue(color_lut[b]),

	.hblank_out(hblank_c),
	.vblank_out(vblank_c),
	.hs_out(hs_c),
	.vs_out(vs_c),
	.red_out(red),
	.green_out(green),
	.blue_out(blue)
);

///////////////////////////////////////////////////////////////////////////////
// The Analogizer: the picture as the Pocket's screen gets it (the gun's mark in, black
// behind a load) out of the cartridge slot, and SNAC controllers in (Controls, above).
// pocket_analogizer.sv says how it is set.
///////////////////////////////////////////////////////////////////////////////

wire show_mark_sys = lg_target != 0 && lightgun_enabled;
wire anz_pocket_off;

pocket_analogizer analogizer (
	.clk_74a(clk_74a),
	.bridge_wr(bridge_wr),
	.bridge_addr(bridge_addr),
	.bridge_wr_data(bridge_wr_data),

	.clk_sys(clk_sys),
	.pal(pal_s),
	.h40(resolution[0]),
	.ce_pix(ce_pix),
	.hs(hs_c),
	.vs(vs_c),
	.hblank(hblank_c),
	.vblank(vblank_c),
	.r(ss_load_blank ? 8'd0 : show_mark_sys ? {8{lg_target[0]}} : red),
	.g(ss_load_blank ? 8'd0 : show_mark_sys ? {8{lg_target[1]}} : green),
	.b(ss_load_blank ? 8'd0 : show_mark_sys ? {8{lg_target[2]}} : blue),
	.pocket_off(anz_pocket_off),

	.cont1_key(cont1_key[15:0]),
	.cont2_key(cont2_key[15:0]),
	.cont3_key(cont3_key[15:0]),
	.cont4_key(cont4_key[15:0]),
	.key1(key1),
	.key2(key2),
	.key3(key3),
	.key4(key4),

	.cart_tran_bank2(cart_tran_bank2),
	.cart_tran_bank2_dir(cart_tran_bank2_dir),
	.cart_tran_bank3(cart_tran_bank3),
	.cart_tran_bank3_dir(cart_tran_bank3_dir),
	.cart_tran_bank1(cart_tran_bank1),
	.cart_tran_bank1_dir(cart_tran_bank1_dir),
	.cart_tran_bank0(cart_tran_bank0),
	.cart_tran_bank0_dir(cart_tran_bank0_dir),
	.cart_tran_pin30(cart_tran_pin30),
	.cart_tran_pin30_dir(cart_tran_pin30_dir),
	.cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
	.cart_tran_pin31(cart_tran_pin31),
	.cart_tran_pin31_dir(cart_tran_pin31_dir)
);

// The pixel clock for the width, at either height
wire pix_clk    = !resolution[0] ? clk_vid_256 : clk_vid_320;
wire pix_clk_90 = !resolution[0] ? clk_vid_256_90deg : clk_vid_320_90deg;

// What goes out, steady around that clock's edge (video_hold.sv), and black from the
// moment a state starts to load until it lets go, as the chips fill while the VDP
// goes on drawing them; black too, mark and all, when analogizer.bin asks for the
// Pocket's own screen off
wire hs_h, vs_h, hblank_h, vblank_h;
wire [2:0] lg_target_h;
wire [7:0] red_h, green_h, blue_h;

video_hold #(.WIDTH(31)) video_hold (
	.clk_sys(clk_sys),
	.clk_pix(pix_clk),
	.d({hs_c, vs_c, hblank_c, vblank_c, anz_pocket_off ? 3'd0 : lg_target,
	    ss_load_blank || anz_pocket_off ? 24'd0 : {red, green, blue}}),
	.q({hs_h, vs_h, hblank_h, vblank_h, lg_target_h, red_h, green_h, blue_h})
);

wire [1:0] mode;
synch_3 #(.WIDTH(2)) mode_s (resolution, mode, pix_clk);

// video.json's list: 0 H32 at 224, 1 H40 at 224, 2 H32 at 240, 3 H40 at 240, each in the
// console's own shape
wire [10:0] scaler_slot = {9'd0, mode[1], mode[0]};

wire show_mark = lg_target_h != 0 && lightgun_enabled;

reg [23:0] vidout_rgb;
reg        vidout_de, vidout_vs, vidout_hs;
reg        hs_was, vs_was;
reg        line_hidden = 0;

always @(posedge pix_clk) begin
    hs_was <= hs_h;
    vs_was <= vs_h;
    vidout_hs <= hs_h & ~hs_was;
    vidout_vs <= vs_h & ~vs_was;

    // the vblank signal starts and stops a bit before the end of the visible
    // portion of the line. if used to gate pixel output, this means the last
    // visible line gets truncated and the last blank line is partially shown,
    // producing garbage on the screen. capture and use vblank's value at hsync
    // to avoid this; hsync starts a line so that's when we care whether or not
    // the line is visible.
    if (hs_h & ~hs_was) line_hidden <= vblank_h;

    if (line_hidden | hblank_h) begin
        vidout_de <= 0;
        vidout_rgb <= {scaler_slot, 13'd0};
    end
    else begin
        vidout_de <= 1;
        vidout_rgb <= show_mark ? {{8{lg_target_h[0]}}, {8{lg_target_h[1]}}, {8{lg_target_h[2]}}} : {red_h, green_h, blue_h};
    end
end

assign video_rgb_clock = pix_clk;
assign video_rgb_clock_90 = pix_clk_90;
assign video_rgb = vidout_rgb;
assign video_de = vidout_de;
assign video_skip = 0;
assign video_vs = vidout_vs;
assign video_hs = vidout_hs;

endmodule
