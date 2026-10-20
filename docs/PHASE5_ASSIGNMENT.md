# Phase 5 — Pipelined CPU, Cache-Safe Memory, and Independent GPU Clock

## Status and goal

This document is the implementation specification, not a claim of completed work.
Phase 4 is the current integrated baseline. Phase 5 adds the features below.

Replace the multi-cycle CPU with the existing five-stage RV32I-subset processor.
Keep its instruction cache and use its data cache only for CPU-private RAM.
Run the CPU and GPU on independent clocks through explicit clock-domain crossing (CDC) modules.
Verify the complete system in Verilator against the existing independent blur reference.

The implementation must preserve GPU instructions, framebuffer contents, and CPU-visible MMIO addresses.
It need not preserve cycle counts or the old CPU's internal state encoding.

## Starting points

- `soc/rtl/`: current SoC, AXI4-Lite master, interconnect, MMIO, and memories.
- `multi_cycle/rtl/`: working CPU baseline. Keep it available for regression.
- `simt_gpu/rtl/`: GPU, scheduler, warps, and per-lane memory sequencer.
- `soc/tools/run_soc.py`: boot firmware, frame generation, reference comparison, and traces.
- `docs/ADDRESS_MAP.md` and `docs/BUS_PROTOCOL.md`: existing address and transaction rules.
- CPU source: sibling repository `../riscv/pipeline_cache/`, relative to RAPTOR-SoC.

The CPU source contains `rv32_pkg.sv`, `decoder.sv`, `core.sv`, `blocking_cache.sv`, and `pipeline_cache.sv`.
Its decoder supports every instruction required by the current RAPTOR firmware.
The firmware needs `ADD`, `ADDI`, `AND`, `LW`, `SW`, and `BEQ`.
The replacement also supports the other existing CPU instructions, including `SUB`, `OR`, `BNE`, and `JAL`.

Record the imported source revision and any local source changes before integration.
Copy the required source and tests into this repository. Do not require a sibling checkout to build RAPTOR.
Keep module names distinct from the existing GPU and multi-cycle CPU modules.
Preserve the source license and record integration changes next to the imported code.

Use `pipeline_cache/rtl/` and `pipeline_cache/tb/` for the imported implementation and standalone tests.
Put SoC-specific adapters and CDC modules in `soc/rtl/`, with their tests in `soc/tb/`.
Use `soc_phase5_top` for the new integration. Keep `soc_top` as the Phase 4 compatibility top.

## Scope decisions

| Decision | Phase 5 choice |
|---|---|
| Clock domains | CPU/system domain and GPU domain |
| CPU/system domain | CPU, I/D caches, AXI, MMIO, CPU instruction memory, and shared RAM |
| GPU domain | GPU execution, GPU program memory, and GPU-side CDC adapters |
| I-cache | Enabled after instruction-fetch adapter bring-up |
| D-cache | Write-back/write-allocate for CPU-private RAM only |
| GPU MMIO and shared buffers | Always uncached |
| Coherence | None. Use explicit ownership and uncached shared buffers |
| AXI | Preserve AXI4-Lite and one outstanding data transaction |
| GPU memory bridge | One outstanding GPU transaction initially, with request and response async FIFOs |
| GPU launch | Atomic configuration command with acknowledged delivery |
| Completion | Lossless completion event and CPU-domain sticky status |
| Reset | Coordinated system reset with synchronized release in each domain |
| Verification | Verilator unit, integration, randomized-stall, and multi-clock tests |

Do not add cache snooping, cache-maintenance instructions, AXI bursts, interrupts, or independent domain resets.
Do not pipeline the GPU divider or otherwise change the GPU ISA in this phase.
Do not implement SRAM macros or claim new synthesis frequencies from simulation.

## Architecture

```text
 cpu_clk domain                                      gpu_clk domain
 ----------------                                    --------------
 Pipelined CPU + I-cache                              SIMT GPU
       |                                                    |
       +-- instruction adapter --> CPU instruction memory   |
       |                                                    |
       +-- data address router                              |
             |                                              |
             +-- private RAM --> D-cache --+                 |
             +-- MMIO/shared --> bypass ---+                 |
                                          |                 |
                                 AXI request adapter        |
                                          |                 |
                                 AXI4-Lite interconnect     |
                                  |                |        |
                            RAM host port       GPU MMIO    |
                                  |                |        |
                            Shared RAM       command CDC --> launch/config
                                  |             event CDC <-- completion
                            RAM pixel port                  |
                                  ^                         |
                                  +-- request/response CDC --+ GPU memory

 CPU-domain boot loader -------- program-write CDC ------> GPU program memory
```

