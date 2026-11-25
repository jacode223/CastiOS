; CastiOS x86-64 bootstrap. Independent experimental target, no 32-bit ABI.
bits 32
org 0x100000
MB_MAGIC equ 0x1badb002
MB_FLAGS equ 0x10007
align 4
mb_header:
    dd MB_MAGIC, MB_FLAGS, -(MB_MAGIC+MB_FLAGS)
    dd mb_header, 0x100000, image_end, image_end, start32
    dd 0, 1024, 768, 32       ; Multiboot linear graphics request
start32:
    cli
    mov esp, stack_end
    cmp eax, 0x2badb002
    jne no64
    mov [boot_info], ebx
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb no64
    mov eax, 0x80000001
    cpuid
    bt edx, 29                 ; long mode required
    jnc no64
    mov eax, 1
    cpuid
    bt edx, 6                  ; PAE required
    jnc no64
    mov eax, pdpt
    or eax, 3
    mov [pml4], eax
    mov eax, pages
    or eax, 3
    mov [pdpt], eax
    xor ecx, ecx
.map:
    mov eax, ecx
    shl eax, 21
    or eax, 0x83              ; present, writable, 2 MiB
    mov [pages+ecx*8], eax
    inc ecx
    cmp ecx, 512               ; identity-map first 1 GiB
    jb .map
    lgdt [gdt_ptr]
    mov eax, cr4
    or eax, 1<<5              ; PAE
    mov cr4, eax
    mov eax, pml4
    mov cr3, eax
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1<<8              ; EFER.LME
    wrmsr
    mov eax, cr0
    or eax, 1<<31             ; paging activates long mode
    mov cr0, eax
    jmp 8:long_entry
no64:
    mov esi, error_msg
.print:
    lodsb
    test al, al
    jz .stop
    out 0xe9, al
    jmp .print
.stop:
    hlt
    jmp .stop

align 8
gdt: dq 0, 0x00af9a000000ffff, 0x00cf92000000ffff
     dq 0x00affa000000ffff, 0x00cff2000000ffff ; CPL3 code/data
tss_desc: dq 0, 0
gdt_end:
gdt_ptr: dw gdt_end-gdt-1
         dd gdt
boot_info: dd 0
error_msg db 'CastiOS x64: CPU o GRUB incompatible',10,0

bits 64
%include "src/x64/castips_defs.inc"
long_entry:
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, stack_end
    xor rbp, rbp
    cld
    lea rdi, [rel panic]
    mov rcx, 256
    mov rsi, idt
.gate:
    mov word [rsi], di
    mov word [rsi+2], 8
    mov byte [rsi+4], 0
    mov byte [rsi+5], 0x8e
    mov rax, rdi
    shr rax, 16
    mov word [rsi+6], ax
    shr rax, 16
    mov dword [rsi+8], eax
    mov dword [rsi+12], 0
    add rsi, 16
    loop .gate
    lea rdi, [rel syscall80]
    mov rsi, idt+0x80*16
    mov dl, 0xee               ; DPL3 interrupt gate
    call set_gate
    lea rdi, [rel page_fault]
    mov rsi, idt+14*16
    mov dl, 0x8e
    call set_gate
    lea rdi, [rel page_fault]
    mov rsi, idt+13*16
    mov dl, 0x8e
    call set_gate
    lea rdi, [rel user_fault_noerr]
    mov rsi, idt+6*16         ; invalid opcode
    mov dl, 0x8e
    call set_gate
    mov rsi, idt+0*16         ; divide by zero
    call set_gate
    lidt [rel idt_ptr]
    mov rax, tss
    mov word [tss_desc], 103
    mov word [tss_desc+2], ax
    shr rax, 16
    mov byte [tss_desc+4], al
    mov byte [tss_desc+5], 0x89
    shr rax, 8
    mov byte [tss_desc+7], al
    shr rax, 8
    mov dword [tss_desc+8], eax
    mov qword [tss+4], tss_stack_end
    mov word [tss+102], 104
    mov ax, 0x28
    ltr ax
    call mem_init
    call user_init
    call fb64_init
    call scheduler_init
    call cps_init
    call mouse64_init
    mov rsi, welcome
    call puts
    call shell64_prompt
    sti
