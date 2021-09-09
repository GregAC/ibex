// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simple_system_common.h"

#define CLK_FIXED_FREQ_HZ (50ULL * 1000 * 1000)
#define GPIO_OUT 0x80000000
#define UART_TX 0x80001000
#define UART_STATUS 0x80001004

/**
 * Delay loop executing within 8 cycles on ibex
 */
static void delay_loop_ibex(unsigned long loops) {
  int out; /* only to notify compiler of modifications to |loops| */
  asm volatile(
      "1: nop             \n" // 1 cycle
      "   nop             \n" // 1 cycle
      "   nop             \n" // 1 cycle
      "   nop             \n" // 1 cycle
      "   addi %1, %1, -1 \n" // 1 cycle
      "   bnez %1, 1b     \n" // 3 cycles
      : "=&r" (out)
      : "0" (loops)
  );
}

static int usleep_ibex(unsigned long usec) {
  unsigned long usec_cycles;
  usec_cycles = CLK_FIXED_FREQ_HZ * usec / 1000 / 1000 / 8;

  delay_loop_ibex(usec_cycles);
  return 0;
}

static int usleep(unsigned long usec) {
  return usleep_ibex(usec);
}

static void putchar_uart(char c) {
  while (DEV_READ(UART_STATUS) != 0);

  DEV_WRITE(UART_TX, (uint32_t)c);
}

static void putstr_uart(char* str) {
  while (*str) {
    putchar_uart(*str++);
  }
}

static void puthex_uart(uint32_t h) {
  int cur_digit;
  // Iterate through h taking top 4 bits each time and outputting ASCII of hex
  // digit for those 4 bits
  for (int i = 0; i < 8; i++) {
    cur_digit = h >> 28;

    if (cur_digit < 10)
      putchar_uart('0' + cur_digit);
    else
      putchar_uart('A' - 10 + cur_digit);

    h <<= 4;
  }
}
int main(int argc, char **argv) {
  uint32_t leds = 0xAAAA;
  uint32_t num = 0;

  while(1) {
    putstr_uart("Hello world from super system 11! ");
    puthex_uart(num);
    putstr_uart("\r\n");
    ++num;
    DEV_WRITE(GPIO_OUT, leds);
    leds = ~leds;
    usleep(1000 * 1000); // 1000 ms
    delay_loop_ibex(50);
  }

  return 0;
}
