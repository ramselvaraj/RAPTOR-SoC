#!/usr/bin/env python3
"""Build inputs, run the Phase 4 SoC testbench, and verify the full RAM dump."""

import argparse
import os
import re
import subprocess
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GPU_TOOLS = os.path.join(REPO, "simt_gpu", "tools")
sys.path.insert(0, HERE)
import riscv_asm  # noqa: E402
sys.path.insert(0, GPU_TOOLS)
import assemble  # noqa: E402
import blur_ref  # noqa: E402
import img_to_mem  # noqa: E402
import isa_sim  # noqa: E402
import mem_to_img  # noqa: E402


RAM_WORDS = 32768
SRC_ADDR = 0x2000
DST_ADDR = 0x6000
FRAME_WORDS = 4096
GPU_PROGRAM_WORDS = 1024
GPU2_OFFSET = 512
KV = re.compile(r"(\w+)=(\S+)")


CPU_DRIVER = """
    # x5=MMIO, x6=SRC, x7=DST, x8/x9=threads, x10=0, x11=512, x14=done mask
    sw x6, 12(x5)
    sw x7, 16(x5)
    sw x8, 8(x5)
    sw x10, 20(x5)
    addi x12, x0, 1
    sw x12, 0(x5)
poll1:
    lw x13, 4(x5)
    and x15, x13, x14
    beq x15, x0, poll1

    sw x6, 12(x5)
    sw x7, 16(x5)
    sw x9, 8(x5)
    sw x11, 20(x5)
    sw x12, 0(x5)
poll2:
    lw x13, 4(x5)
    and x15, x13, x14
    beq x15, x0, poll2
halt:
    beq x0, x0, halt
"""


def _write_hex(path, words, digits):
    with open(path, "w", encoding="ascii") as output:
        for word in words:
            output.write(f"{word & ((1 << (digits * 4)) - 1):0{digits}x}\n")


def _cpu_bootstrap(threads1, threads2):
    """Initialize driver registers with supported ADDI/ADD instructions."""
    registers = {
        5: 0x40000000, 6: SRC_ADDR, 7: DST_ADDR,
        8: threads1, 9: threads2, 10: 0, 11: GPU2_OFFSET, 14: 2,
    }
    lines = []
    for reg, value in registers.items():
        # Start with the most significant bit, then shift with ADD and add bits.
        bits = f"{value:b}"
        lines.append(f"addi x{reg}, x0, {bits[0]}")
        for bit in bits[1:]:
            lines.append(f"add x{reg}, x{reg}, x{reg}")
            if bit == "1":
                lines.append(f"addi x{reg}, x{reg}, 1")
    return "\n".join(lines) + "\n"


PHASE5_PRIVATE_TEST = """
    add x1, x6, x6
    addi x2, x0, 123
    sw x2, 0(x1)
    lw x3, 0(x1)
    bne x2, x3, private_fail
    sb x2, 1(x1)
    lbu x3, 1(x1)
    bne x2, x3, private_fail
    sh x2, 2(x1)
    lhu x3, 2(x1)
    bne x2, x3, private_fail
    sw x2, 64(x1)
    sw x2, 128(x1)
    sw x2, 192(x1)
    sw x2, 256(x1)
    lw x3, 256(x1)
    bne x2, x3, private_fail
    jal x0, private_done
private_fail:
    beq x0, x0, private_fail
private_done:
"""
PHASE5_READBACK = """
    add x1, x7, x7
    add x1, x1, x1
    lw x20, 0(x1)
    add x1, x6, x6
    add x1, x1, x1
    lw x21, 0(x1)
    addi x22, x0, 123
"""


def _build_programs(width, height):
    interior, interior_meta = assemble.assemble(f".gen_blur {width} {height}\n")[:2]
    border, border_meta = assemble.assemble(f".gen_blur_border {width} {height}\n")[:2]
    if len(interior) > GPU2_OFFSET:
        raise ValueError(
            f"interior program has {len(interior)} words; offset {GPU2_OFFSET} permits {GPU2_OFFSET}")
    if GPU2_OFFSET + len(border) > GPU_PROGRAM_WORDS:
        raise ValueError(
            f"border program has {len(border)} words; only {GPU_PROGRAM_WORDS - GPU2_OFFSET} fit at offset {GPU2_OFFSET}")
    return interior, interior_meta["threads"], border, border_meta["threads"]


