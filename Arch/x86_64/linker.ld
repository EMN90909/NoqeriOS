ENTRY(_start)

SECTIONS
{
    . = 1M;
    __kernel_start = .;

    .multiboot2 : ALIGN(8) {
        KEEP(*(.multiboot2))
    }

    .text : ALIGN(4K) {
        *(.text .text.*)
    }

    .rodata : ALIGN(4K) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(4K) {
        *(.data .data.*)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
    }

    . = ALIGN(4K);
    __kernel_end = .;

    . = 4M;
    __user_text_start = .;
    .usertext : ALIGN(4K) {
        *(.usertext)
    }
    __user_text_end = .;

    . = 6M;
    __user_stack_start = .;
    .userstack (NOLOAD) : ALIGN(4K) {
        *(.userstack)
    }
    __user_stack_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
