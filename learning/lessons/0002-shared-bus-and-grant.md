# Lesson 2 — The shared bus and the grant

> **Where this sits**
> ```
> learning/
> ├── MISSION.md                          why we're doing this
> ├── RESOURCES.md                        grounded sources
> ├── NOTES.md                            plan + your preferences
> └── lessons/
>     ├── 0001-what-are-you-building     ← the big picture
>     └── 0002-shared-bus-and-grant.md   ← you are here
> ```

**Goal of this lesson:** be able to say, in one breath, *why* two warps cannot
both use memory on the same cycle, and *how* the scheduler decides who does.

---

## Warm-up (recall before reading)

Cover the answers. From Lesson 1:

1. What do the four lanes of a warp share?
2. What does `r0` hold?
3. Who owns the scheduler, you or Person B?

<details><summary>Answers</summary>

1. One program counter, one instruction fetch, one decoder.
2. That lane's global thread index — how it finds its own pixel.
3. You (Person A).

</details>

---

## 1. The problem: many masters, one memory

Two warps each want to run instructions and load/store data. But there is a
single memory port. If both drove it at once, you'd get two values fighting over
the same wires.

```
      WARP 0                    WARP 1
     ┌────────┐                ┌────────┐
     │ "I want│                │ "I want│
     │  the   │                │  the   │
     │  bus"  │                │  bus"  │
     └───┬────┘                └────┬───┘
         │  request                request │
         └──────────┬──────────────┬───────┘
                    ▼              ▼
              ┌────────────────────────┐
              │       SCHEDULER        │   exactly one winner per cycle
              └───────────┬────────────┘
                          │  grant (one-hot)
                          ▼
              ┌────────────────────────┐
              │   SHARED MEMORY PORT   │   one transfer per cycle,
              └────────────────────────┘   no exceptions
```

The scheduler is an **arbiter**: a circuit that picks exactly one requester and
"grants" it the resource for this cycle. Everything else waits.

---

## 2. What a "bus" actually is

Strip away the jargon: a bus is just a bundle of wires with an agreed meaning.

- Some wires carry the **address** you want to touch.
- Some carry **data** going in or coming out.
- A few carry **control** bits: *is anyone asking?*, *is it a read or a write?*,
  *is the memory answering?*

Two devices agree on the protocol; the wires don't care who is attached. In this
design the GPU is the only device on the phase-1 bus, but the protocol is written
so a CPU could share it later (see `docs/BUS_PROTOCOL.md`).

The signals you will wire up:

| Signal | Direction | Meaning |
|---|---|---|
| `mem_req` | master → memory | "I want a transfer this cycle" |
| `mem_we` | master → memory | 1 = write, 0 = read |
| `mem_addr` | master → memory | **word** address (not bytes) |
| `mem_wdata` | master → memory | write data |
| `mem_rdata` | memory → master | read data |
| `mem_ready` | memory → master | "transfer completes this cycle" |

---

## 3. Your bus's contract: single-cycle, combinational

Most buses you may have met (AXI, ready/valid) take **two or more** cycles: the
master asserts `valid`, then *later* the slave asserts `ready`, and the transfer
happens when they overlap. That handshake style exists to tolerate slow or
variable-latency slaves.

Phase 1 deliberately throws that away. The rule is in `docs/BUS_PROTOCOL.md`:

> A master asserts `mem_req` (and address/`we`/data). The slave returns
> `mem_ready` **in the same cycle**. Reads are combinational: `mem_rdata` is
> valid in the same cycle. No valid/ack phases, no burst.

So one read looks like this:

```
cycle:      1      2      3
          ┌────┐ ┌────┐ ┌────┐
clk      ─┘    └─┘    └─┘    └─

mem_req     0      1      0
mem_we      0      0      0
mem_addr    --   0x2007   --
mem_rdata   --   value    --     ← already valid, same cycle
mem_ready   1      1      1      ← memory is never busy in Phase 1
```

