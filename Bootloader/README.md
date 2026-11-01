# NoqeriOS bootloader and handoff

The currently supported boot chain is **GRUB Multiboot2 → minimal x86 assembly entry → Noqeri kernel**. GRUB loads the ELF, provides the memory map and boot tags, and enters the 32-bit Multiboot2 entry point. `Arch/x86_64/entry.S` sets up paging and 64-bit mode. Noqeri boot validation lives in `handoff.noqeri`; the kernel entry validates boot metadata before using it.

This is a real bootloader integration, **not a standalone, fully Noqeri-written BIOS/UEFI bootloader**. Pre-long-mode CPU transitions and firmware interfaces cannot be replaced by an ordinary Noqeri function without a qualified freestanding loader backend and architecture entry adapter.

## Build and test

```sh
bash build.sh --bootstrap
bash Tests/qemu-smoke.sh
```

The generated ISO includes `/boot/grub/grub.cfg` and `/boot/kernel.elf`. The second command must pass before claiming this boots correctly. NoqeriOS is currently an experimental kernel, not a general-purpose production OS.
