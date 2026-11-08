// Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
// Copyright (c) 2018 Sorgelig
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.

module system
(
	input         RESET_N,
	input         MCLK,

	input   [1:0] LPF_MODE,
	input         ENABLE_FM,
	input         ENABLE_PSG,
	output [15:0] DAC_LDATA,
	output [15:0] DAC_RDATA,

	input         LOADING,
	input         PAL,
	input         PAL_SAYS,      // what a game reads, PAL being the timing: Europe's lockouts at 60 Hz
	input         EXPORT,
	input         FAST_FIFO,
	input         SRAM00_QUIRK,
	input   [2:0] EEPROM_MAP,    // the cart's serial save chip: 0 none, 1 Sega, 2 EA, 3 Acclaim's 16M board, 4 its 32M, 5 Codemasters
	input   [2:0] EEPROM_CHIP,   // which chip (EEPROM_24CXX.sv)
	input         NORAM_QUIRK,
	input         PIER_QUIRK,
	input         SVP_QUIRK, 
	input         FMBUSY_QUIRK,
	input         SCHAN_QUIRK,

	input   [1:0] TURBO,

	input         GG_RESET,
	input         GG_EN,
	input [128:0] GG_CODE,
	output        GG_AVAILABLE,

	input  [14:0] BRAM_A,
	input  [15:0] BRAM_DI,
	output [15:0] BRAM_DO,
	input         BRAM_WE,
	output        BRAM_CHANGE,

	output  [3:0] RED,
	output  [3:0] GREEN,
	output  [3:0] BLUE,
	output        VS,
	output        HS,
	output        HBL,
	output        VBL,
	output        CE_PIX,
	input         BORDER,
	input         CRAM_DOTS,

	output        INTERLACE,
	output        FIELD,
	output  [1:0] RESOLUTION,

	input         J3BUT,
	input  [11:0] JOY_1,
	input  [11:0] JOY_2,
	input  [11:0] JOY_3,
	input  [11:0] JOY_4,
	input  [11:0] JOY_5,
	input   [2:0] MULTITAP,

	input  [24:0] MOUSE,
	input   [2:0] MOUSE_OPT,
	
	input         GUN_OPT,
	input         GUN_TYPE,
	input         GUN_SENSOR,
	input         GUN_A,
	input         GUN_B,
	input         GUN_C,
	input         GUN_START,

	input   [7:0] SERJOYSTICK_IN,
	output  [7:0] SERJOYSTICK_OUT,
	input   [1:0] SER_OPT,

	input  [24:1] ROMSZ,
	output [24:1] ROM_ADDR,
	input  [15:0] ROM_DATA,
	output [15:0] ROM_WDATA,
	output reg    ROM_WE,
	output  [1:0] ROM_BE,
	output reg    ROM_REQ,
	input         ROM_ACK,

	output [24:1] ROM_ADDR2,
	input  [15:0] ROM_DATA2,
	output        ROM_REQ2,
	input         ROM_ACK2, 
	
	input         EN_HIFI_PCM,
	input         LADDER,
	input         OBJ_LIMIT_HIGH,

	output		  TRANSP_DETECT,
	
	//debug
	input         PAUSE_EN,
	input         BGA_EN,
	input         BGB_EN,
	input         SPR_EN,
	output [23:0] DBG_M68K_A,
	output [23:0] DBG_VBUS_A,

	// Save states, as core_top.sv drives them: SS_SAVE
	// finds the clean point and freezes there, SS_LOAD (the header matched)
	// stops the console for a state to be written, SS_GO ends the read-out or
	// the writing; the console is let go at the recorded raster position.
	// SS_STATUS 0 idle, 1 busy, 2 ok (frozen, or restored), 3 error. A word
	// of the state, its byte offset / 2: SS_RD reads it into SS_DO in
	// SS_CLOCKS clocks, SS_WR writes SS_DI there; one at a time, in order.
	input         SS_SAVE,
	input         SS_LOAD,
	input         SS_GO,
	output  [1:0] SS_STATUS,
	input  [17:0] SS_ADDR,
	input         SS_RD,
	output reg [15:0] SS_DO,
	input         SS_WR,
	input  [15:0] SS_DI
);

localparam SS_CLOCKS = 24;

// ---- save states: what the chips take from the save logic (it is at the end)
reg         ss_freeze = 0;              // the clock enables of the 68000, the Z80, the YM2612 and the PSG held, their dividers too
reg         ss_run68 = 0;               // (a load) the 68000's run on through its reset, the rest frozen
reg         ss_div_we = 0;              // (a load) the dividers set from the state
reg  [23:0] ss_div_d;
reg         ss_park68 = 0, ss_parkdisp68 = 0, ss_rst68 = 0;
reg         ss_srwe = 0, ss_miscwe = 0, ss_grpwe = 0, ss_clkwe = 0;
reg  [15:0] ss_sr_d, ss_misc_d, ss_grp_d, ss_clk_d;
reg         ss_zpark = 0, ss_rstZ = 0, ss_dirset = 0;
wire [211:0] ss_dir;
reg  [18:0] ss_dirx;
reg         ss_sysrst = 0;              // (a load) system.sv's bus machines and registers reset before they are written
reg         ss_vdp_rst = 0, ss_vdp_en = 0, ss_vdp_snap = 0, ss_vdp_rest = 0;
reg         ss_fm_scan = 0, ss_fm_load = 0;
reg         ss_mem = 0;                 // the memories' free ports are the save logic's
reg         ss_bram = 0;                // the save RAM's port B too, for a word of it: between
                                        // words the Pocket may move the .sav (a Memory keeps one)
reg         ss_vec = 0;                 // the 68000's reset vectors answered from the state
reg  [31:0] ss_vec_sp, ss_vec_pc;
reg         ss_nodata_we = 0;
reg  [15:0] ss_nodata_d;
wire        sreset = reset | ss_sysrst;
reg  [15:0] ss_wd;                      // the word being written
wire        ss_ipl_we;
wire  [5:0] ss_ipl_d;
wire [14:0] ss_vram_a, ss_ram68_a;
wire [15:0] ss_sram_a;
wire  [1:0] ss_i2c_a;
wire        ss_i2c_we;
wire [15:0] ss_i2c_q;
wire        ss_vram_we, ss_ram68_we, ss_sram_we, ss_zram_we, ss_vdp_we, ss_psg_we, ss_io_we;
wire [12:0] ss_zram_a;
wire  [9:0] ss_vdp_a;
wire  [3:0] ss_psg_i, ss_io_i;
wire        ss_cw;                      // a console register written (ss_wa, ss_wd)
wire [16:0] ss_wa;
wire        ss_fm_gsh, ss_fm_gi, ss_fm_ld, ss_fm_step;
wire  [3:0] ss_fm_lane;
reg         ss_svp_sh = 0, ss_svp_en = 0, rd_busy = 0, wr_busy = 0;
wire        ss_svp_ra_we, ss_svp_rb_we, ss_svp_ir_we, svp_ss_quiet;
wire  [9:0] ss_svp_a;
wire [15:0] svp_ss_so, svp_ss_ra, svp_ss_rb, svp_ss_ir;
wire        M68K_CLKEN_SYS;             // the 68000's clock enable for the rest of system.sv (not while it runs alone)

reg reset;
reg hard_reset;
always @(posedge MCLK) if(M68K_CLKENn) begin
	reset <= ~RESET_N | LOADING;
	hard_reset <= LOADING;
end

//--------------------------------------------------------------
// CLOCK ENABLERS
//--------------------------------------------------------------
wire M68K_CLKEN = M68K_CLKENp;
reg  M68K_CLKENp, M68K_CLKENn;
reg  Z80_CLKENp, Z80_CLKENn, PSG_CLKEN;
reg  FM_CLKEN;

reg [3:0] FCLKCNT = 0;
reg [3:0] VCLKCNT = 0;
reg [3:0] ZCLKCNT = 0;
reg [3:0] PCLKCNT = 0;
reg [3:0] VCLKMAX = 0;
reg [3:0] VCLKMID = 0;

always @(negedge MCLK) begin
	if(~RESET_N | LOADING) begin
		VCLKCNT <= 0;
		PCLKCNT <= 0;
		FCLKCNT <= 0;
		Z80_CLKENp <= 1;
		Z80_CLKENn <= 1;
		PSG_CLKEN <= 1;
		M68K_CLKENp <= 1;
		M68K_CLKENn <= 1;
		VCLKMAX = 6;
		VCLKMID = 3;
	end
	else if(ss_div_we) begin
		// save states: the dividers' phases from the state, the enables held
		{VCLKCNT, ZCLKCNT, FCLKCNT, PCLKCNT, VCLKMAX, VCLKMID} <= ss_div_d;
		{Z80_CLKENp, Z80_CLKENn, PSG_CLKEN, M68K_CLKENp, M68K_CLKENn, FM_CLKEN} <= 0;
	end
	else if(ss_freeze & ~ss_run68) begin
		// save states: frozen, as if the clock had stopped for these chips
		{Z80_CLKENp, Z80_CLKENn, PSG_CLKEN, M68K_CLKENp, M68K_CLKENn, FM_CLKEN} <= 0;
	end
	else if(ss_freeze) begin
		// save states: a load's 68000 runs alone through its reset
		{Z80_CLKENp, Z80_CLKENn, PSG_CLKEN, FM_CLKEN} <= 0;
		M68K_CLKENp <= 0;
		VCLKCNT <= VCLKCNT + 1'b1;
		if (VCLKCNT == VCLKMAX) begin
			VCLKCNT <= 0;
			M68K_CLKENp <= 1;
		end
		M68K_CLKENn <= VCLKCNT == VCLKMID;
	end
	else begin
		Z80_CLKENn <= 0;
		ZCLKCNT <= ZCLKCNT + 1'b1;
		if (ZCLKCNT == 14) begin
			ZCLKCNT <= 0;
			Z80_CLKENn <= ~PAUSE_EN;
		end
		
		Z80_CLKENp <= 0;
		if (ZCLKCNT == 7) begin
			Z80_CLKENp <= ~PAUSE_EN;
		end

		PSG_CLKEN <= 0;
		PCLKCNT <= PCLKCNT + 1'b1;
		if (PCLKCNT == 14) begin
			PCLKCNT <= 0;
			PSG_CLKEN <= ~PAUSE_EN;
		end

		M68K_CLKENp <= 0;
		VCLKCNT <= VCLKCNT + 1'b1;
		if (VCLKCNT == VCLKMAX) begin
			VCLKCNT <= 0;
			M68K_CLKENp <= ~PAUSE_EN;
			VCLKMAX <= (TURBO == 2) ? 4'd1 : (TURBO == 1) ? 4'd3 : 4'd6;
			VCLKMID <= (TURBO == 2) ? 4'd0 : (TURBO == 1) ? 4'd1 : 4'd3;
		end

		M68K_CLKENn <= 0;
		if (VCLKCNT == VCLKMID) begin
			M68K_CLKENn <= ~PAUSE_EN;
		end

		FM_CLKEN <= 0;
		FCLKCNT <= FCLKCNT + 1'b1;
		if (FCLKCNT == 6) begin
			FCLKCNT <= 0;
			FM_CLKEN <= ~PAUSE_EN;
		end
	end
end

reg [16:1] ram_rst_a;
always @(posedge MCLK) ram_rst_a <= ram_rst_a + LOADING;


//--------------------------------------------------------------
// CPU 68000
//--------------------------------------------------------------
wire [23:1] M68K_A;
wire [15:0] M68K_DO;
wire        M68K_AS_N;
wire        M68K_UDS_N;
wire        M68K_LDS_N;
wire        M68K_RNW;
wire  [2:0] M68K_FC;
wire        M68K_BG_N;
wire        M68K_BR_N;
wire        M68K_BGACK_N;

reg   [2:0] M68K_IPL_N;
reg         old_as;
reg   [1:0] scnt;
assign      M68K_CLKEN_SYS = M68K_CLKEN & ~ss_run68;
always @(posedge MCLK) begin
	if(sreset) M68K_IPL_N <= 3'b111;
	else if (ss_ipl_we) {M68K_IPL_N, old_as, scnt} <= ss_ipl_d;
	else if (M68K_CLKEN_SYS) begin
		old_as <= M68K_AS_N;
		scnt <= scnt + 1'd1;
		if(~M68K_AS_N) scnt <= 0;
		if((~old_as & M68K_AS_N) || &scnt) begin
			if (M68K_VINT) M68K_IPL_N <= 3'b001;
			else if (M68K_HINT) M68K_IPL_N <= 3'b011;
			else if (M68K_EXINT) M68K_IPL_N <= 3'b101;
			else M68K_IPL_N <= 3'b111;
		end
	end
