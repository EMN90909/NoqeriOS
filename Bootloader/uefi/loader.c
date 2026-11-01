/*
 * NoqeriOS-owned UEFI x86_64 kernel loader. Firmware adapter only:
 * kernel, boot metadata validation, drivers and terminal remain Noqeri.
 * gnu-efi provides PE/COFF startup; no GRUB/Limine dependencies.
 */
#include <efi.h>
#include <efilib.h>

#define MAX_ELF (512u * 1024u)
#define MAX_BOOT_INFO (128u * 1024u)
#define MAX_MEMMAP (128u * 1024u)
#define MAX_PHDRS 128u
#define IDENTITY_LIMIT 0x40000000ULL

typedef struct __attribute__((packed)) {
    UINT8 ident[16];
    UINT16 type, machine;
    UINT32 version;
    UINT64 entry, phoff, shoff;
    UINT32 flags;
    UINT16 ehsize, phentsize, phnum, shentsize, shnum, shstrndx;
} ELF_HEADER;
typedef struct __attribute__((packed)) {
    UINT32 kind, flags;
    UINT64 offset, vaddr, paddr, filesz, memsz, align;
} ELF_PROGRAM;
typedef struct __attribute__((packed)) {
    UINT32 name, type;
    UINT64 flags, addr, offset, size;
    UINT32 link, info;
    UINT64 addralign, entsize;
} ELF_SECTION;
typedef struct __attribute__((packed)) {
    UINT32 name;
    UINT8 info, other;
    UINT16 shndx;
    UINT64 value, size;
} ELF_SYMBOL;
typedef struct __attribute__((packed)) {
    UINT64 address, size;
    UINT32 type, reserved;
} MB2_ENTRY;

static EFI_GUID loaded_image_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID filesystem_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;

static void log_debug(const CHAR8 *s) {
    while (*s) {
        UINT8 b = (UINT8) *s++;
        __asm__ volatile("outb %0, $0xe9" : : "a"(b));
    }
}
static BOOLEAN eq(const CHAR8 *a, const CHAR8 *b) {
    while (*a && *b) if (*a++ != *b++) return FALSE;
    return *a == *b;
}
static BOOLEAN bounds(UINT64 start, UINT64 length, UINT64 limit) {
    return start <= limit && length <= limit - start;
}
static void bytes_copy(void *to, const void *from, UINTN count) {
    UINT8 *d = to;
    const UINT8 *s = from;
    for (UINTN i = 0; i < count; ++i) d[i] = s[i];
}
static void bytes_zero(void *to, UINTN count) {
    UINT8 *d = to;
    for (UINTN i = 0; i < count; ++i) d[i] = 0;
}
static EFI_STATUS fail(EFI_STATUS status, const CHAR16 *message, const CHAR8 *debug) {
    Print(L"NoqeriOS UEFI: %s (%r)\r\n", message, status);
    log_debug(debug);
    return status;
}

/* Read ELF from the same FAT volume as BOOTX64.EFI. */
static EFI_STATUS read_kernel(EFI_HANDLE image_handle, EFI_SYSTEM_TABLE *st,
                              UINT8 **contents, UINTN *bytes) {
    EFI_LOADED_IMAGE *loaded = NULL;
    EFI_FILE_IO_INTERFACE *volume = NULL;
    EFI_FILE_HANDLE root = NULL, file = NULL;
    EFI_STATUS status = uefi_call_wrapper(st->BootServices->HandleProtocol, 3,
                                        image_handle, &loaded_image_guid, (VOID **)&loaded);
    if (EFI_ERROR(status)) return status;
    status = uefi_call_wrapper(st->BootServices->HandleProtocol, 3,
                              loaded->DeviceHandle, &filesystem_guid, (VOID **)&volume);
    if (EFI_ERROR(status)) return status;
    status = uefi_call_wrapper(volume->OpenVolume, 2, volume, &root);
    if (EFI_ERROR(status)) return status;
    status = uefi_call_wrapper(root->Open, 5, root, &file,
                              L"\\EFI\\BOOT\\KERNEL.ELF", EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(status)) {
        uefi_call_wrapper(root->Close, 1, root);
        return status;
    }
    /* One extra byte lets us reject oversized images without trusting file metadata. */
    status = uefi_call_wrapper(st->BootServices->AllocatePool, 3,
                              EfiLoaderData, MAX_ELF + 1, (VOID **)contents);
    if (!EFI_ERROR(status)) {
        *bytes = MAX_ELF + 1;
        status = uefi_call_wrapper(file->Read, 3, file, bytes, *contents);
        if (!EFI_ERROR(status) && (*bytes < sizeof(ELF_HEADER) || *bytes > MAX_ELF))
            status = EFI_LOAD_ERROR;
    }
    uefi_call_wrapper(file->Close, 1, file);
    uefi_call_wrapper(root->Close, 1, root);
    return status;
}

