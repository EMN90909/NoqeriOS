# Zig bootloader migration (experimental)

The kernel stays in **Noqeri**. The bootloader migrates to **Zig** incrementally to avoid regressing the BIOS/UEFI boot path.

## Implemented in this branch

- `elf.zig`: freestanding Zig ELF64 header and segment validation.
- `NOQERIOS_ZIG_BOOT=1`: the UEFI build compiles and links the Zig validator as an x86-64 freestanding object.
- The UEFI loader invokes Zig validation before allocating or loading ELF segments. Existing checks remain in place for defense in depth.
- Existing BIOS stage0/stage1 and Noqeri handoff remain unchanged.

## Build (UEFI, experimental)

Install Zig (target 0.15.2), the existing kernel dependencies, GNU-EFI and mtools.

```sh
zig test Bootloader/zig/elf.zig
NOQERIOS_ZIG_BOOT=1 bash build.sh --uefi
bash Tests/uefi-smoke.sh
```

This builds Zig into `BOOTX64.EFI`. The final EFI file is not yet a wholly Zig-authored loader, because the firmware-protocol adapter, memory map, GOP paging, and boot menu are still implemented in C. BIOS real-mode stage0 remains assembly.

## Next migration gates

1. Port UEFI filesystem loading, memory map, graphics handoff and ExitBootServices to Zig while preserving the Multiboot2 handoff structure.
2. Port the UEFI boot menu and alternate-OS chainloading.
3. Move BIOS protected-mode ELF loading to Zig; retain a tiny real-mode/CPU-transition assembly shim.
4. Prove QEMU OVMF and BIOS boots, boot-menu chainloading, RAM variants, and actual removable-media boot before retiring C/assembly stages.

**Safety**: Do not flash this experimental branch onto a working system disk. Prefer QEMU tests first. As of this change, the Zig path has not been run through a compiler or QEMU in this session.
