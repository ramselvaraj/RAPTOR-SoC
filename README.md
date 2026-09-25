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

### `simt_gpu/` — SIMT GPU (Phase 0 skeleton)

> Phase 0 is a deliberate placeholder: a single-lane scanner that echoes a
> framebuffer unchanged. It exercises the host <-> simulation <-> host file loop;
> the SIMT core and real ISA replace it in later phases.

Set up the optional Python environment and run the full file-I/O loop:

```sh
cd simt_gpu
make venv     # optional: Pillow/numpy for PNG + reference models
make inputs   # crop/downscale the sample photos
make run      # frame -> sim -> out, verifies the echo, renders a PNG
```

`make build` alone builds `build/obj/Vtb_gpu`; `make clean` removes artifacts.

## Status

Early development. The CPU runs standalone; the GPU is a bring-up scaffold.
A top-level SoC integration (shared bus, CPU <-> GPU memory) is future work.
The CPU currently embeds its own memories and is not yet wired to a shared bus.

## License

TBD.
