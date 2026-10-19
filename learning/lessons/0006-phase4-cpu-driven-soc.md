# Lesson 6 — Phase 4: the CPU-driven SoC

This lesson uses Simplified Technical English. Each sentence is short. Each
word has one meaning.

> **Where this sits**
> ```
> learning/
> ├── PHASE2.md
> ├── PHASE3.md
> ├── PHASE4.md                              phase 4 hub
> └── lessons/
>     ├── 0004-phase2-blur-and-branches.md
>     ├── 0005-phase3-full-frame-blur.md
>     └── 0006-phase4-cpu-driven-soc.md      ← you are here
> ```

**Goal:** know how CPU software starts the GPU, how AXI transfers work, and
why the control path and pixel path are separate.

---

## Warm-up

Cover the answers.

1. Which component started each GPU pass in Phase 3?
2. Why does the full-frame blur need two GPU programs?

<details><summary>Answers</summary>

1. The SystemVerilog testbench started each pass in Phase 3.
2. One program writes the interior. The other program writes the border.

</details>

---

## 1. What Phase 4 does

Phase 3 already made the correct full-frame blur.
However, the testbench still controlled both GPU launches.
Phase 4 moves this job to the RISC-V CPU.

The CPU now does these tasks:

1. Write the source address.
2. Write the destination address.
3. Write the thread count.
4. Select the GPU program.
5. Start the GPU.
6. Read the status until the GPU completes the pass.
7. Repeat the sequence for the second pass.

The blur calculation does not change.
The control authority changes.

```
PHASE 3                              PHASE 4
───────                              ───────
testbench selects program       →    CPU writes PROG_BASE
testbench sends start           →    CPU writes CTRL.start
testbench waits for done        →    CPU polls STATUS.done
Python checks the result        →    Python still checks the result
```

---

## 2. The complete SoC picture

The system has one CPU and one GPU.
It also has one shared data memory.

```
                    private CPU instruction memory
                               │
                               ▼
                         RISC-V CPU
                               │ memory request
                               ▼
                        CPU AXI master
                               │
                               ▼
                    AXI4-Lite interconnect
                         │             │
                         ▼             ▼
                    AXI RAM slave   GPU MMIO
                         │             │ control
                         ▼             ▼
                    shared RAM ◄── pixel bus ── GPU
                         ▲                       ▲
                         │                       │
                    host port              GPU program memory
```

The CPU instruction memory is private.
The GPU program memory is also private.
The shared RAM stores system data and both framebuffers.

`soc/rtl/soc_top.sv` connects these modules.
It does not implement their internal behavior.

---

## 3. Two paths with two jobs

Phase 4 uses two different communication paths.
Do not treat them as one bus.

| Path | User | Purpose | Address unit |
|:--|:--|:--|:--|
| AXI4-Lite control path | CPU | write GPU settings and read status | byte |
| GPU pixel path | GPU lanes | read source pixels and write destination pixels | word |

The CPU does not send every pixel through the MMIO registers.
The CPU only starts the work.
The GPU moves pixels through its existing simple bus.

This separation keeps the Phase 1 through Phase 3 GPU interface unchanged.

```
control path: CPU ──AXI──► MMIO ──► start, threads, addresses, program
pixel path:   GPU ──simple bus──► shared RAM
```

---

## 4. Byte addresses and word addresses

RISC-V and AXI use byte addresses.
The GPU pixel bus uses word addresses.
One word contains four bytes.

Use this conversion for shared RAM:

```
CPU byte address = GPU word address << 2
GPU word address = CPU byte address >> 2
```

| Region | CPU byte address | GPU word address |
|:--|--:|--:|
| source framebuffer | `0x0000_8000` | `0x2000` |
| destination framebuffer | `0x0001_8000` | `0x6000` |

Example:

```
0x2000 << 2 = 0x8000
```

The MMIO `SRC` and `DST` registers contain GPU word addresses.
Thus, the CPU writes `0x2000` and `0x6000` into these registers.

---

## 5. AXI4-Lite is a handshake protocol

AXI4-Lite moves one 32-bit value per transaction in this design.
The sender asserts `VALID` when a payload is available.
The receiver asserts `READY` when it can accept the payload.
The transfer occurs when both signals are 1.

```
transfer = VALID && READY
```

The sender must keep the payload stable while it waits.
The receiver can delay `READY`.
This delay is backpressure.

AXI uses five channels:

| Channel | Purpose |
|:--|:--|
| `AW` | write address |
| `W` | write data and byte strobes |
| `B` | write response |
| `AR` | read address |
| `R` | read data and response |

A write needs three channel handshakes.
A read needs two channel handshakes.

```
write: AW ──► W ──► B
read:  AR ──► R
```

The protocol permits separate write-address and write-data timing.
The RAM and MMIO slaves save each part until both parts arrive.

---

## 6. The CPU AXI master

The CPU has a small request interface.
The CPU does not directly control all five AXI channels.
`cpu_axi_master.sv` converts one CPU request into one AXI transaction.

Its write states are:

```
A_IDLE → A_AW → A_W → A_B → A_DONE → A_IDLE
```

Its read states are:

```
A_IDLE → A_AR → A_R → A_DONE → A_IDLE
```

The master saves the address and write data in `A_IDLE`.
It holds each `VALID` signal until the slave asserts `READY`.
It pulses `done` after the response arrives.

The CPU controller has memory wait states.
An `LW` or `SW` instruction stays in a wait state until `done` arrives.
This behavior prevents a slow AXI transfer from being lost.

---

## 7. The interconnect selects and routes

The AXI interconnect has two master ports and two slave ports.
The integrated SoC uses master 0 for the CPU.
The AXI testbench also tests master 1.

The slave ports have these purposes:

```
slave 0 = shared RAM
slave 1 = GPU MMIO
```

The address selects the slave.
An address with top hexadecimal digit `4` selects GPU MMIO.
Other valid system addresses select RAM.

The interconnect also selects a master.
If both masters request access, a round-robin rule selects one master.
The interconnect keeps that selection until the response completes.

```
request → select master → select slave → hold route → accept response
```

The held route is important.
Without it, a response could return to a different master.

---

## 8. MMIO turns stores into GPU control

Memory-mapped input/output is called MMIO.
MMIO gives hardware registers normal memory addresses.
The CPU uses `SW` and `LW` instructions to access these registers.

The GPU MMIO base address is `0x4000_0000`.

| Offset | Register | CPU action | Hardware result |
|--:|:--|:--|:--|
| `0x00` | `CTRL` | write bit 0 as 1 | send a one-cycle `start` pulse |
| `0x04` | `STATUS` | read | get `busy` and `done` |
| `0x08` | `THREADS` | write | set the thread count |
| `0x0C` | `SRC` | write | set the source word address |
| `0x10` | `DST` | write | set the destination word address |
| `0x14` | `PROG_BASE` | write | select the GPU program offset |

The native GPU `done` output lasts for one cycle.
CPU polling can miss a one-cycle pulse.
Therefore, `gpu_mmio.sv` saves completion in `done_sticky`.

```
GPU pulses done       → done_sticky becomes 1
CPU reads STATUS      → bit 1 stays 1
CPU writes next start → done_sticky becomes 0
```

This register converts a short hardware event into durable software state.

---

## 9. How the CPU runs both passes

The CPU driver uses two copies of the same control sequence.
The first copy selects the interior program.
The second copy selects the border program.

The GPU program memory contains both programs:

```
word 0                 interior program
word 512               border program
```

`PROG_BASE` changes the GPU instruction address:

```
program memory index = PROG_BASE + GPU pc
```

The first pass uses 3,844 threads for a 64x64 frame.
The second pass uses 252 threads.

The CPU driver has this shape:

```asm
# interior pass
sw   x6, 12(x5)       # SRC = 0x2000
sw   x7, 16(x5)       # DST = 0x6000
sw   x8,  8(x5)       # THREADS = interior count
sw   x10,20(x5)       # PROG_BASE = 0
sw   x12, 0(x5)       # CTRL.start = 1
poll1:
lw   x13, 4(x5)       # read STATUS
and  x15,x13,x14      # keep done bit
beq  x15,x0,poll1     # repeat if done is 0

# border pass uses x9 threads and PROG_BASE = 512
```

The testbench initializes registers with the large constants.
The CPU instruction subset does not include `LUI`.

---

## 10. Why the CPU needed new instructions

The Phase 4 driver needs constants, loops, and function-style jumps.
The CPU therefore adds `ADDI`, `BNE`, and `JAL`.

| Instruction | Purpose |
|:--|:--|
| `ADDI` | add a small immediate value |
| `BNE` | branch when two values differ |
| `JAL` | jump and save a return address |

The driver also uses the existing `LW`, `SW`, `AND`, and `BEQ` instructions.
The memory instructions now wait for an external completion signal.

