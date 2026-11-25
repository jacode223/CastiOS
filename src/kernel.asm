; CastiOS 0.36: bounded clean-room PE32 inspection for Win32 groundwork.
bits 16
org 0x10000
%include "src/drivers/abi.inc"
%define FS 0x200000
%define RECORDS FS+512
%define NFILES 480
%define RSIZE 8192
%define RDATA 64
%define RLEN 40
%define RPARENT 32
%define RKIND 36
%define ROOT_ID 0xffffffff
%define FS_SECTORS 7681
%define LIMIT 8000
%define LINE 0x40000
%define HISTORY 0x41000
%define EDITBUF 0x43000
%define IDT 0x45000
%define DRAFT 0x46000
; Scratch after the 4 KiB assembler output. Never stored in the kernel image.
%define VALIDATOR_MAPS 0x49000   ; two 504-byte bitmaps
%define PCI_RECORDS 0x49400      ; 128 BDF/ID/class entries of 12 bytes
%define ATA_IDENTIFY_SCRATCH 0x49a00 ; 512 bytes after PCI_RECORDS
%define BACKUP 0x50000
align 4
multiboot_header:
%ifdef TEXT_CONSOLE
    dd 0x1badb002, 0x10003, -(0x1badb002+0x10003)
%else
    dd 0x1badb002, 0x10007, -(0x1badb002+0x10007)
%endif
    dd multiboot_header, 0x10000, kernel_end, kernel_end, grub_entry
    dd 0, 1024, 768, 32
entry:
    cli
    mov ax, 0x1000
    mov ds, ax
    mov [boot_bios-$$], dl
    ; Memoria convencional antes de abandonar BIOS.
    int 0x12
    mov [mem_kib-$$], ax
    in al, 0x92
    and al, 0xfe
    or al, 2
    out 0x92, al
    lgdt [gdtr-$$]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword 8:protected
align 8
gdt:
    dq 0, 0x00cf9a000000ffff, 0x00cf92000000ffff
    dq 0x00cffa000000ffff, 0x00cff2000000ffff
    dq 0, 0 ; entry six: TLS for bundled NASM
gdtr:
    dw $-gdt-1
    dd gdt
bits 32
grub_entry:
    cli
    lgdt [gdtr]
    jmp 8:grub_segments
grub_segments:
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000
    mov [boot_info], ebx
    mov byte [boot_bios], 0x80
    test dword [ebx], 4
    jz .selected
    mov esi, [ebx+16]
.trial_scan:
    cmp byte [esi], 0
    je .disk_scan
    cmp dword [esi], 'tria'
    jne .trial_next
    cmp word [esi+4], 'l='
    jne .trial_next
    cmp byte [esi+6], '1'
    jne .trial_next
    mov byte [ku_trial_boot], 1
    jmp .disk_scan
.trial_next:
    inc esi
    jmp .trial_scan
.disk_scan:
    mov esi, [ebx+16]
.scan:
    cmp byte [esi], 0
    je .selected
    cmp word [esi], 0x6468
    jne .next
    mov al, [esi+2]
    sub al, 'a'
    cmp al, 3
    ja .selected
    add al, 0x80
    mov [boot_bios], al
    jmp .selected
.next:
    inc esi
    jmp .scan
.selected:
    jmp protected
protected:
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x90000
    cld
    ; Copia pristina para instalar, antes de modificar datos del kernel.
    mov esi, 0x10000
    mov edi, 0x60000
    mov ecx, 32768/4
    rep movsd
    ; Consume GRUB's map, modules and RGB fields while its low-memory
    ; structures are still valid. Later boot stages reuse that workspace.
    call memory_init
    call fb_init
    mov edi, 0x30000
    xor eax, eax
    mov ecx, (0x60000-0x30000)/4
    rep stosd
    ; IDT: parada explicita en excepciones; IRQ0 actualiza el reloj.
    mov edi, IDT
    mov ecx, 256
    mov eax, panic
.idt:
    mov word [edi], ax
    mov word [edi+2], 8
    mov word [edi+4], 0x8e00
    ror eax, 16
    mov word [edi+6], ax
    ror eax, 16
    add edi, 8
    loop .idt
    mov eax, process_int80
    mov word [IDT+128*8], ax
    mov word [IDT+128*8+4], 0xee00
    shr eax, 16
    mov word [IDT+128*8+6], ax
    mov eax, process_fault
    mov word [IDT+13*8], ax
    mov word [IDT+14*8], ax
    shr eax, 16
    mov word [IDT+13*8+6], ax
    mov word [IDT+14*8+6], ax
    mov eax, process_invalid
    mov word [IDT+6*8], ax
    mov word [IDT+0*8], ax   ; #DE: terminate faulty CPL3 task
    shr eax, 16
    mov word [IDT+6*8+6], ax
    mov word [IDT+0*8+6], ax
    mov esi, irq_stubs
    mov edi, IDT+32*8
    mov ecx, 16
