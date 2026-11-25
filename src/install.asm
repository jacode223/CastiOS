; Formato rapido del disco indicado, con confirmacion visible.
cmd_install:
    mov esi, [args]
    cmp word [esi], 'hd'
    jne .usage
    cmp byte [esi+3], 0
    jne .usage
    movzx eax, byte [esi+2]
    sub eax, 'a'
    cmp eax, 3
    ja .usage
    mov [install_target], eax
    add al, 'a'
    mov [install_format_hda+9], al
.target:
    mov eax, [install_target]
    cmp dword [disk_caps+eax*4], 32768+8192+FS_SECTORS
    jb .refused
    cmp byte [disk_flush_cap+eax], 1
    jne .refused
    cmp dword [installer_size], 0
    je .live_required
    call cmd_disks
    mov esi, install_warning
    call puts
    mov esi, install_format_hda
.prompt:
    call puts
    call nl
    call readline
    mov edi, install_format_hda
.confirm:
    mov esi, LINE
    call equal
    jne .cancel
    mov eax, [install_target]
    call select_disk
    mov byte [persistent], 0
    cmp dword [installer_size], 0
    je .live_required
    ; Ajustar el fichero de configuracion ISO antes de copiar el instalador.
    mov esi, 0x800000
    mov ecx, [installer_size]
    sub ecx, 16
.config:
    cmp dword [esi], 'set '
    jne .next_config
    cmp dword [esi+4], 'asmd'
    jne .next_config
    cmp dword [esi+8], 'isk='
    jne .next_config
    mov eax, [install_target]
    add al, 'a'
.set_config:
    mov [esi+14], al
.next_config:
    inc esi
    loop .config
    mov dword [fs_base], 32768
    call fs_empty
    call fs_seed_docs
    call checksum
    mov [FS+16], eax
    mov eax, 0
    mov edi, 0x800000
    mov bl, 1
    mov ebp, [installer_size]
    add ebp, 511
    shr ebp, 9
.kernel:
    call ata
    jc .error
    add edi, 512
    inc eax
    cmp eax, ebp
    jb .kernel
    mov eax, 32768
    mov edi, FS
.fs:
    call ata
    jc .error
    inc eax
    add edi, 512
    cmp eax, 32768+FS_SECTORS
    jb .fs
    mov eax, 32768+8192
    mov edi, FS
.mirror:
    call ata
    jc .error
    inc eax
    add edi, 512
    cmp eax, 32768+8192+FS_SECTORS
    jb .mirror
    call disk_flush
    jc .error
    mov byte [persistent], 1
    mov esi, install_done
    jmp puts
.live_required:
    mov esi, install_live_msg
    jmp puts
.usage:
    mov esi, install_usage
    jmp puts
.refused:
    mov esi, install_refused
    jmp puts
.cancel:
    mov esi, install_cancelled
    jmp puts
.error:
    mov esi, install_error
    jmp puts
install_target dd 0
install_hda db 'hda',0
install_hdb db 'hdb',0
install_format_hda db 'FORMAT hda',0
install_format_hdb db 'FORMAT hdb',0
install_warning db 'ATENCION: se borrara el disco elegido, sus particiones y datos.',10,'Para confirmar escribe exactamente: ',0
install_usage db 'Uso: install hda|hdb|hdc|hdd. Consulta discos con disks.',10,0
install_done db 'Formateado e instalado. Retira la ISO y arranca desde ese disco.',10,0
install_refused db 'Instalacion rechazada: disco ausente, no compatible o pequeno.',10,0
install_cancelled db 'Instalacion cancelada. Discos sin cambios.',10,0
install_error db 'Error ATA durante instalacion: destino incompleto, datos en RAM.',10,0
align 4
installed_boot:
    incbin "build/hddboot.bin"

install_live_msg db "Arranca la ISO Live para instalar GRUB.",10,0
