/* Minimal x86-64 firmware ABI adapter for the Noqeri-generated UEFI loader.
 * No gnu-efi, libc, or C runtime. Firmware is Win64; Noqeri functions use SysV.
 * These stubs preserve Win64 nonvolatile registers at firmware entry and
 * allocate 32 bytes of home space for every EFIAPI firmware callback.
 */
.intel_syntax noprefix
.text
.globl efi_entry
efi_entry:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    mov rdi, rcx                    /* EFI_HANDLE -> first SysV argument */
    mov rsi, rdx                    /* EFI_SYSTEM_TABLE* -> second */
    call noqeri_uefi_main
    pop rsi
    pop rdi
    pop rbp
    ret

/* func pointer first, then up to five uint64 arguments. */
.globl efi_call1
efi_call1:
    push rbp
    mov rbp, rsp
    mov r11, rdi
    mov rcx, rsi
    sub rsp, 32
    call r11
    leave
    ret

.globl efi_call2
efi_call2:
    push rbp
    mov rbp, rsp
    mov r11, rdi
    mov rcx, rsi
    sub rsp, 32
    call r11
    leave
    ret

.globl efi_call3
efi_call3:
    push rbp
    mov rbp, rsp
    mov r11, rdi
    mov r8, rcx
    mov rcx, rsi
    sub rsp, 32
    call r11
    leave
    ret

.globl efi_call4
efi_call4:
    push rbp
    mov rbp, rsp
    mov r11, rdi
    mov r9, r8
    mov r8, rcx
    mov rcx, rsi
    sub rsp, 32
    call r11
    leave
    ret

.globl efi_call5
efi_call5:
    push rbp
    mov rbp, rsp
    mov r11, rdi
    sub rsp, 48                    /* 32 bytes shadow + 5th arg + alignment */
    mov QWORD PTR [rsp+32], r9
    mov r9, r8
    mov r8, rcx
    mov rcx, rsi
    call r11
    leave
    ret

/* Debugcon (QEMU/OVMF). Debug port is never part of the firmware ABI. */
.globl efi_debug
efi_debug:
    mov dx, 0xe9
.Ldebug_loop:
    mov al, BYTE PTR [rdi]
    test al, al
    jz .Ldebug_done
    out dx, al
    inc rdi
    jmp .Ldebug_loop
.Ldebug_done:
    ret

/* Firmware services already exited. Do not return to any EFIAPI caller. */
.globl efi_handoff
efi_handoff:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    jmp rax

/* Force a PE base-relocation record for firmware load-address randomization. */
.data
.globl efi_reloc_anchor
efi_reloc_anchor:
    .quad efi_entry
