# RAPTOR-SoC Address Map (v0 — Phase 1 draft)

Frozen at the interface level in Phase 1, finalized in Phase 4 when the CPU is
connected. Phase 1 only uses the **framebuffer** region (the testbench memory
model implements the whole map).

All addresses below are **word indices** in Phase 1 (see BUS_PROTOCOL.md rule 4).
They are written as byte-style hex for readability; treat the value as the
array index.

| Region | Base | Size (words) | Notes |
|---|---|---|---|
| CPU instruction memory | `0x0000_0000` | 1024 | Phase 4 |
| System data RAM / stack | `0x0000_1000` | 1024 | Phase 4 |
| Framebuffer bank A (src) | `0x0000_2000` | 4096 | 64x64 packed RGB |
| Framebuffer bank B (dst) | `0x0000_6000` | 4096 | double buffer |
| GPU program memory | `0x0000_A000` | 1024 | 16-bit GPU instructions |
| GPU MMIO | `0x4000_0000` | 8 | `CTRL/STATUS/THREADS/SRC/DST` |

**Total data memory modelled Phase 1:** 32768 words (128 KiB), covering bank A
and bank B with headroom.

## GPU MMIO registers (Phase 4; Phase 1 drives these as direct ports)

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x00` | `CTRL` | W | bit0 = start (write 1 to launch) |
| `0x04` | `STATUS` | R | bit0 = busy, bit1 = done |
| `0x08` | `THREADS` | W | thread count |
| `0x0C` | `SRC` | W | source framebuffer word address |
| `0x10` | `DST` | W | destination framebuffer word address |

## Framebuffer format

Packed RGB in the low 24 bits: `0x00RRGGBB`. The top byte is ignored on read.
