# NoqeriOS physical boot, 250-CPU topology capacity, and graphical desktop

## Implemented and tested boundaries

This milestone builds on the existing **x86-64 UEFI** removable-media
loader. It ports the firmware GOP framebuffer handoff and pre-ELF-load
x86-64 capability guard from prior PR #4 onto the current main branch.

The UEFI loader now hands off a 32-bit GOP framebuffer as a Multiboot2
framebuffer tag and carries an ACPI v1/v2 RSDP tag from the firmware
configuration table. The paging adapter maps the GOP MMIO aperture before
`ExitBootServices`. Unsupported GOP formats remain serial-only.

The new CPU registry can hold **250 distinct logical processor APIC IDs**
and rejects duplicates or overflow. It parses bounded, checksummed
ACPI RSDT/XSDT and MADT tables, including legacy LAPIC entries and
32-bit x2APIC IDs, **only if those table addresses fall below the
bootstrap 1 GiB identity map**. If ACPI tables are not mapped or are
invalid, it retains a BSP-only fallback.

**250 CPU slots is not 250 running CPUs.** No INIT-SIPI or x2APIC
application-processor bring-up was included; the online count remains
one. The older experimental SMP PR #3 is not integrated into main, and
its original source uses obsolete `.nqr` paths. A production
250-processor kernel needs mapped ACPI tables, x2APIC AP startup,
per-CPU stacks/TSS/GS, per-CPU interrupt tables, NUMA-aware allocators,
scheduler run queues, shared-state synchronization and tests on multi-socket
hardware. The `cpu_capacity_self_test` verifies 250 unique entries and
overflow behavior, not hardware execution.

## Graphical desktop and input

`Kernel/gui.noqeri` provides an initial native software-composited
on-screen desktop in a 32-bit RGB GOP framebuffer. It draws background,
top bar, two overlapping window surfaces, selection state, text using
an embedded bitmap font and a bottom navigation dock. Focus changes
repaint the retained layers in foreground/background order.

Interact with an attached legacy PS/2 keyboard or QEMU emulated keyboard:

- **A**: focus the Welcome panel
- **S**: focus the System panel
- **Z or Enter**: activate/switch the focused panel

The same `a`, `s`, `z` commands can be issued over COM1 serial.
The GUI is optional: non-GOP BIOS machines still boot to the serial console.

This is a **single-process compositor prototype**, not a real window
server. It has no isolated application surfaces, GPU acceleration,
mouse/touch handling, USB xHCI/HID, Unicode fonts, accelerated virtual
memory mapping, double buffering, clipboard or task switching.

## Build and emulator validation

```sh
bash build.sh --uefi-bootstrap
NOQERIOS_REQUIRE_GOP=1 bash Tests/uefi-smoke.sh
python3 Tests/gui-smoke.py
bash Tests/bios-cpu-smoke.sh
```

The graphical regression captures actual QEMU VGA screenshots via the
monitor and checks that a PS/2 key changes the rendered frame. Serial
boot alone is insufficient. The firmware and framebuffer paths require
video hardware exposing a supported UEFI GOP linear frame buffer.

## Physical hardware cautions

The build creates `build/noqerios-uefi-usb.img`, an image that can be
tested on a spare x86-64 UEFI PC. **No physical machine was available for
testing here**, so successful OVMF boots do not imply device support.

Use a spare/removable drive, verify its real device path and back up
important data before flashing. Never assume `/dev/sdX`. Disable Secure
Boot to boot the unsigned EFI application. The kernel has no native
NVMe/AHCI persistence stack or USB HID driver, and many laptops cannot
interact with the GUI without a serial adapter or legacy PS/2 keyboard.
For now, avoid production data and untrusted networks.

## Noqeri compiler reference

The implementation follows the
[Noqeri language reference](https://github.com/EMN90909/Noqeri/blob/main/Doc/LANGUAGE_REFERENCE.md),
[freestanding target](https://github.com/EMN90909/Noqeri/blob/main/Doc/FREESTANDING.md),
and [ABI](https://github.com/EMN90909/Noqeri/blob/main/Doc/ABI.md).
GUI primitives, ACPI parsing and registry logic are written in `.noqeri`;
only firmware UEFI protocol adaptation and minimal CPU instructions use C
or assembly. Full native compiler portability and 250-core SMP still
require independent validation.
