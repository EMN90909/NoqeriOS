/* Harmless second EFI application for dual-boot integration testing only. */
#include <efi.h>
#include <efilib.h>
EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *st) {
    (void)image;
    (void)st;
    const char *p = "NOQERI_ALT_EFI_EXECUTED\n";
    while (*p) {
        UINT8 ch=(UINT8)*p++;
        __asm__ volatile("outb %0, $0xe9" : : "a"(ch));
    }
    return EFI_SUCCESS;
}
