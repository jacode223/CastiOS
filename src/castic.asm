; Castic i386 0.1. Compile print statements into validated AX05 machine code.
; The compiler is kernel-resident; resulting programs execute in CPL3.
cmd_castic:
    call filename
    jc badname
    mov [castic_output_arg], esi
    call findfile
    jc missing
    call require_text
    jc badname
    mov eax, [edi+RLEN]
    test eax, eax
    jz .syntax
    cmp eax, LIMIT
    ja toolong
    lea esi, [edi+RDATA]
    mov [castic_input], esi
    add eax, esi
    mov [castic_end], eax
    mov esi, [castic_output_arg]
    cmp byte [esi], 0
    je .usage
    push dword [args]
    mov [args], esi
    call filename
    pop dword [args]
    jc .usage
    cmp byte [esi], 0
    jne .usage
    call findfile
    jnc .exists
    call getslot
    jc full
    mov [castic_slot], edi
    mov edi, ASMBUF+8
    mov esi, [castic_input]
    mov dword [castic_statements], 0
    mov dword [castic_defined], 0
    mov byte [castic_returned], 0
    mov byte [castic_in_function], 0
    mov dword [castic_functions], 0
    mov dword [castic_depth], 0
    mov byte [castic_library_active], 0
    mov byte [castic_library_used], 0
.next:
    cmp esi, [castic_end]
    jb .not_end
    cmp byte [castic_in_function], 0
    jne .end_function
    cmp dword [castic_depth], 0
    jne .syntax
    cmp byte [castic_library_active], 0
    je .finish
    mov byte [castic_library_active], 0
    mov esi, [castic_library_return]
    mov eax, [castic_library_end]
    mov [castic_end], eax
    jmp .next
.end_function:
    mov byte [castic_in_function], 0
    mov esi, [castic_call_return]
    mov eax, [castic_outer_end]
    mov [castic_end], eax
    jmp .next
.not_end:
    mov al, [esi]
    cmp al, ' '
    je .skip
    cmp al, 9
    je .skip
    cmp al, 10
    je .skip
    cmp al, 13
    je .skip
    cmp al, ';'
    je .skip
    cmp byte [esi], '}'
    je .block_close
    cmp byte [castic_returned], 0
    jne .syntax
    mov eax, [castic_end]
    sub eax, esi
    cmp eax, 3
    jb .syntax
    cmp byte [esi], 'a'
    jb .function_check
    cmp byte [esi], 'z'
    ja .function_check
    cmp byte [esi+1], '('
    jne .function_check
    cmp byte [esi+2], ')'
    je .function_call
.function_check:
    cmp eax, 4
    jb .syntax
    cmp word [esi], 'fn'
    jne .function_checked
    cmp byte [esi+2], ' '
    je .function_define
.function_checked:
    cmp eax, 5
    jb .check_postfix
    mov dl, [esi]
    cmp dl, 'a'
    jb .check_postfix
    cmp dl, 'z'
    ja .check_postfix
    cmp byte [esi+1], ' '
    jne .check_postfix
    cmp byte [esi+2], '='
    jne .check_postfix
    cmp byte [esi+3], ' '
    je .plain_assign
.check_postfix:
    mov byte [castic_postfix], 0
    cmp eax, 3
    jb .postfix_done
    mov dl, [esi]
    cmp dl, 'a'
    jb .postfix_done
    cmp dl, 'z'
    ja .postfix_done
    cmp word [esi+1], '++'
    je .postfix_inc
    cmp word [esi+1], '--'
    je .postfix_dec
    jmp .postfix_done
.postfix_inc:
    mov byte [castic_operation], 1
    jmp .postfix_start
.postfix_dec:
    mov byte [castic_operation], 2
.postfix_start:
    mov byte [castic_postfix], 1
    jmp .unit_variable
.postfix_done:
    mov byte [castic_c_decl], 0
    mov byte [castic_assignment], 0
    cmp eax, 5
    jb .command_name
    mov dl, [esi]
    cmp dl, 'a'
    jb .command_name
    cmp dl, 'z'
    ja .command_name
    cmp byte [esi+1], ' '
    jne .command_name
    cmp byte [esi+3], '='
    jne .command_name
    cmp byte [esi+4], ' '
    jne .syntax
    mov dl, [esi+2]
    mov byte [castic_operation], 1
    cmp dl, '+'
    je .assignment
    mov byte [castic_operation], 2
    cmp dl, '-'
    je .assignment
    mov byte [castic_operation], 4
    cmp dl, '*'
    je .assignment
    mov byte [castic_operation], 5
    cmp dl, '/'
    jne .syntax
