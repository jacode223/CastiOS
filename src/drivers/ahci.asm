; AHCI 1.x, PCI class 010601, one HBA, four exposed SATA disks.
; DMA pages are identity-mapped allocator pages, never caller buffers.
ahci_probe:
    pushad
    mov ebp, [pci_ahci_bdf]
    cmp ebp, -1
    je .done
    mov eax, ebp
    shl eax, 8
    or eax, 0x80000024
    call pci_config
    test al, 1
    jnz .done
    and eax, 0xfffffff0
    cmp eax, 0x2000000
    jb .done
    cmp eax, 0xffffe000
    ja .done
    mov [ahci_hba], eax
    call ahci_map
    jc .done
    mov eax, [ahci_hba]
    add eax, 8191
    call ahci_map
    jc .done
    ; Enable memory decoding and bus mastering without writing PCI status.
    mov eax, ebp
    shl eax, 8
    or eax, 0x80000004
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in ax, dx
    or ax, 6
    out dx, ax
    mov esi, [ahci_hba]
    test dword [esi+0x24], 1
    jz .owned
    or dword [esi+0x28], 2
    mov ecx, ATA_POLLS
.handoff:
    test dword [esi+0x28], 0x11
    jz .owned
    loop .handoff
    jmp .done
.owned:
    or dword [esi+4], 0x80000000
    and dword [esi+4], 0xfffffffd
    xor ebp, ebp
.port:
    mov esi, [ahci_hba]
    bt dword [esi+12], ebp
    jnc .next
    mov ebx, ebp
    shl ebx, 7
    lea ebx, [esi+ebx+0x100]
    mov eax, [ebx+0x28]
    and eax, 0xf0f
    cmp eax, 0x103
    jne .next
    cmp dword [ebx+0x24], 0x101
    jne .next
    xor edx, edx
.slot:
    cmp dword [disk_caps+edx*4], 0
    je .slot_found
    inc edx
    cmp edx, 4
    jb .slot
    jmp .done
.slot_found:
    mov [ahci_slot], edx
    and dword [ebx+0x18], 0xfffffffe
    mov ecx, ATA_POLLS
.stop:
    test dword [ebx+0x18], 0x8000
    jz .stop_fis
    loop .stop
    jmp .next
.stop_fis:
    and dword [ebx+0x18], 0xffffffef
    mov ecx, ATA_POLLS
.fis:
    test dword [ebx+0x18], 0x4000
    jz .alloc
    loop .fis
    jmp .next
.alloc:
    call alloc_page
    test eax, eax
    jz .done
    mov edx, [ahci_slot]
    mov byte [ahci_poison+edx], 0
    mov [ahci_pages+edx*4], eax
    mov [ahci_ports+edx*4], ebx
    mov edi, eax
    mov ecx, 1024
    xor eax, eax
    rep stosd
    mov eax, [ahci_pages+edx*4]
    mov [ebx], eax
    mov dword [ebx+4], 0
    add eax, 1024
    mov [ebx+8], eax
    mov dword [ebx+12], 0
    mov dword [ebx+0x14], 0
    mov dword [ebx+0x10], -1
    mov dword [ebx+0x30], -1
    or dword [ebx+0x18], 0x10000017
    mov eax, edx
    mov [disk_selected], eax
    mov al, 0xec
    mov edi, identify_buffer
    xor ebx, ebx
    call ahci_command
    jc .next
    ; Reuse ATA IDENTIFY validation, model and capacity parsing.
    push ebp
    mov ebp, [ahci_slot]
    call ata_parse_identify
    mov eax, ebp
    pop ebp
    cmp byte [disk_states+eax], 1
    jne .next
    mov byte [disk_backend+eax], 1
.next:
    inc ebp
    cmp ebp, 32
    jb .port
.done:
    popad
    ret

; Map the MMIO-containing 4 MiB region uncached through a dedicated page table.
ahci_map:
    pushad
    mov ebx, eax
    shr ebx, 22
    cmp dword [0x1d0000+ebx*4], 0
    jne .ok
    and eax, 0xffc00000
    mov edx, eax
    call alloc_page
    test eax, eax
    jz .bad
    mov edi, eax
    mov esi, eax
    mov eax, edx
    or eax, 0x1b
    mov ecx, 1024
