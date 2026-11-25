; Explicit, cooperative disk swap for one 4 KiB data page per AX05 process.
; Use the last 100 KiB of the selected HSFS disk; HSFS large allocator
; excludes it. Slots 0..3 belong to multitask entries, slot 4 to exec.
%define SWAP_SECTORS 200
%define SWAP_PAGE_VA USER_BASE+0x4000
swap_page_address:
    push ebx
    xor eax, eax
    cmp byte [mt_active], 0
    je .single
    mov ebx, [mt_current]
    cmp ebx, [mt_count]
    jae .done
    imul ebx, MT_SIZE
    mov eax, [mt_table+ebx+MT_SWAP]
    jmp .done
.single:
    mov eax, [process_swap_page]
.done:
    pop ebx
    ret
; ESI=address of page field, EDI=address of saved flag, EBX=slot.
swap_slot:
    cmp byte [mt_active], 0
    je .single
    mov ebx, [mt_current]
    cmp ebx, [mt_count]
    jae .no
    mov esi, ebx
    imul esi, MT_SIZE
    lea edi, [mt_table+esi+MT_SAVED]
    lea esi, [mt_table+esi+MT_SWAP]
    clc
    ret
.single:
    mov ebx, 4
    mov esi, process_swap_page
    mov edi, process_swap_saved
    clc
    ret
.no:
    stc
    ret
; CF=0 if the mounted, writable disk has a collision-free reserved tail.
swap_ready:
    cmp byte [persistent], 1
    jne .no
    mov eax, [disk_sectors]
    cmp eax, SWAP_SECTORS+16384+40
    jb .no
    mov edx, [fs_base]
    add edx, 16384+40+SWAP_SECTORS
    jc .no
    cmp eax, edx
    jb .no
    sub eax, SWAP_SECTORS
    mov [swap_start], eax
    mov eax, [disk_selected]
    cmp byte [disk_flush_cap+eax], 1
    jne .no
    ; Disks installed before swap may already have large HSFS data here.
    mov ecx, NFILES
    mov edi, RECORDS
.scan:
    cmp byte [edi], 0
    je .next
    cmp dword [edi+RKIND], 5
    jne .next
    mov eax, [edi+48]
    add eax, [fs_base]
    jc .no
    mov edx, [edi+52]
    add edx, eax
    jc .no
    cmp eax, [disk_sectors]
    jae .no
    cmp edx, [swap_start]
    ja .no
.next:
    add edi, RSIZE
    loop .scan
    clc
    ret
.no:
    stc
    ret
sys_swap_alloc:
    call swap_slot
    jc .unsupported
    cmp dword [edi], 0
    jne .busy
    mov eax, [esi]
    test eax, eax
    jnz .address
    push esi
    call alloc_page
    pop esi
    test eax, eax
    jz .nomem
    mov [esi], eax
    push eax
    mov eax, [mt_current]
    cmp byte [mt_active], 0
    je .single
    imul eax, MT_SIZE
    mov edi, [mt_table+eax+MT_PT]
    jmp .map
.single:
    mov edi, [process_pt]
.map:
    pop eax
    or eax, 7
    mov [edi+16], eax
    invlpg [SWAP_PAGE_VA]
.address:
    mov eax, SWAP_PAGE_VA
    ret
.busy:
    mov eax, -16
    ret
.nomem:
    mov eax, -12
    ret
.unsupported:
    mov eax, -38
    ret
sys_swap_out:
    call swap_slot
    jc sys_swap_alloc.unsupported
    cmp dword [edi], 0
    jne sys_swap_alloc.busy
    cmp dword [esi], 0
    je .invalid
    push esi
    push edi
    push ebx
    call swap_ready
    pop ebx
    pop edi
    pop esi
    jc .nodev
    mov eax, ebx
    shl eax, 3
    add eax, [swap_start]
    mov [swap_lba], eax
    mov [swap_phys], esi
    mov eax, [esi]
    mov [swap_buffer], eax
    mov ecx, 8
.write:
    mov eax, [swap_lba]
    mov edi, [swap_buffer]
    push ecx
    mov bl, 1
    call ata
    pop ecx
    jc .io
    inc dword [swap_lba]
    add dword [swap_buffer], 512
    loop .write
    call disk_flush
    jc .io
    mov esi, [swap_phys]
    mov eax, [mt_current]
    cmp byte [mt_active], 0
    je .single
    imul eax, MT_SIZE
    mov edi, [mt_table+eax+MT_PT]
    jmp .unmap
.single:
    mov edi, [process_pt]
.unmap:
    mov dword [edi+16], 0
    invlpg [SWAP_PAGE_VA]
    mov eax, [esi]
    push esi
    call free_page
    pop esi
    mov dword [esi], 0
    mov edi, esi
    add edi, 4
    mov dword [edi], 1
    xor eax, eax
    ret
.invalid:
    mov eax, -22
    ret
.nodev:
    mov eax, -19
    ret
.io:
    mov eax, -5
    ret
sys_swap_in:
    call swap_slot
    jc sys_swap_alloc.unsupported
    cmp dword [edi], 1
    jne sys_swap_out.invalid
    push esi
    push edi
    push ebx
    call swap_ready
    pop ebx
    pop edi
    pop esi
    jc sys_swap_out.nodev
    mov eax, ebx
    shl eax, 3
    add eax, [swap_start]
    mov [swap_lba], eax
    mov [swap_phys], esi
    call alloc_page
    test eax, eax
    jz sys_swap_alloc.nomem
    mov [swap_allocated], eax
    mov [swap_buffer], eax
    mov ecx, 8
.read:
    mov eax, [swap_lba]
    mov edi, [swap_buffer]
    push ecx
    xor ebx, ebx
    call ata
    pop ecx
    jc .read_fail
    inc dword [swap_lba]
    add dword [swap_buffer], 512
    loop .read
    mov esi, [swap_phys]
    mov eax, [swap_buffer]
    sub eax, 4096
    mov [esi], eax
    push eax
    mov eax, [mt_current]
    cmp byte [mt_active], 0
    je .single
    imul eax, MT_SIZE
    mov edi, [mt_table+eax+MT_PT]
    jmp .map
.single:
    mov edi, [process_pt]
.map:
    pop eax
    or eax, 7
    mov [edi+16], eax
    invlpg [SWAP_PAGE_VA]
    mov dword [esi+4], 0
    mov eax, SWAP_PAGE_VA
    ret
.read_fail:
    mov eax, [swap_allocated]
    call free_page
    jmp sys_swap_out.io
sys_swap_sleep_unsupported:
    mov eax, -38
    ret
swap_start dd 0
swap_lba dd 0
swap_phys dd 0
swap_buffer dd 0
swap_allocated dd 0
