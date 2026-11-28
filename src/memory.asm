; Paginacion de identidad 32 MiB; marcos libres segun mapa Multiboot.
%define PAGE_MAP 0x1b0000
%define PAGE_DIR 0x1d0000
%define PAGE_TABLES 0x1d1000
memory_init:
    ; Modules may overlap PAGE_MAP/PAGE_TABLES: preserve them FIRST.
    mov ebx, [boot_info]
    test ebx, ebx
    jz .halt
    call memory_modules
    mov edi, PAGE_MAP
    mov ecx, 8192
    mov al, 2
    rep stosb
    mov ebx, [boot_info]
    test ebx, ebx
    jz .halt
    test dword [ebx], 64
    jz .halt
    mov esi, [ebx+48]
    mov ebp, esi
    add ebp, [ebx+44]
.region:
    cmp esi, ebp
    jae .paging
    cmp dword [esi+20], 1
    jne .next
    cmp dword [esi+8], 0
    jne .next
    mov eax, [esi+4]
    add eax, 4095
    jc .next
    and eax, 0xfffff000
    mov edx, [esi+4]
    add edx, [esi+12]
    jc .cap
    cmp dword [esi+16], 0
    jne .cap
    cmp edx, 0x2000000
    jbe .range
.cap:
    mov edx, 0x2000000
.range:
    cmp eax, 0x1000000
    jae .frames
    mov eax, 0x1000000
.frames:
    lea ecx, [eax+4096]
    cmp ecx, edx
    ja .next
    mov edi, eax
    shr edi, 12
    cmp edi, 8192
    jae .next
    mov byte [PAGE_MAP+edi], 0
    add eax, 4096
    jmp .frames
.next:
    mov eax, [esi]
    lea esi, [esi+eax+4]
    jmp .region
.paging:
.tables:
    mov edi, PAGE_DIR
    xor eax, eax
    mov ecx, 1024
    rep stosd
    mov edi, PAGE_TABLES
    mov eax, 3
    mov ecx, 8192
.pte:
    stosd
    add eax, 4096
    loop .pte
    mov dword [PAGE_TABLES], 0
    mov edi, PAGE_DIR
    mov eax, PAGE_TABLES+3
    mov ecx, 8
.pde:
    stosd
    add eax, 4096
    loop .pde
    cmp dword [nasm_size], 0
    je .enable
    ; Isolated reserved regions, outside the 16..32 MiB page allocator:
    ; module 48 MiB, transactional ASFS 64 MiB, tool 128..192 MiB.
    mov dword [PAGE_DIR+12*4], 0x3000083
    mov dword [PAGE_DIR+16*4], 0x4000083
    mov edi, PAGE_DIR+32*4
    mov eax, 0x08000083
    mov ecx, 16
.large:
    stosd
    add eax, 0x400000
    loop .large
    mov eax, cr4
    or eax, 0x610 ; PSE, OSFXSR, OSXMMEXCPT for libc's SSE2 routines
    mov cr4, eax
.enable:
    mov eax, PAGE_DIR
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80010000
    mov cr0, eax
    ret
.halt:
    mov esi, memory_error
    call puts
    cli
    jmp stop
memory_modules:
    ; Conservar NASM antes de reubicar el instalador, cuyos destinos pueden
    ; solaparse con la ubicacion original elegida por GRUB para otros modulos.
    mov ebx, [boot_info]
    test dword [ebx], 8
    jz .done
    cmp dword [ebx+20], 0
    je .done
    mov ebp, [ebx+24]
    mov edx, [ebx+20]
.modules:
    mov esi, [ebp]
    cmp dword [esi], 'CINS'
    jne .elf
    mov ecx, [ebp+4]
    sub ecx, esi
    cmp ecx, 8
    jb .nextmod
    cmp ecx, 65536
    ja .nextmod
    cmp dword [esi+4], 0x70008
    jb .nextmod
    mov eax, 0x70000
    add eax, ecx
    cmp [esi+4], eax
    jae .nextmod
    mov edi, 0x70000
    rep movsb
    jmp .nextmod
.elf:
    cmp dword [esi], 0x464c457f
    jne .nextmod
    test dword [ebx], 1
    jz .nextmod
    cmp dword [ebx+8], 196*1024 ; GRUB excludes conventional RAM/ACPI
    jb .nextmod
    mov ecx, [ebp+4]
    sub ecx, esi
    cmp ecx, 0x400000
    ja .nextmod
    mov [nasm_size], ecx
    mov edi, 0x3000000
    rep movsb
.nextmod:
    add ebp, 16
    dec edx
    jnz .modules
    mov ebp, [ebx+24]
    mov esi, [ebp]
    cmp dword [esi], 0x464c457f
    je .done
    mov ecx, [ebp+4]
    sub ecx, esi
    cmp ecx, 0x800000
    ja memory_init.halt
    mov [installer_size], ecx
    mov edi, 0x800000
    rep movsb
.done:
    ret
alloc_page:
    push ecx
    push edi
    mov ecx, 4096
.scan:
    cmp ecx, 8192
    jae .full
    cmp byte [PAGE_MAP+ecx], 0
    je .found
    inc ecx
    jmp .scan
.found:
    mov byte [PAGE_MAP+ecx], 1
    mov eax, ecx
    shl eax, 12
    mov edi, eax
    push eax
    mov ecx, 1024
    xor eax, eax
    rep stosd
    pop eax
    pop edi
    pop ecx
    ret
.full:
    xor eax, eax
    pop edi
    pop ecx
    ret
free_page:
    test eax, 4095
    jnz .bad
    cmp eax, 0x1000000
    jb .bad
    cmp eax, 0x2000000
    jae .bad
    push eax
    shr eax, 12
    cmp byte [PAGE_MAP+eax], 1
    jne .popbad
    mov byte [PAGE_MAP+eax], 0
    pop eax
    xor eax, eax
    ret
.popbad:
    pop eax
.bad:
    mov eax, EINVAL
    ret
cmd_mem:
    mov esi, memory_msg
    call puts
    xor eax, eax
    mov ecx, 8192
    mov edi, PAGE_MAP
.count:
    cmp byte [edi], 0
    jne .next
    inc eax
.next:
    inc edi
    loop .count
    shl eax, 2
    call number
    mov esi, memory_units
    jmp puts
cmd_memtest:
    call alloc_page
    test eax, eax
    jz .fail
    mov ebx, eax
    mov dword [eax], 0x12345678
    call alloc_page
    test eax, eax
    jz .fail
    mov edi, eax
    cmp eax, ebx
    je .fail
    cmp dword [eax], 0
    jne .fail
    call free_page
    test eax, eax
    jnz .fail
    mov eax, ebx
    call free_page
    test eax, eax
    jnz .fail
    mov eax, ebx
    call free_page
    cmp eax, EINVAL
    jne .fail
    mov esi, memory_ok
    jmp puts
.fail:
    mov esi, memory_failed
    jmp puts
boot_info dd 0
installer_size dd 0
nasm_size dd 0
memory_msg db 'Paging activo | libres: ',0
memory_units db ' KiB | marcos 4 KiB, mapa GRUB, ventana 32 MiB',10,0
memory_error db 'Se requiere GRUB Multiboot con mapa de memoria.',10,0
memory_ok db 'Memoria: OK (paginas, zero, free, doble free)',10,0
memory_failed db 'Memoria: FAILED (se requieren al menos 2 paginas libres)',10,0
