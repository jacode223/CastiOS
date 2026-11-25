; read6 RUTA OFFSET NUM_BYTES: display at most 512 bytes of a large file.
; Works with 64-bit offsets, so callers don't have to dump huge files via cat.
hs6_read_range:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    ; Token 1: pathname, until first space.
    mov rdi, hs6_range_path
    xor ecx, ecx
.path:
    mov al, [rsi]
    cmp al, ' '
    je .path_done
    test al, al
    jz .syntax
    cmp ecx, 63
    jae .syntax
    mov [rdi+rcx], al
    inc rsi
    inc ecx
    jmp .path
.path_done:
    test ecx, ecx
    jz .syntax
    mov byte [rdi+rcx], 0
    call hs6_skip_spaces
    call hs6_parse_u64
    jc .syntax
    mov [hs6_range_offset], rax
    call hs6_skip_spaces
    call hs6_parse_u64
    jc .syntax
    test rax, rax
    jz .syntax
    cmp rax, 512
    ja .syntax
    mov [hs6_range_count], rax
    call hs6_skip_spaces
    cmp byte [rsi], 0
    jne .syntax
    mov rsi, hs6_range_path
    call hs6_resolve
    jc hs6_bad_entry
    test rdi, rdi
    jz hs6_bad_entry
    cmp dword [rdi+64], 1
    jne hs6_bad_entry
    mov r14, [rdi+80]
    mov r15, [rdi+88]
    mov r12, [hs6_range_offset]
    cmp r12, r14
    jae .done
    sub r14, r12
    mov r13, [hs6_range_count]
    cmp r13, r14
    jbe .bounded
    mov r13, r14
.bounded:
    mov rax, [rdi+80]
    add rax, 511
    jc hs6_bad_entry
    shr rax, 9
    add rax, r15
    jc hs6_bad_entry
    cmp rax, [hs6_total]
    ja hs6_bad_entry
    mov edx, [hs6_base]
    add rax, rdx
    jc hs6_too_large
    cmp rax, 0x10000000
    ja hs6_too_large
.loop:
    test r13, r13
    jz .done
    mov rax, r12
    shr rax, 9
    add rax, r15
    mov edx, [hs6_base]
    add rax, rdx
    jc hs6_too_large
    cmp rax, 0x10000000
    jae hs6_too_large
    mov rdi, hs6_sector
    call ata_read64
    jc hs6_bad_entry
    mov rax, r12
    and eax, 511
    mov ecx, 512
    sub ecx, eax
    cmp rcx, r13
    jbe .emit
    mov rcx, r13
.emit:
    sub r13, rcx
    add r12, rcx
    lea rsi, [hs6_sector+rax]
.bytes:
    mov al, [rsi]
    call putc
    inc rsi
    dec ecx
    jnz .bytes
    jmp .loop
.done:
    mov al, 10
    jmp putc
.syntax:
    mov rsi, hs6_range_usage
    jmp puts

hs6_skip_spaces:
    cmp byte [rsi], ' '
    jne .done
    inc rsi
    jmp hs6_skip_spaces
.done:
    ret

; Parse an unsigned decimal <= 2^64-1, reject overflow / empty values.
; RSI updated to first separator, CF=0 and RAX=value if valid.
hs6_parse_u64:
    xor r8d, r8d
    xor r9d, r9d
.next:
    movzx ecx, byte [rsi]
    cmp ecx, '0'
    jb .done
    cmp ecx, '9'
    ja .done
    sub ecx, '0'
    mov rax, r8
    mov r10d, 10
    mul r10
    test rdx, rdx
    jnz .bad
    add rax, rcx
    jc .bad
    mov r8, rax
    inc r9d
    inc rsi
    jmp .next
.done:
    test r9d, r9d
    jz .bad
    mov rax, r8
    clc
    ret
.bad:
    stc
    ret

hs6_range_offset dq 0
hs6_range_count dq 0
hs6_range_path times 64 db 0
hs6_range_usage db 'Uso: read6 ruta offset bytes (1..512)',10,0
