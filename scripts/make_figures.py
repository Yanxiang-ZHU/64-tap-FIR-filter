#!/usr/bin/env python3
"""Generate the Report #1 figures as editable .drawio sources.

Style: monochrome scientific, Times New Roman, white fills, no gradients, no
shadows, English labels only -- the figures drop straight into an IEEE
two-column paper.  Everything is hand-placed on a 10 px grid.

Run:  python3 scripts/make_figures.py
Out:  report1/figures/src/*.drawio
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "report1", "figures", "src")

INK = "#1a1a1a"
GREY = "#6b6b6b"
FILL = "#ffffff"
FILL_MEM = "#eef1f5"
FILL_DAT = "#fafafa"
FILL_CTL = "#ffffff"
FILL_HL = "#dfe6ee"

FONT = "fontFamily=Times New Roman;"


def st(fill=FILL, dashed=0, bold=0, fs=11, stroke=INK, align="center"):
    s = ("html=1;whiteSpace=wrap;rounded=0;strokeWidth=1;strokeColor=%s;"
         % stroke + FONT + "fontSize=%d;align=%s;verticalAlign=middle;" % (fs, align))
    s += "fillColor=%s;" % fill
    if dashed:
        s += "dashed=1;"
    if bold:
        s += "fontStyle=1;"
    return s


def esc(s):
    """XML-escape a label, then re-introduce drawio's line-break entity.

    The labels carry inline HTML (<sub>, <i>, <b>) which drawio renders when
    html=1, so the angle brackets must be entity-encoded or the XML parser
    silently drops every following cell.
    """
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s.replace("\n", "&#xa;")


class Diagram:
    def __init__(self, name, w, h):
        self.name = name
        self.w, self.h = w, h
        self.cells = []
        self.n = 2

    def _id(self):
        i = "c%d" % self.n
        self.n += 1
        return i

    def box(self, x, y, w, h, label, style=None):
        cid = self._id()
        style = style or st()
        self.cells.append(
            '<mxCell id="%s" value="%s" style="%s" vertex="1" parent="1">'
            '<mxGeometry x="%d" y="%d" width="%d" height="%d" as="geometry"/>'
            '</mxCell>' % (cid, esc(label), style, x, y, w, h))
        return cid

    def text(self, x, y, w, h, label, fs=10, align="left", italic=0, bold=0):
        s = ("text;html=1;strokeColor=none;fillColor=none;align=%s;"
             "verticalAlign=middle;%sfontSize=%d;" % (align, FONT, fs))
        if italic:
            s += "fontStyle=2;"
        if bold:
            s += "fontStyle=1;"
        return self.box(x, y, w, h, label, s)

    def _edge(self, style, label, cell_src=None, cell_tgt=None, pts=None,
              geo_src=None, geo_tgt=None):
        cid = self._id()
        geo = '<mxGeometry relative="1" as="geometry">'
        if pts:
            geo += '<Array as="points">' + "".join(
                '<mxPoint x="%d" y="%d"/>' % p for p in pts) + '</Array>'
        geo += '</mxGeometry>'
        if cell_src:
            return self.box_edge(cid, style, label, cell_src, cell_tgt, geo)
        attrs = ""
        if geo_src:
            attrs += '<mxPoint x="%d" y="%d" as="sourcePoint"/>' % geo_src
        if geo_tgt:
            attrs += '<mxPoint x="%d" y="%d" as="targetPoint"/>' % geo_tgt
        self.cells.append(
            '<mxCell id="%s" value="%s" style="%s" edge="1" parent="1">'
            '%s</mxCell>' % (cid, esc(label), style,
                             geo.replace('<mxGeometry relative="1" as="geometry">',
                                         '<mxGeometry relative="1" as="geometry">' + attrs)))
        return cid

    def box_edge(self, cid, style, label, src, tgt, geo):
        self.cells.append(
            '<mxCell id="%s" value="%s" style="%s" edge="1" parent="1" '
            'source="%s" target="%s">%s</mxCell>'
            % (cid, esc(label), style, src, tgt, geo))
        return cid

    def line(self, x1, y1, x2, y2, label="", pts=None, dashed=0, arrow="block",
             fs=9, loff=(4, -14)):
        s = ("edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;"
             "jettySize=auto;html=1;strokeColor=%s;strokeWidth=1;"
             % INK + FONT + "fontSize=%d;" % fs)
        s += ("endArrow=none;" if arrow == "none" else
              "endArrow=open;endFill=0;endSize=6;" if arrow == "open" else
              "endArrow=block;endFill=1;endSize=6;")
        if dashed:
            s += "dashed=1;"
        cid = self._id()
        geo = '<mxGeometry relative="1" as="geometry">'
        geo += '<mxPoint x="%d" y="%d" as="sourcePoint"/>' % (x1, y1)
        geo += '<mxPoint x="%d" y="%d" as="targetPoint"/>' % (x2, y2)
        if pts:
            geo += '<Array as="points">' + "".join(
                '<mxPoint x="%d" y="%d"/>' % p for p in pts) + '</Array>'
        geo += '</mxGeometry>'
        self.cells.append(
            '<mxCell id="%s" value="%s" style="%s" edge="1" parent="1">%s'
            '</mxCell>' % (cid, esc(label), s, geo))
        return cid

    def dump(self):
        body = "".join(self.cells)
        return ('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<mxfile host="drawio" version="26.0.0">\n'
                '  <diagram name="%s">\n'
                '    <mxGraphModel dx="1400" dy="900" grid="0" gridSize="10" '
                'guides="1" page="1" pageWidth="%d" pageHeight="%d" '
                'background="#ffffff">\n'
                '      <root>\n'
                '        <mxCell id="0"/>\n'
                '        <mxCell id="1" parent="0"/>\n'
                '        %s\n'
                '      </root>\n'
                '    </mxGraphModel>\n'
                '  </diagram>\n'
                '</mxfile>\n' % (self.name, self.w + 60, self.h + 60, body))


# ===========================================================================
# Figure 1 -- datapath block diagram
#
#   Drawn at final print size: 700 px == 7.0 in at 96 dpi, i.e. a two-column
#   figure.  Keeping the drawing at this size means a 9 pt label stays 9 pt
#   after \includegraphics[width=\textwidth].
# ===========================================================================
def fig_block():
    d = Diagram("dut-block", 700, 264)

    FS = 9
    d.line(146, 12, 146, 250, dashed=1, arrow="none")
    d.text(60, 2, 80, 12, "clk1", fs=8, italic=1)
    d.text(154, 2, 80, 12, "clk2", fs=8, italic=1)

    # FSM-controlled region: encloses window, CMEM and the whole datapath
    d.box(156, 12, 424, 186, "", st(fill=FILL, dashed=1, stroke=GREY))

    d.box(70, 34, 66, 50, "FIFO\n16 × 8", st(FILL_MEM, fs=FS))
    d.box(164, 26, 80, 62, "Window\n8 × 8 × 16", st(FILL_MEM, fs=FS))
    d.box(164, 128, 80, 52, "CMEM\n8 × 8 × 16", st(FILL_MEM, fs=FS))
    d.box(268, 26, 72, 62, "MAC × 8\nQ2.18", st(FILL_DAT, fs=FS))
    d.box(360, 26, 52, 62, "Σ tree", st(FILL_DAT, fs=FS))
    d.box(424, 47, 24, 22, "Σ", st(FILL, fs=10))
    d.box(462, 26, 52, 62, "ACC\n32 b", st(FILL_DAT, fs=FS))
    d.box(526, 26, 54, 62, "Round\n+ sat", st(FILL_DAT, fs=FS))
    d.box(342, 214, 88, 42, "FSM\nK = 8", st(FILL_CTL, fs=FS))

    d.text(594, 28, 60, 22, "dout", fs=FS)
    d.text(594, 52, 60, 22, "Q7.9", fs=FS, italic=1)

    # datapath: every segment axis-aligned, the 2nd point is the destination
    d.line(6, 52, 70, 52)
    d.line(6, 72, 70, 72)
    d.line(6, 154, 164, 154)
    d.line(136, 60, 164, 60)
    d.line(244, 50, 268, 50)
    d.line(244, 154, 256, 88, pts=[(256, 154)])
    d.line(340, 50, 360, 50)
    d.line(412, 57, 424, 57)
    d.line(448, 57, 462, 57)
    d.line(514, 50, 526, 50)
    d.line(580, 50, 592, 50)
    d.line(488, 88, 436, 69, pts=[(488, 110), (436, 110)])

    d.line(386, 214, 386, 198, dashed=1)

    d.text(16, 34, 40, 14, "din", fs=8, italic=1)
    d.text(16, 76, 62, 14, "din_valid", fs=8, italic=1)
    d.text(16, 134, 124, 14, "cin / caddr / cload", fs=8, italic=1)
    return d


# ===========================================================================
# Figure 2 -- ASM chart
#
#   Vertical ASM: state column on the left, every loop-back in a right-hand
#   corridor, the single long return path (OUT -> WAIT) in a left-hand
#   corridor.  No two routes cross.
# ===========================================================================
def fig_asm():
    d = Diagram("asm-chart", 340, 856)

    BW, BH = 170, 64        # state box
    DW, DH = 170, 56        # decision diamond
    X = 40                  # left edge of the state column
    CX = X + BW // 2        # spine x
    RC = 285                # right corridor
    LC = 20                 # left corridor

    Y = dict(idle=30, cl=130, d1=210, wa=300, d2=380,
             ac=470, cp=570, d3=650, out=740)

    d.box(X, Y["idle"], BW, BH, "<b>IDLE</b>", st(fill=FILL, fs=11))
    d.box(X, Y["cl"], BW, BH,
          "<b>CLOAD</b>\ncload ← 1\ncaddr ← i", st(fill=FILL, fs=10))
    d.box(X, Y["wa"], BW, BH, "<b>WAIT</b>", st(fill=FILL, fs=11))
    d.box(X, Y["ac"], BW, BH,
          "<b>ACCEPT</b>\nwe ← 1, gidx ← 0\nstart ← 1, rot ← rot − 1",
          st(fill=FILL, fs=10))
    d.box(X, Y["cp"], BW, BH,
          "<b>COMPUTE</b>\ngidx ← j\nR ← R + Σ<sub>p</sub> x<sub>p</sub>c<sub>p</sub>",
          st(fill=FILL, fs=10))
    d.box(X, Y["out"], BW, BH,
          "<b>OUT</b>\ndout ← sat(round R)\ndout_valid ← 1", st(fill=FILL, fs=10))

    def dia(y, label):
        d.box(X, y, DW, DH, label,
              "rhombus;whiteSpace=wrap;html=1;fillColor=%s;strokeColor=%s;"
              "strokeWidth=1;%sfontSize=10;" % (FILL, INK, FONT))

    dia(Y["d1"], "i = 63 ?")
    dia(Y["d2"], "FIFO empty ?")
    dia(Y["d3"], "j = K − 1 ?")

    # ---- spine -----------------------------------------------------------
    d.line(CX, Y["idle"] + BH, CX, Y["cl"])
    d.line(CX, Y["cl"] + BH, CX, Y["d1"])
    d.line(CX, Y["d1"] + DH, CX, Y["wa"], label="yes", loff=(6, -8))
    d.line(CX, Y["wa"] + BH, CX, Y["d2"])
    d.line(CX, Y["d2"] + DH, CX, Y["ac"], label="no", loff=(6, -8))
    d.line(CX, Y["ac"] + BH, CX, Y["cp"])
    d.line(CX, Y["cp"] + BH, CX, Y["d3"])
    d.line(CX, Y["d3"] + DH, CX, Y["out"], label="yes", loff=(6, -8))

    # ---- right-hand corridor: loop-backs ---------------------------------
    #   each starts at a diamond's right vertex and returns to the right edge
    #   of the state box it belongs to, via the corridor at RC
    d.line(X + DW, Y["d1"] + DH // 2, X + BW, Y["cl"] + BH // 2,
           pts=[(RC, Y["d1"] + DH // 2), (RC, Y["cl"] + BH // 2)],
           label="no", loff=(8, -14))
    d.line(X + DW, Y["d2"] + DH // 2, X + BW, Y["wa"] + BH // 2,
           pts=[(RC, Y["d2"] + DH // 2), (RC, Y["wa"] + BH // 2)],
           label="yes", loff=(8, -14))
    d.line(X + DW, Y["d3"] + DH // 2, X + BW, Y["cp"] + BH // 2,
           pts=[(RC, Y["d3"] + DH // 2), (RC, Y["cp"] + BH // 2)],
           label="no", loff=(8, -14))

    # ---- left-hand corridor: OUT -> WAIT ---------------------------------
    d.line(X, Y["out"] + BH // 2, LC, Y["out"] + BH // 2,
           pts=[(LC, Y["out"] + BH // 2), (LC, Y["wa"] + 20), (X, Y["wa"] + 20)])

    d.text(8, 812, 324, 34,
           "Boxes list the outputs asserted in that state;\ndiamonds are the "
           "transition conditions.", fs=8, italic=1, align="left")
    return d


# ===========================================================================
# Figure 3 -- tap to bank / entry mapping (single column, 3.4 in)
# ===========================================================================
def fig_map():
    d = Diagram("tap-map", 336, 300)

    CW, CH = 32, 26
    X0, Y0 = 62, 44

    for j in range(8):
        d.text(X0 + j * CW, Y0 - 22, CW, 14, "%d" % j, fs=7, align="center")
    d.text(X0 - 60, Y0 - 22, 56, 14, "j  =", fs=7, align="right", italic=1)

    for p in range(8):
        d.text(X0 - 40, Y0 + p * CH, 36, CH, "b%d" % p, fs=7, align="right")
        for j in range(8):
            hl = (p == 0)
            d.box(X0 + j * CW, Y0 + p * CH, CW, CH, "%d" % (p + 8 * j),
                  st(FILL_HL if hl else FILL, fs=8, bold=1 if hl else 0))

    d.text(X0 - 40, Y0 + 8 * CH + 6, 200, 14,
           "bank (tap group p)", fs=7, align="left", italic=1)
    d.text(X0 - 62, Y0 + 8 * CH + 24, 300, 40,
           "cell = tap index i = p + 8j.\nAt step j every bank reads only\n"
           "its own entry j, so one read\nport per bank is enough.",
           fs=7, align="left")
    return d


def main():
    os.makedirs(SRC, exist_ok=True)
    for fn in (fig_block, fig_asm, fig_map):
        d = fn()
        path = os.path.join(SRC, d.name + ".drawio")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(d.dump())
        print("wrote", path)


if __name__ == "__main__":
    main()
