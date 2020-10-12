module core_ibex_fcov_bind;
  import core_ibex_fcov_pkg::*;

  bind ibex_id_stage core_ibex_fcov_id_stage_if u_id_stage_if (
    .*
  );

  bind ibex_if_stage core_ibex_fcov_if_stage_if u_if_stage_if (
    .*
  );

  bind ibex_wb_stage core_ibex_fcov_wb_stage_if u_wb_stage_if (
    .wb_valid_q(g_writeback_stage.wb_valid_q)
  );

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
    if (fcov_ifs::id_stage.instr_valid_i) begin
      if (fcov_ifs::id_stage.stall_multdiv || fcov_ifs::id_stage.stall_branch ||
          fcov_ifs::id_stage.stall_jump) begin
        return IdStallTypeInsn;
      end

      if (fcov_ifs::id_stage.stall_ld_hz) begin
        return IdStallTypeLdHz;
      end

      if (fcov_ifs::id_stage.stall_mem) begin
        return IdStallTypeMem;
      end

      return IdStallTypeNone;
    end

   return IdStallTypeNone;
  endfunction

  covergroup uarch_cg @(posedge fcov_ifs::id_stage.clk_i);
    cp_insn_category_id: coverpoint insn_category_from_bits(fcov_ifs::id_stage.instr_rdata_i, fcov_ifs::id_stage.instr_valid_i);
    cp_stall_type_id: coverpoint determine_id_stall_type();
    stall_cross: cross cp_insn_category_id, cp_stall_type_id;
    pipe_cross: cross cp_insn_category_id, fcov_ifs::if_stage.if_instr_valid, fcov_ifs::wb_stage.wb_valid_q;
  endgroup

  uarch_cg uarch_cg_inst;

  initial begin
    #0;
    uarch_cg_inst = new();
  end
endmodule
