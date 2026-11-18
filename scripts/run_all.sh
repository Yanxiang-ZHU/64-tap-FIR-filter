#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# CSEE W4823 64-tap FIR filter -- full RTL regression
#
#   ./scripts/run_all.sh              run every testbench, fail on any error
#   ./scripts/run_all.sh -v           also echo the per-test log
#
# Requires Icarus Verilog (iverilog + vvp) on PATH.  Optionally runs Verilator
# lint first when verilator is available.
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."
mkdir -p sim/log

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

RTL="rtl/fir_alu.v rtl/fir_cmem.v rtl/fir_win.v rtl/fir_sync.v rtl/fir_core.v"
FAIL=0
PASS=0

run() {                     # run <name> <top> <sources> [plusargs...]
    local name="$1" top="$2" src="$3"; shift 3
    local log="sim/log/${name}.log"
    if ! iverilog -g2012 -o "sim/${name}.vvp" -s "$top" $src > "$log" 2>&1; then
        echo "  BUILD FAIL  $name"; FAIL=$((FAIL+1)); return
    fi
    if ./"sim/${name}.vvp" "$@" >> "$log" 2>&1 && grep -q "RESULT: PASS" "$log"; then
        echo "  PASS        $name"; PASS=$((PASS+1))
    else
        echo "  FAIL        $name   (see $log)"; FAIL=$((FAIL+1))
    fi
    [ $VERBOSE -eq 1 ] && sed -n '/====/,$p' "$log"
    return 0
}

echo
echo "=== 1. lint ================================================="
if command -v verilator >/dev/null 2>&1; then
    verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND \
        --top-module fir_core $RTL && echo "  PASS        verilator lint"
else
    echo "  SKIP        verilator not installed"
fi

echo
echo "=== 2. block level =========================================="
run tb_fir_alu  tb_fir_alu  "rtl/fir_alu.v tb/tb_fir_alu.v"
run tb_fir_cmem tb_fir_cmem "rtl/fir_cmem.v tb/tb_fir_cmem.v"
run tb_fir_win  tb_fir_win  "rtl/fir_win.v tb/tb_fir_win.v"
run tb_fir_sync tb_fir_sync "rtl/fir_sync.v tb/tb_fir_sync.v"

echo
echo "=== 3. reference model (Report #1) =========================="
run tb_fir_golden tb_fir_golden "tb/fir_golden.v tb/tb_fir_golden.v"
run tb_fir_ref  tb_fir_ref  "tb/fir_core_ref.v tb/fir_golden.v tb/tb_fir_ref.v"

echo
echo "=== 4. full core ============================================"
run tb_fir_core tb_fir_core "$RTL tb/fir_golden.v tb/tb_fir_core.v"
run tb_core_s1  tb_fir_core "$RTL tb/fir_golden.v tb/tb_fir_core.v" +SEED=1
run tb_core_s2  tb_fir_core "$RTL tb/fir_golden.v tb/tb_fir_core.v" +SEED=987654321
run tb_core_gap tb_fir_core "$RTL tb/fir_golden.v tb/tb_fir_core.v" +GAPS +SEED=424242
run tb_fullscale tb_fir_fullscale "$RTL tb/tb_fir_fullscale.v"

echo
echo "=== 5. clk2 phase sweep (CDC robustness) ===================="
for PH in 0.0 0.15 0.31 0.47 0.625 0.78 0.94 1.10; do
    run "tb_ph_${PH}" tb_fir_core "$RTL tb/fir_golden.v tb/tb_fir_core.v" +PHASE=$PH
done

echo
echo "============================================================="
echo "  passed: $PASS    failed: $FAIL"
echo "============================================================="
[ $FAIL -eq 0 ] || exit 1
