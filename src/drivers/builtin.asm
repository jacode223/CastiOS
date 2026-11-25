; Adaptadores de hardware existentes al registro comun.
DRIVER vga_driver, vga_name, text_class, 0, builtin_ok, 0, vga_write, 0
DRIVER pit_driver, pit_name, timer_class, 0, pit_init, pit_read, 0, 0
DRIVER ps2_driver, ps2_name, input_class, ps2_probe, ps2_init, ps2_read, 0, 0
DRIVER mouse_driver, mouse_name, input_class, ps2_probe, mouse_init, mouse_read, 0, 0
DRIVER ata_driver, ata_name, block_class, ata_probe, builtin_ok, ata_read_driver, ata_write_driver, 0
DRIVER rtc_driver, rtc_name, clock_class, rtc_probe, builtin_ok, rtc_read_driver, 0, 0
vga_name db 'vga',0
pit_name db 'pit',0
ps2_name db 'ps2',0
mouse_name db 'ps2mouse',0
ata_name db 'ata',0
rtc_name db 'rtc',0
text_class db 'text',0
timer_class db 'timer',0
input_class db 'input',0
block_class db 'block',0
clock_class db 'clock',0
builtin_ok:
    xor eax, eax
    ret
vga_write:
    mov edx, ecx
    mov esi, edi
.loop:
    jecxz .done
    lodsb
    call putc
    loop .loop
.done:
    xor eax, eax
    ret
pit_init:
    mov al, 0x36
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al
    xor eax, eax
    mov ecx, timer_tick
    call irq_register
    ret
pit_read:
    cmp ecx, 4
    jb builtin_invalid
    mov eax, [ticks]
    mov [edi], eax
    mov edx, 4
    xor eax, eax
    ret
rtc_probe:
    call rtc_snapshot
    jc builtin_absent
    xor eax, eax
    ret
rtc_read_driver:
    cmp ecx, 8
    jb builtin_invalid
    push edi
    call rtc_snapshot
    pop edi
    jc builtin_ioerror
    mov esi, rtc_data
    mov ecx, 8
    rep movsb
    mov edx, 8
    xor eax, eax
    ret
builtin_invalid:
    mov eax, EINVAL
    ret
builtin_absent:
    mov eax, ENODEV
    ret
builtin_ioerror:
    mov eax, EIO
    ret

ata_read_driver:
    cmp ecx, 512
    jne builtin_invalid
    cmp edx, FS_SECTORS-1
    ja builtin_invalid
    add edx, [fs_base]
    jc builtin_invalid
    add edx, [fs_io_bias]
    jc builtin_invalid
    cmp edx, [disk_sectors]
    jae builtin_invalid
    mov eax, edx
    xor ebx, ebx
    call ata
    jc builtin_ioerror
    mov edx, 512
    xor eax, eax
    ret
ata_write_driver:
    cmp byte [persistent], 1
    jne builtin_invalid
    cmp ecx, 512
    jne builtin_invalid
    cmp edx, FS_SECTORS-1
    ja builtin_invalid
    add edx, [fs_base]
    jc builtin_invalid
    add edx, [fs_io_bias]
    jc builtin_invalid
    cmp edx, [disk_sectors]
    jae builtin_invalid
    mov eax, edx
    mov bl, 1
    call ata
    jc builtin_ioerror
    mov edx, 512
    xor eax, eax
    ret
block_sector:
    pushad
    mov edx, eax
    mov ecx, 512
    test bl, bl
    mov ebx, ata_driver
    jnz .write
    call driver_read
    jmp .status
.write:
    call driver_write
.status:
    test eax, eax
    jnz .error
    popad
    clc
    ret
.error:
    popad
    stc
    ret
cmd_disks:
    call ata_controller_report
    xor ebp, ebp
