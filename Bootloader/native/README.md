# NoqeriOS custom BIOS kernel bootloader

This repository owns the BIOS boot sector, second-stage ELF loader and Noqeri boot-information validator. No Limine or GRUB binary is included in the custom raw disk image.

The BIOS boot sector reads stage1 from LBA 1. Stage1 queries BIOS E820, constructs a minimal Multiboot2 memory-map tag, uses INT 13h extended reads to load a fixed 512 KiB ELF64 region from LBA 33, enables A20, enters 32-bit protected mode, copies ELF PT_LOAD segments to physical addresses, zero-fills BSS and jumps to the original kernel's 32-bit Multiboot2 entry with EAX magic and EBX boot-info pointer. The kernel itself enters long mode and runs the Noqeri entry.

The loader intentionally has tight restrictions: BIOS x86 only, fixed image offsets, x86-64 executable ELF with 32-bit physical segment addresses, image <=512 KiB, no disk filesystem or general-purpose boot menu. UEFI, framebuffer mode negotiation, ACPI and Limine protocol parity are not implemented.

Build the existing kernel first with `bash build.sh --bootstrap`, then `bash Bootloader/native/build.sh`. Boot in QEMU using `qemu-system-x86_64 -drive format=raw,file=build/native-boot/noqerios-native.img -serial stdio -display none`.

**Do not treat these code paths as verified until compilation, ELF checking and the QEMU serial smoke test pass.** The legacy Limine ISO remains a fallback while custom boot verification is incomplete.
