; Live-only installer module at 0x70000. No installer code on installed disk.
cmd_install:
    cmp dword [installer_size], 0
    je .missing
    cmp dword [0x70000], 'CINS'
    jne .missing
    push dword [args]
    push dword install_api
    call [0x70004]
    add esp, 8
    call fb_clear
    jmp cursor_update
.missing:
    mov esi, install_live_msg
    jmp puts
; C ABI callbacks preserve callee-saved registers.
install_seed:
    pushad
    mov byte [persistent], 0
    mov dword [fs_base], 32768
    call fs_empty
    call fs_seed_docs
    call checksum
    mov [FS+16], eax
    popad
    ret
install_select:
    pushad
    mov eax, [esp+36]
    call select_disk
    popad
    ret
install_api:
    dd ext_api, installer_size, disk_flush_cap, disk_models
    dd install_seed, install_select
install_live_msg db 'Arranca la ISO Live para instalar GRUB.',10,0
align 4
installed_boot:
    incbin "build/hddboot.bin"
