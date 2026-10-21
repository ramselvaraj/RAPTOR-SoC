<p align="center">
  <img src="docs/assets/raptor-soc.png" alt="RAPTOR-SoC logo" width="640">
</p>

<h1 align="center">RAPTOR-SoC</h1>

<p align="center">
  A small RISC-V system-on-chip with a programmable eight-lane GPU.
</p>

## What it is

RAPTOR-SoC combines two processors:

- a five-stage, 32-bit RISC-V CPU with instruction and data caches; and
- a custom SIMT GPU with two warps of four lanes each.

The CPU runs at 100 MHz and the GPU runs at 50 MHz in the synthesized design.
Because they use separate clocks, commands, completion notifications, and GPU
memory requests cross between them through asynchronous FIFOs.

The current demonstration applies a clamped 3×3 blur to an image. A boot port
loads the CPU and GPU programs before execution starts. The CPU then supplies
the source and destination addresses, starts two GPU passes, and waits for each
pass to finish. The GPU processes the image while the CPU remains responsible
for the shared RAM.

<p align="center">
  <img src="docs/assets/raptor-soc-architecture-deckcraft.png" alt="RAPTOR-SoC dual-clock architecture" width="100%">
</p>

## Memory and control

The CPU controls the GPU through memory-mapped registers on an AXI4-Lite bus.
The register block holds the launch configuration and reports whether the GPU is
busy or finished.

CPU-private data from `0x4000` through `0x4fff` can use the write-back data
cache. GPU registers and shared framebuffers always bypass the cache, so the CPU
sees GPU writes without a hardware cache-coherence protocol.

The shared RAM is clocked by the CPU/system domain. When a GPU lane reads or
writes a pixel, its request crosses to the CPU domain, the RAM operation is
completed there, and the response crosses back to the GPU. The bridge keeps the
requesting warp selected until its operation completes.

The integrated Phase 5 design is `soc_phase5_top`. The older shared-clock design
remains available as `soc_top`.

## What has been tested

The complete Verilator test suite passes.

### Complete SoC tests

The test suite boots the CPU, launches both blur passes, and compares every
output pixel with a separate Python implementation of the same blur. It runs
with 16×16, 32×32, and 64×64 images.

There are 31 end-to-end test runs. Across those runs, the tests change the CPU
and GPU clock ratio, pause either clock, add bus stalls, reduce FIFO depth,
disable caches, and reset the system during an unfinished job. Every completed
run produced the expected image, left the source image unchanged, and completed
without losing or duplicating a memory operation.

### CPU, cache, and clock-crossing tests

- **CPU:** Four CPU test setups each execute 228 instructions. For all 912
  retired instructions, the test checks the program counter, instruction, and
  register write-back against a separate instruction interpreter. The
  interpreter also tracks memory contents and branch targets.
- **Caches:** Standalone cache tests complete 672 read and write operations.
  They cover byte and halfword writes, dirty-line eviction, reset, and delayed
  request or response handshakes.
- **Clock-domain crossing:** FIFO depths 2, 4, and 8 each carry 2,000 ordered
  request/response operations, for 6,000 operations in total. The test also
  interrupts traffic with a reset and checks that traffic from the old reset
  epoch cannot appear afterward.
- **GPU launch handling:** A control-path stress test sends 32 zero-thread
  launches while the GPU clock runs ten times faster than the CPU clock. Every
  launch produces one completion notification—none are lost or duplicated.
- **Bus and control logic:** Directed tests separately stall AXI channels,
  inject bus errors, access uncached GPU registers, change shadow configuration
  after a launch, and reset the system while work is active.

<p align="center">
  <img src="docs/assets/simt_gpu_full_blur_ferrari.png" alt="Image blurred by the RAPTOR-SoC GPU" width="720">
</p>

## Synthesis results

The Phase 5 core was synthesized with Synopsys Design Compiler using the
FreePDK45 `gscl45nm` standard-cell library.

| Clock domain | Target | Setup slack | Hold slack |
|---|---:|---:|---:|
| CPU/system | 100 MHz | +0.924154 ns | +0.012687 ns |
| GPU | 50 MHz | +0.000183 ns | +0.012687 ns |

Both clock domains pass the reported pre-layout setup and hold checks. The GPU
setup result has almost no margin, so it should not be read as evidence that the
GPU can run faster than 50 MHz.

The mapped core includes the CPU and GPU register files, both caches, the AXI
logic, and the clock-crossing FIFOs. It excludes the CPU program memory, GPU
program memory, and shared backing RAM. The timing result therefore depends on
those external memories meeting the input and output timing requirements in the
saved constraints.

| Mapped-core metric | Result |
|---|---:|
| Standard-cell area | 422,604.18 library area units |
| Leaf cells | 120,776 |
| Sequential cells | 8,945 |
| Combinational cells | 111,831 |
| GPU share of cell area | 75.1% |
| CPU and caches share of cell area | 18.2% |
| Power | Not characterized |

These are synthesis and pre-layout timing results, not physical-design signoff.
The saved reports also contain unresolved library electrical-rule violations and
the CDC structure still requires implementation-tool review.

Reports: [area and hierarchy](synth/results/phase5/area.rpt) ·
[cell counts and quality of results](synth/results/phase5/qor.rpt) ·
[inferred resources](synth/results/phase5/resources.rpt) ·
[timing paths and constraints](synth/results/phase5/gpu_50mhz_interfaces/)

## Running the tests

Install Verilator, a C++ compiler, Make, and Python 3. Install the Python
packages listed in `simt_gpu/requirements.txt`, then run these commands from the
repository root:

```sh
make phase5       # Run every Phase 5 test and the earlier regression tests.
make phase5-soc   # Run only the dual-clock, end-to-end SoC tests.
```

Generated execution traces, memory dumps, and output images are written under
`soc/build/phase5/`.

## Documentation

- [Implementation details and measured results](docs/PHASE5_PROGRESS.md)
- [Architecture and verification specification](docs/PHASE5_ASSIGNMENT.md)
- [CPU and GPU address map](docs/ADDRESS_MAP.md)
- [AXI, GPU memory, and clock-crossing protocols](docs/BUS_PROTOCOL.md)
- [GPU instruction set](docs/GPU_ISA.md)
