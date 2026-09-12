.section .bss
.align 16
tss64:
    .skip 104

.align 16
user_kernel_stack_bottom:
    .skip 16384
user_kernel_stack_top:

.align 8
user_test_return_rsp:
    .quad 0
user_test_seen:
    .quad 0

.section .data
.align 16
gdt_userspace:
    .quad 0x0000000000000000
    .quad 0x00af9a000000ffff
    .quad 0x00af92000000ffff
    .quad 0x00cff2000000ffff
    .quad 0x00affa000000ffff
    .quad 0x0000000000000000
    .quad 0x0000000000000000
gdt_userspace_end:

gdt_userspace_ptr:
    .word gdt_userspace_end - gdt_userspace - 1
    .quad 0

.section .text
.code64
.extern kernel_syscall_dispatch

.global arch_userspace_init
.type arch_userspace_init, @function
arch_userspace_init:
    cli
    lea user_kernel_stack_top(%rip), %rax
    mov %rax, tss64+4(%rip)
    movw $104, tss64+102(%rip)

    lea tss64(%rip), %rax
    mov %rax, %rdx
    and $0x00ffffff, %rdx
    shl $16, %rdx
    or $103, %rdx
    movabs $0x0000890000000000, %rcx
    or %rcx, %rdx

    mov %rax, %rcx
    shr $24, %rcx
    and $0xff, %rcx
    shl $56, %rcx
    or %rcx, %rdx
    mov %rdx, gdt_userspace+40(%rip)

    mov %rax, %rdx
    shr $32, %rdx
    movl %edx, gdt_userspace+48(%rip)
    movl $0, gdt_userspace+52(%rip)

    lea gdt_userspace(%rip), %rax
    mov %rax, gdt_userspace_ptr+2(%rip)
    lgdt gdt_userspace_ptr(%rip)

    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss

    mov $0x28, %ax
    ltr %ax

    movq $0, user_test_seen(%rip)
    mov $1, %eax
    ret

.global arch_set_tss_rsp0
.type arch_set_tss_rsp0, @function
arch_set_tss_rsp0:
    mov %rdi, tss64+4(%rip)
    ret

.global arch_enter_user_test
.type arch_enter_user_test, @function
arch_enter_user_test:
    mov %rsp, user_test_return_rsp(%rip)
    pushq $0x1b
    lea user_test_stack_top(%rip), %rax
    push %rax
    pushq $0x2
    pushq $0x23
    lea user_test_entry(%rip), %rax
    push %rax
    iretq

.global isr_user_test_syscall
.type isr_user_test_syscall, @function
isr_user_test_syscall:
    mov %eax, %edi
    xor %esi, %esi
    xor %edx, %edx
    sub $8, %rsp
    call kernel_syscall_dispatch
    add $8, %rsp

    cmp $1, %rax
    sete %al
    movzbq %al, %rax
    mov %rax, user_test_seen(%rip)

    mov user_test_return_rsp(%rip), %rsp
    mov $1, %eax
    ret

.global arch_user_test_seen
.type arch_user_test_seen, @function
arch_user_test_seen:
    mov user_test_seen(%rip), %rax
    ret

.section .usertext,"ax"
.code64
.align 16
user_test_entry:
    mov $0x4e4f4552, %eax
    int $0x80
1:
    pause
    jmp 1b

.section .userstack,"aw",@nobits
.align 4096
user_test_stack_bottom:
    .skip 16384
user_test_stack_top:
