// The YM2612's scan, proved on jt12 alone:
// three copies of MiSTer's jt12 (rtl/jt12) side by side, each with its own
// inputs, driven by main.cpp. tools/jt12-scan-test.sh builds and runs it.
module bench(
  input         clk,
  input  [ 2:0] rst,
  input  [ 2:0] cen,
  input  [ 2:0] wr_n,
  input  [ 5:0] addr,
  input  [23:0] din,
  input  [ 2:0] ss_scan,
  input  [ 2:0] ss_step,
  input  [11:0] ss_lane,
  input  [ 2:0] ss_load,
  input  [47:0] ss_wd,
  input  [ 2:0] ss_gsh,
  input  [ 2:0] ss_gi,
  output [47:0] ss_tap,
  output [ 2:0] ss_go,
  output [47:0] snd_left,
  output [47:0] snd_right,
  output [ 2:0] snd_sample,
  output [23:0] dout,
  output [ 2:0] irq_n,
  // what the bench looks at inside: the slot, the clock enable as the chip
  // takes it, and its prescaler's (quiet between FM clock enables)
  output [14:0] slot,
  output [ 2:0] clk_en,
  output [ 2:0] pre_clk_en
);
  genvar i;
  generate
    for (i = 0; i < 3; i = i + 1) begin : fm
      jt12 u (
        .rst(rst[i]), .clk(clk), .cen(cen[i]),
        .din(din[i*8 +: 8]), .addr(addr[i*2 +: 2]), .cs_n(1'b0), .wr_n(wr_n[i]),
        .dout(dout[i*8 +: 8]), .irq_n(irq_n[i]),
        // as the core sets them by default (core_top.sv): the interpolated
        // DAC on, so its state is in play, and the ladder effect
        .en_hifi_pcm(1'b1), .ladder(1'b1),
        .snd_right(snd_right[i*16 +: 16]), .snd_left(snd_left[i*16 +: 16]), .snd_sample(snd_sample[i]),
        .ss_scan(ss_scan[i]), .ss_step(ss_step[i]), .ss_lane(ss_lane[i*4 +: 4]), .ss_load(ss_load[i]),
        .ss_wd(ss_wd[i*16 +: 16]), .ss_tap(ss_tap[i*16 +: 16]),
        .ss_gsh(ss_gsh[i]), .ss_gi(ss_gi[i]), .ss_go(ss_go[i])
      );
      assign slot[i*5 +: 5]  = { u.u_jt12.u_mmr.u_reg.cur_op, u.u_jt12.u_mmr.u_reg.cur_ch };
      assign clk_en[i]       = u.u_jt12.clk_en;
      assign pre_clk_en[i]   = u.u_jt12.u_mmr.u_div.pre_clk_en;
    end
  endgenerate
endmodule
