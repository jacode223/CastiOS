; AX05 file ABI, root files. One descriptor (3) per process.
; EAX=6 open(EBX=name,ECX=len), 7 read(EBX=3,ECX=buf,EDX<=256),
; 8 close(EBX=3), 9 stat(EBX=name,ECX=len,EDX=8-byte output),
; 10 write(EBX=3,ECX=buf,EDX<=256): existing single-record text files.
sys_slot:
    xor edi, edi
    cmp byte [mt_active], 0
    je .done
    mov edi, [mt_current]
    inc edi
.done:
    ret
; ESI pointer, ECX length. CF clear only inside a single user page.
sys_user_range:
    test ecx, ecx
    jz .ok
    mov eax, esi
    sub eax, USER_BASE
    jc .bad
.ordinary:
    cmp eax, 4096
    jb .window
    cmp eax, 0x8000
    jb .old_pages
    cmp eax, 0xc000
    jae .bad
    push eax
    call demand_present
    test eax, eax
    pop eax
    jz .bad
    and eax, 4095
    jmp .window
.old_pages:
    cmp eax, 0x4000
    jb .stack
    sub eax, 0x4000
    cmp eax, 4096
    jae .bad
    push eax
    call swap_page_address
    test eax, eax
    pop eax
    jz .bad
    jmp .window
.stack:
    sub eax, 8192
    jc .bad
    cmp eax, 4096
    jae .bad
.window:
    mov edx, 4096
    sub edx, eax
    cmp ecx, edx
    ja .bad
.ok:
    clc
    ret
.bad:
    stc
    ret
; Output buffer variant: code page is read-only. Other pages have to
; pass the existing range and residency check first.
sys_user_writable:
    call sys_user_range
    jc .bad
    test ecx, ecx
    jz .ok
    mov eax, esi
    sub eax, USER_BASE
    jc .bad
    cmp eax, 4096
    jb .bad
.ok:
    clc
    ret
.bad:
    stc
    ret
sys_getname:
    test ecx, ecx
    jz .invalid
    cmp ecx, 31
    ja .invalid
    mov esi, ebx
    call sys_user_range
    jc .fault
    mov esi, ebx
    mov edi, sys_name
    mov edx, ecx
.char:
    lodsb
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    jbe .store
.upper:
    cmp al, 'A'
    jb .digit
    cmp al, 'Z'
    jbe .store
.digit:
    cmp al, '0'
    jb .punct
    cmp al, '9'
    jbe .store
.punct:
    cmp al, '.'
    je .store
    cmp al, '_'
    je .store
    cmp al, '-'
    jne .invalid
.store:
    stosb
    dec edx
    jnz .char
    mov byte [edi], 0
    cmp word [sys_name], 0x002e
    je .invalid
    cmp ecx, 2
    jne .ok
    cmp word [sys_name], 0x2e2e
    je .invalid
.ok:
    clc
    ret
.invalid:
    mov eax, -22
    stc
    ret
.fault:
    mov eax, -14
    stc
    ret
sys_find:
    mov edi, RECORDS
    mov ecx, NFILES
.next:
    cmp byte [edi], 0
    je .skip
    cmp dword [edi+RPARENT], ROOT_ID
    jne .skip
    mov esi, sys_name
    call equal
    je .found
.skip:
    add edi, RSIZE
    loop .next
    stc
    ret
.found:
    clc
    ret
sys_open:
    call sys_getname
    jc .done
    call sys_find
    jc .missing
    mov eax, [edi+RKIND]
    cmp eax, 1
    je .found
    cmp eax, 3
    jne .invalid
.found:
    mov eax, edi
    sub eax, RECORDS
    shr eax, 13
    inc eax
    push eax
    call sys_slot
    pop eax
    mov [sys_fd_head+edi*4], eax
    mov dword [sys_fd_pos+edi*4], 0
    mov eax, 3
.done:
    ret
.missing:
    mov eax, -2
    ret
.invalid:
    mov eax, -21
    ret
sys_read:
    cmp ebx, 3
    jne .badfd
    cmp edx, 256
    ja .invalid
    push ecx
    push edx
    mov esi, ecx
    mov ecx, edx
    call sys_user_writable
    pop edx
    pop ecx
    jc .fault
    call sys_slot
    mov eax, [sys_fd_head+edi*4]
    test eax, eax
    jz .badfd
    dec eax
    shl eax, 13
    add eax, RECORDS
    mov [sys_record], eax
    mov eax, [sys_fd_pos+edi*4]
    mov ebp, [sys_record]
    mov esi, [ebp+RLEN]
    cmp eax, esi
    jae .zero
    sub esi, eax
    cmp edx, esi
    jbe .take
    mov edx, esi
.take:
    mov [sys_remaining], edx
    mov [sys_total], edx
    mov [sys_dest], ecx
