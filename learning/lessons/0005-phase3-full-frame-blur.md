# Lesson 5 — Phase 3: the full-frame blur and the trace

This lesson uses Simplified Technical English. Each sentence is short. Each
word has one meaning.

> **Where this sits**
> ```
> learning/
> ├── PHASE2.md
> ├── PHASE3.md                              phase 3 hub
> └── lessons/
>     ├── 0001-what-are-you-building
>     ├── 0002-shared-bus-and-grant.md
>     ├── 0003-wiring-and-modules.md
>     ├── 0004-phase2-blur-and-branches.md
>     └── 0005-phase3-full-frame-blur.md    ← you are here
> ```

**Goal:** know what Phase 3 does, why it uses two passes, and how the trace
helps you.

---

## Warm-up

Cover the answers.

1. What does the wave loop do?
2. What does a branch do?

<details><summary>Answers</summary>

1. The wave loop runs the same program again for the next 8 threads. The DCR
   controls the wave loop. The wave loop is hardware.
2. A branch changes the program counter. The program jumps to another
   instruction. A branch makes a loop in software.

</details>

---

## 1. What Phase 3 does

Phase 2 blurred the interior of the image. The border stayed black.
Phase 3 blurs **every** pixel. Now the output image is complete.

Phase 3 does two more things:

- It blurs three image sizes. The sizes are 16x16, 32x32, and 64x64.
- It writes a trace file. The trace shows how the GPU worked.

Phase 3 does not change the hardware. It adds a new program, a two-pass
harness, and a trace.

---

## 2. The word "clamp"

A clamp keeps a value inside a limit.
A border pixel has no neighbor on one side. The sample coordinate is outside
the image.
Then the GPU uses the nearest edge pixel. This is a clamped sample.

Look at the pixel on the top-left corner. The sample for the row above is
outside the image. The GPU uses the top row again.

```
   real pixels          sample with clamp
   ┌───┬───┐            ┌───┬───┐
   │ A │ B │            │ A │ A │   ← row above copies row 0
   ├───┼───┤            ├───┼───┤
   │ C │ D │            │ C │ A │   ← left column copies column 0
   └───┴───┘            └───┴───┘
```

The GPU does this for each side. Then it averages the nine samples and divides
by nine.

---

## 3. Why the GPU uses two passes

The instruction memory holds 1024 words.
A single program for every pixel is too large.
So the design uses two programs:

1. The **interior** program. It writes the middle pixels.
2. The **border** program. It writes the edge pixels.

The wave loop runs each program many times. The interior program runs first.
The border program runs second.

```
   pass 1: interior        pass 2: border
   ┌───────────────┐       ┌───────────────┐
   │ . . . . . . . │       │ B B B B B B B │
   │ . I I I I I . │       │ B . . . . . B │
   │ . I I I I I . │       │ B . . . . . B │
   │ . . . . . . . │       │ B B B B B B B │
   └───────────────┘       └───────────────┘
        I = interior            B = border
```

---

## 4. The border mapping

Each border thread writes one border pixel.
The thread ids go in this order:

1. Top row. This includes both corners.
2. Bottom row. This includes both corners.
3. Left edge. This excludes the corners.
4. Right edge. This excludes the corners.

The number of border threads is:

```
border_threads = 2*W + 2*(H-2)
```

Example for 16x16: `2*16 + 2*14 = 60` border threads.

---

## 5. Why the border kernel has no branch

A warp has 4 lanes. The 4 lanes have 4 thread ids in a row.
A warp can cross a border region. Look at this example with W = 64:

```
   thread ids:  188   189   190   191
   region:      left  left  right right
                          ↑
                    the boundary is here
```

One warp holds both regions. If the kernel used a branch, the lanes would take
different paths. This hardware does not support that yet.
So the border kernel uses **arithmetic** to select the region. The kernel has
no branch. Each lane computes its own pixel. This is safe for every warp.

The register map shows the idea:

```
   x is in r2.  y is in r3.
   the kernel computes four candidate pixels.
   the kernel selects one candidate with a mask.
   the mask is 0 or 1. The mask comes from a comparison.
```

The instruction set has no `min`, `max`, or `select` instruction.
So the kernel cannot clamp a coordinate with one instruction.
The kernel does these steps for each clamped coordinate:

