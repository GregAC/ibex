// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Arithmetic logic unit
 */
module ibex_alu #(
  parameter ibex_pkg::rv32b_e RV32B = ibex_pkg::RV32BNone
) (
    input  ibex_pkg::alu_op_e operator_i,
    input  logic [31:0]       operand_a_i,
    input  logic [31:0]       operand_b_i,

    input  logic              instr_first_cycle_i,

    input  logic [32:0]       multdiv_operand_a_i,
    input  logic [32:0]       multdiv_operand_b_i,

    input  logic              multdiv_sel_i,

    input  logic [31:0]       imd_val_q_i[2],
    output logic [31:0]       imd_val_d_o[2],
    output logic [1:0]        imd_val_we_o,

    output logic [31:0]       adder_result_o,
    output logic [33:0]       adder_result_ext_o,

    output logic [31:0]       result_o,
    output logic              comparison_result_o,
    output logic              is_equal_result_o
);
  import ibex_pkg::*;

  logic [31:0] operand_a_rev;
  logic [32:0] operand_b_neg;

  // bit reverse operand_a for left shifts and bit counting
  for (genvar k = 0; k < 32; k++) begin : gen_rev_operand_a
    assign operand_a_rev[k] = operand_a_i[31-k];
  end

  ///////////
  // Adder //
  ///////////

  logic        adder_op_b_negate;
  logic [32:0] adder_in_a, adder_in_b;
  logic [31:0] adder_result;

  always_comb begin
    adder_op_b_negate = 1'b0;
    unique case (operator_i)
      // Adder OPs
      ALU_SUB,

      // Comparator OPs
      ALU_EQ,   ALU_NE,
      ALU_GE,   ALU_GEU,
      ALU_LT,   ALU_LTU,
      ALU_SLT,  ALU_SLTU,

      // MinMax OPs (RV32B Ops)
      ALU_MIN,  ALU_MINU,
      ALU_MAX,  ALU_MAXU: adder_op_b_negate = 1'b1;

      default:;
    endcase
  end

  // prepare operand a
  assign adder_in_a    = multdiv_sel_i ? multdiv_operand_a_i : {operand_a_i,1'b1};

  // prepare operand b
  assign operand_b_neg = {operand_b_i,1'b0} ^ {33{1'b1}};
  always_comb begin
    unique case(1'b1)
      multdiv_sel_i:     adder_in_b = multdiv_operand_b_i;
      adder_op_b_negate: adder_in_b = operand_b_neg;
      default :          adder_in_b = {operand_b_i, 1'b0};
    endcase
  end

  // actual adder
  assign adder_result_ext_o = $unsigned(adder_in_a) + $unsigned(adder_in_b);

  assign adder_result       = adder_result_ext_o[32:1];

  assign adder_result_o     = adder_result;

  ////////////////
  // Comparison //
  ////////////////

  logic is_equal;
  logic is_greater_equal;  // handles both signed and unsigned forms
  logic cmp_signed;

  always_comb begin
    unique case (operator_i)
      ALU_GE,
      ALU_LT,
      ALU_SLT,
      // RV32B only
      ALU_MIN,
      ALU_MAX: cmp_signed = 1'b1;

      default: cmp_signed = 1'b0;
    endcase
  end

  assign is_equal = (adder_result == 32'b0);
  assign is_equal_result_o = is_equal;

  // Is greater equal
  always_comb begin
    if ((operand_a_i[31] ^ operand_b_i[31]) == 1'b0) begin
      is_greater_equal = (adder_result[31] == 1'b0);
    end else begin
      is_greater_equal = operand_a_i[31] ^ (cmp_signed);
    end
  end

  // GTE unsigned:
  // (a[31] == 1 && b[31] == 1) => adder_result[31] == 0
  // (a[31] == 0 && b[31] == 0) => adder_result[31] == 0
  // (a[31] == 1 && b[31] == 0) => 1
  // (a[31] == 0 && b[31] == 1) => 0

  // GTE signed:
  // (a[31] == 1 && b[31] == 1) => adder_result[31] == 0
  // (a[31] == 0 && b[31] == 0) => adder_result[31] == 0
  // (a[31] == 1 && b[31] == 0) => 0
  // (a[31] == 0 && b[31] == 1) => 1

  // generate comparison result
  logic cmp_result;

  always_comb begin
    unique case (operator_i)
      ALU_EQ:             cmp_result =  is_equal;
      ALU_NE:             cmp_result = ~is_equal;
      ALU_GE,   ALU_GEU,
      ALU_MAX,  ALU_MAXU: cmp_result = is_greater_equal; // RV32B only
      ALU_LT,   ALU_LTU,
      ALU_MIN,  ALU_MINU, //RV32B only
      ALU_SLT,  ALU_SLTU: cmp_result = ~is_greater_equal;

      default: cmp_result = is_equal;
    endcase
  end

  assign comparison_result_o = cmp_result;

  ///////////
  // Shift //
  ///////////

  // The shifter structure consists of a 33-bit shifter: 32-bit operand + 1 bit extension for
  // arithmetic shifts and one-shift support.
  // Rotations and funnel shifts are implemented as multi-cycle instructions.
  // The shifter is also used for single-bit instructions and bit-field place as detailed below.
  //
  // Standard Shifts
  // ===============
  // For standard shift instructions, the direction of the shift is to the right by default. For
  // left shifts, the signal shift_left signal is set. If so, the operand is initially reversed,
  // shifted to the right by the specified amount and shifted back again. For arithmetic- and
  // one-shifts the 33rd bit of the shifter operand can is set accordingly.
  //
  // Multicycle Shifts
  // =================
  //
  // Rotation
  // --------
  // For rotations, the operand signals operand_a_i and operand_b_i are kept constant to rs1 and
  // rs2 respectively.
  //
  // Rotation pseudocode:
  //   shift_amt = rs2 & 31;
  //   multicycle_result = (rs1 >> shift_amt) | (rs1 << (32 - shift_amt));
  //                       ^-- cycle 0 -----^ ^-- cycle 1 --------------^
  //
  // Funnel Shifts
  // -------------
  // For funnel shifs, operand_a_i is tied to rs1 in the first cycle and rs3 in the
  // second cycle. operand_b_i is always tied to rs2. The order of applying the shift amount or
  // its complement is determined by bit [5] of shift_amt.
  //
  // Funnel shift Pseudocode: (fsl)
  //  shift_amt = rs2 & 63;
  //  shift_amt_compl = 32 - shift_amt[4:0]
  //  if (shift_amt >=33):
  //     multicycle_result = (rs1 >> shift_amt_cmpl[4:0]) | (rs3 << shift_amt[4:0]);
  //                         ^-- cycle 0 ---------------^ ^-- cycle 1 ------------^
  //  else if (shift_amt <= 31 && shift_amt > 0):
  //     multicycle_result = (rs1 << shift_amt[4:0]) | (rs3 >> shift_amt_compl[4:0]);
  //                         ^-- cycle 0 ----------^ ^-- cycle 1 -------------------^
  //  For shift_amt == 0, 32, both shift_amt[4:0] and shift_amt_compl[4:0] == '0.
  //  these cases need to be handled separately outside the shifting structure:
  //  else if (shift_amt == 32):
  //     multicycle_result = rs3
  //  else if (shift_amt == 0):
  //     multicycle_result = rs1.
  //
  // Single-Bit Instructions
  // =======================
  // Single bit instructions operate on bit operand_b_i[4:0] of operand_a_i.

  // The operations sbset, sbclr and sbinv are implemented by generation of a bit-mask using the
  // shifter structure. This is done by left-shifting the operand 32'h1 by the required amount.
  // The signal shift_sbmode multiplexes the shifter input and sets the signal shift_left.
  // Further processing is taken care of by a separate structure.
  //
  // For sbext, the bit defined by operand_b_i[4:0] is to be returned. This is done by simply
  // shifting operand_a_i to the right by the required amount and returning bit [0] of the result.
  //
  // Bit-Field Place
  // ===============
  // The shifter structure is shared to compute bfp_mask << bfp_off.

  logic       shift_left;
  logic       shift_ones;
  logic       shift_arith;
  logic       shift_funnel;
  logic       shift_sbmode;
  logic [5:0] shift_amt;
  logic [5:0] shift_amt_compl; // complementary shift amount (32 - shift_amt)

  logic [31:0] shift_result;
  logic [32:0] shift_result_ext;
  logic [31:0] shift_result_rev;

  // zbf
  logic bfp_op;
  logic [4:0]  bfp_len;
  logic [4:0]  bfp_off;
  logic [31:0] bfp_mask;
  logic [31:0] bfp_mask_rev;
  logic [31:0] bfp_result;

  // bfp: shares the shifter structure to compute bfp_mask << bfp_off
  assign bfp_op = (RV32B != RV32BNone) ? (operator_i == ALU_BFP) : 1'b0;
  assign bfp_len = {~(|operand_b_i[27:24]), operand_b_i[27:24]}; // len = 0 encodes for len = 16
  assign bfp_off = operand_b_i[20:16];
  assign bfp_mask = (RV32B != RV32BNone) ? ~(32'hffff_ffff << bfp_len) : '0;
  for (genvar i=0; i<32; i++) begin : gen_rev_bfp_mask
    assign bfp_mask_rev[i] = bfp_mask[31-i];
  end

  assign bfp_result =(RV32B != RV32BNone) ?
      (~shift_result & operand_a_i) | ((operand_b_i & bfp_mask) << bfp_off) : '0;

  // bit shift_amt[5]: word swap bit: only considered for FSL/FSR.
  // if set, reverse operations in first and second cycle.
  assign shift_amt[5] = operand_b_i[5] & shift_funnel;
  assign shift_amt_compl = 32 - operand_b_i[4:0];

  always_comb begin
    if (bfp_op) begin
      shift_amt[4:0] = bfp_off ; // length field of bfp control word
    end else begin
      shift_amt[4:0] = instr_first_cycle_i ?
          (operand_b_i[5] && shift_funnel ? shift_amt_compl[4:0] : operand_b_i[4:0]) :
          (operand_b_i[5] && shift_funnel ? operand_b_i[4:0] : shift_amt_compl[4:0]);
    end
  end

  // single-bit mode: shift
  assign shift_sbmode = (RV32B != RV32BNone) ?
      (operator_i == ALU_SBSET) | (operator_i == ALU_SBCLR) | (operator_i == ALU_SBINV) : 1'b0;

  // left shift if this is:
  // * a standard left shift (slo, sll)
  // * a rol in the first cycle
  // * a ror in the second cycle
  // * fsl: without word-swap bit: first cycle, else: second cycle
  // * fsr: without word-swap bit: second cycle, else: first cycle
  // * a single-bit instruction: sbclr, sbset, sbinv (excluding sbext)
  // * bfp: bfp_mask << bfp_off
  always_comb begin
    unique case (operator_i)
      ALU_SLL: shift_left = 1'b1;
      ALU_SLO,
      ALU_BFP: shift_left = (RV32B != RV32BNone) ? 1'b1 : 1'b0;
      ALU_ROL: shift_left = (RV32B != RV32BNone) ? instr_first_cycle_i : 0;
      ALU_ROR: shift_left = (RV32B != RV32BNone) ? ~instr_first_cycle_i : 0;
      ALU_FSL: shift_left = (RV32B != RV32BNone) ?
        (shift_amt[5] ? ~instr_first_cycle_i : instr_first_cycle_i) : 1'b0;
      ALU_FSR: shift_left = (RV32B != RV32BNone) ?
          (shift_amt[5] ? instr_first_cycle_i : ~instr_first_cycle_i) : 1'b0;
      default: shift_left = 1'b0;
    endcase
    if (shift_sbmode) begin
      shift_left = 1'b1;
    end
  end

  assign shift_arith  = (operator_i == ALU_SRA);
  assign shift_ones   =
      (RV32B != RV32BNone) ? (operator_i == ALU_SLO) | (operator_i == ALU_SRO) : 1'b0;
  assign shift_funnel =
      (RV32B != RV32BNone) ? (operator_i == ALU_FSL) | (operator_i == ALU_FSR) : 1'b0;

  // shifter structure.
  always_comb begin
    // select shifter input
    // for bfp, sbmode and shift_left the corresponding bit-reversed input is chosen.
    if (RV32B == RV32BNone) begin
      shift_result = shift_left ? operand_a_rev : operand_a_i;
    end else begin
      unique case (1'b1)
        bfp_op:       shift_result = bfp_mask_rev;
        shift_sbmode: shift_result = 32'h8000_0000;
        default:      shift_result = shift_left ? operand_a_rev : operand_a_i;
      endcase
    end

    shift_result_ext =
        $signed({shift_ones | (shift_arith & shift_result[31]), shift_result}) >>> shift_amt[4:0];

    shift_result = shift_result_ext[31:0];

    for (int unsigned i=0; i<32; i++) begin
      shift_result_rev[i] = shift_result[31-i];
    end

    shift_result = shift_left ? shift_result_rev : shift_result;

  end

  ///////////////////
  // Bitwise Logic //
  ///////////////////

  logic bwlogic_or;
  logic bwlogic_and;
  logic [31:0] bwlogic_operand_b;
  logic [31:0] bwlogic_or_result;
  logic [31:0] bwlogic_and_result;
  logic [31:0] bwlogic_xor_result;
  logic [31:0] bwlogic_result;

  logic bwlogic_op_b_negate;

  always_comb begin
    unique case (operator_i)
      // Logic-with-negate OPs (RV32B Ops)
      ALU_XNOR,
      ALU_ORN,
      ALU_ANDN: bwlogic_op_b_negate = (RV32B != RV32BNone) ? 1'b1 : 1'b0;
      ALU_CMIX: bwlogic_op_b_negate = (RV32B != RV32BNone) ? ~instr_first_cycle_i : 1'b0;
      default:  bwlogic_op_b_negate = 1'b0;
    endcase
  end

  assign bwlogic_operand_b = bwlogic_op_b_negate ? operand_b_neg[32:1] : operand_b_i;

  assign bwlogic_or_result  = operand_a_i | bwlogic_operand_b;
  assign bwlogic_and_result = operand_a_i & bwlogic_operand_b;
  assign bwlogic_xor_result = operand_a_i ^ bwlogic_operand_b;

  assign bwlogic_or  = (operator_i == ALU_OR)  | (operator_i == ALU_ORN);
  assign bwlogic_and = (operator_i == ALU_AND) | (operator_i == ALU_ANDN);

  always_comb begin
    unique case (1'b1)
      bwlogic_or:  bwlogic_result = bwlogic_or_result;
      bwlogic_and: bwlogic_result = bwlogic_and_result;
      default:     bwlogic_result = bwlogic_xor_result;
    endcase
  end

  logic [5:0]  bitcnt_result;
  logic [31:0] minmax_result;
  logic [31:0] pack_result;
  logic [31:0] sext_result;
  logic [31:0] singlebit_result;
  logic [31:0] rev_result;
  logic [31:0] shuffle_result;
  logic [31:0] butterfly_result;
  logic [31:0] invbutterfly_result;
  logic [31:0] clmul_result;
  logic [31:0] multicycle_result;

  // RV32B result signals
  assign bitcnt_result       = '0;
  assign minmax_result       = '0;
  assign pack_result         = '0;
  assign sext_result         = '0;
  assign singlebit_result    = '0;
  assign rev_result          = '0;
  assign shuffle_result      = '0;
  assign butterfly_result    = '0;
  assign invbutterfly_result = '0;
  assign clmul_result        = '0;
  assign multicycle_result   = '0;
  // RV32B support signals
  assign imd_val_d_o         = '{default: '0};
  assign imd_val_we_o        = '{default: '0};

  ////////////////
  // Result mux //
  ////////////////

  always_comb begin
    result_o   = '0;

    unique case (operator_i)
      // Bitwise Logic Operations (negate: RV32B)
      ALU_XOR,  ALU_XNOR,
      ALU_OR,   ALU_ORN,
      ALU_AND,  ALU_ANDN: result_o = bwlogic_result;

      // Adder Operations
      ALU_ADD,  ALU_SUB: result_o = adder_result;

      // Shift Operations
      ALU_SLL,  ALU_SRL,
      ALU_SRA,
      // RV32B
      ALU_SLO,  ALU_SRO: result_o = shift_result;

      // Shuffle Operations (RV32B)
      ALU_SHFL, ALU_UNSHFL: result_o = shuffle_result;

      // Comparison Operations
      ALU_EQ,   ALU_NE,
      ALU_GE,   ALU_GEU,
      ALU_LT,   ALU_LTU,
      ALU_SLT,  ALU_SLTU: result_o = {31'h0,cmp_result};

      // MinMax Operations (RV32B)
      ALU_MIN,  ALU_MAX,
      ALU_MINU, ALU_MAXU: result_o = minmax_result;

      // Bitcount Operations (RV32B)
      ALU_CLZ, ALU_CTZ,
      ALU_PCNT: result_o = {26'h0, bitcnt_result};

      // Pack Operations (RV32B)
      ALU_PACK, ALU_PACKH,
      ALU_PACKU: result_o = pack_result;

      // Sign-Extend (RV32B)
      ALU_SEXTB, ALU_SEXTH: result_o = sext_result;

      // Ternary Bitmanip Operations (RV32B)
      ALU_CMIX, ALU_CMOV,
      ALU_FSL,  ALU_FSR,
      // Rotate Shift (RV32B)
      ALU_ROL, ALU_ROR,
      // Cyclic Redundancy Checks (RV32B)
      ALU_CRC32_W, ALU_CRC32C_W,
      ALU_CRC32_H, ALU_CRC32C_H,
      ALU_CRC32_B, ALU_CRC32C_B,
      // Bit Extract / Deposit (RV32B)
      ALU_BEXT, ALU_BDEP: result_o = multicycle_result;

      // Single-Bit Bitmanip Operations (RV32B)
      ALU_SBSET, ALU_SBCLR,
      ALU_SBINV, ALU_SBEXT: result_o = singlebit_result;

      // General Reverse / Or-combine (RV32B)
      ALU_GREV, ALU_GORC: result_o = rev_result;

      // Bit Field Place (RV32B)
      ALU_BFP: result_o = bfp_result;

      // Carry-less Multiply Operations (RV32B)
      ALU_CLMUL, ALU_CLMULR,
      ALU_CLMULH: result_o = clmul_result;

      default: ;
    endcase
  end

endmodule
