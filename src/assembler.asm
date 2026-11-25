; Ensamblador reducido real x86. Sin etiquetas, memoria, saltos o macros.
; AX05: firma + longitud DWORD + instrucciones de EAX verificables.
%define ASMBUF 0x48000
cmd_asm:
    call filename
    jc badname
    mov [asm_output_arg], esi
    call findfile
    jc missing
    call require_text
    jc badname
    cmp dword [edi+RLEN], LIMIT
    ja toolong
    lea eax, [edi+RDATA]
    mov [asm_source], eax
    mov eax, [edi+RLEN]
    add eax, [asm_source]
    mov [asm_source_end], eax
    mov esi, [asm_output_arg]
    cmp byte [esi], 0
    je badname
    push dword [args]
    mov [args], esi
    call filename
    pop dword [args]
    jc badname
    cmp byte [esi], 0
    jne badname
    call getslot
    jc full
    cmp byte [edi], 0
    je .slot
    cmp dword [edi+RKIND], 2
    je badname
.slot:
    mov [asm_slot], edi
    mov edi, ASMBUF+8
    mov esi, [asm_source]
    mov dword [asm_line], 1
.line:
    cmp esi, [asm_source_end]
    jae .finish
    mov ebx, asm_text
    xor ecx, ecx
.read:
    cmp esi, [asm_source_end]
    jae .parse
    lodsb
    cmp al, 10
    je .parse
    cmp al, ';'
    je .comment
    cmp al, ' '
    je .read
    cmp al, 9
    je .read
    cmp al, 13
    je .read
    cmp al, 'A'
    jb .store
    cmp al, 'Z'
    ja .store
    add al, 32
.store:
    cmp ecx, 127
    jae .error
    mov [ebx+ecx], al
    inc ecx
    jmp .read
.comment:
    cmp esi, [asm_source_end]
    jae .parse
    lodsb
    cmp al, 10
    jne .comment
.parse:
    mov byte [ebx+ecx], 0
    push esi
    push edi
    mov esi, asm_text
    cmp byte [esi], 0
    je .skip
    mov edi, asm_bits
    call equal
    je .skip
    mov edi, asm_ret
    call equal
    je .ret
    mov edi, asm_inc
    call equal
    je .inc
    mov edi, asm_dec
    call equal
    je .dec
    mov edi, asm_nop
    call equal
    je .nop
    mov edi, asm_int80
    call equal
    je .int80
    mov edi, asm_xor
    call equal
    je .xor
    cmp dword [esi], 'move'
    je .mov
    cmp dword [esi], 'adde'
    je .add
    cmp dword [esi], 'sube'
    je .sub
    jmp .bad_parse
.mov:
    mov byte [asm_opcode], 0xb8
    cmp dword [esi+3], 'ebx,'
    jne .mov_ecx
    mov byte [asm_opcode], 0xbb
    jmp .immediate_register
.mov_ecx:
    cmp dword [esi+3], 'ecx,'
    jne .mov_edx
    mov byte [asm_opcode], 0xb9
    jmp .immediate_register
.mov_edx:
    cmp dword [esi+3], 'edx,'
    jne .immediate
    mov byte [asm_opcode], 0xba
    jmp .immediate_register
    jmp .immediate
.add:
    mov byte [asm_opcode], 0x05
    jmp .immediate
.sub:
    mov byte [asm_opcode], 0x2d
.immediate:
    cmp dword [esi+3], 'eax,'
    jne .bad_parse
.immediate_register:
    add esi, 7
    call parse_integer
    jc .bad_parse
    pop edi
    cmp edi, ASMBUF+4000-5
    ja .bad_emit
    mov dl, [asm_opcode]
    mov [edi], dl
    inc edi
    stosd
    jmp .next
.ret:
    mov al, 0xc3
    jmp .single
.inc:
    mov al, 0x40
    jmp .single
.dec:
    mov al, 0x48
    jmp .single
.nop:
    mov al, 0x90
.single:
    pop edi
    cmp edi, ASMBUF+4000
    jae .bad_emit
    stosb
    jmp .next
