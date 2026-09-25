<p align="center">
  <img src="docs/raptor-soc-logo.png" alt="RAPTOR-SoC logo" width="480">
</p>

<h1 align="center">RAPTOR-SoC</h1>

<p align="center">
  A RISC-V System-on-Chip.
</p>

---

## Overview

RAPTOR-SoC is a RISC-V based System-on-Chip project. This repository contains the
hardware design sources, verification environment, and supporting documentation.

## Repository Layout

```
RAPTOR-SoC/
├── docs/            # Documentation and assets (logo)
├── multi_cycle/     # RISC-V multi-cycle CPU (SystemVerilog)
│   ├── rtl/         #   design sources
│   ├── tb/          #   integration testbench
│   └── files.txt    #   Verilator file list
├── simt_gpu/        # SIMT GPU subsystem (SystemVerilog + Python harness)
│   ├── rtl/         #   design sources
│   ├── tb/          #   testbench
│   ├── sw/kernels/  #   device kernels
│   ├── tools/       #   host image <-> memory helpers
│   └── input_images/#   test frames
└── README.md
```

## Subsystems

### `multi_cycle/` — RISC-V Multi-Cycle CPU

Textbook-style multi-cycle RISC-V processor (Patterson & Hennessey) implementing
`ADD, SUB, AND, OR, LW, SW, BEQ`. Self-contained: instruction and data memories
are embedded (64 x 32).

Simulate (from the repository root):

```sh
verilator --binary --timing --top-module tb_riscv_mc \
  -f multi_cycle/files.txt --Mdir /tmp/riscv_mc_obj && \
  /tmp/riscv_mc_obj/Vtb_riscv_mc
```

Expected: `All multi-cycle processor tests passed.`

### `simt_gpu/` — SIMT GPU (Phase 1 in progress)

A programmable SIMT accelerator: 2 warps × 4 lanes, custom 16-bit ISA
(`CONST/ADD/SUB/LDR/STR/RET`), driven by `start`/`done` and an external memory
port. Phase 0's echo scanner has been replaced by the Phase 1 module set.

The RTL modules are **scaffolded** (ports + `TODO` behavior) for the Phase 1
assignment. See `docs/PHASE1_ASSIGNMENT.md`.

```sh
cd simt_gpu
make build                     # compile the integration testbench
make unit TEST=tb_alu          # run one module unit test
make run                       # assemble -> golden model -> RTL -> PNG compare
make venv                      # optional: Pillow/numpy for images
```

See `docs/GPU_ISA.md`, `docs/BUS_PROTOCOL.md`, and `docs/ADDRESS_MAP.md`.

## Status

Phase 1 in progress. The CPU runs standalone from the riscv repo; the GPU is
being brought up as a programmable SIMT device (`docs/PHASE1_ASSIGNMENT.md`).
A top-level SoC integration (shared bus, CPU <-> GPU memory) is future work.
The CPU currently embeds its own memories and is not yet wired to a shared bus.

## License

TBD.
