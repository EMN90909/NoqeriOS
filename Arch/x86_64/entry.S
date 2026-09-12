.section .multiboot2,"a"
.align 8
mb2_header:
    .long 0xe85250d6
    .long 0
    .long mb2_header_end - mb2_header
    .long -(0xe85250d6 + 0 + (mb2_header_end - mb2_header))
    .short 0
    .short 0
    .long 8
mb2_header_end:

.section .bss
.align 4096
pml4_table:
    .skip 4096
pdpt_table:
    .skip 4096
pd_table:
    .skip 4096

.align 16
stack_bottom:
    .skip 65536
stack_top:

.section .rodata
.align 8
gdt64:
    .quad 0x0000000000000000
    .quad 0x00af9a000000ffff
    .quad 0x00af92000000ffff
gdt64_end:

gdt64_ptr:
    .word gdt64_end - gdt64 - 1
    .long gdt64

.section .text
.code32
.global _start
.extern kernel_main
_start:
    cli
    mov $stack_top, %esp

    /* Preserve Multiboot2 info address across the mode switch. */
    mov %ebx, %edi

    /* Build an identity map for the first GiB using 2 MiB pages. The upper
       paging levels permit user traversal, while individual PDEs decide which
       2 MiB windows are actually user accessible. */
    mov $pdpt_table, %eax
    or $0x7, %eax
    mov %eax, pml4_table

    mov $pd_table, %eax
    or $0x7, %eax
    mov %eax, pdpt_table

    xor %ecx, %ecx
    mov $0x83, %eax
1:
    mov %eax, pd_table(,%ecx,8)
    movl $0, pd_table+4(,%ecx,8)
    add $0x200000, %eax
    inc %ecx
    cmp $512, %ecx
    jne 1b

    /* Dedicated bootstrap user text (4-6 MiB) and user stack (6-8 MiB). */
    orl $0x4, pd_table+16
    orl $0x4, pd_table+24

    /* Enable PAE. */
    mov %cr4, %eax
    or $(1 << 5), %eax
    mov %eax, %cr4

    /* Install the PML4. */
    mov $pml4_table, %eax
    mov %eax, %cr3

    /* Enable long mode in EFER. */
    mov $0xc0000080, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr

    /* Enable paging. */
    mov %cr0, %eax
    or $(1 << 31), %eax
    mov %eax, %cr0

    lgdt gdt64_ptr
    ljmp $0x08, $long_mode_start

.code64
long_mode_start:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    xor %ax, %ax
    mov %ax, %fs
    mov %ax, %gs

    mov $stack_top, %rsp
    xor %rbp, %rbp
    mov %edi, %edi

    call kernel_main

halt_forever:
    cli
    hlt
    jmp halt_forever
