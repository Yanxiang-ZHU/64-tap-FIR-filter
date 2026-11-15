# CSEE W4823 — 64-Tap FIR Filter Project

Individual project for **CSEE W4823 Advanced Logic Design** (Columbia University,
Fall 2026). The deliverable is a 64-tap FIR filter core that sustains
100 MS/s with 16-bit Q1.15 inputs and coefficients, produces a 16-bit Q7.9
output, and closes its input interface across two asynchronous clocks.

The project is graded in four reports. This repository contains everything that
is not a synthesis run: the RTL, the verification environment, the numerical
study, and the Report #1 LaTeX source.

| Report | Content | Weight | State |
|---|---|---|---|
| #1 | Golden model, stimulus, DUT pseudocode, ASM chart, datapath diagram, block specifications | 4 | **done** |
| #2 | ALU RTL → synthesis → PrimeTime → PPA | 3 | RTL done, synthesis pending |
| #3 | CMEM / register RTL → synthesis → PrimeTime → PPA | 3 | RTL done, synthesis pending |
| #4 | Assembled core → synthesis → metrics → FoM | 15 | RTL done, synthesis pending |

---

## Quick start

Everything runs with Icarus Verilog; Verilator is used for lint.

```bash
# full regression: lint + 4 block benches + reference/corner cases + phase sweep
./scripts/run_all.sh

# numerical characterisation (word length, phase, seeds)
python3 scripts/sweep.py

# regenerate the figures (.drawio sources, then vector PDF/PNG)
python3 scripts/make_figures.py
python3 scripts/make_accuracy_fig.py
```

The regression exits non-zero on any failure, so it works as a pre-commit gate.

---

## Architecture at a glance

```
           clk1 = 100 MHz                    clk2 = 800 MHz
  din ──► async FIFO ──► prefetch ──► sample window ──┐
          (16b × 8,              (8 banks × 8 × 16b,  ├──► 8 × MAC ──► Σ tree
           gray ptrs)             rotating)           │    Q2.18       3 levels
                                     CMEM ────────────┘                  │
                                   (8 banks × 8 × 16b)               ACC 32b
                                                                         │
                                          dout ◄── round + sat ◄── Q7.9 ─┘
```

Key decisions, each justified in `doc/ARCH.md` and in the report:

- **P = 8 MACs, K = 8 cycles, clk2 = 800 MHz.** Fewest multipliers for
  100 MS/s, hence the smallest area and switching energy.
- **Products truncated to 20-bit Q2.18 with round-half-up.** Measured NRMSE is
  0.0028 % against 0.0028 % for full precision — the Q7.9 output format sets
  the error floor, so extra internal precision is pure cost.
- **Rotating banked register file for the sample window.** Bank `p` holds tap
  group `p`; the bank *role* rotates instead of the data, so each bank needs
  exactly one read port and only one bank is rewritten per sample.
- **Transposed CMEM addressing**, so multiplier `p` reads one window word and
  one coefficient word per cycle, both at entry `j` of bank `p`.
- **Dual-clock FIFO with a one-word prefetch stage.** At `f2 = 8·f1` there is no
  rate margin; the prefetch keeps the pointer-synchroniser latency off the
  critical path.

---

## Repository layout

```
report1/                      Report #1 submission
  CSEE4823_Report1.tex        IEEE conference template, compiles on Overleaf
  figures/                    vector PDF figures + accuracy plot
  figures/src/                editable .drawio sources and PNG previews
  overleaf-upload.zip         exactly what to upload to Overleaf
rtl/                          synthesizable Verilog-2001
  fir_alu.v                   8-MAC pipelined datapath        (Report #2)
  fir_cmem.v                  coefficient memory, 1W/8R        (Report #3)
  fir_win.v                   rotating sample window, 1W/8R    (Report #3)
  fir_sync.v                  dual-clock FIFO                  (Report #4)
  fir_core.v                  top level, controller            (Report #4)
tb/                           verification
  fir_golden.v                binary32 golden model
  fir_core_ref.v              behavioural fixed-point reference (Report #1)
  tb_fir_alu.v                per-block benches
  tb_fir_cmem.v
  tb_fir_win.v
  tb_fir_core.v               end-to-end self-checking bench
  tb_fir_ref.v                reference-model bench (Report #1)
scripts/                      run_all.sh, sweep.py, figure generators
doc/                          ARCH.md, RTL_SPEC.md, results/, board.html
```

---

## Verification

`./scripts/run_all.sh` runs 16 checks and passes cleanly:

| Check | What it proves |
|---|---|
| Verilator lint | no width, latch, or unused-signal defects in the RTL |
| `tb_fir_alu` | every accumulator value and every output word over 400 groups, plus forced saturation |
| `tb_fir_cmem` | the address transpose, read stability under a concurrent write, write-through timing |
| `tb_fir_win` | the window invariant `x[n-p-8j]` for 200 samples × 8 groups, including the group-0 bypass |
| `tb_fir_ref` | the behavioural reference against the golden model |
| `tb_fir_core` ×4 | the synthesizable core end to end: 3 seeds + a bursty-input case |
| phase sweep ×8 | CDC robustness over clk2 phase offsets 0 – 1.1 ns |

Measured accuracy of the assembled core: **average NRMSE 0.0028 %, worst case
0.0049 %, peak error 0.51 LSB** of Q7.9 over 10 000 random samples.

---

## Report #1

`report1/CSEE4823_Report1.tex` is written for the IEEE conference template and
compiles unchanged on Overleaf. Upload the `.tex` together with the
`figures/*.pdf` it references (`report1/overleaf-upload.zip` already has that
layout).

Figures are authored as editable `.drawio` files and exported to vector PDF at
final print size, so the fonts stay legible in a two-column layout:

| Figure | Source |
|---|---|
| DUT block diagram | `report1/figures/src/dut-block.drawio` |
| ASM chart | `report1/figures/src/asm-chart.drawio` |
| Tap/bank index map | `report1/figures/src/tap-map.drawio` |
| Accuracy sweep | `scripts/make_accuracy_fig.py` |

---

## Background

The project brief specifies the filter, the formats and the two-clock interface;
the architecture, the word lengths and the block decomposition are our own. The
figure of merit is

```
FoM = Throughput / (Energy per sample × Area)
```

with throughput fixed at 100 MS/s by the specification, which is why the whole
design is driven by area and energy rather than by arithmetic accuracy.
