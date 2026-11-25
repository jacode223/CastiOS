; MiniDRV: fuentes editables desde el sistema, dispositivos virtuales internos.
%define DYNAMIC 0x740000
%define STAGING 0x73f000
cmd_drvnew:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    cmp dword [path_id], 0xfffffffe
    jne badname
    call getslot
    jc full
    call init_slot
    mov dword [edi+RLEN], mini_template_end-mini_template-1
    add edi, RDATA
    mov esi, mini_template
    call copy
    jmp sync
cmd_drvload:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call findfile
    jc missing
    call require_text
    jc badname
    cmp dword [edi+RLEN], LIMIT
    ja toolong
    lea esi, [edi+RDATA]
    mov eax, [edi+RLEN]
    add eax, esi
    mov [mini_end], eax
    push esi
    mov edi, STAGING
    xor eax, eax
    mov ecx, 128
    rep stosd
    pop esi
    mov dword [STAGING+56], 0xffffffff
    mov byte [mini_seen], 0
.line:
    cmp esi, [mini_end]
    jae .parsed
    mov edi, mini_line
    xor ecx, ecx
.char:
    cmp esi, [mini_end]
    jae .parse
    lodsb
    cmp al, 10
    je .parse
    cmp al, 13
    je .char
    cmp ecx, 255
    jae .error
    stosb
    inc ecx
    jmp .char
.parse:
    mov byte [edi], 0
    push esi
    mov esi, mini_line
    call spaces
    cmp byte [esi], 0
    je .next
    cmp byte [esi], ';'
    je .next
    cmp dword [esi], 'name'
    je .name
    cmp dword [esi], 'type'
    je .type
    cmp dword [esi], 'text'
    je .text
    jmp .bad
.name:
    test byte [mini_seen], 1
    jnz .bad
    or byte [mini_seen], 1
    cmp byte [esi+4], ' '
    jne .bad
    add esi, 5
    call spaces
    mov edi, STAGING+40
    xor ecx, ecx
.namechar:
    lodsb
    test al, al
    jz .name_end
    cmp ecx, 15
    jae .bad
    cmp al, 'a'
    jb .digit
    cmp al, 'z'
    jbe .valid
.digit:
    cmp al, '0'
    jb .underscore
    cmp al, '9'
    jbe .valid
.underscore:
    cmp al, '_'
    jne .bad
.valid:
    stosb
    inc ecx
    jmp .namechar
.name_end:
    test ecx, ecx
    jz .bad
    jmp .next
.type:
    test byte [mini_seen], 2
    jnz .bad
    or byte [mini_seen], 2
    cmp byte [esi+4], ' '
    jne .bad
    add esi, 5
    call spaces
    mov edi, mini_echo
    call equal
    je .echo
    mov edi, mini_text
    call equal
    je .constant
    mov edi, mini_counter
    call equal
    jne .bad
    mov dword [STAGING+56], 2
    jmp .next
.echo:
    mov dword [STAGING+56], 0
    jmp .next
.constant:
    mov dword [STAGING+56], 1
    jmp .next
.text:
    test byte [mini_seen], 4
    jnz .bad
    or byte [mini_seen], 4
    cmp byte [esi+4], ' '
    jne .bad
    add esi, 5
    call length
    cmp eax, 250
    ja .bad
    mov [STAGING+64], eax
    mov edi, STAGING+68
    call copy
.next:
    pop esi
    jmp .line
.bad:
    pop esi
.error:
    mov esi, mini_error
    jmp puts
.parsed:
    mov al, [mini_seen]
    and al, 3
    cmp al, 3
    jne .error
    mov edi, DYNAMIC
    mov ecx, 8
.free:
    cmp dword [edi], 0
    je .slot
    add edi, 512
    loop .free
    mov eax, ENOSPC
    jmp driver_error
.slot:
    mov ebx, edi
    mov esi, STAGING
    mov ecx, 128
    rep movsd
    mov dword [ebx+D_ABI], DRIVER_ABI
    lea eax, [ebx+40]
    mov [ebx+D_NAME], eax
    mov dword [ebx+D_CLASS], text_class
    mov dword [ebx+D_READ], mini_read
    cmp dword [ebx+56], 1
    je .register
    mov dword [ebx+D_WRITE], mini_write
.register:
    call driver_register
    test eax, eax
    jnz .rejected
    call driver_start
    test eax, eax
    jnz .rejected
    mov esi, mini_loaded
    jmp puts
.rejected:
    push eax
    mov edi, ebx
    xor eax, eax
    mov ecx, 128
    rep stosd
    pop eax
    jmp driver_error
mini_read:
    cmp dword [ebx+56], 2
    je .counter
    mov edx, [ebx+64]
    cmp edx, ecx
    jbe .copy
    mov edx, ecx
.copy:
    lea esi, [ebx+68]
    mov ecx, edx
    rep movsb
    xor eax, eax
    ret
.counter:
    mov eax, [ebx+60]
    mov esi, mini_decimal+16
    mov byte [esi], 0
    mov ebp, 10
.digits:
    xor edx, edx
    div ebp
    add dl, '0'
    dec esi
    mov [esi], dl
    test eax, eax
    jnz .digits
    mov edx, mini_decimal+16
    sub edx, esi
    cmp ecx, edx
    jb builtin_invalid
    mov ecx, edx
    rep movsb
    inc dword [ebx+60]
    xor eax, eax
    ret
mini_write:
    cmp dword [ebx+56], 2
    je .reset
    cmp ecx, 250
    ja builtin_invalid
    mov [ebx+64], ecx
    mov edx, ecx
    mov esi, edi
    lea edi, [ebx+68]
    rep movsb
    xor eax, eax
    ret
.reset:
    test ecx, ecx
    jnz builtin_invalid
    mov dword [ebx+60], 0
    xor eax, eax
    xor edx, edx
    ret
cmd_drvunload:
    mov esi, [args]
    call driver_find
    test eax, eax
    jnz driver_error
    mov ebx, edx
    cmp ebx, DYNAMIC
    jb .bad
    cmp ebx, DYNAMIC+8*512
    jae .bad
    mov ecx, 0
.find:
    cmp [driver_registry+ecx*4], ebx
    je .remove
    inc ecx
    cmp ecx, [driver_count]
    jb .find
    jmp .bad
.remove:
    inc ecx
    cmp ecx, [driver_count]
    jae .removed
    mov eax, [driver_registry+ecx*4]
    mov [driver_registry+ecx*4-4], eax
    jmp .remove
.removed:
    dec dword [driver_count]
    mov ecx, [driver_count]
    mov dword [driver_registry+ecx*4], 0
    mov edi, ebx
    xor eax, eax
    mov ecx, 128
    rep stosd
    mov esi, mini_unloaded
    jmp puts
.bad:
    mov eax, EINVAL
    jmp driver_error
mini_end dd 0
mini_seen db 0
mini_line times 256 db 0
mini_decimal times 17 db 0
mini_template db 'name demo',10,'type echo',10,'text Hola desde MiniDRV',10,0
mini_template_end:
mini_echo db 'echo',0
mini_text db 'text',0
mini_counter db 'counter',0
mini_loaded db 'MiniDRV activado.',10,0
mini_unloaded db 'MiniDRV retirado.',10,0
mini_error db 'Fuente MiniDRV invalido: usa name, type echo|text|counter y text opcional.',10,0
