; Multiboot RGB framebuffer console. A fixed 80x25 viewport bounds RAM use.
; Other modes and physical addresses outside our identity map use VGA fallback.
fb64_init:
    mov esi, [boot_info]
    test dword [rsi], 1<<12
    jz .done
    cmp byte [rsi+109], 1       ; direct RGB
    jne .done
    cmp byte [rsi+108], 32
    jne .done
    cmp byte [rsi+113], 8
    jne .done
    cmp byte [rsi+115], 8
    jne .done
    cmp byte [rsi+117], 8
    jne .done
    cmp dword [rsi+92], 0       ; physical address must fit in 32 bits
    jne .done
    mov eax, [rsi+100]
    cmp eax, 640
    jb .done
    cmp eax, 16384
    ja .done
    shl eax, 2
    mov ecx, [rsi+96]
    cmp ecx, eax
    jb .done
    mov eax, [rsi+104]
    cmp eax, 400
    jb .done
    cmp eax, 16384
    ja .done
    mul rcx
    test rdx, rdx
    jnz .done
    mov edi, [rsi+88]
    test edi, edi
    jz .done
    add rax, rdi
    mov rdx, 0x100000000
    cmp rax, rdx
    ja .done
    cmp rax, 0x40000000
    jbe .mapped
    cmp edi, 0xc0000000
    jb .done
    ; Reuse the AHCI supervisor-only identity map for 3-4 GiB MMIO.
    push rsi
    push rdi
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
.tasks:
    mov rdx, [task_cr3+rcx*8]
    test rdx, rdx
    jz .next
    mov rdx, [rdx]
    and rdx, -4096
    mov [rdx+24], rax
.next:
    inc ecx
    cmp ecx, 2
    jb .tasks
    mov rax, cr3
    mov cr3, rax
    pop rdi
    pop rsi
.mapped:
    mov [fb64_base], rdi
    mov eax, [rsi+100]
    mov [fb64_width], eax
    mov eax, [rsi+104]
    mov [fb64_height], eax
    mov eax, [rsi+96]
    mov [fb64_pitch], eax
    mov byte [fb64_active], 1
    ; Clear the viewport only; no framebuffer-sized allocation in RAM.
    mov edx, 400
    xor eax, eax
.clear:
    push rdi
    mov ecx, 640
    rep stosd
    pop rdi
    add rdi, [fb64_pitch]
    dec edx
    jnz .clear
.done:
    ret

; Preserve registers expected by the console and its callers.
fb64_putc:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    movzx ebx, word [cursor]
    cmp al, 10
    je .newline
    cmp al, 8
    je .backspace
    call fb64_draw
    inc ebx
    jmp .wrap
.backspace:
    test ebx, ebx
    jz .save
    dec ebx
    mov al, ' '
    call fb64_draw
    jmp .save
.newline:
    mov eax, ebx
    xor edx, edx
    mov ecx, 80
    div ecx
    sub ebx, edx
    add ebx, 80
.wrap:
    cmp ebx, 2000
    jb .save
    call fb64_scroll
    mov ebx, 1920
.save:
    mov [cursor], bx
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; AL = character, EBX = cell number. White and black are RGB-order independent.
fb64_draw:
    movzx r10d, al
    shl r10, 4
    add r10, fb64_font
    mov eax, ebx
    xor edx, edx
    mov ecx, 80
    div ecx
    shl eax, 4
    imul rax, [fb64_pitch]
    shl edx, 5
    add rax, rdx
    add rax, [fb64_base]
    mov r9, rax
    mov r8d, 16
.row:
    movzx r11d, byte [r10]
    mov rdi, r9
    mov ecx, 8
.pixel:
    xor eax, eax
    test r11b, 0x80
    jz .black
    mov eax, 0xffffff
.black:
    stosd
    shl r11b, 1
    loop .pixel
    inc r10
    add r9, [fb64_pitch]
    dec r8d
    jnz .row
    ret

fb64_scroll:
    mov rdi, [fb64_base]
    mov rsi, [fb64_pitch]
    shl rsi, 4
    add rsi, rdi
    mov edx, 384
.copy:
    push rdi
    push rsi
    mov ecx, 640
    rep movsd
    pop rsi
    pop rdi
    add rsi, [fb64_pitch]
    add rdi, [fb64_pitch]
    dec edx
    jnz .copy
    mov edx, 16
    xor eax, eax
.clear:
    push rdi
    mov ecx, 640
    rep stosd
    pop rdi
    add rdi, [fb64_pitch]
    dec edx
    jnz .clear
    ret

fb64_width dd 0
fb64_height dd 0
fb64_active db 0
align 8
fb64_base dq 0
fb64_pitch dq 0
fb64_font: incbin "src/console/font8x16.bin"
