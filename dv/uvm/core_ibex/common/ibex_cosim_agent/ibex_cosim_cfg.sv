// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class core_ibex_cosim_cfg extends uvm_object;
  bit [31:0] start_pc;
  bit [31:0] start_mtvec;

  `uvm_object_utils_begin(core_ibex_cosim_cfg)
    `uvm_field_int(start_pc,    UVM_DEFAULT)
    `uvm_field_int(start_mtvec, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass
