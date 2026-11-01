/* Minimal second-stage entry for the custom BIOS bootloader.
 * This stage proves that we own the boot path independently of Limine/GRUB.
 * It does not yet parse ELF or enter the Noqeri kernel.
 */
.code16
.section .text
.global _start
_start:
    cli
    xorw %ax,%ax
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%ss
    movw $0x7b00,%sp
    sti
    movw $message,%si
1:
    lodsb
    testb %al,%al
    jz 2f
    movb $0x0e,%ah
    int $0x10
    jmp 1b
2:
    cli
3:
    hlt
    jmp 3b
message: .asciz "NoqeriOS native stage1 loaded. Kernel ELF handoff not implemented."
