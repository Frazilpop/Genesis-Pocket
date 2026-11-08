// The save path end to end: a .sav from the bridge into the save RAM through
// data_loader and save_layout, then back out through data_unloader, as
// core_top wires them. tools/save-test.sh runs it on real saves.
`timescale 1ps/1ps
module tb;
  reg clk_74a = 0, clk_sys = 0;
  always #6734 clk_74a = ~clk_74a;   // 74.25 MHz
  always #9310 clk_sys = ~clk_sys;   // about 53.7 MHz

  reg        bridge_wr = 0, bridge_rd = 0;
  reg [31:0] bridge_addr = 0, bridge_wr_data = 0;
  wire [31:0] bridge_rd_data;

  reg        req = 0;
  reg [15:0] req_id = 0;
  reg [31:0] req_size = 0;

  wire        save_wr;
  wire [16:0] save_wr_addr, save_rd_addr;
  wire [15:0] save_wr_data, save_rd_data;
  wire        ram_we;
  wire [14:0] ram_addr;
  wire [15:0] ram_di;
  reg  [15:0] ram_do;

  data_loader #(.ADDRESS_MASK_UPPER_4(4'h6), .ADDRESS_SIZE(17), .WRITE_MEM_CLOCK_DELAY(7), .OUTPUT_WORD_SIZE(2)) ld (
    .clk_74a(clk_74a), .clk_memory(clk_sys), .bridge_wr(bridge_wr), .bridge_endian_little(1'b0),
    .bridge_addr(bridge_addr), .bridge_wr_data(bridge_wr_data),
    .write_en(save_wr), .write_addr(save_wr_addr), .write_data(save_wr_data));

  data_unloader #(.ADDRESS_MASK_UPPER_4(4'h6), .ADDRESS_SIZE(17), .READ_MEM_CLOCK_DELAY(7), .INPUT_WORD_SIZE(2)) un (
    .clk_74a(clk_74a), .clk_memory(clk_sys), .bridge_rd(bridge_rd), .bridge_endian_little(1'b0),
    .bridge_addr(bridge_addr), .bridge_rd_data(bridge_rd_data),
    .read_en(), .read_addr(save_rd_addr), .read_data(save_rd_data));

  save_layout sl (
    .clk_74a(clk_74a), .clk_sys(clk_sys),
    .dataslot_requestwrite(req), .dataslot_requestwrite_id(req_id), .dataslot_requestwrite_size(req_size),
    .wr(save_wr), .wr_addr(save_wr_addr), .wr_data(save_wr_data),
    .rd_addr(save_rd_addr), .rd_data(save_rd_data),
    .ram_we(ram_we), .ram_addr(ram_addr), .ram_di(ram_di), .ram_do(ram_do));

  // system.sv's RAM, port B: cleared to FF as a game loads
  reg [15:0] ram [0:32767];
  always @(posedge clk_sys) begin
    if (ram_we) ram[ram_addr] <= ram_di;
    ram_do <= ram[ram_addr];
  end

  reg [7:0] file_in [0:131071];
  integer size, i, fd;
  string in_path, out_path, ram_path;

  task automatic tick74(input integer n); repeat (n) @(posedge clk_74a); endtask

  initial begin
    if (!$value$plusargs("in=%s", in_path) || !$value$plusargs("size=%d", size) ||
        !$value$plusargs("out=%s", out_path) || !$value$plusargs("ram=%s", ram_path)) begin
      $display("usage: +in=hex +size=bytes +out=hex +ram=hex"); $finish;
    end
    for (i = 0; i < 32768; i++) ram[i] = 16'hFFFF;
    $readmemh(in_path, file_in, 0, size - 1);
    tick74(20);

    // 0x0082 for the save slot, then the file a 32-bit word at a time
    req_id = 16'd10; req_size = size; req = 1; tick74(4); req = 0;
    tick74(20);
    for (i = 0; i < size; i += 4) begin
      bridge_addr = 32'h60000000 + i;
      bridge_wr_data = {file_in[i], file_in[i+1], file_in[i+2], file_in[i+3]};
      bridge_wr = 1; tick74(1); bridge_wr = 0; tick74(40);
      if (i % 16384 == 0) $display("load %0d of %0d", i, size);
    end
    tick74(100);

    fd = $fopen(ram_path, "w");
    for (i = 0; i < 32768; i++) $fwrite(fd, "%02x\n%02x\n", ram[i][7:0], ram[i][15:8]);
    $fclose(fd);

    // the Pocket reads the 128 KB the data table says back
    fd = $fopen(out_path, "w");
    for (i = 0; i < 131072; i += 4) begin
      bridge_addr = 32'h60000000 + i;
      bridge_rd = 1; tick74(1); bridge_rd = 0; tick74(60);
      $fwrite(fd, "%02x\n%02x\n%02x\n%02x\n", bridge_rd_data[31:24], bridge_rd_data[23:16], bridge_rd_data[15:8], bridge_rd_data[7:0]);
      if (i % 16384 == 0) $display("unload %0d of 131072", i);
    end
    $fclose(fd);
    $finish;
  end
endmodule
