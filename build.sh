#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"

if [[ -z "${NOQERI:-}" ]]; then
    if [[ -x "$ROOT/../Noqeri/build/noqeri" ]]; then
        NOQERI="$ROOT/../Noqeri/build/noqeri"
    elif [[ -x "$ROOT/.deps/Noqeri/build/noqeri" ]]; then
        NOQERI="$ROOT/.deps/Noqeri/build/noqeri"
    else
        NOQERI="$ROOT/../Noqeri/build/noqeri"
    fi
fi

mkdir -p "$OUT"

if [[ ! -x "$NOQERI" ]]; then
    echo "Noqeri compiler not found at $NOQERI" >&2
    echo "Build https://github.com/EMN90909/Noqeri and set NOQERI=/path/to/noqeri" >&2
    exit 1
fi

"$NOQERI" check "$ROOT/Kernel/main.nqr"
"$NOQERI" build "$ROOT/Kernel/main.nqr" "$OUT/kernel_noqeri.s"

as --64 "$OUT/kernel_noqeri.s" -o "$OUT/kernel_noqeri.o"
as --64 "$ROOT/Arch/x86_64/entry.S" -o "$OUT/entry.o"
as --64 "$ROOT/Arch/x86_64/arch.S" -o "$OUT/arch.o"
as --64 "$ROOT/Arch/x86_64/interrupts.S" -o "$OUT/interrupts.o"
as --64 "$ROOT/Arch/x86_64/userspace.S" -o "$OUT/userspace.o"

ld -nostdlib -z max-page-size=0x1000 \
   -T "$ROOT/Arch/x86_64/linker.ld" \
   -o "$OUT/kernel.elf" \
   "$OUT/entry.o" "$OUT/arch.o" "$OUT/interrupts.o" "$OUT/userspace.o" "$OUT/kernel_noqeri.o"

if command -v grub-file >/dev/null 2>&1; then
    grub-file --is-x86-multiboot2 "$OUT/kernel.elf"
fi

if command -v grub-mkrescue >/dev/null 2>&1; then
    ISO_ROOT="$OUT/iso-root"
    rm -rf "$ISO_ROOT"
    mkdir -p "$ISO_ROOT/boot/grub"
    cp "$OUT/kernel.elf" "$ISO_ROOT/boot/kernel.elf"
    cp "$ROOT/grub.cfg" "$ISO_ROOT/boot/grub/grub.cfg"
    grub-mkrescue -o "$OUT/noqerios.iso" "$ISO_ROOT" >/dev/null
    echo "built $OUT/noqerios.iso"
else
    echo "built $OUT/kernel.elf (install grub-mkrescue to produce an ISO)"
fi
