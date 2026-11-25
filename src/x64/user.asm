; First isolated x64 task: one synchronous CPL3 image, private 4 KiB pages.
; Deliberately no direct access to the supervisor identity map or VGA.
USER_BASE equ 0x40000000
user_init:
    xor ebp, ebp
.task:
    call frame_alloc
    test rax, rax
    jz .fail
    mov rsi, rax               ; private PML4
    mov [task_cr3+rbp*8], rax
    call frame_alloc
    test rax, rax
    jz .fail
    mov rdi, rax               ; private PDPT
    call frame_alloc
    test rax, rax
    jz .fail
    mov rbx, rax               ; private PD
    call frame_alloc
    test rax, rax
    jz .fail
    mov r12, rax               ; private PT
    call frame_alloc
    test rax, rax
    jz .fail
    mov r13, rax               ; code
    mov [task_code+rbp*8], rax
    call frame_alloc
    test rax, rax
    jz .fail
    mov r14, rax               ; data
    mov [task_data+rbp*8], rax
    call frame_alloc
    test rax, rax
    jz .fail
    mov r15, rax               ; stack
    mov [task_stack+rbp*8], rax
    mov rax, rdi
    or rax, 7
    mov [rsi], rax             ; PML4 entry with U/S for user subtree
    mov rax, pages
    or rax, 3
    mov [rdi], rax             ; shared supervisor identity map
    mov rax, rbx
    or rax, 7
    mov [rdi+8], rax           ; user region starts at 1 GiB
    mov rax, r12
    or rax, 7
    mov [rbx], rax
    mov rax, r13
    or rax, 5                 ; code read-only to user
    mov [r12], rax
    mov rax, r14
    or rax, 7
    mov [r12+16], rax         ; data at +0x2000
    mov rax, r15
    or rax, 7
    mov [r12+32], rax         ; stack at +0x4000; guard +0x3000
    inc ebp
    cmp ebp, 2
    jb .task
    mov rax, [task_code]
    mov [app_code_phys], rax
    mov rax, cr0
    or rax, 1<<16             ; supervisor honours read-only user PTE
    mov cr0, rax
    mov byte [user_ready], 1
.fail:
    ret

; RSI=static code template, ECX=size; returns EAX=0 after exit/fault.
user_launch:
    cmp byte [user_ready], 1
    jne .error
    cmp ecx, 4096
    ja .error
    movzx ebx, byte [selected_user]
    mov rdi, [task_code+rbx*8]
    push rsi
    push rcx
    mov ecx, 512
    xor eax, eax
    rep stosq
    pop rcx
    pop rsi
    mov rdi, [task_code+rbx*8]
    rep movsb
    call clear_user_slot
    mov byte [user_fault], 0
    mov qword [user_result], 0
    mov rdi, [cps_pending_name]
    mov dl, CPS_RUNNING
    call cps_register
    mov byte [cps_single_active], 1
    mov byte [cps_table+CPS_ENTRY_SIZE+CPS_STATE], CPS_BLOCKED
    mov [resume_sp], rsp
    mov [task_current], bl
    call task_activate
    mov ax, 0x23
    mov ds, ax
    mov es, ax
    push qword 0x23           ; SS
    push qword USER_BASE+0x5000 ; stack top
    pushfq
    push qword 0x1b           ; CPL3 64-bit code
    push qword USER_BASE
    iretq
.error:
    mov eax, 1
    ret

syscall80:
    cmp rax, 50
    jae .nosys
    jmp [syscall64_table+rax*8]
; Nonblocking PS/2 keyboard input for the foreground CPL3 process.
; Returns ASCII, -EAGAIN when no key is available, -EBUSY in multitask.
.key_poll:
    cmp byte [multi_active], 0
    jne .key_busy
    push rdx
    mov dx, 0x64
    in al, dx
    test al, 1
    jz .key_empty
    test al, 0x20
    jnz .key_mouse
    mov dx, 0x60
    in al, dx
    cmp byte [key_ext_prefix], 0
    je .key_prefix
    mov byte [key_ext_prefix], 0
    jmp .key_empty
