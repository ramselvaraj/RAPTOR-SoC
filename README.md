<p align="center">
  <img src="docs/assets/raptor-soc.png" alt="RAPTOR-SoC logo" width="640">
</p>

<h1 align="center">RAPTOR-SoC</h1>

<p align="center">
  A pipelined RISC-V processor and programmable SIMT GPU with independent clocks.
</p>

## Design

- Five-stage RV32I-subset CPU with instruction and data caches.
- Eight-lane SIMT GPU organized as two four-lane warps.
- AXI4-Lite interconnect and memory-mapped GPU control.
- Async FIFOs for cross-clock commands, completion events, and memory traffic.
- Uncached GPU registers and shared framebuffers; cached CPU-private RAM.

The CPU configures and launches GPU programs, then polls for completion.
The current workload is a two-pass, clamped 3×3 image blur.
The integration top is `soc_phase5_top`.

## Verification

The complete Verilator regression passes, including **31 SoC configurations** with independent clocks, stalls, clock pauses, and reset recovery.
The 16×16, 32×32, and 64×64 blur results match an independent Python reference, with unchanged source frames.

- **912 CPU retirements** checked against an architectural reference across four configurations.
- **672 standalone cache transactions** covering byte writes, eviction, reset, and backpressure.
- **6,000 ordered CDC request/response transactions** across FIFO depths 2, 4, and 8.
- **32 short GPU launches** tested with the GPU clock ten times faster than the CPU clock.
- Directed tests for AXI stalls, bus faults, MMIO cache bypass, atomic launch configuration, and reset recovery.

<p align="center">
  <img src="docs/assets/simt_gpu_full_blur_ferrari.png" alt="GPU clamped full-frame blur output" width="720">
</p>

## Synthesis and Implementation Results

Synthesized in **Synopsys Design Compiler** using the **FreePDK45 `gscl45nm` library**.

| Clock domain | Frequency |
|---|---:|
| CPU/system | **100 MHz** |
| GPU | **50 MHz** |

Both domains meet pre-layout setup and hold timing under the documented boot and external-memory interface contracts.
Caches, register files, and CDC FIFOs are included; backing memories are excluded.

| Mapped-core metric | Result |
|---|---:|
| Standard-cell area | **422,604.18 library area units** |
| Leaf cells | **120,776** |
| Sequential cells | **8,945** |
| Combinational cells | **111,831** |
| GPU share of cell area | **75.1%** |
| CPU and caches share of cell area | **18.2%** |
| Power | Not yet characterized |

Evidence: [area and hierarchy](synth/results/phase5/area.rpt) · [cell counts and QoR](synth/results/phase5/qor.rpt) · [inferred resources](synth/results/phase5/resources.rpt) · [timing and exact constraints](synth/results/phase5/gpu_50mhz_interfaces/).
The report set also includes structural checks and electrical-rule violations; these results are not physical signoff.

## Run

Requires Verilator, a C++ compiler, Make, and Python 3 with the dependencies in `simt_gpu/requirements.txt`.
Run from the repository root:

```sh
make phase5       # Complete regression.
make phase5-soc   # Multi-clock SoC tests only.
```

Generated traces, memory dumps, and images appear under `soc/build/phase5/`.

## Documentation

- [Implementation and results](docs/PHASE5_PROGRESS.md)
- [Architecture and verification specification](docs/PHASE5_ASSIGNMENT.md)
- [Memory map](docs/ADDRESS_MAP.md)
- [Bus interfaces and CDC](docs/BUS_PROTOCOL.md)
- [GPU instruction set](docs/GPU_ISA.md)