.assignment:
    mov byte [castic_assignment], 1
    jmp .variable
.command_name:
    cmp word [esi], 'if'
    je .if_start
    cmp dword [esi], 'whil'
    je .while_start
    cmp dword [esi], 'use '
    je .use_library
    cmp dword [esi], 'inc '
    je .increment
    cmp dword [esi], 'dec '
    je .decrement
    cmp dword [esi], 'int '
    je .c_decl
    cmp dword [esi], 'sysc'
    je .syscall_c
    cmp dword [esi], 'let '
    je .let
    cmp dword [esi], 'add '
    je .add
    cmp dword [esi], 'sub '
    je .sub
    cmp dword [esi], 'mul '
    je .mul
    cmp dword [esi], 'div '
    je .div
    cmp eax, 7
    jb .check_print
    cmp dword [esi], 'retu'
    jne .check_print
    cmp word [esi+4], 'rn'
    jne .check_print
    cmp byte [esi+6], ' '
    jne .syntax
    add esi, 7
    mov byte [castic_operation], 3
    jmp .variable
.check_print:
    cmp eax, 6
    jb .syntax
    cmp dword [esi], 'prin'
    jne .syntax
    cmp byte [esi+4], 't'
    jne .syntax
    cmp byte [esi+5], ' '
    jne .syntax
    add esi, 6
.trim:
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ' '
    jne .text
    inc esi
    jmp .trim
.text:
    mov ebx, castic_text
    xor ecx, ecx
.copy:
    cmp esi, [castic_end]
    jae .text_end
    mov al, [esi]
    cmp al, ';'
    je .text_end
    cmp al, 10
    je .text_end
    cmp al, 13
    je .text_end
    cmp al, 32
    jb .syntax
    cmp al, 126
    ja .syntax
    cmp ecx, 128
    jae .syntax
    mov [ebx+ecx], al
    inc ecx
    inc esi
    jmp .copy
.text_end:
    test ecx, ecx
    jz .syntax
    mov byte [ebx+ecx], 10
    inc ecx
    mov [castic_length], ecx
    ; Clear trailing bytes of the final dword.
    mov dword [ebx+ecx], 0
    ; Capacity: twelve bytes per four characters, plus syscall and ret.
    lea eax, [ecx+3]
    shr eax, 2
    imul eax, 12
    add eax, 20
    add eax, edi
    cmp eax, ASMBUF+4000
    ja .too_big
    push esi
    xor edx, edx
.emit_data:
    cmp edx, [castic_length]
    jae .emit_write
    mov al, 0xb8              ; mov eax, destination in demand memory
    stosb
    lea eax, [edx+0x20008000]
    stosd
    mov al, 0xbb              ; mov ebx, four bytes
    stosb
    mov eax, [castic_text+edx]
    stosd
    mov ax, 0x1889            ; mov [eax], ebx
    stosw
    add edx, 4
    jmp .emit_data
.emit_write:
    mov al, 0xb8
    stosb
    mov eax, 5                ; console_write
    stosd
    mov al, 0xbb
    stosb
    mov eax, 0x20008000
    stosd
    mov al, 0xb9
    stosb
    mov eax, [castic_length]
    stosd
    mov ax, 0x80cd
    stosw
    pop esi
    inc dword [castic_statements]
    jmp .next
.function_define:
    cmp dword [castic_depth], 0
    jne .syntax
    cmp byte [castic_in_function], 0
    jne .syntax
    add esi, 3
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    movzx ecx, byte [esi]
    sub ecx, 'a'
    cmp ecx, 25
    ja .syntax
    bt dword [castic_functions], ecx
    jc .syntax
    bts dword [castic_functions], ecx
    inc esi
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '{'
    jne .syntax
    inc esi
    mov [castic_func_start+ecx*4], esi
.scan_function:
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '{'
    je .syntax
    cmp byte [esi], '}'
    je .function_end
    inc esi
    jmp .scan_function
.function_end:
    mov [castic_func_end+ecx*4], esi
    inc esi
    jmp .next
