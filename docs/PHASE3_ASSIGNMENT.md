# Phase 3 Assignment - Full-Frame Blur and Performance Trace

## Goal

Extend the Phase 2 interior-only blur into a complete, pixel-exact 3x3 box
blur. The GPU must write every output pixel for 16x16, 32x32, and 64x64
images and produce a deterministic execution trace with useful performance
metrics.

Phase 3 uses two GPU launches:

1. The existing interior kernel writes all non-border pixels.
2. A new border kernel writes the four clamped edges, including corners.

The Python driver and SystemVerilog testbench still schedule both launches.
CPU-controlled scheduling, shared CPU/GPU memory, MMIO, and SoC arbitration
belong to Phase 4.

Read first:

- `docs/GPU_ISA.md`
- `docs/BUS_PROTOCOL.md`
- `docs/PHASE2_ASSIGNMENT.md`
- `simt_gpu/tools/assemble.py`
- `simt_gpu/tools/run_sim.py`
- `simt_gpu/tb/tb_gpu.sv`

## Scope Decisions

- Keep the current uniform branch model. Do not add per-lane divergence or
  reconvergence.
- Generate separate programs for each image size. Do not add runtime width or
  height registers to the GPU.
- Keep the uncoalesced memory unit. Coalescing remains deferred scale-out work.
- Keep source and destination as separate framebuffer regions.
- Use clamped sampling for all border neighbors.
- Trace summary data and meaningful bus events. A full register-level
  architectural trace is not required.

## Clamped Blur Definition

For every output coordinate `(x, y)`, sample the 3x3 neighborhood centered on
that pixel. Clamp each sample coordinate independently:

```text
sample_x = min(max(x + dx, 0), width - 1)
sample_y = min(max(y + dy, 0), height - 1)
```

For each packed-RGB channel:

```text
output_channel = sum(nine clamped samples) // 9
```

Repack the result as `0x00RRGGBB`. Integer division truncates toward zero.

## Required Work

### 1. Independent Full-Frame Reference

Extend `simt_gpu/tools/blur_ref.py` with:

```python
box_blur_clamped(img, width, height)
```

Requirements:

- Return one output word for every input pixel.
- Clamp all out-of-range neighbor coordinates.
- Average red, green, and blue independently.
- Do not call the assembler or ISA simulator.
- Retain `box_blur_interior()` for the Phase 2 regression.

Add focused tests covering:

- All four corners.
- One pixel from each edge.
- At least one interior pixel.
- Packed-channel extraction and repacking.
- Integer-division truncation.

### 2. Border Kernel Generator

Add this assembler directive:

```asm
.gen_blur_border W H
```

Implement an `emit_blur_border(width, height)` generator in
`simt_gpu/tools/assemble.py`.

Launch exactly one thread for each border pixel:

```text
border_threads = 2 * width + 2 * (height - 2)
```

Map thread IDs to border coordinates without launching interior threads:

1. Top row, including both corners.
2. Bottom row, including both corners.
3. Left edge, excluding corners.
4. Right edge, excluding corners.

Every generated thread is a border thread, so no lane-dependent branch is
needed. The generated program must clamp the nine sample coordinates, average
the three channels, and write to `DST + y*width + x`.

The assembler must reject unsupported dimensions with a clear error. At
minimum, require `width >= 3` and `height >= 3`. Also reject a generated program
that exceeds the testbench's 1024-word instruction memory.

Metadata must distinguish the generated pass:

```json
{
  "width": 64,
  "height": 64,
  "pass": "border",
  "threads": 252,
  "src": 8192,
  "dst": 24576
}
```

Update the existing interior generator metadata to use `"pass": "interior"`.

### 3. Two-Pass RTL Dispatch

Extend `simt_gpu/tb/tb_gpu.sv` so one simulation can run two programs without
resetting data memory:

1. Load the source framebuffer once.
2. Load and run the interior program.
3. Wait for `done`.
4. Load or select the border program.
5. Run the border pass against the same source and destination buffers.
6. Wait for `done` and dump memory.

Add second-pass plusargs or an equivalent explicit interface. A suggested
scheme is:

```text
+prog=<interior.hex>
+count=<interior_threads>
+prog2=<border.hex>
+count2=<border_threads>
```

The single-pass Phase 1 and Phase 2 paths must continue to work when `prog2` is
not supplied.

### 4. Host Driver

Refactor `simt_gpu/tools/run_sim.py` to support a full-frame blur mode:

1. Generate or assemble the interior program for the requested dimensions.
2. Generate or assemble the border program for the same dimensions.
3. Generate the input frame.
4. Execute both programs in sequence in the ISA model using one data-memory
   image.
5. Compare the complete ISA-model destination against
   `box_blur_clamped()`.
6. Run both launches in one RTL simulation.
7. Compare every destination pixel against the ISA model.
8. Confirm the source framebuffer is unchanged.
9. Render the complete output image.

Dimension mismatches must fail before simulation begins.

