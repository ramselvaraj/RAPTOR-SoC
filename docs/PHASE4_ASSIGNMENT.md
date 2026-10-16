# Phase 4 Assignment — SoC Integration (AXI4-Lite + CPU-Driven GPU)

## Goal

Make the RISC-V CPU the master of the system. The CPU configures the GPU through
AXI4-Lite MMIO and dispatches both blur passes itself, replacing the testbench
and Python driver as the launch authority. Framebuffer pixel traffic keeps
flowing over the existing simple GPU bus. The result must be the same
pixel-exact clamped full-frame blur produced in Phase 3.

```text
              CPU (riscv_mc + ADDI/BNE/JAL)
                 │                    │
      private instr TCM          AXI4-Lite data master
      (0x0000_0000)                    │
                                 ┌─────┴───────────────┐
                       AXI4-Lite interconnect (round-robin)
                                 │                     │
                        shared RAM host port      GPU MMIO slave
                                 │                CTRL/STATUS/THREADS/
                                 │                SRC/DST/PROG_BASE
                                 │                     │
                                 │             MMIO→DCR bridge
                                 │                     │
        GPU pixel simple bus ────┤              simt_gpu control ports
        (mem_req/mem_ready)      │
                          shared RAM pixel port
                          (dual-port BRAM)
```

Read first:

- `docs/GPU_ISA.md`, `docs/BUS_PROTOCOL.md`, `docs/ADDRESS_MAP.md`
- `docs/PHASE{1,2,3}_ASSIGNMENT.md`
- `simt_gpu/rtl/simt_gpu.sv`, `simt_gpu/rtl/dcr.sv`, `simt_gpu/rtl/mem_unit.sv`
- `multi_cycle/rtl/*.sv`
- `simt_gpu/tools/run_sim.py`, `simt_gpu/tb/tb_gpu.sv`

## Scope Decisions

These are fixed for Phase 4.

| Decision | Choice |
|---|---|
| CPU ISA extension | Add `ADDI`, `BNE`, `JAL` |
| Memory | Single unified RAM + address decoder |
| Control interconnect | AXI4-Lite |
| CPU instruction fetch | Private instruction TCM (not on AXI) |
| Interconnect topology | Shared AXI4-Lite bus + round-robin arbiter |
| Pixel path | Existing simple `mem_req/mem_ready` bus |
| GPU program selection | `PROG_BASE` MMIO register |
| Completion | Polling `STATUS`; no interrupts |

Do **not** add in Phase 4: AXI4 bursts, cache coherency, DMA, interrupts, CPU
writing kernel code, per-lane divergence, or memory coalescing.

## New Directory Layout

```text
soc/
├── rtl/
│   ├── soc_top.sv                 # CPU + GPU + interconnect + RAM + MMIO
│   ├── axi_lite_interconnect.sv   # round-robin arbiter + address decoder
│   ├── axi_lite_ram.sv            # shared-RAM host port (AXI4-Lite slave)
│   ├── gpu_mmio.sv                # CTRL/STATUS/THREADS/SRC/DST/PROG_BASE
│   ├── cpu_axi_master.sv          # single-outstanding AXI4-Lite master
│   ├── shared_ram.sv              # dual-port BRAM (pixel port + host port)
│   └── program_memory.sv          # GPU imem, indexed by PROG_BASE + pc
├── tb/
│   ├── tb_axi_lite.sv             # interconnect + slaves + backpressure
│   ├── axi_lite_checker.sv        # SVA protocol assertions (bound)
│   └── tb_soc.sv                  # end-to-end CPU-driven blur
├── tools/
│   ├── riscv_asm.py               # tiny assembler for the CPU subset
│   └── run_soc.py                 # preload programs+image, run, compare, trace
└── files.txt
```

CPU RTL changes stay in `multi_cycle/rtl/`. GPU RTL is untouched except wiring.

## Final Address Map

The Phase 1 draft labels its values "word indices written as byte-style hex."
Resolve that as follows: the GPU pixel bus stays **word-addressed** with
`src=0x2000`, `dst=0x6000`, exactly as in Phase 1–3, so no tests or images
change. The CPU/AXI side is **byte-addressed** per RISC-V, so `byte = word << 2`.

| Region | CPU/AXI byte base | GPU word base | Size | Port |
|---|---:|---:|---:|---|
| CPU instruction TCM | `0x0000_0000` | — | 4 KiB | private |
| System RAM | `0x0000_4000` | `0x1000` | 4 KiB | AXI + pixel |
| Framebuffer A (src) | `0x0000_8000` | `0x2000` | 16 KiB | AXI + pixel |
| Framebuffer B (dst) | `0x0001_8000` | `0x6000` | 16 KiB | AXI + pixel |
| GPU program memory | `0x0002_8000` | `0xA000` | 4 KiB | private GPU imem |
| GPU MMIO | `0x4000_0000` | — | 0x20 | AXI |

