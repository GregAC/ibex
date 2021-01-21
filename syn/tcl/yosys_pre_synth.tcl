# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

source ./tcl/yosys_common.tcl

if { $lr_synth_flatten } {
  set flatten_opt "-flatten"
} else {
  set flatten_opt ""
}

if { $lr_synth_timing_run } {
  write_sdc_out $lr_synth_sdc_file_in $lr_synth_sdc_file_out
}

yosys "read_verilog -sv ./rtl/prim_clock_gating.v $lr_synth_out_dir/generated/*.v"

if { $lr_synth_ibex_branch_target_alu } {
  yosys "chparam -set BranchTargetALU 1 ibex_core"
}

if { $lr_synth_ibex_writeback_stage } {
  yosys "chparam -set WritebackStage 1 ibex_core"
}

yosys "chparam -set RV32B $lr_synth_ibex_bitmanip ibex_core"

yosys "chparam -set RV32M $lr_synth_ibex_multiplier ibex_core"

yosys "chparam -set RegFile $lr_synth_ibex_regfile ibex_core"

yosys "hierarchy -check -top $lr_synth_top_module"

yosys "proc"

yosys "flatten"

yosys "cd ibex_core"

yosys "shell"
