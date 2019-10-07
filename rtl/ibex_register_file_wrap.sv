// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Ibex register file wrapper
 *
 * This wraps the actual register file instantiation. It muxes between RF writes from writeback and
 * LSU and provides a forwarding path when the Writeback pipeline stage is in use
 */
module ibex_register_file_wrap #(
    parameter bit RV32E              = 0,
    parameter bit WritebackStage     = 0,
    parameter int unsigned DataWidth = 32
) (
    // Clock and Reset
    input  logic                 clk_i,
    input  logic                 rst_ni,

    input  logic                 test_en_i,

    //Read port R1
    input  logic [4:0]           raddr_a_i,
    output logic [DataWidth-1:0] rdata_a_o,

    //Read port R2
    input  logic [4:0]           raddr_b_i,
    output logic [DataWidth-1:0] rdata_b_o,

    // Write port W1
    input  logic [4:0]           waddr_i,
    input  logic [DataWidth-1:0] wdata_wb_i,
    input  logic [DataWidth-1:0] wdata_lsu_i,
    input  logic                 we_wb_i,
    input  logic                 we_lsu_i
);
  logic [DataWidth-1:0] rdata_a_raw;
  logic [DataWidth-1:0] rdata_b_raw;
  logic [DataWidth-1:0] wdata;
  logic                 we;

  if(WritebackStage) begin
    // When the Writeback stage is present the register that ID wants to read may only just be being
    // written. Check to see if either read port wants the data in writeback and forward it
    // appropriately. Read from zero register always returns raw data (which will be 0 ) and
    // doesn't forward.
    assign rdata_a_o = (raddr_a_i == waddr_i) & |raddr_a_i & we_wb_i ? wdata_wb_i : rdata_a_raw;
    assign rdata_b_o = (raddr_b_i == waddr_i) & |raddr_b_i & we_wb_i ? wdata_wb_i : rdata_b_raw;
  end else begin
    // When no writeback stage is present no forwarding paths are required.
    assign rdata_a_o = rdata_a_raw;
    assign rdata_b_o = rdata_b_raw;
  end

  // RF write data can come from Writeback (all RF writes that aren't because of loads will come
  // from here) or the LSU (RF writes for load data). They are muxed here to allow only the
  // Writeback data to be used on the forwarding paths. The write data from the LSU is too late to
  // use on the forwarding path without effecting timing.
  assign we    = we_wb_i | we_lsu_i;
  assign wdata = we_wb_i ? wdata_wb_i : wdata_lsu_i;

  ibex_register_file #(
      .RV32E(RV32E),
      .DataWidth(DataWidth)
  ) register_file_i (
      .clk_i        ( clk_i       ),
      .rst_ni       ( rst_ni      ),

      .test_en_i    ( test_en_i   ),

      .raddr_a_i    ( raddr_a_i   ),
      .rdata_a_o    ( rdata_a_raw ),

      .raddr_b_i    ( raddr_b_i   ),
      .rdata_b_o    ( rdata_b_raw ),

      .waddr_a_i    ( waddr_i     ),
      .wdata_a_i    ( wdata       ),
      .we_a_i       ( we          )
  );
endmodule
