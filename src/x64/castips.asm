; CastiPS 0.1 - process metadata and integration with the existing x64 scheduler.
; An initial 32-record PCB table with TWO runnable CPL3 slots, NOT 32 processes.
; One kernel shell (PID 1) and idle descriptor (PID 0). Fixed-structure, no heap.
;
; PCB layout (64 bytes each): pid/ppid/uid/gid u32, state u8,
; exit_status i32, cpu_ticks u32, name[24]. Remaining bytes reserved.
; State transitions: READY -> RUNNING -> READY | ZOMBIE.
; The shell is BLOCKED while a foreground task runs. The kernel shell isn't
; a separate schedulable CPL3 task. External shell programs run foreground.
cps_init:
    ; Entries start zeroed as part of the kernel image.
    mov dword [cps_table+CPS_PID], 0
    mov byte [cps_table+CPS_STATE], CPS_BLOCKED
    mov rsi, cps_idle_name
    lea rdi, [rel cps_table+CPS_NAME]
    call cps_copy_name
    mov dword [cps_table+CPS_ENTRY_SIZE+CPS_PID], 1
    mov byte [cps_table+CPS_ENTRY_SIZE+CPS_STATE], CPS_RUNNING
    mov rsi, cps_shell_name
    lea rdi, [rel cps_table+CPS_ENTRY_SIZE+CPS_NAME]
    call cps_copy_name
    mov dword [cps_next_pid], 2
    ret

; Copy at most 23 bytes including a NUL terminator into a name[24] field.
; RDI=destination, RSI=source. Does not overwrite the next PCB.
cps_copy_name:
    mov ecx, CPS_NAME_CAP-1
.loop:
    mov al, [rsi]
    test al, al
    jz .end
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .loop
.end:
    mov byte [rdi], 0
    ret

; EBX = user task slot (0 or 1), RDI = process name, DL = initial state.
; Preserves all registers; records PPID 1 (shell), immutable UID/GID.
cps_register:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    movzx r8d, bl
    add r8d, CPS_USER_BASE_SLOT
    shl r8d, 6
    lea r9, [rel cps_table]
    add r9, r8
    mov rdi, r9
    mov ecx, CPS_ENTRY_SIZE/8
    xor eax, eax
    rep stosq
    mov eax, [cps_next_pid]
    mov [r9+CPS_PID], eax
    inc dword [cps_next_pid]
    cmp dword [cps_next_pid], 2
    jae .pid_ok
    mov dword [cps_next_pid], 2
.pid_ok:
    mov dword [r9+CPS_PPID], 1
    mov eax, [task_uids+rbx*4]
    mov [r9+CPS_UID], eax
    mov eax, [task_gids+rbx*4]
    mov [r9+CPS_GID], eax
    mov byte [r9+CPS_STATE], dl
    ; Stack (top first): r9,r8,rsi,rdi,rdx,rcx,rbx,rax.
    ; Original RDI (name) is at rsp+24.
    mov rsi, [rsp+24]
    lea rdi, [r9+CPS_NAME]
    call cps_copy_name
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; EBX=user task slot, DL=new state. RAX, RCX, RDX clobbered.
cps_set_state:
    movzx eax, bl
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    lea rcx, [rel cps_table]
    add rcx, rax
    mov byte [rcx+CPS_STATE], dl
    ret

; Called by timer IRQ with all user registers already saved.
cps_tick_current:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    lea rcx, [rel cps_table]
    add rcx, rax
    inc dword [rcx+CPS_TICKS]
    ret

; Mark current process as zombie, retain status and counters for ps/reap.
cps_finish_current:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    lea rcx, [rel cps_table]
    add rcx, rax
    mov byte [rcx+CPS_STATE], CPS_ZOMBIE
    mov eax, [user_result]
    mov [rcx+CPS_EXIT], eax
    ret

cps_resume_shell:
    mov byte [cps_single_active], 0
    mov byte [cps_table+CPS_ENTRY_SIZE+CPS_STATE], CPS_RUNNING
    ret