The CPU fetch path stays private.
Only CPU data requests use AXI4-Lite.

---

## 11. One RAM with two ports

`shared_ram.sv` contains one 32-bit memory array.
It gives the array two access ports.

| Port | User | Main purpose |
|:--|:--|:--|
| host port | AXI RAM slave | CPU data access |
| pixel port | GPU | pixel reads and writes |

Both ports read the same array.
Thus, the CPU and GPU see the same framebuffers.

The RAM has 32,768 words.
The AXI slave uses address bits `[16:2]` as the word index.
The GPU uses its 15-bit word address directly.

If both ports write one word in one cycle, the host write has priority.
The code establishes this priority with the order of two assignments.

---

## 12. The end-to-end trace

The SoC trace proves that software caused both launches.
The 64x64 trace contains these important events:

```text
MMIO_WRITE cycle=51 addr=40000000 data=00000001
GPU_START cycle=52 pass=interior threads=3844 prog_base=0
GPU_DONE cycle=289576 pass=interior
MMIO_WRITE cycle=289637 addr=40000000 data=00000001
GPU_START cycle=289638 pass=border threads=252 prog_base=512
GPU_DONE cycle=317312 pass=border
SUMMARY cycles=317362 reads=36864 writes=4096 starts=2 dones=2
```

The first MMIO write starts the interior pass.
The second MMIO write starts the border pass.
The traffic totals match Phase 3 because the blur calculation is unchanged.

Phase 4 needs more cycles than Phase 3.
The additional cycles come from CPU setup, AXI transfers, and status polling.

---

## 13. How verification divides the problem

The tests check each layer before they check the complete SoC.

| Command | Main check |
|:--|:--|
| `make axi` | AXI routing, byte strobes, errors, fairness, and backpressure |
| `make cpu` | new instructions and stalled external memory transfers |
| `make soc16` | complete 16x16 CPU-driven blur |
| `make soc32` | complete 32x32 CPU-driven blur |
| `make soc64` | complete 64x64 CPU-driven blur |
| `make phase4` | all Phase 1 through Phase 4 checks |

`run_soc.py` checks the GPU programs with the ISA model first.
It then runs the RTL SoC.
It compares every destination pixel with the independent blur reference.
It also confirms that the source framebuffer did not change.

---

## 14. The measured results

| Size | Interior + border threads | Cycles | GPU reads | GPU writes |
|---:|---:|---:|---:|---:|
| 16x16 | 196 + 60 | 22,066 | 2,304 | 256 |
| 32x32 | 900 + 124 | 81,970 | 9,216 | 1,024 |
| 64x64 | 3,844 + 252 | 317,362 | 36,864 | 4,096 |

All three results have zero mismatches.
All three tests preserve the source framebuffer.
Each trace contains two starts and two completions.

---

## Quiz

<details>
<summary>1. Why does Phase 4 keep separate control and pixel paths?</summary>

The CPU uses AXI4-Lite to configure and start the GPU.
The GPU uses its existing simple bus for high-volume pixel traffic.
This design keeps the earlier GPU interface unchanged.

</details>

<details>
<summary>2. When does an AXI channel transfer occur?</summary>

A transfer occurs on a cycle when both `VALID` and `READY` are 1.
The sender keeps its payload stable while it waits.

</details>

<details>
<summary>3. Why is the MMIO done bit sticky?</summary>

The GPU completion pulse lasts for one cycle.
The CPU can miss this pulse during polling.
The sticky bit stays set until the CPU starts the next pass.

</details>

<details>
<summary>4. Why does the CPU write 0x2000 into SRC instead of 0x8000?</summary>

The `SRC` register contains a GPU word address.
The value `0x8000` is the equivalent CPU byte address.

</details>

<details>
<summary>5. What selects the interior or border program?</summary>

The `PROG_BASE` register selects the program offset.
The interior program starts at word 0.
The border program starts at word 512.

</details>

---

## Sources

- The specification: `docs/PHASE4_ASSIGNMENT.md`.
- The measured results: `docs/PHASE4_PROGRESS.md`.
- The top-level wiring: `soc/rtl/soc_top.sv`.
- The AXI control path: `soc/rtl/cpu_axi_master.sv` and `soc/rtl/axi_lite_interconnect.sv`.
- The GPU registers: `soc/rtl/gpu_mmio.sv`.
- The shared memory: `soc/rtl/shared_ram.sv`.
- The CPU driver and result checks: `soc/tools/run_soc.py`.
