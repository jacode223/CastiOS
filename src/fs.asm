; ASFS4: 256 bloques, archivos por extents; validacion compartida en C.
checksum:
    push esi
    push ecx
    push edx
    mov esi, RECORDS
    mov ecx, NFILES*RSIZE
    xor eax, eax
.loop:
    movzx edx, byte [esi]
    add eax, edx
    inc esi
    loop .loop
    pop edx
    pop ecx
    pop esi
    ret
fs_empty:
    pushad
    mov edi, FS
    xor eax, eax
    mov ecx, (512+NFILES*RSIZE)/4
    rep stosd
    mov dword [FS], 'HSF5'
    mov dword [FS+4], 5
    mov dword [FS+8], NFILES
    mov dword [FS+12], RSIZE
    mov dword [fs_cwd], ROOT_ID
    popad
    ret
mount:
    ; Prefer requested disk; if ASFS is absent/corrupt, try all other ATA disks.
    mov eax, [disk_selected]
    mov [mount_first_disk], eax
    call mount_selected
    cmp byte [persistent], 1
    je .print
    xor ebp, ebp
.scan:
    cmp ebp, [mount_first_disk]
    je .next
    cmp dword [disk_caps+ebp*4], 0
    je .next
    mov eax, ebp
    call select_disk
    call mount_selected
    cmp byte [persistent], 1
    je .print
.next:
    inc ebp
    cmp ebp, 4
    jb .scan
    mov eax, [mount_first_disk]
    call select_disk
.print:
    mov esi, fs_mounted
    cmp byte [persistent], 1
    je .done
    ; Only the fresh, temporary root receives the live desktop and guides.
    call fs_seed_docs
    mov esi, fs_ram
.done:
    jmp puts
mount_first_disk dd 0
mount_selected:
    mov byte [primary_valid], 0
    mov dword [fs_io_bias], 0
    call mount_one
    cmp byte [persistent], 1
    jne .mirror
    mov byte [primary_valid], 1
    mov eax, [fs_base]
    mov [primary_base], eax
    mov esi, FS
    mov edi, 0xC00000
    mov ecx, (512+NFILES*RSIZE)/4
    rep movsd
.mirror:
    mov dword [fs_io_bias], 8192
    call mount_one
    cmp byte [persistent], 1
    jne .restore
    cmp byte [primary_valid], 1
    jne .recovered
    mov eax, [FS+20]
    cmp eax, [0xC00000+20]
    jbe .restore
.recovered:
    mov esi, recovered_msg
    call puts
    jmp .done
.restore:
    cmp byte [primary_valid], 1
    jne .done
    mov esi, 0xC00000
    mov edi, FS
    mov ecx, (512+NFILES*RSIZE)/4
    rep movsd
    mov eax, [primary_base]
    mov [fs_base], eax
    mov byte [persistent], 1
.done:
    mov dword [fs_io_bias], 0
    mov esi, fs_mounted
    cmp byte [persistent], 1
    je .print
    mov esi, fs_ram
.print:
    ret
mount_one:
    mov dword [fs_cwd], ROOT_ID
    mov dword [fs_base], 0
    xor eax, eax
    xor ebx, ebx
    mov edi, FS
    call block_sector
    jc .ram
        cmp dword [FS], 'HSF5'
    je .header
    mov dword [fs_base], 32768
    xor eax, eax
    call block_sector
    jc .ram
.header:
        cmp dword [FS], 'HSF5'
    jne .ram
.recognized:
    cmp dword [FS+8], NFILES
    jne .ram
    cmp dword [FS+12], RSIZE
    jne .ram
    mov eax, 1
    mov edi, RECORDS
.read:
    call block_sector
    jc .ram
    inc eax
    add edi, 512
    cmp eax, FS_SECTORS
    jb .read
    push dword FS
    call [0x2000c]
    add esp, 4
    test eax, eax
    jnz .ram
    mov byte [persistent], 1
    ret
.ram:
    call fs_empty
    mov byte [persistent], 0
    ret
sync:
    cmp byte [persistent], 1
    jne sync_bank
    inc dword [FS+20]
    mov dword [fs_io_bias], 8192
    call sync_bank
    mov dword [fs_io_bias], 0
    cmp byte [persistent], 1
    jne .done
    call sync_bank
.done:
    ret
sync_bank:
    cmp byte [persistent], 1
    jne .ram
    ; Commit protocol: data -> FLUSH -> header/checksum -> FLUSH.
    ; The other mirror remains valid until this bank commits.
    call checksum
    mov [FS+16], eax
    mov eax, 1
    mov edi, RECORDS
    mov bl, 1