.function_call:
    cmp byte [castic_in_function], 0
    jne .syntax            ; bounded inlining, no recursion/nesting
    movzx ecx, byte [esi]
    sub ecx, 'a'
    bt dword [castic_functions], ecx
    jnc .syntax
    add esi, 3
    call .end_statement
    jc .syntax
    mov [castic_call_return], esi
    mov eax, [castic_end]
    mov [castic_outer_end], eax
    mov eax, [castic_func_end+ecx*4]
    mov [castic_end], eax
    mov esi, [castic_func_start+ecx*4]
    mov byte [castic_in_function], 1
    jmp .next
.if_start:
    add esi, 2
    mov byte [castic_block_type], 0
    jmp .block_start
.while_start:
    cmp byte [esi+4], 'e'
    jne .syntax
    add esi, 5
    mov byte [castic_block_type], 1
.block_start:
    cmp byte [castic_in_function], 0
    jne .syntax
    mov ecx, [castic_depth]
    cmp ecx, 8
    jae .syntax
    mov [castic_block_begin+ecx*4], edi
    mov al, [castic_block_type]
    mov [castic_block_types+ecx], al
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '('
    jne .syntax
    inc esi
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    movzx ecx, byte [esi]
    sub ecx, 'a'
    cmp ecx, 25
    ja .syntax
    bt dword [castic_defined], ecx
    jnc .syntax
    lea eax, [ecx*4+0x20008100]
    mov [castic_address], eax
    inc esi
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    mov al, [esi]
    inc esi
    mov dl, 0
    cmp al, '='
    je .eq_op
    cmp al, '!'
    je .ne_op
    cmp al, '<'
    je .lt_op
    cmp al, '>'
    je .gt_op
    jmp .syntax
.eq_op:
    mov dl, 0x85 ; jne
    jmp .requires_eq
.ne_op:
    mov dl, 0x84 ; je
.requires_eq:
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '='
    jne .syntax
    inc esi
    jmp .op_done
.lt_op:
    mov dl, 0x83 ; jae
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '='
    jne .op_done
    inc esi
    mov dl, 0x87 ; ja
    jmp .op_done
.gt_op:
    mov dl, 0x86 ; jbe
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '='
    jne .op_done
    inc esi
    mov dl, 0x82 ; jb
.op_done:
    mov [castic_branch_op], dl
    call .sys_number
    jc .syntax
    mov [castic_value], eax
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ')'
    jne .syntax
    inc esi
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], '{'
    jne .syntax
    inc esi
    lea eax, [edi+18]
    cmp eax, ASMBUF+3990
    ja .too_big
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x008b
    stosw
    mov al, 0x3d
    stosb
    mov eax, [castic_value]
    stosd
    mov al, 0x0f
    stosb
    mov al, [castic_branch_op]
    stosb
    mov ecx, [castic_depth]
    mov [castic_block_patch+ecx*4], edi
    xor eax, eax
    stosd
    inc dword [castic_depth]
    jmp .next
.block_close:
    cmp dword [castic_depth], 0
    je .syntax
    inc esi
    dec dword [castic_depth]
    mov ecx, [castic_depth]
    cmp byte [castic_block_types+ecx], 0
    je .patch_block
    lea eax, [edi+5]
    cmp eax, ASMBUF+3990
    ja .too_big
    mov al, 0xe9
    stosb
    mov eax, [castic_block_begin+ecx*4]
    sub eax, edi
    sub eax, 4
    stosd
.patch_block:
    mov edx, [castic_block_patch+ecx*4]
    mov eax, edi
    sub eax, edx
    sub eax, 4
    mov [edx], eax
    jmp .next
.syscall_c:
    ; syscall(number,ebx,ecx,edx,result_var) with decimal immediates.
    mov eax, [castic_end]
    sub eax, esi
    cmp eax, 9
    jb .syntax
    cmp dword [esi+4], 'all('
    jne .syntax
    add esi, 8
    mov dword [castic_sys_vars], 0
    mov ebp, castic_sys_args
    mov ecx, 4
.sys_parse_loop:
    push ecx
    call .sys_spaces
    movzx eax, byte [esi]
    sub eax, 'a'
    cmp eax, 25
    ja .sys_immediate
    bt dword [castic_defined], eax
    jnc .sys_undefined
    lea eax, [eax*4+0x20008100]
    inc esi
    mov edx, ebp
    sub edx, castic_sys_args
    shr edx, 2
    bts [castic_sys_vars], edx
    clc
    jmp .sys_parsed
.sys_undefined:
    stc
    jmp .sys_parsed
