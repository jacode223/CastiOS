; Minimal credentials and Unix-style owner/group/other permission checks.
; The privileged shell assigns immutable identities to built-in task slots.
task_uids: dd 0, 1000
task_gids: dd 0, 100
; EDI owner UID, ESI owning GID, EDX mode, ECX requested rwx bit.
; EAX=1 allowed, zero denied. Root bypasses DAC in this preview.
permission_check:
    movzx eax, byte [task_current]
    mov r8d, [task_uids+rax*4]
    test r8d, r8d
    jz .allow
    cmp r8d, edi
    je .owner
    mov r8d, [task_gids+rax*4]
    cmp r8d, esi
    je .group
    and edx, 7
    jmp .result
.owner:
    shr edx, 6
    and edx, 7
    jmp .result
.group:
    shr edx, 3
    and edx, 7
.result:
    and edx, ecx
    setnz al
    movzx eax, al
    ret
.allow:
    mov eax, 1
    ret
