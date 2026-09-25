#!/usr/bin/env python3
"""Assembler for the RAPTOR-SoC GPU ISA v0 (see docs/GPU_ISA.md).

Supports the Phase 1 subset: ADD, SUB, CONST, LDR, STR, RET.

Syntax::

    .threads 256
    .src 0x2000
    .dst 0x6000
    .text
        CONST r1, 0x20
        LDR   r2, r14, r0
        ADD   r3, r2, r1
        STR   r15, r0, r3
        RET

Outputs a 16-bit-per-line hex program plus a JSON sidecar with the launch
metadata (.threads/.src/.dst).

Usage::

    assemble.py kernel.asm --out prog.hex --meta prog.json
"""
import argparse
import json
import re
import sys

OPCODES = {"ADD": 0x0, "CONST": 0x1, "SUB": 0x2, "LDR": 0x3, "STR": 0x4, "RET": 0x5}

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


def assemble(text):
    threads, src, dst = 0, 0, 0
    words = []
    labels = {}
    lines = []

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = COMMENT.sub("", raw).strip()
        if not line:
            continue
        lines.append((lineno, line))

    # First pass: directives and label definitions.
    for lineno, line in lines:
        if line.startswith("."):
            parts = line.split()
            d = parts[0].lower()
            if d == ".threads" and len(parts) == 2:
                threads = int(parts[1], 0)
            elif d == ".src" and len(parts) == 2:
                src = int(parts[1], 0)
            elif d == ".dst" and len(parts) == 2:
                dst = int(parts[1], 0)
            elif d in (".text", ".data", ".global"):
                pass
            else:
                raise ValueError(f"line {lineno}: unknown directive {d!r}")
        elif line.endswith(":"):
            labels[line[:-1]] = len(words)
        else:
            words.append(line)

    # Second pass: encode instructions.
    prog = []
    for lineno, line in [(n, l) for n, l in lines if not l.startswith(".") and not l.endswith(":")]:
        toks = line.replace(",", " ").split()
        mnem = toks[0].upper()
        if mnem not in OPCODES:
            raise ValueError(f"line {lineno}: unknown mnemonic {mnem!r}")
        op = OPCODES[mnem]
        try:
            if mnem == "RET":
                prog.append(enc_r(op, 0, 0, 0))
            elif mnem == "CONST":
                rd = parse_reg(toks[1])
                imm = int(toks[2], 0) & 0xFF
                prog.append((op << 12) | (rd << 8) | imm)
            elif mnem in ("ADD", "SUB"):
                rd, rs1, rs2 = (parse_reg(t) for t in toks[1:4])
                prog.append(enc_r(op, rd, rs1, rs2))
            elif mnem == "LDR":
                rd, base, idx = (parse_reg(t) for t in toks[1:4])
                prog.append(enc_r(op, rd, base, idx))
            elif mnem == "STR":
                data, base, idx = (parse_reg(t) for t in toks[1:4])
                prog.append(enc_r(op, data, base, idx))
        except (IndexError, ValueError) as e:
            raise ValueError(f"line {lineno}: {e}") from e

    return prog, {"threads": threads, "src": src, "dst": dst}, labels


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