.sys_immediate:
    call .sys_argument
.sys_parsed:
    pop ecx
    jc .syntax
    mov [ebp], eax
    add ebp, 4
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ','
    jne .syntax
    inc esi
    loop .sys_parse_loop
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    movzx eax, byte [esi]
    sub eax, 'a'
    cmp eax, 25
    ja .syntax
    cmp dword [castic_depth], 0
    je .sys_define
    bt dword [castic_defined], eax
    jnc .syntax
.sys_define:
    bts dword [castic_defined], eax
    lea eax, [eax*4+0x20008100]
    mov [castic_address], eax
    inc esi
    call .sys_spaces
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ')'
    jne .syntax
    inc esi
    call .end_statement
    jc .syntax
    lea eax, [edi+70]
    cmp eax, ASMBUF+4000
    ja .too_big
    ; Allocate data page before syscall and preserve result via EBX.
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x008b
    stosw
    mov edx, 1
    mov cl, 0xbb
    call .emit_argument
    mov edx, 2
    mov cl, 0xb9
    call .emit_argument
    mov edx, 3
    mov cl, 0xba
    call .emit_argument
    xor edx, edx
    mov cl, 0xb8
    call .emit_argument
    mov ax, 0x80cd
    stosw
    mov ax, 0xc389
    stosw
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x1889
    stosw
    inc dword [castic_statements]
    jmp .next
.emit_argument:
    bt [castic_sys_vars], edx
    jc .emit_variable
    mov al, cl
    stosb
    mov eax, [castic_sys_args+edx*4]
    stosd
    ret
.emit_variable:
    mov al, 0xb8
    stosb
    mov eax, [castic_sys_args+edx*4]
    stosd
    mov ax, 0x008b
    stosw
    cmp cl, 0xb8
    je .emit_done
    mov al, 0x89
    stosb
    mov al, cl
    sub al, 0xb8
    add al, 0xc0
    stosb
.emit_done:
    ret
.sys_spaces:
    cmp esi, [castic_end]
    jae .sys_spaces_done
    cmp byte [esi], ' '
    jne .sys_spaces_done
    inc esi
    jmp .sys_spaces
.sys_spaces_done:
    ret
.sys_argument:
    call .sys_spaces
    cmp esi, [castic_end]
    jae .sys_bad
    cmp byte [esi], 39
    jne .sys_number
    ; Pack 1..4 printable characters directly into a register immediate.
    inc esi
    xor ebx, ebx
    xor ecx, ecx
.literal:
    cmp esi, [castic_end]
    jae .sys_bad
    movzx edx, byte [esi]
    inc esi
    cmp dl, 39
    je .literal_end
    cmp cl, 32
    je .sys_bad
    cmp dl, 32
    jb .sys_bad
    cmp dl, 126
    ja .sys_bad
    shl edx, cl
    or ebx, edx
    add cl, 8
    jmp .literal
.literal_end:
    test ecx, ecx
    jz .sys_bad
    mov eax, ebx
    clc
    ret
.sys_number:
    call .sys_spaces
    xor eax, eax
    xor ebx, ebx
.sys_digit:
    cmp esi, [castic_end]
    jae .sys_number_done
    movzx edx, byte [esi]
    cmp edx, '0'
    jb .sys_number_done
    cmp edx, '9'
    ja .sys_number_done
    sub edx, '0'
    cmp eax, 429496729
    ja .sys_bad
    imul eax, eax, 10
    add eax, edx
    jc .sys_bad
    inc ebx
    inc esi
    jmp .sys_digit
.sys_number_done:
    test ebx, ebx
    jz .sys_bad
    clc
    ret
.sys_bad:
    stc
    ret
.use_library:
    cmp byte [castic_in_function], 0
    jne .syntax
    cmp byte [castic_library_active], 0
    jne .syntax
    cmp dword [castic_depth], 0
    jne .syntax
    add esi, 4
    mov eax, [castic_end]
    sub eax, esi
    cmp eax, 4
    jb .syntax
    mov ebx, castic_math_path
    cmp dword [esi], 'math'
    je .lib_name
    mov ebx, castic_util_path
    cmp dword [esi], 'util'
    je .lib_name
    mov ebx, castic_desk_path
    cmp dword [esi], 'desk'
    jne .syntax
