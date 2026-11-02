#!/usr/bin/env python3
"""End-to-end NoqeriOS TCP 3-way handshake + HTTP reply over QEMU user NAT.

Only a local host fixture is contacted (guest 10.0.2.2:18080); no public
internet traffic or forwarded inbound guest ports. Requires built kernel ISO.
"""
import argparse
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
ISO = ROOT / "build" / "noqerios.iso"
DISK = ROOT / "build" / "virtio-test.img"
EXPECTED = b"TCP: local HTTP fixture response verified"


def fixture(server: socket.socket, failures: list[str]) -> None:
    try:
        server.settimeout(35)
        client, address = server.accept()
        with client:
            client.settimeout(7)
            incoming = bytearray()
            while b"\r\n\r\n" not in incoming and len(incoming) < 1024:
                data = client.recv(1024)
                if not data:
                    break
                incoming.extend(data)
            if not incoming.startswith(b"GET / HTTP/1.0\r\n"):
                failures.append(f"Unexpected guest HTTP request: {incoming!r}")
                return
            body = b"NOQERI_NET_OK"
            client.sendall(
                b"HTTP/1.0 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n"
                b"\r\n" + body
            )
            time.sleep(0.4)
    except Exception as e:
        failures.append(str(e))


def until(proc: subprocess.Popen, expected: bytes,
          limit: float, output: bytearray) -> None:
    stop = time.monotonic() + limit
    while expected not in output:
        if proc.poll() is not None:
            raise RuntimeError(f"QEMU exited with {proc.returncode}")
        remaining = stop - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"Expected {expected!r}; observed: {output[-2500:]!r}")
        ready, _, _ = select.select([proc.stdout], [], [], min(0.2, remaining))
        if ready:
            data = os.read(proc.stdout.fileno(), 4096)
            if not data:
                raise EOFError("QEMU serial stream closed")
            output.extend(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--nic", choices=("virtio", "e1000", "rtl8139"), default="virtio")
    args = parser.parse_args()
    if not ISO.is_file() or not DISK.is_file():
        raise SystemExit("Run Tests/qemu-smoke.sh first to build ISO and NoqFS disk")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 18080))
    server.listen(2)
    errors = []
    worker = threading.Thread(target=fixture, args=(server, errors), daemon=True)
    worker.start()
    device = {
        "virtio": "virtio-net-pci,netdev=noqnet,disable-legacy=on,mac=52:54:00:12:34:56",
        "e1000": "e1000,netdev=noqnet,mac=52:54:00:12:34:56",
        "rtl8139": "rtl8139,netdev=noqnet,mac=52:54:00:12:34:56",
    }[args.nic]
    command = [
        "qemu-system-x86_64", "-machine", "q35", "-m", "256M",
        "-boot", "order=d", "-cdrom", str(ISO),
        "-device", "virtio-rng-pci,disable-legacy=on",
        "-netdev", "user,id=noqnet,ipv6=off",
        "-device", device,
        "-drive", f"if=none,format=raw,file={DISK},id=noqerios-test-disk",
        "-device", "virtio-blk-pci,drive=noqerios-test-disk,disable-legacy=on",
        "-serial", "stdio", "-monitor", "none", "-display", "none",
        "-no-reboot", "-no-shutdown",
    ]
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, bufsize=0)
    output = bytearray()
    try:
        until(proc, b"NoqeriOS serial terminal ready (COM1)", 14, output)
        until(proc, b"N:\\> ", 4, output)
        output.clear()
        proc.stdin.write(b"tcp\r")
        proc.stdin.flush()
        until(proc, EXPECTED, 17, output)
        worker.join(timeout=1)
        if errors:
            raise AssertionError(f"Host TCP fixture failed: {errors}")
        print(f"PASS: {args.nic} NoqeriOS TCP SYN/SYN-ACK/ACK, HTTP request, and local HTTP response")
    except Exception:
        print("Captured serial output:\n" +
              output.decode(errors="replace"), file=sys.stderr)
        raise
    finally:
        proc.kill()
        proc.communicate(timeout=5)
        server.close()


if __name__ == "__main__":
    main()
