// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Ibex simple system
 *
 * This is a basic system consisting of an ibex, a 1 MB sram for instruction/data
 * and a small memory mapped control module for outputting ASCII text and
 * controlling/halting the simulation from the software running on the ibex.
 *
 * It is designed to be used with verilator but should work with other
 * simulators, a small amount of work may be required to support the
 * simulator_ctrl module.
 */

module display_ibex_sim (
  input IO_CLK,
  input IO_RST_N
);
  logic       hdmi_tx_de;
  logic       hdmi_tx_hs;
  logic       hdmi_tx_vs;
  logic [7:0] hdmi_tx_r;
  logic [7:0] hdmi_tx_g;
  logic [7:0] hdmi_tx_b;

  int display_dump_file;
  int frame;

  initial begin
    display_dump_file = $fopen("display.out", "w");
    frame = 0;
    $fdisplay(display_dump_file, "Frame: %d", frame);
  end

  always @(posedge IO_CLK) begin
    if(hdmi_tx_de) begin
      $fdisplay(display_dump_file, "%08x%08x%08x", hdmi_tx_r, hdmi_tx_g, hdmi_tx_b);
    end
  end

  logic prev_display_vs;

  always @(posedge IO_CLK) begin
    prev_display_vs <= hdmi_tx_vs;

    if(prev_display_vs & ~hdmi_tx_vs) begin
      $fdisplay(display_dump_file, "Frame: %d", frame + 1);
      frame <= frame + 1;
    end
  end

  display_ibex_top display_ibex_top_i (
    .clk_sys_i    ( IO_CLK     ),
    .rst_sys_ni   ( IO_RST_N   ),

    .clk_hdmi_i   ( IO_CLK     ),
    .rst_hdmi_ni  ( IO_RST_N   ),

    .hdmi_tx_de_o ( hdmi_tx_de ),
    .hdmi_tx_hs_o ( hdmi_tx_hs ),
    .hdmi_tx_vs_o ( hdmi_tx_vs ),
    .hdmi_tx_r_o  ( hdmi_tx_r  ),
    .hdmi_tx_g_o  ( hdmi_tx_g  ),
    .hdmi_tx_b_o  ( hdmi_tx_b  )
  );
endmodule
