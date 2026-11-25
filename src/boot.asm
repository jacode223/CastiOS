; CastiOS: sector BIOS, 512 bytes. Carga el kernel por CHS.
bits 16
org 0x7c00

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 32
%endif

    jmp 0x0000:start
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    cld
    sti
    mov [drive], dl
    mov si, loading
    call puts
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov word [lba], 1
    mov word [remaining], KERNEL_SECTORS
.sector:
    mov byte [attempts], 3
.retry:
    ; LBA / 18 = pista y sector; pista / 2 = cilindro y cabeza.
    mov ax, [lba]
    xor dx, dx
    mov cx, 18
    div cx
    mov cl, dl
    inc cl
    xor dx, dx
    mov si, 2
    div si
    mov ch, al
    mov dh, dl
    mov dl, [drive]
    mov ax, 0x0201
    push bx
    int 0x13
    pop bx
    jnc .loaded
    xor ax, ax
    mov dl, [drive]
    int 0x13
    dec byte [attempts]
    jnz .retry
    mov si, failure
    call puts
    cli
.stop:
    hlt
    jmp .stop
.loaded:
    add bx, 512
    inc word [lba]
    dec word [remaining]
    jnz .sector
    mov dl, [drive]
    jmp 0x1000:0x0000

puts:
    lodsb
    test al, al
    jz .done
    out 0xe9, al
    mov ah, 0x0e
    mov bx, 7
    int 0x10
    jmp puts
.done:
    ret

drive db 0
attempts db 0
lba dw 1
remaining dw 0
loading db 'CastiOS: cargando kernel...', 13, 10, 0
failure db 'Error de lectura. Reinicia la maquina.', 13, 10, 0
times 510-($-$$) db 0
dw 0xaa55
