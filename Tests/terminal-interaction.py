#!/usr/bin/env python3
"""Verify the *interactive* NoqeriOS COM1 terminal on the custom BIOS ISO.

The existing smoke test checks boot milestones. This integration test sends
actual commands over QEMU's serial input and checks the Noqeri responses.
"""
import argparse
import os
from pathlib import Path
import select
import subprocess
import sys
import time


def collect_until(proc: subprocess.Popen, expected: bytes, timeout: float, output: bytearray) -> None:
    deadline = time.monotonic() + timeout
    while expected not in output:
        if proc.poll() is not None:
            raise RuntimeError(f"QEMU terminated before {expected!r} (exit {proc.returncode})")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"No serial response containing {expected!r}")
        readable, _, _ = select.select([proc.stdout], [], [], min(0.25, remaining))
        if readable:
            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                raise EOFError("QEMU closed its serial output")
            output.extend(chunk)


def verify(iso: Path, disk: Path, memory: str) -> None:
    if not iso.is_file() or not disk.is_file():
        raise FileNotFoundError("Build the ISO and test NoqFS disk with Tests/qemu-smoke.sh first")
    command = [
        "qemu-system-x86_64", "-machine", "q35", "-m", memory,
        "-boot", "order=d", "-cdrom", str(iso),
        "-device", "virtio-rng-pci,disable-legacy=on",
        "-drive", f"if=none,format=raw,file={disk},id=noqerios-test-disk",
        "-device", "virtio-blk-pci,drive=noqerios-test-disk,disable-legacy=on",
        "-serial", "stdio", "-monitor", "none",
        "-display", "none", "-no-reboot", "-no-shutdown",
    ]
    output = bytearray()
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, bufsize=0)
    try:
        collect_until(proc, b"NoqeriOS serial terminal ready (COM1)", 15.0, output)
        collect_until(proc, b"noqerios> ", 5.0, output)
        cases = [
            (b"h", b"Commands: h help"),
            (b"i", b"experimental x86_64 kernel"),
            (b"m", b"Memory: physical allocator"),
            (b"p", b"Processes: kernel scheduler"),
            (b"n", b"Network: no configured Ethernet interface"),
            (b"g", b"Network: no configured gateway"),
            (b"d", b"DNS: network offline"),
            (b"c", b"noqerios> "),
            (b"r", b"Reboot requires QEMU reset"),
        ]
        for key, response in cases:
            # Only look at output produced after this command, not earlier text.
            output.clear()
            proc.stdin.write(key)
            proc.stdin.flush()
            collect_until(proc, response, 5.0, output)
        print(f"PASS: NoqeriOS custom BIOS ISO boots and responds to {len(cases)} serial commands")
    except Exception:
        print("Captured serial output:\n" + output.decode("utf-8", errors="replace"), file=sys.stderr)
        raise
    finally:
        proc.kill()
        _, stderr = proc.communicate(timeout=5)
        if proc.returncode not in (0, -9) and stderr:
            print(stderr.decode("utf-8", errors="replace")[-3000:], file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iso", type=Path, default=Path("build/noqerios.iso"))
    parser.add_argument("--disk", type=Path, default=Path("build/virtio-test.img"))
    parser.add_argument("--memory", default="256M")
    args = parser.parse_args()
    verify(args.iso.resolve(), args.disk.resolve(), args.memory)


if __name__ == "__main__":
    main()
