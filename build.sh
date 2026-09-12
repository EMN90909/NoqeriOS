#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
BOOTSTRAP=0

case "${1:-}" in
    --bootstrap) BOOTSTRAP=1 ;;
    --no-bootstrap|"") BOOTSTRAP=0 ;;
    *) echo "usage: $0 [--bootstrap|--no-bootstrap]" >&2; exit 2 ;;
esac

on_error() {
    local rc=$?
    echo >&2
    echo "NoqeriOS build failed (exit $rc) at line ${BASH_LINENO[0]}." >&2
    echo "Command: ${BASH_COMMAND}" >&2
    echo "Build directory: $OUT" >&2
    exit "$rc"
}
trap on_error ERR

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "This script targets Linux or WSL. On Windows, run build.bat." >&2
    exit 2
fi

if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
    echo "NoqeriOS build host: WSL"
else
    echo "NoqeriOS build host: Linux"
fi

run_root() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "Need root privileges to install missing build tools, but sudo is unavailable." >&2
        return 1
    fi
}

required_tools=(cmake g++ as ld grub-file grub-mkrescue xorriso mformat git)
missing_tools=()
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done

if (( ${#missing_tools[@]} > 0 )); then
    if (( BOOTSTRAP == 0 )); then
        echo "Missing build tools: ${missing_tools[*]}" >&2
        echo "Re-run with --bootstrap to install them on Ubuntu/Debian/WSL." >&2
        exit 3
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "Automatic dependency installation currently supports apt-based Linux/WSL hosts." >&2
        exit 3
    fi
    echo "Installing missing build dependencies..."
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential cmake binutils grub-common grub-pc-bin xorriso mtools \
        qemu-system-x86 git ca-certificates
fi

mkdir -p "$OUT"

NOQERI_SRC=""
if [[ -n "${NOQERI:-}" && -x "${NOQERI}" ]]; then
    :
elif [[ -x "$ROOT/../Noqeri/build/noqeri" ]]; then
    NOQERI="$ROOT/../Noqeri/build/noqeri"
    NOQERI_SRC="$ROOT/../Noqeri"
elif [[ -x "$ROOT/.deps/Noqeri/build/noqeri" ]]; then
    NOQERI="$ROOT/.deps/Noqeri/build/noqeri"
    NOQERI_SRC="$ROOT/.deps/Noqeri"
else
    if [[ -d "$ROOT/../Noqeri/CMakeLists.txt" ]]; then
        NOQERI_SRC="$ROOT/../Noqeri"
    elif [[ -d "$ROOT/.deps/Noqeri/CMakeLists.txt" ]]; then
        NOQERI_SRC="$ROOT/.deps/Noqeri"
    elif (( BOOTSTRAP == 1 )); then
        echo "Noqeri compiler source not found; cloning current main..."
        rm -rf "$ROOT/.deps/Noqeri"
        mkdir -p "$ROOT/.deps"
        git clone --depth 1 https://github.com/EMN90909/Noqeri.git "$ROOT/.deps/Noqeri"
        NOQERI_SRC="$ROOT/.deps/Noqeri"
    else
        echo "Noqeri compiler not found." >&2
        echo "Set NOQERI=/path/to/noqeri or re-run with --bootstrap." >&2
        exit 4
    fi

    jobs=2
    if command -v nproc >/dev/null 2>&1; then jobs="$(nproc)"; fi
    echo "Building Noqeri compiler from $NOQERI_SRC"
    cmake -S "$NOQERI_SRC" -B "$NOQERI_SRC/build" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$NOQERI_SRC/build" --parallel "$jobs"
    NOQERI="$NOQERI_SRC/build/noqeri"
fi

if [[ ! -x "$NOQERI" ]]; then
    echo "Noqeri compiler was not produced at $NOQERI" >&2
    exit 4
fi

echo "Using $($NOQERI --version | head -n 1)"

"$NOQERI" check "$ROOT/Kernel/main.nqr" -O2
"$NOQERI" build "$ROOT/Kernel/main.nqr" "$OUT/kernel_noqeri.s" -O2

as --64 "$OUT/kernel_noqeri.s" -o "$OUT/kernel_noqeri.o"
as --64 "$ROOT/Arch/x86_64/entry.S" -o "$OUT/entry.o"
as --64 "$ROOT/Arch/x86_64/arch.S" -o "$OUT/arch.o"
as --64 "$ROOT/Arch/x86_64/interrupts.S" -o "$OUT/interrupts.o"
as --64 "$ROOT/Arch/x86_64/userspace.S" -o "$OUT/userspace.o"

ld -nostdlib -z max-page-size=0x1000 \
   -T "$ROOT/Arch/x86_64/linker.ld" \
   -o "$OUT/kernel.elf" \
   "$OUT/entry.o" "$OUT/arch.o" "$OUT/interrupts.o" "$OUT/userspace.o" "$OUT/kernel_noqeri.o"

grub-file --is-x86-multiboot2 "$OUT/kernel.elf"

ISO_ROOT="$OUT/iso-root"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"
cp "$OUT/kernel.elf" "$ISO_ROOT/boot/kernel.elf"
cp "$ROOT/grub.cfg" "$ISO_ROOT/boot/grub/grub.cfg"
rm -f "$OUT/noqerios.iso"
grub-mkrescue -o "$OUT/noqerios.iso" "$ISO_ROOT" >/dev/null

if [[ ! -s "$OUT/noqerios.iso" ]]; then
    echo "ISO creation reported success but build/noqerios.iso is missing or empty." >&2
    exit 5
fi

echo "NoqeriOS ISO built successfully: $OUT/noqerios.iso"
