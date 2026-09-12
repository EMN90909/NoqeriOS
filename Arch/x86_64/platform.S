.section .bss
.align 8
lapic_mmio_base:
    .quad 0
smp_online_count:
    .quad 0
scheduler_system_ptr:
    .quad 0

.section .text
.code64
.extern kernel_ap_main
.extern kernel_thread_entry
.extern kernel_thread_finished

.global arch_read_msr
.type arch_read_msr, @function
arch_read_msr:
    mov %edi, %ecx
    rdmsr
    shl $32, %rdx
    or %rdx, %rax
    ret

.global arch_write_msr
.type arch_write_msr, @function
arch_write_msr:
    mov %edi, %ecx
    mov %rsi, %rax
    mov %rsi, %rdx
    shr $32, %rdx
    wrmsr
    ret

.global arch_pic_mask_all
.type arch_pic_mask_all, @function
arch_pic_mask_all:
    mov $0xff, %al
    mov $0x21, %dx
    out %al, %dx
    mov $0xa1, %dx
    out %al, %dx
    ret

.global arch_set_lapic_base
.type arch_set_lapic_base, @function
arch_set_lapic_base:
    mov %rdi, lapic_mmio_base(%rip)
    ret

.global arch_get_lapic_base
.type arch_get_lapic_base, @function
arch_get_lapic_base:
    mov lapic_mmio_base(%rip), %rax
    ret

.global arch_current_apic_id
.type arch_current_apic_id, @function
arch_current_apic_id:
    mov lapic_mmio_base(%rip), %rdx
    test %rdx, %rdx
    jz 1f
    mov 0x20(%rdx), %eax
    shr $24, %eax
    ret
1:
    xor %eax, %eax
    ret

.global arch_lapic_eoi
.type arch_lapic_eoi, @function
arch_lapic_eoi:
    mov lapic_mmio_base(%rip), %rdx
    test %rdx, %rdx
    jz 1f
    movl $0, 0xb0(%rdx)
1:
    ret

.global arch_smp_reset_online
.type arch_smp_reset_online, @function
arch_smp_reset_online:
    movq $1, smp_online_count(%rip)
    ret

.global arch_smp_online_count
.type arch_smp_online_count, @function
arch_smp_online_count:
    mov smp_online_count(%rip), %rax
    ret

.global arch_smp_mark_online
.type arch_smp_mark_online, @function
arch_smp_mark_online:
    lock incq smp_online_count(%rip)
    ret

.global arch_scheduler_bind
.type arch_scheduler_bind, @function
arch_scheduler_bind:
    mov %rdi, scheduler_system_ptr(%rip)
    ret

.global arch_scheduler_system
.type arch_scheduler_system, @function
arch_scheduler_system:
    mov scheduler_system_ptr(%rip), %rax
    ret

.global arch_prepare_kernel_thread
.type arch_prepare_kernel_thread, @function
arch_prepare_kernel_thread:
    # rdi=stackTop, rsi=thread id, rdx=argument. Build the exact register +
    # iret frame consumed by isr_timer in interrupts.S.
    lea -144(%rdi), %rax
    movq $0, 0(%rax)
    movq $0, 8(%rax)
    movq $0, 16(%rax)
    movq $0, 24(%rax)
    movq $0, 32(%rax)
    movq $0, 40(%rax)
    movq $0, 48(%rax)
    movq $0, 56(%rax)
    mov %rdx, 64(%rax)
    mov %rsi, 72(%rax)
    movq $0, 80(%rax)
    movq $0, 88(%rax)
    movq $0, 96(%rax)
    movq $0, 104(%rax)
    movq $0, 112(%rax)
    lea kernel_thread_trampoline(%rip), %rcx
    mov %rcx, 120(%rax)
    movq $0x08, 128(%rax)
    movq $0x202, 136(%rax)
    ret

.global arch_prepare_user_thread
.type arch_prepare_user_thread, @function
arch_prepare_user_thread:
    # rdi=kernelStackTop, rsi=userRip, rdx=userRsp, rcx=arg0.
    lea -160(%rdi), %rax
    movq $0, 0(%rax)
    movq $0, 8(%rax)
    movq $0, 16(%rax)
    movq $0, 24(%rax)
    movq $0, 32(%rax)
    movq $0, 40(%rax)
    movq $0, 48(%rax)
    movq $0, 56(%rax)
    movq $0, 64(%rax)
    mov %rcx, 72(%rax)
    movq $0, 80(%rax)
    movq $0, 88(%rax)
    movq $0, 96(%rax)
    movq $0, 104(%rax)
    movq $0, 112(%rax)
    mov %rsi, 120(%rax)
    movq $0x23, 128(%rax)
    movq $0x202, 136(%rax)
    mov %rdx, 144(%rax)
    movq $0x1b, 152(%rax)
    ret

