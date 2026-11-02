#!/usr/bin/env python3
"""OVMF surrogate for the physical Lenovo G500 GOP diagnostic USB image.

Prove that the separately compiled diagnostic loader shows its expected
8 bars before kernel handoff and that the kernel subsequently paints GUI.
This is NOT a substitute for a physical Lenovo G500 boot.
"""
import os
from pathlib import Path
import re
import select
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
IMAGE = ROOT / "build" / "noqerios-uefi-usb.img"
BARS = [
    (255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255),
    (255, 0, 255), (255, 255, 0), (255, 255, 255), (0, 0, 0),
]


def firmware():
    codes = [
        "/usr/share/OVMF/OVMF_CODE_4M.fd",
        "/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/ovmf/OVMF.fd",
    ]
    variables = [
        "/usr/share/OVMF/OVMF_VARS_4M.fd",
        "/usr/share/OVMF/OVMF_VARS.fd",
    ]
    return next((Path(p) for p in codes if Path(p).exists()), None), next(
        (Path(p) for p in variables if Path(p).exists()), None
    )


def wait_marker(proc, marker, timeout, captured):
    until = time.monotonic() + timeout
    while marker not in captured:
        if proc.poll() is not None:
            raise RuntimeError(f"QEMU exited early: {proc.returncode}")
        left = until - time.monotonic()
        if left <= 0:
            raise TimeoutError(f"No debug marker {marker!r}; output: {captured[-4000:]!r}")
        readable, _, _ = select.select([proc.stdout], [], [], min(left, 0.1))
        if readable:
            data = os.read(proc.stdout.fileno(), 4096)
            if not data:
                raise EOFError("QEMU debug console ended")
            captured.extend(data)


def wait_serial(path, marker, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and marker in path.read_bytes():
            return
        time.sleep(0.1)
    raise TimeoutError(f"No serial marker {marker!r}; tail: {path.read_bytes()[-2000:]!r}")


def screenshot(monitor, path):
    # QEMU HMP is a plaintext control socket; inspect actual display pixels.
    monitor.sendall(f"screendump {path}\n".encode("ascii"))
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        if path.exists() and path.stat().st_size > 4000:
            return path.read_bytes()
        time.sleep(0.05)
    raise TimeoutError(f"QEMU screenshot missing: {path}")


def parse_ppm(data):
    match = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    if not match:
        raise AssertionError("Malformed QEMU screenshot PPM")
    width, height = map(int, match.groups())
    payload = data[match.end():]
    if width < 320 or height < 240 or len(payload) != width * height * 3:
        raise AssertionError(f"Bad screenshot dimensions or payload: {width}x{height}")
    def pixel(x, y):
        offset = (y * width + x) * 3
        return tuple(payload[offset:offset + 3])
    return width, height, pixel


def near(actual, expected, tolerance=7):
    return all(abs(a - b) <= tolerance for a, b in zip(actual, expected))


def verify_bars(data):
    width, height, pixel = parse_ppm(data)
    y = (height * 5) // 8
    for i, expected in enumerate(BARS):
        x = (width * (2 * i + 1)) // 16
        actual = pixel(x, y)
        if not near(actual, expected):
            raise AssertionError(
                f"Lenovo GOP bar {i + 1} at ({x}, {y}) got {actual}; expected {expected}"
            )
    for y in (height // 4, height // 2, height * 3 // 4):
        for x in (width // 8, width // 2, width * 7 // 8):
            if not near(pixel(x, y), (255, 255, 255)):
                raise AssertionError(f"Horizontal GOP guide missing at ({x}, {y})")


def verify_desktop(data):
    width, height, pixel = parse_ppm(data)
    for x, y, expected in (
        (8, 8, (36, 36, 36)),
        (8, 75, (48, 48, 48)),
        (8, height - 18, (36, 36, 36)),
    ):
        if not near(pixel(x, y), expected):
            raise AssertionError(f"Kernel GUI pixel at ({x}, {y}): {pixel(x,y)} != {expected}")


def main():
    if not IMAGE.is_file():
        raise FileNotFoundError("Build NOQERIOS_LENOVO_VERIFY=1 bash build.sh --uefi first")
    code, var_original = firmware()
    if not code or not var_original:
        raise FileNotFoundError("Install OVMF firmware for the virtual GOP verification")
    with tempfile.TemporaryDirectory(prefix="noqerios-lenovo-") as d:
        work = Path(d)
        variables = work / "ovmf-vars.fd"
        variables.write_bytes(var_original.read_bytes())
        monitor_path = work / "monitor.sock"
        serial = work / "serial.txt"
        args = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={variables}",
            "-drive", f"if=ide,format=raw,file={IMAGE}", "-boot", "order=c",
            "-vga", "std", "-display", "none",
            "-debugcon", "stdio", "-global", "isa-debugcon.iobase=0xe9",
            "-serial", f"file:{serial}",
            "-monitor", f"unix:{monitor_path},server,nowait",
            "-no-reboot", "-no-shutdown",
        ]
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0)
        output = bytearray()
        try:
            wait_marker(proc, b"uefi: Lenovo GOP diagnostic pattern drawn", 35, output)
            deadline = time.monotonic() + 3
            while not monitor_path.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as monitor:
                monitor.settimeout(5)
                monitor.connect(str(monitor_path))
                verify_bars(screenshot(monitor, work / "pattern.ppm"))
                wait_serial(serial, b"NoqeriOS: GUI compositor frame presented", 35)
                verify_desktop(screenshot(monitor, work / "desktop.ppm"))
            print("PASS: dedicated Lenovo GOP pattern and kernel GUI verified in OVMF/QEMU")
        except Exception:
            print("UEFI debug:\n" + output[-4000:].decode(errors="replace"), file=sys.stderr)
            if serial.exists():
                print("Kernel serial:\n" + serial.read_text(errors="replace")[-4000:],
                      file=sys.stderr)
            raise
        finally:
            proc.kill()
            proc.communicate(timeout=5)


if __name__ == "__main__":
    main()
