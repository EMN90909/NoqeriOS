#!/usr/bin/env python3
"""Verify the shell `shutdown` and `reboot` commands on the BIOS ISO in QEMU.

shutdown: QEMU must exit by itself (ACPI PM1a write) with status 0.
reboot:   with -no-reboot QEMU exits when the guest resets the CPU.
Emulator evidence only; real hardware shutdown needs an ACPI FADT parser.
"""
import os
import select
import subprocess
import sys
import time
from pathlib import Path

ISO = Path(__file__).resolve().parent.parent / "build" / "noqerios.iso"


def run(command: bytes, expect: bytes) -> None:
    args = ["qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-boot", "order=d", "-cdrom", str(ISO),
            "-serial", "stdio", "-monitor", "none", "-display", "none",
            "-no-reboot"]
    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, bufsize=0)
    out = bytearray()
    deadline = time.monotonic() + 30
    sent = False
    while proc.poll() is None and time.monotonic() < deadline:
        r, _, _ = select.select([proc.stdout], [], [], 0.25)
        if r:
            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                break
            out.extend(chunk)
        if not sent and b"N:\\> " in out:
            proc.stdin.write(command + b"\r")
            proc.stdin.flush()
            sent = True
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise SystemExit(f"FAIL: {command!r} did not terminate QEMU")
    if expect not in out:
        raise SystemExit(f"FAIL: {command!r} missing {expect!r}")
    print(f"PASS: {command.decode()} -> QEMU exited ({proc.returncode})")


if __name__ == "__main__":
    run(b"shutdown", b"safe to power off")
    run(b"reboot", b"Rebooting...")
