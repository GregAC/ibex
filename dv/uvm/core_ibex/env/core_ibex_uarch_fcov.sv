// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class core_ibex_uarch_fcov extends uvm_component;
  `uvm_component_utils(core_ibex_uarch_fcov)

  virtual clk_rst_if              clk_vif;
  virtual core_ibex_uarch_fcov_if uarch_fcov_vif;

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

  typedef struct {
    insn_category_e insn_category_id;
    id_stall_type_e stall_type_id;
    bit             valid_if;
    bit             valid_wb;
  } cov_info_t;

  cov_info_t cov_info;

  covergroup uarch_cg;
    cp_insn_category_id: coverpoint cov_info.insn_category_id;
    cp_stall_type_id: coverpoint cov_info.stall_type_id;
    pipe_cross: cross cp_insn_category_id, cov_info.valid_if, cov_info.valid_wb;
    stall_cross: cross cp_insn_category_id, cp_stall_type_id;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);

    uarch_cg = new();
  endfunction

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
  function id_stall_type_e determine_id_stall_type_from_vif();
    if (uarch_fcov_vif.fcov_cb.valid_id) begin
      if (uarch_fcov_vif.fcov_cb.stall_id_multdiv || uarch_fcov_vif.fcov_cb.stall_id_branch ||
          uarch_fcov_vif.fcov_cb.stall_id_jump) begin
        return IdStallTypeInsn;
      end

      if (uarch_fcov_vif.fcov_cb.stall_id_ld_hz) begin
        return IdStallTypeLdHz;
      end

      if (uarch_fcov_vif.fcov_cb.stall_id_mem) begin
        return IdStallTypeMem;
      end

      return IdStallTypeNone;
    end

   return IdStallTypeNone;
  endfunction

  // Update the cov_info struct with the values from uart_fcov_vif
  virtual function update_cov_info();
    // Instruction in ID is always uncompressed as IF handles decompression
    cov_info.insn_category_id = insn_category_from_bits(uarch_fcov_vif.fcov_cb.instr_id, uarch_fcov_vif.fcov_cb.valid_id);
    cov_info.stall_type_id = determine_id_stall_type_from_vif();
    cov_info.valid_if = uarch_fcov_vif.fcov_cb.valid_if;
    cov_info.valid_wb = uarch_fcov_vif.fcov_cb.valid_wb;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    // Obtain virtual interfaces for fcov signals and clocking
    if (!uvm_config_db#(virtual clk_rst_if)::get(null, "", "clk_if", clk_vif)) begin
      `uvm_fatal(`gfn, "Cannot get clk_if")
    end

    if (!uvm_config_db#(virtual core_ibex_uarch_fcov_if)::get(null, "", "uarch_fcov_if",
                                                              uarch_fcov_vif)) begin
      `uvm_fatal(`gfn, "Cannot get uarch_fcov_if")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      // Every clock update cov_info with the current uarch_fcov_vif values then sample cover group
      clk_vif.wait_clks(1);

      update_cov_info();

      uarch_cg.sample();
    end
  endtask
endclass