.write:
    call block_sector
    jc .error
    inc eax
    add edi, 512
    cmp eax, FS_SECTORS
    jb .write
    call disk_flush
    jc .error
    xor eax, eax
    mov edi, FS
    call block_sector
    jc .error
    call disk_flush
    jc .error
    mov esi, saved
    jmp puts
.ram:
    mov esi, ramsaved
    jmp puts
.error:
    mov byte [persistent], 0
    mov esi, ioerror
    jmp puts

; Extrae primer argumento y resuelve ruta. ESI queda tras el argumento.
filename:
    mov esi, [args]
    call spaces
    mov edi, pathbuf
    xor ecx, ecx
.copy:
    lodsb
    test al, al
    jz .end
    cmp al, ' '
    je .space
    cmp ecx, 127
    jae .bad
    stosb
    inc ecx
    jmp .copy
.end:
    dec esi
    jmp .resolve
.space:
    call spaces
.resolve:
    test ecx, ecx
    jz .bad
    mov byte [edi], 0
    push esi
    mov esi, pathbuf
    call resolve_path
    pop esi
    ret
.bad:
    stc
    ret
resolve_path:
    mov eax, [fs_cwd]
    cmp byte [esi], '/'
    jne .start
    mov eax, ROOT_ID
.start:
    mov [target_parent], eax
.skip:
    cmp byte [esi], '/'
    jne .component
    inc esi
    jmp .skip
.component:
    cmp byte [esi], 0
    je .special
    mov edi, namebuf
    xor ecx, ecx
.name:
    lodsb
    test al, al
    jz .finish
    cmp al, '/'
    je .finish
    cmp ecx, 31
    jae .bad
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    jbe .valid
.upper:
    cmp al, 'A'
    jb .num
    cmp al, 'Z'
    jbe .valid
.num:
    cmp al, '0'
    jb .other
    cmp al, '9'
    jbe .valid
.other:
    cmp al, '.'
    je .valid
    cmp al, '_'
    je .valid
    cmp al, '-'
    jne .bad
.valid:
    stosb
    inc ecx
    jmp .name
.finish:
    dec esi
    mov byte [edi], 0
    cmp word [namebuf], 0x002e
    je .dot
    cmp word [namebuf], 0x2e2e
    jne .normal
    cmp byte [namebuf+2], 0
    je .dotdot
.normal:
    call find_named
    jc .notfound
    mov eax, edi
    sub eax, RECORDS
    shr eax, 13
    mov [path_id], eax
    cmp byte [esi], 0
    je .ok
    ; Si solo queda '/', esta ruta debe ser una carpeta.
    cmp dword [edi+RKIND], 2
    jne .bad
    mov [target_parent], eax
    inc esi
    jmp .skip
.notfound:
    cmp byte [esi], 0
    jne .bad
    mov dword [path_id], 0xfffffffe
.ok:
    clc
    ret
.dotdot:
    mov eax, [target_parent]
    cmp eax, ROOT_ID
    je .dot
    shl eax, 13
    mov eax, [RECORDS+eax+RPARENT]
    mov [target_parent], eax
.dot:
    cmp byte [esi], 0
    je .special
    inc esi
    jmp .skip
.special:
    mov byte [namebuf], 0
    mov eax, [target_parent]
    mov [path_id], eax
    clc
    ret
.bad:
    stc
    ret
find_named:
    push esi
    push ecx
    mov esi, namebuf
    mov edi, RECORDS
    mov ecx, NFILES
.loop:
    mov eax, [target_parent]
    cmp [edi+RPARENT], eax
    jne .next
    cmp byte [edi], 0
    je .next
    call equal
    je .found
.next:
    add edi, RSIZE
    loop .loop
    stc
    jmp .done
.found:
    clc
.done:
    pop ecx
    pop esi
    ret
findfile:
    mov eax, [path_id]
    cmp eax, NFILES
    jae .bad
    shl eax, 13
    lea edi, [RECORDS+eax]
    clc
    ret
.bad:
    stc
    ret
getslot:
    call findfile
    jnc .done
    cmp dword [path_id], 0xfffffffe
    jne .bad
    mov edi, RECORDS
    mov ecx, NFILES
.loop:
    cmp byte [edi], 0
    je .found
    add edi, RSIZE
    loop .loop
.bad:
    stc
    ret
.found:
    clc
.done:
    ret
; Crea metadatos para un archivo nuevo. No modifica un archivo existente.
init_slot:
    cmp byte [edi], 0
    jne .done
    pushad
    mov ebx, edi
    mov ecx, RSIZE/4
    xor eax, eax
    rep stosd
    mov edi, ebx
    mov esi, namebuf
    call copy
    mov eax, [target_parent]
    mov [ebx+RPARENT], eax
    mov dword [ebx+RKIND], 1
    popad
