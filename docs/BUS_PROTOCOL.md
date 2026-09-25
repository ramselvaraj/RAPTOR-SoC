# RAPTOR-SoC Bus Protocol (v0)

Phase 1 uses a deliberately simple single-cycle bus. It matches the dual-port
framebuffer BRAM and is enough to grow into a shared CPU/GPU fabric in Phase 4.

## Signals

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `mem_req` | master→slave | 1 | transfer requested this cycle |
| `mem_we` | master→slave | 1 | 1 = write, 0 = read |
| `mem_addr` | master→slave | 32 | **word** address (Phase 1 simplification, see below) |
| `mem_wdata` | master→slave | 32 | write data (valid when `mem_we`) |
| `mem_rdata` | slave→master | 32 | read data (valid when `mem_req && !mem_we && mem_ready`) |
| `mem_ready` | slave→master | 1 | transfer completes this cycle |

## Rules

1. **Single-cycle, combinational handshake.** A master asserts `mem_req`
   (and `mem_addr`, `mem_we`, `mem_wdata`). The slave returns `mem_ready`
   (and `mem_rdata` for reads) in the **same cycle**. There is no separate
   valid/ack phase and no burst.
2. **Reads are combinational.** `mem_rdata` must be valid in the same cycle as
   `mem_req`, `!mem_we`, and `mem_ready`. A slave may always tie `mem_ready=1`
   if it has no wait states (Phase 1 memory does).
3. **Writes take effect on the rising clock edge** while `mem_req && mem_we &&
   mem_ready`.
4. **`mem_addr` is a word address in Phase 1.** `data_mem[mem_addr]`, not byte
   addressing. Phase 4's SoC decoder owns the byte↔word conversion; kernels do
   not change.
5. **One transfer per master per cycle.** Multi-master arbitration (CPU + GPU)
   is a Phase 4 concern; the arbiter will grant one master's request per cycle.

## Phase 4 evolution (do not implement now)

- Byte enables (`mem_be[3:0]`), byte addresses, error response.
- Arbiter with round-robin grant between CPU and GPU masters.
- Address decoder routing to system RAM / framebuffer / GPU program memory /
  GPU MMIO.