.loop:
    stosd
    add eax, 4096
    loop .loop
    or esi, 3
    mov [0x1d0000+ebx*4], esi
    mov eax, cr3
    mov cr3, eax
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

ahci_io:
    pushad
    test bl, bl
    jz .range
    push eax
    mov eax, [disk_selected]
    cmp byte [disk_flush_cap+eax], 1
    pop eax
    jne .bad
.range:
    cmp eax, [disk_sectors]
    jae .bad
    mov [io_lba], eax
    mov al, 0x25
    test bl, bl
    jz .issue
    mov al, 0x35
.issue:
    call ahci_command
    jc .bad
    popad
    clc
    ret
.bad:
    inc dword [ata_errors]
    popad
    stc
    ret
ahci_flush:
    pushad
    mov al, 0xe7
    xor ebx, ebx
    call ahci_command
    jc .bad
    popad
    clc
    ret
.bad:
    inc dword [ata_errors]
    popad
    stc
    ret

; AL=command, BL=write, EDI=buffer. All operations serialized.
; Timeout poisons the port: DMA page retained, never reused or freed.
ahci_command:
    mov [ahci_op], al
    mov [ahci_write], bl
    mov [ahci_buffer], edi
    mov eax, [disk_selected]
    cmp byte [ahci_poison+eax], 0
    jne .bad
    mov ebx, [ahci_ports+eax*4]
    mov esi, [ahci_pages+eax*4]
    test esi, esi
    jz .bad
    cmp dword [ebx+0x38], 0
    jne .poison
    cmp dword [ebx+0x34], 0
    jne .poison
    mov ecx, ATA_POLLS
.ready:
    test dword [ebx+0x20], 0x88
    jz .setup
    loop .ready
    jmp .poison
.setup:
    lea edi, [esi+1280]
    xor eax, eax
    mov ecx, 160/4
    rep stosd
    mov dword [esi], 0x10005
    mov dword [esi+4], 0
    lea eax, [esi+1280]
    mov [esi+8], eax
    mov dword [esi+12], 0
    mov byte [esi+1280], 0x27
    mov byte [esi+1281], 0x80
    mov al, [ahci_op]
    mov [esi+1282], al
    cmp al, 0xe7
    je .nodata
    mov byte [esi+1287], 0x40
    mov eax, [io_lba]
    mov [esi+1284], ax
    shr eax, 16
    mov [esi+1286], al
    mov [esi+1288], ah
    cmp byte [ahci_op], 0xec
    je .identify
    mov byte [esi+1292], 1
    jmp .prdt
.identify:
    mov dword [esi+1284], 0
    mov byte [esi+1288], 0
.prdt:
    lea eax, [esi+2048]
    mov [esi+1408], eax
    mov dword [esi+1412], 0
    mov dword [esi+1420], 511
    cmp byte [ahci_write], 0
    je .submit
    or dword [esi], 0x40
    push esi
    lea edi, [esi+2048]
    mov esi, [ahci_buffer]
    mov ecx, 128
    rep movsd
    pop esi
    jmp .submit
.nodata:
    mov dword [esi], 5
.submit:
    mov dword [ebx+0x10], -1
    mov dword [ebx+0x30], -1
    mov dword [ebx+0x38], 1
    mov ecx, ATA_POLLS
.wait:
    test dword [ebx+0x10], 0x7d000000
    jnz .poison
    test dword [ebx+0x38], 1
    jz .complete
    loop .wait
    jmp .poison
.complete:
    mov eax, [ebx+0x20]
    mov [ata_last_status], al
    mov [ata_last_error], ah
    test al, 0x21
    jnz .poison
    cmp byte [ahci_op], 0xe7
    je .ok
    cmp dword [esi+4], 512
    jne .poison
    cmp byte [ahci_write], 0
    jne .ok
    lea esi, [esi+2048]
    mov edi, [ahci_buffer]
    mov ecx, 128
    rep movsd
.ok:
    clc
    ret
.poison:
    mov eax, [disk_selected]
    mov byte [ahci_poison+eax], 1
    and dword [ebx+0x18], 0xfffffffe
.bad:
    stc
    ret

ahci_hba dd 0
ahci_slot dd 0
ahci_ports times 4 dd 0
ahci_pages times 4 dd 0
ahci_poison times 4 db 0
disk_backend times 4 db 0
ahci_buffer dd 0
ahci_op db 0
ahci_write db 0
