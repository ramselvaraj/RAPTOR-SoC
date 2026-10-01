# Phase 2 Assignment — Packed-RGB Blur

**Goal:** extend the ISA/ALU to the full integer op set and make the interior
3×3 box blur match the reference **pixel-for-pixel**.

Read first: `docs/GPU_ISA.md` (Phase 2 opcodes), `docs/BUS_PROTOCOL.md`.

## What is already done (harness, verified)

- **ISA spec** extended: `MUL/DIV/AND/OR/XOR/SLL/SRL`, `CMP`, branches
  (`B/BEQ/BNE/BLT/BGE/BLE/BGT`) with labels.
- **Assembler** (`tools/assemble.py`) understands the new mnemonics, labels, and
  the ` .gen_blur W H` directive that emits a fully-unrolled interior blur.
- **Golden model** (`tools/isa_sim.py`) executes the new ops + branches.
- **Independent reference** (`tools/blur_ref.py`): plain Python box blur.
- **Kernel** `sw/kernels/blur.asm` (` .gen_blur 64 64` → 125 instructions,
  3844 threads).
- **Driver** `tools/run_sim.py`: interior-blur mode, cross-checks the golden
  model against `blur_ref`, then compares the RTL.

I (coach) already confirmed the whole path passes end-to-end **once the ALU ops
below exist** — RTL matched the reference at 4096/4096 pixels. So your job is
purely the RTL.

## Your job

### Person B — the ALU and decoder (the whole task this phase)

| File | Requirement | Test |
|---|---|---|
| `rtl/alu.sv` | Implement ops `2..8`: `MUL`, `DIV` (unsigned, `b==0`→0), `AND`, `OR`, `XOR`, `SLL` (`a << b[4:0]`), `SRL` (`a >> b[4:0]`) | `make unit TEST=tb_alu` |
| `rtl/decoder.sv` | `legal = (opcode <= 4'hE)` (was `<= 4'h5`) | `make unit TEST=tb_decoder` |

ALU op encoding (already derived in `warp.sv`):

```
0 ADD   1 SUB   2 MUL   3 DIV   4 AND   5 OR   6 XOR   7 SLL   8 SRL
```

`warp.sv` already routes all nine ops through the ALU and writes `rd`, so no
warp change is needed for the blur.

### Person A — integration + start on 2b

| Task | Detail |
|---|---|
| Verify the blur run | `make blur` (below) — watch it go from FAIL to PASS |
| Trace the failing op | When it fails, the first mismatch tells you which ALU op is wrong; single-step the wave in a wave dump if needed |
| Start 2b (branches) | `warp.sv` has a `TODO(Person B, 2b)` block: add the `{N,Z,P}` flags register, execute `CMP` (`0xD`), and redirect `pc` on a taken branch (`0xE`, format `[op][cond:3][off:9]`, signed offset from `pc+1`). Uniform branches only for now. |

## Test commands

```sh
cd simt_gpu
make unit TEST=tb_alu          # should fail: MUL/DIV/... return 0
make unit TEST=tb_decoder      # should fail: 0x6..0xE marked illegal
make blur                      # full: assemble -> model -> RTL -> compare -> PNG
```

`make blur` prints `PASS: 3844 threads, 0 mismatches -> .../out.png`.

Use `make golden` to check the model/reference without the RTL, and
`make run` for the Phase 1 brighten regression (must stay passing).

## Milestones

| # | Milestone | Acceptance |
|---|---|---|
| M1 | ALU + decoder unit tests pass | `TB_ALU PASS`, `TB_DECODER PASS` |
| M2 | Brighten regression holds | `make run` → `PASS: 256 threads, 0 mismatches` |
| M3 | Blur passes | `make blur` → `PASS: 3844 threads, 0 mismatches` (black 1px border expected) |
| M4 | 2b: branches | a `CMP`/`BRnzp` test program loops correctly (you'll add the unit test) |

## Notes / gotchas

- Shifts take the amount from `rs2` (a register), so the kernel loads `16`/`8`
  into registers first. `SLL`/`SRL` must use `b[4:0]`.
- `DIV` by zero must yield `0` (the kernel never divides by zero, but the unit
  test checks it).
- The blur reads `SRC` and writes `DST`; the source buffer must stay unchanged
  (the driver checks this).
- Border pixels are intentionally left as 0 in Phase 2; clamped borders are
  Phase 3.
