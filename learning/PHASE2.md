# Phase 2 — Packed-RGB Blur (learning hub)

Short overview of Phase 2. For the full teaching version see
`lessons/0004-phase2-blur-and-branches.md`.

---

## One line

```
Phase 1: one op per pixel (brighten)   →   Phase 2: 3x3 box blur, 9 ops, loops
```

Acceptance: the interior 3×3 blur matches the reference pixel-for-pixel.

---

## Status board

```
ALU ops 2-8      [x]   MUL DIV AND OR XOR SLL SRL
decoder 0xE      [x]   legal = opcode <= 0xE
blur             [x]   make blur   PASS: 3844 threads, 0 mismatches
brighten regress [x]   make run    PASS: 256 threads, 0 mismatches
branches (2b)    [x]   CMP + BRnzp, loop kernel PASS
```

---

## File map

| File | What changed |
|:--|:--|
| `rtl/alu.sv` | added ops 2..8 |
| `rtl/decoder.sv` | `legal <= 0xE` |
| `rtl/warp.sv` | flags `N/Z/P` + `CMP` + branch `pc` redirect |

Harness (already done, not ours): `tools/assemble.py`, `tools/isa_sim.py`,
`tools/blur_ref.py`, `sw/kernels/blur.asm`.

---

## The three new ideas

```
1. ALU grew      ── 7 more math/bit ops
2. Decoder       ── one line, more opcodes legal
3. Branches      ── remember {N,Z,P}, jump pc if a condition holds
```

---

## The big idea: two loops

```
OUTER (wave loop, hardware)      run the whole program again for the next 8 threads
   └─ nested around ──►
INNER (branch loop, software)    jump backward inside the program (for/while)
```

They meet in `warp.sv` where `pc` is decided — `start_warp` (outer) overrides a
branch (inner). Details in `lessons/0004-phase2-blur-and-branches.md` §5.

---

## Results

```
make unit TEST=tb_alu       → TB_ALU PASS
make unit TEST=tb_decoder   → TB_DECODER PASS
make blur                   → PASS: 3844 threads, 0 mismatches
make run                    → PASS: 256 threads, 0 mismatches
```

---

## Note that fixes an old open item

The old "8 lanes vs 256 threads" concern is solved by the wave loop in
`dcr.sv`: 8 lanes run many waves. `8 × ~481 waves ≈ 3844 threads`.

---

## Read more

- `docs/PHASE2_ASSIGNMENT.md` — the spec
- `docs/GPU_ISA.md` §Phase 2 — opcodes and branch encoding
- `docs/PHASE2_PROGRESS.md` — build-order checklist
- `lessons/0004-phase2-blur-and-branches.md` — the lesson
