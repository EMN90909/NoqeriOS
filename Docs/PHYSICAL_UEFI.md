# NoqeriOS UEFI and physical PC bring-up

## Scope

NoqeriOS is an **experimental** x86-64 OS, not yet a daily-driver PC OS.
The original BIOS loader is tested with QEMU SeaBIOS. The separate,
NoqeriOS-owned EFI application (`Bootloader/uefi/loader.c`) targets UEFI
x86-64 firmware and loads the Noqeri kernel's ELF64 from the EFI volume.
Neither boot path includes Limine or GRUB.

The UEFI kernel relies on a low identity map (first 1 GiB), reserved
bootstrap memory, and a synthesized Multiboot2-compatible memory map.
The EFI app must call `ExitBootServices` before handing off to Noqeri.
It preserves firmware-reserved regions in the allocator map; this does
**not** replace a full ACPI/IOMMU/higher-half-memory implementation.

## Linux build

```sh
bash build.sh --uefi-bootstrap
```

This should create `build/noqerios.iso` with BIOS and UEFI El Torito entries,
`build/uefi/BOOTX64.EFI`, `build/uefi/esp.img`, and
`build/noqerios-uefi-usb.img` with a GPT EFI System Partition.

The legacy BIOS-only build stays `bash build.sh --bootstrap`.

## Firmware emulator validation

```sh
bash Tests/uefi-smoke.sh
python3 -m unittest discover -s Tests -p 'test_uefi_usb.py'
```

An optional GOP-integration run requires a working video MMIO handoff:

```sh
NOQERIOS_REQUIRE_GOP=1 bash Tests/uefi-smoke.sh
bash Tests/bios-cpu-smoke.sh
```

UEFI firmware now writes a simple startup/error message to the firmware
screen before `ExitBootServices`. The kernel can receive a Multiboot2
32-bit RGB framebuffer tag, including a framebuffer mapped above 1 GiB
up to the 512 GiB identity-map limit. It draws a boot marker, **not**
a kernel text console, and unsupported GOP pixel formats remain serial-only.

A successful OVMF test verifies **virtual UEFI firmware** boot, not
physical-hardware functionality. Use the CI logs to confirm that the
kernel entry and terminal are reached, not only that the PE/COFF image
is executed.

## Real hardware compatibility boundaries

| Feature | Current status |
|---|---|
| x86-64 UEFI removable-media boot | Custom EFI loader and GPT image implemented; test on each firmware |
| Legacy BIOS | QEMU SeaBIOS smoke-tested |
| UEFI Secure Boot | **Not supported**: no trusted signature/enrollment |
| Real keyboard / USB HID | **Not implemented**; terminal uses COM1 |
| Laptop internal display | GOP RGB framebuffer handoff and boot mark where supported; **no text console yet** |
| NVMe / AHCI / USB storage | **Not implemented** as general native drivers |
| ACPI/APIC, SMP and broad hardware discovery | Incomplete |
| PCI / VirtIO devices | QEMU-tested; not universal hardware drivers |
| Network/Wi-Fi | Not implemented |
| Hardware protection/power management | Incomplete |

The interactive COM1 terminal may be inaccessible on most modern laptops
that lack a physical serial port. UEFI's preboot text screen does not
mean the kernel can draw text or accept USB keyboard input after
`ExitBootServices`.

## Testing on a spare machine

Only use expendable test hardware or a spare USB drive. Back up any
important files and **do not overwrite the machine's internal drive**.
Boot a USB device via the firmware's one-time boot menu, with UEFI
boot enabled and Secure Boot disabled. The test image is unsigned.

To identify USB disks on Linux: `lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS`.
Never assume a fixed `/dev/sdX` name. Confirm the actual removable
device and unmount its partitions before flashing. A mistake may
destroy data. The GPT image is intended for whole-device writing, not
writing to a partition.

Record the motherboard/laptop model, UEFI version, CPU, RAM, GPU,
storage controller, boot-screen messages, and serial debug output.
A hang, black screen, or unavailable serial terminal is **not** proof
of OS startup. Avoid loading the experimental kernel against important
disks until storage write operations, ACPI, and exception handling are
properly audited and tested.

## Next physical-hardware prerequisites

1. A real kernel GOP on-screen text console (boot-mark-only now), and
   framebuffer modes beyond supported 32-bit RGB.
2. USB xHCI + HID keyboards (plus PS/2 fallback where applicable).
3. ACPI MADT / IOAPIC / interrupt-mode setup and safe PCI enumeration.
4. Storage drivers (NVMe/AHCI/USB mass storage), with write safety.
5. Runtime fault handling, memory protection, and hardware regression
   tests across multiple machines.

## CPU and firmware architecture limits

The boot flow uses 16-bit real mode for the BIOS stages, 32-bit protected
mode for loading ELF64, and 64-bit long mode for the actual kernel. The
32-bit protected-mode stage **does not** make NoqeriOS run on 32-bit-only
CPUs. The BIOS loader detects and rejects CPUs lacking x86-64 long mode,
PAE, PSE or MSR. 32-bit UEFI firmware also is not supported because the
project only builds BOOTX64.EFI. See [Boot compatibility](BOOT_COMPATIBILITY.md)
for the exact matrix.
