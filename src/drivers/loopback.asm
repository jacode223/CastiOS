; Driver ejemplo sin hardware. Escribe una cadena y recuperala con read.
DRIVER loopback_driver, loopback_name, loopback_class, 0, loopback_init, loopback_read, loopback_write, loopback_ioctl
loopback_name db 'loopback',0
loopback_class db 'text',0
loopback_length dd 0
loopback_data times 250 db 0
loopback_init:
    mov dword [loopback_length], 0
    xor edx, edx
    xor eax, eax
    ret
loopback_write:
    cmp ecx, 250
    ja builtin_invalid
    mov [loopback_length], ecx
    mov edx, ecx
    mov esi, edi
    mov edi, loopback_data
    rep movsb
    xor eax, eax
    ret
loopback_read:
    cmp ecx, [loopback_length]
    jae .fits
    mov edx, ecx
    jmp .copy
.fits:
    mov edx, [loopback_length]
.copy:
    mov ecx, edx
    mov esi, loopback_data
    rep movsb
    xor eax, eax
    ret
loopback_ioctl:
    ; Opcode 0: vaciar; opcode 1: obtener longitud (DWORD en EDI).
    test edx, edx
    jz loopback_init
    cmp edx, 1
    jne builtin_invalid
    cmp ecx, 4
    jb builtin_invalid
    mov eax, [loopback_length]
    mov [edi], eax
    mov edx, 4
    xor eax, eax
    ret