.irqs:
    lodsd
    mov word [edi], ax
    shr eax, 16
    mov word [edi+6], ax
    add edi, 8
    loop .irqs
    lidt [idtr]
    ; PIC remapeado. Solo IRQ0 habilitada; PS/2 por lectura de puertos.
    mov al, 0x11
    out 0x20, al
    out 0xa0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xa1, al
    mov al, 4
    out 0x21, al
    mov al, 2
    out 0xa1, al
    mov al, 1
    out 0x21, al
    out 0xa1, al
    mov al, 0xff
    out 0x21, al
    mov al, 0xff
    out 0xa1, al
    call history_init
    call clear
    mov esi, title
    call puts
    movzx eax, byte [boot_bios]
    sub eax, 0x80
    cmp eax, 3
    jbe .disk_id
    xor eax, eax
.disk_id:
    mov [disk_selected], eax
    mov edi, 0x740000
    mov ecx, 8*512/4
    xor eax, eax
    rep stosd
    call drivers_boot
    call ku_early_guard
    sti
    call mount
    call ku_boot_guard
    call kconfig_load
    call ext_init
shell:
    mov al, [color]
    mov [attr], al
    mov esi, prompt
    call puts
    mov byte [attr], 7
    call readline
    cmp byte [LINE], 0
    je shell
    ; Historial cronologico, diez entradas, ultima se conserva completa.
    cmp dword [hist_count], 10
    jb .store
    mov esi, HISTORY+256
    mov edi, HISTORY
    mov ecx, 9*256
    rep movsb
    dec dword [hist_count]
.store:
    mov edi, [hist_count]
    shl edi, 8
    add edi, HISTORY
    mov esi, LINE
    call copy
    inc dword [hist_count]
    mov esi, LINE
    call spaces
    cmp byte [esi], 0
    je shell
    mov [cmdptr], esi
.split:
    mov al, [esi]
    test al, al
    jz .args
    cmp al, ' '
    je .cut
    cmp al, 'A'
    jb .next
    cmp al, 'Z'
    ja .next
    add byte [esi], 32
.next:
    inc esi
    jmp .split
.cut:
    mov byte [esi], 0
    inc esi
    call spaces
.args:
    mov [args], esi
    ; Only public Unix-style names may reach the extension router.
    mov ebx, commands
.public:
    mov esi, [cmdptr]
    mov edi, [ebx]
    test edi, edi
    jz .unknown
    call equal
    je .allowed
    add ebx, 12
    jmp .public
.allowed:
    call ext_route
    test eax, eax
    jnz shell
    mov ebx, commands
.find:
    mov esi, [cmdptr]
    mov edi, [ebx]
    test edi, edi
    jz .unknown
    call equal
    je .run
    add ebx, 12
    jmp .find
.run:
    call [ebx+4]
    jmp shell
.unknown:
    mov esi, unknown
    call puts
    jmp shell

timer_tick:
    inc dword [ticks]
    ret
panic:
    cli
    mov esi, panicmsg
    call puts
    jmp stop

; Consola VGA, cursor hardware y scroll. EAX/otros registros preservados.
putc:
    pushad
    call history_bottom
    out 0xe9, al
    mov ebx, [cursor]
    cmp al, 13
    je .done
    cmp al, 10
    je .newline
    mov ah, [attr]
    mov [term_cells+ebx*2], ax
    call fb_cell
    inc ebx
    jmp .bound
.newline:
    mov eax, ebx
    xor edx, edx
    mov ecx, 80
    div ecx
    inc eax
    imul ebx, eax, 80
.bound:
    cmp ebx, 2000
    jb .save
    call history_push
    mov esi, term_cells+160
    mov edi, term_cells
    mov ecx, 1920
    rep movsw
    mov ax, 0x0720
    mov ecx, 80
    rep stosw
    sub ebx, 80
    call fb_redraw
.save:
    mov [cursor], ebx
.done:
    call cursor_update
    popad
    ret
cursor_update:
    pushad
    cmp byte [fb_batch], 1
    je .end
    mov byte [fb_force], 1
    cmp dword [history_offset], 0
    jne .hidden
    cmp byte [fb_active], 1
    jne .vga
    mov byte [fb_cursor_draw], 0
    mov ebx, [fb_old_cursor]
    mov ax, [term_cells+ebx*2]
    call fb_cell
    mov ebx, [cursor]
    mov [fb_old_cursor], ebx
    cmp ebx, 2000
    jae .end
    mov ax, [term_cells+ebx*2]
    mov byte [fb_cursor_draw], 1
    call fb_cell
    mov byte [fb_cursor_draw], 0
.end:
    mov byte [fb_force], 0
    popad
    ret
.hidden:
    cmp byte [fb_active], 1
    je .end
    mov dx, 0x3d4
    mov al, 10
    out dx, al
    inc dx
    mov al, 0x20
    out dx, al
    jmp .end
.vga:
    mov dx, 0x3d4
    mov al, 10
    out dx, al
    inc dx
    mov al, 14
    out dx, al
    mov ebx, [cursor]
    mov dx, 0x3d4
    mov al, 14
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    dec dx
    mov al, 15
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    popad
    ret
puts:
    pushad
.loop:
    lodsb
    test al, al
    jz .done
    call putc
    jmp .loop
.done:
    popad
    ret
nl:
    push eax
    mov al, 10
    call putc
    pop eax
    ret
clear:
    pushad
    mov edi, term_cells
    mov eax, 0x07200720
    mov ecx, 1000
    rep stosd
    mov dword [cursor], 0
    cmp byte [fb_batch], 1
    je .no_paint
    call fb_clear
