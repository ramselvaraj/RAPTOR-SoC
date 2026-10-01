# Lesson 3 (condensed) — Wiring, the Person A modules, and integration

> **This one file replaces Lessons 3–8.** It is the rest of the course:
> the wiring, each module you own, and how it all gets proven.
>
> ```
> learning/
> ├── lessons/
> │   ├── 0001-what-are-you-building         the SIMT big picture
> │   ├── 0002-shared-bus-and-grant.md       bus + arbitration
> │   └── 0003-wiring-and-modules.md         ← you are here (everything else)
> ```
>
> Read 0001 and 0002 first. This assumes warp / lane / ready / grant.

---

## The map of everything you own

| # | File | Job in one line | Unit test |
|:--:|:--|:--|:--|
| A | `rtl/dcr.sv` | Latch launch config; own `busy`/`done` | `make unit TEST=tb_dcr` |
| B | `rtl/dispatcher.sv` | Thread count → per-warp start / tid base / lane mask | `make unit TEST=tb_dispatcher` |
| C | `rtl/scheduler.sv` | Fairly pick one ready warp per cycle | `make unit TEST=tb_scheduler` |
| D | `rtl/mem_unit.sv` | Walk lanes one at a time over the single bus | *(proved by `make run`)* |
| E | `rtl/simt_gpu.sv` | Wire A–D + warps together; mux granted warp onto bus | *(proved by `make run`)* |
| W | `rtl/alu.sv` **or** `decoder.sv` | Warm-up: pick one to implement | `tb_alu` / `tb_decoder` |

Mental order: **A → B → C → D → E**, with the warm-up W first.

---

# Part 1 — The wiring (`rtl/simt_gpu.sv`)

This file is *provided* (not a TODO), but you must **verify** it. It is where the
grant-based mux lives.

```
 start ─►┌─────┐ threads_q ┌────────────┐ warp_start,warp_tid_base,warp_lane_mask
         │ DCR │──────────►│ DISPATCHER │───────────────┬───────────┐
         │  A  │ src_q/dst_q            A? B           ▼           ▼
         └──┬──┘            └────────────┘        ┌─────────┐ ┌─────────┐
            │ busy/done                           │ WARP 0  │ │ WARP 1  │
            │                                     │Person B │ │Person B │
            │  all_halted ◄───────────────────────┴────┬────┴────┬────┘
            │                                    ready│         │ready
            │                              ┌──────────┐│         │
            │                              │SCHEDULER │◄─────────┘
            │                              │    C     │
            │                              └────┬─────┘ grant[]
            │                                   │
            │         ┌──────────────────────────────────┐
            └─────────┤  grant-mux: pick w_mem_*/w_imem_* │──► imem + data bus
                      │  of the single granted warp      │
                      └──────────────────────────────────┘
```

The mux, in words (`simt_gpu.sv` ~lines 106–122):

```
for each warp w:
    if grant[w]:
        imem_addr = w_imem_addr[w]
        mem_req   = w_mem_req[w]
        mem_we    = w_mem_we[w]
        mem_addr  = w_mem_addr[w]
        mem_wdata = w_mem_wdata[w]
all_halted = &warp_halted
```

### The trap you must not miss

`grant` comes from the scheduler, and the scheduler only looks at `ready`. The
warp header says `ready` is high in `W_FETCH`/`W_EXEC` **only**.

Now trace a load:

```
  W_EXEC ──(granted)──► starts mem_unit, goes to W_MEM
  W_MEM:  ready = 0  →  scheduler never grants  →  mux never selects its
          mem_req  →  the load never reaches memory  →  deadlock
          → tb_gpu watchdog fires after 200000 cycles
```

You also **cannot** mux on `mem_req` alone, because sooner or later two warps
can both be sitting in `W_MEM` and would fight over the bus.

