# Noed: Windows compatibility for NoqeriOS

**Status: foundation only. Windows programs are NOT executable yet.**

Noed is a native NoqeriOS Windows application compatibility project. It
will target *Windows x86-64 user-mode PE32+* programs and provide selected
Win32 functionality without copying Microsoft's implementation.

## Implemented

The Noed module is `Kernel/noed.noqeri`. The kernel shell exposes:

```text
N:\> noed
N:\> noed inspect FILE.EXE
N:\> noed run FILE.EXE
```

It loads up to one 4 KiB page of PE metadata through the existing NoqFS
read-only VFS and validates the DOS/PE signature, AMD64 COFF machine,
PE32+ optional header, bounded section table, image size, subsystem and
raw/virtual section bounds. This rejects malformed, non-PE, non-x64,
non-application images, including UEFI and kernel drivers.

**Both commands currently inspect only. `noed run` must never jump
into a Windows entrypoint.** The shell explicitly reports that launching
is unavailable. It is not a working Windows compatibility runtime.

The QEMU integration test creates a deliberately non-executable x64
PE32+ metadata fixture (NoqFS file key 2), validates it through the
serial shell, verifies a plain-text file (key 1) is rejected, and
checks that `noed run` does not execute untrusted code.

## Actual .exe execution requirements

To run Windows applications, Noed must implement the following in order:

1. **Isolated native process loader:** allocate private user-mode memory,
   create a separate page table and guarded stack, copy PE sections with
   validated permissions, apply ASLR and PE relocations, and start at a
   protected ring-3 entrypoint. Kernel execution is never acceptable.
2. **PE imports and runtime:** a robust import resolver and Windows x64
   calling-convention bridge, TLS, thread-local state and PEB/TEB.
3. **Win32 API compatibility:** start with console apps and a deliberately
   small documented set of Kernel32 functions (console IO, process exit,
   memory allocation, file IO, environment and string helpers). Missing
   functions must fail predictably.
4. **Platform features:** exception dispatching (SEH), threads,
   synchronization, handles, dynamic library loading, process lifetime,
   security checks, and DLL search controls.
5. **Desktop integration:** Win32 window classes, USER32/GDI32 drawing,
   input events, filesystem path conversion and graphics surfaces.
6. **App compatibility testing:** a licensed, redistributable suite of
   simple x64 console programs, API conformance tests, crash isolation,
   resource quotas and fuzz testing.

Many modern Windows applications additionally depend on .NET, COM,
DirectX, installers and services. Running arbitrary Windows programs
requires a far larger implementation; there is no automatic guarantee
of Wine-like compatibility.

## Scope and security

- Noed is not a virtual machine or Windows installation.
- It never requires Windows product keys to inspect PE metadata.
- 32-bit x86 applications and Windows ARM applications are not supported.
- No executable code from a NoqFS file currently runs in NoqeriOS.
- Do not mount untrusted Windows volumes writable until NoqFS and the VFS
  have robust, tested read/write and partition support.
- There is no Microsoft branding, and the UI stays monochrome grey.

## Developer test

```sh
bash Tests/qemu-smoke.sh
python3 Tests/terminal-interaction.py --memory 256M
```

Inspect the latest GitHub Actions status before treating a change as
verified; passing PE recognition is **not** evidence that Win32 apps run.