.no_paint:
    call cursor_update
    popad
    ret
erase:
    pushad
    cmp dword [cursor], 0
    je .done
    dec dword [cursor]
    mov ebx, [cursor]
    mov word [term_cells+ebx*2], 0x0720
    mov ax, 0x0720
    call fb_cell
    call cursor_update
.done:
    popad
    ret
copy:
    push eax
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    pop eax
    ret
length:
    push esi
    xor eax, eax
.loop:
    cmp byte [esi], 0
    je .done
    inc esi
    inc eax
    jmp .loop
.done:
    pop esi
    ret
equal:
    pushad
.loop:
    mov al, [esi]
    cmp al, [edi]
    jne .done
    test al, al
    jz .done
    inc esi
    inc edi
    jmp .loop
.done:
    popad
    ret
spaces:
    cmp byte [esi], ' '
    jne .done
    inc esi
    jmp spaces
.done:
    ret
number:
    pushad
    mov ebx, 10
    xor ecx, ecx
.loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .loop
.print:
    pop eax
    add al, '0'
    call putc
    loop .print
    popad
    ret

; PS/2 set 1: ASCII US, Shift, Caps Lock, extendidas arriba/abajo.
getkey:
.wait:
    call [0x2001c]              ; poll EHCI HID interrupt endpoint, if active
    cmp byte [mouse_gui], 1
    jne .keyboard
    cmp byte [mouse_click], 0
    je .movement
    mov byte [mouse_click], 0
    mov al, 0x89
    ret
.movement:
    cmp byte [mouse_event], 0
    je .keyboard
    mov byte [mouse_event], 0
    mov al, 0x8a
    ret
.keyboard:
    call ps2_pop
    cmp eax, 256
    jne .decode
    hlt
    jmp .wait
.decode:
    cmp al, 0xe0
    je .wait
    cmp al, 0x2a
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xaa
    je .shift_off
    cmp al, 0xb6
    je .shift_off
    cmp al, 0x1d
    je .ctrl_on
    cmp al, 0x9d
    je .ctrl_off
    cmp al, 0x3a
    je .caps
    test al, 0x80
    jnz .wait
    cmp al, 0x49
    je .pgup
    cmp al, 0x51
    je .pgdn
    cmp al, 0x48
    je .up
    cmp al, 0x50
    je .down
    cmp al, 0x4b
    je .left
    cmp al, 0x4d
    je .right
    cmp al, 0x47
    je .home
    cmp al, 0x4f
    je .end
    cmp al, 0x53
    je .delete
    movzx eax, al
    cmp eax, 128
    jae .wait
    mov al, [keymap+eax]
    cmp byte [shift], 0
    je .capital
    ; Cambiar al mapa Shift usando el scancode original.
    mov [last_ascii], al
    ; Convertimos caracteres con tabla paralela indexada por ASCII.
    movzx eax, al
    mov al, [shiftascii+eax]
.capital:
    cmp byte [caps], 0
    je .ctrl
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    ja .ctrl
    sub al, 32
    jmp .ctrl
.upper:
    cmp al, 'A'
    jb .ctrl
    cmp al, 'Z'
    ja .ctrl
    add al, 32
.ctrl:
    cmp byte [ctrl], 0
    je .return
    cmp al, 'a'
    jb .wait
    cmp al, 'z'
    ja .wait
    sub al, 'a'-1
.return:
    test al, al
    jz .wait
    ret
.shift_on:
    mov byte [shift], 1
    jmp .wait
.shift_off:
    mov byte [shift], 0
    jmp .wait
.ctrl_on:
    mov byte [ctrl], 1
    jmp .wait
.ctrl_off:
    mov byte [ctrl], 0
    jmp .wait
.caps:
    xor byte [caps], 1
    jmp .wait
.pgup:
    mov al, 0x87
    ret
.pgdn:
    mov al, 0x88
    ret
.up:
    mov al, 0x80
    ret
.down:
    mov al, 0x81
    ret
.left:
    mov al, 0x82
    ret
.right:
    mov al, 0x83
    ret
.home:
    mov al, 0x84
    ret
.end:
    mov al, 0x85
    ret
.delete:
    mov al, 0x86
    ret

readline:
    pushad
    xor ebx, ebx
    mov byte [LINE], 0
    mov eax, [hist_count]
    mov [hist_pos], eax
.key:
    call getkey
    cmp al, 0x87
    je .pageup
    cmp al, 0x88
    je .pagedown
    call history_bottom
    cmp al, 13
    je .enter
    cmp al, 8
    je .back
    cmp al, 27
    je .wipe
    cmp al, 21
    je .wipe
    cmp al, 9
    je .tab
    cmp al, 0x80
    je .up
    cmp al, 0x81
    je .down
    cmp al, 32
    jb .key
    cmp al, 126
    ja .key
    cmp ebx, 250
    jae .key
    mov [LINE+ebx], al
    inc ebx
    mov byte [LINE+ebx], 0
    call putc
    jmp .key
.pageup:
    cmp byte [editing], 1
    je .key
    call history_up
    jmp .key
.pagedown:
    cmp byte [editing], 1
    je .key
    call history_down
    jmp .key
