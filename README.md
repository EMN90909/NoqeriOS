# NoqeriOS

NoqeriOS is a standalone x86-64 operating-system project built around the Noqeri language and its freestanding `x86_64-unknown-none` target.

## Current milestone

The kernel is moving toward a modular monolith: core services execute in kernel space, while architecture code, device drivers, filesystems, process management, and syscall services are kept behind explicit subsystem boundaries. The organization is inspired by mature hobby/research kernels such as ToaruOS/Misaka, but the implementation and ABI are native NoqeriOS code.

The boot path supports these experimental milestones, with some still awaiting successful full CI qualification:

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
  main.noqeri          architecture-neutral boot orchestration
  memory.noqeri        bootstrap physical memory discovery/allocation
  process.noqeri       kernel process model
  scheduler.noqeri     round-robin ready queue
  syscall.noqeri       native syscall dispatcher
  fs/
    types.noqeri       VFS mount/node contracts
    vfs.noqeri         filesystem dispatch facade
    noqfs.noqeri       NoqFS mount, root lookup and file reads
Drivers/            PCI, serial, framebuffer and VirtIO drivers
Tests/              deterministic QEMU boot/integration tests
build.sh            Linux/WSL ISO builder
build.bat           Windows self-bootstrapping ISO builder
Bootloader/native/  original BIOS stage0/stage1, ELF loader, image packager
```

## Build on Linux or WSL

The recommended one-command setup is:

```sh
bash ./build.sh --bootstrap
```

`--bootstrap` checks the build host, installs missing packages on apt-based Linux/WSL systems, clones and builds the current Noqeri compiler when necessary, compiles the Noqeri kernel, assembles the architecture sources, links the Multiboot2 ELF kernel, packages it with the original NoqeriOS BIOS bootloader (El Torito floppy emulation), and produces:

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

All kernel, driver, and architecture source files use the canonical `.noqeri` extension. `build.sh` checks and compiles `Kernel/main.noqeri` directly, including its imported modules. No source-copy or rename stage is required.

The Noqeri compiler itself is built by CMake with the host C/C++ toolchain. GNU binutils assemble the CPU-entry code and xorriso packages the custom BIOS loader as an ISO. The loader contains no GRUB or Limine dependency.

## Build on Windows

Run:

```bat
build.bat
```

The batch launcher uses a WSL Linux toolchain so the Windows and Linux builds use the same native BIOS/binutils ISO path. If WSL or an Ubuntu distribution is missing, it attempts to install the required Windows/WSL components. Once WSL is available it invokes `build.sh --bootstrap`, which installs the C/C++ compiler, CMake, binutils, xorriso, QEMU and the other required Linux-side tools.

Build output is written to:

```text
build\noqerios.iso
```

Windows build diagnostics are retained in `build\windows-build.log`. If the batch build fails, it displays a Windows error dialog containing the last build messages and pauses the console instead of closing immediately. Some first-time WSL installations require a Windows reboot; in that case the dialog explains that setup must be completed before rerunning the batch file.

## Boot test

Run the BIOS-only ISO interactively with a serial terminal:

```sh
bash build.sh --bootstrap
qemu-system-x86_64 -m 256M -cdrom build/noqerios.iso -boot d -serial mon:stdio -display none
```

The COM1 terminal uses single-letter commands: `h`, `i`, `m`, `p`, `c`, and `r`. The CI suite also sends each command to the running kernel and checks its response. UEFI is available experimentally with `bash build.sh --uefi-bootstrap`, producing a BIOS+UEFI optical ISO and `build/uefi/esp.img`. OVMF verification is required before using it on physical hardware. A graphical desktop is not yet supported.


On Linux or WSL with QEMU installed:

```sh
bash Tests/qemu-smoke.sh
```

The smoke test creates a deterministic NoqFS disk, boots `build/noqerios.iso` in QEMU with modern VirtIO RNG and block devices, and requires serial milestones for memory, scheduling, PCI/VirtIO DMA, VFS file reads, interrupts, ring 3, and the Noqeri syscall dispatcher. After that test, run `python3 Tests/terminal-interaction.py` to verify the COM1 terminal commands using real QEMU serial input.

## Compiler baseline

NoqeriOS tracks the current Noqeri systems compiler. The upstream Noqeri repository currently identifies its compiler as experimental version 0.1.4. On November 1, 2026 the native BIOS ISO passed QEMU smoke gates with 128 MB, 256 MB, and 768 MB RAM, including E820, PCI/VirtIO, VFS and serial terminal entry. New code must pass the same gates. UEFI now passes QEMU OVMF optical boot tests. This is not physical-hardware compatibility certification.

## Experimental custom x86-64 UEFI boot

The native UEFI loader is original NoqeriOS firmware adapter code in `Bootloader/uefi/loader.c`, compiled as `BOOTX64.EFI` using GNU-EFI. It loads the existing Noqeri kernel ELF, converts UEFI memory descriptors into Multiboot2 boot tags, creates an identity mapping and enters the Noqeri kernel through `uefi_kernel_entry`. The kernel remains authored in Noqeri, with small assembly/firmware adapters.

```bash
bash build.sh --uefi-bootstrap
bash Tests/uefi-smoke.sh
```

The resulting ISO contains BIOS and UEFI optical boot entries; the FAT image `build/uefi/esp.img` contains `EFI/BOOT/BOOTX64.EFI` and `EFI/BOOT/KERNEL.ELF`. UEFI Secure Boot will reject the unsigned loader unless disabled or signed with trusted keys. No physical-PC boot is certified without device-specific testing. USB booting from a raw ISO is not yet validated; use an appropriate EFI system partition when preparing removable media.


## Experimental UEFI and physical hardware

Linux can build a hybrid original BIOS + UEFI ISO and a removable-media
GPT/FAT EFI image using:

```sh
bash build.sh --uefi-bootstrap
```

The output files are `build/noqerios.iso` and
`build/noqerios-uefi-usb.img`. UEFI uses our own PE/COFF loader in
`Bootloader/uefi/` and the 64-bit Noqeri kernel entry; it does not
use Limine or GRUB. `Tests/uefi-smoke.sh` is the required OVMF test.

See [UEFI physical hardware compatibility](Docs/PHYSICAL_UEFI.md)
before experimenting on any real machine. Secure Boot, USB input,
modern display text output and general hardware drivers are **not yet
supported**, so OVMF boot success alone does not establish laptop or
desktop usability.

To verify the UEFI GPT removable-media image through virtual USB xHCI, run `bash Tests/uefi-usb-smoke.sh` after building with `--uefi`. Actual machine firmware, xHCI, NVMe, graphics and keyboard support still require device-specific validation. Never erase your system disk when preparing boot media.
