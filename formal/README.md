# Formal verification (SymbiYosys)

`formal/async_fifo`: the Gray-pointer dual-clock FIFO (`soc/rtl/async_fifo.sv`) used for every clock-domain crossing in
the SoC (commands, completions, GPU memory traffic). Properties are attached with `bind`; the RTL is untouched.
`wclk` and `rclk` are free, independent inputs (SymbiYosys `multiclock on`), so every interleaving of write/read clock
edges is explored. Tools: OSS CAD Suite 2026-11-18, yosys-slang front end.

```
export PATH=$HOME/builds/oss-cad-suite/bin:$PATH
cd formal/async_fifo
sby -f async_fifo.sby bmc      # bounded (depth 28), no helper invariants
sby -f async_fifo.sby prove    # unbounded: IC3/PDR with helper invariants (-D STRENGTHEN)
sby -f async_fifo.sby cover
python3 mutants.py             # formal mutation check (10 RTL bugs)
```

Environment contract (from the RTL header): resets are asserted together at the start and never re-asserted; each
domain may release its reset at an arbitrary later time. A producer holds its request until accepted.

## Properties

| ID | Property |
|---|---|
| S1 | Occupancy (`wb - rb`, observing both domains' true pointers) never exceeds DEPTH |
| S2 | A write is never accepted into a full FIFO; a read never from an empty one; `wready`/`rvalid` only when there is room / data |
| S3 | Each Gray pointer changes by at most one bit per source-clock edge (the property that makes the synchronizers safe) |
| S4 | Data integrity and ordering: a ghost FIFO driven only by the handshake events (written on `wclk` when a write is accepted, popped on `rclk` when a read is accepted); whenever `rvalid`, `rdata` equals the ghost's oldest word |

For the unbounded proof the property module also carries helper invariants: the ghost counters equal the DUT's binary
pointers; the Gray registers equal `gray(binary)`; ghost binary shadows of both synchronizer chains tie each stage to an
earlier pointer value with the ordering `rb <= gwb2 <= gwb1 <= wb`; and every occupied storage slot equals the ghost's word.

## Results (WIDTH = 4)

| Task | DEPTH | Result |
|---|---|---|
| `prove` (abc pdr, unbounded) | 2 / 4 / 8 | **PASS** (2 s / 11 s / 67 s): S1-S4 hold for all clock interleavings and all time |
| `bmc` depth 28 | 4 | PASS (about 7 clock cycles per domain: the FIFO fills, drains and wraps) |
| `cover` | 4 | 4/4 reached (write accepted, read accepted, FIFO full, read while more words are queued) |
| formal mutation (`mutants.py`, BMC depth 22) | 4 | **10 / 10 killed** |

Mutants: full threshold wrong, never full, never empty, binary write pointer crossing instead of Gray, binary read
pointer crossing, write slot off by one, read indexed by the Gray pointer, read accepted when empty, synchronizer fed
from the binary pointer, `wready` ignoring full. Several are CDC-structure bugs a simulation with a single zero-skew
clock ratio would miss.

## Modelling notes (things that went wrong first)

* `(* anyconst *)` is not honoured by the yosys-slang front end (the "constant" became a free per-step signal and
  produced a bogus counterexample); data integrity therefore uses a ghost FIFO, not a tracked slot.
* Edge-gated immediate assertions mixing signals from different sampling instants are ambiguous under multi-clock;
  the properties are written as state invariants evaluated every step.
* k-induction alone did not converge on the data-integrity invariant; PDR with the helper invariants above does.

## Not covered

Metastability and physical CDC are not formal-modelled (this proves the logical protocol, not analog behaviour). The
dual-clock FIFOs wrapped by `cdc_request_channel.sv`/`gpu_memory_cdc.sv` are not verified separately. WIDTH/DEPTH other
than the three configurations above are not proven.
