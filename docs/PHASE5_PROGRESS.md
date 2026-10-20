# Phase 5 — Implementation and Verification

**Status:** implemented. The final `make phase5` acceptance run passed, including strict lint and the complete legacy regression.

## Implemented architecture

`soc/rtl/soc_phase5_top.sv` is the new integration top.
The Phase 4 `soc_top` remains available without changing its external interface.

| Function | Implementation |
|---|---|
| CPU | Imported five-stage RV32I-subset processor, forwarding, load-use interlocks, retirement trace, and fail-stop faults |
| Instruction cache | Direct-mapped blocking I-cache, default 4 lines x 4 words |
| Data cache | Same default capacity, write-back/write-allocate for `0x4000..0x4fff` only |
| Shared buffers and MMIO | Uncached route selected before D-cache, serialized through the CPU AXI adapter |
| AXI adapter | One outstanding transaction, byte strobes, stable responses, and sticky bus fault |
| CPU clock domain | CPU, caches, AXI, MMIO, CPU program memory, and both shared-RAM ports |
| GPU clock domain | GPU, active configuration snapshot, GPU program memory, and GPU-side bridge endpoints |
| CDC | Gray-pointer async FIFOs with two-stage pointer synchronization |
| GPU memory | Request and response FIFOs, write acknowledgment after commit, and warp-owner grant locking |
| Launch/completion | Atomic command FIFO and lossless completion FIFO with CPU-domain busy reservation/sticky done |
| Boot | Local CPU/RAM writes and acknowledged GPU-domain program writes while execution is held |
| Reset | Coordinated asynchronous assertion, separately synchronized release, and distinct execution hold |

Source provenance is recorded in `pipeline_cache/IMPORT.md`.
The CPU copy does not require another repository at build time.
GPU arithmetic and instructions are unchanged. The owner-lock option defaults off for legacy GPU tests.

## Reproduce

From the repository root, with Verilator and Python dependencies available:

```sh
make phase5-lint
make phase5-cpu
make phase5-bus
make phase5-cdc
make phase5-soc
make phase5
```

`make phase5` includes the complete Phase 4 regression.
Generated files stay under ignored `soc/build/phase5/` directories.
`soc/build/phase5/results.json` records the completed SoC matrix and its seeds.
Each workload directory contains its generated firmware, programs, frame, output, and trace.

## Verification evidence

The tests use Verilator 5.052 with timing and assertions enabled.

- Imported CPU differential tests: 228 retirements per configuration, four configurations.
- Standalone caches: 334 write-back and 338 write-through transactions, including partial writes, eviction, reset, and response backpressure.
- CPU fault tests: eight unsupported/misaligned cases with reset recovery.
- Cache router: cached private RAM, partial writes, dirty eviction, live shared-memory updates, uncached repeated MMIO reads, and exactly-once writes.
- AXI adapter: separate channel stalls, byte strobes, held CPU request-valid, delayed response acceptance, bus errors, and reset recovery.
- MMIO: command backpressure, busy-start rejection, shadow writes, and sticky completion.
- CDC channel: 2,000 ordered request/response transactions after an interrupted reset epoch at each FIFO depth 2, 4, and 8.
- SoC matrix: 31 configurations covering clock ratios, all three frame sizes, ten 16x16 pressure seeds, three 64x64 pressure seeds, reset recovery, disabled caches, and shallow FIFOs.

The full regression is the acceptance command. Do not substitute compilation or lint alone for that run.
Short-launch testing additionally checks 32 zero-thread launches with the GPU clock ten times faster than the CPU clock.

### Recorded 64x64 runs

All rows have zero pixel mismatches, 36,864 committed GPU reads, and 4,096 committed GPU writes.
Counts are sampled at firmware completion after both blur passes.

| Configuration | CPU period | GPU period | CPU cycles | GPU cycles |
|---|---:|---:|---:|---:|
| Equal clocks, coincident edges | 10 ns | 10 ns | 604,979 | 604,979 |
| CPU faster | 4 ns | 10 ns | 1,199,816 | 479,925 |
| GPU faster | 10 ns | 4 ns | 312,942 | 782,358 |
| Unrelated clocks | 7 ns | 11 ns | 814,884 | 518,562 |
| Depth-two queues, pressure seed 97 | 7 ns | 11 ns | 824,272 | 524,538 |

The clocks above are simulation inputs, not silicon or synthesized frequency claims.
The counters include execution-domain idle/polling time and are not kernel-only latency measurements.
CDC transport adds memory latency, so replacing the CPU does not guarantee a faster complete blur workload.

## End-to-end checks

Each normal frame run checks both CPU-dispatched blur passes against the independent Python reference.
It also verifies the following properties:

