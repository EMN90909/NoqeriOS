# NoqeriOS memory core

This directory contains the first native Noqeri memory-management layer that replaces the bootstrap bump allocator as the kernel's source of truth.

## Physical memory

`pmm.nqr` owns frame state from the complete Multiboot2 memory map. It uses two bitmaps: an allocation bitmap and a reservation bitmap. The reservation bitmap prevents `pmm_free_page` from releasing firmware/kernel/bootstrap pages by accident.

Initialization starts with every frame unavailable, releases only Multiboot type-1 usable frames, then re-reserves critical ranges. The initial protected set includes low legacy memory, the kernel and PMM bootstrap metadata, Multiboot information, and the current 4-8 MiB ring-3 regression-test area.

The PMM accounts for all frames described by Multiboot. Until the VMM provides a direct physical map, normal allocations are deliberately limited to the first 1 GiB because only that range is guaranteed to be identity mapped by `entry.S`. This is an access constraint, not a truncation of PMM accounting. High frames remain represented and are not silently lost.

The old `arch_alloc_page` interface remains temporarily for existing drivers. After PMM initialization the kernel gives it a small contiguous pool that is first allocated and reserved by the PMM, so legacy users cannot collide with PMM allocations. New memory code must use the PMM directly.

## Virtual memory

`vmm.nqr` implements four-level x86-64 page-table walking for 4 KiB mappings and recognizes existing 2 MiB bootstrap mappings during translation. It can create an address-space root that shares the current bootstrap low mapping, map/unmap/protect pages, translate addresses, invalidate TLB entries, and switch CR3 through the architecture API.

Page-table flags are intentionally constructed arithmetically because the current Noqeri language has no bitwise operators. NX is not enabled in this batch because current Noqeri integer literals/NIR constants cannot safely express bit 63. That compiler limitation is recorded rather than hidden.

## Kernel heap

`heap.nqr` is a reusable page-backed free-list allocator. Each heap page starts as one free block; allocations split blocks and frees coalesce adjacent blocks within a page. The allocator tracks allocations, frees, bytes in use, and backing pages. The implementation intentionally keeps completely free pages cached in the heap for now; page return can be added after heap ownership is used by more kernel objects.

## Invariants

- A physical page may be returned by the PMM only when it is usable, unreserved, unallocated, and currently kernel-accessible.
- Reserved frames cannot be freed through `pmm_free_page`.
- PMM bitmap metadata is itself reserved before general allocation begins.
- VMM page-table pages come from PMM and are zeroed before installation.
- Page mappings must be 4 KiB aligned.
- Existing low bootstrap mappings are shared only as a compatibility mapping; isolated user/kernel layouts are the next address-space milestone.
- Heap block metadata has a fixed 32-byte layout under Noqeri's natural record alignment. If record layout changes, the heap header constant must change with a compiler regression test.

## Boot tests

The kernel boot test exercises PMM allocate/free/reserve/contiguous behavior, creates a second CR3 root, maps a physical page at a high virtual address and verifies the alias, then stress-checks heap allocation/free/reuse. CI runs the QEMU smoke path with multiple RAM sizes so PMM accounting is not tied to one machine size.
