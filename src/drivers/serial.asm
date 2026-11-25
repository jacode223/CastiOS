; UART COM1 16550: deteccion loopback, 115200 8N1, polling acotado.
DRIVER serial_driver, serial_name, text_class, serial_probe, serial_init, serial_read, serial_write, 0
serial_name db 'serial',0
serial_probe:
    mov dx, 0x3fb
    mov al, 3
    out dx, al
    mov dx, 0x3f9
    xor al, al
    out dx, al
    mov dx, 0x3fc
    mov al, 0x1e
    out dx, al
    mov dx, 0x3f8
    mov al, 0xae
    out dx, al
    mov ecx, 100000
.wait:
    mov dx, 0x3fd
    in al, dx
    test al, 1
    jnz .read
    loop .wait
    jmp .absent
.read:
    mov dx, 0x3f8
    in al, dx
    cmp al, 0xae
    jne .absent
    mov dx, 0x3fc
    mov al, 3
    out dx, al
    xor eax, eax
    ret
.absent:
    mov dx, 0x3fc
    xor al, al
    out dx, al
    mov eax, ENODEV
    ret
serial_init:
    mov dx, 0x3fb
    mov al, 0x80
    out dx, al
    mov dx, 0x3f8
    mov al, 1
    out dx, al
    inc dx
    xor al, al
    out dx, al
    mov dx, 0x3fb
    mov al, 3
    out dx, al
    mov dx, 0x3fa
    mov al, 0xc7
    out dx, al
    xor eax, eax
    ret
serial_write:
    mov esi, edi
    mov ebp, ecx
    xor ebx, ebx
.byte:
    cmp ebx, ebp
    jae .done
    mov ecx, 100000
    mov dx, 0x3fd
.wait:
    in al, dx
    test al, 0x20
    jnz .send
    loop .wait
    mov eax, EIO
    ret
.send:
    mov dx, 0x3f8
    lodsb
    out dx, al
    inc ebx
    jmp .byte
.done:
    mov edx, ebx
    xor eax, eax
    ret
serial_read:
    xor ebx, ebx
.byte:
    cmp ebx, ecx
    jae .done
    mov dx, 0x3fd
    in al, dx
    test al, 1
    jz .done
    test al, 0x1e
    jnz .error
    mov dx, 0x3f8
    in al, dx
    stosb
    inc ebx
    jmp .byte
.done:
    mov edx, ebx
    xor eax, eax
    ret
.error:
    mov eax, EIO
    ret
