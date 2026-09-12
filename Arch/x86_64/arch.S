.section .bss
.align 8
early_alloc_next:
    .quad 0
early_alloc_end:
    .quad 0

.section .text
.code64

.global arch_out8
.type arch_out8, @function
arch_out8:
    mov %di, %dx
    mov %sil, %al
    out %al, %dx
    ret

.global arch_in8
.type arch_in8, @function
arch_in8:
    mov %di, %dx
    xor %eax, %eax
    in %dx, %al
    ret

.global arch_cli
.type arch_cli, @function
arch_cli:
    cli
    ret

.global arch_sti
.type arch_sti, @function
arch_sti:
    sti
    ret

.global arch_halt
.type arch_halt, @function
arch_halt:
    hlt
    ret

.global arch_pause
.type arch_pause, @function
arch_pause:
    pause
    ret

.global arch_read_cr2
.type arch_read_cr2, @function
arch_read_cr2:
    mov %cr2, %rax
    ret

.global arch_read_cr3
.type arch_read_cr3, @function
arch_read_cr3:
    mov %cr3, %rax
    ret

.global arch_write_cr3
.type arch_write_cr3, @function
arch_write_cr3:
    mov %rdi, %cr3
    ret

.global arch_kernel_start
.type arch_kernel_start, @function
arch_kernel_start:
    lea __kernel_start(%rip), %rax
    ret

.global arch_kernel_end
.type arch_kernel_end, @function
arch_kernel_end:
    lea __kernel_end(%rip), %rax
    ret

.global arch_early_allocator_set
.type arch_early_allocator_set, @function
arch_early_allocator_set:
    add $4095, %rdi
    and $-4096, %rdi
    and $-4096, %rsi
    cmp %rsi, %rdi
    jae 1f
    mov %rdi, early_alloc_next(%rip)
    mov %rsi, early_alloc_end(%rip)
    mov $1, %eax
    ret
1:
    movq $0, early_alloc_next(%rip)
    movq $0, early_alloc_end(%rip)
    xor %eax, %eax
    ret

.global arch_alloc_page
.type arch_alloc_page, @function
arch_alloc_page:
    mov early_alloc_next(%rip), %rax
    test %rax, %rax
    jz 2f
    lea 4096(%rax), %rdx
    cmp early_alloc_end(%rip), %rdx
    ja 2f
    mov %rdx, early_alloc_next(%rip)
    ret
2:
    xor %eax, %eax
    ret

.global arch_serial_write
.type arch_serial_write, @function
arch_serial_write:
    test %rdi, %rdi
    jz 5f
3:
    movb (%rdi), %al
    test %al, %al
    jz 5f
    push %rax
4:
    mov $0x3fd, %dx
    in %dx, %al
    test $0x20, %al
    jz 4b
    pop %rax
    mov $0x3f8, %dx
    out %al, %dx
    inc %rdi
    jmp 3b
5:
    ret
