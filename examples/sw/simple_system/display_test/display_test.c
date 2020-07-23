// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simple_system_common.h"

#define DISPLAY_MEM_BASE 0x40000
#define COLOUR_MEM_BASE 0x50000
#define FG_PALETTE_MEM_BASE 0x60000
#define BG_PALETTE_MEM_BASE 0x60040
#define DISPLAY_CTRL_BASE 0x70000
#define DISPLAY_CTRL 0x0
#define DISPLAY_STATUS 0x4
#define DISPLAY_VCOUNT_TRIGGER 0x8
#define DISPLAY_W 32
#define DISPLAY_H 8
//#define DISPLAY_W 240
//#define DISPLAY_H 76

volatile uint8_t* disp_mem = (volatile uint8_t*)DISPLAY_MEM_BASE;
volatile uint8_t* colour_mem = (volatile uint8_t*)COLOUR_MEM_BASE;
volatile uint32_t* fg_palette_mem = (volatile uint32_t*)FG_PALETTE_MEM_BASE;
volatile uint32_t* bg_palette_mem = (volatile uint32_t*)BG_PALETTE_MEM_BASE;

char * test_msg = "Hello world from Ibex!!!";

void enable_vcounter_int() {
  // enable timer interrupt
  asm volatile("csrs  mie, %0\n" : : "r"(0x10000));
  // enable global interrupt
  asm volatile("csrs  mstatus, %0\n" : : "r"(0x8));
}

uint32_t frame = 0;

int main(int argc, char **argv) {
  puts("Welcome to the display test\n");

  for(int i = 0;i < (DISPLAY_W * DISPLAY_H); ++i) {
    disp_mem[i] = (char)i % 16;
    colour_mem[i] = i;
  }

  for(int i = 0;i < 16; ++i) {
    if (i % 2) {
      bg_palette_mem[i] = 0xFFFFFFFF;
    } else {
      bg_palette_mem[i] = 0x00FF0000;
    }
  }

  for(int i = 0;i < 16; ++i) {
    fg_palette_mem[i] = i << 4;
  }

  //for(int x = 20; x < 60; ++x) {
  //  for(int y = 10; y < 30; ++y) {
  //    disp_mem[y * DISPLAY_W + x] = ' ';
  //  }
  //}

  //int msg_x = 25;
  //int msg_y = 20;

  //for(char* c = test_msg; *c; ++c) {
  //  disp_mem[msg_y * DISPLAY_W + msg_x] = *c;
  //  ++msg_x;
  //}

  enable_vcounter_int();
  DEV_WRITE(DISPLAY_CTRL_BASE + DISPLAY_VCOUNT_TRIGGER, 132);
  DEV_WRITE(DISPLAY_CTRL_BASE + DISPLAY_CTRL, 0x3);

  while (frame < 4) {
    asm volatile("wfi");
  }

  return 0;
}

void display_int_handler(void) __attribute__((interrupt));

void display_int_handler(void) {
  frame++;


  for(int i = 0;i < 16; ++i) {
    int polarity = (frame % 2) ^ (i % 2);

    if (polarity) {
      bg_palette_mem[i] = 0xFFFFFFFF;
    } else {
      bg_palette_mem[i] = 0x00FF0000;
    }
  }

  DEV_WRITE(DISPLAY_CTRL_BASE + DISPLAY_STATUS, 0x0);
}
