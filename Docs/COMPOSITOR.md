# NoqeriOS compositor and GPU bring-up

## What is implemented

NoqeriOS draws the desktop natively into a 32-bit UEFI GOP/Multiboot2
framebuffer. `Kernel/compositor.noqeri` now provides CPU-side RGB alpha
compositing and four-by-four subpixel coverage calculations for crisp,
anti-aliased window corners. `Kernel/gui.noqeri` uses these primitives for
window surfaces while keeping full-screen opaque fills on the fast path.
The native Noqeri UI retains the legacy BIOS serial-only fallback.

`Drivers/gpu.noqeri` probes the VirtIO 1.0 GPU PCI device (vendor
0x1AF4, device 0x1050) and checks modern VirtIO capabilities. **Detection
does not enable acceleration.** The compositor deliberately uses CPU GOP
drawing until the GPU backend passes queue, buffer, fence, resource and
frame-present tests. This is essential to avoid silently declaring a
CPU-rendered framebuffer to be GPU accelerated.

## GPU implementation requirements

A true GPU path needs a kernel-controlled virtual graphics transport.
For VirtIO GPU 2D, the standards-defined flow is:

1. Negotiate VirtIO GPU features, build the control virtqueue and validate
   descriptor, available and used ring behavior with strict timeouts.
2. Discover connected scanouts, supported dimensions and pixel formats.
3. Create 2D resources; attach accessible pinned DMA backing memory.
4. Bind a resource to a scanout.
5. Transfer changed rectangles into the host resource and flush them.
6. Wait for completion/fences, track failures, and retain a last-known-good
   CPU display path. Never access released or firmware-owned memory.

VirtIO GPU's *2D* scanout path is still CPU rasterization plus virtual GPU
presentation. Actual GPU-rasterized graphics requires a 3D pipeline, for
example Virgl with appropriate shaders, command submission and isolation.
Intel/AMD/NVIDIA hardware needs separate native kernel-mode DRM-equivalent
drivers and memory management. UEFI GOP is not such a driver.

For sharp visuals irrespective of GPU type, the next CPU compositor stages
are double-buffering, dirty-rectangle redraws, alpha surfaces, scalable fonts
with glyph anti-aliasing and correct DPI modes. Current bitmap text is 5x7
scaled 2x; it will not resemble Windows 11 typography until fonts improve.

## Tests

Build the existing hybrid ISO using `bash build.sh --uefi-bootstrap`.
Use `python3 Tests/gui-smoke.py` to verify the framebuffer changes after
keyboard navigation in QEMU. A passing GUI test proves display composition,
not GPU offload. GPU acceleration should be marked verified only after the
GPU-specific command submission and visual checks pass.

The current implementation must never advertise GPU rendering as active
because the backend is not implemented yet.
