#!/usr/bin/env python3
"""Phase 1 host driver: assemble -> golden model -> RTL sim -> PNG.

    kernel.asm -> prog.hex
    image      -> frame.hex
    isa_sim    -> expected.hex        (golden model)
    Verilated tb_gpu -> out.hex
    compare out vs expected over [dst, dst+count); render out.png

Usage::

    run_sim.py                                   # brighten, built-in pattern
    run_sim.py --image in.png --width 16 --height 16
    run_sim.py --kernel sw/kernels/copy.asm
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import assemble   # noqa: E402
import img_to_mem  # noqa: E402
import isa_sim     # noqa: E402
import mem_to_img  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", default=os.path.join(ROOT, "sw", "kernels", "brighten.asm"))
    ap.add_argument("--image", default=None, help="input image (needs Pillow)")
    ap.add_argument("--width", type=int, default=16)
    ap.add_argument("--height", type=int, default=16)
    ap.add_argument("--binary", default=os.path.join(ROOT, "build", "obj", "Vtb_gpu"))
    ap.add_argument("--workdir", default=os.path.join(ROOT, "build", "run"))
    args = ap.parse_args()

    os.makedirs(args.workdir, exist_ok=True)
    frame_hex = os.path.join(args.workdir, "frame.hex")
    frame_json = os.path.join(args.workdir, "frame.json")
    prog_hex = os.path.join(args.workdir, "prog.hex")
    prog_json = os.path.join(args.workdir, "prog.json")
    expected_hex = os.path.join(args.workdir, "expected.hex")
    out_hex = os.path.join(args.workdir, "out.hex")
    out_png = os.path.join(args.workdir, "out.png")

    # 1. Assemble the kernel.
    with open(args.kernel) as f:
        prog, meta, _ = assemble.assemble(f.read())
    with open(prog_hex, "w") as f:
        f.write("".join(f"{w & 0xFFFF:04x}\n" for w in prog))
    with open(prog_json, "w") as f:
        json.dump(meta, f)
    print(f"assemble: {args.kernel} -> {len(prog)} instr, {meta}")

    # 2. Frame.
    count = args.width * args.height
    img_to_mem.generate(args.image, args.width, args.height, frame_hex, frame_json)

    threads, src, dst = meta["threads"], meta["src"], meta["dst"]
    if threads != count:
        sys.exit(f"FAIL: kernel .threads={threads} but image is {count} pixels")

    # 3. Golden model.
    data = [0] * 32768
    frame = isa_sim.read_hex_words(frame_hex)
    data[src:src + len(frame)] = frame
    isa_sim.run(prog, data, threads, src, dst)
    with open(expected_hex, "w") as f:
        f.write("".join(f"{w & 0x00FFFFFF:08x}\n" for w in data))

    # 4. RTL simulation.
    if not os.path.exists(args.binary):
        sys.exit(f"error: verilated binary not found: {args.binary}\nrun `make build` first")
    cmd = [
        args.binary,
        f"+frame={frame_hex}", f"+prog={prog_hex}", f"+out={out_hex}",
        f"+count={threads}", f"+src={src}", f"+dst={dst}",
    ]
    print("run:", " ".join(cmd))
    try:
        subprocess.run(cmd, check=True, cwd=args.workdir)
    except subprocess.CalledProcessError:
        sys.exit("FAIL: RTL simulation did not complete (timeout or abort).\n"
                 "      This is expected until the Phase 1 TODO modules are implemented.\n"
                 "      Start with the unit tests: make unit TEST=tb_alu")

    # 5. Compare.
    expected = isa_sim.read_hex_words(expected_hex)
    actual = isa_sim.read_hex_words(out_hex)
    if len(actual) < dst + threads:
        sys.exit(f"FAIL: output has {len(actual)} words, need {dst + threads}")

    mismatches = [i for i in range(threads) if actual[dst + i] != expected[dst + i]]
    if mismatches:
        i = mismatches[0]
        sys.exit(f"FAIL: {len(mismatches)}/{threads} pixel mismatches "
                 f"(first at thread {i}: got {actual[dst+i]:06x} expected {expected[dst+i]:06x})")

    src_touched = [i for i in range(threads) if actual[src + i] != frame[i]]
    if src_touched:
        sys.exit(f"FAIL: source buffer modified at {len(src_touched)} words (first {src_touched[0]})")

    # 6. Render.
    with open(out_hex, "w") as f:
        f.write("".join(f"{actual[dst+i] & 0x00FFFFFF:08x}\n" for i in range(threads)))
    _, _, path = mem_to_img.write_image(out_hex, frame_json, out_png)
    print(f"PASS: {threads} threads, {len(mismatches)} mismatches -> {path}")


if __name__ == "__main__":
    main()