**Resolution (an interface agreement with Person B):** a warp that is waiting on
memory must keep `ready` high in `W_MEM`, so the scheduler can grant it and the
existing mux just works. `warp.sv` is Person B's file — this is exactly the
"tell the other person first" clause. Say it explicitly:

> `ready` = "I may need the shared bus this cycle" = high in `W_FETCH`,
> `W_EXEC`, and `W_MEM`.

---

# Part 2 — DCR (`rtl/dcr.sv`)

**What it is:** the launch register. Not a datapath; a handshake.

```
       reset
         │
         ▼
    ┌─────────┐   start    ┌─────────┐   busy && all_halted   ┌─────────┐
    │  IDLE   │───────────►│  BUSY   │───────────────────────►│  DONE   │
    │ busy=0  │  latch q   │ busy=1  │   busy<=0, done<=1     │ busy=0  │
    └─────────┘            └─────────┘   (one cycle)          └────┬────┘
                                                                   │
                                                          back to IDLE
```

**Contract, read off `tb/unit/tb_dcr.sv`:**
- `start` high for one edge → next cycle `busy=1` and `thread_count_q / src_q / dst_q` equal the inputs.
- `all_halted=1` while busy → next cycle `busy=0`, `done=1`.
- the cycle after → `done=0`. **One-cycle pulse.**

**Shape** (`always_ff @(posedge clk or posedge reset)`):

```
if reset: clear everything
else:
    done <= 0;                 // default every cycle  ← this creates the pulse
    if (start):                // highest priority
        busy <= 1; q <= inputs;
    else if (busy && all_halted):
        busy <= 0; done <= 1;
```

**Pitfalls**
- No default `done <= 0` → `done` sticks high forever.
- Updating `_q` every cycle instead of only on `start` → they follow the inputs.
- `else if` order: `start` must win over the halt condition.

Run: `make unit TEST=tb_dcr` → `TB_DCR PASS`.

---

# Part 3 — Dispatcher (`rtl/dispatcher.sv`)

**What it is:** pure combinational fan-out. No clock in its ports. It answers
*"given N threads, which warps/lanes are alive, and where does each warp start?"*

```
   thread_count = 6
        │
        ▼
   warp 0: tid_base 0, lanes 0 1 2 3          threads 0 1 2 3  ← all full
   warp 1: tid_base 4, lanes 0 1 0 0          threads 4 5      ← lanes 2,3 off
```

**Contract from `tb_dispatcher.sv`:**

| `thread_count` | warp 0 mask | warp 1 mask |
|:--:|:--:|:--:|
| 6 | `1111` | `0011` |
| 1 | `0001` | `0000` |
| 0 | `0000` | `0000` |
| 8 | `1111` | `1111` |

