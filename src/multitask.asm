; Up to four foreground AX05 processes, preempted by PIT IRQ0.
%define MT_MAX 4
%define MT_SIZE 56
%define MT_PD 0
%define MT_PT 4
%define MT_CODE 8
%define MT_STACK 12
%define MT_KSTACK 16
%define MT_ESP 20
%define MT_STATE 24
%define MT_RESULT 28
%define MT_SWITCHES 32
%define MT_SWAP 36
%define MT_SAVED 40
%define MT_WAKE 44
%define MT_CAP 48
%define MT_PID 52
mt_pid_current:
    imul eax, MT_SIZE
    mov eax, [mt_table+eax+MT_PID]
    ret
cmd_run2:
    cmp byte [mt_active], 0
    jne .busy
    mov dword [mt_parsed], 0
    mov esi, [args]
    call spaces
    mov edi, mt_names
    mov ecx, MT_MAX
.names:
    xor ebx, ebx
.word:
    lodsb
    test al, al
    jz .nul
    cmp al, ' '
    je .word_end
    cmp ebx, 127
    jae .bad
    stosb
    inc ebx
    jmp .word
.nul:
    dec esi
.word_end:
    test ebx, ebx
    jz .bad
    mov byte [edi], 0
    add edi, 128
    sub edi, ebx
    call spaces
    inc dword [mt_parsed]
    cmp byte [esi], 0
    je .parsed
    dec ecx
    jnz .names
    jmp .bad
.parsed:
    cmp dword [mt_parsed], 2
    jb .bad
    cmp byte [esi], 0
    jne .bad
    mov dword [mt_count], 0
    mov dword [mt_current], 0
    mov dword [mt_switch_total], 0
    mov edi, mt_table
    xor eax, eax
    mov ecx, MT_SIZE*MT_MAX/4
    rep stosd
.load:
    mov eax, [mt_count]
    mov [mt_load_slot], eax
    mov esi, eax
    shl esi, 7
    add esi, mt_names
    call mt_load
    jc .failed
    mov eax, [mt_count]
    cmp eax, [mt_parsed]
    jb .load
    call process_init_tss
    mov [mt_kernel_sp], esp
    mov byte [mt_active], 1
    mov eax, [mt_table+MT_KSTACK]
    add eax, 4096
    mov [process_tss+4], eax
    mov eax, [mt_table+MT_PD]
    mov cr3, eax
    mov esp, [mt_table+MT_ESP]
    popad
    add esp, 4
    iretd
.resume:
    call mt_release
    mov esi, mt_done
    call puts
    mov eax, [mt_switch_total]
    call number
    call nl
    xor ebp, ebp
.results:
    mov esi, mt_proc
    call puts
    mov eax, ebp
    inc eax
    call number
    mov esi, mt_eax
    call puts
    mov ebx, ebp
    imul ebx, MT_SIZE
    mov eax, [mt_table+ebx+MT_RESULT]
    call number
    call nl
    inc ebp
    cmp ebp, [mt_parsed]
    jb .results
    ret
.failed:
    call mt_release
.bad:
    mov esi, mt_usage
    jmp puts
.busy:
    mov esi, mt_foreground_busy
    jmp puts
; ESI name, load and validate same AX05 format as run.
mt_load:
    mov eax, [mt_load_slot]
    mov dword [sys_fd_head+eax*4+4], 0
    mov dword [sys_fd_pos+eax*4+4], 0
    mov [args], esi
    call filename
    jc .bad
    call findfile
    jc .bad
    cmp dword [edi+RKIND], 3
    jne .bad
    cmp dword [edi+RDATA], 'AX05'
    jne .bad
    mov ecx, [edi+RDATA+4]
    cmp ecx, 3992
    ja .bad
    lea eax, [ecx+8]
    cmp eax, [edi+RLEN]
    jne .bad
    lea esi, [edi+RDATA+8]
    call validate_code
    jc .bad
    mov ebx, [mt_load_slot]
    imul ebx, MT_SIZE
    add ebx, mt_table
    mov eax, [edi+56]
    and eax, 1
    mov [ebx+MT_CAP], eax
    mov [mt_source], esi
    mov [mt_length], ecx
    xor ebp, ebp