.loop:
    mov esi, disk_name
    mov al, 'a'
    add eax, ebp
    mov [disk_name+2], al
    call puts
    mov eax, [disk_caps+ebp*4]
    call number
    mov esi, disk_sectors_text
    call puts
    movzx eax, byte [disk_states+ebp]
    mov esi, [disk_state_text+eax*4]
    call puts
    cmp byte [disk_backend+ebp], 2
    jne .not_via
    mov esi, disk_via_ro_text
    cmp byte [disk_flush_cap+ebp], 1
    jne .via_report
    mov esi, disk_via_rw_text
.via_report:
    call puts
    jmp .model
.not_via:
    cmp byte [disk_backend+ebp], 3
    jne .not_native
    mov esi, disk_native_text
    call puts
    jmp .model
.not_native:
    cmp byte [disk_backend+ebp], 1
    jne .model
    mov esi, disk_ahci_text
    call puts
.model:
    imul esi, ebp, 41
    add esi, disk_models
    call puts
    cmp ebp, [disk_selected]
    jne .nl
    mov esi, disk_active
    call puts
.nl:
    call nl
    inc ebp
    cmp ebp, 4
    jb .loop
    mov esi, disk_diag_text
    call puts
    movzx eax, byte [ata_last_status]
    call hex32
    mov al, '/'
    call putc
    movzx eax, byte [ata_last_error]
    call hex32
    mov esi, disk_errors_text
    call puts
    mov eax, [ata_errors]
    call number
    call nl
    ret
disk_name db 'hda ',0
disk_sectors_text db ' sectores | ',0
disk_active db ' [activo]',0
disk_diag_text db 'ATA status/error: ',0
disk_errors_text db ' fallos E/S: ',0

; Read-only controller inventory. Does not enable PCI I/O or change modes.
ata_controller_report:
    pushad
    mov esi, disk_controller_text
    call puts
    mov ebp, pci_devices
    mov ecx, [pci_count]
.loop:
    test ecx, ecx
    jz .done
    cmp dword [ebp+4], 0x32491106 ; VIA VT6421, PCI vendor/device
    jne .class
    mov esi, disk_via_text
    call puts
    mov eax, [ebp]
    call hex32
    mov esi, disk_via_bar_text
    call puts
    mov eax, [ebp]
    shl eax, 8
    or eax, 0x80000010
    call pci_config
    call hex32
    mov al, '/'
    call putc
    mov eax, [ebp]
    shl eax, 8
    or eax, 0x80000014
    call pci_config
    call hex32
    mov esi, disk_via_end
    call puts
    jmp .next
.class:
    cmp byte [ebp+11], 1       ; mass storage, including unfamiliar modes
    jne .next
    mov esi, disk_ide_text
    cmp byte [ebp+10], 1
    je .print
    mov esi, disk_ahci_text
    cmp word [ebp+9], 0x0601
    je .print
    mov esi, disk_nvme_text
    cmp byte [ebp+10], 8
    je .print
    mov esi, disk_other_text
    cmp byte [ebp+10], 4
    jne .print
    mov esi, disk_raid_text
.print:
    call puts
    mov eax, [ebp+4]            ; same ID and class format as castctl pci
    call hex32
    mov al, '/'
    call putc
    mov eax, [ebp+8]
    call hex32
    call nl
.next:
    add ebp, 12
    dec ecx
    jnz .loop
.done:
    call nl
    popad
    ret
disk_via_text db 'VIA VT6421 detectada BDF=',0
disk_via_bar_text db ' BAR0/BAR1=',0
disk_via_end db ' (sondeo SATA experimental) ',0
disk_via_ro_text db 'VIA VT6421 solo lectura (sin FLUSH) | ',0
disk_via_rw_text db 'VIA VT6421 escritura experimental | ',0
disk_controller_text db 'PCI almacenamiento: ',0
disk_ide_text db 'IDE PCI ',0
disk_native_text db 'IDE PCI nativo | ',0
disk_raid_text db 'RAID PCI ',0
disk_other_text db 'Controladora PCI ',0
disk_ahci_text db 'SATA/AHCI ',0
disk_nvme_text db 'NVMe (sin driver) ',0
