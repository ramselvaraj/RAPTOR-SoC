# Phase 1 Progress — Person A

Simple running log. One file at a time, in the order we build them.

Legend: `[x]` done · `[~]` in progress · `[ ]` not yet

---

## [x] 1. `rtl/decoder.sv` — "is this a real instruction?"

One line. Opcodes 0–5 are legal, everything else is illegal.

```systemverilog
legal = (opcode <= 4'h5);
```

Test: `make unit TEST=tb_decoder` → `TB_DECODER PASS`

---

## [x] 2. `rtl/alu.sv` — "do the math"

One operation per lane. Phase 1 only needs add and subtract.

```systemverilog
case (op)
    2'd0:    result = a + b;   // ADD
    2'd1:    result = a - b;   // SUB
    default: result = 32'b0;   // illegal op
endcase
```

Test: `make unit TEST=tb_alu` → `TB_ALU PASS`

---

## [x] 3. `rtl/dcr.sv` — "start button + status light"

The GPU's launch register.

```
[IDLE] ──start──► [BUSY] ──all warps done──► [DONE] ──► back to [IDLE]
```

- `start` copies thread_count/src/dst into the `_q` registers and raises `busy`.
- `all_halted` clears `busy` and blinks `done` for **one cycle**.
- Trick: `done <= 1'b0;` every cycle = pulse, not a stuck-on light.

```systemverilog
end else begin
    done <= 1'b0;
    if (start) begin
        busy <= 1'b1;
        thread_count_q <= thread_count;
        src_addr_q <= src_addr;
        dst_addr_q <= dst_addr;
    end else if (busy && all_halted) begin
        busy <= 1'b0;
        done <= 1'b1;
    end
end
```

Test: `make unit TEST=tb_dcr` → `TB_DCR PASS`

---

## [x] 4. `rtl/dispatcher.sv` — "who is alive?"

Turns the thread count into: which lanes are on, and where each warp starts.
No clock in its ports — pure combinational wiring.

```
thread_count = 6
  warp 0: lanes 1111   (threads 0 1 2 3)
  warp 1: lanes 0011   (threads 4 5)
```

Rule: warp `w` starts at tid `w*LANES`; a lane is ON if its global tid is
less than `thread_count`.

Why a mask at all? Thread counts aren't always a multiple of 8, so some lanes
have no thread behind them.

```
global tid:   0  1  2  3 | 4  5  6  7
mask:         1  1  1  1 | 1  1  0  0
                                   └─┴─ no thread here!
```

Those extra lanes would load/store outside the image → garbage writes. The mask
tells `mem_unit` and `warp` to skip them, and lets the warp still finish cleanly.

```systemverilog
warp_start     = '0;
warp_tid_base  = '0;
warp_lane_mask = '0;
for (int w = 0; w < WARPS; w++) begin
    warp_start[w]    = start;
    warp_tid_base[w] = w * LANES;
    for (int l = 0; l < LANES; l++)
        warp_lane_mask[w][l] = ((w*LANES + l) < thread_count);
end
```

Test: `make unit TEST=tb_dispatcher` → `TB_DISPATCHER PASS`

---

## [x] 5. `rtl/scheduler.sv` — "who gets the bus this cycle?"

Round-robin: fair turn-taking.

```
ready[0] ─┐
          ├─► [SCHEDULER] ─► grant (one-hot: exactly one warp, or none)
ready[1] ─┘
```

- `always_comb` computes `grant` from `ready` + `last`.
- `always_ff` remembers `last` (who won last), advance to the next warp.

```systemverilog
int last;
int winner;

always_comb begin
    logic found;
    grant  = '0;
    found  = 0;
    winner = 0;
    for (int i = 0; i < WARPS; i++) begin
        int w;
        w = (last + i) % WARPS;      // scan starting just after `last`
        if (!found && ready[w]) begin
            grant[w] = 1'b1;         // one-hot win
            found    = 1;
            winner   = w;
        end
    end
end

always_ff @(posedge clk or posedge reset) begin
    if (reset)          last <= 0;
    else if (|grant)    last <= (winner + 1) % WARPS;
end
```

The key line is `w = (last + i) % WARPS` — it rotates the start point so no
warp can hog the bus.

Test: `make unit TEST=tb_scheduler` → `TB_SCHEDULER PASS`

---

## [~] 6. `rtl/mem_unit.sv` — "one lane at a time"

The bus moves one word per cycle, so walk lanes 0→1→2→3, skipping masked-off ones.

```
mask 1101 →  lane 0 xfer, lane 1 xfer, lane 2 skip, lane 3 xfer → done
```

Needs new state: `busy`, a lane pointer, and `load_data` storage.
Split: `always_comb` drives the bus, `always_ff` holds state.

