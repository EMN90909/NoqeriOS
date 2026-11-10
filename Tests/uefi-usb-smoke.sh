#!/usr/bin/env bash
# Check GPT removable UEFI media through QEMU's USB mass-storage controller.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
IMAGE="$OUT/noqerios-uefi-usb.img"
[[ -s "$IMAGE" ]] || { echo "Missing removable GPT image. Run bash build.sh --uefi" >&2; exit 2; }

CODE=""
VARS=""
for path in /home/antigravity/local-root/usr/share/OVMF/OVMF_CODE_4M.fd /home/antigravity/local-root/usr/share/OVMF/OVMF_CODE.fd; do
    if [[ -f "$path" ]]; then CODE="$path"; break; fi
done
for path in /home/antigravity/local-root/usr/share/OVMF/OVMF_VARS_4M.fd /home/antigravity/local-root/usr/share/OVMF/OVMF_VARS.fd; do
    if [[ -f "$path" ]]; then VARS="$path"; break; fi
done
[[ -n "$CODE" && -n "$VARS" ]] || { echo "Missing OVMF firmware" >&2; exit 2; }
cp "$VARS" "$OUT/uefi-usb-vars.fd"
LOG="$OUT/uefi-usb-serial.log"
DEBUG="$OUT/uefi-usb-debug.log"
: >"$LOG"
: >"$DEBUG"
set +e
timeout 30s qemu-system-x86_64 \
    -machine q35 -m 256M \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="$OUT/uefi-usb-vars.fd" \
    -device qemu-xhci,id=xhci \
    -drive if=none,id=usbboot,format=raw,file="$IMAGE" \
    -device usb-storage,bus=xhci.0,drive=usbboot,bootindex=1 \
    -serial file:"$LOG" \
    -debugcon file:"$DEBUG" -global isa-debugcon.iobase=0xe9 \
    -display none -no-reboot -no-shutdown >/dev/null 2>&1
result=$?
set -e
if [[ $result -ne 0 && $result -ne 124 ]] || \
   ! grep -q 'NoqeriOS UEFI: ExitBootServices OK' "$DEBUG" || \
   ! grep -q 'NoqeriOS serial terminal ready' "$LOG"; then
    echo "UEFI USB GPT boot smoke test failed ($result):" >&2
    cat "$DEBUG" "$LOG" >&2
    exit 1
fi
echo "PASS: GPT removable UEFI image booted via emulated USB xHCI and reached Noqeri serial terminal"