- Shared RAM host window: `0x4000–0x1BFFF`, backed by a 32768-word sparse
  memory so GPU word addresses remain unchanged; host index `addr[16:2]`.
- GPU `SRC`/`DST` MMIO values are **word** addresses (GPU-native), so
  `0x2000`/`0x6000`.

This table supersedes the Phase 1 draft in `docs/ADDRESS_MAP.md`. Update that
document to match.

## AXI4-Lite Interface Specification

| Channel | Signals |
|---|---|
| Write address | `AWADDR[31:0]`, `AWVALID`, `AWREADY` |
| Write data | `WDATA[31:0]`, `WSTRB[3:0]`, `WVALID`, `WREADY` |
| Write response | `BRESP[1:0]`, `BVALID`, `BREADY` |
| Read address | `ARADDR[31:0]`, `ARVALID`, `ARREADY` |
| Read data | `RDATA[31:0]`, `RRESP[1:0]`, `RVALID`, `RREADY` |

Rules: 32-bit data, 4-byte aligned addresses (low 2 bits ignored), `WSTRB`
honored, responses `OKAY=2'b00` / `SLVERR=2'b10`, one outstanding transaction
per master.

## Module Requirements

### `soc_top.sv`

Instantiates `riscv_mc`, `simt_gpu`, `axi_lite_interconnect`, `shared_ram`,
`gpu_mmio`, `program_memory`, `cpu_axi_master`. Wiring:

- CPU instruction TCM is internal to the CPU (private).
- `cpu_axi_master` → AXI master port 0 of the interconnect.
- Interconnect slave 0 → `axi_lite_ram` (host port of `shared_ram`); slave 1 →
  `gpu_mmio`.
- `shared_ram` pixel port ↔ `simt_gpu` `mem_*` (word-addressed, unchanged).
- `program_memory` read = `prog_mem[prog_base + imem_addr]` → `imem_rdata`.
- `gpu_mmio` outputs drive `simt_gpu.start/thread_count/src_addr/dst_addr`;
  `gpu_mmio` reads `simt_gpu.busy/done` for `STATUS`.
- CPU data port ↔ `cpu_axi_master`.

### `axi_lite_interconnect.sv`

Two masters (CPU, bring-up testbench), two slaves (RAM, MMIO).

- **Arbiter**: round-robin over requesting masters, modeled on
  `simt_gpu/rtl/scheduler.sv`. Hold the grant for the whole transaction; release
  when the master accepts its response.
- **Decoder**: combinational on the pending address (`AWADDR` for writes,
  `ARADDR` for reads). MMIO if `addr[31:28]==4'h4`; else RAM.
- **Muxing**: forward the granted master's `AW/W/AR` to the decoded slave;
  forward the slave's `B/R` back to that master. Non-granted masters see
  `*READY=0`.

### `axi_lite_ram.sv`

AXI4-Lite slave over the `shared_ram` host port. Byte address → word index
`addr[16:2]`. Combinational read; synchronous write honoring `WSTRB`. Always
`OKAY`. Unknown address → `SLVERR`.

### `gpu_mmio.sv`

| Offset | Name | R/W | Behavior |
|---|---|---|---|
| `0x00` | `CTRL` | W | bit0 write → one-cycle `start` pulse to DCR |
| `0x04` | `STATUS` | R | bit0=`busy`, bit1=`done` |
| `0x08` | `THREADS` | W | thread count latch |
| `0x0C` | `SRC` | W | source word address latch |
| `0x10` | `DST` | W | destination word address latch |
| `0x14` | `PROG_BASE` | W | program base word offset latch |

`start` is a one-cycle pulse; the DCR already ignores `start` unless in `D_IDLE`.

### `program_memory.sv`

`logic [15:0] mem[0:1023]`, preloaded by the testbench. Read
`mem[(prog_base + imem_addr) & 10'h3FF]`. Interior program at offset 0; border
program at offset 512 (`PROG_BASE=512` for pass 2).

### `shared_ram.sv`

Dual-port array in a **single `always_ff`** so it is legal in Verilator:

```systemverilog
always_ff @(posedge clk) begin
    if (px_we)   mem[px_addr]   <= px_wdata;    // pixel port
    if (host_we) mem[host_addr] <= host_wdata;  // host port (wins on collision)
end
assign px_rdata   = mem[px_addr];
assign host_rdata = mem[host_addr];
```

Pixel port is word-addressed; host port word index `addr[16:2]`.

### CPU Changes (`multi_cycle/rtl`)