.alloc:
    call alloc_page
    test eax, eax
    jz .bad
    mov [ebx+ebp*4], eax
    inc ebp
    cmp ebp, 5
    jb .alloc
    mov esi, PAGE_DIR
    mov edi, [ebx+MT_PD]
    mov ecx, 1024
    rep movsd
    mov edi, [ebx+MT_PT]
    mov eax, [ebx+MT_CODE]
    or eax, 5                  ; code is user read-only
    mov [edi], eax
    mov eax, [ebx+MT_STACK]
    or eax, 7
    mov [edi+8], eax
    mov eax, [ebx+MT_PT]
    or eax, 7
    mov edi, [ebx+MT_PD]
    mov [edi+128*4], eax
    mov esi, [mt_source]
    mov edi, [ebx+MT_CODE]
    mov ecx, [mt_length]
    rep movsb
    mov word [edi], 0xc389   ; mov ebx,eax
    mov byte [edi+2], 0xb8
    mov dword [edi+3], 1
    mov word [edi+7], 0x80cd
    mov eax, [ebx+MT_STACK]
    mov edx, [mt_length]
    add edx, USER_BASE
    mov [eax+4092], edx
    mov edi, [ebx+MT_KSTACK]
    add edi, 4096
%macro MT_PUSH 1
    sub edi, 4
    mov dword [edi], %1
%endmacro
    MT_PUSH 35
    MT_PUSH USER_BASE+0x2ffc
    MT_PUSH 0x202
    MT_PUSH 27
    MT_PUSH USER_BASE
    MT_PUSH 0
%rep 8
    MT_PUSH 0
%endrep
    mov [ebx+MT_ESP], edi
    mov dword [ebx+MT_STATE], 1
    mov eax, [mt_load_slot]
    cmp eax, [mt_count]
    jb .loaded
    inc dword [mt_count]
.loaded:
    clc
    ret
.bad:
    stc
    ret
mt_schedule:
    cmp byte [mt_active], 2
    je mt_bg_schedule
    cmp byte [mt_active], 1
    jne .same
    cmp dword [esp+4+32], 0 ; caller return address precedes irq number
    jne .same
    test byte [esp+4+40], 3 ; CS after pushad + IRQ + EIP
    jz .same
    jmp mt_switch
.same:
    lea eax, [esp+4]
    ret
mt_switch:
    mov ebx, [mt_current]
    imul ebx, MT_SIZE
    add ebx, mt_table
    lea eax, [esp+4]
    mov [ebx+MT_ESP], eax
    call mt_next
    jc .same
    cmp eax, [mt_current]
    je .same
    mov [mt_current], eax
    inc dword [mt_switch_total]
    mov eax, [edx+MT_KSTACK]
    add eax, 4096
    mov [process_tss+4], eax
    mov eax, [edx+MT_PD]
    mov cr3, eax
    mov eax, [edx+MT_ESP]
    ret
.same:
    lea eax, [esp+4]
    ret
; Finds the next runnable task, circular order. CF=1 if none.
mt_next:
    push ebx
    mov eax, [mt_current]
    mov ecx, [mt_count]
.scan:
    inc eax
    cmp eax, [mt_count]
    jb .slot
    xor eax, eax
.slot:
    mov edx, eax
    imul edx, MT_SIZE
    add edx, mt_table
    cmp dword [edx+MT_STATE], 3
    jne .check
    mov ebx, [ticks]
    sub ebx, [edx+MT_WAKE]
    js .check
    mov dword [edx+MT_STATE], 1
.check:
    cmp dword [edx+MT_STATE], 1
    je .found
    loop .scan
    pop ebx
    stc
    ret
.found:
    pop ebx
    clc
    ret
mt_syscall:
    cmp eax, 1
    je .exit
    cmp eax, 2
    je .yield
    cmp eax, 18
    je .sleep
    pushad
    call syscall_service
    mov [esp+28], eax
    popad
    iretd
.yield:
    push dword 0
    pushad
    mov dword [esp+28], 0       ; return value of yield
    cmp byte [mt_active], 2
    je .background_yield
    call mt_switch
    jmp .resume
.background_yield:
    mov ebx, [mt_current]
    imul ebx, MT_SIZE
    add ebx, mt_table
    mov [ebx+MT_ESP], esp
    call mt_bg_back
.resume:
    mov esp, eax
    popad
    add esp, 4
    iretd
.sleep:
    cmp byte [mt_active], 2
    jne .sleep_unsupported
    cmp ebx, 1
    jb .sleep_invalid
    cmp ebx, 10000
    ja .sleep_invalid
    push dword 0
    pushad
    mov dword [esp+28], 0
    mov ebx, [mt_current]
    imul ebx, MT_SIZE
    add ebx, mt_table
    mov [ebx+MT_ESP], esp
    mov eax, [ticks]
    add eax, [esp+16]          ; original EBX: duration
    mov [ebx+MT_WAKE], eax
    mov dword [ebx+MT_STATE], 3
    call mt_bg_back
    jmp .resume
