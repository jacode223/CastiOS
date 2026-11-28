; AX05 process: private CR3, CPL3, guarded stack and exit syscall.
%define USER_BASE 0x20000000
process_run:
    mov dword [sys_fd_head], 0
    mov [process_source], esi
    mov [process_length], ecx
    mov [process_kernel_sp], esp
    mov dword [process_pd], 0
    mov dword [process_pt], 0
    mov dword [process_code], 0
    mov dword [process_stack], 0
    mov dword [process_kstack], 0
    mov dword [process_swap_page], 0
    mov dword [process_swap_saved], 0
    call alloc_page
    mov [process_pd], eax
    test eax, eax
    jz .failed
    call alloc_page
    mov [process_pt], eax
    test eax, eax
    jz .failed
    call alloc_page
    mov [process_code], eax
    test eax, eax
    jz .failed
    call alloc_page
    mov [process_stack], eax
    test eax, eax
    jz .failed
    call alloc_page
    mov [process_kstack], eax
    test eax, eax
    jz .failed
    mov esi, PAGE_DIR
    mov edi, [process_pd]
    mov ecx, 1024
    rep movsd
    mov edi, [process_pt]
    mov eax, [process_code]
    or eax, 5                  ; user read/execute, no writes
    mov [edi], eax
    mov eax, [process_stack]
    or eax, 7
    mov [edi+8], eax
    mov eax, [process_pt]
    or eax, 7
    mov edi, [process_pd]
    mov [edi+128*4], eax
    mov esi, [process_source]
    mov edi, [process_code]
    mov ecx, [process_length]
    rep movsb
    ; ret from AX05 lands here; exit(EAX) through int 0x80.
    mov byte [edi], 0x89
    mov byte [edi+1], 0xc3
    mov byte [edi+2], 0xb8
    mov dword [edi+3], 1
    mov word [edi+7], 0x80cd
    mov eax, [process_stack]
    add eax, 4092
    mov edx, [process_length]
    add edx, USER_BASE
    mov [eax], edx
    call process_init_tss
.ready:
    mov eax, [process_kstack]
    add eax, 4096
    mov [process_tss+4], eax
    mov byte [process_active], 1
    mov eax, [process_pd]
    mov cr3, eax
    push dword 35                 ; user SS
    push dword USER_BASE+0x2ffc  ; return address on user stack
    pushfd
    or dword [esp], 0x200
    push dword 27                 ; user CS
    push dword USER_BASE
    xor eax, eax
    iretd
.returned:
    mov eax, [process_result]
    push eax
    call process_release
    cmp byte [process_painted], 0
    je .console_ready
    mov byte [process_painted], 0
    call ext_repaint
.console_ready:
    pop eax
    clc
    ret
.failed:
    call process_release
    stc
    ret
process_release:
    mov dword [sys_fd_head], 0
    mov dword [sys_fd_pos], 0
    mov edi, [process_pt]
    test edi, edi
    jz .swap
    call demand_release_pt
.swap:
    mov eax, [process_swap_page]
    test eax, eax
    jz .code
    call free_page
    mov dword [process_swap_page], 0
.code:
    mov eax, [process_code]
    test eax, eax
    jz .stack
    call free_page
.stack:
    mov eax, [process_stack]
    test eax, eax
    jz .pt
    call free_page
.pt:
    mov eax, [process_pt]
    test eax, eax
    jz .pd
    call free_page
.pd:
    mov eax, [process_pd]
    test eax, eax
    jz .ks
    call free_page
.ks:
    mov eax, [process_kstack]
    test eax, eax
    jz .done
    call free_page
.done:
    ret
process_init_tss:
    cmp byte [process_tss_ready], 0
    jne .ready
    mov eax, process_tss
    mov word [gdt+40], 103
    mov word [gdt+42], ax
    shr eax, 16
    mov byte [gdt+44], al
    mov byte [gdt+45], 0x89
    mov byte [gdt+46], 0
    mov byte [gdt+47], ah
    mov word [process_tss+8], 16
    mov word [process_tss+102], 104
    mov ax, 40
    ltr ax
    mov byte [process_tss_ready], 1
.ready:
    ret
process_int80:
    cld
    test byte [esp+4], 3
    jz nasm_int80
    cmp byte [mt_active], 0
    jne mt_syscall
    cmp eax, 1
    jne .service
    mov [process_result], ebx
    jmp process_return
.service:
    cmp eax, 2
    jne .call
    xor eax, eax                ; no other process to yield to
    iretd
.call:
    pushad
    call syscall_service
    mov [esp+28], eax
    popad
    iretd
