#!/usr/bin/env python3
"""Probe the actual VirtIO GPU control queue under QEMU/OVMF.

An OK_DISPLAY_INFO reply proves device control is functioning; it does not
mean NoqeriOS uses GPU acceleration for rasterization yet.
"""
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ISO = ROOT / "build" / "noqerios.iso"


def find_firmware():
    codes = ("/home/antigravity/local-root/usr/share/OVMF/OVMF_CODE_4M.fd",
             "/home/antigravity/local-root/usr/share/OVMF/OVMF_CODE.fd")
    variables = ("/home/antigravity/local-root/usr/share/OVMF/OVMF_VARS_4M.fd",
                 "/home/antigravity/local-root/usr/share/OVMF/OVMF_VARS.fd")
    code = next((p for p in codes if Path(p).exists()), None)
    vars_file = next((p for p in variables if Path(p).exists()), None)
    if not code or not vars_file:
        raise FileNotFoundError("OVMF firmware must be installed")
    return code, vars_file


def main():
    if not ISO.exists():
        raise FileNotFoundError("Build the hybrid ISO first")
    code, vars_file = find_firmware()
    with tempfile.TemporaryDirectory(prefix="noqeri-gpu-") as tmp:
        variables = Path(tmp) / "vars.fd"
        variables.write_bytes(Path(vars_file).read_bytes())
        command = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={variables}",
            "-cdrom", str(ISO), "-boot", "order=d",
            "-vga", "std", "-device", "virtio-gpu-pci",
            "-serial", "stdio", "-monitor", "none", "-display", "none",
            "-no-reboot", "-no-shutdown",
        ]
        proc = subprocess.Popen(command, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                bufsize=0)
        output = bytearray()
        try:
            deadline = time.monotonic() + 32
            expected = b"NoqeriOS: VirtIO GPU control queue display-info handshake passed"
            scanout = b"NoqeriOS: VirtIO GPU 2D scanout and DMA presentation active"
            complete = b"NoqeriOS serial terminal ready"
            while time.monotonic() < deadline:
                if expected in output and scanout in output and complete in output:
                    print("PASS: VirtIO GPU PCI control queue and 2D DMA-backed scanout presented")
                    return
                if proc.poll() is not None:
                    break
                ready, _, _ = select.select([proc.stdout], [], [], 0.2)
                if ready:
                    chunk = os.read(proc.stdout.fileno(), 4096)
                    if not chunk:
                        break
                    output.extend(chunk)
            raise AssertionError("GPU handshake/terminal missing:\n" +
                                 output.decode("utf-8", errors="replace")[-5000:])
        finally:
            proc.kill()
            proc.communicate(timeout=5)


if __name__ == "__main__":
    main()
