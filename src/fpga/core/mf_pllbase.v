// mf_pllbase.v
//
// One fractional PLL off clk_74a whose fraction is changed for PAL (pal_clock.sv),
// so every clock moves together. Intel's generator, with no wizard's file to go back to:
//   ip-generate --component-name=altera_pll --file-set=QUARTUS_SYNTH
//     --system-info=DEVICE_FAMILY="Cyclone V" --system-info=DEVICE=5CEBA4F23C8
//     --component-param=gui_pll_mode="Fractional-N PLL" gui_en_reconf=true
//     gui_reference_clock_frequency=74.25 gui_operation_mode=direct
//     gui_fractional_cout=32 gui_dsm_out_sel=1st_order gui_use_locked=true
//     gui_number_of_clocks=6 and each clock as mf_pllbase_0002.v has it
// (the K it wrote, 2910627320, is 53.693165 MHz; 2910634261 is 53.693175).

`timescale 1 ps / 1 ps
module mf_pllbase (
		input  wire        refclk,            //  refclk.clk
		input  wire        rst,               //   reset.reset
		output wire        outclk_0,          // outclk0.clk
		output wire        outclk_1,          // outclk1.clk
		output wire        outclk_2,          // outclk2.clk
		output wire        outclk_3,          // outclk3.clk
		output wire        outclk_4,          // outclk4.clk
		output wire        outclk_5,          // outclk5.clk
		output wire        locked,            //  locked.export
		input  wire [63:0] reconfig_to_pll,
		output wire [63:0] reconfig_from_pll
	);

	mf_pllbase_0002 mf_pllbase_inst (
		.refclk            (refclk),
		.rst               (rst),
		.outclk_0          (outclk_0),
		.outclk_1          (outclk_1),
		.outclk_2          (outclk_2),
		.outclk_3          (outclk_3),
		.outclk_4          (outclk_4),
		.outclk_5          (outclk_5),
		.locked            (locked),
		.reconfig_to_pll   (reconfig_to_pll),
		.reconfig_from_pll (reconfig_from_pll)
	);

endmodule
