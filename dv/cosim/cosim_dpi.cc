// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <svdpi.h>

#include "cosim.h"
#include "cosim_dpi.h"

int riscv_cosim_step(void *cosim_handle, const svBitVecVal *write_reg,
                     const svBitVecVal *write_reg_data, const svBitVecVal *pc) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  return cosim->step(write_reg[0], write_reg_data[0], pc[0]) ? 1 : 0;
}

void riscv_cosim_set_mip(void *cosim_handle, const svBitVecVal *mip) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  cosim->set_mip(mip[0]);
}

void riscv_cosim_set_debug_req(void *cosim_handle, svBit debug_req) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  cosim->set_debug_req(debug_req);
}

void riscv_cosim_notify_dside_access(void* cosim_handle, svBit store, svBitVecVal* addr, svBitVecVal* data, svBitVecVal* be, svBit error, svBit misaligned_first, svBit misaligned_second) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  cosim->notify_dside_access(store, addr[0], data[0], be[0], error, misaligned_first, misaligned_second);
}

void riscv_cosim_notify_iside_err(void* cosim_handle, svBitVecVal* addr) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  cosim->notify_iside_err(addr[0]);
}

int riscv_cosim_get_num_errs(void *cosim_handle) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  return cosim->get_errors().size();
}

const char *riscv_cosim_get_err(void *cosim_handle, int index) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  if (index >= cosim->get_errors().size()) {
    return nullptr;
  }

  return cosim->get_errors()[index].c_str();
}

void riscv_cosim_clear_errs(void *cosim_handle) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  cosim->clear_errors();
}

void riscv_cosim_write_mem_byte(void* cosim_handle, const svBitVecVal *addr, const svBitVecVal *d) {
  auto cosim = static_cast<Cosim *>(cosim_handle);
  cosim->backdoor_write_mem(addr[0], 1, (const uint8_t*)(&d[0]));
}
