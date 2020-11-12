// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

interface core_ibex_fcov_if import ibex_pkg::*; (
  input clk_i,
  input rst_ni,

  input priv_lvl_e priv_mode_id,
  input priv_lvl_e priv_mode_if,
  input priv_lvl_e priv_mode_lsu
);
  `include "dv_macros.svh"
  `include "dv_fcov.svh"

  typedef enum {
    InsnCategoryALU,
    InsnCategoryMult,
    InsnCategoryDiv,
    InsnCategoryBranch,
    InsnCategoryJump,
    InsnCategoryLoad,
    InsnCategoryStore,
    InsnCategoryOther,
    InsnCategoryNone
  } insn_category_e;

  typedef enum {
    IdStallTypeNone,
    IdStallTypeInsn,
    IdStallTypeLdHz,
    IdStallTypeMem
  } id_stall_type_e;

  // Given a uncompressed RISC-V instruction determine what instruction category it belongs to.
  // Compressed instructions are not handled.  When `insn_valid` isn't set `InsnCategoryNone` is
  // returned.
  function insn_category_e insn_category_from_bits(logic [31:0] insn, logic insn_valid);

    if (insn_valid) begin
      case (insn[6:0])
        ibex_pkg::OPCODE_LUI: return InsnCategoryALU;
        ibex_pkg::OPCODE_AUIPC: return InsnCategoryALU;
        ibex_pkg::OPCODE_JAL: return InsnCategoryJump;
        ibex_pkg::OPCODE_JALR: return InsnCategoryJump;
        ibex_pkg::OPCODE_BRANCH: return InsnCategoryBranch;
        ibex_pkg::OPCODE_LOAD: return InsnCategoryLoad;
        ibex_pkg::OPCODE_STORE: return InsnCategoryStore;
        ibex_pkg::OPCODE_OP_IMM: return InsnCategoryALU;
        ibex_pkg::OPCODE_OP: begin
          if(insn[31:25] == 7'b0000000) begin
            return InsnCategoryALU; // RV32I ALU reg-reg ops
          end else if (insn[31:25] == 7'b0000001) begin
            if (insn[14]) begin
              return InsnCategoryMult; //MUL*
            end else begin
              return InsnCategoryDiv; // DIV*
            end
          end
        end
        default: return InsnCategoryOther;
      endcase
    end

    return InsnCategoryNone;
  endfunction

  // Look at signals for ID stage (using uarch_fcov_vif) to determine what kind of stall, if any, is
  // occurring in the ID stage and return it.
  function id_stall_type_e determine_id_stall_type();
    if (id_stage_i.instr_valid_i) begin
      if (id_stage_i.stall_multdiv || id_stage_i.stall_branch ||
          id_stage_i.stall_jump) begin
        return IdStallTypeInsn;
      end

      if (id_stage_i.stall_ld_hz) begin
        return IdStallTypeLdHz;
      end

      if (id_stage_i.stall_mem) begin
        return IdStallTypeMem;
      end

      return IdStallTypeNone;
    end

   return IdStallTypeNone;
  endfunction

`ifndef DV_FCOV_SVA
`define DV_FCOV_SVA(__ev_name, __sva, __clk = clk_i, __rst = rst_ni) \
  event __ev_name; \
  cover property (@(posedge __clk) disable iff (__rst == 0) (__sva)) begin \
    -> __ev_name; \
  end
`endif

  `DV_FCOV_SVA(instruction_unstalled,
    determine_id_stall_type() != IdStallTypeNone ##1 determine_id_stall_type() == IdStallTypeNone)

  covergroup uarch_cg @(posedge clk_i);
    type_option.strobe = 1;
    cp_insn_unstalled: coverpoint instruction_unstalled.triggered;

    cp_insn_category_id: coverpoint insn_category_from_bits(id_stage_i.instr_rdata_i,
                                                            id_stage_i.instr_valid_i);

    cp_stall_type_id: coverpoint determine_id_stall_type();

    cp_wb_reg_hz: coverpoint id_stage_i.fcov_rf_rd_wb_hz;
    cp_wb_load_hz: coverpoint id_stage_i.fcov_rf_rd_wb_hz &&
                              wb_stage_i.outstanding_load_wb_o;

    cp_ls_error_exception: coverpoint load_store_unit_i.fcov_ls_error_exception;
    cp_ls_pmp_exception: coverpoint load_store_unit_i.fcov_ls_pmp_exception;

    cp_branch_taken: coverpoint id_stage_i.fcov_branch_taken;
    cp_branch_not_taken: coverpoint id_stage_i.fcov_branch_not_taken;

    cp_priv_mode_id: coverpoint priv_mode_id;
    cp_priv_mode_if: coverpoint priv_mode_if;
    cp_prov_mode_lsu: coverpoint priv_mode_lsu;

    cp_interrupt_taken: coverpoint id_stage_i.controller_i.fcov_interrupt_taken;
    cp_debug_entry_if: coverpoint id_stage_i.controller_i.fcov_debug_entry_if;
    cp_debug_entry_id: coverpoint id_stage_i.controller_i.fcov_debug_entry_id;
    cp_pipe_flush: coverpoint id_stage_i.controller_i.fcov_pipe_flush;

    wb_reg_hz_instr_cross: cross cp_insn_category_id, cp_wb_reg_hz;
    stall_cross: cross cp_insn_category_id, cp_stall_type_id;
    pipe_cross: cross cp_insn_category_id, if_stage_i.if_instr_valid,
                      wb_stage_i.fcov_wb_valid;

    interrupt_taken_instr_cross: cross cp_interrupt_taken, cp_insn_category_id;
    debug_entry_if_instr_cross: cross cp_debug_entry_if, cp_insn_category_id;
    pipe_flush_instr_cross: cross cp_pipe_flush, cp_insn_category_id;
  endgroup

  uarch_cg uarch_cg_inst;

  initial begin
    #0;
    uarch_cg_inst = new();
  end
endmodule
