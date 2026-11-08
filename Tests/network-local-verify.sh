#!/usr/bin/env bash
# Local-only networking regression matrix. NEVER invokes GitHub Actions.
# Requires Zig 0.15.2, Noqeri compiler, QEMU, xorriso and Python3.
# No physical network access: QEMU user-mode NAT with no host forwarding.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for name in zig qemu-system-x86_64 python3 xorriso bash; do
    command -v "$name" >/dev/null 2>&1 || {
        echo "Missing $name. Install the local toolchain before testing." >&2
        exit 3
    }
done
[[ "$(zig version)" == "0.15.2" ]] || {
    echo "Zig 0.15.2 required; detected $(zig version)" >&2
    exit 3
}
bash -n build.sh Tests/qemu-smoke.sh Tests/network-local-verify.sh
echo "Local NoqeriOS networking: VirtIO, Intel 82540EM, RTL8139"

for nic in virtio e1000 rtl8139; do
    echo "=== $nic: real DHCP, ARP and kernel packet-parser fixtures ==="
    NOQERIOS_NETWORK="$nic" bash Tests/qemu-smoke.sh
    log="build/qemu-serial.log"
    grep -q 'NoqeriOS: IPv4 DHCP packet validation fixture passed' "$log" || {
        echo "FAILED: IPv4/DHCP parser fixture ($nic)" >&2
        exit 1
    }
    grep -q 'NoqeriOS: DNS wire parser fixture passed' "$log" || {
        echo "FAILED: DNS parser fixture ($nic)" >&2
        exit 1
    }
    grep -q 'NoqeriOS: DHCP IPv4 lease acquired' "$log" || {
        echo "FAILED: DHCP lease ($nic)" >&2
        exit 1
    }
    grep -q 'NoqeriOS: IPv4 gateway ARP resolved' "$log" || {
        echo "FAILED: gateway ARP ($nic)" >&2
        exit 1
    }
    echo "=== $nic: restricted loopback TCP/HTTP fixture ==="
    python3 Tests/tcp-http-smoke.py --nic "$nic"
done
echo "PASS: local-only NoqeriOS network regression suite"
