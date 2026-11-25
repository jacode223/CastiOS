; Editor propio inspirado en nano. Buffer de texto de 8000 bytes.
cmd_nano:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call getslot
    jc full
    cmp byte [edi], 0
    je .new
    call require_text
    jc badname
    mov eax, [edi+RLEN]
    cmp eax, LIMIT
    ja toolong
    mov [nano_len], eax
    mov [slot], edi
    lea esi, [edi+RDATA]
    mov edi, EDITBUF
    mov ecx, eax
    rep movsb
    mov byte [edi], 0
    jmp .start
.new:
    mov [slot], edi
    mov dword [nano_len], 0
    mov byte [EDITBUF], 0
.start:
    mov dword [nano_pos], 0
    mov byte [nano_dirty], 0
    mov byte [nano_message], 0
    mov byte [editing], 1
.loop:
    call nano_render
    call getkey
    cmp al, 15
    je .save
    cmp al, 24
    je .exit
    cmp al, 27
    je .exit
    cmp al, 8
    je .back
    cmp al, 0x86
    je .delete
    cmp al, 0x82
    je .left
    cmp al, 0x83
    je .right
    cmp al, 0x80
    je .up
    cmp al, 0x81
    je .down
    cmp al, 0x84
    je .home
    cmp al, 0x85
    je .end
    cmp al, 13
    je .newline
    cmp al, 9
    je .tab
    cmp al, 32
    jb .loop
    cmp al, 126
    ja .loop
    call nano_insert
    jmp .loop
.newline:
    mov al, 10
    call nano_insert
    jmp .loop
.tab:
    mov al, ' '
    call nano_insert
    call nano_insert
    call nano_insert
    call nano_insert
    jmp .loop
.left:
    cmp dword [nano_pos], 0
    je .loop
    dec dword [nano_pos]
    jmp .loop
.right:
    mov eax, [nano_pos]
    cmp eax, [nano_len]
    jae .loop
    inc dword [nano_pos]
    jmp .loop
.home:
    mov ebx, [nano_pos]
.home_loop:
    test ebx, ebx
    jz .position
    cmp byte [EDITBUF+ebx-1], 10
    je .position
    dec ebx
    jmp .home_loop
.end:
    mov ebx, [nano_pos]
.end_loop:
    cmp ebx, [nano_len]
    jae .position
    cmp byte [EDITBUF+ebx], 10
    je .position
    inc ebx
    jmp .end_loop
.position:
    mov [nano_pos], ebx
    jmp .loop
.up:
    mov ebx, [nano_pos]
    mov ecx, 0
.up_start:
    test ebx, ebx
    jz .loop
    cmp byte [EDITBUF+ebx-1], 10
    je .previous
    dec ebx
    inc ecx
    jmp .up_start
.previous:
    dec ebx
    mov edx, ebx
.previous_start:
    test ebx, ebx
    jz .column
    cmp byte [EDITBUF+ebx-1], 10
    je .column
    dec ebx
    jmp .previous_start
.column:
    add ebx, ecx
    cmp ebx, edx
    jbe .position
    mov ebx, edx
    jmp .position
.down:
    mov ebx, [nano_pos]
    mov edx, ebx
.line_start:
    test edx, edx
    jz .current_col
    cmp byte [EDITBUF+edx-1], 10
    je .current_col
    dec edx
    jmp .line_start
.current_col:
    mov ecx, ebx
    sub ecx, edx
.next_start:
    cmp ebx, [nano_len]
    jae .loop
    cmp byte [EDITBUF+ebx], 10
    je .next_line
    inc ebx
    jmp .next_start
.next_line:
    inc ebx
.next_column:
    test ecx, ecx
    jz .position
    cmp ebx, [nano_len]
    jae .position
    cmp byte [EDITBUF+ebx], 10
    je .position
    inc ebx
    dec ecx
    jmp .next_column
.back:
    cmp dword [nano_pos], 0
    je .loop
    dec dword [nano_pos]
.delete:
    mov ebx, [nano_pos]
    cmp ebx, [nano_len]
    jae .loop
    lea esi, [EDITBUF+ebx+1]
    lea edi, [EDITBUF+ebx]
    mov ecx, [nano_len]
    sub ecx, ebx
    rep movsb
    dec dword [nano_len]
    mov byte [nano_dirty], 1
    jmp .loop
.save:
    mov edi, [slot]
    call init_slot
    mov eax, [nano_len]
    mov [edi+RLEN], eax
    add edi, RDATA
    mov esi, EDITBUF
    mov ecx, eax
    inc ecx
    rep movsb
    call sync
    mov byte [nano_dirty], 0
    mov byte [nano_message], 1
    jmp .loop