And `warp_start` follows `start` for **all** warps (don't gate it by mask);
`start=0` → `warp_start = 00`.

**The formula:**
```
for w in 0..WARPS-1:
    warp_tid_base[w] = w*LANES                     // constant
    warp_start[w]    = start
    for l in 0..LANES-1:
        tid = w*LANES + l
        warp_lane_mask[w][l] = (tid < thread_count)
```

**Pitfalls**
- Signedness: `w*LANES + l` is a signed `int`; `thread_count` is `logic [31:0]`.
  Cast: `32'(w*LANES + l) < thread_count`.
- Use the `WARPS`/`LANES` parameters, not magic `2`/`4`.

Run: `make unit TEST=tb_dispatcher` → `TB_DISPATCHER PASS`.

---

# Part 4 — Scheduler (`rtl/scheduler.sv`)

You already learned the concept in Lesson 2. Here is only the module-specific
part.

**Ports:** `clk, reset, ready[WARPS]` → `grant[WARPS]`.

**Split the work (this is the whole design):**

```
  always_comb  ── computes grant from ready + last        (blocking =)
  always_ff    ── remembers last, advances it on a grant  (nonblocking <=)
```

```
grant = '0; found = 0;
for i in 0..WARPS-1:
    w = (last + i) % WARPS
    if (!found && ready[w]):
        grant[w] = 1; found = 1;

// always_ff:
if (reset)            last <= 0;
else for i: if (grant[i]) last <= (i + 1) % WARPS;
```

**Contract from `tb_scheduler.sv`:**
- no ready → `grant=00`; solo ready → that warp every cycle;
- both ready → alternate, 4 each over 8 cycles; never two bits set.

**Pitfalls**
- Don't drive `grant` from both blocks (multiple drivers). Comb only.
- Use a `found` flag rather than `break` (portable, Verilator-friendly).
- Reset `last`, or the first grant is non-deterministic.

Run: `make unit TEST=tb_scheduler` → `TB_SCHEDULER PASS`.

---

# Part 5 — Memory unit (`rtl/mem_unit.sv`)

**What it is:** the uncoalesced baseline. A SIMT `LDR`/`STR` is per-lane, but the
bus moves one word per cycle, so the unit walks lanes 0…LANES-1 and skips the
masked-off ones.

```
  lane_mask = 1 1 0 1        lane_ptr walks:  0 ──► 1 ──► 2(skip) ──► 3 ──► done
  bus xfers:              ──►xfer──►xfer──────────────►xfer──────────►  done pulse
  load_data[0..3] captured as reads come back
```

**Interface:** `start, is_store, lane_mask[], base_val[], idx_val[], data_val[]`
in; `mem_req, mem_we, mem_addr, mem_wdata` out to the bus; `mem_rdata, mem_ready`
in; `load_data[]` and `done` out.

**The skeleton has no state** — everything is in one `always_comb`. You must add
`busy`, a lane pointer, and the `load_data` storage.

**Shape:**

```
// combinational: find first active lane at/after lane_ptr
mem_req = 0; cur_valid = 0;
for l in lane_ptr..LANES-1:
    if (lane_mask[l] && !cur_valid): cur = l; cur_valid = 1;
if (busy && cur_valid):
    mem_req   = 1;
    mem_we    = is_store;
    mem_addr  = base_val[cur] + idx_val[cur];
    mem_wdata = data_val[cur];

// sequential:
if reset: busy=0, lane_ptr=0, done=0, load_data[]=0
else:
    done <= 0;
    if (start):      busy<=1; lane_ptr<=0; clear load_data;
    else if (busy):
        if (cur_valid && mem_req && mem_ready):
            if (!is_store) load_data[cur] <= mem_rdata;
            lane_ptr <= cur + 1;
        else if (!cur_valid):      // walked past the last active lane
            busy <= 0; done <= 1;
```

**Pitfalls**
- **Pointer width:** 0…LANES needs `$clog2(LANES+1)` bits (3 for LANES=4).
  `$clog2(LANES)` = 2 bits wraps at 4 — classic bug.
- Don't assert `mem_req` on a masked-off lane; skip it.
- All-masked warp (e.g. beyond thread count) must still pulse `done`, or it never
  halts and `all_halted` never fires.
- Gate progress on `mem_ready` even though Phase 1 ties it to 1.
- `load_data` is storage: drive it from the flop, not from comb (multiple drivers).

There is no unit test; `make build` + `make run` is the test.

---

# Part 6 — Integration, milestones, and a real blocker

## Milestones

| # | What | Command / evidence |
|:--:|:--|:--|
| M1 | All six unit tests pass | `TB_<NAME> PASS` each |
| M2 | Copy round-trip | `python3 tools/run_sim.py --kernel sw/kernels/copy.asm` |
| M3 | Brighten | `make run` → `PASS: 256 threads, 0 mismatches` |
| M4 | Both warps progress | the alternating grant trace from Lesson 2 |
| M5 | Lane masking | edit `.threads` to a non-multiple of 4 → inactive lanes write nothing |

## The blocker nobody wrote down: 256 threads cannot fit in 8 lanes

Do the arithmetic before you chase your tail at M3.

```
WARPS = 2, LANES = 4                (the "decided" config)
max thread index the hardware can name
    = w*LANES + l for w∈{0,1}, l∈{0..3}
    = 0 .. 7                        →  8 distinct threads

brighten.asm:      .threads 256
run_sim default:   16 x 16 = 256 pixels
golden model:      for tid in range(256)   → writes dst[0..255]
```

So the RTL can only ever write `dst[0..7]`. The golden model expects
`dst[0..255]`. `make run` compares all 256 and will report ~248 mismatches — no
bug in your modules can fix that, because `r0` is `tid_base + lane` and neither
side of that sum can reach 8.

**This is an assignment/spec inconsistency, not a bug in your code.** Before you
burn hours on it, confirm with the course staff / your partner. The likely
resolutions:

1. The acceptance run is meant to be a small image whose thread count is
   `≤ WARPS*LANES` (e.g. `.threads 8`), and the "256" in the docs is aspirational.
2. The design is meant to grow `WARPS`/`LANES` (or add a per-warp thread-stride
   loop) — but that needs a *new port* to advance `tid_base`, which the frozen
   interface does not have, so this contradicts "ports are frozen".

Either way: get an explicit answer, and if the doc is wrong, request that
`docs/PHASE1_ASSIGNMENT.md` be updated. Do **not** silently change frozen ports.

## Definition of done (Person A)

- `tb_dcr`, `tb_dispatcher`, `tb_scheduler` pass; warm-up unit passes.
- `mem_unit` + `simt_gpu` verified by `make run`.
- `ready`-in-`W_MEM` agreed with Person B.
- Thread-count question resolved and written down.
- No frozen port changed without the partner's agreement.

---

## Consolidated quiz

<details>
<summary>1. Which module turns a thread count into lane masks, and is it clocked?</summary>

The dispatcher. It is purely combinational — its ports have no clock, because the
mapping is a function of the current inputs only.

</details>

<details>
<summary>2. What is the one default assignment in the DCR that creates the one-cycle `done` pulse?</summary>

`done <= 1'b0` at the top of the non-reset branch every cycle; the halt condition
then overrides it to 1 for exactly one edge.

</details>

<details>
<summary>3. Why must a warp in `W_MEM` still assert `ready`?</summary>

Because the bus mux only selects the warp the scheduler grants, and the scheduler
only grants `ready` warps. If a memory-waiting warp drops `ready`, its request
never reaches the port and the machine deadlocks.

</details>

<details>
<summary>4. How many bits does the mem_unit lane pointer need for LANES=4, and why not 2?</summary>

Three bits (`$clog2(LANES+1)`). Two bits can only represent 0–3, so the "past the
last lane" value of 4 would wrap and the unit would never finish.

</details>

<details>
<summary>5. `make run` reports 248 mismatches with correct-looking RTL. What is the most likely cause?</summary>

The config/thread-count inconsistency: `WARPS*LANES = 8` threads can execute, but
the kernel and golden model expect 256. Confirm with staff before changing code.

</details>

---

## Sources

- Round-robin pointer and fairness: [FPGA CPU — Round-Robin Arbiter](https://fpgacpu.ca/fpga/Arbiter_Round_Robin.html),
  [Yildiz, "Arbiters: Design Ideas and Coding Styles"](https://abdullahyildiz.github.io/files/Arbiters-Design_Ideas_and_Coding_Styles.pdf).
- Handshake background: [FPGA CPU — Ready/Valid Handshake Rules](https://fpgacpu.ca/fpga/handshake.html).
- Local spec: `docs/PHASE1_ASSIGNMENT.md`, `docs/BUS_PROTOCOL.md`, `docs/GPU_ISA.md`.
- `always_comb`/`always_ff` refresh: [UW CSE371 SystemVerilog Tutorial](https://courses.cs.washington.edu/courses/cse371/24sp/verilog/Verilog_Tutorial.pdf).
