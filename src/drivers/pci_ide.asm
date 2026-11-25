; PCI IDE 01:01. Firmware supplies the I/O BARs and mode independently
; for each channel. Never switch a channel, enable DMA or reprogram a BAR.
pci_ide_native_probe:
    pushad
    mov esi, pci_devices
    mov ecx, [pci_count]
.controller:
    test ecx, ecx
    jz .done
    cmp word [esi+10], 0x0101
    jne .next
    cmp dword [esi+4], 0x32491106
    je .next                     ; dedicated VIA port layout
    mov ebx, [esi]
    shl ebx, 8
    or ebx, 0x80000000
    mov eax, ebx
    or al, 4
    call pci_config
    test al, 1                   ; I/O decoding enabled
    jz .next
    test byte [esi+9], 1
    jz .secondary
    mov al, 0x10
    call .channel
.secondary:
    test byte [esi+9], 4
    jz .next
    mov al, 0x18
    call .channel
.next:
    add esi, 12
    dec ecx
    jmp .controller
.done:
    popad
    ret

.channel:
    pushad
    movzx edi, al
    lea eax, [ebx+edi]
    call pci_config
    mov edx, eax
    and edx, 7
    cmp edx, 1                   ; I/O BAR, 8-port command range
    jne .end
    and eax, ~7
    cmp eax, 0x100
    jb .end
    cmp eax, 0xfff8
    ja .end
    cmp ax, 0x1f0                ; both legacy ranges already probed
    je .end
    cmp ax, 0x170
    je .end
    mov [ata_base], ax
    lea eax, [ebx+edi+4]
    call pci_config
    mov edx, eax
    and edx, 3
    cmp edx, 1
    jne .end
    and eax, ~3
    cmp eax, 0x100
    jb .end
    cmp eax, 0xfffc
    ja .end
    add ax, 2
    mov [ata_control], ax
    ; Ignore duplicate task files published by an alias controller.
    xor ecx, ecx
.alias:
    cmp byte [disk_backend+ecx], 3
    jne .another
    mov ax, [native_base+ecx*2]
    cmp ax, [ata_base]
    je .end
.another:
    inc ecx
    cmp ecx, 4
    jb .alias
    mov byte [disk_bit], 0
.unit:
    mov ebp, 4
    mov dword [disk_caps+4*4], 0
    mov byte [disk_states+4], 0
    mov byte [disk_flush_cap+4], 0
    call ata_probe_one
    cmp dword [disk_caps+4*4], 0
    je .next_unit
    xor ebx, ebx
.slot:
    cmp dword [disk_caps+ebx*4], 0
    jne .occupied
    cmp byte [disk_states+ebx], 2 ; keep known optical devices
    jne .publish
.occupied:
    inc ebx
    cmp ebx, 4
    jb .slot
    jmp .end
.publish:
    mov eax, [disk_caps+4*4]
    mov [disk_caps+ebx*4], eax
    mov al, [disk_flush_cap+4]
    mov [disk_flush_cap+ebx], al
    mov byte [disk_states+ebx], 1
    mov byte [disk_backend+ebx], 3
    mov ax, [ata_base]
    mov [native_base+ebx*2], ax
    mov ax, [ata_control]
    mov [native_control+ebx*2], ax
    mov al, [disk_bit]
    mov [native_unit+ebx], al
    imul edi, ebx, 41
    add edi, disk_models
    mov esi, disk_models+4*41
    mov ecx, 41
    rep movsb
.next_unit:
    xor byte [disk_bit], 0x10
    jnz .unit
.end:
    popad
    ret

native_base times 4 dw 0
native_control times 4 dw 0
native_unit times 4 db 0
