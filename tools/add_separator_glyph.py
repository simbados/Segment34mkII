#!/usr/bin/env python3
"""Add a narrow separator glyph '!' (a column of LED dots) to the LED fonts.

The fonts have no thin divider ('|' is a solid bar in led_big, used for the battery),
so the activity data types use '!' as a separator: it is the stem of the '1' glyph
with a little space on both sides, about a third as wide as '/'.

Every glyph ends with a gap (the '0' in led: 14 px wide, advances 18, so 4 px), so the
separator gets that gap plus `pad` before it and the same space after it, e.g. in led:
digit | 4 + 2 px | 2 px dots | 2 + 4 px | digit.

Run from the repo root (idempotent; rerunning updates the spacing), then regenerate led_x2:
    python3 tools/add_separator_glyph.py
    python3 tools/gen_scaled_font.py led led_x2
"""
import re

from pngio import read_png, write_png

# font: (x of the stem in the '1' glyph, stem width, extra space on each side)
FONTS = {
    "led": (3, 2, 2),
    "led_inbetween": (3, 2, 2),
    "led_lines": (3, 2, 2),
    "led_big": (8, 3, 2),
}

for name, (stem_x, width, pad) in FONTS.items():
    fnt_path = "resources/fonts/%s.fnt" % name
    fnt = open(fnt_path).read()
    zero = re.search(r"char id=48 .*?width=(\d+) .*?xoffset=(\d+) .*?xadvance=(\d+)", fnt)
    gap = int(zero.group(3)) - int(zero.group(2)) - int(zero.group(1))
    xoffset, xadvance = pad, width + 2 * pad + gap
    if "char id=33 " in fnt:  # already added: update the spacing only
        fnt = re.sub(r"(char id=33 .*?xoffset=)\d+( .*?xadvance=)\d+",
                     lambda m: "%s%d%s%d" % (m.group(1), xoffset, m.group(2), xadvance), fnt)
        open(fnt_path, "w").write(fnt)
        print(name, "spacing", xoffset, xadvance)
        continue
    w, h, rows, ctype = read_png("resources/fonts/%s.png" % name)
    bpp = 3 if ctype == 2 else 1
    one = re.search(r"char id=49 x=(\d+) y=0", fnt)
    src_x = int(one.group(1)) + stem_x
    new_rows = []
    for row in rows:
        new_rows.append(row + bytearray(bpp) + row[src_x * bpp:(src_x + width) * bpp])
    write_png("resources/fonts/%s.png" % name, w + 1 + width, h, new_rows, ctype)
    line = "char id=33 x=%d y=0 width=%d height=%d xoffset=%d yoffset=0 xadvance=%d page=0\n" % (
        w + 1, width, h, xoffset, xadvance)
    count = int(re.search(r"chars count=(\d+)", fnt).group(1))
    fnt = fnt.replace("chars count=%d" % count, "chars count=%d" % (count + 1))
    fnt = fnt.rstrip("\n") + "\n" + line
    open(fnt_path, "w").write(fnt)
    print(name, "added")
