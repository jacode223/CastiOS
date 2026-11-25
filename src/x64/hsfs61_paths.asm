; HSFS 6.1 directory / path helpers. IDs are table index + 1; root = 0.
; A path is absolute when it starts with '/', otherwise relative to cwd.
; hs6_resolve: RSI=NUL path, CF=0 RDI=record pointer or 0 for /,
; EBX=record index or -1.  CF=1 for missing or invalid path.
hs6_resolve:
    push r12
    push r13
    push r14
    push r15
    mov r14, rsi
    mov r13d, [hs6_cwd]
    cmp byte [r14], '/'
    jne .next_component
    xor r13d, r13d
.next_component:
    cmp byte [r14], '/'
    jne .start
    inc r14
    jmp .next_component
.start:
    cmp byte [r14], 0
    je .resolved
    xor r12d, r12d
.copy:
    mov al, [r14]
    cmp al, 0
    je .copied
    cmp al, '/'
    je .copied
    cmp r12d, 63
    jae .bad
    mov [hs6_part+r12], al
    inc r12d
    inc r14
    jmp .copy
.copied:
    cmp r12d, 0
    je .bad
    mov byte [hs6_part+r12], 0
    cmp word [hs6_part], '.'
    jne .not_dot
    cmp byte [hs6_part+2], 0
    je .next_component
.not_dot:
    cmp word [hs6_part], '..'
    jne .normal
    cmp byte [hs6_part+2], 0
    jne .normal
    test r13d, r13d
    jz .next_component
    mov eax, r13d
    dec eax
    shl rax, 7
    mov r13d, [hs6_table+rax+96]
    jmp .next_component
.normal:
    xor ebx, ebx
.scan:
    cmp ebx, 128
    jae .bad
    mov eax, ebx
    shl rax, 7
    lea rdi, [hs6_table+rax]
    cmp byte [rdi], 0
    je .scan_next
    cmp dword [rdi+96], r13d
    jne .scan_next
    mov rsi, hs6_part
    call streq
    je .matched
.scan_next:
    inc ebx
    jmp .scan
.matched:
    mov r13d, ebx
    inc r13d
    cmp byte [r14], 0
    je .resolved
    cmp dword [rdi+64], 2
    jne .bad
    jmp .next_component
.resolved:
    test r13d, r13d
    jz .root
    mov ebx, r13d
    dec ebx
    mov eax, ebx
    shl rax, 7
    lea rdi, [hs6_table+rax]
    cmp byte [rdi], 0
    je .bad
    clc
    jmp .return
.root:
    mov rbx, -1
    xor edi, edi
    clc
    jmp .return
.bad:
    stc
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; Input RSI pathname. Returns CF=0, leaf name at hs6_leaf,
; parent directory ID at hs6_target_parent; rejects slash-terminated names.
hs6_prepare_create:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov rdi, hs6_path_copy
    xor ecx, ecx
.copy:
    mov al, [r12+rcx]
    cmp ecx, 126
    jae .bad
    mov [rdi+rcx], al
    test al, al
    jz .copied
    inc ecx
    jmp .copy
.copied:
    test ecx, ecx
    jz .bad
    cmp byte [rdi+rcx-1], '/'
    je .bad
    xor r13d, r13d
    mov rbx, -1
.scan_slash:
    cmp r13d, ecx
    jae .split
    cmp byte [rdi+r13], '/'
    jne .scan_next
    mov ebx, r13d
.scan_next:
    inc r13d
    jmp .scan_slash
.split:
    mov r12d, ecx
    sub r12d, ebx
    dec r12d
    cmp r12d, 1
    jb .bad
    cmp r12d, 63
    ja .bad
    lea rsi, [hs6_path_copy+rbx+1]
    mov rdi, hs6_leaf
    mov ecx, r12d
    rep movsb
    mov byte [rdi], 0
    mov byte [hs6_leaf+63], 0
    ; Names only [A-Za-z0-9_.-], not '.' / '..'.
    cmp word [hs6_leaf], '.'
    jne .validate
    cmp byte [hs6_leaf+1], 0
    je .bad
    cmp word [hs6_leaf], '..'
    jne .validate
    cmp byte [hs6_leaf+2], 0
    je .bad
