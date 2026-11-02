/*
 * NoqeriOS native UEFI dual-boot picker.
 * Read-only discovery of known EFI loaders from all firmware-visible
 * Simple File System volumes. Never touches BootOrder, NVRAM or partitions.
 * Chainloading happens before ExitBootServices, as required by UEFI.
 */
#include <efi.h>
#include <efilib.h>

#define NOQ_MAX_ALT 9u
#define NOQ_SCAN_MAX 64u
#define NOQ_TIMEOUT_TICKS 50u

typedef struct {
    EFI_HANDLE volume;
    const CHAR16 *path;
    const CHAR16 *label;
} NOQ_BOOT_CHOICE;

static NOQ_BOOT_CHOICE alternatives[NOQ_MAX_ALT];

static void display(EFI_SYSTEM_TABLE *st, const CHAR16 *message) {
    if (st && st->ConOut && message)
        uefi_call_wrapper(st->ConOut->OutputString, 2, st->ConOut, (CHAR16 *)message);
}
static void log_port(const char *s) {
    while (*s) {
        UINT8 b = (UINT8)*s++;
        __asm__ volatile("outb %0, $0xe9" : : "a"(b));
    }
}
/* No fallback BOOTX64.EFI entry: never rediscover ourselves as an alternative. */
static const struct { const CHAR16 *path; const CHAR16 *label; } known[] = {
    {L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi", L"Windows Boot Manager"},
    {L"\\EFI\\ubuntu\\shimx64.efi", L"Ubuntu (shim)"},
    {L"\\EFI\\ubuntu\\grubx64.efi", L"Ubuntu (GRUB)"},
    {L"\\EFI\\fedora\\shimx64.efi", L"Fedora (shim)"},
    {L"\\EFI\\fedora\\grubx64.efi", L"Fedora (GRUB)"},
    {L"\\EFI\\debian\\shimx64.efi", L"Debian (shim)"},
    {L"\\EFI\\debian\\grubx64.efi", L"Debian (GRUB)"},
    {L"\\EFI\\opensuse\\shim.efi", L"openSUSE"},
    {L"\\EFI\\BOOT\\refind_x64.efi", L"rEFInd"},
    {L"\\EFI\\systemd\\systemd-bootx64.efi", L"systemd-boot"},
    {L"\\EFI\\refind\\refind_x64.efi", L"rEFInd"}
};

static BOOLEAN file_present(EFI_SYSTEM_TABLE *st, EFI_HANDLE h,
                            EFI_GUID *fs_guid, const CHAR16 *path) {
    EFI_FILE_IO_INTERFACE *fs = NULL;
    EFI_FILE_HANDLE root = NULL, file = NULL;
    EFI_STATUS status = uefi_call_wrapper(st->BootServices->HandleProtocol, 3,
                        h, fs_guid, (VOID **)&fs);
    if (EFI_ERROR(status) || !fs) return FALSE;
    status = uefi_call_wrapper(fs->OpenVolume, 2, fs, &root);
    if (EFI_ERROR(status) || !root) return FALSE;
    status = uefi_call_wrapper(root->Open, 5, root, &file,
                              (CHAR16 *)path, EFI_FILE_MODE_READ, 0);
    if (!EFI_ERROR(status) && file)
        uefi_call_wrapper(file->Close, 1, file);
    uefi_call_wrapper(root->Close, 1, root);
    return !EFI_ERROR(status) && file != NULL;
}

static UINTN discover(EFI_SYSTEM_TABLE *st) {
    EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
    EFI_HANDLE *handles = NULL;
    UINTN handle_count = 0, found = 0;
    EFI_STATUS status = uefi_call_wrapper(st->BootServices->LocateHandleBuffer, 5,
                  ByProtocol, &fs_guid, NULL, &handle_count, &handles);
    if (EFI_ERROR(status) || !handles) return 0;
    if (handle_count > NOQ_SCAN_MAX) handle_count = NOQ_SCAN_MAX;
    for (UINTN v = 0; v < handle_count && found < NOQ_MAX_ALT; ++v) {
        for (UINTN i = 0; i < sizeof(known)/sizeof(known[0]) && found < NOQ_MAX_ALT; ++i) {
            /* Favor shim on each distro: prevent a duplicate GRUB option. */
            if (i > 0 && (i == 2 || i == 4 || i == 6)) {
                const CHAR16 *shim = known[i-1].path;
                if (file_present(st, handles[v], &fs_guid, shim)) continue;
            }
            if (file_present(st, handles[v], &fs_guid, known[i].path)) {
                alternatives[found].volume = handles[v];
                alternatives[found].path = known[i].path;
                alternatives[found].label = known[i].label;
                ++found;
            }
        }
    }
    uefi_call_wrapper(st->BootServices->FreePool, 2, handles);
    return found;
}

static EFI_STATUS chainload(EFI_HANDLE parent, EFI_SYSTEM_TABLE *st,
                            const NOQ_BOOT_CHOICE *option) {
    EFI_DEVICE_PATH *device_path = FileDevicePath(option->volume,
                                                   (CHAR16 *)option->path);
    if (!device_path) return EFI_OUT_OF_RESOURCES;
    EFI_HANDLE other = NULL;
    EFI_STATUS status = uefi_call_wrapper(st->BootServices->LoadImage, 6,
                      FALSE, parent, device_path, NULL, 0, &other);
    if (!EFI_ERROR(status)) {
        log_port("NoqeriOS boot menu: chainloading alternate EFI image\n");
        status = uefi_call_wrapper(st->BootServices->StartImage, 3,
                                    other, NULL, NULL);
    }
    if (other) uefi_call_wrapper(st->BootServices->UnloadImage, 1, other);
    FreePool(device_path);
    return status;
}

/* 0 = continue booting NoqeriOS, otherwise selected EFI image may return. */
EFI_STATUS noq_boot_menu(EFI_HANDLE image, EFI_SYSTEM_TABLE *st) {
    UINTN count = discover(st);
    if (count == 0) {
        log_port("NoqeriOS boot menu: no alternate EFI loader detected\n");
        return EFI_SUCCESS;
    }
    display(st, L"\r\nNoqeriOS Boot Manager (UEFI)\r\n");
    display(st, L"[0] NoqeriOS (default)\r\n");
    for (UINTN i = 0; i < count; ++i) {
        CHAR16 index[] = {L'[', (CHAR16)(L'1' + i), L']', L' ', 0};
        display(st, index);
        display(st, alternatives[i].label);
        display(st, L"\r\n");
    }
    display(st, L"Press 0-9 to choose. NoqeriOS starts in 5 seconds.\r\n");
    log_port("NoqeriOS boot menu: alternate EFI loaders found\n");

    EFI_INPUT_KEY key;
    for (UINTN tick = 0; tick < NOQ_TIMEOUT_TICKS; ++tick) {
        EFI_STATUS status = uefi_call_wrapper(st->ConIn->ReadKeyStroke, 2,
                                              st->ConIn, &key);
        if (!EFI_ERROR(status)) {
            if (key.UnicodeChar == L'0' || key.ScanCode == 0x17)
                return EFI_SUCCESS;
            if (key.UnicodeChar >= L'1' &&
                key.UnicodeChar <= L'0' + (CHAR16)count) {
                UINTN index = (UINTN)(key.UnicodeChar - L'1');
                display(st, L"Loading alternate EFI bootloader...\r\n");
                status = chainload(image, st, &alternatives[index]);
                if (EFI_ERROR(status)) {
                    display(st, L"Other bootloader returned an error.\r\n");
                    log_port("NoqeriOS boot menu: chainload returned error\n");
                } else {
                    /* A chainloaded EFI app may legitimately return. */
                    display(st, L"Other bootloader returned to NoqeriOS.\r\n");
                }
                return EFI_SUCCESS;
            }
        }
        uefi_call_wrapper(st->BootServices->Stall, 1, 100000);
    }
    log_port("NoqeriOS boot menu: default NoqeriOS selected\n");
    return EFI_SUCCESS;
}