; Syscall 20: return state of caller's own process (RDI=PID).
; Other processes are rejected; PID cannot be forged by a task.
cps_sys_procstate:
    movzx eax, byte [task_current]
    add eax, CPS_USER_BASE_SLOT
    shl eax, 6
    lea rdx, [cps_table+rax]
    mov eax, [rdx+CPS_PID]
    cmp rdi, rax
    jne .denied
    movzx eax, byte [rdx+CPS_STATE]
    ret
.denied:
    mov rax, -13
    ret

; Show only allocated PCBs, including completed tasks until reap/reuse.
cps_ps:
    push r12
    push r13
    mov rsi, cps_header
    call puts
    xor r12d, r12d
.loop:
    cmp r12d, CPS_MAX
    jae .done
    mov r13d, r12d
    shl r13d, 6
    lea rax, [rel cps_table]
    add r13, rax
    cmp byte [r13+CPS_STATE], CPS_FREE
    je .next
    mov rsi, cps_pid_label
    call puts
    mov eax, [r13+CPS_PID]
    call decimal
    mov rsi, cps_ppid_label
    call puts
    mov eax, [r13+CPS_PPID]
    call decimal
    mov rsi, cps_uid_label
    call puts
    mov eax, [r13+CPS_UID]
    call decimal
    mov rsi, cps_state_label
    call puts
    movzx eax, byte [r13+CPS_STATE]
    cmp eax, CPS_READY
    je .ready
    cmp eax, CPS_RUNNING
    je .running
    cmp eax, CPS_BLOCKED
    je .blocked
    mov rsi, cps_zombie_text
    jmp .show_state
.ready:
    mov rsi, cps_ready_text
    jmp .show_state
.running:
    mov rsi, cps_running_text
    jmp .show_state
.blocked:
    mov rsi, cps_blocked_text
.show_state:
    call puts
    mov rsi, cps_tick_label
    call puts
    mov eax, [r13+CPS_TICKS]
    call decimal
    mov rsi, cps_name_label
    call puts
    lea rsi, [r13+CPS_NAME]
    call puts
    cmp byte [r13+CPS_STATE], CPS_ZOMBIE
    jne .line_end
    mov rsi, cps_exit_label
    call puts
    mov eax, [r13+CPS_EXIT]
    test eax, eax
    jns .exit_positive
    push rax
    mov al, '-'
    call putc
    pop rax
    neg eax
.exit_positive:
    call decimal
.line_end:
    mov al, 10
    call putc
.next:
    inc r12d
    jmp .loop
.done:
    pop r13
    pop r12
    ret

; Reap completed foreground children (does not kill running processes).
cps_reap:
    xor ecx, ecx
    mov r8d, CPS_USER_BASE_SLOT
.loop:
    cmp r8d, CPS_MAX
    jae .done
    mov eax, r8d
    shl eax, 6
    lea rdx, [rel cps_table]
    add rdx, rax
    cmp byte [rdx+CPS_STATE], CPS_ZOMBIE
    jne .next
    mov byte [rdx+CPS_STATE], CPS_FREE
    mov dword [rdx+CPS_PID], 0
    inc ecx
.next:
    inc r8d
    jmp .loop
.done:
    mov rsi, cps_reap_label
    push rcx
    call puts
    pop rcx
    mov eax, ecx
    call decimal
    mov al, 10
    call putc
    ret

cps_pending_name: dq cps_shell_name
cps_single_active: db 0
cps_next_pid: dd 2
cps_idle_name: db 'idle',0
cps_shell_name: db 'shell64',0
cps_multi_root_name: db 'multi-root',0
cps_multi_alice_name: db 'multi-alice',0
cps_header: db 'CastiPS 0.1 - tabla PCB (32 reservados, 2 CPL3)',10,0
cps_pid_label: db 'PID=',0
cps_ppid_label: db ' PPID=',0
cps_uid_label: db ' UID=',0
cps_state_label: db ' STATE=',0
cps_tick_label: db ' TICKS=',0
cps_name_label: db ' NAME=',0
cps_exit_label: db ' EXIT=',0
cps_ready_text: db 'READY',0
cps_running_text: db 'RUNNING',0
cps_blocked_text: db 'BLOCKED',0
cps_zombie_text: db 'ZOMBIE',0
cps_reap_label: db 'CastiPS procesos recogidos: ',0
align 16
cps_table: times CPS_MAX*CPS_ENTRY_SIZE db 0
