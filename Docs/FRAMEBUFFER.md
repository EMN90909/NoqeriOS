# Native Noqeri framebuffer

The graphics stack uses a **32-bit linear RGB framebuffer** advertised by
Multiboot2 tag 8. The UEFI loader supplies the tag from GOP; BIOS systems
without a supported framebuffer retain the serial terminal.

## Driver primitives

`Drivers/framebuffer.noqeri` owns the shared software drawing operations:

- `mb2_find_framebuffer(info)`: bounded, 8-byte-aligned tag discovery.
- `framebuffer_valid(tag)`: validates 32bpp direct RGB, supported channel
  masks, mapped framebuffer address, resolution and pitch.
- `framebuffer_pack_rgb(rgb, swapRedBlue)`: convert 0x00RRGGBB into the
  firmware's RGB or BGR layout.
- `framebuffer_fill_rect(tag, x, y, w, h, rgb)`: clipped and pitch-aware
  direct frame writes.
- `framebuffer_clear(tag, rgb)`: full-frame paint.
- `framebuffer_pixel(tag, x, y, rgb)`: bounds-checked individual pixel.
- `framebuffer_blit_rgb32(...)`: clipped software copy from a caller-owned
  RGB32 image buffer.
- `framebuffer_hline(...)` / `framebuffer_vline(...)`: clipped horizontal and vertical borders.
- `framebuffer_blit_argb32(...)`: alpha-composited 0xAARRGGBB sprites,
  icons and overlays; color channels are normalized for RGB and BGR modes.

The boot splash uses the shared MMIO rectangle draw; the desktop reuses the
shared RGB/BGR packing logic. The desktop may switch to a VirtIO GPU backing
buffer using its independent rectangle painter. No UEFI Boot
Services are called after the kernel handoff.

## Safety and constraints

- Only packed 32bpp RGB/BGR modes with 8-bit channels are accepted.
- A rectangle is clipped by subtraction before any pixel offset is computed.
- Row stride is derived from the firmware pitch, never assumed equal to width.
- The firmware bootloader must map the framebuffer into the bootstrap paging
  environment; a valid tag alone does not establish a mapping.
- Physical addresses above the bootloader's 512 GiB paging range are rejected.
- Graphics on physical PCs, USB keyboard input, GPU DMA, displays with other
  pixel formats and full userspace windowing remain separate work.

The driver also validates the complete `pitch × height` MMIO aperture,
alignment and the bootloader's 512 GiB identity-map boundary. A malformed
descriptor is rejected before touching video memory.

When `NOQERIOS_ZIG_BOOT=1` is enabled, the UEFI firmware adapter additionally
runs the independent Zig GOP contract validator before mapping the display.
The kernel falls back to serial output if graphics are unsupported.

## Verify

```sh
bash Tests/uefi-smoke.sh
python3 Tests/gui-smoke.py
```

The tests are most meaningful on the GitHub Actions runner, which installs
OVMF, QEMU, GNU-EFI, Noqeri, and the disk-image dependencies. A successful
OVMF/QEMU test does not certify compatibility with a physical Lenovo G500.
