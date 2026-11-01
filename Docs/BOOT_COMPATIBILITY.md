# NoqeriOS boot paths and x86 CPU compatibility

NoqeriOS currently contains **one ELF64 x86-64 kernel**. The word "16-bit"
in the BIOS boot process describes the real-mode *bootstrap*, not support
for an 8086/286 kernel. The word "32-bit" describes the protected-mode
ELF loader, not an IA-32 kernel. A CPU lacking x86-64 long mode cannot
execute the present kernel.

| CPU or firmware | Boot stage | Can run current kernel? | Validation |
|---|---|---|---|
| x86-64 with legacy BIOS/CSM | 16-bit BIOS stage0/stage1, 32-bit loader, 64-bit kernel | Yes | QEMU SeaBIOS ISO smoke tests |
| x86-64 with 64-bit UEFI | BOOTX64.EFI, 64-bit kernel | Yes | QEMU OVMF ISO and GPT USB tests |
| 32-bit-only x86 with BIOS | 16-bit BIOS stage and protected-mode loading, CPU capability gate | **No**: cleanly rejected | QEMU `-cpu qemu32` regression |
| 32-bit UEFI firmware (IA32) | Needs BOOTIA32.EFI | **No** | Not built |
| 16-bit 8086/286 CPU | Not a supported target | **No** | Not built |
| ARM / AArch64 / RISC-V | Separate architecture ports required | **No** | Not built |

## Requirements for an x86-64 boot

On the BIOS path the loader now checks that CPUID is available, that the CPU
advertises 64-bit long mode, and that it supports PAE, PSE and MSR. This
happens **before** entering protected mode and copying the ELF kernel.
On failure the firmware's BIOS text output shows a diagnostic and boot
does not attempt the kernel. UEFI's 64-bit execution environment already
requires an appropriate CPU/firmware pair.

## Real-hardware UEFI status

`bash build.sh --uefi-bootstrap` builds an original x64 EFI application,
a hybrid BIOS+UEFI ISO, and a GPT USB image with a FAT EFI system partition.
The EFI program reads `EFI/BOOT/KERNEL.ELF`, allocates fixed ELF load
addresses, synthesizes a Multiboot2-compatible memory map, locates GOP,
maps an RGB framebuffer if available, then calls `ExitBootServices`.

The GOP handoff is conditional. It supports 32-bit
`PixelRedGreenBlueReserved8BitPerColor` and
`PixelBlueGreenRedReserved8BitPerColor` formats, including a framebuffer
above the first 1 GiB, up to the 512 GiB bootstrap identity-map limit.
Unsupported formats remain serial-only. The kernel draws a small boot
marker; **there is not yet a kernel graphical text terminal or USB input**.
UEFI firmware text output is only available before `ExitBootServices`.

Firmware can still refuse the image if Secure Boot is enabled, the EFI
binary is unsigned, the fixed kernel load addresses are occupied, or
required legacy I/O facilities are absent. Successful OVMF boot is not
physical-PC certification.

## Emulator checks

```sh
bash build.sh --uefi-bootstrap
bash Tests/qemu-smoke.sh
bash Tests/bios-cpu-smoke.sh
NOQERIOS_REQUIRE_GOP=1 bash Tests/uefi-smoke.sh
bash Tests/uefi-usb-smoke.sh
```

The GOP test uses an emulated standard VGA device, proving only the
boot-information handoff and mapped MMIO access in that environment.

## What would be required for true 16-bit and 32-bit OS support?

A separate IA-32 kernel port (32-bit ABI, compiler backend, paging,
interrupts, drivers and tests) would allow 32-bit-only x86 CPUs. A true
8086/286-targeted kernel would require an entirely different 16-bit
execution and memory model. Neither is implied by the BIOS boot stages,
and neither is implemented here.
