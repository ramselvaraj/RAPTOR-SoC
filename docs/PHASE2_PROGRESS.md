# Phase 2 Progress

Simple running log. One file at a time, in build order.

Legend: `[x]` done · `[~]` in progress · `[ ]` not yet

Goal: full integer op set + packed-RGB interior 3×3 blur, pixel-for-pixel.

---

## [x] 1. `rtl/alu.sv` — "do all the math"

Added ops 2–8. Op encoding: `0 ADD 1 SUB 2 MUL 3 DIV 4 AND 5 OR 6 XOR 7 SLL 8 SRL`

```systemverilog
case (op)
    4'd0: result = a + b;                      // ADD
    4'd1: result = a - b;                      // SUB
    4'd2: result = a * b;                      // MUL
    4'd3: result = (b == 0) ? 32'b0 : a / b;   // DIV (unsigned)
    4'd4: result = a & b;                      // AND
    4'd5: result = a | b;                      // OR
    4'd6: result = a ^ b;                      // XOR
    4'd7: result = a << b[4:0];                // SLL
    4'd8: result = a >> b[4:0];                // SRL
    default: result = 32'b0;                   // illegal op
endcase
```

Gotchas: shifts use `b[4:0]`; `DIV` by zero → 0.

Test: `make unit TEST=tb_alu` → `TB_ALU PASS`

---

## [x] 2. `rtl/decoder.sv` — "which opcodes are real?"

One line: `legal` now allows the Phase 2 opcodes.

```systemverilog
legal = (opcode <= 4'hE);
```

Test: `make unit TEST=tb_decoder` → `TB_DECODER PASS`

---

## [x] 3. Integration — `make blur`

`warp.sv` already routed all 9 ALU ops, so no warp change was needed for blur.

```
golden: isa_sim matches blur reference on all 4096 pixels
PASS: 3844 threads, 0 mismatches
```

Brighten regression still holds: `make run` → `PASS: 256 threads, 0 mismatches`.

(The 256-thread "problem" from Phase 1 is solved by the wave loop in `warp.sv`:
the GPU runs 8 threads, finishes, then restarts for the next 8.)

---

## [x] 4. Phase 2b — branches  (`rtl/warp.sv`)

Added to `warp.sv`:

- decode `is_cmp` (0xD) / `is_br` (0xE)
- flags register `N/Z/P`, updated on `CMP`: `cmp_res = rd1[0] - rd2[0]`
  (uniform: lane 0 decides)
- `br_taken = (cond[2]&N) | (cond[1]&Z) | (cond[0]&P)`
- on a taken `BRnzp`, `pc <= pc + 1 + signed_offset`

Flags are unused by `CMP`/`BR` register writes (they write nothing), so the
execute path just redirects `pc`.

Tested with a uniform counted loop (`CONST` counter, `SUB`, `CMP`, `BNE`):

```
PASS: 8 threads, 0 mismatches
make run   → PASS: 256 threads, 0 mismatches   (regression)
make blur  → PASS: 3844 threads, 0 mismatches  (regression)
```

Note: no dedicated `tb_warp.sv` yet — verified via the loop kernel through
`run_sim.py`.

