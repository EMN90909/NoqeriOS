#!/usr/bin/env bash
# Build freestanding BOOTX64.EFI from .noqeri source and a pure-assembly ABI shim.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="$ROOT/build"
UEFI_OUT="$OUT/uefi"
mkdir -p "$UEFI_OUT"
: "${NOQERI:?Set NOQERI to the UEFI-capable Noqeri compiler}"
for tool in clang lld-link mformat mmd mcopy python3; do
    command -v "$tool" >/dev/null || { echo "Missing $tool (install clang lld mtools python3)" >&2; exit 3; }
done
test -s "$OUT/kernel-uefi.elf" || { echo "Build kernel-uefi.elf before EFI loader" >&2; exit 4; }
"$NOQERI" targets | grep -q 'x86_64-unknown-uefi' || {
    echo "Noqeri compiler needs the x86_64-unknown-uefi target from the Noqeri compiler UEFI PR" >&2
    exit 4
}
"$NOQERI" check "$ROOT/Bootloader/uefi/noqeri/loader.noqeri" --unsafe --target=x86_64-unknown-uefi -O2
"$NOQERI" build "$ROOT/Bootloader/uefi/noqeri/loader.noqeri" "$UEFI_OUT/loader-noqeri.s" --unsafe --target=x86_64-unknown-uefi -O2

clang -target x86_64-pc-windows-msvc -c "$UEFI_OUT/loader-noqeri.s" -o "$UEFI_OUT/loader-noqeri.obj"
clang -target x86_64-pc-windows-msvc -c "$ROOT/Bootloader/uefi/noqeri/efi_bridge.S" -o "$UEFI_OUT/efi_bridge.obj"
lld-link /nologo /machine:x64 /nodefaultlib /subsystem:efi_application \
    /entry:efi_entry /include:efi_reloc_anchor /fixed:no /dynamicbase /nxcompat \
    /out:"$UEFI_OUT/BOOTX64.EFI" \
    "$UEFI_OUT/efi_bridge.obj" "$UEFI_OUT/loader-noqeri.obj"
python3 "$ROOT/Tests/uefi_noqeri_pe.py" "$UEFI_OUT/BOOTX64.EFI" "$OUT/kernel-uefi.elf"

ESP="$UEFI_OUT/esp.img"
truncate -s 32M "$ESP"
mformat -i "$ESP" -T 65536 -h 64 -s 32 -n 32 ::
mmd -i "$ESP" ::/EFI ::/EFI/BOOT
mcopy -i "$ESP" "$UEFI_OUT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP" "$OUT/kernel-uefi.elf" ::/EFI/BOOT/KERNEL.ELF
echo "Native Noqeri UEFI application: $UEFI_OUT/BOOTX64.EFI"
echo "Native Noqeri UEFI FAT image: $ESP"
