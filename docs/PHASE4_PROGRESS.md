# Phase 4 Progress - SoC Integration

Phase 4 integrates the multi-cycle RISC-V CPU, SIMT GPU, AXI4-Lite control path,
dual-port shared RAM, GPU MMIO, and private CPU/GPU program memories.

## Completed

- Added a two-master, two-slave round-robin AXI4-Lite interconnect.
- Added AXI RAM and GPU MMIO slaves with byte strobes, backpressure-safe
  responses, address validation, and `SLVERR` handling.
- Added sticky GPU completion status so CPU polling cannot miss the DCR pulse.
- Extended the CPU with `ADDI`, `BNE`, `JAL`, external data-memory requests, and
  read/write completion wait states.
- Added the single-outstanding CPU AXI master and 1024-word instruction TCM.
- Added a 32768-word dual-port shared RAM preserving GPU word addresses
  `0x2000` and `0x6000` while mapping AXI byte addresses through `addr[16:2]`.
- Added private GPU program memory with interior and border programs resident at
  offsets 0 and 512.
- Added a tiny RISC-V assembler, CPU driver, integrated SoC testbench, trace,
  independent reference comparison, and root Make targets.

## Measured Results

Measured with Verilator 5.052 using the generated deterministic input pattern.

| Size | Interior + border threads | Cycles | GPU reads | GPU writes | Result |
|---:|---:|---:|---:|---:|---|
| 16x16 | 196 + 60 | 22,066 | 2,304 | 256 | 0 mismatches; source unchanged |
| 32x32 | 900 + 124 | 81,970 | 9,216 | 1,024 | 0 mismatches; source unchanged |
| 64x64 | 3,844 + 252 | 317,362 | 36,864 | 4,096 | 0 mismatches; source unchanged |

Each output pixel performs nine GPU reads and one write. Every trace contains
two CPU MMIO launches and two GPU completions.

## Verification

- `make axi`: passes randomized RAM/MMIO traffic, byte strobes, invalid-address
  responses, two-master fairness, response stalls, and bound AXI assertions.
- `make cpu`: passes existing R-type/BEQ behavior plus `ADDI`, BNE taken and not
  taken, JAL target/link, and stalled external `LW`/`SW` without duplicate
  requests.
- `make soc16`, `make soc32`, and `make soc64`: pass the independent clamped
  blur reference, source-preservation check, and two-pass trace validation.
- `make phase3`: passes all Phase 1-3 RTL, Python, image, branch, and trace
  regressions unchanged.

## Design Clarifications

The assignment's draft 16384-word RAM and `addr[15:2]` index would alias the two
framebuffers and could not represent GPU destination word address `0x6000`.
The implementation therefore retains the established 32768-word physical
memory and uses AXI `addr[16:2]`. The MMIO `done` bit is sticky because the GPU's
native `done` output is a one-cycle pulse and cannot be polled reliably through
a multi-cycle AXI load otherwise.
