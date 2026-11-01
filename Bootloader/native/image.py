#!/usr/bin/env python3
"""Build a custom NoqeriOS BIOS boot image suitable for El Torito floppy emulation.

LBA0: our stage0. LBA1..32: stage1. LBA33..1056: kernel ELF64.
The remainder is zero-padded to a standard 1.44 MiB virtual floppy.
"""
from pathlib import Path
import argparse
import struct

SECTOR = 512
STAGE1_SECTORS = 32
KERNEL_SECTORS = 1024
FLOPPY_SECTORS = 2880
KERNEL_FILE_LIMIT = KERNEL_SECTORS * SECTOR


def check_elf64(kernel: bytes) -> None:
    if len(kernel) < 64 or len(kernel) > KERNEL_FILE_LIMIT:
        raise ValueError("ELF64 kernel must fit in the 512 KiB loader window")
    if kernel[:4] != b"\x7fELF" or kernel[4] != 2 or kernel[5] != 1:
        raise ValueError("kernel must be a little-endian ELF64")
    if struct.unpack_from("<HH", kernel, 16) != (2, 62):
        raise ValueError("kernel must be an x86-64 ELF executable (ET_EXEC)")
    entry = struct.unpack_from("<Q", kernel, 24)[0]
    phoff = struct.unpack_from("<Q", kernel, 32)[0]
    phentsize, phcount = struct.unpack_from("<HH", kernel, 54)
    if not 0x100000 <= entry < 0x40000000:
        raise ValueError("entry must be 32-bit and within bootstrap identity mapping")
    if phentsize < 56 or not (1 <= phcount <= 128):
        raise ValueError("invalid program header table")
    if phoff + phentsize * phcount > len(kernel):
        raise ValueError("program headers exceed the kernel ELF")
    loads = 0
    entry_covered = False
    for i in range(phcount):
        h = phoff + i * phentsize
        kind = struct.unpack_from("<I", kernel, h)[0]
        if kind != 1:
            continue
        _, _, offset, vaddr, paddr, filesz, memsz, _ = struct.unpack_from("<IIQQQQQQ", kernel, h)
        if filesz > memsz or offset + filesz > len(kernel):
            raise ValueError("PT_LOAD file/memory bounds invalid")
        if paddr < 0x100000 or paddr + memsz > 0x40000000 or vaddr != paddr:
            raise ValueError("PT_LOAD must use low identity-mapped physical addresses")
        if paddr <= entry < paddr + memsz:
            entry_covered = True
        loads += 1
    if not loads or not entry_covered:
        raise ValueError("kernel entry is not covered by a PT_LOAD segment")


def assemble_image(stage0: bytes, stage1: bytes, kernel: bytes) -> bytes:
    if len(stage0) != SECTOR or stage0[510:] != b"\x55\xaa":
        raise ValueError("stage0 must have a signed 512-byte BIOS boot sector")
    if not stage1 or len(stage1) > STAGE1_SECTORS * SECTOR:
        raise ValueError("stage1 must fit in the first 32 sectors")
    check_elf64(kernel)
    result = stage0 + stage1.ljust(STAGE1_SECTORS * SECTOR, b"\x00")
    result += kernel.ljust(KERNEL_FILE_LIMIT, b"\x00")
    return result.ljust(FLOPPY_SECTORS * SECTOR, b"\x00")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage0", type=Path)
    parser.add_argument("stage1", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    image = assemble_image(args.stage0.read_bytes(), args.stage1.read_bytes(), args.kernel.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    print(f"Built {len(image)}-byte original BIOS/El Torito floppy image: {args.output}")


if __name__ == "__main__":
    main()
