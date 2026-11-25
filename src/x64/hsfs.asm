; HSFS5 read-only on primary ATA master, LBA28. Metadata scratch at 6 MiB.
; All device polls have finite bounds; no writes are issued by this driver.
HSBUF equ 0x600000
HSCOUNT equ 480
HSSECTORS equ 7681
ata_read64:
    ; Retry a failed IDE sector once, keeping the caller's destination intact.
    ; AHCI failures poison the DMA port and must never be retried here.
    push rax
    push rdi
    call ata_read64_once
    jnc .success
    inc dword [disk64_read_errors]
    cmp byte [ahci64_active], 1
    je .failed
    mov rdi, [rsp]
    mov eax, [rsp+8]
    inc dword [disk64_read_retries]
    call ata_read64_once
    jnc .success
    inc dword [disk64_read_errors]
.failed:
    add rsp, 16
    stc
    ret
.success:
    add rsp, 16
    clc
    ret
ata_read64_once:
    ; EAX=LBA, RDI=512-byte destination; returns CF on error.
    cmp byte [ahci64_active], 1
    je ahci64_read
    cmp eax, 0x10000000
    jae .error
    mov r8d, eax
    mov dx, 0x1f6
    shr eax, 24
    and al, 15
    or al, 0xe0
    out dx, al
    mov dx, 0x3f6
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    mov dx, 0x1f7
    mov ecx, 1000000
.idle:
    in al, dx
    test al, al
    jz .error
    cmp al, 0xff
    je .error
    test al, 0x80
    jz .issue
    loop .idle
    jmp .error
.issue:
    mov dx, 0x1f2
    mov al, 1
    out dx, al
    inc dx
    mov eax, r8d
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    mov dx, 0x1f7
    mov al, 0x20
    out dx, al
    mov ecx, 1000000
.wait:
    in al, dx
    test al, al
    jz .error
    cmp al, 0xff
    je .error
    test al, 0x80
    jnz .again
    test al, 0x21
    jnz .error
    test al, 8
    jnz .ready
.again:
    loop .wait
    jmp .error
.ready:
    mov dx, 0x1f0
    mov ecx, 256
    rep insw
    clc
    ret
.error:
    stc
    ret

; Read complete copy into HSBUF, validate header and additive checksum.
; EAX=starting LBA; returns CF on error.
hs_copy:
    mov r12d, eax
    mov r13d, HSSECTORS
    mov rdi, HSBUF
.read:
    mov eax, r12d
    call ata_read64
    jc .bad
    inc r12d
    dec r13d
    jnz .read
    cmp dword [HSBUF], 0x35465348
    jne .bad
    cmp dword [HSBUF+4], 5
    jne .bad
    cmp dword [HSBUF+8], HSCOUNT
    jne .bad
    cmp dword [HSBUF+12], 8192
    jne .bad
    mov rsi, HSBUF+512
    mov ecx, HSCOUNT*8192
    xor edx, edx
.sum:
    movzx eax, byte [rsi]
    add edx, eax
    inc rsi
    dec ecx
    jnz .sum
    cmp edx, [HSBUF+16]
    jne .bad
    clc
    ret
.bad:
    stc
    ret

hs_mount:
    mov byte [hs_ready], 0
    ; Require the entire metadata buffer to lie within a usable E820 region.
    mov eax, [boot_info]
    test dword [rax], 1<<6
    jz .missing
    mov edx, [rax+48]
    mov ecx, [rax+44]
    mov r8d, edx
    add r8, rcx
    cmp r8, 0x40000000
    ja .missing
.map_scan:
    cmp rdx, r8
    jae .missing
    mov r9, r8
    sub r9, rdx
    cmp r9, 24
    jb .missing
    mov ecx, [rdx]
    cmp ecx, 20
    jb .missing
    lea r9, [rdx+rcx+4]
    cmp r9, r8
    ja .missing
    cmp dword [rdx+20], 1
    jne .map_next
    mov rax, [rdx+4]
    cmp rax, HSBUF
    ja .map_next
    add rax, [rdx+12]
    jc .missing
    cmp rax, HSBUF+HSSECTORS*512
    jae .map_ok