.shell:
    in al, 0x64
    test al, 1
    jz .shell
    test al, 0x20
    jnz .mouse_byte
    in al, 0x60
    cmp al, 0x2a
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xaa
    je .shift_off
    cmp al, 0xb6
    je .shift_off
    test al, 0x80
    jnz .shell
    cmp al, 0x1c
    je .enter
    cmp al, 0x0e
    je .back
    movzx eax, al
    cmp eax, keymap_end-keymap
    jae .shell
    mov al, [keymap+rax]
    test al, al
    jz .shell
    cmp byte [shell_shift], 0
    je .no_shift
    cmp al, '.'
    jne .no_shift
    mov al, '>'
.no_shift:
    movzx edx, byte [line_len]
    cmp edx, 62
    jae .shell
    mov [line+rdx], al
    inc byte [line_len]
    call putc
    jmp .shell
.mouse_byte:
    in al, 0x60
    call mouse64_byte
    jmp .shell
.shift_on:
    mov byte [shell_shift], 1
    jmp .shell
.shift_off:
    mov byte [shell_shift], 0
    jmp .shell
.back:
    cmp byte [line_len], 0
    je .shell
    dec byte [line_len]
    mov al, 8
    call putc
    jmp .shell
.enter:
    mov al, 10
    call putc
    movzx edx, byte [line_len]
    mov byte [line+rdx], 0
    call shell64_dispatch
    cmp eax, 0
    jne .again
    mov rdi, castic_cmd
    call cmd_prefix
    jz .castic
    mov rsi, line
    mov rdi, help_cmd
    call streq
    jz .help
    mov rdi, uname_cmd
    call streq
    jz .uname
    mov rdi, mem_cmd
    call streq
    jz .mem
    mov rdi, halt_cmd
    call streq
    jz .halt
    mov rdi, reboot_cmd
    call streq
    jz .reboot
    mov rdi, run_cmd
    call streq
    jz .run
    mov rdi, fault_cmd
    call streq
    jz .fault
    mov rdi, frames_cmd
    call streq
    jz .frames
    mov rdi, badptr_cmd
    call streq
    jz .badptr
    mov rdi, ud_cmd
    call streq
    jz .ud
    mov rdi, io_cmd
    call streq
    jz .io
    mov rdi, users_cmd
    call streq
    jz .users
    mov rdi, groups_cmd
    call streq
    jz .groups
    mov rdi, perms_cmd
    call streq
    jz .perms
    mov rdi, rootcred_cmd
    call streq
    jz .rootcred
    mov rdi, guestcred_cmd
    call streq
    jz .guestcred
    mov rdi, ps_cmd
    call streq
    jz .ps
    mov rdi, reap_cmd
    call streq
    jz .reap
    mov rdi, pidtest_cmd
    call streq
    jz .pidtest
    mov rdi, syscheck_cmd
    call streq
    jz .syscheck
    mov rdi, multi_cmd
    call streq
    jz .multi
    mov rdi, multifault_cmd
    call streq
    jz .multifault
    mov rdi, groupcred_cmd
    call streq
    jz .groupcred
    mov rdi, filesys_cmd
    call streq
    jz .filesys
    mov rdi, filedeny_cmd
    call streq
    jz .filedeny
    mov rdi, filewrite_cmd
    call streq
    jz .filewrite
    mov rdi, fileguest_cmd
    call streq
    jz .fileguest
    mov rdi, mount_cmd
    call streq
    jz .mount
    mov rdi, ahciscan_cmd
    call streq
    jz .ahciscan
    mov rdi, disks_cmd
    call streq
    jz .disks
    mov rdi, install_cmd
    call streq
    jz .install
    mov rdi, install_cmd
    call cmd_prefix
    jz .install_args
    mov rdi, mousestat_cmd
    call streq
    jz .mousestat
    mov rdi, mount6_cmd
    call streq
    jz .mount6
    mov rdi, ls6_cmd
    call cmd_prefix
    jz .ls6
    mov rdi, cat6_cmd
    call cmd_prefix
    jz .cat6
    mov rdi, stat6_cmd
    call cmd_prefix
    jz .stat6
    mov rdi, write6_cmd
    call cmd_prefix
    jz .write6
    mov rdi, read6_cmd
    call cmd_prefix
    jz .read6
    mov rdi, write_cmd
    call cmd_prefix
    jz .echo
    mov rdi, stat_cmd
    call cmd_prefix
    jz .stat6
    mov rsi, line
    mov rdi, ls_cmd
    call cmd_prefix
    jz .ls
    mov rdi, cat_cmd
    call cmd_prefix
    jz .cat
    mov rdi, cd_cmd
    call cmd_prefix
    jz .cd
    mov rdi, mkdir6_cmd
    call cmd_prefix
    jz .mkdir6
    mov rdi, mkdir_cmd
    call cmd_prefix
    jz .mkdir6
    mov rdi, cp_cmd
    call cmd_prefix
    jz .cp
    mov rdi, pwd_cmd
    call streq
    jz .pwd
    cmp byte [line], 0
    je .again
    mov rsi, unknown
    jmp .out
