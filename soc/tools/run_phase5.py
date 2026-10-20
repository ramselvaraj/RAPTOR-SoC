#!/usr/bin/env python3
"""Deterministic Phase 5 clock/stall/reset matrix; all expected pixels are independent."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    binary = ROOT / "soc/build/phase5/obj/Vtb_soc_phase5"
    configurations = [("same", 5000, 5000), ("cpu_fast", 2000, 5000),
                      ("gpu_fast", 5000, 2000), ("unrelated", 3500, 5500)]
    cases = []
    for name, cpu, gpu in configurations:
        for size in ([16] if args.quick else [16, 32, 64]):
            cases.append((f"{name}_{size}", size, cpu, gpu, 1, False, False))
    for seed in range(1, (2 if args.quick else 11)):
        cases.append((f"pressure16_s{seed}", 16, 3500, 5500, seed, True, False))
    if not args.quick:
        for seed in range(1, 4):
            cases.append((f"pressure64_s{seed}", 64, 3500, 5500, seed, True, False))
    cases.append(("reset_epoch", 16, 2000, 5500, 47, True, True))
    for size in ([16] if args.quick else [16, 32, 64]):
        cases.append((f"uncached_{size}", size, 5000, 5000, 1, False, False))
    cases.append(("shallow16", 16, 3500, 5500, 53, True, False))
    if not args.quick:
        cases.append(("shallow64", 64, 3500, 5500, 97, True, False))
    completed = []
    for name, size, cpu, gpu, seed, stalls, reset in cases:
        selected_binary = binary
        if name.startswith("uncached_"):
            selected_binary = ROOT / "soc/build/phase5/nocache/Vtb_soc_phase5"
        if name.startswith("shallow"):
            selected_binary = ROOT / "soc/build/phase5/shallow/Vtb_soc_phase5"
        work = ROOT / "soc/build/phase5/run" / name
        command = [sys.executable, str(ROOT / "soc/tools/run_soc.py"), "--phase5",
                   "--binary", str(selected_binary), "--width", str(size), "--height", str(size),
                   "--cpu-half-ps", str(cpu), "--gpu-half-ps", str(gpu), "--seed", str(seed),
                   "--workdir", str(work)]
        if stalls:
            command.append("--stalls")
        if reset:
            command.append("--reset-test")
        print(f"=== Phase 5: {name} ===", flush=True)
        subprocess.run(command, check=True, cwd=ROOT)
        completed.append(dict(case=name, size=size, cpu_period_ps=cpu*2, gpu_period_ps=gpu*2,
                              seed=seed, stalls=stalls, reset=reset))
    output = ROOT / "soc/build/phase5/results.json"
    output.write_text(json.dumps(completed, indent=2) + "\n")
    print(f"Phase 5 SoC matrix: {len(completed)} cases passed. {output}")


if __name__ == "__main__":
    main()
