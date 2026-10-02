# Lesson 4 — Phase 2: the blur, the math, and the loops

> **Where this sits**
> ```
> learning/
> ├── PHASE2.md                              phase 2 overview / hub
> └── lessons/
>     ├── 0001-what-are-you-building         the big picture
>     ├── 0002-shared-bus-and-grant.md       bus + arbitration
>     ├── 0003-wiring-and-modules.md         wiring + Person A modules
>     └── 0004-phase2-blur-and-branches.md   ← you are here
> ```

**Goal:** be able to say *what changed in Phase 2* and *why a branch is a
software loop while the wave restart is a hardware loop.*

---

## Warm-up (cover the answers)

1. In one line: what is a warp? a lane?
2. What makes 256 threads work on 8 lanes?

<details><summary>Answers</summary>

1. A warp is LANES lanes sharing one PC (4 in this GPU). A lane is one physical
   ALU/register slot.
2. The **wave loop** in the DCR: run 8 threads, then relaunch the same program
   for the next 8, until all 256 are covered.

</details>

---

## 1. What Phase 2 is

```
PHASE 1                          PHASE 2
────────                         ────────
1 op per pixel (brighten)   →    3x3 box blur (average 9 neighbours)
ADD/SUB only                →    9 ops + compare + branches
straight-line code          →    code that can jump (loops)
```

The acceptance test is a **packed-RGB interior 3×3 blur** that must match a
reference pixel-for-pixel. Only the interior is blurred; the 1-pixel border
stays 0.

---

## 2. The ALU grew up

Seven new ops, one line each:

| op | name | does |
|:--:|:--|:--|
| 2 | MUL | `a * b` |
| 3 | DIV | `a / b`, and `b==0 → 0` |
| 4 | AND | `a & b` |
| 5 | OR  | `a \| b` |
| 6 | XOR | `a ^ b` |
| 7 | SLL | `a << b[4:0]` |
| 8 | SRL | `a >> b[4:0]` |

Two gotchas:
```
shifts read the amount from b's low 5 bits   →  b[4:0]
divide by zero must give 0, not explode
```

`warp.sv` already routed all nine ops to the ALU, so we only filled in the case.

---

## 3. The decoder grew a notch

```
before:  legal = opcode <= 0x5    (Phase 1 ops only)
after :  legal = opcode <= 0xE    (adds 0x6..0xE)
```

That's the whole "are these opcodes real?" check.

---

## 4. Branches: compare, then jump

No new hardware block. Just three remembered bits and a change to `pc`.

```
CMP rs1, rs2      →  compute rs1 - rs2, remember:
                       N = result negative
                       Z = result zero
                       P = result positive

BRnzp             →  cond[2]&N | cond[1]&Z | cond[0]&P
                       if true:  pc = pc + 1 + signed_offset
                       else:     pc = pc + 1
```

Picture a loop:

```
   pc3:  sum += 1
   pc4:  count -= 1
   pc5:  CMP count, zero
   pc6:  BNE pc3        ──┐  if count != 0 …
                          └─► jump back to pc3
```

The only state added to `warp.sv`: `N, Z, P` (a flags register).

---

## 5. The two loops  ← the big idea

There are **two different things called "loop"**. They are nested.

```
OUTER LOOP = WAVE LOOP        (hardware, in dcr.sv)
  run the WHOLE program, then do it again for the next 8 threads
      wave 0: threads 0–7     run program...
      wave 1: threads 8–15    run program...
      wave 2: threads 16–23   run program...
      ... until all threads covered

INNER LOOP = BRANCH LOOP      (software, in the kernel)
  jump BACKWARD inside the program while a condition holds
      pc3: sum += 1
      pc5: CMP / BNE ──► back to pc3
```

| | wave loop | branch loop |
|:--|:--|:--|
| Who controls it | the DCR (`start`/`launch`) | the program (`CMP`+`BR`) |
| Effect on `pc` | forced to 0 (restart) | `pc + 1 + offset` (jump) |
| Repeats | the whole program × N waves | a few instructions |
| Purpose | cover more threads than lanes | while/for loops in code |

They meet in the same spot in `warp.sv`:

```systemverilog
if (start_warp)                       // OUTER loop wins
    pc <= '0;
else if (state == W_EXEC && grant) begin
    if (is_br && br_taken)
        pc <= pc + 1 + offset;        // INNER loop
    else
        pc <= pc + 1;
end
```

Mnemonic:
```
wave loop   = "run the whole program again for the next 8 threads"   (hardware)
branch loop = "run these few instructions again for these 8 threads" (software)
```

---

## 6. How the blur actually runs

```
interior 3x3 blur:
  dst[x,y] = average of the 9 pixels around src[x,y]
  only for x,y in 1..62  (the 1-pixel border stays 0)

.thethreads 3844  →  run in waves of 8  →  ~481 waves
the kernel is fully unrolled (no branches) → 125 instructions
```

The blur was the thing that needed the new math ops. Branches (2b) are a
separate, later addition.

---

## 7. Results

| check | command | result |
|:--|:--|:--|
| ALU ops | `make unit TEST=tb_alu` | `TB_ALU PASS` |
| decoder | `make unit TEST=tb_decoder` | `TB_DECODER PASS` |
| blur | `make blur` | `PASS: 3844 threads, 0 mismatches` |
| brighten | `make run` | `PASS: 256 threads, 0 mismatches` |
| branches | loop kernel | `PASS: 8 threads, 0 mismatches` |

---

## 8. Correction to the old notes

`learning/NOTES.md` used to flag: *"8 lanes but 256 threads — unresolved."*
That is now **explained and solved** by the wave loop (`dcr.sv`). The hardware
really does only have 8 lanes; it just runs 481 waves.

```
8 lanes  ×  481 waves  ≈  3844 threads   ✓
```

---

## Quiz

<details>
<summary>1. Which loop is hardware and which is software?</summary>

Wave loop = hardware (DCR relaunches the program per batch of 8). Branch loop =
software (the kernel uses CMP/BR to jump).

</details>

<details>
<summary>2. What exactly does CMP store, and where?</summary>

It computes `rs1 - rs2` and stores three flags in a register in `warp.sv`:
N (negative), Z (zero), P (positive). It writes no general register.

</details>

<details>
<summary>3. Why did the blur need the ALU changes but not the branch changes?</summary>

The blur is fully unrolled straight-line code, so it needs the extra math ops
(MUL/DIV/AND/OR/XOR/SLL/SRL) but never branches. Branches were a separate task.

</details>

<details>
<summary>4. The GPU has 8 lanes but runs 3844 threads. How?</summary>

The wave loop: each wave runs the program for 8 threads, then the DCR advances
`block_base` by 8 and relaunches, until all 3844 threads are covered.

</details>

---

## Sources

- The authoritative spec: `docs/PHASE2_ASSIGNMENT.md`, `docs/GPU_ISA.md` §Phase 2.
- Progress/checklist: `docs/PHASE2_PROGRESS.md`.
- The wave sequencer: `simt_gpu/rtl/dcr.sv`.
- Branch execution: `simt_gpu/rtl/warp.sv` (flags + `pc` redirect).