.chunk:
    mov eax, [sys_fd_pos+edi*4]
    xor edx, edx
    mov ecx, LIMIT
    div ecx
    mov esi, [sys_record]
.follow:
    test eax, eax
    jz .offset
    mov esi, [esi+44]
    dec esi
    shl esi, 13
    add esi, RECORDS
    dec eax
    jmp .follow
.offset:
    add esi, RDATA
    add esi, edx
    mov ecx, LIMIT
    sub ecx, edx
    cmp ecx, [sys_remaining]
    jbe .copy
    mov ecx, [sys_remaining]
.copy:
    mov edx, ecx
    push edi
    mov edi, [sys_dest]
    rep movsb
    mov [sys_dest], edi
    pop edi
    add [sys_fd_pos+edi*4], edx
    sub [sys_remaining], edx
    jnz .chunk
    mov eax, [sys_total]
    ret
.zero:
    xor eax, eax
    ret
.fault:
    mov eax, -14
    ret
.invalid:
    mov eax, -22
    ret
.badfd:
    mov eax, -9
    ret
sys_close:
    cmp ebx, 3
    jne .bad
    call sys_slot
    cmp dword [sys_fd_head+edi*4], 0
    je .bad
    mov dword [sys_fd_head+edi*4], 0
    xor eax, eax
    ret
.bad:
    mov eax, -9
    ret
sys_stat:
    push edx
    call sys_getname
    jc .failed
    call sys_find
    jc .missing
    mov ebp, edi
    pop esi
    mov ecx, 8
    call sys_user_writable
    jc .fault
    mov eax, [ebp+RKIND]
    mov [esi], eax
    mov eax, [ebp+RLEN]
    mov [esi+4], eax
    xor eax, eax
    ret
.fault:
    mov eax, -14
    ret
.missing:
    pop edx
    mov eax, -2
    ret
.failed:
    pop edx
    ret
; Write into an existing one-record text file at the descriptor offset.
sys_file_write:
    cmp ebx, 3
    jne sys_read.badfd
    call sys_write_allowed
    test eax, eax
    jz .denied
    cmp byte [persistent], 1
    jne .readonly
    cmp edx, 256
    ja sys_read.invalid
    push ecx
    push edx
    mov esi, ecx
    mov ecx, edx
    call sys_user_range
    pop edx
    pop ecx
    jc sys_read.fault
    call sys_slot
    mov eax, [sys_fd_head+edi*4]
    test eax, eax
    jz sys_read.badfd
    dec eax
    shl eax, 13
    add eax, RECORDS
    cmp dword [eax+RKIND], 1
    jne .readonly
    cmp dword [eax+RLEN], LIMIT
    ja sys_read.invalid
    mov ebp, [sys_fd_pos+edi*4]
    cmp ebp, LIMIT
    ja sys_read.invalid
    mov esi, ebp
    add esi, edx
    cmp esi, LIMIT
    ja sys_read.invalid
    mov [sys_record], eax
    mov [sys_total], edx
    test edx, edx
    jz .zero
    mov [sys_dest], ecx
    mov esi, ecx
    mov ecx, edx
.validate:
    jecxz .copy
    lodsb
    cmp al, 10
    je .valid
    cmp al, 32
    jb sys_read.invalid
    cmp al, 126
    ja sys_read.invalid
.valid:
    loop .validate
.copy:
    mov eax, [sys_record]
    cmp dword [eax+44], 0
    jne sys_read.invalid
    lea edi, [eax+RDATA+ebp]
    mov esi, [sys_dest]
    mov ecx, [sys_total]
    rep movsb
    mov eax, [sys_record]
    mov ebx, [eax+RLEN]
    mov edx, ebp
    add edx, [sys_total]
    cmp edx, ebx
    jbe .length
    mov [eax+RLEN], edx
    mov ebx, edx
.length:
    mov byte [eax+RDATA+ebx], 0
    call sys_slot
    mov [sys_fd_pos+edi*4], edx
    call sync
    cmp byte [persistent], 1
    jne .ioerror
    mov eax, [sys_total]
    ret
.zero:
    xor eax, eax
    ret
.ioerror:
    mov eax, -5
    ret
.readonly:
    mov eax, -30
    ret
.denied:
    mov eax, -13                ; EACCES: AX05 has no file-write capability
    ret
sys_write_allowed:
    xor eax, eax
    cmp byte [mt_active], 0
    je .single
    mov edi, [mt_current]
    cmp edi, [mt_count]
    jae .done
    imul edi, MT_SIZE
    mov eax, [mt_table+edi+MT_CAP]
    jmp .done
.single:
    mov eax, [process_cap]
.done:
    ret
sys_name times 32 db 0
sys_fd_head times 5 dd 0
sys_fd_pos times 5 dd 0
sys_record dd 0
sys_dest dd 0
sys_remaining dd 0
sys_total dd 0
