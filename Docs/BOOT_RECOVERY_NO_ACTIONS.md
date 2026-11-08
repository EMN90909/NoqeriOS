# Local-only NoqeriOS boot + framebuffer verification

This guide deliberately uses **no GitHub Actions**. QEMU/OVMF tests are local and never write an internal system disk.

## What was corrected

- The old `build.sh` framebuffer command had an extra trailing backslash, which could prevent the Zig object and kernel from building.
- The UEFI loader now **preserves the active GOP scanout** by default rather than calling `SetMode` on an already-active laptop panel.
- C/Multiboot2 framebuffer descriptor offsets are checked at compile time against the 38-byte tag expected by Zig and Noqeri.
- The Noqeri memory-map parser checks total length, tag bounds and entry strides instead of advancing forever on invalid firmware metadata.
- Zig framebuffer unit tests include a 1366x768 RGB/BGR mode, valid pitch, invalid channel masks, and a framebuffer extending past the 512 GiB mapping limit.

These changes are plausible fixes for a failed build and corrupted GOP screen, **not proof of physical hardware success**.

## Requirements

Linux or WSL with Zig **0.15.2** installed and on PATH, the current Noqeri compiler, GNU-EFI, binutils, xorriso, QEMU, OVMF and mtools. Use `bash build.sh --bootstrap` to obtain the available apt-based build dependencies, but install Zig separately first. `NOQERI=/absolute/path/to/noqeri` selects an existing Noqeri compiler.

## Verification without GitHub Actions

```bash
# Compiler and framebuffer/ELF unit tests only
bash Tests/local-verify.sh --unit

# Full BIOS + UEFI ISO/USB boots and framebuffer screenshot checks in QEMU
bash Tests/local-verify.sh --full

# Additional pre-ExitBootServices GOP bars and post-handoff desktop checks
bash Tests/local-verify.sh --lenovo
```

**Do not claim the kernel boots until the full local suite passes.** The OVMF screenshot tests check actual pixels, not just that the UEFI application prints a message. OVMF success still does not certify a Lenovo G500 panel or Intel graphics firmware.

## Physical Lenovo G500 testing

Create the *separate* diagnostic image after the local QEMU suite passes:

```bash
NOQERIOS_ZIG_BOOT=1 NOQERIOS_LENOVO_VERIFY=1 bash build.sh --uefi
sha256sum build/noqerios-uefi-usb.img
```

Write **only** to a confirmed expendable removable USB drive, never the internal HDD/SSD. Secure Boot must be disabled for this unsigned EFI loader.

The boot display has multiple phases:

1. Firmware/UEFI text and menu.
2. Diagnostic vertical color bars and three horizontal white rules, rendered **before** `ExitBootServices` by the firmware loader.
3. Early kernel boot marker and the Zig-backed Noqeri splash.
4. Desktop compositor.

Interpret the results carefully:

- If phase 2 is already corrupted, troubleshoot firmware GOP format/mode/scanout and the physical display; Zig has not rendered anything yet.
- If phase 2 is clean but phases 3/4 corrupt, investigate UEFI paging, Multiboot2 framebuffer pitch/channel tags, cache attributes and the kernel renderer.
- If phases 2/3 are clean but only phase 4 is corrupt, investigate the desktop compositor's independent pixel-writing path.
- If the same lines appear in Windows or the BIOS setup screen, check the LCD panel/cable or hardware before blaming NoqeriOS.

You can perform an A/B test with the old explicit GOP reset path:

```bash
NOQERIOS_GOP_REINIT=1 NOQERIOS_ZIG_BOOT=1 NOQERIOS_LENOVO_VERIFY=1 bash build.sh --uefi
```

Leave `NOQERIOS_GOP_REINIT` **unset** for normal operation. The experiment changes the generated image, not the firmware settings. Do not install NoqeriOS onto your primary drive until a physical boot is proven stable.
