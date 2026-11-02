#!/usr/bin/env python3
"""UEFI dual-boot integration: scan a second EFI disk and chainload its image.

Never modifies a host disk. The alternate EFI app is a harmless test
fixture that prints an I/O-port marker and returns to the menu.
"""
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build"


def command(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def firmware():
    codes = ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd"]
    vars_files = ["/usr/share/OVMF/OVMF_VARS_4M.fd", "/usr/share/OVMF/OVMF_VARS.fd"]
    return (next(Path(x) for x in codes if Path(x).exists()),
            next(Path(x) for x in vars_files if Path(x).exists()))


def build_fixture(tmp):
    crt = next(Path(x) for x in ("/usr/lib", "/usr/lib64", "/usr/lib/gnuefi",
                                "/usr/lib/x86_64-linux-gnu")
               if (Path(x) / "crt0-efi-x86_64.o").exists()
               and (Path(x) / "elf_x86_64_efi.lds").exists())
    obj, so, efi = (tmp / "alternate.o", tmp / "alternate.so", tmp / "alternate.efi")
    command("gcc", "-std=gnu11", "-O2", "-fpic", "-ffreestanding",
            "-fshort-wchar", "-fno-stack-protector", "-fno-builtin",
            "-mno-red-zone", "-DGNU_EFI_USE_MS_ABI",
            "-I/usr/include/efi", "-I/usr/include/efi/x86_64",
            "-c", str(ROOT / "Tests/fixtures/alternate_efi.c"), "-o", str(obj))
    libgcc = subprocess.check_output(["gcc", "-print-libgcc-file-name"], text=True).strip()
    command("ld", "-nostdlib", "-znocombreloc", "-shared", "-Bsymbolic",
            "-T", str(crt / "elf_x86_64_efi.lds"),
            str(crt / "crt0-efi-x86_64.o"), str(obj),
            "-L", str(crt), "-o", str(so), "-lgnuefi", "-lefi", libgcc)
    command("objcopy", "-j", ".text", "-j", ".sdata", "-j", ".data",
            "-j", ".rodata", "-j", ".dynamic", "-j", ".dynsym",
            "-j", ".rel", "-j", ".rela", "-j", ".reloc", "-j", ".rela.*",
            "--target=efi-app-x86_64", "--subsystem=10", str(so), str(efi))
    disk = tmp / "windows-esp.img"
    with disk.open("wb") as fd:
        fd.truncate(32 * 1024 * 1024)
    command("mformat", "-i", str(disk), "::")
    command("mmd", "-i", str(disk), "::/EFI", "::/EFI/Microsoft", "::/EFI/Microsoft/Boot")
    command("mcopy", "-i", str(disk), str(efi),
            "::/EFI/Microsoft/Boot/bootmgfw.efi")
    return disk


def wait_for(datafile, needle, timeout=24):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if datafile.exists() and needle in datafile.read_bytes():
            return
        time.sleep(0.1)
    text = datafile.read_text(errors="replace")[-5000:] if datafile.exists() else "missing"
    raise AssertionError(f"Missing {needle!r} in UEFI debug output: {text}")


def run():
    code, vars_file = firmware()
    if not (OUT / "noqerios.iso").exists():
        raise FileNotFoundError("Build NoqeriOS UEFI ISO first")
    with tempfile.TemporaryDirectory(prefix="noqeri-dualboot-") as scratch:
        tmp = Path(scratch)
        disk = build_fixture(tmp)
        vars_copy = tmp / "vars.fd"
        shutil.copyfile(vars_file, vars_copy)
        monitor = tmp / "hmp.sock"
        debug = tmp / "debug.log"
        cmd = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}",
            "-cdrom", str(OUT / "noqerios.iso"), "-boot", "order=d",
            "-drive", f"if=none,format=raw,file={disk},id=alternate",
            "-device", "virtio-blk-pci,drive=alternate",
            "-device", "qemu-xhci,id=keyboard-controller",
            "-device", "usb-kbd,bus=keyboard-controller.0",
            "-serial", "none", "-display", "none",
            "-debugcon", f"file:{debug}", "-global", "isa-debugcon.iobase=0xe9",
            "-monitor", f"unix:{monitor},server,nowait",
            "-no-reboot", "-no-shutdown",
        ]
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE)
        try:
            wait_for(debug, b"NoqeriOS boot menu: alternate EFI loaders found")
            end = time.monotonic() + 5
            while not monitor.exists() and time.monotonic() < end:
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as sock:
                sock.settimeout(5)
                sock.connect(str(monitor))
                for attempt in range(8):
                    sock.sendall(b"sendkey 1\n")
                    time.sleep(0.2)
            wait_for(debug, b"NOQERI_ALT_EFI_EXECUTED", 12)
            wait_for(debug, b"NoqeriOS UEFI: ExitBootServices OK", 12)
            print("PASS: cross-volume EFI loader discovery, selection, chainload and safe return")
        finally:
            proc.kill()
            proc.communicate(timeout=5)


if __name__ == "__main__":
    run()
