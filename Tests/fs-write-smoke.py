#!/usr/bin/env python3
"""Verify persistent NoqFS write and directory creation in QEMU.

Creates a fresh NoqFS v2 disk image, launches QEMU with VirtIO block device,
issues 'touch', 'mkdir', 'write', and 'type' commands via COM1 serial shell,
and verifies the on-disk binary structures and contents persist.
"""
import os
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ISO = Path(__file__).resolve().parent.parent / "build" / "noqerios.iso"


def create_noqfs_disk(path: Path) -> None:
    volume = bytearray(2 * 1024 * 1024)
    # Magic NQFS, version 2, rootSector 1, rootEntries 1, sectorSize 512
    struct.pack_into("<4sIQII", volume, 0, b"NQFS", 2, 1, 1, 512)
    # Entry 0: HELLO.TXT, key=1, firstSector=4, size=16, flags=1, parent=0
    raw = b"HELLO.TXT"
    struct.pack_into("<QQQIIQ24s", volume, 512, 1, 4, 16, 1, len(raw), 0, raw)
    volume[4 * 512:4 * 512 + 16] = b"HELO from NoqFS!"
    path.write_bytes(volume)


def collect_until(proc, expected: bytes, timeout: float, output: bytearray) -> None:
    import select
    deadline = time.monotonic() + timeout
    while expected not in output:
        if proc.poll() is not None:
            raise RuntimeError(f"QEMU terminated early ({proc.returncode})")
        rem = deadline - time.monotonic()
        if rem <= 0:
            raise TimeoutError(f"Timed out waiting for {expected!r}; got: {output[-2000:]!r}")
        r, _, _ = select.select([proc.stdout], [], [], min(0.2, rem))
        if r:
            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                break
            output.extend(chunk)


def main():
    with tempfile.TemporaryDirectory(prefix="noqfs-write-") as tmp:
        work = Path(tmp)
        disk = work / "disk.img"
        create_noqfs_disk(disk)

        cmd = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-boot", "order=d", "-cdrom", str(ISO),
            "-drive", f"if=none,format=raw,file={disk},id=files",
            "-device", "virtio-blk-pci,drive=files,disable-legacy=on",
            "-serial", "stdio", "-monitor", "none", "-display", "none",
            "-no-reboot"
        ]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0)
        out = bytearray()
        try:
            collect_until(proc, b"Noqeri Shell 1.0. Enter help for commands.", 20.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)

            # 1. Create a new file
            proc.stdin.write(b"touch TEST.TXT\r")
            proc.stdin.flush()
            collect_until(proc, b"File created", 6.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)
            print("PASS: touch TEST.TXT created entry")

            # 2. Write data to the file
            proc.stdin.write(b"write TEST.TXT HelloFromNoqeriOSWriteTest\r")
            proc.stdin.flush()
            collect_until(proc, b"Wrote 26 bytes", 6.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)
            print("PASS: write TEST.TXT wrote 26 bytes")

            # 3. Read it back via type
            proc.stdin.write(b"type TEST.TXT\r")
            proc.stdin.flush()
            collect_until(proc, b"HelloFromNoqeriOSWriteTest", 6.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)
            print("PASS: type TEST.TXT verified contents on console")

            # 4. Create directory
            proc.stdin.write(b"mkdir MYDIR\r")
            proc.stdin.flush()
            collect_until(proc, b"Directory created", 6.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)
            print("PASS: mkdir MYDIR created directory entry")

            # 5. List directory contents
            proc.stdin.write(b"dir\r")
            proc.stdin.flush()
            collect_until(proc, b"MYDIR", 6.0, out)
            collect_until(proc, b"TEST.TXT", 6.0, out)
            collect_until(proc, b"N:\\> ", 5.0, out)
            print("PASS: dir listed both created entries")

            # 6. Clean shutdown
            proc.stdin.write(b"shutdown\r")
            proc.stdin.flush()
            proc.wait(timeout=5)
            print("PASS: clean shutdown after writes")

        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=3)

        # 7. Check persistence in the disk image file directly!
        saved_disk = disk.read_bytes()
        # Superblock entry count should now be 3 (HELLO.TXT, TEST.TXT, MYDIR)
        magic, ver, rootSec, rootEntries, secSize = struct.unpack_from("<4sIQII", saved_disk, 0)
        assert magic == b"NQFS", f"Bad magic {magic}"
        assert rootEntries == 3, f"Expected 3 root entries, found {rootEntries}"

        # Find TEST.TXT entry in directory table
        found_test = False
        test_first_sec = 0
        for i in range(rootEntries):
            k, first, sz, flags, nlen, par, name = struct.unpack_from("<QQQIIQ24s", saved_disk, 512 + i * 64)
            cleaned_name = name[:nlen].decode("ascii", errors="ignore")
            if cleaned_name == "TEST.TXT":
                found_test = True
                test_first_sec = first
                assert flags == 1, f"Expected file flags=1, got {flags}"
                break
        assert found_test, "TEST.TXT not found in persistent directory table"

        # Check payload in sector
        payload = saved_disk[test_first_sec * 512: test_first_sec * 512 + 26]
        assert payload == b"HelloFromNoqeriOSWriteTest", f"Payload mismatch: {payload!r}"
        print("PASS: offline binary verification confirmed filesystem persistence!")


if __name__ == "__main__":
    main()
