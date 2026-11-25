ext_init:
    pushad
    xor eax, eax
    cmp dword [nasm_size], 0
    je .init
    ; memory_modules verified the Multiboot RAM size before loading NASM.
    inc eax
.init:
    push eax
    push dword ext_api
    call [0x20010]
    add esp, 8
    popad
    ret
ext_route:
    push ebx
    push esi
    push edi
    push ebp
    push dword [args]
    push dword [cmdptr]
    call [0x20014]
    add esp, 8
    cmp eax, 2
    jne .done
    mov esi, 0x4000000
    mov edi, FS
    mov ecx, (512+NFILES*RSIZE)/4
    rep movsd
    call sync
    mov eax, 1
.done:
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret
ext_raw_read:
    pushad
    mov eax, [esp+36]
    cmp eax, 4
    jae .bad
    mov ebp, [disk_selected]
    call select_disk
    mov edi, [esp+44]
    mov eax, [esp+40]
    xor ebx, ebx
    call ata
    setc cl
    movzx ecx, cl
    push ecx
    mov eax, ebp
    call select_disk
    pop eax
    neg eax
    mov [esp+28], eax
    popad
    ret
.bad:
    mov dword [esp+28], -1
    popad
    ret
ext_raw_write:
    pushad
    mov eax, [esp+36]
    cmp eax, 4
    jae .bad
    mov ebp, [disk_selected]
    call select_disk
    mov edi, [esp+44]
    mov eax, [esp+40]
    mov ebx, 1
    call ata
    setc cl
    movzx ecx, cl
    push ecx
    mov eax, ebp
    call select_disk
    pop eax
    neg eax
    mov [esp+28], eax
    popad
    ret
.bad:
    mov dword [esp+28], -1
    popad
    ret
ext_raw_flush:
    call disk_flush
    mov eax, 0
    jnc .ok
    dec eax
.ok:
    ret
ext_free:
    mov eax, [esp+4]
    jmp free_page
ext_map:
    mov eax, [esp+4]
    call ahci_map
    mov eax, 0
    jnc .ok
    dec eax
.ok:
    ret
ext_repaint:
    call fb_clear
    jmp cursor_update
ext_api:
    dd nasm_console, ext_raw_read, disk_caps, alloc_page, ext_map
    dd ticks, fb_font, ext_repaint, fs_cwd, fb_active, ext_key, clear
    dd fb_addr, fb_pitch, fb_width, fb_height, ext_free, persistent
    dd ext_raw_write, ext_raw_flush, disk_selected, fs_base, 0
    dd ext_kbd_emit, mouse_gui, mouse_x, mouse_y, mt_count, mt_active
    dd mouse_click, mouse_event, mt_table, mouse_buttons
; Called from CPL0 C runtime; serialize with the IRQ1 producer.
ext_kbd_emit:
    pushfd
    cli
    pushad
    mov ebx, [kbd_head]
    lea edx, [ebx+1]
    and edx, 255
    cmp edx, [kbd_tail]
    je .full
    mov eax, [esp+40]
    mov [kbd_queue+ebx], al
    mov [kbd_head], edx
    jmp .done
.full:
    inc dword [kbd_dropped]
.done:
    popad
    popfd
    ret
ext_key:
    call getkey
    movzx eax, al
    ret
; Entries for help/autocomplete; routing happens before the legacy command table.
cmd_mount:
cmd_umount:
cmd_volumes:
cmd_usbscan:
cmd_usbinfo:
cmd_usbkbd:
cmd_font:
cmd_cp:
cmd_stat:
cmd_raminfo:
cmd_cpbig:
cmd_desktop:
    ret
