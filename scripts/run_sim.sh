#!/usr/bin/env bash
# Build + run the self-checking testbench.
#   ./scripts/run_sim.sh                  # default (PW=20, phase 0.31 ns)
#   ./scripts/run_sim.sh -PPW=24          # extra iverilog args are forwarded
set -e
cd "$(dirname "$0")/.."
iverilog -g2012 -o sim/tb.vvp -s tb_fir_top \
    rtl/fir_golden.v rtl/fir_core.v tb/tb_fir_top.v "$@"
./sim/tb.vvp