.back:
    test ebx, ebx
    jz .key
    dec ebx
    mov byte [LINE+ebx], 0
    call erase
    jmp .key
.wipe:
    call .erase_all
    jmp .key
.erase_all:
    test ebx, ebx
    jz .erased
    dec ebx
    call erase
    jmp .erase_all
.erased:
    mov byte [LINE], 0
    ret
.up:
    cmp byte [editing], 1
    je .key
    cmp dword [hist_pos], 0
    je .key
    mov eax, [hist_pos]
    cmp eax, [hist_count]
    jne .older
    mov esi, LINE
    mov edi, DRAFT
    call copy
.older:
    dec dword [hist_pos]
    jmp .loadhist
.down:
    cmp byte [editing], 1
    je .key
    mov eax, [hist_pos]
    cmp eax, [hist_count]
    jae .key
    inc dword [hist_pos]
.loadhist:
    call .erase_all
    mov esi, [hist_pos]
    cmp esi, [hist_count]
    je .draft
    shl esi, 8
    add esi, HISTORY
    jmp .load
.draft:
    mov esi, DRAFT
.load:
    mov edi, LINE
    call copy
    mov esi, LINE
    call length
    mov ebx, eax
    call puts
    jmp .key
.tab:
    cmp byte [editing], 1
    je .key
    call complete
    jmp .key
.enter:
    call nl
    popad
    ret

; Completa una coincidencia unica. Prefijos ambiguos conservan la linea.
complete:
    pushad
    mov esi, LINE
    mov edx, esi
.token:
    lodsb
    test al, al
    jz .start
    cmp al, ' '
    jne .token
    mov edx, esi
    jmp .token
.start:
    mov [prefix], edx
    mov dword [matches], 0
    cmp edx, LINE
    jne .files
    mov ebp, commands
.cmd:
    mov edi, [ebp]
    test edi, edi
    jz .finish
    call candidate
    add ebp, 12
    jmp .cmd
.files:
    mov ebp, RECORDS
    mov ecx, NFILES
.file:
    mov edi, ebp
    cmp byte [edi], 0
    je .next
    mov eax, [fs_cwd]
    cmp [edi+RPARENT], eax
    jne .next
    call candidate
.next:
    add ebp, RSIZE
    loop .file
.finish:
    cmp dword [matches], 1
    jne .done
    mov esi, [match]
    mov edi, [prefix]
    mov eax, edi
    sub eax, LINE
    mov edx, eax
    push esi
    call length
    add eax, edx
    pop esi
    cmp eax, 250
    ja .done
    ; Borrar la linea y volver a dibujar la coincidencia completa.
    mov ecx, ebx
.erase:
    jecxz .copy
    call erase
    loop .erase
.copy:
    call copy
    mov esi, LINE
    call puts
.done:
    popad
    mov esi, LINE
    call length
    mov ebx, eax
    ret
candidate:
    pushad
    mov esi, [prefix]
    mov [candidate_ptr], edi
.cmp:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, [edi]
    jne .done
    inc esi
    inc edi
    jmp .cmp
.yes:
    inc dword [matches]
    mov eax, [candidate_ptr]
    mov [match], eax
.done:
    popad
    ret

%include "src/drivers/ata_pio.asm"
%include "src/console/history.asm"
%include "src/console/framebuffer.asm"
%include "src/fs.asm"
%include "src/nano.asm"
%include "src/assembler.asm"

cmd_help:
    mov esi, [args]
    mov ebx, commands
    cmp byte [esi], 0
    je .all
.search:
    mov edi, [ebx]
    test edi, edi
    jz .unknown
    call equal
    je .one
    add ebx, 12
    jmp .search
.one:
    mov esi, [ebx+8]
    call puts
    call nl
    ret
.all:
    mov esi, [ebx+8]
    test esi, esi
    jz .done
    call puts
    call nl
    add ebx, 12
    jmp .all
.unknown:
    mov esi, unknown
    call puts
.done:
    ret
cmd_echo:
    mov esi, [args]
    call puts
    jmp nl
cmd_version:
    mov esi, versionmsg
    jmp puts
cmd_whoami:
    mov esi, usermsg
    jmp puts
cmd_uptime:
    mov eax, [ticks]
    xor edx, edx
    mov ecx, 100
    div ecx
    call number
    mov esi, secondsmsg
    jmp puts
old_cmd_mem:
    movzx eax, word [mem_kib]
    call number
    mov esi, memmsg
    jmp puts
cmd_fsinfo:
    cmp byte [persistent], 1
    jne .ram
    mov esi, fs_mounted
    jmp puts
.ram:
    mov esi, fs_ram
    jmp puts
; RTC CMOS: muestra estable, BCD/binario y modos de 12/24 horas.
cmos:
    out 0x70, al
    in al, 0x71
    ret
rtc_snapshot:
    mov ecx, 100000
.retry:
    mov al, 0x0a
    call cmos
    test al, 0x80
    jnz .again
    xor edi, edi
.read:
    mov al, [rtc_indices+edi]
    call cmos
    mov [rtc_data+edi], al
    inc edi
    cmp edi, 8
    jb .read
    mov al, 0x0a
    call cmos
    test al, 0x80
    jnz .again
    xor eax, eax
    call cmos
    cmp al, [rtc_data]
    jne .again
    clc
    ret
