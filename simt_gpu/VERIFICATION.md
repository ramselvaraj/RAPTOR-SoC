# GPU verification: random-kernel differential testing and mutation testing

`tools/rand_kernel.py` generates random kernels and compares the **entire data memory** after running them on the
Verilated GPU (`tb_gpu`) against the Python golden model (`tools/isa_sim.py`). `tools/mutate_gpu.py` injects RTL bugs
and checks the harness kills them.

```
make build
python3 tools/rand_kernel.py --count 800 --seed 1            # random kernels (default features: loops,scratch,branches)
KERNEL_FEATURES=loops python3 tools/rand_kernel.py ...        # restrict generator features
ALLOW_G1=1 python3 tools/rand_kernel.py ...                   # also generate loops on the thread counts that trigger finding G1
python3 tools/mutate_gpu.py --kernels 80                      # 30 mutants
python3 tools/repro_g1_idle_warp_hang.py                      # finding G1 reproducer
```

## Kernel generator

Thread count 1..20 (so partial warps and up to 3 launch waves), a random 256-word frame, and: ADD/SUB/MUL/DIV/AND/OR/XOR/
SLL/SRL, constants (including large values with bit 31 set), masked loads from the frame, per-thread scratch
store-then-load round trips, `CMP` + forward `BRnzp` blocks with thread-uniform conditions, uniform counted loops
(backward branches), occasional writes to `r0/r14/r15` (which must be ignored), and an epilogue that stores every
register of every thread to a unique address. Every register is initialised in a prologue (the register file is only
reset by the global reset, not per launch wave). Branch conditions are provably thread-uniform (a flow-sensitive
uniformity analysis merges both paths of every skipped block) because the GPU has no divergence support.

## Results

| Run | Result |
|---|---|
| 800 random kernels (loops kept off the G1-prone thread counts) | 800 / 800 memory-identical to the model |
| 600 random kernels, earlier feature set | 600 / 600 |
| Branch isolation: 6 operand relations x 8 condition masks x 9 offsets | 432 / 432 identical |
| Mutation testing, 30 RTL mutants | **27 killed**, 3 survivors (equivalent, below) |

Mutants: ALU (sub, mul width, div by zero, signed div, sll width, srl arithmetic, and/or, xor/or), register file (tid per
lane, src/dst swapped, special-register write protection), dispatcher (lane mask, warp base), wave sequencer (extra wave, base
step), warp flags and branches (cmp operand order, N/Z/P flags, branch sign-extension, condition bits, offset), constants (7-bit),
memory unit (address, write data lane, load lane, lane skipping, stuck lane pointer).

The 3 survivors (`rf_r0/r14/r15_writable`) are equivalent: reads of those registers are hard-wired in `read_one`, so
their storage is never observable. (An earlier "signed divide" mutant also survived because SystemVerilog propagates the
unsigned conditional-arm type into the `/` operands and overrides `$signed`; rewritten with a self-determined cast it is killed.)

## Finding G1: an idle warp can hang the GPU (liveness)

**Symptom.** `tb_gpu` never reaches `done` ("GPU never asserted done"; the watchdog fires after 50M cycles) for a kernel that
terminates for every active thread, for thread counts 9-12 and 17-20, when the kernel contains a data-dependent backward branch.

**Mechanism.** In the last launch wave, one warp can have no active lane (T = 9..12: warp 1 would hold tids 12-15, all >= T).
That warp still executes the kernel. The branch unit decides from **lane 0's** `CMP` result regardless of the lane mask (see the
comment in `warp.sv`: "Branches are uniform: lane 0's comparison decides the flags"), but a fully masked warp never performs the
kernel's register writes, so lane 0's registers keep the *previous wave's* values. If those satisfy a backward branch the idle warp
loops forever, `all_halted` never rises, and the wave sequencer never finishes. For T <= 4 the stale values are the reset zeros, so the
loop exits by luck; for T = 13-16 both warps are active; hence the exact thread-count pattern.

**Evidence.** Delta-debugging shrank a failing random kernel to a 4-instruction hang (after the register-initialising prologue) (`tools/repro_g1_idle_warp_hang.py`:
`CMP r10, r9 ; BR p, -11` with r10 = 81, r9 = 96, a later `CONST r9, 1`). A scratch copy of `warp.sv` with `br_taken` gated by
`|lane_mask` (an idle warp never branches) removes every hang for T = 1..20, and the full random-kernel regression with loops on
all thread counts then passes 400/400. Real RTL with loops on the affected thread counts: 171/200 (the rest hang).

**Impact.** Any kernel whose loop depends on a register value can hang the GPU depending on leftover register state of an idle warp
in the final wave. The shipped kernels (brighten/blur/copy, no data-dependent loops) are unaffected. **Suggested fix (not applied):**
gate branch resolution with `|lane_mask`, or move a warp with an empty lane mask straight to `W_HALT` on launch. No RTL was changed.

## Gaps

No divergence (the ISA/RTL do not support it), no data-dependent addressing beyond the masked-load pattern, 24-bit pixel
semantics only through full-word comparison, and no functional/code coverage numbers yet for the GPU.