.key_prefix:
    cmp al, 0xe0
    jne .key_shift
    mov byte [key_ext_prefix], 1
    jmp .key_empty
.key_shift:
    cmp al, 0x2a
    je .key_down
    cmp al, 0x36
    je .key_down
    cmp al, 0xaa
    je .key_up
    cmp al, 0xb6
    je .key_up
    test al, 0x80
    jnz .key_empty
    cmp al, 0x0e
    je .key_back
    movzx eax, al
    cmp eax, keymap_end-keymap
    jae .key_empty
    movzx eax, byte [keymap+rax]
    test al, al
    jz .key_empty
    cmp byte [shell_shift], 0
    je .key_return
    cmp al, '.'
    jne .key_return
    mov eax, '>'
.key_return:
    pop rdx
    iretq
.key_back:
    mov eax, 8
    jmp .key_return
.key_down:
    mov byte [shell_shift], 1
    jmp .key_empty
.key_up:
    mov byte [shell_shift], 0
    jmp .key_empty
.key_mouse:
    mov dx, 0x60
    in al, dx
    push rbx
    push rcx
    push rsi
    push rdi
    call mouse64_byte
    pop rdi
    pop rsi
    pop rcx
    pop rbx
.key_empty:
    pop rdx
    mov rax, -11
    iretq
.key_busy:
    mov rax, -16
    iretq
.abi_version:
    mov eax, 1
    iretq
.console_size:
    ; high 32 bits = rows, low 32 bits = columns
    mov rax, (25 << 32) | 80
    iretq
.fb_width:
    cmp byte [fb64_active], 1
    jne .nodev
    mov eax, [fb64_width]
    iretq
.fb_height:
    cmp byte [fb64_active], 1
    jne .nodev
    mov eax, [fb64_height]
    iretq
.shell_id:
    movzx eax, byte [shell64_current]
    iretq
.getppid:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    mov eax, [cps_table+rax+CPS_PPID]
    iretq
.uptime:
    mov eax, [pit_ticks]
    iretq
.task_ticks:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    mov eax, [cps_table+rax+CPS_TICKS]
    iretq
.pagesize:
    mov eax, 4096
    iretq
.mounted:
    movzx eax, byte [hs6_ready]
    iretq
.capacity:
    cmp byte [hs6_ready], 1
    jne .nodev
    mov rax, [hs6_total]
    iretq
.diskbackend:
    movzx eax, byte [ahci64_active]
    iretq
.diskerrors:
    mov eax, [disk64_read_errors]
    iretq
.diskretries:
    mov eax, [disk64_read_retries]
    iretq
.filesize:
    call hs6_sys_filesize
    iretq
.procstate:
    call cps_sys_procstate
    iretq
.mouse_x:
    cmp byte [mouse64_ready], 1
    jne .nodev
    mov eax, [mouse64_x]
    iretq
.mouse_y:
    cmp byte [mouse64_ready], 1
    jne .nodev
    mov eax, [mouse64_y]
    iretq
.mouse_buttons:
    cmp byte [mouse64_ready], 1
    jne .nodev
    movzx eax, byte [mouse64_buttons]
    iretq
.mouse_ready:
    movzx eax, byte [mouse64_ready]
    iretq
.mouse_events:
    cmp byte [mouse64_ready], 1
    jne .nodev
    mov eax, [mouse64_events]
    iretq
.nodev:
    mov rax, -19
    iretq
.getpid:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    mov eax, [cps_table+rax+CPS_PID]
    iretq
.uid:
    movzx eax, byte [task_current]
    mov eax, [task_uids+rax*4]
    iretq
.gid:
    movzx eax, byte [task_current]
    mov eax, [task_gids+rax*4]
    iretq
