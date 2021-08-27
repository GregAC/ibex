// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <svdpi.h>

#include "cosim.h"
#include "spike_cosim.h"

extern "C" {
void* spike_cosim_init(svBitVecVal* start_pc, svBitVecVal* start_mtval) {
  SpikeCosim* cosim = new SpikeCosim(start_pc[0], start_mtval[0]);
  cosim->add_memory(0x0, 0x100000000);
  return static_cast<Cosim*>(cosim);
}

void spike_cosim_release(void* cosim_handle) {
  auto cosim = static_cast<Cosim*>(cosim_handle);

  delete cosim;
}
}