/* Locate entry in the ELF symbol table, rather than jumping to _start
 * (which expects the BIOS 32-bit Multiboot2 calling convention). */
static UINT64 uefi_entry_symbol(const UINT8 *bytes, UINTN length, const ELF_HEADER *h) {
    if (h->shentsize != sizeof(ELF_SECTION) || h->shnum == 0 ||
        !bounds(h->shoff, (UINT64)h->shnum * h->shentsize, length)) return 0;
    const ELF_SECTION *sections = (const ELF_SECTION *)(bytes + h->shoff);
    for (UINTN i = 0; i < h->shnum; ++i) {
        const ELF_SECTION *symtab = &sections[i];
        if (symtab->type != 2 || symtab->entsize != sizeof(ELF_SYMBOL) ||
            symtab->link >= h->shnum ||
            !bounds(symtab->offset, symtab->size, length)) continue;
        const ELF_SECTION *strings = &sections[symtab->link];
        if (!bounds(strings->offset, strings->size, length)) continue;
        UINT64 n = symtab->size / sizeof(ELF_SYMBOL);
        const ELF_SYMBOL *syms = (const ELF_SYMBOL *)(bytes + symtab->offset);
        for (UINT64 j = 0; j < n; ++j) {
            if (syms[j].shndx == 0 || syms[j].name >= strings->size) continue;
            const CHAR8 *name = (const CHAR8 *)(bytes + strings->offset + syms[j].name);
            UINT64 left = strings->size - syms[j].name;
            /* Reject unterminated untrusted string-table entries. */
            BOOLEAN terminated = FALSE;
            for (UINT64 k = 0; k < left; ++k) if (!name[k]) { terminated = TRUE; break; }
            if (terminated && eq(name, "uefi_kernel_entry")) return syms[j].value;
        }
    }
    return 0;
}

static EFI_STATUS load_elf(EFI_SYSTEM_TABLE *st, UINT8 *file, UINTN bytes, UINT64 *entry) {
    if (bytes < sizeof(ELF_HEADER)) return EFI_LOAD_ERROR;
    ELF_HEADER *h = (ELF_HEADER *)file;
    if (h->ident[0] != 0x7f || h->ident[1] != 'E' ||
        h->ident[2] != 'L' || h->ident[3] != 'F' ||
        h->ident[4] != 2 || h->ident[5] != 1 ||
        h->type != 2 || h->machine != 62 || h->phnum == 0 ||
        h->phnum > MAX_PHDRS || h->phentsize != sizeof(ELF_PROGRAM) ||
        !bounds(h->phoff, (UINT64)h->phnum * h->phentsize, bytes))
        return EFI_LOAD_ERROR;
    UINT64 candidate = uefi_entry_symbol(file, bytes, h);
    if (!candidate || candidate >= IDENTITY_LIMIT) return EFI_LOAD_ERROR;
    const ELF_PROGRAM *ph = (const ELF_PROGRAM *)(file + h->phoff);
    BOOLEAN entry_in_code = FALSE;
    for (UINTN i = 0; i < h->phnum; ++i) {
        if (ph[i].kind != 1) continue;
        if (!bounds(ph[i].offset, ph[i].filesz, bytes) ||
            ph[i].filesz > ph[i].memsz ||
            ph[i].paddr < 0x100000 ||
            !bounds(ph[i].paddr, ph[i].memsz, IDENTITY_LIMIT) ||
            ph[i].vaddr != ph[i].paddr ||
            ((ph[i].paddr & 4095u) != (ph[i].offset & 4095u)))
            return EFI_LOAD_ERROR;
        if (candidate >= ph[i].paddr && candidate < ph[i].paddr + ph[i].memsz &&
            (ph[i].flags & 1)) entry_in_code = TRUE;
    }
    if (!entry_in_code) return EFI_LOAD_ERROR;
    /* Validate all loadable program headers before allocating any pages. */
    for (UINTN i = 0; i < h->phnum; ++i) {
        if (ph[i].kind != 1 || ph[i].memsz == 0) continue;
        EFI_PHYSICAL_ADDRESS start = ph[i].paddr & ~4095ULL;
        UINT64 total = ((ph[i].paddr & 4095ULL) + ph[i].memsz + 4095ULL) & ~4095ULL;
        EFI_STATUS status = uefi_call_wrapper(st->BootServices->AllocatePages, 4,
                                              AllocateAddress, EfiLoaderData,
                                              (UINTN)(total >> 12), &start);
        if (EFI_ERROR(status)) return status;
        bytes_copy((VOID *)(UINTN)ph[i].paddr, file + ph[i].offset, (UINTN)ph[i].filesz);
        bytes_zero((VOID *)(UINTN)(ph[i].paddr + ph[i].filesz),
                   (UINTN)(ph[i].memsz - ph[i].filesz));
    }
    *entry = candidate;
    return EFI_SUCCESS;
}

