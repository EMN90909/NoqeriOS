# NoqeriOS-owned bootloader

The default Linux build produces a BIOS-bootable ISO with **only NoqeriOS's
own first- and second-stage loader**. No GRUB or Limine code is used.

- `native/stage0.S`: 512-byte BIOS boot sector, INT 13h EDD/CHS reads.
- `native/stage1.S`: E820 discovery, A20, ELF64 segments and Multiboot2
  handoff; minimal x86 assembly required before Noqeri can execute.
- `native/image.py`: validates kernel ELF and constructs a 1.44 MiB boot
  floppy image for El Torito BIOS emulation.
- `handoff.noqeri`: checks the boot info passed to the Noqeri kernel.

From Linux (or Linux inside WSL):

```bash
bash build.sh --bootstrap
bash Tests/qemu-smoke.sh
```

The output is `build/noqerios.iso`; test interactively using:

```bash
qemu-system-x86_64 -m 256M -cdrom build/noqerios.iso -boot d -serial mon:stdio -display none
```

BIOS x86-64 is supported. A native UEFI bootloader, full filesystem loading,
boot menu, SMP and higher-half Limine protocol are separate future projects.
The ordinary x86 processor bring-up code is assembly; the kernel and
interactive terminal are written in Noqeri.

## Opt-in Zig-enhanced UEFI loader

`Bootloader/zig/elf.zig` provides bounds-checked ELF64 validation before any UEFI segment allocation. Enable it with `NOQERIOS_ZIG_BOOT=1 bash build.sh --uefi`. The firmware adapter and boot-menu implementation remain in C, and the BIOS entry remains assembly. The CI UEFI job runs the Zig-enhanced loader in OVMF and requires a serial debug marker confirming the Zig code executed.
