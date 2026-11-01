#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
LOG="$OUT/qemu-serial.log"
DEBUG_LOG="$OUT/qemu-boot-debug.log"
DISK="$OUT/virtio-test.img"
MEMORY="${NOQERIOS_MEMORY:-256M}"

on_exit() {
    local status=$?
    if (( status != 0 )); then
        echo "QEMU boot test failed (status $status). Serial log:" >&2
        if [[ -f "$LOG" ]]; then cat "$LOG" >&2; fi
        echo "BIOS stage debug port:" >&2
        if [[ -f "$DEBUG_LOG" ]]; then cat "$DEBUG_LOG" >&2; fi
    fi
}
trap on_exit EXIT

bash "$ROOT/build.sh" --native

if [[ ! -s "$OUT/noqerios.iso" ]]; then
    echo "ERROR: custom BIOS ISO was not produced" >&2
    exit 1
fi
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "ERROR: qemu-system-x86_64 unavailable" >&2
    exit 1
fi

# NoqFS v1 test image.
# sector 0: superblock { magic, version, root dir sector, entry count, sector size }
# sector 1: one 32-byte root directory entry { key, first sector, byte length, flags }
# sector 2: file payload beginning with the HELO marker.
truncate -s 1M "$DISK"
printf 'NQFS' | dd of="$DISK" bs=1 seek=0 conv=notrunc status=none
printf '\x01\x00\x00\x00' | dd of="$DISK" bs=1 seek=4 conv=notrunc status=none
printf '\x01\x00\x00\x00\x00\x00\x00\x00' | dd of="$DISK" bs=1 seek=8 conv=notrunc status=none
printf '\x01\x00\x00\x00' | dd of="$DISK" bs=1 seek=16 conv=notrunc status=none
printf '\x00\x02\x00\x00' | dd of="$DISK" bs=1 seek=20 conv=notrunc status=none

printf '\x01\x00\x00\x00\x00\x00\x00\x00' | dd of="$DISK" bs=1 seek=512 conv=notrunc status=none
printf '\x02\x00\x00\x00\x00\x00\x00\x00' | dd of="$DISK" bs=1 seek=520 conv=notrunc status=none
printf '\x10\x00\x00\x00\x00\x00\x00\x00' | dd of="$DISK" bs=1 seek=528 conv=notrunc status=none
printf '\x01\x00\x00\x00' | dd of="$DISK" bs=1 seek=536 conv=notrunc status=none
printf 'HELO from NoqFS\n' | dd of="$DISK" bs=1 seek=1024 conv=notrunc status=none

# Network tests use slirp's isolated virtual LAN, without forwarding ports
# or exposing the experimental kernel as a service to the host network.
NETWORK_ARGS=()
if [[ "${NOQERIOS_NETWORK:-0}" == 1 ]]; then
    NETWORK_ARGS=(-netdev user,id=noqnet,restrict=on -device virtio-net-pci,netdev=noqnet,disable-legacy=on,mac=52:54:00:12:34:56)
fi
rm -f "$LOG" "$DEBUG_LOG"
set +e
timeout 20s qemu-system-x86_64 \
    -machine q35 \
    -m "$MEMORY" \
    -boot order=d \
    -cdrom "$OUT/noqerios.iso" \
    -device virtio-rng-pci,disable-legacy=on \
    "${NETWORK_ARGS[@]}" \
    -drive if=none,format=raw,file="$DISK",id=noqerios-test-disk \
    -device virtio-blk-pci,drive=noqerios-test-disk,disable-legacy=on \
    -serial file:"$LOG" \
    -debugcon file:"$DEBUG_LOG" \
    -global isa-debugcon.iobase=0xe9 \
    -display none -no-reboot -no-shutdown >/dev/null 2>&1
rc=$?
set -e

if [[ $rc -ne 0 && $rc -ne 124 ]]; then
    echo "QEMU exited unexpectedly with $rc" >&2
    cat "$LOG" >&2 || true
    exit 1
fi

if ! grep -q "NoqeriOS: entered 64-bit Noqeri kernel" "$LOG"; then
    echo "NoqeriOS kernel entry not observed. Boot debug:" >&2
    cat "$DEBUG_LOG" >&2 || true
    cat "$LOG" >&2 || true
    exit 1
fi
grep -q "NoqeriOS: serial driver online" "$LOG"
grep -q "NoqeriOS: physical memory map accepted" "$LOG"
grep -q "NoqeriOS: bitmap physical memory manager online" "$LOG"
grep -q "NoqeriOS: PMM alloc free reserve and contiguous tests passed" "$LOG"
grep -q "NoqeriOS: physical page allocation succeeded" "$LOG"
grep -q "NoqeriOS: VMM isolated CR3 map unmap protect test passed" "$LOG"
grep -q "NoqeriOS: kernel heap alloc free reuse stress passed" "$LOG"
grep -q "NoqeriOS: legacy page allocator rebased onto PMM-owned pool" "$LOG"
grep -q "NoqeriOS: round-robin process scheduler core active" "$LOG"
grep -q "NoqeriOS: PCI configuration space enumerated" "$LOG"
grep -q "NoqeriOS: VirtIO RNG PCI device detected" "$LOG"
grep -q "NoqeriOS: modern VirtIO PCI transport capabilities detected" "$LOG"
grep -q "NoqeriOS: VirtIO common-config status handshake succeeded" "$LOG"
grep -q "NoqeriOS: VirtIO RNG DMA request completed" "$LOG"
grep -q "NoqeriOS: VirtIO block device detected" "$LOG"
grep -q "NoqeriOS: VirtIO block sector read succeeded" "$LOG"
grep -q "NoqeriOS: NoqFS boot volume recognized by VFS" "$LOG"
grep -q "NoqeriOS: VFS opened and read a NoqFS file" "$LOG"
grep -q "NoqeriOS: IDT and PIT timer interrupts active" "$LOG"
grep -q "NoqeriOS: ring-3 transition and syscall gate active" "$LOG"
grep -q "NoqeriOS: ring-3 syscall reached Noqeri dispatcher" "$LOG"
grep -q "NoqeriOS: modular monolith core services online" "$LOG"
grep -q "NoqeriOS: bootstrap milestone complete" "$LOG"
grep -q "NoqeriOS serial terminal ready" "$LOG"

if [[ "${NOQERIOS_NETWORK:-0}" == 1 ]]; then
    grep -q "NoqeriOS: VirtIO Ethernet DMA RX/TX queues online" "$LOG"
    grep -q "NoqeriOS: DHCP IPv4 lease acquired" "$LOG"
    grep -q "NoqeriOS: IPv4 gateway ARP resolved (Ethernet connected)" "$LOG"
fi

echo "NoqeriOS custom BIOS ISO QEMU smoke test passed with $MEMORY RAM"
cat "$LOG"
