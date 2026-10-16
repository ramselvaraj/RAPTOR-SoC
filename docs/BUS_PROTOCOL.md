# RAPTOR-SoC Bus Protocol (Phase 4)

The GPU pixel path retains the deliberately simple Phase 1 single-cycle bus.
Phase 4 adds a separate AXI4-Lite control/data path for the CPU.

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

## CPU AXI4-Lite path

- 32-bit byte-addressed AXI4-Lite with independent `AW`, `W`, `B`, `AR`, and
  `R` channels and one outstanding transaction per master.
- Four write strobes are honored by RAM and MMIO writes.
- The round-robin interconnect has two master ports and routes top-nibble
  `0x4` accesses to GPU MMIO; other accesses go to the RAM slave, which returns
  `SLVERR` outside `0x0000_4000..0x0001_BFFF`.
- CPU instruction fetch remains on a private TCM. GPU program fetch remains on
  a private 16-bit program-memory port.
- CPU/AXI byte addresses map to the unchanged GPU word addresses by shifting
  right two bits. GPU pixel traffic does not traverse AXI.
