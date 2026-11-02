#!/usr/bin/env bash
# Build the Noqeri source on Linux, link a freestanding x86-64 kernel,
# then package our own BIOS bootloader as an El Torito bootable ISO.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
BOOTSTRAP=0
UEFI=0
NATIVE_EFI=0
case "${1:-}" in
    --bootstrap|--native-bootstrap) BOOTSTRAP=1 ;;
    --uefi-bootstrap) BOOTSTRAP=1; UEFI=1 ;;
    --uefi-noqeri-bootstrap) BOOTSTRAP=1; UEFI=1; NATIVE_EFI=1 ;;
    --uefi) UEFI=1 ;;
    --uefi-noqeri) UEFI=1; NATIVE_EFI=1 ;;
    --native|--no-bootstrap|"") ;;
    *) echo "Usage: $0 [--bootstrap|--native|--native-bootstrap|--uefi|--uefi-bootstrap|--uefi-noqeri|--uefi-noqeri-bootstrap]" >&2; exit 2 ;;
esac
trap 'status=$?; echo "NoqeriOS Linux build failed (exit $status) near line $LINENO" >&2; exit "$status"' ERR
[[ "$(uname -s)" == Linux ]] || { echo "Requires Linux/WSL. On Windows run build.bat." >&2; exit 2; }

need=(git cmake g++ as ld nm xorriso python3)
if (( UEFI == 1 )); then
    need+=(mformat mmd mcopy)
    if (( NATIVE_EFI == 1 )); then need+=(clang lld-link); else need+=(gcc objcopy); fi
fi
missing=()
for tool in "${need[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
# GNU-EFI headers are not executables: detect them separately for --uefi-bootstrap.
if (( UEFI == 1 && NATIVE_EFI == 0 )) && [[ ! -f /usr/include/efi/efi.h ]]; then
    missing+=(gnu-efi)
