// core_top.sv's quirks table and pad layouts on their own (tools/quirk-test.sh,
// which cuts both out of core_top.sv into block.inc and writes cases.inc from the
// table). A game's whole load goes in as the loader gives it, with cart_download
// dropping part way as bridge_addr leaves the ROM; when it is over, that game's
// quirk must be on and no other, and it stays on until another game's header.
module tb;
  reg clk_sys = 0, cart_download = 0, ioctl_wr = 0;
  reg [24:0] ioctl_addr = 0;
  reg [15:0] ioctl_data = 0;
  reg [31:0] cont1_key_s = 0, cont2_key_s = 0, cont3_key_s = 0, cont4_key_s = 0;
  integer bad = 0, runs = 0;

  `include "block.inc"

  always #5 clk_sys = ~clk_sys;

  function automatic string on();
    on = "";
    if (fifo_quirk)   on = {on, " fifo"};
    if (eeprom_map)   on = {on, $sformatf(" eeprom %0d:%0d", eeprom_map, eeprom_chip)};
    if (sram00_quirk) on = {on, " sram00"};
    if (noram_quirk)  on = {on, " noram"};
    if (pier_quirk)   on = {on, " pier"};
    if (svp_quirk)    on = {on, " svp"};
    if (fmbusy_quirk) on = {on, " fmbusy"};
    if (schan_quirk)  on = {on, " schan"};
  endfunction

  // the first 0x400 bytes of a ROM with this serial at 0x183, then more words
  // (and the header's save memory: 'RA', its byte, its first and last; a stack
  // pointer and a checksum, which is all two of Codemasters' have for a serial)
  task automatic load(input string serial, input int kind = -1, input int first = 0, input int last = 0,
                      input int sp = 'h20202020, input int checksum = 'h2020);
    reg [7:0] b[0:1023];
    for (int i = 0; i < 1024; i++) b[i] = 8'h20;
    for (int i = 0; i < 8; i++) b['h183 + i] = serial[i];
    for (int i = 0; i < 4; i++) b[i] = sp[(3 - i) * 8 +: 8];
    b['h18E] = checksum[15:8]; b['h18F] = checksum[7:0];
    if (kind >= 0) begin
      b['h1B0] = "R"; b['h1B1] = "A"; b['h1B2] = kind[7:0]; b['h1B3] = 8'h40;
      for (int i = 0; i < 4; i++) begin
        b['h1B4 + i] = first[(3 - i) * 8 +: 8];
        b['h1B8 + i] = last[(3 - i) * 8 +: 8];
      end
    end
    @(negedge clk_sys); cart_download = 1; repeat (4) @(negedge clk_sys);
    for (int a = 0; a < 1024; a += 2) begin
      ioctl_addr = a; ioctl_data = {b[a + 1], b[a]}; ioctl_wr = 1;
      @(negedge clk_sys); ioctl_wr = 0;
      repeat (3) @(negedge clk_sys);
      if (a == 'h100 || a == 'h300) begin   // the bridge elsewhere for a moment
        cart_download = 0; repeat (6) @(negedge clk_sys);
        cart_download = 1; repeat (6) @(negedge clk_sys);
      end
    end
    cart_download = 0; repeat (6) @(negedge clk_sys);
  endtask

  task automatic expect_game(input string serial, input string want);
    load(serial);
    runs++;
    if (on() != want) begin
      bad++;
      $display("FAILED %s: wanted [%s], got [%s]", serial, want, on());
    end
  endtask

  task automatic expect_header(input string what, input string serial, input int kind, first, last, input string want,
                               input int sp = 'h20202020, input int checksum = 'h2020);
    load(serial, kind, first, last, sp, checksum);
    runs++;
    if (on() != want) begin
      bad++;
      $display("FAILED %s: wanted [%s], got [%s]", what, want, on());
    end
  endtask

  // the Pocket's own layout (input.json): which key bit gives Z, Y, X, B, C, A
  function automatic [5:0] pad(input [2:0] l, input [31:0] k); pad = face_buttons(k); endfunction
  task automatic expect_pad(input [2:0] l, input int z, y, x, b, c, a);
    int want[6] = '{a, c, b, x, y, z};
    for (int i = 0; i < 6; i++) begin
      runs++;
      if (pad(l, 32'd1 << want[i]) != 6'd1 << i
          || (pad(l, ~(32'd1 << want[i])) & (6'd1 << i)) != 0) begin
        bad++;
        $display("FAILED layout %0d, button %0d: key %0d does not drive it alone", l, i, want[i]);
      end
    end
  endtask

  initial begin
    `include "cases.inc"
    expect_game("T-000000", "");
    expect_header("Wily Wars as sold", "T-12046 ", 'hE8, 'h200001, 'h200001, " eeprom 1:0");
    expect_header("a Wily Wars hacked to a save RAM", "T-12046 ", 'hF8, 'h200001, 'h203FFF, "");
    expect_header("a Wonder Boy hacked to a save RAM", "G-4060  ", 'hF8, 'h200001, 'h203FFF, "");
    expect_header("a Rockman hacked to a save RAM", "T-12053 ", 'hF8, 'h200001, 'h203FFF, "");
    expect_header("a chip's byte, not in the table", "T-000000", 'hE8, 'h200001, 'h200FFF, " eeprom 1:0");
    expect_header("a chip's short range, not in the table", "T-000000", 'hF8, 'h200001, 'h200001, " eeprom 1:0");
    expect_header("an ordinary save RAM", "MK-1583 ", 'hF8, 'h200001, 'h200FFF, "");
    expect_header("Sonic Classic Heroes's", "00001051", 'hF8, 'h200000, 'h2001FF, "");
    expect_header("Pier Solar's own chip", "T-574023", 'hE8, 'h200001, 'h200001, " pier");
    expect_header("Micro Machines Military", "00000000", -1, 0, 0, " eeprom 5:4", 'h444E4C44, 'h168B);
    expect_header("Micro Machines 96", "00000000", -1, 0, 0, " eeprom 5:5", 'h444E4C44, 'h165E);
    expect_header("Super Skidmarks: the checksum, not the stack", "00000000", -1, 0, 0, "", 'hFFFFFFFC, 'h168B);
    expect_header("a chip game's after another's", "T-000000", -1, 0, 0, "");
    expect_pad(0,  9, 6, 8,  4, 5,  7);
    $display("%0d of %0d good", runs - bad, runs);
    if (bad != 0) $fatal(1, "quirks: %0d failed", bad);
    $finish;
  end
endmodule
