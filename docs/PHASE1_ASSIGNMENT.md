# Phase 1 Assignment — SIMT GPU Bring-Up

**Goal:** replace the Phase 0 scanner with a real SIMT device and run the
`brighten` kernel through it, verified pixel-for-pixel against a Python golden
model.

Read first: `docs/BUS_PROTOCOL.md`, `docs/ADDRESS_MAP.md`, `docs/GPU_ISA.md`.

## Configuration (decided)

- `WARPS = 2`, `LANES = 4` → **8 physical threads per wave**, 16 registers/lane,
  16-bit ISA.
- Data bus is single-cycle combinational; instruction memory is combinational.
- `r0 = threadIdx`, `r14 = SRC`, `r15 = DST` (dispatcher-preloaded).

## Wave (thread-block) loop

The hardware has only 8 lanes, but a kernel may ask for more threads (the
acceptance kernel wants 256). Like a real GPU running a grid of thread blocks,
`dcr` sequences **waves**: it launches the 8 lanes, waits for all warps to
halt, advances `block_base` by 8, and relaunches — until `thread_count` is
covered. 256 threads = 32 waves.

```
dcr: IDLE --start--> LAUNCH --1cy--> RUN --all_halted?--> more? LAUNCH : DONE
                     launch=1                    block_base += 8
dispatcher: tid = block_base + w*LANES + l
```

So `dcr` gained `launch` (per-wave restart pulse) and `block_base`, and
`dispatcher` gained the `block_base` input. A warp restarts from `W_HALT` (pc
back to 0) on each `start_warp` pulse.

## Repair the interface first

The module **ports are frozen**. Both of you should read every `rtl/*.sv`
skeleton and agree on these before writing bodies:

- `rtl/dcr.sv` — `start/thread_count/src/dst/all_halted` →
  `busy/done/launch/block_base/*_q`
- `rtl/dispatcher.sv` — `thread_count`, `block_base` → `warp_start`,
  `warp_tid_base`, `warp_lane_mask`
- `rtl/scheduler.sv` — `ready[WARPS]` → one-hot `grant[WARPS]`
- `rtl/warp.sv` — per-warp FSM (FETCH/EXEC/MEM/HALT), instantiates
  `decoder`, `regfile`, `mem_unit`, and concurrent `alu`s
- `rtl/mem_unit.sv` — serialized per-lane load/store
- `rtl/regfile.sv`, `rtl/alu.sv`, `rtl/decoder.sv`

If you need to change a port, **tell the other person first** and update this
doc.

## Ownership

### Person A — control & data movement

| File | Requirement | Test |
|---|---|---|
| `rtl/alu.sv` **or** `rtl/decoder.sv` (pick one to start) | see Person B table | unit |
| `rtl/dcr.sv` | Latch config on `start`; sequence waves: `launch=1` for one cycle, `busy` while running, advance `block_base` by `TB`, pulse `done` after the final wave | `make unit TEST=tb_dcr` |
| `rtl/dispatcher.sv` | `tid = block_base + w*LANES + l`; `warp_tid_base[w] = block_base + w*LANES`; lane active iff `tid < thread_count`; `warp_start` follows `start` | `make unit TEST=tb_dispatcher` |
| `rtl/scheduler.sv` | Round-robin, exactly one grant/cycle, fair | `make unit TEST=tb_scheduler` |
| `rtl/mem_unit.sv` | Walk lanes 0..LANES-1, skip inactive; one bus transfer per active lane at `base+idx`; capture loads; pulse `done` | via `make run` |
| `rtl/simt_gpu.sv` | Provided wiring — verify the grant-based memory/instruction mux and fix if needed | `make run` |

### Person B — compute core

| File | Requirement | Test |
|---|---|---|
| `rtl/alu.sv` | `op==0`→`a+b`, `op==1`→`a-b` | `make unit TEST=tb_alu` |
| `rtl/decoder.sv` | Slice the fields; `legal=1` for opcodes `0x0..0x5` | `make unit TEST=tb_decoder` |
| `rtl/regfile.sv` | 16 regs × LANES; `r0/r14/r15` special read-only; per-lane write mask; reset to 0 | `make unit TEST=tb_regfile` |
| `rtl/warp.sv` | FSM in the file header; instantiate decoder/regfile/alu/mem_unit; `ready` in FETCH/EXEC/MEM; `RET` halts; restart from `W_HALT` (pc←0) on `start_warp` | `make run` |

## Test commands

```sh
cd simt_gpu
make unit TEST=tb_alu          # or tb_decoder / tb_regfile / tb_dcr /
                               #   tb_dispatcher / tb_scheduler
make build                     # compile integration tb
make run                       # assemble -> golden model -> RTL -> PNG compare
```

`make run` prints `PASS: 256 threads, 0 mismatches -> .../out.png` when done.

## Golden model

`tools/isa_sim.py` executes the same program in Python. If RTL and golden model
disagree, the golden model is the reference — your RTL has the bug. Suggested
debug order:

1. `make run` passes with `sw/kernels/copy.asm` first (M2).
2. Then `sw/kernels/brighten.asm` (M3).

## Milestones

| # | Milestone | Acceptance |
|---|---|---|
| M1 | All six unit tests pass | each prints `TB_<NAME> PASS` |
| M2 | Copy round-trip | `make run` with `--kernel sw/kernels/copy.asm` → 0 mismatches |
| M3 | Brighten | `make run` → 0 mismatches, PNG rendered |
| M4 | Scheduling proof | both warps make progress (inspect with a wave/trace) |
| M5 | Lane masking | run a `count` not a multiple of 4 (e.g. edit `.threads`) → inactive lanes write nothing |

## Definition of done

- All six unit tests pass.
- `make run` with `brighten.asm` prints 0 mismatches.
- No edits to frozen ports without the partner's agreement.
- `make run` with `copy.asm` also passes.

## Notes / gotchas

- `rtl/simt_gpu.sv` wiring is provided; if you change submodule ports, update it.
- `mem_addr` is a **word** index in Phase 1 (`docs/BUS_PROTOCOL.md` rule 4).
- Memory is 32768 words; `SRC=0x2000`, `DST=0x6000` are word indices.
- Inactive lanes must not write registers or memory.
- `STR` operand order is `STR rs_data, rs_base, rs_idx`.