Keep an explicit Phase 2 interior-only mode so the prior milestone remains
directly testable.

### 5. Supported Image Sizes

Support these square dimensions:

| Size | Interior threads | Border threads | Total pixels |
|---|---:|---:|---:|
| 16x16 | 196 | 60 | 256 |
| 32x32 | 900 | 124 | 1024 |
| 64x64 | 3844 | 252 | 4096 |

Programs may be generated independently for each size. One compiled program
does not need to support multiple dimensions.

### 6. Trace Output

Add a `+trace=<path>` testbench plusarg and emit a deterministic text file.

The trace header and summary must include:

- Width and height.
- Source and destination addresses.
- Pass names and thread counts.
- Wave count per pass.
- Cycle at each pass start and completion.
- Total cycle count.
- Total memory reads and writes.
- Grant count for each warp.

Emit event lines for meaningful cycles:

- Pass launch.
- Pass completion.
- Warp grant with instruction address.
- Memory read address.
- Memory write address and data.

Do not emit idle-only cycles. Use stable, script-friendly key/value text, for
example:

```text
CONFIG width=64 height=64 src=8192 dst=24576
PASS_START cycle=3 pass=interior threads=3844 waves=481
BUS cycle=42 warp=0 op=read addr=8255
BUS cycle=47 warp=1 op=write addr=24641 data=00112233
PASS_DONE cycle=123456 pass=interior
SUMMARY cycles=... reads=36864 writes=4096 grants_warp0=... grants_warp1=...
```

The exact line format may differ, but it must be documented and deterministic.

### 7. Trace Validation

Add a Python trace checker or equivalent automated assertions. For a complete
3x3 blur, the expected memory traffic is:

| Size | Reads | Writes |
|---|---:|---:|
| 16x16 | 2304 | 256 |
| 32x32 | 9216 | 1024 |
| 64x64 | 36864 | 4096 |

The checker must also verify:

- Both passes started and completed.
- Both warps received grants.
- No writes targeted the source framebuffer.
- Exactly one destination write occurred per pixel.

### 8. Make Targets

Add these targets or equivalent names with the same behavior:

```sh
make blur16
make blur32
make blur64
make trace SIZE=64
make phase3
```

`make phase3` must run the complete regression suite, including all existing
Phase 1 and Phase 2 checks.

## Acceptance Tests

Phase 3 is complete only when all of these pass:

| Check | Required result |
|---|---|
| Existing unit tests | All pass |
| `make branch` | `TB_BRANCH PASS` |
| Phase 1 brighten | 0 mismatches |
| Phase 2 interior blur | 0 mismatches |
| Clamped blur 16x16 | 256 pixels, 0 mismatches |
| Clamped blur 32x32 | 1024 pixels, 0 mismatches |
| Clamped blur 64x64 | 4096 pixels, 0 mismatches |
| Independent reference | ISA model matches every pixel |
| Source preservation | No source words changed |
| Trace checker | All counts and invariants pass |

The test input must include non-uniform corner and edge pixels so incorrect
border handling cannot pass accidentally.

## Regression Requirements

Do not break:

- `make run`
- `make blur`
- `make golden`
- `make branch`
- `make unit TEST=<existing-test>`

Do not change the Phase 2 ISA encoding or kernel-visible source/destination
register conventions.

## Deliverables

- Updated `simt_gpu/tools/blur_ref.py` and its tests.
- Updated `simt_gpu/tools/assemble.py` and assembler tests.
- Border-kernel source or documented generated-kernel entry point.
- Two-pass support in `simt_gpu/tb/tb_gpu.sv`.
- Two-pass/full-frame support in `simt_gpu/tools/run_sim.py`.
- Trace generation and automated trace validation.
- New Makefile targets.
- `docs/PHASE3_PROGRESS.md` containing measured results and cycle counts.
- README updates showing Phase 3 commands and final output.

## Out of Scope

Do not implement these in Phase 3:

- CPU-driven GPU launch.
- Unified CPU/GPU memory integration.
- GPU MMIO registers.
- CPU/GPU bus arbitration.
- AXI, APB, or PCIe interfaces.
- Per-lane branch divergence or reconvergence.
- Memory coalescing or caches.
- Interrupts.

These belong to Phase 4 or later.

## Recommended Implementation Order

1. Implement and test `box_blur_clamped()`.
2. Prototype the border generator and validate its instruction count and
   register allocation for all three sizes.
3. Verify the border program in `isa_sim.py` against the independent reference.
4. Add two-pass dispatch to `tb_gpu.sv`.
5. Add full-frame mode to `run_sim.py`.
6. Add 16x16, 32x32, and 64x64 Make targets.
7. Add trace generation and trace validation.
8. Run every regression and record exact results in
   `docs/PHASE3_PROGRESS.md`.

Before changing the RTL testbench, confirm that the generated border program
fits in program memory and that its register allocation does not overwrite
reserved registers `r0`, `r14`, or `r15`.