.lib_name:
    add esi, 4
    call .end_statement
    jc .syntax
    mov [castic_library_return], esi
    mov eax, [castic_end]
    mov [castic_library_end], eax
    push edi
    mov esi, ebx
    call resolve_path
    jc .lib_error
    call findfile
    jc .lib_error
    call require_text
    jc .lib_error
    mov eax, [edi+RLEN]
    test eax, eax
    jz .lib_error
    cmp eax, LIMIT
    ja .lib_error
    lea esi, [edi+RDATA]
    add eax, esi
    mov [castic_end], eax
    pop edi
    mov byte [castic_library_active], 1
    jmp .next
.lib_error:
    pop edi
    jmp .syntax
.plain_assign:
    movzx ecx, byte [esi]
    sub ecx, 'a'
    bt dword [castic_defined], ecx
    jnc .syntax
    lea eax, [ecx*4+0x20008100]
    mov [castic_address], eax
    mov byte [castic_operation], 0
    add esi, 3
    jmp .spaces_number
.increment:
    mov byte [castic_operation], 1
    jmp .unit_operation
.decrement:
    mov byte [castic_operation], 2
.unit_operation:
    add esi, 4
.unit_variable:
    cmp esi, [castic_end]
    jae .syntax
    movzx ecx, byte [esi]
    sub ecx, 'a'
    cmp ecx, 25
    ja .syntax
    bt dword [castic_defined], ecx
    jnc .syntax
    lea eax, [ecx*4+0x20008100]
    mov [castic_address], eax
    inc esi
    mov dword [castic_value], 1
    cmp byte [castic_postfix], 0
    je .nonzero_checked
    add esi, 2
    jmp .nonzero_checked
.c_decl:
    mov byte [castic_c_decl], 1
    mov byte [castic_operation], 0
    jmp .arithmetic
.let:
    mov byte [castic_operation], 0
    jmp .arithmetic
.add:
    mov byte [castic_operation], 1
    jmp .arithmetic
.sub:
    mov byte [castic_operation], 2
    jmp .arithmetic
.mul:
    mov byte [castic_operation], 4
    jmp .arithmetic
.div:
    mov byte [castic_operation], 5
.arithmetic:
    add esi, 4
.variable:
    cmp esi, [castic_end]
    jae .syntax
    movzx ecx, byte [esi]
    sub ecx, 'a'
    cmp ecx, 25
    ja .syntax
    inc esi
    mov [castic_var], ecx
    cmp byte [castic_operation], 0
    je .define
    bt dword [castic_defined], ecx
    jnc .syntax
    jmp .known
.define:
    cmp dword [castic_depth], 0
    jne .syntax
    bts dword [castic_defined], ecx
.known:
    lea eax, [ecx*4+0x20008100]
    mov [castic_address], eax
    cmp byte [castic_operation], 3
    je .return_value
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ' '
    jne .syntax
    cmp byte [castic_assignment], 0
    je .no_assignment
    add esi, 3
.no_assignment:
    cmp byte [castic_c_decl], 1
    jne .spaces_number
.c_equals_space:
    inc esi
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ' '
    je .c_equals_space
    cmp byte [esi], '='
    jne .syntax
    inc esi
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ' '
    jne .syntax
.spaces_number:
    inc esi
    cmp esi, [castic_end]
    jae .syntax
    cmp byte [esi], ' '
    je .spaces_number
    xor eax, eax
    xor ebx, ebx
.number:
    cmp esi, [castic_end]
    jae .number_done
    movzx edx, byte [esi]
    cmp dl, '0'
    jb .number_done
    cmp dl, '9'
    ja .number_done
    sub edx, '0'
    cmp eax, 429496729
    ja .syntax
    imul eax, eax, 10
    add eax, edx
    jc .syntax
    inc ebx
    inc esi
    jmp .number
.number_done:
    test ebx, ebx
    jz .syntax
    mov [castic_value], eax
    cmp byte [castic_operation], 5
    jne .nonzero_checked
    test eax, eax
    jz .syntax
.nonzero_checked:
    call .end_statement
    jc .syntax
    lea eax, [edi+40]
    cmp eax, ASMBUF+4000
    ja .too_big
    cmp byte [castic_operation], 0
    je .store_immediate
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x008b
    stosw
    cmp byte [castic_operation], 4
    je .multiply
    cmp byte [castic_operation], 5
    je .divide
    mov al, 0x05
    cmp byte [castic_operation], 1
    je .operation_opcode
    mov al, 0x2d