.castic:
    call castic_compile
    jmp .again
.help:
    mov rsi, help_text
    jmp .out
.uname:
    mov rsi, welcome
    jmp .out
.mem:
    mov rsi, mem_text
    call puts
    mov eax, [boot_info]
    test eax, eax
    jz .again
    test dword [rax], 1
    jz .again
    mov eax, [rax+8]          ; upper memory KiB, Multiboot v1
    call decimal
    mov rsi, kib_text
    jmp .out
.halt:
    mov rsi, halt_text
    call puts
.halt_loop:
    cli
    hlt
    jmp .halt_loop
.reboot:
    mov al, 0xfe
    out 0x64, al
    jmp .halt_loop
.run:
    mov rsi, app_start
    mov ecx, app_end-app_start
    jmp .launch
.fault:
    mov rsi, app_fault
    mov ecx, app_fault_end-app_fault
    jmp .launch
.badptr:
    mov rsi, app_badptr
    mov ecx, app_badptr_end-app_badptr
    jmp .launch
.ud:
    mov rsi, app_ud
    mov ecx, app_ud_end-app_ud
    jmp .launch
.io:
    mov rsi, app_io
    mov ecx, app_io_end-app_io
    jmp .launch
.rootcred:
    mov rsi, app_cred
    mov ecx, app_cred_end-app_cred
    jmp .launch
.guestcred:
    mov rsi, app_cred
    mov ecx, app_cred_end-app_cred
    mov byte [selected_user], 1
    jmp .launch_ready
.groupcred:
    mov rsi, app_groupcred
    mov ecx, app_groupcred_end-app_groupcred
    mov byte [selected_user], 1
    jmp .launch_ready
.filesys:
    mov rsi, app_filesys
    mov ecx, app_filesys_end-app_filesys
    jmp .launch
.filedeny:
    mov rsi, app_filedeny
    mov ecx, app_filedeny_end-app_filedeny
    mov byte [selected_user], 1
    jmp .launch_ready
.filewrite:
    mov rsi, app_filewrite
    mov ecx, app_filewrite_end-app_filewrite
    jmp .launch
.fileguest:
    mov rsi, app_fileguest
    mov ecx, app_fileguest_end-app_fileguest
    mov byte [selected_user], 1
    jmp .launch_ready
.pidtest:
    mov rsi, app_pidtest
    mov ecx, app_pidtest_end-app_pidtest
    jmp .launch
