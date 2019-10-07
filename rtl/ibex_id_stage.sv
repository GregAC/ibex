// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifdef RISCV_FORMAL
  `define RVFI
`endif

/**
 * Instruction Decode Stage
 *
 * Decode stage of the core. It decodes the instructions and hosts the register
 * file.
 */

`include "prim_assert.sv"

module ibex_id_stage #(
    parameter bit RV32E           = 0,
    parameter bit RV32M           = 1,
    parameter bit BranchTargetALU = 0,
    parameter bit WritebackStage  = 0
) (
    input  logic                      clk_i,
    input  logic                      rst_ni,

    input  logic                      fetch_enable_i,
    output logic                      ctrl_busy_o,
    output logic                      illegal_insn_o,

    // Interface to IF stage
    input  logic                      instr_valid_i,
    input  logic [31:0]               instr_rdata_i,         // from IF-ID pipeline registers
    input  logic [31:0]               instr_rdata_alu_i,     // from IF-ID pipeline registers
    input  logic [15:0]               instr_rdata_c_i,       // from IF-ID pipeline registers
    input  logic                      instr_is_compressed_i,
    output logic                      instr_req_o,
    output logic                      instr_first_cycle_id_o,
    output logic                      instr_valid_clear_o,   // kill instr in IF-ID reg
    output logic                      id_in_ready_o,         // ID stage is ready for next instr

    // Jumps and branches
    input  logic                      branch_decision_i,

    // IF and ID stage signals
    output logic                      pc_set_o,
    output ibex_pkg::pc_sel_e         pc_mux_o,
    output ibex_pkg::exc_pc_sel_e     exc_pc_mux_o,
    output ibex_pkg::exc_cause_e      exc_cause_o,

    input  logic                      illegal_c_insn_i,
    input  logic                      instr_fetch_err_i,

    input  logic [31:0]               pc_id_i,

    // Stalls
    input  logic                      ex_valid_i,     // EX stage has valid output
    input  logic                      lsu_valid_i,    // LSU has valid output, or is done
    input  logic                      id_stall_lsu_i, // LSU wants to stall ID/EX
                                                      // (only used when writeback stage present)
    input  logic                      lsu_load_i,     // LSU is performing a load
    input  logic                      lsu_busy_i,     // LSU is busy
    // ALU
    output ibex_pkg::alu_op_e         alu_operator_ex_o,
    output logic [31:0]               alu_operand_a_ex_o,
    output logic [31:0]               alu_operand_b_ex_o,

    // Branch target ALU
    output ibex_pkg::jt_mux_sel_e     jt_mux_sel_ex_o,
    output logic [11:0]               bt_operand_imm_o,

    // MUL, DIV
    output logic                      mult_en_ex_o,
    output logic                      div_en_ex_o,
    output logic                      multdiv_sel_ex_o,
    output ibex_pkg::md_op_e          multdiv_operator_ex_o,
    output logic  [1:0]               multdiv_signed_mode_ex_o,
    output logic [31:0]               multdiv_operand_a_ex_o,
    output logic [31:0]               multdiv_operand_b_ex_o,
    output logic                      multdiv_ready_id_o,

    // CSR
    output logic                      csr_access_o,
    output ibex_pkg::csr_op_e         csr_op_o,
    output logic                      csr_save_if_o,
    output logic                      csr_save_id_o,
    output logic                      csr_save_wb_o,
    output logic                      csr_restore_mret_id_o,
    output logic                      csr_restore_dret_id_o,
    output logic                      csr_save_cause_o,
    output logic [31:0]               csr_mtval_o,
    input  ibex_pkg::priv_lvl_e       priv_mode_i,
    input  logic                      csr_mstatus_tw_i,
    input  logic                      illegal_csr_insn_i,

    // Interface to load store unit
    output logic                      data_req_ex_o,
    output logic                      data_we_ex_o,
    output logic [1:0]                data_type_ex_o,
    output logic                      data_sign_ext_ex_o,
    output logic [31:0]               data_wdata_ex_o,

    input  logic                      lsu_addr_incr_req_i,
    input  logic [31:0]               lsu_addr_last_i,

    // Interrupt signals
    input  logic                      csr_mstatus_mie_i,
    input  logic                      csr_msip_i,
    input  logic                      csr_mtip_i,
    input  logic                      csr_meip_i,
    input  logic [14:0]               csr_mfip_i,
    input  logic                      irq_pending_i,
    input  logic                      irq_nm_i,
    output logic                      nmi_mode_o,

    input  logic                      lsu_load_err_i,
    input  logic                      lsu_store_err_i,

    // Debug Signal
    output logic                      debug_mode_o,
    output ibex_pkg::dbg_cause_e      debug_cause_o,
    output logic                      debug_csr_save_o,
    input  logic                      debug_req_i,
    input  logic                      debug_single_step_i,
    input  logic                      debug_ebreakm_i,
    input  logic                      debug_ebreaku_i,
    input  logic                      trigger_match_i,

    // Write back signal
    input  logic [31:0]               wdata_ex_i,
    input  logic [31:0]               csr_rdata_i,

    // Register file read
    output logic [4:0]                rf_raddr_a_o,
    input  logic [31:0]               rf_rdata_a_i,
    output logic [4:0]                rf_raddr_b_o,
    input  logic [31:0]               rf_rdata_b_i,

    // Register file write (via writeback)
    output logic [4:0]                rf_waddr_id_o,
    output logic [31:0]               rf_wdata_id_o,
    output logic                      rf_we_id_o,

    // Register file address Writeback is writing to
    // (Only relevant when Writeback Stage is present)
    input  logic [4:0]                rf_waddr_wb_i,

    output  logic                     en_wb_o,
    output  ibex_pkg::wb_instr_type_e instr_type_wb_o,
    input logic                       ready_wb_i,
    input logic                       rf_write_wb_i,
    input logic                       outstanding_load_wb_i,
    input logic                       outstanding_store_wb_i,

    // Performance Counters
    output logic                      perf_jump_o,    // executing a jump instr
    output logic                      perf_branch_o,  // executing a branch instr
    output logic                      perf_tbranch_o, // executing a taken branch instr
    output logic                      perf_dside_wait_o, // instruction in ID/EX is awaiting memory
                                                         // access to finish before proceeding
    output logic                      instr_id_done_o,
    output logic                      instr_id_done_compressed_o
);

  import ibex_pkg::*;

  // Decoder/Controller, ID stage internal signals
  logic        illegal_insn_dec;
  logic        ebrk_insn;
  logic        mret_insn_dec;
  logic        dret_insn_dec;
  logic        ecall_insn_dec;
  logic        wfi_insn_dec;

  logic        wb_exception;

  logic        branch_in_dec;
  logic        branch_set, branch_set_d;
  logic        jump_in_dec;
  logic        jump_set;

  logic        instr_first_cycle;
  logic        instr_executing;
  logic        instr_done;
  logic        controller_run;
  logic        stall_ld_hz;
  logic        stall_mem;
  logic        stall_multdiv;
  logic        stall_branch;
  logic        stall_jump;
  logic        stall_id;
  logic        stall_wb;
  logic        flush_id;
  logic        multicycle_done;

  // Immediate decoding and sign extension
  logic [31:0] imm_i_type;
  logic [31:0] imm_s_type;
  logic [31:0] imm_b_type;
  logic [31:0] imm_u_type;
  logic [31:0] imm_j_type;
  logic [31:0] zimm_rs1_type;

  logic [31:0] imm_a;       // contains the immediate for operand b
  logic [31:0] imm_b;       // contains the immediate for operand b

  // Register file interface

  rf_wd_sel_e  rf_wdata_id_sel;
  logic        rf_we_id_dec, rf_we_id_raw;
  logic        rf_ren_a, rf_ren_b;

  // ALU Control
  alu_op_e     alu_operator;
  op_a_sel_e   alu_op_a_mux_sel, alu_op_a_mux_sel_dec;
  op_b_sel_e   alu_op_b_mux_sel, alu_op_b_mux_sel_dec;

  imm_a_sel_e  imm_a_mux_sel;
  imm_b_sel_e  imm_b_mux_sel, imm_b_mux_sel_dec;

  // Multiplier Control
  logic        mult_en_id, mult_en_dec; // use integer multiplier
  logic        div_en_id, div_en_dec;   // use integer division or reminder
  logic        multdiv_sel_dec;
  logic        multdiv_en_dec;
  md_op_e      multdiv_operator;
  logic [1:0]  multdiv_signed_mode;

  // Data Memory Control
  logic        data_we_id;
  logic [1:0]  data_type_id;
  logic        data_sign_ext_id;
  logic        data_req_id, data_req_dec;
  logic        data_req_allowed;

  // CSR control
  logic        csr_pipe_flush;

  logic [31:0] alu_operand_a;
  logic [31:0] alu_operand_b;

  /////////////
  // LSU Mux //
  /////////////

  // Misaligned loads/stores result in two aligned loads/stores, compute second address
  assign alu_op_a_mux_sel = lsu_addr_incr_req_i ? OP_A_FWD        : alu_op_a_mux_sel_dec;
  assign alu_op_b_mux_sel = lsu_addr_incr_req_i ? OP_B_IMM        : alu_op_b_mux_sel_dec;
  assign imm_b_mux_sel    = lsu_addr_incr_req_i ? IMM_B_INCR_ADDR : imm_b_mux_sel_dec;

  ///////////////////
  // Operand A MUX //
  ///////////////////

  // Immediate MUX for Operand A
  assign imm_a = (imm_a_mux_sel == IMM_A_Z) ? zimm_rs1_type : '0;

  // ALU MUX for Operand A
  always_comb begin : alu_operand_a_mux
    unique case (alu_op_a_mux_sel)
      OP_A_REG_A:  alu_operand_a = rf_rdata_a_i;
      OP_A_FWD:    alu_operand_a = lsu_addr_last_i;
      OP_A_CURRPC: alu_operand_a = pc_id_i;
      OP_A_IMM:    alu_operand_a = imm_a;
      default:     alu_operand_a = pc_id_i;
    endcase
  end

  ///////////////////
  // Operand B MUX //
  ///////////////////

  // Immediate MUX for Operand B
  always_comb begin : immediate_b_mux
    unique case (imm_b_mux_sel)
      IMM_B_I:         imm_b = imm_i_type;
      IMM_B_S:         imm_b = imm_s_type;
      IMM_B_B:         imm_b = imm_b_type;
      IMM_B_U:         imm_b = imm_u_type;
      IMM_B_J:         imm_b = imm_j_type;
      IMM_B_INCR_PC:   imm_b = instr_is_compressed_i ? 32'h2 : 32'h4;
      IMM_B_INCR_ADDR: imm_b = 32'h4;
      default:         imm_b = 32'h4;
    endcase
  end

  // ALU MUX for Operand B
  assign alu_operand_b = (alu_op_b_mux_sel == OP_B_IMM) ? imm_b : rf_rdata_b_i;

  ///////////////////////
  // Register File MUX //
  ///////////////////////

  // Register file write enable mux - do not propagate illegal CSR ops, do not write when idle,
  // for loads/stores and multdiv operations write when the data is ready only
  assign rf_we_id_o = rf_we_id_raw & instr_executing & ~illegal_csr_insn_i;

  // Register file write data mux
  always_comb begin : rf_wdata_id_mux
    unique case (rf_wdata_id_sel)
      RF_WD_EX:  rf_wdata_id_o = wdata_ex_i;
      RF_WD_CSR: rf_wdata_id_o = csr_rdata_i;
      default:   rf_wdata_id_o = wdata_ex_i;
    endcase;
  end

  /////////////
  // Decoder //
  /////////////

  ibex_decoder #(
      .RV32E           ( RV32E           ),
      .RV32M           ( RV32M           ),
      .BranchTargetALU ( BranchTargetALU )
  ) decoder_i (
      .clk_i                           ( clk_i                ),
      .rst_ni                          ( rst_ni               ),

      // controller
      .illegal_insn_o                  ( illegal_insn_dec     ),
      .ebrk_insn_o                     ( ebrk_insn            ),
      .mret_insn_o                     ( mret_insn_dec        ),
      .dret_insn_o                     ( dret_insn_dec        ),
      .ecall_insn_o                    ( ecall_insn_dec       ),
      .wfi_insn_o                      ( wfi_insn_dec         ),
      .jump_set_o                      ( jump_set             ),

      // from IF-ID pipeline register
      .instr_first_cycle_i             ( instr_first_cycle    ),
      .instr_rdata_i                   ( instr_rdata_i        ),
      .instr_rdata_alu_i               ( instr_rdata_alu_i    ),
      .illegal_c_insn_i                ( illegal_c_insn_i     ),

      // immediates
      .imm_a_mux_sel_o                 ( imm_a_mux_sel        ),
      .imm_b_mux_sel_o                 ( imm_b_mux_sel_dec    ),
      .jt_mux_sel_o                    ( jt_mux_sel_ex_o      ),

      .imm_i_type_o                    ( imm_i_type           ),
      .imm_s_type_o                    ( imm_s_type           ),
      .imm_b_type_o                    ( imm_b_type           ),
      .imm_u_type_o                    ( imm_u_type           ),
      .imm_j_type_o                    ( imm_j_type           ),
      .zimm_rs1_type_o                 ( zimm_rs1_type        ),

      // register file
      .rf_wdata_id_sel_o               ( rf_wdata_id_sel      ),
      .rf_we_id_o                      ( rf_we_id_dec         ),

      .rf_raddr_a_o                    ( rf_raddr_a_o         ),
      .rf_raddr_b_o                    ( rf_raddr_b_o         ),
      .rf_waddr_id_o                   ( rf_waddr_id_o        ),
      .rf_ren_a_o                      ( rf_ren_a             ),
      .rf_ren_b_o                      ( rf_ren_b             ),

      // ALU
      .alu_operator_o                  ( alu_operator         ),
      .alu_op_a_mux_sel_o              ( alu_op_a_mux_sel_dec ),
      .alu_op_b_mux_sel_o              ( alu_op_b_mux_sel_dec ),

      // MULT & DIV
      .mult_en_o                       ( mult_en_dec          ),
      .div_en_o                        ( div_en_dec           ),
      .multdiv_sel_o                   ( multdiv_sel_dec      ),
      .multdiv_operator_o              ( multdiv_operator     ),
      .multdiv_signed_mode_o           ( multdiv_signed_mode  ),

      // CSRs
      .csr_access_o                    ( csr_access_o         ),
      .csr_op_o                        ( csr_op_o             ),
      .csr_pipe_flush_o                ( csr_pipe_flush       ),

      // LSU
      .data_req_o                      ( data_req_dec         ),
      .data_we_o                       ( data_we_id           ),
      .data_type_o                     ( data_type_id         ),
      .data_sign_extension_o           ( data_sign_ext_id     ),

      // jump/branches
      .jump_in_dec_o                   ( jump_in_dec          ),
      .branch_in_dec_o                 ( branch_in_dec        )
  );

  ////////////////
  // Controller //
  ////////////////

  assign illegal_insn_o = instr_valid_i & (illegal_insn_dec | illegal_csr_insn_i);

  ibex_controller #(
    .WritebackStage ( WritebackStage )
  ) controller_i (
      .clk_i                          ( clk_i                  ),
      .rst_ni                         ( rst_ni                 ),

      .fetch_enable_i                 ( fetch_enable_i         ),
      .ctrl_busy_o                    ( ctrl_busy_o            ),

      // decoder related signals
      .illegal_insn_i                 ( illegal_insn_o         ),
      .ecall_insn_i                   ( ecall_insn_dec         ),
      .mret_insn_i                    ( mret_insn_dec          ),
      .dret_insn_i                    ( dret_insn_dec          ),
      .wfi_insn_i                     ( wfi_insn_dec           ),
      .ebrk_insn_i                    ( ebrk_insn              ),
      .csr_pipe_flush_i               ( csr_pipe_flush         ),

      // from IF-ID pipeline
      .instr_valid_i                  ( instr_valid_i          ),
      .instr_i                        ( instr_rdata_i          ),
      .instr_compressed_i             ( instr_rdata_c_i        ),
      .instr_is_compressed_i          ( instr_is_compressed_i  ),
      .instr_fetch_err_i              ( instr_fetch_err_i      ),
      .pc_id_i                        ( pc_id_i                ),

      // to IF-ID pipeline
      .instr_valid_clear_o            ( instr_valid_clear_o    ),
      .id_in_ready_o                  ( id_in_ready_o          ),
      .controller_run_o               ( controller_run         ),

      // to prefetcher
      .instr_req_o                    ( instr_req_o            ),
      .pc_set_o                       ( pc_set_o               ),
      .pc_mux_o                       ( pc_mux_o               ),
      .exc_pc_mux_o                   ( exc_pc_mux_o           ),
      .exc_cause_o                    ( exc_cause_o            ),

      // LSU
      .lsu_addr_last_i                ( lsu_addr_last_i        ),
      .load_err_i                     ( lsu_load_err_i         ),
      .store_err_i                    ( lsu_store_err_i        ),
      .wb_exception_o                 ( wb_exception           ),

      // jump/branch control
      .branch_set_i                   ( branch_set             ),
      .jump_set_i                     ( jump_set               ),

      // interrupt signals
      .csr_mstatus_mie_i              ( csr_mstatus_mie_i      ),
      .csr_msip_i                     ( csr_msip_i             ),
      .csr_mtip_i                     ( csr_mtip_i             ),
      .csr_meip_i                     ( csr_meip_i             ),
      .csr_mfip_i                     ( csr_mfip_i             ),
      .irq_pending_i                  ( irq_pending_i          ),
      .irq_nm_i                       ( irq_nm_i               ),
      .nmi_mode_o                     ( nmi_mode_o             ),

      // CSR Controller Signals
      .csr_save_if_o                  ( csr_save_if_o          ),
      .csr_save_id_o                  ( csr_save_id_o          ),
      .csr_save_wb_o                  ( csr_save_wb_o          ),
      .csr_restore_mret_id_o          ( csr_restore_mret_id_o  ),
      .csr_restore_dret_id_o          ( csr_restore_dret_id_o  ),
      .csr_save_cause_o               ( csr_save_cause_o       ),
      .csr_mtval_o                    ( csr_mtval_o            ),
      .priv_mode_i                    ( priv_mode_i            ),
      .csr_mstatus_tw_i               ( csr_mstatus_tw_i       ),

      // Debug Signal
      .debug_mode_o                   ( debug_mode_o           ),
      .debug_cause_o                  ( debug_cause_o          ),
      .debug_csr_save_o               ( debug_csr_save_o       ),
      .debug_req_i                    ( debug_req_i            ),
      .debug_single_step_i            ( debug_single_step_i    ),
      .debug_ebreakm_i                ( debug_ebreakm_i        ),
      .debug_ebreaku_i                ( debug_ebreaku_i        ),
      .trigger_match_i                ( trigger_match_i        ),

      // stall signals
      .stall_id_i                     ( stall_id               ),
      .stall_wb_i                     ( stall_wb               ),
      .flush_id_o                     ( flush_id               ),

      // Performance Counters
      .perf_jump_o                    ( perf_jump_o            ),
      .perf_tbranch_o                 ( perf_tbranch_o         )
  );

  //////////////
  // ID-EX/WB //
  //////////////

  assign multdiv_en_dec   = mult_en_dec | div_en_dec;

  assign data_req_id     = instr_executing ? data_req_allowed & data_req_dec : 1'b0;
  assign mult_en_id      = instr_executing ? mult_en_dec                     : 1'b0;
  assign div_en_id       = instr_executing ? div_en_dec                      : 1'b0;

  ///////////
  // ID-EX //
  ///////////

  assign data_req_ex_o               = data_req_id;
  assign data_we_ex_o                = data_we_id;
  assign data_type_ex_o              = data_type_id;
  assign data_sign_ext_ex_o          = data_sign_ext_id;
  assign data_wdata_ex_o             = rf_rdata_b_i;

  assign alu_operator_ex_o           = alu_operator;
  assign alu_operand_a_ex_o          = alu_operand_a;
  assign alu_operand_b_ex_o          = alu_operand_b;

  if (BranchTargetALU) begin : g_bt_operand_imm
    // Branch target ALU sign-extends and inserts bottom 0 bit so only want the
    // 'raw' B-type immediate bits.
    assign bt_operand_imm_o = imm_b_type[12:1];
  end else begin : g_no_bt_operand_imm
    assign bt_operand_imm_o = '0;
  end

  assign mult_en_ex_o                = mult_en_id;
  assign div_en_ex_o                 = div_en_id;
  assign multdiv_sel_ex_o            = multdiv_sel_dec;

  assign multdiv_operator_ex_o       = multdiv_operator;
  assign multdiv_signed_mode_ex_o    = multdiv_signed_mode;
  assign multdiv_operand_a_ex_o      = rf_rdata_a_i;
  assign multdiv_operand_b_ex_o      = rf_rdata_b_i;

  typedef enum logic { FIRST_CYCLE, MULTI_CYCLE } id_fsm_e;
  id_fsm_e id_wb_fsm_cs, id_wb_fsm_ns;

  ////////////////////////////////
  // ID-EX/WB Pipeline Register //
  ////////////////////////////////

  if (BranchTargetALU) begin : g_branch_set_direct
    // Branch set fed straight to controller with branch target ALU
    // (condition pass/fail used same cycle as generated instruction request)
    assign branch_set = branch_set_d;
  end else begin : g_branch_set_flopped
    // Branch set flopped without branch target ALU
    // (condition pass/fail used next cycle where branch target is calculated)
    logic branch_set_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        branch_set_q <= 1'b0;
      end else begin
        branch_set_q <= branch_set_d;
      end
    end

    assign branch_set = branch_set_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : id_wb_pipeline_reg
    if (!rst_ni) begin
      id_wb_fsm_cs            <= FIRST_CYCLE;
    end else begin
      id_wb_fsm_cs            <= id_wb_fsm_ns;
    end
  end

  //////////////////
  // ID-EX/WB FSM //
  //////////////////

  // ID/EX stage can be in two states, FIRST_CYCLE and MULTI_CYCLE. An instruction enters
  // MULTI_CYCLE if it requires multiple cycles to complete regardless of stalls and other
  // considerations. An instruction may be held in FIRST_CYCLE if it's unable to begin executing
  // (this is controlled by instr_executing).

  always_comb begin : id_wb_fsm
    id_wb_fsm_ns            = id_wb_fsm_cs;
    rf_we_id_raw            = rf_we_id_dec;
    stall_multdiv           = 1'b0;
    stall_jump              = 1'b0;
    stall_branch            = 1'b0;
    branch_set_d            = 1'b0;
    perf_branch_o           = 1'b0;
    instr_done              = 1'b0;
    multdiv_ready_id_o      = 1'b0;

    if (instr_executing) begin
      unique case (id_wb_fsm_cs)
        FIRST_CYCLE: begin
          unique case (1'b1)
            data_req_dec: begin
              if (!WritebackStage) begin
                // LSU operation
                id_wb_fsm_ns          = MULTI_CYCLE;
              end else begin
                if(stall_mem) begin
                  instr_done          = 1'b0;
                  id_wb_fsm_ns        = MULTI_CYCLE;
                end else begin
                  instr_done          = 1'b1;
                end
              end
            end
            multdiv_en_dec: begin
              // MUL or DIV operation
              id_wb_fsm_ns            = MULTI_CYCLE;
              rf_we_id_raw            = 1'b0;
              stall_multdiv           = 1'b1;
            end
            branch_in_dec: begin
              // cond branch operation
              id_wb_fsm_ns            =  branch_decision_i ? MULTI_CYCLE : FIRST_CYCLE;
              stall_branch            =  branch_decision_i;
              branch_set_d            =  branch_decision_i;
              perf_branch_o           =  1'b1;
              instr_done              = ~branch_decision_i;
            end
            jump_in_dec: begin
              // uncond branch operation
              id_wb_fsm_ns            = MULTI_CYCLE;
              stall_jump              = 1'b1;
            end
            default: begin
              instr_done              = 1'b1;
            end
          endcase
        end

        MULTI_CYCLE: begin
          if(multdiv_en_dec) begin
            rf_we_id_raw = rf_we_id_dec & ex_valid_i;

            if (WritebackStage) begin
              multdiv_ready_id_o = ready_wb_i;
            end
          end

          if (multicycle_done & ready_wb_i) begin
            id_wb_fsm_ns            = FIRST_CYCLE;
            instr_done              = 1'b1;
          end else begin
            stall_multdiv           = multdiv_en_dec;
            stall_branch            = branch_in_dec;
            stall_jump              = jump_in_dec;
          end
        end

        default: begin
          id_wb_fsm_ns = FIRST_CYCLE;
        end
      endcase
    end
  end

  // Stall ID/EX stage for reason that relates to instruction in ID/EX
  assign stall_id = stall_ld_hz | stall_mem | stall_multdiv | stall_jump | stall_branch;

  assign en_wb_o = instr_done & ~stall_id & ~flush_id & instr_executing;

  if (WritebackStage) begin
    assign multicycle_done = data_req_dec ? ~stall_mem : ex_valid_i;
  end else begin
    assign multicycle_done = data_req_dec ? lsu_valid_i : ex_valid_i;
  end

  // Signal instruction in ID is in it's first cycle. It can remain in its
  // first cycle if it is stalled.
  assign instr_first_cycle      = instr_valid_i & (id_wb_fsm_cs == FIRST_CYCLE);
  // Used by RVFI to know when to capture register read data
  assign instr_first_cycle_id_o = instr_first_cycle;

  if (WritebackStage) begin : gen_stall_mem
    // Hazard between registers being read and written
    logic rf_rd_a_hz;
    logic rf_rd_b_hz;

    logic data_req_complete_d;
    logic data_req_complete_q;

    logic outstanding_memory_access;

    assign data_req_complete_d =
      (data_req_complete_q | (data_req_id & ~id_stall_lsu_i)) & ~instr_id_done_o;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        data_req_complete_q <= 1'b0;
      end else begin
        data_req_complete_q <= data_req_complete_d;
      end
    end

    // Is a memory access ongoing that isn't finishing this cycle
    assign outstanding_memory_access = (outstanding_load_wb_i | outstanding_store_wb_i) &
                                       ~lsu_valid_i;

    // Can start a new memory access if any previous one has finished or is finishing
    // Don't start a new memory access if this instruction has already done it's request
    assign data_req_allowed = ~outstanding_memory_access & ~data_req_complete_q;

    // With writeback stage instructions must be prevented from executing if there is:
    // - A load hazard
    // - A pending exception in writeback
    //   Instruction in ID/EX will be flushed and core will jump to exception handler
    // - The controller isn't running instructions
    // - A pending memory access
    //   If it receives an error response this results in a precise exception from WB so ID/EX
    //   instruction must not execute util error response is known).
    // - A load/store error
    //   This will cause a precise exception for the instruction in WB so ID/EX instruction must not
    //   execute
    assign instr_executing = instr_valid_i              &
                             ~instr_fetch_err_i         &
                             ~stall_ld_hz               &
                             ~outstanding_memory_access &
                             ~wb_exception              &
                             controller_run;

    // Stall when requested by the LSU (meaning load/store in ID/EX needs to be held there whilst
    // data request is granted or util second half of misaligned access is sent out) or when LSU is
    // required but data requests aren't allowed.
    assign stall_mem = id_stall_lsu_i | (instr_valid_i & data_req_dec & ~data_req_allowed);

    // If instruction is reading register that load will be writing stall in
    // ID until load is complete. No need to stall when reading zero register.
    assign rf_rd_a_hz = (rf_waddr_wb_i == rf_raddr_a_o) & |rf_raddr_a_o & rf_ren_a;
    assign rf_rd_b_hz = (rf_waddr_wb_i == rf_raddr_b_o) & |rf_raddr_b_o & rf_ren_b;

    assign stall_ld_hz = outstanding_load_wb_i & lsu_load_i & (rf_rd_a_hz | rf_rd_b_hz) & rf_write_wb_i;

    assign instr_type_wb_o = ~data_req_dec ? WB_INSTR_OTHER :
                              data_we_id   ? WB_INSTR_STORE :
                                             WB_INSTR_LOAD;

    // Stall ID/EX as instruction in ID/EX cannot proceed to writeback yet
    assign stall_wb = en_wb_o & ~ready_wb_i;

    assign perf_dside_wait_o = instr_valid_i & (outstanding_memory_access | stall_ld_hz);
  end else begin

    assign data_req_allowed = instr_first_cycle;

    // Without Writeback Stage always stall the first cycle of a load/store.
    // Then stall until it is complete
    assign stall_mem = (lsu_busy_i & ~lsu_valid_i) | (instr_first_cycle & data_req_dec);

    // No load hazards without Writeback Stage
    assign stall_ld_hz = 1'b0;

    // Without writeback stage any valid instruction that hasn't seen an error will execute
    assign instr_executing = instr_valid_i & ~instr_fetch_err_i & controller_run;

    // Unused Writeback stage only IO & wiring
    // Assign inputs and internal wiring to unused signals to satisfy lint checks
    // Tie-off outputs to constant values
    logic unused_id_stall_lsu;
    logic unused_lsu_load;
    logic [4:0] unused_rf_waddr_wb;
    logic unused_rf_write_wb;
    logic unused_outstanding_load_wb;
    logic unused_outstanding_store_wb;
    logic unused_wb_exception;
    logic unused_rf_ren_a, unused_rf_ren_b;

    assign unused_id_stall_lsu         = id_stall_lsu_i;
    assign unused_lsu_load             = lsu_load_i;
    assign unused_rf_waddr_wb          = rf_waddr_wb_i;
    assign unused_rf_write_wb          = rf_write_wb_i;
    assign unused_outstanding_load_wb  = outstanding_load_wb_i;
    assign unused_outstanding_store_wb = outstanding_store_wb_i;
    assign unused_wb_exception         = wb_exception;
    assign unused_rf_ren_a             = rf_ren_a;
    assign unused_rf_ren_b             = rf_ren_b;

    assign instr_type_wb_o = WB_INSTR_OTHER;
    assign stall_wb        = 1'b0;

    assign perf_dside_wait_o = data_req_dec & ~lsu_valid_i;
  end


  assign instr_id_done_o = en_wb_o & ready_wb_i;
  assign instr_id_done_compressed_o = instr_id_done_o & instr_is_compressed_i;

  ////////////////
  // Assertions //
  ////////////////

  // Selectors must be known/valid.
  `ASSERT_KNOWN(IbexAluOpMuxSelKnown, alu_op_a_mux_sel, clk_i, !rst_ni)
  `ASSERT(IbexImmBMuxSelValid, imm_b_mux_sel inside {
      IMM_B_I,
      IMM_B_S,
      IMM_B_B,
      IMM_B_U,
      IMM_B_J,
      IMM_B_INCR_PC,
      IMM_B_INCR_ADDR
      }, clk_i, !rst_ni)
  `ASSERT(IbexRegfileWdataSelValid, regfile_wdata_sel inside {
      RF_WD_LSU,
      RF_WD_EX,
      RF_WD_CSR
      }, clk_i, !rst_ni)
  `ASSERT_KNOWN(IbexWbStateKnown, id_wb_fsm_cs, clk_i, !rst_ni)

  // Branch decision must be valid when jumping.
  `ASSERT(IbexBranchDecisionValid, branch_in_dec |-> !$isunknown(branch_decision_i), clk_i, !rst_ni)

  // Instruction delivered to ID stage can not contain X.
  `ASSERT(IbexIdInstrKnown,
      (instr_valid_i && !(illegal_c_insn_i || instr_fetch_err_i)) |-> !$isunknown(instr_rdata_i),
      clk_i, !rst_ni)

  // Instruction delivered to ID stage can not contain X.
  `ASSERT(IbexIdInstrALUKnown,
      (instr_valid_i && !(illegal_c_insn_i || instr_fetch_err_i)) |-> !$isunknown(instr_rdata_alu_i),
      clk_i, !rst_ni)

  // Multicycle enable signals must be unique.
  `ASSERT(IbexMulticycleEnableUnique,
      $onehot0({data_req_dec, multdiv_en_dec, branch_in_dec, jump_in_dec}), clk_i, !rst_ni)

  // Duplicated instruction flops must match
  `ASSERT(IbexDuplicateInstrMatch, instr_valid_i |-> instr_rdata_i == instr_rdata_alu_i, clk_i, !rst_ni);

  `ifdef CHECK_MISALIGNED
  `ASSERT(IbexMisalignedMemoryAccess, !lsu_addr_incr_req_i, clk_i, !rst_ni)
  `endif

endmodule