.map_next:
    mov rdx, r9
    jmp .map_scan
.map_ok:
    mov byte [hs_primary_valid], 0
    mov eax, 32768             ; installed HDD: 16 MiB
    call hs_copy
    jc .mirror
    mov byte [hs_primary_valid], 1
    mov eax, [HSBUF+20]
    mov [hs_generation], eax
.mirror:
    mov eax, 40960             ; mirror: 20 MiB
    call hs_copy
    jc .primary
    cmp byte [hs_primary_valid], 0
    je .ok_mirror
    mov eax, [HSBUF+20]
    sub eax, [hs_generation]
    jg .ok_mirror
.primary:
    cmp byte [hs_primary_valid], 1
    jne .missing
    mov eax, 32768
    call hs_copy
    jc .missing
    mov byte [hs_copy_used], 1
    jmp .mounted
.ok_mirror:
    mov byte [hs_copy_used], 2
.mounted:
    mov byte [hs_ready], 1
    mov dword [hs_cwd], 0xffffffff
    mov rsi, hs_mounted
    call puts
    movzx eax, byte [hs_copy_used]
    call decimal
    mov al, 10
    call putc
    ret
.missing:
    mov rsi, hs_missing
    jmp puts

; Resolve absolute/relative path. ESI=path, returns EAX=index or ROOT, CF on error.
hs_resolve:
    mov r14d, [hs_cwd]
    cmp byte [rsi], '/'
    jne .component
    mov r14d, 0xffffffff
.component:
    cmp byte [rsi], '/'
    jne .name
    inc rsi
    jmp .component
.name:
    cmp byte [rsi], 0
    je .success
    mov rdi, hs_name
    xor ecx, ecx
.copy:
    mov al, [rsi]
    test al, al
    jz .copied
    cmp al, '/'
    je .copied
    cmp ecx, 31
    jae .bad
    mov [rdi+rcx], al
    inc ecx
    inc rsi
    jmp .copy
.copied:
    mov byte [rdi+rcx], 0
    cmp byte [hs_name], '.'
    jne .lookup
    cmp byte [hs_name+1], 0
    je .component
    cmp word [hs_name+1], '.'
    jne .lookup
    cmp r14d, 0xffffffff
    je .component
    cmp r14d, HSCOUNT
    jae .bad
    mov eax, r14d
    shl rax, 13
    mov r14d, [HSBUF+512+rax+32]
    jmp .component
.lookup:
    xor ebx, ebx
.find:
    cmp ebx, HSCOUNT
    jae .bad
    mov eax, ebx
    shl rax, 13
    lea rdi, [HSBUF+512+rax]
    cmp byte [rdi], 0
    je .next
    cmp byte [rdi+31], 0
    jne .bad
    cmp dword [rdi+36], 4
    je .next
    cmp [rdi+32], r14d
    jne .next
    push rsi
    mov rsi, hs_name
    call streq
    pop rsi
    je .found
.next:
    inc ebx
    jmp .find
.found:
    mov r14d, ebx
    cmp byte [rsi], 0
    je .success
    cmp dword [rdi+36], 2
    jne .bad
    jmp .component
.success:
    mov eax, r14d
    clc
    ret
.bad:
    stc
    ret

hs_command:
    cmp byte [hs_ready], 1
    jne .unmounted
    ; RSI points at shell argument; EDX=0 ls, 1 cat, 2 cd
    mov [hs_op], edx
    call hs_resolve
    jc .bad
    mov ebx, eax
    cmp dword [hs_op], 1
    je .cat
    cmp ebx, 0xffffffff
    je .dir
    cmp ebx, HSCOUNT
    jae .bad
    mov eax, ebx
    shl rax, 13
    cmp dword [HSBUF+512+rax+36], 2
    jne .bad