def _check_gpu_model(interior, threads1, border, threads2, frame, expected):
    memory = [0] * RAM_WORDS
    memory[SRC_ADDR:SRC_ADDR + len(frame)] = frame
    isa_sim.run(interior, memory, threads1, SRC_ADDR, DST_ADDR)
    isa_sim.run(border, memory, threads2, SRC_ADDR, DST_ADDR)
    modeled = memory[DST_ADDR:DST_ADDR + len(frame)]
    if modeled != expected:
        first = next(index for index, pair in enumerate(zip(modeled, expected)) if pair[0] != pair[1])
        raise RuntimeError(
            f"GPU ISA model disagrees with independent blur at pixel {first}: "
            f"{modeled[first]:08x} != {expected[first]:08x}")


def _check_trace(path):
    with open(path, encoding="utf-8") as trace_file:
        lines = [line.strip() for line in trace_file if line.strip()]
    starts = [line for line in lines if re.search(r"\b(?:PASS_START|GPU_START)\b", line)]
    dones = [line for line in lines if re.search(r"\b(?:PASS_DONE|GPU_DONE)\b", line)]
    if len(starts) < 2 or len(dones) < 2:
        raise RuntimeError(
            f"trace is missing GPU pass events (starts={len(starts)}, dones={len(dones)})")

    start_passes = [dict(KV.findall(line)).get("pass") for line in starts]
    done_passes = [dict(KV.findall(line)).get("pass") for line in dones]
    expected_passes = ["interior", "border"]
    if start_passes != expected_passes or done_passes != expected_passes:
        raise RuntimeError(
            f"trace pass sequence is invalid: starts={start_passes}, dones={done_passes}")

    summaries = [line for line in lines if re.search(r"\bSUMMARY\b", line)]
    if not summaries:
        raise RuntimeError("trace has no cycle/traffic SUMMARY")
    summary = summaries[-1]
    values = dict(KV.findall(summary))
    if not any("cycle" in key.lower() for key in values):
        raise RuntimeError("trace SUMMARY has no cycle count")
    if "reads" not in values or "writes" not in values:
        raise RuntimeError("trace SUMMARY has no read/write traffic counts")
    return summary


