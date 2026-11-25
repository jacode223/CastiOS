; E820-derived 4 KiB physical frame allocator, bounded to identity mapped GiB.
; Does not allocate below 16 MiB (kernel, GRUB and firmware live below it).
mem_init:
    mov dword [mmap_cur], 0
    mov dword [mmap_end], 0
    mov qword [region_frame], 0
    mov qword [region_end], 0
    mov eax, [boot_info]
    test eax, eax
    jz .done
    test dword [rax], 1<<6
    jz .done
    mov edx, [rax+48]
    mov ecx, [rax+44]
    test ecx, ecx
    jz .done
    cmp edx, 0x40000000
    jae .done
    cmp ecx, 0x40000000
    jae .done
    cmp edx, 0x40000000
    jae .done
    mov r8d, edx
    add r8, rcx
    cmp r8, 0x40000000
    ja .done
    mov [mmap_cur], edx
    mov [mmap_end], r8d
.done:
    ret

; RAX = zeroed physical page or zero. Non-reclaiming in this early preview.
frame_alloc:
    mov rax, [region_frame]
    cmp rax, [region_end]
    jb .got
.next:
    mov r8d, [mmap_cur]
    mov r9d, [mmap_end]
    cmp r8, r9
    jae .none
    cmp r9, r8
    jb .none
    sub r9, r8
    cmp r9, 4
    jb .none
    mov ecx, [r8]
    cmp ecx, 20
    jb .none
    lea rdx, [r8+rcx+4]
    mov r9d, [mmap_end]
    cmp rdx, r9
    ja .none
    mov [mmap_cur], edx
    cmp dword [r8+20], 1
    jne .next
    mov rax, [r8+4]
    mov rcx, [r8+12]
    add rcx, rax
    jc .next
    cmp rax, 0x1000000
    jae .low_ok
    mov rax, 0x1000000
.low_ok:
    cmp rcx, 0x40000000
    jbe .high_ok
    mov rcx, 0x40000000
.high_ok:
    add rax, 4095
    and rax, -4096
    and rcx, -4096
    cmp rax, rcx
    jae .next
    mov [region_frame], rax
    mov [region_end], rcx
.got:
    mov rax, [region_frame]
    add qword [region_frame], 4096
    inc dword [frame_count]
    push rdi
    push rcx
    mov rdi, rax
    mov ecx, 512
    push rax
    xor eax, eax
    rep stosq
    pop rax
    pop rcx
    pop rdi
    ret
.none:
    xor eax, eax
    ret

set_gate:
    mov word [rsi], di
    mov word [rsi+2], 8
    mov byte [rsi+4], 0
    mov [rsi+5], dl
    mov rax, rdi
    shr rax, 16
    mov word [rsi+6], ax
    shr rax, 16
    mov dword [rsi+8], eax
    mov dword [rsi+12], 0
    ret

mmap_cur: dd 0
mmap_end: dd 0
region_frame: dq 0
region_end: dq 0
frame_count: dd 0
