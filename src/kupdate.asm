; Internal A/B updater. Immutable stable boot file; candidate occupies the
; preallocated ISO extent. Layout is asserted by tools/grub_build.py.
%define KU_BUF 0x600000
%define KU_SECTOR 0x620000
%define KU_NEXT 440
%define KU_SLOT 696
%define KU_STABLE 708
; Live ISO update: copy only the embedded kernel into the existing A/B slot.
cmd_update_live:
    cmp dword [installer_size], 0
    je .refused
    mov esi, [args]
    cmp word [esi], 'hd'
    jne .usage
    cmp byte [esi+3], 0
    jne .usage
    movzx eax, byte [esi+2]
    sub eax, 'a'
    cmp eax, 3
    ja .usage
    cmp eax, [disk_selected]
    jne .refused
    cmp byte [persistent], 1
    jne .refused
    cmp dword [fs_base], 32768
    jne .refused
    cmp byte [disk_flush_cap+eax], 1
    jne .refused
    cmp dword [installer_size], (KU_STABLE+256)*512
    jb .refused
    call ku_check_slot
    jc .refused
    cmp byte [KU_SECTOR+32], 'C'
    je .refused ; do not overwrite a previously accepted candidate
    mov esi, 0x800000+KU_STABLE*512
    mov edi, KU_BUF
    mov ecx, 131072/4
    rep movsd
    mov eax, [KU_BUF+20]
    sub eax, 0x10000
    cmp eax, 64
    jb .refused
    cmp eax, 131072
    ja .refused
    mov [ku_length], eax
    jmp cmd_kapply.validate
.usage:
    mov esi, update_live_usage
    jmp puts
.refused:
    mov esi, update_live_refused
    jmp puts
update_live_usage db 'Uso: update hda|hdb|hdc|hdd (ISO Live)',10,0
update_live_refused db 'Update rechazado: requiere ISO Live y disco CastiOS montado compatible; usa kstatus para recuperar ranura.',10,0

cmd_kapply:
    call ku_ready
    jc .refused
    call filename
    jc .usage
    cmp byte [esi], 0
    jne .usage
    call findfile
    jc .usage
    mov eax, [edi+RLEN]
    cmp eax, 64
    jb .invalid
    cmp eax, 131072
    ja .invalid
    mov [ku_length], eax
    mov eax, [edi+RKIND]
    cmp eax, 3
    je .copy
    cmp eax, 5
    jne .invalid
.copy:
    mov [ku_record], edi
    mov edi, KU_BUF
    xor eax, eax
    mov ecx, 131072/4
    rep stosd
    mov edi, [ku_record]
    cmp dword [edi+RKIND], 5
    je .large
    mov edx, [ku_length]
    mov edi, KU_BUF
    mov esi, [ku_record]
.chain:
    mov ecx, edx
    cmp ecx, LIMIT
    jbe .chunk
    mov ecx, LIMIT
.chunk:
    sub edx, ecx
    push esi
    add esi, RDATA
    rep movsb
    pop esi
    test edx, edx
    jz .validate
    mov esi, [esi+44]
    dec esi
    shl esi, 13
    add esi, RECORDS
    jmp .chain
.large:
    mov eax, [edi+48]
    add eax, [fs_base]
    jc .invalid
    mov [ku_source_lba], eax
    mov eax, [ku_length]
    add eax, 511
    shr eax, 9
    mov [ku_sectors], eax
    mov edi, KU_BUF
.read_large:
    mov eax, [ku_source_lba]
    xor ebx, ebx
    call ata
    jc .io_error
    inc dword [ku_source_lba]
    add edi, 512
    dec dword [ku_sectors]
    jnz .read_large
.validate:
    cmp dword [KU_BUF], 0x1badb002
    jne .invalid
    mov eax, [KU_BUF]
    add eax, [KU_BUF+4]
    add eax, [KU_BUF+8]
    jnz .invalid
    mov eax, [KU_BUF+4]
    cmp eax, 0x10003
    je .flags
    cmp eax, 0x10007
    jne .invalid
