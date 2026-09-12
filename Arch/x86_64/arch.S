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

.global arch_out16
.type arch_out16, @function
arch_out16:
    mov %di, %dx
    mov %si, %ax
    out %ax, %dx
    ret

.global arch_in16
.type arch_in16, @function
arch_in16:
    mov %di, %dx
    xor %eax, %eax
    in %dx, %ax
    ret

.global arch_out32
.type arch_out32, @function
arch_out32:
    mov %di, %dx
    mov %esi, %eax
    out %eax, %dx
    ret

.global arch_in32
.type arch_in32, @function
arch_in32:
    mov %di, %dx
    in %dx, %eax
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

.global arch_invlpg
.type arch_invlpg, @function
arch_invlpg:
    invlpg (%rdi)
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

.global arch_serial_hex_u32
.type arch_serial_hex_u32, @function
arch_serial_hex_u32:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %edi, %r8d
    lea -12(%rbp), %rdi
    movb $'0', 0(%rdi)
    movb $'x', 1(%rdi)
    lea serial_hex_digits(%rip), %r11
    xor %r10d, %r10d
    mov $28, %r9d
6:
    mov %r8d, %eax
    mov %r9b, %cl
    shr %cl, %eax
    and $0x0f, %eax
    movzbl (%r11,%rax,1), %eax
    mov %al, 2(%rdi,%r10,1)
    sub $4, %r9d
    inc %r10d
    cmp $8, %r10d
    jb 6b
    movb $10, 10(%rdi)
    movb $0, 11(%rdi)
    call arch_serial_write
    leave
    ret

.section .rodata
serial_hex_digits:
    .ascii "0123456789ABCDEF"
