# Limine boot integration

The official Limine v12 boot manager replaces GRUB. The configured entry uses
Limine's **Multiboot2 compatibility protocol**, retaining the current kernel
ABI and memory-map parser.

Boot chain: BIOS/UEFI -> Limine -> Multiboot2 x86 entry ->
Arch/x86_64/entry.S -> Kernel/main.noqeri.

Configuration: Bootloader/limine.conf.

To build: bash build.sh --bootstrap
To verify the kernel: bash Tests/qemu-smoke.sh

The builder creates a hybrid BIOS/UEFI ISO using Limine's upstream
boot binaries and xorriso. The bootloader executable is upstream Limine,
not a Noqeri reimplementation. The kernel and handoff validation are Noqeri.

Do not set protocol: limine yet: native Limine needs request/response
structures, HHDM-aware memory management and a 64-bit protocol entry.
A successfully generated ISO is not a confirmed QEMU boot.