.sleep_unsupported:
    mov eax, -38
    iretd
.sleep_invalid:
    mov eax, -22
    iretd
.exit:
    mov eax, ebx
    jmp mt_exit
mt_fault:
    mov eax, 0xfffffffe
mt_exit:
    cli
    mov ebx, [mt_current]
    imul ebx, MT_SIZE
    add ebx, mt_table
    mov [ebx+MT_RESULT], eax
    mov dword [ebx+MT_STATE], 2
    mov ebx, [mt_current]
    inc ebx
    mov dword [sys_fd_head+ebx*4], 0
    mov dword [sys_fd_pos+ebx*4], 0
    cmp byte [mt_active], 2
    je mt_bg_return
    call mt_next
    jc .all_done
    mov [mt_current], eax
    mov eax, [edx+MT_KSTACK]
    add eax, 4096
    mov [process_tss+4], eax
    mov eax, [edx+MT_PD]
    mov cr3, eax
    mov esp, [edx+MT_ESP]
    popad
    add esp, 4
    iretd
.all_done:
    mov eax, PAGE_DIR
    mov cr3, eax
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov byte [mt_active], 0
    mov esp, [mt_kernel_sp]
    sti
    jmp cmd_run2.resume
mt_release:
    mov ebx, mt_table
    mov ebp, MT_MAX
.job:
    push ebx
    mov edi, [ebx+MT_PT]
    test edi, edi
    jz .no_demand
    call demand_release_pt
.no_demand:
    pop ebx
    mov eax, [ebx+MT_SWAP]
    test eax, eax
    jz .page_start
    call free_page
    mov dword [ebx+MT_SWAP], 0
.page_start:
    xor esi, esi
.page:
    mov eax, [ebx+esi*4]
    test eax, eax
    jz .next
    call free_page
    mov dword [ebx+esi*4], 0
.next:
    inc esi
    cmp esi, 5
    jb .page
    add ebx, MT_SIZE
    dec ebp
    jnz .job
    ret
; Background shell is the fifth scheduling context (current = -1).
cmd_bg:
    cmp byte [mt_active], 1
    je .busy
    mov esi, [args]
    call spaces
    test byte [esi], 0xff
    jz .busy
    cli
    cmp byte [mt_active], 2
    je .existing
    mov dword [mt_count], 0
    mov dword [mt_bg_cursor], 0xffffffff
    mov edi, mt_table
    xor eax, eax
    mov ecx, MT_SIZE*MT_MAX/4
    rep stosd
.existing:
    xor ebp, ebp
.find_slot:
    cmp ebp, [mt_count]
    jae .append
    mov eax, ebp
    imul eax, MT_SIZE
    cmp dword [mt_table+eax+MT_STATE], 0
    je .slot
    inc ebp
    jmp .find_slot
.append:
    cmp ebp, MT_MAX
    jae .full
.slot:
    mov [mt_load_slot], ebp
    mov esi, [args]
    call mt_load
    jc .failed
    inc dword [mt_pid_next]
    cmp dword [mt_pid_next], 1000000
    jb .pid_ok
    mov dword [mt_pid_next], 1
.pid_ok:
    mov ebx, [mt_load_slot]
    imul ebx, MT_SIZE
    mov eax, [mt_pid_next]
    mov [mt_table+ebx+MT_PID], eax
    call process_init_tss
    mov byte [mt_active], 2
    sti
    mov esi, mt_started
    call puts
    mov eax, [mt_pid_next]
    call number
    jmp nl
.full:
    sti
.busy:
    mov esi, mt_bg_busy
    jmp puts
.failed:
    mov ebx, [mt_load_slot]
    imul ebx, MT_SIZE
    add ebx, mt_table
    xor ebp, ebp
.cleanup:
    mov eax, [ebx+ebp*4]
    test eax, eax
    jz .cleanup_next
    call free_page
    mov dword [ebx+ebp*4], 0
.cleanup_next:
    inc ebp
    cmp ebp, 5
    jb .cleanup
    mov eax, [ebx+MT_SWAP]
    test eax, eax
    jz .cleanup_done
    call free_page
    mov dword [ebx+MT_SWAP], 0
.cleanup_done:
    sti
    mov esi, mt_usage_bg
    jmp puts
cmd_ps:
    cmp byte [mt_active], 2
    jne .empty
    xor ebp, ebp