**Controller (`controller.sv`)**

- New states: `EXEC_I` (ADDI), `JAL`, `MEM_READ_WAIT`, `MEM_WRITE_WAIT`.
- New outputs: `branch_ne`, `mem_start`, `mem_rd_done`, `mem_wr_done`.
- `ADDI` (`opcode 0x13`): `DECODE → EXEC_I → WB_ALU`; `EXEC_I` sets
  `alu_src_b=2`, `alu_operation=ADD`, `aluout_write=1`.
- `BNE` (`0x63`, `funct3=001`): `BRANCH` sets
  `pc_write = branch_ne ? ~zero : zero`.
- `JAL` (`0x6F`): `DECODE` latches `pc+4` into `alu_out`; `JAL` writes
  `rd=alu_out`, sets `pc_write=1`, `alu_src_b=4`, `pc_next_from_aluout=0`.
- `LW`/`SW`: `MEM_READ`/`MEM_WRITE` assert `mem_start`; wait for
  `mem_rd_done`/`mem_wr_done` before `WB_MEM`/`FETCH`.

**Datapath (`datapath.sv`)**

- Remove the internal `memory dmem_inst`; expose the CPU data-memory port up to
  `riscv_mc`.
- Add the J-type immediate
  `imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0}`.
- Extend `alu_src_b`: `4` → `imm_j - 4` (compensates PC already advanced by 4).

**ALU (`alu.sv`)** — unchanged (`ADD/SUB/AND/OR` + `zero` suffice).

**Instruction TCM (`instruction_memory.sv`)** — enlarge to 1024 words; add a load
port (or `$readmemh`) for the driver program.

**`riscv_mc.sv`** — add CPU data-memory ports; `cpu_axi_master` is instantiated
in `soc_top` (or expose `req/we/addr/wdata/rdata/done`).

### `cpu_axi_master.sv`

Single-outstanding AXI4-Lite master FSM:

```text
A_IDLE → (req) read ? A_AR : A_AW
A_AR   → ARVALID until ARREADY → A_R
A_R    → RVALID → latch RDATA → done → A_IDLE
A_AW   → AWVALID until AWREADY → A_W
A_W    → WVALID until WREADY → A_B
A_B    → BVALID → done → A_IDLE
```

Drives `rdata` and `done` back to the CPU. `WSTRB` from the CPU byte address
(all 4 bits for word ops).

## Clock and Reset

Single `clk`, single `reset`, shared by CPU and GPU. Reset initializes MMIO
registers and all FSMs. The testbench loads the TCM, GPU program memory, and RAM.

## CPU Driver Software

Driver subset: `ADDI/BNE/JAL/LW/SW/ADD/SUB/AND/OR/BEQ`. Because `ADDI` cannot
form `0x4000_0000` and there is no `LUI`, the testbench preloads pointers before
reset release:

| Reg | Value |
|---|---|
| x5 | `0x4000_0000` MMIO base |
| x6 | `0x2000` SRC word |
| x7 | `0x6000` DST word |
| x8 | interior thread count |
| x9 | border thread count |
| x10 | `PROG_BASE=0` |
| x11 | `PROG_BASE=512` |
| x14 | `2` (done mask) |

Program shape:

```asm
# pass 1 (interior)
sw   x6, 0x0C(x5)       # SRC
sw   x7, 0x10(x5)       # DST
sw   x8, 0x08(x5)       # THREADS
sw   x10,0x14(x5)       # PROG_BASE
addi x12, x0, 1
sw   x12,0x00(x5)       # CTRL.start
poll1: lw x13,0x04(x5); and x15,x13,x14; beq x15,x0,poll1
# pass 2 (border): repeat with x9, x11
halt:  beq x0, x0, halt
```

`riscv_asm.py` assembles this subset to hex; the testbench loads it into the CPU
TCM.

> Alternative: add `LUI` and drop the register preload. Phase 4 uses the preload;
> `LUI` is deferred.

## Verification Requirements

### AXI protocol checker (`axi_lite_checker.sv`, SVA, bound)

- Payload/address stable while `VALID && !READY`.
- `BVALID` only after `AW` and `W` accepted.
- `RVALID` only after `AR` accepted.
- No combinational `*READY`-depends-on-`*VALID` loop.
- Response only after request.

### `tb_axi_lite.sv`

- Per-slave: RAM read/write with `WSTRB`, MMIO read/write, `SLVERR` for unknown
  addresses.
- Arbiter: fairness/no-starvation (mirrors the scheduler test).
- Randomized `READY` backpressure on all channels.
- Testbench master issues randomized read/write sequences and self-checks.

### CPU tests (`tb_riscv_mc.sv`, rewritten)