.validate:
    mov rsi, hs6_leaf
.name:
    movzx eax, byte [rsi]
    test al, al
    jz .parent
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    jbe .next_name
.upper:
    cmp al, 'A'
    jb .digit
    cmp al, 'Z'
    jbe .next_name
.digit:
    cmp al, '0'
    jb .punct
    cmp al, '9'
    jbe .next_name
.punct:
    cmp al, '.'
    je .next_name
    cmp al, '_'
    je .next_name
    cmp al, '-'
    jne .bad
.next_name:
    inc rsi
    jmp .name
.parent:
    cmp ebx, -1
    je .relative_parent
    cmp ebx, 0
    jne .parent_path
    mov dword [hs6_target_parent], 0
    jmp .ok
.parent_path:
    mov byte [hs6_path_copy+rbx], 0
    mov rsi, hs6_path_copy
    call hs6_resolve
    jc .bad
    test rdi, rdi
    jz .root_parent
    cmp dword [rdi+64], 2
    jne .bad
    lea eax, [rbx+1]
    mov [hs6_target_parent], eax
    jmp .ok
.root_parent:
    mov dword [hs6_target_parent], 0
    jmp .ok
.relative_parent:
    mov eax, [hs6_cwd]
    mov [hs6_target_parent], eax
.ok:
    clc
    jmp .return
.bad:
    stc
.return:
    pop r13
    pop r12
    pop rbx
    ret

; Iterate a directory.  RSI = pathname (empty => cwd).
hs6_ls_path:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    cmp byte [rsi], 0
    je .current
    call hs6_resolve
    jc hs6_bad_entry
    test rdi, rdi
    jz .root
    cmp dword [rdi+64], 2
    jne hs6_bad_entry
    lea r8d, [rbx+1]
    jmp .list
.current:
    mov r8d, [hs6_cwd]
    jmp .list
.root:
    xor r8d, r8d
.list:
    xor ebx, ebx
.entry:
    cmp ebx, 128
    jae .done
    mov eax, ebx
    shl rax, 7
    lea rsi, [hs6_table+rax]
    cmp byte [rsi], 0
    je .next
    cmp dword [rsi+96], r8d
    jne .next
    cmp byte [rsi+63], 0
    jne hs6_bad_entry
    call puts
    mov eax, ebx
    shl rax, 7
    cmp dword [hs6_table+rax+64], 2
    jne .line
    mov al, '/'
    call putc
.line:
    mov al, 10
    call putc
.next:
    inc ebx
    jmp .entry
.done:
    ret

hs6_cd:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    cmp byte [rsi], 0
    jne .specified
    mov rsi, hs6_root_path
.specified:
    call hs6_resolve
    jc hs6_bad_entry
    test rdi, rdi
    jz .root
    cmp dword [rdi+64], 2
    jne hs6_bad_entry
    lea eax, [rbx+1]
    mov [hs6_cwd], eax
    ret
.root:
    mov dword [hs6_cwd], 0
    ret

hs6_pwd:
    cmp byte [hs6_ready], 1
    jne hs6_not_mounted
    mov eax, [hs6_cwd]
    xor ecx, ecx
.collect:
    test eax, eax
    jz .print
    cmp ecx, 128
    jae hs6_bad_entry
    mov [hs6_ancestors+rcx], al
    inc ecx
    dec eax
    shl rax, 7
    mov eax, [hs6_table+rax+96]
    jmp .collect
.print:
    test ecx, ecx
    jnz .loop
    mov rsi, hs6_root_print
    jmp puts
.loop:
    dec ecx
    mov al, '/'
    call putc
    movzx eax, byte [hs6_ancestors+rcx]
    dec eax
    shl rax, 7
    lea rsi, [hs6_table+rax]
    call puts
    test ecx, ecx
    jnz .loop
    mov al, 10
    jmp putc

hs6_root_path db '/',0
hs6_root_print db '/',10,0
hs6_cwd dd 0
hs6_target_parent dd 0
hs6_part times 64 db 0
hs6_leaf times 64 db 0
hs6_path_copy times 128 db 0
hs6_ancestors times 128 db 0
