#!/usr/bin/env python3
"""Accuracy figure for Report #1.

Reads the word-length table produced by scripts/sweep.py and plots measured
NRMSE against product width, together with the output-quantisation floor.

Style: single-column IEEE figure, Times New Roman, no in-figure title, thin
black lines, vector PDF plus a PNG preview.
"""
import os
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "doc", "results", "numerics.txt")
OUT = os.path.join(ROOT, "report1", "figures", "accuracy")


def parse(path):
    pw, avg, wc = [], [], []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"\s*(\d+)\s+Q2\.\d+\s+([0-9.]+)\s+([0-9.]+)", line)
            if m:
                pw.append(int(m.group(1)))
                avg.append(float(m.group(2)))
                wc.append(float(m.group(3)))
    return pw, avg, wc


def main():
    plt.rcParams.update({
        "font.family": "serif",
        "font.serif": ["Times New Roman", "DejaVu Serif"],
        "font.size": 8,
        "axes.linewidth": 0.6,
        "xtick.major.width": 0.6,
        "ytick.major.width": 0.6,
        "xtick.direction": "in",
        "ytick.direction": "in",
        "mathtext.fontset": "stix",
    })

    pw, avg, wc = parse(SRC)
    floor = min(avg)          # the output-quantisation floor, measured

    fig, ax = plt.subplots(figsize=(3.4, 2.25))
    ax.semilogy(pw, wc, "o-", color="black", ms=3.5, lw=0.9,
                label="worst case")
    ax.semilogy(pw, avg, "s--", color="0.35", ms=3.2, lw=0.9,
                label="average")
    ax.axhline(floor, color="0.55", lw=0.7, ls=":")
    ax.annotate("Q7.9 output floor",
                xy=(23.0, floor), xytext=(23.0, floor * 1.09),
                fontsize=7, color="0.30")

    ax.set_xlabel("product word length (bit)")
    ax.set_ylabel("NRMSE (%)")
    ax.set_xticks(pw)
    ax.set_xlim(14.5, 33.5)
    ax.set_ylim(0.0024, 0.011)
    ax.legend(frameon=False, fontsize=7, loc="upper right")
    ax.grid(True, which="major", lw=0.3, color="0.85")

    fig.tight_layout(pad=0.3)
    fig.savefig(OUT + ".pdf")
    fig.savefig(OUT + ".png", dpi=300)
    print("wrote", OUT + ".pdf")
    print("data:", list(zip(pw, avg, wc)))


if __name__ == "__main__":
    main()
