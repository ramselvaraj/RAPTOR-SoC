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

## Phase 5 multi-clock interfaces

These additions apply to `soc_phase5_top`. The legacy `soc_top` keeps the Phase 4 behavior.

- CPU request/response ports use valid/ready on both directions. Each successful accepted request gets exactly one registered response, including writes.
- The data-to-AXI adapter carries all byte strobes. It accepts one outstanding operation and holds the CPU response under backpressure.
- An AXI error latches a fail-stop SoC fault instead of returning a successful response. Coordinated reset is required for recovery. The design does not provide precise traps.
- GPU memory completion can take many cycles. `mem_ready` means response completion, not async-FIFO request acceptance.
- The GPU scheduler locks the requesting warp until that completion. Other warps cannot consume its response.
- Request and response FIFOs connect the GPU bus to the CPU-clocked shared RAM. Writes are acknowledged after commit.
- CPU MMIO start captures a complete configuration snapshot. Busy reserves the launch until completion returns to the CPU domain.
- A start during busy returns `SLVERR`. Shadow configuration writes cannot change the active GPU job.
- Done crosses through an event FIFO and becomes sticky CPU-domain status. It cannot precede the launch's final committed write.

The top has separate `cpu_clk`, `gpu_clk`, coordinated active-high `arst`, and `boot_hold` inputs.
Each clock domain synchronizes reset release. Only coordinated domain reset is supported.
Keep `boot_hold=1` after reset until boot writes finish, then release execution.
Do not reassert boot hold during a live job without coordinated reset.
CDC transport stays operational during boot hold.

`boot_valid && boot_ready` accepts one word write in the CPU domain.
`boot_sel` uses the original CPU-program/GPU-program/RAM selections.
Hold the payload until acceptance. Wait for `boot_done` before issuing the next boot word.
`boot_error` accompanies completion for reserved selections or out-of-range instruction addresses.
CPU/RAM writes commit locally. GPU program writes complete only after acknowledgment from the GPU domain.
After the final completion, deassert `boot_hold` to release execution and invalidate caches.
`memory_service_enable` is a CPU-domain service-enable input. Tie it high normally or use it to inject test stalls.

Debug counters remain in their owning clock domains. CPU/GPU cycle counts cannot be added together.
Tests observe them directly, but a hardware CPU reader would need a separate snapshot protocol.