.show:
    mov ebx, ebp
    imul ebx, MT_SIZE
    add ebx, mt_table
    cmp dword [ebx+MT_STATE], 0
    je .next
    mov esi, mt_proc
    call puts
    mov eax, [ebx+MT_PID]
    call number
    mov esi, mt_running
    cmp dword [ebx+MT_STATE], 1
    je .print
    cmp dword [ebx+MT_STATE], 3
    je .sleeping
    mov esi, mt_finished
.sleeping:
    cmp dword [ebx+MT_STATE], 3
    jne .print
    mov esi, mt_sleeping
.print:
    call puts
    cmp dword [ebx+MT_STATE], 2
    jne .next
    mov eax, [ebx+MT_RESULT]
    call number
    call nl
.next:
    inc ebp
    cmp ebp, [mt_count]
    jb .show
    ret
.empty:
    mov esi, mt_none
    jmp puts
; Shell is the only caller: stop a background task and reclaim its pages.
; The result remains visible until wait reaps the group.
cmd_kill:
    cmp byte [mt_active], 2
    jne .empty
    mov esi, [args]
    call mt_parse_pid
    jc .usage
    cli
    call mt_lookup_pid
    jc .notfound
    mov eax, [ebx+MT_STATE]
    cmp eax, 1
    je .stop
    cmp eax, 3
    jne .finished
.stop:
    mov dword [ebx+MT_STATE], 2
    mov dword [ebx+MT_RESULT], 143
    mov eax, ebp
    inc eax
    mov dword [sys_fd_head+eax*4], 0
    mov dword [sys_fd_pos+eax*4], 0
    call mt_release_slot
    sti
    mov esi, mt_killed
    call puts
    mov eax, [ebx+MT_PID]
    call number
    jmp nl
.finished:
    sti
    mov esi, mt_already_done
    jmp puts
.notfound:
    sti
    jmp .usage
.usage:
    mov esi, mt_kill_usage
    jmp puts
.empty:
    mov esi, mt_none
    jmp puts
cmd_waitbg:
    cmp byte [mt_active], 2
    jne cmd_ps.empty
    mov esi, [args]
    call spaces
    cmp byte [esi], 0
    je .wait
    call mt_parse_pid
    jc .usage
    mov [mt_wait_pid], eax
.one:
    cli
    mov eax, [mt_wait_pid]
    call mt_lookup_pid
    jc .notfound
    cmp dword [ebx+MT_STATE], 2
    je .reap
    sti
    hlt
    jmp .one
.reap:
    push ebx
    mov esi, mt_proc
    call puts
    mov eax, [mt_wait_pid]
    call number
    mov esi, mt_eax
    call puts
    pop ebx
    mov eax, [ebx+MT_RESULT]
    call number
    call nl
    call mt_release_slot
    mov dword [ebx+MT_STATE], 0
    mov dword [ebx+MT_PID], 0
    ; If no live or completed jobs remain, close the group.
    xor ebp, ebp
.remaining:
    cmp ebp, [mt_count]
    jae .last
    mov eax, ebp
    imul eax, MT_SIZE
    cmp dword [mt_table+eax+MT_STATE], 0
    jne .one_done
    inc ebp
    jmp .remaining
.last:
    mov byte [mt_active], 0
    mov dword [mt_count], 0
.one_done:
    sti
    ret
.notfound:
    sti
.usage:
    mov esi, mt_wait_usage
    jmp puts
.wait:
    cli
    xor ebx, ebx
    mov ecx, [mt_count]
    mov esi, mt_table
.scan:
    cmp dword [esi+MT_STATE], 1
    je .running
    cmp dword [esi+MT_STATE], 3
    jne .next
.running:
    inc ebx
.next:
    add esi, MT_SIZE
    loop .scan
    test ebx, ebx
    jz .done
    sti
    hlt
    jmp .wait
.done:
    sti
    call cmd_ps
    call mt_release
    mov byte [mt_active], 0
    mov dword [mt_count], 0
    ret
mt_bg_schedule:
    cmp dword [esp+4+32], 0
    jne mt_schedule.same
    test byte [esp+4+40], 3
    jnz .user
    lea eax, [esp+4]
    mov [mt_shell_sp], eax
    mov eax, [mt_bg_cursor]
    mov [mt_current], eax
    call mt_next
    jc mt_schedule.same
    mov [mt_current], eax
    mov eax, [edx+MT_KSTACK]
    add eax, 4096
    mov [process_tss+4], eax
    mov eax, [edx+MT_PD]
    mov cr3, eax
    mov eax, [edx+MT_ESP]
    ret
