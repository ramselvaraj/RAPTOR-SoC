#!/usr/bin/env python3
"""Formal mutation check for async_fifo: inject an RTL bug, run `bmc` (reduced depth), report whether a property fails."""
import subprocess, shutil, os, re, sys
from concurrent.futures import ThreadPoolExecutor
DEPTH = int(os.environ.get("DEPTH", "22"))
MUT = {
 "full_wrong_threshold": ("assign full_compare = rg2 ^ ((A+1)'(3) << (A-1));", "assign full_compare = rg2 ^ ((A+1)'(1) << (A-1));"),
 "never_empty":          ("assign empty = rg == wg2;", "assign empty = 1'b0;"),
 "never_full":           ("assign full = wg == full_compare;", "assign full = 1'b0;"),
 "binary_write_ptr_crosses": ("wg <= ((wb + 1'b1) >> 1) ^ (wb + 1'b1);", "wg <= (wb + 1'b1);"),
 "binary_read_ptr_crosses":  ("rg <= ((rb + 1'b1) >> 1) ^ (rb + 1'b1);", "rg <= (rb + 1'b1);"),
 "write_index_off":      ("storage[wb[A-1:0]] <= wdata;", "storage[wb[A-1:0] + 1'b1] <= wdata;"),
 "read_index_gray":      ("assign rdata = storage[rb[A-1:0]];", "assign rdata = storage[rg[A-1:0]];"),
 "read_ignores_valid":   ("if (rvalid && rready) begin\n                rb <= rb + 1'b1;", "if (rready) begin\n                rb <= rb + 1'b1;"),
 "sync_from_binary":     ("rg1 <= rg; rg2 <= rg1;", "rg1 <= rb; rg2 <= rg1;"),
 "wready_ignores_full":  ("assign wready = !wrst && !full;", "assign wready = !wrst;"),
}
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(here + "/../..")
def run(item):
    n, (old, new) = item
    d = f"/tmp/ff_{n}"; shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    shutil.copy(root + "/soc/rtl/async_fifo.sv", d); shutil.copy(here + "/async_fifo_props.sv", d)
    cfg = open(here + "/async_fifo.sby").read().replace("../../soc/rtl/async_fifo.sv", "async_fifo.sv").replace("depth 40", f"depth {DEPTH}")
    open(d + "/async_fifo.sby", "w").write(cfg)
    p = d + "/async_fifo.sv"; s = open(p).read()
    if s.count(old) != 1: return n, "BAD-PATTERN", ""
    open(p, "w").write(s.replace(old, new))
    out = subprocess.run(["sby", "-f", "async_fifo.sby", "bmc"], cwd=d, capture_output=True, text=True).stdout
    m = re.search(r"Assert failed in async_fifo: \S+:(\d+)", out)
    return n, "KILLED" if "DONE (FAIL" in out else "SURVIVED" if "DONE (PASS" in out else "ERROR", f"line {m.group(1)}" if m else ""
with ThreadPoolExecutor(10) as ex:
    res = list(ex.map(run, MUT.items()))
for n, st, extra in res: print(f"{n:28s} {st:9s} {extra}")
print(f"== killed {sum(r[1]=='KILLED' for r in res)}/{len(res)} at BMC depth {DEPTH}")