.int80:
    pop edi
    cmp edi, ASMBUF+4000-1
    jae .bad_emit
    mov ax, 0x80cd
    stosw
    jmp .next
.xor:
    pop edi
    cmp edi, ASMBUF+4000-1
    jae .bad_emit
    mov ax, 0xc031
    stosw
    jmp .next
.skip:
    pop edi
.next:
    pop esi
    inc dword [asm_line]
    jmp .line
.bad_parse:
    pop edi
.bad_emit:
    pop esi
.error:
    mov esi, asm_error
    call puts
    mov eax, [asm_line]
    call number
    jmp nl
.finish:
    cmp edi, ASMBUF+8
    je .error
    cmp byte [edi-1], 0xc3
    jne .error
    mov eax, edi
    sub eax, ASMBUF+8
    mov dword [ASMBUF], 'AX05'
    mov [ASMBUF+4], eax
    ; Valida el codigo tambien antes de guardar.
    mov esi, ASMBUF+8
    mov ecx, eax
    call validate_code
    jc .error
    mov edi, [asm_slot]
    call init_slot
    call free_extra
    mov dword [edi+RKIND], 3
    mov eax, [ASMBUF+4]
    add eax, 8
    mov [edi+RLEN], eax
    mov ecx, eax
    mov esi, ASMBUF
    add edi, RDATA
    rep movsb
    call sync
    mov esi, asm_ok
    jmp puts
parse_integer:
    xor eax, eax
    mov ebx, 10
    xor ebp, ebp
    cmp byte [esi], '-'
    jne .hex
    mov ebp, 1
    inc esi
.hex:
    cmp word [esi], 0x7830
    jne .start
    mov ebx, 16
    add esi, 2
.start:
    xor ecx, ecx
.digit:
    movzx edx, byte [esi]
    test edx, edx
    jz .done
    sub edx, '0'
    cmp edx, 9
    jbe .value
    sub edx, 'a'-'0'-10
    cmp edx, 10
    jb .bad
    cmp edx, 15
    ja .bad
.value:
    cmp edx, ebx
    jae .bad
    push edx
    mul ebx
    test edx, edx
    pop edx
    jnz .bad
    add eax, edx
    jc .bad
    inc ecx
    inc esi
    jmp .digit
.done:
    test ecx, ecx
    jz .bad
    test ebp, ebp
    jz .ok
    neg eax
.ok:
    clc
    ret
.bad:
    stc
    ret
cmd_run:
    cmp byte [mt_active], 0
    jne .busy
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call findfile
    jc missing
    cmp dword [edi+RKIND], 3
    jne .bad
    cmp dword [edi+RDATA], 'AX05'
    jne .bad
    mov ecx, [edi+RDATA+4]
    cmp ecx, 4000-8
    ja .bad
    lea eax, [ecx+8]
    cmp eax, [edi+RLEN]
    jne .bad
    lea esi, [edi+RDATA+8]
    call validate_code
    jc .bad
    mov eax, [edi+56]
    and eax, 1
    mov [process_cap], eax
    call process_run
    jc .nomem
    push eax
    mov esi, asm_result
    call puts
    pop eax
    call number
    jmp nl
.nomem:
    mov esi, run_nomem
    jmp puts
.busy:
    mov esi, run_background_busy
    jmp puts
.bad:
    mov esi, asm_bad_binary
    jmp puts
asm_output_arg dd 0
asm_source dd 0
asm_source_end dd 0
asm_slot dd 0
asm_line dd 0
program_entry dd 0
asm_opcode db 0
asm_text times 128 db 0
asm_bits db 'bits32',0
asm_ret db 'ret',0
asm_inc db 'inceax',0
asm_dec db 'deceax',0
asm_nop db 'nop',0
asm_int80 db 'int0x80',0
asm_xor db 'xoreax,eax',0
asm_ok db 'Ensamblado AX05 listo.',10,0
asm_error db 'Error de ensamblado en linea ',0
asm_result db 'Programa termino. EAX=',0
asm_bad_binary db 'Binario no valido o instrucciones no admitidas.',10,0
run_nomem db 'No hay una pagina libre para el programa.',10,0
run_background_busy db 'Espera los procesos de fondo con waitbg antes de run.',10,0
