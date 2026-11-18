#!/usr/bin/env python3
"""Mutation testing of the GPU RTL against the Python golden model (rand_kernel.py).

Each mutant is a one-line RTL bug; it is built with a short watchdog, the random kernels are run, and it is KILLED if
any kernel differs from the model or the GPU stops terminating. The unmodified RTL must pass first.

  mutate_gpu.py [--kernels 60] [--jobs 12]
"""
import argparse, os, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import rand_kernel as rk  # noqa: E402

RTL = "simt_gpu warp regfile alu decoder dcr dispatcher scheduler mem_unit".split()
M = [  # (name, file, old, new)
 ("alu_sub_as_add",      "alu", "4'd1: result = a - b;", "4'd1: result = a + b;"),
 ("alu_mul_16bit",       "alu", "4'd2: result = a * b;", "4'd2: result = a * b[15:0];"),
 ("alu_div0_one",        "alu", "(b == 0) ? 32'b0 : a / b;", "(b == 0) ? 32'b1 : a / b;"),
 ("alu_div_signed",      "alu", "(b == 0) ? 32'b0 : a / b;  // DIV (unsigned)", "(b == 0) ? 32'b0 : 32'($signed(a) / $signed(b));  // DIV, real signed divide (self-determined cast)"),
 ("alu_sll_4bit",        "alu", "4'd7: result = a << b[4:0];", "4'd7: result = a << b[3:0];"),
 ("alu_srl_arith",       "alu", "4'd8: result = a >> b[4:0];", "4'd8: result = $signed(a) >>> b[4:0];"),
 ("alu_and_as_or",       "alu", "4'd4: result = a & b;", "4'd4: result = a | b;"),
 ("alu_xor_as_or",       "alu", "4'd6: result = a ^ b;", "4'd6: result = a | b;"),
 ("rf_tid_no_lane",      "regfile", "4'd0:    read_one = tid_base + 32'(lane);", "4'd0:    read_one = tid_base;"),
 ("rf_src_dst_swapped",  "regfile", "4'd14:   read_one = src_addr;", "4'd14:   read_one = dst_addr;"),
 ("rf_r14_writable",     "regfile", "write_addr != 4'd14 &&", ""),
 ("rf_r15_writable",     "regfile", "write_addr != 4'd15)", "1'b1)"),
 ("rf_r0_writable",      "regfile", "write_addr != 4'd0 &&", ""),
 ("disp_mask_le",        "dispatcher", "warp_lane_mask[w][l] = ((block_base + w * LANES + l) < thread_count);", "warp_lane_mask[w][l] = ((block_base + w * LANES + l) <= thread_count);"),
 ("disp_warp_base",      "dispatcher", "warp_tid_base[w] = block_base + w * LANES;", "warp_tid_base[w] = block_base;"),
 ("dcr_extra_wave",      "dcr", "if ((block_base + TB) < thread_count_q) begin", "if ((block_base + TB) <= thread_count_q) begin"),
 ("dcr_base_step",       "dcr", "block_base <= block_base + TB;", "block_base <= block_base + TB - 1;"),
 ("warp_cmp_swapped",    "warp", "cmp_res  = rd1[0] - rd2[0];", "cmp_res  = rd2[0] - rd1[0];"),
 ("warp_n_flag_zero",    "warp", "N <= cmp_res[31];", "N <= 1'b0;"),
 ("warp_z_flag_bit0",    "warp", "Z <= (cmp_res == 0);", "Z <= (cmp_res[0] == 1'b0);"),
 ("warp_p_includes_zero","warp", "P <= (cmp_res != 0) && !cmp_res[31];", "P <= !cmp_res[31];"),
 ("warp_br_no_signext",  "warp", "{{(PC_W-9){ir[8]}}, ir[8:0]}", "{{(PC_W-9){1'b0}}, ir[8:0]}"),
 ("warp_br_z_uses_n",    "warp", "(br_cond[1] & Z)", "(br_cond[1] & N)"),
 ("warp_br_off_plus1",   "warp", "pc <= pc + 1'b1 + {{(PC_W-9){ir[8]}}, ir[8:0]};", "pc <= pc + 2'd2 + {{(PC_W-9){ir[8]}}, ir[8:0]};"),
 ("warp_const_7bit",     "warp", "wdata[l] = {24'b0, imm8};", "wdata[l] = {25'b0, imm8[6:0]};"),
 ("mem_addr_sub",        "mem_unit", "mem_addr  = base_val[cur_lane] + idx_val[cur_lane];", "mem_addr  = base_val[cur_lane] - idx_val[cur_lane];"),
 ("mem_wdata_lane0",     "mem_unit", "mem_wdata = data_val[cur_lane];", "mem_wdata = data_val[0];"),
 ("mem_load_lane0",      "mem_unit", "if (!is_store) load_data[cur_lane] <= mem_rdata;", "if (!is_store) load_data[0] <= mem_rdata;"),
 ("mem_skip_lane0",      "mem_unit", "(l >= lane_ptr) && lane_mask[l]", "(l > lane_ptr) && lane_mask[l]"),
 ("mem_ptr_stuck",       "mem_unit", "lane_ptr <= cur_lane + 1;", "lane_ptr <= cur_lane;"),
]

