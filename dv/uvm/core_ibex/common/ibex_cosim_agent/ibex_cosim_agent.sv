// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

import "DPI-C" function void riscv_cosim_write_mem_byte(chandle cosim_handle, bit [31:0] addr, bit [7:0] d);

class ibex_cosim_agent extends uvm_agent;
  ibex_instr_monitor instr_monitor;
  ibex_cosim_scoreboard scoreboard;

  uvm_analysis_export#(ibex_mem_intf_seq_item) dmem_port;
  uvm_analysis_export#(ibex_mem_intf_seq_item) imem_port;

  `uvm_component_utils(ibex_cosim_agent)

  function new(string name="", uvm_component parent=null);
    super.new(name, parent);

    dmem_port = new("dmem_port", this);
    imem_port = new("imem_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    instr_monitor = ibex_instr_monitor::type_id::create("instr_monitor", this);
    scoreboard = ibex_cosim_scoreboard::type_id::create("scoreboard", this);
  endfunction: build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    instr_monitor.item_collected_port.connect(scoreboard.instr_port.analysis_export);
    dmem_port.connect(scoreboard.dmem_port.analysis_export);
    imem_port.connect(scoreboard.imem_port.analysis_export);
  endfunction: connect_phase

  function void write_mem_byte(bit [31:0] addr, bit [7:0] d);
    riscv_cosim_write_mem_byte(scoreboard.cosim_handle, addr, d);
  endfunction
endclass : ibex_cosim_agent
