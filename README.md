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
├── soc/             # AXI4-Lite integration, shared RAM, MMIO, SoC tests
└── README.md
```

## Subsystems

### `multi_cycle/` — RISC-V Multi-Cycle CPU

Textbook-style multi-cycle RISC-V processor (Patterson & Hennessey) implementing
`ADD, SUB, AND, OR, ADDI, LW, SW, BEQ, BNE, JAL`. It uses a private 1024-word
instruction TCM and exposes a stalled data-memory request interface for AXI.

Simulate (from the repository root):

```sh
verilator --binary --timing --top-module tb_riscv_mc \
  soc/rtl/cpu_axi_master.sv -f multi_cycle/files.txt \
  --Mdir /tmp/riscv_mc_obj && \
  /tmp/riscv_mc_obj/Vtb_riscv_mc
```

Expected: `All multi-cycle processor tests passed.`

### `soc/` - CPU-driven Phase 4 integration

The CPU configures and launches both GPU blur passes through AXI4-Lite MMIO,
polls sticky completion status, and shares a dual-port RAM with the GPU pixel
bus. The GPU programs remain resident at offsets 0 and 512.

```sh
make axi                 # AXI slaves, arbitration, backpressure, assertions
make cpu                 # CPU ISA and stalled-memory tests
make soc16               # CPU-driven clamped blur at 16x16
make soc32               # CPU-driven clamped blur at 32x32
make soc64               # CPU-driven clamped blur at 64x64
make phase4              # complete Phase 1-4 regression
```

### `simt_gpu/` — SIMT GPU (Phase 1–3 done)

A programmable SIMT accelerator: 2 warps × 4 lanes = 8 physical threads,
custom 16-bit ISA. Larger thread counts run as **waves** (thread blocks): 256
threads = 32 waves of 8. Verified pixel-for-pixel against a Python golden model.
Phase 2 adds the full ALU (`MUL/DIV/AND/OR/XOR/SLL/SRL`), `CMP` + uniform
branches, and the interior 3×3 box blur. Phase 3 adds the **clamped full-frame**
blur (a second border pass) and a deterministic performance trace (see
`docs/PHASE3_ASSIGNMENT.md`).

<p align="center">
  <img src="docs/assets/simt_gpu_brighten_aston.png" alt="RTL brighten kernel: input (left) vs output (right)" width="720">
</p>

<p align="center"><em>Phase 1 <code>brighten</code> kernel running on the RTL
datapath (input: <code>alonso_aston</code>, 64×64 → 4096 threads = 512 waves,
0 mismatches vs the golden model). The scalar <code>+0x20</code> add overflows
blue into green — the speckles that Phase 2's per-channel saturating math
fixes.</em></p>

Phase 2 adds the full ALU (`MUL/DIV/AND/OR/XOR/SLL/SRL`) and a fully-unrolled
interior 3×3 box blur, matched pixel-for-pixel against an independent Python
reference:

<p align="center">
  <img src="docs/assets/simt_gpu_blur_ferrari.png" alt="3x3 box blur: input (left) vs RTL output (right)" width="720">
</p>

<p align="center"><em>Phase 2 interior <code>blur</code> on the RTL datapath
(input: <code>alonso_ferrari</code>, 3844 threads, 125 instructions,
0 mismatches). The 1-pixel border is untouched — Phase 3 clamps
it.</em></p>

Phase 3 runs the interior pass, then a second **border** pass that clamps the
edges and corners, producing a complete full-frame blur for 16×16, 32×32, and
64×64:

<p align="center">
  <img src="docs/assets/simt_gpu_full_blur_ferrari.png" alt="Clamped full-frame 3x3 blur: input (left) vs RTL output (right)" width="720">
</p>

<p align="center"><em>Phase 3 clamped full-frame <code>blur</code>
(input: <code>alonso_ferrari</code>, 4096 pixels = 3844 interior + 252 border
threads over two launches, 0 mismatches). Borders are edge-replicated.</em></p>



```sh
cd simt_gpu
make build                     # compile the integration testbench
make unit TEST=tb_alu          # run one module unit test
make branch                    # CMP + BRnzp counted-loop regression
make run                       # brighten: assemble -> golden model -> RTL -> PNG
make blur                      # Phase 2: interior 3x3 box blur
make blur16 / blur32 / blur64  # Phase 3: clamped full-frame blur
make trace SIZE=64             # Phase 3: RTL trace + trace checker
make phase3                    # full Phase 1-3 regression
make golden                    # model + reference only, no RTL
make venv                      # optional: Pillow/numpy for images
```

See `docs/GPU_ISA.md`, `docs/BUS_PROTOCOL.md`, `docs/ADDRESS_MAP.md`, and
`docs/PHASE{1,2,3,4}_ASSIGNMENT.md`.

## Progress notes

- `docs/PHASE1_PROGRESS.md`, `docs/PHASE2_PROGRESS.md`, `docs/PHASE3_PROGRESS.md`,
  `docs/PHASE4_PROGRESS.md`
  — running build logs for the GPU bring-up, written while implementing the RTL.
- `learning/` — accompanying study notes, mission, and lessons generated during
  the build (not part of the hardware design).

## Status

Phase 1-4 complete: the multi-cycle RISC-V CPU launches both GPU blur passes
through AXI4-Lite MMIO and polls completion. The integrated SoC produces the
clamped 16x16, 32x32, and 64x64 frames pixel-for-pixel against the independent
Python reference while preserving the source framebuffer. Memory coalescing,
interrupts, caches, and per-lane divergence remain deferred scale-out work.

## License

TBD.
