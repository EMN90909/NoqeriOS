.section .bss
.align 16
idt_table:
    .skip 4096

.align 8
timer_ticks:
    .quad 0

.section .data
.align 8
idt_descriptor:
    .word 4095
    .quad 0

.section .text
.code64
.extern isr_user_test_syscall

.type set_idt_gate, @function
set_idt_gate:
    lea idt_table(%rip), %rax
    shl $4, %rdi
    add %rdi, %rax

    mov %rsi, %rdx
    movw %dx, 0(%rax)
    movw $0x08, 2(%rax)
    movb $0, 4(%rax)
    movb $0x8e, 5(%rax)

    mov %rsi, %rdx
    shr $16, %rdx
    movw %dx, 6(%rax)

    mov %rsi, %rdx
    shr $32, %rdx
    movl %edx, 8(%rax)
    movl $0, 12(%rax)
    ret

.global arch_interrupts_init
.type arch_interrupts_init, @function
arch_interrupts_init:
    cli
    xor %r8d, %r8d
1:
    mov %r8, %rdi
    lea isr_default(%rip), %rsi
    call set_idt_gate
    inc %r8
    cmp $256, %r8
    jne 1b

    mov $32, %rdi
    lea isr_timer(%rip), %rsi
    call set_idt_gate

    mov $128, %rdi
    lea isr_user_test_syscall(%rip), %rsi
    call set_idt_gate
    movb $0xee, idt_table+2053(%rip)

    lea idt_table(%rip), %rax
    mov %rax, idt_descriptor+2(%rip)
    lidt idt_descriptor(%rip)

    mov $0x11, %al
    mov $0x20, %dx
    out %al, %dx
    mov $0x11, %al
    mov $0xa0, %dx
    out %al, %dx

    mov $0x20, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0x28, %al
    mov $0xa1, %dx
    out %al, %dx

    mov $0x04, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0x02, %al
    mov $0xa1, %dx
    out %al, %dx

    mov $0x01, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0x01, %al
    mov $0xa1, %dx
    out %al, %dx

    mov $0xfe, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0xff, %al
    mov $0xa1, %dx
    out %al, %dx

    mov $0x36, %al
    mov $0x43, %dx
    out %al, %dx
    mov $0x9c, %al
    mov $0x40, %dx
    out %al, %dx
    mov $0x2e, %al
    out %al, %dx

    movq $0, timer_ticks(%rip)
    ret

.global arch_timer_ticks
.type arch_timer_ticks, @function
arch_timer_ticks:
    mov timer_ticks(%rip), %rax
    ret

.align 16
isr_timer:
    push %rax
    push %rdx
    incq timer_ticks(%rip)
    mov $0x20, %al
    mov $0x20, %dx
    out %al, %dx
    pop %rdx
    pop %rax
    iretq

.align 16
isr_default:
    cli
2:
    hlt
    jmp 2b
