#!/usr/bin/env python3
"""Phase 0 host driver for the simt_gpu file-I/O loop.

    frame image -> frame.hex -> [Verilated tb_gpu] -> out.hex -> image

It generates (or converts) a frame, runs the simulator with file plusargs,
verifies the device echoed the buffer unchanged, and renders the result.

Usage:
    run_sim.py --image in.png --width 16 --height 16
    run_sim.py                       # built-in test pattern
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import img_to_mem  # noqa: E402
import mem_to_img  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", default=None, help="input image (needs Pillow)")
    ap.add_argument("--width", type=int, default=16)
    ap.add_argument("--height", type=int, default=16)
    ap.add_argument("--binary", default=os.path.join(ROOT, "build", "obj", "Vtb_gpu"))
    ap.add_argument("--workdir", default=os.path.join(ROOT, "build", "run"))
    args = ap.parse_args()

    os.makedirs(args.workdir, exist_ok=True)
    frame_hex = os.path.join(args.workdir, "frame.hex")
    prog_hex = os.path.join(args.workdir, "prog.hex")
    out_hex = os.path.join(args.workdir, "out.hex")
    meta = os.path.join(args.workdir, "frame.json")
    out_png = os.path.join(args.workdir, "out.png")

    # Phase 0 does not execute the program memory yet; just prove it loads.
    with open(prog_hex, "w") as f:
        f.write("0000\n")

    img_to_mem.generate(args.image, args.width, args.height, frame_hex, meta)

    if not os.path.exists(args.binary):
        sys.exit(f"error: verilated binary not found: {args.binary}\nrun `make build` first")

    count = args.width * args.height
    cmd = [
        args.binary,
        f"+frame={frame_hex}",
        f"+prog={prog_hex}",
        f"+out={out_hex}",
        f"+count={count}",
    ]
    print("run:", " ".join(cmd))
    subprocess.run(cmd, check=True, cwd=args.workdir)

    src = mem_to_img.read_words(frame_hex)
    dst = mem_to_img.read_words(out_hex)
    if len(dst) < len(src):
        sys.exit(f"FAIL: output has {len(dst)} words, fewer than the {len(src)} written")

    active, trailing = dst[: len(src)], dst[len(src):]
    mismatches = [i for i, (a, b) in enumerate(zip(src, active)) if a != b]
    if mismatches:
        i = mismatches[0]
        sys.exit(f"FAIL: echo mismatch on {len(mismatches)}/{len(src)} words "
                 f"(first at {i}: {src[i]:06x} != {active[i]:06x})")

    stray = [i for i, v in enumerate(trailing) if v != 0]
    if stray:
        sys.exit(f"FAIL: device wrote {len(stray)} word(s) outside the active "
                 f"region (first at +{stray[0]})")

    _, _, path = mem_to_img.write_image(out_hex, meta, out_png)
    print(f"PASS: echoed {len(src)} words unchanged, {len(trailing)} trailing words "
          f"untouched -> {path}")


if __name__ == "__main__":
    main()
