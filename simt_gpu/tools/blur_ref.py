#!/usr/bin/env python3
"""Independent integer reference for the interior 3x3 box blur.

Deliberately does NOT use the GPU ISA: run_sim compares it against both the
golden ISA model and the RTL, so a bug in the assembler/kernel is caught here.

Interior pixels only: for y in [1,H-2], x in [1,W-2], average each channel of
the 3x3 neighbourhood, integer-divided by 9, repacked 0x00RRGGBB. Border pixels
are left as 0 (Phase 2 scope; Phase 3 clamps borders).
"""
MASK = 0x00FFFFFF


def box_blur_interior(img, W, H):
    """img: flat list of packed-RGB words. Returns a new list, same length."""
    out = [0] * len(img)
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            sr = sg = sb = 0
            for dy in (-1, 0, 1):
                row = (y + dy) * W
                for dx in (-1, 0, 1):
                    q = img[row + x + dx]
                    sr += (q >> 16) & 0xFF
                    sg += (q >> 8) & 0xFF
                    sb += q & 0xFF
            out[y * W + x] = ((sr // 9) << 16) | ((sg // 9) << 8) | (sb // 9)
    return out