.flags:
    cmp dword [KU_BUF+12], 0x10000
    jne .invalid
    cmp dword [KU_BUF+16], 0x10000
    jne .invalid
    mov eax, [ku_length]
    add eax, 0x10000
    cmp [KU_BUF+20], eax
    jne .invalid
    cmp [KU_BUF+24], eax
    jb .invalid
    cmp dword [KU_BUF+24], 0x30000
    ja .invalid
    mov eax, [KU_BUF+28]
    cmp eax, 0x10000
    jb .invalid
    cmp eax, [KU_BUF+20]
    jae .invalid
    call ku_check_slot
    jc .refused
    ; Point GRUB to the untouched stable slot before any candidate writes.
    mov al, '0'
    call ku_select
    jc .io_error
    mov dword [ku_sectors], 256
    mov dword [ku_target_lba], KU_NEXT
    mov esi, KU_BUF
.write:
    mov eax, [ku_target_lba]
    mov edi, esi
    mov bl, 1
    call ata
    jc .io_error
    add esi, 512
    inc dword [ku_target_lba]
    dec dword [ku_sectors]
    jnz .write
    call disk_flush
    jc .io_error
    mov dword [ku_sectors], 256
    mov dword [ku_target_lba], KU_NEXT
    mov esi, KU_BUF
.verify:
    mov eax, [ku_target_lba]
    mov edi, KU_SECTOR
    xor ebx, ebx
    call ata
    jc .io_error
    mov edi, KU_SECTOR
    mov ecx, 512
    repe cmpsb
    jne .io_error
    inc dword [ku_target_lba]
    dec dword [ku_sectors]
    jnz .verify
    mov al, '1'
    call ku_select
    jc .io_error
    mov esi, ku_installed
    jmp puts
.usage:
    mov esi, ku_usage
    jmp puts
.invalid:
    mov esi, ku_bad
    jmp puts
.refused:
    mov esi, ku_refused
    jmp puts
.io_error:
    mov esi, ku_io_error
    jmp puts
cmd_krollback:
    call ku_ready
    jc cmd_kapply.refused
    call ku_check_slot
    jc cmd_kapply.refused
    mov al, '0'
    call ku_select
    jc cmd_kapply.io_error
    mov esi, ku_rollback
    jmp puts
cmd_kstatus:
    call ku_ready
    jc cmd_kapply.refused
    call ku_check_slot
    jc cmd_kapply.refused
    mov esi, ku_stable
    cmp byte [KU_SECTOR+12], '1'
    jne .print
    mov esi, ku_next
.print:
    jmp puts
; One-shot trial: select the stable slot before reading the filesystem.
; A verified candidate can be kept with kaccept. Hangs before disk probe
; still require the GRUB stable menu entry.
; Run before mount: an unreadable HSFS must not leave the trial selected.
; BIOS/GRUB and disk initialization must have succeeded already.
ku_early_guard:
    cmp byte [ku_trial_boot], 1
    jne .done
    cmp dword [installer_size], 0
    jne .done
    mov eax, [disk_selected]
    add al, 0x80
    cmp al, [boot_bios]
    jne .done
    cmp dword [disk_sectors], 32768+8192+FS_SECTORS
    jb .done
    call ku_check_slot
    jc .warn
    cmp byte [KU_SECTOR+12], '1'
    jne .done
    ; Only an explicitly confirmed candidate may remain the default.
    cmp byte [KU_SECTOR+32], 'C'
    je .done
    mov al, '0'
    call ku_select
    jc .warn
    mov esi, ku_early_ok
    call puts
    ret
.warn:
    mov esi, ku_early_warn
    call puts
.done:
    ret
ku_boot_guard:
    call ku_ready
    jc .done
    call ku_check_slot
    jc .done
    cmp byte [KU_SECTOR+12], '1'
    jne .done
    cmp byte [KU_SECTOR+32], 'C'
    je .done
    mov al, '0'
    call ku_select
.done:
    ret
cmd_kaccept:
    cmp byte [ku_trial_boot], 1
    jne .not_trial
    call ku_ready
    jc cmd_kapply.refused
    call ku_check_slot
    jc cmd_kapply.refused
    cmp byte [KU_SECTOR+12], '0'
    jne .already
    ; Re-enable the verified trial slot and mark it confirmed.
    mov al, '1'
    call ku_select
    jc cmd_kapply.io_error
