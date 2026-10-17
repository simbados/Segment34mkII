#!/usr/bin/env python3
"""Generate the led_huge font (led_big scaled 2x, nearest neighbour) from led_big.fnt/png.

Used for the single line above the clock. Run from the repo root:
    python3 tools/gen_led_huge.py
Needs only the standard library.
"""
import re
import struct
import zlib

SCALE = 2
SRC = "resources/fonts/led_big"
DST = "resources/fonts/led_huge"


def read_png(path):
    data = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype == 2, "expected 8-bit RGB"
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp, stride = 3, w * 3
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
    return w, h, rows


def write_png(path, w, h, rows):
    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def scale_fnt(text):
    def mul(m):
        return "%s=%d" % (m.group(1), int(m.group(2)) * SCALE)
    keys = "x|y|width|height|xoffset|yoffset|xadvance|size|lineHeight|base|scaleW|scaleH"
    text = re.sub(r"\b(%s)=(\d+)" % keys, mul, text)
    return text.replace("led_big.png", "led_huge.png")


w, h, rows = read_png(SRC + ".png")
out = []
for row in rows:
    wide = bytearray()
    for x in range(w):
        wide += row[x * 3:x * 3 + 3] * SCALE
    out.extend([wide] * SCALE)
write_png(DST + ".png", w * SCALE, h * SCALE, out)
open(DST + ".fnt", "w").write(scale_fnt(open(SRC + ".fnt").read()))