end

wire M68K_INTACK = &M68K_FC;

assign M68K_BR_N = VBUS_BR_N & Z80_BR_N;
assign M68K_BGACK_N = VBUS_BGACK_N & Z80_BGACK_N;

wire        fx_atstart, fx_atdisp, fx_busidle;
wire  [9:0] fx_uaddr;
wire [31:0] fx_regq, fx_pc;
wire [15:0] fx_sr, fx_misc, fx_grpdisp, fx_clk;
wire  [4:0] fx_rega;
wire        fx_regwe;
wire [31:0] fx_regd;

fx68k M68K
(
	.clk(MCLK),
	.extReset(reset | ss_rst68),
	.pwrUp(hard_reset),
	.enPhi1(M68K_CLKENp),
	.enPhi2(M68K_CLKENn),

	.eRWn(M68K_RNW),
	.ASn(M68K_AS_N),
	.UDSn(M68K_UDS_N),
	.LDSn(M68K_LDS_N),

	.FC0(M68K_FC[0]),
	.FC1(M68K_FC[1]),
	.FC2(M68K_FC[2]),

	.BGn(M68K_BG_N),
	.BRn(M68K_BR_N),
	.BGACKn(M68K_BGACK_N),
	.HALTn(1),

	.DTACKn(M68K_MBUS_DTACK_N),
	.VPAn(~M68K_INTACK),
	.BERRn(1),
	.IPL0n(M68K_IPL_N[0]),
	.IPL1n(M68K_IPL_N[1]),
	.IPL2n(M68K_IPL_N[2]),
	.iEdb(genie_data),
	.oEdb(M68K_DO),
	.eab(M68K_A),

	// save states
	.ssPark(ss_park68), .ssParkDisp(ss_parkdisp68),
	.ssAtStart(fx_atstart), .ssAtDisp(fx_atdisp), .ssBusIdle(fx_busidle),
	.ssUaddr(fx_uaddr),
	.ssRegA(fx_rega), .ssRegQ(fx_regq), .ssRegWe(fx_regwe), .ssRegD(fx_regd),
	.ssPc(fx_pc), .ssSr(fx_sr), .ssMisc(fx_misc), .ssGrpDisp(fx_grpdisp), .ssClk(fx_clk),
	.ssSrWe(ss_srwe), .ssSrD(ss_sr_d), .ssMiscWe(ss_miscwe), .ssMiscD(ss_misc_d),
	.ssGrpWe(ss_grpwe), .ssGrpD(ss_grp_d), .ssClkWe(ss_clkwe), .ssClkD(ss_clk_d)
);