.already:
    mov eax, KU_SLOT
    mov edi, KU_SECTOR
    xor ebx, ebx
    call ata
    jc cmd_kapply.io_error
    mov byte [KU_SECTOR+32], 'C'
    mov bl, 1
    call ata
    jc cmd_kapply.io_error
    call disk_flush
    jc cmd_kapply.io_error
    mov esi, ku_accepted
    jmp puts
.not_trial:
    mov esi, ku_only_trial
    jmp puts
ku_ready:
    cmp byte [persistent], 1
    jne .no
    cmp dword [fs_base], 32768
    jne .no
    cmp dword [installer_size], 0
    jne .no
    mov eax, [disk_selected]
    add al, 0x80
    cmp al, [boot_bios]
    jne .no
    cmp dword [disk_sectors], 32768+8192+FS_SECTORS
    jb .no
    clc
    ret
.no:
    stc
    ret
ku_check_slot:
    mov eax, 64              ; ISO9660 primary volume descriptor
    mov edi, KU_SECTOR
    xor ebx, ebx
    call ata
    jc .bad
    cmp dword [KU_SECTOR], 0x30444301 ; type 1, 'CD0'
    jne .bad
    cmp word [KU_SECTOR+4], '01'
    jne .bad
    mov eax, KU_STABLE
    call ata
    jc .bad
    cmp dword [KU_SECTOR], 0x1badb002
    jne .bad
    mov eax, KU_SLOT
    call ata
    jc .bad
    cmp dword [KU_SECTOR], 'set '
    jne .bad
    cmp dword [KU_SECTOR+4], 'defa'
    jne .bad
    cmp dword [KU_SECTOR+16], 'CAST'
    jne .bad
    cmp byte [KU_SECTOR+12], '0'
    je .ok
    cmp byte [KU_SECTOR+12], '1'
    jne .bad
.ok:
    clc
    ret
.bad:
    stc
    ret
; AL contains the single-byte GRUB default. Read/modify/write one sector.
ku_select:
    mov [ku_desired], al
    mov eax, KU_SLOT
    mov edi, KU_SECTOR
    xor ebx, ebx
    call ata
    jc .fail
    cmp dword [KU_SECTOR], 'set '
    jne .fail
    cmp dword [KU_SECTOR+16], 'CAST'
    jne .fail
    mov al, [ku_desired]
    mov [KU_SECTOR+12], al
    mov byte [KU_SECTOR+32], 'R'
    cmp al, '1'
    jne .write
    mov byte [KU_SECTOR+32], 'P'
.write:
    mov eax, KU_SLOT
    mov bl, 1
    call ata
    jc .fail
    call disk_flush
    jc .fail
    mov eax, KU_SLOT
    xor ebx, ebx
    call ata
    jc .fail
    cmp dword [KU_SECTOR+16], 'CAST'
    jne .fail
    mov al, [ku_desired]
    cmp byte [KU_SECTOR+12], al
    jne .fail
    clc
    ret
.fail:
    stc
    ret
ku_length dd 0
ku_record dd 0
ku_source_lba dd 0
ku_target_lba dd 0
ku_sectors dd 0
ku_desired db 0
ku_trial_boot db 0
ku_usage db 'Uso: castctl kapply /kernel.img (HSFS del disco de arranque).',10,0
ku_bad db 'Kernel IMG incompatible: Multiboot, longitud o tipo.',10,0
ku_refused db 'Actualizacion rechazada: requiere HDD CastiOS compatible con HSFS persistente.',10,0
ku_io_error db 'Error de disco: arranque estable conservado; comprueba kstatus.',10,0
ku_installed db 'Kernel nuevo verificado y seleccionado. Reinicia con reboot. GRUB permite elegir Estable.',10,0
ku_rollback db 'Arranque estable seleccionado. Reinicia con reboot.',10,0
ku_stable db 'Arranque seleccionado: estable.',10,0
ku_next db 'Arranque seleccionado: kernel nuevo.',10,0
ku_accepted db 'Kernel nuevo confirmado para los siguientes arranques.',10,0
ku_only_trial db 'Confirma solo desde la sesion de prueba del kernel nuevo.',10,0
ku_early_ok db 'Recuperacion: siguiente arranque estable antes del montaje HSFS.',10,0
ku_early_warn db 'ATENCION: no se pudo asegurar el siguiente arranque estable. Usa GRUB Estable.',10,0