def build(work, f, old, new):
    os.makedirs(f"{work}/rtl"); os.makedirs(f"{work}/tb")
    for x in RTL: shutil.copy(f"{ROOT}/rtl/{x}.sv", f"{work}/rtl/")
    tb = open(f"{ROOT}/tb/tb_gpu.sv").read().replace("repeat (50000000)", "repeat (300000)")
    open(f"{work}/tb/tb_gpu.sv", "w").write(tb)
    if f:
        p = f"{work}/rtl/{f}.sv"; s = open(p).read()
        if s.count(old) != 1: return None, f"pattern occurs {s.count(old)}x"
        open(p, "w").write(s.replace(old, new))
    subprocess.run(["verilator", "--binary", "--timing", "-Wno-fatal", "--top-module", "tb_gpu",
                    *[f"{work}/rtl/{x}.sv" for x in RTL], f"{work}/tb/tb_gpu.sv", "--Mdir", f"{work}/obj"], capture_output=True)
    sim = f"{work}/obj/Vtb_gpu"
    return (sim if os.path.exists(sim) else None), ""

def run_mutant(m, seeds):
    name, f, old, new = m
    work = tempfile.mkdtemp(prefix=f"gm_{name}_")
    try:
        sim, why = build(work, f, old, new)
        if not sim: return name, "BAD-PATTERN" if why else "BUILD-FAIL", why
        for s in seeds:
            seed, T, err = rk.run_one((s, sim, None))
            if err: return name, "KILLED", f"seed {seed} (T={T}): {err[:90]}"
        return name, "SURVIVED", ""
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--kernels", type=int, default=60); ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--only"); a = ap.parse_args()
    seeds = list(range(30000, 30000 + a.kernels)); muts = [m for m in M if not a.only or a.only in m[0]]
    base = run_mutant(("baseline", None, "", ""), seeds)
    print(f"baseline (unmodified RTL): {base[1]} {base[2]}", flush=True)
    if base[1] != "SURVIVED": sys.exit("baseline must pass first")
    t0 = time.time(); res = []
    with ThreadPoolExecutor(a.jobs) as ex:
        for r in ex.map(lambda m: run_mutant(m, seeds), muts):
            res.append(r); print(f"{r[0]:22s} {r[1]:9s} {r[2]}", flush=True)
    k = sum(r[1] == "KILLED" for r in res)
    print(f"== killed {k}/{len(res)} in {time.time()-t0:.0f}s; survivors: {[r[0] for r in res if r[1]=='SURVIVED'] or 'none'}")