.done:
    ret
require_text:
    cmp dword [edi+RKIND], 1
    jne .bad
    clc
    ret
.bad:
    stc
    ret
badname:
    mov esi, fs_badname
    jmp puts
missing:
    mov esi, missingmsg
    jmp puts
full:
    mov esi, fs_full
    jmp puts
toolong:
    mov esi, fs_long
    jmp puts
cmd_ls:
    mov eax, [fs_cwd]
    mov [ls_parent], eax
    mov esi, [args]
    call spaces
    cmp byte [esi], 0
    je .list
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    mov eax, [path_id]
    cmp eax, ROOT_ID
    je .target
    call findfile
    jc missing
    cmp dword [edi+RKIND], 2
    jne .file
    mov eax, [path_id]
    jmp .target
.file:
    mov esi, edi
    call puts
    mov al, ' '
    call putc
    mov eax, [edi+RLEN]
    call number
    jmp nl
.target:
    mov [ls_parent], eax
.list:
    mov edi, RECORDS
    mov ecx, NFILES
.loop:
    cmp byte [edi], 0
    je .next
    cmp dword [edi+RKIND], 4
    je .next
    mov eax, [ls_parent]
    cmp [edi+RPARENT], eax
    jne .next
    mov esi, edi
    call puts
    mov al, ' '
    cmp dword [edi+RKIND], 2
    jne .space
    mov al, '/'
.space:
    call putc
    mov eax, [edi+RLEN]
    call number
    call nl
.next:
    add edi, RSIZE
    loop .loop
    ret
ls_parent dd ROOT_ID
cmd_cd:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    mov eax, [path_id]
    cmp eax, ROOT_ID
    je .set
    call findfile
    jc missing
    cmp dword [edi+RKIND], 2
    jne badname
    mov eax, [path_id]
.set:
    mov [fs_cwd], eax
    ret
cmd_pwd:
    mov eax, [fs_cwd]
    call print_path
    jmp nl
print_path:
    pushad
    cmp eax, ROOT_ID
    jne .parent
    mov al, '/'
    call putc
    jmp .done
.parent:
    shl eax, 13
    lea edi, [RECORDS+eax]
    mov eax, [edi+RPARENT]
    call print_path
    mov esi, edi
    call puts
    mov al, '/'
    call putc
.done:
    popad
    ret
cmd_mkdir:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    cmp dword [path_id], 0xfffffffe
    jne badname
    call getslot
    jc full
    call init_slot
    mov dword [edi+RKIND], 2
    jmp sync
cmd_touch:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call getslot
    jc full
    call init_slot
    call require_text
    jc badname
    jmp sync
cmd_cat:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call findfile
    jc missing
    cmp dword [edi+RKIND], 5
    je cat_big
    call require_text
    jc badname
    mov edx, [edi+RLEN]
.chunk:
    lea esi, [edi+RDATA]
    mov ecx, edx
    cmp ecx, LIMIT
    jbe .bytes
    mov ecx, LIMIT
.bytes:
    sub edx, ecx
.print:
    jecxz .next
    lodsb
    call putc
    loop .print
.next:
    test edx, edx
    jz .done
    mov eax, [edi+44]
    dec eax
    shl eax, 13
    lea edi, [RECORDS+eax]
    jmp .chunk
.done:
    jmp nl
cat_big:
    cmp byte [persistent], 1
    jne missing
    mov eax, [edi+48]
    add eax, [fs_base]
    jc .error
    mov [big_lba], eax
    mov eax, [edi+RLEN]
    mov [big_left], eax
.sector:
    mov eax, [big_lba]
    mov edi, 0x3f000
    xor ebx, ebx
    call ata
    jc .error
    mov ecx, [big_left]
    cmp ecx, 512
    jbe .print
    mov ecx, 512
.print:
    mov esi, 0x3f000
    sub [big_left], ecx
.byte:
    jecxz .next
    lodsb
    call putc
    dec ecx
    jmp .byte
.next:
    inc dword [big_lba]
    cmp dword [big_left], 0
    jne .sector
    jmp nl
.error:
    mov esi, ioerror
    jmp puts
big_lba dd 0
big_left dd 0
cmd_head:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call findfile
    jc missing
    call require_text
    jc badname
    lea esi, [edi+RDATA]
    mov ecx, 5
.loop:
    lodsb
    test al, al
    jz .done
    call putc
    cmp al, 10
    jne .loop
    loop .loop
.done:
    jmp nl
cmd_write:
    call filename
    jc badname
    mov [textptr], esi
    call getslot
    jc full
    call init_slot
    call require_text
    jc badname
    call free_extra
    mov [slot], edi
    mov esi, [textptr]
    call length
    mov [edi+RLEN], eax
    add edi, RDATA
    call copy
    jmp sync