.again:
    loop .retry
    stc
    ret
rtc_value:
    and eax, 255
    test byte [rtc_data+7], 4
    jnz .done
    mov ah, al
    and al, 15
    shr ah, 4
    movzx edx, ah
    movzx eax, al
    imul edx, 10
    add eax, edx
.done:
    ret
pair:
    pushad
    xor edx, edx
    mov ebx, 10
    div ebx
    add al, '0'
    call putc
    mov al, dl
    add al, '0'
    call putc
    popad
    ret
cmd_time:
    call rtc_snapshot
    jc rtc_fail
    movzx eax, byte [rtc_data+2]
    mov ebx, eax
    and eax, 127
    call rtc_value
    test byte [rtc_data+7], 2
    jnz .hour
    cmp eax, 12
    jne .pm
    xor eax, eax
.pm:
    test ebx, 128
    jz .hour
    add eax, 12
.hour:
    call pair
    mov al, ':'
    call putc
    movzx eax, byte [rtc_data+1]
    call rtc_value
    call pair
    mov al, ':'
    call putc
    movzx eax, byte [rtc_data]
    call rtc_value
    call pair
    jmp nl
cmd_date:
    call rtc_snapshot
    jc rtc_fail
    movzx eax, byte [rtc_data+6]
    call rtc_value
    cmp eax, 19
    jb .century
    cmp eax, 99
    jbe .year
.century:
    mov eax, 20
.year:
    call pair
    movzx eax, byte [rtc_data+5]
    call rtc_value
    call pair
    mov al, '-'
    call putc
    movzx eax, byte [rtc_data+4]
    call rtc_value
    call pair
    mov al, '-'
    call putc
    movzx eax, byte [rtc_data+3]
    call rtc_value
    call pair
    jmp nl
rtc_fail:
    mov esi, rtc_error
    jmp puts
cmd_color:
    mov esi, [args]
    mov edi, greenword
    call equal
    je .green
    mov edi, cyanword
    call equal
    je .cyan
    mov edi, whiteword
    call equal
    je .white
    mov esi, colormsg
    jmp puts
.green:
    mov byte [color], 10
    ret
.cyan:
    mov byte [color], 11
    ret
.white:
    mov byte [color], 15
    ret
cmd_reboot:
    cli
    mov ecx, 1000000
.wait:
    in al, 0x64
    test al, 2
    jz .reset
    loop .wait
.reset:
    mov al, 0xfe
    out 0x64, al
    lidt [null_idtr]
    int 3
cmd_halt:
    mov esi, haltmsg
    call puts
    cli
stop:
    hlt
    jmp stop

; Tabla escrita manualmente abajo para conservar binario plano compacto.
%macro CMD 2
    dd n_%1, cmd_%1, d_%1
%endmacro
commands:
    dd n_help, cmd_help, d_help
    dd n_clear, clear, d_clear
    dd n_echo, cmd_echo, d_echo
    dd n_uname, cmd_version, d_uname
    dd n_whoami, cmd_whoami, d_whoami
    dd n_uptime, cmd_uptime, d_uptime
    dd n_date, cmd_date, d_date
    dd n_ls, cmd_ls, d_ls
    dd n_cat, cmd_cat, d_cat
    dd n_head, cmd_head, d_head
    dd n_rm, cmd_rm, d_rm
    dd n_mkdir, cmd_mkdir, d_mkdir
    dd n_cd, cmd_cd, d_cd
    dd n_pwd, cmd_pwd, d_pwd
    dd n_touch, cmd_touch, d_touch
    dd n_nano, cmd_nano, d_nano
    dd n_cp, cmd_cp, d_cp
    dd n_mv, cmd_mv, d_mv
    dd n_stat, cmd_stat, d_stat
    dd n_chmod, cmd_chmod, d_chmod
    dd n_disks, cmd_disks, d_disks
    dd n_install, cmd_install, d_install
    dd n_mount, cmd_mount, d_mount
    dd n_umount, cmd_umount, d_umount
    dd n_sync, sync, d_sync
    dd n_reboot, cmd_reboot, d_reboot
    dd n_halt, cmd_halt, d_halt
    dd n_ps, cmd_ps, d_ps
    dd n_desktop, cmd_desktop, d_desktop
    dd n_mousestat, cmd_mousestat, d_mousestat
    dd n_kill, cmd_kill, d_kill
    dd n_wait, cmd_waitbg, d_wait
    dd n_exec, cmd_run, d_exec
    dd n_execall, cmd_run2, d_execall
    dd n_bg, cmd_bg, d_bg
    dd n_nasm, cmd_nasm, d_nasm
    dd n_castic, cmd_castic, d_castic
    dd n_update, cmd_update_live, d_update
    dd n_castctl, cmd_castctl, d_castctl
    dd 0,0,0
