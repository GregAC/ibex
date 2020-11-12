// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Boot address specified in decimal to avoid single quote in number, which
// causes parsing errors of this file in Riviera.
+define+BOOT_ADDR=2147483648 // 32'h8000_0000
+define+TRACE_EXECUTION
+define+RVFI
+define+DV_FCOV

// Shared lowRISC code
+incdir+${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl
+incdir+${PRJ_DIR}/rtl/fcov_macro_test.svh
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_assert.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_lfsr.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_28_22_enc.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_28_22_dec.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_39_32_enc.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_39_32_dec.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_72_64_enc.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim/rtl/prim_secded_72_64_dec.sv

// Until this list is generated by FuseSoC, we have to use manually generated
// wrappers around the prim_* modules to instantiate the prim_generic_* ones,
// see https://github.com/lowRISC/ibex/issues/893.
${PRJ_DIR}/dv/uvm/core_ibex/common/prim/prim_pkg.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim_generic/rtl/prim_generic_ram_1p.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/prim/prim_ram_1p.sv
${PRJ_DIR}/vendor/lowrisc_ip/prim_generic/rtl/prim_generic_clock_gating.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/prim/prim_clock_gating.sv

// ibex CORE RTL files
+incdir+${PRJ_DIR}/rtl
${PRJ_DIR}/rtl/ibex_pkg.sv
${PRJ_DIR}/rtl/ibex_tracer_pkg.sv
${PRJ_DIR}/rtl/ibex_tracer.sv
${PRJ_DIR}/rtl/ibex_alu.sv
${PRJ_DIR}/rtl/ibex_branch_predict.sv
${PRJ_DIR}/rtl/ibex_compressed_decoder.sv
${PRJ_DIR}/rtl/ibex_controller.sv
${PRJ_DIR}/rtl/ibex_cs_registers.sv
${PRJ_DIR}/rtl/ibex_counter.sv
${PRJ_DIR}/rtl/ibex_decoder.sv
${PRJ_DIR}/rtl/ibex_dummy_instr.sv
${PRJ_DIR}/rtl/ibex_ex_block.sv
${PRJ_DIR}/rtl/ibex_wb_stage.sv
${PRJ_DIR}/rtl/ibex_id_stage.sv
${PRJ_DIR}/rtl/ibex_icache.sv
${PRJ_DIR}/rtl/ibex_if_stage.sv
${PRJ_DIR}/rtl/ibex_load_store_unit.sv
${PRJ_DIR}/rtl/ibex_multdiv_slow.sv
${PRJ_DIR}/rtl/ibex_multdiv_fast.sv
${PRJ_DIR}/rtl/ibex_prefetch_buffer.sv
${PRJ_DIR}/rtl/ibex_fetch_fifo.sv
${PRJ_DIR}/rtl/ibex_register_file_ff.sv
${PRJ_DIR}/rtl/ibex_register_file_fpga.sv
${PRJ_DIR}/rtl/ibex_register_file_latch.sv
${PRJ_DIR}/rtl/ibex_pmp.sv
${PRJ_DIR}/rtl/ibex_core.sv
${PRJ_DIR}/rtl/ibex_core_tracing.sv

// Core DV files
${PRJ_DIR}/vendor/google_riscv-dv/src/riscv_signature_pkg.sv
+incdir+${PRJ_DIR}/dv/uvm/core_ibex/env
+incdir+${PRJ_DIR}/dv/uvm/core_ibex/tests
+incdir+${PRJ_DIR}/dv/uvm/core_ibex/common/ibex_mem_intf_agent
+incdir+${PRJ_DIR}/dv/uvm/core_ibex/common/irq_agent
+incdir+${PRJ_DIR}/vendor/lowrisc_ip/mem_model
+incdir+${PRJ_DIR}/vendor/lowrisc_ip/dv_utils
${PRJ_DIR}/dv/uvm/bus_params_pkg/bus_params_pkg.sv
${PRJ_DIR}/vendor/lowrisc_ip/common_ifs/clk_rst_if.sv
${PRJ_DIR}/vendor/lowrisc_ip/common_ifs/pins_if.sv
${PRJ_DIR}/vendor/lowrisc_ip/dv_utils/dv_utils_pkg.sv
${PRJ_DIR}/vendor/lowrisc_ip/mem_model/mem_model_pkg.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/ibex_mem_intf_agent/ibex_mem_intf.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/ibex_mem_intf_agent/ibex_mem_intf_agent_pkg.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/irq_agent/irq_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/common/irq_agent/irq_agent_pkg.sv
${PRJ_DIR}/dv/uvm/core_ibex/env/core_ibex_instr_monitor_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/env/core_ibex_dut_probe_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/env/core_ibex_rvfi_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/env/core_ibex_csr_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/env/core_ibex_env_pkg.sv
${PRJ_DIR}/dv/uvm/core_ibex/tests/core_ibex_test_pkg.sv
${PRJ_DIR}/dv/uvm/core_ibex/fcov/core_ibex_fcov_if.sv
${PRJ_DIR}/dv/uvm/core_ibex/fcov/core_ibex_fcov_bind.sv
${PRJ_DIR}/dv/uvm/core_ibex/tb/core_ibex_tb_top.sv
