#!/usr/bin/env python3
"""Verify OVMF GOP graphics, compositor redraw and keyboard focus in QEMU.

The test sends a PS/2 key through QEMU's HMP monitor and compares
actual captured video frames. No OCR, screen text scraping, or host
graphics stack is required. This does not validate USB HID or real GPUs.
"""
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"


def firmware():
    for name in ("/usr/share/OVMF/OVMF_CODE_4M.fd",
                 "/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/ovmf/OVMF.fd"):
        if Path(name).exists():
            code = name
            break
    else:
        raise FileNotFoundError("Missing OVMF_CODE")
    for name in ("/usr/share/OVMF/OVMF_VARS_4M.fd",
                 "/usr/share/OVMF/OVMF_VARS.fd"):
        if Path(name).exists():
            return code, name
    raise FileNotFoundError("Missing OVMF_VARS")


def observe(proc, marker, timeout, output):
    end = time.monotonic() + timeout
    while marker not in output:
        if proc.poll() is not None:
            raise RuntimeError(f"QEMU exit {proc.returncode}; serial {output[-4000:]!r}")
        left = end - time.monotonic()
        if left < 0:
            raise TimeoutError(f"Missing {marker!r}: {output[-4000:]!r}")
        ready, _, _ = select.select([proc.stdout], [], [], min(0.2, left))
        if ready:
            data = os.read(proc.stdout.fileno(), 4096)
            if not data:
                raise EOFError("QEMU serial output closed")
            output.extend(data)


def hmp(sock, command):
    sock.sendall((command + "\n").encode("ascii"))


def screenshot(sock, name):
    hmp(sock, f"screendump {name}")
    end = time.monotonic() + 5
    path = Path(name)
    while time.monotonic() < end:
        if path.exists() and path.stat().st_size > 4000:
            return path.read_bytes()
        time.sleep(0.1)
    raise TimeoutError(f"No QEMU screenshot at {name}")


def main():
    code, vars_origin = firmware()
    if not (OUT / "noqerios.iso").exists():
        raise FileNotFoundError("Run Tests/uefi-smoke.sh to build the hybrid ISO")
    with tempfile.TemporaryDirectory(prefix="noqerios-ui-") as tmp:
        working = Path(tmp)
        vars_image = working / "vars.fd"
        vars_image.write_bytes(Path(vars_origin).read_bytes())
        mon = working / "hmp.sock"
        cmd = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={vars_image}",
            "-cdrom", str(OUT / "noqerios.iso"), "-boot", "order=d",
            "-vga", "std", "-display", "none", "-serial", "stdio",
            "-monitor", f"unix:{mon},server,nowait",
            "-no-reboot", "-no-shutdown",
        ]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0)
        output = bytearray()
        try:
            observe(proc, b"NoqeriOS: GUI compositor frame presented", 25, output)
            observe(proc, b"NoqeriOS serial terminal ready", 5, output)
            end = time.monotonic() + 5
            while not mon.exists() and time.monotonic() < end:
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(5)
                sock.connect(str(mon))
                first = screenshot(sock, str(working / "first.ppm"))
                # QEMU keyboard injection reaches legacy i8042 controller.
                hmp(sock, "sendkey s")
                observe(proc, b"NoqeriOS: GUI compositor window focus updated", 6, output)
                second = screenshot(sock, str(working / "second.ppm"))
            if not first.startswith(b"P6") or not second.startswith(b"P6"):
                raise AssertionError("QEMU did not capture PPM framebuffer images")
            if first == second:
                raise AssertionError("Framebuffers unchanged after PS/2 keyboard focus event")
            print("PASS: UEFI GOP GUI rendered and PS/2 keyboard caused a compositor redraw")
        except Exception:
            print("Serial diagnostic:\n" + output.decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            proc.kill()
            proc.communicate(timeout=5)


if __name__ == "__main__":
    main()
