# NoqeriOS hybrid CPU / GPU compositor

## Render paths

**CPU path, always available with a compatible 32-bit GOP framebuffer:**
The Noqeri software compositor uses native 32-bit RGB pixels, alpha blending,
clipping and 4×4 coverage antialiasing on rounded window corners. The
Windows-style desktop and File Explorer are rendered from the same retained
UI state. CPU-side drawing does not require GPU drivers.

**Virtual GPU scanout path (experimental):**
NoqeriOS detects VirtIO GPU (PCI vendor 0x1AF4 / device 0x1050), negotiates
the modern device, and queries its display configuration using its control
virtqueue. The new `Drivers/virtio_gpu_display.noqeri` driver can create a
VirtIO-GPU 2D resource, attach contiguous pinned physical memory, set the
scanout, transfer CPU-rasterized pixel data to the GPU and flush the resource
to display. The CPU draws into that backing image; the GPU transports and
presents it.

GPU mode is opt-in at runtime only if the virtual GPU responds correctly
and there is a low-memory contiguous framebuffer. Failed creation, transfer
or flush must return to the original GOP framebuffer. The BIOS serial-only
fallback is unchanged.

**This is not hardware GPU-accelerated rasterization.** VirtIO GPU's
unaccelerated 2D protocol still relies on CPU rendering of pixels. True
shader-accelerated drawing requires 3D command submission (such as Virgl)
or dedicated physical Intel/AMD/NVIDIA display drivers, resource and fence
management, memory ownership, and isolation. A GOP framebuffer alone is
not a GPU driver.

## Verification

```bash
bash build.sh --uefi-bootstrap
python3 Tests/gui-smoke.py
python3 Tests/gpu-smoke.py
```

`gui-smoke.py` captures real QEMU screenshots and checks keyboard-triggered
frame changes. `gpu-smoke.py` runs OVMF with `virtio-gpu-pci` and requires
the kernel to report a successful GPU control-queue handshake, 2D scanout and
DMA presentation, and serial terminal boot. The CI workflow gates these
tests. Read the result of the **latest** CI run rather than assuming the
new VirtIO scanout works on all GPU models.

## Display quality and current limits

- Native framebuffer resolution is taken from the validated UEFI GOP mode.
- RGB channel-order conversion and buffer bounds checking are performed in
  the software compositor.
- Rounded panel edges use subpixel alpha coverage. Other shapes and text
  remain bitmap-based.
- There is no shader pipeline, GPU blurring, smooth animation scheduler,
  DPI scaling or full Unicode/scalable text engine.
- Full-frame GPU transfers are used. Dirty rectangle updates and
  asynchronous double/triple buffering are still future work.
- Physical GPU drivers are not implemented. VirtIO GPU is a virtual GPU
  protocol primarily intended for QEMU/virtual-machine environments.

## Architecture

```text
Kernel/gui.noqeri
  window layout, Explorer, redraw/focus
        |
Kernel/compositor.noqeri
  CPU blending, pixel coverage
        |
        +--> GOP/MB2 framebuffer (CPU fallback)
        |
        +--> DMA backing image (CPU rasterized)
                 |
         Drivers/virtio_gpu_display.noqeri
          VirtIO 2D resource / transfer / flush
                 |
            Virtual GPU scanout
```

The implementation deliberately prioritizes predictable CPU rendering,
explicit GPU negotiation, and a safe fallback over mislabeling a BIOS/UEFI
framebuffer write as GPU acceleration.
