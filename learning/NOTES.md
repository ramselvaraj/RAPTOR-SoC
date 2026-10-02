# Teaching notes

## Workspace
Teaching workspace lives in `learning/` (not the repo root) to keep the
RAPTOR-SoC tree clean. Relative links inside lessons assume this directory.

## Learner preferences
- Engineer background: knows HDL/SystemVerilog and CPU design; new to GPUs.
- Wants understanding first; implementation is secondary.
- Strongly prefers **one concept/file at a time** — do not front-load the whole assignment.
- Disliked the earlier wall-of-text file-by-file dump; requested a from-scratch rebuild.
- **Format: Markdown, not HTML.** Learner does not want HTML lessons.
  Keep the same "visual + hierarchical" feel using ASCII diagrams, tables,
  nested headings, and `<details>` reveals — no hand-authored HTML/CSS pages.
- Lesson 0001 was originally HTML (`lessons/0001-what-are-you-building.html`);
  offer to back-convert it to `.md` for consistency.

## Lesson plan
1. What are you building? (SIMT big picture) — `lessons/0001-...html` ✅ (HTML, to convert)
2. The shared bus and grant arbitration — `lessons/0002-...md` ✅
3. Wiring + all Person A modules + integration — `lessons/0003-wiring-and-modules.md` ✅
   (this condenses the originally-planned lessons 3–8 into one file, at the
   learner's request; no further core lessons planned)
4. Phase 2: blur, math, and the two loops — `lessons/0004-phase2-blur-and-branches.md` ✅
   Phase 2 hub: `PHASE2.md` ✅

## Open items
- Back-convert lesson 0001 to Markdown for consistency (offer pending).
- ~~Spec inconsistency: `WARPS*LANES = 8` but kernels use 256 threads.~~
  **Resolved:** the DCR wave loop relaunches the program per 8-thread wave, so
  the hardware covers any thread count. See lesson 0004 §8 and `PHASE2.md`.
