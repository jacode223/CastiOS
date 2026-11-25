; Shell files: short jump over CSH1 header, up to one 4 KiB code page.
; shell new writes an embedded template; shell run reads the file from HSFS.
shell_ext_new:
    cmp byte [hs6_ready], 1
    jne .no_mount
    mov [shell_ext_path], rsi
    call shell_ext_validate_path
    jc .bad
    mov rsi, [shell_ext_path]
    call hs6_resolve
    jnc .exists
    mov rsi, [shell_ext_path]
    mov rdx, shell_ext_template
    mov ecx, shell_ext_template_end-shell_ext_template
    jmp hs6_write_binary
.no_mount:
    mov rsi, shell_ext_no_mount
    jmp puts
.exists:
    mov rsi, shell_ext_exists
    jmp puts
.bad:
    mov rsi, shell_ext_bad
    jmp puts

shell_ext_run:
    cmp byte [hs6_ready], 1
    jne shell_ext_new.no_mount
    mov [shell_ext_path], rsi
    call shell_ext_validate_path
    jc shell_ext_new.bad
    mov rsi, [shell_ext_path]
    call hs6_resolve
    jc .load_error
    test rdi, rdi
    jz .load_error
    cmp dword [rdi+64], 1
    jne .load_error
    mov rax, [rdi+80]
    cmp rax, 7
    jb .load_error
    cmp rax, 4096
    ja .load_error
    mov [shell_ext_size], eax
    mov r12, [rdi+88]
    cmp r12, 80
    jb .load_error
    mov r13, rax
    add rax, 511
    shr rax, 9
    add rax, r12
    jc .load_error
    cmp rax, [hs6_total]
    ja .load_error
    mov edx, [hs6_base]
    add rax, rdx
    cmp rax, 0x10000000
    ja .load_error
    mov r14, shell_ext_image
.read:
    mov rax, r12
    mov edx, [hs6_base]
    add rax, rdx
    mov rdi, hs6_sector
    call ata_read64
    jc .load_error
    mov ecx, 512
    cmp r13, rcx
    jae .copy
    mov rcx, r13
.copy:
    sub r13, rcx
    mov rsi, hs6_sector
    mov rdi, r14
    rep movsb
    mov r14, rdi
    inc r12
    test r13, r13
    jnz .read
    cmp byte [shell_ext_image], 0xeb
    jne .load_error
    cmp byte [shell_ext_image+1], 4
    jne .load_error
    cmp dword [shell_ext_image+2], 0x31485343 ; CSH1
    jne .load_error
    mov byte [selected_user], 0
    mov qword [cps_pending_name], shell_ext_process
    mov rsi, shell_ext_image
    mov ecx, [shell_ext_size]
    call user_launch
    test eax, eax
    jnz .load_error
    cmp byte [user_fault], 0
    jne .fault
    mov rsi, shell_ext_returned
    jmp puts
.fault:
    mov rsi, shell_ext_fault
    jmp puts
.load_error:
    mov rsi, shell_ext_error
    jmp puts

shell_ext_validate_path:
    xor ecx, ecx
.next:
    mov al, [rsi+rcx]
    test al, al
    jz .done
    cmp al, ' '
    je .bad
    inc ecx
    cmp ecx, 63
    ja .bad
    jmp .next
.done:
    test ecx, ecx
    jz .bad
    clc
    ret
.bad:
    stc
    ret
shell_ext_path dq 0
shell_ext_size dd 0
shell_ext_image times 4096 db 0
shell_ext_template: incbin 'build/x64/sample_shell.bin'
shell_ext_template_end:
%if shell_ext_template_end-shell_ext_template > 511
    %error 'Shell template exceeds HSFS binary writer limit'
%endif
shell_ext_process db 'shell-cpl3',0
shell_ext_no_mount db 'Monta primero un disco HSFS con mount',10,0
shell_ext_exists db 'El archivo ya existe; no se sobrescribe',10,0
shell_ext_bad db 'Ruta o tamano invalido',10,0
shell_ext_error db 'No se puede cargar la shell: ruta, formato o disco',10,0
shell_ext_fault db 'Shell terminada por fallo; consola recuperada',10,0
shell_ext_returned db 'Shell terminada; consola recuperada',10,0
