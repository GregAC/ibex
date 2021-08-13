// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simple_system_common.h"

volatile unsigned int some_int = 10;
volatile unsigned char some_chars[] = {1, 2, 3, 4, 5, 6, 7, 8};

int main(int argc, char **argv) {
  pcount_enable(0);
  pcount_reset();
  pcount_enable(1);

  puts("Hello simple system\n");
  puthex(0xDEADBEEF);
  putchar('\n');
  puthex(0xBAADF00D);
  putchar('\n');

  pcount_enable(0);
  puthex(some_int);
  uint32_t unaligned_read = *((uint32_t*)(some_chars+3));
  puthex(unaligned_read);

  //// Enable periodic timer interrupt
  //// (the actual timebase is a bit meaningless in simulation)
  //timer_enable(2000);

  //uint64_t last_elapsed_time = get_elapsed_time();

  //while (last_elapsed_time <= 4) {
  //  uint64_t cur_time = get_elapsed_time();
  //  if (cur_time != last_elapsed_time) {
  //    last_elapsed_time = cur_time;

  //    if (last_elapsed_time & 1) {
  //      puts("Tick!\n");
  //    } else {
  //      puts("Tock!\n");
  //    }
  //  }
  //  asm volatile("wfi");
  //}

  //return 0;
}
