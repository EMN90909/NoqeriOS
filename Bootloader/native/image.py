#!/usr/bin/env python3
"""Build a stage0/stage1 BIOS image with strict size and signature checks."""
from pathlib import Path
import argparse

SECTOR = 512
STAGE1_SECTORS = 32

def assemble_image(boot_sector: bytes, stage1: bytes) -> bytes:
    if len(boot_sector) != SECTOR or boot_sector[510:] != bytes((0x55, 0xaa)):
        raise ValueError("stage0 must be a signed 512-byte BIOS boot sector")
    if not stage1 or len(stage1) > STAGE1_SECTORS * SECTOR:
        raise ValueError("stage1 must fit in 32 sectors and cannot be empty")
    return boot_sector + stage1.ljust(STAGE1_SECTORS * SECTOR, bytes((0,)))

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("stage0", type=Path)
    ap.add_argument("stage1", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    image = assemble_image(args.stage0.read_bytes(), args.stage1.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)

if __name__ == "__main__":
    main()
