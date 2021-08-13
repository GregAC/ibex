// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "spike_cosim.h"
#include "config.h"
#include "decode.h"
#include "devices.h"
#include "log_file.h"
#include "processor.h"
#include "simif.h"

#include <cassert>
#include <iostream>
#include <sstream>

SpikeCosim::SpikeCosim(uint32_t start_pc, uint32_t start_mtval) {
  log = std::make_unique<log_file_t>("spike_trace.log");

  processor = std::make_unique<processor_t>("RV32IMC", "MU", DEFAULT_VARCH,
                                            this, 0, false, log->get());

  processor->set_mmu_capability(IMPL_MMU_SBARE);
  processor->set_debug(true);
  processor->get_state()->pc = start_pc;
  processor->get_state()->mtvec = start_mtval;
  processor->enable_log_commits();
}

// always return nullptr so all memory accesses go via mmio_load/mmio_store
char *SpikeCosim::addr_to_mem(reg_t addr) { return nullptr; }

bool SpikeCosim::mmio_load(reg_t addr, size_t len, uint8_t *bytes, bool iside) {
  bool bus_error = !bus.load(addr, len, bytes);
  bool dut_error = false;

  if (!iside) {
    dut_error = check_mem_access(false, addr, len, bytes);
  }

  return !(bus_error | dut_error);
}

bool SpikeCosim::mmio_store(reg_t addr, size_t len, const uint8_t *bytes) {
  bool bus_error = !bus.store(addr, len, bytes);
  bool dut_error = check_mem_access(true, addr, len, bytes);

  return !(bus_error | dut_error);
}

void SpikeCosim::proc_reset(unsigned id) {}

const char *SpikeCosim::get_symbol(uint64_t addr) { return nullptr; }

void SpikeCosim::add_memory(uint32_t base_addr, size_t size) {
  auto new_mem = std::make_unique<mem_t>(size);
  bus.add_device(base_addr, new_mem.get());
  mems.emplace_back(std::move(new_mem));
}

bool SpikeCosim::backdoor_write_mem(uint32_t addr, size_t len,
                                    const uint8_t *data_in) {
  return bus.store(addr, len, data_in);
}

bool SpikeCosim::backdoor_read_mem(uint32_t addr, size_t len,
                                   uint8_t *data_out) {

  return bus.load(addr, len, data_out);
}

