// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simple_system_common.h"
#include "pmp.h"


#define MCAUSE_INSN_ACCESS 1
#define MCAUSE_READ_ACCESS 5
#define MCAUSE_WRITE_ACCESS 7
#define MCAUSE_ECALL_U 8
#define MCAUSE_ECALL_M 11

#define ECALL_ENTER_UMODE 0
#define ECALL_ENTER_MMODE 1

bool exception_expected = false;
bool exception_seen = false;
bool exception_error = false;
uintptr_t expected_fault_addr = 0;
uint32_t expected_mcause = 0;

pmp_region_index_t  pmp_test_region;
pmp_region_config_t pmp_test_allow_config;

typedef enum {
  kPrivLevelU = 0,
  kPrivLevelS = 1,
  kPrivLevelM = 3
} priv_level_t;

void set_mstatus_mpp(priv_level_t priv_level) {
  uint32_t mstatus = get_mstatus();

  mstatus = (mstatus & 0xFFFFE7FF) | (priv_level << 11);

  set_mstatus(mstatus);
}

void inc_mepc() {
  uint32_t mepc = get_mepc();
  mepc += 4;
  set_mepc(mepc);
}

void handle_ecall(uint32_t arg) {
  if (arg == ECALL_ENTER_UMODE) {
    set_mstatus_mpp(kPrivLevelU);
  } else if (arg == ECALL_ENTER_MMODE) {
    set_mstatus_mpp(kPrivLevelM);
  } else {
    puts("FAIL\nUnexpected ecall arg ");
    puthex(arg);
    sim_halt();
  }

  inc_mepc();
}

void default_exc_handler(void) __attribute__((interrupt));
void default_exc_handler(void) {
  // Grab a0 register before anything can clobber it
  register volatile uint32_t a0 asm ("a0");
  uint32_t ecall_arg = a0;

  uint32_t mcause = get_mcause();
  uint32_t mtval = get_mtval();

  if ((mcause == MCAUSE_ECALL_U) || (mcause == MCAUSE_ECALL_M)) {
    handle_ecall(ecall_arg);
  } else if (exception_expected) {
    exception_expected = false;

    if (mcause != expected_mcause) {
      puts("FAIL\nUnexpected MCAUSE\nExpected: ");
      puthex(expected_mcause);
      puts("\n");
      exception_error = true;
    } else if (mtval != (uint32_t)expected_fault_addr) {
      puts("FAIL\nUnexpected fault address (MTVAL)\nExpected: ");
      puthex((uint32_t)expected_fault_addr);
      puts("\n");
      exception_error = true;
    }

    exception_seen = true;

    pmp_region_configure_na4_result_t configure_result;
    configure_result = pmp_region_configure_na4(pmp_test_region,
        pmp_test_allow_config, expected_fault_addr);

    if (configure_result != kPmpRegionConfigureNa4Ok) {
      puts("FAIL\nFailure to configure PMP in default_exc_handler ");
      puthex(configure_result);
      sim_halt();
    }
  } else {
    puts("FAIL\nUnexpected exception!\n");
    simple_exc_handler();
  }
}

void enable_rlb(bool enable) {
  if (enable) {
    asm ("csrsi 0x390, 0x4");
  } else {
    asm ("csrci 0x390, 0x4");
  }
}

void enable_mml() {
  asm ("csrsi 0x390, 0x1");
}

bool switch_privledge_level(priv_level_t level) {
  register uint32_t a0 asm("a0");

  if (level == kPrivLevelU) {
    a0 = ECALL_ENTER_UMODE;
  } else if (level == kPrivLevelM) {
    a0 = ECALL_ENTER_MMODE;
  } else {
    return false;
  }

  asm volatile("ecall" : : "r"(a0));

  return true;
}

volatile uint32_t test_read_mem = 0xFACEF00D;
volatile uint32_t test_write_mem = 0x0;

void test_insn_access(void) __attribute__((aligned(4), noinline));
void test_insn_access(void) {
  asm volatile ("nop");
}

typedef enum {
  kTestAccessTypeRead,
  kTestAccessTypeWrite,
  kTestAccessTypeInsn
} test_access_type_t;

void do_test_access(test_access_type_t test_type) {
  volatile uint32_t test_read;

  switch(test_type) {
    case kTestAccessTypeRead:
      test_read = test_read_mem;
      break;
    case kTestAccessTypeWrite:
      test_write_mem = 0xDEADBEEF;
      break;
    case kTestAccessTypeInsn:
      test_insn_access();
      break;
  }
}

