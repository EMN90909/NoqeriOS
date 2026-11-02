#!/usr/bin/env python3
"""Validate native Noqeri BOOTX64.EFI PE32+ and the x64 kernel handoff entry."""
import struct
import subprocess
import sys
from pathlib import Path

def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]

def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]

def check_pe(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 0x100 or data[0:2] != b"MZ":
        raise ValueError("not a DOS/PE executable")
    pe = u32(data, 0x3C)
    if pe + 24 + 160 > len(data) or data[pe:pe+4] != b"PE\x00\x00":
        raise ValueError("missing PE signature / optional header")
    if u16(data, pe + 4) != 0x8664:
        raise ValueError("BOOTX64.EFI must be an AMD64 image")
    optional = pe + 24
    if u16(data, optional) != 0x20B:
        raise ValueError("not PE32+")
    if u16(data, optional + 68) != 10:
        raise ValueError("not EFI application subsystem 10")
    if u32(data, optional + 16) == 0:
        raise ValueError("entry RVA is empty")
    if u32(data, optional + 108) <= 5:
        raise ValueError("missing relocation directory")
    rva, size = struct.unpack_from("<II", data, optional + 112 + 5*8)
    if not rva or not size:
        raise ValueError("image cannot be relocated by firmware")
    print(f"PE32+ EFI application: {path}, relocation directory RVA=0x{rva:x}")

def check_kernel(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("not little-endian ELF64")
    if u16(data, 16) != 2 or u16(data, 18) != 62:
        raise ValueError("not x86-64 ET_EXEC")
    entry = struct.unpack_from("<Q", data, 24)[0]
    symbols = subprocess.check_output(["nm", "-P", str(path)], text=True)
    entry_symbol = None
    bios_symbol = None
    for line in symbols.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "uefi_kernel_entry":
            entry_symbol = int(parts[2], 16)
        if len(parts) >= 3 and parts[0] == "_start":
            bios_symbol = int(parts[2], 16)
    if entry_symbol is None or entry != entry_symbol or entry == bios_symbol:
        raise ValueError("kernel ELF entry must be uefi_kernel_entry, never _start")
    print(f"UEFI ELF kernel: {path}, entry=0x{entry:x}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: uefi_noqeri_pe.py BOOTX64.EFI kernel-uefi.elf")
    check_pe(Path(sys.argv[1]))
    check_kernel(Path(sys.argv[2]))