; ABI AX05: EAX=3 getpid, 4 ticks, 5 write(EBX=buf, ECX=len).
; User buffers must be mapped in the current process; never trust CPL3 pointers.
syscall_service:
    cmp eax, 3
    je .pid
    cmp eax, 4
    je .ticks
    cmp eax, 5
    je .write
    cmp eax, 6
    je sys_open
    cmp eax, 7
    je sys_read
    cmp eax, 8
    je sys_close
    cmp eax, 9
    je sys_stat
    cmp eax, 10
    je sys_file_write
    cmp eax, 15
    je sys_swap_alloc
    cmp eax, 16
    je sys_swap_out
    cmp eax, 17
    je sys_swap_in
    cmp eax, 18
    je sys_swap_sleep_unsupported
    cmp eax, 19
    je .gfx_width
    cmp eax, 20
    je .gfx_height
    cmp eax, 21
    je .gfx_rectangle
    cmp eax, 22
    je .gfx_key
    cmp eax, 23
    je sys_gfx_text4
    cmp eax, 25
    je sys_mouse_state
    cmp eax, 26
    je sys_input_event
    cmp eax, 24
    je .disk_capacity
    mov eax, -38                 ; ENOSYS
    ret
.disk_capacity:
    cmp ebx, 4
    jae .gfx_invalid
    mov eax, [disk_caps+ebx*4]
    ret
.gfx_key:
    cmp byte [mt_active], 0
    jne .gfx_busy
    sti
    call getkey
    cli
    movzx eax, al
    ret
.gfx_busy:
    mov eax, -16
    ret
.gfx_rectangle:
    ; EBX: x|y<<16, ECX: width|height<<16, EDX: RGB.
    push edx
    mov eax, ecx
    shr eax, 16
    push eax
    movzx eax, cx
    push eax
    mov eax, ebx
    shr eax, 16
    push eax
    movzx eax, bx
    push eax
    push dword 12
    push esp
    call [0x20018]
    add esp, 28
    test eax, eax
    jz .gfx_invalid
.gfx_success:
    cmp byte [process_active], 0
    je .gfx_ok
    mov byte [process_painted], 1
.gfx_ok:
    xor eax, eax
    ret
.gfx_invalid:
    mov eax, -22
    ret
.gfx_width:
    cmp byte [fb_active], 0
    je .gfx_unavailable
    mov eax, [fb_width]
    ret
.gfx_height:
    cmp byte [fb_active], 0
    je .gfx_unavailable
    mov eax, [fb_height]
    ret
.gfx_unavailable:
    mov eax, -19
    ret
.pid:
    mov eax, 1
    cmp byte [mt_active], 0
    je .done
    mov eax, [mt_current]
    cmp byte [mt_active], 2
    jne .foreground
    call mt_pid_current
    jmp .done
.foreground:
    inc eax
.done:
    ret
.ticks:
    mov eax, [ticks]
    ret
.write:
    test ecx, ecx
    jz .zero
    cmp ecx, 256
    ja .invalid
    mov esi, ebx
    call sys_user_range
    jc .fault
    ; Validate all bytes before printing any of them.
    mov esi, ebx
    mov edx, ecx
.validate:
    mov al, [esi]
    cmp al, 10
    je .valid
    cmp al, 32
    jb .invalid
    cmp al, 126
    ja .invalid
.valid:
    inc esi
    dec edx
    jnz .validate
    mov esi, ebx
    mov edx, ecx
.emit:
    movzx eax, byte [esi]
    call putc
    inc esi
    dec edx
    jnz .emit
    mov eax, ecx
    ret
.zero:
    xor eax, eax
    ret
.invalid:
    mov eax, -22                 ; EINVAL
    ret
.fault:
    mov eax, -14                 ; EFAULT
    ret
process_fault:
    test byte [esp+8], 3
    jz panic
    call demand_fault
    jnc .resume
    cmp byte [mt_active], 0
    jne mt_fault
    mov dword [process_result], 0xfffffffe
    jmp process_return
.resume:
    add esp, 4                ; page fault error code
    iretd
process_invalid:
    test byte [esp+4], 3
    jz panic
    cmp byte [mt_active], 0
    jne mt_fault
    mov dword [process_result], 0xfffffffe
    jmp process_return
process_return:
    cli
    mov eax, PAGE_DIR
    mov cr3, eax
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, [process_kernel_sp]
    mov byte [process_active], 0
    sti
    jmp process_run.returned
align 8
process_tss times 104 db 0
process_tss_ready db 0
process_active db 0
process_painted db 0
process_pd dd 0
process_pt dd 0
process_code dd 0
process_stack dd 0
process_kstack dd 0
process_source dd 0
process_length dd 0
process_kernel_sp dd 0
process_result dd 0
process_cap dd 0
process_swap_page dd 0
process_swap_saved dd 0
