; Read-only AHCI x86-64, adapted from CastiOS i386 driver.
; First PCI AHCI HBA, first SATA disk, serialized polling and bounce DMA.
ahci64_probe:
    cmp byte [ahci64_active], 0
    jne .already
    xor ebp, ebp
.scan:
    mov eax, ebp
    shl eax, 8
    or eax, 0x80000008
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in eax, dx
    shr eax, 8
    cmp eax, 0x010601
    je .found
    inc ebp
    cmp ebp, 65536
    jb .scan
    jmp .failure
.found:
    mov eax, ebp
    shl eax, 8
    or eax, 0x80000024
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in eax, dx
    test al, 1
    jnz .failure
    and eax, 0xfffffff0
    cmp eax, 0xc0000000
    jb .failure
    cmp eax, 0xffffe000
    ja .failure
    mov [ahci64_hba], eax
    ; Map the 3-4 GiB physical region uncached in kernel and CPL3 tables.
    mov rdi, ahci64_mmio_pd
    mov eax, 0xc000009b
    mov ecx, 512
.map:
    mov [rdi], rax
    add rax, 0x200000
    add rdi, 8
    loop .map
    mov rax, ahci64_mmio_pd
    or rax, 3
    mov [pdpt+24], rax
    xor ecx, ecx
.task_map:
    mov rdx, [task_cr3+rcx*8]
    test rdx, rdx
    jz .next_task
    mov rdx, [rdx]
    and rdx, -4096
    mov [rdx+24], rax
.next_task:
    inc ecx
    cmp ecx, 2
    jb .task_map
    mov rdx, cr3
    mov cr3, rdx
    mov eax, ebp
    shl eax, 8
    or eax, 0x80000004
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in ax, dx
    or ax, 6
    out dx, ax
    mov esi, [ahci64_hba]
    test dword [rsi+0x24], 1
    jz .owned
    or dword [rsi+0x28], 2
    mov ecx, 2000000
.handoff:
    test dword [rsi+0x28], 0x11
    jz .owned
    loop .handoff
    jmp .failure
.owned:
    or dword [rsi+4], 0x80000000
    and dword [rsi+4], 0xfffffffd
    xor ebp, ebp
.ports:
    mov esi, [ahci64_hba]
    bt dword [rsi+12], ebp
    jnc .next
    mov ebx, ebp
    shl ebx, 7
    lea rbx, [rsi+rbx+0x100]
    mov eax, [rbx+0x28]
    and eax, 0xf0f
    cmp eax, 0x103
    jne .next
    cmp dword [rbx+0x24], 0x101
    jne .next
    and dword [rbx+0x18], 0xfffffffe
    mov ecx, 2000000
.stop:
    test dword [rbx+0x18], 0x8000
    jz .stop_fis
    loop .stop
    jmp .next
.stop_fis:
    and dword [rbx+0x18], 0xffffffef
    mov ecx, 2000000
.fis:
    test dword [rbx+0x18], 0x4000
    jz .allocate
    loop .fis
    jmp .next
.allocate:
    call frame_alloc
    test rax, rax
    jz .failure
    mov [ahci64_dma], rax
    mov [ahci64_port], rbx
    mov [rbx], eax
    mov dword [rbx+4], 0
    add eax, 1024
    mov [rbx+8], eax
    mov dword [rbx+12], 0
    mov dword [rbx+0x14], 0
    mov dword [rbx+0x10], -1
    mov dword [rbx+0x30], -1
    or dword [rbx+0x18], 0x10000017
    mov byte [ahci64_op], 0xec
    mov qword [ahci64_lba], 0
    mov qword [ahci64_target], ahci64_ident
    call ahci64_command
    jc .failure
    test word [ahci64_ident+49*2], 1<<9
    jz .failure
    test word [ahci64_ident+83*2], 1<<10
    jz .failure
    mov rax, [ahci64_ident+100*2]
    test rax, rax
    jz .failure
    mov [ahci64_sectors], rax
    mov byte [ahci64_active], 1
    mov byte [hs6_ready], 0
    mov rsi, ahci64_success
    jmp puts
.next:
    inc ebp
    cmp ebp, 32
    jb .ports
.failure:
    mov rsi, ahci64_failure
    jmp puts
.already:
    mov rsi, ahci64_success
    jmp puts
ahci64_read:
    cmp rax, [ahci64_sectors]
    jae .bad
    push rbx
    push rsi
    mov [ahci64_lba], rax
    mov [ahci64_target], rdi
    mov byte [ahci64_op], 0x25
    call ahci64_command
    pop rsi
    pop rbx
    ret
.bad:
    stc
    ret
ahci64_command:
    mov rbx, [ahci64_port]
    mov rsi, [ahci64_dma]
    test rsi, rsi
    jz .bad
    cmp byte [ahci64_poison], 0
    jne .bad
    cmp dword [rbx+0x38], 0
    jne .poison
    cmp dword [rbx+0x34], 0
    jne .poison
    mov ecx, 2000000
.ready:
    test dword [rbx+0x20], 0x88
    jz .setup
    loop .ready
    jmp .poison
.setup:
    lea rdi, [rsi+1280]
    xor eax, eax
    mov ecx, 40
    rep stosd
    mov dword [rsi], 0x10005
    mov dword [rsi+4], 0
    lea eax, [esi+1280]
    mov [rsi+8], eax
    mov dword [rsi+12], 0
    mov byte [rsi+1280], 0x27
    mov byte [rsi+1281], 0x80
    mov al, [ahci64_op]
    mov [rsi+1282], al
    cmp al, 0xec
    je .prdt
    mov byte [rsi+1287], 0x40
    mov rax, [ahci64_lba]
    mov [rsi+1284], ax
    shr rax, 16
    mov [rsi+1286], al
    shr rax, 8
    mov [rsi+1288], al
    shr rax, 8
    mov [rsi+1289], al
    shr rax, 8
    mov [rsi+1290], al
    mov byte [rsi+1292], 1
.prdt:
    lea eax, [esi+2048]
    mov [rsi+1408], eax
    mov dword [rsi+1412], 0
    mov dword [rsi+1420], 511
    mov dword [rbx+0x10], -1
    mov dword [rbx+0x30], -1
    mov dword [rbx+0x38], 1
    mov ecx, 2000000
.wait:
    test dword [rbx+0x10], 0x7d000000
    jnz .poison
    test dword [rbx+0x38], 1
    jz .complete
    loop .wait
    jmp .poison
.complete:
    test byte [rbx+0x20], 0x21
    jnz .poison
    cmp dword [rsi+4], 512
    jne .poison
    lea rsi, [rsi+2048]
    mov rdi, [ahci64_target]
    mov ecx, 128
    rep movsd
    clc
    ret
.poison:
    mov byte [ahci64_poison], 1
    and dword [rbx+0x18], 0xfffffffe
.bad:
    stc
    ret
ahci64_hba dd 0
ahci64_active db 0
ahci64_poison db 0
ahci64_op db 0
ahci64_port dq 0
ahci64_dma dq 0
ahci64_lba dq 0
ahci64_target dq 0
ahci64_sectors dq 0
ahci64_success db 'AHCI SATA listo (solo lectura)',10,0
ahci64_failure db 'AHCI SATA no disponible',10,0
align 16
ahci64_ident times 512 db 0
align 4096
ahci64_mmio_pd times 4096 db 0
