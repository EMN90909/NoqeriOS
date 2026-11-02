# NoqeriOS UEFI dual-boot manager

NoqeriOS includes a **read-only UEFI boot menu** in its own
`BOOTX64.EFI`, before the Noqeri kernel starts or exits UEFI Boot Services.

## What it detects

The manager enumerates EFI Simple File System volumes visible to firmware,
including other EFI System Partitions when UEFI exposes them, and looks for
known x86-64 EFI bootloader filenames:

- Windows Boot Manager: `\\EFI\\Microsoft\\Boot\\bootmgfw.efi`
- Ubuntu: `\\EFI\\ubuntu\\shimx64.efi` or `grubx64.efi`
- Fedora: `\\EFI\\fedora\\shimx64.efi` or `grubx64.efi`
- Debian: `\\EFI\\debian\\shimx64.efi` or `grubx64.efi`
- openSUSE: `\\EFI\\opensuse\\shim.efi`
- systemd-boot: `\\EFI\\systemd\\systemd-bootx64.efi`
- rEFInd: `\\EFI\\refind\\refind_x64.efi` or
  `\\EFI\\BOOT\\refind_x64.efi`

For Ubuntu/Fedora/Debian, if a shim exists the corresponding GRUB is
omitted to avoid duplicate menu entries.

## Boot menu behavior

If no known other EFI image exists, NoqeriOS boots normally with no delay.

When an alternative is found, the firmware text console offers:

```text
NoqeriOS Boot Manager (UEFI)
[0] NoqeriOS (default)
[1] Windows Boot Manager
[2] Ubuntu (shim)
...
Press 0-9 to choose. NoqeriOS starts in 5 seconds.
```

Press the indicated digit. The default boots NoqeriOS automatically
after five seconds. The boot manager uses UEFI `LoadImage` and
`StartImage` with a full device/file path, before `ExitBootServices`.
If an alternate application exits back to the firmware, NoqeriOS continues
booting. If image load fails (missing or invalid image, Secure Boot
policy, etc.), the manager prints an error and returns to NoqeriOS.

**There is no automatic resizing, formatting, writing to partitions,
editing NVRAM, BootOrder, BootNext or modifying Windows/Linux files.**
The manager never launches arbitrary files found on user disks. It only
presents a bounded list of recognized paths. It does not try to
chainload a fallback `\\EFI\\BOOT\\BOOTX64.EFI` (which might be
NoqeriOS itself and cause a loop).

## Limitations

- **UEFI x86-64 only.** The original BIOS loader is unaffected; legacy BIOS
  Windows/Linux bootloaders are not discovered.
- Booting other systems requires their real, working EFI applications
  and all the files they expect on their own volumes.
- Secure Boot signature enforcement remains controlled by the firmware.
  The NoqeriOS EFI application is currently unsigned.
- Devices hidden from firmware or encrypted before UEFI volume exposure
  cannot be enumerated.
- This recognizes a curated set of paths, not every distro, boot manager,
  or user-created NVRAM `Boot####` configuration.
- Menu input relies on a firmware-supported keyboard/console.
- No persistent default configuration yet; NoqeriOS remains the default.

## Test in QEMU

```sh
bash build.sh --uefi-bootstrap
python3 Tests/dualboot-uefi.py
```

The test builds a harmless alternate EFI application, places it on a
*virtual* FAT EFI system partition at the Windows EFI path, boots an isolated CI-only variant of the NoqeriOS UEFI image, invokes the\nsame chainloading routine directly, confirms the alternate EFI application\nexecuted, and verifies NoqeriOS can still boot after it returns. The release\nbuild retains normal keyboard selection; headless OVMF keyboard selection is\nnot established by this fixture. Cross-volume discovery is supported by the implementation but physical-drive coverage is not established by the same-ESP test. No host disk or Windows installation changes.

Do not flash or replace your existing EFI System Partition to experiment
with dual boot. Boot NoqeriOS from a separate USB drive using the firmware
one-time boot picker, and keep your existing OS boot entries intact.