.operation_opcode:
    stosb
    mov eax, [castic_value]
    stosd
    jmp .arithmetic_result
.multiply:
    mov ax, 0xc069          ; imul eax,eax,imm32 (low 32 bits)
    stosw
    mov eax, [castic_value]
    stosd
    jmp .arithmetic_result
.divide:
    mov al, 0xbb            ; mov ebx,divisor
    stosb
    mov eax, [castic_value]
    stosd
    mov al, 0xba            ; mov edx,0
    stosb
    xor eax, eax
    stosd
    mov ax, 0xf3f7          ; div ebx
    stosw
.arithmetic_result:
    mov ax, 0xc389          ; mov ebx,eax
    stosw
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x1889
    stosw
    jmp .arithmetic_done
.store_immediate:
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov al, 0xbb
    stosb
    mov eax, [castic_value]
    stosd
    mov ax, 0x1889
    stosw
.arithmetic_done:
    inc dword [castic_statements]
    jmp .next
.return_value:
    cmp dword [castic_depth], 0
    jne .syntax
    cmp byte [castic_in_function], 0
    jne .syntax
    call .end_statement
    jc .syntax
    lea eax, [edi+10]
    cmp eax, ASMBUF+4000
    ja .too_big
    mov al, 0xb8
    stosb
    mov eax, [castic_address]
    stosd
    mov ax, 0x008b
    stosw
    mov byte [castic_returned], 1
    inc dword [castic_statements]
    jmp .next
.end_statement:
    cmp esi, [castic_end]
    jae .end_ok
    cmp byte [esi], ' '
    je .end_advance
    cmp byte [esi], 9
    je .end_advance
    cmp byte [esi], 10
    je .end_ok
    cmp byte [esi], 13
    je .end_ok
    cmp byte [esi], ';'
    je .end_ok
    stc
    ret
.end_advance:
    inc esi
    jmp .end_statement
.end_ok:
    clc
    ret
.skip:
    inc esi
    jmp .next
.finish:
    cmp dword [castic_statements], 0
    je .syntax
    cmp byte [castic_returned], 1
    je .emit_ret
    mov ax, 0xc031           ; xor eax,eax; ret
    stosw
.emit_ret:
    mov al, 0xc3
    stosb
    mov eax, edi
    sub eax, ASMBUF+8
    mov dword [ASMBUF], 'AX05'
    mov [ASMBUF+4], eax
    mov ecx, eax
    mov esi, ASMBUF+8
    call validate_code
    jc .syntax
    push dword [args]
    mov eax, [castic_output_arg]
    mov [args], eax
    call filename
    pop dword [args]
    jc .syntax
    mov edi, [castic_slot]
    call init_slot
    mov dword [edi+RKIND], 3
    mov ecx, [ASMBUF+4]
    add ecx, 8
    mov [edi+RLEN], ecx
    add edi, RDATA
    mov esi, ASMBUF
    rep movsb
    call sync
    mov esi, castic_ok
    jmp puts
.usage:
    mov esi, castic_usage
    jmp puts
.exists:
    mov esi, castic_exists
    jmp puts
.syntax:
    mov esi, castic_syntax
    jmp puts
.too_big:
    mov esi, castic_big
    jmp puts
castic_postfix db 0
castic_library_active db 0
castic_library_used db 0
castic_library_return dd 0
castic_library_end dd 0
castic_math_path db '/lib/math.cas',0
castic_util_path db '/lib/util.cas',0
castic_desk_path db '/lib/desk.cas',0
castic_depth dd 0
castic_block_type db 0
castic_branch_op db 0
castic_block_types times 8 db 0
castic_block_begin times 8 dd 0
castic_block_patch times 8 dd 0
castic_functions dd 0
castic_func_start times 26 dd 0
castic_func_end times 26 dd 0
castic_outer_end dd 0
castic_call_return dd 0
castic_in_function db 0
castic_sys_vars dd 0
castic_sys_args times 4 dd 0
castic_c_decl db 0
castic_assignment db 0
castic_defined dd 0
castic_var dd 0
castic_value dd 0
castic_address dd 0
castic_operation db 0
castic_returned db 0
castic_output_arg dd 0
castic_input dd 0
castic_end dd 0
castic_slot dd 0
castic_length dd 0
castic_statements dd 0
castic_text times 133 db 0

