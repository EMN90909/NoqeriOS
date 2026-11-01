/* Freestanding linker shim for a currently unconditional Stage-0 print-float
 * runtime dependency. Kernel code uses no float printing; this safely
 * returns an empty output rather than depending on libc in ring 0.
 * Remove when Noqeri's freestanding backend omits hosted float formatting.
 */
.section .text
.code64
.global snprintf
.type snprintf,@function
snprintf:
    testq %rdi,%rdi
    jz 1f
    testq %rsi,%rsi
    jz 1f
    movb $0,(%rdi)
1:
    xorl %eax,%eax
    ret
.section .note.GNU-stack,"",@progbits
