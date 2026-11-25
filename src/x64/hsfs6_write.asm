; HSFS6 bounded copy-on-write for small text files. Primary IDE only.
; No write is attempted until IDENTIFY reports LBA, FLUSH and enough sectors.
hs6_identify:
    cmp byte [ahci64_active], 1
    je .bad                 ; AHCI is read-only in this version
    mov dx, 0x1f6
    mov al, 0xa0
    out dx, al
    mov dx, 0x3f6
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    mov dx, 0x1f2
    xor eax, eax
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    mov dx, 0x1f7
    mov al, 0xec
    out dx, al
    call hs6_wait_drq
    jc .bad
    mov dx, 0x1f0
    mov rdi, hs6_ident
    mov ecx, 256
    rep insw
    test word [hs6_ident+49*2], 1<<9
    jz .bad
    cmp byte [hs6_probe_only], 1
    je .capacity
    test word [hs6_ident+83*2], 1<<12
    jz .bad
.capacity:
    mov eax, [hs6_ident+60*2]
    test eax, eax
    jz .bad
    mov edx, [hs6_base]
    add rdx, [hs6_total]
    jc .bad
    cmp rax, rdx
    jb .bad
    clc
    ret
.bad:
    stc
    ret
hs6_wait_drq:
    mov dx, 0x1f7
    mov ecx, 1000000
.loop:
    in al, dx
    test al, al
    jz .bad
    cmp al, 0xff
    je .bad
    test al, 0x80
    jnz .again
    test al, 0x21
    jnz .bad
    test al, 8
    jnz .ok
.again:
    loop .loop
.bad:
    stc
    ret
.ok:
    clc
    ret
hs6_wait_complete:
    mov dx, 0x1f7
    mov ecx, 1000000
.loop:
    in al, dx
    test al, al
    jz .bad
    cmp al, 0xff
    je .bad
    test al, 0x80
    jnz .again
    test al, 0x21
    jnz .bad
    test al, 8
    jz .ok
.again:
    loop .loop
.bad:
    stc
    ret
.ok:
    clc
    ret
hs6_flush:
    mov dx, 0x1f7
    mov al, 0xe7
    out dx, al
    call hs6_wait_complete
    ret
hs6_write_sector:
    ; EAX=LBA, RSI=512 bytes; CF on error.
    add eax, [hs6_base]
    jc .bad
    cmp eax, 0x10000000
    jae .bad
    mov r8d, eax
    mov dx, 0x1f6
    shr eax, 24
    and al, 15
    or al, 0xe0
    out dx, al
    mov dx, 0x3f6
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    mov dx, 0x1f2
    mov al, 1
    out dx, al
    inc dx
    mov eax, r8d
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    mov dx, 0x1f7
    mov al, 0x30
    out dx, al
    call hs6_wait_drq
    jc .bad
    mov dx, 0x1f0
    mov ecx, 256
    rep outsw
    call hs6_wait_complete
    ret
.bad:
    stc
    ret

; Validate HSFS6 legacy and HSFS6.1 trees, live extents and sibling names.
; Input: hs6_table + hs6_total + header minor; output CF. hs6_high is
; highest end of live data and the persistent allocation watermark.
hs6_validate_table:
    xor ebx, ebx
    mov qword [hs6_high], 80
.entry:
    cmp ebx, 128
    jae .ok
    mov eax, ebx
    shl rax, 7
    lea rdi, [hs6_table+rax]
    cmp byte [rdi], 0
    je .next
    cmp byte [rdi+63], 0
    jne .bad
    mov edx, [rdi+64]
    cmp edx, 1
    je .kind_ok
    cmp edx, 2
    jne .bad
    cmp dword [hs6_header+48], 1
    jne .bad
    cmp qword [rdi+80], 0
    jne .bad
    cmp qword [rdi+88], 80
    jne .bad
.kind_ok:
    cmp dword [hs6_header+48], 0
    jne .parent
    cmp dword [rdi+96], 0
    jne .bad
.parent:
    ; Every ancestor must exist, be a directory, and eventually reach root.
    mov r11d, [rdi+96]
    xor r9d, r9d
