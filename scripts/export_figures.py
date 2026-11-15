#!/usr/bin/env python3
"""Export every .drawio source to a single-page vector PDF and a PNG preview.

draw.io occasionally emits a blank first page and puts the drawing on the
second one (it does so for the block diagram).  Both ``\\includegraphics`` and
Overleaf then show an empty box, so the exporter keeps the page that actually
carries the drawing.
"""
import os
import glob
import shutil
import subprocess
import sys

import fitz

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "report1", "figures", "src")
OUT = os.path.join(ROOT, "report1", "figures")

DRAWIO_CANDIDATES = [
    r"C:/Program Files/draw.io/draw.io.exe",
    os.path.expandvars(r"%LOCALAPPDATA%/Programs/draw.io/draw.io.exe"),
    "drawio",
]


def find_drawio():
    for c in DRAWIO_CANDIDATES:
        if c == "drawio" and shutil.which("drawio"):
            return "drawio"
        if os.path.exists(c):
            return c
    sys.exit("draw.io not found")


def page_score(page):
    """how much drawing is on this page"""
    score = len(page.get_text()) * 10
    score += len(page.get_drawings()) * 100
    score += len(page.get_images()) * 100
    return score


def main():
    exe = find_drawio()
    for src in sorted(glob.glob(os.path.join(SRC, "*.drawio"))):
        name = os.path.splitext(os.path.basename(src))[0]
        raw = os.path.join(OUT, name + ".raw.pdf")
        subprocess.run([exe, "-x", "-f", "pdf", "-o", raw, src],
                       check=True, capture_output=True)
        subprocess.run([exe, "-x", "-f", "png", "--width", "1600",
                        "-o", os.path.join(SRC, name + ".png"), src],
                       check=True, capture_output=True)
        doc = fitz.open(raw)
        best = max(range(doc.page_count), key=lambda i: page_score(doc[i]))
        page = doc[best]

        # crop to the ink: draw.io pads the page with the diagram margin, and
        # in a two-column paper that padding shows up as white space between
        # the figure and its caption
        boxes = [d["rect"] for d in page.get_drawings()]
        for b in page.get_text("blocks"):
            boxes.append(fitz.Rect(b[:4]))
        if boxes:
            ink = boxes[0]
            for r in boxes[1:]:
                ink |= r
            pad = 4
            mb = page.mediabox
            crop = fitz.Rect(max(ink.x0 - pad, mb.x0), max(ink.y0 - pad, mb.y0),
                             min(ink.x1 + pad, mb.x1), min(ink.y1 + pad, mb.y1))
            page.set_cropbox(crop)

        single = fitz.open()
        single.insert_pdf(doc, from_page=best, to_page=best)
        single.save(os.path.join(OUT, name + ".pdf"))
        print("%-14s pages=%d  kept page %d  (%d chars, %d drawings)" % (
            name, doc.page_count, best + 1,
            len(doc[best].get_text()), len(doc[best].get_drawings())))
        doc.close()
        single.close()
        os.remove(raw)


if __name__ == "__main__":
    main()
