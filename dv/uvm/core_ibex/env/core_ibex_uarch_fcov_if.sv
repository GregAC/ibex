// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

interface core_ibex_uarch_fcov_if (
  input clk
);

  logic        valid_if;
  logic        valid_id;
  logic        valid_wb;

  logic [31:0] instr_id;

  logic        stall_id_ld_hz;
  logic        stall_id_mem;
  logic        stall_id_multdiv;
  logic        stall_id_branch;
  logic        stall_id_jump;

  clocking fcov_cb @(posedge clk);
    input valid_if;
    input valid_id;
    input valid_wb;
    input instr_id;
    input stall_id_ld_hz;
    input stall_id_mem;
    input stall_id_multdiv;
    input stall_id_branch;
    input stall_id_jump;
  endclocking

endinterface
