; Read-only probe for the one IDE target, plus selected AHCI target.
disk64_list:
    cmp byte [ahci64_active], 1
    je .sata
    mov rax, [hs6_total]
    push rax
    mov eax, [hs6_base]
    push rax
    mov dword [hs6_base], 0
    mov qword [hs6_total], 0
    mov byte [hs6_probe_only], 1
    call hs6_identify
    mov byte [hs6_probe_only], 0
    pop rax
    mov [hs6_base], eax
    pop rdx
    mov [hs6_total], rdx
    jc .none
    mov rsi, disk64_ide
    call puts
    mov eax, [hs6_ident+60*2]
    call decimal
    mov rsi, disk64_sectors
    call puts
    jmp .stats
.sata:
    mov rsi, disk64_sata
    call puts
    mov rax, [ahci64_sectors]
    call hs6_decimal
    mov rsi, disk64_sectors
    call puts
.stats:
    mov rsi, disk64_errors_msg
    call puts
    mov eax, [disk64_read_errors]
    call decimal
    mov rsi, disk64_retries_msg
    call puts
    mov eax, [disk64_read_retries]
    call decimal
    mov al, 10
    jmp putc
.none:
    mov rsi, disk64_none
    jmp puts
disk64_ide db 'IDE hda: sectores=',0
disk64_sata db 'AHCI SATA: sectores=',0
disk64_sectors db ' (512 bytes)',10,0
disk64_none db 'No hay disco IDE compatible; usa ahciscan para SATA.',10,0
disk64_errors_msg db 'Lecturas fallidas=',0
disk64_retries_msg db ' reintentos=',0
disk64_read_errors dd 0
disk64_read_retries dd 0
install64_msg db 'install: BORRA TODO hda IDE. Para confirmar: install hda borrar',10,0
install64_confirm db 'hda borrar',0

; Installs the GRUB hybrid payload provided by the live ISO as a Multiboot
; module, with HSFS6 at 16 MiB. MBR is published last after FLUSH.
install64_run:
    cmp byte [ahci64_active], 0
    jne .bad
    mov eax, [boot_info]
    test dword [rax], 1<<3
    jz .no_payload
    cmp dword [rax+20], 1
    jb .no_payload
    mov edx, [rax+24]
    cmp rdx, 0x3ffffff0
    ja .no_payload
    mov eax, [rdx]
    mov ecx, [rdx+4]
    cmp ecx, eax
    jbe .no_payload
    cmp ecx, 0x40000000
    ja .no_payload
    mov [install64_ptr], rax
    sub ecx, eax
    test ecx, 511
    jnz .no_payload
    cmp ecx, 512
    jbe .no_payload
    cmp ecx, 16*1024*1024
    ja .no_payload
    cmp word [rax+510], 0xaa55
    jne .no_payload
    shr ecx, 9
    mov [install64_sectors], ecx
    ; Probe before any write, regardless of the currently mounted volume.
    mov rax, [hs6_total]
    push rax
    mov eax, [hs6_base]
    push rax
    mov qword [hs6_total], 0
    mov dword [hs6_base], 0
    call hs6_identify
    pop rdx
    mov [hs6_base], edx
    pop rdx
    mov [hs6_total], rdx
    jc .bad
    mov eax, [hs6_ident+60*2]
    cmp eax, 34816             ; at least 17 MiB
    jb .bad
    cmp eax, 0x10000000
    jbe .capacity
    mov eax, 0x10000000
.capacity:
    sub eax, 32768
    mov [install64_volume], rax
    mov byte [hs6_ready], 0
    mov dword [hs6_base], 0
    mov r12d, 1
.image:
    cmp r12d, [install64_sectors]
    jae .image_done
    mov eax, r12d
    mov rsi, [install64_ptr]
    mov edx, r12d
    shl rdx, 9
    add rsi, rdx
    call hs6_write_sector
    jc .io
    inc r12d
    jmp .image
.image_done:
    call hs6_flush
    jc .io
    mov rdi, hs6_sector
    mov ecx, 64
    xor eax, eax
    rep stosq
    mov r12d, 32768+16
    mov r13d, 64
.tables:
    mov eax, r12d
    mov rsi, hs6_sector
    call hs6_write_sector
    jc .io
    inc r12d
    dec r13d
    jnz .tables
    call hs6_flush
    jc .io
    mov rdi, hs6_header
    mov ecx, 64
    xor eax, eax
    rep stosq
    mov dword [hs6_header], 'HSFS'
    mov dword [hs6_header+4], 0x36
    mov dword [hs6_header+8], 6
    mov dword [hs6_header+12], 512
    mov rax, [install64_volume]
    mov [hs6_header+24], rax
    xor ebx, ebx
.headers:
    mov eax, ebx
    shl eax, 5
    add eax, 16
    mov [hs6_header+32], rax
    mov dword [hs6_header+44], 0
    mov rsi, hs6_header
    mov ecx, 512
    call hs6_sum
    mov [hs6_header+44], eax
    lea eax, [ebx+32768+8]
    mov rsi, hs6_header
    call hs6_write_sector
    jc .io
    inc ebx
    cmp ebx, 2
    jb .headers
    call hs6_flush
    jc .io
    xor eax, eax              ; write boot sector only after data and HSFS6
    mov rsi, [install64_ptr]
    call hs6_write_sector
    jc .io
    call hs6_flush
    jc .io
    mov rsi, install64_ok
    jmp puts
.no_payload:
    mov rsi, install64_nopayload
    jmp puts
.io:
    mov rsi, install64_io
    jmp puts
.bad:
    mov rsi, install64_bad
    jmp puts
install64_ptr dq 0
install64_volume dq 0
install64_sectors dd 0
install64_ok db 'Instalacion BIOS terminada. Retira ISO y reinicia.',10,0
install64_nopayload db 'Instalacion requiere arrancar desde ISO instaladora.',10,0
install64_io db 'Error de escritura: instalacion incompleta.',10,0
install64_bad db 'Requiere disco IDE hda con LBA28 y FLUSH, minimo 17 MiB.',10,0
