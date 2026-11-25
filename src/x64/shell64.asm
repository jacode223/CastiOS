; Shell descriptors: name, prompt and command-filter hook. The registered
; implementations are kernel-linked; none is a separately loaded process.
SHELL64_COUNT equ 2
SHELL64_ENTRY equ 24
shell64_prompt:
    movzx eax, byte [shell64_current]
    imul eax, SHELL64_ENTRY
    mov rsi, [shell64_table+rax+8]
    jmp puts

; 0 = continue to common command handlers, 1 = handled/denied.
shell64_dispatch:
    mov rdi, shell64_command
    call cmd_prefix
    jnz .module
    cmp byte [rsi], 0
    je .list
    mov rdi, shell64_run_prefix
    call shell64_subcommand
    jz .run_external
    mov rdi, shell64_new_prefix
    call shell64_subcommand
    jz .new_external
    mov rdi, shell64_list
    call streq
    jz .list
    mov rdi, shell64_classic
    call streq
    jz .classic
    mov rdi, shell64_rescue
    call streq
    jz .rescue
    mov rsi, shell64_usage
    call puts
    mov eax, 1
    ret
.run_external:
    call shell_ext_run
    mov eax, 1
    ret
.new_external:
    call shell_ext_new
    mov eax, 1
    ret
.classic:
    mov byte [shell64_current], 0
    jmp .changed
.rescue:
    mov byte [shell64_current], 1
.changed:
    mov rsi, shell64_changed
    call puts
    mov eax, 1
    ret
.list:
    mov rsi, shell64_options
    call puts
    mov eax, 1
    ret
.module:
    movzx eax, byte [shell64_current]
    imul eax, SHELL64_ENTRY
    call [shell64_table+rax+16]
    ret

shell64_allow:
    xor eax, eax
    ret
; Recovery mode provides a conservative command set; this is a UI policy,
; not an isolation or security boundary, and the user can switch back.
shell64_filter_rescue:
    cmp byte [line], 0
    je shell64_allow
    mov rbx, shell64_safe_commands
.check:
    mov rdi, [rbx]
    test rdi, rdi
    jz .deny
    call cmd_prefix
    jz shell64_allow
    add rbx, 8
    jmp .check
.deny:
    mov rsi, shell64_denied
    call puts
    mov eax, 1
    ret

align 8
shell64_table:
    dq shell64_classic, prompt, shell64_allow
    dq shell64_rescue, shell64_rescue_prompt, shell64_filter_rescue
shell64_safe_commands:
    dq help_cmd, uname_cmd, mem_cmd, disks_cmd, ps_cmd, mount_cmd
    dq ls_cmd, cat_cmd, pwd_cmd, cd_cmd, stat_cmd, reboot_cmd, halt_cmd
    dq 0
shell64_current db 0
shell64_command db 'shell',0
shell64_list db 'list',0
shell64_classic db 'classic',0
shell64_rescue db 'rescue',0
shell64_rescue_prompt db 'rescue> ',0
shell64_options db 'Shells disponibles: classic, rescue',10,0
shell64_changed db 'Shell cambiada para esta sesion',10,0
shell64_usage db 'Uso: shell [list|classic|rescue|new RUTA|run RUTA]',10,0
shell64_denied db 'Comando no disponible en rescue; usa shell classic',10,0

; RSI=arguments after shell, RDI=subcommand. ZF if token and path supplied.
shell64_subcommand:
    push rsi
.next:
    mov al, [rdi]
    test al, al
    jz .end
    cmp al, [rsi]
    jne .fail
    inc rdi
    inc rsi
    jmp .next
.end:
    cmp byte [rsi], ' '
    jne .fail
.skip:
    inc rsi
    cmp byte [rsi], ' '
    je .skip
    cmp byte [rsi], 0
    je .fail
    add rsp, 8
    xor eax, eax
    ret
.fail:
    pop rsi
    mov eax, 1
    test eax, eax
    ret
shell64_run_prefix db 'run',0
shell64_new_prefix db 'new',0
