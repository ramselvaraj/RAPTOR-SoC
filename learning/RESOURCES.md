# SIMT / GPU Bring-Up Resources

## Knowledge

- [NVIDIA CUDA Programming Guide — 1.2.2.2 Warps and SIMT](https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html)
  Primary definition of warp, lane, lock-step execution, and masking. Use for:
  grounding the SIMT vocabulary and why inactive lanes do no useful work.
- [Cornell Virtual Workshop — SIMT and Warps](https://cvw.cac.cornell.edu/gpu-architecture/gpu-characteristics/simt_warp)
  Clear SIMT-vs-SIMD comparison and a diagram of branch masking. Use for:
  the "why is SIMT not just SIMD" question.
- [Pastewka, "GPU architecture" (RWTH Aachen lecture notes)](https://pastewka.github.io/Accelerators/lecture/gpu_architecture.html)
  Thread hierarchy, warp/wavefront sizes, latency hiding. Use for: the
  big-picture GPU model above the level of this assignment.
- [UW CSE371 SystemVerilog Tutorial (PDF)](https://courses.cs.washington.edu/courses/cse371/24sp/verilog/Verilog_Tutorial.pdf)
  `always_comb` vs `always_ff`, blocking vs non-blocking, FSM idioms. Use for:
  the RTL patterns used throughout `simt_gpu/rtl`.
- [SystemVerilog for RTL Modeling, Simulation, and Verification](https://systemverilog.dev/3.html)
  Reference for `always_comb`, `always_ff`, reset styles, non-blocking semantics.
  Use for: nailing down exact simulation semantics when a testbench surprises me.
- [FPGA CPU — Ready/Valid Handshake Rules](https://fpgacpu.ca/fpga/handshake.html)
  Why ready/valid must not depend combinationally on each other, and the
  deadlock/livelock rules. Use for: contrasting the multi-cycle ready/valid
  handshake with this GPU's single-cycle one.
- [FPGA CPU — Round-Robin Arbiter](https://fpgacpu.ca/fpga/Arbiter_Round_Robin.html)
  Reference implementation and rationale for a non-starving round-robin arbiter
  with a "last granted" pointer. Use for: understanding the scheduler.
- [Yildiz, "Arbiters: Design Ideas and Coding Styles" (PDF)](https://abdullahyildiz.github.io/files/Arbiters-Design_Ideas_and_Coding_Styles.pdf)
  Survey of priority vs round-robin arbitration and pointer-update strategies.
  Use for: why pointer handling affects fairness and timing.
- RAPTOR-SoC in-repo docs: `docs/GPU_ISA.md`, `docs/BUS_PROTOCOL.md`,
  `docs/ADDRESS_MAP.md`, `docs/PHASE1_ASSIGNMENT.md`.
  Authoritative for this specific machine. Use for: field encodings, register
  aliases, bus rules, address map.

## Gaps

- No primary source found specifically for *warp schedulers* / round-robin
  arbitration at RTL level. Likely covered by a standard computer-architecture
  text (Hennessy & Patterson) once identified.
- No source yet on the "uncoalesced vs coalesced memory" contrast that Phase 2
  builds on. Deferred until Phase 2.

## Wisdom (Communities)

- [r/FPGA](https://www.reddit.com/r/FPGA/)
  High-signal, well-moderated hardware community. Use for: RTL style critique,
  "does this FSM smell right" questions.
- [Stack Exchange — Electrical Engineering](https://electronics.stackexchange.com/)
  Good for precise digital-design questions. Use for: specific SystemVerilog /
  Verilator behavior.
- Course staff / TA (if available) and the Person B partner.
  Use for: interface agreements and assignment-specific intent.