admin_commands:
    CMD dir, 0
    CMD type, 0
    CMD copy, 0
    CMD ver, 0
    CMD help, 0
    CMD clear, 0
    CMD echo, 0
    CMD version, 0
    CMD whoami, 0
    CMD uptime, 0
    CMD mem, 0
    CMD time, 0
    CMD date, 0
    CMD ls, 0
    CMD cat, 0
    CMD write, 0
    CMD append, 0
    CMD head, 0
    CMD edit, 0
    CMD rm, 0
    CMD color, 0
    CMD fsinfo, 0
    CMD sync, 0
    CMD reboot, 0
    CMD halt, 0
    CMD drivers, 0
    CMD drvinfo, 0
    CMD drvread, 0
    CMD drvwrite, 0
    CMD drvtest, 0
    CMD install, 0
    CMD pci, 0
    CMD disks, 0
    CMD console, 0
    CMD mount, 0
    CMD umount, 0
    CMD volumes, 0
    CMD usbscan, 0
    CMD usbinfo, 0
    CMD usbkbd, 0
    CMD font, 0
    CMD cp, 0
    CMD stat, 0
    CMD raminfo, 0
    CMD cpbig, 0

    CMD nano, 0
    CMD mkdir, 0
    CMD cd, 0
    CMD pwd, 0
    CMD touch, 0
    CMD asm, 0
    CMD nasm, 0
    CMD run, 0
    CMD run2, 0
    CMD bg, 0
    CMD ps, 0
    CMD waitbg, 0
    CMD kbdstat, 0
    CMD kset, 0
    CMD kshow, 0
    CMD kreload, 0
    CMD kbuild, 0
    CMD kapply, 0
    CMD krollback, 0
    CMD kstatus, 0
    CMD kaccept, 0
    CMD memtest, 0
    CMD drvnew, 0
    CMD drvload, 0
    CMD drvunload, 0
    dd n_about, cmd_version, d_version
    dd n_cls, clear, d_clear
    dd n_theme, cmd_color, d_color
    dd 0,0,0