```systemverilog
logic busy;
int   lane_ptr;
logic cur_valid;
int   cur_lane;

always_comb begin
    cur_valid = 1'b0;
    cur_lane  = 0;
    for (int l = 0; l < LANES; l++)
        if (!cur_valid && (l >= lane_ptr) && lane_mask[l]) begin
            cur_valid = 1'b1;
            cur_lane  = l;
        end

    mem_req = 1'b0; mem_we = 1'b0; mem_addr = 32'b0; mem_wdata = 32'b0;
    if (busy && cur_valid) begin
        mem_req   = 1'b1;
        mem_we    = is_store;
        mem_addr  = base_val[cur_lane] + idx_val[cur_lane];
        mem_wdata = data_val[cur_lane];
    end
end

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        busy <= 1'b0; lane_ptr <= 0; done <= 1'b0;
        for (int l = 0; l < LANES; l++) load_data[l] <= 32'b0;
    end else begin
        done <= 1'b0;
        if (start) begin
            busy <= 1'b1; lane_ptr <= 0;
            for (int l = 0; l < LANES; l++) load_data[l] <= 32'b0;
        end else if (busy) begin
            if (cur_valid && mem_ready) begin
                if (!is_store) load_data[cur_lane] <= mem_rdata;
                lane_ptr <= cur_lane + 1;
            end else if (!cur_valid) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end
end
```

Status: implemented, `make build` clean. Functional check pending Person B's
`warp.sv` + `make run`.

Test: none yet — proved by `make run`.

---

## [x] 6b. `rtl/regfile.sv` — "16 registers × 4 lanes"  *(Person B's file)*

Storage + special read-only registers `r0` (tid), `r14` (SRC), `r15` (DST).

```systemverilog
logic [31:0] regs [0:15][0:LANES-1];

function automatic logic [31:0] read_one(input logic [3:0] addr, input int lane);
    case (addr)
        4'd0:    read_one = tid_base + 32'(lane);   // threadIdx
        4'd14:   read_one = src_addr;
        4'd15:   read_one = dst_addr;
        default: read_one = regs[addr][lane];
    endcase
endfunction

always_ff @(posedge clk or posedge reset) begin
    if (reset)
        for (int r = 0; r < 16; r++)
            for (int l = 0; l < LANES; l++) regs[r][l] <= 32'b0;
    else if (write_enable && write_addr != 4'd0 &&
             write_addr != 4'd14 && write_addr != 4'd15)
        for (int l = 0; l < LANES; l++)
            if (write_mask[l]) regs[write_addr][l] <= write_data[l];
end

always_comb
    for (int l = 0; l < LANES; l++) begin
        read_data1[l] = read_one(read_addr1, l);
        read_data2[l] = read_one(read_addr2, l);
        read_data3[l] = read_one(read_addr3, l);
    end
```

Test: `make unit TEST=tb_regfile` → `TB_REGFILE PASS`

---

## [x] 6c. `rtl/warp.sv` — "one warp's control FSM"  *(Person B's file)*

`W_IDLE → W_FETCH → W_EXEC → W_MEM → W_HALT`. Executes only on `grant`.

- `W_FETCH`: grant → latch `ir <= imem_rdata`, go `W_EXEC`.
- `W_EXEC`: grant → `CONST`/`ADD`/`SUB` write `rd`, `pc++`; `LDR`/`STR` start
  `mem_unit`; `RET` → `W_HALT`.
- `W_MEM`: wait `mem_done` → `LDR` writes `rd`, `pc++`.
- Instantiates `decoder`, `regfile`, one `alu` per lane, and `mem_unit`.

The key line (bug fix / deadlock trap):

```systemverilog
mem_unit #(.LANES(LANES)) u_mem(
    ...
    .mem_ready(mem_ready && grant),   // only advance when we own the bus
    ...
);
```

`ready` is asserted in `W_FETCH`, `W_EXEC`, **and `W_MEM`**, so a
memory-waiting warp can still be granted.

Test: `make run` (see integration below).

---

## [ ] 7. `rtl/simt_gpu.sv` — "wire it all together"

Provided file. Verify the grant-based bus mux.

Agreement needed with Person B: a warp waiting on memory (`W_MEM`) must
keep `ready` high, or it deadlocks.

---

## [~] 8. Integration — `make run`

Copies/brightens the image and compares to the golden model.

**Result (2026-10-01):** with an 8-thread kernel (4×2 image) the full datapath
passes — `PASS: 8 threads, 0 mismatches` for both copy and brighten.

**Known issue confirmed.** The stock `brighten.asm` uses `.threads 256`, but the
hardware is `WARPS*LANES = 8` threads, so only `dst[0..7]` can ever be written:

```
FAIL: 248/256 pixel mismatches (first at thread 8: got 000000 expected b00097)
```

Threads 0–7 are correct; 8–255 are never touched. This is a spec/harness
mismatch, **not** an RTL bug — confirm with staff whether the acceptance run
should use `.threads 8`, or whether `WARPS`/`LANES` must grow.
