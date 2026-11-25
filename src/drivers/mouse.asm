; PS/2 auxiliary port: three-byte relative packets and IRQ12.
mouse_init:
    mov byte [mouse_ready], 0
    mov eax, 480
    mov [mouse_x], eax
    mov eax, 300
    mov [mouse_y], eax
    call mouse_wait_write
    jc .failed
    mov al, 0xa8                 ; enable auxiliary port
    out 0x64, al
    call mouse_wait_write
    jc .failed
    mov al, 0x20                 ; read controller configuration byte
    out 0x64, al
    call mouse_wait_read
    jc .failed
    in al, 0x60
    and al, 0xdf                 ; enable auxiliary clock
    or al, 2                    ; IRQ12
    mov [mouse_config], al
    call mouse_wait_write
    jc .failed
    mov al, 0x60
    out 0x64, al
    call mouse_wait_write
    jc .failed
    mov al, [mouse_config]
    out 0x60, al
    mov al, 0xf6                ; defaults, then start reporting
    call mouse_send
    jc .failed
    mov al, 0xf4
    call mouse_send
    jc .failed
    mov byte [mouse_ready], 1
    mov eax, 12
    mov ecx, ps2_irq            ; shared drain routes by status bit 5
    call irq_register
    test eax, eax
    jnz .failed
    xor eax, eax
    ret
.failed:
    mov byte [mouse_ready], 0
    mov eax, ENODEV
    ret
mouse_wait_write:
    mov ecx, 65536
.loop:
    in al, 0x64
    test al, 2
    jz .ok
    loop .loop
    stc
    ret
.ok:
    clc
    ret
mouse_wait_read:
    mov ecx, 65536
.loop:
    in al, 0x64
    test al, 1
    jnz .ok
    loop .loop
    stc
    ret
.ok:
    clc
    ret
mouse_send:
    push eax
    call mouse_wait_write
    jc .error
    mov al, 0xd4
    out 0x64, al
    call mouse_wait_write
    jc .error
    pop eax
    out 0x60, al
    call mouse_wait_read
    jc .bad_ack
    in al, 0x60
    cmp al, 0xfa
    jne .bad_ack
    clc
    ret
.error:
    pop eax
.bad_ack:
    stc
    ret
; AL=mouse byte, called from shared PS/2 IRQ with registers saved by ISR.
mouse_byte:
    movzx edx, byte [mouse_index]
    test edx, edx
    jnz .store
    test al, 8
    jz .done
.store:
    mov [mouse_packet+edx], al
    inc edx
    cmp edx, 3
    jne .partial
    mov byte [mouse_index], 0
    test byte [mouse_packet], 0xc0 ; discard overflow packets
    jnz .done
    movzx edx, byte [mouse_packet]
    and edx, 7
    mov al, [mouse_buttons]
    not al
    and al, dl
    and al, 1
    or [mouse_click], al
    mov [mouse_buttons], dl
    movsx edx, byte [mouse_packet+1]
    add edx, [mouse_x]
    cmp edx, 0
    jge .x_positive
    xor edx, edx
.x_positive:
    cmp edx, 959
    jle .x_ok
    mov edx, 959
.x_ok:
    mov [mouse_x], edx
    movsx edx, byte [mouse_packet+2]
    mov ebx, [mouse_y]
    sub ebx, edx
    cmp ebx, 0
    jge .y_positive
    xor ebx, ebx
.y_positive:
    cmp ebx, 599
    jle .y_ok
    mov ebx, 599
.y_ok:
    mov [mouse_y], ebx
    mov byte [mouse_event], 1
.done:
    ret
.partial:
    mov [mouse_index], dl
    ret
mouse_read:
    cmp ecx, 12
    jb builtin_invalid
    mov eax, [mouse_x]
    mov [edi], eax
    mov eax, [mouse_y]
    mov [edi+4], eax
    movzx eax, byte [mouse_buttons]
    mov [edi+8], eax
    mov edx, 12
    xor eax, eax
    ret
cmd_mousestat:
    cmp byte [mouse_ready], 1
    jne .absent
    mov esi, mouse_x_msg
    call puts
    mov eax, [mouse_x]
    call number
    mov esi, mouse_y_msg
    call puts
    mov eax, [mouse_y]
    call number
    mov esi, mouse_buttons_msg
    call puts
    movzx eax, byte [mouse_buttons]
    call number
    jmp nl
.absent:
    mov esi, mouse_absent_msg
    jmp puts
mouse_ready db 0
mouse_gui db 0
mouse_config db 0
mouse_index db 0
mouse_packet times 3 db 0
mouse_buttons db 0
mouse_click db 0
mouse_event db 0
align 4
mouse_x dd 480
mouse_y dd 300
mouse_x_msg db 'Mouse PS/2 x=',0
mouse_y_msg db ' y=',0
mouse_buttons_msg db ' botones=',0
mouse_absent_msg db 'Mouse PS/2 no detectado.',10,0
