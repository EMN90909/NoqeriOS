# NoqeriOS

NoqeriOS is a standalone x86-64 operating-system project built around the Noqeri language and its freestanding `x86_64-unknown-none` target.

## Current milestone

The kernel is moving toward a modular monolith: core services execute in kernel space, while architecture code, device drivers, filesystems, process management, and syscall services are kept behind explicit subsystem boundaries. The organization is inspired by mature hobby/research kernels such as ToaruOS/Misaka, but the implementation and ABI are native NoqeriOS code.

The current boot path can:

- boot an x86-64 Multiboot2 kernel under QEMU;
- enter an exported `kernel_main` implemented in Noqeri;
- initialize COM1 serial debugging and a 32-bit framebuffer;
- discover Multiboot2 physical memory and allocate bootstrap pages;
- enumerate PCI and negotiate modern VirtIO PCI transport;
- perform VirtIO RNG DMA and VirtIO block-sector reads;
- mount a bootstrap NoqFS volume through a VFS dispatch layer;
- open a NoqFS root entry and read file data through the VFS;
- initialize a kernel process model and round-robin ready queue;
- install an IDT and PIT timer;
- enter ring 3 and route the software-syscall gate into a Noqeri syscall dispatcher.

NoqeriOS is not a Linux kernel port. It owns its kernel and native ABI. Linux/POSIX compatibility, ELF application loading, graphics, networking, and richer userspace remain higher layers to build above the native kernel.

## Layout

```text
Arch/x86_64/       bootstrap, CPU, interrupt and ring-3 transition code
Kernel/
  main.nqr          architecture-neutral boot orchestration
  memory.nqr        bootstrap physical memory discovery/allocation
  process.nqr       kernel process model
  scheduler.nqr     round-robin ready queue
  syscall.nqr       native syscall dispatcher
  fs/
    types.nqr       VFS mount/node contracts
    vfs.nqr         filesystem dispatch facade
    noqfs.nqr       NoqFS mount, root lookup and file reads
Drivers/            PCI, serial, framebuffer and VirtIO drivers
Tests/              deterministic QEMU boot/integration tests
build.sh            Linux/WSL ISO builder
build.bat           Windows self-bootstrapping ISO builder
grub.cfg            Multiboot2 boot menu
```

## Build on Linux or WSL

The recommended one-command setup is:

```sh
bash ./build.sh --bootstrap
```

`--bootstrap` checks the build host, installs missing packages on apt-based Linux/WSL systems, clones and builds the current Noqeri compiler when necessary, compiles the Noqeri kernel, assembles the architecture sources, links the Multiboot2 ELF kernel, verifies it with `grub-file`, and produces:

```text
build/noqerios.iso
```

For an already configured machine, use:

```sh
bash ./build.sh --no-bootstrap
```

You can also provide an existing compiler explicitly:

```sh
NOQERI=/path/to/noqeri bash ./build.sh --no-bootstrap
```

The Noqeri compiler itself is built by CMake with the host C/C++ toolchain. GNU binutils and GRUB/xorriso then produce the freestanding kernel and ISO image.

## Build on Windows

Run:

```bat
build.bat
```

The batch launcher uses a WSL Linux toolchain so the Windows and Linux builds use the same GRUB/binutils ISO path. If WSL or an Ubuntu distribution is missing, it attempts to install the required Windows/WSL components. Once WSL is available it invokes `build.sh --bootstrap`, which installs the C/C++ compiler, CMake, binutils, GRUB, xorriso, mtools, QEMU and the other required Linux-side tools.

Build output is written to:

```text
build\noqerios.iso
```

Windows build diagnostics are retained in `build\windows-build.log`. If the batch build fails, it displays a Windows error dialog containing the last build messages and pauses the console instead of closing immediately. Some first-time WSL installations require a Windows reboot; in that case the dialog explains that setup must be completed before rerunning the batch file.

## Boot test

On Linux or WSL with QEMU installed:

```sh
bash Tests/qemu-smoke.sh
```

The smoke test creates a deterministic NoqFS disk, boots `build/noqerios.iso` in QEMU with modern VirtIO RNG and block devices, and requires serial milestones for memory, scheduling, PCI/VirtIO DMA, VFS file reads, interrupts, ring 3, and the Noqeri syscall dispatcher.

## Compiler baseline

NoqeriOS tracks the current Noqeri systems compiler. The modular-monolith work was started after validating Noqeri 1.5 (`1.5.0-ecosystem-foundation`) and its `x86_64-unknown-none` target against the existing QEMU boot path.
