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

### `simt_gpu/` — SIMT GPU (Phase 1 working)

A programmable SIMT accelerator: 2 warps × 4 lanes = 8 physical threads,
custom 16-bit ISA (`CONST/ADD/SUB/LDR/STR/RET`). Larger thread counts run as
**waves** (thread blocks): 256 threads = 32 waves of 8. Verified
pixel-for-pixel against a Python golden model.

<p align="center">
  <img src="docs/assets/simt_gpu_brighten_compare.png" alt="RTL brighten kernel: input (left) vs output (right)" width="720">
</p>

<p align="center"><em>Phase 1 <code>brighten</code> kernel running on the RTL
datapath (4096 threads = 512 waves, 0 mismatches vs the golden model).
The scalar <code>+0x20</code> add overflows blue into green — the speckles
that Phase 2's per-channel saturating math fixes.</em></p>


```sh
cd simt_gpu
make build                     # compile the integration testbench
make unit TEST=tb_alu          # run one module unit test
make run                       # brighten: assemble -> golden model -> RTL -> PNG
make venv                      # optional: Pillow/numpy for images
```

See `docs/GPU_ISA.md`, `docs/BUS_PROTOCOL.md`, `docs/ADDRESS_MAP.md`, and
`docs/PHASE1_ASSIGNMENT.md`.

## Progress notes

- `docs/PHASE1_PROGRESS.md` — running build log for the Phase 1 GPU bring-up,
  written while implementing the RTL module by module.
- `learning/` — accompanying study notes, mission, and lessons generated during
  the build (not part of the hardware design).

## Status

Phase 1 complete: the programmable SIMT GPU runs the `brighten` and `copy`
kernels through a wave loop and matches the Python golden model at 256 threads.
The CPU runs standalone from the riscv repo. A top-level SoC integration
(shared bus, CPU <-> GPU memory + MMIO) is Phase 4; the CPU currently embeds
its own memories and is not yet wired to a shared bus.

## License

TBD.
