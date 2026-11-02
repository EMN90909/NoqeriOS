#!/usr/bin/env bash
# Boot NoqeriOS UEFI ISO under OVMF. Select Noqeri or legacy GNU-EFI loader.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"
if [[ "${NOQERIOS_UEFI_LOADER:-legacy}" == noqeri ]]; then
    bash "$ROOT/build.sh" --uefi-noqeri
else
    bash "$ROOT/build.sh" --uefi
fi
LOG="$OUT/uefi-serial.log"
DEBUG="$OUT/uefi-boot-debug.log"
: >"$LOG"
: >"$DEBUG"
CODE=""
VARS=""
for p in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
    if [[ -f "$p" ]]; then CODE="$p"; break; fi
done
for p in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    if [[ -f "$p" ]]; then VARS="$p"; break; fi
done
[[ -n "$CODE" && -n "$VARS" ]] || { echo "OVMF firmware missing (install ovmf)" >&2; exit 3; }
cp "$VARS" "$OUT/uefi-vars-test.fd"
# Test both El Torito optical UEFI boot and the GPT removable disk image.
MEDIA_ARGS=(-cdrom "$OUT/noqerios.iso" -boot order=d)
if [[ "${NOQERIOS_UEFI_MEDIA:-iso}" == usb ]]; then
    test -s "$OUT/noqerios-uefi-usb.img"
    MEDIA_ARGS=(-drive "if=ide,format=raw,file=$OUT/noqerios-uefi-usb.img" -boot order=c)
elif [[ "${NOQERIOS_UEFI_MEDIA:-iso}" != iso ]]; then
    echo "NOQERIOS_UEFI_MEDIA must be iso or usb" >&2
    exit 2
fi
set +e
timeout 25s qemu-system-x86_64 \
    -machine q35 -vga std -m "${NOQERIOS_MEMORY:-256M}" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="$OUT/uefi-vars-test.fd" \
    "${MEDIA_ARGS[@]}" \
    -serial file:"$LOG" \
    -debugcon file:"$DEBUG" -global isa-debugcon.iobase=0xe9 \
    -display none -no-reboot -no-shutdown >/dev/null 2>&1
result=$?
set -e
if [[ $result -ne 124 && $result -ne 0 ]]; then
    echo "QEMU failed with exit $result" >&2
    cat "$DEBUG" "$LOG" >&2
    exit 1
fi
if ! grep -q 'NoqeriOS UEFI: ExitBootServices OK' "$DEBUG" || \
   ! grep -q 'NoqeriOS: entered 64-bit Noqeri kernel' "$LOG" || \
   ! grep -q 'NoqeriOS serial terminal ready' "$LOG"; then
    echo "UEFI did not reach NoqeriOS serial terminal:" >&2
    cat "$DEBUG" "$LOG" >&2
    exit 1
fi
# The framebuffer is optional on real machines. CI explicitly asks for
# a GOP handoff so graphics regressions cannot hide behind serial success.
if [[ "${NOQERIOS_REQUIRE_GOP:-0}" == 1 ]]; then
    [[ "${NOQERIOS_UEFI_LOADER:-legacy}" != noqeri ]] || { echo "Native Noqeri UEFI path is currently serial-only; GOP smoke belongs to the legacy path" >&2; exit 3; }
    if ! grep -q 'uefi: supported GOP RGB framebuffer found' "$DEBUG" || \
       ! grep -q 'NoqeriOS: early framebuffer boot marker displayed' "$LOG" || \
       ! grep -q 'NoqeriOS: 32-bit framebuffer discovered' "$LOG" || \
       ! grep -q 'NoqeriOS: framebuffer MMIO write succeeded' "$LOG" || \
       ! grep -q 'NoqeriOS: GUI compositor frame presented' "$LOG"; then
        echo "UEFI graphics framebuffer handoff failed:" >&2
        cat "$DEBUG" "$LOG" >&2
        exit 1
    fi
fi
echo "PASS: custom NoqeriOS UEFI bootloader reached kernel and terminal (${NOQERIOS_UEFI_MEDIA:-iso})"
