# Mission: Understand the RAPTOR-SoC Phase 1 SIMT GPU

## Why
I'm Person A on the Phase 1 GPU bring-up and I currently can't read the RTL or
the assignment without getting lost. I want a working mental model of how a
SIMT machine executes a kernel, so I can understand *why* each module exists
rather than transcribing TODOs. Understanding matters more to me than shipping
the implementation.

## Success looks like
- I can explain, in my own words, what a warp, a lane, a thread, and masking are.
- I can trace `brighten.asm` through this specific GPU, cycle by cycle, at block level.
- I can read any of the five Person A modules and say what it does and who it talks to.
- I can implement Person A knowing *why* each line is there (implementation is a bonus, not the goal).

## Constraints
- Engineer's background: comfortable with HDL/SystemVerilog and CPU design; new to GPUs/SIMT.
- Prefers going one file/concept at a time; dislikes being handed the whole thing at once.
- This is a real course assignment, so the work must remain honestly my own.

## Out of scope
- Phase 2 coalescing, Phase 4 SoC/bus integration, CUDA programming.
- Synthesis/FPGA/timing closure.
- The RISC-V `multi_cycle/` CPU subsystem (separate topic).
