; Castic 0.1: native, deliberately small x86-64 compiler in the kernel.
; Grammar: statements "print TEXT", separated by newline or semicolon.
; Output: a CSH1 executable, using int 80h write and exit, <=511 bytes.
; Entire source is compiled/validated before committing a new output file.
castic_compile:
    cmp byte [hs6_ready], 1
    jne .mount
    mov rdi, castic_srcpath
    call .token
    jc .usage
    call .spaces
    mov rdi, castic_dstpath
    call .token
    jc .usage
    call .spaces
    cmp byte [rsi], 0
    jne .usage
    mov rsi, castic_dstpath
    call hs6_resolve
    jnc .exists
    mov rsi, castic_srcpath
    call hs6_resolve
    jc .read_error
    test rdi, rdi
    jz .read_error
    cmp dword [rdi+64], 1
    jne .read_error
    mov rax, [rdi+80]
    test rax, rax
    jz .syntax
    cmp rax, 256
    ja .read_error
    mov [castic_source_len], eax
    mov rax, [rdi+88]
    cmp rax, 80
    jb .read_error
    cmp rax, [hs6_total]
    jae .read_error
    mov edx, [hs6_base]
    add rax, rdx
    jc .read_error
    cmp rax, 0x10000000
    jae .read_error
    mov rdi, hs6_sector
    call ata_read64
    jc .read_error
    mov rsi, hs6_sector
    mov rdi, castic_source
    mov ecx, [castic_source_len]
    ; Embedded NUL bytes would otherwise hide trailing source.
.copy_source:
    lodsb
    test al, al
    jz .syntax
    stosb
    loop .copy_source
    mov byte [rdi], 0
    mov rdi, castic_binary
    mov ax, 0x04eb
    stosw
    mov eax, 0x31485343
    stosd
    mov r13, rdi
    mov r12, castic_source
    xor r15d, r15d
.statement:
    mov al, [r12]
    cmp al, ' '
    je .skip
    cmp al, 9
    je .skip
    cmp al, 10
    je .skip
    cmp al, 13
    je .skip
    cmp al, ';'
    je .skip
    test al, al
    jz .finish
    cmp dword [r12], 0x6e697270 ; prin
    jne .syntax
    cmp byte [r12+4], 't'
    jne .syntax
    cmp byte [r12+5], ' '
    jne .syntax
    add r12, 6
.trim_start:
    cmp byte [r12], ' '
    jne .start_text
    inc r12
    jmp .trim_start
.start_text:
    mov rbx, r12
.count:
    mov al, [r12]
    test al, al
    jz .count_done
    cmp al, ';'
    je .count_done
    cmp al, 10
    je .count_done
    cmp al, 13
    je .count_done
    inc r12
    jmp .count
.count_done:
    mov rax, r12
    sub rax, rbx
    test rax, rax
    jz .syntax
    cmp rax, 119
    ja .syntax
    mov [castic_text_len], eax
    ; 19 code bytes + text + newline + 8 exit bytes.
    lea rdx, [r13+rax+28]
    cmp rdx, castic_binary+511
    ja .too_big
    mov rdi, r13
    mov al, 0xb8            ; mov eax, 1
    stosb
    mov eax, 1
    stosd
    mov al, 0xbf            ; mov edi, address of string
    stosb
    lea eax, [r13+19]
    sub eax, castic_binary
    add eax, 0x40000000
    stosd
    mov al, 0xbe            ; mov esi, length including newline
    stosb
    mov eax, [castic_text_len]
    inc eax
    stosd
    mov ax, 0x80cd          ; int 0x80
    stosw
    mov al, 0xeb            ; jump over the string data
    stosb
    mov eax, [castic_text_len]
    inc eax
    stosb
    mov rsi, rbx
    mov ecx, [castic_text_len]
    rep movsb
    mov al, 10
    stosb
    mov r13, rdi
    inc r15d
    jmp .statement
.skip:
    inc r12
    jmp .statement
.finish:
    test r15d, r15d
    jz .syntax
    mov rdi, r13
    mov ax, 0xc031          ; xor eax,eax (exit)
    stosw
    mov ax, 0xff31          ; xor edi,edi
    stosw
    mov ax, 0x80cd
    stosw
    mov ax, 0x0b0f          ; ud2 if exit unexpectedly returns
    stosw
    mov rcx, rdi
    sub rcx, castic_binary
    mov rsi, castic_dstpath
    mov rdx, castic_binary
    call hs6_write_binary
    cmp dword [hs6_write_status], 0
    jne .return
    mov rsi, castic_success
    jmp puts
.return:
    ret
.mount:
    mov rsi, shell_ext_no_mount
    jmp puts
.exists:
    mov rsi, castic_exists
    jmp puts
.read_error:
    mov rsi, castic_read_error
    jmp puts
.syntax:
    mov rsi, castic_syntax
    jmp puts
.too_big:
    mov rsi, castic_too_big
    jmp puts
.usage:
    mov rsi, castic_usage
    jmp puts
.spaces:
    cmp byte [rsi], ' '
    jne .space_end
    inc rsi
    jmp .spaces
.space_end:
    ret
.token:
    xor ecx, ecx
.token_loop:
    mov al, [rsi]
    test al, al
    jz .token_end
    cmp al, ' '
    je .token_end
    cmp ecx, 63
    jae .token_bad
    mov [rdi+rcx], al
    inc rsi
    inc ecx
    jmp .token_loop
.token_end:
    test ecx, ecx
    jz .token_bad
    mov byte [rdi+rcx], 0
    clc
    ret
.token_bad:
    stc
    ret
castic_srcpath times 64 db 0
castic_dstpath times 64 db 0
castic_source times 257 db 0
castic_binary times 511 db 0
castic_source_len dd 0
castic_text_len dd 0
castic_usage db 'Uso: castic fuente destino',10,0
castic_exists db 'Castic: destino existe; no se sobrescribe',10,0
castic_read_error db 'Castic: fuente no valida, disco o fuente >256 bytes',10,0
castic_syntax db 'Castic: sintaxis invalida; usa print texto',10,0
castic_too_big db 'Castic: programa compilado excede 511 bytes',10,0
castic_success db 'Castic: compilado x86-64',10,0