cmd_clear equ clear
cmd_sync equ sync
%macro DESC 3
n_%1 db %2,0
d_%1 db %3,0
%endmacro
DESC help, 'help', 'help [comando] - ayuda general o especifica'
DESC clear, 'clear', 'clear - limpiar pantalla'
DESC echo, 'echo', 'echo TEXTO - mostrar texto'
DESC version, 'version', 'version - CastiOS 0.36, kernel de 32 bits'
DESC whoami, 'whoami', 'whoami - identidad de la sesion'
DESC uptime, 'uptime', 'uptime - segundos desde el arranque (PIT 100 Hz)'
DESC mem, 'mem', 'mem - memoria convencional informada por BIOS'
DESC time, 'time', 'time - hora RTC CMOS'
DESC date, 'date', 'date - fecha RTC CMOS'
DESC cpbig, 'cpbig', 'cpbig ORIGEN DESTINO - copiar archivo grande'
DESC raminfo, 'raminfo', 'raminfo - estado de RMFS'
DESC peinfo, 'peinfo', 'castctl peinfo RUTA.exe - inspeccionar PE32 x86'
DESC ls, 'ls', 'ls [RUTA] - listar archivos'
DESC cat, 'cat', 'cat NOMBRE - mostrar archivo completo'
DESC write, 'write', 'write NOMBRE [TEXTO] - crear o reemplazar'
DESC append, 'append', 'append NOMBRE TEXTO - agregar una linea'
DESC head, 'head', 'head NOMBRE - primeras cinco lineas'
DESC edit, 'edit', 'edit RUTA - alias del editor nano'
DESC rm, 'rm', 'rm NOMBRE - eliminar archivo'
DESC color, 'color', 'color / theme cyan|green|white - color del prompt'
DESC fsinfo, 'fsinfo', 'fsinfo - estado de HSFS5'
DESC sync, 'sync', 'sync - guardar HSFS5 en el disco reconocido'
DESC reboot, 'reboot', 'reboot - reiniciar'
DESC halt, 'halt', 'halt - detener CPU'
DESC drivers, 'drivers', 'drivers - listar drivers registrados y su estado'
DESC drvinfo, 'drvinfo', 'drvinfo NOMBRE - datos del driver'
DESC drvread, 'drvread', 'drvread NOMBRE - leer driver'
DESC drvwrite, 'drvwrite', 'drvwrite NOMBRE TEXTO - escribir driver'
DESC drvtest, 'drvtest', 'drvtest - probar drivers'
DESC install, 'install', 'install DISCO - instalar CastiOS'
DESC nano, 'nano', 'nano RUTA - editor (Ctrl-O, Ctrl-X)'
DESC mkdir, 'mkdir', 'mkdir RUTA - crear carpeta'
DESC cd, 'cd', 'cd RUTA - cambiar carpeta (/, ., ..)'
DESC pwd, 'pwd', 'pwd - carpeta actual'
DESC touch, 'touch', 'touch RUTA - crear archivo vacio si no existe'
DESC asm, 'asm', 'asm FUENTE SALIDA - ensamblar AX05 con int 0x80'
DESC castic, 'castic', 'castic FUENTE SALIDA - compilar Castic a AX05'
DESC nasm, 'nasm', 'nasm -f bin FUENTE -o SALIDA | nasm -v (200 MiB RAM)'
DESC run, 'run', 'run ARCHIVO - ejecutar binario AX05 validado'
DESC run2, 'run2', 'run2 A B [C D] - ejecutar 2-4 AX05'
DESC bg, 'bg', 'bg APP - iniciar tarea de fondo'
DESC ps, 'ps', 'ps - estado de procesos en segundo plano'
DESC desktop, 'desktop', 'desktop - escritorio grafico con ventanas'
DESC mousestat, 'mousestat', 'mousestat - posicion y botones del mouse PS/2'
DESC kill, 'kill', 'kill PID - detener tarea AX05 de fondo'
DESC waitbg, 'waitbg', 'wait [PID] - esperar tareas AX05'
DESC drvnew, 'drvnew', 'drvnew RUTA - crear driver'
DESC drvload, 'drvload', 'drvload RUTA - cargar driver virtual'
DESC drvunload, 'drvunload', 'drvunload NOMBRE - retirar driver virtual'
DESC memtest, 'memtest', 'memtest - probar memoria'
DESC kbdstat, 'kbdstat', 'kbdstat - teclas descartadas'
DESC kset, 'kset', 'kset - cambiar color o prompt'
DESC kbuild, 'kbuild', 'kbuild - generar kernel.img'
DESC update, 'update', 'update hda|hdb|hdc|hdd - actualizar desde ISO Live'
DESC kapply, 'kapply', 'kapply RUTA.img - instalar kernel A/B'
DESC krollback, 'krollback', 'krollback - volver al kernel estable'
DESC kstatus, 'kstatus', 'kstatus - mostrar kernel elegido para arrancar'
DESC kaccept, 'kaccept', 'kaccept - confirmar kernel nuevo'
DESC kshow, 'kshow', 'kshow - mostrar configuracion del sistema'
DESC kreload, 'kreload', 'kreload - recargar /system.cfg'
DESC mount, 'mount', 'mount DISCO RUTA - FAT32 solo lectura'
DESC umount, 'umount', 'umount /mnt/NOMBRE - desmontar'
DESC volumes, 'volumes', 'volumes - discos y particiones MBR/GPT'
DESC usbscan, 'usbscan', 'usbscan - detectar USB EHCI/UHCI/xHCI'
DESC usbinfo, 'usbinfo', 'usbinfo - informacion de discos USB'
DESC usbkbd, 'usbkbd', 'usbkbd - estado del teclado USB HID EHCI'
DESC font, 'font', 'font RUTA.ttf | font default - fuente terminal'
DESC cp, 'cp', 'cp ORIGEN DESTINO - copiar archivo; FAT32 solo lectura'
DESC mv, 'mv', 'mv ORIGEN DESTINO - mover/renombrar archivo HSFS'
DESC stat, 'stat', 'stat /mnt/ARCHIVO - informacion FAT32'
DESC chmod, 'chmod', 'chmod APP [+w|-w] - permiso AX05'
DESC dir, 'dir', 'dir - listar archivos (alias de ls)'
DESC type, 'type', 'type RUTA - leer texto (alias de cat)'
DESC copy, 'copy', 'copy ORIGEN DESTINO - importar FAT32 a ASFS'
DESC ver, 'ver', 'ver - version'
DESC console, 'console', 'console - datos de pantalla'
DESC disks, 'disks', 'disks - hda..hdd: deteccion, modelo y capacidad'
DESC pci, 'pci', 'pci - listar dispositivos PCI'
DESC uname, 'uname', 'uname - version y arquitectura de CastiOS'
DESC wait, 'wait', 'wait [PID] - esperar tareas de fondo'
DESC exec, 'exec', 'exec ARCHIVO.app - ejecutar AX05 en primer plano'
DESC execall, 'execall', 'execall A B [C D] - ejecutar tareas'
DESC castctl, 'castctl', 'castctl SUBCOMANDO - funciones internas'
castctl_help db 'castctl: write append fsinfo raminfo mem time color console disks pci volumes usbscan usbinfo usbkbd font cpbig peinfo wmtheme',10
             db '         drivers drvinfo drvread drvwrite drvtest drvnew drvload drvunload install memtest kbdstat asm',10
             db '         kset kshow kreload: /system.cfg | kbuild kapply kstatus krollback: kernel A/B',10,0
n_about db 'about',0
n_cls db 'cls',0
n_theme db 'theme',0
title db 'CastiOS 0.36',10,'HELP: comandos | PgUp/PgDn: scroll',10,0
prompt db 'CastiOS> ',0
       times 32-($-prompt) db 0
versionmsg db 'CastiOS 0.36 | x86 | CPL3 | HSFS5 | USB HID',10,0
usermsg db 'root (sesion unica; sin autenticacion)',10,0
secondsmsg db ' segundos',10,0
memmsg db ' KiB convencionales (no representa toda la RAM)',10,0
unknown db 'Comando desconocido. Usa help.',10,0
mounted db 'ASFS v1: disco persistente, 32 archivos, 1000 bytes por archivo.',10,0
rammsg db 'ASFS en RAM: disco ausente, incompatible o corrupto. Sin persistencia.',10,0
saved db 'Guardado en disco ASFS.',10,0
ramsaved db 'Guardado solo en RAM.',10,0
ioerror db 'Error ATA: datos en RAM; persistencia deshabilitada.',10,0
badnamemsg db 'Nombre invalido: 1-15 letras, cifras, . _ -; sin argumentos extra.',10,0
missingmsg db 'El archivo no existe.',10,0
fullmsg db 'ASFS lleno: 32 archivos como maximo.',10,0
longmsg db 'Texto demasiado largo: maximo 1000 bytes. Sin cambios.',10,0
editmsg db 'Editor: escribe el reemplazo. .save guarda; .cancel cancela.',10,0
editprompt db 'edit> ',0
saveword db '.save',0
cancelword db '.cancel',0
cancelled db 'Edicion cancelada.',10,0
greenword db 'green',0
cyanword db 'cyan',0
whiteword db 'white',0
colormsg db 'Uso: color cyan|green|white',10,0
haltmsg db 'CPU detenida.',10,0
panicmsg db 10,'PANIC: excepcion del procesador. CPU detenida.',10,0
rtc_error db 'RTC no disponible.',10,0
rtc_indices db 0,2,4,7,8,9,0x32,0x0b
rtc_data times 8 db 0
idtr dw 2047
    dd IDT