- Destination pixels match exactly, with unchanged source frame and protected padding.
- Committed pixel traffic is exactly nine reads and one write per output pixel.
- Both launches complete in order without duplicate completion or side effects.
- Private-cache byte/halfword writes survive dirty eviction with the expected backing-memory value.
- CPU post-completion uncached reads observe GPU output and original source data.
- Enabled caches record instruction hits, private-data hits, and dirty write-backs.
- Shadow configuration writes after launch do not change the active GPU configuration.
- Clock pauses resume without deadlock, loss, or duplicate traffic.
- A coordinated reset aborts the old epoch, reloads memory, and completes a fresh job.

The random source holds valid/data until an actual sampling-edge handshake.
The reset test truncates the normal workload trace at the epoch change, while the console records the deliberate abort.
The trace checker therefore evaluates the two completed launches in the new epoch, not an abandoned pre-reset launch.

## Timing and CDC scope

Simulation uses equal clocks, CPU-faster clocks, GPU-faster clocks, and unrelated 7 ns/11 ns periods.
These periods are protocol stress settings, not measured synthesis frequencies.
The Phase 4 shared-clock 50 MHz result does not apply to this new integration.

The new synthesis preparation targets are:

```sh
make dc-phase5-elab
make dc-phase5-core
```

They use `synth/phase5_constraints.tcl` and write to `synth/build/phase5/`.
CPU and GPU periods use `DC_CPU_CLOCK_PERIOD` and `DC_GPU_CLOCK_PERIOD`.
The memory-excluded top retains caches, register files, and CDC FIFO storage.
It excludes CPU instruction memory, GPU program memory, and shared backing RAM.

DC is not installed in the local verification environment, so these new DC targets are not mapped or timing-validated here.
The constraint template deliberately does not blanket-false-path all paths between the clocks.
It applies a conservative source-period bound to Gray-pointer crossings and fails if expected synchronizer names are absent.
Actual mapped synchronizer naming, bundled-data paths, reset checks, and physical bus delay/skew still need review in implementation tools.

Verilator does not model analog metastability. The digital tests do not establish CDC signoff or a metastability MTBF.
Independent reset of only one clock domain, coherent cached GPU buffers, and live instruction modification are not supported.
Reassert boot hold only when execution is quiescent or together with coordinated reset.
Debug counters stay in their original domains and are not synchronized for direct hardware CPU reads.

## Remaining implementation-tool validation

The uploaded internal CPU-clock register reports show +14.449377 ns setup slack at a 20 ns period
and +0.012687 ns hold slack. These are register-to-register paths, not complete-domain timing.
The setup-only internal boundary is approximately 5.550623 ns under the saved assumptions.
This estimate is not a validated whole-domain operating frequency.

Use `make dc-phase5-cpu-check` for a focused 10 ns CPU / 20 ns GPU experiment.
It reads the saved mapped DDC, applies the documented margins and I/O budgets, and reports only CPU-domain setup and hold.
It avoids the expensive explicit register-to-register and cross-domain searches of the full sweep.
It writes `synth/build/phase5/reports/cpu_100mhz/summary.txt`, reports, and SDC, without changing the original files.
The GPU remains targeted at 20 ns, but this focused command does not re-report GPU timing.
Passing CPU setup alone does not clear CPU hold, CDC, or electrical-rule violations.

The first Phase 5 DC reports are now available in `synth/results/phase5/`.
They show completed mapping at 20 ns CPU and GPU targets, with remaining hold and capacitance violations.
Use `make dc-phase5-sweep` to inspect the saved mapped design without recompilation.
It writes `synth/build/phase5/reports/cpu_sweep/summary.csv` and per-case reports.
The saved baseline retains its original constraints.
Controlled cases fix GPU period at 20 ns and test CPU periods of 20, 15, 10, and 5 ns.
Setup/hold margins stay at 0.2/0.05 ns, clock/input transitions at 0.1 ns, and I/O budgets and load stay fixed.
The Gray-pointer delay bound follows the faster clock period, as in the synthesis constraints.
Compare each case's exported SDC before attributing differences to clock period alone.

The summary separates internal CPU/GPU register paths, interface paths, port feedthroughs, and cross-domain paths.
`NA` means no analyzed path. It does not mean a path passed.
Internal timing excludes interface and CDC paths, so its passing target is not automatically a complete-domain frequency claim.

- Run the new top through DC and verify the two-domain timing exceptions against its actual hierarchy.
- Perform structural CDC analysis and physical Gray-bus delay/skew checks with suitable tools.
- Characterize any backing-memory implementation before asserting complete-SoC timing.
- Obtain independent CPU/GPU clock results for this top rather than reusing Phase 4 numbers.
