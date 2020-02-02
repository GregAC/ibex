# FOSDEM README

Talk slides and video can be found at:
https://fosdem.org/2020/schedule/event/riscv_lowrisc/

This branches contains the RTL for the optional third pipeline stage of Ibex. At
the time of writing it also exists as a draft PR against Ibex master
(https://github.com/lowRISC/ibex/pull/568)

Also in this branch are the Coremark (https://github.com/eembc/coremark) and
Embench (https://github.com/embench/embench-iot/pulls) benchmarks which can be
run against Ibex simple system (the basic system setup I used for the results in
the fosdem talk, which can be run under verilator as well as other RTL
simulators).

See examples/simple_system/README.md for the prequisites to run the benchmark
simulations.

Everything in here will eventually be available in Ibex master.

If you have any questions please contact me at gac@lowrisc.org.

## Running Coremark

Build coremark:

```
cd examples/sw/benchmarks/coremark
make ITERATIONS=10 PORT_DIR=ibex
```

(You can try different numbers of ITERATIONS if you wish but due to lack of
caches and predictive structures there is no difference in execution from one
iteration to the next)

Build verilator simulation

```
fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ibex:ibex_simple_system --RV32M=1 --RV32E=0 --BranchTargetALU=1 --WritebackStage=1
```

This builds with both branch target ALU and writeback stage enabled, alter the
parameters to turn them off

Run coremark

```
./build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system --raminit=./examples/sw/benchmarks/coremark/coremark.vmem
```

The performance counters are output at the end of the simulation, you can also
look at `ibex_simple_system.log` to see the output from the coremark binary and
`ibex_simple_system_pcount.csv` to get a CSV version of the performance counters

## Running Embench

Build Embench:

```
cd examples/sw/benchmarks/embench-iot
./run_build.sh
```

Build verilator simulation (if not previously built from above)

```
fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ibex:ibex_simple_system --RV32M=1 --RV32E=0 --BranchTargetALU=1 --WritebackStage=1
```

Run Embench:

```
cd examples/sw/benchmarks/embench-iot
./run_benchmark.sh
```

Outputs from each benchmark can be found in `./bd/src/[benchmark-name]`, these
are `ibex_simple_system.log` which gives the output from the binary and
`ibex_simple_system_pcount.csv` which gives a CSV version of the performance
counters.

Gather results:

```
cd examples/sw/benchmarks/embench-iot
python3 ./gather_results.py ./bd/src embench_results.csv
```

The `gather_results.py` script takes the individual performance counter CSVs and
merges them into one CSV `embench_results.csv`

## Running synthesis flow

See the instruction in syn/README.md the `syn/syn_seutp_example.sh` will enable
both the branch target ALU and writeback stage. Alter the environment variables
set there to try different configurations.
