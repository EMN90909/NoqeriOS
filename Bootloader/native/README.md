# NoqeriOS native bootloader (early development)

This is **original NoqeriOS bootloader code**. Unlike the separate Limine compatibility ISO, the custom BIOS image contains no Limine or GRUB code.

- `stage0.S`: a 512-byte BIOS boot sector, checks INT 13h extensions and loads 32 sectors at 0x8000.
- `stage1.S`: an independently loaded, observable second-stage entry.
- `image.py`: strict disk-image packaging.
- `build.sh`: build and assemble an independent raw BIOS disk image.

Build: `bash Bootloader/native/build.sh`.

Optional emulator check: `qemu-system-x86_64 -drive format=raw,file=build/native-boot/noqerios-native.img -display curses`.

**Not yet a kernel-booting loader.** Stage1 still needs a physical memory map (E820), A20 handling, storage/filesystem support, an ELF64 PT_LOAD loader, protected-mode handoff with a correct Multiboot2-compatible information structure, error paths, and automated QEMU serial assertions. UEFI remains a separate native implementation milestone.

Existing Limine ISO tooling is retained only as a compatibility/reference path until native handoff can demonstrably boot the full Noqeri kernel. Do not mistake this bootstrap milestone for Limine feature parity.