1. Compute the value `x - 1` or `x + 1`.
2. Get the sign bit. A shift to the right gives the sign bit.
3. Make a mask from the sign bit. The mask is 0 or all ones.
4. Use the mask to keep the value or to replace it.

The kernel uses about eight instructions for one clamped coordinate.
This is the reason the border kernel is long.

The kernel has only 13 registers. It keeps three rows, three columns, three
sums, and two temporaries. A person planned this order by hand.

---

## 6. Two passes, one memory

The testbench does these steps:

1. Load the source image one time.
2. Run the interior program.
3. Wait for `done`.
4. Load the border program.
5. Run the border program on the same memory.
6. Wait for `done` and dump the memory.

Do not reset the data memory between the passes.
The harness loads the second program and sends `start` again.
The GPU latches the new thread count and runs the second program.
The interior pass writes the middle pixels.
The border pass writes the edge pixels.
The source image does not change.

---

## 7. The trace

The testbench can write a trace file. Add `+trace=<path>` to the simulation.
The trace is text. Each line has a type and key/value pairs.
The trace has these line types:

| Line | Meaning |
|:--|:--|
| `CONFIG` | The image size and the memory addresses |
| `PASS_START` | A pass starts. It shows the thread count and the wave count |
| `GRANT` | The scheduler grants a warp. It shows the warp and the instruction address |
| `BUS` | A memory read or write. It shows the address |
| `PASS_DONE` | A pass is complete |
| `SUMMARY` | The totals for the run |

Example for 64x64:

```
CONFIG width=64 height=64 src=8192 dst=24576
PASS_START cycle=1 pass=interior threads=3844 waves=481
PASS_DONE  cycle=289526 pass=interior
PASS_START cycle=289528 pass=border threads=252 waves=32
PASS_DONE  cycle=317203 pass=border
SUMMARY cycles=317207 reads=36864 writes=4096 grants_warp0=158126 grants_warp1=158044
```

The trace is deterministic. A checker reads the trace and tests the numbers.
The checker also tests that each output pixel is written one time.

---

## 8. The numbers

These are the measured results on the RTL:

| Size | interior + border threads | cycles | reads | writes |
|---:|---:|---:|---:|---:|
| 16x16 | 196 + 60 | 21911 | 2304 | 256 |
| 32x32 | 900 + 124 | 81815 | 9216 | 1024 |
| 64x64 | 3844 + 252 | 317207 | 36864 | 4096 |

The number of reads is easy to check. Each thread reads 9 samples.
The interior pass reads `3844 * 9` words. The border pass reads `252 * 9`
words. The total is 36864 reads. Each thread writes one pixel. The total is
4096 writes.

---

## 9. How to run it

Go to the `simt_gpu` directory. Then use these commands:

```sh
make blur16        # clamped full-frame blur, 16x16
make blur32        # clamped full-frame blur, 32x32
make blur64        # clamped full-frame blur, 64x64
make trace SIZE=64 # run one trace and check it
make phase3        # the full Phase 1-3 regression
```

---

## Quiz

<details>
<summary>1. What is a clamped sample?</summary>

A sample coordinate outside the image uses the nearest edge pixel. The GPU
does this for each of the nine samples.

</details>

<details>
<summary>2. Why does Phase 3 use two passes?</summary>

The instruction memory is too small for one program. Two small programs fit.
The interior program writes the middle pixels. The border program writes the
edge pixels.

</details>

<details>
<summary>3. Why does the border kernel have no branch?</summary>

A warp can cross a border region. A branch would make the lanes diverge. This
hardware does not support divergence. So the kernel selects the region with
arithmetic.

</details>

<details>
<summary>4. How many reads does a 64x64 clamped blur do?</summary>

Each thread reads nine samples. The interior pass has 3844 threads. The border
pass has 252 threads. The total is `(3844 + 252) * 9 = 36864` reads.

</details>

---

## Sources

- The specification: `docs/PHASE3_ASSIGNMENT.md`.
- The measured results: `docs/PHASE3_PROGRESS.md`.
- The reference: `simt_gpu/tools/blur_ref.py`.
- The border generator: `simt_gpu/tools/assemble.py`.
- The trace checker: `simt_gpu/tools/check_trace.py`.