validate_code:
    ; ESI=bytes, ECX=len. Exige un unico RET al final.
    pushad
    mov [val_start], esi
    mov [val_size], ecx
    cmp ecx, 4000
    ja .bad
    push edi
    mov edi, val_boundaries
    xor eax, eax
    push ecx
    mov ecx, 252
    rep stosd
    pop ecx
    pop edi
.instruction:
    test ecx, ecx
    jz .bad
    mov eax, esi
    sub eax, [val_start]
    bts dword [val_boundaries], eax
    lodsb
    dec ecx
    cmp al, 0xc3
    je .ret
    cmp al, 0x40
    je .instruction
    cmp al, 0x48
    je .instruction
    cmp al, 0x49          ; dec ecx
    je .instruction
    cmp al, 0x75          ; jnz -3, bounded instruction window
    je .loop
    cmp al, 0x3d          ; cmp eax, imm32
    je .imm
    cmp al, 0xe9          ; relative jump
    je .branch
    cmp al, 0x0f          ; near conditional jump
    je .condition
    cmp al, 0xcd          ; int 0x80: exit / yield
    je .syscall
    cmp al, 0x90
    je .instruction
    cmp al, 0x31
    je .xor
    cmp al, 0x69
    je .imul
    cmp al, 0xf7
    je .divide
    cmp al, 0x89          ; bounded memory write: mov [eax],ebx
    je .store
    cmp al, 0x8b          ; bounded memory read: mov eax,[eax]
    je .load
    cmp al, 0xb8
    je .imm
    cmp al, 0xb9          ; mov ecx, imm32
    je .imm
    cmp al, 0xbb          ; mov ebx, imm32
    je .imm
    cmp al, 0xba          ; mov edx, imm32
    je .imm
    cmp al, 0x05
    je .imm
    cmp al, 0x2d
    jne .bad
.imm:
    cmp ecx, 4
    jb .bad
    add esi, 4
    sub ecx, 4
    jmp .instruction
.imul:
    cmp ecx, 5
    jb .bad
    cmp byte [esi], 0xc0
    jne .bad
    inc esi
    dec ecx
    jmp .imm
.divide:
    test ecx, ecx
    jz .bad
    cmp byte [esi], 0xf3
    jne .bad
    inc esi
    dec ecx
    jmp .instruction
.xor:
    test ecx, ecx
    jz .bad
    lodsb
    dec ecx
    cmp al, 0xc0
    je .instruction
    jmp .bad
.store:
    test ecx, ecx
    jz .bad
    cmp byte [esi], 0x18
    je .store_allowed
    cmp byte [esi], 0xc1
    je .store_allowed
    cmp byte [esi], 0xc2
    je .store_allowed
    cmp byte [esi], 0xc3     ; mov ebx,eax
    jne .bad
.store_allowed:
    inc esi
    dec ecx
    jmp .instruction
.load:
    test ecx, ecx
    jz .bad
    cmp byte [esi], 0x00
    jne .bad
    inc esi
    dec ecx
    jmp .instruction
.loop:
    test ecx, ecx
    jz .bad
    cmp byte [esi], 0xfd
    jne .bad
    cmp byte [esi-2], 0x49
    jne .bad
    inc esi
    dec ecx
    jmp .instruction
.condition:
    test ecx, ecx
    jz .bad
    lodsb
    dec ecx
    cmp al, 0x82
    jb .bad
    cmp al, 0x87
    ja .bad
.branch:
    cmp ecx, 4
    jb .bad
    mov eax, [esi]
    add esi, 4
    sub ecx, 4
    add eax, esi
    sub eax, [val_start]
    cmp eax, [val_size]
    jae .bad
    bts dword [val_targets], eax
    jmp .instruction
.syscall:
    test ecx, ecx
    jz .bad
    cmp byte [esi], 0x80
    jne .bad
    inc esi
    dec ecx
    jmp .instruction
.ret:
    test ecx, ecx
    jnz .bad
    xor edx, edx
.check_targets:
    mov eax, [val_targets+edx*4]
    mov ebx, [val_boundaries+edx*4]
    not ebx
    test eax, ebx
    jnz .bad
    inc edx
    cmp edx, 126
    jb .check_targets
    popad
    clc
    ret
.bad:
    popad
    stc
    ret
align 4
val_start dd 0
val_size dd 0
val_boundaries equ VALIDATOR_MAPS
val_targets equ VALIDATOR_MAPS+126*4


desk_cas: incbin "examples/castic/desktop.cas"