assign DBG_M68K_A = {M68K_A,1'b0};
assign DBG_VBUS_A = {VBUS_A,1'b0};

//--------------------------------------------------------------
// CHEAT CODES
//--------------------------------------------------------------

wire [15:0] genie_data;
CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) codes
(
	.clk(MCLK),
	.reset(LOADING | GG_RESET),
	.enable(~GG_EN),
	.code(GG_CODE),
	.available(GG_AVAILABLE),
	.addr_in({M68K_A[23:1], 1'b0}),
	.data_in(M68K_MBUS_D),
	.data_out(genie_data)
);


//--------------------------------------------------------------
// VDP + PSG
//--------------------------------------------------------------
reg         VDP_SEL;
wire [15:0] VDP_DO;
wire        VDP_DTACK_N;

wire [23:1] VBUS_A;
wire        VBUS_SEL;
wire        VBUS_BR_N;
wire        VBUS_BGACK_N;

wire        M68K_EXINT;
wire        M68K_HINT;
wire        M68K_VINT;
wire        Z80_VINT;

wire        vram_req;
wire        vram_we_u = vram_we & ~vram_u_n;
wire        vram_we_l = vram_we & ~vram_l_n;
wire        vram_we;
wire        vram_u_n;
wire        vram_l_n;
wire [15:1] vram_a;
wire [15:0] vram_d;
wire [15:0] vram_q1, vram_q2;

wire        vram32_req;
wire [15:1] vram32_a;
wire [31:0] vram32_q;

dpram #(14) vram_l1
(
	.clock(MCLK),
	.address_a(ss_mem ? ss_vram_a[14:1] : vram_a[15:2]),
	.data_a(ss_mem ? ss_wd[7:0] : vram_d[7:0]),
	.wren_a(ss_mem ? ss_vram_we & ~ss_vram_a[0] : vram_we_l & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[7:0]),

	.address_b(LOADING ? ram_rst_a[14:1] : vram32_a[15:2]),
	.wren_b(LOADING),
	.q_b(vram32_q[7:0])
);

dpram #(14) vram_u1
(
	.clock(MCLK),
	.address_a(ss_mem ? ss_vram_a[14:1] : vram_a[15:2]),
	.data_a(ss_mem ? ss_wd[15:8] : vram_d[15:8]),
	.wren_a(ss_mem ? ss_vram_we & ~ss_vram_a[0] : vram_we_u & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[15:8]),

	.address_b(LOADING ? ram_rst_a[14:1] : vram32_a[15:2]),
	.wren_b(LOADING),
	.q_b(vram32_q[15:8])
);

dpram #(14) vram_l2
(
	.clock(MCLK),
	.address_a(ss_mem ? ss_vram_a[14:1] : vram_a[15:2]),
	.data_a(ss_mem ? ss_wd[7:0] : vram_d[7:0]),
	.wren_a(ss_mem ? ss_vram_we & ss_vram_a[0] : vram_we_l & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[7:0]),

	.address_b(LOADING ? ram_rst_a[14:1] : vram32_a[15:2]),
	.wren_b(LOADING),
	.q_b(vram32_q[23:16])
);

dpram #(14) vram_u2
(
	.clock(MCLK),
	.address_a(ss_mem ? ss_vram_a[14:1] : vram_a[15:2]),
	.data_a(ss_mem ? ss_wd[15:8] : vram_d[15:8]),
	.wren_a(ss_mem ? ss_vram_we & ss_vram_a[0] : vram_we_u & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[15:8]),

	.address_b(LOADING ? ram_rst_a[14:1] : vram32_a[15:2]),
	.wren_b(LOADING),
	.q_b(vram32_q[31:24])
);

reg vram_ack;
always @(posedge MCLK) vram_ack <= vram_req;

reg vram32_ack;
always @(posedge MCLK) vram32_ack <= vram32_req;

wire VDP_hs, VDP_vs;
assign HS = ~VDP_hs;
assign VS = ~VDP_vs;

wire HL;

wire [15:0] vdp_ss_q;
wire        vdp_ss_idle, vdp_ss_spr;
wire [22:0] vdp_ss_pos;

vdp vdp
(
	.RST_n(~hard_reset & ~ss_vdp_rst),
	.CLK(MCLK),

	.SEL(VDP_SEL),
	.A({MBUS_A[4:1], 1'b0}),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO),
	.DO(VDP_DO),
	.DTACK_n(VDP_DTACK_N),

	.VRAM_req(vram_req),
	.VRAM_ack(vram_ack),
	.VRAM_we(vram_we),
	.VRAM_u_n(vram_u_n),
	.VRAM_l_n(vram_l_n),
	.VRAM_a(vram_a),
	.VRAM_d(vram_d),
	.VRAM_q(vram_a[1] ? vram_q2 : vram_q1),

	.VRAM32_req(vram32_req),
	.VRAM32_ack(vram32_ack),
	.VRAM32_a(vram32_a),
	.VRAM32_q(vram32_q),
	
	.EXINT(M68K_EXINT),
	.HL(HL),
	
	.HINT(M68K_HINT),
	.VINT_TG68(M68K_VINT),
	.INTACK(M68K_INTACK),

	.VINT_T80(Z80_VINT),

	.VBUS_addr(VBUS_A),
	.VBUS_data(VDP_MBUS_D),
	.VBUS_sel(VBUS_SEL),
	.VBUS_dtack_n(VDP_MBUS_DTACK_N),

	.BG_N(M68K_BG_N),
	.BR_N(VBUS_BR_N),
	.BGACK_N(VBUS_BGACK_N),

	.VRAM_SPEED(~(FAST_FIFO|TURBO)),
	.VSCROLL_BUG(0),
	.BORDER_EN(BORDER),
	.CRAM_DOTS(CRAM_DOTS),
	.SVP_QUIRK(SVP_QUIRK),
	.OBJ_LIMIT_HIGH_EN(OBJ_LIMIT_HIGH),

	.FIELD_OUT(FIELD),
	.INTERLACE(INTERLACE),
	.RESOLUTION(RESOLUTION),

	.PAL(PAL),
	.PAL_SAYS(PAL_SAYS),
	.R(RED),
	.G(GREEN),
	.B(BLUE),
	.HS(VDP_hs),
	.VS(VDP_vs),
	.CE_PIX(CE_PIX),
	.HBL(HBL),
	.VBL(VBL),

	.TRANSP_DETECT(TRANSP_DETECT),

	.SS_EN(ss_vdp_en),
	.SS_ADDR(ss_vdp_a),
	.SS_DI(ss_wd),
	.SS_DO(vdp_ss_q),
	.SS_WE(ss_vdp_we),
	.SS_SNAP(ss_vdp_snap),
	.SS_REST(ss_vdp_rest),
	.SS_IDLE(vdp_ss_idle),
	.SS_POS(vdp_ss_pos),
	.SS_SPR(vdp_ss_spr),
	
	.BGA_EN(BGA_EN),
	.BGB_EN(BGB_EN),
	.SPR_EN(SPR_EN)
);

// PSG 0x10-0x17 in VDP space
wire signed [10:0] PSG_SND;
jt89 psg
(
	.rst(reset),
	.clk(MCLK),
	.clk_en(PSG_CLKEN),

	.wr_n(MBUS_RNW | ~VDP_SEL | ~MBUS_A[4] | MBUS_A[3]),
	.din(MBUS_DO[15:8]),

	.sound(PSG_SND),

	.ss_idx(ss_psg_i),
	.ss_q(psg_ss_q),
	.ss_we(ss_psg_we),
	.ss_wd(ss_wd)
);
wire [15:0] psg_ss_q;


//--------------------------------------------------------------
// Gamepads
//--------------------------------------------------------------
reg         IO_SEL;
wire  [7:0] IO_DO;
wire        IO_DTACK_N;

reg         JCART_SEL;
wire [15:0] JCART_DO;
wire        JCART_DTACK_N;

wire [15:0] io_ss_q;

multitap multitap
(
	.RESET(hard_reset),
	.CLK(MCLK),
	.CE(M68K_CLKEN_SYS),

	.SS_IDX(ss_io_i),
	.SS_Q(io_ss_q),
	.SS_WE(ss_io_we),
	.SS_D(ss_wd),

	.J3BUT(J3BUT),

	.P1_UP(~JOY_1[3]),
	.P1_DOWN(~JOY_1[2]),
	.P1_LEFT(~JOY_1[1]),
	.P1_RIGHT(~JOY_1[0]),
	.P1_A(~JOY_1[4]),
	.P1_B(~JOY_1[5]),
	.P1_C(~JOY_1[6]),
	.P1_START(~JOY_1[7]),
	.P1_MODE(~JOY_1[8]),
	.P1_X(~JOY_1[9]),
	.P1_Y(~JOY_1[10]),
	.P1_Z(~JOY_1[11]),

	.P2_UP(~JOY_2[3]),
	.P2_DOWN(~JOY_2[2]),
	.P2_LEFT(~JOY_2[1]),
	.P2_RIGHT(~JOY_2[0]),
	.P2_A(~JOY_2[4]),
	.P2_B(~JOY_2[5]),
	.P2_C(~JOY_2[6]),
	.P2_START(~JOY_2[7]),
	.P2_MODE(~JOY_2[8]),
	.P2_X(~JOY_2[9]),
	.P2_Y(~JOY_2[10]),
	.P2_Z(~JOY_2[11]),

	.P3_UP(~JOY_3[3]),
	.P3_DOWN(~JOY_3[2]),
	.P3_LEFT(~JOY_3[1]),
	.P3_RIGHT(~JOY_3[0]),
	.P3_A(~JOY_3[4]),
	.P3_B(~JOY_3[5]),
	.P3_C(~JOY_3[6]),
	.P3_START(~JOY_3[7]),
	.P3_MODE(~JOY_3[8]),
	.P3_X(~JOY_3[9]),
	.P3_Y(~JOY_3[10]),
	.P3_Z(~JOY_3[11]),

	.P4_UP(~JOY_4[3]),
	.P4_DOWN(~JOY_4[2]),
	.P4_LEFT(~JOY_4[1]),
	.P4_RIGHT(~JOY_4[0]),
	.P4_A(~JOY_4[4]),
	.P4_B(~JOY_4[5]),
	.P4_C(~JOY_4[6]),
	.P4_START(~JOY_4[7]),
	.P4_MODE(~JOY_4[8]),
	.P4_X(~JOY_4[9]),
	.P4_Y(~JOY_4[10]),
	.P4_Z(~JOY_4[11]),
	
	.P5_UP(~JOY_5[3]),
	.P5_DOWN(~JOY_5[2]),
	.P5_LEFT(~JOY_5[1]),
	.P5_RIGHT(~JOY_5[0]),
	.P5_A(~JOY_5[4]),
	.P5_B(~JOY_5[5]),
	.P5_C(~JOY_5[6]),
	.P5_START(~JOY_5[7]),
	.P5_MODE(~JOY_5[8]),
	.P5_X(~JOY_5[9]),
	.P5_Y(~JOY_5[10]),
	.P5_Z(~JOY_5[11]),

	.FOURWAY_EN(MULTITAP == 1),
	.TEAMPLAYER_EN({MULTITAP == 3,MULTITAP == 2}),

	.MOUSE(MOUSE),
	.MOUSE_OPT(MOUSE_OPT),
	
	.GUN_OPT(GUN_OPT),
	.GUN_TYPE(GUN_TYPE),
	.GUN_SENSOR(GUN_SENSOR),
	.GUN_A(GUN_A),
	.GUN_B(GUN_B),
	.GUN_C(GUN_C),
	.GUN_START(GUN_START),

	.SERJOYSTICK_IN(SERJOYSTICK_IN),
	.SERJOYSTICK_OUT(SERJOYSTICK_OUT),
	.SER_OPT(SER_OPT),

	.PAL(PAL_SAYS),
	.EXPORT(EXPORT),

	.SEL(IO_SEL),
	.A(MBUS_A[4:1]),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO[7:0]),
	.DO(IO_DO),
	.DTACK_N(IO_DTACK_N),
	.HL(HL),

	.JCART_SEL(JCART_SEL),
	.JCART_DO(JCART_DO),
	.JCART_DTACK_N(JCART_DTACK_N)
);


//-----------------------------------------------------------------------
// ROM
//-----------------------------------------------------------------------

assign ROM_ADDR = BANK_ROM ? {BANK_REG[MBUS_A[21:19]], MBUS_A[18:1]} : MBUS_A;
assign ROM_BE = ~{MBUS_UDS_N, MBUS_LDS_N};
assign ROM_WDATA = MBUS_DO;

//-----------------------------------------------------------------------
// 64KB SRAM / 128KB SVP DRAM
//-----------------------------------------------------------------------
reg SRAM_SEL;
wire [15:0] sram_addr;
wire [7:0] sram_di;
wire sram_wren;

always_comb begin
	if (PIER_QUIRK) begin
		sram_addr = {4'b0000, m95_addr};
		sram_di = m95_di;
		sram_wren = m95_rnw;
	end else if (EEPROM_MAP) begin
		sram_addr = {3'b000, i2c_addr};
		sram_di = i2c_di;
		sram_wren = i2c_we;
	end else begin
		sram_addr = MBUS_A[16:1];
		sram_di = MBUS_DO[7:0];
		sram_wren = SRAM_SEL & ~MBUS_RNW;
	end
end

dpram_dif #(17,8,16,16) sram
(
	.clock(MCLK),
	.address_a(sram_addr),
	.data_a(sram_di),
	.wren_a(sram_wren & ~SVP_QUIRK),
	.q_a(sram_q),

	.address_b(LOADING ? ram_rst_a : ss_bram ? ss_sram_a : SVP_QUIRK ? SVP_DRAM_A : BRAM_A),
	// Initializes SRAM to 0x0 for Sonic 1 Remastered, all other games have SRAM initialized to 0xFF
	.data_b(LOADING ? (SRAM00_QUIRK ? 16'h0000 : 16'hFFFF) : ss_bram ? {ss_wd[7:0], ss_wd[15:8]} : SVP_QUIRK ? SVP_DRAM_DO : BRAM_DI),
	// (not the .sav's writes with the SVP: this is its DRAM, and the Pocket moves a Memory's .sav around the state)
	.wren_b(LOADING | (ss_bram ? ss_sram_we : SVP_QUIRK ? SVP_DRAM_WE : BRAM_WE)),
	.q_b(BRAM_DO)
);

wire [7:0] sram_q;
assign BRAM_CHANGE = sram_wren;

//-----------------------------------------------------------------------
// EEPROM Handling
//-----------------------------------------------------------------------
reg ep_si, m95_so, ep_sck, ep_hold, ep_cs;
wire [7:0] m95_di, m95_q;
wire [11:0] m95_addr;
wire m95_rnw;

STM95XXX pier_eeprom
(
	.clk(MCLK),
	.enable(PIER_QUIRK),
	.so(m95_so),
	.si(ep_si),
	.sck(ep_sck),
	.hold_n(ep_hold),
	.cs_n(ep_cs),
	.wp_n(1'b1),
	.ram_addr(m95_addr),
	.ram_q(sram_q),
	.ram_di(m95_di),
	.ram_RnW(m95_rnw)
);

// The serial save chips, their contents in the save RAM as above. SDA and SCL
// are the 68000's writes (the 68000's bus, below), the mappers Genesis Plus GX's.
reg  i2c_scl, i2c_sda, i2c_read_map, I2C_SEL;
wire i2c_o, i2c_we;
wire [12:0] i2c_addr;
wire  [7:0] i2c_di;

EEPROM_24CXX i2c_eeprom
(
	.clk(MCLK),
	.reset(sreset),
	.chip(EEPROM_CHIP),
	.scl(i2c_scl),
	.sda(i2c_sda),
	.sda_o(i2c_o),
	.ram_addr(i2c_addr),
	.ram_q(sram_q),
	.ram_di(i2c_di),
	.ram_we(i2c_we),
	.ss_a(ss_i2c_a),
	.ss_we(ss_i2c_we),
	.ss_di(ss_wd),
	.ss_do(ss_i2c_q)
);

//-----------------------------------------------------------------------
// SVP
//-----------------------------------------------------------------------
reg         SVP_SEL;
wire [15:0] SVP_DO;
wire        SVP_DTACK_N;

wire [15:0] SVP_DRAM_A;
wire [15:0] SVP_DRAM_DO;
wire        SVP_DRAM_WE;
wire [15:0] SVP_DRAM_DI = BRAM_DO;

reg SVP_CLKEN;
always @(posedge MCLK) SVP_CLKEN <= ~reset & ~SVP_CLKEN & ~ss_freeze;   // (a save state: held, the memory machine finishes)

SVP svp
(
	.CLK(MCLK),
	.CE(SVP_CLKEN),
	.RST_N(~sreset & SVP_QUIRK),
	.ENABLE(1),

	.BUS_A(MBUS_A[23:1]),
	.BUS_DO(SVP_DO),
	.BUS_DI(MBUS_DO),
	.BUS_SEL(SVP_SEL),
	.BUS_RNW(MBUS_RNW),
	.BUS_DTACK_N(SVP_DTACK_N),
	.DMA_ACTIVE(VBUS_SEL),

	.ROM_A(ROM_ADDR2),
	.ROM_DI(ROM_DATA2),
	.ROM_REQ(ROM_REQ2),
	.ROM_ACK(ROM_ACK2),

	.DRAM_A(SVP_DRAM_A),
	.DRAM_DI(SVP_DRAM_DI),
	.DRAM_DO(SVP_DRAM_DO),
	.DRAM_WE(SVP_DRAM_WE),

	.SS_SH(ss_svp_sh),
	.SS_SI(wr_busy ? ss_wd : svp_ss_so),
	.SS_SO(svp_ss_so),
	.SS_EN(ss_svp_en),
	.SS_A(ss_svp_a),
	.SS_RA_WE(ss_svp_ra_we),
	.SS_RB_WE(ss_svp_rb_we),
	.SS_IR_WE(ss_svp_ir_we),
	.SS_RA_Q(svp_ss_ra),
	.SS_RB_Q(svp_ss_rb),
	.SS_IR_Q(svp_ss_ir),
	.SS_QUIET(svp_ss_quiet)
);


//-----------------------------------------------------------------------
// 68K RAM
//-----------------------------------------------------------------------
reg RAM_SEL;

dpram #(15) ram68k_u
(
	.clock(MCLK),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[15:8]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_UDS_N),
	.q_a(ram68k_q[15:8]),

	.address_b(LOADING ? ram_rst_a[15:1] : ss_ram68_a),
	.data_b(LOADING ? 8'd0 : ss_wd[15:8]),
	.wren_b(LOADING | ss_ram68_we),
	.q_b(ram68k_qb[15:8])
);

dpram #(15) ram68k_l
(
	.clock(MCLK),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[7:0]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_LDS_N),
	.q_a(ram68k_q[7:0]),

	.address_b(LOADING ? ram_rst_a[15:1] : ss_ram68_a),
	.data_b(LOADING ? 8'd0 : ss_wd[7:0]),
	.wren_b(LOADING | ss_ram68_we),
	.q_b(ram68k_qb[7:0])
);
wire [15:0] ram68k_q, ram68k_qb;

//-----------------------------------------------------------------------
// MBUS Handling
//-----------------------------------------------------------------------
reg        M68K_MBUS_DTACK_N;
reg        Z80_MBUS_DTACK_N;
reg        VDP_MBUS_DTACK_N;

reg [15:0] M68K_MBUS_D;
reg  [7:0] Z80_MBUS_D;
reg [15:0] VDP_MBUS_D;

reg [23:1] MBUS_A;
reg [15:0] MBUS_DO;

reg        MBUS_RNW;
reg        MBUS_UDS_N;
reg        MBUS_LDS_N;

reg [15:0] NO_DATA;

reg  [4:0] BANK_REG[0:7];
reg        BANK_ROM;
reg        BANK_SRAM;

reg  [3:0] mstate;
reg  [1:0] msrc;
	
localparam	MSRC_NONE = 0,
				MSRC_M68K = 1,
				MSRC_Z80  = 2,
				MSRC_VDP  = 3;

localparam 	MBUS_IDLE         = 0,
				MBUS_SELECT       = 1,
				MBUS_RAM_READ     = 2,
				MBUS_ROM_READ     = 3,
				MBUS_ROM_WRITE    = 4,
				MBUS_VDP_READ     = 5,
				MBUS_IO_READ      = 6,
				MBUS_JCRT_READ    = 7,
				MBUS_SRAM_READ    = 8,
				MBUS_ZBUS_PRE     = 9,
				MBUS_ZBUS_WS 	   = 10,
				MBUS_ZBUS_READ    = 11,
				MBUS_SVP_READ     = 12,
				MBUS_REFRESH      = 13,
				MBUS_FINISH       = 14,
				MBUS_Z80_PREREAD  = 15; 

				
// Where each mapper has the chip, and which data bit SDA reads back on. Sega's, EA's
// and Acclaim's 16M answer all over 200000-3FFFFF, past the ROM. Acclaim's 32M takes
// writes at 200000-2FFFFF, and has its ROM there to read until a word write of 0
// (below). Codemasters' writes at 300000-37FFFF, reads at 380000-3FFFFF, with the
// J-Cart's pads where the setting has them.
wire i2c_rom_end = EEPROM_MAP <= 3 && MBUS_A[23:21] == 1 && MBUS_A >= ROMSZ;
wire i2c_jcart   = MULTITAP == 4 && ({MBUS_A,1'b0} == 'h3FFFFE || {MBUS_A,1'b0} == 'h38FFFE);
wire i2c_wr_hit  = i2c_rom_end || (EEPROM_MAP == 4 && MBUS_A[23:20] == 2) || (EEPROM_MAP == 5 && MBUS_A[23:19] == 5'b00110);
wire i2c_rd_hit  = i2c_rom_end || (EEPROM_MAP == 4 && MBUS_A[23:20] == 2 && i2c_read_map) || (EEPROM_MAP == 5 && MBUS_A[23:19] == 5'b00111 && ~i2c_jcart);
wire i2c_hit     = EEPROM_MAP != 0 && (MBUS_RNW ? i2c_rd_hit : i2c_wr_hit);
wire i2c_d7      = EEPROM_MAP == 2 || EEPROM_MAP == 5;
wire [15:0] i2c_q = EEPROM_MAP == 3 ? {14'd0, i2c_o, 1'b0} : i2c_d7 ? {8'd0, i2c_o, 7'd0} : {15'd0, i2c_o};

// The 68000's refresh wait: a console holds it about 2 of its clocks in every 128 for the
// memory's refresh. Every 896 MCLK the next access has its DTACK two of the 68000's samples
// late, as BlastEm has it, wherever the access is. (A console's work RAM has a timer of its
// own, at about 3 clocks in 118, measured by Mask of Destiny, and BlastEm doesn't model it.)
// The timer and the flag are in a save state; the count is 0 at the clean point, as the bus
// machine is idle there.
reg [9:0] refresh_timer = 0;
reg       rfs_pend = 0;
reg [1:0] rfs_cnt = 0;

always @(posedge MCLK) begin
	reg [15:0] data;
	reg  [3:0] pier_count;
	reg [1:0] rfs_wait;
	reg [1:0] cycle_cnt;

	if (sreset) begin
		M68K_MBUS_DTACK_N <= 1;
		Z80_MBUS_DTACK_N  <= 1;
		VDP_MBUS_DTACK_N  <= 1;
		VDP_SEL <= 0;
		IO_SEL <= 0;
		SVP_SEL <= 0; 
		ZBUS_SEL <= 0;
		BANK_ROM <= 0;
		BANK_SRAM <= 0;
		mstate <= MBUS_IDLE;
		pier_count <= 0;
		I2C_SEL <= 0;
		i2c_scl <= 1;
		i2c_sda <= 1;
		i2c_read_map <= 0;
		MBUS_RNW <= 1;
		NO_DATA <= 'h4E71;
		BANK_REG <= '{0,1,2,3,4,5,6,7};
		refresh_timer <= 0;
		rfs_pend <= 0;
		rfs_cnt <= 0;
	end
	else begin
		if (M68K_CLKENp) begin
			if (cycle_cnt) cycle_cnt = cycle_cnt - 1'd1;
		end

		if (M68K_AS_N) M68K_MBUS_DTACK_N <= 1;
		if (~Z80_IO)   Z80_MBUS_DTACK_N  <= 1;
		if (~VBUS_SEL) VDP_MBUS_DTACK_N  <= 1;

		case(mstate)
		MBUS_IDLE:
			begin
				CTRL_SEL <= 0;
				SRAM_SEL <= 0;
				RAM_SEL <= 0;
				MBUS_RNW <= 1;
				MBUS_UDS_N <= 1;
				MBUS_LDS_N <= 1;

				// a write to the chip's lines, the strobes known by now (MBUS_FINISH).
				// Sega's and EA's take the low byte's strobe. Acclaim's 16M and
				// Codemasters' look at neither. Acclaim's 32M has D0 go to SDA on the low
				// strobe alone, SCL on the high alone, and with both picks what reads
				// see: 1 the ROM, 0 the chip.
				I2C_SEL <= 0;
				if (I2C_SEL) case (EEPROM_MAP)
					1,3,5: if (EEPROM_MAP != 1 || ~MBUS_LDS_N) {i2c_scl, i2c_sda} <= MBUS_DO[1:0];
					2:     if (~MBUS_LDS_N) {i2c_sda, i2c_scl} <= MBUS_DO[7:6];
					4:     case ({MBUS_UDS_N, MBUS_LDS_N})
					       	2'b10: i2c_sda <= MBUS_DO[0];
					       	2'b01: i2c_scl <= MBUS_DO[0];
					       	2'b00: i2c_read_map <= ~MBUS_DO[0];
					       	default: ;
					       endcase
					default: ;
				endcase
				
				if (!M68K_AS_N && M68K_MBUS_DTACK_N) begin
					msrc <= MSRC_M68K;
					MBUS_A <= M68K_A[23:1];
					data <= NO_DATA;
					MBUS_DO <= M68K_DO;
					MBUS_RNW <= M68K_RNW;
					mstate <= MBUS_SELECT;
				end
				else if (VBUS_SEL && VDP_MBUS_DTACK_N) begin
					msrc <= MSRC_VDP;
					MBUS_A <= VBUS_A;
					data <= NO_DATA;
					MBUS_DO <= 0;
					mstate <=  MBUS_SELECT;
				end
				else if (Z80_IO && !Z80_ZBUS && Z80_MBUS_DTACK_N && !Z80_BGACK_N && Z80_BR_N) begin
					msrc <= MSRC_Z80;
					MBUS_A <= Z80_A[15] ? {BAR[23:15],Z80_A[14:1]} : {16'hC000, Z80_A[7:1]};
					data <= 16'hFFFF;
					MBUS_DO <= {Z80_DO,Z80_DO};
					MBUS_RNW <= Z80_WR_N;
					mstate <= MBUS_Z80_PREREAD;
					cycle_cnt <= 2'd1;
				end
			end
			
		MBUS_Z80_PREREAD:
			begin
				if (!cycle_cnt) begin
					mstate <= MBUS_SELECT;
					cycle_cnt <= 2'd1;
				end
			end

		MBUS_SELECT:
			if (ss_vec && msrc == MSRC_M68K && !MBUS_A[23:3]) begin
				// save states: a load's 68000 reads its reset vectors, and
				// gets the state's stack pointer and PC
				case (MBUS_A[2:1])
					0: data <= ss_vec_sp[31:16];
					1: data <= ss_vec_sp[15:0];
					2: data <= ss_vec_pc[31:16];
					3: data <= ss_vec_pc[15:0];
				endcase
				mstate <= MBUS_FINISH;
			end
			else begin
				//NO DEVICE (usually lockup on real HW)
				mstate <= MBUS_FINISH;

				if (MBUS_A[23:20]<'hA || (msrc == MSRC_Z80 && MBUS_A[23:20]<'hE && ROMSZ[24:20]>='hA)) begin
					//ROM: 000000-9FFFFF (A00000-DFFFFF)
					if (i2c_hit) begin
						// (its reads answered here, its writes done back in MBUS_IDLE)
						I2C_SEL <= ~MBUS_RNW;
						data <= i2c_q;
					end
					else if (BANK_SRAM && MBUS_A[23:21] == 1) begin
						// 200000-3FFFFF SRAM overrides ROM when bank is selected
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if (PIER_QUIRK && ({MBUS_A,1'b0} == 'h0015E6 || {MBUS_A,1'b0} == 'h0015E8)) begin
						if (pier_count < 'h6) begin
							pier_count <= pier_count + 1'h1;
							data <= MBUS_A[1] ? 16'h0 : 16'h0010;
						end else begin
							data <= MBUS_A[1] ? 16'h0001 : 16'h8010;
						end
					end
					else if (SRAM00_QUIRK && {MBUS_A,1'b0} == 'h200000) begin
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if(SVP_QUIRK && MBUS_A[23:20] == 3) begin
						// 300000-37FFFF (+mirrors) SVP DRAM
						// 390000-39FFFF SVP DRAM cell arrange 1
						// 3A0000-3AFFFF SVP DRAM cell arrange 2
						SVP_SEL <= 1;
						mstate <= MBUS_SVP_READ;
					end 
					else if (SCHAN_QUIRK && ~MBUS_RNW && (MBUS_A < 'h400000)) begin
						mstate <= MBUS_ROM_WRITE;
					end
					else if (MBUS_A < ROMSZ) begin
						if (SVP_QUIRK && msrc == MSRC_VDP) MBUS_A <= MBUS_A - 1'd1;
						ROM_WE <= 0;
						ROM_REQ <= ~ROM_ACK;
						mstate <= MBUS_ROM_READ;
					end
					else if ((MULTITAP == 4) && ({MBUS_A,1'b0} == 'h3FFFFE || {MBUS_A,1'b0} == 'h38FFFE)) begin
						JCART_SEL <= 1;
						mstate <= MBUS_JCRT_READ;
					end
					else if(MBUS_A[23:21] == 1 && ~&MBUS_A[20:19] && ~NORAM_QUIRK) begin
						// 200000-37FFFF
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else begin
						data <= 0;
						mstate <= MBUS_FINISH;
					end
				end

				//ZBUS: A00000-A07FFF (A08000-A0FFFF)
				else if(MBUS_A[23:16] == 'hA0) mstate <= !Z80_BUSRQ_N ? MBUS_ZBUS_PRE : MBUS_FINISH;

				//I/O: A10000-A1001F (+mirrors)
				else if(MBUS_A[23:5] == {16'hA100, 3'b000}) begin
					IO_SEL <= 1;
					mstate <= MBUS_IO_READ;
				end

				//CTL: A11100, A11200
				else if(MBUS_A[23:12] == 12'hA11 && !MBUS_A[7:1]) begin
					CTRL_SEL <= 1;
					data <= CTRL_DO;
					mstate <= MBUS_FINISH;
				end

				// BANK Register A13XXX
				else if (MBUS_A[23:8] == 'hA130) begin
					if (~MBUS_RNW) begin
						if (ROMSZ > 'h200000) begin // SSF2/Pier Solar ROM banking
							if (MBUS_A[3:1]) begin
								BANK_ROM <= 1;
								if (~PIER_QUIRK) begin // SSF2
									BANK_REG[MBUS_A[3:1]] <= MBUS_DO[4:0];
								end
								else if (MBUS_A[3:1] == 4) begin // Pier EEPROM
									{ep_cs, ep_hold , ep_sck, ep_si} <= MBUS_DO[3:0];
								end
								else if (~MBUS_A[3]) begin // Pier Banks
									BANK_REG[{1'b1,MBUS_A[2:1]}] <= MBUS_DO[3:0];
								end
							end
							else if (~PIER_QUIRK) begin // SRAM control only in the first register on SSF2 mapper
							   BANK_SRAM <= {MBUS_DO[0]};
							end
						end else begin
							BANK_SRAM <= {MBUS_DO[0]};
						end
					end else if (PIER_QUIRK && MBUS_A[3:1] == 'h5) begin
						data <= {15'h7FFF, m95_so};
					end
					mstate <= MBUS_FINISH;
				end
				
				//SVP: A15000-A5000F 
				else if(MBUS_A[23:4] == 20'hA1500) begin
					SVP_SEL <= 1;
					mstate <= MBUS_SVP_READ;
				end 

				//VDP: C00000-C0001F (+mirrors)
				else if(MBUS_A[23:21] == 3'b110 && !MBUS_A[18:16] && !MBUS_A[7:5]) begin
					VDP_SEL <= 1;
					mstate <= MBUS_VDP_READ;
				end

				//RAM: E00000-FFFFFF
				else if(&MBUS_A[23:21]) begin
					RAM_SEL <= 1;
					mstate <= MBUS_RAM_READ;
				end
			end
			
		MBUS_ZBUS_PRE:
			case(msrc)
			MSRC_M68K:
				if(M68K_AS_N | (~M68K_UDS_N | ~M68K_LDS_N)) begin
					MBUS_UDS_N <= M68K_UDS_N;
					MBUS_LDS_N <= M68K_LDS_N;
					ZBUS_SEL <= 1;
					mstate <= MBUS_RNW ? MBUS_ZBUS_WS : MBUS_ZBUS_READ;
				end

			MSRC_Z80:
				begin
					MBUS_UDS_N <= Z80_A[0];
					MBUS_LDS_N <= ~Z80_A[0];
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end

			MSRC_VDP:
				begin
					MBUS_UDS_N <= 0;
					MBUS_LDS_N <= 0;
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end
			endcase

		MBUS_ZBUS_WS:
			begin
				if (M68K_CLKENp) begin
					mstate <= MBUS_ZBUS_READ;
				end
			end
			
		MBUS_ZBUS_READ:
			begin
				if(~MBUS_ZBUS_DTACK_N) begin
					ZBUS_SEL <= 0;
					data <= {MBUS_ZBUS_D, MBUS_ZBUS_D};
					mstate <= MBUS_FINISH;
				end
			end

		MBUS_RAM_READ:
			begin
				data <= ram68k_q;
				if(msrc == MSRC_M68K) NO_DATA <= ram68k_q;
				mstate <= MBUS_FINISH;
			end

		MBUS_ROM_WRITE:
			case(msrc)
			MSRC_M68K:
				if(M68K_AS_N | (~M68K_UDS_N | ~M68K_LDS_N)) begin
					MBUS_UDS_N <= M68K_UDS_N;
					MBUS_LDS_N <= M68K_LDS_N;
					ROM_WE <= 1;
					ROM_REQ <= ~ROM_ACK;
					mstate <= MBUS_ROM_READ;
				end

			MSRC_Z80:
				begin
					MBUS_UDS_N <= Z80_A[0];
					MBUS_LDS_N <= ~Z80_A[0];
					ROM_WE <= 1;
					ROM_REQ <= ~ROM_ACK;
					mstate <= MBUS_ROM_READ;
				end
			endcase

		MBUS_ROM_READ:
			if (ROM_REQ == ROM_ACK) begin
				data <= ROM_DATA;
				if(msrc == MSRC_M68K) NO_DATA <= ROM_DATA;
				if (msrc != MSRC_Z80 || !cycle_cnt)
					mstate <= MBUS_FINISH;
			end

		MBUS_SRAM_READ:
			begin
				data <= {sram_q,sram_q};
				if(msrc == MSRC_M68K) NO_DATA <= {sram_q,sram_q};
				SRAM_SEL <= 0;
				mstate <= MBUS_FINISH;
			end

		MBUS_VDP_READ:
			if (~VDP_DTACK_N) begin
				VDP_SEL <= 0;
				data <= VDP_DO;
				if(MBUS_A[4:2] == 1) data[15:10] <= NO_DATA[15:10]; //unused status bits
				else if(MBUS_A[4]) data <= NO_DATA; // PSG/debug registers
				mstate <= MBUS_FINISH;
			end

		MBUS_IO_READ:
			if(~IO_DTACK_N) begin
				IO_SEL <= 0;
				data <= {IO_DO, IO_DO};
				mstate <= MBUS_FINISH;
			end

		MBUS_JCRT_READ:
			if(~JCART_DTACK_N) begin
				JCART_SEL <= 0;
				data <= (JCART_DO & 16'h3F7F) | (EEPROM_MAP == 5 ? {8'd0, i2c_o, 7'd0} : 16'd0);
				mstate <= MBUS_FINISH;
			end

		MBUS_SVP_READ:
			if(~SVP_DTACK_N) begin
				SVP_SEL <= 0;
				data <= SVP_DO;
				mstate <= MBUS_FINISH;
			end 

		MBUS_REFRESH:
			if (M68K_CLKENp) begin
				rfs_wait <= rfs_wait + 1'd1;
				if (rfs_wait == 1) begin
					rfs_wait <= 0;
					mstate <= MBUS_IDLE;
				end
			end

		MBUS_FINISH:
			begin
				case(msrc)
				MSRC_M68K:
					// (only before DTACK: past it, a write's strobes are on their way and
					// have to be caught as they come. And not while frozen: a load's 68000
					// fetches through here, and the flag is what the state says)
					if (rfs_pend && M68K_MBUS_DTACK_N && !ss_freeze) begin
						rfs_pend <= 0;
						rfs_cnt <= 2'd2;
					end
					else if (rfs_cnt) begin
						if (M68K_CLKENn) rfs_cnt <= rfs_cnt - 1'd1;
					end
					else begin
						M68K_MBUS_D <= data;
						M68K_MBUS_DTACK_N <= 0;
						if((M68K_AS_N | MBUS_RNW | ~M68K_UDS_N | ~M68K_LDS_N)) begin
							MBUS_UDS_N <= M68K_UDS_N;
							MBUS_LDS_N <= M68K_LDS_N;
							mstate <= MBUS_IDLE;
						end
					end

				MSRC_Z80:
					begin
						if (Z80_CLKENp) begin
							Z80_MBUS_D <= Z80_A[0] ? data[7:0] : data[15:8];
							Z80_MBUS_DTACK_N <= 0;
							MBUS_UDS_N <= Z80_A[0];
							MBUS_LDS_N <= ~Z80_A[0];
							mstate <= MBUS_IDLE;
						end
					end

				MSRC_VDP:
					begin
						VDP_MBUS_D <= data;
						VDP_MBUS_DTACK_N <= 0;
						mstate <= MBUS_IDLE;
					end
				endcase
			end
		endcase

		// the refresh's timer, held with the 68000's clock in a save state
		if (!ss_freeze) begin
			refresh_timer <= refresh_timer + 1'd1;
			if (refresh_timer == 10'h37F) begin
				refresh_timer <= 0;
				rfs_pend <= 1;
			end
		end

		// save states: the mapper written by a load, the open bus at its end
		if (ss_cw && ss_wa[16:2] == 15'h0008) begin
			BANK_REG[{ss_wa[1:0], 1'b0}] <= ss_wd[12:8];
			BANK_REG[{ss_wa[1:0], 1'b1}] <= ss_wd[4:0];
		end
		if (ss_cw && ss_wa == 17'h00024) {BANK_ROM, BANK_SRAM} <= ss_wd[3:2];
		if (ss_cw && ss_wa == 17'h0002C) {i2c_read_map, i2c_scl, i2c_sda} <= ss_wd[2:0];
		if (ss_cw && ss_wa == 17'h00030) {rfs_pend, refresh_timer} <= ss_wd[10:0];
		if (ss_nodata_we) NO_DATA <= ss_nodata_d;
	end
end


//--------------------------------------------------------------
// CPU Z80
//--------------------------------------------------------------
reg         Z80_RESET_N;
reg         Z80_BUSRQ_N;
wire        Z80_BUSAK_N;
wire        Z80_MREQ_N;
wire        Z80_RD_N;
wire        Z80_WR_N;
wire [15:0] Z80_A;
wire  [7:0] Z80_DO;
wire        Z80_IO = ~Z80_MREQ_N & (~Z80_RD_N | ~Z80_WR_N);
wire [211:0] z80_reg;
wire  [18:0] z80_regx;
wire         z80_instend;

T80s #(.T2Write(1)) Z80
//T80pa Z80
(
	.RESET_n(Z80_RESET_N & ~ss_rstZ),
	.CLK(MCLK),
//	.CEN_p(Z80_CLKENp),
//	.CEN_n(Z80_CLKENn),
	.CEN(Z80_CLKENn),
	.BUSRQ_n(Z80_BUSRQ_N),
	.BUSAK_n(Z80_BUSAK_N),
	.WAIT_n(~Z80_MBUS_DTACK_N | ~Z80_ZBUS_DTACK_N | ~Z80_IO),
	.INT_n(~Z80_VINT),
	.MREQ_n(Z80_MREQ_N),
	.RD_n(Z80_RD_N),
	.WR_n(Z80_WR_N),
	.A(Z80_A),
	.DI((~Z80_MBUS_DTACK_N) ? Z80_MBUS_D : Z80_ZBUS_D),
	.DO(Z80_DO),

	// save states
	.REG(z80_reg),
	.DIRSet(ss_dirset),
	.DIR(ss_dir),
	.SS_Park(ss_zpark),
	.InstEnd(z80_instend),
	.REGX(z80_regx),
	.DIRX(ss_dirx)
);


// (a Z80 stopped by a save, not by the game, is not shown to it as granted)
wire        CTRL_F  = (MBUS_A[11:8] == 1) ? Z80_BUSAK_N | (ss_zpark & Z80_BUSRQ_N) : (MBUS_A[11:8] == 2) ? Z80_RESET_N : NO_DATA[8];
wire [15:0] CTRL_DO = {NO_DATA[15:9], CTRL_F, NO_DATA[7:0]};
reg         CTRL_SEL;
always @(posedge MCLK) begin
	if (sreset) begin
		Z80_BUSRQ_N <= 1;
		Z80_RESET_N <= 0;
	end
	else if (ss_cw && ss_wa == 17'h00024) {Z80_BUSRQ_N, Z80_RESET_N} <= ss_wd[1:0];
	else if(CTRL_SEL & ~MBUS_RNW & ~MBUS_UDS_N) begin
		if (MBUS_A[11:8] == 1) Z80_BUSRQ_N <= ~MBUS_DO[8];
		if (MBUS_A[11:8] == 2) Z80_RESET_N <=  MBUS_DO[8];
	end
end

//-----------------------------------------------------------------------
// ZBUS Handling
//-----------------------------------------------------------------------
// Z80:   0000-7EFF
// 68000: A00000-A07FFF (A08000-A0FFFF)

wire       Z80_ZBUS  = ~Z80_A[15] && ~&Z80_A[14:8];

wire       ZBUS_NO_BUSY = ZBUS_A[14] && ~|ZBUS_A[13:2] && |ZBUS_A[1:0] && FMBUSY_QUIRK;

reg        ZBUS_SEL;
reg [14:0] ZBUS_A;
reg        ZBUS_WE;
reg  [7:0] ZBUS_DO;
wire [7:0] ZBUS_DI = ZRAM_SEL ? ZRAM_DO : (FM_SEL ? (ZBUS_NO_BUSY ? {1'b0, FM_DO[6:0]} : FM_DO) : 8'hFF);

reg  [7:0] MBUS_ZBUS_D;
reg  [7:0] Z80_ZBUS_D;

reg        MBUS_ZBUS_DTACK_N;
reg        Z80_ZBUS_DTACK_N;

reg        Z80_BR_N;
reg        Z80_BGACK_N;

wire       Z80_ZBUS_SEL = Z80_ZBUS & Z80_IO;
wire       ZBUS_FREE = ~Z80_BUSRQ_N & Z80_RESET_N;

wire       Z80_MBUS_SEL = Z80_IO & ~Z80_ZBUS;

// RAM 0000-1FFF (2000-3FFF)
wire ZRAM_SEL = ~ZBUS_A[14];

wire  [7:0] ZRAM_DO;
dpram #(13) ramZ80
(
	.clock(MCLK),
	.address_a(ZBUS_A[12:0]),
	.data_a(ZBUS_DO),
	.wren_a(ZBUS_WE & ZRAM_SEL),
	.q_a(ZRAM_DO),

	.address_b(ss_zram_a),
	.data_b(ss_zram_a[0] ? ss_wd[7:0] : ss_wd[15:8]),
	.wren_b(ss_zram_we),
	.q_b(zram_qb)
);
wire  [7:0] zram_qb;

reg [1:0] zstate;
always @(posedge MCLK) begin
	reg [1:0] zsrc;
	reg Z80_BGACK_DIS;

	localparam 	ZSRC_MBUS = 0,
					ZSRC_Z80  = 1;

	localparam	ZBUS_IDLE   = 0,
					ZBUS_READ   = 1,
					ZBUS_FINISH = 2;

	ZBUS_WE <= 0;
	
	if (sreset) begin
		MBUS_ZBUS_DTACK_N <= 1;
		Z80_ZBUS_DTACK_N  <= 1;
		zstate <= ZBUS_IDLE;
		
		Z80_BR_N <= 1;
		Z80_BGACK_N <= 1;
		Z80_BGACK_DIS <= 0;
	end
	else begin
		if (~ZBUS_SEL)     MBUS_ZBUS_DTACK_N <= 1;
		if (~Z80_ZBUS_SEL) Z80_ZBUS_DTACK_N  <= 1;

		case (zstate)
		ZBUS_IDLE:
			begin
				if (Z80_RD_N)      Z80_ZBUS_D <= 8'hFF;

				if (ZBUS_SEL & MBUS_ZBUS_DTACK_N) begin
					ZBUS_A <= {MBUS_A[14:1], MBUS_UDS_N};
					ZBUS_DO <= (~MBUS_UDS_N) ? MBUS_DO[15:8] : MBUS_DO[7:0];
					ZBUS_WE <= ~MBUS_RNW & ZBUS_FREE;
					zsrc <= ZSRC_MBUS;
					zstate <= ZBUS_READ;
				end
				else if (Z80_ZBUS_SEL & Z80_ZBUS_DTACK_N) begin
					ZBUS_A <= Z80_A[14:0];
					ZBUS_DO <= Z80_DO;
					ZBUS_WE <= ~Z80_WR_N;
					zsrc <= ZSRC_Z80;
					zstate <= ZBUS_READ;
				end
			end

		ZBUS_READ:
			zstate <= ZBUS_FINISH;

		ZBUS_FINISH:
			begin
				case(zsrc)
				ZSRC_MBUS:
					begin
						MBUS_ZBUS_D <= ZBUS_FREE ? ZBUS_DI : 8'hFF;
						MBUS_ZBUS_DTACK_N <= 0;
					end

				ZSRC_Z80:
					begin
						Z80_ZBUS_D <= ZBUS_DI;
						Z80_ZBUS_DTACK_N <= 0;
					end
				endcase
				zstate <= ZBUS_IDLE;
			end
		endcase
		
		if (Z80_MBUS_SEL && Z80_BR_N && Z80_BGACK_N && VBUS_BR_N && VBUS_BGACK_N && M68K_CLKENp) begin
			Z80_BR_N <= 0;
		end
		else if (!Z80_BR_N && !M68K_BG_N && M68K_AS_N && M68K_CLKENn) begin
			Z80_BGACK_N <= 0;
		end
		else if (!Z80_BGACK_N && !Z80_BR_N && !M68K_BG_N && M68K_CLKENp) begin
			Z80_BR_N <= 1;
		end
		else if (!Z80_BGACK_DIS && !Z80_BGACK_N && Z80_BR_N && !Z80_MBUS_SEL && M68K_CLKENn) begin
			Z80_BGACK_DIS <= 1;
		end
		else if (!Z80_BGACK_N && Z80_BGACK_DIS && M68K_CLKENn) begin
			Z80_BGACK_N <= 1;
			Z80_BGACK_DIS <= 0;
		end
	end
end


//-----------------------------------------------------------------------
// Z80 BANK REGISTER
//-----------------------------------------------------------------------
// 6000-60FF

wire BANK_SEL = ZBUS_A[14:8] == 7'h60;
reg [23:15] BAR;

always @(posedge MCLK) begin
	if (sreset) BAR <= 0;
	else if (ss_cw && ss_wa == 17'h00025) BAR <= ss_wd[8:0];
	else if (BANK_SEL & ZBUS_WE) BAR <= {ZBUS_DO[0], BAR[23:16]};
end


//--------------------------------------------------------------
// YM2612
//--------------------------------------------------------------
// 4000-4003 (4000-5FFF)

wire        FM_SEL = ZBUS_A[14:13] == 2'b10;
wire  [7:0] FM_DO;
wire signed [15:0] FM_right;
wire signed [15:0] FM_left;
wire signed [15:0] FM_LPF_right;
wire signed [15:0] FM_LPF_left;
wire signed [15:0] PRE_LPF_L;
wire signed [15:0] PRE_LPF_R;

wire [15:0] fm_ss_tap;
wire        fm_ss_go, fm_ss_cen;
wire  [4:0] fm_ss_slot;

jt12 fm
(
	// (a load: out of reset, frozen, its state written by its scan)
	.rst(~Z80_RESET_N & ~ss_fm_load),
	.clk(MCLK),
	.cen(FM_CLKEN),

	.cs_n(0),
	.addr(ZBUS_A[1:0]),
	.wr_n(~(FM_SEL & ZBUS_WE)),
	.din(ZBUS_DO),
	.dout(FM_DO),
	.en_hifi_pcm( EN_HIFI_PCM ),
	.ladder(LADDER),
	.snd_left(FM_left),
	.snd_right(FM_right),

	// save states: the YM2612's scan
	.ss_scan(ss_fm_scan),
	.ss_step(ss_fm_step),
	.ss_lane(ss_fm_lane),
	.ss_load(ss_fm_ld),
	.ss_wd(ss_wd),
	.ss_tap(fm_ss_tap),
	.ss_gsh(ss_fm_gsh),
	.ss_gi(ss_fm_gi),
	.ss_go(fm_ss_go),
	.ss_slot(fm_ss_slot),
	.ss_cen(fm_ss_cen)
);

wire signed [15:0] fm_adjust_l = (FM_left  << 4) + (FM_left  << 2) + (FM_left  << 1) + (FM_left  >>> 2);
wire signed [15:0] fm_adjust_r = (FM_right << 4) + (FM_right << 2) + (FM_right << 1) + (FM_right >>> 2);

genesis_fm_lpf fm_lpf_l
(
	.clk(MCLK),
	.reset(reset),
	.in(fm_adjust_l),
	.out(FM_LPF_left)
);

genesis_fm_lpf fm_lpf_r
(
	.clk(MCLK),
	.reset(reset),
	.in(fm_adjust_r),
	.out(FM_LPF_right)
);

wire signed [15:0] fm_select_l = ((LPF_MODE == 2'b01) ? FM_LPF_left : fm_adjust_l);
wire signed [15:0] fm_select_r = ((LPF_MODE == 2'b01) ? FM_LPF_right : fm_adjust_r);

wire signed [10:0] psg_adjust = PSG_SND - (PSG_SND >>> 5);

jt12_genmix genmix
(
	.rst(reset),
	.clk(MCLK),
	.fm_left(fm_select_l),
	.fm_right(fm_select_r),
	.psg_snd(psg_adjust),
	.fm_en(ENABLE_FM),
	.psg_en(ENABLE_PSG),
	.snd_left(PRE_LPF_L),
	.snd_right(PRE_LPF_R)
);

genesis_lpf lpf_right
(
	.clk(MCLK),
	.reset(reset),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_R),
	.out(DAC_RDATA)
);

genesis_lpf lpf_left
(
	.clk(MCLK),
	.reset(reset),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_L),
	.out(DAC_LDATA)
);

//--------------------------------------------------------------
// SAVE STATES
//--------------------------------------------------------------
// The state by word (its byte offset / 2), in the file's format:
//   00000 header        00020 console       00040 68000          00080 Z80
//   000A0 VDP's registers, port and snapshot  00120 PSG          00140 pads
//   00180 YM2612 chain  00200 YM2612 loops  00500 CRAM  00540 VSRAM  00580 sprite cache
//   00800 the SVP's chain  00900 its RAM A  00A00 its RAM B      00C00 its IRAM
//   01000 Z80 RAM       02000 68000 RAM     0A000 VRAM           12000 save RAM (64 KB), or the SVP's DRAM (128 KB)

// The PC a load's reset vector gives, against the PC saved, found in the
// simulation: at a boundary the PC is the opcode's address + 2 (the IRC's),
// as the reset's prefetch leaves it. STOP waits by dispatching itself again
// and again (its first microword, SS_STOP_UA in MiSTer's FX68K microcode),
// the PC then 6 past its opcode; a load runs it until its PC is the saved one.
localparam [31:0] SS_START_PC = 32'd2;
localparam [31:0] SS_STOP_PC  = 32'd6;
localparam  [9:0] SS_STOP_UA  = 10'h3A2;

localparam SS_RUN = 0, SS_SEEK = 1, SS_FROZEN = 2, SS_UNSCAN = 3, SS_WAIT = 4,
           SS_LSTOP = 5, SS_LOADING = 6, SS_RZ80 = 7, SS_R68_1 = 8, SS_R68_2 = 9, SS_R68_3 = 10, SS_R68_4 = 11;
reg   [3:0] ss_st = SS_RUN;
reg         ss_err = 0;
reg         ss_loaded = 0;              // what is let go of came from a load: a whole frame first
reg         ss_frame_seen = 0;
reg   [7:0] ss_tries;
reg         ss_win = 0, ss_vint_d = 0, ss_retry = 0, ss_inwin = 0;
reg   [1:0] ss_fmc = 0;
reg  [11:0] ss_park_t;
reg   [5:0] ss_cnt;
reg  [19:0] ss_wait_t;
reg  [22:0] ss_pos;                     // the raster position at the freeze: field, line, dot, pixel divider
reg         ss_m68_stop;                // the 68000 was in STOP's wait
reg  [31:0] ss_frames;
reg         ss_vbl_d;
reg         ss_spr_bad = 0, ss_spr_cur = 0, ss_spr_d = 0;
// the read and write engine: a word at a time
reg   [4:0] e_cnt;
reg  [17:0] e_a;
reg  [15:0] rd_sh, rd_tap;
reg   [7:0] rd_b0;
reg   [9:0] ch_pos;                     // the YM2612's chain: bits moved, mod 603
reg   [3:0] lp_lane;                    // its loops: the lane, and the step mod 24
reg   [4:0] lp_step;
reg   [5:0] svp_pos;                    // the SVP's chain: words moved, mod 63
// staging: what a load gives the chips only at the end
reg  [15:0] st_reghi, st_sr, st_misc, st_grpd, st_clk, st_nodata;
reg  [31:0] st_pc;
reg  [23:0] st_div;
reg [223:0] st_zpad;
assign ss_dir = st_zpad[211:0];

wire [17:0] ea = e_a;
wire in_hdr   = ea < 17'h20;
wire in_con   = ea >= 17'h20   && ea < 17'h40;
wire in_68k   = ea >= 17'h40   && ea < 17'h80;
wire in_z80   = ea >= 17'h80   && ea < 17'hA0;
wire in_vdpr  = ea >= 17'hA0   && ea < 17'hC2;
wire in_psg   = ea >= 17'h120  && ea < 17'h12A;
wire in_io    = ea >= 17'h140  && ea < 17'h14C;
wire in_chain = ea >= 17'h180  && ea < 17'h1A6;
wire in_loops = ea >= 17'h200  && ea < 17'h320;
wire in_cram  = ea >= 17'h500  && ea < 17'h540;
wire in_vsram = ea >= 17'h540  && ea < 17'h568;
wire in_cache = ea >= 17'h580  && ea < 17'h620;
wire in_zram  = ea >= 17'h1000 && ea < 17'h2000;
wire in_ram68 = ea >= 17'h2000 && ea < 17'hA000;
wire in_vram  = ea >= 17'hA000 && ea < 17'h12000;
wire in_sram  = ea >= 18'h12000;         // (the file's end is state_bridge.sv's)
wire in_svp   = SVP_QUIRK && ea[17:11] == 7'd1;
wire in_svpc  = in_svp && !ea[10] && ea[9:8] == 0 && ea[7:0] < 8'd63;
wire in_rama  = in_svp && !ea[10] && ea[9:8] == 1;
wire in_ramb  = in_svp && !ea[10] && ea[9:8] == 2;
wire in_iram  = in_svp && ea[10];
wire [16:0] o_con = ea - 17'h20, o_68k = ea - 17'h40, o_z80 = ea - 17'h80, o_vdpr = ea - 17'hA0;
wire [16:0] o_psg = ea - 17'h120, o_io = ea - 17'h140, o_cram = ea - 17'h500, o_vsram = ea - 17'h540;
wire [16:0] o_cache = ea - 17'h580, o_ram68 = ea - 17'h2000, o_vram = ea - 17'hA000, o_sram = ea - 17'h12000;
wire        last_chain = ea == 17'h1A5;  // the chain's last word moves 11 bits

wire e_w0 = wr_busy && e_cnt == 0;
assign ss_cw       = e_w0 && in_con;
assign ss_wa       = o_con + 17'h20;
assign ss_ipl_we   = e_w0 && in_con && o_con == 6;
assign ss_ipl_d    = ss_wd[5:0];
assign ss_vdp_a    = in_cram ? {4'h1, o_cram[5:0]} : in_vsram ? {4'h2, o_vsram[5:0]} : in_cache ? {2'b01, o_cache[7:0]} : {2'b00, o_vdpr[7:0]};
assign ss_vdp_we   = e_w0 && (in_vdpr || in_cram || in_vsram || in_cache);
assign ss_psg_i    = o_psg[3:0];
assign ss_psg_we   = e_w0 && in_psg;
assign ss_io_i     = o_io[3:0];
assign ss_io_we    = e_w0 && in_io;
assign ss_vram_a   = o_vram[14:0];
assign ss_vram_we  = e_w0 && in_vram;
assign ss_ram68_a  = o_ram68[14:0];
assign ss_ram68_we = e_w0 && in_ram68;
assign ss_sram_a   = o_sram[15:0];
assign ss_sram_we  = e_w0 && in_sram;
assign ss_i2c_a    = o_con[1:0] - 2'd1;
assign ss_i2c_we   = e_w0 && in_con && o_con >= 13 && o_con <= 15;
assign ss_zram_a   = {ea[11:0], e_cnt >= 5'd8};       // a word's first byte, then from e_cnt 8 its second
assign ss_zram_we  = wr_busy && in_zram && (e_cnt == 0 || e_cnt == 8);
assign ss_svp_a    = ea[9:0];
assign ss_svp_ra_we = e_w0 && in_rama;
assign ss_svp_rb_we = e_w0 && in_ramb;
assign ss_svp_ir_we = e_w0 && in_iram;
assign fx_rega     = o_68k[5:1];
assign fx_regd     = {st_reghi, ss_wd};
assign fx_regwe    = e_w0 && in_68k && o_68k < 17'h22 && o_68k[0];

// the YM2612's scan: the chain 16 moves a word (11 for its last), fed back on a
// read; the loops a step a word; and both brought round to where they started
wire un_chain = ss_st == SS_UNSCAN && ch_pos != 0;
wire un_loop  = ss_st == SS_UNSCAN && lp_step != 0;
assign ss_fm_gsh  = ((rd_busy | wr_busy) && in_chain && e_cnt >= 1 && e_cnt <= (last_chain ? 5'd11 : 5'd16)) || un_chain;
assign ss_fm_gi   = (wr_busy && in_chain) ? ss_wd[5'd16 - e_cnt] : fm_ss_go;
assign ss_fm_lane = lp_lane;
assign ss_fm_ld   = wr_busy && in_loops && e_cnt == 0;
assign ss_fm_step = (wr_busy && in_loops && e_cnt == 0) || (rd_busy && in_loops && e_cnt == 2) || un_loop;

// the SVP's chain a word at a time, as the YM2612's, fed back on a read
wire un_svp  = ss_st == SS_UNSCAN && svp_pos != 0;
wire svp_mov = (rd_busy && in_svpc && e_cnt == 20) || (e_w0 && in_svpc) || un_svp;
wire ss_svp_ok = ~SVP_QUIRK | ss_svp_en;      // quiet, so its memories are free for the state
wire ss_a_sram = SS_ADDR[17] | (SS_ADDR[16] & |SS_ADDR[15:13]);
wire ss_a_svpc = SVP_QUIRK && SS_ADDR >= 18'h800 && SS_ADDR < 18'h83F;

wire [16:0] ss_lpos = {lp_lane, 4'd0} + {lp_lane, 3'd0} + lp_step;   // lane * 24 + step
wire [223:0] z80_pad = {12'd0, z80_reg};
wire  [15:0] z80_pc = z80_reg[79:64];          // (to watch in the simulation)
wire [15:0] ss_flags = {5'd0, FAST_FIFO, SCHAN_QUIRK, FMBUSY_QUIRK, PIER_QUIRK, NORAM_QUIRK, EEPROM_MAP != 0 && EEPROM_MAP != 4,
                        SRAM00_QUIRK, EEPROM_MAP == 4, SVP_QUIRK, EXPORT, PAL};

// the conditions of the clean point
wire ss_z80_end = ~Z80_BUSAK_N & z80_instend;               // stopped where an instruction ends
wire ss_hold68  = ~Z80_BUSRQ_N & Z80_RESET_N & ~ss_z80_end;  // the game holds the Z80 mid-instruction: the 68000 must go on
wire ss_ok68    = ss_park68 & fx_atstart & fx_busidle & M68K_AS_N & M68K_MBUS_DTACK_N;
// not in STOP with an interrupt waiting (the menu's pause lets one build up): a
// load goes round STOP's loop to the saved PC and would take it there. Parked
// 64 us, the 68000 is let go for an instruction and takes it
wire ss_stopirq = fx_uaddr == SS_STOP_UA && (fx_misc[1] || &(~M68K_IPL_N) || (~M68K_IPL_N) > fx_sr[10:8]);
wire ss_okZ     = ~Z80_RESET_N | ss_z80_end;
wire ss_okV     = vdp_ss_idle & ~VBUS_SEL & VBUS_BR_N & VBUS_BGACK_N & ~VDP_SEL;
wire ss_okB     = mstate == MBUS_IDLE && zstate == 0 && Z80_BR_N && Z80_BGACK_N && ~ZBUS_SEL && ~ZBUS_WE && ROM_REQ == ROM_ACK
                  && Z80_MBUS_DTACK_N && Z80_ZBUS_DTACK_N && MBUS_ZBUS_DTACK_N && ~Z80_IO;
wire ss_vcnt_1fe = vdp_ss_pos[21:13] == 9'h1FE;

assign SS_STATUS = ss_err ? 2'd3 : ss_st == SS_RUN ? 2'd0 :
                   (ss_st == SS_FROZEN && ss_cnt > 6 && ss_svp_ok) || ss_st == SS_WAIT ? 2'd2 : 2'd1;

always @(posedge MCLK) begin
	// pulses
	ss_vdp_snap <= 0; ss_vdp_rest <= 0; ss_dirset <= 0; ss_div_we <= 0; ss_nodata_we <= 0;
	ss_srwe <= 0; ss_miscwe <= 0; ss_grpwe <= 0; ss_clkwe <= 0;
	ss_svp_sh <= svp_mov;
	ss_svp_en <= ss_mem & svp_ss_quiet;

	ss_vint_d <= Z80_VINT;
	// the window, every frame: from the Z80's interrupt pulse's end to line 1FE
	if (ss_vint_d & ~Z80_VINT) ss_inwin <= 1;
	else if (ss_vcnt_1fe) ss_inwin <= 0;
	ss_vbl_d <= VBL;
	if (hard_reset) ss_frames <= 0;
	else if (VBL & ~ss_vbl_d) ss_frames <= ss_frames + 1'd1;

	// the YM2612's position at its slot 12, three clocks before the freeze
	if (ss_fmc) ss_fmc <= ss_fmc - 1'd1;
	else if (fm_ss_cen && fm_ss_slot == 5'b10000) ss_fmc <= 2'd2;

	// the sprite cache read while the sprite engines may use its port: let go
	// only after a frame the engines had to themselves
	ss_spr_d <= vdp_ss_spr;
	if (rd_busy && in_cache && vdp_ss_spr) begin ss_spr_bad <= 1; ss_spr_cur <= 1; end
	else begin
		if (vdp_ss_spr & ~ss_spr_d) ss_spr_cur <= 0;
		if (~vdp_ss_spr & ss_spr_d & ~ss_spr_cur) ss_spr_bad <= 0;
	end

	// the 68000's reset vectors: the last one read
	if (ss_vec && mstate == MBUS_SELECT && msrc == MSRC_M68K && !MBUS_A[23:3] && MBUS_A[2:1] == 3) ss_vec <= 0;

	// ---- the engine ----
	if (SS_RD && ss_st == SS_FROZEN && ss_cnt > 6) begin
		rd_busy <= 1; e_a <= SS_ADDR; e_cnt <= 0; ss_bram <= ss_a_sram;
		if (SS_ADDR >= 17'h180 && SS_ADDR < 17'h1A6 && {SS_ADDR[16:0] - 17'h180, 4'd0} != ch_pos) ss_err <= 1;
		if (SS_ADDR >= 17'h200 && SS_ADDR < 17'h320 && SS_ADDR - 17'h200 != ss_lpos) ss_err <= 1;
		if (ss_a_svpc && SS_ADDR[5:0] != svp_pos) ss_err <= 1;
	end
	else if (SS_WR && ss_st == SS_LOADING) begin
		wr_busy <= 1; e_a <= SS_ADDR; ss_wd <= SS_DI; e_cnt <= 0; ss_bram <= ss_a_sram;
		if (SS_ADDR >= 17'h180 && SS_ADDR < 17'h1A6 && {SS_ADDR[16:0] - 17'h180, 4'd0} != ch_pos) ss_err <= 1;
		if (SS_ADDR >= 17'h200 && SS_ADDR < 17'h320 && SS_ADDR - 17'h200 != ss_lpos) ss_err <= 1;
		if (ss_a_svpc && SS_ADDR[5:0] != svp_pos) ss_err <= 1;
	end
	else if (rd_busy | wr_busy) begin
		e_cnt <= e_cnt + 1'd1;
		if (e_cnt == SS_CLOCKS - 4) begin rd_busy <= 0; wr_busy <= 0; ss_bram <= 0; end
	end

	if (ss_fm_gsh) ch_pos <= ch_pos == 10'd602 ? 10'd0 : ch_pos + 1'd1;
	if (svp_mov) svp_pos <= svp_pos == 6'd62 ? 6'd0 : svp_pos + 1'd1;
	if (ss_fm_step) begin
		lp_step <= lp_step == 5'd23 ? 5'd0 : lp_step + 1'd1;
		if (lp_step == 5'd23) lp_lane <= lp_lane == 4'd11 ? 4'd0 : lp_lane + 1'd1;
	end

	if (rd_busy) begin
		if (e_cnt == 1) rd_tap <= fm_ss_tap;
		if (e_cnt == 4) rd_b0 <= zram_qb;
		if (in_chain && e_cnt >= 1 && e_cnt <= (last_chain ? 5'd11 : 5'd16)) rd_sh <= {rd_sh[14:0], fm_ss_go};
		if (e_cnt == 20) begin
			SS_DO <= 0;
			if (in_hdr) case (ea[4:0])
				0: SS_DO <= 16'h4750;                   // GPSS
				1: SS_DO <= 16'h5353;
				2: SS_DO <= SVP_QUIRK ? 16'h0002 : 16'h0001;   // the format's version
				3: SS_DO <= ss_flags;
				4: SS_DO <= SVP_QUIRK ? 16'h0004 : 16'h0003;   // its size, 0x44000 or 0x34000
				5: SS_DO <= 16'h4000;
				6: SS_DO <= {7'd0, ROMSZ[24:16]};       // the ROM's size in bytes (the serial and checksum are core_top.sv's)
				7: SS_DO <= {ROMSZ[15:1], 1'b0};
				16: SS_DO <= 16'h0006;                  // the core's version, 0.6.0
				18: SS_DO <= ss_frames[31:16];          // the frame since power-on
				19: SS_DO <= ss_frames[15:0];
				default: ;
			endcase
			if (in_con) case (o_con[4:0])
				0,1,2,3: SS_DO <= {3'd0, BANK_REG[{o_con[1:0], 1'b0}], 3'd0, BANK_REG[{o_con[1:0], 1'b1}]};
				4: SS_DO <= {12'd0, BANK_ROM, BANK_SRAM, Z80_BUSRQ_N, Z80_RESET_N};
				5: SS_DO <= {7'd0, BAR};
				6: SS_DO <= {10'd0, M68K_IPL_N, old_as, scnt};
				7: SS_DO <= NO_DATA;
				8: SS_DO <= {9'd0, ss_pos[22:16]};
				9: SS_DO <= ss_pos[15:0];
				10: SS_DO <= {VCLKCNT, ZCLKCNT, FCLKCNT, PCLKCNT};
				11: SS_DO <= {8'd0, VCLKMAX, VCLKMID};
				12: SS_DO <= {13'd0, i2c_read_map, i2c_scl, i2c_sda};
				13,14,15: SS_DO <= ss_i2c_q;
				16: SS_DO <= {5'd0, rfs_pend, refresh_timer};
				default: ;
			endcase
			if (in_68k) begin
				if (o_68k < 17'h22) SS_DO <= o_68k[0] ? fx_regq[15:0] : fx_regq[31:16];
				else case (o_68k[5:0])
					6'h22: SS_DO <= fx_pc[31:16];
					6'h23: SS_DO <= fx_pc[15:0];
					6'h24: SS_DO <= fx_sr;
					6'h25: SS_DO <= fx_misc;
					6'h26: SS_DO <= fx_grpdisp;
					6'h27: SS_DO <= fx_clk;
					6'h28: SS_DO <= {15'd0, ss_m68_stop};
					6'h29: SS_DO <= {6'd0, fx_uaddr};    // (to read, not loaded)
					default: ;
				endcase
			end
			if (in_z80) begin
				if (o_z80 < 17'd14) SS_DO <= z80_pad[(4'd13 - o_z80[3:0]) * 16 +: 16];
				else if (o_z80 == 17'd14) SS_DO <= z80_regx[15:0];
				else if (o_z80 == 17'd15) SS_DO <= {11'd0, ~Z80_BUSAK_N, z80_instend, z80_regx[18:16]};
			end
			if (in_vdpr | in_cram | in_vsram | in_cache) SS_DO <= vdp_ss_q;
			if (in_psg) SS_DO <= psg_ss_q;
			if (in_io) SS_DO <= io_ss_q;
			if (in_chain) SS_DO <= last_chain ? {rd_sh[10:0], 5'd0} : rd_sh;
			if (in_loops) SS_DO <= rd_tap;
			if (in_zram) SS_DO <= {rd_b0, zram_qb};
			if (in_ram68) SS_DO <= ram68k_qb;
			if (in_vram) SS_DO <= ss_vram_a[0] ? vram_q2 : vram_q1;
			if (in_sram) SS_DO <= {BRAM_DO[7:0], BRAM_DO[15:8]};
			if (in_svpc) SS_DO <= svp_ss_so;
			if (in_rama) SS_DO <= svp_ss_ra;
			if (in_ramb) SS_DO <= svp_ss_rb;
			if (in_iram) SS_DO <= svp_ss_ir;
		end
	end

	if (e_w0) begin
		if (in_con) case (o_con[4:0])
			7: st_nodata <= ss_wd;
			8: ss_pos[22:16] <= ss_wd[6:0];
			9: ss_pos[15:0] <= ss_wd;
			10: st_div[23:8] <= ss_wd;
			11: st_div[7:0] <= ss_wd[7:0];
			default: ;
		endcase
		if (in_68k) begin
			if (o_68k < 17'h22 && !o_68k[0]) st_reghi <= ss_wd;
			if (o_68k == 17'h21) ss_vec_sp <= {st_reghi, ss_wd};
			case (o_68k[5:0])
				6'h22: st_pc[31:16] <= ss_wd;
				6'h23: st_pc[15:0] <= ss_wd;
				6'h24: st_sr <= ss_wd;
				6'h25: st_misc <= ss_wd;
				6'h26: st_grpd <= ss_wd;
				6'h27: st_clk <= ss_wd;
				6'h28: ss_m68_stop <= ss_wd[0];
				default: ;
			endcase
		end
		if (in_z80) begin
			if (o_z80 < 17'd14) st_zpad[(4'd13 - o_z80[3:0]) * 16 +: 16] <= ss_wd;
			else if (o_z80 == 17'd14) ss_dirx[15:0] <= ss_wd;
			else if (o_z80 == 17'd15) ss_dirx[18:16] <= ss_wd[2:0];
		end
	end

	// ---- the save logic ----
	if (hard_reset) begin
		ss_st <= SS_RUN; ss_err <= 0;
		ss_freeze <= 0; ss_run68 <= 0; ss_park68 <= 0; ss_parkdisp68 <= 0; ss_rst68 <= 0;
		ss_zpark <= 0; ss_rstZ <= 0; ss_sysrst <= 0; ss_vdp_rst <= 0; ss_vdp_en <= 0; ss_fm_scan <= 0; ss_fm_load <= 0;
		ss_mem <= 0; ss_bram <= 0; ss_vec <= 0;
	end
	else case (ss_st)
	SS_RUN:
		if (SS_SAVE) begin
			ss_err <= 0;
			ss_st <= SS_SEEK; ss_tries <= 0; ss_win <= 0; ss_retry <= 0; ss_loaded <= 0;
		end
		else if (SS_LOAD) begin
			// a state is coming: the CPUs and the bus machines stopped, the VDP reset,
			// the YM2612 out of reset and frozen for its scan
			ss_err <= 0;
			ss_freeze <= 1; ss_rst68 <= 1; ss_rstZ <= 1; ss_vdp_rst <= 1; ss_sysrst <= 1; ss_fm_load <= 1;
			ss_cnt <= 0; ss_st <= SS_LSTOP;
		end

	SS_SEEK: begin
		// in the window (a save asked inside one starts there)
		if (ss_inwin & ~ss_vcnt_1fe) ss_win <= 1;
		if (ss_vcnt_1fe && ss_win) begin
			ss_win <= 0; ss_park68 <= 0; ss_zpark <= 0; ss_retry <= 0;
			ss_tries <= ss_tries + 1'd1;
			if (ss_tries == 8'd120) begin ss_err <= 1; ss_st <= SS_RUN; end   // 2 s
		end
		else if (ss_win) begin
			ss_zpark <= 1;
			// parked 64 us with no point: let the 68000 go for an instruction
			if (ss_ok68) ss_park_t <= ss_park_t + 1'd1; else ss_park_t <= 0;
			if (ss_park_t == 12'd3435) ss_retry <= 1;
			else if (ss_retry && !fx_atstart) ss_retry <= 0;
			ss_park68 <= ~ss_hold68 & ~ss_retry;
			// the freeze, at the YM2612's slot boundary halfway through its sample
			if (ss_fmc == 1 && ss_ok68 && ~ss_stopirq && ss_okZ && ss_okV && ss_okB) begin
				ss_freeze <= 1; ss_pos <= vdp_ss_pos; ss_vdp_snap <= 1; ss_vdp_en <= 1; ss_mem <= 1;
				ss_m68_stop <= fx_uaddr == SS_STOP_UA;
				ch_pos <= 0; lp_lane <= 0; lp_step <= 0; svp_pos <= 0;
				ss_cnt <= 0; ss_st <= SS_FROZEN;
			end
		end
	end

	SS_FROZEN: begin
		// readable; the YM2612 in its scan mode
		if (ss_cnt != 6'd63) ss_cnt <= ss_cnt + 1'd1;
		if (ss_cnt == 4) ss_fm_scan <= 1;
		if (SS_GO && !rd_busy && ss_cnt > 6) begin ss_st <= SS_UNSCAN; ss_cnt <= 0; end
	end

	SS_UNSCAN:
		if (!un_chain && !un_loop && !un_svp) begin
			ss_cnt <= ss_cnt + 1'd1;
			if (ss_cnt == 4) begin ss_vdp_en <= 0; ss_mem <= 0; ss_frame_seen <= ~ss_loaded; ss_st <= SS_WAIT; end
		end

	SS_WAIT:
		if (SS_SAVE) begin
			// a save before a load has let go: the state as it was written
			ss_vdp_en <= 1; ss_mem <= 1; ch_pos <= 0; lp_lane <= 0; lp_step <= 0; svp_pos <= 0; ss_cnt <= 0; ss_st <= SS_FROZEN;
		end
		else begin
			if (ss_vcnt_1fe) ss_frame_seen <= 1;
			if (ss_frame_seen && vdp_ss_pos == ss_pos && !ss_spr_bad) begin
				// let go: the drifting flags back, the clock enables and both parks
				// released in the one clock
				// (the YM2612 stays in its scan mode until now, so nothing in it
				// runs while it is frozen, its plain-clock parts included)
				ss_freeze <= 0; ss_park68 <= 0; ss_zpark <= 0; ss_vdp_rest <= 1;
				ss_fm_scan <= 0; ss_fm_load <= 0; ss_loaded <= 0; ss_st <= SS_RUN;
			end
		end

	SS_LSTOP: begin
		// the 68000's clock run in its reset a while, as a reset is, before its
		// registers are written: FX68K clears its bus cycle's latches only on
		// its clock enables, and its latched nanocode controls (left from the
		// microword the reset cut short) write a register on the first T3
		if (ss_cnt != 62 || ss_svp_ok) ss_cnt <= ss_cnt + 1'd1;   // (the SVP's fetch done: it has been reset, as the bus machines)
		if (ss_cnt == 2) ss_run68 <= 1;
		if (ss_cnt == 15) begin ss_vdp_rst <= 0; ss_sysrst <= 0; end
		if (ss_cnt == 20) begin ss_fm_scan <= 1; ss_vdp_en <= 1; ss_mem <= 1; end
		if (ss_cnt == 58) ss_run68 <= 0;
		if (ss_cnt == 62 && ss_svp_ok) begin ch_pos <= 0; lp_lane <= 0; lp_step <= 0; svp_pos <= 0; ss_st <= SS_LOADING; end
	end

	SS_LOADING:
		if (SS_GO && !wr_busy) begin
			if (ch_pos != 0 || lp_step != 0 || lp_lane != 0 || svp_pos != 0) ss_err <= 1;   // the YM2612's or the SVP's not all written
			ss_cnt <= 0; ss_st <= SS_RZ80;
		end

	SS_RZ80: begin
		// the Z80's registers in as it comes out of reset (frozen still)
		ss_cnt <= ss_cnt + 1'd1;
		if (ss_cnt == 0) begin ss_dirset <= 1; ss_rstZ <= 0; end
		if (ss_cnt == 4) begin ss_vdp_en <= 0; ss_mem <= 0; ss_run68 <= 1; end
		if (ss_cnt == 8) begin
			// the 68000 out of its reset, alone, to the dispatch the state was saved after
			ss_rst68 <= 0; ss_parkdisp68 <= 1; ss_vec <= 1;
			ss_vec_pc <= st_pc - (ss_m68_stop ? SS_STOP_PC : SS_START_PC);
			ss_wait_t <= 0; ss_st <= SS_R68_1;
		end
	end

	SS_R68_1: begin
		ss_wait_t <= ss_wait_t + 1'd1;
		if (fx_atdisp && !ss_vec) begin ss_run68 <= 0; ss_cnt <= 0; ss_st <= SS_R68_2; end
		else if (&ss_wait_t) begin ss_err <= 1; ss_st <= SS_R68_4; ss_cnt <= 0; end
	end

	SS_R68_2: begin
		// the decision its dispatch takes, and the SR
		ss_cnt <= ss_cnt + 1'd1;
		if (ss_cnt == 3) begin ss_grpwe <= 1; ss_grp_d <= st_grpd; ss_srwe <= 1; ss_sr_d <= st_sr; end
		if (ss_cnt == 5) begin
			ss_parkdisp68 <= 0; ss_park68 <= 1; ss_run68 <= 1; ss_retry <= 0;
			ss_wait_t <= 0; ss_st <= SS_R68_3;
		end
	end

	SS_R68_3: begin
		ss_wait_t <= ss_wait_t + 1'd1;
		// (in STOP, round its loop until the PC is the saved one)
		if (ss_retry) begin
			if (!fx_atstart) begin ss_retry <= 0; ss_park68 <= 1; end
		end
		else if (fx_atstart && fx_busidle && M68K_AS_N && ss_park68) begin
			if (fx_pc == st_pc) begin ss_run68 <= 0; ss_cnt <= 0; ss_st <= SS_R68_4; end
			else begin ss_retry <= 1; ss_park68 <= 0; end
		end
		if (&ss_wait_t) begin ss_err <= 1; ss_st <= SS_R68_4; ss_cnt <= 0; end
	end

	SS_R68_4: begin
		// parked at its boundary: what it holds there, the dividers, the open bus
		ss_cnt <= ss_cnt + 1'd1;
		if (ss_cnt == 3) begin
			ss_srwe <= 1; ss_sr_d <= st_sr; ss_miscwe <= 1; ss_misc_d <= st_misc;
			ss_grpwe <= 1; ss_grp_d <= {5'd0, st_misc[15:5]}; ss_clkwe <= 1; ss_clk_d <= st_clk;
			ss_div_we <= 1; ss_div_d <= st_div; ss_nodata_we <= 1; ss_nodata_d <= st_nodata;
		end
		if (ss_cnt == 5) begin ss_loaded <= 1; ss_frame_seen <= 0; ss_st <= SS_WAIT; end
	end

	default: ss_st <= SS_RUN;
	endcase
end

endmodule