**Why this matters:** because the answer is *combinational*, there is exactly
one cycle in which a master may use the bus. You cannot "hold" it across cycles.
That makes arbitration a per-cycle decision, which is exactly what the
scheduler's one-hot `grant` expresses.

---

## 4. Two kinds of traffic share this one bus

Here is the part that surprises people. The **instruction fetch** and the
**data load/store** use the *same* port. A warp that wants its next instruction
and a warp that wants to load a pixel are competitors for one resource.

```
        instruction fetch          data load / store
              │                          │
              └────────────┬─────────────┘
                           ▼
                   ┌───────────────┐
                   │  ONE PORT     │
                   └───────────────┘
```

Consequences:

- A warp that is waiting on a memory access still needs to be **grantable**, or
  its load/store can never reach the port.
- Granting one warp stalls everyone else for that cycle — but only one cycle.

---

## 5. The vocabulary: `ready` vs `grant`

These two words sound similar. They are different questions:

| Signal | Who drives it | The question it answers |
|---|---|---|
| `ready[w]` | the **warp** | "Am I in a state where I could use the bus now?" |
| `grant[w]` | the **scheduler** | "You, warp `w`, may use the bus *this* cycle." |

`ready` is information *into* the arbiter. `grant` is the decision *out* of it.
A warp can be ready and still not be granted (someone else won this cycle); a
warp must never be granted while not ready.

```
  ready[0] ──┐
             ├──►┌───────────┐
  ready[1] ──┘   │ SCHEDULER │──► grant[0]
                 │           │──► grant[1]      (exactly one high, or none)
                 └───────────┘
```

---

## 6. Round-robin: fairness by rotating the starting point

The naive arbiter is a **fixed-priority** arbiter: "lowest index ready always
wins." Simple, one line of logic — and unfair. If warp 0 is ready every cycle,
warp 1 starves forever.

A **round-robin** arbiter fixes this with one extra piece of state: a pointer,
call it `last`, remembering who won most recently. Each cycle you scan starting
*just after* `last`, wrapping around, and grant the first ready warp you find.
Then you advance `last` past the winner.

Picture it with two warps:

```
both ready, last = 0
   priority order is:   0 then 1
   winner = 0        →   grant = 01,  last becomes 1

both ready, last = 1
   priority order is:   1 then 0
   winner = 1        →   grant = 10,  last becomes 0
```

So the priority order rotates, and nobody can monopolise the bus.

### The scan, in words

```
for i in 0 .. WARPS-1:
    w = (last + i) mod WARPS
    if ready[w]:
        grant[w] = 1
        stop        # only one winner
```

`grant` is **one-hot**: exactly one bit set, or all zero when nobody is ready.

---

## 7. Why the pointer must live in a flip-flop

`grant` is combinational — it follows `ready` and `last` immediately, no clock
needed. But `last` is **memory**: it must survive to the next cycle. So:

```
        ready[]                         ┌──────────────┐
           │                            │  always_ff   │
           ▼                            │   last <=    │
     ┌──────────────┐   next_last       │  (winner+1)  │
     │  scan from   ├──────────────────►│              │
     │    last      │                   └──────┬───────┘
     └──────┬───────┘                          │ last
            │ grant (comb)                     │
            └──────────────────────────────────┘
```

This is the standard split you already know: **combinational logic decides, a
flip-flop remembers.** Test that split and everything falls out.

---

## 8. Worked trace

Let `ready = 11` (both warps hungry) and start `last = 0`.

| cycle | `last` | scan order | `grant[1:0]` | next `last` |
|:---:|:---:|:---:|:---:|:---:|
| 1 | 0 | 0, 1 | `01` | 1 |
| 2 | 1 | 1, 0 | `10` | 0 |
| 3 | 0 | 0, 1 | `01` | 1 |
| 4 | 1 | 1, 0 | `10` | 0 |
| 5 | 0 | 0, 1 | `01` | 1 |
| 6 | 1 | 1, 0 | `10` | 0 |

Over 8 cycles: 4 grants each. Perfectly fair — that is milestone **M4**
("both warps make progress").

