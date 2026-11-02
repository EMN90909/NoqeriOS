# Lenovo G500 physical UEFI boot verification

This is a **diagnostic build**, not proof of physical-hardware compatibility.
It does not install to your internal drive, flash firmware or write runtime
logs to any disk. It tests the firmware's real CPU-mapped GOP framebuffer
before the Noqeri kernel starts, then boots the normal Noqeri kernel.

## Build the diagnostic image

From the NoqeriOS repository root:

```sh
NOQERIOS_LENOVO_VERIFY=1 bash build.sh --uefi-bootstrap
python3 Tests/lenovo-g500-smoke.py
sha256sum build/noqerios-uefi-usb.img
```

QEMU + OVMF must be installed for the smoke test. A successful smoke test
**does not** imply the Lenovo Intel display works.

Or visit the latest **successful** GitHub Actions `NoqeriOS kernel`
run on `main`; download the separate
`noqerios-lenovo-g500-verify` artifact containing
`noqerios-lenovo-g500-verify.img` and `SHA256SUMS`. This is NOT the
normal `noqerios-bios-uefi-iso-and-usb` image.

Verify the downloaded file against SHA256SUMS:

```sh
cd <unpacked-diagnostic-artifact-directory>
sha256sum -c SHA256SUMS
```

## Physical Lenovo G500 boot

1. Save work, use an **expendable USB flash drive**, and ensure Windows/Linux
   data on your internal HDD/SSD has a backup.
2. Before any USB write, identify the device with
   `lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS`. **Never assume `sdb`**
   or type the example placeholder `/dev/sdX` into a flash command.
   An incorrect device destroys files. Do not overwrite a partition.
3. Flash the verified **whole-device** diagnostic image to the **confirmed
   removable USB device**, following your trusted flashing tool's safeguards.
   Safely eject it.
4. Open Lenovo's **one-time boot menu** (commonly F12; device firmware varies).
   Choose the USB's UEFI entry. Do not format the internal disk. Secure Boot
   must be disabled or the unsigned EFI binary will be refused.
5. Photograph **each screen** and note its sequence.

## What each visible stage means

| Stage | Expected display | If it fails |
|---|---|---|
| 1: UEFI text | `LENOVO VERIFY` message for about 1.5 s | USB, firmware entry, ELF load or GOP discovery |
| 2: pre-kernel GOP | Eight vertical bars, left to right: **red green blue cyan magenta yellow white black**, with three straight white horizontal rules for about 6 s | If striped/garbled already, investigate firmware GOP scanout / physical video memory / pixel layout before blaming the Noqeri GUI |
| 3: kernel framebuffer | Early small boot marker, followed by the kernel desktop | If Stage 2 is clean but Stage 3 is bad, focus on page mapping, ExitBootServices handoff, framebuffer aliasing and GUI drawing |
| 4: desktop | Dark NoqeriOS GUI and start tiles, not distorted horizontal noise | If stuck before GUI, investigate firmware memory map, PMM, interrupt/timer initialization and serial diagnostics |
| 5: keyboard | Try PS/2 keyboard input only if available; USB HID is not implemented | Keyboard failure is not evidence of a graphics failure |

If Stage 1 appears but Stage 2 does not, the mode may have been rejected.
If Stage 2 appears and the kernel never draws, the problem is after
the diagnostic renderer. If Stage 2 and GUI are both distorted, the issue
may be shared GOP framebuffer format, physical scanout, or hardware.

## Record the actual result

- Machine: Lenovo G500 (confirm BIOS/UEFI version in Setup)
- Boot type: UEFI USB
- Stage 1 text appeared: yes/no
- Stage 2 color bars and three horizontal lines: clean / distorted / absent
- Stage 3 kernel boot marker: yes/no
- Stage 4 GUI: clean / distorted / absent
- Stage 5 keyboard: works / unavailable / not tested
- Attach photographs at Stage 2 and Stage 4.

**Limits:** The kernel lacks reliable USB HID, a production disk driver and
general physical Intel GPU drivers. A virtual QEMU success is only a
regression check. Keep the NoqeriOS image on an expendable USB and do not
install it to the daily-use internal drive.