.syscheck:
    mov rsi, app_syscheck
    mov ecx, app_syscheck_end-app_syscheck
    jmp .launch
.launch:
    mov byte [selected_user], 0
.launch_ready:
    mov qword [cps_pending_name], line
    call user_launch
    test eax, eax
    jnz .failed
    cmp byte [user_fault], 0
    jne .faulted
    mov rsi, exit_text
    call puts
    mov eax, [user_result]
    call decimal
    mov al, 10
    call putc
    jmp .again
.failed:
    mov rsi, no_user_text
    jmp .out
.faulted:
    mov rsi, user_fault_text
    jmp .out
.frames:
    mov rsi, frames_text
    call puts
    mov eax, [frame_count]
    call decimal
    mov al, 10
    call putc
    jmp .again
.users:
    mov rsi, users_text
    jmp .out
.mount:
    call hs6_mount
    jmp .again
.ahciscan:
    call ahci64_probe
    jmp .again
.disks:
    call disk64_list
    jmp .again
.install:
    mov rsi, install64_msg
    call puts
    jmp .again
.install_args:
    mov rdi, install64_confirm
    call streq
    jne .install
    call install64_run
    jmp .again
.mousestat:
    call mouse64_status
    jmp .again
.mount6:
    call hs6_mount
    jmp .again
.ls6:
    call hs6_ls_path
    jmp .again
.cat6:
    mov byte [hs6_stat_mode], 0
    call hs6_cat
    jmp .again
.stat6:
    mov byte [hs6_stat_mode], 1
    call hs6_cat
    jmp .again
.write6:
    call hs6_write
    jmp .again
.read6:
    call hs6_read_range
    jmp .again
.echo:
    call shell_echo
    jmp .again
.ls:
    call hs6_ls_path
    jmp .again
.cat:
    mov byte [hs6_stat_mode], 0
    call hs6_cat
    jmp .again
.cd:
    call hs6_cd
    jmp .again
.mkdir6:
    call hs6_mkdir
    jmp .again
.cp:
    call hs6_copy
    jmp .again
.pwd:
    call hs6_pwd
    jmp .again
.groups:
    mov rsi, groups_text
    jmp .out
.perms:
    mov rsi, perms_text
    jmp .out
.ps:
    call cps_ps
    jmp .again
.reap:
    call cps_reap
    jmp .again
.multi:
    mov byte [multi_fault_variant], 0
    jmp .multi_ready
.multifault:
    mov byte [multi_fault_variant], 1
.multi_ready:
    call multi_launch
    test eax, eax
    jnz .failed
    mov rsi, multi_text
    call puts
    mov eax, [switch_count]
    call decimal
    mov al, 10
    call putc
    mov rsi, results_text
    call puts
    mov eax, [task_results]
    call decimal
    mov rsi, second_result_text
    call puts
    mov eax, [task_results+8]
    call decimal
    mov al, 10
    call putc
    jmp .again
.out:
    call puts
.again:
    mov byte [line_len], 0
    call shell64_prompt
    jmp .shell

; Compare rsi (input) with rdi (literal), preserve both and report ZF.
cmd_prefix:
    mov rsi, line
.next:
    mov al, [rdi]
    test al, al
    jz .end
    cmp al, [rsi]
    jne .no
    inc rsi
    inc rdi
    jmp .next
.end:
    cmp byte [rsi], 0
    je .yes
    cmp byte [rsi], ' '
    jne .no
.space:
    cmp byte [rsi], ' '
    jne .yes
    inc rsi
    jmp .space
.yes:
    xor eax, eax
    ret
.no:
    mov eax, 1
    test eax, eax
    ret
; echo TEXTO or echo TEXTO > ARCHIVO. Redirection uses the HSFS6 writer.
shell_echo:
    mov rbx, rsi
.find_redirect:
    mov al, [rsi]
    test al, al
    jz .plain
    cmp al, '>'
    je .redirect
    inc rsi
    jmp .find_redirect
