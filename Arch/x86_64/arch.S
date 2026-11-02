.section .bss
.align 8
early_alloc_next:
    .quad 0
early_alloc_end:
    .quad 0
console_surface_ptr:
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

.global arch_read_tsc
.type arch_read_tsc, @function
arch_read_tsc:
    rdtsc
    shl $32, %rdx
    or %rdx, %rax
    ret

.global arch_cpu_apic_id
.type arch_cpu_apic_id, @function
arch_cpu_apic_id:
    push %rbx
    xor %eax, %eax
    cpuid
    cmp $11, %eax
    jb .Lcpu_leaf1
    mov $11, %eax
    xor %ecx, %ecx
    cpuid
    test %ebx, %ebx
    jz .Lcpu_leaf1
    mov %edx, %eax
    pop %rbx
    ret
.Lcpu_leaf1:
    mov $1, %eax
    cpuid
    shr $24, %ebx
    mov %ebx, %eax
    pop %rbx
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

.global arch_console_attach
.type arch_console_attach, @function
arch_console_attach:
    mov %rdi, console_surface_ptr(%rip)
    ret

.global arch_console_echo
.type arch_console_echo, @function
arch_console_echo:
    movzbl %dil, %esi
    mov console_surface_ptr(%rip), %rdi
    test %rdi, %rdi
    jz .Lconsole_echo_end
    jmp gui_terminal_char
.Lconsole_echo_end:
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
    push %rdi
    mov console_surface_ptr(%rip), %rdi
    test %rdi, %rdi
    jz .Lserial_no_mirror
    movzbl %al, %esi
    call gui_terminal_char
.Lserial_no_mirror:
    pop %rdi
    inc %rdi
    jmp 3b
5:
    ret

/* Explicitly request a non-executable kernel stack from GNU ld. */
.section .note.GNU-stack,"",@progbits