.admin:
    push rdi
    push rsi
    mov edi, 0               ; owner uid
    mov esi, 0               ; group system
    mov edx, 0600o
    mov ecx, 2               ; write
    call permission_check
    pop rsi
    pop rdi
    test eax, eax
    jz .denied
    jmp .write_check
.group_log:
    push rdi
    push rsi
    mov edi, 0
    mov esi, 100             ; group users
    mov edx, 0660o
    mov ecx, 2
    call permission_check
    pop rsi
    pop rdi
    test eax, eax
    jz .denied
.write_check:
    test rsi, rsi
    jz .empty
    cmp rsi, 256
    ja .bad
    ; A complete range must fit inside one mapped user page.
    cmp rdi, USER_BASE
    jb .bad
    mov rcx, USER_BASE+4096
    cmp rdi, rcx
    jb .range
    cmp rdi, USER_BASE+0x2000
    jb .bad
    mov rcx, USER_BASE+0x3000
    cmp rdi, rcx
    jb .range
    cmp rdi, USER_BASE+0x4000
    jb .bad
    mov rcx, USER_BASE+0x5000
    cmp rdi, rcx
    jae .bad
.range:
    sub rcx, rdi
    cmp rsi, rcx
    ja .bad
    mov edx, esi
    mov rbx, rsi
    mov rsi, rdi
.write:
    mov al, [rsi]
    call putc
    inc rsi
    dec rbx
    jnz .write
    mov eax, edx
    iretq
.file_read:
    call hs6_sys_read
    iretq
.file_write:
    call hs6_sys_write
    iretq
.empty:
    xor eax, eax
    iretq
.bad:
    mov rax, -14
    iretq
.denied:
    mov rax, -13
    iretq
.nosys:
    mov rax, -38
    iretq
.exit:
    mov [user_result], rdi
    jmp task_finish

; Stable x64 ABI has 50 slots. Unimplemented entries explicitly return
; -ENOSYS; reserving a slot does not advertise a working operation.
align 8
syscall64_table:
    dq syscall80.exit, syscall80.write_check, syscall80.uid, syscall80.gid
    dq syscall80.admin, syscall80.group_log, syscall80.file_read, syscall80.file_write
    dq syscall80.getpid, cps_sys_yield, syscall80.getppid, syscall80.uptime
    dq syscall80.task_ticks, syscall80.pagesize, syscall80.mounted
    dq syscall80.capacity, syscall80.diskbackend, syscall80.diskerrors
    dq syscall80.diskretries, syscall80.filesize, syscall80.procstate
    dq syscall80.mouse_x, syscall80.mouse_y, syscall80.mouse_buttons
    dq syscall80.mouse_ready, syscall80.mouse_events
    dq syscall80.abi_version, syscall80.console_size, syscall80.fb_width
    dq syscall80.fb_height, syscall80.shell_id
    dq syscall80.key_poll
    times 18 dq syscall80.nosys

; #PF and #GP push an error code before RIP, CS, RFLAGS, user RSP, SS.
page_fault:
    mov rax, [rsp+16]
    and eax, 3
    cmp eax, 3
    jne panic
    mov byte [user_fault], 1
    mov qword [user_result], -14
    jmp task_finish
user_fault_noerr:
    mov rax, [rsp+8]
    and eax, 3
    cmp eax, 3
    jne panic
    mov byte [user_fault], 1
    mov qword [user_result], -14
    jmp task_finish
user_resume:
    call cps_resume_shell
    mov rax, pml4
    mov cr3, rax
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov rsp, [resume_sp]
    xor eax, eax
    sti
    ret

; Byte-for-byte templates copied into the isolated code frame on launch.
app_start:
    mov eax, 1
    lea rdi, [rel app_message]
    mov esi, app_message_end-app_message
    int 0x80
    mov eax, 0
    mov edi, 42
    int 0x80
    ud2
