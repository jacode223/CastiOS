; PCI configuration mechanism 1. Solo lectura, bus 0..255, dev 0..31, fn 0..7.
DRIVER pci_driver, pci_name, pci_class, pci_probe, pci_init, pci_read, 0, 0
pci_name db 'pci',0
pci_class db 'bus',0
pci_count dd 0
pci_truncated db 0
pci_devices equ PCI_RECORDS
pci_via_bdf dd -1
pci_ahci_bdf dd -1
pci_config:
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in eax, dx
    ret
pci_probe:
    mov eax, 0x80000000
    call pci_config
    cmp ax, 0xffff
    je builtin_absent
    xor eax, eax
    ret
pci_init:
    xor ebp, ebp
    mov dword [pci_count], 0
    mov byte [pci_truncated], 0
    mov dword [pci_via_bdf], -1
    mov dword [pci_ahci_bdf], -1
.slot:
    mov ebx, ebp
    shl ebx, 8
    or ebx, 0x80000000
    mov eax, ebx
    call pci_config
    cmp ax, 0xffff
    je .next_slot
    mov eax, ebx
    or al, 0x0c
    call pci_config
    mov esi, ebp
    bt eax, 23                  ; multifunction bit of header type
    jnc .function
    add esi, 7
.function:
    mov ebx, ebp
    shl ebx, 8
    or ebx, 0x80000000
    mov eax, ebx
    call pci_config
    cmp ax, 0xffff
    je .next
    mov edi, eax
    cmp eax, 0x32491106
    jne .class
    cmp dword [pci_via_bdf], -1
    jne .class
    mov [pci_via_bdf], ebp
.class:
    mov eax, ebx
    or al, 8
    call pci_config
    mov edx, eax
    shr edx, 8
    cmp edx, 0x010601
    jne .record
    cmp dword [pci_ahci_bdf], -1
    jne .record
    mov [pci_ahci_bdf], ebp
.record:
    mov ecx, [pci_count]
    cmp ecx, 128
    jae .overflow
    imul ecx, 12
    mov [pci_devices+ecx], ebp
    mov [pci_devices+ecx+4], edi
    mov [pci_devices+ecx+8], eax
    inc dword [pci_count]
    jmp .next
.overflow:
    mov byte [pci_truncated], 1
.next:
    cmp ebp, esi
    je .next_slot
    inc ebp
    jmp .function
.next_slot:
    or ebp, 7
    inc ebp
    cmp ebp, 65536
    jb .slot
    xor eax, eax
    ret
pci_read:
    mov edx, [pci_count]
    imul edx, 12
    cmp ecx, edx
    jb builtin_invalid
    mov ecx, edx
    mov esi, pci_devices
    rep movsb
    xor eax, eax
    ret
cmd_pci:
    cmp dword [pci_driver+D_STATE], READY
    jne .absent
    mov esi, pci_devices
    mov ecx, [pci_count]
.print:
    jecxz .done
    mov eax, [esi]
    call hex32
    mov al, ' '
    call putc
    mov eax, [esi+4]
    call hex32
    mov al, ' '
    call putc
    mov eax, [esi+8]
    call hex32
    call nl
    add esi, 12
    loop .print
.done:
    ret
.absent:
    mov eax, ENODEV
    jmp driver_error
hex32:
    pushad
    mov ebx, eax
    mov ecx, 8
.digit:
    rol ebx, 4
    mov eax, ebx
    and eax, 15
    mov al, [hex_digits+eax]
    call putc
    loop .digit
    popad
    ret
hex_digits db '0123456789ABCDEF'
