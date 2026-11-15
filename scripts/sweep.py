#!/usr/bin/env python3
"""Numerical characterisation of the 64-tap FIR core.

Runs the full-core testbench across
  * product word lengths PW = 16 / 20 / 24 / 32
  * clk1<->clk2 phase offsets
  * several stimulus seeds
and writes the tables used in the reports to doc/results/.

Usage:  python3 scripts/sweep.py [outdir]
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
RTL = ["rtl/fir_alu.v", "rtl/fir_cmem.v", "rtl/fir_win.v",
       "rtl/fir_sync.v", "rtl/fir_core.v", "tb/fir_golden.v",
       "tb/tb_fir_core.v"]

def run(pw=20, phase=0.31, seed=None, gaps=False, ntest=None):
    args = ["iverilog", "-g2012", "-o", "sim/sw.vvp", "-s", "tb_fir_core",
            "-Ptb_fir_core.PW=%d" % pw] + RTL
    # PW is a localparam inside the core instance; use the TB parameter instead
    subprocess.run(args, check=True, capture_output=True)
    plus = ["+PHASE=%f" % phase]
    if seed is not None:
        plus.append("+SEED=%d" % seed)
    if gaps:
        plus.append("+GAPS")
    if ntest is not None:
        plus.append("+NTEST=%d" % ntest)
    out = subprocess.run(["./sim/sw.vvp"] + plus, check=True,
                         capture_output=True, text=True).stdout
    def grab(key):
        m = re.search(key + r"\s*:?\s*([-0-9.]+)", out)
        return float(m.group(1)) if m else float("nan")
    return dict(avg=grab("NRMSE  average"), wc=grab("NRMSE  worst case"),
                err=grab("max abs error"),
                passed="RESULT: PASS" in out, raw=out)


def table(title, rows, header):
    lines = [title, "-" * len(title), header, "-" * len(header)]
    lines += rows
    return "\n".join(lines)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "doc/results"
    os.makedirs(outdir, exist_ok=True)
    text = []

    # --- word length sweep ---------------------------------------------------
    rows, bad = [], 0
    for pw in (16, 20, 24, 32):
        r = run(pw=pw)
        bad += 0 if r["passed"] else 1
        rows.append("%4d   %-9s %10.4f  %10.4f  %12.2f" % (
            pw, "Q2.%d" % (pw - 2), r["avg"], r["wc"], r["err"] * 512))
    text.append(table("Table A -- product word length (phase 0.31 ns, 10000 samples)",
                      rows,
                      "  PW   format     NRMSE avg%   NRMSE wc%   max err [LSB]"))

    # --- phase sweep --------------------------------------------------------
    rows, bad = [], bad
    for ph in (0.0, 0.15, 0.31, 0.47, 0.625, 0.78, 0.94, 1.10):
        r = run(phase=ph)
        bad += 0 if r["passed"] else 1
        rows.append("%7.3f        %10.4f  %10.4f" % (ph, r["avg"], r["wc"]))
    text.append(table("Table B -- clk1/clk2 phase offset (PW 20)",
                      rows, " phase [ns]   NRMSE avg%   NRMSE wc%"))

    # --- seed sweep ---------------------------------------------------------
    rows = []
    for sd in (1, 12345, 424242, 976431, 5556667):
        r = run(seed=sd)
        bad += 0 if r["passed"] else 1
        rows.append("%10d     %10.4f  %10.4f  %s" % (
            sd, r["avg"], r["wc"], "PASS" if r["passed"] else "FAIL"))
    text.append(table("Table C -- stimulus seeds (PW 20, phase 0.31 ns)",
                      rows, "      seed   NRMSE avg%   NRMSE wc%   result"))
    text.append("")
    text.append("failing configurations: %d" % bad)

    blob = "\n".join(text)
    print(blob)
    open(os.path.join(outdir, "numerics.txt"), "w").write(blob + "\n")