Shared RAM remains a single-clock memory with both write ports in the CPU domain.
The GPU never directly clocks or writes that array.
GPU instruction reads remain local to the GPU domain after program loading completes.
Preserve the existing host-write priority if both CPU-domain RAM ports write the same word.

## Memory map and cache policy

Keep the existing byte-addressed CPU map and word-addressed GPU map.

| CPU byte range | Purpose | CPU cache policy |
|---|---|---|
| `0x0000_0000..0x0000_0FFF` | Private instruction memory | I-cache only |
| `0x0000_4000..0x0000_4FFF` | CPU-private data and stack | D-cache permitted |
| `0x0000_8000..0x0000_BFFF` | Source framebuffer | Uncached |
| `0x0001_8000..0x0001_BFFF` | Destination framebuffer | Uncached |
| Other legal addresses in the existing AXI RAM window | Reserved/shared RAM | Uncached |
| `0x4000_0000..0x4000_001F` | GPU MMIO | Uncached, no speculative reads or line refills |

The existing AXI RAM window remains `0x0000_4000..0x0001_BFFF`.
Do not broaden that window or create aliases to the private cached region.
The GPU program-memory allocation remains a private programming/fetch interface, not a new AXI slave.

GPU `SRC` and `DST` values stay word-addressed: `0x2000` and `0x6000`.
Apply the byte-to-word conversion exactly once at the existing RAM interface.

Place the cached/uncached router **before the D-cache**.
Routing after the cache cannot prevent cached status reads or buffered control writes.
Write-through alone is not an MMIO bypass and does not prevent stale reads.

The cacheable region must contain each complete cache line that it admits.
Latch the selected route when a request transfers. Keep that route until its response transfers.
Serialize cached and uncached data operations. A later operation must not overtake an earlier one.
I-cache traffic may progress independently through its private instruction interface.

CPU-private RAM is private by software ownership, not new hardware memory protection.
GPU programs must not access that region. Phase 5 does not promise coherent behavior if they do.
During a GPU launch, the CPU must not change its input buffers or race its output writes.
After completion, uncached CPU reads must observe the GPU's committed writes.

## Interface requirements

### CPU and AXI adapter

The imported CPU uses request and response handshakes, not RAPTOR's original request pulse.
For each accepted request, return exactly one response, including stores.
Return responses no earlier than the cycle after request acceptance.
Hold request and response payloads stable during backpressure.

Adapt this interface to `cpu_axi_master` or extend that master behind a compatible wrapper.
Latch address, data, and byte strobes once. Do not issue repeated AXI operations while request-valid stays high.
Preserve independent AXI address/data handshakes and wait for the actual AXI response.
Hold a completed CPU response until the CPU accepts it.

Plumb all four write strobes through AXI instead of hard-wiring `4'b1111`.
Test `SB`, `SH`, and `SW`, plus signed and unsigned subword loads.
MMIO accesses in the GPU-control firmware remain aligned word accesses.
Define and test unsupported MMIO strobe behavior rather than relying on register side effects.

Define bus-error behavior explicitly. A rejected AXI operation must not become a silent successful CPU access.
The imported CPU has no response-error input. Add an SoC fault latch that blocks further requests until coordinated reset.
Specify the adapter's error-response retirement behavior. Do not claim precise architectural traps.

### Instruction fetch

Wrap the current instruction memory with the imported CPU's request/response interface.
Instruction addresses are byte addresses. The existing memory selects words with address bits `[11:2]`.
Define out-of-range fetch behavior explicitly. The production firmware must stay within the 4 KiB boot allocation.
Preserve stable responses under stalls and discard redirected fetches only through the CPU's existing protocol.

First test direct fetch without I-cache. Then enable I-cache and test complete line refills.
Do not modify instructions during execution. A new boot session must invalidate the I-cache before execution resumes.

### GPU memory CDC

Use a synthesizable async FIFO with binary local pointers and synchronized Gray pointers.
Synchronize pointer crossings with dedicated synchronizer stages in their receiving domains.
Do not synchronize payload bits independently.
Support power-of-two depths of at least two. Use depth four for initial integration.