- `ADDI`, `BNE` (taken/not-taken), `JAL` (target + return address).
- `LW`/`SW` over AXI with injected stalls.
- Stop poking internal arrays; drive the AXI RAM model instead.

### `tb_soc.sv` + `run_soc.py`

1. Preload CPU TCM with the driver; preload GPU program memory (interior @0,
   border @512); preload the image into framebuffer A.
2. Release reset; the CPU dispatches both passes and polls.
3. Dump framebuffer B; compare against `blur_ref.box_blur_clamped()` for
   16/32/64.
4. Confirm framebuffer A is unchanged.
5. Emit a trace: CPU MMIO writes, GPU pass start/done, GPU bus reads/writes,
   and totals.

## Make Targets

```sh
make axi                 # tb_axi_lite + checker
make cpu                 # rewritten CPU tests
make soc16 soc32 soc64   # end-to-end CPU-driven blur per size
make soc                 # full SoC at 64x64
make phase4              # unit + branch + phase1-3 + axi + cpu + soc{16,32,64}
```

## Acceptance Tests

Phase 4 is complete only when all of these pass:

| Check | Required result |
|---|---|
| AXI protocol checker | No assertion failures under random backpressure |
| `make axi` | All per-slave + arbiter tests pass |
| `make cpu` | `ADDI/BNE/JAL` and AXI `LW/SW` pass |
| CPU-driven blur 16x16 | 256 pixels, 0 mismatches |
| CPU-driven blur 32x32 | 1024 pixels, 0 mismatches |
| CPU-driven blur 64x64 | 4096 pixels, 0 mismatches |
| Independent reference | Output matches `box_blur_clamped()` |
| Source preservation | No framebuffer-A words changed |
| Both passes | Started and completed, seen in the trace |
| Phase 1–3 regressions | All still pass |

## Regression Requirements

Do not break:

- `make run`, `make blur`, `make blur16/32/64`, `make golden`
- `make branch`, `make trace SIZE=<n>`, `make phase3`
- `make unit TEST=<existing-test>`

Do not change the Phase 2/3 ISA encoding, the GPU pixel-bus protocol, or the
kernel-visible source/destination conventions.

## Sub-Phase Milestones

| Milestone | Deliverable | Acceptance |
|---|---|---|
| **4a** | Interconnect, RAM slave, MMIO slave, checker, `tb_axi_lite` | All AXI tests + assertions pass under random backpressure |
| **4b** | CPU `ADDI/BNE/JAL` + AXI master; GPU wired; `tb_riscv_mc` rewritten | CPU tests pass; Phase 1–3 targets still green |
| **4c** | Driver + `tb_soc` + `run_soc.py` | Clamped blur 16/32/64 pixel-exact, source unchanged, trace valid |

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| AXI master FSM bugs (dropped transfers, unstable payload, lost responses) | SVA checker + randomized backpressure before integration |
| CPU memory rewrite breaks `tb_riscv_mc` | Rewrite around an AXI RAM model; keep ISA tests independent |
| Dual-port RAM modeling in Verilator | Single `always_ff` with explicit collision priority |
| Byte vs word addressing confusion | Single resolution table above; assert addresses in tests |
| Instruction-register pressure / TCM size | Size TCM to the driver; preload via `$readmemh` |
| Two control paths for the DCR | `simt_gpu` keeps its ports; `tb_gpu` drives them directly, SoC drives from MMIO |

## Deliverables

- New `soc/` RTL, testbenches, and tools listed above.
- CPU changes in `multi_cycle/rtl` for `ADDI/BNE/JAL` and the AXI data master.
- Rewritten `tb_riscv_mc.sv`.
- AXI protocol checker and its testbench.
- `run_soc.py` with pixel-exact comparison and a trace.
- New Makefile targets.
- Updated `docs/ADDRESS_MAP.md`, `docs/BUS_PROTOCOL.md`, `README.md`.
- `docs/PHASE4_PROGRESS.md` with measured results and cycle counts.

## Recommended Implementation Order

1. Build `shared_ram`, `axi_lite_ram`, `gpu_mmio`, `axi_lite_checker`.
2. Build `axi_lite_interconnect` (arbiter + decoder); pass `tb_axi_lite`.
3. Add `cpu_axi_master`; verify standalone.
4. Extend the CPU ISA + FSM; rewrite `tb_riscv_mc`.
5. Assemble `soc_top`; wire the GPU pixel port and `program_memory`.
6. Write `riscv_asm.py` and the driver; load via `tb_soc`.
7. Run `make soc16/32/64`; compare to `box_blur_clamped`.
8. Add the trace and `run_soc.py`; run `make phase4`.
9. Update the docs and record exact results in `docs/PHASE4_PROGRESS.md`.
