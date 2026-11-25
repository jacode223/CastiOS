; 256 lines in pages allocated as history fills. The scroll view is lazy.
history_init:
    pushad
    cmp byte [fb_active], 1
    jne .done
    call alloc_page
    mov [fb_cache], eax
.done:
    popad
    ret
history_line:
    ; EAX ring index -> ESI address
    mov esi, eax
    shr esi, 4
    mov esi, [history_pages+esi*4]
    and eax, 15
    imul eax, 160
    add esi, eax
    ret
history_push:
    pushad
    cmp dword [history_capacity], 0
    jne .grow
    call alloc_page
    test eax, eax
    jz .done
    mov [history_pages], eax
    mov dword [history_capacity], 16
    jmp .copy
.grow:
    cmp byte [history_growth_blocked], 1
    je .copy
    mov eax, [history_count]
    cmp eax, [history_capacity]
    jne .copy
    cmp eax, 256
    jae .copy
    mov ebx, eax
    shr ebx, 4
    call alloc_page
    test eax, eax
    jz .block_growth
    mov [history_pages+ebx*4], eax
    mov eax, [history_capacity]
    mov [history_head], eax
    add dword [history_capacity], 16
.copy:
    mov eax, [history_head]
    call history_line
    mov edi, esi
    mov esi, term_cells
    mov ecx, 40
    rep movsd
    mov eax, [history_head]
    inc eax
    cmp eax, [history_capacity]
    jb .head
    xor eax, eax
.head:
    mov [history_head], eax
    mov eax, [history_count]
    cmp eax, [history_capacity]
    jae .done
    inc dword [history_count]
.done:
    popad
    ret
.block_growth:
    mov byte [history_growth_blocked], 1
    jmp .copy
history_bottom:
    pushfd
    pushad
    cmp dword [history_offset], 0
    je .done
    mov dword [history_offset], 0
    call fb_redraw
    call cursor_update
.done:
    popad
    popfd
    ret
history_up:
    pushad
    mov eax, [history_offset]
    add eax, 12
    cmp eax, [history_count]
    jbe .set
    mov eax, [history_count]
.set:
    mov [history_offset], eax
    call history_show
    popad
    ret
history_down:
    pushad
    mov eax, [history_offset]
    sub eax, 12
    jnc .set
    xor eax, eax
.set:
    mov [history_offset], eax
    call history_show
    popad
    ret
history_show:
    pushad
    cmp dword [history_offset], 0
    je .paint
    mov edi, [history_view]
    test edi, edi
    jnz .view
    call alloc_page
    mov [history_view], eax
    mov edi, eax
    test edi, edi
    jz .done
.view:
    mov ebp, [history_count]
    sub ebp, [history_offset]
    mov ebx, 25
.row:
    cmp ebp, [history_count]
    jae .live
    mov eax, [history_head]
    add eax, [history_capacity]
    sub eax, [history_count]
    add eax, ebp
    xor edx, edx
    div dword [history_capacity]
    mov eax, edx
    call history_line
    jmp .copy
.live:
    mov eax, ebp
    sub eax, [history_count]
    imul esi, eax, 160
    add esi, term_cells
.copy:
    mov ecx, 40
    rep movsd
    inc ebp
    dec ebx
    jnz .row
.paint:
    call fb_redraw
    mov byte [fb_force], 1
    mov ebx, [fb_old_cursor]
    mov esi, term_cells
    cmp dword [history_offset], 0
    je .cursor
    mov esi, [history_view]
.cursor:
    mov ax, [esi+ebx*2]
    call fb_cell
    mov byte [fb_force], 0
    call cursor_update
.done:
    popad
    ret
history_head dd 0
history_count dd 0
history_offset dd 0
history_capacity dd 0
history_growth_blocked db 0
history_view dd 0
history_pages times 16 dd 0