Request payload: operation, GPU word address, write data, and any source tag required by arbitration.
Response payload: read data and completion/error status. Writes also need a completion response.
The RAM service must acknowledge a write only after the memory write commits.

The current GPU scheduler can change the granted warp while memory is stalled.
Therefore, latch and lock the requesting warp's grant until the response completes its original transaction.
Do not deliver a response to whichever warp happens to hold the grant later.
Locking the whole scheduler grant during the transaction is acceptable for this phase.
Any later optimization that runs other warps needs explicit owner tags and equivalent response routing tests.

The bridge translates a delayed FIFO response into the existing GPU `mem_ready` completion handshake.
Assert `mem_ready` only for the owner, with matching read data held stable through completion.
While a request is outstanding, do not enqueue it again even if GPU `mem_req` remains high.
Release ownership only after that completion. Repeated identical adjacent requests must remain separate transactions.

Do not tie `gpu_mem_ready` high in the multi-clock implementation.
Do not interpret request-FIFO acceptance as completion of a memory write.
Keep GPU address units unchanged across both FIFO payloads and the RAM service.

### Launch, status, and completion CDC

Keep AXI-visible MMIO registers in the CPU domain.
An accepted start must capture one command containing `THREADS`, `SRC`, `DST`, and `PROG_BASE`.
Transfer that command atomically to the GPU domain.
Latch all active GPU parameters there and issue exactly one GPU-clock start pulse.
Hold the active parameters, including program base, unchanged until the launch finishes.
Later CPU configuration writes may change shadow registers but must not alter the active launch.

Reserve CPU-domain busy status as soon as the command is accepted.
Busy must cover queued launch delivery, GPU execution, and completion delivery.
Do not expose a false idle interval while GPU-domain busy is still crossing clocks.
Reject a second start while reserved-busy with `SLVERR`. It must not clear sticky done or enqueue another command.
Backpressure an otherwise legal start when the command transport cannot accept it.
Return `OKAY` for start only after the command is safely accepted by that transport.

Transfer completion as a lossless event using a handshake or async FIFO.
Do not pass a one-cycle done pulse through two flops and assume it survives.
Publish sticky done in the CPU domain only after the launch's memory writes have committed.
Keep done set until the next accepted start, as in Phase 4.
Test zero-thread launches and very short launches that can finish between CPU edges.

### Reset and boot programming

Separate **transport reset** from **execution hold during boot**.
A bridge held in reset cannot carry program writes or return acknowledgments.

For the new multi-clock top, define a coordinated system reset and a separate boot hold.
Keep the existing single-clock top and its boot interface available for legacy tests.
The multi-clock boot sequence is:

1. Assert system reset in both domains. Block new transactions and clear transport state.
2. Deassert reset through a local reset-release synchronizer in each domain.
3. Wait until both transports report ready. Keep CPU and GPU execution held for programming.
4. Load CPU instructions and RAM in the CPU domain.
5. Forward GPU program writes to the GPU domain through an acknowledged programming bridge.
6. Wait for every accepted boot write to commit. Do not use a fixed arbitrary delay as completion.
7. Invalidate caches and release execution only after both domains confirm boot completion.

The new boot interface must expose acceptance/backpressure and completion information.
Do not assume the old one-write-per-CPU-cycle boot port can feed a slower GPU without backpressure.
The GPU program memory remains 1024 x 16 bits, with kernels at offsets zero and 512.
Keep memory contents across reset unless the loader explicitly overwrites them.
Do not treat reset as a write-back-cache flush. CPU-private dirty state is discarded by a new boot session.

Coordinated reset may abort outstanding operations. Exactly-once guarantees apply within a reset epoch.
Both domains must flush transport state and prevent old responses from entering the new epoch.
A write that committed before reset need not roll back. Tests must distinguish that from duplicate post-reset execution.
Independent reset of only one domain is outside this phase's contract.

## Implementation milestones and gates

Complete each gate before starting the next integration change.

### 5A — Import and establish the CPU baseline

- Import the five CPU/cache RTL files and their standalone verification dependencies.
- Record source provenance and create a standalone file list.
- Run CPU differential, cache, fault, and request-backpressure tests in Verilator.
- Keep the original multi-cycle CPU and all Phase 4 targets unchanged.

**Gate:** all imported tests pass in this repository without a sibling checkout.

### 5B — Replace the CPU on the existing shared clock

