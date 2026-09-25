# RAPTOR-SoC GPU ISA v0 (Phase 1 subset)

16-bit instructions, 16 registers per lane. Two warps x four lanes in Phase 1.

## Registers

| Reg | Meaning |
|---|---|
| `r0` | `threadIdx` — read-only, per-lane global thread id |
| `r1`–`r13` | general purpose |
| `r14` | `SRC` base — preloaded by the dispatcher from DCR |
| `r15` | `DST` base — preloaded by the dispatcher from DCR |

Writes to `r0`, `r14`, `r15` are ignored.

## Encodings

All instructions are 16 bits. Common fields:

- `opcode = instr[15:12]`
- `rd     = instr[11:8]`
- `rs1    = instr[7:4]`
- `rs2    = instr[3:0]`
- `imm8   = instr[7:0]` (CONST only)

| Opcode | Mnemonic | Format | Operation |
|---|---|---|---|
| `0x0` | `ADD rd, rs1, rs2` | R | `rd = rs1 + rs2` |
| `0x1` | `CONST rd, imm8` | I | `rd = zero_extend(imm8)` |
| `0x2` | `SUB rd, rs1, rs2` | R | `rd = rs1 - rs2` |
| `0x3` | `LDR rd, rs_base, rs_idx` | R | `rd = mem[rs_base + rs_idx]` |
| `0x4` | `STR rs_data, rs_base, rs_idx` | R | `mem[rs_base + rs_idx] = rs_data` |
| `0x5` | `RET` | — | halt this warp |

Any other opcode is illegal and must behave as a NOP.

### Memory operand field aliases

- `LDR rd, rs_base, rs_idx` uses `rd = [11:8]`, `rs_base = [7:4]`, `rs_idx = [3:0]`.
- `STR rs_data, rs_base, rs_idx` uses `rs_data = [11:8]`, `rs_base = [7:4]`,
  `rs_idx = [3:0]`.

## Semantics

- Each **lane** executes the same instruction stream on its own register file
  and its own `threadIdx`. Lanes with `threadIdx >= thread_count` are inactive
  and must not write registers or memory.
- `LDR`/`STR` are per-lane. Phase 1 issues them **one lane per bus cycle**
  (no coalescing) — this is the baseline that Phase 2 optimizes.
- `RET` halts the warp; inactive lanes do not participate in `done`.

## Example kernel: brighten

```asm
.threads 256
.src 0x2000
.dst 0x6000
.text
CONST r1, 0x20      ; delta = 32
LDR   r2, r14, r0   ; r2 = src[tid]
ADD   r3, r2, r1    ; add delta
STR   r3, r15, r0   ; dst[tid] = r3
RET
```

Note: because packed RGB is per-channel, `+0x202020` is the "true" brighten;
Phase 1 exercises the data path with a scalar add, and Phase 2 introduces
per-channel extract/repack.
