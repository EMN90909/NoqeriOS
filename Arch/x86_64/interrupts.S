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
.extern kernel_timer_interrupt
.extern arch_current_apic_id
.extern arch_lapic_eoi

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

    mov $48, %rdi
    lea isr_timer(%rip), %rsi
    call set_idt_gate

    mov $128, %rdi
    lea isr_user_test_syscall(%rip), %rsi
    call set_idt_gate
    movb $0xee, idt_table+2053(%rip)

    lea idt_table(%rip), %rax
    mov %rax, idt_descriptor+2(%rip)
    lidt idt_descriptor(%rip)

    # Legacy PIC remains fully masked. External IRQ0 is delivered by IOAPIC.
    mov $0xff, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0xa1, %dx
    out %al, %dx

    # PIT channel 0 remains a stable bootstrap time source. IOAPIC routes IRQ0
    # to vector 48 on the BSP; APs use their local APIC periodic timers.
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

.global arch_interrupts_load
.type arch_interrupts_load, @function
arch_interrupts_load:
    lidt idt_descriptor(%rip)
    ret

.global arch_timer_ticks
.type arch_timer_ticks, @function
arch_timer_ticks:
    mov timer_ticks(%rip), %rax
    ret

.align 16
isr_timer:
    push %rax
    push %rbx
    push %rcx
    push %rdx
    push %rbp
    push %rdi
    push %rsi
    push %r8
    push %r9
    push %r10
    push %r11
    push %r12
    push %r13
    push %r14
    push %r15

    lock incq timer_ticks(%rip)
    mov %rsp, %rbx

    # Work below the saved frame so C/Noqeri calls cannot overwrite it.
    sub $32, %rsp
    and $-16, %rsp
    call arch_current_apic_id
    mov %eax, %esi
    mov %rbx, %rdi
    call kernel_timer_interrupt
    mov %rax, %r13
    call arch_lapic_eoi
    mov %r13, %rsp

    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %r11
    pop %r10
    pop %r9
    pop %r8
    pop %rsi
    pop %rdi
    pop %rbp
    pop %rdx
    pop %rcx
    pop %rbx
    pop %rax
    iretq

.align 16
isr_default:
    cli
2:
    hlt
    jmp 2b
