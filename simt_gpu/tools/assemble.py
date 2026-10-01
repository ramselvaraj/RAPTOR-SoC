#!/usr/bin/env python3
"""Assembler for the RAPTOR-SoC GPU ISA (see docs/GPU_ISA.md).

Phase 1 subset: ADD, SUB, CONST, LDR, STR, RET.
Phase 2 adds:   MUL, DIV, AND, OR, XOR, SLL, SRL, CMP, branches
                (B/BEQ/BNE/BLT/BGE/BLE/BGT), labels, and the
                ``.gen_blur W H`` directive which emits a fully-unrolled
                interior 3x3 box-blur kernel.

Syntax::

    .threads 256
    .src 0x2000
    .dst 0x6000
    .text
        CONST r1, 0x20
        LDR   r2, r14, r0
        ...
    loop:
        ...
        BLT loop

    ; or, for a blur:
    .gen_blur 64 64
    .src 0x2000
    .dst 0x6000

Outputs a 16-bit-per-line hex program plus a JSON sidecar with launch
metadata.
"""
import argparse
import json
import re
import sys

OPCODES = {
    "ADD": 0x0, "CONST": 0x1, "SUB": 0x2, "LDR": 0x3, "STR": 0x4, "RET": 0x5,
    "MUL": 0x6, "DIV": 0x7, "AND": 0x8, "OR": 0x9, "XOR": 0xA,
    "SLL": 0xB, "SRL": 0xC, "CMP": 0xD,
}
# n, z, p condition bits
BRANCHES = {
    "B": 0b111, "BEQ": 0b010, "BNE": 0b101, "BLT": 0b100,
    "BGE": 0b011, "BLE": 0b110, "BGT": 0b001,
}
BR_OP = 0xE

COMMENT = re.compile(r"[;#].*$")


def parse_reg(tok):
    tok = tok.strip().lower()
    if not tok.startswith("r"):
        raise ValueError(f"expected register, got {tok!r}")
    n = int(tok[1:])
    if not 0 <= n < 16:
        raise ValueError(f"register out of range: {tok}")
    return n


def enc_r(op, a, b, c):
    return (op << 12) | (a << 8) | (b << 4) | c


def emit_blur(W, H):
    """Emit a fully-unrolled interior 3x3 box blur for a W x H image.

    One thread per interior pixel t in [0, (W-2)*(H-2)):
        iw = W-2;  x = t % iw + 1;  y = t / iw + 1;  p = y*W + x
        average each of R,G,B over the 3x3 neighbourhood around p, //9,
        repack to 0x00RRGGBB, store at DST + p.
    Register map: r6=0xFF r7=16 r8=8 r9=9 r10/11/12=sum R/G/B r13=p;
    r1..r5 temps; r14=SRC r15=DST.
    """
    iw = W - 2
    prog = []

    def C(rd, imm):
        prog.append((0x1 << 12) | (rd << 8) | (imm & 0xFF))

    def R(op, rd, rs1, rs2):
        prog.append(enc_r(OPCODES[op], rd, rs1, rs2))

    # constants + accumulators
    C(6, 0xFF)
    C(7, 16)
    C(8, 8)
    C(9, 9)
    C(10, 0)
    C(11, 0)
    C(12, 0)
    # x = t % iw + 1 ; y = t / iw + 1 ; p = y*W + x
    C(1, iw)
    R("DIV", 2, 0, 1)      # q = t / iw
    R("MUL", 3, 2, 1)      # q*iw
    R("SUB", 4, 0, 3)      # x0 = t - q*iw
    C(5, 1)
    R("ADD", 4, 4, 5)      # x = x0 + 1
    R("ADD", 2, 2, 5)      # y = q + 1
    C(1, W)
    R("MUL", 3, 2, 1)      # y*W
    R("ADD", 13, 3, 4)     # p = y*W + x

    offsets = [-(W + 1), -W, -(W - 1), -1, 0, 1, (W - 1), W, (W + 1)]
    for off in offsets:
        if off >= 0:
            C(1, off)
            R("ADD", 2, 13, 1)     # idx = p + off
        else:
            C(1, -off)
            R("SUB", 2, 13, 1)     # idx = p - |off|
        R("LDR", 3, 14, 2)         # r3 = mem[SRC + idx]
        R("SRL", 4, 3, 7)          # r4 = r3 >> 16
        R("AND", 4, 4, 6)          # r4 &= 0xFF   (R)
        R("ADD", 10, 10, 4)        # sumR += R
        R("SRL", 4, 3, 8)          # r4 = r3 >> 8
        R("AND", 4, 4, 6)
        R("ADD", 11, 11, 4)        # sumG += G
        R("AND", 4, 3, 6)          # r4 = r3 & 0xFF (B)
        R("ADD", 12, 12, 4)        # sumB += B

    R("DIV", 10, 10, 9)
    R("DIV", 11, 11, 9)
    R("DIV", 12, 12, 9)
    R("SLL", 10, 10, 7)            # R << 16
    R("SLL", 11, 11, 8)            # G << 8
    R("OR", 10, 10, 11)
    R("OR", 10, 10, 12)
    R("STR", 10, 15, 13)           # DST[p] = packed
    R("RET", 0, 0, 0)
    return prog, iw * (H - 2)