bool SpikeCosim::step(uint32_t write_reg, uint32_t write_reg_data,
                      uint32_t pc) {
  assert(write_reg < 32);

  // Execute the next instruction
  processor->step(1);

  int step_retries = 0;
  while (processor->get_state()->last_inst_pc == PC_INVALID) {
    // When a trap occurs no instruction will be execute and `last_inst_pc` will
    // be set to PC_INVALID. Rerun `step` until we execute a new instruction.
    processor->step(1);
    ++step_retries;

    if (step_retries > 2) {
      std::stringstream err_str;
      err_str << "Too many step retries, DUT PC: " << std::hex << pc << " iss PC: " << processor->get_state()->pc;
      errors.emplace_back(err_str.str());
    }
  }

  // Check PC of executed instruction matches the expected PC
  // TODO: Confirm details of why spike sign extends PC, something to do with
  // 32-bit address as 64-bit address must be sign extended?
  if ((processor->get_state()->last_inst_pc & 0xffffffff) != pc) {
    std::stringstream err_str;
    err_str << "PC mismatch, DUT: " << std::hex << pc
            << " expected: " << std::hex << processor->get_state()->last_inst_pc;
    errors.emplace_back(err_str.str());

    return false;
  }

  // Check register writes from executed instruction match what is expected
  auto &reg_changes = processor->get_state()->log_reg_write;

  bool gpr_write_seen = false;

  for (auto reg_change : reg_changes) {
    // reg_change.first provides register type in bottom 4 bits, then register
    // index above that

    // Ignore writes to x0
    if (reg_change.first == 0)
      continue;

    if ((reg_change.first & 0xf) == 0) {
      // register is GPR
      // should never see more than one GPR write per step
      assert(!gpr_write_seen);
      int cosim_write_reg = reg_change.first >> 4;

      if (write_reg == 0) {
        std::stringstream err_str;
        err_str << "DUT didn't write register, but one was expected to x"
                << std::dec << cosim_write_reg;
        errors.emplace_back(err_str.str());

        return false;
      }

      if (write_reg != cosim_write_reg) {
        std::stringstream err_str;
        err_str << "Register write index mismatch, DUT: x" << std::dec
                << write_reg << " expected: x" << cosim_write_reg;
        errors.emplace_back(err_str.str());

        return false;
      }

      uint32_t cosim_write_reg_data =
          static_cast<uint32_t>(reg_change.second.v[0]);

      if (write_reg_data != cosim_write_reg_data) {
        std::stringstream err_str;
        err_str << "Register write data mismatch to x" << std::dec
                << cosim_write_reg << " DUT: " << std::hex << write_reg_data
                << " expected: " << std::hex << cosim_write_reg_data;
        errors.emplace_back(err_str.str());

        return false;
      }

      gpr_write_seen = true;
    } else if ((reg_change.first & 0xf) == 4) {
      int cosim_write_csr = (reg_change.first >> 4) & 0xfff;

      uint32_t cosim_write_csr_data =
          static_cast<uint32_t>(reg_change.second.v[0]);

      // Spike and Ibex have different WARL behaviours so after any CSR write
      // check the fields and adjust to match Ibex behaviour.
      fixup_csr(cosim_write_csr, cosim_write_csr_data);
    } else {
      // should never see other types
      assert(false);
    }
  }

  if (write_reg != 0 && !gpr_write_seen) {
    std::stringstream err_str;
    err_str << "DUT wrote register x" << std::dec << write_reg
            << " but a write was not expected" << std::endl;
    errors.emplace_back(err_str.str());

    return false;
  }

  return errors.size() == 0;
}

void SpikeCosim::set_mip(uint32_t mip) {
  // TODO: How to deal with NMI? Spike doesn't support it
  processor->get_state()->mip = mip;
}

void SpikeCosim::set_debug_req(bool debug_req) {
  processor->halt_request =
      debug_req ? processor_t::HR_REGULAR : processor_t::HR_NONE;
}

// TODO: Just make struct public and have this take a struct, getting too many
// arguments.
void SpikeCosim::notify_dside_access(bool store, uint32_t addr, uint32_t data,
                                     uint32_t be, bool error, bool misaligned_first,
                                     bool misaligned_second) {
  pending_dside_accesses.emplace_back(PendingMemAccess{.store = store, .error = error,
    .misaligned_first = misaligned_first, .misaligned_second = misaligned_second, .addr = addr, .data = data, .be_dut = be,
    .be_spike = 0});
}

const std::vector<std::string>& SpikeCosim::get_errors() { return errors; }

void SpikeCosim::clear_errors() { errors.clear(); }

void SpikeCosim::fixup_csr(int csr_num, uint32_t csr_val) {
  switch (csr_num) {
    case CSR_MSTATUS:
      reg_t mask = MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPRV | MSTATUS_MPP |
        MSTATUS_TW;

      reg_t new_val = csr_val & mask;
      processor->set_csr(csr_num, new_val);
      break;
  }
}

