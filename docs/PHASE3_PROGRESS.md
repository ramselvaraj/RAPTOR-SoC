# Phase 3 Progress — Full-Frame Blur + Performance Trace

Legend: `[x]` done · `[~]` in progress · `[ ]` not yet

Goal: extend the interior-only blur to a complete, pixel-exact clamped 3×3
blur (three sizes) plus a deterministic execution trace.

---

## Status

```
[1] reference box_blur_clamped() + tests      [x]
[2] .gen_blur_border generator + tests        [x]
[3] two-pass tb_gpu.sv (+prog2/+count2)       [x]
[4] run_sim.py --full mode                    [x]
[5] sizes 16/32/64                            [x]
[6] trace  (+trace=<path>)                    [x]
[7] trace checker tools/check_trace.py        [x]
[8] Make targets blur16/32/64, trace, phase3  [x]
```

---

## What was added

| File | Change |
|:--|:--|
| `tools/blur_ref.py` | `box_blur_clamped(img,W,H)` (interior kept) |
| `tools/assemble.py` | `.gen_blur_border W H` → `emit_blur_border()`; `pass` metadata; 1024-word limit check |
| `tools/run_sim.py` | `--full` two-pass clamped mode, `--trace` |
| `tb/tb_gpu.sv` | two-pass launch (`+prog2/+count2`), counters, `+trace` |
| `tools/check_trace.py` | trace invariants + traffic totals |
| `tools/tests/` | `test_blur_ref.py` (8), `test_blur_border.py` (4) |
| `Makefile` | `blur16/32/64`, `trace SIZE=`, `phase3`, `py-test` |

The border kernel is **branchless**: each thread selects its region arithmetically
from `tid`, so a warp that straddles two regions still computes correct
coordinates (no divergence).

---

## Measured results (RTL, built-in pattern)

| Size | interior + border threads | total cycles | reads | writes | result |
|---:|---:|---:|---:|---:|:--|
| 16×16 | 196 + 60 | 21 911 | 2304 | 256 | 0 mismatches |
| 32×32 | 900 + 124 | 81 815 | 9216 | 1024 | 0 mismatches |
| 64×64 | 3844 + 252 | 317 207 | 36864 | 4096 | 0 mismatches |

Program sizes: interior 125 instructions, border 191 instructions (constant per
size).

Trace (64×64, `make trace SIZE=64`):

```
CONFIG width=64 height=64 src=8192 dst=24576
PASS_START cycle=1 pass=interior threads=3844 waves=481
PASS_DONE  cycle=289526 pass=interior
PASS_START cycle=289528 pass=border threads=252 waves=32
PASS_DONE  cycle=317203 pass=border
SUMMARY cycles=317207 reads=36864 writes=4096 grants_warp0=158126 grants_warp1=158044
TRACE PASS
```

---

## Regressions (all still pass)

```
make unit TEST=tb_{alu,decoder,regfile,dcr,dispatcher,scheduler}   PASS
make branch                                                       TB_BRANCH PASS
make run        (brighten)                                        256 threads, 0 mismatches
make blur       (Phase 2 interior)                                3844 threads, 0 mismatches
make py-test                                                      12 tests OK
```

---

## Notes

- Two launches share one data-memory image (no reset between passes); the second
  pass just re-pulses `start`.
- Source framebuffer is never written (checked by `run_sim` and by the trace
  checker).
- Borders use edge-replicated (clamped) sampling for all 9 neighbours.
