#!/usr/bin/env bash
# Local-only verification; never calls GitHub Actions or writes to a disk.
# Usage: bash Tests/local-verify.sh --unit | --full | --lenovo
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mode="${1:---unit}"
case "$mode" in --unit|--full|--lenovo) ;; *) echo "Use --unit, --full or --lenovo" >&2; exit 2 ;; esac

for command_name in zig bash gcc python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing $command_name. Install local build tools first." >&2; exit 3;
  }
done
[[ "$(zig version)" == "0.15.2" ]] || {
  echo "Zig 0.15.2 required; found $(zig version)" >&2; exit 3;
}
bash -n build.sh Bootloader/uefi/build.sh Tests/uefi-smoke.sh Tests/qemu-smoke.sh
zig test Bootloader/zig/elf.zig
zig test Drivers/framebuffer.zig
echo "PASS: local Zig and build-script preflight"

if [[ "$mode" == --unit ]]; then
  echo "NOTE: unit tests alone DO NOT prove that BIOS/UEFI or physical GOP boots."
  exit 0
fi

for command_name in qemu-system-x86_64 xorriso mformat mmd mcopy ld as; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing $command_name; install QEMU, binutils, xorriso, and mtools." >&2; exit 3;
  }
done
[[ -f /usr/include/efi/efi.h || -f /home/antigravity/local-root/usr/include/efi/efi.h ]] || { echo "Missing GNU-EFI headers" >&2; exit 3; }

# Run the actual kernel in SeaBIOS and OVMF rather than testing code paths
# with mocked firmware. Both paths must reach a Noqeri serial terminal.
bash Tests/qemu-smoke.sh
NOQERIOS_ZIG_BOOT=1 NOQERIOS_REQUIRE_GOP=1 bash Tests/uefi-smoke.sh
python3 Tests/gui-smoke.py
python3 Tests/mouse-smoke.py
python3 Tests/fs-write-smoke.py
NOQERIOS_ZIG_BOOT=1 NOQERIOS_REQUIRE_GOP=1 NOQERIOS_UEFI_MEDIA=usb bash Tests/uefi-smoke.sh
bash Tests/uefi-usb-smoke.sh
echo "PASS: local BIOS, UEFI, framebuffer, desktop and USB-boot QEMU gates"

if [[ "$mode" == --lenovo ]]; then
  # Virtual diagnostic only. Real Lenovo hardware still requires a fresh
  # removable-media boot and two photographs.
  NOQERIOS_LENOVO_VERIFY=1 NOQERIOS_ZIG_BOOT=1 bash build.sh --uefi
  python3 Tests/lenovo-g500-smoke.py
  echo "PASS: virtual Lenovo GOP pattern test (NOT a physical hardware certificate)"
fi