cmd_append:
    call filename
    jc badname
    mov [textptr], esi
    call findfile
    jc missing
    call require_text
    jc badname
    call length
    mov ecx, [edi+RLEN]
    mov edx, ecx
    test ecx, ecx
    jz .size
    inc edx
.size:
    add edx, eax
    cmp edx, LIMIT
    ja toolong
    mov [edi+RLEN], edx
    lea edi, [edi+RDATA+ecx]
    test ecx, ecx
    jz .copy
    mov byte [edi], 10
    inc edi
.copy:
    call copy
    jmp sync
cmd_rm:
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    call findfile
    jc missing
    mov eax, [path_id]
    cmp eax, [fs_cwd]
    je badname
    cmp dword [edi+RKIND], 2
    jne .remove
    mov ebx, RECORDS
    mov ecx, NFILES
.children:
    cmp byte [ebx], 0
    je .next
    cmp [ebx+RPARENT], eax
    je badname
.next:
    add ebx, RSIZE
    loop .children
.remove:
    call free_extra
    mov ecx, RSIZE/4
    xor eax, eax
    rep stosd
    jmp sync
; The privileged shell grants an AX05 binary permission to call file_write.
; Format: chmod FILE.app +w|-w. This is a capability, not Unix uid/gid.
cmd_chmod:
    cmp byte [persistent], 1
    jne .ro
    call filename
    jc badname
    push esi
    call findfile
    jc .missing
    pop esi
    cmp dword [edi+RKIND], 3
    jne badname
    cmp dword [edi+RDATA], 'AX05'
    jne badname
    cmp byte [esi], 0
    je .show
    cmp byte [esi+2], 0
    jne badname
    cmp byte [esi], '+'
    je .grant
    cmp byte [esi], '-'
    jne badname
    cmp byte [esi+1], 'w'
    jne badname
    and dword [edi+56], ~1
    jmp sync
.grant:
    cmp byte [esi+1], 'w'
    jne badname
    or dword [edi+56], 1
    jmp sync
.show:
    mov esi, chmod_readonly
    test dword [edi+56], 1
    jz .print
    mov esi, chmod_readwrite
.print:
    jmp puts
.missing:
    pop esi
    jmp missing
.ro:
    mov esi, chmod_ro
    jmp puts
chmod_ro db 'chmod requiere HSFS persistente.',10,0
chmod_readonly db 'AX05: lectura; escritura denegada.',10,0
chmod_readwrite db 'AX05: lectura y escritura de texto simple.',10,0
; mv on HSFS: rename/move a regular file without copying its payload.
cmd_mv:
    call filename
    jc badname
    cmp byte [esi], 0
    je badname
    call findfile
    jc missing
    cmp dword [edi+RKIND], 2
    je badname
    mov [mv_record], edi
    mov [args], esi
    call filename
    jc badname
    cmp byte [esi], 0
    jne badname
    cmp dword [path_id], 0xfffffffe
    jne badname
    mov edi, [mv_record]
    mov eax, [target_parent]
    mov [edi+RPARENT], eax
    mov esi, namebuf
    mov ecx, 32
.name:
    lodsb
    stosb
    test al, al
    jz .done
    loop .name
.done:
    jmp sync
mv_record dd 0
; Release continuation records before replacing/removing a head. Metadata and
; payload in the head stay intact until its caller publishes the new contents.
free_extra:
    pushad
    mov eax, [edi+44]
    mov dword [edi+44], 0
.next:
    test eax, eax
    jz .done
    dec eax
    shl eax, 13
    lea edi, [RECORDS+eax]
    mov ebx, [edi+44]
    mov ecx, RSIZE/4
    xor eax, eax
    rep stosd
    mov eax, ebx
    jmp .next
.done:
    popad
    ret
cmd_edit equ cmd_nano
fs_cwd dd ROOT_ID
target_parent dd ROOT_ID
path_id dd ROOT_ID
pathbuf times 128 db 0
fs_mounted db 'HSFS v5: disco persistente, 480 bloques + archivos grandes hasta 100 MiB.',10,0
fs_ram db 'HSFS sin disco: RMFS disponible en /ram; datos temporales.',10,0
fs_badname db 'Ruta o tipo invalido; comprueba carpetas y argumentos.',10,0
fs_full db 'HSFS lleno: 480 bloques compartidos por archivos, carpetas y extents.',10,0
fs_long db 'Esta herramienta admite hasta 8000 bytes; usa NASM para archivos grandes. Sin cambios.',10,0

primary_valid db 0
primary_base dd 0
recovered_msg db "ASFS: copia recuperada.",10,0

%include "src/installed_docs.asm"
