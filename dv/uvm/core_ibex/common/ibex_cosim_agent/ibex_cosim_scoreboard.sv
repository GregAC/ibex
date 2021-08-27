// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

import "DPI-C" function chandle spike_cosim_init(bit [31:0] start_pc, bit [31:0] start_mtvec);
import "DPI-C" function void spike_cosim_release(chandle cosim_handle);

import "DPI-C" function int riscv_cosim_step(chandle cosim_handle, bit [4:0] write_reg, bit [31:0] write_reg_data, bit [31:0] pc);
import "DPI-C" function void riscv_cosim_set_mip(chandle cosim_handle, bit [31:0] mip);
import "DPI-C" function void riscv_cosim_set_nmi(chandle cosim_handle, bit nmi);
import "DPI-C" function void riscv_cosim_set_debug_req(chandle cosim_handle, bit debug_req);
import "DPI-C" function void riscv_cosim_set_mcycle(chandle cosim_handle, bit [63:0]);
import "DPI-C" function void riscv_cosim_notify_dside_access(chandle cosim_handle, bit store, bit [31:0] addr, bit [31:0] data, bit [3:0] be, bit error, bit misaligned_first, bit misaligned_second);
import "DPI-C" function void riscv_cosim_notify_iside_err(chandle cosim_handle, bit [31:0] addr);
import "DPI-C" function int riscv_cosim_get_num_errs(chandle cosim_handle);
import "DPI-C" function string riscv_cosim_get_err(chandle cosim_handle, int index);
import "DPI-C" function void riscv_cosim_clear_errs(chandle cosim_handle);
import "DPI-C" function void riscv_cosim_write_mem_byte(chandle cosim_handle, bit [31:0] addr, bit [7:0] d);

