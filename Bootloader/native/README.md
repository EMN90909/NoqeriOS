# NoqeriOS native BIOS boot chain

The custom loader uses LBA0 for its stage0 boot sector, LBA1–32 for stage1,
and LBA33–1056 for the ELF64 kernel (maximum 512 KiB). The image is padded
to exactly 1.44 MiB for BIOS El Torito floppy emulation.

Stage0 reads stage1 via INT 13h extensions or CHS fallback. Stage1 obtains
an E820 physical memory map, enables A20, reads the kernel via EDD or CHS,
enters 32-bit protected mode, loads ELF64 PT_LOAD segments, and jumps to
the kernel's Multiboot2-compatible 32-bit entry. The architecture shim
switches to long mode and enters the Noqeri kernel.

Linux builds and tests:

```sh
bash build.sh --bootstrap
bash Tests/qemu-smoke.sh
```

Use `-serial mon:stdio` and `-display none` to interact with the COM1
terminal. Boot debugging is emitted to QEMU ISA port 0xe9.

**Limits:** legacy BIOS only, 1.44 MiB boot media, fixed layout, ELF64
without relocation, no EFI protocol, full ACPI discovery, filesystem boot
loader or graphical shell. The kernel's own VirtIO filesystem is separate.
A passing ISO creation is not proof of a passing QEMU kernel smoke test.
