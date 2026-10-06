# Phase 2 — Packed-RGB Blur (COMPLETE)

**Status:** complete. Full integer ALU, `CMP` + uniform branches, and an
interior 3×3 box blur matched pixel-for-pixel against an independent reference.

Read first: `docs/GPU_ISA.md` (Phase 2 opcodes), `docs/BUS_PROTOCOL.md`.
Build log: `docs/PHASE2_PROGRESS.md`.

## What was delivered

- **ISA** (`docs/GPU_ISA.md`): `MUL/DIV/AND/OR/XOR/SLL/SRL`, `CMP`, and branches
  (`B/BEQ/BNE/BLT/BGE/BLE/BGT`) with flags + labels.
- **ALU** (`rtl/alu.sv`): ops `2..8` — `MUL`, `DIV` (unsigned, `b==0`→0),
  `AND`, `OR`, `XOR`, `SLL` (`a << b[4:0]`), `SRL` (`a >> b[4:0]`).
- **Decoder** (`rtl/decoder.sv`): `legal = (opcode <= 4'hE)`.
- **Warp** (`rtl/warp.sv`): routes all nine ALU ops; `CMP` updates the `{N,Z,P}`
  flags (lane 0 decides, uniform); a taken `BRnzp` redirects `pc` by the signed
  offset. Branch format `[op][cond:3][off:9]`.
- **Assembler** (`tools/assemble.py`): new mnemonics, labels, and the
  `.gen_blur W H` directive (fully-unrolled interior blur → 125 instructions).
- **Golden model** (`tools/isa_sim.py`) executes the new ops + branches;
  **`tools/blur_ref.py`** is an independent Python box blur.
- **Driver** (`tools/run_sim.py`): interior-blur mode, cross-checks the golden
  model against `blur_ref`, then compares the RTL.
- **Kernel** `sw/kernels/blur.asm` (`.gen_blur 64 64`, 3844 threads).

## Verified

| Check | Command | Result |
|---|---|---|
| ALU ops | `make unit TEST=tb_alu` | `TB_ALU PASS` |
| Decode | `make unit TEST=tb_decoder` | `TB_DECODER PASS` |
| Branches | `make branch` | `TB_BRANCH PASS` (CMP/BNE counted loop) |
| Brighten regression | `make run` | `PASS: 256 threads, 0 mismatches` |
| Golden model vs reference | `make golden` | matches on all pixels |
| RTL blur | `make blur` | `PASS: 3844 threads, 0 mismatches` |

The 1-pixel border is left untouched in Phase 2; clamped borders are Phase 3.

## Deferred (by design)

- **Coalescing** of per-lane `LDR`/`STR`: the current `mem_unit` issues one lane
  per bus cycle (uncoalesced baseline). This is a later scale-out optimization,
  not a Phase 2 requirement.
- **Per-lane divergence**: branches are uniform (all active lanes together).
  Reconvergence/masking is a later phase.