class ibex_cosim_scoreboard extends uvm_scoreboard;
  chandle cosim_handle;
  int instr_cnt;

  core_ibex_cosim_cfg cfg;

  uvm_tlm_analysis_fifo #(ibex_instr_seq_item) instr_port;
  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item) dmem_port;
  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item) imem_port;

  virtual core_ibex_instr_monitor_if              instr_vif;

  bit failed_iside_accesses [bit[31:0]];

  typedef struct {
    bit [63:0] order;
    bit [31:0] addr;
  } iside_err_t;

  iside_err_t iside_err_queue [$];

  `uvm_component_utils(ibex_cosim_scoreboard)

  function new(string name="", uvm_component parent=null);
    super.new(name, parent);

    instr_port = new("instr_port", this);
    dmem_port = new("dmem_port", this);
    imem_port = new("imem_port", this);
    instr_cnt = 0;
    cosim_handle = null;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(core_ibex_cosim_cfg)::get(this, "", "cosim_cfg", cfg)) begin
      `uvm_fatal(get_full_name(), "Cannot get cosim configuration")
    end

    if (!uvm_config_db#(virtual core_ibex_instr_monitor_if)::get(null, "",
                                                                 "instr_monitor_if",
                                                                 instr_vif)) begin
      `uvm_fatal(`gfn, "Cannot get instr_monitor_if")
    end

    cosim_handle = spike_cosim_init(cfg.start_pc, cfg.start_mtvec);

    if (cosim_handle == null) begin
      `uvm_fatal(get_full_name(), "Could not initialise cosim")
    end
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    wait (instr_vif.instr_cb.reset === 1'b0);

    forever begin
      fork
        run_cosim_instr();
        run_cosim_dmem();
        run_cosim_imem();
        run_cosim_imem_errs();
        wait (instr_vif.instr_cb.reset === 1'b1);
      join_any
      disable fork;
      handle_reset();
    end
  endtask : run_phase

  task run_cosim_instr();
    ibex_instr_seq_item instr;

    forever begin
      instr_port.get(instr);

      while (iside_err_queue.size() > 0 && iside_err_queue[0].order < instr.order) begin
        iside_err_queue.pop_front();
      end

      if (iside_err_queue.size() !=0 && iside_err_queue[0].order == instr.order) begin
        riscv_cosim_notify_iside_err(cosim_handle, iside_err_queue[0].addr);
        iside_err_queue.pop_front();
      end

      if (!instr.trap) begin
        riscv_cosim_set_nmi(cosim_handle, instr.nmi);
        riscv_cosim_set_mip(cosim_handle, instr.mip);
        riscv_cosim_set_debug_req(cosim_handle, instr.debug_req);
        riscv_cosim_set_mcycle(cosim_handle, instr.mcycle);

        if (!riscv_cosim_step(cosim_handle, instr.rd_addr, instr.rd_wdata, instr.pc)) begin
          `uvm_fatal(get_full_name(), get_cosim_error_str())
        end

        instr_cnt += 1;
      end
    end
  endtask: run_cosim_instr

  task run_cosim_dmem();
    ibex_mem_intf_seq_item mem_op;

    forever begin
      dmem_port.get(mem_op);

      riscv_cosim_notify_dside_access(cosim_handle, mem_op.read_write == WRITE, mem_op.addr,
        mem_op.read_write == WRITE ? mem_op.wdata : mem_op.rdata, mem_op.be, mem_op.error,
        mem_op.misaligned_first, mem_op.misaligned_second);
    end
  endtask: run_cosim_dmem

  task run_cosim_imem();
    ibex_mem_intf_seq_item mem_op;

    forever begin
      imem_port.get(mem_op);
      if (mem_op.error) begin
        `uvm_info(get_full_name(), $sformatf("Seen iside error: %x", mem_op.addr), UVM_HIGH);
        failed_iside_accesses[mem_op.addr] = 1'b1;
      end else begin
        if (failed_iside_accesses.exists(mem_op.addr)) begin
          `uvm_info(get_full_name(), $sformatf("Removing iside error: %x", mem_op.addr), UVM_HIGH);
          failed_iside_accesses.delete(mem_op.addr);
        end
      end
    end
  endtask: run_cosim_imem

  task run_cosim_imem_errs();
    bit [63:0] latest_order = 64'hffffffff_ffffffff;
    bit [31:0] aligned_addr;
    bit [31:0] aligned_addr_cross;
    bit test_word_cross;
    forever begin
      wait (instr_vif.instr_cb.valid_id && latest_order != instr_vif.instr_cb.rvfi_order_id);

      test_word_cross = !instr_vif.instr_cb.is_compressed_id && (instr_vif.instr_cb.pc_id & 32'h3);

      aligned_addr = instr_vif.instr_cb.pc_id & 32'hfffffffc;

      `uvm_info(get_full_name, $sformatf("Order: %d at aligned pc: %x", instr_vif.instr_cb.rvfi_order_id, aligned_addr), UVM_HIGH)
      if (test_word_cross) begin
        aligned_addr_cross = (instr_vif.instr_cb.pc_id + 32'd4) & 32'hfffffffc;
        `uvm_info(get_full_name, $sformatf("Order: %d crosses aligned pc: %x", instr_vif.instr_cb.rvfi_order_id, aligned_addr_cross), UVM_HIGH)
      end

      if (failed_iside_accesses.exists(instr_vif.instr_cb.pc_id & 32'hfffffffc)) begin
        `uvm_info(get_full_name(), $sformatf("Should see iside error on order id %d, addr: %x", instr_vif.instr_cb.rvfi_order_id, instr_vif.instr_cb.pc_id & 32'hfffffffc), UVM_HIGH);
        iside_err_queue.push_back('{order : instr_vif.instr_cb.rvfi_order_id,
                                    addr  : instr_vif.instr_cb.pc_id & 32'hfffffffc});
      end else if (!instr_vif.instr_cb.is_compressed_id &&
                   (instr_vif.instr_cb.pc_id & 32'h3) != 0 &&
                   failed_iside_accesses.exists((instr_vif.instr_cb.pc_id + 32'd4) & 32'hfffffffc)) begin
        `uvm_info(get_full_name(), $sformatf("Should see iside error (2) on order id %d, addr: %x", instr_vif.instr_cb.rvfi_order_id, instr_vif.instr_cb.pc_id & 32'hfffffffc), UVM_HIGH);
        iside_err_queue.push_back('{order : instr_vif.instr_cb.rvfi_order_id,
                                    addr  : (instr_vif.instr_cb.pc_id + 32'd4) & 32'hfffffffc});
      end

      latest_order = instr_vif.instr_cb.rvfi_order_id;
    end
  endtask: run_cosim_imem_errs;

  function string get_cosim_error_str();
      string error = $sformatf("Cosim mismatch at instruction %d: ", instr_cnt);
      for (int i = 0;i < riscv_cosim_get_num_errs(cosim_handle); ++i) begin
        error = {error, riscv_cosim_get_err(cosim_handle, i), "\n"};
      end
      riscv_cosim_clear_errs(cosim_handle);

      return error;
  endfunction : get_cosim_error_str

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);

    if (cosim_handle) begin
      spike_cosim_release(cosim_handle);
    end
  endfunction : final_phase

  task handle_reset();
    if (cosim_handle) begin
      spike_cosim_release(cosim_handle);
    end

    cosim_handle = spike_cosim_init(cfg.start_pc, cfg.start_mtvec);
    wait (instr_vif.instr_cb.reset === 1'b0);
  endtask
endclass : ibex_cosim_scoreboard
