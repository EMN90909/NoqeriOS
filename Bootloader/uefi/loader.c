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
/* One PML4 slot covers 512 GiB. Keep the first GiB identity-mapped for
 * bootstrap code, and map only the extra 2 MiB framebuffer pages required. */
#define FRAMEBUFFER_LIMIT 0x8000000000ULL
#define MAX_FRAMEBUFFER (256ULL * 1024ULL * 1024ULL)

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

/* Multiboot2 RGB framebuffer tag: 38-byte payload, padded to eight bytes. */
typedef struct __attribute__((packed)) {
    UINT32 kind, size;
    UINT64 address;
    UINT32 pitch, width, height;
    UINT8 bpp, framebuffer_type;
    UINT16 reserved;
    UINT8 red_position, red_mask_size;
    UINT8 green_position, green_mask_size;
    UINT8 blue_position, blue_mask_size;
} MB2_FRAMEBUFFER;

/* Deliberately use private GOP definitions to avoid gnu-efi header variations.
 * Only Mode and the mode-info layout are read; no graphics protocol calls
 * are issued after ExitBootServices. */
typedef struct {
    UINT32 version, width, height, pixel_format;
    struct { UINT32 red, green, blue, reserved; } masks;
    UINT32 pixels_per_scanline;
} NOQ_GOP_INFO;
typedef struct {
    UINT32 max_mode, mode;
    NOQ_GOP_INFO *info;
    UINTN info_size;
    EFI_PHYSICAL_ADDRESS framebuffer_base;
    UINTN framebuffer_size;
} NOQ_GOP_MODE;
typedef struct {
    VOID *query_mode, *set_mode, *blt;
    NOQ_GOP_MODE *mode;
} NOQ_GOP;
typedef struct {
    UINT64 address, length;
    UINT32 pitch, width, height;
    UINT8 red_position, blue_position;
    BOOLEAN valid;
} NOQ_FRAMEBUFFER;

// Capture the firmware ACPI RSDP in a Multiboot2 tag. ACPI SDTs are
// inspected by the kernel only when reachable through its low 1 GiB map.
static EFI_GUID acpi20_guid = {
    0x8868e871, 0xe4f1, 0x11d3,
    {0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81}
};
static EFI_GUID acpi10_guid = {
    0xeb9d2d30, 0x2d88, 0x11d3,
    {0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d}
};
static BOOLEAN guid_same(const EFI_GUID *a, const EFI_GUID *b) {
    const UINT8 *x = (const UINT8 *)a;
    const UINT8 *y = (const UINT8 *)b;
    for (UINTN i = 0; i < 16; ++i) if (x[i] != y[i]) return FALSE;
    return TRUE;
}
static BOOLEAN acpi_sum_ok(const UINT8 *bytes, UINTN length) {
    UINT8 sum = 0;
    for (UINTN i = 0; i < length; ++i) sum = (UINT8)(sum + bytes[i]);
    return sum == 0;
}
static UINTN capture_acpi(EFI_SYSTEM_TABLE *st, UINT8 out[36]) {
    for (UINTN i = 0; i < st->NumberOfTableEntries; ++i) {
        EFI_CONFIGURATION_TABLE *entry = &st->ConfigurationTable[i];
        BOOLEAN v2 = guid_same(&entry->VendorGuid, &acpi20_guid);
        if (!v2 && !guid_same(&entry->VendorGuid, &acpi10_guid))
            continue;
        const UINT8 *source = (const UINT8 *)entry->VendorTable;
        if (!source) continue;
        const UINT8 signature[8] = {'R','S','D',' ','P','T','R',' '};
        BOOLEAN match = TRUE;
        for (UINTN j = 0; j < 8; ++j)
            if (source[j] != signature[j]) match = FALSE;
        if (!match || !acpi_sum_ok(source, 20)) continue;
        UINTN count = v2 && source[15] >= 2 ? 36 : 20;
        if (count == 36 && !acpi_sum_ok(source, 36)) continue;
        for (UINTN j = 0; j < count; ++j) out[j] = source[j];
        return count;
    }
    return 0;
}

