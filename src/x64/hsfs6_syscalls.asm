; Syscall 6: read a named HSFS6 file into the caller's data page.
; RDI=name in user code page (NUL <=63), RSI=destination in data page,
; RDX=count <=512, RCX=64-bit offset. RAX=bytes read or negative errno.
hs6_sys_read:
    mov r13, rdx
    mov r12, rcx
    mov r14, rsi
    cmp byte [hs6_ready], 1
    jne .unmounted
    cmp rdi, USER_BASE
    jb .fault
    mov rax, USER_BASE+4096
    cmp rdi, rax
    jae .fault
    mov rbx, rdi
    xor r8d, r8d
.name:
    cmp rbx, rax
    jae .fault
    mov dl, [rbx]
    mov [hs6_sys_name+r8], dl
    inc rbx
    test dl, dl
    jz .name_done
    inc r8
    cmp r8, 63
    ja .fault
    jmp .name
.name_done:
    cmp r13, 512
    ja .invalid
    cmp r14, USER_BASE+0x2000
    jb .fault
    mov rax, USER_BASE+0x3000
    cmp r14, rax
    ja .fault
    sub rax, r14
    cmp r13, rax
    ja .fault
    mov rsi, hs6_sys_name
    call hs6_resolve
    jc .missing
    test rdi, rdi
    jz .missing
    jmp .found
.found:
    cmp dword [rdi+64], 1
    jne .io
    mov rbp, rdi
    mov edi, [rbp+68]
    mov esi, [rbp+72]
    mov edx, [rbp+76]
    mov ecx, 4
    call permission_check
    test eax, eax
    jz .denied
    mov rax, [rbp+80]
    mov r15, [rbp+88]
    cmp r15, 80
    jb .io
    mov rdx, rax
    add rdx, 511
    jc .io
    shr rdx, 9
    add rdx, r15
    jc .io
    cmp rdx, [hs6_total]
    ja .io
    cmp rdx, 0x10000000
    ja .io
    cmp r12, rax
    jae .empty
    sub rax, r12
    cmp r13, rax
    jbe .length_ok
    mov r13, rax
.length_ok:
    mov rbx, r13
.sector:
    test r13, r13
    jz .done
    mov rax, r12
    shr rax, 9
    add rax, r15
    mov edx, [hs6_base]
    add rax, rdx
    cmp rax, 0x10000000
    jae .io
    mov rdi, hs6_sector
    call ata_read64
    jc .io
    mov rax, r12
    and eax, 511
    mov ecx, 512
    sub ecx, eax
    cmp rcx, r13
    jbe .part
    mov rcx, r13
.part:
    mov rdx, rcx
    lea rsi, [hs6_sector+rax]
    mov rdi, r14
    rep movsb
    add r14, rdx
    add r12, rdx
    sub r13, rdx
    jmp .sector
.done:
    mov rax, rbx
    ret
.empty:
    xor eax, eax
    ret
.missing:
    mov rax, -2
    ret
.denied:
    mov rax, -13
    ret
.invalid:
    mov rax, -22
    ret
.io:
    mov rax, -5
    ret
.unmounted:
    mov rax, -19
    ret
.fault:
    mov rax, -14
    ret
hs6_sys_name times 64 db 0
; Syscall 19: file size in bytes, after read permission check.
; RDI=user code-page path; RAX=size or negative errno.
hs6_sys_filesize:
    cmp byte [hs6_ready], 1
    jne .nodev
    cmp rdi, USER_BASE
    jb .fault
    cmp rdi, USER_BASE+4096
    jae .fault
    xor ecx, ecx
.copy:
    cmp rdi, USER_BASE+4096
    jae .fault
    mov al, [rdi]
    mov [hs6_sys_name+rcx], al
    inc rdi
    test al, al
    jz .find
    inc ecx
    cmp ecx, 63
    ja .fault
    jmp .copy
.find:
    mov rsi, hs6_sys_name
    call hs6_resolve
    jc .missing
    test rdi, rdi
    jz .missing
    cmp dword [rdi+64], 1
    jne .missing
    mov rbp, rdi
    mov edi, [rbp+68]
    mov esi, [rbp+72]
    mov edx, [rbp+76]
    mov ecx, 4
    call permission_check
    test eax, eax
    jz .denied
    mov rax, [rbp+80]
    test rax, rax              ; negative values are reserved for errors
    js .overflow
    ret
.nodev: mov rax, -19
    ret
.fault: mov rax, -14
    ret
.missing: mov rax, -2
    ret
.denied: mov rax, -13
    ret
.overflow: mov rax, -75
    ret
; Syscall 7: root-only small text write. Both input strings must reside in
; the immutable user code page, bounded and NUL terminated before its end.
hs6_sys_write:
    cmp byte [hs6_ready], 1
    jne .nodev
    movzx eax, byte [task_current]
    cmp dword [task_uids+rax*4], 0
    jne .denied
    mov rbx, rsi
    mov rsi, rdi
    mov rdi, hs6_sys_line
    xor r8d, r8d
.name:
    cmp rsi, USER_BASE
    jb .fault
    cmp rsi, USER_BASE+4096
    jae .fault
    mov al, [rsi]
    inc rsi
    test al, al
    jz .space
    cmp r8d, 31
    jae .invalid
    mov [rdi], al
    inc rdi
    inc r8d
    jmp .name
.space:
    test r8d, r8d
    jz .invalid
    mov byte [rdi], ' '
    inc rdi
    mov rsi, rbx
    xor r8d, r8d
.text:
    cmp rsi, USER_BASE
    jb .fault
    cmp rsi, USER_BASE+4096
    jae .fault
    mov al, [rsi]
    inc rsi
    test al, al
    jz .end
    cmp r8d, 255
    jae .invalid
    mov [rdi], al
    inc rdi
    inc r8d
    jmp .text
.end:
    test r8d, r8d
    jz .invalid
    mov byte [rdi], 0
    mov rsi, hs6_sys_line
    call hs6_write
    movsxd rax, dword [hs6_write_status]
    ret
.nodev:
    mov rax, -19
    ret
.denied:
    mov rax, -13
    ret
.invalid:
    mov rax, -22
    ret
.fault:
    mov rax, -14
    ret
hs6_sys_line times 288 db 0