static EFI_STATUS alloc_low(EFI_BOOT_SERVICES *bs, UINTN pages, EFI_PHYSICAL_ADDRESS *address) {
    *address = IDENTITY_LIMIT - 1;
    return uefi_call_wrapper(bs->AllocatePages, 4, AllocateMaxAddress,
                             EfiLoaderData, pages, address);
}

static EFI_STATUS paging(EFI_BOOT_SERVICES *bs, EFI_PHYSICAL_ADDRESS *root) {
    EFI_PHYSICAL_ADDRESS addr;
    EFI_STATUS status = alloc_low(bs, 3, &addr);
    if (EFI_ERROR(status)) return status;
    UINT64 *pml4 = (UINT64 *)(UINTN)addr;
    UINT64 *pdpt = (UINT64 *)(UINTN)(addr + 4096);
    UINT64 *pd   = (UINT64 *)(UINTN)(addr + 8192);
    bytes_zero(pml4, 12288);
    pml4[0] = addr + 4096 + 7;
    pdpt[0] = addr + 8192 + 7;
    for (UINTN i = 0; i < 512; ++i) pd[i] = (i * 0x200000ULL) | 0x83;
    /* Retain the kernel's existing ring-3 self-test text and stack windows. */
    pd[2] |= 4;
    pd[3] |= 4;
    *root = addr;
    return EFI_SUCCESS;
}

/* Convert UEFI descriptors into Multiboot2 memory entries. Reserve loader
 * pages so the Noqeri allocator does not reclaim the kernel or boot metadata. */