.align 16
kernel_thread_trampoline:
    # rdi/rsi were restored from the synthetic frame.
    call kernel_thread_entry
    call kernel_thread_finished
1:
    sti
    hlt
    jmp 1b

.global arch_smp_start_ap
.type arch_smp_start_ap, @function
arch_smp_start_ap:
    # rdi=destination APIC id, rsi=stack top, rdx=CR3.
    push %rbx
    push %r12
    push %r13
    push %r14
    mov %edi, %r12d
    mov %rsi, %r13
    mov %rdx, %r14

    lea ap_trampoline_start(%rip), %rsi
    mov $0x7000, %rdi
    mov $(ap_trampoline_end-ap_trampoline_start), %rcx
    cld
    rep movsb

    mov %r14, 0x7f20
    mov %r13, 0x7f28
    lea kernel_ap_main(%rip), %rax
    mov %rax, 0x7f30
    mov %r12, 0x7f38

    mov smp_online_count(%rip), %rbx
    mov lapic_mmio_base(%rip), %r10
    test %r10, %r10
    jz 9f

    mov %r12d, %eax
    shl $24, %eax
    mov %eax, 0x310(%r10)
    movl $0x00004500, 0x300(%r10)
2:
    mov 0x300(%r10), %eax
    test $0x1000, %eax
    jnz 2b
    mov $200000, %ecx
3:
    pause
    loop 3b

    mov %r12d, %eax
    shl $24, %eax
    mov %eax, 0x310(%r10)
    movl $0x00004607, 0x300(%r10)
4:
    mov 0x300(%r10), %eax
    test $0x1000, %eax
    jnz 4b
    mov $100000, %ecx
5:
    pause
    loop 5b

    mov %r12d, %eax
    shl $24, %eax
    mov %eax, 0x310(%r10)
    movl $0x00004607, 0x300(%r10)
6:
    mov 0x300(%r10), %eax
    test $0x1000, %eax
    jnz 6b

    mov $50000000, %ecx
7:
    mov smp_online_count(%rip), %rax
    cmp %rbx, %rax
    ja 8f
    pause
    dec %ecx
    jnz 7b
9:
    xor %eax, %eax
    jmp 10f
8:
    mov $1, %eax
10:
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret

.section .rodata
.align 16
.set AP_BASE, 0x7000
ap_trampoline_start:
.code16
    cli
    xor %ax, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    lgdt AP_BASE + (ap_gdt_desc-ap_trampoline_start)
    mov %cr0, %eax
    or $1, %eax
    mov %eax, %cr0
    ljmpl $0x08, $(AP_BASE + (ap_protected-ap_trampoline_start))

.code32
ap_protected:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov %cr4, %eax
    or $0x20, %eax
    mov %eax, %cr4
    mov 0x7f20, %eax
    mov %eax, %cr3
    mov $0xc0000080, %ecx
    rdmsr
    or $0x100, %eax
    wrmsr
    mov %cr0, %eax
    or $0x80000000, %eax
    mov %eax, %cr0
    ljmpl $0x18, $(AP_BASE + (ap_long-ap_trampoline_start))

.code64
ap_long:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    xor %ax, %ax
    mov %ax, %fs
    mov %ax, %gs
    movabs $0x7f28, %rax
    mov (%rax), %rsp
    xor %rbp, %rbp
    movabs $0x7f38, %rax
    mov (%rax), %rdi
    movabs $0x7f30, %rax
    mov (%rax), %rax
    call *%rax
11:
    cli
    hlt
    jmp 11b

.align 8
ap_gdt:
    .quad 0x0000000000000000
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
    .quad 0x00af9a000000ffff
ap_gdt_end:
ap_gdt_desc:
    .word ap_gdt_end-ap_gdt-1
    .long AP_BASE + (ap_gdt-ap_trampoline_start)
ap_trampoline_end:
.code64
