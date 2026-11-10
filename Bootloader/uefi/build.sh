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
for dir in "${GNU_EFI_DIR:-/nonexistent}" /home/antigravity/local-root/usr/lib /usr/lib /usr/lib64 /usr/lib/gnuefi /usr/lib/x86_64-linux-gnu; do
  if [[ -f "$dir/crt0-efi-x86_64.o" && -f "$dir/elf_x86_64_efi.lds" ]]; then
    EFI_CRT="$dir"
    break
  fi
done
[[ -n "$EFI_CRT" ]] || { echo "GNU-EFI CRT/linker script missing (install gnu-efi)" >&2; exit 3; }

EFI_INC_FLAGS=()
for inc in "${GNU_EFI_DIR:-/nonexistent}/include" /home/antigravity/local-root/usr/include /usr/include; do
  if [[ -d "$inc/efi" ]]; then
    EFI_INC_FLAGS+=("-I$inc/efi" "-I$inc/efi/x86_64")
    break
  fi
done

ZIG_BOOT_OBJECTS=()
if [[ "${NOQERIOS_ZIG_BOOT:-0}" == 1 ]]; then
  command -v zig >/dev/null || { echo "Zig is required for NOQERIOS_ZIG_BOOT=1" >&2; exit 3; }
  zig build-obj "$ROOT/Bootloader/zig/elf.zig" -target x86_64-freestanding -O ReleaseSmall -fPIC -mno-red-zone -fno-stack-protector \
    -femit-bin="$UEFI_OUT/zig_elf.o"
  ZIG_BOOT_OBJECTS+=("$UEFI_OUT/zig_elf.o")
fi

LOADER_DEFINES=()
# Hardware debug only: default is to preserve the firmware's existing GOP
# scanout. Explicitly opt into SetMode(current) for A/B diagnostics.
if [[ "${NOQERIOS_GOP_REINIT:-0}" == 1 ]]; then
  LOADER_DEFINES+=(-DNOQERIOS_GOP_REINIT)
  echo "Diagnostic: explicitly reinitialize current GOP mode"
fi
if [[ "${NOQERIOS_ZIG_BOOT:-0}" == 1 ]]; then LOADER_DEFINES+=(-DNOQERIOS_ZIG_BOOT); fi
if [[ "${NOQERIOS_LENOVO_VERIFY:-0}" == 1 ]]; then
  LOADER_DEFINES+=(-DNOQERIOS_LENOVO_VERIFY)
  echo "Building dedicated Lenovo G500 GOP verification loader"
fi
gcc -std=gnu11 -O2 -fpic -ffreestanding -fshort-wchar \
  -fno-stack-protector -fno-stack-check -fno-builtin -mno-red-zone \
  -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f \
  -DGNU_EFI_USE_MS_ABI -Wall -Wextra "${LOADER_DEFINES[@]}" \
  "${EFI_INC_FLAGS[@]}" \
  -c "$ROOT/Bootloader/uefi/loader.c" -o "$UEFI_OUT/loader.o"

BOOT_MENU_DEFINES=()
if [[ "${NOQERI_CI_CHAINLOAD:-0}" == 1 ]]; then
  BOOT_MENU_DEFINES+=(-DNOQERI_TEST_AUTO_CHAINLOAD)
fi
gcc -std=gnu11 -O2 -fpic -ffreestanding -fshort-wchar \
  -fno-stack-protector -fno-stack-check -fno-builtin -mno-red-zone \
  -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f \
  -DGNU_EFI_USE_MS_ABI -Wall -Wextra "${BOOT_MENU_DEFINES[@]}" \
  "${EFI_INC_FLAGS[@]}" \
  -c "$ROOT/Bootloader/uefi/boot_menu.c" -o "$UEFI_OUT/boot_menu.o"

ld -nostdlib -znocombreloc -shared -Bsymbolic \
  -T "$EFI_CRT/elf_x86_64_efi.lds" \
  "$EFI_CRT/crt0-efi-x86_64.o" "$UEFI_OUT/loader.o" "$UEFI_OUT/boot_menu.o" "${ZIG_BOOT_OBJECTS[@]}" \
  -L "$EFI_CRT" -o "$UEFI_OUT/loader.so" \
  -lgnuefi -lefi "$(gcc -print-libgcc-file-name)"

objcopy -j .text -j .sdata -j .data -j .rodata -j .dynamic \
  -j .dynsym -j .rel -j .rela -j .reloc -j .rela.* \
  --output-target=efi-app-x86_64 --subsystem=10 \
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