static EFI_SYSTEM_TABLE *screen_table = NULL;
static EFI_GUID gop_guid = {
    0x9042a9de, 0x23dc, 0x4a38,
    {0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a}
};

static EFI_GUID loaded_image_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID filesystem_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;

static void log_debug(const char *s) {
    while (*s) {
        UINT8 b = (UINT8) *s++;
        __asm__ volatile("outb %0, $0xe9" : : "a"(b));
    }
}
static BOOLEAN eq(const char *a, const char *b) {
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
static void screen_message(const CHAR16 *message) {
    if (screen_table && screen_table->ConOut && message)
        uefi_call_wrapper(screen_table->ConOut->OutputString, 2,
                          screen_table->ConOut, (CHAR16 *)message);
}
static EFI_STATUS fail(EFI_STATUS status, const CHAR16 *message, const char *debug) {
    log_debug(debug);
    screen_message(L"NoqeriOS boot error: ");
    screen_message(message);
    screen_message(L"\r\n");
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
    log_debug("uefi: loaded image protocol OK\n");
    status = uefi_call_wrapper(st->BootServices->HandleProtocol, 3,
                              loaded->DeviceHandle, &filesystem_guid, (VOID **)&volume);
    if (EFI_ERROR(status)) return status;
    log_debug("uefi: filesystem protocol OK\n");
    status = uefi_call_wrapper(volume->OpenVolume, 2, volume, &root);
    if (EFI_ERROR(status)) return status;
    log_debug("uefi: opened boot volume\n");
    status = uefi_call_wrapper(root->Open, 5, root, &file,
                              L"\\EFI\\BOOT\\KERNEL.ELF", EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(status)) {
        uefi_call_wrapper(root->Close, 1, root);
        return status;
    }
    /* One extra byte lets us reject oversized images without trusting file metadata. */
    log_debug("uefi: opened kernel file\n");
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

/* Prefer a firmware-provided 32-bit RGB framebuffer when one is available.
 * A 64-bit physical address is not necessarily covered by the kernel's first
 * GiB bootstrap map, so paging() explicitly maps every additional framebuffer
 * page before the kernel touches it. Unsupported GOP formats stay serial-only. */
static NOQ_FRAMEBUFFER probe_gop(EFI_SYSTEM_TABLE *st) {
    NOQ_FRAMEBUFFER fb = {0};
    NOQ_GOP *gop = NULL;
    EFI_STATUS status = uefi_call_wrapper(st->BootServices->LocateProtocol, 3,
                                          &gop_guid, NULL, (VOID **)&gop);
    if (EFI_ERROR(status) || !gop || !gop->mode || !gop->mode->info)
        return fb;
    /*
     * Some physical firmware leaves a mode description in place while the
     * display engine is still using the boot-console state. Reassert the
     * current supported GOP scanout while UEFI boot services are available
     * and recapture all mode metadata before constructing the handoff.
     */
    const NOQ_GOP_MODE *mode = gop->mode;
    const NOQ_GOP_INFO *info = mode->info;
    if (info->pixel_format <= 2 && info->width && info->height &&
        mode->mode < mode->max_mode && gop->set_mode) {
        EFI_STATUS mode_status = uefi_call_wrapper(gop->set_mode, 2, gop, mode->mode);
        if (!EFI_ERROR(mode_status)) {
            log_debug("uefi: GOP graphics scanout mode reinitialized\n");
            if (!gop->mode || !gop->mode->info) return fb;
            mode = gop->mode;
            info = mode->info;
        } else {
            log_debug("uefi: GOP SetMode unavailable; using existing scanout\n");
        }
    }
    if (info->pixel_format > 2 || info->width == 0 || info->height == 0 ||
        info->width > 4096 || info->height > 2160 ||
        info->pixels_per_scanline < info->width ||
        info->pixels_per_scanline > 16384)
        return fb;
    /*
     * GOP PixelBitMask (2) can also be a linear 32bpp framebuffer, but only
     * when the masks describe the two byte orders our Noqeri renderer knows.
     * Reject 10-bit, sparse, overlapping and other unsupported masks instead
     * of interpreting their bytes as XRGB and displaying random colours.
     */
    UINT8 red = 0, blue = 16;
    if (info->pixel_format == 1) {
        red = 16; blue = 0;
    } else if (info->pixel_format == 2) {
        if (info->masks.green != 0x0000ff00u) return fb;
        if (info->masks.red == 0x000000ffu &&
            info->masks.blue == 0x00ff0000u) {
            red = 0; blue = 16;
        } else if (info->masks.red == 0x00ff0000u &&
                   info->masks.blue == 0x000000ffu) {
            red = 16; blue = 0;
        } else return fb;
    }
    UINT64 pitch = (UINT64)info->pixels_per_scanline * 4;
    UINT64 visible_bytes = pitch * info->height;
    if (mode->framebuffer_base < 0x100000 ||
        visible_bytes == 0 || visible_bytes > MAX_FRAMEBUFFER ||
        visible_bytes > mode->framebuffer_size ||
        !bounds(mode->framebuffer_base, visible_bytes, FRAMEBUFFER_LIMIT))
        return fb;
    fb.address = mode->framebuffer_base;
    fb.length = visible_bytes;
    fb.pitch = (UINT32)pitch;
    fb.width = info->width;
    fb.height = info->height;
    fb.red_position = red;
    fb.blue_position = blue;
    fb.valid = TRUE;
    log_debug("uefi: supported GOP RGB framebuffer found\n");
    return fb;
}


#ifdef NOQERIOS_LENOVO_VERIFY
/* Diagnostic mode is built only for a dedicated Lenovo G500 USB image.
 * Draw into firmware's actual linear GOP framebuffer BEFORE ExitBootServices.
 * A clean pattern followed by broken kernel graphics isolates the problem
 * to the handoff/mapping/renderer rather than the pre-kernel GOP scanout.
 * Do not depend on serial ports or storage writes on physical laptops.
 */
static UINT32 lenovo_pack_rgb(const NOQ_FRAMEBUFFER *fb,
                              UINT8 red, UINT8 green, UINT8 blue) {
    return ((UINT32)red << fb->red_position) |
           ((UINT32)green << 8) |
           ((UINT32)blue << fb->blue_position);
}

static void lenovo_gop_diagnostic(EFI_SYSTEM_TABLE *st,
                                  const NOQ_FRAMEBUFFER *fb) {
    if (!fb || !fb->valid) {
        screen_message(L"LENOVO VERIFY: unsupported GOP mode. No graphics test.\r\n");
        log_debug("uefi: Lenovo GOP diagnostic unsupported\n");
        uefi_call_wrapper(st->BootServices->Stall, 1, 3000000);
        return;
    }
    screen_message(L"LENOVO VERIFY: eight-color linear framebuffer test follows.\r\n");
    screen_message(L"Photograph bars. They should be vertical with straight white rules.\r\n");
    uefi_call_wrapper(st->BootServices->Stall, 1, 1500000);

    /* Exclude scanline padding from the visible width, but honor GOP pitch. */
    const UINT8 bars[8][3] = {
        {255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {0, 255, 255},
        {255, 0, 255}, {255, 255, 0}, {255, 255, 255}, {0, 0, 0}
    };
    volatile UINT32 *pixels = (volatile UINT32 *)(UINTN)fb->address;
    const UINTN stride = fb->pitch / sizeof(UINT32);
    for (UINTN y = 0; y < fb->height; ++y) {
        for (UINTN x = 0; x < fb->width; ++x) {
            UINTN band = (x * 8u) / fb->width;
            if (band > 7u) band = 7u;
            UINT32 pixel = lenovo_pack_rgb(fb, bars[band][0],
                                            bars[band][1], bars[band][2]);
            /* Straight 3px-wide horizontal lines reveal damaged scanlines. */
            if (y == fb->height/4u || y == fb->height/2u ||
                y == (fb->height*3u)/4u ||
                y == fb->height/4u + 1u || y == fb->height/2u + 1u ||
                y == (fb->height*3u)/4u + 1u)
                pixel = lenovo_pack_rgb(fb, 255, 255, 255);
            pixels[y * stride + x] = pixel;
        }
    }
    log_debug("uefi: Lenovo GOP diagnostic pattern drawn\n");
    /* Leave it visible long enough for a physical-hardware photograph.
       Stall runs before GetMemoryMap/ExitBootServices. */
    for (UINTN i = 0; i < 12u; ++i)
        uefi_call_wrapper(st->BootServices->Stall, 1, 500000);
    log_debug("uefi: Lenovo GOP diagnostic handoff starting\n");
}
#endif

static EFI_STATUS paging(EFI_BOOT_SERVICES *bs, EFI_PHYSICAL_ADDRESS *root,
                         const NOQ_FRAMEBUFFER *fb) {
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

    if (fb && fb->valid) {
        /*
         * Real Intel GOP framebuffers are MMIO. Map only actual 4 KiB
         * framebuffer pages, rather than mapping entire surrounding 2 MiB
         * regions with large-page cache attributes.
         * If the aperture resides in the first 1 GiB, split the existing
         * identity-mapped large page without losing adjacent RAM mappings.
         */
        UINT64 first = fb->address >> 12;
        UINT64 last = (fb->address + fb->length - 1) >> 12;
        UINT64 current_pde = ~(UINT64)0;
        UINT64 *pt = NULL;
        for (UINT64 page = first; page <= last; ++page) {
            UINT64 pde_number = page >> 9;
            UINTN pdpt_index = (UINTN)(pde_number >> 9);
            UINTN pd_index = (UINTN)(pde_number & 511u);
            UINTN pt_index = (UINTN)(page & 511u);
            if (pdpt_index >= 512) return EFI_UNSUPPORTED;
            if (!pdpt[pdpt_index]) {
                EFI_PHYSICAL_ADDRESS extra_pd;
                status = alloc_low(bs, 1, &extra_pd);
                if (EFI_ERROR(status)) return status;
                bytes_zero((VOID *)(UINTN)extra_pd, 4096);
                pdpt[pdpt_index] = extra_pd | 3;
            }
            UINT64 *entries = (UINT64 *)(UINTN)(pdpt[pdpt_index] & ~4095ULL);
            if (pde_number != current_pde) {
                UINT64 old = entries[pd_index];
                EFI_PHYSICAL_ADDRESS extra_pt;
                status = alloc_low(bs, 1, &extra_pt);
                if (EFI_ERROR(status)) return status;
                pt = (UINT64 *)(UINTN)extra_pt;
                bytes_zero(pt, 4096);
                if (old & 0x80ULL) {
                    UINT64 base = old & 0x000fffffffe00000ULL;
                    for (UINTN i = 0; i < 512; ++i)
                        pt[i] = (base + (i << 12)) | 3;
                } else if (old & 1ULL) {
                    return EFI_UNSUPPORTED;
                }
                entries[pd_index] = extra_pt | 3;
                current_pde = pde_number;
            }
            /* Present, writable, write-through, cache disabled (UC). */
            pt[pt_index] = (page << 12) | 0x1bULL;
        }
        log_debug("uefi: framebuffer mapped with 4 KiB uncached pages\n");
    }
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
                        UINTN size, UINTN descriptor_size,
                        const NOQ_FRAMEBUFFER *fb,
                        const UINT8 *rsdp, UINTN rsdp_size) {
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
    if (fb && fb->valid) {
        if (end + 48 > capacity) return FALSE;
        MB2_FRAMEBUFFER *tag_fb = (MB2_FRAMEBUFFER *)(dest + end);
        tag_fb->kind = 8;
        tag_fb->size = sizeof(MB2_FRAMEBUFFER);
        tag_fb->address = fb->address;
        tag_fb->pitch = fb->pitch;
        tag_fb->width = fb->width;
        tag_fb->height = fb->height;
        tag_fb->bpp = 32;
        tag_fb->framebuffer_type = 1; /* Direct RGB */
        tag_fb->reserved = 0;
        tag_fb->red_position = fb->red_position;
        tag_fb->red_mask_size = 8;
        tag_fb->green_position = 8;
        tag_fb->green_mask_size = 8;
        tag_fb->blue_position = fb->blue_position;
        tag_fb->blue_mask_size = 8;
        end += (sizeof(MB2_FRAMEBUFFER) + 7u) & ~7u;
    }
    if (rsdp && (rsdp_size == 20 || rsdp_size == 36)) {
        UINTN padded = (8 + rsdp_size + 7u) & ~7u;
        if (end + padded + 8 > capacity) return FALSE;
        UINT32 *acpi_tag = (UINT32 *)(dest + end);
        acpi_tag[0] = rsdp_size == 36 ? 15u : 14u;
        acpi_tag[1] = (UINT32)(8 + rsdp_size);
        for (UINTN j = 0; j < rsdp_size; ++j)
            dest[end + 8 + j] = rsdp[j];
        end += padded;
    }
    if (end + 8 > capacity) return FALSE;
    ((UINT32 *)(dest + end))[0] = 0;
    ((UINT32 *)(dest + end))[1] = 8;
    header[0] = (UINT32)(end + 8);
    header[1] = 0;
    return TRUE;
}

EFI_STATUS noq_boot_menu(EFI_HANDLE image, EFI_SYSTEM_TABLE *st);

EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *st) {
    InitializeLib(image, st);
    screen_table = st;
    EFI_STATUS menu_status = noq_boot_menu(image, st);
    if (EFI_ERROR(menu_status)) return menu_status;
    screen_message(L"NoqeriOS UEFI x64: loading kernel...\r\n");
    log_debug("NoqeriOS UEFI: entered firmware application\n");
    log_debug("uefi:before-console-print\n");
    log_debug("NoqeriOS UEFI: reading kernel file\n");
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
    NOQ_FRAMEBUFFER framebuffer = probe_gop(st);
    UINT8 acpi_rsdp[36] = {0};
    UINTN acpi_rsdp_size = capture_acpi(st, acpi_rsdp);
    if (acpi_rsdp_size) log_debug("uefi: ACPI RSDP boot tag available\n");

    EFI_PHYSICAL_ADDRESS pml4, boot_info;
    status = paging(st->BootServices, &pml4, &framebuffer);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve identity-map pages", "uefi:no-paging\n");
    status = alloc_low(st->BootServices, MAX_BOOT_INFO / 4096, &boot_info);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve boot information", "uefi:no-mb2\n");
    EFI_MEMORY_DESCRIPTOR *map = NULL;
    status = uefi_call_wrapper(st->BootServices->AllocatePool, 3, EfiLoaderData,
                               MAX_MEMMAP, (VOID **)&map);
    if (EFI_ERROR(status)) return fail(status, L"Cannot reserve firmware memory map", "uefi:no-map\n");
#ifdef NOQERIOS_LENOVO_VERIFY
    lenovo_gop_diagnostic(st, &framebuffer);
#endif
    if (framebuffer.valid)
        screen_message(L"NoqeriOS: GOP framebuffer ready; entering kernel...\r\n");
    else
        screen_message(L"NoqeriOS: kernel ready (serial console only).\r\n");
    log_debug("NoqeriOS UEFI: kernel loaded, exiting boot services\n");
    log_debug("NoqeriOS UEFI: ELF loaded, preparing handoff\n");
    UINTN key = 0, desc_size = 0, map_size = 0;
    UINT32 desc_version = 0;
    for (UINTN attempt = 0; attempt < 6; ++attempt) {
        map_size = MAX_MEMMAP;
        status = uefi_call_wrapper(st->BootServices->GetMemoryMap, 5,
                                   &map_size, map, &key, &desc_size, &desc_version);
        if (EFI_ERROR(status)) return fail(status, L"GetMemoryMap failed", "uefi:bad-map\n");
        if (!make_mb2((UINT8 *)(UINTN)boot_info, MAX_BOOT_INFO, map, map_size, desc_size,
                      &framebuffer, acpi_rsdp, acpi_rsdp_size))
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