Now `ready = 01` (only warp 0 wants it) and start `last = 1`:

| cycle | `last` | scan order | `grant[1:0]` | next `last` |
|:---:|:---:|:---:|:---:|:---:|
| 1 | 1 | 1, 0 | `01` | 1 |
| 2 | 1 | 1, 0 | `01` | 1 |
| 3 | 1 | 1, 0 | `01` | 1 |

The scan passes over the idle warp 1 and keeps granting warp 0 every cycle.
Correct: fairness only matters among the *ready*.

And `ready = 00`:

| cycle | `last` | `grant[1:0]` | next `last` |
|:---:|:---:|:---:|:---:|
| 1 | 0 | `00` | 0 |

No ready, no grant, pointer holds.

---

## 9. Why this is *your* problem

This diagram is the assignment, split in two:

```
   ready[0] ──────────►┌────────────┐
   ready[1] ──────────►│ SCHEDULER  │──► grant[0] ──► bus mux ──► memory
                       │ (Person A) │──► grant[1]
                       └────────────┘
        ▲
        │ ready[0], ready[1]
   ┌────┴─────────────┐
   │  WARP 0 / WARP 1 │   Person B decides when a warp is ready
   │  (Person B)      │
   └──────────────────┘
```

- **You** own the arbiter (`rtl/scheduler.sv`) and the bus mux (`rtl/simt_gpu.sv`).
- **Person B** owns the `ready` signal inside `rtl/warp.sv`.

That boundary is exactly the thing the assignment warns about: *"if you need to
change a port, tell the other person first."* You can't test your scheduler in
integration until you two agree what `ready` means.

> **Hold that thought for Lesson 3.** There is a subtle trap here: a warp that
> is *waiting for its load/store to finish* must still assert `ready`, because
> otherwise the scheduler never grants it and its memory access never reaches
> the port. We'll make that concrete when we look at the whole machine's wiring.

---

## Quiz (markdown, no browser required)

<details>
<summary>1. What does the scheduler hand out each cycle, and how many?</summary>

Exactly one `grant` bit — one warp's exclusive use of the shared bus for that
cycle. If no warp is ready, it hands out nothing (all-zero grant).

</details>

<details>
<summary>2. Why does `last` have to be a flip-flop instead of a wire?</summary>

Because it must remember the previous winner into the next cycle. `grant` is
combinational (it reacts instantly to `ready` + `last`), but state that persists
across cycles lives in an `always_ff` register.

</details>

<details>
<summary>3. With both warps ready forever, what does a fixed-priority arbiter do wrong, and how does round-robin fix it?</summary>

Fixed priority always picks the same (e.g. lowest-index) warp, so the other
starves. Round-robin rotates the scan's starting point past the last winner, so
each ready warp gets a turn.

</details>

<details>
<summary>4. Instruction fetch and data load both want one port. What does that imply for a warp doing a load?</summary>

Its memory request competes with instruction fetches, so the warp must remain
grant-eligible (assert `ready`) while it waits for the load to complete — or its
request never reaches the port.

</details>

---

## Primary sources

- **Bus handshake:** [FPGA CPU — Ready/Valid Handshake Rules](https://fpgacpu.ca/fpga/handshake.html)
  — read this to understand the *multi-cycle* handshake this design deliberately
  does not use, and why.
- **Arbitration:** [FPGA CPU — Round-Robin Arbiter](https://fpgacpu.ca/fpga/Arbiter_Round_Robin.html)
  and [Yildiz, "Arbiters: Design Ideas and Coding Styles"](https://abdullahyildiz.github.io/files/Arbiters-Design_Ideas_and_Coding_Styles.pdf)
  — the "rotate + priority" idea, and why where you move the pointer matters.
- **The authoritative local spec:** `docs/BUS_PROTOCOL.md`.

---

When you're ready, say so and we'll do **Lesson 3 — the wiring: how
`simt_gpu.sv` connects these blocks**, where that "ready in MEM" trap becomes
visible.
