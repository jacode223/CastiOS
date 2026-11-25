; PS/2 mouse for x86-64, adapted from CastiOS i386; polled via shared i8042.
mouse64_init:
    mov byte [mouse64_ready], 0
    call mouse64_wait_write
    jc .bad
    mov al, 0xa8
    out 0x64, al
    call mouse64_wait_write
    jc .bad
    mov al, 0x20
    out 0x64, al
    call mouse64_wait_read
    jc .bad
    in al, 0x60
    and al, 0xdd               ; aux clock on, IRQ12 disabled (polling)
    mov [mouse64_config], al
    call mouse64_wait_write
    jc .bad
    mov al, 0x60
    out 0x64, al
    call mouse64_wait_write
    jc .bad
    mov al, [mouse64_config]
    out 0x60, al
    mov al, 0xf6
    call mouse64_send
    jc .bad
    mov al, 0xf4
    call mouse64_send
    jc .bad
    mov byte [mouse64_ready], 1
.bad:
    ret
mouse64_wait_write:
    mov ecx, 100000
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
mouse64_wait_read:
    mov ecx, 100000
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
mouse64_send:
    push rax
    call mouse64_wait_write
    jc .error
    mov al, 0xd4
    out 0x64, al
    call mouse64_wait_write
    jc .error
    pop rax
    out 0x60, al
    call mouse64_wait_read
    jc .bad_ack
    test al, 0x20               ; response must originate at auxiliary port
    jz .bad_ack
    in al, 0x60
    cmp al, 0xfa
    jne .bad_ack
    clc
    ret
.error:
    pop rax
.bad_ack:
    stc
    ret
mouse64_byte:
    cmp byte [mouse64_ready], 1
    jne .done
    movzx edx, byte [mouse64_index]
    test edx, edx
    jnz .store
    test al, 8
    jz .done
.store:
    mov [mouse64_packet+rdx], al
    inc edx
    cmp edx, 3
    jne .partial
    mov byte [mouse64_index], 0
    test byte [mouse64_packet], 0xc0
    jnz .done
    mov al, [mouse64_packet]
    and al, 7
    mov [mouse64_buttons], al
    movsx eax, byte [mouse64_packet+1]
    add eax, [mouse64_x]
    jns .x_pos
    xor eax, eax
.x_pos:
    cmp eax, 959
    jbe .x_done
    mov eax, 959
.x_done:
    mov [mouse64_x], eax
    movsx eax, byte [mouse64_packet+2]
    neg eax
    add eax, [mouse64_y]
    jns .y_pos
    xor eax, eax
.y_pos:
    cmp eax, 599
    jbe .y_done
    mov eax, 599
.y_done:
    mov [mouse64_y], eax
    inc dword [mouse64_events]
.done:
    ret
.partial:
    mov [mouse64_index], dl
    ret
mouse64_status:
    cmp byte [mouse64_ready], 1
    jne .absent
    mov rsi, mouse64_msg
    call puts
    mov eax, [mouse64_x]
    call decimal
    mov rsi, mouse64_ymsg
    call puts
    mov eax, [mouse64_y]
    call decimal
    mov rsi, mouse64_bmsg
    call puts
    movzx eax, byte [mouse64_buttons]
    call decimal
    mov rsi, mouse64_emsg
    call puts
    mov eax, [mouse64_events]
    call decimal
    mov al, 10
    jmp putc
.absent:
    mov rsi, mouse64_missing
    jmp puts
mouse64_config db 0
mouse64_ready db 0
mouse64_index db 0
mouse64_buttons db 0
mouse64_packet times 3 db 0
mouse64_x dd 480
mouse64_y dd 300
mouse64_events dd 0
mouse64_msg db 'PS/2 x=',0
mouse64_ymsg db ' y=',0
mouse64_bmsg db ' botones=',0
mouse64_emsg db ' eventos=',0
mouse64_missing db 'Raton PS/2 no disponible',10,0
