#!/usr/bin/env python3
"""Generates 24-bit RGB (no alpha) YouTube-style App Icons for LiteTube5s."""

import os
import shutil
import struct
import zlib


def write_rgb_png(path: str, size: int) -> None:
    bg_r, bg_g, bg_b = 0xE6, 0x21, 0x17  # #E62117
    fg_r, fg_g, fg_b = 0xFF, 0xFF, 0xFF  # #FFFFFF

    # Triangle vertices in normalized [-1, 1] space
    # Left edge at x = -0.26, tip at x = 0.38, half-height = 0.36
    x_left = -0.26
    x_tip = 0.38
    half_h = 0.36

    raw = bytearray()
    inv_half = 2.0 / float(size)

    for py in range(size):
        raw.append(0)  # filter type None
        ny = (py + 0.5) * inv_half - 1.0
        abs_ny = abs(ny)
        for px in range(size):
            nx = (px + 0.5) * inv_half - 1.0
            if nx >= x_left and nx <= x_tip:
                max_y = half_h * (x_tip - nx) / (x_tip - x_left)
                if abs_ny <= max_y:
                    # Simple 1px anti-aliasing along edges
                    raw.extend((fg_r, fg_g, fg_b))
                    continue
            raw.extend((bg_r, bg_g, bg_b))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", crc)

    ihdr = struct.pack("!IIBBBBB", size, size, 8, 2, 0, 0, 0)  # color_type=2 (RGB, no alpha)
    idat = zlib.compress(bytes(raw), 9)
    png_bytes = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png_bytes)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    xcassets_dir = os.path.join(root, "Resources", "Assets.xcassets", "AppIcon.appiconset")
    bundle_dir = os.path.join(root, "Resources", "BundleIcons")

    specs = {
        "AppIcon20x20@2x.png": 40,
        "AppIcon20x20@3x.png": 60,
        "AppIcon29x29@2x.png": 58,
        "AppIcon29x29@3x.png": 87,
        "AppIcon40x40@2x.png": 80,
        "AppIcon40x40@3x.png": 120,
        "AppIcon60x60@2x.png": 120,
        "AppIcon60x60@3x.png": 180,
        "Icon-1024.png": 1024,
    }

    for filename, sz in specs.items():
        dst = os.path.join(xcassets_dir, filename)
        write_rgb_png(dst, sz)

    # Also stage flat bundle PNGs for Info.plist CFBundleIcons / Chimera uicache
    os.makedirs(bundle_dir, exist_ok=True)
    bundle_files = [
        "AppIcon20x20@2x.png",
        "AppIcon29x29@2x.png",
        "AppIcon40x40@2x.png",
        "AppIcon60x60@2x.png",
        "AppIcon60x60@3x.png",
    ]
    for name in bundle_files:
        shutil.copyfile(os.path.join(xcassets_dir, name), os.path.join(bundle_dir, name))
    shutil.copyfile(os.path.join(xcassets_dir, "AppIcon60x60@2x.png"), os.path.join(bundle_dir, "Icon-60@2x.png"))

    print("Generated AppIcons in", xcassets_dir, "and", bundle_dir)


if __name__ == "__main__":
    main()
