cmake_minimum_required(VERSION 3.10)

# set the project name
project(build_test)

set(COMMON_DIR "${CMAKE_SOURCE_DIR}/../common")
set(LINKER_SCRIPT "${COMMON_DIR}/link.ld")
set(CMAKE_C_COMPILER riscv32-unknown-elf-gcc)
set(CMAKE_EXE_LINKER_FLAGS "-nostdlib -nostartfiles -T${LINKER_SCRIPT}")
set(CMAKE_C_FLAGS "-march=rv32imc -mabi=ilp32 -static -mcmodel=medany -Wall -g \
  -Os -fvisibility=hidden -ffreestanding")
set_property(SOURCE ${COMMON_DIR}/crt0.S PROPERTY LANGUAGE C)
set(COMMON_SRCS ${COMMON_DIR}/simple_system_common.c ${COMMON_DIR}/crt0.S)

# add the executable
add_executable(build_test main.c ${COMMON_SRCS})

target_include_directories(build_test PUBLIC "${COMMON_DIR}")
