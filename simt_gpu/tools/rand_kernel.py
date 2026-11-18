#!/usr/bin/env python3
"""Random-kernel differential test: Python golden model (isa_sim.py) vs the Verilated GPU.

Generates a random kernel (ALU/MUL/DIV/shift/logic ops, masked loads from a random frame, CMP + forward branches whose
conditions are thread-uniform so no divergence is needed, and an epilogue that stores every register of every thread
to a unique address), runs it on both and compares the ENTIRE data memory.

  rand_kernel.py --count 200 --seed 1 [--threads 1..20]
"""
import argparse, os, random, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import isa_sim  # noqa: E402

SRC, DST, WORDS = 0x2000, 0x6000, 32768
FEATURES = set(os.environ.get("KERNEL_FEATURES", "loops,scratch,branches").split(","))
OPS = {"ADD": 0x0, "SUB": 0x2, "MUL": 0x6, "DIV": 0x7, "AND": 0x8, "OR": 0x9, "XOR": 0xA, "SLL": 0xB, "SRL": 0xC}
TID, SRCR, DSTR, TMP, MASKR, SCR = 0, 14, 15, 12, 13, 11                     # special registers / reserved temporaries

def enc3(op, rd, a, b): return (op << 12) | (rd << 8) | (a << 4) | b
def enc_const(rd, imm): return (0x1 << 12) | (rd << 8) | (imm & 0xFF)
def enc_cmp(a, b):      return (0xD << 12) | (a << 4) | b
def enc_br(cond, off):  return (0xE << 12) | (cond << 9) | (off & 0x1FF)
RET = 0x5 << 12

class Kernel:
    def __init__(self, seed, threads, loops=True):
        self.loops = loops; self.r = random.Random(seed); self.T = threads; self.p = []; self.uni = {i: i != TID for i in range(16)}
    def e(self, w): self.p.append(w)
    def pick(self, lo=1, hi=10):
        if lo == 1 and hi == 10 and self.r.random() < 0.05: return self.r.choice([0, 14, 15])     # must be ignored by the regfile
        return self.r.randint(lo, hi)
    def src_reg(self): return self.r.choice([0, 14, 15] + list(range(1, 11)))
    def gen_op(self, w):
        r = self.r; k = r.random()
        if k < 0.62:
            name = r.choice(list(OPS)); rd, a, b = self.pick(), self.src_reg(), self.src_reg()
            self.e(enc3(OPS[name], rd, a, b))
            if rd not in (0, 14, 15): w[rd] = self.uni[a] and self.uni[b]; self.uni[rd] = w[rd]
        elif k < 0.78:
            rd = self.pick(); self.e(enc_const(rd, r.choice([0, 1, 2, 255, 128, 127, 31, 32, r.randrange(256)])))
            if rd not in (0, 14, 15): self.uni[rd] = True; w[rd] = True
        elif k < 0.84 and "scratch" in FEATURES:                     # per-thread scratch: dst + 0x800 + tid (unique address)
            if r.random() < 0.55:
                x = self.src_reg(); self.e(enc3(0x4, x, DSTR, SCR)); self.scr_uni = self.uni[x]
            else:
                rd = self.pick(); self.e(enc3(0x3, rd, DSTR, SCR))
                if rd not in (0, 14, 15): self.uni[rd] = False; w[rd] = False
        elif k < 0.95:                                               # masked load: address = src + (x & 63)
            rd, x = self.pick(), self.src_reg()
            self.e(enc3(OPS["AND"], TMP, x, MASKR)); self.e(enc3(0x3, rd, SRCR, TMP))
            self.uni[TMP] = self.uni[x]; w[TMP] = self.uni[x]
            if rd not in (0, 14, 15): self.uni[rd] = self.uni[x]; w[rd] = self.uni[x]
        else:
            self.e(enc3(OPS["ADD"], self.pick(), self.src_reg(), self.src_reg()))   # (rd result unused by uniformity: recompute)
            rd = (self.p[-1] >> 8) & 0xF; a = (self.p[-1] >> 4) & 0xF; b = self.p[-1] & 0xF
            if rd not in (0, 14, 15): self.uni[rd] = self.uni[a] and self.uni[b]; w[rd] = self.uni[rd]
    def build(self):
        r = self.r
        for i in range(1, 11): self.e(enc_const(i, r.randrange(256)))        # every register is defined before use
        self.e(enc_const(SCR, 8)); self.e(enc3(OPS["SLL"], SCR, SCR, SCR)); self.e(enc3(OPS["ADD"], SCR, SCR, TID))   # SCR = 0x800 + tid
        self.uni[SCR] = False
        # large values (bit 31 set) so signed/unsigned, overflow and shift-in-high-bit behaviour is exercised
        self.e(enc_const(TMP, r.choice([24, 25, 28, 31])))
        for big in r.sample(range(1, 11), 2):
            self.e(enc_const(big, r.choice([128, 255, 129, r.randrange(128, 256)]))); self.e(enc3(OPS["SLL"], big, big, TMP))
        self.e(enc_const(TMP, r.randrange(256)))                                 # the temporary too: the register file is only
        self.e(enc_const(MASKR, 63)); self.uni[MASKR] = True                      # reset by the global reset, not per thread batch
        n = r.randint(25, 90); i = 0
        while i < n:
            uni_regs = [x for x in range(16) if self.uni[x]]
            if "branches" in FEATURES and r.random() < 0.12 and len(uni_regs) >= 2:   # uniform CMP + forward branch over a block
                a, b = r.choice(uni_regs), r.choice(uni_regs)
                self.e(enc_cmp(a, b)); blk = []
                before = dict(self.uni); w = {}
                start = len(self.p); self.e(0)                                  # placeholder for BR
                for _ in range(r.randint(1, 5)): self.gen_op(w)
                body_len = len(self.p) - start - 1
                self.p[start] = enc_br(r.randrange(1, 8), body_len)
                for reg in w:                                                  # a register written on one path only: uniform iff both
                    self.uni[reg] = before[reg] and self.uni[reg]
                i += body_len + 2
            elif "loops" in FEATURES and self.loops and r.random() < 0.07:                      # uniform counted loop (backward branch)
                rc, ro, rz = r.sample(range(1, 11), 3); n_it = r.randint(1, 5)
                self.e(enc_const(rc, n_it)); self.e(enc_const(ro, 1)); self.e(enc_const(rz, 0))
                for q in (rc, ro, rz): self.uni[q] = True
                protected = {rc, ro, rz}
                start = len(self.p); w = {}
                for _ in range(r.randint(1, 5)):
                    save = (self.pick, )
                    self.gen_op(w)
                    while (self.p[-1] >> 8) & 0xF in protected and (self.p[-1] >> 12) not in (0x4,):   # undo a write to a loop-control reg
                        self.p.pop(); self.gen_op(w)
                body = len(self.p) - start
                self.e(enc3(OPS["SUB"], rc, rc, ro)); self.e(enc_cmp(rc, rz)); self.e(enc_br(0b001, -(body + 3)))
                for q in w: self.uni[q] = self.uni[q] if q in w else self.uni[q]
                i += body + 6
            else:
                self.gen_op({}); i += 1
        T = self.T
        for j, reg in enumerate(range(1, 11)):                                  # epilogue: dst + tid + j*T <- r[reg]
            self.e(enc_const(TMP, j * T)); self.e(enc3(0x0, TMP, TID, TMP)); self.e(enc3(0x4, reg, DSTR, TMP))
        self.e(RET)
        return self.p