.dir:
    cmp dword [hs_op], 2
    je .cd
    xor r12d, r12d
.list:
    cmp r12d, HSCOUNT
    jae .done
    mov eax, r12d
    shl rax, 13
    lea rdi, [HSBUF+512+rax]
    cmp byte [rdi], 0
    je .next
    cmp byte [rdi+31], 0
    jne .bad
    cmp dword [rdi+32], ebx
    jne .next
    cmp dword [rdi+36], 4
    je .next
    mov rsi, rdi
    call puts
    cmp dword [rdi+36], 2
    jne .nl
    mov al, '/'
    call putc
.nl:
    mov al, 10
    call putc
.next:
    inc r12d
    jmp .list
.cd:
    mov [hs_cwd], ebx
    ret
.cat:
    cmp ebx, HSCOUNT
    jae .bad
    mov eax, ebx
    shl rax, 13
    lea rdi, [HSBUF+512+rax]
    cmp dword [rdi+36], 5
    je .large
    cmp dword [rdi+36], 1
    jne .bad
    mov r13d, [rdi+40]
    cmp r13d, 3840000
    ja .bad
    mov r14d, ebx
    xor r15d, r15d
.extent:
    inc r15d
    cmp r15d, HSCOUNT
    ja .bad
    cmp ebx, HSCOUNT
    jae .bad
    mov eax, ebx
    shl rax, 13
    lea rdi, [HSBUF+512+rax]
    cmp r15d, 1
    je .data
    cmp byte [rdi], 255
    jne .bad
    cmp dword [rdi+36], 4
    jne .bad
    cmp [rdi+32], r14d
    jne .bad
.data:
    mov ecx, r13d
    cmp ecx, 8000
    jbe .print
    mov ecx, 8000
.print:
    lea rsi, [rdi+64]
    sub r13d, ecx
.chars:
    test ecx, ecx
    jz .more
    mov al, [rsi]
    call putc
    inc rsi
    dec ecx
    jmp .chars
.more:
    test r13d, r13d
    jz .done
    mov ebx, [rdi+44]
    test ebx, ebx
    jz .bad
    dec ebx
    jmp .extent
.large:
    mov r13d, [rdi+40]
    test r13d, r13d
    jz .bad
    cmp r13d, 104857600
    ja .bad
    mov r12d, [rdi+48]
    cmp r12d, 16384
    jb .bad
    mov eax, r13d
    add eax, 511
    shr eax, 9
    cmp eax, [rdi+52]
    jne .bad
    add r12d, 32768            ; sectors relative to installed volume
    jc .bad
    add eax, r12d
    jc .bad
    cmp eax, 0x10000000
    ja .bad
.large_sector:
    mov eax, r12d
    mov rdi, hs_sector
    call ata_read64
    jc .bad
    inc r12d
    mov ecx, r13d
    cmp ecx, 512
    jbe .large_ready
    mov ecx, 512
.large_ready:
    sub r13d, ecx
    mov rsi, hs_sector
.large_print:
    mov al, [rsi]
    call putc
    inc rsi
    dec ecx
    jnz .large_print
    test r13d, r13d
    jnz .large_sector
    ret
.done:
    ret
.unmounted:
    mov rsi, hs_not_mounted
    jmp puts
.bad:
    mov rsi, hs_bad
    jmp puts

hs_mounted db 'HSFS5 montado en solo lectura, copia ',0
hs_missing db 'HSFS5 no disponible: disco IDE o copias invalidas',10,0
hs_not_mounted db 'HSFS5 no montado; usa mount',10,0
hs_bad db 'HSFS5: ruta o archivo invalido',10,0
hs_ready db 0
hs_primary_valid db 0
hs_copy_used db 0
hs_generation dd 0
hs_cwd dd 0xffffffff
hs_op dd 0
hs_name times 32 db 0
hs_sector times 512 db 0
