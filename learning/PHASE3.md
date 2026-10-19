# Phase 3 — Full-Frame Blur (learning hub)

This file uses Simplified Technical English. For the full lesson, read
`lessons/0005-phase3-full-frame-blur.md`.

---

## One line

```
Phase 2: interior blur only      →      Phase 3: blur every pixel + a trace
```

Phase 3 blurs the whole image. It uses two passes. It also writes a
performance trace.

---

## Status board

```
box_blur_clamped reference   [x]   tools/blur_ref.py + tests
border generator             [x]   .gen_blur_border (no branch)
two-pass testbench           [x]   +prog2 / +count2
full-frame driver            [x]   run_sim.py --full
sizes 16/32/64               [x]
trace + checker              [x]   +trace, tools/check_trace.py
Make targets                 [x]   blur16/32/64, trace, phase3
```

---

## File map

| File | What changed |
|:--|:--|
| `tools/blur_ref.py` | add `box_blur_clamped()` |
| `tools/assemble.py` | add `.gen_blur_border`; add `pass` metadata |
| `tools/run_sim.py` | add `--full` and `--trace` |
| `tb/tb_gpu.sv` | run two programs in one simulation |
| `tools/check_trace.py` | test the trace |

---

## The two ideas

```
1. Two passes       interior program first. Border program second.
2. Trace            the testbench writes a text file. A checker tests it.
```

---

## Results

```
make blur16   PASS 256 pixels,  0 mismatches
make blur32   PASS 1024 pixels, 0 mismatches
make blur64   PASS 4096 pixels, 0 mismatches
make trace SIZE=64   TRACE PASS (reads=36864 writes=4096)
make phase3   all checks pass
```

---

## Read more

- `docs/PHASE3_ASSIGNMENT.md` — the specification
- `docs/PHASE3_PROGRESS.md` — the measured results
- `lessons/0005-phase3-full-frame-blur.md` — the lesson