int test_access(test_access_type_t test_type,
    pmp_region_config_t disallow_config, pmp_region_config_t allow_config,
    const char* test_name, bool u_mode) {

  uintptr_t test_addr;
  switch(test_type) {
    case kTestAccessTypeRead:
      test_addr = &test_read_mem;
      expected_mcause = MCAUSE_READ_ACCESS;
      break;
    case kTestAccessTypeWrite:
      test_addr = &test_write_mem;
      expected_mcause = MCAUSE_WRITE_ACCESS;
      break;
    case kTestAccessTypeInsn:
      test_addr = &test_insn_access;
      expected_mcause = MCAUSE_INSN_ACCESS;
      break;
  }

  expected_fault_addr = test_addr;
  pmp_test_allow_config = allow_config;

  pmp_region_configure_na4_result_t configure_result;
  configure_result = pmp_region_configure_na4(pmp_test_region, disallow_config,
      test_addr);
  if (configure_result != kPmpRegionConfigureNa4Ok) {
    puts("FAIL\nFailure to configure PMP in test_access ");
    puthex(configure_result);
    sim_halt();
  }

  exception_seen = false;
  exception_error = false;
  exception_expected = true;

  puts(test_name);
  puts("...");

  if (u_mode) {
    if(!switch_privledge_level(kPrivLevelU)) {
      puts("FAIL\nU Mode switch failure\n");
      return;
    }
  }

  do_test_access(test_type);

  if (u_mode) {
    if(!switch_privledge_level(kPrivLevelM)) {
      puts("FAIL\nU Mode switch failure\n");
      return;
    }
  }

  if (!exception_seen) {
    puts("FAIL\nNo exception seen when disallowed\n");
    return 1;
  }

  if (exception_error) {
    return 1;
  }

  puts("SUCCESS\n");

  return 0;
}

int main(int argc, char **argv) {
  enable_rlb(true);
  enable_mml();

  pmp_test_region = 0;

  pmp_region_config_t disallow =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsNone};

  pmp_region_config_t read_allow_m =
    {.lock = kPmpRegionLockLocked, .permissions = kPmpRegionPermissionsReadOnly};

  pmp_region_config_t write_allow_m =
    {.lock = kPmpRegionLockLocked, .permissions = kPmpRegionPermissionsReadWrite};

  pmp_region_config_t insn_allow_m =
    {.lock = kPmpRegionLockLocked, .permissions = kPmpRegionPermissionsExecuteOnly};

  pmp_region_config_t read_allow_u =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsReadOnly};

  pmp_region_config_t write_allow_u =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsReadWrite};

  pmp_region_config_t insn_allow_u =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsExecuteOnly};

  pmp_region_config_t shared_rw =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsSharedReadWrite};

  pmp_region_config_t shared_x =
    {.lock = kPmpRegionLockUnlocked, .permissions = kPmpRegionPermissionsSharedExecuteOnly};

  pmp_region_configure_napot_result_t configure_result;

  configure_result = pmp_region_configure_napot(1, shared_x, 0x100000, 0x80000);
  if (configure_result != kPmpRegionConfigureNapotOk) {
    puts("FAIL\nCould not configure shared X region");
    return 0;
  }

  configure_result = pmp_region_configure_napot(2, shared_rw, 0x000000, 0x400000);
  if (configure_result != kPmpRegionConfigureNapotOk) {
    puts("FAIL\nCould not configure shared RW region");
    return 0;
  }

  int failures = 0;

  failures += test_access(kTestAccessTypeRead, read_allow_u, read_allow_m, "M read", false);
  failures += test_access(kTestAccessTypeWrite, write_allow_u, write_allow_m, "M write", false);
  failures += test_access(kTestAccessTypeInsn, insn_allow_u, insn_allow_m, "M insn", false);


  failures += test_access(kTestAccessTypeRead, read_allow_m, read_allow_u, "U read", true);
  failures += test_access(kTestAccessTypeWrite, write_allow_m, write_allow_u, "U write", true);
  failures += test_access(kTestAccessTypeInsn, insn_allow_m, insn_allow_u, "U insn", true);

  if(!switch_privledge_level(kPrivLevelM)) {
    puts("FAIL\nM Mode switch failure\n");
    return;
  }

  if (failures == 0) {
    puts("PASS\n");
  } else {
    puthex(failures);
    puts(" failures seen\n");
  }

  return 0;
}
