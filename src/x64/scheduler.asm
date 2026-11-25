; PIT IRQ0 round robin for two isolated CPL3 tasks. Kernel IRQs only count.
scheduler_init:
    lea rdi, [rel timer_irq]
    mov rsi, idt+0x20*16
    mov dl, 0x8e
    call set_gate
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
    mov al, 0xfe               ; only timer IRQ0
    out 0x21, al
    mov al, 0xff
    out 0xa1, al
    mov al, 0x36               ; PIT 100 Hz
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al
    ret

%macro SAVE_REGS 0
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro
%macro RESTORE_REGS 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro
timer_irq:
    SAVE_REGS
    inc dword [pit_ticks]
    mov al, 0x20
    out 0x20, al
    mov rax, [rsp+128]         ; saved CS in CPU IRET frame
    and eax, 3
    cmp eax, 3
    jne .return
    call cps_tick_current
    cmp byte [multi_active], 1
    jne .return
    movzx ebx, byte [task_current]
    mov [task_rsp+rbx*8], rsp
    xor ebx, 1
    cmp byte [task_state+rbx], 1
    jne .return
    inc dword [switch_count]
    mov dl, CPS_RUNNING
    call cps_set_state
    xor ebx, 1
    mov dl, CPS_READY
    call cps_set_state
    xor ebx, 1
    mov [task_current], bl
    call task_activate
    mov rsp, [task_rsp+rbx*8]
.return:
    RESTORE_REGS
    iretq

; EBX=selected slot. All task address spaces share only supervisor mappings.
task_activate:
    mov rax, [task_cr3+rbx*8]
    mov cr3, rax
    test ebx, ebx
    jnz .second
    mov qword [tss+4], tss_stack_0_end
    ret
.second:
    mov qword [tss+4], tss_stack_1_end
    ret

; Two built-in tasks, each with private page tables and code/stack frames.
multi_launch:
    cmp byte [user_ready], 1
    jne .error
    mov rdi, [task_code]
    mov rsi, app_multi0
    mov ecx, app_multi0_end-app_multi0
    rep movsb
    mov rdi, [task_code+8]
    cmp byte [multi_fault_variant], 1
    je .fault_image
    mov rsi, app_multi1
    mov ecx, app_multi1_end-app_multi1
    jmp .copy_second
.fault_image:
    mov rsi, app_fault
    mov ecx, app_fault_end-app_fault
.copy_second:
    rep movsb
    xor ebx, ebx
    call clear_user_slot
    mov ebx, 1
    call clear_user_slot
    mov byte [task_state], 1
    mov byte [task_state+1], 1
    xor ebx, ebx
    mov rdi, cps_multi_root_name
    mov dl, CPS_RUNNING
    call cps_register
    mov ebx, 1
    mov rdi, cps_multi_alice_name
    mov dl, CPS_READY
    call cps_register
    mov byte [cps_single_active], 0
    mov byte [cps_table+CPS_ENTRY_SIZE+CPS_STATE], CPS_BLOCKED
    mov byte [multi_active], 1
    mov dword [switch_count], 0
    mov qword [task_results], 0
    mov qword [task_results+8], 0
    mov [resume_sp], rsp
    mov rdi, tss_stack_1_end-40
    mov qword [rdi], USER_BASE
    mov qword [rdi+8], 0x1b
    mov qword [rdi+16], 0x202
    mov qword [rdi+24], USER_BASE+0x5000
    mov qword [rdi+32], 0x23
    sub rdi, 120
    mov [task_rsp+8], rdi
    mov ecx, 15
    xor eax, eax
    rep stosq                   ; mistaken direction? RDI initial saved below
    mov byte [task_current], 0
    xor ebx, ebx
    call task_activate
    mov ax, 0x23
    mov ds, ax
    mov es, ax
    push qword 0x23
    push qword USER_BASE+0x5000
    pushfq
    push qword 0x1b
    push qword USER_BASE
    iretq
.error:
    mov eax, 1
    ret

; Called by user syscall exit or exception. Resume another runnable task.
task_finish:
    call cps_finish_current
    cmp byte [multi_active], 1
    jne user_resume
    movzx ebx, byte [task_current]
    mov rax, [user_result]
    mov [task_results+rbx*8], rax
    mov byte [task_state+rbx], 0
    xor ebx, 1
    cmp byte [task_state+rbx], 1
    jne .all_done
    mov [task_current], bl
    mov dl, CPS_RUNNING
    call cps_set_state
    call task_activate
    mov rsp, [task_rsp+rbx*8]
    RESTORE_REGS
    iretq
.all_done:
    mov byte [multi_active], 0
    jmp user_resume

cps_sys_yield:
    xor eax, eax
    cmp byte [multi_active], 1
    jne .return_direct
    SAVE_REGS
    movzx ebx, byte [task_current]
    mov [task_rsp+rbx*8], rsp
    xor ebx, 1
    cmp byte [task_state+rbx], 1
    jne .return_saved
    mov dl, CPS_RUNNING
    call cps_set_state
    xor ebx, 1
    mov dl, CPS_READY
    call cps_set_state
    xor ebx, 1
    mov [task_current], bl
    inc dword [switch_count]
    call task_activate
    mov rsp, [task_rsp+rbx*8]
.return_saved:
    RESTORE_REGS
    iretq
.return_direct:
    iretq

app_multi0:
    mov rax, USER_BASE+0x2000
    mov dword [rax], 111
    mov ecx, 40000000
.spin:
    dec ecx
    jnz .spin
    cmp dword [rax], 111
    jne .corrupt
    mov eax, 1
    lea rdi, [rel .msg]
    mov esi, .end-.msg
    int 0x80
    xor eax, eax
    mov edi, 11
    int 0x80
.corrupt:
    xor eax, eax
    mov edi, 99
    int 0x80
.msg db 'tarea root completada',10
.end:
app_multi0_end:
app_multi1:
    mov rax, USER_BASE+0x2000
    mov dword [rax], 222
    mov ecx, 40000000
.spin:
    dec ecx
    jnz .spin
    cmp dword [rax], 222
    jne .corrupt
    mov eax, 1
    lea rdi, [rel .msg]
    mov esi, .end-.msg
    int 0x80
    xor eax, eax
    mov edi, 22
    int 0x80
.corrupt:
    xor eax, eax
    mov edi, 99
    int 0x80
.msg db 'tarea alice completada',10
.end:
app_multi1_end:

pit_ticks: dd 0
switch_count: dd 0
multi_active: db 0
multi_fault_variant: db 0
task_state: db 0,0
task_rsp: dq 0,0
task_results: dq 0,0
align 16
tss_stack_0: times 8192 db 0
tss_stack_0_end:
tss_stack_1: times 8192 db 0
tss_stack_1_end:
