# Cached Five-Stage Processor

RAPTOR's Phase 5 integration uses this imported CPU with optional address-based
data-cache bypass. Its source revision and local changes are in `IMPORT.md`.
`soc_phase5_top` enables that routing so MMIO and shared GPU buffers stay uncached.
The default standalone configuration below retains the original all-address cache policy.

`pipeline_cache/` contains a separate CPU implementation. It does not change
`pipeline/`, `multi_cycle/`, or `single_cycle/`.

## Architecture

The core has five stages: IF, ID, EX, MEM, and WB. Packed structures hold the
`IF/ID`, `ID/EX`, `EX/MEM`, and `MEM/WB` register sets.

- The core forwards results from EX/MEM and MEM/WB.
- The newest result takes priority when both stages match a source register.
- The core bypasses WB results to the decode stage.
- Load-use dependencies insert a bubble.
- A pending data access stops the earlier stages. WB can still retire an older instruction.
- Taken branches and jumps flush the younger stages.
- A redirected fetch discards an old response without canceling an accepted transaction.
- An unaccepted request keeps its address and data stable during backpressure.

The front end permits one outstanding fetch. It can replace a completed request
on the same cycle when the interface accepts the next request.

## Instructions

| Group | Instructions |
|---|---|
| Register arithmetic | `ADD`, `SUB`, `SLT`, `SLTU` |
| Register logic | `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA` |
| Immediate arithmetic | `ADDI`, `SLTI`, `SLTIU` |
| Immediate logic | `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI` |
| Upper immediate | `LUI`, `AUIPC` |
| Loads | `LB`, `LBU`, `LH`, `LHU`, `LW` |
| Stores | `SB`, `SH`, `SW` |
| Branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Jumps | `JAL`, `JALR` |
| Ordering | `FENCE` |

Memory uses little-endian byte order. The core clears target bit zero for `JALR`.
Instructions need four-byte alignment. Halfword accesses need two-byte alignment.
Word accesses need four-byte alignment.

This implementation covers the RV32I integer datapath, not a complete privileged
system. Unsupported instructions and misaligned accesses assert the sticky
`fault` output. Reset clears the fault. Faults stop execution, but do not provide
precise traps or guarantee retirement of older instructions.

`ECALL`, `EBREAK`, CSR operations, interrupts, and trap handlers are not implemented.
`FENCE` needs no extra action because memory operations complete in order. There
is no store buffer, memory-mapped I/O support, or multi-hart coherence.

## Memory interfaces

The top module exposes separate instruction and data ports to external memory.
Both ports use the same request/response protocol:

| Signal | Meaning |
|---|---|
| `*_req_valid`, `*_req_ready` | A request transfers when both signals are high |
| `*_req_addr` | Aligned, 32-bit byte address |
| `*_req_data` | Word data for a write |
| `*_req_strb` | Byte write enables. Zero selects a read |
| `*_resp_valid`, `*_resp_ready` | A response transfers when both signals are high |
| `*_resp_data` | Word data for a read |

Every accepted request needs exactly one response, including writes. The earliest
response occurs after the request cycle. Keep requests and responses stable
until the receiving port accepts them. Each cache permits one outstanding
external transaction. The two caches have independent ports and can operate together.

The core shifts store data and generates byte enables. It extends signed loads
after the data response. The cache always receives aligned word requests.

## Blocking caches

Both caches use direct mapping. Each cache blocks new CPU requests until its
current response completes. Each cache transfers a line through sequential word
requests, not a burst protocol.

| Parameter | Default | Meaning |
|---|---|---|
| `CACHE_LINES` | 4 | Lines in each cache |
| `WORDS_PER_LINE` | 4 | 32-bit words in each line |
| `DATA_WRITE_BACK` | 1 | Data-cache write policy |
| `BYPASS_ICACHE` | 0 | Direct fetch interface for core tests |
| `REGION_BYPASS` | 0 | Cache only RAPTOR CPU-private RAM when enabled |
| `BYPASS_DCACHE` | 0 | Route all data requests directly to memory |

