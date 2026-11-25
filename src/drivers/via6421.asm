; VIA VT6421 PCI 1106:3249, experimental SATA PIO, read/write with FLUSH CACHE.
; Firmware must already enable I/O and SATA ports. No PCI writes or reset.
; BAR0/BAR1 are independent SATA taskfiles; control is BAR+0x0a.
; Existing ATA IDENTIFY and READ SECTORS routines bound retries and LBA28.
via6421_probe:
    pushad
    mov ebx, [pci_via_bdf]
    cmp ebx, -1
    je .done
    mov eax, ebx
    shl eax, 8
    or eax, 0x80000004
    call pci_config
    test eax, 1                  ; firmware-enabled PCI I/O decode
    jz .done
    mov dword [via_port], 0      ; SATA BAR number 0 or 1
.port:
    mov eax, ebx
    shl eax, 8
    or eax, 0x80000010
    mov edx, [via_port]
    lea eax, [eax+edx*4]
    call pci_config
    test eax, 1                  ; require an I/O BAR, not memory BAR
    jz .next_port
    and eax, 0xfffffffc
    cmp eax, 0x100
    jb .next_port
    cmp eax, 0xfff0
    ja .next_port
    test eax, 15                 ; VT6421 SATA BAR spans 16 ports
    jnz .next_port
    mov [via_probe_base], ax
    ; Do not alias a legacy ATA channel or overwrite a discovered disk.
    cmp ax, 0x1f0
    je .next_port
    cmp ax, 0x170
    je .next_port
    xor ebp, ebp
.slot:
    cmp dword [disk_caps+ebp*4], 0
    je .slot_found
    inc ebp
    cmp ebp, 4
    jb .slot
    jmp .done
.slot_found:
    mov ax, [via_probe_base]
    mov [ata_base], ax
    add ax, 10
    mov [ata_control], ax
    mov byte [disk_bit], 0
    call ata_probe_one
    cmp dword [disk_caps+ebp*4], 0
    je .next_port
    mov ax, [via_probe_base]
    mov [via_slot_base+ebp*2], ax
    mov byte [disk_backend+ebp], 2
.next_port:
    inc dword [via_port]
    cmp dword [via_port], 2
    jb .port
.done:
    popad
    ret
via_port dd 0
via_probe_base dw 0