.plain:
    mov rsi, rbx
    call puts
    mov al, 10
    jmp putc
.redirect:
    mov rdx, rsi
    inc rsi
.skip_spaces:
    cmp byte [rsi], ' '
    jne .name
    inc rsi
    jmp .skip_spaces
.name:
    mov rdi, echo_buffer
    xor ecx, ecx
.copy_name:
    mov al, [rsi]
    test al, al
    jz .end_name
    cmp al, ' '
    je .end_name
    cmp ecx, 63
    jae .error
    mov [rdi], al
    inc rdi
    inc rsi
    inc ecx
    jmp .copy_name
.end_name:
    test ecx, ecx
    jz .error
.trailing:
    cmp byte [rsi], ' '
    jne .trailing_done
    inc rsi
    jmp .trailing
.trailing_done:
    cmp byte [rsi], 0
    jne .error
.trim:
    cmp rdx, rbx
    jbe .error
    cmp byte [rdx-1], ' '
    jne .copy_text
    dec rdx
    jmp .trim
.copy_text:
    mov byte [rdi], ' '
    inc rdi
.copy:
    cmp rbx, rdx
    jae .done
    mov al, [rbx]
    mov [rdi], al
    inc rdi
    inc rbx
    jmp .copy
.done:
    mov byte [rdi], 10
    inc rdi
    mov byte [rdi], 0
    mov rsi, echo_buffer
    call hs6_write
    ret
.error:
    mov rsi, echo_usage
    jmp puts
streq:
    push rsi
    push rdi
.next:
    mov al, [rsi]
    cmp al, [rdi]
    jne .done
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .next
.done:
    pop rdi
    pop rsi
    ret
puts:
    mov al, [rsi]
    test al, al
    jz .done
    call putc
    inc rsi
    jmp puts
.done: ret
putc:
    out 0xe9, al
    cmp byte [fb64_active], 0
    je .vga
    call fb64_putc
    ret
.vga:
    push rbx
    push rcx
    push rdx
    movzx ebx, word [cursor]
    cmp al, 10
    je .newline
    cmp al, 8
    je .backspace
    mov ecx, ebx
    shl ecx, 1
    mov [0xb8000+rcx], al
    mov byte [0xb8001+rcx], 0x1f
    inc ebx
    jmp .wrap
.backspace:
    test ebx, ebx
    jz .save
    dec ebx
    mov ecx, ebx
    shl ecx, 1
    mov word [0xb8000+rcx], 0x1f20
    jmp .save
.newline:
    mov eax, ebx
    xor edx, edx
    mov ecx, 80
    div ecx
    sub ebx, edx
    add ebx, 80
.wrap:
    cmp ebx, 2000
    jb .save
    xor ebx, ebx
.save:
    mov [cursor], bx
    pop rdx
    pop rcx
    pop rbx
    ret
decimal:
    mov ecx, 10
    lea rdi, [rel digits+11]
    mov byte [rdi], 0
.next:
    xor edx, edx
    div ecx
    dec rdi
    add dl, '0'
    mov [rdi], dl
    test eax, eax
    jnz .next
    mov rsi, rdi
    jmp puts
panic:
    mov rsi, panic_text
    call puts
.stop:
    cli
    hlt
    jmp .stop

%include "src/x64/shell64.asm"
%include "src/x64/shell_external.asm"
%include "src/x64/castic.asm"
%include "src/x64/framebuffer.asm"
%include "src/x64/memory.asm"
%include "src/x64/security.asm"
%include "src/x64/user.asm"
%include "src/x64/scheduler.asm"
%include "src/x64/castips.asm"
%include "src/x64/hsfs.asm"
%include "src/x64/hsfs6.asm"
%include "src/x64/hsfs61_paths.asm"
%include "src/x64/hsfs61_read.asm"
%include "src/x64/hsfs6_write.asm"
%include "src/x64/hsfs61_copy.asm"
%include "src/x64/hsfs6_syscalls.asm"
%include "src/x64/ahci.asm"
%include "src/x64/mouse.asm"
%include "src/x64/diskinfo.asm"

