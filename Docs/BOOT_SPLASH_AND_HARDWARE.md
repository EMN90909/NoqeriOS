# Noqeri boot loading screen and hardware resource foundations

## Boot appearance

NoqeriOS now shows **Noqeri** above a horizontal orange progress bar on a
minimal charcoal background, prior to drawing the desktop. The bar is updated
by the native Noqeri kernel at completed milestones (memory, CPU topology,
PCI detection, network and interrupts, userspace and final GUI handoff).
The screen is drawn using the validated 32-bit GOP framebuffer, honoring
its actual pitch and RGB/BGR channel positions.

No timer-based fake percentage is used. A failed stage remains diagnostically
visible instead of disguising a boot problem. Legacy BIOS machines with no
supported 32-bit framebuffer retain the serial console boot path. The
pre-existing early-framebuffer boot marker test remains intact.

## Hardware compatibility and resource management

- This release targets **x86-64 UEFI and legacy BIOS** only, not ARM,
  mobile devices, 32-bit CPUs or all consumer PCs.
- Legacy PCI mechanism-1 enumeration now checks the per-slot multifunction
  bit before probing additional functions, reducing unnecessary configuration
  I/O on real devices. Driver initialization remains opt-in for recognized
  hardware, not guessed from device class alone.
- Memory discovery uses a conservative identity-mapped 1 GiB bootstrap
  aperture and a physical memory bitmap. The GOP framebuffer is reserved
  against allocator reuse. This is not yet high-memory direct mapping.
- CPU MADT discovery is a **topology inventory** only: the bootstrap
  processor runs the system. Multi-core SMP, ACPI IOAPIC/MSI routing,
  safe driver DMA, native Intel graphics, AHCI/NVMe, USB xHCI/HID, and
  modern Wi-Fi require separate implementations.
- Hardware capability absence must leave unrelated services alive, not
  claim that non-existent drivers can use devices.

## Validation

```sh
bash build.sh --uefi-bootstrap
NOQERIOS_REQUIRE_GOP=1 bash Tests/uefi-smoke.sh
python3 Tests/gui-smoke.py
```

GitHub Actions executes these along with BIOS and GPU smoke tests. OVMF/QEMU
success verifies the graphics handoff virtually. Test the Lenovo G500 and
other physical systems before claiming hardware compatibility.

Note: Boot progress is real milestone progress, **not** a reliable percentage
of elapsed boot time; some hardware stages take longer than others.