- Add the CPU data-to-AXI adapter, instruction-response adapter, and a data-cache bypass mode.
- Initially run without caches. Reuse the existing firmware initialization and GPU launch programs.
- Add retirement tracing and a sticky SoC fault indicator.
- Test one AXI transaction per CPU memory request under independent channel stalls.
- Run both GPU blur passes at 16x16, 32x32, and 64x64.

**Gate:** pixel-exact results, unchanged source frames, two accepted launches, and no duplicate side effects.

### 5C — Enable caches with address-based bypass

- Enable I-cache and the private-RAM D-cache.
- Add the route latch, response mux, and cache-line eligibility checks before the D-cache.
- Preserve data ordering between the cached path and the uncached path.
- Verify byte strobes and private-RAM dirty eviction against an independent memory model.
- Test repeated GPU status polls and CPU visibility of GPU results without cache invalidation tricks.

**Gate:** caches show hits on eligible memory, while MMIO/shared requests never allocate or hit D-cache lines.

### 5D — Verify CDC modules in isolation

- Implement reset-release synchronization and async FIFOs.
- Implement command/completion and GPU memory request/response bridges.
- Implement acknowledged GPU program loading while execution is held.
- Test grant ownership, FIFO pressure, stalls, wraparound, and coordinated reset.

**Gate:** scoreboards show no lost, duplicated, reordered, or misrouted transfers within each reset epoch.

### 5E — Integrate the two-clock SoC

- Add a multi-clock top with `cpu_clk` and `gpu_clk`, plus the specified reset and boot controls.
- Keep AXI and both shared-RAM ports entirely in the CPU domain.
- Keep GPU execution and program fetch entirely in the GPU domain.
- Connect the bridges and remove direct crossings of start, done, configuration, and pixel transactions.
- Preserve the same-clock mode for differential comparison.

**Gate:** all end-to-end workloads pass for CPU-faster, GPU-faster, and unrelated clock configurations.

### 5F — Regression, documentation, and synthesis preparation

- Automate the complete test matrix below with deterministic seeds and bounded timeouts.
- Update address, protocol, boot, and clock-domain documentation to match the implementation.
- Keep the memory-excluded synthesis flow available for both the legacy and new tops.
- Add separate CPU/GPU clocks to new-top constraints only after the CDC structure exists.
- Record measured simulation counters and actual test commands in `docs/PHASE5_PROGRESS.md`.

**Gate:** the Phase 4 regression and the complete Phase 5 regression both pass from a clean checkout.

## Verilator verification plan

Use `--timing --assert` and fail the test on assertion failures, scoreboard mismatches, faults, or timeouts.
Generate clocks independently with SystemVerilog delays or a timed C++ harness.
Use nonzero phase offsets and periods that do not require one clock edge to coincide with the other.
Test coincident edges separately rather than relying on them for progress.

### Unit and interface tests

| Module or behavior | Required tests |
|---|---|
| Imported CPU | ISA differential tests, forwarding, load-use bubbles, branch flushes, faults, and stalled fetch/data responses |
| AXI adapter | Independent AW/W/AR stalls, delayed B/R, CPU response stalls, byte strobes, errors, and back-to-back requests |
| Cache router | Region edges, cached/uncached alternation, request stability, response ownership, and no shared-memory aliases |
| I-cache | Refill, conflict replacement, reset invalidation, redirected fetch, and end-of-program line reads |
| D-cache | Partial writes, dirty conflicts, write-back ordering, and independent backing-memory checks after eviction |
| Async FIFO | Empty/full, simultaneous activity, repeated wraparound, depth 2/4/8, pointer synchronization delay, and reset |
| GPU memory bridge | Load/store interleaving, identical adjacent requests, both warps, response pressure, and owner lock |
| Launch bridge | Atomic snapshots, very short jobs, zero threads, repeated launches, busy-start rejection, and shadow-register changes |
| Completion | No missed event, no duplicate done, sticky status, and final-write visibility before done |
| Boot bridge | Faster loader than GPU, full queue, program-content checks, interrupted programming, and no execution before acknowledgment |

Assert request and response stability when valid is high and ready is low.
Assert FIFO pointer advances only on accepted local transfers and no local overflow/underflow occurs.
Check one-bit Gray transitions on the **source pointer**, not on synchronized pointer samples that may skip source increments.
Use ordered transaction scoreboards and independent memory models, not only FIFO occupancy counters.

### End-to-end matrix

Clock values below are simulation stress settings, not proven operating frequencies.

