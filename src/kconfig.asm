; Persistent editable kernel settings. Fixed HSFS root file, no code patching.
kconfig_find:
    mov edi, RECORDS
    mov ecx, NFILES
.scan:
    cmp byte [edi], 0
    je .next
    cmp dword [edi+RPARENT], ROOT_ID
    jne .next
    mov esi, kconfig_name
    call equal
    je .found
.next:
    add edi, RSIZE
    loop .scan
    stc
    ret
.found:
    clc
    ret
kconfig_load:
    call kconfig_find
    jc .none
    cmp dword [edi+RKIND], 1
    jne .invalid
    mov ecx, [edi+RLEN]
    cmp ecx, 12
    jb .invalid
    cmp ecx, 96
    ja .invalid
    lea esi, [edi+RDATA]
    lea ebx, [esi+ecx]
    mov edi, kcfg_prefix_color
    mov ecx, 6
    repe cmpsb
    jne .invalid
    mov edi, kcfg_cyan
    call kcfg_match_color
    jnc .cyan
    mov edi, kcfg_green
    call kcfg_match_color
    jnc .green
    mov edi, kcfg_white
    call kcfg_match_color
    jc .invalid
    mov dl, 15
    jmp .color_ok
.cyan:
    mov dl, 11
    jmp .color_ok
.green:
    mov dl, 10
.color_ok:
    lea eax, [esi+7]
    cmp eax, ebx
    ja .invalid
    mov edi, kcfg_prefix_prompt
    mov ecx, 7
    cmp ebx, esi
    jbe .invalid
    repe cmpsb
    jne .invalid
    mov edi, kcfg_temp_prompt
    xor ecx, ecx
.prompt:
    cmp esi, ebx
    jae .finish
    lodsb
    cmp al, 10
    je .newline
    cmp al, 32
    jb .invalid
    cmp al, 126
    ja .invalid
    cmp ecx, 23
    jae .invalid
    stosb
    inc ecx
    jmp .prompt
.newline:
    cmp esi, ebx
    jne .invalid
.finish:
    test ecx, ecx
    jz .invalid
    mov byte [edi], 0
    mov [color], dl
    mov esi, kcfg_temp_prompt
    mov edi, prompt
    call copy
    clc
    ret
.invalid:
    stc
    ret
.none:
    clc
    ret
; Compare newline-terminated color, advancing ESI on success.
kcfg_match_color:
    push esi
.char:
    mov al, [edi]
    test al, al
    jz .end
    cmp esi, ebx
    jae .no
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .char
.end:
    cmp esi, ebx
    jae .no
    cmp byte [esi], 10
    jne .no
    inc esi
    add esp, 4
    clc
    ret
.no:
    pop esi
    stc
    ret
cmd_kshow:
    mov esi, kcfg_show_color
    call puts
    mov esi, kcfg_cyan
    cmp byte [color], 11
    je .color
    mov esi, kcfg_green
    cmp byte [color], 10
    je .color
    mov esi, kcfg_white
.color:
    call puts
    call nl
    mov esi, kcfg_show_prompt
    call puts
    mov esi, prompt
    call puts
    call nl
    mov esi, kcfg_show_status
    cmp byte [persistent], 1
    je .status
    mov esi, kcfg_ram_status
.status:
    jmp puts
cmd_kreload:
    call kconfig_load
    jc .bad
    mov esi, kcfg_loaded
    jmp puts
.bad:
    mov esi, kcfg_invalid
    jmp puts
cmd_kset:
    cmp byte [persistent], 1
    jne .ram
    mov esi, [args]
    call spaces
    mov edi, kcfg_key_color
    call kcfg_key
    jnc .color
    mov edi, kcfg_key_prompt
    call kcfg_key
    jnc .prompt
    jmp .usage
.color:
    mov byte [kcfg_temp_prompt], 0
    mov edi, kcfg_cyan
    call equal
    je .cyan
    mov edi, kcfg_green
    call equal
    je .green
    mov edi, kcfg_white
    call equal
    jne .usage
    mov byte [kcfg_new_color], 15
    jmp .save
.cyan:
    mov byte [kcfg_new_color], 11
    jmp .save
.green:
    mov byte [kcfg_new_color], 10
    jmp .save