.user:
    mov ebx, [mt_current]
    imul ebx, MT_SIZE
    add ebx, mt_table
    lea eax, [esp+4]
    mov [ebx+MT_ESP], eax
    jmp mt_bg_back
mt_bg_return:
    mov eax, [mt_current]
    mov [mt_bg_cursor], eax
    mov dword [mt_current], 0xffffffff
    mov eax, PAGE_DIR
    mov cr3, eax
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, [mt_shell_sp]
    ; Current task's stack and CR3 are no longer active. Reclaim now,
    ; including pages allocated lazily and the optional swap page.
    mov ebx, [mt_bg_cursor]
    imul ebx, MT_SIZE
    add ebx, mt_table
    call mt_release_slot
    popad
    add esp, 4
    iretd
mt_bg_back:
    mov eax, [mt_current]
    mov [mt_bg_cursor], eax
    mov dword [mt_current], 0xffffffff
    mov eax, PAGE_DIR
    mov cr3, eax
    mov eax, [mt_shell_sp]
    ret
; ESI=ASCII PID; EAX=positive PID, CF clear only on an exact decimal value.
mt_parse_pid:
    call spaces
    xor eax, eax
    xor ecx, ecx
.digit:
    movzx edx, byte [esi]
    cmp dl, '0'
    jb .end
    cmp dl, '9'
    ja .end
    sub edx, '0'
    cmp eax, 99999
    ja .bad
    imul eax, eax, 10
    add eax, edx
    inc ecx
    inc esi
    jmp .digit
.end:
    test ecx, ecx
    jz .bad
    push eax
    call spaces
    cmp byte [esi], 0
    pop eax
    jne .bad
    test eax, eax
    jz .bad
    clc
    ret
.bad:
    stc
    ret
; EAX=PID; EBX=slot pointer, EBP=slot index, CF clear if found.
mt_lookup_pid:
    xor ebp, ebp
.scan:
    cmp ebp, [mt_count]
    jae .missing
    mov ebx, ebp
    imul ebx, MT_SIZE
    add ebx, mt_table
    cmp dword [ebx+MT_STATE], 0
    je .next
    cmp eax, [ebx+MT_PID]
    je .found
.next:
    inc ebp
    jmp .scan
.found:
    clc
    ret
.missing:
    stc
    ret
mt_release_slot:
    mov edi, [ebx+MT_PT]
    test edi, edi
    jz .no_demand
    call demand_release_pt
.no_demand:
    mov eax, [ebx+MT_SWAP]
    test eax, eax
    jz .base
    call free_page
    mov dword [ebx+MT_SWAP], 0
.base:
    xor esi, esi
.next:
    mov eax, [ebx+esi*4]
    test eax, eax
    jz .skip
    call free_page
    mov dword [ebx+esi*4], 0
.skip:
    inc esi
    cmp esi, 5
    jb .next
    mov dword [ebx+MT_SAVED], 0
    ret
mt_active db 0
align 4
mt_count dd 0
mt_load_slot dd 0
mt_pid_next dd 0
mt_wait_pid dd 0
mt_parsed dd 0
mt_current dd 0
mt_kernel_sp dd 0
mt_source dd 0
mt_length dd 0
mt_switch_total dd 0
mt_shell_sp dd 0
mt_bg_cursor dd 0
mt_table times MT_SIZE*MT_MAX db 0
mt_names times 128*MT_MAX db 0
mt_usage db 'Uso: run2 A.app B.app [C.app D.app] (2-4 procesos CPL3).',10,0
mt_foreground_busy db 'Usa waitbg antes de ejecutar run2.',10,0
mt_done db 'Planificador: cambios de contexto=',0
mt_proc db 'Proceso ',0
mt_eax db ' EAX=',0
mt_started db 'Proceso de fondo iniciado: ',0
mt_running db ' ejecutando',10,0
mt_sleeping db ' durmiendo',10,0
mt_finished db ' terminado EAX=',0
mt_none db 'Sin procesos de fondo.',10,0
mt_bg_busy db 'No hay ranuras libres o hay ejecucion en primer plano.',10,0
mt_usage_bg db 'Uso: bg ARCHIVO.app (AX05 valido).',10,0
mt_kill_usage db 'Uso: kill PID (tarea bg activa).',10,0
mt_wait_usage db 'Uso: wait [PID] (tarea bg existente).',10,0
mt_killed db 'Proceso detenido: ',0
mt_already_done db 'El proceso ya termino.',10,0