def assemble(text):
    threads = None
    src, dst = 0, 0
    width = height = None
    interior = False
    labels = {}
    prog = []
    pending = []   # (index, cond, label)

    raw = []
    for lineno, line in enumerate(text.splitlines(), 1):
        line = COMMENT.sub("", line).strip()
        if line:
            raw.append((lineno, line))

    for lineno, line in raw:
        if line.startswith("."):
            parts = line.split()
            d = parts[0].lower()
            if d == ".threads" and len(parts) == 2:
                threads = int(parts[1], 0)
            elif d == ".src" and len(parts) == 2:
                src = int(parts[1], 0)
            elif d == ".dst" and len(parts) == 2:
                dst = int(parts[1], 0)
            elif d == ".gen_blur" and len(parts) == 3:
                width, height = int(parts[1], 0), int(parts[2], 0)
                body, n = emit_blur(width, height)
                prog.extend(body)
                interior = True
                if threads is None:
                    threads = n
            elif d in (".text", ".data", ".global"):
                pass
            else:
                raise ValueError(f"line {lineno}: unknown directive {d!r}")
            continue

        if line.endswith(":"):
            labels[line[:-1]] = len(prog)
            continue

        toks = line.replace(",", " ").split()
        mnem = toks[0].upper()

        if mnem in BRANCHES:
            if len(toks) != 2:
                raise ValueError(f"line {lineno}: branch needs a label")
            pending.append((len(prog), BRANCHES[mnem], toks[1]))
            prog.append(0)
            continue

        if mnem not in OPCODES:
            raise ValueError(f"line {lineno}: unknown mnemonic {mnem!r}")
        op = OPCODES[mnem]
        try:
            if mnem == "RET":
                prog.append(enc_r(op, 0, 0, 0))
            elif mnem == "CONST":
                prog.append((op << 12) | (parse_reg(toks[1]) << 8) | (int(toks[2], 0) & 0xFF))
            elif mnem == "CMP":
                prog.append(enc_r(op, 0, parse_reg(toks[1]), parse_reg(toks[2])))
            else:  # 3-register R-type
                a, b, c = (parse_reg(t) for t in toks[1:4])
                prog.append(enc_r(op, a, b, c))
        except (IndexError, ValueError) as e:
            raise ValueError(f"line {lineno}: {e}") from e

    for idx, cond, label in pending:
        if label not in labels:
            raise ValueError(f"undefined label {label!r}")
        off = labels[label] - (idx + 1)
        if not -256 <= off <= 255:
            raise ValueError(f"branch to {label!r} out of range ({off})")
        prog[idx] = (BR_OP << 12) | (cond << 9) | (off & 0x1FF)

    meta = {"threads": threads or 0, "src": src, "dst": dst}
    if interior:
        meta.update({"width": width, "height": height, "interior": True})
    return prog, meta, labels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--out", default="prog.hex")
    ap.add_argument("--meta", default=None)
    args = ap.parse_args()

    with open(args.source) as f:
        text = f.read()

    try:
        prog, meta, _ = assemble(text)
    except ValueError as e:
        sys.exit(f"assemble: {e}")

    with open(args.out, "w") as f:
        for w in prog:
            f.write(f"{w & 0xFFFF:04x}\n")
    if args.meta:
        with open(args.meta, "w") as f:
            json.dump(meta, f, indent=2)
    print(f"assemble: {len(prog)} instructions -> {args.out} {meta}")


if __name__ == "__main__":
    main()
