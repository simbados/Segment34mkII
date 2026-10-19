#!/usr/bin/env python3
"""Scale a bitmap font 2x (nearest neighbour), e.g. for the single line above the clock.

Run from the repo root:
    python3 tools/gen_scaled_font.py led led_x2
reads resources/fonts/led.fnt/png and writes resources/fonts/led_x2.fnt/png.
Supports 8-bit grayscale and RGB PNGs. Needs only the standard library.
"""
import re
import sys

from pngio import read_png, write_png

SCALE = 2
SRC_NAME, DST_NAME = sys.argv[1], sys.argv[2]
SRC = "resources/fonts/" + SRC_NAME
DST = "resources/fonts/" + DST_NAME


def scale_fnt(text):
    def mul(m):
        return "%s=%d" % (m.group(1), int(m.group(2)) * SCALE)
    keys = "x|y|width|height|xoffset|yoffset|xadvance|size|lineHeight|base|scaleW|scaleH"
    text = re.sub(r"\b(%s)=(\d+)" % keys, mul, text)
    return text.replace(SRC_NAME + ".png", DST_NAME + ".png")


w, h, rows, ctype = read_png(SRC + ".png")
bpp = 3 if ctype == 2 else 1
out = []
for row in rows:
    wide = bytearray()
    for x in range(w):
        wide += row[x * bpp:x * bpp + bpp] * SCALE
    out.extend([wide] * SCALE)
write_png(DST + ".png", w * SCALE, h * SCALE, out, ctype)
open(DST + ".fnt", "w").write(scale_fnt(open(SRC + ".fnt").read()))
