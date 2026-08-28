"""Generates the Claude Usage Monitor icon (ICO + PNG frames) without Pillow.

Outputs:
  assets/icons/app_icon.ico             -> Windows tray icon
  windows/runner/resources/app_icon.ico -> Windows window / exe icon
  assets/icons/app_icon.png             -> macOS tray icon (44 px, @2x of 22 pt)
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<n>.png -> macOS app icon

Design: rounded terracotta square with a white four-point spark (the app mark).
Run:  python tools/make_icon.py
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (0xD9, 0x77, 0x57)      # Claude terracotta
FG = (0xFF, 0xFA, 0xF5)      # warm white
SIZES = [16, 24, 32, 48, 64, 128, 256]
MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
TRAY_PNG = 44                 # macOS status-item icon: 22 pt at @2x
SS = 4                        # supersampling factor (small sizes need it most)


def supersample_for(size):
    """Only the macOS 512/1024 frames drop below SS.

    Every size the Windows .ico contains (<= 256) keeps the original SS, so the
    Windows icon stays byte-for-byte what it was; sampling 1024 px at 16x is
    minutes of pure Python for no visible gain at that scale.
    """
    return 2 if size >= 512 else SS


def coverage_rounded_square(x, y, size):
    r = size * 0.22
    half = size / 2
    dx = abs(x - half) - (half - r)
    dy = abs(y - half) - (half - r)
    dx = max(dx, 0.0)
    dy = max(dy, 0.0)
    return (dx * dx + dy * dy) <= r * r


def coverage_spark(x, y, size):
    # Concave four-point star: |x|^p + |y|^p <= R^p with p < 1.
    half = size / 2
    nx = abs(x - half) / (size * 0.34)
    ny = abs(y - half) / (size * 0.34)
    p = 0.55
    return (nx ** p + ny ** p) <= 1.0


def render(size):
    ss = supersample_for(size)
    px = bytearray()
    for y in range(size):
        row = bytearray()
        for x in range(size):
            bg_hits = 0
            fg_hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    fx = x + (sx + 0.5) / ss
                    fy = y + (sy + 0.5) / ss
                    if coverage_rounded_square(fx, fy, size):
                        bg_hits += 1
                        if coverage_spark(fx, fy, size):
                            fg_hits += 1
            total = ss * ss
            a = bg_hits / total
            if bg_hits == 0:
                row += bytes((0, 0, 0, 0))
                continue
            t = fg_hits / bg_hits
            r = round(BG[0] + (FG[0] - BG[0]) * t)
            g = round(BG[1] + (FG[1] - BG[1]) * t)
            b = round(BG[2] + (FG[2] - BG[2]) * t)
            row += bytes((r, g, b, round(255 * a)))
        px += b"\x00" + row
    return bytes(px)


def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def encode_png(size, raw):
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")


def build_ico():
    frames = [(s, encode_png(s, render(s))) for s in SIZES]
    header = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries = b""
    body = b""
    for size, data in frames:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        body += data
        offset += len(data)
    return header + entries + body


def write(rel, data):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print("wrote", rel, len(data), "bytes")


def main():
    ico = build_ico()
    for rel in ("assets/icons/app_icon.ico", "windows/runner/resources/app_icon.ico"):
        write(rel, ico)

    # macOS: the tray wants a plain PNG, and the app icon is an asset catalogue.
    write("assets/icons/app_icon.png", encode_png(TRAY_PNG, render(TRAY_PNG)))
    for size in MAC_SIZES:
        write(
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_%d.png" % size,
            encode_png(size, render(size)),
        )


if __name__ == "__main__":
    main()