.ancestor:
    test r11d, r11d
    jz .name_start
    cmp r11d, 128
    ja .bad
    lea eax, [ebx+1]
    cmp r11d, eax
    je .bad
    inc r9d
    cmp r9d, 128
    ja .bad
    mov eax, r11d
    dec eax
    shl rax, 7
    lea rsi, [hs6_table+rax]
    cmp byte [rsi], 0
    je .bad
    cmp dword [rsi+64], 2
    jne .bad
    mov r11d, [rsi+96]
    jmp .ancestor
.name_start:
    cmp byte [rdi], '.'
    jne .name_scan
    cmp byte [rdi+1], 0
    je .bad
    cmp word [rdi+1], '.'
    je .bad
.name_scan:
    xor ecx, ecx
.name:
    mov al, [rdi+rcx]
    test al, al
    jz .range
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    jbe .name_next
.upper:
    cmp al, 'A'
    jb .digit
    cmp al, 'Z'
    jbe .name_next
.digit:
    cmp al, '0'
    jb .punct
    cmp al, '9'
    jbe .name_next
.punct:
    cmp al, '.'
    je .name_next
    cmp al, '_'
    je .name_next
    cmp al, '-'
    jne .bad
.name_next:
    inc ecx
    cmp ecx, 63
    ja .bad
    jmp .name
.range:
    cmp dword [rdi+64], 2
    je .duplicates
    mov rax, [rdi+80]
    add rax, 511
    jc .bad
    shr rax, 9
    mov rdx, [rdi+88]
    cmp rdx, 80
    jb .bad
    add rax, rdx
    jc .bad
    cmp rax, [hs6_total]
    ja .bad
    cmp rax, [hs6_high]
    jbe .duplicates
    mov [hs6_high], rax
.duplicates:
    xor r10d, r10d
.compare:
    cmp r10d, ebx
    jae .next
    mov eax, r10d
    shl rax, 7
    lea rsi, [hs6_table+rax]
    cmp byte [rsi], 0
    je .compare_next
    mov eax, [rdi+96]
    cmp [rsi+96], eax
    jne .overlap
    call streq
    je .bad
.overlap:
    cmp dword [rdi+64], 1
    jne .compare_next
    cmp dword [rsi+64], 1
    jne .compare_next
    cmp qword [rdi+80], 0
    je .compare_next
    cmp qword [rsi+80], 0
    je .compare_next
    mov rax, [rdi+80]
    add rax, 511
    jc .bad
    shr rax, 9
    add rax, [rdi+88]
    jc .bad
    mov rdx, [rsi+80]
    add rdx, 511
    jc .bad
    shr rdx, 9
    add rdx, [rsi+88]
    jc .bad
    cmp [rsi+88], rax
    jae .compare_next
    cmp [rdi+88], rdx
    jb .bad
.compare_next:
    inc r10d
    jmp .compare
.next:
    inc ebx
    jmp .entry
.ok:
    clc
    ret
.bad:
    stc
    ret

hs6_write:
    ; write6 PATH TEXT, a single short text sector.  Larger file payloads
    ; can be populated by the host; 64-bit offset reads remain supported.
    mov dword [hs6_write_status], 0
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    mov rdi, hs6_write_name
    xor ecx, ecx
.parse_name:
    mov al, [rsi]
    cmp al, ' '
    je .end_name
    test al, al
    jz .syntax
    cmp ecx, 63
    jae .syntax
    mov [rdi+rcx], al
    inc ecx
    inc rsi
    jmp .parse_name
.end_name:
    test ecx, ecx
    jz .syntax
    mov byte [rdi+rcx], 0
.spaces:
    inc rsi
    cmp byte [rsi], ' '
    je .spaces
    cmp byte [rsi], 0
    je .syntax
    mov [hs6_text_ptr], rsi
    xor ecx, ecx
.text_len:
    cmp byte [rsi+rcx], 0
    je .text_end
    inc ecx
    cmp ecx, 511
    jae .syntax
    jmp .text_len
.text_end:
    mov [hs6_text_len], ecx
.commit_text:
    mov rsi, hs6_write_name
    call hs6_prepare_create
    jc .invalid
    call hs6_identify
    jc .io
    call hs6_validate_table
    jc .invalid
    ; Keep the persistent high-water mark of previously committed extents.
    mov rax, [hs6_high]
    cmp [hs6_header+56], rax
    jbe .snapshot_high
    mov rax, [hs6_header+56]
