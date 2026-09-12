# NoqeriOS x86-64 platform core

This milestone replaces the bootstrap PIC-only interrupt model with ACPI-discovered APIC topology and introduces actual multicore kernel-thread execution.

## Boot order

1. The PMM, VMM and heap from Milestone 1 must pass their boot-time tests.
2. The shared IDT is installed while interrupts are disabled.
3. Multiboot2 ACPI tags locate the RSDP; the XSDT/RSDT is checksummed and the MADT is parsed.
4. The BSP local APIC is enabled, both legacy PICs are masked, and the IOAPIC routes the PIT override GSI to vector 48.
5. A `SchedulerSystem` and one `CpuRunQueue` per MADT CPU are allocated from the PMM.
6. APs are started one at a time with INIT/SIPI. Each AP enters long mode through the low-memory trampoline, loads the shared CR3/IDT, creates its bootstrap and worker kernel threads, enables its LAPIC periodic timer and marks its run queue online.
7. Vector 48 saves the complete general-purpose register set, calls the Noqeri scheduler, switches to the returned saved stack and completes with `iretq`.

## Current invariants

- `main` is not updated until the 128 MiB, 256 MiB and 768 MiB QEMU matrix passes with four virtual CPUs.
- The PMM remains the owner of all AP stacks, thread records and kernel-thread stacks.
- AP startup is serialized so the current PMM does not receive concurrent bootstrap allocations.
- User mode still uses the existing ring-3 `int 0x80` regression path in this milestone. Hardware `SYSCALL/SYSRET`, isolated process address spaces and executable loading belong to the next dependency milestone.
- The temporary 4 GiB bootstrap identity map exists only to make conventional LAPIC, IOAPIC and PCI MMIO reachable before the VMM grows the permanent kernel direct map and cache-attribute policy.
- Assembly is restricted to architectural transitions, interrupt entry/exit, MSRs, AP startup and initial synthetic register frames; topology and scheduling policy are implemented in Noqeri.
