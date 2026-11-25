; BIOS EDD boot para disco duro: MBR de carga fija, sin particiones.
bits 16
org 0x7c00
    jmp 0:start
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
    mov bx, 0x55aa
    mov ah, 0x41
    int 0x13
    jc failure
    cmp bx, 0xaa55
    jne failure
    test cx, 1
    jz failure
    mov bp, 3
.retry:
    mov word [packet+2], 64
    mov si, packet
    mov dl, [drive]
    mov ah, 0x42
    int 0x13
    jnc .loaded
    xor ax, ax
    mov dl, [drive]
    int 0x13
    dec bp
    jnz .retry
    jmp failure
.loaded:
    mov dl, [physical_disk]
    add dl, 0x80
    jmp 0x1000:0
failure:
    mov si, error
.print:
    lodsb
    test al, al
    jz .stop
    out 0xe9, al
    mov ah, 0x0e
    mov bx, 7
    int 0x10
    jmp .print
.stop:
    cli
    hlt
    jmp .stop
align 4
packet db 16,0
    dw 64
    dw 0,0x1000
    dq 1
drive db 0
error db 'CastiOS: fallo BIOS EDD',0
times 0x180-($-$$) db 0
db 'ASM05HD',0
physical_disk db 0
times 510-($-$$) db 0
dw 0xaa55
