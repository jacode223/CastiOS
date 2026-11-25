; Real uploaded NASM executable, adapted through the i386 ABI in nasm_runtime.c.
; Single trusted CPL0 tool; no process isolation is claimed.
cmd_nasm:
    cmp dword [nasm_size], 0
    je .unavailable
    pushad
    mov dword [nasm_argc], 1
    mov dword [nasm_argv], n_nasm
    mov esi, [args]
.arg:
    call spaces
    cmp byte [esi], 0
    je .start
    mov eax, [nasm_argc]
    cmp eax, 16
    jae .too_many
    mov [nasm_argv+eax*4], esi
    inc dword [nasm_argc]
.scan:
    cmp byte [esi], 0
    je .start
    cmp byte [esi], ' '
    je .cut
    inc esi
    jmp .scan
.cut:
    mov byte [esi], 0
    inc esi
    jmp .arg
.start:
    ; Transaction: NASM sees a private snapshot; errors cannot truncate source
    ; or existing output. Only a successful exit may publish the new snapshot.
    mov esi, FS
    mov edi, 0x4000000
    mov ecx, (512+NFILES*RSIZE)/4
    rep movsd
    push dword gdt
    push dword nasm_console
    push dword [fs_cwd]
    push dword nasm_argv
    push dword [nasm_argc]
    push dword [nasm_size]
    push dword 0x3000000
    call [0x20000]
    add esp, 28
    test eax, eax
    jz .invalid
    mov [nasm_kernel_sp], esp
    mov esp, eax
    xor ebp, ebp
    xor edx, edx
    cld
    mov eax, cr0
    and eax, ~0x0c
    or eax, 2
    mov cr0, eax
    fninit
    jmp dword [0x3000000+24]
.too_many:
    mov esi, nasm_usage
    call puts
    popad
    ret
.invalid:
    mov esi, nasm_invalid
    call puts
    popad
    ret
.unavailable:
    mov esi, nasm_unavailable
    jmp puts
nasm_console:
    mov eax, [esp+4]
    jmp putc
nasm_int80:
    cld
    cmp eax, 1
    je nasm_exit
    cmp eax, 252
    je nasm_exit
    pushad
    push esp
    call [0x20004]
    add esp, 4
    popad
    iretd
nasm_exit:
    mov [nasm_status], ebx
    mov ax, 16
    mov gs, ax
    mov fs, ax
    mov esp, [nasm_kernel_sp]
    sti
    cmp dword [nasm_status], 0
    jne .failed
    call [0x20008]
    test eax, eax
    jz .done
    push dword 0x4000000
    call [0x2000c]
    add esp, 4
    test eax, eax
    jnz .corrupt
    mov esi, 0x4000000
    mov edi, FS
    mov ecx, (512+NFILES*RSIZE)/4
    rep movsd
    call sync
.done:
    mov esi, nasm_ok
    call puts
    popad
    ret
.corrupt:
    mov esi, nasm_corrupt
    call puts
    popad
    ret
.failed:
    mov esi, nasm_failed
    call puts
    mov eax, [nasm_status]
    call number
    call nl
    popad
    ret
nasm_argc dd 0
nasm_argv times 16 dd 0
nasm_kernel_sp dd 0
nasm_status dd 0
nasm_ok db 'NASM terminado: OK',10,0
nasm_failed db 'NASM error; transaccion descartada. Codigo=',0
nasm_invalid db 'Modulo NASM ELF32 invalido.',10,0
nasm_unavailable db 'NASM requiere el modulo incluido y 200 MiB de RAM (usa -m 200).',10,0
nasm_usage db 'NASM: maximo 15 argumentos, sin comillas.',10,0
nasm_corrupt db 'NASM: snapshot ASFS invalido; transaccion descartada.',10,0
