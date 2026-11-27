; Graphics service and compiler messages placed in the first kernel segment.
castic_usage db 'Uso: castic FUENTE SALIDA',10,0
castic_exists db 'Castic: destino existe; no se sobrescribe',10,0
castic_syntax db 'Castic: sintaxis invalida; usa print texto ASCII',10,0
castic_big db 'Castic: programa excede el limite AX05',10,0
castic_ok db 'Castic: compilado i386 AX05',10,0

lib_deskcas: incbin "lib/desk.cas"

sys_gfx_text4:
    ; EBX=up to four packed ASCII bytes, ECX=x|y<<16, EDX=RGB.
    sub esp, 160
    mov edi, esp
    push ecx
    mov ecx, 40
    xor eax, eax
    rep stosd
    pop ecx
    mov dword [esp], 13
    movzx eax, cx
    mov [esp+4], eax
    shr ecx, 16
    mov [esp+8], ecx
    mov [esp+20], edx
    lea edi, [esp+24]
    mov eax, ebx
    mov ecx, 4
.text_char:
    test al, al
    jz .text_end
    cmp al, 32
    jb .text_invalid
    cmp al, 126
    ja .text_invalid
    stosb
    shr eax, 8
    loop .text_char
.text_end:
    lea eax, [esp+24]
    cmp edi, eax
    je .text_invalid
    push esp
    call [0x20018]
    add esp, 164
    test eax, eax
    jz syscall_service.gfx_invalid
    jmp syscall_service.gfx_success
.text_invalid:
    add esp, 160
    jmp syscall_service.gfx_invalid
