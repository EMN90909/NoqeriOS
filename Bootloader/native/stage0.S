/* NoqeriOS BIOS stage 0: EDD when available, CHS fallback for El Torito floppy. */
.code16
.section .text
.global _start
_start:
    cli
    xorw %ax,%ax
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%ss
    movw $0x7c00,%sp
    sti
    movb 
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc read_chs
    cmpw $0xaa55,%bx
    jne read_chs
    testw $1,%cx
    jz read_chs
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc loaded
read_chs:
    /* ISO El Torito floppy emulation exposes 18 sectors x 2 heads. */
    movw $0x0800,%ax
    movw %ax,%es
    xorw %di,%di
    movw $1,%bp
.chs_loop:
    movw %bp,%ax
    xorw %dx,%dx
    movw $18,%bx
    divw %bx
    movb %dl,%cl
    incb %cl
    movw %ax,%bx
    andb $1,%bl
    movb %bl,%dh
    shrw $1,%ax
    movb %al,%ch
    movb drive,%dl
    movw %di,%bx
    movw $0x0201,%ax
    int $0x13
    jc disk_failure
    addw $512,%di
    incw %bp
    cmpw $33,%bp
    jne .chs_loop
loaded:
    movb     movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movb     movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
0',%al
    outb %al,$0xe9
    movb %dl,drive
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc read_chs
    cmpw $0xaa55,%bx
    jne read_chs
    testw $1,%cx
    jz read_chs
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc loaded
read_chs:
    /* ISO El Torito floppy emulation exposes 18 sectors x 2 heads. */
    movw $0x0800,%ax
    movw %ax,%es
    xorw %di,%di
    movw $1,%bp
.chs_loop:
    movw %bp,%ax
    xorw %dx,%dx
    movw $18,%bx
    divw %bx
    movb %dl,%cl
    incb %cl
    movw %ax,%bx
    andb $1,%bl
    movb %bl,%dh
    shrw $1,%ax
    movb %al,%ch
    movb drive,%dl
    movw %di,%bx
    movw $0x0201,%ax
    int $0x13
    jc disk_failure
    addw $512,%di
    incw %bp
    cmpw $33,%bp
    jne .chs_loop
loaded:
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
A',%al
    outb %al,$0xe9
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
0',%al
    outb %al,$0xe9
    movb %dl,drive
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc read_chs
    cmpw $0xaa55,%bx
    jne read_chs
    testw $1,%cx
    jz read_chs
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc loaded
read_chs:
    /* ISO El Torito floppy emulation exposes 18 sectors x 2 heads. */
    movw $0x0800,%ax
    movw %ax,%es
    xorw %di,%di
    movw $1,%bp
.chs_loop:
    movw %bp,%ax
    xorw %dx,%dx
    movw $18,%bx
    divw %bx
    movb %dl,%cl
    incb %cl
    movw %ax,%bx
    andb $1,%bl
    movb %bl,%dh
    shrw $1,%ax
    movb %al,%ch
    movb drive,%dl
    movw %di,%bx
    movw $0x0201,%ax
    int $0x13
    jc disk_failure
    addw $512,%di
    incw %bp
    cmpw $33,%bp
    jne .chs_loop
loaded:
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
!',%al
    outb %al,$0xe9
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
0',%al
    outb %al,$0xe9
    movb %dl,drive
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc read_chs
    cmpw $0xaa55,%bx
    jne read_chs
    testw $1,%cx
    jz read_chs
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc loaded
read_chs:
    /* ISO El Torito floppy emulation exposes 18 sectors x 2 heads. */
    movw $0x0800,%ax
    movw %ax,%es
    xorw %di,%di
    movw $1,%bp
.chs_loop:
    movw %bp,%ax
    xorw %dx,%dx
    movw $18,%bx
    divw %bx
    movb %dl,%cl
    incb %cl
    movw %ax,%bx
    andb $1,%bl
    movb %bl,%dh
    shrw $1,%ax
    movb %al,%ch
    movb drive,%dl
    movw %di,%bx
    movw $0x0201,%ax
    int $0x13
    jc disk_failure
    addw $512,%di
    incw %bp
    cmpw $33,%bp
    jne .chs_loop
loaded:
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
A',%al
    outb %al,$0xe9
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
0',%al
    outb %al,$0xe9
    movb %dl,drive
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc read_chs
    cmpw $0xaa55,%bx
    jne read_chs
    testw $1,%cx
    jz read_chs
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc loaded
read_chs:
    /* ISO El Torito floppy emulation exposes 18 sectors x 2 heads. */
    movw $0x0800,%ax
    movw %ax,%es
    xorw %di,%di
    movw $1,%bp
.chs_loop:
    movw %bp,%ax
    xorw %dx,%dx
    movw $18,%bx
    divw %bx
    movb %dl,%cl
    incb %cl
    movw %ax,%bx
    andb $1,%bl
    movb %bl,%dh
    shrw $1,%ax
    movb %al,%ch
    movb drive,%dl
    movw %di,%bx
    movw $0x0201,%ax
    int $0x13
    jc disk_failure
    addw $512,%di
    incw %bp
    cmpw $33,%bp
    jne .chs_loop
loaded:
    movb drive,%dl
    ljmp $0,$0x8000
disk_failure:
    movw $failure,%si
.print:
    lodsb
    testb %al,%al
    jz .hang
    movb $0x0e,%ah
    int $0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang
drive: .byte 0
failure: .asciz "NoqeriOS: stage0 read failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0x8000
    .word 0
    .quad 1
.org 510
.word 0xaa55
