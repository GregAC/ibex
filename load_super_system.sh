#!/bin/sh


if [ $# -ne 1 ]; then
  echo "Must supply an elf binary to load"
  exit 1
fi

openocd -f arty-a7-openocd-cfg.tcl -c "load_image $1 0x0" \
 -c "verify_image $1 0x0" \
 -c "debug_level 3" \
 -c "echo \"Doing reset\"" \
 -c "reset run" \
 -c "exit"