static UINT32 map_type(UINT32 t) {
    if (t == EfiConventionalMemory || t == EfiBootServicesCode ||
        t == EfiBootServicesData) return 1;
    if (t == EfiACPIReclaimMemory) return 3;
    if (t == EfiACPIMemoryNVS) return 4;
    return 2;
}
static BOOLEAN make_mb2(UINT8 *dest, UINTN capacity, EFI_MEMORY_DESCRIPTOR *map,
                        UINTN size, UINTN descriptor_size) {
    if (descriptor_size < sizeof(EFI_MEMORY_DESCRIPTOR) || size % descriptor_size != 0)
        return FALSE;
    UINTN count = size / descriptor_size;
    if (count > 4096 || 32 + count * sizeof(MB2_ENTRY) > capacity) return FALSE;
    bytes_zero(dest, capacity);
    UINT32 *header = (UINT32 *)dest;
    UINT32 *tag = (UINT32 *)(dest + 8);
    tag[0] = 6;
    tag[1] = (UINT32)(16 + count * sizeof(MB2_ENTRY));
    tag[2] = sizeof(MB2_ENTRY);
    tag[3] = 0;
    MB2_ENTRY *out = (MB2_ENTRY *)(dest + 24);
    for (UINTN i = 0; i < count; ++i) {
        EFI_MEMORY_DESCRIPTOR *d = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)map + i * descriptor_size);
        out[i].address = d->PhysicalStart;
        out[i].size = d->NumberOfPages * 4096ULL;
        out[i].type = map_type(d->Type);
        out[i].reserved = 0;
    }
    UINTN end = 24 + count * sizeof(MB2_ENTRY);
    ((UINT32 *)(dest + end))[0] = 0;
    ((UINT32 *)(dest + end))[1] = 8;
    header[0] = (UINT32)(end + 8);
    header[1] = 0;
    return TRUE;
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *st) {
    InitializeLib(image, st);
    log_debug("NoqeriOS UEFI: entered firmware application\n");
    log_debug("uefi:before-console-print\n");
    Print(L"NoqeriOS UEFI loader: opening kernel ELF\r\n");
    log_debug("uefi:after-console-print\n");
    UINT8 *kernel = NULL;
    UINTN kernel_size = 0;
    log_debug("uefi:before-file-open\n");
    EFI_STATUS status = read_kernel(image, st, &kernel, &kernel_size);
    log_debug("uefi:after-file-open\n");
    if (EFI_ERROR(status)) return fail(status, L"Cannot read KERNEL.ELF", "uefi:no-kernel\n");
    UINT64 kernel_entry = 0;
    log_debug("uefi:before-elf-load\n");
    status = load_elf(st, kernel, kernel_size, &kernel_entry);
    log_debug("uefi:after-elf-load\n");
    if (EFI_ERROR(status)) return fail(status, L"ELF load rejected or memory occupied", "uefi:bad-elf\n");
    EFI_PHYSICAL_ADDRESS pml4, boot_info;
    status = paging(st->BootServices, &pml4);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve identity-map pages", "uefi:no-paging\n");
    status = alloc_low(st->BootServices, MAX_BOOT_INFO / 4096, &boot_info);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve boot information", "uefi:no-mb2\n");
    EFI_MEMORY_DESCRIPTOR *map = NULL;
    status = uefi_call_wrapper(st->BootServices->AllocatePool, 3, EfiLoaderData,
                               MAX_MEMMAP, (VOID **)&map);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve firmware memory map", "uefi:no-map\n");
    Print(L"NoqeriOS UEFI: kernel loaded, exiting boot services\r\n");
    log_debug("NoqeriOS UEFI: ELF loaded, preparing handoff\n");
    UINTN key = 0, desc_size = 0, map_size, desc_version = 0;
    for (UINTN attempt = 0; attempt < 6; ++attempt) {
        map_size = MAX_MEMMAP;
        status = uefi_call_wrapper(st->BootServices->GetMemoryMap, 5,
                                   &map_size, map, &key, &desc_size, &desc_version);
        if (EFI_ERROR(status)) return fail(status, L"GetMemoryMap failed", "uefi:bad-map\n");
        if (!make_mb2((UINT8 *)(UINTN)boot_info, MAX_BOOT_INFO, map, map_size, desc_size))
            return fail(EFI_LOAD_ERROR, L"Memory map exceeds boot-info capacity", "uefi:map-overflow\n");
        status = uefi_call_wrapper(st->BootServices->ExitBootServices, 2, image, key);
        if (!EFI_ERROR(status)) {
            log_debug("NoqeriOS UEFI: ExitBootServices OK\n");
            typedef void (*kernel_entry_fn)(UINTN, UINTN);
            ((kernel_entry_fn)(UINTN)kernel_entry)((UINTN)boot_info, (UINTN)pml4);
            for (;;) __asm__ volatile("cli; hlt");
        }
        if (status != EFI_INVALID_PARAMETER) break;
        /* Firmware invalidated map key: GetMemoryMap again, without allocating. */
    }
    /* Firmware may have partially shut down services after the first failure:
     * do not call Print() or additional protocol services here. */
    log_debug("NoqeriOS UEFI: ExitBootServices failed\n");
    return status;
}
