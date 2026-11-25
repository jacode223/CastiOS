; HSFS6 v1. Independent volume on primary IDE.
; Header sector 8/9, table 16/48; writes use copy-on-write.
hs6_read_slot:
    ; EBX slot; return CF if corrupt. scratch and table are bounded.
    mov eax, ebx
    add eax, 8
    add eax, [hs6_base]
    mov rdi, hs6_header
    call ata_read64
    jc .bad
    cmp dword [hs6_header], 'HSFS'
    jne .bad
    cmp dword [hs6_header+4], 0x36
    jne .bad
    cmp dword [hs6_header+8], 6
    jne .bad
    cmp dword [hs6_header+12], 512
    jne .bad
    cmp dword [hs6_header+48], 1  ; 0 = legacy, 1 = HSFS6.1
    ja .bad
    mov eax, ebx
    shl eax, 5
    add eax, 16
    cmp qword [hs6_header+32], rax
    jne .bad
    mov edx, [hs6_header+44]
    mov dword [hs6_header+44], 0
    mov rsi, hs6_header
    mov ecx, 512
    call hs6_sum
    cmp eax, edx
    jne .bad
    mov rax, [hs6_header+24]
    cmp rax, 80
    jb .bad
    mov rdi, hs6_table
    mov r12d, ebx
    shl r12d, 5
    add r12d, 16
    mov r13d, 32
.read:
    mov eax, r12d
    add eax, [hs6_base]
    call ata_read64
    jc .bad
    inc r12d
    dec r13d
    jnz .read
    mov rsi, hs6_table
    mov ecx, 16384
    call hs6_sum
    cmp eax, [hs6_header+40]
    jne .bad
    ; Validate directory references, duplicate siblings and extents before mounting.
    push rbx
    mov rax, [hs6_header+24]
    mov [hs6_total], rax
    call hs6_validate_table
    pop rbx
    jc .bad
    clc
    ret
.bad:
    stc
    ret
hs6_sum:
    xor eax, eax
.loop:
    movzx r9d, byte [rsi]
    add eax, r9d
    inc rsi
    dec ecx
    jnz .loop
    ret
hs6_mount:
    mov byte [hs6_ready], 0
    mov dword [hs6_cwd], 0
    mov dword [hs6_base], 0
.try_base:
    mov qword [hs6_reserved_high], 80
    mov byte [hs6_first], 0
    xor ebx, ebx
    call hs6_read_slot
    jc .second
    call hs6_track_high
    mov byte [hs6_first], 1
    mov rax, [hs6_header+16]
    mov [hs6_generation], rax
.second:
    mov ebx, 1
    call hs6_read_slot
    jc .first
    call hs6_track_high
    cmp byte [hs6_first], 0
    je .ok
    mov rax, [hs6_header+16]
    cmp rax, [hs6_generation]
    ja .ok
.first:
    cmp byte [hs6_first], 1
    jne .bad
    xor ebx, ebx
    call hs6_read_slot
    jc .bad
.ok:
    mov rax, [hs6_header+24]
    mov [hs6_total], rax
    mov [hs6_active_slot], bl
    mov byte [hs6_ready], 1
    mov rsi, hs6_mount_ok
    jmp puts
.bad:
    cmp dword [hs6_base], 0
    jne .unavailable
    mov dword [hs6_base], 32768
    jmp .try_base
.unavailable:
    mov rsi, hs6_mount_bad
    jmp puts
; Preserve occupied allocation high-water across both valid snapshots.
hs6_track_high:
    mov rax, [hs6_high]
    cmp [hs6_reserved_high], rax
    jae .done
    mov [hs6_reserved_high], rax
.done:
    ret
hs6_ls:
    mov rsi, hs6_empty
    jmp hs6_ls_path
hs6_cat:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    cmp byte [rsi], 0
    je hs6_bad_entry
    call hs6_resolve
    jc hs6_bad_entry
    test rdi, rdi
    jz hs6_bad_entry
    cmp dword [rdi+64], 1
    jne hs6_bad_entry
    mov r14, [rdi+80]          ; 64-bit file length
    mov r15, [rdi+88]          ; 64-bit starting LBA
    cmp byte [hs6_stat_mode], 1
    jne .validate
    mov rsi, hs6_size_msg
    call puts
    mov rax, r14
    call hs6_decimal
    mov rsi, hs6_lba_msg
    call puts
    mov rax, r15
    call hs6_decimal
    mov al, 10
    call putc
    ret
.validate:
    cmp r15, 80
    jb hs6_bad_entry
    mov rax, r14
    add rax, 511
    jc hs6_bad_entry
    shr rax, 9
    mov rdx, r15
    add rdx, rax
    jc hs6_bad_entry
    cmp rdx, [hs6_total]
    ja hs6_bad_entry
    mov eax, [hs6_base]
    add rdx, rax
    jc hs6_too_large
    cmp rdx, 0x10000000
    ja hs6_too_large
.sector:
    test r14, r14
    jz .done
    mov eax, r15d
    add eax, [hs6_base]
    jc hs6_too_large
    mov rdi, hs6_sector
    call ata_read64
    jc hs6_bad_entry
    inc r15
    mov ecx, 512
    cmp r14, 512
    jae .emit
    mov ecx, r14d
.emit:
    sub r14, rcx
    mov rsi, hs6_sector
.char:
    mov al, [rsi]
    call putc
    inc rsi
    dec ecx
    jnz .char
    jmp .sector
.done:
    ret

hs6_not_mounted:
    mov rsi, hs6_nomount
    jmp puts
hs6_bad_entry:
    mov rsi, hs6_err
    jmp puts
hs6_too_large:
    mov rsi, hs6_limit
    jmp puts
hs6_decimal:
    mov ecx, 10
    lea rdi, [hs6_digits+20]
    mov byte [rdi], 0
.digit:
    xor edx, edx
    div rcx
    dec rdi
    add dl, '0'
    mov [rdi], dl
    test rax, rax
    jnz .digit
    mov rsi, rdi
    jmp puts
hs6_mount_ok db 'HSFS6 montado',10,0
hs6_empty db 0
hs6_mount_bad db 'HSFS6: ninguna copia valida',10,0
hs6_nomount db 'HSFS6 no montado',10,0
hs6_err db 'HSFS6: archivo inexistente o metadatos invalidos',10,0
hs6_limit db 'HSFS6: fuera del limite LBA28 del driver',10,0
hs6_size_msg db 'bytes=',0
hs6_lba_msg db ' lba=',0
hs6_ready db 0
hs6_first db 0
hs6_active_slot db 0
hs6_stat_mode db 0
hs6_generation dq 0
hs6_total dq 0
hs6_reserved_high dq 80
hs6_base dd 0
align 16
hs6_header times 512 db 0
hs6_sector times 512 db 0
hs6_digits times 21 db 0
hs6_table times 16384 db 0
