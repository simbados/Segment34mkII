#!/usr/bin/env python3
"""Scale a bitmap font 2x (nearest neighbour), e.g. for the single line above the clock.

Run from the repo root:
    python3 tools/gen_scaled_font.py led led_x2
reads resources/fonts/led.fnt/png and writes resources/fonts/led_x2.fnt/png.
Supports 8-bit grayscale and RGB PNGs. Needs only the standard library.
"""
import re
import sys
import struct
import zlib

SCALE = 2
SRC_NAME, DST_NAME = sys.argv[1], sys.argv[2]
SRC = "resources/fonts/" + SRC_NAME
DST = "resources/fonts/" + DST_NAME


def read_png(path):
    data = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (0, 2), "expected 8-bit grayscale or RGB"
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp = 3 if ctype == 2 else 1
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        base = y * (stride + 1)
        ft, line = raw[base], bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1: line[i] = (line[i] + a) & 255
            elif ft == 2: line[i] = (line[i] + b) & 255
            elif ft == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, rows, ctype


def write_png(path, w, h, rows, ctype):
    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


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