def run(args):
    width, height = args.width, args.height
    if width < 3 or height < 3:
        raise ValueError(f"blur dimensions must both be at least 3, got {width}x{height}")
    count = width * height
    if count > FRAME_WORDS:
        raise ValueError(f"{width}x{height} needs {count} words; framebuffer banks hold {FRAME_WORDS}")

    workdir = os.path.abspath(args.workdir or os.path.join(
        REPO, "soc", "build", "run", f"soc{width}" if width == height else f"soc{width}x{height}"))
    binary = os.path.abspath(args.binary)
    os.makedirs(workdir, exist_ok=True)

    path = lambda name: os.path.join(workdir, name)  # noqa: E731
    frame_hex, frame_json = path("frame.hex"), path("frame.json")
    cpu_hex, gpu1_hex, gpu2_hex = path("cpu.hex"), path("gpu1.hex"), path("gpu2.hex")
    ram_hex, trace_path = path("out.hex"), path("trace.txt")
    pixels_hex, output_png = path("pixels.hex"), path("output.png")

    interior, threads1, border, threads2 = _build_programs(width, height)
    driver = CPU_DRIVER
    prelude = _cpu_bootstrap(threads1, threads2)
    if getattr(args, "phase5", False):
        prelude += PHASE5_PRIVATE_TEST
        driver = driver.replace("    sw x12, 0(x5)", """    sw x12, 0(x5)
    # Shadow writes must not change the already accepted launch snapshot.
    sw x0, 8(x5)
    sw x0, 12(x5)
    sw x0, 16(x5)
    sw x11, 20(x5)""", 1)
        driver = driver.replace("halt:", PHASE5_READBACK + "\nhalt:")
    cpu = riscv_asm.assemble(prelude + driver)
    if len(cpu) > 1024:
        raise ValueError(f"CPU program has {len(cpu)} words; instruction memory holds 1024")
    _write_hex(cpu_hex, cpu, 8)
    _write_hex(gpu1_hex, interior, 4)
    _write_hex(gpu2_hex, border, 4)
    print(
        f"assemble: CPU {len(cpu)} instructions; GPU interior {len(interior)} words "
        f"at 0 ({threads1} threads), border {len(border)} words at {GPU2_OFFSET} "
        f"({threads2} threads)")

    img_to_mem.generate(args.image, width, height, frame_hex, frame_json)
    frame = isa_sim.read_hex_words(frame_hex)
    if len(frame) != count:
        raise RuntimeError(f"generated frame has {len(frame)} words, expected {count}")
    expected = blur_ref.box_blur_clamped(frame, width, height)
    _check_gpu_model(interior, threads1, border, threads2, frame, expected)
    print(f"golden: GPU programs match independent clamped blur on {count} pixels")

    if not os.path.isfile(binary):
        raise FileNotFoundError(f"Verilated testbench not found: {binary}")
    command = [
        binary,
        f"+frame={frame_hex}",
        f"+cpu={cpu_hex}",
        f"+gpu1={gpu1_hex}",
        f"+gpu2={gpu2_hex}",
        f"+out={ram_hex}",
    ]
    if not args.no_trace:
        command.append(f"+trace={trace_path}")
    command.extend([
        f"+width={width}",
        f"+height={height}",
        f"+threads1={threads1}",
        f"+threads2={threads2}",
    ])
    if getattr(args, "phase5", False):
        command.extend([f"+cpu_half_ps={args.cpu_half_ps}", f"+gpu_half_ps={args.gpu_half_ps}",
                        f"+seed={args.seed}", f"+stalls={int(args.stalls)}", f"+reset_test={int(args.reset_test)}"])
    print("run:", " ".join(command))
    subprocess.run(command, check=True, cwd=workdir)

    ram = isa_sim.read_hex_words(ram_hex)
    if len(ram) != RAM_WORDS:
        raise RuntimeError(f"RAM dump has {len(ram)} words, expected exactly {RAM_WORDS}")
    actual = ram[DST_ADDR:DST_ADDR + count]
    mismatches = [index for index, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]]
    if mismatches:
        first = mismatches[0]
        raise RuntimeError(
            f"{len(mismatches)}/{count} destination pixels differ; first pixel {first}: "
            f"got {actual[first]:08x}, expected {expected[first]:08x}")
    original_source_bank = frame + [0] * (FRAME_WORDS - count)
    source_changes = [index for index, pair in enumerate(
        zip(ram[SRC_ADDR:SRC_ADDR + FRAME_WORDS], original_source_bank)) if pair[0] != pair[1]]
    if source_changes:
        raise RuntimeError(
            f"source framebuffer changed at {len(source_changes)} pixels; first is {source_changes[0]}")

    _write_hex(pixels_hex, actual, 8)
    _, _, rendered_path = mem_to_img.write_image(pixels_hex, frame_json, output_png)
    if not args.no_trace:
        summary = _check_trace(trace_path)
        print(f"trace: {summary}")
    print(
        f"PASS: {width}x{height}, {threads1}+{threads2} threads, destination pixel-exact, "
        f"source unchanged -> {rendered_path}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=64)
    parser.add_argument("--height", type=int, default=64)
    parser.add_argument("--binary", default=os.path.join(REPO, "soc", "build", "obj", "Vtb_soc"))
    parser.add_argument("--workdir", default=None, help="default: soc/build/run/soc<SIZE>")
    parser.add_argument("--image", default=None, help="optional input image (requires Pillow)")
    parser.add_argument("--no-trace", action="store_true", help="disable trace generation and validation")
    parser.add_argument("--phase5", action="store_true", help="test the cached multi-clock SoC")
    parser.add_argument("--cpu-half-ps", type=int, default=3500)
    parser.add_argument("--gpu-half-ps", type=int, default=5500)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--stalls", action="store_true")
    parser.add_argument("--reset-test", action="store_true")
    args = parser.parse_args(argv)
    try:
        run(args)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