.snapshot_high:
    cmp [hs6_reserved_high], rax
    jbe .high_ready
    mov rax, [hs6_reserved_high]
.high_ready:
    mov [hs6_alloc_high], rax
    call hs6_find_slot
    jc .full
    cmp dword [hs6_existing_type], 2
    je .invalid
    ; This copy-on-write append does not reuse a still-live extent.
    mov eax, [hs6_slot]
    shl rax, 7
    lea rdi, [hs6_table+rax]
    mov [hs6_record_ptr], rdi
    mov rcx, 16
    xor eax, eax
    rep stosq
    mov rdi, [hs6_record_ptr]
    mov rsi, hs6_leaf
    mov ecx, 64
    rep movsb
    mov rdi, [hs6_record_ptr]
    mov dword [rdi+64], 1
    mov dword [rdi+76], 0644o
    mov eax, [hs6_text_len]
    mov [rdi+80], rax
    mov rax, [hs6_alloc_high]
    cmp rax, 0x0fffffff
    jae .full
    cmp rax, [hs6_total]
    jae .full
    mov [hs6_write_lba], eax
    mov [rdi+88], rax
    mov eax, [hs6_target_parent]
    mov [rdi+96], eax
    call hs6_validate_table
    jc .invalid
    cmp qword [hs6_header+16], -1
    je .invalid
    ; Data first, metadata second: interrupted writes keep old generation.
    mov rdi, hs6_sector
    xor eax, eax
    mov ecx, 64
    rep stosq
    mov rdi, hs6_sector
    mov rsi, [hs6_text_ptr]
    mov ecx, [hs6_text_len]
    rep movsb
    mov eax, [hs6_write_lba]
    mov rsi, hs6_sector
    call hs6_write_sector
    jc .io
    call hs6_flush
    jc .io
    inc qword [hs6_alloc_high]
    call hs6_commit
    jc .io
    mov rsi, hs6_written
    jmp puts
.syntax:
    mov dword [hs6_write_status], -22
    mov rsi, hs6_write_usage
    jmp puts
.full:
    mov dword [hs6_write_status], -28
    mov rsi, hs6_write_full
    jmp .fail
.invalid:
    mov dword [hs6_write_status], -22
    mov rsi, hs6_write_invalid
    jmp .fail
.io:
    mov dword [hs6_write_status], -5
    mov rsi, hs6_write_io
.fail:
    mov byte [hs6_ready], 0
    jmp puts

; Kernel-only binary writer: RSI=NUL path, RDX=source, ECX=1..511.
hs6_write_binary:
    mov dword [hs6_write_status], 0
    cmp byte [hs6_ready], 1
    jne .no_mount
    test ecx, ecx
    jz .invalid
    cmp ecx, 511
    ja .invalid
    mov [hs6_text_ptr], rdx
    mov [hs6_text_len], ecx
    mov rdi, hs6_write_name
    xor ecx, ecx
.copy:
    mov al, [rsi+rcx]
    cmp ecx, 63
    jae .invalid
    mov [rdi+rcx], al
    inc ecx
    test al, al
    jnz .copy
    cmp ecx, 1
    je .invalid
    jmp hs6_write.commit_text
.no_mount:
    mov dword [hs6_write_status], -19
    mov rsi, shell_ext_no_mount
    jmp puts
.invalid:
    mov dword [hs6_write_status], -22
    mov rsi, shell_ext_bad
    jmp puts

; Find a free record or an existing same-named child of target_parent.
; CF=1 when full.  Returns hs6_slot and hs6_existing_type (0 if new).
hs6_find_slot:
    mov dword [hs6_slot], 0xffffffff
    mov dword [hs6_existing_type], 0
    xor ebx, ebx
.find:
    cmp ebx, 128
    jae .finish
    mov eax, ebx
    shl rax, 7
    lea rdi, [hs6_table+rax]
    cmp byte [rdi], 0
    jne .compare
    cmp dword [hs6_slot], 0xffffffff
    jne .next
    mov [hs6_slot], ebx
    jmp .next
