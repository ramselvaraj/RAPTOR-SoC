#!/usr/bin/env python3
"""Small assembler for the RV32I subset used by the Phase 4 CPU driver."""

import argparse
import re
import sys


_LABEL = re.compile(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):")
_REGISTER = re.compile(r"^[xX]([0-9]+)$")
_MEMORY = re.compile(r"^(.+)\(([xX][0-9]+)\)$")


def _register(token):
    match = _REGISTER.fullmatch(token.strip())
    if not match or not 0 <= int(match.group(1)) < 32:
        raise ValueError(f"invalid register {token!r}")
    return int(match.group(1))


def _integer(token):
    try:
        return int(token, 0)
    except ValueError as exc:
        raise ValueError(f"invalid integer {token!r}") from exc


def _signed(value, bits, kind):
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not low <= value <= high:
        raise ValueError(f"{kind} immediate {value} is outside [{low}, {high}]")
    return value & ((1 << bits) - 1)


def _target(token, labels, pc, bits, kind):
    value = labels[token] - pc if token in labels else _integer(token)
    if value & 1:
        raise ValueError(f"{kind} target offset {value} is not 2-byte aligned")
    return _signed(value, bits, kind)


def _operands(text):
    parts = text.split(None, 1)
    mnemonic = parts[0].upper()
    operands = [] if len(parts) == 1 else [item.strip() for item in parts[1].split(",")]
    if any(not item for item in operands):
        raise ValueError("empty operand")
    return mnemonic, operands


def _expect(operands, count, mnemonic):
    if len(operands) != count:
        raise ValueError(f"{mnemonic} expects {count} operands, got {len(operands)}")


def _encode_instruction(text, pc, labels):
    mnemonic, ops = _operands(text)

    r_type = {
        "ADD": (0b0000000, 0b000),
        "SUB": (0b0100000, 0b000),
        "AND": (0b0000000, 0b111),
        "OR": (0b0000000, 0b110),
    }
    if mnemonic in r_type:
        _expect(ops, 3, mnemonic)
        rd, rs1, rs2 = map(_register, ops)
        funct7, funct3 = r_type[mnemonic]
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33

    if mnemonic == "ADDI":
        _expect(ops, 3, mnemonic)
        rd, rs1 = _register(ops[0]), _register(ops[1])
        imm = _signed(_integer(ops[2]), 12, mnemonic)
        return (imm << 20) | (rs1 << 15) | (rd << 7) | 0x13

    if mnemonic in ("LB", "LH", "LW", "LBU", "LHU"):
        _expect(ops, 2, mnemonic)
        match = _MEMORY.fullmatch(ops[1].replace(" ", ""))
        if not match:
            raise ValueError(f"invalid memory operand {ops[1]!r}; expected offset(register)")
        rd = _register(ops[0])
        imm = _signed(_integer(match.group(1)), 12, mnemonic)
        rs1 = _register(match.group(2))
        funct3 = {"LB": 0, "LH": 1, "LW": 2, "LBU": 4, "LHU": 5}[mnemonic]
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x03

    if mnemonic in ("SB", "SH", "SW"):
        _expect(ops, 2, mnemonic)
        match = _MEMORY.fullmatch(ops[1].replace(" ", ""))
        if not match:
            raise ValueError(f"invalid memory operand {ops[1]!r}; expected offset(register)")
        rs2 = _register(ops[0])
        imm = _signed(_integer(match.group(1)), 12, mnemonic)
        rs1 = _register(match.group(2))
        funct3 = {"SB": 0, "SH": 1, "SW": 2}[mnemonic]
        return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | 0x23

    if mnemonic in ("BEQ", "BNE"):
        _expect(ops, 3, mnemonic)
        rs1, rs2 = _register(ops[0]), _register(ops[1])
        imm = _target(ops[2], labels, pc, 13, mnemonic)
        funct3 = 0b000 if mnemonic == "BEQ" else 0b001
        return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63

    if mnemonic == "JAL":
        _expect(ops, 2, mnemonic)
        rd = _register(ops[0])
        imm = _target(ops[1], labels, pc, 21, mnemonic)
        return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F

    raise ValueError(f"unknown mnemonic {mnemonic!r}")


def assemble(source):
    """Assemble source text and return a list of 32-bit instruction words."""
    labels = {}
    instructions = []
    pc = 0

    for line_number, raw_line in enumerate(source.splitlines(), 1):
        line = re.split(r"#|;|//", raw_line, maxsplit=1)[0].strip()
        while line:
            match = _LABEL.match(line)
            if not match:
                break
            name = match.group(1)
            if name in labels:
                raise ValueError(f"line {line_number}: duplicate label {name!r}")
            labels[name] = pc
            line = line[match.end():].strip()
        if line:
            instructions.append((line_number, pc, line))
            pc += 4

    words = []
    for line_number, pc, text in instructions:
        try:
            words.append(_encode_instruction(text, pc, labels))
        except ValueError as exc:
            raise ValueError(f"line {line_number}: {exc}") from exc
    return words


def write_hex(words, stream):
    """Write one zero-padded 32-bit hexadecimal instruction per line."""
    for word in words:
        stream.write(f"{word & 0xFFFFFFFF:08x}\n")


def self_check():
    """Check representative encodings and immediate diagnostics."""
    source = """
        add x3, x1, x2
        sub x5, x1, x2
        addi x1, x0, -1
        sw x3, 12(x5)
        lw x4, -4(x5)
        beq x1, x2, skip
        jal x10, done
    skip: or x6, x1, x2
    done: bne x0, x0, done
    """
    expected = [
        0x002081B3, 0x402082B3, 0xFFF00093, 0x0032A623, 0xFFC2A203,
        0x00208463, 0x0080056F, 0x0020E333, 0x00001063,
    ]
    if assemble(source) != expected:
        raise AssertionError("representative instruction encoding mismatch")
    for bad in ("addi x1, x0, 2048", "beq x0, x0, 3", "jal x0, 1048576"):
        try:
            assemble(bad)
        except ValueError:
            continue
        raise AssertionError(f"assembler accepted invalid instruction: {bad}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", default="-", help="assembly file, or - for stdin")
    parser.add_argument("-o", "--out", default="-", help="hex output file, or - for stdout")
    parser.add_argument("--self-check", action="store_true", help="run built-in encoding checks")
    args = parser.parse_args(argv)

    if args.self_check:
        self_check()
        print("riscv_asm: self-check passed")
        return 0

    try:
        if args.source == "-":
            source = sys.stdin.read()
        else:
            with open(args.source, encoding="utf-8") as source_file:
                source = source_file.read()
        words = assemble(source)
        if args.out == "-":
            write_hex(words, sys.stdout)
        else:
            with open(args.out, "w", encoding="ascii") as output_file:
                write_hex(words, output_file)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"riscv_asm: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