app_message db 'Proceso CPL3 x64: syscall write OK',10
app_message_end:
app_end:
app_pidtest:
    mov eax, 8                 ; CastiPS getpid syscall
    int 0x80
    cmp eax, 2
    jb .fail
    mov r12d, eax
    mov eax, 9                 ; CastiPS yield syscall
    int 0x80
    test eax, eax
    jne .fail
    mov eax, 8
    int 0x80
    cmp eax, r12d
    jne .fail
    xor eax, eax
    xor edi, edi
    int 0x80
.fail:
    xor eax, eax
    mov edi, 77
    int 0x80
app_pidtest_end:
; Verify process identity, system information and all reserved ABI slots.
app_syscheck:
    mov eax, 10
    int 0x80
    cmp rax, 1
    jne .fail
    mov eax, 13
    int 0x80
    cmp rax, 4096
    jne .fail
    mov eax, 8
    int 0x80
    mov rdi, rax
    mov eax, 20
    int 0x80
    cmp eax, CPS_RUNNING
    jne .fail
    xor edi, edi
    mov eax, 20
    int 0x80
    cmp rax, -13
    jne .fail
    mov eax, 14
    int 0x80
    test rax, rax
    jnz .fail
    mov eax, 15
    int 0x80
    cmp rax, -19
    jne .fail
    mov eax, 24
    int 0x80
    cmp rax, 1
    jne .fail
    mov eax, 21
    int 0x80
    cmp rax, 959
    ja .fail
    mov eax, 22
    int 0x80
    cmp rax, 599
    ja .fail
    mov eax, 23
    int 0x80
    cmp rax, 7
    ja .fail
    mov eax, 25
    int 0x80
    test rax, rax
    js .fail
    mov eax, 26
    int 0x80
    cmp rax, 1
    jne .fail
    mov eax, 27
    int 0x80
    mov rdx, (25 << 32) | 80
    cmp rax, rdx
    jne .fail
    mov eax, 28
    int 0x80
    cmp rax, -19
    je .no_fb
    cmp rax, 640
    jb .fail
    mov eax, 29
    int 0x80
    cmp rax, 400
    jb .fail
.no_fb:
    mov eax, 30
    int 0x80
    cmp rax, 1
    ja .fail
    ; Data and stack pages are now valid console buffers; guard page is not.
    mov byte [USER_BASE+0x2000], 'X'
    mov eax, 1
    mov edi, USER_BASE+0x2000
    mov esi, 1
    int 0x80
    cmp rax, 1
    jne .fail
    mov eax, 1
    mov edi, USER_BASE+0x2fff
    mov esi, 2
    int 0x80
    cmp rax, -14
    jne .fail
    mov byte [USER_BASE+0x4000], 'Y'
    mov eax, 1
    mov edi, USER_BASE+0x4000
    mov esi, 1
    int 0x80
    cmp rax, 1
    jne .fail
    mov eax, 1
    mov edi, 0x100000
    mov esi, 1
    int 0x80
    cmp rax, -14
    jne .fail
    mov eax, 1
    mov edi, USER_BASE+0x3000
    mov esi, 1
    int 0x80
    cmp rax, -14
    jne .fail
    mov ebx, 32
.loop:
    mov eax, ebx
    int 0x80
    cmp rax, -38
    jne .fail
    inc ebx
    cmp ebx, 50
    jb .loop
    mov eax, 50
    int 0x80
    cmp rax, -38
    jne .fail
    xor eax, eax
    xor edi, edi
    int 0x80
.fail:
    xor eax, eax
    mov edi, 78
    int 0x80
app_syscheck_end:
app_fault:
    mov rax, 0x100000
    mov byte [rax], 0x5a     ; supervisor page: must fault
    ud2
app_fault_end:
app_badptr:
    mov eax, 1
    mov rdi, 0x100000
    mov esi, 4
    int 0x80
    cmp rax, -14
    jne .bad
    mov edi, 7
    jmp .exit
.bad:
    mov edi, 99
.exit:
    xor eax, eax
    int 0x80
app_badptr_end:
app_ud:
    ud2