.compare:
    mov eax, [hs6_target_parent]
    cmp dword [rdi+96], eax
    jne .next
    mov rsi, hs6_leaf
    call streq
    jne .next
    mov [hs6_slot], ebx
    mov eax, [rdi+64]
    mov [hs6_existing_type], eax
    jmp .ok
.next:
    inc ebx
    jmp .find
.finish:
    cmp dword [hs6_slot], 0xffffffff
    je .no
.ok:
    clc
    ret
.no:
    stc
    ret

; Publish the metadata mirror then header.  On error the caller unmounts.
hs6_commit:
    movzx r12d, byte [hs6_active_slot]
    xor r12d, 1
    mov r13d, r12d
    shl r13d, 5
    add r13d, 16
    mov r14d, 32
    mov r15, hs6_table
.table:
    mov eax, r13d
    mov rsi, r15
    call hs6_write_sector
    jc .bad
    add r15, 512
    inc r13d
    dec r14d
    jnz .table
    call hs6_flush
    jc .bad
    mov rsi, hs6_table
    mov ecx, 16384
    call hs6_sum
    mov [hs6_header+40], eax
    inc qword [hs6_header+16]
    mov eax, r12d
    shl eax, 5
    add eax, 16
    mov [hs6_header+32], rax
    mov rax, [hs6_alloc_high]
    cmp [hs6_header+56], rax
    jae .watermark_ok
    mov [hs6_header+56], rax
.watermark_ok:
    mov dword [hs6_header+44], 0
    mov rsi, hs6_header
    mov ecx, 512
    call hs6_sum
    mov [hs6_header+44], eax
    lea eax, [r12+8]
    mov rsi, hs6_header
    call hs6_write_sector
    jc .bad
    call hs6_flush
    jc .bad
    mov [hs6_active_slot], r12b
    mov rax, [hs6_alloc_high]
    mov [hs6_reserved_high], rax
    clc
    ret
.bad:
    stc
    ret

hs6_mkdir:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    cmp dword [hs6_header+48], 1
    jne .invalid
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
    mov [hs6_alloc_high], rax
    call hs6_find_slot
    jc .full
    cmp dword [hs6_existing_type], 0
    jne .invalid
    mov eax, [hs6_slot]
    shl rax, 7
    lea rdi, [hs6_table+rax]
    mov rcx, 16
    xor eax, eax
    rep stosq
    mov eax, [hs6_slot]
    shl rax, 7
    lea rdi, [hs6_table+rax]
    mov rsi, hs6_leaf
    mov ecx, 64
    rep movsb
    mov eax, [hs6_slot]
    shl rax, 7
    lea rdi, [hs6_table+rax]
    mov dword [rdi+64], 2
    mov dword [rdi+76], 0755o
    mov qword [rdi+80], 0
    mov qword [rdi+88], 80
    mov eax, [hs6_target_parent]
    mov [rdi+96], eax
    call hs6_validate_table
    jc .invalid
    call hs6_commit
    jc .io
    mov rsi, hs6_mkdir_ok
    jmp puts
.full:
    mov rsi, hs6_write_full
    jmp .fail
.invalid:
    mov rsi, hs6_write_invalid
    jmp .fail
.io:
    mov rsi, hs6_write_io
.fail:
    mov byte [hs6_ready], 0
    jmp puts

hs6_ident times 512 db 0
hs6_probe_only db 0
hs6_write_name times 64 db 0
hs6_existing_type dd 0
hs6_alloc_high dq 0
hs6_text_ptr dq 0
hs6_record_ptr dq 0
hs6_high dq 0
hs6_text_len dd 0
hs6_slot dd 0
hs6_write_lba dd 0
hs6_write_status dd 0
hs6_write_usage db 'Uso: write6 nombre texto',10,0
hs6_write_full db 'HSFS6: sin espacio o fuera de LBA28; vuelve a montar',10,0
hs6_write_invalid db 'HSFS6: metadatos o nombre invalidos; vuelve a montar',10,0
hs6_write_io db 'HSFS6: error ATA o FLUSH; vuelve a montar',10,0
hs6_written db 'HSFS6: archivo guardado',10,0
hs6_mkdir_ok db 'HSFS6: directorio creado',10,0
