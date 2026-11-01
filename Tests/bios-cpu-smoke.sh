#!/usr/bin/env bash
# Exercise the existing BIOS real-mode -> protected-mode boot chain with an
# x86 CPU that cannot execute the 64-bit NoqeriOS kernel.
# A clear CPU rejection is correct; a triple fault is not.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$ROOT/build/noqerios.iso"
DEBUG="$ROOT/build/bios-32bit-cpu-debug.log"
[[ -s "$ISO" ]] || { echo "Build the BIOS ISO first with build.sh" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "QEMU is required" >&2; exit 3; }
: >"$DEBUG"
set +e
timeout 15s qemu-system-x86_64 \
    -machine pc -cpu qemu32 -m 256M \
    -cdrom "$ISO" -boot order=d \
    -serial none -debugcon file:"$DEBUG" -global isa-debugcon.iobase=0xe9 \
    -display none -no-reboot -no-shutdown >/dev/null 2>&1
status=$?
set -e
if [[ "$status" != 0 && "$status" != 124 ]]; then
    echo "32-bit BIOS CPU test: unexpected QEMU exit $status" >&2
    cat "$DEBUG" >&2
    exit 1
fi
# The native stage1 emits 'R' after loading the kernel and 'C' only when
# the processor fails long-mode/PAE/MSR capability checks.
if ! grep -q 'RC' "$DEBUG"; then
    echo "The 32-bit CPU was not rejected before long-mode transition:" >&2
    cat "$DEBUG" >&2
    exit 1
fi
echo "PASS: BIOS real-mode boot handles 32-bit-only x86 CPU without entering ELF64 kernel"
