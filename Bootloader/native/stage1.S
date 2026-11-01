/* NoqeriOS original BIOS ELF64 loader. This is the firmware/CPU adapter;
 * all kernel services and boot-data validation remain in Noqeri.
 * Fixed image layout: LBA0 stage0, LBA1-32 stage1, LBA33-1056 ELF (512KiB).
 */
.code16
.section .text
.global _start
_start:
    cli
    xorw %ax,%ax
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%ss
    movw $0x7b00,%sp
    sti
    movb %dl,drive
    /* El Torito floppy images may not support EDD. Probe once. */
    movw $0x55aa,%bx
    movb $0x41,%ah
    int $0x13
    jc .no_edd
    cmpw $0xaa55,%bx
    jne .no_edd
    testw $1,%cx
    jz .no_edd
    movb $1,edd
.no_edd:
    /* Geometry for CHS fallback (floppy: 18 sectors, 2 heads). */
    movb drive,%dl
    movb $0x08,%ah
    int $0x13
    jc .default_geometry
    andb $0x3f,%cl
    jz .default_geometry
    movzbw %cl,%ax
    movw %ax,spt
    movzbw %dh,%ax
    incw %ax
    movw %ax,heads
.default_geometry:
    /* A20 via fast gate, required before copying PT_LOAD above 1MiB. */
    inb $0x92,%al
    orb $2,%al
    outb %al,$0x92
    /* Minimal valid Multiboot2 info: header + E820 memory map + end. */
    movw $0x5000,%di
    xorl %eax,%eax
    movl %eax,(%di)
    movl %eax,4(%di)
    movl $6,8(%di)
    movl $0,12(%di)
    movl $24,16(%di)
    movl $0,20(%di)
    movw $0x5018,%di
    xorl %ebx,%ebx
e820_next:
    movl $0x534d4150,%edx
    movl $0xe820,%eax
    movl $24,%ecx
    movl $1,20(%di)
    int $0x15
    jc e820_done
    cmpl $0x534d4150,%eax
    jne boot_error
    cmpw $20,%cx
    jb boot_error
    addw $24,%di
    cmpw $0x6fc0,%di
    jae boot_error
    testl %ebx,%ebx
    jnz e820_next
e820_done:
    /* Tag size includes its 16-byte header and all 24-byte entries. */
    movzwl %di,%eax
    subl $0x5008,%eax
    movl %eax,0x500c
    /* MB2 tags must be 8-byte aligned. Entries are multiples of 24. */
    movl $0,(%di)
    movl $8,4(%di)
    addw $8,%di
    movzwl %di,%eax
    subl $0x5000,%eax
    movl %eax,0x5000
    /* Read exactly 1024 sectors into 0x10000..0x8ffff. */
    movw $0x1000,%ax
    movw %ax,buffer_seg
    movl $33,sector
    movw $32,%bp
read_chunk:
    cmpb $0,edd
    je read_chs_chunk
    movw buffer_seg,%ax
    movw %ax,dap_seg
    movl sector,%eax
    movl %eax,dap_lba
    movb drive,%dl
    movw $dap,%si
    movb $0x42,%ah
    int $0x13
    jnc .chunk_complete
    /* Firmware may advertise EDD but reject this emulated disk. */
    movb $0,edd
read_chs_chunk:
    movw $32,%di
.read_sector:
    /* Convert logical sector -> cylinder/head/sector. */
    movw sector,%ax
    xorw %dx,%dx
    divw spt
    movb %dl,%cl
    incb %cl
    xorw %dx,%dx
    divw heads
    movb %al,%ch
    movb %dl,%dh
    movb %ah,%al
    andb $3,%al
    shlb $6,%al
    orb %al,%cl
    movw buffer_seg,%ax
    movw %ax,%es
    xorw %bx,%bx
    movb drive,%dl
    movw $0x0201,%ax
    int $0x13
    jc boot_error
    addw $0x20,buffer_seg
    incl sector
    decw %di
    jnz .read_sector
    jmp .next_chunk
.chunk_complete:
    addw $0x400,buffer_seg
    addl $32,sector
.next_chunk:
    decw %bp
    jnz read_chunk
    /* Enter protected mode and process the ELF program headers. */
    cli
    lgdt gdt_ptr
    movl %cr0,%eax
    orl $1,%eax
    movl %eax,%cr0
    ljmp $0x08,$protected
boot_error:
    movw $failure,%si
print_error:
    lodsb
    testb %al,%al
    jz halt16
    movb $0x0e,%ah
    int $0x10
    jmp print_error
halt16:
    cli
    hlt
    jmp halt16
drive: .byte 0
edd: .byte 0
.align 2
spt: .word 18
heads: .word 2
buffer_seg: .word 0x1000
sector: .long 33
failure: .asciz "NoqeriOS native loader: BIOS failure"
.align 4
dap:
    .byte 16,0
    .word 32
    .word 0
dap_seg: .word 0x1000
dap_lba: .quad 33
.align 8
gdt:
    .quad 0
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
gdt_end:
gdt_ptr:
    .word gdt_end-gdt-1
    .long gdt
.code32
protected:
    movw $0x10,%ax
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%ss
    movl $0x7b00,%esp
    movl $0x10000,%esi
    cmpl $0x464c457f,(%esi)
    jne halt32
    cmpb $2,4(%esi)
    jne halt32
    cmpw $62,18(%esi)
    jne halt32
    cmpl $0,36(%esi) /* ELF64 e_phoff high word */
    jne halt32
    movl 32(%esi),%ebp
    addl %esi,%ebp
    movzwl 54(%esi),%ebx
    movzwl 56(%esi),%ecx
    testl %ecx,%ecx
    jz halt32
    cmpl $128,%ecx
    ja halt32
    cmpl $56,%ebx
    jb halt32
load_ph:
    cmpl $1,(%ebp)
    jne next_ph
    cmpl $0,12(%ebp)
    jne halt32
    cmpl $0,28(%ebp)
    jne halt32
    cmpl $0,36(%ebp)
    jne halt32
    cmpl $0,44(%ebp)
    jne halt32
    movl 24(%ebp),%edi
    cmpl $0x100000,%edi
    jb halt32
    movl 32(%ebp),%edx
    cmpl 40(%ebp),%edx
    ja halt32
    pushl %esi
    pushl %ecx
    movl 8(%ebp),%esi
    cmpl $0,12(%ebp)
    jne halt32
    addl $0x10000,%esi
    movl %edx,%ecx
    rep movsb
    movl 40(%ebp),%ecx
    subl %edx,%ecx
    xorl %eax,%eax
    rep stosb
    popl %ecx
    popl %esi
next_ph:
    addl %ebx,%ebp
    decl %ecx
    jnz load_ph
    movl 24(%esi),%edx
    cmpl $0,28(%esi)
    jne halt32
    movl $0x36d76289,%eax
    movl $0x5000,%ebx
    jmp *%edx
halt32:
    cli
1:
    hlt
    jmp 1b
