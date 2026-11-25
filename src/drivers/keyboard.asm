; IRQ1 consume scancodes en una cola SPSC de 256 bytes.
ps2_probe:
    in al, 0x64
    cmp al, 0xff
    je builtin_absent
    xor eax, eax
    ret
ps2_init:
    mov dword [kbd_head], 0
    mov dword [kbd_tail], 0
    mov dword [kbd_dropped], 0
    mov eax, 1
    mov ecx, ps2_irq
    call irq_register
    ret
ps2_irq:
    mov ecx, 32
.drain:
    in al, 0x64
    test al, 1
    jz .done
    mov ah, al
    in al, 0x60
    test ah, 0xc0
    jnz .next
    test ah, 0x20
    jz .keyboard
    cmp byte [mouse_ready], 1
    jne .next
    call mouse_byte
    jmp .next
.keyboard:
    mov ebx, [kbd_head]
    lea edx, [ebx+1]
    and edx, 255
    cmp edx, [kbd_tail]
    je .full
    mov [kbd_queue+ebx], al
    mov [kbd_head], edx
    jmp .next
.full:
    inc dword [kbd_dropped]
.next:
    loop .drain
.done:
    ret
ps2_pop:
    push ebx
    mov ebx, [kbd_tail]
    cmp ebx, [kbd_head]
    je .empty
    movzx eax, byte [kbd_queue+ebx]
    inc ebx
    and ebx, 255
    mov [kbd_tail], ebx
    pop ebx
    ret
.empty:
    mov eax, 256
    pop ebx
    ret
ps2_read:
    test ecx, ecx
    jz builtin_invalid
    call ps2_pop
    cmp eax, 256
    je .empty
    mov [edi], al
    mov edx, 1
    xor eax, eax
    ret
.empty:
    xor edx, edx
    xor eax, eax
    ret
kbd_head dd 0
kbd_tail dd 0
kbd_dropped dd 0
kbd_queue times 256 db 0
cmd_kbdstat:
    mov eax, [kbd_dropped]
    call number
    mov esi, kbd_stats_msg
    jmp puts
kbd_stats_msg db ' scancodes descartados',10,0
