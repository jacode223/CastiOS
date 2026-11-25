; ATA PIO synchronous, legacy primary/secondary, 512-byte logical sectors.
; No BIOS services, DMA, AHCI or dynamic switching of the mounted volume.
%define ATA_LIMIT 0x10000000
%define ATA_POLLS 2000000

select_disk:
    ; Internal API: EAX=0..3, only boot/installer may select a volume.
    mov [disk_selected], eax
    mov edx, [disk_caps+eax*4]
    mov [disk_sectors], edx
    cmp byte [disk_backend+eax], 3
    jne .check_via
    mov dx, [native_base+eax*2]
    mov [ata_base], dx
    mov dx, [native_control+eax*2]
    mov [ata_control], dx
    mov dl, [native_unit+eax]
    mov [disk_bit], dl
    ret
.check_via:
    cmp byte [disk_backend+eax], 2
    jne .legacy
    mov dx, [via_slot_base+eax*2]
    mov [ata_base], dx
    add dx, 10
    mov [ata_control], dx
    mov byte [disk_bit], 0
    ret
.legacy:
    mov edx, eax
    shr edx, 1
    mov dx, [ata_bases+edx*2]
    mov [ata_base], dx
    mov edx, eax
    shr edx, 1
    mov dx, [ata_controls+edx*2]
    mov [ata_control], dx
    and eax, 1
    shl eax, 4
    mov [disk_bit], al
    ret

ata_delay:
    push edx
    mov dx, [ata_control]
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    pop edx
    ret

ata_select:
    ; AL=device/head; callers reload AL after this operation.
    mov dx, [ata_base]
    add dx, 6
    out dx, al
    mov dx, [ata_control]
    mov al, 2                 ; nIEN: this driver exclusively polls.
    out dx, al
    call ata_delay
    ret

; Common waits: preserve ECX/EDX. BSY makes ERR/DF/DRQ undefined.
ata_idle:
    push ebx
    xor ebx, ebx             ; only wait for BSY to clear; old ERR is allowed.
    jmp ata_wait
wait_ready:
    push ebx
    mov ebx, 1               ; command complete, DRQ must also clear.
    jmp ata_wait
ata_wait_drq:
    push ebx
    mov ebx, 2
ata_wait:
    push ecx
    push edx
    mov dx, [ata_base]
    add dx, 7
    mov ecx, ATA_POLLS
.loop:
    in al, dx
    mov [ata_last_status], al
    test al, al
    jz .fail
    cmp al, 0xff
    je .fail
    test al, 0x80
    jnz .again
    test ebx, ebx
    jz .ok
    test al, 0x21
    jnz .fail
    cmp ebx, 2
    je .drq
    test al, 8
    jz .ok
    jmp .again
.drq:
    test al, 8
    jnz .ok
.again:
    loop .loop
.fail:
    mov dx, [ata_base]
    inc dx
    in al, dx
    mov [ata_last_error], al
    pop edx
    pop ecx
    pop ebx
    stc
    ret
.ok:
    mov byte [ata_last_error], 0
    pop edx
    pop ecx
    pop ebx
    clc
    ret

ata_probe:
    mov eax, [disk_selected]
    mov [boot_disk_choice], eax
    xor ebp, ebp
.scan:
    mov dword [disk_caps+ebp*4], 0
    mov byte [disk_states+ebp], 0
    mov byte [disk_flush_cap+ebp], 0
    mov byte [disk_backend+ebp], 0
    mov eax, ebp
    call select_disk
    call ata_probe_one
    inc ebp
    cmp ebp, 4
    jb .scan
    call pci_ide_native_probe
    call via6421_probe
    call ahci_probe
    mov eax, [boot_disk_choice]
    cmp dword [disk_caps+eax*4], 0
    jne .selected
    xor eax, eax
.find:
    cmp dword [disk_caps+eax*4], 0
    jne .selected
    inc eax
    cmp eax, 4
    jb .find
    xor eax, eax
    call select_disk
    mov eax, ENODEV
    ret
.selected:
    call select_disk
    xor eax, eax
    ret

ata_probe_one:
    mov al, 0xa0
    or al, [disk_bit]
    call ata_select
    call ata_idle
    jc .initial_fail
    mov dx, [ata_base]
    add dx, 2
    xor al, al
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    inc dx
    mov al, 0xec
    out dx, al
    call ata_delay
    mov ecx, ATA_POLLS
.wait:
    in al, dx
    mov [ata_last_status], al
    test al, al
    jz .absent
    cmp al, 0xff
    je .absent
    test al, 0x80
    jnz .again
    ; Read signatures before ERR: IDENTIFY aborts normally on ATAPI.
    mov dx, [ata_base]
    add dx, 4
    in al, dx
    mov ah, al
    inc dx
    in al, dx
    cmp ax, 0x14eb
    je .atapi
    cmp ax, 0x6996
    je .atapi
    mov dx, [ata_base]
    add dx, 7
    in al, dx
    test al, 0x21
    jnz .ioerror
    test al, 8
    jnz .identify
.again:
    loop .wait
.timeout:
    mov byte [disk_states+ebp], 3
    ret
.initial_fail:
    mov al, [ata_last_status]
    test al, al
    jz .absent
    cmp al, 0xff
    jne .timeout
.absent:
    ret
.atapi:
    mov byte [disk_states+ebp], 2
    ret
.ioerror:
    mov byte [disk_states+ebp], 5
    ret
.identify:
    mov dx, [ata_base]
    mov edi, identify_buffer
    mov ecx, 256
    cld
    rep insw
    call ata_delay
    call wait_ready
    jc .ioerror