bool SpikeCosim::check_mem_access(bool store, uint32_t addr, size_t len,
                                  const uint8_t* bytes) {
  assert(len >= 1 && len <= 4);
  // Expect that no spike memory accesses cross a 32-bit boundary
  assert(((addr + (len - 1)) & 0xfffffffc) == (addr & 0xfffffffc));

  std::string iss_action = store ? "store" : "load";

  if (pending_dside_accesses.size() == 0) {
    std::stringstream err_str;
    err_str << "A " << iss_action << " at address " << std::hex << addr <<
      " was expected but there are no pending accesses";
    errors.emplace_back(err_str.str());

    return false;
  }

  auto& top_pending_access = pending_dside_accesses.front();

  std::string dut_action = top_pending_access.store ? "store" : "load";

  uint32_t aligned_addr = addr & 0xfffffffc;
  if (aligned_addr != top_pending_access.addr) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at address " << std::hex
      << top_pending_access.addr << " but " << iss_action << " at address "
      << aligned_addr << " was expected";
    errors.emplace_back(err_str.str());

    return false;
  }

  if (store != top_pending_access.store) {
    std::stringstream err_str;
    err_str << "DUT generated " << dut_action << " at addr " << std::hex
      << top_pending_access.addr << " but a " << iss_action << " was expected";
    errors.emplace_back(err_str.str());

    return false;
  }

  uint32_t expected_be = ((1 << len) - 1) << (addr & 0x3);

  bool pending_access_done = false;
  bool misaligned = top_pending_access.misaligned_first ||
    top_pending_access.misaligned_second;

  if (misaligned) {
    if ((expected_be & top_pending_access.be_spike) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
        << top_pending_access.addr << " with BE " << top_pending_access.be_dut
        << " and expected BE " << expected_be
        << " has been seen twice, so far seen " << top_pending_access.be_spike;

      errors.emplace_back(err_str.str());

      return false;
    }

    if ((expected_be & ~top_pending_access.be_dut) != 0) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
        << top_pending_access.addr << " with BE " << top_pending_access.be_dut
        << " but expected BE " << expected_be << " has other bytes enabled";
      errors.emplace_back(err_str.str());
      return false;
    }

    top_pending_access.be_spike |= expected_be;

    if (top_pending_access.be_spike == top_pending_access.be_dut) {
      pending_access_done = true;
    }
  } else {
    if (expected_be != top_pending_access.be_dut) {
      std::stringstream err_str;
      err_str << "DUT generated " << dut_action << " at address " << std::hex
        << top_pending_access.addr << " with BE " << top_pending_access.be_dut << " but BE "
        << expected_be << " was expected";
      errors.emplace_back(err_str.str());

      return false;
    }

    pending_access_done = true;
  }

  // Data is ignored on error responses to loads so don't check it
  if (store || !top_pending_access.error) {
    uint32_t expected_data = 0;
    for (int i = 0; i < len; ++i) {
      expected_data |= bytes[i] << (i * 8);
    }

    expected_data <<= (addr & 0x3) * 8;

    uint32_t expected_be_bits = (((uint64_t)1 << (len * 8)) - 1) << ((addr & 0x3) * 8);
    uint32_t masked_dut_data = top_pending_access.data & expected_be_bits;

    if (expected_data != masked_dut_data) {
      std::stringstream err_str;
      err_str << "DUT generated " << iss_action << " at address " << std::hex
        << top_pending_access.addr << " with data " << masked_dut_data << " but data "
        << expected_data << " was expected with byte mask " << expected_be;

      errors.emplace_back(err_str.str());

      return false;
    }
  }

  bool pending_access_error = top_pending_access.error;

  if (pending_access_error && misaligned) {
    if (top_pending_access.misaligned_first) {
      if (top_pending_access.be_dut & 0x8) {
        if ((pending_dside_accesses.size() < 2) || !pending_dside_accesses[1].misaligned_second) {
          std::stringstream err_str;
          err_str << "DUT generated first half of misaligned " << iss_action
            << " at address " << std::hex << top_pending_access.addr
            << " but second half was expected and not seen";

          errors.emplace_back(err_str.str());

          return false;
        }

        if (pending_dside_accesses[1].addr != (top_pending_access.addr + 4)) {
          std::stringstream err_str;
          err_str << "DUT generated first half of misaligned " << iss_action
            << " at address " << std::hex << top_pending_access.addr
            << " but second half had incorrect address "
            << pending_dside_accesses[1].addr;

          errors.emplace_back(err_str.str());

          return false;
        }

        //TODO: How to check BE? May need length of transaction?

        pending_dside_accesses.erase(pending_dside_accesses.begin());
      }
    }

    pending_access_done = true;
  }

  if (pending_access_done) {
    pending_dside_accesses.erase(pending_dside_accesses.begin());
  }

  return pending_access_error;
}
