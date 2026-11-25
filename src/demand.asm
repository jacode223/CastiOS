; Four bounded, zeroed AX05 user data pages at 0x20008000..0x2000bfff.
; Page fault entry has return address, CPU error code, EIP, CS, EFLAGS.
%define DEMAND_BASE USER_BASE+0x8000
%define DEMAND_PAGES 4
demand_fault:
    pushad
    test dword [esp+36], 1       ; only not-present user faults
    jnz .bad
    test dword [esp+36], 4
    jz .bad
    mov edx, cr2
    mov eax, edx
    sub eax, DEMAND_BASE
    cmp eax, DEMAND_PAGES*4096
    jae .bad
    shr eax, 12
    mov ebx, eax
    cmp byte [mt_active], 0
    je .single
    mov eax, [mt_current]
    cmp eax, [mt_count]
    jae .bad
    imul eax, MT_SIZE
    mov edi, [mt_table+eax+MT_PT]
    jmp .pt
.single:
    mov edi, [process_pt]
.pt:
    test edi, edi
    jz .bad
    lea edi, [edi+ebx*4+32]
    cmp dword [edi], 0
    jne .bad
    call alloc_page
    test eax, eax
    jz .bad
    or eax, 7
    mov [edi], eax
    invlpg [edx]
    popad
    clc
    ret
.bad:
    popad
    stc
    ret
; ESI=user address in the demand window. EAX=1 if mapped, else 0.
demand_present:
    push ebx
    push edi
    xor eax, eax
    cmp byte [mt_active], 0
    je .single
    mov ebx, [mt_current]
    cmp ebx, [mt_count]
    jae .done
    imul ebx, MT_SIZE
    mov edi, [mt_table+ebx+MT_PT]
    jmp .check
.single:
    mov edi, [process_pt]
.check:
    test edi, edi
    jz .done
    mov ebx, esi
    sub ebx, USER_BASE
    shr ebx, 12
    mov eax, [edi+ebx*4]
    and eax, 1
.done:
    pop edi
    pop ebx
    ret
; EDI=private user page table; clear and release its demand pages.
demand_release_pt:
    pushad
    mov esi, 8
.next:
    mov eax, [edi+esi*4]
    and eax, 0xfffff000
    test eax, eax
    jz .skip
    mov dword [edi+esi*4], 0
    call free_page
.skip:
    inc esi
    cmp esi, 8+DEMAND_PAGES
    jb .next
    popad
    ret
