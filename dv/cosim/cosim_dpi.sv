// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

import "DPI-C" function int riscv_cosim_step(chandle cosim_handle, bit [4:0] write_reg, bit [31:0] write_reg_data, bit [31:0] pc);
import "DPI-C" function void riscv_cosim_set_mip(chandle cosim_handle, bit [31:0] mip);
import "DPI-C" function void riscv_cosim_set_nmi(chandle cosim_handle, bit nmi);
import "DPI-C" function void riscv_cosim_set_debug_req(chandle cosim_handle, bit debug_req);
import "DPI-C" function void riscv_cosim_notify_dside_access(chandle cosim_handle, bit store, bit [31:0] addr, bit [31:0] data, bit [3:0] be, bit error, bit misaligned_first, bit misaligned_second);
import "DPI-C" function int riscv_cosim_get_num_errs(chandle cosim_handle);
import "DPI-C" function string riscv_cosim_get_err(chandle cosim_handle, int index);
import "DPI-C" function void riscv_cosim_clear_errs(chandle cosim_handle);
import "DPI-C" function void riscv_cosim_write_mem_byte(chandle cosim_handle, bit [31:0] addr, bit [7:0] d);