.prompt:
    mov edi, kcfg_temp_prompt
    xor ecx, ecx
.prompt_char:
    lodsb
    test al, al
    jz .prompt_end
    cmp al, 32
    jb .usage
    cmp al, 126
    ja .usage
    cmp ecx, 23
    jae .usage
    stosb
    inc ecx
    jmp .prompt_char
.prompt_end:
    test ecx, ecx
    jz .usage
    mov byte [edi], 0
    mov al, [color]
    mov [kcfg_new_color], al
    jmp .save
.save:
    ; Keep the old prompt if only the color is changed.
    cmp byte [kcfg_temp_prompt], 0
    jne .build
    mov esi, prompt
    mov edi, kcfg_temp_prompt
    call copy
.build:
    mov edi, kcfg_text
    mov esi, kcfg_prefix_color
    call kcfg_write_literal
    mov esi, kcfg_cyan
    cmp byte [kcfg_new_color], 11
    je .color_text
    mov esi, kcfg_green
    cmp byte [kcfg_new_color], 10
    je .color_text
    mov esi, kcfg_white
.color_text:
    call kcfg_write_literal
    mov byte [edi], 10
    inc edi
    mov esi, kcfg_prefix_prompt
    call kcfg_write_literal
    mov esi, kcfg_temp_prompt
    call kcfg_write_literal
    mov byte [edi], 10
    inc edi
    mov [kcfg_length], edi
    sub dword [kcfg_length], kcfg_text
    call kconfig_find
    jc .allocate
    cmp dword [edi+RKIND], 1
    jne .usage
    jmp .slot
.allocate:
    mov edi, RECORDS
    mov ecx, NFILES
.free:
    cmp byte [edi], 0
    je .create
    add edi, RSIZE
    loop .free
    mov esi, kcfg_full
    jmp puts
.create:
    push edi
    mov ecx, RSIZE/4
    xor eax, eax
    rep stosd
    pop edi
    mov esi, kconfig_name
    mov ebx, edi
    call copy
    mov edi, ebx
    mov dword [edi+RPARENT], ROOT_ID
    mov dword [edi+RKIND], 1
.slot:
    mov eax, [kcfg_length]
    mov [edi+RLEN], eax
    add edi, RDATA
    mov esi, kcfg_text
    mov ecx, eax
    rep movsb
    mov byte [edi], 0
    call sync
    call kconfig_load
    mov byte [kcfg_temp_prompt], 0
    ret
.ram:
    mov esi, kcfg_no_disk
    jmp puts
.usage:
    mov esi, kcfg_usage
    jmp puts
; ESI args; EDI key. On match, ESI points to value.
kcfg_key:
    push esi
.next:
    mov al, [edi]
    test al, al
    jz .space
    cmp al, [esi]
    jne .bad
    inc edi
    inc esi
    jmp .next
.space:
    cmp byte [esi], ' '
    jne .bad
    inc esi
    call spaces
    cmp byte [esi], 0
    je .bad
    add esp, 4
    clc
    ret
.bad:
    pop esi
    stc
    ret
kcfg_write_literal:
    lodsb
    test al, al
    jz .done
    stosb
    jmp kcfg_write_literal
.done:
    ret
kconfig_name db 'system.cfg',0
kcfg_prefix_color db 'color=',0
kcfg_prefix_prompt db 'prompt=',0
kcfg_key_color db 'color',0
kcfg_key_prompt db 'prompt',0
kcfg_cyan db 'cyan',0
kcfg_green db 'green',0
kcfg_white db 'white',0
kcfg_show_color db 'color=',0
kcfg_show_prompt db 'prompt=',0
kcfg_show_status db 'system.cfg persistente',10,0
kcfg_ram_status db 'sin disco persistente',10,0
kcfg_loaded db 'Configuracion aplicada.',10,0
kcfg_invalid db 'system.cfg invalido; cambios descartados.',10,0
kcfg_full db 'HSFS sin registros libres.',10,0
kcfg_no_disk db 'kset requiere HSFS persistente.',10,0
kcfg_usage db 'Uso: castctl kset color cyan|green|white | castctl kset prompt TEXTO',10,0
kcfg_temp_prompt times 32 db 0
kcfg_text times 96 db 0
kcfg_length dd 0
kcfg_new_color db 0
