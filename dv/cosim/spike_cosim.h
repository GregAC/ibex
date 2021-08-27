// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SPIKE_COSIM_H_
#define SPIKE_COSIM_H_

#include "cosim.h"
#include "devices.h"
#include "log_file.h"
#include "processor.h"
#include "simif.h"

#include <stdint.h>
#include <memory>
#include <string>
#include <vector>
#include <deque>

class SpikeCosim : public simif_t, public Cosim {
 private:
  std::unique_ptr<processor_t> processor;
  std::unique_ptr<log_file_t> log;
  bus_t bus;
  std::vector<std::unique_ptr<mem_t>> mems;
  std::vector<std::string> errors;

  void fixup_csr(int csr_num, uint32_t csr_val);

  struct PendingMemAccess {
    bool store;
    bool error;
    bool misaligned_first;
    bool misaligned_second;
    uint32_t addr;
    uint32_t data;
    uint32_t be_dut;
    uint32_t be_spike;
  };

  std::vector<PendingMemAccess> pending_dside_accesses;

  bool pending_iside_err;
  uint32_t pending_iside_err_addr;

  bool check_mem_access(bool store, uint32_t addr, size_t len,
                        const uint8_t* bytes);
 public:
  SpikeCosim(uint32_t start_pc, uint32_t start_mtval);

  // simif_t implementation
  virtual char *addr_to_mem(reg_t addr) override;
  virtual bool mmio_load(reg_t addr, size_t len, uint8_t *bytes, bool iside) override;
  virtual bool mmio_store(reg_t addr, size_t len,
                          const uint8_t *bytes) override;
  virtual void proc_reset(unsigned id) override;
  virtual const char *get_symbol(uint64_t addr) override;

  // Cosim implementation
  void add_memory(uint32_t base_addr, size_t size) override;
  bool backdoor_write_mem(uint32_t addr, size_t len,
                          const uint8_t *data_in) override;
  bool backdoor_read_mem(uint32_t addr, size_t len, uint8_t *data_out) override;
  bool step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc) override;
  void set_mip(uint32_t mip) override;
  void set_nmi(bool nmi) override;
  void set_debug_req(bool debug_req) override;
  void set_mcycle(uint64_t mcycle) override;
  void notify_dside_access(bool store, uint32_t addr, uint32_t data,
                           uint32_t be, bool error, bool misaligned_first,
                           bool misaligned_second) override;
  void notify_iside_err(uint32_t addr) override;
  const std::vector<std::string> &get_errors() override;
  void clear_errors() override;

  bool seen_nmi;
};

#endif // SPIKE_COSIM_H_