fi
if (( ${#missing[@]} > 0 )); then
    if (( BOOTSTRAP != 1 )); then
        echo "Missing Linux tools: ${missing[*]}. Re-run with --bootstrap." >&2
        exit 3
    fi
    command -v apt-get >/dev/null || { echo "Automatic install requires apt-get." >&2; exit 3; }
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y git cmake g++ binutils xorriso python3 qemu-system-x86 gnu-efi mtools ovmf clang lld
    else
        sudo apt-get update
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git cmake g++ binutils xorriso python3 qemu-system-x86 gnu-efi mtools ovmf clang lld
    fi
fi
mkdir -p "$OUT"

if [[ -n "${NOQERI:-}" ]]; then
    [[ -x "$NOQERI" ]] || { echo "NOQERI does not point to an executable compiler." >&2; exit 4; }
elif [[ -x "$ROOT/../Noqeri/build/noqeri" ]]; then
    NOQERI="$ROOT/../Noqeri/build/noqeri"
elif [[ -x "$ROOT/.deps/Noqeri/build/noqeri" ]]; then
    NOQERI="$ROOT/.deps/Noqeri/build/noqeri"
else
    SRC=""
    if [[ -f "$ROOT/../Noqeri/CMakeLists.txt" ]]; then
        SRC="$ROOT/../Noqeri"
    elif [[ -f "$ROOT/.deps/Noqeri/CMakeLists.txt" ]]; then
        SRC="$ROOT/.deps/Noqeri"
    elif (( BOOTSTRAP == 1 )); then
        mkdir -p "$ROOT/.deps"
        git clone --depth 1 https://github.com/EMN90909/Noqeri.git "$ROOT/.deps/Noqeri"
        SRC="$ROOT/.deps/Noqeri"
    else
        echo "Noqeri compiler unavailable. Set NOQERI or use --bootstrap." >&2
        exit 4
    fi
    cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DNOQERI_GRAPHICS_PORTABLE_BUILD=ON -DBUILD_TESTING=OFF
    cmake --build "$SRC/build" --target noqeri --parallel "${NOQERI_BUILD_JOBS:-2}"
    NOQERI="$SRC/build/noqeri"
fi
[[ -x "$NOQERI" ]] || { echo "Noqeri compiler missing at $NOQERI" >&2; exit 4; }
echo "Compiling kernel with $("$NOQERI" --version | head -n 1)"
"$NOQERI" check "$ROOT/Kernel/main.noqeri" --unsafe -O2
"$NOQERI" build "$ROOT/Kernel/main.noqeri" "$OUT/kernel_noqeri.s" --unsafe -O2
[[ -s "$OUT/kernel_noqeri.s" ]] || { echo "Compiler emitted no assembly." >&2; exit 5; }

as --64 "$OUT/kernel_noqeri.s" -o "$OUT/kernel_noqeri.o"
for module in entry arch interrupts userspace freestanding; do
    as --64 "$ROOT/Arch/x86_64/$module.S" -o "$OUT/$module.o"
done
ld -nostdlib -z max-page-size=0x1000 -T "$ROOT/Arch/x86_64/linker.ld" \
    -o "$OUT/kernel.elf" "$OUT/entry.o" "$OUT/arch.o" \
    "$OUT/interrupts.o" "$OUT/userspace.o" "$OUT/freestanding.o" "$OUT/kernel_noqeri.o"
nm "$OUT/kernel.elf" | grep -Eq '[[:space:]]T[[:space:]]kernel_main$' || {
    echo "No exported kernel_main after linking." >&2
    exit 5
}
bash "$ROOT/Bootloader/native/build.sh"
ISO_ROOT="$OUT/iso-root"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot"
cp "$OUT/native-boot/noqerios-native.img" "$ISO_ROOT/boot/noqerios-native.img"
cp "$OUT/kernel.elf" "$ISO_ROOT/boot/kernel.elf"
if (( UEFI == 1 )); then
    if (( NATIVE_EFI == 1 )); then
        # BIOS and UEFI share object files but not the ELF entry ABI.
        ld -nostdlib -z max-page-size=0x1000 -T "$ROOT/Arch/x86_64/linker.ld" \
            -e uefi_kernel_entry -o "$OUT/kernel-uefi.elf" \
            "$OUT/entry.o" "$OUT/arch.o" "$OUT/interrupts.o" \
            "$OUT/userspace.o" "$OUT/freestanding.o" "$OUT/kernel_noqeri.o"
        export NOQERI
        bash "$ROOT/Bootloader/uefi/noqeri/build.sh"
    else
        bash "$ROOT/Bootloader/uefi/build.sh"
    fi
    python3 "$ROOT/Bootloader/uefi/make_usb.py" "$OUT/uefi/esp.img" "$OUT/noqerios-uefi-usb.img"
    mkdir -p "$ISO_ROOT/boot/uefi"
    cp "$OUT/uefi/esp.img" "$ISO_ROOT/boot/uefi/esp.img"
fi
# El Torito floppy emulation provides the standard 512-byte sector INT 13h
# interface used by our own stage0/stage1 BIOS loader. No GRUB or Limine.
if (( UEFI == 1 )); then
    xorriso -as mkisofs -R -J -V NOQERIOS \
        -b boot/noqerios-native.img -c boot/boot.cat \
        -eltorito-alt-boot -e boot/uefi/esp.img -no-emul-boot \
        -o "$OUT/noqerios.iso" "$ISO_ROOT"
else
    xorriso -as mkisofs -R -J -V NOQERIOS \
        -b boot/noqerios-native.img -c boot/boot.cat \
        -o "$OUT/noqerios.iso" "$ISO_ROOT"
fi
[[ -s "$OUT/noqerios.iso" ]] || { echo "ISO output is empty." >&2; exit 5; }
echo "NoqeriOS custom BIOS image: $OUT/native-boot/noqerios-native.img"
if (( UEFI == 1 )); then
    if (( NATIVE_EFI == 1 )); then
        echo "NoqeriOS BIOS + native Noqeri UEFI El Torito ISO: $OUT/noqerios.iso"
    else
        echo "NoqeriOS BIOS + UEFI El Torito ISO: $OUT/noqerios.iso"
    fi
    echo "NoqeriOS UEFI removable-media GPT image: $OUT/noqerios-uefi-usb.img"
else
    echo "NoqeriOS bootable BIOS ISO: $OUT/noqerios.iso"
fi
