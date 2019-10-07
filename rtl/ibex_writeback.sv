// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Writeback Stage
 *
 * Writeback is an optional third pipeline stage. It writes data back to the register file that was
 * produced in the ID/EX stage or awaits a response to a load/store (LSU writes direct to register
 * file for load data). If the writeback stage is not present (WritebackStage == 0) this acts as
 * a simple passthrough to write data direct to the register file.
 */
module ibex_writeback #(
  parameter bit WritebackStage = 1'b0
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,

  input  logic                     en_wb_i,
  input  ibex_pkg::wb_instr_type_e instr_type_wb_i,
  input  logic [31:0]              pc_id_i,

  output logic                     ready_wb_o,
  output logic                     rf_write_wb_o,
  output logic                     outstanding_load_wb_o,
  output logic                     outstanding_store_wb_o,
  output logic [31:0]              pc_wb_o,

  input  logic [4:0]               rf_waddr_id_i,
  input  logic [31:0]              rf_wdata_id_i,
  input  logic                     rf_we_id_i,

  output logic [4:0]               rf_waddr_wb_o,
  output logic [31:0]              rf_wdata_wb_o,
  output logic                     rf_we_wb_o,

  input logic                      lsu_data_valid_i,

  output logic                     instr_done_wb_o
);

  import ibex_pkg::*;

  if(WritebackStage) begin : g_writeback_stage
    logic [31:0]    rf_wdata_wb_q;
    logic [31:0]    rf_we_wb_q;
    logic [4:0]     rf_waddr_wb_q;

    logic           wb_done;

    logic           wb_valid_q;
    logic [31:0]    wb_pc_q;
    wb_instr_type_e wb_instr_type_q;

    logic           wb_valid_d;

    // Stage becomes valid if an instruction enters for ID/EX and valid is cleared when instruction
    // is done
    assign wb_valid_d = (en_wb_i & ready_wb_o) | (wb_valid_q & ~wb_done);

    // Writeback for non load/store instructions always completes in a cycle (so instantly done)
    // Writeback for load/store must wait for response to be received by the LSU
    // Signal only relevant if wb_valid_q set
    assign wb_done = (wb_instr_type_q == WB_INSTR_OTHER) | lsu_data_valid_i;


    always_ff @(posedge clk_i or negedge rst_ni) begin
      if(~rst_ni) begin
        wb_valid_q <= 1'b0;
      end else begin
        wb_valid_q <= wb_valid_d;
      end
    end

    always_ff @(posedge clk_i) begin
      if(en_wb_i) begin
        rf_we_wb_q      <= rf_we_id_i;
        rf_waddr_wb_q   <= rf_waddr_id_i;
        rf_wdata_wb_q   <= rf_wdata_id_i;
        wb_instr_type_q <= instr_type_wb_i;
        wb_pc_q         <= pc_id_i;
      end
    end

    assign rf_waddr_wb_o = rf_waddr_wb_q;
    assign rf_wdata_wb_o = rf_wdata_wb_q;
    assign rf_we_wb_o    = rf_we_wb_q & wb_valid_q;

    assign ready_wb_o = ~wb_valid_q | wb_done;

    // Instruction in writeback will be writing to register file if either rf_we is set or writeback
    // is awaiting load data. This is used for determining RF read hazards in ID/EX
    assign rf_write_wb_o = wb_valid_q & (rf_we_wb_q | (wb_instr_type_q == WB_INSTR_LOAD));

    assign outstanding_load_wb_o  = wb_valid_q & (wb_instr_type_q == WB_INSTR_LOAD);
    assign outstanding_store_wb_o = wb_valid_q & (wb_instr_type_q == WB_INSTR_STORE);

    assign pc_wb_o = wb_pc_q;

    assign instr_done_wb_o = wb_valid_q & wb_done;
  end else begin
    // without writeback stage just pass through register write signals
    assign rf_waddr_wb_o = rf_waddr_id_i;
    assign rf_wdata_wb_o = rf_wdata_id_i;
    assign rf_we_wb_o    = rf_we_id_i;

    // ready needs to be constant 1 without writeback stage (otherwise ID/EX stage will stall)
    assign ready_wb_o    = 1'b1;

    // Unused Writeback stage only IO & wiring
    // Assign inputs and internal wiring to unused signals to satisfy lint checks
    // Tie-off outputs to constant values
    logic           unused_clk;
    logic           unused_rst;
    logic           unused_en_wb;
    wb_instr_type_e unused_instr_type_wb;
    logic [31:0]    unused_pc_id;
    logic           unused_lsu_data_valid;

    assign unused_clk            = clk_i;
    assign unused_rst            = rst_ni;
    assign unused_en_wb          = en_wb_i;
    assign unused_instr_type_wb  = instr_type_wb_i;
    assign unused_pc_id          = pc_id_i;
    assign unused_lsu_data_valid = lsu_data_valid_i;

    assign outstanding_load_wb_o  = 1'b0;
    assign outstanding_store_wb_o = 1'b0;
    assign pc_wb_o = '0;
    assign rf_write_wb_o = 1'b0;
    assign instr_done_wb_o = 1'b0;
  end
endmodule