The default cache capacity is 64 bytes per cache. Line counts and words per line
must be powers of two, with a minimum value of two.

- The instruction cache refills a complete line on a miss.
- With `DATA_WRITE_BACK=1`, the data cache uses write-back and write-allocate.
- A dirty conflict writes the old line to memory before the refill.
- With `DATA_WRITE_BACK=0`, the data cache uses write-through and no-write-allocate.
- A write-through hit also updates the cached bytes.
- A write-through miss writes external memory without allocating a line.
- Reset invalidates all lines and clears counters. Reset does not write dirty lines to memory.

There is no cache-maintenance instruction. Do not reset the system to flush dirty
data. Evict dirty lines before a host reads their external memory locations.
Separate instruction and data storage in the tests does not support self-modifying code.

## Counters and retirement trace

The core exposes the retired PC, instruction, destination register, and result.
The trace includes stores, branches, fences, and instructions that target `x0`.
`retire_write` only identifies actual register writes.

The following 64-bit counters reset to zero:

- `cycles`: active cycles before a fault
- `retired`: retired instructions
- `load_stalls`: load-use bubbles outside a data-memory stall
- `memory_stalls`: cycles that wait for a data response
- `fetch_stalls`: cycles with an empty IF/ID register
- `redirects`: taken branches and jumps
- `branch_misses`: taken conditional branches under sequential, predict-not-taken fetch
- `icache_hits`, `icache_misses`: instruction-cache transactions
- `dcache_hits`, `dcache_misses`: data-cache transactions
- `dcache_writebacks`: dirty line evictions, not individual word writes

Stall counters can overlap. They are not additive components of the cycle count.
There is no dynamic branch predictor.

## Verification

Run all tests from the repository root:

```bash
make -f pipeline_cache/Makefile test
```

The Makefile stores generated files under `/tmp/opencode/pipeline_cache`.
Use `BUILD=/another/path` to change this directory.

### CPU differential tests

A separate architectural interpreter checks each retired PC, instruction, and
register result. It uses byte-addressed reference memory. The test program reads
stored values to check memory effects.

The tests cover all supported instruction groups, negative immediates, signed
comparisons, backward branches, jumps, wrong-path stores, and load dependencies.
A deterministic random ALU sequence adds dependent instructions.

Four configurations test:

1. Write-back caches with variable delays.
2. Write-through caches with the minimum registered response delay.
3. Larger caches and lines with longer variable delays.
4. A fast instruction interface to exercise forwarding priority and load-use bubbles.

The test memory also delays request acceptance. Assertions check interface
stability, pipeline holds, flushing, load-use bubbles, and `x0`.

### Cache tests

The standalone tests check read hits, compulsory misses, conflicting tags,
partial writes, dirty eviction, and complete backing-memory contents after eviction.
They also check response backpressure and reset invalidation.

### Fault tests

The fault tests check illegal encodings, unsupported instructions, misaligned
loads and stores, misaligned jump targets, and reset recovery.

These are custom tests, not an architectural compliance suite. Spike is not a
test dependency. The interpreter is not a substitute for independent compliance
tests or formal verification.

## Files

```text
pipeline_cache/
├── rtl/
│   ├── rv32_pkg.sv         # Pipeline register structures and ALU operations
│   ├── decoder.sv         # Instruction decoding and immediate generation
│   ├── core.sv            # Five stages, hazards, trace, and counters
│   ├── blocking_cache.sv  # Shared configurable cache implementation
│   └── pipeline_cache.sv  # Core and separate I/D caches
├── tb/
│   ├── delayed_memory.sv  # Backpressure and variable response delay
│   ├── tb_pipeline_cache.sv
│   ├── tb_blocking_cache.sv
│   └── tb_core_faults.sv
└── Makefile
```