ata_parse_identify:
    ; Save a sanitized model even if the device is unsupported.
    imul edi, ebp, 41
    add edi, disk_models
    mov esi, identify_buffer+54
    mov ecx, 40
.model:
    ; Copy in forward order, swapping each ATA word.
    mov eax, 40
    sub eax, ecx
    xor eax, 1
    mov al, [esi+eax]
    cmp al, 32
    jb .sanitize
    cmp al, 126
    jbe .store
.sanitize:
    mov al, '?'
.store:
    stosb
    loop .model
    mov byte [edi], 0
    mov byte [disk_states+ebp], 4
    test word [identify_buffer+98], 0x200
    jz .return
    mov ax, [identify_buffer+212]
    and ax, 0xd000
    cmp ax, 0x5000
    jne .capacity
    cmp dword [identify_buffer+234], 256
    jne .return               ; 4Kn cannot be used by this block ABI.
.capacity:
    ; LBA48 metadata can report the real size even though commands stay LBA28.
    ; Large drives often saturate words 60/61 at 0x0fffffff.
    mov ax, [identify_buffer+166]
    and ax, 0xc400
    cmp ax, 0x4400
    jne .lba28
    cmp dword [identify_buffer+204], 0
    jne .full_window
    mov eax, [identify_buffer+200]
    jmp .check_capacity
.full_window:
    mov eax, ATA_LIMIT
    jmp .check_capacity
.lba28:
    mov eax, [identify_buffer+120]
.check_capacity:
    test eax, eax
    jz .return
    cmp eax, ATA_LIMIT
    jbe .save
    mov eax, ATA_LIMIT        ; usable LBA28 window, not total capacity.
.save:
    mov [disk_caps+ebp*4], eax
    mov byte [disk_states+ebp], 1
    mov ax, [identify_buffer+166]
    and ax, 0xd000
    cmp ax, 0x5000            ; valid word 83 and FLUSH CACHE supported.
    jne .return
    mov byte [disk_flush_cap+ebp], 1
.return:
    ret

; EAX=LBA physical (32-bit, LBA28 checked), EDI=512-byte buffer,
; BL=0 read / nonzero write. Preserves all GPRs; CF signals failure.
ata:
    push eax
    mov eax, [disk_selected]
    cmp byte [disk_backend+eax], 1
    pop eax
    je ahci_io
    pushad
    cld
    cmp eax, ATA_LIMIT
    jae .fail
    cmp eax, [disk_sectors]
    jae .fail
    test bl, bl
    jz .allowed
    push eax
    mov eax, [disk_selected]
    cmp byte [disk_flush_cap+eax], 1
    pop eax
    jne .fail
.allowed:
    mov [io_lba], eax
    mov [io_write], bl
    shr eax, 24
    and al, 15
    or al, 0xe0
    or al, [disk_bit]
    call ata_select
    call ata_idle
    jc .fail
    mov dx, [ata_base]
    add dx, 2
    mov al, 1
    out dx, al
    inc dx
    mov eax, [io_lba]
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    inc dx
    mov al, 0x20
    cmp byte [io_write], 0
    je .issue
    mov al, 0x30
.issue:
    out dx, al
    call ata_delay
    call ata_wait_drq
    jc .fail
    mov dx, [ata_base]
    mov ecx, 256
    cmp byte [io_write], 0
    jne .write
    rep insw
    jmp .end
.write:
    mov esi, edi
    rep outsw
.end:
    call ata_delay
    call wait_ready
    jc .fail
    popad
    clc
    ret
.fail:
    inc dword [ata_errors]
    popad
    stc
    ret

disk_flush:
    push eax
    mov eax, [disk_selected]
    cmp byte [disk_backend+eax], 1
    pop eax
    je ahci_flush
    pushad
    mov eax, [disk_selected]
    cmp byte [disk_flush_cap+eax], 1
    jne .fail                 ; never claim durability without supported flush.
    mov al, 0xe0
    or al, [disk_bit]
    call ata_select
    call ata_idle
    jc .fail
    mov dx, [ata_base]
    add dx, 7
    mov al, 0xe7
    out dx, al
    call ata_delay
    call wait_ready
    jc .fail
    popad
    clc
    ret
.fail:
    inc dword [ata_errors]
    popad
    stc
    ret

ata_bases dw 0x1f0, 0x170
ata_controls dw 0x3f6, 0x376
ata_base dw 0x1f0
ata_control dw 0x3f6
fs_base dd 0
fs_io_bias dd 0
via_slot_base times 4 dw 0
disk_selected dd 0
boot_disk_choice dd 0
disk_sectors dd 0
; Index 4 is private staging for a native-channel IDENTIFY.
disk_caps times 5 dd 0
disk_models times 5*41 db 0
disk_states times 5 db 0
disk_flush_cap times 5 db 0
disk_bit db 0
ata_last_status db 0
ata_last_error db 0
ata_errors dd 0
identify_buffer equ ATA_IDENTIFY_SCRATCH
disk_state_text dd disk_none, disk_ata, disk_atapi, disk_timeout, disk_unsupported, disk_ioerror
disk_none db 'ausente | ',0
disk_ata db 'ATA LBA28 | ',0
disk_atapi db 'ATAPI (sin lectura optica) | ',0
disk_timeout db 'timeout | ',0
disk_unsupported db 'ATA no compatible (LBA/sector) | ',0
disk_ioerror db 'error IDENTIFY | ',0

%include "src/drivers/ahci.asm"
%include "src/drivers/via6421.asm"
%include "src/drivers/pci_ide.asm"
