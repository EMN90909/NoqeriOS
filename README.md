# NoqeriOS

NoqeriOS is a standalone x86-64 operating-system project built around the Noqeri language and its freestanding native target.

## Current milestone

The current bootstrap is deliberately small but real:

- boot an x86-64 kernel image under QEMU through a Multiboot2-capable loader;
- enter an exported `kernel_main` implemented in Noqeri;
- initialize COM1 serial debugging;
- discover Multiboot2 physical memory and allocate bootstrap pages;
- install an IDT and PIT timer;
- perform a ring-3 transition and software-syscall probe;
- initialize a simple 32-bit framebuffer abstraction when boot information supplies one.

NoqeriOS is not a Linux kernel port. It owns its kernel and native ABI. Linux ELF support, Vulkan, and Wine/Proton integration are compatibility/platform layers to be built above the native kernel and userspace.

## Layout

```text
Arch/x86_64/     bootstrap, CPU, interrupt and userspace transition code
Kernel/          Noqeri kernel entry and core memory services
Drivers/         Noqeri device drivers
Tests/           QEMU smoke tests
build.sh         kernel build helper
grub.cfg         Multiboot2 boot menu
```

## Noqeri compiler dependency

Build Noqeri separately, then point this project at the compiler:

```sh
git clone https://github.com/EMN90909/Noqeri.git ../Noqeri
(cd ../Noqeri && ./scripts/build.sh)
NOQERI=../Noqeri/build/noqeri ./build.sh
```

The build uses GNU binutils, GRUB tooling, and QEMU for the current bootstrap path.
