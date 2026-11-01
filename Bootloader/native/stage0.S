/* NoqeriOS-owned legacy BIOS bootstrap. Loaded by BIOS at 0000:7c00.
 * Reads stage1 (up to 32 sectors) from LBA 1 using INT 13h extensions.
 * Boot protocol and kernel ELF loading live in later stages.
 */
.code16
.section .text
.global _start
_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7c00, %sp
    sti
    movb %dl, drive_number
    movw $0x55aa, %bx
    movb $0x41, %ah
    int $0x13
    jc disk_failure
    cmpw $0xaa55, %bx
    jne disk_failure
    testw $1, %cx
    jz disk_failure
    movb drive_number, %dl
    movw $dap, %si
    movb $0x42, %ah
    int $0x13
    jc disk_failure
    movb drive_number, %dl
    ljmp $0, $0x8000
disk_failure:
    movw $failure_message, %si
1:
    lodsb
    testb %al, %al
    jz 2f
    movb $0x0e, %ah
    int $0x10
    jmp 1b
2:
    cli
    hlt
    jmp 2b
drive_number: .byte 0
failure_message: .asciz "NoqeriOS native boot: disk read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
