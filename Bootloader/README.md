# NoqeriOS-owned bootloader

The default Linux build produces a BIOS-bootable ISO with **only NoqeriOS's
own first- and second-stage loader**. No GRUB or Limine code is used.

- `native/stage0.S`: 512-byte BIOS boot sector, INT 13h EDD/CHS reads.
- `native/stage1.S`: E820 discovery, A20, ELF64 segments and Multiboot2
  handoff; minimal x86 assembly required before Noqeri can execute.
- `native/image.py`: validates kernel ELF and constructs a 1.44 MiB boot
  floppy image for El Torito BIOS emulation.
- `handoff.noqeri`: checks the boot info passed to the Noqeri kernel.
- `uefi/loader.c`: current firmware adapter for file access, page mapping,
  GOP framebuffer and native Multiboot2 handoff.
- `zig/elf.zig`: freestanding Zig ELF64 validation core used in the opt-in
  UEFI build to reject malformed, overlapping and non-executable kernels.

From Linux (or Linux inside WSL):

```bash
bash build.sh --bootstrap
bash Tests/qemu-smoke.sh
```

The output is `build/noqerios.iso`; test interactively using:

```bash
qemu-system-x86_64 -m 256M -cdrom build/noqerios.iso -boot d -serial mon:stdio -display none
```

BIOS x86-64 and UEFI x86-64 are experimental targets. The default build
retains the existing firmware adapter; the Zig-enhanced UEFI path is selected
explicitly on a machine with Zig 0.15.2 installed:

```sh
zig test Bootloader/zig/elf.zig
NOQERIOS_ZIG_BOOT=1 bash build.sh --uefi
NOQERIOS_ZIG_BOOT=1 bash Tests/uefi-smoke.sh
```

Zig verifies the ELF64 image before the existing UEFI adapter loads it.
The boot menu, EFI protocol access and page-table handoff still use C.
This is a **staged migration**, not a completed pure-Zig EFI loader.
BIOS requires a real-mode/CPU bring-up assembly shim. No GRUB or Limine
dependency is introduced.

The framebuffer and boot splash are native Noqeri; see
[Docs/FRAMEBUFFER.md](../Docs/FRAMEBUFFER.md). Physical PC boot remains
uncertified until tested on the target machine.
