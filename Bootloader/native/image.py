#!/usr/bin/env python3
"""Strict disk image layout for NoqeriOS original BIOS ELF loader."""
from pathlib import Path
import argparse
import struct

SECTOR = 512
STAGE1_SECTORS = 32
KERNEL_SECTORS = 1024

def assemble_image(stage0: bytes, stage1: bytes, kernel: bytes) -> bytes:
    if len(stage0) != SECTOR or stage0[510:] != bytes((0x55, 0xaa)):
        raise ValueError("stage0 must have a 512-byte BIOS signature")
    if not stage1 or len(stage1) > STAGE1_SECTORS * SECTOR:
        raise ValueError("stage1 must fit in 32 sectors")
    if len(kernel) < 64 or len(kernel) > KERNEL_SECTORS * SECTOR:
        raise ValueError("ELF64 kernel must fit in 512 KiB")
    if kernel[:4] != bytes((0x7f, 0x45, 0x4c, 0x46)) or kernel[4] != 2:
        raise ValueError("kernel must be ELF64")
    if struct.unpack_from("<H", kernel, 18)[0] != 62:
        raise ValueError("kernel must target x86-64")
    return stage0 + stage1.ljust(STAGE1_SECTORS * SECTOR, bytes(1)) + kernel.ljust(KERNEL_SECTORS * SECTOR, bytes(1))

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("stage0", type=Path)
    ap.add_argument("stage1", type=Path)
    ap.add_argument("kernel", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    data = assemble_image(args.stage0.read_bytes(), args.stage1.read_bytes(), args.kernel.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"Wrote {len(data)} bytes to {args.output}")

if __name__ == "__main__":
    main()
