#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/native-boot"
mkdir -p "$OUT"
for tool in as ld python3; do command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }; done
as --32 "$ROOT/Bootloader/native/stage0.S" -o "$OUT/stage0.o"
ld -m elf_i386 -Ttext 0x7c00 --oformat binary -o "$OUT/stage0.bin" "$OUT/stage0.o"
as --32 "$ROOT/Bootloader/native/stage1.S" -o "$OUT/stage1.o"
ld -m elf_i386 -Ttext 0x8000 --oformat binary -o "$OUT/stage1.bin" "$OUT/stage1.o"
python3 "$ROOT/Bootloader/native/image.py" "$OUT/stage0.bin" "$OUT/stage1.bin" "$OUT/noqerios-native.img"
echo "Custom BIOS stage0/stage1 image: $OUT/noqerios-native.img"
