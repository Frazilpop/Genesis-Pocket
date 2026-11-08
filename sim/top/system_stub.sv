// The console, as core_top.sv sees it: every input noted in the bench's hashes and
// watched by its checks, and a little of what the real one does at each port: a
// picture, sound, the ROM's readers, the save RAM, the state window. It answers only
// from what it is given and its own clock, so two core_top.sv's that drive it the same
// see the same. The whole console is sim/top's --console.
`timescale 1ps/1ps
module system (
    input         RESET_N, MCLK,
    input   [1:0] LPF_MODE,
    input         ENABLE_FM, ENABLE_PSG,
    output reg [15:0] DAC_LDATA = 0, DAC_RDATA = 0,
    input         LOADING, PAL, PAL_SAYS, EXPORT, FAST_FIFO, SRAM00_QUIRK,
    input   [2:0] EEPROM_MAP, EEPROM_CHIP,
    input         NORAM_QUIRK, PIER_QUIRK, SVP_QUIRK, FMBUSY_QUIRK, SCHAN_QUIRK,
    input   [1:0] TURBO,
    input  [14:0] BRAM_A,
    input  [15:0] BRAM_DI,
    output reg [15:0] BRAM_DO = 0,
    input         BRAM_WE,
    output        BRAM_CHANGE,
    output  [3:0] RED, GREEN, BLUE,
    output        VS, HS, HBL, VBL,
    output        CE_PIX,
    input         BORDER, CRAM_DOTS,
    output        INTERLACE, FIELD,
    output  [1:0] RESOLUTION,
    input         J3BUT,
    input  [11:0] JOY_1, JOY_2, JOY_3, JOY_4,
    input   [2:0] MULTITAP,
    input         GUN_OPT, GUN_TYPE, GUN_SENSOR, GUN_A, GUN_B, GUN_C, GUN_START,
    input  [24:1] ROMSZ,
    output reg [24:1] ROM_ADDR = 0,
    input  [15:0] ROM_DATA,
    output reg [15:0] ROM_WDATA = 0,
    output reg    ROM_WE = 0,
    output reg  [1:0] ROM_BE = 0,
    output reg    ROM_REQ = 0,
    input         ROM_ACK,
    output reg [24:1] ROM_ADDR2 = 0,
    input  [15:0] ROM_DATA2,
    output reg    ROM_REQ2 = 0,
    input         ROM_ACK2,
    input         EN_HIFI_PCM, LADDER, OBJ_LIMIT_HIGH,
    output        TRANSP_DETECT,
    input         PAUSE_EN, BGA_EN, BGB_EN, SPR_EN,
    input         SS_SAVE, SS_LOAD, SS_GO,
    output reg  [1:0] SS_STATUS = 0,
    input  [17:0] SS_ADDR,
    input         SS_RD,
    output reg [15:0] SS_DO = 0,
    input         SS_WR,
    input  [15:0] SS_DI
);
    assign BRAM_CHANGE = 0;

    // ---- what the bench watches, as one word for the hash and by name for the checks ----
    // (not ROMSZ in the hash: it follows the data table some clocks after the Pocket fills it
    // in, long before anything reads it, and the bench checks it by name once a game is in)
    wire [420:0] seen = {RESET_N, LPF_MODE, ENABLE_FM, ENABLE_PSG, LOADING, PAL, EXPORT, FAST_FIFO, SRAM00_QUIRK,
        EEPROM_MAP, EEPROM_CHIP, NORAM_QUIRK, PIER_QUIRK, SVP_QUIRK, FMBUSY_QUIRK, SCHAN_QUIRK, TURBO,
        BRAM_A, BRAM_DI, BRAM_WE, BORDER, CRAM_DOTS, J3BUT, JOY_1, JOY_2, JOY_3, JOY_4, MULTITAP,
        GUN_OPT, GUN_TYPE, GUN_SENSOR, GUN_A, GUN_B, GUN_C, GUN_START, ROM_DATA, ROM_ACK, ROM_DATA2, ROM_ACK2,
        EN_HIFI_PCM, LADDER, OBJ_LIMIT_HIGH, PAUSE_EN, BGA_EN, BGB_EN, SPR_EN, SS_SAVE, SS_LOAD, SS_GO,
        SS_ADDR, SS_RD, SS_WR, SS_DI};
    always @(posedge MCLK) tb.note(0, seen);

    always @* begin
        tb.s.reset_n = RESET_N; tb.s.lpf = LPF_MODE; tb.s.fm = ENABLE_FM; tb.s.psg = ENABLE_PSG;
        tb.s.loading = LOADING; tb.s.pal = PAL; tb.s.pal_says = PAL_SAYS; tb.s.export_ = EXPORT; tb.s.fifo = FAST_FIFO;
        tb.s.sram00 = SRAM00_QUIRK; tb.s.emap = EEPROM_MAP; tb.s.echip = EEPROM_CHIP;
        tb.s.noram = NORAM_QUIRK; tb.s.pier = PIER_QUIRK; tb.s.svp = SVP_QUIRK; tb.s.fmbusy = FMBUSY_QUIRK; tb.s.schan = SCHAN_QUIRK;
        tb.s.turbo = TURBO; tb.s.j3 = J3BUT; tb.s.joy1 = JOY_1; tb.s.joy2 = JOY_2; tb.s.joy3 = JOY_3; tb.s.joy4 = JOY_4;
        tb.s.multitap = MULTITAP; tb.s.gun = GUN_OPT; tb.s.guntype = GUN_TYPE; tb.s.romsz = ROMSZ;
        tb.s.hifi = EN_HIFI_PCM; tb.s.ladder = LADDER; tb.s.sprites = OBJ_LIMIT_HIGH; tb.s.pause = PAUSE_EN;
    end

    // ---- a picture: a short frame, a colour for each pixel ----
    localparam LINES = 24, VISIBLE = 20;
    reg [3:0] div = 0;
    reg [8:0] hc = 0;
    reg [7:0] vc = 0;
    reg [7:0] frame = 0;
    assign RESOLUTION = tb.video_mode;
    assign INTERLACE = tb.interlaced;
    assign FIELD = tb.interlaced & frame[0];
    assign TRANSP_DETECT = tb.transparent;
    wire [8:0] width = RESOLUTION[0] ? 9'd320 : 9'd256;
    assign CE_PIX = div == 0;
    assign HBL = hc >= width;
    assign VBL = vc >= VISIBLE;
    assign HS = hc >= 9'd330;
    assign VS = vc >= VISIBLE + 2;
    assign RED   = hc[3:0] ^ frame[3:0];
    assign GREEN = hc[7:4] ^ vc[3:0];
    assign BLUE  = vc[3:0] ^ hc[4:1];
    always @(posedge MCLK) begin
        div <= div == (RESOLUTION[0] ? 4'd7 : 4'd9) ? 4'd0 : div + 1'd1;
        if (CE_PIX) begin
            hc <= hc + 1'd1;
            if (hc == 9'd341) begin
                hc <= 0;
                vc <= vc + 1'd1;
                if (vc == LINES - 1) begin vc <= 0; frame <= frame + 1'd1; end
            end
        end
    end

    // ---- sound ----
    reg [9:0] sc = 0;
    always @(posedge MCLK) begin
        sc <= sc + 1'd1;
        if (&sc) begin DAC_LDATA <= DAC_LDATA + 16'h0137; DAC_RDATA <= DAC_RDATA - 16'h0259; end
    end

    // ---- the ROM's readers: each word read in turn, once a game is in ----
    reg       rom_wait = 0, rom2_wait = 0;
    reg [7:0] rom_gap = 0;
    wire      run = RESET_N & ~LOADING & tb.rom_readers;
    always @(posedge MCLK) begin
        rom_gap <= rom_gap + 1'd1;
        if (rom_wait && ROM_ACK == ROM_REQ) begin
            rom_wait <= 0;
            tb.rom_word(ROM_ADDR, ROM_DATA, 0);
            ROM_ADDR <= tb.rom_next(ROM_ADDR);
            ROM_WE <= 0;
        end
        else if (!rom_wait && run && rom_gap == 8'd0) begin
            ROM_REQ <= ~ROM_REQ;
            rom_wait <= 1;
        end
        if (rom2_wait && ROM_ACK2 == ROM_REQ2) begin
            rom2_wait <= 0;
            tb.rom_word(ROM_ADDR2, ROM_DATA2, 1);
            ROM_ADDR2 <= tb.rom_next(ROM_ADDR2 + 7'd97);
        end
        else if (!rom2_wait && run && rom_gap == 8'd128) begin
            ROM_REQ2 <= ~ROM_REQ2;
            rom2_wait <= 1;
        end
    end

    // ---- the save RAM's port B, and what a game wrote through port A ----
    reg [15:0] bram [0:32767];
    initial for (int i = 0; i < 32768; i++) bram[i] = 16'hFFFF;
    always @(posedge MCLK) begin
        if (BRAM_WE) bram[BRAM_A] <= BRAM_DI;
        BRAM_DO <= bram[BRAM_A];
    end

    // ---- the state window ----
    reg [15:0] state_mem [0:262143];
    reg  [9:0] ss_t = 0;
    reg  [1:0] ss_what = 0;     // 1 a save, 2 a load being written, 3 a load let go
    always @(posedge MCLK) begin
        if (ss_t != 0) ss_t <= ss_t - 1'd1;
        if (SS_SAVE) begin SS_STATUS <= 1; ss_what <= 1; ss_t <= 10'd300; end
        if (SS_LOAD) begin SS_STATUS <= 1; ss_what <= 2; end
        if (SS_GO) begin
            if (ss_what == 1) begin SS_STATUS <= 0; ss_what <= 0; end
            if (ss_what == 2) begin ss_what <= 3; ss_t <= 10'd400; end
        end
        if (ss_what == 1 && ss_t == 1) SS_STATUS <= 2;
        if (ss_what == 3 && ss_t == 200) SS_STATUS <= 2;
        if (ss_what == 3 && ss_t == 1) begin SS_STATUS <= 0; ss_what <= 0; end
        tb.console_loading <= ss_what == 2 && !SS_GO;
        if (SS_RD) begin
            // the format's header, as the real one's save logic gives it
            case (SS_ADDR)
                18'd0:   SS_DO <= 16'h4750;
                18'd1:   SS_DO <= 16'h5353;
                18'd2:   SS_DO <= SVP_QUIRK ? 16'h0002 : 16'h0001;
                18'd3:   SS_DO <= {15'd0, PAL};
                18'd4:   SS_DO <= SVP_QUIRK ? 16'h0004 : 16'h0003;
                18'd5:   SS_DO <= 16'h4000;
                18'd6:   SS_DO <= {7'd0, ROMSZ[24:16]};
                18'd7:   SS_DO <= {ROMSZ[15:1], 1'b0};
                default: SS_DO <= SS_ADDR[15:0] ^ {SS_ADDR[7:0], SS_ADDR[15:8]};
            endcase
        end
        if (SS_WR) begin state_mem[SS_ADDR] <= SS_DI; tb.state_written <= tb.state_written + 1; end
    end
endmodule
