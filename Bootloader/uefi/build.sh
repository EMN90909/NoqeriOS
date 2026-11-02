#!/usr/bin/env bash
# Build an original NoqeriOS UEFI x86-64 PE/COFF loader using gnu-efi.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build"
UEFI_OUT="$OUT/uefi"
mkdir -p "$UEFI_OUT"

for tool in gcc ld objcopy mformat mmd mcopy; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (install gcc binutils gnu-efi mtools)" >&2; exit 3; }
done
test -f "$ROOT/build/kernel.elf" || { echo "Build kernel.elf first with build.sh --uefi" >&2; exit 4; }

EFI_CRT=""
for dir in /usr/lib /usr/lib64 /usr/lib/gnuefi /usr/lib/x86_64-linux-gnu; do
  if [[ -f "$dir/crt0-efi-x86_64.o" && -f "$dir/elf_x86_64_efi.lds" ]]; then
    EFI_CRT="$dir"
    break
  fi
done
[[ -n "$EFI_CRT" ]] || { echo "GNU-EFI CRT/linker script missing (install gnu-efi)" >&2; exit 3; }

gcc -std=gnu11 -O2 -fpic -ffreestanding -fshort-wchar \
  -fno-stack-protector -fno-stack-check -fno-builtin -mno-red-zone \
  -DGNU_EFI_USE_MS_ABI -Wall -Wextra \
  -I/usr/include/efi -I/usr/include/efi/x86_64 \
  -c "$ROOT/Bootloader/uefi/loader.c" -o "$UEFI_OUT/loader.o"

gcc -std=gnu11 -O2 -fpic -ffreestanding -fshort-wchar \
  -fno-stack-protector -fno-stack-check -fno-builtin -mno-red-zone \
  -DGNU_EFI_USE_MS_ABI -Wall -Wextra \
  -I/usr/include/efi -I/usr/include/efi/x86_64 \
  -c "$ROOT/Bootloader/uefi/boot_menu.c" -o "$UEFI_OUT/boot_menu.o"

ld -nostdlib -znocombreloc -shared -Bsymbolic \
  -T "$EFI_CRT/elf_x86_64_efi.lds" \
  "$EFI_CRT/crt0-efi-x86_64.o" "$UEFI_OUT/loader.o" "$UEFI_OUT/boot_menu.o" \
  -L "$EFI_CRT" -o "$UEFI_OUT/loader.so" \
  -lgnuefi -lefi "$(gcc -print-libgcc-file-name)"

objcopy -j .text -j .sdata -j .data -j .rodata -j .dynamic \
  -j .dynsym -j .rel -j .rela -j .reloc -j .rela.* \
  --target=efi-app-x86_64 --subsystem=10 \
  "$UEFI_OUT/loader.so" "$UEFI_OUT/BOOTX64.EFI"
test -s "$UEFI_OUT/BOOTX64.EFI"

# A FAT ESP is compatible with UEFI optical emulation and disk firmware.
ESP="$UEFI_OUT/esp.img"
truncate -s 32M "$ESP"
mformat -i "$ESP" -T 65536 -h 64 -s 32 -n 32 ::
mmd -i "$ESP" ::/EFI ::/EFI/BOOT
mcopy -i "$ESP" "$UEFI_OUT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP" "$OUT/kernel.elf" ::/EFI/BOOT/KERNEL.ELF

echo "NoqeriOS custom UEFI loader: $UEFI_OUT/BOOTX64.EFI"
echo "NoqeriOS UEFI FAT boot image: $ESP"