.exit:
    cmp byte [nano_dirty], 0
    je .close
    mov dword [cursor], 23*80
    mov esi, nano_exit_msg
    call puts
    call getkey
    cmp al, 'y'
    je .save_exit
    cmp al, 'Y'
    je .save_exit
    cmp al, 'n'
    je .close
    cmp al, 'N'
    jne .loop
    jmp .close
.save_exit:
    mov edi, [slot]
    call init_slot
    mov eax, [nano_len]
    mov [edi+RLEN], eax
    add edi, RDATA
    mov esi, EDITBUF
    mov ecx, eax
    inc ecx
    rep movsb
    call sync
.close:
    mov byte [editing], 0
    call clear
    mov esi, nano_closed
    jmp puts
nano_insert:
    pushad
    cmp dword [nano_len], LIMIT
    jae .full
    mov dl, al
    mov ecx, [nano_len]
    mov ebx, [nano_pos]
.shift:
    mov al, [EDITBUF+ecx]
    mov [EDITBUF+ecx+1], al
    cmp ecx, ebx
    je .store
    dec ecx
    jmp .shift
.store:
    mov [EDITBUF+ebx], dl
    inc dword [nano_pos]
    inc dword [nano_len]
    mov byte [nano_dirty], 1
    mov byte [nano_message], 0
    jmp .done
.full:
    mov byte [nano_message], 2
.done:
    popad
    ret
nano_render:
    pushad
    mov byte [fb_batch], 1
    call clear
    mov esi, nano_title
    call puts
    mov esi, namebuf
    call puts
    ; Primera pasada: fila y columna visual del cursor (wrap a 80).
    xor ebx, ebx
    xor edx, edx
    xor ecx, ecx
.measure:
    cmp ecx, [nano_pos]
    jae .measured
    mov al, [EDITBUF+ecx]
    inc ecx
    cmp al, 10
    je .new_row
    inc edx
    cmp edx, 80
    jb .measure
.new_row:
    inc ebx
    xor edx, edx
    jmp .measure
.measured:
    mov eax, ebx
    sub eax, 21
    jnc .top
    xor eax, eax
.top:
    mov [nano_top], eax
    sub ebx, eax
    inc ebx
    imul ebx, 80
    add ebx, edx
    mov [nano_screen_pos], ebx
    xor ebx, ebx
    xor edx, edx
    xor ecx, ecx
.draw:
    cmp ecx, [nano_len]
    jae .status
    mov al, [EDITBUF+ecx]
    inc ecx
    cmp al, 10
    je .draw_new
    cmp ebx, [nano_top]
    jb .advance
    push eax
    mov eax, ebx
    sub eax, [nano_top]
    cmp eax, 22
    jae .draw_stop
    inc eax
    imul eax, 80
    add eax, edx
    mov edi, eax
    pop eax
    mov ah, 7
    mov [term_cells+edi*2], ax
    push ebx
    mov ebx, edi
    call fb_cell
    pop ebx
    jmp .advance
.draw_stop:
    pop eax
    jmp .status
.advance:
    inc edx
    cmp edx, 80
    jb .draw
.draw_new:
    inc ebx
    xor edx, edx
    jmp .draw
.status:
    mov dword [cursor], 23*80
    mov esi, nano_status
    call puts
    mov eax, [nano_len]
    call number
    cmp byte [nano_dirty], 0
    je .message
    mov esi, nano_modified
    call puts
.message:
    cmp byte [nano_message], 0
    je .help
    mov esi, nano_saved
    cmp byte [nano_message], 1
    je .print_message
    mov esi, nano_limit
.print_message:
    call puts
.help:
    mov dword [cursor], 24*80
    mov esi, nano_help
    call puts
    mov eax, [nano_screen_pos]
    mov [cursor], eax
    mov byte [fb_batch], 0
    call fb_redraw
    call cursor_update
    popad
    ret
nano_len dd 0
nano_pos dd 0
nano_top dd 0
nano_screen_pos dd 0
nano_dirty db 0
nano_message db 0
nano_title db 'ASM nano | ',0
nano_status db 'Bytes: ',0
nano_modified db ' * Modificado',0
nano_saved db ' | Buffer guardado',0
nano_limit db ' | Limite de 8000 bytes',0
nano_help db '^O Guardar   ^X Salir   Flechas/Home/End Mover   Supr Borrar',0
nano_exit_msg db 'Guardar cambios? Y=guardar N=descartar Esc=volver',0
nano_closed db 'Editor cerrado.',10,0