| Test class | Clock and stall configuration | Workload |
|---|---|---|
| Same-clock comparison | Equal periods, no added stalls | All three frame sizes on the old and new CPUs |
| CPU faster | 4 ns CPU period, 10 ns GPU period | All three frame sizes |
| GPU faster | 10 ns CPU period, 4 ns GPU period | All three frame sizes |
| Unrelated clocks | 7 ns CPU period, 11 ns GPU period, varied initial offsets | All three frame sizes |
| CDC pressure | Depth-two FIFOs, bursty response delays, randomized request acceptance | 16x16 and 64x64 |
| Short command stress | Many small or zero-thread launches | Launch/completion scoreboard |
| Reset recovery | Reset with queued commands, reads, writes, and boot data | Abort the old epoch, reload, then complete a fresh blur |
| Clock pause | Pause each domain while a transaction is outstanding, then resume | No loss, duplication, or stale completion |

Use at least ten recorded seeds for the 16x16 randomized multi-clock test.
Use at least three recorded seeds for the 64x64 pressure test.
Timeouts must allow the chosen clocks and stalls. Do not copy the Phase 4 cycle bound without adjustment.
Liveness assertions must assume clocks resume and downstream backpressure eventually clears.

For every complete blur run, check:

- Destination pixels equal the independent Python clamped-blur reference.
- The source frame and its protected padding remain unchanged.
- Exactly two launches complete in the intended interior/border order.
- Accepted GPU memory operations match RAM commits and returned responses.
- MMIO writes occur exactly once, and repeated status reads observe live state.
- CPU reads after done see the GPU's final output through the uncached path.
- No CPU/SoC fault, outstanding transaction, or unexpected cache access remains.

Keep the existing ISA model and blur reference independent of the new CPU and CDC implementation.
Do not use matching cycle counts as the correctness criterion across clock ratios or CPU versions.
Report CPU cycles, GPU cycles, elapsed simulation time, retired instructions, cache statistics, and bus traffic separately.
Do not add cycle counters from unrelated domains as if they used the same time unit.

### Planned targets

These names are requirements for the implementation. They do not exist merely because this document lists them.

```sh
make phase5-cpu       # Imported CPU/cache/fault regression.
make phase5-bus       # CPU adapters, address routing, and cache-bypass tests.
make phase5-cdc       # FIFO, command, completion, memory, reset, and boot tests.
make phase5-soc       # Multi-clock end-to-end workload matrix.
make phase5          # All Phase 5 tests, plus the unchanged Phase 4 regression.
```

Store generated files under ignored build directories, with separate paths for each configuration and seed.
The complete build must run without a proprietary simulator.

## CDC and synthesis checks beyond simulation

Verilator can test digital protocols, backpressure, and clock-ratio behavior.
It does **not** simulate analog metastability or prove a CDC implementation safe in silicon.

Before claiming CDC correctness beyond simulation:

- Review every crossing and identify its synchronizer, handshake, FIFO, or reset mechanism.
- Mark synchronizer registers with the attributes expected by the implementation tools.
- Constrain Gray-pointer bus delay/skew according to the FIFO implementation and source clock.
- Review timing-exception precedence so asynchronous clock exceptions do not silently disable required pointer constraints.
- Do not blanket-false-path unsynchronized payload crossings and call the design CDC-clean.
- Run an available structural CDC checker or document the manual review and its limits.

CPU and GPU clock periods become independent synthesis inputs.
Core-only synthesis must retain the CPU caches and register files while excluding the three large backing memories.
No earlier shared-clock frequency result transfers automatically to the new implementation.
Keeping the GPU divider unchanged may still limit the GPU-domain frequency.
The CPU can use a faster clock only if its own timing analysis supports it.

## Completion criteria and deliverables

Phase 5 is complete when all milestone gates pass and the following evidence exists:

1. Reproducible imported CPU source and tests, with provenance.
2. Working same-clock CPU replacement and cache-safe routing.
3. Explicit, reviewed CDC modules and reset/boot contracts.
4. Passing Verilator tests across the specified clocks, stalls, seeds, and reset cases.
5. Pixel-exact full-SoC results and independent transaction scoreboards.
6. Updated block diagram, memory map, protocol documentation, and actual progress/results file.
7. Preserved legacy tests and a usable memory-excluded synthesis configuration.

Do not label planned targets, simulation stress periods, or unexecuted tests as measured results.
Phase 6 can address GPU arithmetic latency or other performance work after this integration is stable.
