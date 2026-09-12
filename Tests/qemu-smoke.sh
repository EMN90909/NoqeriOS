#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
LOG="$OUT/qemu-serial.log"

bash "$ROOT/build.sh"

if [[ ! -f "$OUT/noqerios.iso" ]]; then
    echo "SKIP: noqerios.iso was not produced (grub-mkrescue unavailable)"
    exit 0
fi
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SKIP: qemu-system-x86_64 unavailable"
    exit 0
fi

rm -f "$LOG"
set +e
timeout 8s qemu-system-x86_64 \
    -machine q35 \
    -m 256M \
    -cdrom "$OUT/noqerios.iso" \
    -device virtio-rng-pci \
    -serial file:"$LOG" \
    -display none \
    -no-reboot \
    -no-shutdown >/dev/null 2>&1
rc=$?
set -e

if [[ $rc -ne 0 && $rc -ne 124 ]]; then
    echo "QEMU exited unexpectedly with $rc" >&2
    cat "$LOG" >&2 || true
    exit 1
fi

grep -q "NoqeriOS: entered 64-bit Noqeri kernel" "$LOG"
grep -q "NoqeriOS: serial driver online" "$LOG"
grep -q "NoqeriOS: physical memory map accepted" "$LOG"
grep -q "NoqeriOS: physical page allocation succeeded" "$LOG"
grep -q "NoqeriOS: PCI configuration space enumerated" "$LOG"
grep -q "NoqeriOS: VirtIO PCI device detected" "$LOG"
grep -q "NoqeriOS: modern VirtIO PCI transport capabilities detected" "$LOG"
grep -q "NoqeriOS: VirtIO common-config status handshake succeeded" "$LOG"
grep -q "NoqeriOS: IDT and PIT timer interrupts active" "$LOG"
grep -q "NoqeriOS: ring-3 transition and syscall gate active" "$LOG"
grep -q "NoqeriOS: bootstrap milestone complete" "$LOG"

echo "NoqeriOS QEMU smoke test passed"
cat "$LOG"