welcome db 'CastiOS x86-64: long mode activo',10,0
prompt db 'x64> ',0
castic_cmd db 'castic',0
help_cmd db 'help',0
uname_cmd db 'uname',0
mem_cmd db 'mem',0
halt_cmd db 'halt',0
reboot_cmd db 'reboot',0
help_text db 'castic fuente destino; shell list classic rescue new run',10,'help mount ls cd pwd mkdir cp cat stat echo write6 read6',10,'disks install ahciscan mousestat uname users groups reboot halt',10,0
ahciscan_cmd db 'ahciscan',0
disks_cmd db 'disks',0
install_cmd db 'install',0
mousestat_cmd db 'mousestat',0
echo_buffer times 96 db 0
echo_usage db 'Uso: echo texto > archivo',10,0
mount6_cmd db 'mount6',0
ls6_cmd db 'ls6',0
cat6_cmd db 'cat6',0
stat6_cmd db 'stat6',0
write6_cmd db 'write6',0
read6_cmd db 'read6',0
write_cmd db 'echo',0
stat_cmd db 'stat',0
mount_cmd db 'mount',0
ls_cmd db 'ls',0
cat_cmd db 'cat',0
cd_cmd db 'cd',0
mkdir_cmd db 'mkdir',0
cp_cmd db 'cp',0
mkdir6_cmd db 'mkdir6',0
pwd_cmd db 'pwd',0
run_cmd db 'run64',0
fault_cmd db 'fault64',0
frames_cmd db 'frames',0
badptr_cmd db 'badptr64',0
ud_cmd db 'ud64',0
io_cmd db 'io64',0
users_cmd db 'users',0
groups_cmd db 'groups',0
perms_cmd db 'perms',0
rootcred_cmd db 'rootcred',0
guestcred_cmd db 'guestcred',0
ps_cmd db 'ps',0
reap_cmd db 'reap',0
pidtest_cmd db 'pidtest64',0
syscheck_cmd db 'syscheck',0
multi_cmd db 'multi64',0
multifault_cmd db 'multifault64',0
groupcred_cmd db 'groupcred',0
filesys_cmd db 'filesys',0
filedeny_cmd db 'filedeny',0
filewrite_cmd db 'filewrite',0
fileguest_cmd db 'fileguest',0
multi_text db 'Cambio de tarea por PIT: ',0
results_text db 'root EAX=',0
second_result_text db ' alice EAX=',0
users_text db 'root uid=0 gid=0; alice uid=1000 gid=100',10,0
groups_text db 'system gid=0; users gid=100',10,0
perms_text db 'admin root:system 0600; log root:users 0660',10,0
exit_text db 'Proceso CPL3 terminado con EAX=',0
no_user_text db 'Sin memoria para proceso CPL3',10,0
user_fault_text db 'Tarea CPL3 terminada por fallo; kernel sigue',10,0
frames_text db 'Marcos 4 KiB asignados: ',0
mem_text db 'RAM por Multiboot: ',0
kib_text db ' KiB sobre 1 MiB',10,0
halt_text db 'CPU detenida',10,0
panic_text db 'EXCEPCION x64',10,0
unknown db 'Comando x64 desconocido',10,0
keymap db 0,0,'1234567890-=',0,0,'qwertyuiop[]',10,0,'asdfghjkl;',0,0,0,0,'zxcvbnm,./',0,0,0,' '
keymap_end:
cursor: dw 0
shell_shift: db 0
line_len: db 0
line: times 64 db 0
digits: times 12 db 0
idt_ptr: dw 256*16-1
         dq idt
align 16
idt: times 256*16 db 0
align 4096
pml4: times 4096 db 0
pdpt: times 4096 db 0
pages: times 4096 db 0
stack: times 8192 db 0
stack_end:
image_end:
