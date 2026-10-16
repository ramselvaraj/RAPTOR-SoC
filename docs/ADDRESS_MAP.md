# RAPTOR-SoC Address Map (Phase 4)

Phase 4 keeps the GPU's original word-addressed pixel interface and adds the
byte-addressed RISC-V/AXI view. For shared memory, the conversion is
`GPU word address = CPU byte address >> 2`.

| Region | CPU/AXI byte base | GPU word base | Size | Notes |
|---|---:|---:|---:|---|
| CPU instruction TCM | `0x0000_0000` | - | 4 KiB | Private CPU port |
| System data RAM / stack | `0x0000_4000` | `0x1000` | 4 KiB | Shared RAM |
| Framebuffer bank A (src) | `0x0000_8000` | `0x2000` | 16 KiB | 64x64 packed RGB |
| Framebuffer bank B (dst) | `0x0001_8000` | `0x6000` | 16 KiB | Double buffer |
| GPU program memory | `0x0002_8000` | `0xA000` | 4 KiB allocated | Private GPU port, 1024 x 16-bit storage |
| GPU MMIO | `0x4000_0000` | - | 0x20 bytes | AXI4-Lite |

The AXI shared-RAM window is `0x0000_4000` through `0x0001_BFFF`. The physical
model remains 32768 words (128 KiB), indexed by AXI `addr[16:2]` or GPU
`mem_addr[14:0]`; this preserves the Phase 1-3 sparse GPU addresses.

## GPU MMIO registers

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x00` | `CTRL` | W | bit0 = start (write 1 to launch) |
| `0x04` | `STATUS` | R | bit0 = busy, bit1 = done |
| `0x08` | `THREADS` | W | thread count |
| `0x0C` | `SRC` | W | source framebuffer word address |
| `0x10` | `DST` | W | destination framebuffer word address |
| `0x14` | `PROG_BASE` | W | GPU program-memory word offset |

`STATUS.done` is sticky until the next accepted `CTRL.start` write so polling
software cannot miss the GPU's one-cycle completion pulse.

## Framebuffer format

Packed RGB in the low 24 bits: `0x00RRGGBB`. The top byte is ignored on read.
