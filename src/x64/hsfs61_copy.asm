; cp ORIGEN DESTINO: 512-byte streaming copy, max 500 MiB. COW commit.
hs6_copy:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    mov rdi, hs6_cp_source
    call hs6_cp_token
    jc .usage
    mov rdi, hs6_cp_dest
    call hs6_cp_token
    jc .usage
    call hs6_skip_spaces
    cmp byte [rsi], 0
    jne .usage
    mov rsi, hs6_cp_source
    call hs6_resolve
    jc .invalid
    test rdi, rdi
    jz .invalid
    cmp dword [rdi+64], 1
    jne .invalid
    mov rax, [rdi+80]
    cmp rax, 524288000
    ja .full
    mov [hs6_cp_size], rax
    add rax, 511
    jc .invalid
    shr rax, 9
    mov [hs6_cp_sectors], rax
    mov rax, [rdi+88]
    mov [hs6_cp_src_lba], rax
    mov rsi, hs6_cp_dest
    call hs6_prepare_create
    jc .invalid
    call hs6_identify
    jc .io
    call hs6_validate_table
    jc .invalid
    mov rax, [hs6_high]
    cmp [hs6_header+56], rax
    jbe .snapshot_high
    mov rax, [hs6_header+56]
.snapshot_high:
    cmp [hs6_reserved_high], rax
    jbe .high_ready
    mov rax, [hs6_reserved_high]
.high_ready:
    mov [hs6_cp_dst_lba], rax
    add rax, [hs6_cp_sectors]
    jc .full
    cmp rax, [hs6_total]
    ja .full
    mov edx, [hs6_base]
    add rax, rdx
    jc .full
    cmp rax, 0x10000000
    ja .full
    call hs6_find_slot
    jc .full
    cmp dword [hs6_existing_type], 2
    je .invalid
    mov eax, [hs6_slot]
    shl rax, 7
    lea rdi, [hs6_table+rax]
    mov [hs6_record_ptr], rdi
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov rdi, [hs6_record_ptr]
    mov rsi, hs6_leaf
    mov ecx, 64
    rep movsb
    mov rdi, [hs6_record_ptr]
    mov dword [rdi+64], 1
    mov dword [rdi+76], 0644o
    mov rax, [hs6_cp_size]
    mov [rdi+80], rax
    mov rax, [hs6_cp_dst_lba]
    mov [rdi+88], rax
    mov eax, [hs6_target_parent]
    mov [rdi+96], eax
    call hs6_validate_table
    jc .invalid
    cmp qword [hs6_header+16], -1
    je .invalid
    mov qword [hs6_cp_progress], 0
.loop:
    mov rax, [hs6_cp_progress]
    cmp rax, [hs6_cp_sectors]
    jae .sync
    add rax, [hs6_cp_src_lba]
    jc .io
    mov edx, [hs6_base]
    add rax, rdx
    jc .io
    cmp rax, 0x10000000
    jae .io
    mov rdi, hs6_sector
    call ata_read64
    jc .io
    mov rax, [hs6_cp_dst_lba]
    add rax, [hs6_cp_progress]
    mov rsi, hs6_sector
    call hs6_write_sector
    jc .io
    inc qword [hs6_cp_progress]
    jmp .loop
.sync:
    call hs6_flush
    jc .io
    mov rax, [hs6_cp_dst_lba]
    add rax, [hs6_cp_sectors]
    mov [hs6_alloc_high], rax
    call hs6_commit
    jc .io
    mov rsi, hs6_cp_ok
    jmp puts
.usage:
    mov rsi, hs6_cp_usage
    jmp puts
.invalid:
    mov rsi, hs6_write_invalid
    jmp .fail
.full:
    mov rsi, hs6_write_full
    jmp .fail
.io:
    mov rsi, hs6_write_io
.fail:
    mov byte [hs6_ready], 0
    jmp puts
hs6_cp_token:
    call hs6_skip_spaces
    xor ecx, ecx
.copy:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, ' '
    je .end
    cmp ecx, 63
    jae .bad
    mov [rdi+rcx], al
    inc ecx
    inc rsi
    jmp .copy
.end:
    test ecx, ecx
    jz .bad
    mov byte [rdi+rcx], 0
    clc
    ret
.bad:
    stc
    ret
hs6_cp_source times 64 db 0
hs6_cp_dest times 64 db 0
hs6_cp_size dq 0
hs6_cp_sectors dq 0
hs6_cp_src_lba dq 0
hs6_cp_dst_lba dq 0
hs6_cp_progress dq 0
hs6_cp_ok db 'Copia terminada',10,0
hs6_cp_usage db 'Uso: cp origen destino (maximo 500 MiB)',10,0