def hexwords(path, words, w=4):
    with open(path, "w") as f: f.write("".join(f"{x & ((1 << (4*w)) - 1):0{w}x}\n" for x in words))

IDLE_WARP_LATER_WAVE = {9, 10, 11, 12, 17, 18, 19, 20}      # a later wave leaves warp 1 with no active lane (finding G1)
ALLOW_G1 = os.environ.get("ALLOW_G1") == "1"                  # set to include loop kernels on those thread counts

def run_one(args):
    seed, sim, keep = args
    rr = random.Random(seed * 7919 + 1); T = rr.randint(1, 20)
    prog = Kernel(seed, T, loops=(ALLOW_G1 or T not in IDLE_WARP_LATER_WAVE)).build()
    frame = [rr.getrandbits(32) for _ in range(256)]
    with tempfile.TemporaryDirectory() as td:
        hexwords(f"{td}/prog.hex", prog); hexwords(f"{td}/frame.hex", frame, 8)
        r = subprocess.run([sim, f"+frame={td}/frame.hex", f"+out={td}/out.hex", f"+prog={td}/prog.hex", f"+count={T}",
                            f"+src={SRC}", f"+dst={DST}"], capture_output=True, text=True, timeout=300)
        if not os.path.exists(f"{td}/out.hex"): return seed, T, f"RTL did not finish: {r.stdout[-120:]}"
        actual = isa_sim.read_hex_words(f"{td}/out.hex")
        data = [0] * WORDS; data[SRC:SRC + len(frame)] = frame
        try: isa_sim.run(prog, data, T, SRC, DST)
        except Exception as e: return seed, T, f"model error: {e}"
        bad = [i for i in range(WORDS) if (actual[i] & 0xFFFFFFFF) != (data[i] & 0xFFFFFFFF)]
        if bad:
            i = bad[0]; j = (i - DST - 0) 
            if keep: os.makedirs(keep, exist_ok=True); hexwords(f"{keep}/k{seed}.hex", prog)
            return seed, T, f"{len(bad)} words differ; first @{i:#x} (dst+{i-DST}) rtl={actual[i]:08x} model={data[i]:08x}"
    return seed, T, None

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--count", type=int, default=100); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--sim", default=f"{ROOT}/build/obj/Vtb_gpu"); ap.add_argument("--keep"); ap.add_argument("-j", type=int, default=16)
    a = ap.parse_args()
    with ThreadPoolExecutor(a.j) as ex: res = list(ex.map(run_one, [(a.seed + i, a.sim, a.keep) for i in range(a.count)]))
    bad = [r for r in res if r[2]]
    for s, T, why in bad[:15]: print(f"seed {s} (T={T}): {why}")
    print(f"== {len(res)-len(bad)}/{len(res)} random kernels identical to the golden model")
    sys.exit(1 if bad else 0)