app_ud_end:
app_io:
    in al, 0x60              ; no I/O permission at CPL3 -> #GP
    ud2
app_io_end:
app_cred:
    mov eax, 4               ; admin diagnostic: root only
    lea rdi, [rel cred_text]
    mov esi, cred_text_end-cred_text
    int 0x80
    cmp eax, -13
    je .guest
    mov eax, 0
    mov edi, 0
    int 0x80
.guest:
    mov eax, 0
    mov edi, 13
    int 0x80
cred_text db 'recurso root:system permitido',10
cred_text_end:
app_cred_end:
app_groupcred:
    mov eax, 5               ; group log root:users 0660
    lea rdi, [rel .msg]
    mov esi, .end-.msg
    int 0x80
    cmp eax, -13
    je .denied
    xor eax, eax
    xor edi, edi
    int 0x80
.denied:
    xor eax, eax
    mov edi, 13
    int 0x80
.msg db 'recurso de grupo users permitido',10
.end:
app_groupcred_end:
app_filesys:
    mov eax, 19
    lea rdi, [rel .filename]
    int 0x80
    cmp rax, 4
    jb .fail
    mov eax, 6
    lea rdi, [rel .filename]
    mov esi, USER_BASE+0x2000
    mov edx, 4
    xor ecx, ecx
    int 0x80
    cmp rax, 4
    jne .fail
    cmp dword [USER_BASE+0x2000], 'hola'
    jne .fail
    ; Kernel addresses supplied as output buffers must be rejected.
    mov eax, 6
    lea rdi, [rel .filename]
    mov esi, 0x100000
    mov edx, 4
    xor ecx, ecx
    int 0x80
    cmp rax, -14
    jne .fail
    xor eax, eax
    mov edi, 7
    int 0x80
.fail:
    xor eax, eax
    mov edi, 99
    int 0x80
.filename db 'nuevo.txt',0
app_filesys_end:
app_filedeny:
    mov eax, 6
    lea rdi, [rel .filename]
    mov esi, USER_BASE+0x2000
    mov edx, 4
    xor ecx, ecx
    int 0x80
    cmp rax, -13
    jne .fail
    xor eax, eax
    mov edi, 7
    int 0x80
.fail:
    xor eax, eax
    mov edi, 99
    int 0x80
.filename db 'secreto.txt',0
app_filedeny_end:
app_filewrite:
    mov eax, 7
    lea rdi, [rel .filename]
    lea rsi, [rel .text]
    int 0x80
    test rax, rax
    jne .fail
    xor eax, eax
    mov edi, 7
    int 0x80
.fail:
    xor eax, eax
    mov edi, 99
    int 0x80
.filename db 'desdeapp.txt',0
.text db 'escrito por cpl3',0
app_filewrite_end:
app_fileguest:
    mov eax, 7
    lea rdi, [rel .filename]
    lea rsi, [rel .text]
    int 0x80
    cmp rax, -13
    jne .fail
    xor eax, eax
    mov edi, 7
    int 0x80
.fail:
    xor eax, eax
    mov edi, 99
    int 0x80
.filename db 'desdeapp.txt',0
.text db 'intruso',0
app_fileguest_end:

app_code_phys: dq 0
task_cr3: times 2 dq 0
task_code: times 2 dq 0
task_data: times 2 dq 0
task_stack: times 2 dq 0
task_current: db 0
selected_user: db 0
resume_sp: dq 0
user_result: dq 0
user_ready: db 0
user_fault: db 0
align 16
tss: times 104 db 0
tss_stack: times 8192 db 0
tss_stack_end:

; EBX=slot. No content from a prior exit or fault survives a relaunch.
clear_user_slot:
    mov rdi, [task_data+rbx*8]
    mov ecx, 512
    xor eax, eax
    rep stosq
    mov rdi, [task_stack+rbx*8]
    mov ecx, 512
    rep stosq
    ret

key_ext_prefix db 0
