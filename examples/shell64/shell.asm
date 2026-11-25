; CastiOS shell executable, NASM flat binary, loaded at 0x40000000.
; int 80h: 1=write, 31=nonblocking keyboard, 0=exit.
bits 64
org 0x40000000
    jmp short start
    db 'CSH1'
start:
    mov rdi, greeting
    mov esi, greeting_end-greeting
    call write
.prompt:
    mov rdi, prompt
    mov esi, prompt_end-prompt
    call write
    xor r12d, r12d
.input:
    mov eax, 31
    int 0x80
    cmp rax, -11
    je .input
    test rax, rax
    js .exit
    cmp al, 10
    je .enter
    cmp al, 8
    je .back
    cmp r12d, 62
    jae .input
    mov [0x40002000+r12], al
    inc r12d
    mov rdi, 0x40002000
    add rdi, r12
    dec rdi
    mov esi, 1
    call write
    jmp .input
.back:
    test r12d, r12d
    jz .input
    dec r12d
    mov rdi, backspace
    mov esi, 1
    call write
    jmp .input
.enter:
    mov byte [0x40002000+r12], 0
    mov rdi, newline
    mov esi, 1
    call write
    mov rsi, 0x40002000
    mov rdi, exit_cmd
    call equals
    test eax, eax
    jz .exit
    mov rsi, 0x40002000
    mov rdi, help_cmd
    call equals
    test eax, eax
    jnz .unknown
    mov rdi, help_msg
    mov esi, help_end-help_msg
    call write
    jmp .prompt
.unknown:
    test r12d, r12d
    jz .prompt
    mov rdi, unknown
    mov esi, unknown_end-unknown
    call write
    jmp .prompt
.exit:
    xor eax, eax
    xor edi, edi
    int 0x80
    ud2
write:
    mov eax, 1
    int 0x80
    ret
equals:
    mov al, [rsi]
    cmp al, [rdi]
    jne .ne
    test al, al
    jz .eq
    inc rsi
    inc rdi
    jmp equals
.eq:
    xor eax, eax
    ret
.ne:
    mov eax, 1
    ret
greeting db 'Shell CPL3 propia. Escribe help o exit.',10
greeting_end:
prompt db 'propia> '
prompt_end:
help_msg db 'Comandos: help exit',10
help_end:
unknown db 'Comando desconocido',10
unknown_end:
exit_cmd db 'exit',0
help_cmd db 'help',0
newline db 10
backspace db 8
