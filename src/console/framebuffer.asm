; Multiboot1 RGB framebuffer, 32 bpp XRGB8888; shadow remains 80x25.
; Initialization is called after paging and before console clear.
fb_init:
    pushad
    mov esi, [boot_info]
    test esi, esi
    jz .done
    test dword [esi], 0x1000
    jz .done
    cmp dword [esi+92], 0
    jne .done
    cmp byte [esi+109], 1
    jne .done
    cmp byte [esi+108], 32
    jne .done
    cmp byte [esi+112], 16
    jne .done
    cmp byte [esi+113], 8
    jne .done
    cmp byte [esi+114], 8
    jne .done
    cmp byte [esi+115], 8
    jne .done
    cmp byte [esi+116], 0
    jne .done
    cmp byte [esi+117], 8
    jne .done
    mov eax, [esi+100]
    cmp eax, 1024
    jb .done
    cmp eax, 4096
    ja .done
    mov [fb_width], eax
    shl eax, 2
    cmp [esi+96], eax
    jb .done
    mov eax, [esi+96]
    cmp eax, 32768
    ja .done
    mov [fb_pitch], eax
    mov eax, [esi+104]
    cmp eax, 768
    jb .done
    cmp eax, 2160
    ja .done
    mov [fb_height], eax
    mul dword [fb_pitch]
    test edx, edx
    jnz .done
    mov ecx, eax
    mov eax, [esi+88]
    cmp eax, 0x2000000
    jb .done
    mov [fb_addr], eax
    add ecx, eax
    jc .done
    mov [fb_end], ecx
.map:
    push eax
    call ahci_map             ; uncached identity mapping via allocator
    pop eax
    jc .done
    and eax, 0xffc00000
    add eax, 0x400000
    jc .done
    cmp eax, [fb_end]
    jb .map
    mov eax, [fb_width]
    sub eax, 960
    shr eax, 1
    mov [fb_left], eax
    mov eax, [fb_height]
    sub eax, 600
    shr eax, 1
    add eax, 10
    mov [fb_top], eax
    mov byte [fb_active], 1
    mov esi, fb_boot_msg
    ; debugcon only: do not emit through putc during initialization.
.log:
    lodsb
    test al, al
    jz .done
    out 0xe9, al
    jmp .log
.done:
    popad
    ret

; AX=character+VGA attribute, EBX=cell. Preserves GPRs and flags.
fb_cell:
    pushfd
    pushad
    cmp ebx, 2000
    jae .done
    cmp byte [fb_batch], 1
    je .done
    cmp byte [fb_active], 1
    je .graphics
    mov [0xb8000+ebx*2], ax
    jmp .done
.graphics:
    mov esi, [fb_cache]
    test esi, esi
    jz .paint
    cmp byte [fb_force], 1
    je .cache
    cmp [esi+ebx*2], ax
    je .done
.cache:
    mov [esi+ebx*2], ax
.paint:
    cmp ebx, 2000
    jae .done
    movzx edx, al
    shl edx, 4
    add edx, fb_font
    mov [fb_glyph], edx
    movzx edx, ah
    and edx, 15
    mov edx, [fb_palette+edx*4]
    mov [fb_fg], edx
    movzx edx, ah
    shr edx, 4
    and edx, 7
    mov edx, [fb_palette+edx*4]
    mov [fb_bg], edx
    mov byte [fb_under], 0
    cmp dword [history_offset], 0
    jne .position
    cmp byte [fb_cursor_draw], 1
    jne .position
    cmp ebx, [cursor]
    jne .position
    mov byte [fb_under], 1
.position:
    mov eax, ebx
    xor edx, edx
    mov ecx, 80
    div ecx
    imul eax, 24
    add eax, [fb_top]
    imul eax, [fb_pitch]
    imul edx, 12
    add edx, [fb_left]
    lea edi, [eax+edx*4]
    add edi, [fb_addr]
    xor ebp, ebp
.row:
    movzx eax, byte [fb_ymap+ebp]
    mov esi, [fb_glyph]
    movzx esi, byte [esi+eax]
    xor ebx, ebx
.pixel:
    movzx ecx, byte [fb_xmap+ebx]
    mov eax, 0x80
    shr eax, cl
    test esi, eax
    mov eax, [fb_bg]
    jz .background
    mov eax, [fb_fg]
.background:
    cmp byte [fb_under], 1
    jne .store
    cmp ebp, 22
    jb .store
    mov eax, 0x67e8f9
.store:
    mov [edi+ebx*4], eax
    inc ebx
    cmp ebx, 12
    jb .pixel
    add edi, [fb_pitch]
    inc ebp
    cmp ebp, 24
    jb .row
.done:
    popad
    popfd
    ret

fb_redraw:
    pushad
    xor ebx, ebx
.loop:
    mov esi, term_cells
    cmp dword [history_offset], 0
    je .source
    mov esi, [history_view]
.source:
    mov ax, [esi+ebx*2]
    call fb_cell
    inc ebx
    cmp ebx, 2000
    jb .loop
.done:
    popad
    ret

fb_clear:
    pushad
    cmp byte [fb_active], 1
    je .graphics
    call fb_redraw
    jmp .done
.graphics:
    ; Fill visible pixels; honor pitch rather than width*height contiguity.
    mov edi, [fb_addr]
    mov ebp, [fb_height]
    mov eax, 0x101010
.row:
    mov ecx, [fb_width]
    push edi
    rep stosd
    pop edi
    add edi, [fb_pitch]
    dec ebp
    jnz .row
    mov edi, [fb_cache]
    test edi, edi
    jz .redraw
    mov eax, 0xffffffff
    mov ecx, 1000
    rep stosd
.redraw:
    call fb_redraw
.done:
    popad
    ret

cmd_console:
    mov esi, fb_text_msg
    cmp byte [fb_active], 1
    jne .print
    mov esi, fb_info_msg
    call puts
    mov eax, [fb_width]
    call number
    mov al, 'x'
    call putc
    mov eax, [fb_height]
    call number
    mov esi, fb_info_tail
.print:
    jmp puts

fb_banner db 'CastiOS 0.11  /  TERMINAL                         FRAMEBUFFER  RGB32  /  80 x 25',0
fb_info_msg db 'Consola framebuffer: ',0
fb_info_tail db ' RGB32 | 80x25 celdas, fuente 12x24 | scroll y cursor software',10,0
fb_text_msg db 'Consola VGA texto: 80x25 (fallback)',10,0

fb_batch db 0
fb_force db 0
fb_cache dd 0
fb_active db 0
fb_under db 0
fb_cursor_draw db 0
fb_addr dd 0
fb_end dd 0
fb_width dd 0
fb_height dd 0
fb_pitch dd 0
fb_left dd 0
fb_top dd 0
fb_glyph dd 0
fb_fg dd 0
fb_bg dd 0
fb_old_cursor dd 0
fb_boot_msg db 'Framebuffer: RGB32 80x25 terminal activa',10,0
fb_xmap db 0,0,1,2,2,3,4,4,5,6,6,7
fb_ymap db 0,0,1,2,2,3,4,4,5,6,6,7,8,8,9,10,10,11,12,12,13,14,14,15
align 4
fb_palette dd 0x101010,0x729bff,0x80d9a4,0x67dbe8
 dd 0xf0788d,0xc4a1fa,0xf2c97d,0xd8e2f0
 dd 0x6b7b96,0x9bb7ff,0x98edba,0x8cecf8
 dd 0xffa2ac,0xdec4ff,0xffe0a0,0xf5f7ff
fb_font:
    incbin "src/console/font8x16.bin"

align 4
term_cells times 2000 dw 0x0720