null_idtr dw 0
    dd 0
mem_kib dw 0
cursor dd 0
ticks dd 0
hist_count dd 0
hist_pos dd 0
cmdptr dd 0
args dd 0
textptr dd 0
slot dd 0
prefix dd 0
matches dd 0
match dd 0
candidate_ptr dd 0
editlen dd 0
io_lba dd 0
io_write db 0
persistent db 0
attr db 7
color db 11
shift db 0
ctrl db 0
caps db 0
last_ascii db 0
editing db 0
boot_bios db 0
namebuf times 32 db 0
; Scancodes set 1, hasta 127.
keymap:
    db 0,27,'1234567890-=',8,9,'qwertyuiop[]',13,0,'asdfghjkl;',39,96,0,92,'zxcvbnm,./',0,'*',0,' '
    times 128-($-keymap) db 0
; ASCII transformado con Shift. Se genera en ensamblado, no en ejecucion.
shiftascii:
%assign i 0
%rep 128
%if i >= 'a' && i <= 'z'
    db i-32
%elif i = '1'
    db '!'
%elif i = '2'
    db '@'
%elif i = '3'
    db '#'
%elif i = '4'
    db '$'
%elif i = '5'
    db '%'
%elif i = '6'
    db '^'
%elif i = '7'
    db '&'
%elif i = '8'
    db '*'
%elif i = '9'
    db '('
%elif i = '0'
    db ')'
%elif i = '-'
    db '_'
%elif i = '='
    db '+'
%elif i = '['
    db '{'
%elif i = ']'
    db '}'
%elif i = ';'
    db ':'
%elif i = 39
    db 34
%elif i = 96
    db '~'
%elif i = 92
    db '|'
%elif i = ','
    db '<'
%elif i = '.'
    db '>'
%elif i = '/'
    db '?'
%else
    db i
%endif
%assign i i+1
%endrep
%include "src/drivers/manager.asm"
%include "src/drivers/builtin.asm"
%include "src/drivers/keyboard.asm"
%include "src/drivers/mouse.asm"
%include "src/drivers/loopback.asm"
%include "src/drivers/serial.asm"
%include "src/drivers/pci.asm"
%include "src/install.asm"
; EXTRA_DRIVER_INCLUDES
%include "src/drivers/manifest.inc"

%include "src/memory.asm"
%include "src/kconfig.asm"
%include "src/process.asm"
%include "src/multitask.asm"
%include "src/demand.asm"
%include "src/sysfiles.asm"
%include "src/swap.asm"
%include "src/drivers/minidrv.asm"
%include "src/nasm.asm"
%include "src/kbuild.asm"
%include "src/kupdate.asm"
%include "src/extensions/bridge.asm"
cmd_castctl:
    mov esi, [args]
    call spaces
    mov edi, esi
.word:
    mov al, [esi]
    test al, al
    jz .split
    cmp al, ' '
    je .split
    cmp al, 'A'
    jb .next
    cmp al, 'Z'
    ja .next
    add byte [esi], 32
.next:
    inc esi
    jmp .word
.split:
    test al, al
    jz .tail
    mov byte [esi], 0
    inc esi
    call spaces
.tail:
    cmp byte [edi], 0
    je .usage
    push edi
    mov [args], esi
    cmp dword [edi], 'help'
    je .help
    mov [cmdptr], edi
    call ext_route
    test eax, eax
    jnz .done
    mov ebx, admin_commands
.find:
    mov esi, [cmdptr]
    mov edi, [ebx]
    test edi, edi
    jz .unknown
    call equal
    je .run
    add ebx, 12
    jmp .find
.run:
    call [ebx+4]
    jmp .done
.unknown:
    mov esi, unknown
    call puts
.done:
    pop edi
    ret
.help:
    pop edi
.usage:
    mov esi, castctl_help
    jmp puts
cmd_dir equ cmd_ls
cmd_type equ cmd_cat
cmd_cls equ clear
cmd_copy equ cmd_cp
cmd_ver equ cmd_version
lib_mathcas: incbin "lib/math.cas"
lib_utilcas: incbin "lib/util.cas"
lib_io: incbin "lib/io.inc"
lib_math: incbin "lib/math.inc"

times 0x10000-($-$$) db 0
incbin "build/nasm_runtime.bin"
%include "src/castic.asm"
kernel_end:
%if (kernel_end-$$) > 0x20000
    %error "Kernel overlaps scratch memory"
%endif
