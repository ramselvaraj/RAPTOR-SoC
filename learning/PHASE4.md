# Phase 4 — CPU-Driven SoC (learning hub)

This file uses Simplified Technical English. For the full lesson, read
`lessons/0006-phase4-cpu-driven-soc.md`.

---

## One line

```
Phase 3: testbench starts the GPU   →   Phase 4: RISC-V software starts the GPU
```

Phase 4 connects the CPU, GPU, shared RAM, and AXI4-Lite control path.
The pixel result stays the same.

---

## Status board

```
AXI4-Lite interconnect       [x]   two masters, two slaves, round-robin grant
AXI RAM + GPU MMIO           [x]   byte strobes, backpressure, error responses
CPU instruction changes     [x]   ADDI, BNE, JAL, external LW/SW waits
CPU AXI master              [x]   one transaction at a time
shared dual-port RAM         [x]   CPU host port + GPU pixel port
GPU program selection       [x]   interior at 0, border at 512
CPU blur driver             [x]   two launches + STATUS polling
sizes 16/32/64              [x]   pixel-exact, source unchanged
```

---

## File map

| File | What changed |
|:--|:--|
| `soc/rtl/soc_top.sv` | connects the CPU, GPU, AXI path, RAM, and program memory |
| `soc/rtl/cpu_axi_master.sv` | converts CPU memory requests to AXI4-Lite transactions |
| `soc/rtl/axi_lite_interconnect.sv` | selects a master and routes each transaction |
| `soc/rtl/axi_lite_ram.sv` | gives AXI access to the host port of shared RAM |
| `soc/rtl/gpu_mmio.sv` | provides GPU control and status registers |
| `soc/rtl/shared_ram.sv` | provides separate host and pixel ports |
| `soc/rtl/program_memory.sv` | selects a GPU program with `PROG_BASE` |
| `multi_cycle/rtl/` | adds CPU instructions and external memory wait states |
| `soc/tools/run_soc.py` | builds, runs, traces, and checks the complete SoC |

---

## The three ideas

```
1. CPU control       software writes GPU settings and polls GPU status
2. Two data paths    AXI controls the GPU, while the pixel bus moves pixels
3. Handshakes        each requester waits until the receiver accepts its transfer
```

---

## The complete control flow

```
CPU program
   │  SW and LW
   ▼
CPU AXI master ──► AXI interconnect ──► GPU MMIO ──► GPU control ports
                                                   │
                                                   ▼
GPU pixel bus ───────────────────────────────► shared dual-port RAM
```

The CPU writes `SRC`, `DST`, `THREADS`, and `PROG_BASE`.
The CPU writes `CTRL.start` last.
The CPU reads `STATUS.done` until it is 1.
The CPU repeats the sequence for the border pass.

---

## Results

| Size | Threads | Cycles | Reads | Writes | Result |
|---:|---:|---:|---:|---:|:--|
| 16x16 | 196 + 60 | 22,066 | 2,304 | 256 | 0 mismatches |
| 32x32 | 900 + 124 | 81,970 | 9,216 | 1,024 | 0 mismatches |
| 64x64 | 3,844 + 252 | 317,362 | 36,864 | 4,096 | 0 mismatches |

Each test also confirms that the source frame did not change.

---

## Run it

Run these commands from the repository root.

```sh
make axi       # test AXI routing, responses, fairness, and backpressure
make cpu       # test CPU instructions and AXI memory waits
make soc16     # run the 16x16 CPU-driven blur
make soc32     # run the 32x32 CPU-driven blur
make soc64     # run the 64x64 CPU-driven blur
make phase4    # run all Phase 1 through Phase 4 tests
```

---

## Read more

- `docs/PHASE4_ASSIGNMENT.md` — the specification
- `docs/PHASE4_PROGRESS.md` — the measured results
- `docs/ADDRESS_MAP.md` — the CPU and GPU address views
- `docs/BUS_PROTOCOL.md` — the bus rules
- `lessons/0006-phase4-cpu-driven-soc.md` — the lesson
