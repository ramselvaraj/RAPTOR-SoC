#!/usr/bin/env python3
"""Reproducer for finding G1: an idle (fully masked) warp runs control flow on stale registers and can hang the GPU.

Kernel: prologue defines every register, then `CMP r10, r9 ; BR p, -11` (a backward branch that is never taken by any
active thread, because r10 = 81 < r9 = 96), a later `CONST r9, 1`, and RET. For T = 9..12 and 17..20 the last wave leaves
warp 1 with no active lane; its lane-0 registers still hold the previous wave's r9 = 1 (masked lanes never run the
prologue writes), so its CMP computes 81 - 1 > 0, `BR p` is taken, and it loops forever: `done` is never asserted.

  repro_g1_idle_warp_hang.py [--sim build/obj/Vtb_gpu]     (the stock testbench watchdog is 50M cycles, so a hang takes a while;
                                                            build a copy with a shorter watchdog for a quick run)
"""
import argparse, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import rand_kernel as rk  # noqa: E402

NOP = rk.enc3(0, 0, 0, 0)
def program():
    p = [rk.enc_const(i, v) for i, v in zip(range(1, 11), [72, 129, 177, 132, 248, 3, 76, 217, 96, 81])]
    p += [rk.enc_const(11, 8), rk.enc3(0xB, 11, 11, 11), rk.enc3(0x0, 11, 11, 0), rk.enc_const(12, 122), rk.enc_const(13, 63)]
    p += [NOP] * 24 + [rk.enc_cmp(10, 9), rk.enc_br(0b001, -11)] + [NOP] * 23 + [rk.enc_const(9, 1), rk.RET]
    return p

def hangs(sim, T):
    with tempfile.TemporaryDirectory() as td:
        rk.hexwords(f"{td}/p.hex", program()); rk.hexwords(f"{td}/f.hex", [0] * 16, 8)
        subprocess.run([sim, f"+frame={td}/f.hex", f"+out={td}/o.hex", f"+prog={td}/p.hex", f"+count={T}",
                        f"+src={rk.SRC}", f"+dst={rk.DST}"], capture_output=True)
        return not os.path.exists(f"{td}/o.hex")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--sim", default=os.path.join(os.path.dirname(HERE), "build/obj/Vtb_gpu"))
    ap.add_argument("--threads", type=int, nargs="*", default=list(range(1, 21))); a = ap.parse_args()
    print({T: ("HANG" if hangs(a.sim, T) else "ok") for T in a.threads})
